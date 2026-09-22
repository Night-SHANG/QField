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


    def test_default_view_extent_is_valid(self) -> None:
        xmin, ymin, xmax, ymax = profile.DEFAULT_VIEW_EXTENT
        self.assertLess(xmin, xmax)
        self.assertLess(ymin, ymax)
        self.assertGreater(xmin, 100)
        self.assertLess(xmax, 120)
        self.assertGreater(ymin, 30)
        self.assertLess(ymax, 45)

    def test_layer_groups_cover_all_business_layers_once(self) -> None:
        grouped = [
            layer
            for layers in profile.LAYER_GROUPS.values()
            for layer in layers
        ]
        self.assertEqual(set(grouped), set(profile.LAYERS))
        self.assertEqual(len(grouped), len(set(grouped)))

    def test_repair_results_are_explicit(self) -> None:
        values = {
            next(iter(item.values()))
            for item in profile.VALUE_MAPS[("repairs", "result")]
        }
        self.assertEqual(values, {"resolved", "monitor", "unresolved"})

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

    def test_attachment_media_type_map_matches_capture_fields(self) -> None:
        media_types = {
            next(iter(item.values()))
            for item in profile.VALUE_MAPS[("attachments", "media_type")]
        }
        configured_types = {
            media_type
            for media_type, _label in profile.ATTACHMENT_MEDIA_FIELDS.values()
        }
        self.assertEqual(
            media_types,
            {"photo", "video", "audio", "document"},
        )
        self.assertEqual(media_types, configured_types)

    def test_system_maintained_fields_are_read_only(self) -> None:
        self.assertIn(
            "last_inspection_at",
            profile.READ_ONLY_FIELDS["assets_point"],
        )
        self.assertIn(
            "position_accuracy_m",
            profile.READ_ONLY_FIELDS["inspections"],
        )

    def test_attachment_widgets_use_relative_storage(self) -> None:
        self.assertEqual(
            set(profile.ATTACHMENT_CONFIGS),
            {"photo_path", "video_path", "audio_path", "document_path"},
        )
        for config in profile.ATTACHMENT_CONFIGS.values():
            self.assertEqual(config["RelativeStorage"], 1)

    def test_attachment_naming_uses_structured_project_paths(self) -> None:
        self.assertEqual(
            set(profile.ATTACHMENT_NAMING),
            {"photo_path", "video_path", "audio_path", "document_path"},
        )
        for field, expression in profile.ATTACHMENT_NAMING.items():
            self.assertIn("attachments/", expression)
            self.assertIn("uuid('WithoutBraces')", expression)
            self.assertTrue(field.endswith("_path"))

    def test_offline_basemap_formats_are_explicit(self) -> None:
        self.assertEqual(
            profile.SUPPORTED_OFFLINE_BASEMAP_EXTENSIONS,
            {".mbtiles", ".tif", ".tiff"},
        )

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
