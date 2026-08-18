# 系统架构

## 运行链路

```text
文字 / 语音
    ↓
SwiftUI App
    ↓
本地命令解析器 ── 命中 ──→ Typed Tool Gateway
    │                              ↓
    └─ 未命中 → Agents SDK 结构化路由 ──→ Typed Tool Gateway
                                             ↓
                                      本地审批状态机
                                   ↓
                         Python / CLI 业务引擎
                                   ↓
                   Excel / SMB / Playwright / SQLite
```

## 分层职责

| 层 | 责任 | 不负责 |
|---|---|---|
| App | 交互、语音转文字、预览、确认、队列 | 解析 Excel 业务规则 |
| 本地解析器 | 将常用语句转为类型化请求 | 写真实系统 |
| Agent | 模糊表达理解、路由、解释 | 直接读写 Excel/SMB/库存 |
| Skill | 域内步骤、规则和引用 | 重复 Python 代码 |
| Gateway | 工具白名单、参数校验、审批边界 | 业务计算 |
| Python 引擎 | 确定性解析、计算、写入和复查 | 自然语言决策 |
| SQLite | 订单索引、商品主资料、审批、任务、审计、Token 用量 | 密码和登录状态 |

运行数据统一保存在 `~/Documents/pp-flowhub/data/`，该目录在 Git 中整体忽略。

## 设计约束

- 只保留一份现行数据契约；商品库首次运行可从既有 XLSX 一次性导入，之后不以 XLSX 作为查询源。
- 常用命令零 Token；Agent 当前只接收用户语句和一份精简动作契约，不接收订单文件或业务数据。
- Agent 使用 `gpt-5.6-luna`、低推理强度、单轮结构化输出；真实审批权限由 Gateway 根据动作重新计算。
- Agent 成功识别的表达按完全相同的规范化文本写入 SQLite；下次直接本地路由，不扩展成模糊通用规则。
- 商品主资料单独保存在 `data/workflow.sqlite3 的 products 表`；每次从库存系统导出 XLSX 后先校验，再事务替换商品表。`data/inventory/current-products.xlsx` 只保留最新一份原始导出备份，运行时查询不依赖 XLSX。
- App 使用单一串行任务队列并显示排队、执行、等待确认、写入和完成状态。排队、读取和等待确认阶段可以取消；文件或库存真实写入开始后不可取消。
- API Key 当前保存在 Git 忽略的 `.env.local`，不进入源码、SQLite 或日志；正式分发前再迁入 Keychain。
- 库存系统密码由 SwiftUI 通过 Security Framework 写入 macOS 登录钥匙串，CLI/Python 通过同项目编译的 `keychain-read` 辅助程序读取；不调用 `/usr/bin/security`，不保存明文或兼容回退。
- Traveler 商品映射预检通过后，App 可直接调用只读库存查询；默认仅查询板材和封边，仓库留空，空表按库存 0 处理。该路径不经过 Agent，也不需要审批。
- App 默认进入助手页，使用单一左侧领域导航切换生产文件、出库、待办和设置。页面共享布局与控件尺寸常量，不为不同页面维护独立视觉规则。
