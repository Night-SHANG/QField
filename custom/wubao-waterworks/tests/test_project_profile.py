from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


PROFILE_PATH = (
    Path(__file__).resolve().parents[1]
    / "tools"
    / "project_profile.py"
)
spec = importlib.util.spec_from_file_location("project_profile", PROFILE_PATH)
profile = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(profile)


class ProjectProfileTests(unittest.TestCase):
    def test_all_form_fields_exist_in_alias_or_technical_schema(self) -> None:
        for table, fields in profile.FORM_FIELDS.items():
            aliases = profile.ALIASES.get(table, {})
            for field_name in fields:
                self.assertIn(
                    field_name,
                    aliases,
                    f"{table}.{field_name} needs a human-readable alias",
                )

    def test_relation_ids_are_unique(self) -> None:
        ids = [relation[0] for relation in profile.RELATIONS]
        self.assertEqual(len(ids), len(set(ids)))

    def test_form_relations_exist(self) -> None:
        known = {relation[0] for relation in profile.RELATIONS}
        for table, relation_ids in profile.FORM_RELATIONS.items():
            self.assertIn(table, profile.LAYERS)
            self.assertTrue(set(relation_ids).issubset(known))

    def test_value_maps_do_not_duplicate_stored_values(self) -> None:
        for key, mapping in profile.VALUE_MAPS.items():
            values = [next(iter(item.values())) for item in mapping]
            self.assertEqual(
                len(values),
                len(set(values)),
                f"duplicate stored value in {key}",
            )


    def test_every_asset_type_has_a_map_symbol(self) -> None:
        stored_types = {
            next(iter(item.values()))
            for item in profile.VALUE_MAPS[("assets_point", "asset_type")]
        }
        self.assertEqual(stored_types, set(profile.ASSET_SYMBOLS))

    def test_every_asset_status_has_a_stroke_color(self) -> None:
        stored_statuses = {
            next(iter(item.values()))
            for item in profile.VALUE_MAPS[("assets_point", "status")]
        }
        self.assertEqual(stored_statuses, set(profile.STATUS_STROKE_COLORS))

    def test_map_labels_use_custom_name_first(self) -> None:
        self.assertIn('"name"', profile.ASSET_LABEL_EXPRESSION)
        self.assertIn('"code"', profile.ASSET_LABEL_EXPRESSION)

    def test_attachment_widgets_use_relative_storage(self) -> None:
        self.assertEqual(
            set(profile.ATTACHMENT_CONFIGS),
            {"photo_path", "video_path", "audio_path", "document_path"},
        )
        for config in profile.ATTACHMENT_CONFIGS.values():
            self.assertEqual(config["RelativeStorage"], 1)

    def test_attachment_viewers_cover_native_capture_modes(self) -> None:
        viewers = {
            field: config["DocumentViewer"]
            for field, config in profile.ATTACHMENT_CONFIGS.items()
        }
        self.assertEqual(
            viewers,
            {
                "photo_path": 1,
                "video_path": 4,
                "audio_path": 3,
                "document_path": 0,
            },
        )


if __name__ == "__main__":
    unittest.main()
