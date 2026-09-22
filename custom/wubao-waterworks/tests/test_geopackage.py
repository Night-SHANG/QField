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
