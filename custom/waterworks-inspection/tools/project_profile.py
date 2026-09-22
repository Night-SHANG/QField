"""Declarative QGIS/QField profile for the waterworks inspection project.

Keep business labels, forms and relations here so they can be tested without a
QGIS installation. configure_qgis_project.py is only an adapter from this
profile to PyQGIS.
"""

PROJECT_TITLE = "供水巡检"
PROJECT_CRS = "EPSG:4490"

# Leave the initial extent unset in the reusable profile. A deployment may
# provide its own extent or let QGIS/QField derive the view from loaded data.
DEFAULT_VIEW_EXTENT = None

LAYER_GROUPS = {
    "管网业务": ("assets_point", "pipelines"),
    "记录": ("inspections", "repairs", "attachments"),
    "配置": ("asset_types",),
}

LAYERS = {
    "asset_types": "设施类型配置",
    "assets_point": "供水设施",
    "pipelines": "供水管线",
    "inspections": "巡检记录",
    "attachments": "附件",
    "repairs": "维修记录",
}

DISPLAY_EXPRESSIONS = {
    "asset_types": '"label"',
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
    "asset_types": {
        "code": "类型代码",
        "label": "类型名称",
        "symbol_shape": "符号形状",
        "symbol_color": "符号颜色",
        "symbol_size": "符号大小",
        "sort_order": "排序",
        "active": "启用",
    },
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
        "last_inspection_at": "最近巡检",
        "note": "备注",
        "created_at": "创建时间",
        "updated_at": "更新时间",
    },
    "inspections": {
        "asset_id": "所属设施",
        "pipeline_id": "所属管线",
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
        "asset_id": "所属设施",
        "pipeline_id": "所属管线",
        "inspection_id": "所属巡检",
        "repair_id": "所属维修",
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
        "pipeline_id": "所属管线",
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

VALUE_RELATIONS = {
    ("assets_point", "asset_type"): {
        "layer": "asset_types",
        "key": "code",
        "value": "label",
        "allow_null": False,
        "order_by_value": True,
        "filter_expression": '"active" = 1',
    },
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
    ("pipeline_inspections", "管线巡检", "inspections", "pipeline_id", "pipelines", "id"),
    ("pipeline_repairs", "管线维修", "repairs", "pipeline_id", "pipelines", "id"),
    ("pipeline_attachments", "管线附件", "attachments", "pipeline_id", "pipelines", "id"),
    ("asset_inspections", "巡检历史", "inspections", "asset_id", "assets_point", "id"),
    ("asset_repairs", "维修历史", "repairs", "asset_id", "assets_point", "id"),
    ("inspection_repairs", "关联维修", "repairs", "inspection_id", "inspections", "id"),
    ("asset_attachments", "设施附件", "attachments", "asset_id", "assets_point", "id"),
    (
        "inspection_attachments",
        "巡检附件",
        "attachments",
        "inspection_id",
        "inspections",
        "id",
    ),
    ("repair_attachments", "维修附件", "attachments", "repair_id", "repairs", "id"),
]

RELATION_REFERENCE_FIELDS = {
    ("assets_point", "pipeline_id"): ("pipeline_assets", True),
    ("inspections", "asset_id"): ("asset_inspections", True),
    ("inspections", "pipeline_id"): ("pipeline_inspections", True),
    ("repairs", "asset_id"): ("asset_repairs", True),
    ("repairs", "pipeline_id"): ("pipeline_repairs", True),
    ("repairs", "inspection_id"): ("inspection_repairs", True),
    ("attachments", "asset_id"): ("asset_attachments", True),
    ("attachments", "pipeline_id"): ("pipeline_attachments", True),
    ("attachments", "inspection_id"): ("inspection_attachments", True),
    ("attachments", "repair_id"): ("repair_attachments", True),
}

HIDDEN_FIELDS = {
    "asset_types": {"fid"},
    "assets_point": {"fid", "id", "created_at", "updated_at"},
    "pipelines": {"fid", "id", "created_at", "updated_at"},
    "inspections": {"fid", "id", "asset_id", "pipeline_id", "created_at"},
    "attachments": {
        "fid",
        "id",
        "asset_id",
        "pipeline_id",
        "inspection_id",
        "repair_id",
        "created_at",
    },
    "repairs": {"fid", "id", "asset_id", "pipeline_id", "inspection_id"},
}

READ_ONLY_FIELDS = {
    "assets_point": {"last_inspection_at"},
    "pipelines": {"last_inspection_at"},
    "inspections": {"position_accuracy_m"},
}

FORM_FIELDS = {
    "asset_types": [
        "code",
        "label",
        "symbol_shape",
        "symbol_color",
        "symbol_size",
        "sort_order",
        "active",
    ],
    "assets_point": [
        "asset_type",
        "name",
        "code",
        "area_name",
        "address_hint",
        "install_date",
        "note",
    ],
    "pipelines": [
        "name",
        "code",
        "diameter_mm",
        "material",
        "pipe_type",
        "pressure_zone",
        "install_date",
        "note",
    ],
    "inspections": [
        "inspected_at",
        "inspector",
        "result",
        "pressure_value",
        "issue",
        "action_taken",
        "note",
        "position_accuracy_m",
    ],
    "attachments": ["media_type", "caption", "captured_at"],
    "repairs": [
        "reported_at",
        "repaired_at",
        "repair_type",
        "description",
        "result",
        "operator",
        "note",
    ],
}

# Keep field forms focused on the task at hand. Attachments are surfaced
# separately from history so a field worker can take a photo without digging
# through inspection/repair history.
FORM_ATTACHMENT_RELATIONS = {
    "asset_types": [],
    "assets_point": ["asset_attachments"],
    "pipelines": ["pipeline_attachments"],
    "inspections": ["inspection_attachments"],
    "attachments": [],
    "repairs": ["repair_attachments"],
}

FORM_HISTORY_RELATIONS = {
    "asset_types": [],
    "assets_point": ["asset_inspections", "asset_repairs"],
    "pipelines": ["pipeline_assets", "pipeline_inspections", "pipeline_repairs"],
    "inspections": ["inspection_repairs"],
    "attachments": [],
    "repairs": [],
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
        'coalesce("asset_id", "pipeline_id", "inspection_id", "repair_id") || '
        "'/' || uuid('WithoutBraces') || '.{extension}'"
    ),
    "video_path": (
        "'attachments/videos/' || "
        'coalesce("asset_id", "pipeline_id", "inspection_id", "repair_id") || '
        "'/' || uuid('WithoutBraces') || '.{extension}'"
    ),
    "audio_path": (
        "'attachments/audio/' || "
        'coalesce("asset_id", "pipeline_id", "inspection_id", "repair_id") || '
        "'/' || uuid('WithoutBraces') || '.{extension}'"
    ),
    "document_path": (
        "'attachments/documents/' || "
        'coalesce("asset_id", "pipeline_id", "inspection_id", "repair_id") || '
        "'/' || uuid('WithoutBraces') || '_{filename}'"
    ),
}


DEFAULT_ASSET_SYMBOL = {
    "label": "其他",
    "shape": "circle",
    "color": "#607D8B",
    "size": "4.0",
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
