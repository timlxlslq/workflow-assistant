# `scan-server` 实际运行追踪（2026-08-14）

本次执行的是项目后端 `scan_server_changes(config)`，未处理待处理变化、未生成 Traveler、未出库。为记录细节，使用临时运行追踪包装器记录了目录枚举、递归 Excel 文件发现、文件属性读取和 SQLite SQL；没有修改业务代码。

## 总结果

- 总耗时：10.229 秒
- Server 根目录：`/Volumes/server/Optimized Orders`
- 同时检查：`/Volumes/server/CUT TO SIZE`
- 订单文件夹：14 个
- 相关 Excel：112 个唯一文件（Fittingslist 50、板材清单 50、material 12）
- 新增：0；修改：0；删除：0
- 本次没有打开 Excel 内容。扫描只递归查找 `.xlsx`，再读取路径的修改时间和文件大小进行比对。
- 本次没有新增或更新当前订单索引记录；只执行了历史临时目录清理：删除 7 个旧目录对应的 `source_files` 记录，并将对应 `active_issues` 标记为 resolved。

## 文件夹扫描耗时

耗时是递归查找该文件夹下 `.xlsx` 的耗时；实际比对的文件会排除 `~$` 临时文件和不属于三类业务报表的 Excel。

| 文件夹 | 找到 `.xlsx` | 递归查找耗时 |
|---|---:|---:|
| `Optimized Orders/CS003 PP0047` | 0 | 0.375 秒 |
| `Optimized Orders/mario extracabinets` | 7 | 0.669 秒 |
| `Optimized Orders/pp0046` | 7 | 0.823 秒 |
| `Optimized Orders/pp0035-2` | 19 | 1.570 秒 |
| `Optimized Orders/pp0065` | 7 | 0.968 秒 |
| `Optimized Orders/pp0067` | 7 | 0.480 秒 |
| `Optimized Orders/pp0063-2` | 32 | 2.760 秒 |
| `Optimized Orders/pp0068` | 7 | 0.748 秒 |
| `CUT TO SIZE/cs001` | 7 | 0.463 秒 |
| `CUT TO SIZE/cs002` | 0 | 0.421 秒 |
| `CUT TO SIZE/cs004` | 7 | 0.598 秒 |
| `CUT TO SIZE/cs003` | 7 | 0.670 秒 |
| `CUT TO SIZE/cs005` | 6 | 0.491 秒 |
| `Optimized Orders/pp0047` | 128 | 6.398 秒 |
| `Optimized Orders/pp0035` | 76 | 8.845 秒 |

`rglob` 找到的数量包含少量 `~$` 临时文件；最终实际纳入元数据比对的是 112 个唯一业务 Excel。完整的逐事件记录（包含 660 条事件、每个文件路径和时间）保存在本次运行的临时文件：`/private/tmp/scan-server-trace.jsonl`。

## SQLite 写入

写入集中发生在开始阶段的历史临时目录清理，涉及以下目录：

- `BLACKSMDOORS`
- `b12`
- `b18 2cabinets`
- `pp001`
- `pp0011bathroompanels`
- `pp0016 GLENDALE`
- `pp006`

每个目录执行两类 SQL：删除 `source_files` 中该目录及其子路径记录；将 `active_issues` 中该路径的开放问题更新为 `resolved`。扫描结果本身没有发现变化，所以没有写入新增、修改或删除的 Server 文件记录。
