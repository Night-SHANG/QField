#!/usr/bin/env python3
"""Create the base GeoPackage used by the Wubao waterworks project.

This generator intentionally uses only Python's sqlite3 module so it can run in
CI without a QGIS/GDAL installation. QGIS/QField-specific forms, relations and
styling are applied by a separate project profile.
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

APPLICATION_ID = 1196437808  # 0x47504B47 = GPKG
USER_VERSION = 10300  # GeoPackage 1.3.0
SCHEMA_VERSION = "2"

UUID_SQL = """(
  lower(hex(randomblob(4))) || '-' ||
  lower(hex(randomblob(2))) || '-' ||
  lower(hex(randomblob(2))) || '-' ||
  lower(hex(randomblob(2))) || '-' ||
  lower(hex(randomblob(6)))
)"""

SCHEMA_SQL = f"""
PRAGMA application_id = {APPLICATION_ID};
PRAGMA user_version = {USER_VERSION};
PRAGMA foreign_keys = ON;

CREATE TABLE gpkg_spatial_ref_sys (
  srs_name TEXT NOT NULL,
  srs_id INTEGER NOT NULL PRIMARY KEY,
  organization TEXT NOT NULL,
  organization_coordsys_id INTEGER NOT NULL,
  definition TEXT NOT NULL,
  description TEXT
);

INSERT INTO gpkg_spatial_ref_sys VALUES
('Undefined Cartesian SRS',-1,'NONE',-1,'undefined','undefined Cartesian coordinate reference system'),
('Undefined Geographic SRS',0,'NONE',0,'undefined','undefined geographic coordinate reference system'),
('WGS 84 geodetic',4326,'EPSG',4326,
 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AXIS["Latitude",NORTH],AXIS["Longitude",EAST],AUTHORITY["EPSG","4326"]]',
 'WGS 84 longitude/latitude'),
('China Geodetic Coordinate System 2000',4490,'EPSG',4490,
 'GEOGCS["China Geodetic Coordinate System 2000",DATUM["China_2000",SPHEROID["CGCS2000",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AXIS["Latitude",NORTH],AXIS["Longitude",EAST],AUTHORITY["EPSG","4490"]]',
 'CGCS2000 geographic 2D');

CREATE TABLE gpkg_contents (
  table_name TEXT NOT NULL PRIMARY KEY,
  data_type TEXT NOT NULL,
  identifier TEXT UNIQUE,
  description TEXT DEFAULT '',
  last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  min_x DOUBLE,
  min_y DOUBLE,
  max_x DOUBLE,
  max_y DOUBLE,
  srs_id INTEGER,
  CONSTRAINT fk_gc_r_srs_id
    FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
);

CREATE TABLE gpkg_geometry_columns (
  table_name TEXT NOT NULL,
  column_name TEXT NOT NULL,
  geometry_type_name TEXT NOT NULL,
  srs_id INTEGER NOT NULL,
  z TINYINT NOT NULL,
  m TINYINT NOT NULL,
  CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
  CONSTRAINT uk_gc_table_name UNIQUE (table_name),
  CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
  CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
);

CREATE TABLE app_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO app_metadata VALUES
('schema_version','{SCHEMA_VERSION}'),
('project_name','吴堡供水巡检'),
('area','陕西省榆林市吴堡县'),
('master_crs','EPSG:4490');

CREATE TABLE assets_point (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  geom BLOB,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  code TEXT,
  name TEXT,
  asset_type TEXT NOT NULL DEFAULT 'other',
  status TEXT NOT NULL DEFAULT 'normal',
  pipeline_id TEXT,
  area_name TEXT,
  address_hint TEXT,
  install_date DATE,
  last_inspection_at DATETIME,
  note TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pipelines (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  geom BLOB,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  code TEXT,
  name TEXT,
  pipe_type TEXT,
  material TEXT,
  diameter_mm REAL,
  pressure_zone TEXT,
  status TEXT NOT NULL DEFAULT 'normal',
  install_date DATE,
  note TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inspections (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  asset_id TEXT NOT NULL,
  inspected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  inspector TEXT,
  result TEXT NOT NULL DEFAULT 'normal',
  pressure_value REAL,
  issue TEXT,
  action_taken TEXT,
  note TEXT,
  position_accuracy_m REAL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE attachments (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  owner_type TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  media_type TEXT NOT NULL,
  file_path TEXT NOT NULL,
  caption TEXT,
  captured_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE repairs (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  asset_id TEXT NOT NULL,
  inspection_id TEXT,
  reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  repaired_at DATETIME,
  repair_type TEXT,
  description TEXT,
  result TEXT,
  operator TEXT,
  note TEXT
);

INSERT INTO gpkg_contents(table_name,data_type,identifier,description,srs_id)
VALUES
('assets_point','features','供水设施','阀门井、阀门、压力表、消防栓等点状供水设施',4490),
('pipelines','features','供水管线','供水主管、支管等线状设施',4490),
('inspections','attributes','巡检记录','设施巡检历史',NULL),
('attachments','attributes','附件','照片、视频、音频和文档附件索引',NULL),
('repairs','attributes','维修记录','设施维修历史',NULL);

INSERT INTO gpkg_geometry_columns VALUES
('assets_point','geom','POINT',4490,0,0),
('pipelines','geom','LINESTRING',4490,0,0);

CREATE INDEX idx_assets_point_id ON assets_point(id);
CREATE INDEX idx_assets_point_code ON assets_point(code);
CREATE INDEX idx_assets_point_name ON assets_point(name);
CREATE INDEX idx_assets_point_type ON assets_point(asset_type);
CREATE INDEX idx_assets_point_status ON assets_point(status);
CREATE INDEX idx_assets_point_pipeline ON assets_point(pipeline_id);
CREATE INDEX idx_pipelines_id ON pipelines(id);
CREATE INDEX idx_pipelines_code ON pipelines(code);
CREATE INDEX idx_inspections_asset ON inspections(asset_id);
CREATE INDEX idx_inspections_time ON inspections(inspected_at);
CREATE INDEX idx_attachments_asset ON attachments(asset_id);
CREATE INDEX idx_attachments_inspection ON attachments(inspection_id);
CREATE INDEX idx_attachments_repair ON attachments(repair_id);
CREATE INDEX idx_repairs_asset ON repairs(asset_id);
CREATE INDEX idx_repairs_inspection ON repairs(inspection_id);

CREATE TRIGGER trg_assets_updated_at
AFTER UPDATE ON assets_point
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE assets_point SET updated_at=CURRENT_TIMESTAMP WHERE fid=OLD.fid;
END;

CREATE TRIGGER trg_pipelines_updated_at
AFTER UPDATE ON pipelines
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE pipelines SET updated_at=CURRENT_TIMESTAMP WHERE fid=OLD.fid;
END;
"""


def create_geopackage(output: Path, *, force: bool = False) -> Path:
    output = output.resolve()
    if output.exists():
        if not force:
            raise FileExistsError(f"{output} already exists; pass --force to replace it")
        output.unlink()

    output.parent.mkdir(parents=True, exist_ok=True)

    connection = sqlite3.connect(output)
    try:
        connection.executescript(SCHEMA_SQL)
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"GeoPackage integrity check failed: {integrity}")
        connection.commit()
    except Exception:
        connection.close()
        output.unlink(missing_ok=True)
        raise
    else:
        connection.close()

    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Create the Wubao waterworks GeoPackage")
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("wubao-waterworks.gpkg"),
        help="output GeoPackage path",
    )
    parser.add_argument("--force", action="store_true", help="replace an existing file")
    args = parser.parse_args()

    created = create_geopackage(args.output, force=args.force)
    print(created)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
