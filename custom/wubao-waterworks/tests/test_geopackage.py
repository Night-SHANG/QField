from __future__ import annotations

import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path


GENERATOR = (
    Path(__file__).resolve().parents[1]
    / "tools"
    / "create_geopackage.py"
)

spec = importlib.util.spec_from_file_location("create_geopackage", GENERATOR)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class GeoPackageSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.path = Path(self.tempdir.name) / "wubao-waterworks.gpkg"
        module.create_geopackage(self.path)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def test_integrity_and_header(self) -> None:
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            self.assertEqual(db.execute("PRAGMA application_id").fetchone()[0], module.APPLICATION_ID)
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], module.USER_VERSION)

    def test_required_business_tables_exist(self) -> None:
        expected = {
            "assets_point",
            "pipelines",
            "inspections",
            "attachments",
            "repairs",
        }
        with sqlite3.connect(self.path) as db:
            tables = {
                row[0]
                for row in db.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
        self.assertTrue(expected.issubset(tables))

    def test_geometries_use_cgcs2000(self) -> None:
        with sqlite3.connect(self.path) as db:
            rows = db.execute(
                """
                SELECT table_name, geometry_type_name, srs_id
                FROM gpkg_geometry_columns
                ORDER BY table_name
                """
            ).fetchall()

        self.assertEqual(
            rows,
            [
                ("assets_point", "POINT", 4490),
                ("pipelines", "LINESTRING", 4490),
            ],
        )

    def test_business_ids_are_generated(self) -> None:
        with sqlite3.connect(self.path) as db:
            db.execute(
                "INSERT INTO assets_point(name, asset_type) VALUES (?, ?)",
                ("测试阀门井", "valve_well"),
            )
            first = db.execute(
                "SELECT id FROM assets_point WHERE name='测试阀门井'"
            ).fetchone()[0]

            db.execute(
                "INSERT INTO assets_point(name, asset_type) VALUES (?, ?)",
                ("测试阀门井2", "valve_well"),
            )
            second = db.execute(
                "SELECT id FROM assets_point WHERE name='测试阀门井2'"
            ).fetchone()[0]

        self.assertEqual(len(first), 36)
        self.assertNotEqual(first, second)

    def test_attachment_requires_one_parent_and_one_media(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "22222222-2222-2222-2222-222222222222"
            inspection_id = "33333333-3333-3333-3333-333333333333"

            db.execute(
                """
                INSERT INTO attachments(asset_id, photo_path)
                VALUES (?, 'attachments/a.jpg')
                """,
                (asset_id,),
            )

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    """
                    INSERT INTO attachments(
                        asset_id, inspection_id, photo_path
                    ) VALUES (?, ?, 'attachments/invalid-parent.jpg')
                    """,
                    (asset_id, inspection_id),
                )

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    """
                    INSERT INTO attachments(asset_id)
                    VALUES (?)
                    """,
                    (asset_id,),
                )

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    """
                    INSERT INTO attachments(
                        asset_id, photo_path, video_path
                    ) VALUES (?, 'attachments/a.jpg', 'attachments/a.mp4')
                    """,
                    (asset_id,),
                )

    def test_attachment_media_type_must_match_populated_field(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    """
                    INSERT INTO attachments(
                        asset_id, media_type, video_path
                    ) VALUES (?, 'photo', 'attachments/a.mp4')
                    """,
                    (asset_id,),
                )

            db.execute(
                """
                INSERT INTO attachments(
                    asset_id, media_type, video_path
                ) VALUES (?, 'video', 'attachments/a.mp4')
                """,
                (asset_id,),
            )

    def test_attachment_media_type_defaults_to_photo(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
            db.execute(
                """
                INSERT INTO attachments(asset_id, photo_path)
                VALUES (?, 'attachments/default.jpg')
                """,
                (asset_id,),
            )
            media_type = db.execute(
                """
                SELECT media_type
                FROM attachments
                WHERE photo_path='attachments/default.jpg'
                """
            ).fetchone()[0]

        self.assertEqual(media_type, "photo")

    def test_attachment_media_columns_cover_qfield_capture_modes(self) -> None:
        with sqlite3.connect(self.path) as db:
            columns = {
                row[1]
                for row in db.execute("PRAGMA table_info(attachments)")
            }

        self.assertTrue(
            {
                "photo_path",
                "video_path",
                "audio_path",
                "document_path",
            }.issubset(columns)
        )

    def test_invalid_domain_values_are_rejected(self) -> None:
        with sqlite3.connect(self.path) as db:
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    "INSERT INTO assets_point(name, asset_type) VALUES (?, ?)",
                    ("非法类型", "unknown_type"),
                )

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    "INSERT INTO pipelines(name, status) VALUES (?, ?)",
                    ("非法状态", "unknown_status"),
                )

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    """
                    INSERT INTO inspections(asset_id, result)
                    VALUES ('asset-x', 'unknown_result')
                    """
                )

    def test_latest_inspection_time_is_maintained(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "44444444-4444-4444-4444-444444444444"
            db.execute(
                "INSERT INTO assets_point(id, name) VALUES (?, ?)",
                (asset_id, "巡检时间测试"),
            )
            db.execute(
                """
                INSERT INTO inspections(id, asset_id, inspected_at)
                VALUES (?, ?, ?)
                """,
                (
                    "55555555-5555-5555-5555-555555555555",
                    asset_id,
                    "2026-09-20 08:00:00",
                ),
            )
            db.execute(
                """
                INSERT INTO inspections(id, asset_id, inspected_at)
                VALUES (?, ?, ?)
                """,
                (
                    "66666666-6666-6666-6666-666666666666",
                    asset_id,
                    "2026-09-22 10:00:00",
                ),
            )

            latest = db.execute(
                "SELECT last_inspection_at FROM assets_point WHERE id=?",
                (asset_id,),
            ).fetchone()[0]
            self.assertEqual(latest, "2026-09-22 10:00:00")

            db.execute(
                "DELETE FROM inspections WHERE id=?",
                ("66666666-6666-6666-6666-666666666666",),
            )
            latest = db.execute(
                "SELECT last_inspection_at FROM assets_point WHERE id=?",
                (asset_id,),
            ).fetchone()[0]
            self.assertEqual(latest, "2026-09-20 08:00:00")

    def test_asset_status_follows_inspection_and_repair_lifecycle(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "cccccccc-cccc-cccc-cccc-cccccccccccc"
            db.execute(
                "INSERT INTO assets_point(id, name) VALUES (?, ?)",
                (asset_id, "状态联动测试"),
            )

            db.execute(
                """
                INSERT INTO inspections(asset_id, result)
                VALUES (?, 'repair')
                """,
                (asset_id,),
            )
            self.assertEqual(
                db.execute(
                    "SELECT status FROM assets_point WHERE id=?",
                    (asset_id,),
                ).fetchone()[0],
                "repair",
            )

            repair_id = "dddddddd-dddd-dddd-dddd-dddddddddddd"
            db.execute(
                """
                INSERT INTO repairs(id, asset_id, result)
                VALUES (?, ?, 'unresolved')
                """,
                (repair_id, asset_id),
            )
            self.assertEqual(
                db.execute(
                    "SELECT status FROM assets_point WHERE id=?",
                    (asset_id,),
                ).fetchone()[0],
                "repair",
            )

            db.execute(
                "UPDATE repairs SET result='resolved' WHERE id=?",
                (repair_id,),
            )
            self.assertEqual(
                db.execute(
                    "SELECT status FROM assets_point WHERE id=?",
                    (asset_id,),
                ).fetchone()[0],
                "attention",
            )

            db.execute(
                """
                INSERT INTO inspections(asset_id, result)
                VALUES (?, 'normal')
                """,
                (asset_id,),
            )
            self.assertEqual(
                db.execute(
                    "SELECT status FROM assets_point WHERE id=?",
                    (asset_id,),
                ).fetchone()[0],
                "normal",
            )

    def test_attention_inspection_does_not_downgrade_repair_status(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
            db.execute(
                """
                INSERT INTO assets_point(id, name, status)
                VALUES (?, ?, 'repair')
                """,
                (asset_id, "不降级测试"),
            )
            db.execute(
                """
                INSERT INTO inspections(asset_id, result)
                VALUES (?, 'attention')
                """,
                (asset_id,),
            )
            status = db.execute(
                "SELECT status FROM assets_point WHERE id=?",
                (asset_id,),
            ).fetchone()[0]

        self.assertEqual(status, "repair")

    def test_repair_result_domain_and_completion_time(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "77777777-7777-7777-7777-777777777777"
            db.execute(
                "INSERT INTO assets_point(id, name) VALUES (?, ?)",
                (asset_id, "维修测试点"),
            )

            with self.assertRaises(sqlite3.IntegrityError):
                db.execute(
                    """
                    INSERT INTO repairs(asset_id, result)
                    VALUES (?, 'invalid')
                    """,
                    (asset_id,),
                )

            repair_id = "88888888-8888-8888-8888-888888888888"
            db.execute(
                """
                INSERT INTO repairs(id, asset_id, result)
                VALUES (?, ?, 'resolved')
                """,
                (repair_id, asset_id),
            )
            repaired_at = db.execute(
                "SELECT repaired_at FROM repairs WHERE id=?",
                (repair_id,),
            ).fetchone()[0]

        self.assertIsNotNone(repaired_at)

    def test_repair_defaults_to_unresolved(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "99999999-9999-9999-9999-999999999999"
            db.execute(
                "INSERT INTO assets_point(id, name) VALUES (?, ?)",
                (asset_id, "维修默认值测试"),
            )
            db.execute(
                "INSERT INTO repairs(asset_id) VALUES (?)",
                (asset_id,),
            )
            result = db.execute(
                "SELECT result FROM repairs ORDER BY fid DESC LIMIT 1"
            ).fetchone()[0]

        self.assertEqual(result, "unresolved")

    def test_history_tables_are_not_delete_cascaded(self) -> None:
        with sqlite3.connect(self.path) as db:
            asset_id = "11111111-1111-1111-1111-111111111111"
            db.execute(
                "INSERT INTO assets_point(id, name) VALUES (?, ?)",
                (asset_id, "历史保留测试"),
            )
            db.execute(
                "INSERT INTO inspections(asset_id, result) VALUES (?, ?)",
                (asset_id, "normal"),
            )
            db.execute("DELETE FROM assets_point WHERE id=?", (asset_id,))
            history_count = db.execute(
                "SELECT count(*) FROM inspections WHERE asset_id=?",
                (asset_id,),
            ).fetchone()[0]

        self.assertEqual(history_count, 1)


if __name__ == "__main__":
    unittest.main()
