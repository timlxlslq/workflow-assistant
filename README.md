# PP FlowHub

这是一个本地优先、Agent 辅助的 macOS 生产工作流应用。它从服务器发现订单，生成或更新 Work Order Traveler，查询库存，并在用户确认后执行出库。

## 架构

```text
SwiftUI App
  → 本地命令解析器（常用命令零 Token）
  → Workflow Agent（仅模糊表达）
  → order / traveler / inventory Skills
  → Typed Tool Gateway + 本地审批
  → Python 确定性引擎
  → Excel / SMB / Playwright / SQLite
```

Agent 不直接修改 Excel、服务器或库存系统。Agent 不可用时，App 和 CLI 仍可执行本地可确定流程。模糊语句由官方 OpenAI Agents SDK 路由，当前使用面向成本敏感任务的 `gpt-5.6-luna`；成功路由会按完全相同的规范化语句记入本地 SQLite，下次零 Token 执行。

## Agent 开发环境

Agent 使用 Python 3.10+，macOS App 的最低系统版本为 14.0。新电脑不要复制旧 `.venv`；请在本机重建环境，以免 Intel/Apple Silicon 原生扩展混用：

```bash
python3 -m venv .venv
.venv/bin/python3 -m pip install "openpyxl==3.1.5" "openai-agents==0.19.2"
```

API Key 保存在被 Git 忽略的 `.env.local`，不会写入源码或 SQLite。构建脚本会从 `.venv` 自动发现 Python 基础运行时，并从 PATH 或项目 `node_modules` 链接自动发现 Node/Playwright；必要时可用 `TRAVELER_PYTHON_BASE`、`TRAVELER_NODE` 和 `TRAVELER_NODE_MODULES` 覆盖。

库存系统的 Playwright 操作默认使用后台无头浏览器，不会弹出 Chrome 或抢占键盘、鼠标焦点。只有在处理登录、验证码或排查网页结构时，才临时设置 `TRAVELER_BROWSER_VISIBLE=1` 使用可见浏览器。

库存页面也支持在设置页点击“打开库存专用 Chrome”，打开 `https://www.jdy.com/login/`，由用户手工登录并完成安全验证。后续库存操作会优先复用该 Chrome 中已登录的 `www.jdy.com` 或 `service.jdy.com` 工作台页面；没有可复用页面时，才回退到原有 Playwright 登录流程。普通用户直接打开且没有 CDP 端口的 Chrome 不会被强行接管。

## CLI

```bash
./scripts/pp-flowhub assistant "在服务器上找一下 PP0063"
./scripts/pp-flowhub assistant "给 PP1234-2-LAUNDRY 添加人工五金 M0144 数量 2 备注现场增加"
./scripts/pp-flowhub order list
./scripts/pp-flowhub order preview --folder "/Volumes/server/Optimized Orders/PP0063"
./scripts/pp-flowhub inventory preview --traveler "/path/to/Work Order Traveler(PP0063).xlsx"
```

写入类助手命令首先返回 `approval_required`；确认后用同一命令加 `--approve`。人工五金命令只读取本地商品资料取得名称和规格，不连接实时库存。商品主资料运行时从 `data/workflow.sqlite3` 的 `products` 表查询；库存系统导出的最新原始 XLSX 仅保留为 `data/inventory/current-products.xlsx` 备份。本地解析失败时才转交 Agent。

## 开发验证

```bash
PYTHONPATH=".:vendor" .venv/bin/python3 -m unittest discover -s tests -v
./scripts/test-macos-ui
./scripts/build-app
```

正式业务规则见 [docs/business-rules.md](docs/business-rules.md)，系统分层见 [docs/architecture/system-architecture.md](docs/architecture/system-architecture.md)。
