# 吴堡县供水 GIS 数据模型 v0

第一版数据模型按“一个能力一个实现”设计，点位类型通过字段和样式区分，不为阀门、压力表、消防栓分别复制整套 CRUD。

## 1. assets_point

点状设施统一图层。

建议字段：

- id: UUID，主键
- code: 设施编号
- name: 自定义名称
- asset_type: valve_well / valve / pressure_gauge / hydrant / air_valve / drain_valve / meter / other
- status: normal / attention / repair / disabled
- pipeline_id: 所属管线 UUID
- area_name: 所属片区
- address_hint: 现场位置描述
- install_date: 安装日期
- last_inspection_at: 最近巡检时间
- note: 备注
- created_at / updated_at

几何：Point。主数据坐标采用标准 GIS CRS；GNSS 输入按 QField 要求使用 EPSG:4326，再由项目 CRS 转换。

## 2. pipelines

管线图层。

建议字段：

- id: UUID
- code
- name
- pipe_type
- material
- diameter_mm
- pressure_zone
- status
- install_date
- note
- created_at / updated_at

几何：LineString。

## 3. inspections

巡检记录表，不覆盖设施历史。

建议字段：

- id: UUID
- asset_id: 关联 assets_point
- inspected_at
- inspector
- result: normal / attention / repair
- pressure_value
- issue
- action_taken
- note
- position_accuracy_m
- created_at

## 4. attachments

附件统一关系表，照片、视频、音频、文档仍共用一个实现；父对象使用明确外键，便于 QGIS/QField 建立原生 1:N Relation 和附件画廊。

建议字段：

- id: UUID
- asset_id: 设施 UUID，可空
- inspection_id: 巡检 UUID，可空
- repair_id: 维修 UUID，可空
- photo_path: 照片，可空
- video_path: 视频，可空
- audio_path: 录音，可空
- document_path: 文档，可空
- caption
- captured_at
- created_at

三个父级字段必须且只能填写一个；四个媒体字段也必须且只能填写一个。这样仍然只有一套附件表和一套关系逻辑，但 QField 可以分别提供原生拍照、录像、录音和文件选择控件。

## 5. repairs

维修历史。

建议字段：

- id: UUID
- asset_id
- inspection_id
- reported_at
- repaired_at
- repair_type
- description
- result
- operator
- note

## 设计约束

- 所有业务主键使用 UUID。
- 删除设施不得级联物理删除历史巡检和附件；业务层使用停用/归档。
- 点位名称、类型、图标、颜色由数据驱动，禁止写死为固定几类设施。
- 在线底图与管网主数据解耦。
- 高德 GCJ-02、百度 BD-09 只能作为显示层转换来源，不能污染主数据。
- 附件允许照片、视频、音频和文档，多附件关联同一设施/巡检/维修记录；父对象必须且只能有一个。


## 状态联动规则

设施状态不要求现场人员重复填写两次：

- 巡检结果为“待维修”时，设施自动变为 `repair`。
- 巡检结果为“需关注”时，设施自动变为 `attention`，但不会把已有 `repair` 降级。
- 新建未解决维修时，设施保持/变为 `repair`。
- 维修标记“已解决”且不存在其他未解决维修时，设施先变为 `attention`，表示需要复查。
- 后续正常巡检确认且没有未解决/观察中的维修后，设施才恢复 `normal`。

这样地图状态颜色直接反映现场工作结果，同时避免“维修单一关闭就自动宣告设备正常”的过度自动化。
