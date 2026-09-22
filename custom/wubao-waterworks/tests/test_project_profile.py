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

    def test_attachment_widget_uses_relative_storage(self) -> None:
        self.assertEqual(profile.ATTACHMENT_CONFIG["RelativeStorage"], 1)


if __name__ == "__main__":
    unittest.main()
