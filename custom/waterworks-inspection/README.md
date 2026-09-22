# 供水巡检

本目录保存基于 QField 的供水巡检专用层。目标是尽量不修改 QField 核心，通过构建参数、主题、内置插件和 QGIS 项目配置实现业务定制。

## 已确定的基础方案

- 上游：QField
- 默认底图：QField 原生在线底图兜底，首次启动固定到榆林区域；定位可用后自动跳到当前位置
- 可选增强底图：天地图·陕西（标准地图 + 影像），需要官方授权 Token
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

普通使用只有一套地图界面，不再使用“巡”总入口，也不按管理员/维修等角色拆模式。

1. 打开软件直接进入地图。首次安装自动建立供水项目；无天地图 Token 时继续使用在线底图并以榆林区域作为默认范围。
2. 地图底部固定四个入口：**查找 / 附近 / 新增 / 更多**；地图右侧保留独立“定位”按钮。
3. 右上角只有一个全局 **查看模式 / 编辑模式** 开关，状态会记住：
   - 查看模式：点位、管线只能查看、搜索、附近查询和导航；所有新增、修改、巡检、维修、添加附件写操作统一拦截。
   - 编辑模式：开放新增点位、新建管线、编辑、巡检、维修和添加附件。
4. “附近”选择点位/管线和查询距离后，结果直接显示在底部面板，同时在地图上临时高亮，不再只提示“载入几个”却看不到列表。
5. “查找”直接提供名称/编号搜索；设施类型、状态、从未巡检等条件放在折叠的“筛选”区域。
6. “新增”只在编辑模式可用，里面仅保留“新增点位 / 新建管线”。新增点位继续复用 QField 原生相机，可连续拍多张；新建管线继续复用 QField 原生数字化。
7. 查询结果中的“地图 / 详情 / 导航”始终可用；“编辑 / 巡检 / 维修 / 附件”只在编辑模式显示。
8. 地图上直接点击单个点位/管线时继续复用 QField 原生识别与详情表单，并自动缩放到对象。
9. “我的位置”标记可以隐藏而不停止 GNSS，避免人在设施点上时定位标记抢占点击。
10. “更多”集中放显示/隐藏我的位置、复制当前位置、备份/导出、打开其他供水数据等低频操作。
11. QField 原生图层树和 Map Theme 继续在现场版隐藏；未来底图切换用明确的“地图样式”入口，不暴露专业 GIS 配置。


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
天地图·陕西官方服务需要授权 Token；供水版 APK 不依赖这个 Token 才能显示地图。没有 Token 时使用默认在线底图，避免出现空白地图；需要官方陕西影像/矢量服务时再配置 Token。
生成后的本地 QGIS/QField 项目如果包含 Token，应视为内部工作数据，不应直接提交到公开仓库。

## 开发期 CI 策略

为避免每次业务提交都触发 QField 全平台构建，开发阶段采用两级检查：

- 日常提交到 `feature/waterworks-inspection`：只运行轻量 `供水巡检 Preflight`，检查 Python 语法、业务测试、主题 JSON 和专用层结构。
- `供水巡检 Android` 完整 APK：可通过手动 `workflow_dispatch` 触发；自动化协作时仅更新专用 `build/waterworks-inspection-apk` 分支触发，用于阶段性真机包。
- 普通功能提交永远不会因为上述 build 分支机制触发完整 Android 构建。
- QField 原生 Android / Linux / Windows / macOS / iOS / CodeQL 等完整矩阵：仅在阶段性 PR 或合并前运行，不把长期开发 PR 保持为开启状态。

这样普通功能开发不会重复消耗完整编译时间，同时仍保留阶段性全量回归能力。

## 数据备份与安全

供水巡检项目由 QGIS/QField 项目文件、GeoPackage、附件目录和可选离线底图共同组成。应用内“备份 / 导出项目”复用 QField 原生项目文件夹导出链路，整目录导出或压缩分享时可以把业务数据和附件一起带走。

普通 ZIP 只解决备份与迁移，不提供加密。默认沿用 QField 的普通项目数据方式，不额外增加数据库加密、加密 ZIP 或禁止截图等机制，避免无实际需求地提高复杂度。

## 上游能力复用规则

新增功能按以下顺序检查：QField 原生能力 → QGIS/QFieldSync → QFieldCloud → 官方/社区插件 → 业务层插件 → 最后才考虑 QField 核心修改。

例如附近管线距离直接复用 QField 已公开到 QML 的 `QfExpressionEvaluator` 与 QGIS `distance()/transform()` 表达式计算，不为供水巡检新增几何距离核心 API。只有上游能力确实无法通过现有接口复用时，才允许增加尽可能小、可通用的核心接口。
