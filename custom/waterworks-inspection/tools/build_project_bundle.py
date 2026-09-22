#!/usr/bin/env python3
"""Create a ready-to-copy waterworks inspection QField project directory."""

from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path

import configure_qgis_project
import create_geopackage
import project_profile as profile


def copy_offline_basemaps(
    source_paths: list[Path],
    destination: Path,
) -> list[Path]:
    copied = []
    if not source_paths:
        return copied

    destination.mkdir(parents=True, exist_ok=True)

    for source in source_paths:
        source = source.resolve()
        if not source.is_file():
            raise FileNotFoundError(f"Offline basemap not found: {source}")

        suffix = source.suffix.lower()
        if suffix not in profile.SUPPORTED_OFFLINE_BASEMAP_EXTENSIONS:
            raise ValueError(f"Unsupported offline basemap extension: {suffix}")

        target = destination / source.name
        if target.exists():
            raise FileExistsError(f"Duplicate offline basemap file name: {target.name}")
        shutil.copy2(source, target)
        copied.append(target)

    return copied


def build_bundle(
    output_directory: Path,
    *,
    tianditu_token: str | None = None,
    offline_basemaps: list[Path] | None = None,
    force: bool = False,
) -> Path:
    output_directory = output_directory.resolve()

    if output_directory.exists():
        if not force:
            raise FileExistsError(
                f"{output_directory} already exists; pass --force to replace it"
            )
        shutil.rmtree(output_directory)

    output_directory.mkdir(parents=True)

    for relative in profile.PROJECT_DIRECTORIES:
        (output_directory / relative).mkdir(parents=True, exist_ok=True)

    geopackage = output_directory / "waterworks-inspection.gpkg"
    project_file = output_directory / "waterworks-inspection.qgs"

    create_geopackage.create_geopackage(geopackage)

    copied_basemaps = copy_offline_basemaps(
        offline_basemaps or [],
        output_directory / "basemaps",
    )

    configure_qgis_project.build_project(
        geopackage,
        project_file,
        tianditu_token=tianditu_token,
        offline_basemaps=copied_basemaps,
    )

    readme = output_directory / "README.txt"
    readme.write_text(
        "供水巡检项目\n"
        "================\n"
        "主项目: waterworks-inspection.qgs\n"
        "业务数据: waterworks-inspection.gpkg\n"
        "附件目录: attachments/\n"
        "离线底图: basemaps/（如有）\n\n"
        "整个文件夹可作为一个 QField 项目整体复制/备份。\n",
        encoding="utf-8",
    )

    return output_directory


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a ready-to-copy waterworks inspection QField project"
    )
    parser.add_argument("output_directory", type=Path)
    parser.add_argument(
        "--tianditu-token",
        default=os.environ.get("TDT_SHAANXI_TOKEN"),
        help=("approved TianDiTu Shaanxi token; defaults to " "TDT_SHAANXI_TOKEN"),
    )
    parser.add_argument(
        "--offline-basemap",
        action="append",
        default=[],
        type=Path,
        help="MBTiles/GeoTIFF/COG file; may be supplied more than once",
    )
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    print(
        build_bundle(
            args.output_directory,
            tianditu_token=args.tianditu_token,
            offline_basemaps=args.offline_basemap,
            force=args.force,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
