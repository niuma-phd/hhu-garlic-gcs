# 地面站控制流程简化方案（草案 v0.1，2026-10-11）

> 执行分支：`simplify-work-flow`（基于 `hhu`）。本文件是新会话执行时的任务书，改动前先通读。
> 背景：车端已切换到《Nav ↔ VCU CAN 通讯协议 v1.0》（Nav 直连 VCU，遥控器经 FCU 授权）。
> 仓库现状文件（`hhu` 分支）：`HHUWorkPanel.qml`、`HHUStatusBar.qml`、`HHUStatus.qml`、`HHUAlarms.qml`、`HHUVcuStatus.cc/h`、`hhu_config.json`、`hhu_custom_zh_CN.ts`。

## 0. 新架构对地面站的约束

车辆行动有两个 GCS 管不着的闸门，都在**遥控器**上：

1. **授权**：遥控器"切无人" → FCU 发 SwapCmd → VCU 握手后 OpSource=2（Nav 才发 Nav_Cmd）；
2. **启动**：遥控器 Ready 0→1 **新边沿** → VCU 进 RUN（Nav_Cmd 才进执行链）。

GCS 的"开始作业"（解锁+AUTO）只是第三级。**操作员在 GCS 上点了开始，车不动，原因可能在遥控器**——这是简化要解决的核心体验问题。

## 1. 协议适配结论（先做这个，量很小）

GCS 与车端的接口是 5 个 `VCU_*` NAMED_VALUE_FLOAT + STATUSTEXT，新脚本全部保留，**C++/QML 逻辑不用改**（`VCU_MODE` 界面代码没有消费，语义从"0 手动/2 自动"变为"1 遥控/2 无人"无影响）。

只需改 `hhu_config.json`（免编译，重启生效）：

**statusText 新增：**

| prefix | text |
|---|---|
| `VCU: NavSta lost` | 底盘状态广播丢失，通信中断 |
| `VCU: not authorized` | 底盘未授权，请用遥控器切换无人模式 |
| `VCU: failsafe` | 底盘已进入故障保护 |
| `VCU: wait RC start` | 已授权，请按遥控器启动键 |
| `VCU: handover failed` | 无人切换失败，请重新切换 |
| `VCU: RC link lost` | 遥控器链路丢失，车辆停车等待恢复 |
| `VCU: CAN bridge loaded (Nav v1.0)` | 底盘通信桥已启动 |

**statusText 淘汰（旧脚本消息，不再发送，留着无害可一并清）：** `VCU: not in auto`、`VCU: estop`。

**preArm 新增：** `VCU: NavSta lost`（底盘通信中断）、`VCU: not authorized`（底盘未授权，请用遥控器切换无人模式）、`VCU: failsafe`（底盘故障保护中）。

**faultCodes 预填（协议已定义部分，编码见 vcu_can.lua 5Hz 上报）：**

| 码 | 含义 |
|---|---|
| 0x01~0x07 | Sys_Fault：急停 / 链路断 / FCU 超时 / 电池低温 / 电池高温 / 电量低 / 提升超时 |
| 0x11~0x16 | HsErr（0x10+码）：Nav 无响应 / Nav 自检故障 / 停稳超时 / Nav_Cmd 断链 / 遥控链断 / 未授权帧溢出 |
| 0x100+ | 驱动器故障码（0x100+码），**码表等甲方提供后补** |

## 2. 现状流程（HHUWorkPanel.qml）

状态 × 按钮矩阵：

| 状态 | 按钮 |
|---|---|
| 未连接 | [连接车辆] |
| 待机（未解锁非 AUTO） | [开始作业]，不满足时弹原因卡：无航线 / 无围栏 / RTK 未固定 / 底盘故障（各带"去处理"） |
| 作业中 | [暂停] [返回起点] ｜ [停车上锁] |
| 已暂停 | [继续] [返回起点] ｜ [停车上锁] |
| 返回中 / 去目标点 | [暂停] ｜ [停车上锁] |

- 开始作业：`startDialog`（断点续作选起点）→ `setCurrentMissionSequence` + `startMission`（解锁+AUTO 一步）→ `_expect` 等 `armed && inAuto`，超时弹"指令未执行 / 重新发送"。
- 暂停 = 切 HOLD；继续 = 切回 AUTO；返回起点 = SmartRTL（3s fallback RTL）；停车上锁 = HOLD + 600ms 后 disarm。

## 3. 问题点

1. **"车为什么不动"不可见**：授权/启动闸门在遥控器，GCS 点开始作业只会解锁失败（`PreArm: VCU: not authorized`），失败原因埋在消息列表里。
2. **状态标签缺两态**：现有 待机/作业中/暂停/返回中/手动/底盘未就绪，看不出"未授权（去找遥控器）"和"已授权待启动（按遥控器）"。
3. **前提检查分散**：`_startBlocked` 卡、`prearmError`、`startDialog` 三处，操作员要在三个地方找原因。
4. **开始/继续是两个入口**，本质都是"解锁+AUTO 跑航线"，可以合一。

## 4. 简化设计

**操作员视角只剩三个动作：[开始/继续作业] [返回起点] [停车上锁]。**

### 4.1 派生状态（HHUStatus.qml）

新增：

```qml
readonly property bool  vcuAuthorized: vcuValid && hhuVcu.mode === 2   // OpSource=2
```

（如需要区分"已授权待启动"，需车端脚本加发 `VCU_HS`（NavSta.HandoverState），属固件侧小改，列为可选项 §6。）

### 4.2 阻塞卡扩充（HHUWorkPanel.qml `_startBlocked`）

在最前面加两条（顺序 = 操作员处理顺序）：

```text
if (status.vcuValid && !status.vcuAuthorized)  →  "请用遥控器切换到无人模式"
if (status.vcuValid && status.vcuAuthorized && !hhuVcu.ok) → "底盘未就绪，看消息列表"
```

### 4.3 状态标签（HHUStatusBar.qml `_work`）

未解锁分支细化：

| 条件 | 标签 | 配色 |
|---|---|---|
| 未解锁 && vcuValid && !authorized | 未授权 | 灰（引导去遥控器） |
| 未解锁 && authorized && ok | 就绪 | 蓝（可按遥控器启动） |
| 未解锁 && （其它） | 待机 / 底盘未就绪 | 维持现状 |

### 4.4 按钮合并（HHUWorkPanel.qml）

- **[开始作业] 与 [继续] 合一**：`_startWork` 和 `_continue` 统一为一个入口 `_startOrContinue`：
  - 未解锁 → 走 startDialog + startMission 全流程；
  - 已解锁暂停中 → 直接切 AUTO；
  - 按钮文案按态显示"开始作业"/"继续作业"，逻辑共用 `_expect` 确认。
- **[暂停] 保留**（任务暂停语义仍需要），但说明文档写明：遥控器随时可接管，GCS 暂停不冲突。
- [返回起点]、[停车上锁] 不动；SmartRTL 3s fallback、disarmTimer、断点续作（hhuWork.resumeWaypoint）逻辑全部保留。

### 4.5 失败引导

"指令未执行"弹窗（failDialog）正文直接带翻译后的 `prearmError`（现状已带原文，确认 hhu_config 翻译链覆盖 §1 新词条即可）。

## 5. 涉及文件清单

| 文件 | 改动 |
|---|---|
| `hhu_config.json` | §1 词条 + faultCodes（无代码） |
| `HHUStatus.qml` | 加 `vcuAuthorized` 派生态 |
| `HHUStatusBar.qml` | `_work` 加"未授权/就绪"两态 |
| `HHUWorkPanel.qml` | `_startBlocked` 加授权检查；开始/继续合并 |
| `hhu_custom_zh_CN.ts` | 新词条翻译（`lupdate` 生成后补译） |
| （可选）车端 `vcu_can.lua` | 加发 `VCU_HS`，跨仓库，单独评审 |

## 6. 待确认 / 风险

1. **需求说明 V1.0 是合同附件**：按钮文案与流程变更要给甲方过目（变化其实不大：按钮从 4 个收敛到 3 个，状态标签多两个）。
2. `VCU_HS`（区分"已授权待启动"）要不要做：做则操作员引导更准，代价是动固件脚本；不做则"就绪"态就够了。**建议先不做**，联调后看操作员反馈。
3. `routeDone`、`inAuto` 等派生态依赖 `flightMode` 字符串比较，改按钮逻辑时勿动。
4. 构建环境：QGC 定制版，Qt 6.8+，参照仓库 `AGENTS.md`/`CLAUDE.md` 的构建说明；改完至少过 `qmllint`。

## 7. 执行步骤（新会话）

1. 从 `simplify-work-flow` 分支检出（基于 `hhu`）；
2. §1 `hhu_config.json` 词条（可立即做，faultCodes 0x100+ 留空待甲方）；
3. §4.1 → §4.2 → §4.3 → §4.4 按序改 QML；
4. `lupdate` 更新 ts，补中文翻译；
5. 构建 + 连接模拟器（或台架飞控）验证三态按钮与标签；
6. 提交、推送、告知用户验收点。
