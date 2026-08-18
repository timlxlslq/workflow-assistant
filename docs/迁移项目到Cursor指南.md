# 将“工作流程助手”项目搬到 Cursor

## 1. 在当前 Mac 上直接使用

Cursor 本质上是代码编辑器，这个项目不需要转换格式。

1. 安装并打开 Cursor。
2. 选择 `File → Open Folder`。
3. 打开项目文件夹：

   `/Users/lantian/Documents/工作流程助手`

4. 首次打开时选择信任项目。
5. 在 Cursor 聊天中先输入：

   > 请先阅读 README.md、docs/business-rules.md 和 docs/inventory-outbound-rules.md，理解项目结构和业务规则。暂时不要修改代码。

项目源代码、Git 记录、测试和构建脚本都会原样保留。

## 2. 给 Cursor 提供长期项目规则

Cursor 支持根目录的 `AGENTS.md`，也支持 `.cursor/rules/*.mdc`。可以在规则中说明：

- 业务规则以哪些文档为准。
- 修改后必须运行哪些测试。
- 用户名、密码和浏览器登录资料不得提交 GitHub。
- 未经明确确认，不得真实保存库存出库单。
- 修改 Swift 界面后必须重新构建应用。
- 不得覆盖用户现有配置和本机同步记录。

简单项目可以使用 `AGENTS.md`；需要按文件范围应用不同规则时，使用 `.cursor/rules`。

Cursor 项目规则文档：

https://docs.cursor.com/context/rules-for-ai

## 3. 在 Cursor 中测试和构建

在 Cursor 终端中运行：

```bash
python3 -m unittest discover -s tests -v
./scripts/build-app
```

安装到“应用程序”：

```bash
./scripts/install-app
```

真实库存操作具有外部影响。让 Cursor 测试浏览器流程时，应明确要求先模拟并在保存前停止。

## 4. 敏感信息

以下内容不应搬入项目或提交 GitHub：

- 库存系统用户名和密码。
- macOS 钥匙串内容。
- 浏览器登录目录。
- 本机 `Application Support` 中的配置和同步记录。
- 真实库存商品资料、库存数据和运行日志。

程序密码保存在 macOS 钥匙串，本机状态位于：

`~/Library/Application Support/工作流程助手/`

Cursor 打开项目时不会直接读取钥匙串密码；程序运行时仍可按现有方式读取。

## 5. 搬到另一台电脑

推荐使用私有 GitHub 仓库：

1. 在当前电脑把项目推送到私有 GitHub 仓库。
2. 在新电脑安装 Cursor 和 Git。
3. 使用 Cursor 克隆仓库。
4. 重新配置服务器路径、iCloud 路径和库存账号。
5. 重新把密码保存到新电脑的 macOS 钥匙串。
6. 不要直接复制旧浏览器登录目录。
7. 运行测试并重新构建应用。

## 6. 对话上下文

Codex 中的历史对话不会自动迁移到 Cursor。项目背景应通过以下文件传递：

- `README.md`
- `docs/business-rules.md`
- `docs/inventory-outbound-rules.md`
- `AGENTS.md` 或 `.cursor/rules/*.mdc`

Cursor Agent 实践建议：

https://cursor.com/blog/agent-best-practices
