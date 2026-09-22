#!/usr/bin/env python3
"""Generate the QGIS/QField project for Wubao waterworks.

Run this with a Python environment that can import qgis.core, for example the
Python shipped with QGIS. The GeoPackage itself is generated independently by
create_geopackage.py so CI can validate the data schema without QGIS.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import project_profile as profile


def require_qgis():
    try:
        from qgis.core import (
            Qgis,
            QgsApplication,
            QgsAttributeEditorContainer,
            QgsAttributeEditorField,
            QgsAttributeEditorRelation,
            QgsCoordinateReferenceSystem,
            QgsDefaultValue,
            QgsEditorWidgetSetup,
            QgsProject,
            QgsRelation,
            QgsVectorLayer,
        )
    except ImportError as exc:
        raise SystemExit(
            "PyQGIS is required. Run this script from the QGIS Python environment."
        ) from exc

    return {
        "Qgis": Qgis,
        "QgsApplication": QgsApplication,
        "QgsAttributeEditorContainer": QgsAttributeEditorContainer,
        "QgsAttributeEditorField": QgsAttributeEditorField,
        "QgsAttributeEditorRelation": QgsAttributeEditorRelation,
        "QgsCoordinateReferenceSystem": QgsCoordinateReferenceSystem,
        "QgsDefaultValue": QgsDefaultValue,
        "QgsEditorWidgetSetup": QgsEditorWidgetSetup,
        "QgsProject": QgsProject,
        "QgsRelation": QgsRelation,
        "QgsVectorLayer": QgsVectorLayer,
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

        project.addMapLayer(layer)
        layers[table] = layer

    return layers


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

    # QGIS's ExternalResource widget is the Attachment widget used by QField.
    layers["attachments"].setEditorWidgetSetup(
        field_index(layers["attachments"], "file_path"),
        QgsEditorWidgetSetup("ExternalResource", profile.ATTACHMENT_CONFIG),
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


def build_project(geopackage: Path, output: Path) -> Path:
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
        configure_fields(api, layers)
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
    args = parser.parse_args()

    if not args.geopackage.is_file():
        parser.error(f"GeoPackage not found: {args.geopackage}")

    print(build_project(args.geopackage, args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
