#!/usr/bin/env python3
"""Generate the QGIS/QField project for Wubao waterworks.

Run this with a Python environment that can import qgis.core, for example the
Python shipped with QGIS. The GeoPackage itself is generated independently by
create_geopackage.py so CI can validate the data schema without QGIS.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import map_sources
import project_profile as profile


def require_qgis():
    try:
        from qgis.PyQt.QtGui import QColor
        from qgis.core import (
            Qgis,
            QgsApplication,
            QgsAttributeEditorContainer,
            QgsAttributeEditorField,
            QgsAttributeEditorRelation,
            QgsCategorizedSymbolRenderer,
            QgsCoordinateReferenceSystem,
            QgsDefaultValue,
            QgsEditorWidgetSetup,
            QgsLineSymbol,
            QgsMarkerSymbol,
            QgsPalLayerSettings,
            QgsProject,
            QgsProperty,
            QgsRectangle,
            QgsReferencedRectangle,
            QgsRendererCategory,
            QgsRasterLayer,
            QgsSingleSymbolRenderer,
            QgsRelation,
            QgsSymbolLayer,
            QgsTextBufferSettings,
            QgsTextFormat,
            QgsVectorLayer,
            QgsVectorLayerSimpleLabeling,
        )
    except ImportError as exc:
        raise SystemExit(
            "PyQGIS is required. Run this script from the QGIS Python environment."
        ) from exc

    return {
        "QColor": QColor,
        "Qgis": Qgis,
        "QgsApplication": QgsApplication,
        "QgsAttributeEditorContainer": QgsAttributeEditorContainer,
        "QgsAttributeEditorField": QgsAttributeEditorField,
        "QgsAttributeEditorRelation": QgsAttributeEditorRelation,
        "QgsCategorizedSymbolRenderer": QgsCategorizedSymbolRenderer,
        "QgsCoordinateReferenceSystem": QgsCoordinateReferenceSystem,
        "QgsDefaultValue": QgsDefaultValue,
        "QgsEditorWidgetSetup": QgsEditorWidgetSetup,
        "QgsLineSymbol": QgsLineSymbol,
        "QgsMarkerSymbol": QgsMarkerSymbol,
        "QgsPalLayerSettings": QgsPalLayerSettings,
        "QgsProject": QgsProject,
        "QgsProperty": QgsProperty,
        "QgsRectangle": QgsRectangle,
        "QgsReferencedRectangle": QgsReferencedRectangle,
        "QgsRendererCategory": QgsRendererCategory,
        "QgsRasterLayer": QgsRasterLayer,
        "QgsSingleSymbolRenderer": QgsSingleSymbolRenderer,
        "QgsRelation": QgsRelation,
        "QgsSymbolLayer": QgsSymbolLayer,
        "QgsTextBufferSettings": QgsTextBufferSettings,
        "QgsTextFormat": QgsTextFormat,
        "QgsVectorLayer": QgsVectorLayer,
        "QgsVectorLayerSimpleLabeling": QgsVectorLayerSimpleLabeling,
    }


def field_index(layer, field_name: str) -> int:
    index = layer.fields().indexOf(field_name)
    if index < 0:
        raise RuntimeError(f"{layer.name()}: missing field {field_name!r}")
    return index


def load_layers(api, project, geopackage: Path):
    layers = {}
    QgsVectorLayer = api["QgsVectorLayer"]

    for table, display_name in profile.LAYERS.items():
        uri = f"{geopackage}|layername={table}"
        layer = QgsVectorLayer(uri, display_name, "ogr")
        if not layer.isValid():
            raise RuntimeError(f"Unable to load {table} from {geopackage}")

        project.addMapLayer(layer, False)
        layers[table] = layer

    return layers


def configure_project_view_and_tree(api, project, layers, basemaps):
    QgsCoordinateReferenceSystem = api["QgsCoordinateReferenceSystem"]
    QgsRectangle = api["QgsRectangle"]
    QgsReferencedRectangle = api["QgsReferencedRectangle"]

    xmin, ymin, xmax, ymax = profile.DEFAULT_VIEW_EXTENT
    extent = QgsReferencedRectangle(
        QgsRectangle(xmin, ymin, xmax, ymax),
        QgsCoordinateReferenceSystem(profile.PROJECT_CRS),
    )
    project.viewSettings().setDefaultViewExtent(extent)
    project.viewSettings().setPresetFullExtent(extent)

    root = project.layerTreeRoot()
    root.removeAllChildren()

    business_group = root.addGroup("管网业务")
    business_group.addLayer(layers["assets_point"])
    business_group.addLayer(layers["pipelines"])

    records_group = root.addGroup("记录")
    records_group.addLayer(layers["inspections"])
    records_group.addLayer(layers["repairs"])
    records_group.addLayer(layers["attachments"])
    records_group.setItemVisibilityChecked(False)

    if basemaps:
        basemap_group = root.addGroup("底图")
        for layer in basemaps:
            basemap_group.addLayer(layer)


def add_tianditu_imagery(api, project, token: str | None):
    if not token:
        return []

    QgsRasterLayer = api["QgsRasterLayer"]
    added = []

    definitions = [
        ("天地图·陕西 影像", map_sources.IMAGERY_XYZ),
        ("天地图·陕西 影像注记", map_sources.IMAGERY_LABEL_XYZ),
    ]

    for name, template in definitions:
        tile_url = map_sources.with_token(template, token)
        uri = (
            "type=xyz&url="
            + tile_url
            + f"&zmin={map_sources.MIN_ZOOM}"
            + f"&zmax={map_sources.MAX_ZOOM}"
            + "&crs=EPSG4490"
        )
        layer = QgsRasterLayer(uri, name, "wms")
        if not layer.isValid():
            raise RuntimeError(f"Unable to create TianDiTu layer: {name}")

        project.addMapLayer(layer, False)
        project.layerTreeRoot().addLayer(layer)
        added.append(layer)

    return added


def configure_map_style(api, layers):
    QColor = api["QColor"]
    Qgis = api["Qgis"]
    QgsCategorizedSymbolRenderer = api["QgsCategorizedSymbolRenderer"]
    QgsLineSymbol = api["QgsLineSymbol"]
    QgsMarkerSymbol = api["QgsMarkerSymbol"]
    QgsPalLayerSettings = api["QgsPalLayerSettings"]
    QgsProperty = api["QgsProperty"]
    QgsRendererCategory = api["QgsRendererCategory"]
    QgsSingleSymbolRenderer = api["QgsSingleSymbolRenderer"]
    QgsSymbolLayer = api["QgsSymbolLayer"]
    QgsTextBufferSettings = api["QgsTextBufferSettings"]
    QgsTextFormat = api["QgsTextFormat"]
    QgsVectorLayerSimpleLabeling = api["QgsVectorLayerSimpleLabeling"]

    asset_layer = layers["assets_point"]
    categories = []
    status_expression = (
        "CASE "
        "WHEN \"status\"='attention' THEN '#F9A825' "
        "WHEN \"status\"='repair' THEN '#C62828' "
        "WHEN \"status\"='disabled' THEN '#616161' "
        "ELSE '#2E7D32' END"
    )

    for value, config in profile.ASSET_SYMBOLS.items():
        symbol = QgsMarkerSymbol.createSimple(
            {
                "name": config["shape"],
                "color": config["color"],
                "size": config["size"],
                "outline_color": profile.STATUS_STROKE_COLORS["normal"],
                "outline_width": "0.8",
            }
        )
        symbol.symbolLayer(0).setDataDefinedProperty(
            QgsSymbolLayer.Property.PropertyStrokeColor,
            QgsProperty.fromExpression(status_expression),
        )
        categories.append(
            QgsRendererCategory(value, symbol, config["label"])
        )

    asset_layer.setRenderer(
        QgsCategorizedSymbolRenderer("asset_type", categories)
    )

    label_settings = QgsPalLayerSettings()
    label_settings.fieldName = profile.ASSET_LABEL_EXPRESSION
    label_settings.isExpression = True
    label_settings.placement = Qgis.LabelPlacement.AroundPoint
    label_settings.scaleVisibility = True
    label_settings.minimumScale = profile.ASSET_LABEL_MIN_SCALE

    text_format = QgsTextFormat()
    text_format.setSize(9)
    text_format.setColor(QColor("#17212B"))

    buffer = QgsTextBufferSettings()
    buffer.setEnabled(True)
    buffer.setSize(1.2)
    buffer.setColor(QColor("#FFFFFF"))
    text_format.setBuffer(buffer)

    label_settings.setFormat(text_format)
    asset_layer.setLabeling(QgsVectorLayerSimpleLabeling(label_settings))
    asset_layer.setLabelsEnabled(True)

    pipeline_symbol = QgsLineSymbol.createSimple(
        {
            "line_color": profile.PIPELINE_STYLE["color"],
            "line_width": profile.PIPELINE_STYLE["width"],
            "capstyle": "round",
            "joinstyle": "round",
        }
    )
    pipeline_symbol.symbolLayer(0).setDataDefinedProperty(
        QgsSymbolLayer.Property.PropertyStrokeColor,
        QgsProperty.fromExpression(status_expression),
    )
    layers["pipelines"].setRenderer(
        QgsSingleSymbolRenderer(pipeline_symbol)
    )


def add_offline_basemap(api, project, path: Path):
    QgsRasterLayer = api["QgsRasterLayer"]

    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(f"Offline basemap not found: {path}")

    suffix = path.suffix.lower()
    if suffix not in profile.SUPPORTED_OFFLINE_BASEMAP_EXTENSIONS:
        raise ValueError(
            f"Unsupported offline basemap extension: {suffix}. "
            f"Supported: {sorted(profile.SUPPORTED_OFFLINE_BASEMAP_EXTENSIONS)}"
        )

    layer = QgsRasterLayer(str(path), f"离线底图 · {path.stem}", "gdal")
    if not layer.isValid():
        raise RuntimeError(f"Unable to load offline basemap: {path}")

    project.addMapLayer(layer, False)
    project.layerTreeRoot().addLayer(layer)
    return layer


def configure_fields(api, layers):
    QgsDefaultValue = api["QgsDefaultValue"]
    QgsEditorWidgetSetup = api["QgsEditorWidgetSetup"]

    for table, layer in layers.items():
        layer.setDisplayExpression(profile.DISPLAY_EXPRESSIONS[table])

        for field_name, alias in profile.ALIASES.get(table, {}).items():
            layer.setFieldAlias(field_index(layer, field_name), alias)

        for field_name in profile.HIDDEN_FIELDS.get(table, set()):
            layer.setEditorWidgetSetup(
                field_index(layer, field_name),
                QgsEditorWidgetSetup("Hidden", {}),
            )

    for (table, field_name), mapping in profile.VALUE_MAPS.items():
        layers[table].setEditorWidgetSetup(
            field_index(layers[table], field_name),
            QgsEditorWidgetSetup("ValueMap", {"map": mapping}),
        )

    for (table, field_name), expression in profile.DEFAULTS.items():
        layers[table].setDefaultValueDefinition(
            field_index(layers[table], field_name),
            QgsDefaultValue(expression),
        )

    # QField's ExternalResource widget maps these viewer modes to its
    # native camera, video recorder, microphone and file picker controls.
    for field_name, config in profile.ATTACHMENT_CONFIGS.items():
        layers["attachments"].setEditorWidgetSetup(
            field_index(layers["attachments"], field_name),
            QgsEditorWidgetSetup("ExternalResource", config),
        )

    layers["attachments"].setCustomProperty(
        "QFieldSync/attachment_naming",
        json.dumps(profile.ATTACHMENT_NAMING, ensure_ascii=False),
    )


def configure_relations(api, project, layers):
    QgsRelation = api["QgsRelation"]
    QgsEditorWidgetSetup = api["QgsEditorWidgetSetup"]

    manager = project.relationManager()
    relations = {}

    for (
        relation_id,
        relation_name,
        child_table,
        child_field,
        parent_table,
        parent_field,
    ) in profile.RELATIONS:
        relation = QgsRelation()
        relation.setId(relation_id)
        relation.setName(relation_name)
        relation.setReferencingLayer(layers[child_table].id())
        relation.setReferencedLayer(layers[parent_table].id())
        relation.addFieldPair(child_field, parent_field)
        relation.updateRelationStatus()

        if not relation.isValid():
            raise RuntimeError(
                f"Invalid relation {relation_id}: {relation.validationError()}"
            )

        manager.addRelation(relation)
        relations[relation_id] = relation

    for (table, field_name), (relation_id, allow_null) in (
        profile.RELATION_REFERENCE_FIELDS.items()
    ):
        config = {
            "Relation": relation_id,
            "AllowNULL": allow_null,
            "AllowAddFeatures": False,
            "MapIdentification": True,
            "OrderByValue": True,
            "ReadOnly": False,
            "ShowForm": False,
            "ShowOpenFormButton": True,
        }
        layers[table].setEditorWidgetSetup(
            field_index(layers[table], field_name),
            QgsEditorWidgetSetup("RelationReference", config),
        )

    return relations


def configure_forms(api, layers, relations):
    Qgis = api["Qgis"]
    QgsAttributeEditorContainer = api["QgsAttributeEditorContainer"]
    QgsAttributeEditorField = api["QgsAttributeEditorField"]
    QgsAttributeEditorRelation = api["QgsAttributeEditorRelation"]

    for table, layer in layers.items():
        config = layer.editFormConfig()
        config.clearTabs()
        config.setLayout(Qgis.AttributeFormLayout.DragAndDrop)
        root = config.invisibleRootContainer()

        details = QgsAttributeEditorContainer("基本信息", root)
        for field_name in profile.FORM_FIELDS.get(table, []):
            details.addChildElement(
                QgsAttributeEditorField(
                    field_name,
                    field_index(layer, field_name),
                    details,
                )
            )
        config.addTab(details)

        relation_ids = profile.FORM_RELATIONS.get(table, [])
        if relation_ids:
            history = QgsAttributeEditorContainer("关联记录", root)
            for relation_id in relation_ids:
                relation = relations[relation_id]
                relation_widget = QgsAttributeEditorRelation(relation, history)
                relation_widget.setLabel(relation.name())
                history.addChildElement(relation_widget)
            config.addTab(history)

        layer.setEditFormConfig(config)


def build_project(
    geopackage: Path,
    output: Path,
    *,
    tianditu_token: str | None = None,
    offline_basemaps: list[Path] | None = None,
) -> Path:
    api = require_qgis()
    QgsApplication = api["QgsApplication"]
    QgsCoordinateReferenceSystem = api["QgsCoordinateReferenceSystem"]
    QgsProject = api["QgsProject"]
    Qgis = api["Qgis"]

    owned_app = None
    if QgsApplication.instance() is None:
        owned_app = QgsApplication([], False)
        owned_app.initQgis()

    try:
        project = QgsProject()
        project.setTitle(profile.PROJECT_TITLE)
        project.setCrs(QgsCoordinateReferenceSystem(profile.PROJECT_CRS))
        project.setFilePathStorage(Qgis.FilePathType.Relative)

        layers = load_layers(api, project, geopackage.resolve())
        basemaps = add_tianditu_imagery(api, project, tianditu_token)
        for offline_basemap in offline_basemaps or []:
            basemaps.append(add_offline_basemap(api, project, offline_basemap))
        configure_project_view_and_tree(api, project, layers, basemaps)
        configure_fields(api, layers)
        configure_map_style(api, layers)
        relations = configure_relations(api, project, layers)
        configure_forms(api, layers, relations)

        output = output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        project.setFileName(str(output))

        if not project.write():
            raise RuntimeError(f"QGIS failed to write project: {output}")

        return output
    finally:
        if owned_app is not None:
            owned_app.exitQgis()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the Wubao waterworks QGIS/QField project"
    )
    parser.add_argument("geopackage", type=Path)
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("wubao-waterworks.qgs"),
    )
    parser.add_argument(
        "--offline-basemap",
        action="append",
        default=[],
        type=Path,
        help=(
            "local MBTiles/GeoTIFF/COG basemap; may be supplied more than once"
        ),
    )
    parser.add_argument(
        "--tianditu-token",
        default=None,
        help=(
            "approved TianDiTu Shaanxi service token; omitted tokens are never "
            "read from source control"
        ),
    )
    args = parser.parse_args()

    if not args.geopackage.is_file():
        parser.error(f"GeoPackage not found: {args.geopackage}")

    print(
        build_project(
            args.geopackage,
            args.output,
            tianditu_token=args.tianditu_token,
            offline_basemaps=args.offline_basemap,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
