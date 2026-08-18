# PP FlowHub 静态上下文

> 用途：给后续任务提供可复用的项目背景、架构、规范和固定约束。本文只记录低频变化的信息；当前 Git 改动、测试数字、服务器/库存/安装包状态不写入这里。
>
> 建立时间：2026-08-15。若源码、业务规则或发布流程发生变化，应更新本文，而不是在每次任务中重复展开同一背景。

## 1. 项目定位

- PP FlowHub 是本地优先的 macOS 生产工作流应用，负责订单发现、订单/工厂单汇总、材料与五金处理、Traveler 按需生成、库存查询和出库流程。
- 事实来源分工：AIHouse=设计事实，AIMES=工厂单/拆单，AICNC=生产报表，金蝶=库存余额与出库记录。PP FlowHub 是汇总、查询、人工修正、同步证据和状态管理层。
- Traveler 是可生成、可打印的工作文件，不是生产事实源，也不是订单查看、库存查询或出库的前置条件。
- 当前版本没有 CNC 加工记录来源；不能从 Server 文件夹、material 或 Traveler 推断“已生产”。

## 2. 技术架构

```text
SwiftUI App / CLI
  -> 本地命令解析器（常用命令零 Token）
  -> Workflow Agent（仅处理模糊表达）
  -> order / traveler / inventory Skills
  -> Typed Tool Gateway + 本地审批
  -> Python 确定性业务引擎
  -> SQLite / Excel / SMB / Playwright
```

- SwiftUI：界面、语音转文字、预览、确认、串行任务队列和状态展示；不承载 Excel 业务规则。
- 本地解析器：把常用文字/语音表达转换成类型化动作；不能直接写真实系统。
- Agent：只理解模糊表达并输出结构化路由；不能直接读写 Excel、Server 或库存系统。Agent 不可用时，本地确定性流程仍应可运行。
- Skill：承载领域步骤、规则和引用；不要在 Skill 中复制 Python 业务实现。
- Tool Gateway：工具白名单、参数校验、审批边界和执行入口；业务计算仍由 Python 完成。
- Python：确定性解析、业务计算、Excel 读写、Server 扫描、库存映射、出库和复查。
- SQLite：订单索引/同步证据、批次、材料、五金、出库单据、商品主资料、备份记录、缓存和相关状态。
- 外部边界：`openpyxl` 处理 Excel，SMB 访问 Server，Playwright 驱动库存网页，Swift Security Framework/`keychain-read` 处理钥匙串。
- macOS 最低系统版本为 14.0；Python 要求 >=3.10；项目依赖固定在 `pyproject.toml`，包括 `openpyxl==3.1.5` 和 `openai-agents==0.19.2`。

## 3. 数据与身份约束

- 订单是核心业务对象；一个订单可有多个工厂单。一个批次可对应多个工厂单，但一个工厂单只能对应一个批次；冲突必须进入人工处理，不自动猜选。
- AIMES 的销售单名称是订单归属权威来源；工厂单号和工厂单名称是工厂单身份权威来源。Server 文件夹和报表只补充文件/优化证据，不覆盖 AIMES 归属。
- 材料和五金必须保存订单/工厂单归属、来源和必要的路径/指纹证据。AICNC 五金与人工五金可共存，使用来源字段区分；重同步 AICNC 不能覆盖人工五金。
- 业务状态必须可从持久化证据恢复，不能只依赖当前进程内存：AIMES 工厂单 -> 已拆单；有效材料映射 -> 已优化；库存系统出库记录 -> 已出库。
- 出库匹配必须使用订单号与工厂单身份；仅有订单号备注时，只有该订单当前唯一工厂单才允许回填，避免拆单订单被错误广播。
- 订单出货状态按当前工厂单集合重新计算；新增未出库工厂单会使已出货订单回到部分出货。
- 运行数据默认在 `~/Documents/pp-flowhub/data/`，整体被 Git 忽略。中央数据库是 `workflow.sqlite3`；代码仅保留旧 `order-index.sqlite3` 的迁移兼容路径，商品资料不再使用旧库存数据库。

## 4. 固定业务规则

- 订单号：PP 加 4 位数字并可带数字后缀，或 CS 加 3 位数字；非法或包含 `test` 的 AIMES 行只作为本次获取警告，不写入业务数据库、不进入待处理中心，必须到 AIMES 修改原始销售单名称。
- 房间不能被猜测地分配到多个工厂单；无法可靠匹配时必须请求人工分配。
- Server 默认区分 `Optimized Orders`（自有订单）和 `CUT TO SIZE`（来料加工）；目录时间变化本身不代表业务内容变化，优先使用文件/业务内容指纹。
- 截止日期由用户调整；未生成 Traveler 的订单不追踪源文件变化，已生成后也要以业务内容指纹而非单纯修改时间决定是否更新。
- Traveler 模板为 `resources/templates/Work Order Traveler.xlsx`，前三个工作表及顺序固定为 `WorkOrderTraveler`、`Usage List`、`Picking List`。
- 新 Traveler 不覆盖旧文件；更新前备份，在临时路径生成并重新打开验证后原子替换。模板样式、合并单元格、尺寸和公式兼容性必须保留。
- `Usage List` 使用从第 3 行开始的明细；多颜色占多行；汇总规则以模板约定为准。自动 material/Traveler 只能使用兼容的 `SUM`/`SUMIF`，不能引入 `UNIQUE`/`FILTER` 动态数组公式。
- 人工五金必须归属工厂单，按本地商品主资料读取，不为录入人工五金查询实时库存；数量必须为正整数；同工厂单中相同 SKU+规格合并。
- 库存查询默认只查板材和封边，仓库留空；结果无数据按库存 0；库存不足仍可出库但必须明确警告；封边出库量按规则取整。
- 标准工厂单出库前必须以订单索引/中央 SQLite 的出库状态为硬门槛；已出库不能再次勾选。真实出库最终以库存系统记录为准，App 提交成功或本地文件不能替代它。
- Server 关联报表只有在内容指纹确实变化且用户明确确认后，才可进入原出库单更新流程；不能因路径、mtime 或文件大小变化直接新建重复出库单。
- 库存遇到验证码、滑块、安全验证或登录失效时不得绕过；暂停并提示用户在库存专用 Chrome 中完成验证。
- 临时订单没有唯一工厂单号时仍可出库，用户可见身份统一使用文件夹名称；内容未变化且已出库时不得重复出库。

## 5. 安全、审批与日志

- 所有写文件、写数据库关键事实、写库存动作必须经过本地确认；写入开始后不可取消，读取/排队/等待确认阶段可以取消。
- Agent 只能建议动作；Gateway 必须重新计算真实审批权限，不能信任 Agent 自带的权限或状态。
- 常用命令零 Token；成功的模糊路由按完全相同的规范化文本写入本地存储，后续优先本地路由，不能把一次成功结果扩展成宽泛模糊规则。
- API Key 不进源码、SQLite 或日志；库存/业务密码进 macOS 钥匙串，不保存明文，也不使用 `/usr/bin/security` 作为应用读密码方案。
- 操作日志记录动作、结果、步骤、耗时和必要上下文，不记录用户输入原文、密码、验证码、网页全文、附件原文、完整业务数据值或 SQL 绑定值。日志写失败是 best-effort，不应阻断业务。
- 用户可在设置中关闭操作日志；关闭动作本身先记录，之后停止新增记录。面向用户的错误必须说明业务影响和下一步，隐藏堆栈、异常代码和内部变量名。

## 6. 编码与维护规范

- 优先修改现行单一路径，避免新增长期兼容分支、重复 UI 或重复业务逻辑；ADR-001 是设计方向，但现有迁移辅助代码仍需按当前实现现场核对。
- 业务规则集中维护在文档和确定性 Python 引擎；SwiftUI 只做展示/交互适配，不复制解析和计算。
- 文件写入采用临时文件、验证、备份和原子替换；对 Server/Excel 的外部变化使用内容指纹，不能只依赖 mtime。
- 真实业务失败必须保留在统一待处理中心和操作记录中；“稍后处理”只关闭当前界面，不解决问题或推进基线。
- 测试夹具必须隔离在临时目录；不能把用户可变的真实订单直接作为负向测试前提。文件类功能至少用两个独立读取器验证，Excel 兼容性还要检查 OOXML 具体记录。
- Python 测试使用标准 `unittest`；命令行通过 `scripts/pp-flowhub` 进入 assistant/order/inventory 入口。不要假设系统 Python、旧虚拟环境或某个个人缓存路径可用。

## 7. 固定验证与发布门禁

代码或 App 修改完成后，按以下顺序验证；结论必须区分“源码/离线测试”“构建成功”“正式安装”“真实外部系统行为”：

1. `./scripts/test-release`：全量 Python `unittest`、macOS UI 回归、PP0067 workbook E2E、`git diff --check`。
2. 发布门禁还必须验证 xlsx ZIP/OOXML、禁止不安全动态数组公式、独立工作簿渲染、自动 material 的 Color Table、模板样式/合并单元格和关键单元格。
3. `./scripts/build-app`：生成新的未签名 `/tmp/pp-flowhub-build/PP FlowHub.app`；不能复用旧构建。
4. 正式安装必须从普通 Aqua Terminal 运行 `./scripts/install-app`：检查 Apple Development 身份、固定 Bundle Identifier、签名/TeamIdentifier/Designated Requirement、可执行文件哈希和钥匙串 helper，再原子替换 `/Applications/PP FlowHub.app`。
5. 安装成功后仍需重新启动已安装 App 做 launch/行为检查；旧进程不会自动替换，验证前应退出并重新打开。
6. 真实 Server、库存网页、钥匙串和 `/Applications` 状态是动态外部证据；离线夹具或单元测试不能代替生产验证。无法访问时必须明确标为待验证。

## 8. 后续任务的上下文读取协议

每次执行任务前先用简短三行说明：

- **复用静态上下文**：列出本次相关的本文件章节和对应权威文档。
- **新读取动态信息**：只列出本次重新检查的代码、diff、日志、测试结果、运行状态或外部状态。
- **无需重复读取**：列出本次未重复读取的稳定文档/源码区域；只有它们发生修改、任务涉及新领域或出现矛盾时才重读。

以下内容默认不作为静态事实，必须在相关任务中重新读取：当前 Git diff/分支、未提交文件、测试通过数量和耗时、异常日志、`data/` 内容、Server/库存可达性、登录/钥匙串状态、构建产物、已安装 App、真实用户界面行为，以及项目交接记录中的“待办/部分完成”状态。

## 9. 权威文档索引

- 项目入口与运行环境：[README.md](../README.md)
- 协作规则：[AGENTS.md](../AGENTS.md)
- 已确认业务规则：[business-rules.md](business-rules.md)
- 订单/库存出库细则：[inventory-outbound-rules.md](inventory-outbound-rules.md)
- 系统架构：[architecture/system-architecture.md](architecture/system-architecture.md)
- 数据模型与边界：[architecture/pp-flowhub-data-model.md](architecture/pp-flowhub-data-model.md)
- 设计决策：[architecture/decisions/001-simple-single-path.md](architecture/decisions/001-simple-single-path.md)
- 发布测试：[release-testing.md](release-testing.md)
- 操作日志：[operation-logging.md](operation-logging.md)
- 动态交接与待办：[project-handoff-log.md](project-handoff-log.md)
