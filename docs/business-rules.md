# 业务逻辑与流程表

## 文件分工

本文件是给人阅读和确认的业务规范，用于记录规则原因、处理顺序、异常政策及人工决策。它不是程序输入，避免因为 Markdown 的措辞或排版变化直接改变生产行为。

以下可量化规则以 `config/business-rules.json` 为程序执行来源：

- Plywood、Panel厚度及标准尺寸
- AICNC厚度别名
- materials列和厚度的换算
- 五金代码、Traveler名称和单位
- 封边保留小数位数

修改上述量化规则时，应直接修改JSON并运行测试，同时更新本文件的说明。复杂配对、停止条件、备份和冲突处理仍由代码执行；修改本文件后可要求Codex根据差异同步代码及测试。

## 1. 路径与运行环境

| 项目 | 规则 |
|---|---|
| 公司 Wi-Fi | `SpectrumSetup-7C81` |
| SMB 地址 | `smb://GUEST:@server/G` |
| 当前测试来源目录 | `~/Downloads`（暂时代替服务器目录，可在设置中恢复） |
| Traveler 目标 | `~/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Order` |
| 模板 | `~/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/模版/Work Order Traveler().xlsx` |
| 备份目录 | `~/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Work Order Traveler Backups` |

## 2. 报表识别与配对

| 项目 | 规则 |
|---|---|
| 新订单范围 | 仅处理名称中可识别 `PP` + 四位数字的订单；三位历史订单及启用前旧报表忽略 |
| 初始扫描日期 | 可在设置中修改，默认 `2026-07-22`；普通扫描处理当天 00:00 以后修改的目标报表 |
| 板材文件名 | `pp-板材清单-newPC<生产批次号>.xlsx` |
| 五金文件名 | `FittingslistPC<生产批次号>.xlsx` |
| 配对字段 | 板材清单 `B2` 与五金清单 `C3` 的 `F...` 工厂单号 |
| Traveler 名称 | 板材清单 `G2` 的 PP 订单名称原样写入括号 |
| 同目录要求 | 一对报表必须位于同一个 `Report` 文件夹 |
| 重复工厂单 | 选择板材清单服务器修改时间较新的完整报表组，并提醒旧组 |
| 映射冲突 | 相同 F 对应不同 PP，或相同 PP 对应不同 F，停止并提醒 |
| 多工厂单五金表 | 同一五金表有多个 F、板材表只有其中一个时，只生成一份；文件名括号内使用源文件夹名 |
| 合并名称 | 登录 AIMES 查询每个 F 的工厂单名称，按五金表出现顺序用 `/` 连接后写入 B5 |
| AIMES 重试 | 仅多工厂单异常触发；失败后约 30 秒、60 秒重试，共三次，仍失败停止并提醒 |
| AIMES 登录 | 直接进入 3VJ Passport 官方登录页；真实进入 AIMES dashboard 后才算成功。账号或密码错误立即停止，避免重复尝试导致锁定 |

### 来料加工订单

- 服务器来源为 `/Volumes/server/CUT TO SIZE`，只列出 `CS` + 三位数字的文件夹。
- 每个订单只读取根目录文件名包含 `materials` 的 `.xlsx`；缺失时停止并明确提示。
- 来料加工不读取五金报表，Traveler 保留空的 `Pickinglist`，只写入板材和封边。
- 输出位置与自有订单一致：`Order/CS###/Work Order Traveler(CS###).xlsx`。
- 所有订单的服务器五金报表 `code` 都不是库存 SKU，不写入 Traveler 的 `SKU NO.`。

## 3. 板材与封边

| 类别 | 规则 |
|---|---|
| 数量来源 | 只读取“大板统计”数量 |
| Plywood | `18mm`、`14.5mm`、`5.4mm`；AICNC 的 `5mm` 按 `5.4mm` 处理 |
| Panel | `19.1mm` 门板；`8mm/9mm` 背板 |
| 标准规格 | Plywood `2440×1220`；Panel `2745×1220` |
| leftover | 比标准尺寸小超过 100mm 时不计入 |
| 可疑尺寸 | 与标准尺寸差 1–100mm、尺寸大于标准或无法识别时停止并提醒 |
| 封边来源 | 只读取“封边统计”，按颜色汇总，四舍五入两位 |
| 无 Panel | 无封边属正常；Edge banding 行保留且数量留空 |
| 首页颜色 | Panel 只有一种颜色时 Door/Body 都写该颜色，否则留空 |
| PP materials | PP 目录如有 `PP#### materials.xlsx`，与所有子文件夹板材及封边合计核对 |
| materials Plywood | 上方 Total Qty：3/4=`18mm`、5/8=`14.5mm`、1/4=`5.4mm` |
| materials Panel | 下方 Color Table：3/4=`19.1mm`、1/4=`9mm`（8/9mm 背板类别） |
| 半张规则 | materials 数量含 `.5` 时向上取整为整张 |
| 核对一致 | 多工厂单合并 Traveler 的板材、Panel 和封边数量以 materials 为准 |
| 核对不一致 | 视为 materials 制作错误；继续以 AICNC 原报表生成，完成后提醒并列出两套汇总差异 |

## 4. 五金

| 源代码/名称 | Traveler 名称 | 计算 |
|---|---|---|
| `WJ-CBT` | Shelf Holder | 原数量 |
| `71T950A` | Hinge | 原数量 |
| `H-Rail` | H-Rail | Left/Right 必须相等，只取一边，单位 set |
| `L-Rail` | L-Rail | Lower Left/Right 必须相等，只取一边，单位 set |
| 其他 | 不写入 | 首次出现或发生变化时提醒 |

多工厂单五金表中的所有区块先合并数量；轨道仍分别汇总 Left/Right，确认相等后只取一边。

## 5. 写入、更新与安全

| 场景 | 行为 |
|---|---|
| 新工厂单 | 校验通过后自动创建 `Order/PP####` 及 Traveler |
| 已有 Traveler 无变化 | 不操作 |
| 已有 Traveler 有变化 | 只显示差异，等待选择“更新自动字段”或“按模板重建” |
| 更新前 | 强制备份到专用备份目录，不放在当前订单目录 |
| 写入方式 | 临时目录生成并复查，通过后原子写入；绝不直接覆盖同名文件 |
| 模板变化 | 暂停新建/重建并提醒确认新模板基准 |
| 日期 | 当天日期，格式 `年.月.日` |

## 6. 运行与提醒

| 项目 | 规则 |
|---|---|
| 启动方式 | 只允许用户手工打开应用并选择预览、查询、扫描或更新，不再后台定时运行 |
| 网络门槛 | 手工运行要求服务器可访问；程序开始前仍执行服务器和AIMES前置检查 |
| 任务前置检查 | 每次任务最先确认服务器目录可读且 AIMES 首页可打开；任一失败均不开始后续处理 |
| 重试 | 手工任务内的AIMES多工厂单查询保留既定重试；服务器或iCloud失败立即显示在界面，由用户决定何时重试 |
| 无变化 | 不发送系统通知，只记日志 |
| 备份清理 | 已取消三个月前备份的月底清理提醒；现有备份继续保留，除非用户另行要求清理 |
| 日志 | 保留一年；超过一年提醒清理；达到 100MB 提醒 |

设置界面允许修改初始扫描日期、公司 Wi-Fi、服务器目录、订单目录、模板、备份目录、尺寸容差及 AIMES 用户名；AIMES 密码只保存在 macOS 钥匙串。

任务界面实时保留本次运行时间线，包括服务器与 AIMES 前置检查、发现的 PP/源文件夹、报表读取、AIMES 查询、核对、生成、跳过和异常结果。

## 7. 主流程

```text
启动扫描
  → 检查运行模式、日期和 Wi-Fi
  → 挂载/检查服务器
  → 发现启用时间后的候选报表
  → 校验文件名及工作表结构
  → 读取 F 工厂单号与 PP 订单名称
  → 在同一 Report 目录内配对
  → 处理重复项与冲突
  → 校验板材、规格、封边和五金
  → 查找既有 Traveler
      ├─ 不存在：安全生成
      ├─ 存在且相同：记录无变化
      └─ 存在且不同：显示差异，等待人工决定
  → 保存日志并按需通知
```

## 8. 新版按订单生成 Traveler

旧版扫描与更新逻辑继续保留为备用入口。新版默认流程如下：

1. 只读取服务器根目录下名称完全符合 `PP####`、`PP####-数字` 或 `CS###` 的文件夹并显示；点击前不读取 Excel。
2. 点击订单后，在订单根目录寻找唯一一个文件名包含 `materials` 的 `.xlsx`，忽略 `~$` 临时文件。
3. materials 中 Plywood 读取 `Total Qty:` 行；多颜色 Panel/封边读取 Color Table，单颜色且 Color Table 为空时回退读取 `Total Qty:` 行的 Finish Panel、Edge Banding 和 Color。
4. `Khaki`、`Khaki (7x9)` 在预览中统一显示为正式名称 `Penelope FA44`，插入 Traveler 的原始 materials 工作簿不改内容。
5. Plywood、19.1mm Panel 和 8/9mm 背板数量必须为非负整数；1/4 Finish Panel 在预览中显示为 8mm。任何小数均停止。
6. 只要某个有 Panel 数量的颜色封边为空、为 0 或为负数，整单停止。
7. 遍历所有板材清单，按“订 单 号”和“订单名称”右侧单元格建立工厂单名称映射。缺失名称先读本机缓存，再查询 AIMES；查询成功后写入本机应用状态缓存。
8. 遍历所有 `Fittingslist*.xlsx`。同一工厂单重复且内容不同时采用修改时间唯一最新的文件，并在操作记录提示；最高修改时间并列且内容不同时停止。
9. 五金忽略偏好按标准化后的名称、Code、Size、Unit 全局保存，对所有订单默认生效；预览中灰显并允许恢复。
10. 校验通过后，一个订单只生成 `Order/<订单号>/Work Order Traveler(<订单号>).xlsx`。已有同名文件不覆盖。
11. 原始 materials 的唯一工作簿原样复制到 `WorkOrderTraveler` 后；不再把板材和封边写入 `WorkOrderTraveler` 或 `Pickinglist`。
12. `Pickinglist` 删除旧 Panel 区域，每个工厂单向下复制一套“工厂单名称、Fitting、Hardware Accessory”区块，只写未忽略五金。
