from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1] / "tools"

profile_spec = importlib.util.spec_from_file_location(
    "project_profile",
    TOOLS / "project_profile.py",
)
project_profile = importlib.util.module_from_spec(profile_spec)
assert profile_spec.loader is not None
profile_spec.loader.exec_module(project_profile)

# build_project_bundle imports sibling modules by name. Add the tools directory
# to sys.path exactly as it is when the script is executed directly.
import sys
sys.path.insert(0, str(TOOLS))
try:
    bundle_spec = importlib.util.spec_from_file_location(
        "build_project_bundle",
        TOOLS / "build_project_bundle.py",
    )
    build_project_bundle = importlib.util.module_from_spec(bundle_spec)
    assert bundle_spec.loader is not None
    bundle_spec.loader.exec_module(build_project_bundle)
finally:
    sys.path.remove(str(TOOLS))


class ProjectBundleTests(unittest.TestCase):
    def test_copy_offline_basemaps_preserves_supported_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.mbtiles"
            source.write_bytes(b"test")
            target_dir = root / "bundle" / "basemaps"

            copied = build_project_bundle.copy_offline_basemaps(
                [source],
                target_dir,
            )

            self.assertEqual(copied, [target_dir / source.name])
            self.assertEqual(copied[0].read_bytes(), b"test")

    def test_copy_offline_basemaps_rejects_unknown_format(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "map.xyz"
            source.write_bytes(b"test")

            with self.assertRaises(ValueError):
                build_project_bundle.copy_offline_basemaps(
                    [source],
                    root / "bundle" / "basemaps",
                )

    def test_project_directories_cover_all_media_kinds(self) -> None:
        self.assertEqual(
            set(project_profile.PROJECT_DIRECTORIES),
            {
                "attachments/photos",
                "attachments/videos",
                "attachments/audio",
                "attachments/documents",
            },
        )


if __name__ == "__main__":
    unittest.main()
