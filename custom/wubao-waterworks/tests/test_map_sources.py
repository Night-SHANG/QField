from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SOURCE_PATH = Path(__file__).resolve().parents[1] / "tools" / "map_sources.py"
spec = importlib.util.spec_from_file_location("map_sources", SOURCE_PATH)
map_sources = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(map_sources)


class MapSourceTests(unittest.TestCase):
    def test_token_is_substituted_without_touching_xyz_placeholders(self) -> None:
        url = map_sources.with_token(map_sources.IMAGERY_XYZ, "abc123")
        self.assertIn("/abc123/TileServer/tile/{z}/{y}/{x}", url)

    def test_empty_or_url_breaking_tokens_are_rejected(self) -> None:
        for token in ("", "a/b", "a?b", "a&b", "a#b"):
            with self.subTest(token=token):
                with self.assertRaises(ValueError):
                    map_sources.with_token(map_sources.IMAGERY_XYZ, token)

    def test_vector_style_source_is_tokenized_separately(self) -> None:
        url = map_sources.with_token(
            map_sources.VECTOR_STYLE_URL,
            "abc123",
        )
        self.assertIn("/abc123/VectorTileServer/styles/default.json", url)
        self.assertNotIn("{z}", url)
        self.assertNotIn("{x}", url)
        self.assertNotIn("{y}", url)

    def test_official_sources_remain_cgcs2000_profile(self) -> None:
        self.assertEqual(map_sources.SHAANXI_CRS, "EPSG:4490")
        self.assertEqual(map_sources.MAX_ZOOM, 18)


if __name__ == "__main__":
    unittest.main()
