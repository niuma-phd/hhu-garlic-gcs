# 地面站基础版简化方案 v2（含 issue #4 围栏移除）

> 状态：待确认。确认后在 `simplify-work-flow` 分支实施。
> 关联：issue #4（围栏移除并入本方案）；飞控侧 garlic-rover-4.7 acd703d0（FENCE_* 已删）。
> 取代《电子围栏移除适配方案》（geofence-removal-plan.md，v1）——v1 的"边界保留为规划元素"被本方案的整体简化取代：边界功能整体删除。

## 1. 方向

- **规划页四步 → 两步**：① 排航线　② 检查上传（原来的①选地块、②画边界砍掉）。
- 砍掉未经真实作业场景验证的功能：地块管理、画边界、面积。等弄清实际作业方式再按需加回（git 历史都在）。
- issue #4 随之变得更简单：不需要"边界降级为规划元素"，而是边界相关 UI/检查/上传/请求**全部移除**，GCS 与飞控零围栏交互。
- 保留基本功：连接车辆、排航线、上传前检查、上传、作业页全套（开始/暂停/继续/返回起点/停车上锁、断点续作、开到指定点、进度、消息列表、状态栏）、设置、4G/NTRIP/服务。

## 2. 砍留清单

### 砍掉（UI 与代码一并删除）

| 功能 | 涉及文件 |
|---|---|
| 地块管理（列表/新建/改名/复制/删除/幅宽/最近作业/.plan 按地块存储） | `HHUFieldPanel.qml`、`HHUFieldManager.cc/h`、`CustomPlugin` 的 `hhuFields` 注册、工具栏"地块"按钮、规划页步骤① |
| 画边界（步骤②、角点、撤销/清空边界） | `HHUPlanPanel.qml` 边界段、`HHUFence.qml`、`HHUVehiclePointTools` 围栏部分、gen_overrides 的围栏层点击路由 |
| 面积（显示与单位设置） | `HHUPlanSummary.qml`（整卡，见 D3）、`GeneralSettings.qml`"面积"下拉、`HHUSettings` 的 `areaUnit/formatArea`、`CustomPlugin` 的 areaUnits 定制 |
| 围栏与飞控的一切交互 | 上传链发送围栏、连接时请求围栏、"从车上删除"清围栏、`hhu_config.json` 5 条围栏死词条 |

### 保留（不动或微改）

- **作业页全套**：`HHUWorkPanel`（仅删 `_fenceAvailable` 检查项）、`HHUMissionProgress`（标题去掉地块名，固定"车上航线"）、`HHUGotoHere`（删围栏限制后无范围约束，见 D4）、消息列表、状态栏、`HHUAlarms`。
- **断点续作**：`HHUWorkLog` 已支持 `fieldId=""`（键自动落到 `none` 命名空间），机制不动；`HHUWorkPanel._openStart` 传 `""`，`HHUStartDialog` 去掉 fieldName 参数。新增小改进：**上传成功后清除该车续作点**（`HHUWorkLog` 加 `clearResume(vehicle)`），防止换了航线还提示旧断点（原按地块命名空间隔离，现在无地块了）。
- **上传前检查** `HHUUploadCheck`：删围栏两项，保留急转弯 / 航点超限 / 首点过远 / 只读连接 / 无航线 / 未连接 / 作业中。
- **.plan 打开/保存**：工具栏回归上游 Open / Save / Save as（去掉地块化 patch）——航线唯一的留存方式，不能砍。
- 设置、4G、NTRIP、服务、链接监控。

## 3. 改动清单

### custom QML
1. `HHUPlanPanel.qml` — **重写为两步**：① 排航线（点图加点 / 在车位加点 / 撤销 / 清空 / 统一速度）② 检查上传（检查结果列表内嵌 + 上传按钮 + 上传成功"去作业"）。删地块、边界、面积全部逻辑，预计 641 → 约 350 行。
2. `HHUUploadCheck.qml` — 删围栏检查与 `HHUFence` 实例。
3. `HHUGotoHere.qml` — 删围栏两项检查（无边界概念后无范围限制）。
4. `HHUWorkPanel.qml` — 删 `_fenceAvailable`/`_fenceController` 及 `_startBlocked` 围栏项；`_openStart` 传 `""`。
5. `HHUMissionProgress.qml` — 删 `_fieldName` 查找。
6. `HHUStartDialog.qml` — 去 fieldName 参数（副标题只显示航点数）。
7. 删除 `HHUFieldPanel.qml`、`HHUFence.qml`、`HHUPlanSummary.qml`、`HHUVehiclePointTools.qml`（车位加点逻辑内联进 HHUPlanPanel）；`custom.qrc` 同步。
8. `settings/GeneralSettings.qml` — 删"面积"下拉。

### custom C++
9. `CustomPlugin.cc/h` — 删 `hhuFields` 注册与 `HHUFieldManager` 成员。areaUnits 定制段**保留**：它只约束上游隐藏设置页里 Fact 的显示单位，与用户可见的"面积"无关，动了反而影响上游行为。
10. 删除 `HHUFieldManager.cc/h`；`custom/CMakeLists.txt` 同步。
11. `HHUSettings.cc/h` — 删 `areaUnit`/`formatArea`。
12. `HHUWorkLog.cc/h` — 加 `Q_INVOKABLE clearResume(Vehicle*)`；`resumeWaypoint` 去掉 fieldId 参数（固定 "none" 键）；删 `vehicleField/setVehicleField`。

### 核心 src（2 处小补丁，issue #4 必需）
13. `PlanMasterController.cc::_sendMissionComplete()` — 跳过 GeoFence 发送段（注释引 issue #4）；`removeAllFromVehicle()` 跳过围栏清空。
14. `InitialConnectStateMachine.cc` State 5 — 连接时跳过围栏请求（省一次请求，规避最坏 ~30 s 等待）。

### gen_overrides.py（改后重跑生成）
15. `PlanView.qml` patch — 删 `HHUPlanSummary` 插入、删 `_layerFence` 点击路由；`HHUPlanPanel` 属性适配。
16. `PlanToolBarIndicators.qml` patch — 删 Fields 按钮 / `hhuFieldPanel` / `setVehicleField` / save-current patch，回归上游 Open/Save；保留 `hhuUploadCheck` 上传前检查。
17. 删 `GeoFenceMapVisuals`、`QGCMapPolygonVisuals`、`PlanEditLayers` 三个不再需要的 patch，恢复上游文件（qrc alias 同步删）。
18. 旧 .plan 兼容：加载路径未改动（上游 `loadFromFile`），文件里的围栏段只进入休眠的 GeoFenceController——不显示、不可编辑、不上传。

### 配置 / 翻译 / 发布
19. `hhu_config.json` — 删 5 条围栏死词条。
20. `hhu_custom_zh_CN.ts` + `.qm` — i18n.py 流程重编，清理地块/边界/面积/围栏词条。
21. `HHU_APP_VERSION` 1.0.2 → 1.1.0；推送 `simplify-work-flow`；CI 自动出 `HHU-GCS-simplify-v1.1.0-b<N>` 滚动 prerelease；issue #4 回复关闭。
22. 本文档随实现一并提交。

## 4. 风险与注意

- 需求说明 V1.0 §3.3 的地块管理/面积属合同附件变更，需甲方过目（与 issue #4 同一处标注）。
- 旧 AppData/fields 数据残留无害（代码删除后不再读取）；旧 .plan 文件可正常打开（边界段加载后即清空）。
- 断点续作无地块命名空间后，同车换航线会带出旧断点 → 由"上传成功清除续作点"解决。
- 作业页进度卡标题不再有地块名（固定"车上航线"）。
- 相关 QML 无单元测试，验证靠 SITL 联调 + CI。

## 5. 验证计划（SITL）

1. 规划页两步走通：加点 → 速度 → 检查 → 上传 → 去作业；旧 .plan（带边界）打开后边界被清空。
2. 上传过程无 FENCE 类 MAVLink 传输；"开始作业"无围栏拦截；Goto 任意点可用。
3. 断点续作：中途停车 → 开始对话框"接着上次 从第 N 点"；上传新航线后断点已清。
4. 工具栏 Open/Save 可用；设置页无面积项；界面无地块/边界/围栏残留文案。
5. 回归：开始/暂停/继续/返回/停车上锁、授权闸门、消息列表、断链行为。

## 6. 决策点

| # | 问题 | 建议 |
|---|------|------|
| D1 | 断点续作保留（去地块化改造）还是也砍 | **保留**——已验证过，作业刚需 |
| D2 | .plan 打开/保存保留还是砍 | **保留**——航线唯一留存方式 |
| D3 | 航线摘要卡（长度/时间/点数）保留还是砍 | **砍**——彻底点，航点数步骤面板上已有 |
| D4 | 开到指定点（Goto）保留还是砍 | **保留**——作业页基本操作 |
| D5 | 版本 1.1.0 + simplify 滚动 prerelease | 同意 |

## 7. 实施结果（2026-10-13）

已按上述方案实现并推送。SITL 联调（WSL ArduRover 4.7.1 + sim_vcu Nav v1.0，Windows 端新构建）全部通过：

- 规划页两步：清空/加点/在车位加点/撤销/速度/下一步/检查/上传 全流程可用；检查步文案"急转弯、航点数量和连接状态均正常"。
- 连接：日志 `Skipping geofence load "(geofence removed, issue #4)"`，连接即就绪。
- 上传：日志 `sendToVehicle GeoFence skipped (HHU, issue #4)`，只传航线段；车上航线与规划一致。
- 开始作业无围栏拦截；Goto 任意点可用（"开到这里？离车 N m"→执行）。
- 断点续作：中途停车 → "接着上次 从第 2 点开始"；上传新航线 → 断点清除（"无记录"）。
- 设置页单位区只剩速度/距离，无面积项；全流程 QML 日志零错误。

顺带修复两个**历史遗留的坏调用**（旧版本就存在，点击即抛 TypeError，功能实际是坏的）：

- `HHUPlanPanel` 清空按钮：`MissionController.removeAll()` 不存在 → 改为 `planMasterController.removeAll()`。
- 上传调用：`planMasterController.upload()` 不存在（上游 QGC master 同样无此方法）→ 改为 `sendToVehicle()`，两处（HHUPlanPanel、PlanToolBarIndicators patch）。

注意：断点只在车进入第 2 航段后记录（`moved` 判定基于 missionItemIndex 前进），在首个航段停车视为"没动"，从头开始即可，语义等价。
