# 吴堡供水巡检

本目录保存基于 QField 的吴堡县自来水巡检专用层。目标是尽量不修改 QField 核心，通过构建参数、主题、内置插件和 QGIS 项目配置实现业务定制。

## 已确定的基础方案

- 上游：QField
- 业务区域：陕西省榆林市吴堡县
- 主底图：天地图·陕西（标准地图 + 影像）
- 管网主数据：标准 GIS 数据，禁止将 GCJ-02 / BD-09 作为主数据坐标
- 本地离线：GeoPackage / MBTiles / COG
- 现场定位：QField GNSS；后续可接外部 GNSS / RTK
- 业务扩展：app-wide QML 插件
- 核心原则：上游能力优先复用，业务差异放在本目录，只有插件接口无法完成时才修改 QField 核心

## 构建参数

专用构建使用以下参数：

- APP_NAME=吴堡供水巡检
- APP_PACKAGE_NAME=wubao_waterworks
- APP_THEME_PATH=custom/wubao-waterworks/theme.json
- APP_BUNDLED_PLUGINS=custom/wubao-waterworks/plugins

Android CI 使用仓库中的 `.github/workflows/wubao-android.yml`。

## 第一阶段

1. 完成专用应用壳和内置插件。
2. 建立点位、管线、巡检、附件的数据模型。
3. 接入天地图·陕西在线底图，并准备吴堡县离线地图包方案。
4. 建立现场检修主流程：查找点位 → 导航/定位 → 查看历史照片 → 记录巡检 → 添加附件。
5. 保持与 QField master 的可持续同步。
