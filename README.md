# 工作流程助手

本项目用于在 macOS 上扫描公司服务器中的 AICNC 报表，校验并配对板材清单与五金清单，然后依据既有模板生成 Work Order Traveler。

当前实现范围：

- 只处理正式启用时间之后出现或更新的 `PP` + 四位数字订单。
- 支持全量查询、`PP####`、`F...` 工厂单号及带 PP 前缀的空间名称查询。
- 校验报表文件名、工作表结构、工厂单号映射、板材厚度/规格、封边及轨道左右数量。
- 新工厂单校验通过后生成 Traveler；已有 Traveler 有变化时只生成差异，等待人工决定。
- 保存运行记录、提醒状态和忽略五金状态。
- 提供 macOS SwiftUI 界面，所有任务由用户手工打开应用后启动。
- 库存出库页可选择 Traveler、执行全量预检、显示商品映射和异常，并在后台模拟填写到保存前。
- 真实保存已启用；每次只允许选择一份 Traveler，且必须在独立确认弹窗中再次确认。

详细业务规则见 [docs/business-rules.md](docs/business-rules.md)。
程序实际读取的可量化规则见 [config/business-rules.json](config/business-rules.json)。

规则文件分工：

- `config/business-rules.json`：厚度、尺寸、五金代码等机器可执行规则；保存后下次启动程序生效。
- `docs/business-rules.md`：解释业务原因、复杂流程、异常处理和人工决定，供检查、讨论及修改审批使用。
- `docs/inventory-outbound-rules.md`：库存商品匹配、其他出库单、同步状态和异常处理的完整业务流程。
- 修改 JSON 后必须运行完整测试；修改复杂流程说明后，仍需同步修改代码和测试。

## 开发运行

```bash
./scripts/traveler-assistant preview --include-history --query PP0047
./scripts/traveler-assistant scan
```

`preview` 永不写入 Traveler；`scan` 只会自动创建全新且校验通过的 Traveler，不覆盖已有文件。

新版按订单工作流使用独立入口，旧命令继续保留：

```bash
./scripts/traveler-assistant order list
./scripts/traveler-assistant order preview --folder "/Volumes/server-1/Optimized Orders/pp0068"
./scripts/traveler-assistant order generate --folder "/Volumes/server-1/Optimized Orders/pp0068"
```

应用中的“Traveler生成”页会先列文件夹，点击后预览并校验。旧版扫描入口目前已隐藏，
其业务逻辑暂时保留备用；待新版流程稳定后，应提醒用户确认并删除旧版界面代码。

## 凭据安全

- AIMES 用户名只保存在本机应用设置中，不在源码中提供真实默认值。
- AIMES 密码只保存在 macOS 钥匙串中，不写入设置文件、日志或 Git。
- 提交代码前运行 `python3 -m unittest tests.test_security` 检查常见凭据格式和敏感文件。
