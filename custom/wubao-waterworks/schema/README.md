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

附件统一关系表，避免照片、视频、文档分别实现一套业务逻辑。

建议字段：

- id: UUID
- owner_type: asset / inspection / repair
- owner_id: UUID
- media_type: photo / video / audio / document
- file_path
- caption
- captured_at
- created_at

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
- 附件允许照片、视频、音频和文档，多附件关联同一设施/巡检记录。
