# 发布测试与安装流程

## 背景

仅验证 Python 可以重新打开 `.xlsx` 不足以证明 Excel 会接受该文件；仅测试源码也不足以证明 `/Applications` 中运行的是同一版本。

## Codex 发布测试门禁

测试和构建由 Codex 执行，正式安装脚本不重复执行这些步骤。Codex 发布门禁依次完成：

1. 全量 Python 回归测试。
2. macOS UI 编译与模型集成测试。
3. 使用真实 PP0067 目录复制品，从缺少 material 开始完成“自动生成 material → 生成 Traveler”。
4. 检查 xlsx ZIP/OOXML 完整性，并拒绝 Usage List 中不安全的 `UNIQUE` / `FILTER` 动态数组公式。
5. 用独立电子表格引擎导入并渲染生成的 Traveler。
6. 校验自动 material 的 Color Table：颜色、3/4 Panel、1/4 Panel、封边汇总均正确；公式只使用兼容的 `SUM` / `SUMIF`，不含 `UNIQUE` / `FILTER`。
7. 将自动 material 与人工模板比较合并单元格、列宽和关键单元格样式，并用独立工作簿渲染器生成整表图片检查可读性。
8. 重新构建 App；不能复用测试前的旧构建。

完成上述门禁后，Codex 会生成 `/tmp/pp-flowhub-build/PP FlowHub.app`，并提醒从普通 Aqua Terminal 执行 `scripts/install-app`。

## Aqua Terminal 安装步骤

`scripts/install-app` 只负责以下与正式安装直接相关的工作，不运行测试、不重新编译：

1. 检查有效的 Apple Development identity。
2. 检查 Codex 已生成的临时 App、固定 Bundle Identifier 和可执行文件路径。
3. 复制临时 App、签名并验证 Bundle Identifier、TeamIdentifier、Designated Requirement、代码签名和可执行文件哈希。
4. 原子替换 `/Applications/PP FlowHub.app`。
5. 将已消费的构建副本移到 `/tmp/pp-flowhub-build-archive`，避免 Finder 将构建产物误显示为第二个 App。

## 缺陷复盘原则

- 测试必须覆盖真实返回结构。例如 `preview-related` 的业务错误位于 `errors`，不能只模拟顶层 `fatal`。
- 测试必须覆盖真实用户入口和真实样本，不能只测内部辅助函数。
- 可变的真实订单不能直接充当“缺文件”等负向测试前提；负向场景必须在临时目录创建隔离夹具，避免用户操作改变测试结论。
- 文件类功能至少使用两个独立读取器；涉及 Excel 兼容性时，还要检查 OOXML 中会触发修复的具体记录。
- “构建成功”和“正式安装成功”是两个不同检查点；最终结论以 `/Applications` 中的哈希为准。
- 安装后正在运行的旧进程不会自动替换，交付时必须明确要求用户用 `⌘Q` 退出后重新打开。
