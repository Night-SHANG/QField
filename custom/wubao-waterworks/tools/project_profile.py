"""Declarative QGIS/QField profile for the Wubao waterworks project.

Keep business labels, forms and relations here so they can be tested without a
QGIS installation. configure_qgis_project.py is only an adapter from this
profile to PyQGIS.
"""

PROJECT_TITLE = "吴堡供水巡检"
PROJECT_CRS = "EPSG:4490"

# Default first-open view around Wubao county seat. This is intentionally a
# working-area view, not an administrative boundary lock.
DEFAULT_VIEW_EXTENT = (110.69, 37.41, 110.79, 37.49)

LAYER_GROUPS = {
    "管网业务": ("assets_point", "pipelines"),
    "记录": ("inspections", "repairs", "attachments"),
}

LAYERS = {
    "assets_point": "供水设施",
    "pipelines": "供水管线",
    "inspections": "巡检记录",
    "attachments": "附件",
    "repairs": "维修记录",
}

DISPLAY_EXPRESSIONS = {
    "assets_point": """coalesce("name", '未命名点位') ||
CASE WHEN coalesce("code", '') <> '' THEN ' [' || "code" || ']' ELSE '' END""",
    "pipelines": """coalesce("name", '未命名管线') ||
CASE WHEN coalesce("code", '') <> '' THEN ' [' || "code" || ']' ELSE '' END""",
    "inspections": """coalesce("inspector", '未填写人员') || ' · ' ||
coalesce(to_string("inspected_at"), '未填写时间')""",
    "attachments": """coalesce(
"caption",
"photo_path",
"video_path",
"audio_path",
"document_path",
'附件'
)""",
    "repairs": """coalesce("repair_type", '维修') || ' · ' ||
coalesce(to_string("reported_at"), '未填写时间')""",
}

ALIASES = {
    "assets_point": {
        "code": "设施编号",
        "name": "点位名称",
        "asset_type": "设施类型",
        "status": "状态",
        "pipeline_id": "所属管线",
        "area_name": "所属片区",
        "address_hint": "位置描述",
        "install_date": "安装日期",
        "last_inspection_at": "最近巡检",
        "note": "备注",
        "created_at": "创建时间",
        "updated_at": "更新时间",
    },
    "pipelines": {
        "code": "管线编号",
        "name": "管线名称",
        "pipe_type": "管线类型",
        "material": "材质",
        "diameter_mm": "管径（mm）",
        "pressure_zone": "压力分区",
        "status": "状态",
        "install_date": "安装日期",
        "note": "备注",
        "created_at": "创建时间",
        "updated_at": "更新时间",
    },
    "inspections": {
        "asset_id": "所属设施",
        "inspected_at": "巡检时间",
        "inspector": "巡检人员",
        "result": "巡检结果",
        "pressure_value": "压力值",
        "issue": "发现问题",
        "action_taken": "现场处理",
        "note": "备注",
        "position_accuracy_m": "定位精度（m）",
        "created_at": "创建时间",
    },
    "attachments": {
        "media_type": "附件类型",
        "photo_path": "照片",
        "video_path": "视频",
        "audio_path": "录音",
        "document_path": "文档",
        "caption": "说明",
        "captured_at": "采集时间",
        "created_at": "创建时间",
    },
    "repairs": {
        "asset_id": "所属设施",
        "inspection_id": "来源巡检",
        "reported_at": "报修时间",
        "repaired_at": "完成时间",
        "repair_type": "维修类型",
        "description": "维修内容",
        "result": "处理结果",
        "operator": "维修人员",
        "note": "备注",
    },
}

VALUE_MAPS = {
    ("assets_point", "asset_type"): [
        {"阀门井": "valve_well"},
        {"阀门": "valve"},
        {"压力表": "pressure_gauge"},
        {"消防栓": "hydrant"},
        {"排气阀": "air_valve"},
        {"排泥阀": "drain_valve"},
        {"水表": "meter"},
        {"其他": "other"},
    ],
    ("assets_point", "status"): [
        {"正常": "normal"},
        {"需关注": "attention"},
        {"待维修": "repair"},
        {"停用": "disabled"},
    ],
    ("pipelines", "status"): [
        {"正常": "normal"},
        {"需关注": "attention"},
        {"待维修": "repair"},
        {"停用": "disabled"},
    ],
    ("inspections", "result"): [
        {"正常": "normal"},
        {"需关注": "attention"},
        {"待维修": "repair"},
    ],
    ("repairs", "result"): [
        {"已解决": "resolved"},
        {"继续观察": "monitor"},
        {"未解决": "unresolved"},
    ],
    ("attachments", "media_type"): [
        {"照片": "photo"},
        {"视频": "video"},
        {"录音": "audio"},
        {"文档": "document"},
    ],
}

DEFAULTS = {
    ("assets_point", "id"): "uuid('WithoutBraces')",
    ("pipelines", "id"): "uuid('WithoutBraces')",
    ("inspections", "id"): "uuid('WithoutBraces')",
    ("attachments", "id"): "uuid('WithoutBraces')",
    ("repairs", "id"): "uuid('WithoutBraces')",
    ("assets_point", "created_at"): "now()",
    ("pipelines", "created_at"): "now()",
    ("inspections", "inspected_at"): "now()",
    ("inspections", "created_at"): "now()",
    ("attachments", "captured_at"): "now()",
    ("attachments", "created_at"): "now()",
    ("repairs", "reported_at"): "now()",
}

# id, human name, child layer/field, parent layer/field
RELATIONS = [
    ("pipeline_assets", "管线设施", "assets_point", "pipeline_id", "pipelines", "id"),
    ("asset_inspections", "巡检历史", "inspections", "asset_id", "assets_point", "id"),
    ("asset_repairs", "维修历史", "repairs", "asset_id", "assets_point", "id"),
    ("inspection_repairs", "关联维修", "repairs", "inspection_id", "inspections", "id"),
    ("asset_attachments", "设施附件", "attachments", "asset_id", "assets_point", "id"),
    ("inspection_attachments", "巡检附件", "attachments", "inspection_id", "inspections", "id"),
    ("repair_attachments", "维修附件", "attachments", "repair_id", "repairs", "id"),
]

RELATION_REFERENCE_FIELDS = {
    ("assets_point", "pipeline_id"): ("pipeline_assets", True),
    ("inspections", "asset_id"): ("asset_inspections", False),
    ("repairs", "asset_id"): ("asset_repairs", False),
    ("repairs", "inspection_id"): ("inspection_repairs", True),
}

HIDDEN_FIELDS = {
    "assets_point": {"fid", "id", "created_at", "updated_at"},
    "pipelines": {"fid", "id", "created_at", "updated_at"},
    "inspections": {"fid", "id", "asset_id", "created_at"},
    "attachments": {
        "fid", "id", "asset_id", "inspection_id", "repair_id", "created_at"
    },
    "repairs": {"fid", "id", "asset_id", "inspection_id"},
}

READ_ONLY_FIELDS = {
    "assets_point": {"last_inspection_at"},
    "inspections": {"position_accuracy_m"},
}

FORM_FIELDS = {
    "assets_point": [
        "code", "name", "asset_type", "status", "pipeline_id", "area_name",
        "address_hint", "install_date", "last_inspection_at", "note",
    ],
    "pipelines": [
        "code", "name", "pipe_type", "material", "diameter_mm",
        "pressure_zone", "status", "install_date", "note",
    ],
    "inspections": [
        "inspected_at", "inspector", "result", "pressure_value", "issue",
        "action_taken", "note", "position_accuracy_m",
    ],
    "attachments": ["media_type", "caption", "captured_at"],
    "repairs": [
        "reported_at", "repaired_at", "repair_type", "description", "result",
        "operator", "note",
    ],
}

# Relations embedded in each parent form.
FORM_RELATIONS = {
    "assets_point": ["asset_inspections", "asset_repairs", "asset_attachments"],
    "pipelines": ["pipeline_assets"],
    "inspections": ["inspection_repairs", "inspection_attachments"],
    "attachments": [],
    "repairs": ["repair_attachments"],
}

ATTACHMENT_BASE_CONFIG = {
    "StorageMode": 0,
    "RelativeStorage": 1,
    "UseLink": False,
    "FullUrl": False,
    "DocumentViewerWidth": 0,
    "DocumentViewerHeight": 0,
}

ATTACHMENT_CONFIGS = {
    # QField ExternalResource viewer: file=0, image=1, audio=3, video=4.
    "photo_path": {**ATTACHMENT_BASE_CONFIG, "DocumentViewer": 1},
    "video_path": {**ATTACHMENT_BASE_CONFIG, "DocumentViewer": 4},
    "audio_path": {**ATTACHMENT_BASE_CONFIG, "DocumentViewer": 3},
    "document_path": {**ATTACHMENT_BASE_CONFIG, "DocumentViewer": 0},
}

ATTACHMENT_MEDIA_FIELDS = {
    "photo_path": ("photo", "拍照 / 图片"),
    "video_path": ("video", "录像 / 视频"),
    "audio_path": ("audio", "录音"),
    "document_path": ("document", "文档"),
}

ATTACHMENT_NAMING = {
    "photo_path": (
        "'attachments/photos/' || "
        "coalesce(\"asset_id\", \"inspection_id\", \"repair_id\") || "
        "'/' || uuid('WithoutBraces') || '.{extension}'"
    ),
    "video_path": (
        "'attachments/videos/' || "
        "coalesce(\"asset_id\", \"inspection_id\", \"repair_id\") || "
        "'/' || uuid('WithoutBraces') || '.{extension}'"
    ),
    "audio_path": (
        "'attachments/audio/' || "
        "coalesce(\"asset_id\", \"inspection_id\", \"repair_id\") || "
        "'/' || uuid('WithoutBraces') || '.{extension}'"
    ),
    "document_path": (
        "'attachments/documents/' || "
        "coalesce(\"asset_id\", \"inspection_id\", \"repair_id\") || "
        "'/' || uuid('WithoutBraces') || '_{filename}'"
    ),
}


ASSET_SYMBOLS = {
    "valve_well": {"label": "阀门井", "shape": "circle", "color": "#1976D2", "size": "4.6"},
    "valve": {"label": "阀门", "shape": "diamond", "color": "#1565C0", "size": "4.4"},
    "pressure_gauge": {"label": "压力表", "shape": "triangle", "color": "#7B1FA2", "size": "4.6"},
    "hydrant": {"label": "消防栓", "shape": "square", "color": "#D32F2F", "size": "4.6"},
    "air_valve": {"label": "排气阀", "shape": "triangle", "color": "#00897B", "size": "4.4"},
    "drain_valve": {"label": "排泥阀", "shape": "diamond", "color": "#6D4C41", "size": "4.4"},
    "meter": {"label": "水表", "shape": "circle", "color": "#3949AB", "size": "4.2"},
    "other": {"label": "其他", "shape": "circle", "color": "#607D8B", "size": "4.0"},
}

STATUS_STROKE_COLORS = {
    "normal": "#2E7D32",
    "attention": "#F9A825",
    "repair": "#C62828",
    "disabled": "#616161",
}

PIPELINE_STYLE = {
    "color": "#00ACC1",
    "width": "1.1",
}

ASSET_LABEL_EXPRESSION = """CASE
WHEN coalesce("name", '') <> '' THEN "name"
WHEN coalesce("code", '') <> '' THEN "code"
ELSE '未命名点位'
END"""

ASSET_LABEL_MIN_SCALE = 12000


SUPPORTED_OFFLINE_BASEMAP_EXTENSIONS = {
    ".mbtiles",
    ".tif",
    ".tiff",
}

PROJECT_DIRECTORIES = (
    "attachments/photos",
    "attachments/videos",
    "attachments/audio",
    "attachments/documents",
)
