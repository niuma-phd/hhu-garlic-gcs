# 河海大学 大蒜播种车地面站（HHU-GCS）

基于 [QGroundControl](https://github.com/mavlink/qgroundcontrol) **v5.1.4** 的定制版地面站，用于阿克曼转向的无人驾驶大蒜播种车（飞控 ArduPilot Rover 4.7.1，底盘 VCU 经 CAN 由 Lua 脚本桥接）。需求见《地面站开发需求说明 V1.0》。

本仓库是 QGC 的 fork，所有改动在 `hhu` 分支，基于 tag `v5.1.4`：

- `custom/`：QGC 官方定制机制（`CustomPlugin`、QML 覆盖、`custom.qrc`），绝大部分改动在这里；
- `src/` 下对 QGC 原版的少量修改（每处一个 commit，汇总见 `custom/patches/upstream.patch`，升级 QGC 时重新打）：
  1. 天地图 18 级以上拉伸显示、地图最大缩放 22 级；
  2. 航线速度（`DO_CHANGE_SPEED`）对车辆开放；
  3. `QGCRadioButton` 字体 bug（上游把字号当字体名）；
  4. 天地图矢量底图、注记图层（卫星 + 注记）；
  5. `cmake/modules/Git.cmake` 取 QGC 版本号时排除产品发布 tag `hhu-*`。

## 功能概览

| 页面 | 内容 |
|---|---|
| 作业 | 蓝色状态栏（连接 / 定位 / 模式 / 电量 / 底盘 / 消息）、作业按钮（开始 / 暂停 / 继续 / 返回 / 停车上锁，滑动确认，指令超时提示）、断点续作、开到指定点（长按 / 右键地图）、告警横幅 + 声音、断线最后位置、任务进度 |
| 航线 | 只保留航点和电子围栏、地块管理、以车辆位置打点、上传前检查（急弯标红、航点上限、离车距离、围栏）、汇总与地块面积 |
| 作业记录 | 每次作业自动记录，按日期 / 车辆 / 地块筛选，导出 Excel（CSV） |
| 设置 | 通用（语言、单位、字号、高对比度、地图注记）、通信连接（串口 / UDP / TCP / 蓝牙 + 4G）、地图、RTK 差分、高级（超时、告警阈值、日志上传）、关于（版本、检查更新） |

车端提示翻译、PreArm 原因、VCU 故障码、差分服务商预设放在 `res/config/hhu_config.json`，安装后位于 `bin/config/hhu_config.json`，改完重启生效。

**程序不内置天地图 Key**：安装后在 设置 → 地图 填写天地图 **浏览器端** Key（服务端 Key 无法下载图片）。

## 目录

| 路径 | 内容 |
|---|---|
| `src/CustomPlugin.*` | 插件入口：品牌、默认设置、STATUSTEXT 翻译、各服务对象注册到 QML |
| `src/HHU*.{h,cc}` | VCU 状态、链路监测（延迟 / 流量）、配置表、设置、4G 连接、差分账号、地块、作业记录、更新与日志上传、密码加密（DPAPI） |
| `src/qml/HHU/Controls/` | 自有 QML 组件（模块 `HHU.Controls`） |
| `src/qml/settings/` | 设置页（替换 / 新增） |
| `src/qml/generated/` | 由 `tools/gen_overrides.py` 从上游 QML 打补丁生成，**不要手改** |
| `translations/`、`res/i18n/` | 中文翻译覆盖层及编译结果（`tools/i18n.py`） |
| `tools/` | `gen_overrides.py`、`trim_settings_pages.py`、`i18n.py`、`mock_server.py`（4G 中转 / 更新 / 日志上传 / NTRIP 的测试服务器） |

## 编译（Windows）

Qt 6.11.1（msvc2022_64）、VS 2022 Build Tools、CMake ≥ 3.25、Ninja：

```bat
cmake -G Ninja -S . -B build -DCMAKE_BUILD_TYPE=Release -DQGC_ENABLE_GST_VIDEOSTREAMING=OFF
cmake --build build --config Release
cmake --install build --config Release   :: 生成 NSIS 安装包（需安装 NSIS）
```

QGC 发现 `custom/` 目录会自动启用定制版（程序名 HHU-GCS）。

CI：`.github/workflows/hhu-windows.yml`，推送 `hhu` 分支时编译并上传安装包；推送 `hhu-v*` tag（如 `hhu-v1.0.0`，与 `custom/CMakeLists.txt` 的 `HHU_APP_VERSION` 一致）时发布 Release。`v*` tag 是 QGC 自己的版本，`cmake/modules/Git.cmake` 取版本号时排除 `hhu-*`。

## 升级 QGC 版本

1. rebase `hhu` 分支到新的上游 tag，解决 `src/` 下的 4 个 commit 冲突；
2. `python custom/tools/gen_overrides.py`（锚点不匹配会报错，逐个检查）；
3. 编译一次后 `python custom/tools/trim_settings_pages.py <build>/qml/QGroundControl/AppSettings/SettingsPagesModel.qml`；
4. `python custom/tools/i18n.py lupdate && python custom/tools/i18n.py build`，补齐新增的未翻译条目。

## 说明

- 按功能拆分的 commit 便于阅读，中间的 commit 不保证能单独编译，完整可编译状态以分支最新提交为准。
- 4G 连接、日志上传的服务器协议见 `src/HHU4GLink.h`、`src/HHUService.h`（日志上传的分片协议为提议，需与服务器方确认）。
- 许可证随 QGroundControl（Apache 2.0 / GPLv3 双许可）。校徽等品牌素材版权归河海大学。
