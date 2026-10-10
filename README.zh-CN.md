# Open-HotSpot

[English](README.md) · [العربية](README.ar.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

Open-HotSpot 是一个运行在 OpenWrt 上的本地 Captive Portal 和热点管理系统，
以 [openNDS](https://opennds.readthedocs.io/) 作为门户与流量执行引擎，并通过 LuCI 管理。

> **状态：生产前验收候选版本。** 当前实现和自动化测试已经较为完整，但真实路由器的验收门仍未全部关闭。`1.2.0-r112` 不能在现场证据完成前作为生产基线。

## 项目理念

Open-HotSpot 将身份、策略、计费和管理保留在 OpenWrt 路由器本地；openNDS
负责 Captive Portal 和流量执行。不依赖 RADIUS、云服务或外部数据库，适合小型热点网络和可控的本地部署。

## 功能概览

| 能力 | 说明 |
|---|---|
| 账户 | 本地用户名与 PIN |
| 设备 | 一个账户可绑定多个设备，并支持安全的生命周期管理与重新分配 |
| 兑换券 | 一次性、事务化兑换 |
| 配置文件 | 时间、周期、上下行速率、流量和设备数限制 |
| 配额 | 按周期累计使用量，并在预算耗尽后拒绝新的访问 |
| 仪表盘 | 将 openNDS 实时状态与 SQLite 历史结合 |
| 管理界面 | 原生 LuCI / RPC 管理 |
| 门户模板 | 本地安装的阿拉伯语 RTL 与英语模板 |

## 工作流程

```text
客户端 → openNDS 门户 → 本地 FAS → 账户/PIN 校验 → SQLite
                         ↓
                 openNDS 授权与流量执行
                         ↓
                 BinAuth 事件 → SQLite 使用量记录
                         ↓
                      LuCI / RPC
```

边界是有意设计的：openNDS 保持为策略执行引擎，Open-HotSpot 负责本地身份、策略、计费和管理。BinAuth 是事件驱动的，不调用 `ndsctl`。

## 仓库结构

```text
starter-kit/   安装到路由器的 LuCI 与运行时文件
tools/         构建、校验、设置、诊断与受控部署工具
tests/         Python 测试、Shell 合约与集成测试
docs/          真相源、架构、验收、运行手册与历史档案
specs/         需求、决策、计划与任务
```

## 当前候选版本

```text
Router:       Linksys EA8300
OpenWrt:      25.12.5
Target:       ipq40xx/generic
openNDS:      11.0.0
Open-HotSpot: 1.2.0-r112 — 已安装候选；硬件验收仍为 Pending Hardware Validation
```

当前构建和状态以 [`docs/source-of-truth.md`](docs/source-of-truth.md) 为准；r60 与 openNDS 10.3.1-r3 保留为回滚基线。

## 界面导览

以下图片展示管理界面，不是现场验收证据，也不代表生产发布。

| 仪表盘 | 配置文件 |
|---|---|
| ![Open-HotSpot 仪表盘](docs/screenshots/dashboard.png) | ![Open-HotSpot 配置文件](docs/screenshots/profiles.png) |
| 账户、会话、配额和速率概览。 | 时间、流量、速率、周期和设备限制。 |

| 账户 | 设备 |
|---|---|
| ![Open-HotSpot 账户](docs/screenshots/accounts.png) | ![Open-HotSpot 设备](docs/screenshots/devices.png) |
| 身份、配置文件、状态和到期时间。 | 所有权、生命周期、会话和重新分配。 |

| 门户模板 |
|---|
| ![Open-HotSpot 门户模板](docs/screenshots/portal-templates.png) |
| 选择本地安装的门户语言，不从外部 URL 下载模板。 |

## 已完成与待完成

| 领域 | 状态 |
|---|---|
| 数据库、配额、兑换券与领域约束 | 本地 Tested |
| Portal → FAS → openNDS → BinAuth 主路径 | 在目标路径 Verified |
| 计数方向与原生配额截断 | Pending Hardware Validation — T006 |
| 重启、恢复与故障隔离 | 部分完成 — T011/T086 |
| 中断设置后的可重复恢复 | 未完成 — T052/T087 |
| 生产基线 | 等待 T090，当前阻止发布 |

## 欢迎贡献

- 在真实客户端上完成 T006 的上下行计数与配额截断测量。
- 完成 T011/T086 的重启、恢复、重复 callback 和故障隔离验证。
- 在干净目标上完成 T052/T087 的中断设置与恢复测试。
- 完成 T088/T090 和发布验收矩阵。
- 实现并现场验证 Family Captive Boundary 1/2；当前 OP-203 合约只证明标识符不冲突，不证明 daemon、FAS、计费或 nftables 隔离。

请先阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)、[`项目状态`](docs/project-status.md) 和 [`发布门`](docs/release-gates.md)。不要把 mock、截图或本地合约测试当作硬件验收。

## 许可证

本软件采用 [GPL-2.0-or-later](LICENSE) 许可证。
