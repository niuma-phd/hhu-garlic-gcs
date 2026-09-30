# 汉化术语表（客户版，农机语境）

面向农户 / 农机手：用"车辆"语境，不用航空词（飞行、起飞、降落、无人机、机体）。

| 英文 | 译文 | 备注 |
|---|---|---|
| Vehicle | 车辆 | 不译"飞机/无人机/载具" |
| Fly / Fly View | 作业 / 作业页 | |
| Plan / Plan View | 航线 / 航线页 | |
| Mission | 航线（任务） | 上传/下载语境用"航线" |
| Waypoint | 航点 | |
| Home / Launch | 起点 | |
| Arm / Disarm | 解锁 / 上锁 | |
| Flight mode | 模式 | |
| Hold | 暂停 | 车端模式名 |
| RTL / Return | 返回 | Smart RTL = 智能返回 |
| Takeoff / Land | 起步 / 停车 | 客户界面已隐藏，保持可读即可 |
| Altitude | 高度 | |
| Ground speed | 车速 | |
| Heading | 航向 | |
| Link / Comm Links | 连接 / 通信连接 | |
| Telemetry radio / SiK | 数传电台 | |
| Offline maps | 离线地图 | |
| Tile | 瓦片 | |
| Token | 密钥（Key） | |
| Provider | 地图源 | |
| RTK fixed / float | RTK 固定解 / 浮点解 | |
| Mountpoint | 挂载点 | |
| Caster | 差分服务器 | |
| Parameter | 参数 | |
| Ground station / GCS | 地面站 | |

规则：
- 占位符 `%1` `%2` … 原样保留，数量一致。
- JSON 里的枚举列表（如 `Indoor,Outdoor`）必须保留英文逗号，项数一致（上游 4.4.3 中文版因用了"，"导致无法添加航点）。
- HTML 标签原样保留。
