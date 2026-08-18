# macOS Code Signing、Bundle Identifier 与 TCC 权限

本项目的 macOS App 使用固定的 Bundle Identifier：

```text
com.pacificpride.ppflowhub
```

它位于 `macos/Info.plist` 的 `CFBundleIdentifier`，构建脚本会在生成 App 前后再次检查，防止构建过程中变成临时或随机 Identifier。可执行文件路径也固定为：

```text
PP FlowHub.app/Contents/MacOS/PPFlowHub
```

## 为什么不能使用 ad-hoc signing

`codesign --sign -` 是 ad-hoc signing。它没有可持续识别开发者的 Apple 证书身份，重新构建时 CodeDirectory 通常会变化，macOS 的 TCC（Transparency, Consent, and Control）权限可能把新构建视为不同的代码，从而再次请求麦克风、语音识别、文件夹等权限。

本项目的本地开发构建不允许 `codesign --sign -`，也不允许在 Apple Development、Distribution 和 Developer ID 之间自动切换。签名职责与构建职责分离：`scripts/build-app` 在 Codex 中只编译和组装未签名 App；`scripts/install-app` 才读取 Apple Development identity 并签名安装。

## Codex Background Security Session 与 Aqua Terminal

Codex 的 shell 可能运行在 macOS 的 Background Security Session 和 seatbelt sandbox 中。即使 `whoami`、`HOME`、默认钥匙串路径都与普通 Terminal 相同，`security find-identity` 仍可能看不到 Aqua 登录会话中可用的登录钥匙串私钥。普通 Terminal 属于用户的 Aqua 图形登录会话，可以访问用户已登录并授权的 Apple Development identity。

因此，项目采用以下开发流程：

1. 在 Codex 中运行 `scripts/test-release` 和 `scripts/build-app`，完成测试、Swift 编译、资源打包和固定 Bundle Identifier 校验。构建脚本向 Swift linker 传入 `-no_adhoc_codesign`，这个阶段不读取钥匙串，也不进行 ad-hoc signing。
2. 从普通 macOS Terminal/Aqua 登录会话运行 `scripts/install-app`。该脚本只读取 Codex 已生成的临时 App，检查 Apple Development identity，在临时副本上签名并验证后安装；它不执行测试，也不重新编译。
3. 只有临时 App 通过 Bundle Identifier、TeamIdentifier、Designated Requirement、`codesign --verify --deep --strict` 和可执行文件哈希校验后，脚本才原子替换 `/Applications/PP FlowHub.app`。

### 资源目录中的钥匙串读取辅助程序必须显式签名

`keychain-read` 位于 `Contents/Resources/project/bin/`，不属于 `codesign --deep` 默认遍历的标准嵌套代码目录。仅对 App bundle 执行 `codesign --deep --sign` 可能留下未签名的辅助程序；macOS 在该程序调用 Security.framework 时可能直接以 `SIGKILL` 终止，Python 端随后会把非零退出误报为“密码尚未保存”。因此 `scripts/install-app` 必须在签署主 App 前显式签署并验证该文件，安装后再用不存在的账号执行不输出密码的探测：预期退出码为辅助程序定义的 `3`，而不是 `137`。

Codex 构建产物默认放在 `/tmp/pp-flowhub-build/PP FlowHub.app`，不再放在项目的 `build/` 目录。这样未签名的构建副本不会和 `/Applications` 中的正式 App 一起被 Finder/Launchpad 识别为第二个应用。安装成功后，构建输入会移动到 `/tmp/pp-flowhub-build-archive/` 留作可恢复归档。

每次 `scripts/build-app` 生成新的 App bundle 后，都必须提醒操作者从普通 macOS Terminal/Aqua 会话运行：

```bash
./scripts/install-app
```

Codex 的构建输出只是未签名构建产物，不代表 `/Applications` 中的 App 已更新。若 Aqua Terminal 中找不到该构建产物，`install-app` 会直接退出并提示先回到 Codex 执行 `scripts/build-app`。

如果 `install-app` 找不到 Apple Development identity，它会提示“请从普通 macOS Terminal/Aqua 登录会话运行此命令”，不会创建证书、导出私钥、修改 keychain ACL，也不会使用 ad-hoc signing。

## Designated Requirement 与 TCC

签名 App 包含一个 Designated Requirement（指定要求），它描述 macOS 用来识别这份代码的条件。典型条件包括：

- Bundle Identifier 必须是 `com.pacificpride.ppflowhub`；
- 签名锚点是 Apple；
- 证书链的叶子证书是固定的 Apple Development 证书；
- Team Identifier 与开发者证书一致。

当 Bundle Identifier、Team Identifier、签名证书身份和可执行文件路径保持稳定时，重新构建更容易被 macOS 视为同一个 App，TCC 授权也更可能保留。注意：`security find-identity` 输出中证书名称括号里的值不是 TeamIdentifier；安装脚本必须从签名后的 `codesign -dv` 元数据读取 TeamIdentifier，并与当前安装版比较。TCC 仍可能因用户主动重置权限、系统升级、Entitlements 改变、证书失效或授权范围改变而重新询问；固定签名不能绕过这些安全规则。

## 项目验证命令

检查当前可用的签名身份：

```bash
security find-identity -v -p codesigning
```

构建后检查 Bundle Identifier：

```bash
plutil -extract CFBundleIdentifier raw /tmp/pp-flowhub-build/PP FlowHub.app/Contents/Info.plist
```

检查签名详情、Team Identifier 和 Designated Requirement：

```bash
codesign -dv --verbose=4 /tmp/pp-flowhub-build/PP FlowHub.app
codesign -d --requirements - /tmp/pp-flowhub-build/PP FlowHub.app
codesign --verify --deep --strict /tmp/pp-flowhub-build/PP FlowHub.app
```

当前 Codex Background Security Session 若没有可见的 Apple Development identity，`build-app` 仍可完成未签名构建；`install-app` 会停止在替换现有 App 之前，并要求从普通 macOS Terminal/Aqua 登录会话重新运行，不会用 ad-hoc 签名冒充稳定开发签名。
