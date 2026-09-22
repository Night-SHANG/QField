#!/usr/bin/env python3
"""Create the base GeoPackage used by the waterworks inspection project.

The file is intentionally generated with Python's sqlite3 module so schema
checks can run in lightweight CI. QGIS/QField-specific forms, relations,
renderers and online basemaps are applied by configure_qgis_project.py.
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

# GeoPackage SQLite application id ("GP10").
APPLICATION_ID = 1196437808
USER_VERSION = 10300
SCHEMA_VERSION = "7"

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
('Undefined Cartesian SRS',-1,'NONE',-1,'undefined',
 'undefined Cartesian coordinate reference system'),
('Undefined Geographic SRS',0,'NONE',0,'undefined',
 'undefined geographic coordinate reference system'),
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
  last_change DATETIME NOT NULL
    DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
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
  CONSTRAINT fk_gc_tn
    FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
  CONSTRAINT fk_gc_srs
    FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
);

CREATE TABLE app_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO app_metadata VALUES
('schema_version','{SCHEMA_VERSION}'),
('project_name','供水巡检'),
('area',''),
('master_crs','EPSG:4490');

CREATE TABLE asset_types (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  symbol_shape TEXT NOT NULL DEFAULT 'circle',
  symbol_color TEXT NOT NULL DEFAULT '#607D8B',
  symbol_size REAL NOT NULL DEFAULT 4.0,
  sort_order INTEGER NOT NULL DEFAULT 100,
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1))
);

INSERT INTO asset_types(
  code, label, symbol_shape, symbol_color, symbol_size, sort_order
) VALUES
('valve_well','阀门井','circle','#1976D2',4.6,10),
('valve','阀门','diamond','#1565C0',4.4,20),
('pressure_gauge','压力表','triangle','#7B1FA2',4.6,30),
('hydrant','消防栓','square','#D32F2F',4.6,40),
('air_valve','排气阀','triangle','#00897B',4.4,50),
('drain_valve','排泥阀','diamond','#6D4C41',4.4,60),
('meter','水表','circle','#3949AB',4.2,70),
('other','其他','circle','#607D8B',4.0,999);

CREATE TABLE assets_point (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  geom BLOB,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  code TEXT,
  name TEXT,
  asset_type TEXT NOT NULL DEFAULT 'other',
  status TEXT NOT NULL DEFAULT 'normal'
    CHECK (status IN ('normal', 'attention', 'repair', 'disabled')),
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
  status TEXT NOT NULL DEFAULT 'normal'
    CHECK (status IN ('normal', 'attention', 'repair', 'disabled')),
  install_date DATE,
  last_inspection_at DATETIME,
  note TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inspections (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  asset_id TEXT,
  pipeline_id TEXT,
  inspected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  inspector TEXT,
  result TEXT NOT NULL DEFAULT 'normal'
    CHECK (result IN ('normal', 'attention', 'repair')),
  pressure_value REAL,
  issue TEXT,
  action_taken TEXT,
  note TEXT,
  position_accuracy_m REAL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_inspection_one_parent CHECK (
    (asset_id IS NOT NULL) +
    (pipeline_id IS NOT NULL) = 1
  )
);

CREATE TABLE repairs (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},
  asset_id TEXT,
  pipeline_id TEXT,
  inspection_id TEXT,
  reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  repaired_at DATETIME,
  repair_type TEXT,
  description TEXT,
  result TEXT NOT NULL DEFAULT 'unresolved'
    CHECK (result IN ('resolved', 'monitor', 'unresolved')),
  operator TEXT,
  note TEXT,
  CONSTRAINT ck_repair_one_parent CHECK (
    (asset_id IS NOT NULL) +
    (pipeline_id IS NOT NULL) = 1
  )
);

CREATE TABLE attachments (
  fid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  id TEXT NOT NULL UNIQUE DEFAULT {UUID_SQL},

  -- Exactly one parent is populated. We deliberately do not use ON DELETE
  -- CASCADE: historical media must survive accidental/administrative changes.
  asset_id TEXT,
  pipeline_id TEXT,
  inspection_id TEXT,
  repair_id TEXT,

  -- One table implements all media. media_type drives conditional form
  -- visibility while dedicated fields expose QField's native capture controls.
  media_type TEXT NOT NULL DEFAULT 'photo'
    CHECK (media_type IN ('photo', 'video', 'audio', 'document')),
  photo_path TEXT,
  video_path TEXT,
  audio_path TEXT,
  document_path TEXT,

  caption TEXT,
  captured_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_attachment_one_parent CHECK (
    (asset_id IS NOT NULL) +
    (pipeline_id IS NOT NULL) +
    (inspection_id IS NOT NULL) +
    (repair_id IS NOT NULL) = 1
  ),
  CONSTRAINT ck_attachment_one_media CHECK (
    (photo_path IS NOT NULL AND trim(photo_path) <> '') +
    (video_path IS NOT NULL AND trim(video_path) <> '') +
    (audio_path IS NOT NULL AND trim(audio_path) <> '') +
    (document_path IS NOT NULL AND trim(document_path) <> '') = 1
  ),
  CONSTRAINT ck_attachment_media_matches_type CHECK (
    (media_type = 'photo' AND photo_path IS NOT NULL AND trim(photo_path) <> '') OR
    (media_type = 'video' AND video_path IS NOT NULL AND trim(video_path) <> '') OR
    (media_type = 'audio' AND audio_path IS NOT NULL AND trim(audio_path) <> '') OR
    (media_type = 'document' AND document_path IS NOT NULL AND trim(document_path) <> '')
  )
);

INSERT INTO gpkg_contents(table_name,data_type,identifier,description,srs_id)
VALUES
('asset_types','attributes','设施类型配置',
 '设施类型、名称与地图符号配置',NULL),
('assets_point','features','供水设施',
 '阀门井、阀门、压力表、消防栓等点状供水设施',4490),
('pipelines','features','供水管线',
 '供水主管、支管等线状设施',4490),
('inspections','attributes','巡检记录','设施巡检历史',NULL),
('repairs','attributes','维修记录','设施维修历史',NULL),
('attachments','attributes','附件',
 '照片、视频、音频和文档附件',NULL);

INSERT INTO gpkg_geometry_columns VALUES
('assets_point','geom','POINT',4490,0,0),
('pipelines','geom','LINESTRING',4490,0,0);

CREATE INDEX idx_asset_types_active_order
ON asset_types(active, sort_order, label);

CREATE INDEX idx_assets_point_id ON assets_point(id);
CREATE INDEX idx_assets_point_code ON assets_point(code);
CREATE INDEX idx_assets_point_name ON assets_point(name);
CREATE INDEX idx_assets_point_type ON assets_point(asset_type);
CREATE INDEX idx_assets_point_status ON assets_point(status);
CREATE INDEX idx_assets_point_pipeline ON assets_point(pipeline_id);

CREATE INDEX idx_pipelines_id ON pipelines(id);
CREATE INDEX idx_pipelines_code ON pipelines(code);
CREATE INDEX idx_pipelines_status ON pipelines(status);

CREATE INDEX idx_inspections_asset ON inspections(asset_id);
CREATE INDEX idx_inspections_pipeline ON inspections(pipeline_id);
CREATE INDEX idx_inspections_time ON inspections(inspected_at);

CREATE INDEX idx_repairs_asset ON repairs(asset_id);
CREATE INDEX idx_repairs_pipeline ON repairs(pipeline_id);
CREATE INDEX idx_repairs_inspection ON repairs(inspection_id);

CREATE INDEX idx_attachments_asset ON attachments(asset_id);
CREATE INDEX idx_attachments_pipeline ON attachments(pipeline_id);
CREATE INDEX idx_attachments_inspection ON attachments(inspection_id);
CREATE INDEX idx_attachments_repair ON attachments(repair_id);

CREATE TRIGGER trg_assets_validate_type_insert
BEFORE INSERT ON assets_point
FOR EACH ROW
WHEN NOT EXISTS (
  SELECT 1 FROM asset_types
  WHERE code = NEW.asset_type AND active = 1
)
BEGIN
  SELECT RAISE(ABORT, 'unknown or inactive asset type');
END;

CREATE TRIGGER trg_assets_validate_type_update
BEFORE UPDATE OF asset_type ON assets_point
FOR EACH ROW
WHEN NOT EXISTS (
  SELECT 1 FROM asset_types
  WHERE code = NEW.asset_type AND active = 1
)
BEGIN
  SELECT RAISE(ABORT, 'unknown or inactive asset type');
END;

CREATE TRIGGER trg_asset_types_protect_delete
BEFORE DELETE ON asset_types
FOR EACH ROW
WHEN EXISTS (
  SELECT 1 FROM assets_point WHERE asset_type = OLD.code
)
BEGIN
  SELECT RAISE(ABORT, 'asset type is in use');
END;

CREATE TRIGGER trg_assets_protect_delete_with_history
BEFORE DELETE ON assets_point
FOR EACH ROW
WHEN EXISTS (
  SELECT 1 FROM inspections WHERE asset_id = OLD.id
) OR EXISTS (
  SELECT 1 FROM repairs WHERE asset_id = OLD.id
) OR EXISTS (
  SELECT 1 FROM attachments WHERE asset_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'asset has history; mark it disabled instead');
END;

CREATE TRIGGER trg_pipelines_protect_delete_with_history
BEFORE DELETE ON pipelines
FOR EACH ROW
WHEN EXISTS (
  SELECT 1 FROM inspections WHERE pipeline_id = OLD.id
) OR EXISTS (
  SELECT 1 FROM repairs WHERE pipeline_id = OLD.id
) OR EXISTS (
  SELECT 1 FROM attachments WHERE pipeline_id = OLD.id
) OR EXISTS (
  SELECT 1 FROM assets_point WHERE pipeline_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'pipeline has linked records; mark it disabled instead');
END;

CREATE TRIGGER trg_inspections_protect_delete_with_history
BEFORE DELETE ON inspections
FOR EACH ROW
WHEN EXISTS (
  SELECT 1 FROM repairs WHERE inspection_id = OLD.id
) OR EXISTS (
  SELECT 1 FROM attachments WHERE inspection_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'inspection has linked history');
END;

CREATE TRIGGER trg_repairs_protect_delete_with_attachments
BEFORE DELETE ON repairs
FOR EACH ROW
WHEN EXISTS (
  SELECT 1 FROM attachments WHERE repair_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'repair has attachments');
END;

CREATE TRIGGER trg_assets_updated_at
AFTER UPDATE ON assets_point
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE assets_point
  SET updated_at = CURRENT_TIMESTAMP
  WHERE fid = OLD.fid;
END;

CREATE TRIGGER trg_pipelines_updated_at
AFTER UPDATE ON pipelines
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE pipelines
  SET updated_at = CURRENT_TIMESTAMP
  WHERE fid = OLD.fid;
END;


CREATE TRIGGER trg_inspection_insert_updates_parent
AFTER INSERT ON inspections
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE asset_id = NEW.asset_id
  )
  WHERE id = NEW.asset_id;

  UPDATE pipelines
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE pipeline_id = NEW.pipeline_id
  )
  WHERE id = NEW.pipeline_id;
END;

CREATE TRIGGER trg_inspection_update_updates_parent
AFTER UPDATE OF asset_id, pipeline_id, inspected_at ON inspections
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE asset_id = OLD.asset_id
  )
  WHERE id = OLD.asset_id;

  UPDATE assets_point
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE asset_id = NEW.asset_id
  )
  WHERE id = NEW.asset_id;

  UPDATE pipelines
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE pipeline_id = OLD.pipeline_id
  )
  WHERE id = OLD.pipeline_id;

  UPDATE pipelines
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE pipeline_id = NEW.pipeline_id
  )
  WHERE id = NEW.pipeline_id;
END;

CREATE TRIGGER trg_inspection_delete_updates_parent
AFTER DELETE ON inspections
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE asset_id = OLD.asset_id
  )
  WHERE id = OLD.asset_id;

  UPDATE pipelines
  SET last_inspection_at = (
    SELECT MAX(inspected_at)
    FROM inspections
    WHERE pipeline_id = OLD.pipeline_id
  )
  WHERE id = OLD.pipeline_id;
END;


CREATE TRIGGER trg_repair_insert_completion_time
AFTER INSERT ON repairs
FOR EACH ROW
WHEN NEW.result = 'resolved' AND NEW.repaired_at IS NULL
BEGIN
  UPDATE repairs
  SET repaired_at = CURRENT_TIMESTAMP
  WHERE fid = NEW.fid;
END;

CREATE TRIGGER trg_repair_update_completion_time
AFTER UPDATE OF result ON repairs
FOR EACH ROW
WHEN NEW.result = 'resolved' AND NEW.repaired_at IS NULL
BEGIN
  UPDATE repairs
  SET repaired_at = CURRENT_TIMESTAMP
  WHERE fid = NEW.fid;
END;


CREATE TRIGGER trg_inspection_insert_updates_parent_status
AFTER INSERT ON inspections
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET status = CASE
    WHEN NEW.result = 'repair' THEN 'repair'
    WHEN NEW.result = 'attention' AND status <> 'repair' THEN 'attention'
    WHEN NEW.result = 'normal'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE asset_id = NEW.asset_id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'normal'
    ELSE status
  END
  WHERE id = NEW.asset_id;

  UPDATE pipelines
  SET status = CASE
    WHEN NEW.result = 'repair' THEN 'repair'
    WHEN NEW.result = 'attention' AND status <> 'repair' THEN 'attention'
    WHEN NEW.result = 'normal'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE pipeline_id = NEW.pipeline_id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'normal'
    ELSE status
  END
  WHERE id = NEW.pipeline_id;
END;

CREATE TRIGGER trg_inspection_update_updates_parent_status
AFTER UPDATE OF result, asset_id, pipeline_id ON inspections
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET status = CASE
    WHEN NEW.result = 'repair' THEN 'repair'
    WHEN NEW.result = 'attention' AND status <> 'repair' THEN 'attention'
    WHEN NEW.result = 'normal'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE asset_id = NEW.asset_id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'normal'
    ELSE status
  END
  WHERE id = NEW.asset_id;

  UPDATE pipelines
  SET status = CASE
    WHEN NEW.result = 'repair' THEN 'repair'
    WHEN NEW.result = 'attention' AND status <> 'repair' THEN 'attention'
    WHEN NEW.result = 'normal'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE pipeline_id = NEW.pipeline_id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'normal'
    ELSE status
  END
  WHERE id = NEW.pipeline_id;
END;

CREATE TRIGGER trg_repair_insert_updates_parent_status
AFTER INSERT ON repairs
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET status = CASE
    WHEN NEW.result = 'unresolved' THEN 'repair'
    WHEN NEW.result = 'monitor' AND status <> 'repair' THEN 'attention'
    WHEN NEW.result = 'resolved'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE asset_id = NEW.asset_id
          AND id <> NEW.id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'attention'
    ELSE status
  END
  WHERE id = NEW.asset_id;

  UPDATE pipelines
  SET status = CASE
    WHEN NEW.result = 'unresolved' THEN 'repair'
    WHEN NEW.result = 'monitor' AND status <> 'repair' THEN 'attention'
    WHEN NEW.result = 'resolved'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE pipeline_id = NEW.pipeline_id
          AND id <> NEW.id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'attention'
    ELSE status
  END
  WHERE id = NEW.pipeline_id;
END;

CREATE TRIGGER trg_repair_update_updates_parent_status
AFTER UPDATE OF result, asset_id, pipeline_id ON repairs
FOR EACH ROW
BEGIN
  UPDATE assets_point
  SET status = CASE
    WHEN NEW.result = 'unresolved' THEN 'repair'
    WHEN NEW.result = 'monitor' THEN 'attention'
    WHEN NEW.result = 'resolved'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE asset_id = NEW.asset_id
          AND id <> NEW.id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'attention'
    ELSE status
  END
  WHERE id = NEW.asset_id;

  UPDATE pipelines
  SET status = CASE
    WHEN NEW.result = 'unresolved' THEN 'repair'
    WHEN NEW.result = 'monitor' THEN 'attention'
    WHEN NEW.result = 'resolved'
      AND NOT EXISTS (
        SELECT 1 FROM repairs
        WHERE pipeline_id = NEW.pipeline_id
          AND id <> NEW.id
          AND result IN ('unresolved', 'monitor')
      )
      THEN 'attention'
    ELSE status
  END
  WHERE id = NEW.pipeline_id;
END;
"""


def create_geopackage(output: Path, *, force: bool = False) -> Path:
    output = output.resolve()
    if output.exists():
        if not force:
            raise FileExistsError(
                f"{output} already exists; pass --force to replace it"
            )
        output.unlink()

    output.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(output)
    try:
        connection.executescript(SCHEMA_SQL)

        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"GeoPackage integrity check failed: {integrity}")

        missing = connection.execute("""
            SELECT name
            FROM sqlite_master
            WHERE type='table'
              AND name IN (
                'asset_types', 'assets_point', 'pipelines', 'inspections',
                'repairs', 'attachments'
              )
            """).fetchall()
        if len(missing) != 6:
            raise RuntimeError("Required business tables were not created")

        connection.commit()
    except Exception:
        connection.close()
        output.unlink(missing_ok=True)
        raise
    else:
        connection.close()

    return output


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create the waterworks inspection GeoPackage"
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("waterworks-inspection.gpkg"),
        help="output GeoPackage path",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace an existing file",
    )
    args = parser.parse_args()

    created = create_geopackage(args.output, force=args.force)
    print(created)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
