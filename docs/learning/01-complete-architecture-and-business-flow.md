# PP FlowHub：完整技术架构与业务流程

本文面向第一次接触项目的开发者，说明从 macOS 页面操作到 Python 业务结果的完整调用链。每次修改业务流程时，应同步更新本文件对应章节。

## 1. 分层结构

```text
SwiftUI 页面
  -> AppModel（状态、Process、操作记录）
  -> scripts/pp-flowhub（命令入口）
  -> Python CLI
  -> command_router / assistant_cli（解析指令）
  -> tool_gateway（安全分发与写入审批）
  -> order_workflow / inventory（确定性业务规则）
  -> Excel、SMB 文件夹、Playwright 浏览器或本地 JSON 数据
```

页面只负责显示状态、收集输入和启动子进程；业务规则集中在 Python；写入操作先返回预览，再等待用户确认。

## 2. 项目目录与职责

| 路径 | 职责 |
|---|---|
| `macos/PPFlowHub.swift` | AppModel、顶部导航、生产文件、出库、待办、设置页面及 Process 调用 |
| `macos/AssistantView.swift` | 助手页面、语音输入、命令预览和库存比较展示 |
| `scripts/pp-flowhub` | 设置 `PYTHONPATH`，选择 Python，分发 `assistant/order/inventory` 子命令 |
| `traveler_assistant/command_router.py` | 常用中文/英文命令的零 Token 本地解析 |
| `traveler_assistant/assistant_cli.py` | 本地解析、学习缓存、Agent 路由和助手命令入口 |
| `traveler_assistant/tool_gateway.py` | Typed command 到业务函数的唯一分发点，控制审批 |
| `traveler_assistant/order_workflow.py` | 订单发现、materials、Report、Traveler 生成/更新和工厂单处理 |
| `traveler_assistant/inventory.py` | Traveler 解析、商品映射、库存预检、JDY/Playwright 出库 |
| `traveler_assistant/core.py` | `Config`、`RuleError`、Excel 五金分组、AIMES 查询和工厂名称缓存 |
| `tools/aimes_lookup.mjs` | AIMES 登录、工厂订单查询、返回工厂单号到名称 JSON |
| `resources/templates` | Traveler Excel 模板 |
| `data` | 本机状态、设置、库存缓存和工厂名称缓存；被 Git 忽略 |

## 3. 统一错误与进度协议

Python 业务错误使用 `RuleError(code, message, **context)`。CLI 将其序列化为标准输出 JSON：

```json
{"status":"failed","error":{"code":"...","message":"..."}}
```

长任务通过标准错误逐行输出：

```json
{"event":"progress","message":"正在读取服务器目录"}
```

Swift 的 `consumeOrderLogChunk` / `consumeInventoryLogChunk` 解析进度并写入当前页面的 `orderSteps` / `inventorySteps`。切换左侧文件时先清空对应数组，保证记录属于当前对象。

生产文件页顶部状态栏将订单短状态保留为单行文本；“查看或打印 Traveler”“按需生成 Traveler”“查询材料库存”集中在右对齐按钮组，详细路径和进度仍通过 `addOrderStep` 写入下方操作记录。

HSplitView 右侧订单详情区不使用固定最小宽度，而是使用 minWidth 0 / maxWidth infinity / leading 对齐，避免点击左侧文件夹后因分栏变窄导致右侧内容左边被裁切。

## 4. 生产文件流程

### 4.1 列出服务器订单

1. 用户打开生产文件页，`loadOrderFolders()` 读取 `activeOwnedSourceRoot` 或 `activeCutToSizeRoot`。
2. Swift 启动 `scripts/pp-flowhub order list --source-root <path>`。
3. `order_workflow.main()` 调用 `list_order_folders(config)`。
4. `resolve_source_root()` 确认目录可访问；`ORDER_FOLDER_RE` 只接受 `PP####`、`PP####-#`、`CS###`。
5. 返回订单号、路径、修改时间；Swift 生成左侧 `OrderFolderItem` 列表。

### 4.1.1 订单中心的 Server 扫描范围

订单中心的扫描入口不是生产文件页的全量文件夹列表。标准订单以 AIMES 为入口：

1. `sync-aimes` 获取 AIMES 最近数据；失败时保留最近一次成功的本地缓存，并由 Swift 显示醒目的失败提示。
2. `factory_orders` 保留历史 AIMES 工厂单记录；当前 AIMES 新增工厂单会立即把所属订单重新纳入 Server 扫描候选。
3. 只有 AIMES 关联的全部工厂单都明确为“已出库”时，标准订单才会跳过 Server 扫描；未出库、部分出库或状态未知都会继续扫描。
4. 非 `PP####`、`PP####-#`、`CS###` 的目录按临时任务处理：建立时间在扫描基准时间（当前为 `CS003 PP0047` 的建立时间 `2026-07-25T11:00:25-07:00`）之后的一段时间内，或从未写入 `source_files`，才自动进入扫描；业务报表递归查找 `Fittingslist`、`板材清单` 和 `material` 文件。
5. 被筛选跳过的标准订单不会触发历史问题自动关闭；`active_issues` 只有在对应文件夹确实被本次扫描后，才会按本次结果更新。

`scan-server` 只读取文件夹和业务 Excel 的轻量元数据；`sync-index` 才解析候选报表并写入 `order-index.sqlite3`。

### 4.2 预览订单

1. 点击左侧订单时，`previewOrderFolder()` 清空旧 `orderSteps` 并启动 `order preview --folder`。
2. `preview_order(config, folder)` 校验目录名称，并在根目录选择唯一的 `*material*.xlsx`。
3. `parse_order_materials()` 读取 `Total Qty:`、`Color Table`、Plywood 列和颜色行，返回 `materials` 与 `edge_banding`。板材、封边数量只来自此文件。
4. PP 订单调用 `_choose_fittings()`，递归查找 `Fittingslist*.xlsx`；`parse_fittings_groups()` 按 `Order No.` 区块读取工厂单号和五金行。
5. `_factory_names()` 先读取 `pp-板材清单*.xlsx` 的“订单号/订单名称”，再读取 `Config.factory_names_file` 本地缓存；仍缺失时调用 `lookup_aimes_names()`。
6. AIMES 成功结果原子写入 `data/factory-names.json`，下次优先使用缓存。
7. `_normalize_fittings()` 按五金 code 聚合、处理左右导轨，并应用忽略映射。
8. `preview_payload()` 返回材料、封边、工厂单号、工厂名称、五金和 warnings；Swift 显示预览。

订单隔离规则：`PP####` 与 `PP####-数字` 是两个完整、独立的订单键。工厂单名称可以用连字符或空格连接完整订单号；例如 `PP0035-OFFICE` 属于 `PP0035`，而 `PP0035-2-MASTER`、`PP0035-2 OPENSHELF` 只属于 `PP0035-2`。`assistant_cli._factory_name_belongs_to_order()` 负责 Agent 命令入口校验，`order_workflow._factory_name_belongs_to_order()` 负责生成 Traveler 前校验。基础订单后紧跟数字的名称会被拒绝，避免材料、五金和 Traveler 数据跨订单混用。

材料文件归属：`preview_order()` 发现一个订单文件夹内有多个 material Excel 时，先按完整订单号匹配文件名；唯一匹配会写入 `data/material-assignments.json`。仍无法判断时返回 `material_assignment_required` 和 `assignment_key`，人工通过 `assign-material` 命令确认后持久化，下一次不再重复询问。五金不依赖材料分配，而是从 Fittingslist 的工厂单号读取并做订单名称一致性校验。

共享文件夹筛选：`_factory_names()` 和 `preview_order()` 会按完整订单号保留当前订单的工厂单；同一文件夹中属于兄弟订单的板材清单、Fittingslist 内容会被忽略并记录提醒，不再导致当前订单无法预览。

旧 Traveler 升级：`update_order_traveler()` 只要求核心 `WorkOrderTraveler`，发现旧版本缺少 `Picking List`、`Usage List` 或使用旧名称 `Pickinglist` 时，从当前模板补齐/替换，再写入最新材料和五金格式；人工五金会尝试迁移。

共享订单处理：`related_order_ids()` 从文件夹名、板材清单、XML 和报表文件名提取完整订单号；`preview_related_orders()` 为每个订单独立调用预览，`update_related_orders()` 分别生成/更新 Traveler。material 的 `Room/section` 行由 `parse_material_room_rows()` 解析，并通过工厂单名称匹配房间后写入对应订单；`_aggregate_material_sources()` 合并多个 material 文件并标记完全重复的房间数据。

AIMES 缓存更新：设置页按钮调用 `order refresh-aimes`，后端通过 `refresh_aimes_recent_names()` 读取 AIMES 当前页 50 条工厂单名称，写入工厂名称缓存。订单预览缺少工厂名称时仍调用 `lookup_aimes_names()` 补齐。

材料整数校验：`parse_material_room_rows()` 允许单个房间的 plywood/panel 数量为小数；`_select_room_materials()` 按订单、规格和颜色汇总后才检查是否为整数，避免把合法的跨房间分摊误判为错误。

预览显示规则：panel 颜色数量使用 `_aggregate_material_sources()` 读取的 `Color Table` 汇总值；房间级行只负责确定订单归属和写入 Usage List，因此同一颜色不会在预览中重复显示。

### 4.3 生成或更新 Traveler

1. 生成/更新按钮先进入 `tool_gateway` 的 `approval_required` 分支，只返回预览。
2. 用户确认后，`generate_order_traveler()` 或 `update_order_traveler()` 读取模板并写入临时文件。
3. `_write_picking_list()` 为每个 `FactoryPreview` 写入工厂单名称和五金明细；材料和封边写入 Usage List。
4. 保存前重新打开校验，更新操作先备份旧文件，再原子替换目标文件。
5. 返回 `created/updated`、备份路径和业务摘要。

## 5. AIMES fallback 流程

`lookup_aimes_names(config, factory_orders)` 的调用顺序是：读取 `aimes_username` 设置 → 从 macOS 钥匙串读取 `com.pacificpride.ppflowhub.aimes` 密码 → 启动 `tools/aimes_lookup.mjs` → Playwright 登录 AIMES → 进入 `OMS/工厂订单` → 查询每个编号 → 读取相邻名称单元格 → 返回 JSON。AIMES helper 优先使用 `TRAVELER_BROWSER_EXECUTABLE` 或 `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`，避免只安装 Playwright 包却缺少 Chromium 缓存。失败会重试三次，并返回 `aimes_credentials` 或 `aimes_unavailable`。

AIMES 只补工厂单名称，不参与板材/封边数量计算。

## 6. 出库流程

1. `loadInventory()` 启动 `inventory list-names`，`list_travelers()` 只读取 Traveler 文件夹和文件名，返回 `InventoryTraveler`。
2. 用户点击左侧 Traveler 时，`previewSelectedInventory()` 清空旧操作记录并串行调用 `inventory preview --traveler`。
3. `parse_traveler()` 读取 Usage List、Picking List 和工厂单名称；`order_stock_requirements()` 形成材料与五金需求。
4. `InventoryMappings` 读取本地商品映射；缺失映射会显示“未映射”，阻止写入。
5. `check_stock()` 读取本地商品目录或调用 JDY Playwright，按商品编码比较 required/available/shortage。
6. 用户确认后，出库写入仍由 Python 负责；Swift 只显示进度、缺货警告和最终结果。

## 7. 助手命令流程

1. Swift `runAssistantCommand()` 启动 `assistant_cli`。
2. `parse_local_command()` 先解析常见命令；成功则 0 Token 进入 `execute_local_command()`。
3. 解析失败时 `RuntimeStore` 查精确短语缓存；仍失败才调用 `agent_runner.route_with_agent()`。
4. Agent 结果会经过订单号、工厂名称、SKU、数量和审批校验，随后仍进入同一个 `tool_gateway`。
5. 写入类命令第一次只返回 `approval_required`；确认后通过同一命令加 `--approve` 执行。
6. Swift 根据 `status/result_type/error` 更新预览、库存表格、任务状态和 Token 统计。

## 8. 待办与设置数据

- 待办由 Swift `TodoItem` 管理，保存到 `data/todo-items.json`，使用原子写入。
- 设置由 `AppModel.loadSettings/saveSettings` 管理，正式数据源只保留服务器、Traveler 和备份路径。
- AIMES 用户名由 `AppModel.saveSettings()` 保存到 settings.json；`saveAimesPassword()` 将密码写入 `com.pacificpride.ppflowhub.aimes` 钥匙串，`saveAllSettings()` 会同时处理库存系统和 AIMES 两套密码。
- AIMES 工厂名称缓存由 Python 管理，文件是 `data/factory-names.json`，写入采用临时文件替换。

## 9. 调试顺序

1. 先看 Swift 页面右侧操作记录和标准错误进度。
2. 再直接执行相同的 `scripts/pp-flowhub` 命令，查看 JSON 错误的 `code/context`。
3. 订单问题依次检查目录名、materials、Fittingslist、板材清单、缓存和 AIMES。
4. Traveler 问题检查模板工作表结构和生成后的重新打开校验。
5. 库存问题检查 Traveler identity、映射文件、商品目录和浏览器输出。

## 10. 修改后的文档维护规则

修改某条业务流程时，同步更新本文件对应章节，并在 `docs/project-handoff-log.md` 记录修改日期、影响文件、入口函数、返回结果和验证命令。
