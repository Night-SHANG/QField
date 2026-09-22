#!/usr/bin/env python3
"""Generate the QGIS/QField project for waterworks inspection.

Run this with a Python environment that can import qgis.core, for example the
Python shipped with QGIS. The GeoPackage itself is generated independently by
create_geopackage.py so CI can validate the data schema without QGIS.
"""

from __future__ import annotations

import argparse
import json
import os
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
            QgsDataSourceUri,
            QgsDefaultValue,
            QgsEditorWidgetSetup,
            QgsExpression,
            QgsLineSymbol,
            QgsMarkerSymbol,
            QgsOptionalExpression,
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
            QgsVectorTileLayer,
            QgsVectorTileUtils,
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
        "QgsDataSourceUri": QgsDataSourceUri,
        "QgsDefaultValue": QgsDefaultValue,
        "QgsEditorWidgetSetup": QgsEditorWidgetSetup,
        "QgsExpression": QgsExpression,
        "QgsLineSymbol": QgsLineSymbol,
        "QgsMarkerSymbol": QgsMarkerSymbol,
        "QgsOptionalExpression": QgsOptionalExpression,
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
        "QgsVectorTileLayer": QgsVectorTileLayer,
        "QgsVectorTileUtils": QgsVectorTileUtils,
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


def configure_project_view_and_tree(
    api,
    project,
    layers,
    *,
    standard_basemap=None,
    imagery_basemaps=None,
    offline_basemaps=None,
):
    QgsCoordinateReferenceSystem = api["QgsCoordinateReferenceSystem"]
    QgsRectangle = api["QgsRectangle"]
    QgsReferencedRectangle = api["QgsReferencedRectangle"]

    if profile.DEFAULT_VIEW_EXTENT is not None:
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

    config_group = root.addGroup("配置")
    config_group.addLayer(layers["asset_types"])
    config_group.setItemVisibilityChecked(False)

    imagery_basemaps = imagery_basemaps or []
    offline_basemaps = offline_basemaps or []

    basemap_sets = []
    if standard_basemap is not None:
        basemap_sets.append(("标准地图", [standard_basemap]))
    if imagery_basemaps:
        basemap_sets.append(("卫星地图", imagery_basemaps))
    if offline_basemaps:
        basemap_sets.append(("离线地图", offline_basemaps))

    if basemap_sets:
        basemap_group = root.addGroup("底图")
        for group_name, group_layers in basemap_sets:
            group = basemap_group.addGroup(group_name)
            for layer in group_layers:
                group.addLayer(layer)

        # Only one basemap set is visible at a time. Prefer the online
        # standard map, then imagery, then offline data.
        basemap_group.setIsMutuallyExclusive(True, 0)


def add_tianditu_vector_map(api, project, token: str | None):
    if not token:
        return None

    QgsDataSourceUri = api["QgsDataSourceUri"]
    QgsVectorTileLayer = api["QgsVectorTileLayer"]
    QgsVectorTileUtils = api["QgsVectorTileUtils"]

    style_url = map_sources.with_token(
        map_sources.VECTOR_STYLE_URL,
        token,
    )

    uri = QgsDataSourceUri()
    uri.setParam("type", "xyz")
    uri.setParam("styleUrl", style_url)
    encoded = uri.encodedUri()

    try:
        updated = QgsVectorTileUtils.updateUriSources(encoded)
        if isinstance(updated, str):
            encoded = updated
        elif isinstance(updated, tuple) and updated:
            encoded = updated[0]
    except Exception as exc:
        print(f"warning: unable to resolve TianDiTu vector sources: {exc}")
        return None

    layer = QgsVectorTileLayer(encoded, "天地图·陕西 标准地图")
    if not layer.isValid():
        print("warning: TianDiTu Shaanxi vector layer is invalid")
        return None

    try:
        style_result = layer.loadDefaultStyle()
        if isinstance(style_result, tuple):
            style_ok = bool(style_result[-1])
        else:
            style_ok = bool(style_result)
        if not style_ok:
            print("warning: TianDiTu vector style could not be loaded")
    except Exception as exc:
        print(f"warning: unable to load TianDiTu vector style: {exc}")

    project.addMapLayer(layer, False)
    return layer


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

    type_features = sorted(
        layers["asset_types"].getFeatures(),
        key=lambda feature: (
            int(feature["sort_order"]),
            str(feature["label"]),
        ),
    )
    for feature in type_features:
        if not bool(feature["active"]):
            continue

        value = str(feature["code"])
        label = str(feature["label"])
        shape = str(feature["symbol_shape"])
        color = str(feature["symbol_color"])
        size = str(feature["symbol_size"])

        symbol = QgsMarkerSymbol.createSimple(
            {
                "name": shape,
                "color": color,
                "size": size,
                "outline_color": profile.STATUS_STROKE_COLORS["normal"],
                "outline_width": "0.8",
            }
        )
        symbol.symbolLayer(0).setDataDefinedProperty(
            QgsSymbolLayer.Property.PropertyStrokeColor,
            QgsProperty.fromExpression(status_expression),
        )
        categories.append(QgsRendererCategory(value, symbol, label))

    if not categories:
        config = profile.DEFAULT_ASSET_SYMBOL
        symbol = QgsMarkerSymbol.createSimple(
            {
                "name": config["shape"],
                "color": config["color"],
                "size": config["size"],
                "outline_color": profile.STATUS_STROKE_COLORS["normal"],
                "outline_width": "0.8",
            }
        )
        categories.append(QgsRendererCategory("other", symbol, config["label"]))

    asset_layer.setRenderer(QgsCategorizedSymbolRenderer("asset_type", categories))

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
    layers["pipelines"].setRenderer(QgsSingleSymbolRenderer(pipeline_symbol))


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

    for (table, field_name), config in profile.VALUE_RELATIONS.items():
        reference_layer = layers[config["layer"]]
        value_relation_config = {
            "Layer": reference_layer.id(),
            "Key": config["key"],
            "Value": config["value"],
            "AllowNull": config["allow_null"],
            "OrderByValue": config["order_by_value"],
            "FilterExpression": config["filter_expression"],
        }
        layers[table].setEditorWidgetSetup(
            field_index(layers[table], field_name),
            QgsEditorWidgetSetup("ValueRelation", value_relation_config),
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

    for (table, field_name), (
        relation_id,
        allow_null,
    ) in profile.RELATION_REFERENCE_FIELDS.items():
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
    QgsExpression = api["QgsExpression"]
    QgsOptionalExpression = api["QgsOptionalExpression"]

    for table, layer in layers.items():
        config = layer.editFormConfig()
        config.clearTabs()
        config.setLayout(Qgis.AttributeFormLayout.DragAndDrop)

        for field_name in profile.READ_ONLY_FIELDS.get(table, set()):
            config.setReadOnly(field_index(layer, field_name), True)

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

        if table == "attachments":
            for field_name, (
                media_type,
                label,
            ) in profile.ATTACHMENT_MEDIA_FIELDS.items():
                media_group = QgsAttributeEditorContainer(label, details)
                media_group.setVisibilityExpression(
                    QgsOptionalExpression(
                        QgsExpression(f"\"media_type\" = '{media_type}'")
                    )
                )
                media_group.addChildElement(
                    QgsAttributeEditorField(
                        field_name,
                        field_index(layer, field_name),
                        media_group,
                    )
                )
                details.addChildElement(media_group)

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
        vector_basemap = add_tianditu_vector_map(
            api,
            project,
            tianditu_token,
        )
        imagery_layers = add_tianditu_imagery(
            api,
            project,
            tianditu_token,
        )
        offline_layers = []
        for offline_basemap in offline_basemaps or []:
            offline_layers.append(add_offline_basemap(api, project, offline_basemap))
        configure_project_view_and_tree(
            api,
            project,
            layers,
            standard_basemap=vector_basemap,
            imagery_basemaps=imagery_layers,
            offline_basemaps=offline_layers,
        )
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
        description="Generate the waterworks inspection QGIS/QField project"
    )
    parser.add_argument("geopackage", type=Path)
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("waterworks-inspection.qgs"),
    )
    parser.add_argument(
        "--offline-basemap",
        action="append",
        default=[],
        type=Path,
        help=("local MBTiles/GeoTIFF/COG basemap; may be supplied more than once"),
    )
    parser.add_argument(
        "--tianditu-token",
        default=os.environ.get("TDT_SHAANXI_TOKEN"),
        help=(
            "approved TianDiTu Shaanxi service token; defaults to the "
            "TDT_SHAANXI_TOKEN environment variable"
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
