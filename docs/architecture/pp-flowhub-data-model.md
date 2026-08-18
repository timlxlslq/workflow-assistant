# PP FlowHub 数据模型与边界

## 系统边界

AIHouse 是设计源，AIMES 是拆单排产源，AICNC 报表是生产源，金蝶是库存余额源。PP FlowHub 只做汇总、查询、人工修正、同步证据和状态管理，不把 Traveler 当作生产事实。

当前完整操作端运行在 Mac；中央数据库先放在 Mac 本地。未来 Windows Server 运行后端服务时，SQLite 仍只放在 Windows 本机磁盘，Mac App 和只读网页通过 API 访问，不直接打开 SMB/UNC 上的 SQLite 文件。

## 中央 SQLite

正式业务数据库：`~/Documents/pp-flowhub/data/workflow.sqlite3`。

主要表按职责分组：订单索引与同步证据、`production_batches`/`batch_evidence` 批次、`material_items` 材料、`hardware_items` 五金、`outbound_documents` 出库单据、`products` 商品主资料、`backup_records` 备份记录。`products` 保存 SKU、名称、规格、单位和商品成本 `cost_price`；库存商品资料没有预计采购价时，`cost_price` 为 `NULL`。AICNC 五金和人工五金在同一张表中，用 `source_type` 区分；AICNC 重同步只替换 AICNC 来源，不会覆盖 `manual`。

原始 Excel、XML、CSV 不复制进数据库，数据库保存路径、指纹、解析结果和同步时间。设置、待办、操作审计仍使用 JSON/JSONL，因为它们不是订单业务事实。

## 迁移与备份

首次准备存储时，旧订单索引和业务缓存合并到中央数据库；商品主资料直接写入中央数据库，不再读取旧库存数据库。旧订单索引成功迁移后只读归档到 `migration-archives/`，不自动删除。数据库备份写入本机 `data/database-backups/`：App 每个自然日首次启动、完成本地订单缓存读取后自动执行一次；保留今天及前两个自然日的每日备份，并在滚动 30 天内每个自然周保留最新一份，其他文件删除。Traveler 文件备份目录与数据库备份目录分开管理。

## Traveler

Traveler 只按需从数据库和当前源文件生成到系统临时目录，用于查看或打印，使用后不写入订单目录。生产事实仍来自 AIMES、AICNC 和金蝶；历史详情依赖中央数据库保存的解析结果。
