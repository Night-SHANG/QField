# 供水巡检

本目录保存基于 QField 的供水巡检专用层。目标是尽量不修改 QField 核心，通过构建参数、主题、内置插件和 QGIS 项目配置实现业务定制。

## 已确定的基础方案

- 上游：QField
- 主底图：天地图·陕西（标准地图 + 影像）
- 管网主数据：标准 GIS 数据，禁止将 GCJ-02 / BD-09 作为主数据坐标
- 本地离线：GeoPackage / MBTiles / COG
- 现场定位：QField GNSS；后续可接外部 GNSS / RTK
- 业务扩展：app-wide QML 插件
- 核心原则：上游能力优先复用，业务差异放在本目录，只有插件接口无法完成时才修改 QField 核心

## 构建参数

专用构建使用以下参数：

- APP_NAME=供水巡检
- APP_PACKAGE_NAME=waterworks_inspection
- APP_THEME_PATH=custom/waterworks-inspection/theme.json
- APP_BUNDLED_PLUGINS=custom/waterworks-inspection/plugins

Android CI 使用仓库中的 `.github/workflows/waterworks-inspection-android.yml`。

## 第一阶段

1. 完成专用应用壳和内置插件。
2. 建立点位、管线、巡检、附件的数据模型。
3. 接入天地图·陕西在线底图，并准备现场区域离线地图包方案。
4. 建立现场检修主流程：查找点位 → 导航/定位 → 查看历史照片 → 记录巡检 → 添加附件。
5. 保持与 QField master 的可持续同步。


## 当前现场工作流

专用插件当前提供以下入口：

1. 在“点位 / 管线”之间切换搜索对象；点位按名称、编号、位置描述查询，管线按名称、编号、类型、材质、压力分区查询。
2. 点位按可配置设施类型和状态筛选；点位、管线均支持“需处理”状态筛选。
3. 按当前位置查询 100 m / 300 m / 500 m / 1 km / 2 km 内点位，并按距离排序。
4. 点位支持查看、编辑、QField 原生导航、巡检、维修、附件；管线支持查看、编辑、巡检、维修、附件。
5. 当前位置新增点位时复用 QField GNSS 与原生 FeatureForm。
6. 巡检自动关联点位或管线，并在 GNSS 精度有效时记录定位精度。
7. 点位和管线详情均通过原生 Relation 查看巡检、维修和附件历史。
8. 设施类型由 GeoPackage 的 asset_types 配置表驱动，新增类型不需要修改插件代码。
9. “备份 / 导出项目”直接进入 QField 原生 Project Folder，复用其“Compress project and send to...”和项目文件夹导出能力，不另造 ZIP/同步实现。

## 生成项目

数据文件可单独生成：

```bash
python custom/waterworks-inspection/tools/create_geopackage.py ./waterworks-inspection.gpkg
```

完整项目包需要在能够导入 PyQGIS 的 QGIS Python 环境运行：

```bash
export TDT_SHAANXI_TOKEN='<你的授权 Token>'
python custom/waterworks-inspection/tools/build_project_bundle.py ./WaterworksInspection
```

也可以追加一个或多个离线底图：

```bash
python custom/waterworks-inspection/tools/build_project_bundle.py \
  ./WaterworksInspection \
  --offline-basemap ./site.mbtiles \
  --offline-basemap ./local-imagery.tif
```

支持的离线底图格式为 MBTiles、GeoTIFF 和 COG。

### Token 安全

天地图 Token 不写入 Git 仓库，推荐通过 `TDT_SHAANXI_TOKEN` 环境变量传入。
生成后的本地 QGIS/QField 项目为了访问在线瓦片会包含实际服务 URL，因此包含 Token 的项目包应视为内部工作数据，不应直接提交到公开仓库。离线部署可以完全不提供在线 Token。

## 开发期 CI 策略

为避免每次业务提交都触发 QField 全平台构建，开发阶段采用两级检查：

- 日常提交到 `feature/waterworks-inspection`：只运行轻量 `供水巡检 Preflight`，检查 Python 语法、业务测试、主题 JSON 和专用层结构。
- `供水巡检 Android` 完整 APK：仅通过手动 `workflow_dispatch` 触发，用于阶段性真机包。
- QField 原生 Android / Linux / Windows / macOS / iOS / CodeQL 等完整矩阵：仅在阶段性 PR 或合并前运行，不把长期开发 PR 保持为开启状态。

这样普通功能开发不会重复消耗完整编译时间，同时仍保留阶段性全量回归能力。

## 数据备份与安全

供水巡检项目由 QGIS/QField 项目文件、GeoPackage、附件目录和可选离线底图共同组成。应用内“备份 / 导出项目”复用 QField 原生项目文件夹导出链路，整目录导出或压缩分享时可以把业务数据和附件一起带走。

普通 ZIP 只解决备份与迁移，不提供加密。生产环境中的管网坐标、巡检记录和附件应保存到受控设备、私有存储或受控同步服务中；后续数据加密单独实现，不把“压缩”当成“加密”。
