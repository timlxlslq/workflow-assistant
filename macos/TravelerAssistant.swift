import SwiftUI
import AppKit

final class AppModel: ObservableObject {
    @Published var query = ""
    @Published var running = false
    @Published var status = "准备就绪"
    @Published var details = "尚未运行查询。"
    @Published var hasError = false
    @Published var pendingOrder: String? = nil
    @Published var activityLines: [String] = []
    @Published var initialDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 22))!
    @Published var companyWiFi = "SpectrumSetup-7C81"
    @Published var sourceRoot = "/Volumes/server/Optimized Orders"
    @Published var orderRoot = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Order"
    @Published var templatePath = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/模版/Work Order Traveler().xlsx"
    @Published var backupRoot = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Work Order Traveler Backups"
    @Published var leftoverThreshold = 100.0
    @Published var aimesUsername = ""
    @Published var aimesPassword = ""
    @Published var plywoodThicknesses = "18, 14.5, 5.4"
    @Published var panelThicknesses = "19.1, 8, 9"
    @Published var plywoodLength = 2440.0
    @Published var plywoodWidth = 1220.0
    @Published var panelLength = 2745.0
    @Published var panelWidth = 1220.0
    @Published var aliasSource = 5.0
    @Published var aliasTarget = 5.4
    @Published var edgeDecimals = 2
    @Published var materialPlywood34 = 18.0
    @Published var materialPlywood58 = 14.5
    @Published var materialPlywood14 = 5.4
    @Published var materialPanel34 = 19.1
    @Published var materialPanel14 = 9.0
    @Published var shelfHolderCode = "WJ-CBT"
    @Published var hingeCode = "71T950A"
    @Published var hRailCode = "H-RAIL"
    @Published var lRailCode = "L-RAIL"
    @Published var settingsStatus = ""
    private var stderrBuffer = ""
    private var rawStderr = ""

    init() {
        loadSettings()
        loadBusinessRules()
    }

    private var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/工作流程助手/settings.json")
    }

    private var localRulesURL: URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent("business-rules.json")
    }

    private var bundledRulesURL: URL {
        projectRoot.appendingPathComponent("config/business-rules.json")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let value = values["initial_date"] as? String, let date = Self.dateFormatter.date(from: value) { initialDate = date }
        companyWiFi = values["company_wifi"] as? String ?? companyWiFi
        sourceRoot = values["source_root"] as? String ?? sourceRoot
        orderRoot = values["order_root"] as? String ?? orderRoot
        templatePath = values["template"] as? String ?? templatePath
        backupRoot = values["backup_root"] as? String ?? backupRoot
        leftoverThreshold = values["leftover_threshold_mm"] as? Double ?? leftoverThreshold
        aimesUsername = values["aimes_username"] as? String ?? aimesUsername
    }

    func saveSettings() {
        let values: [String: Any] = [
            "initial_date": Self.dateFormatter.string(from: initialDate),
            "company_wifi": companyWiFi.trimmingCharacters(in: .whitespacesAndNewlines),
            "source_root": sourceRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            "order_root": orderRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            "template": templatePath.trimmingCharacters(in: .whitespacesAndNewlines),
            "backup_root": backupRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            "leftover_threshold_mm": leftoverThreshold,
            "aimes_username": aimesUsername.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            settingsStatus = "✅ 设置已保存，下次任务立即生效。"
        } catch {
            settingsStatus = "❌ 保存失败：\(error.localizedDescription)"
        }
    }

    private func numberList(_ text: String) -> [Double]? {
        let values = text.split(separator: ",").map {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }
    }

    func loadBusinessRules() {
        let source = FileManager.default.fileExists(atPath: localRulesURL.path) ? localRulesURL : bundledRulesURL
        guard let data = try? Data(contentsOf: source),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sheets = root["sheet_materials"] as? [String: Any],
              let plywood = sheets["plywood"] as? [String: Any],
              let panel = sheets["panel"] as? [String: Any],
              let materials = root["materials_workbook"] as? [String: Any],
              let fittings = root["fittings"] as? [String: Any] else {
            settingsStatus = "❌ 无法读取业务规则配置。"
            return
        }
        func doubles(_ value: Any?) -> [Double] {
            (value as? [NSNumber])?.map(\.doubleValue) ?? []
        }
        let plywoodValues = doubles(plywood["thicknesses_mm"])
        let panelValues = doubles(panel["thicknesses_mm"])
        let plywoodSize = doubles(plywood["standard_size_mm"])
        let panelSize = doubles(panel["standard_size_mm"])
        if !plywoodValues.isEmpty { plywoodThicknesses = plywoodValues.map(formatNumber).joined(separator: ", ") }
        if !panelValues.isEmpty { panelThicknesses = panelValues.map(formatNumber).joined(separator: ", ") }
        if plywoodSize.count == 2 { plywoodLength = plywoodSize[0]; plywoodWidth = plywoodSize[1] }
        if panelSize.count == 2 { panelLength = panelSize[0]; panelWidth = panelSize[1] }
        edgeDecimals = (sheets["edge_decimals"] as? NSNumber)?.intValue ?? edgeDecimals
        if let aliases = sheets["thickness_aliases"] as? [String: Any],
           let pair = aliases.first,
           let source = Double(pair.key),
           let target = pair.value as? NSNumber {
            aliasSource = source
            aliasTarget = target.doubleValue
        }
        if let columns = materials["plywood_columns"] as? [String: Any] {
            materialPlywood34 = (columns["3"] as? NSNumber)?.doubleValue ?? materialPlywood34
            materialPlywood58 = (columns["4"] as? NSNumber)?.doubleValue ?? materialPlywood58
            materialPlywood14 = (columns["5"] as? NSNumber)?.doubleValue ?? materialPlywood14
        }
        if let rows = materials["panel_rows"] as? [String: Any] {
            materialPanel34 = (rows["3/4"] as? NSNumber)?.doubleValue ?? materialPanel34
            materialPanel14 = (rows["1/4"] as? NSNumber)?.doubleValue ?? materialPanel14
        }
        if let direct = fittings["direct_codes"] as? [String: Any] {
            shelfHolderCode = direct.first(where: { $0.value as? String == "Shelf Holder" })?.key ?? shelfHolderCode
            hingeCode = direct.first(where: { $0.value as? String == "Hinge" })?.key ?? hingeCode
        }
        if let paired = fittings["paired_codes"] as? [String: Any] {
            hRailCode = paired.first(where: { $0.value as? String == "H-Rail" })?.key ?? hRailCode
            lRailCode = paired.first(where: { $0.value as? String == "L-Rail" })?.key ?? lRailCode
        }
    }

    private func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    func saveBusinessRules() -> Bool {
        guard let plywoodValues = numberList(plywoodThicknesses), plywoodValues.count == 3 else {
            settingsStatus = "❌ Plywood厚度必须填写3个用逗号分隔的数值。"
            return false
        }
        guard let panelValues = numberList(panelThicknesses), !panelValues.isEmpty else {
            settingsStatus = "❌ Panel厚度格式不正确。"
            return false
        }
        guard plywoodLength > 0, plywoodWidth > 0, panelLength > 0, panelWidth > 0,
              edgeDecimals >= 0, edgeDecimals <= 4,
              !shelfHolderCode.isEmpty, !hingeCode.isEmpty, !hRailCode.isEmpty, !lRailCode.isEmpty else {
            settingsStatus = "❌ 业务规则中存在空值或无效数值。"
            return false
        }
        let rules: [String: Any] = [
            "schema_version": 1,
            "sheet_materials": [
                "thickness_aliases": [formatNumber(aliasSource): aliasTarget],
                "plywood": ["thicknesses_mm": plywoodValues, "standard_size_mm": [plywoodLength, plywoodWidth]],
                "panel": ["thicknesses_mm": panelValues, "standard_size_mm": [panelLength, panelWidth]],
                "display_order_mm": plywoodValues + panelValues.sorted(by: >),
                "edge_decimals": edgeDecimals,
            ],
            "materials_workbook": [
                "plywood_columns": ["3": materialPlywood34, "4": materialPlywood58, "5": materialPlywood14],
                "panel_rows": ["3/4": materialPanel34, "1/4": materialPanel14],
            ],
            "fittings": [
                "direct_codes": [shelfHolderCode.uppercased(): "Shelf Holder", hingeCode.uppercased(): "Hinge"],
                "paired_codes": [hRailCode.uppercased(): "H-Rail", lRailCode.uppercased(): "L-Rail"],
                "units": ["Hinge": "pcs/个", "Shelf Holder": "pcs/个", "H-Rail": "set/套", "L-Rail": "set/套"],
            ],
        ]
        do {
            try FileManager.default.createDirectory(at: localRulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: rules, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: localRulesURL, options: .atomic)
            return true
        } catch {
            settingsStatus = "❌ 业务规则保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func saveAllSettings() {
        guard saveBusinessRules() else { return }
        saveSettings()
        settingsStatus = "✅ 常规设置和业务规则已保存，下次任务立即生效。"
    }

    func saveAimesPassword() {
        guard !aimesUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            settingsStatus = "❌ 请先填写并保存 AIMES 用户名。"
            return
        }
        guard !aimesPassword.isEmpty else {
            settingsStatus = "❌ 请输入新的 AIMES 密码。"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password", "-U", "-a", aimesUsername,
            "-s", "com.pacificpride.traveler-assistant.aimes", "-w", aimesPassword,
        ]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                aimesPassword = ""
                settingsStatus = "✅ AIMES 密码已更新到 macOS 钥匙串。"
            } else {
                settingsStatus = "❌ 钥匙串未能保存 AIMES 密码。"
            }
        } catch {
            settingsStatus = "❌ 无法调用 macOS 钥匙串：\(error.localizedDescription)"
        }
    }

    private var projectRoot: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("project")
        if let bundled = bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func execute(_ mode: String, history: Bool = false, query: String? = nil) {
        if running { return }
        running = true
        hasError = false
        activityLines = []
        stderrBuffer = ""
        rawStderr = ""
        if mode == "preview" || mode == "scan" { pendingOrder = nil }
        status = "任务正在启动…"
        appendActivity("任务已启动；不会覆盖已有 Traveler。")
        let root = projectRoot
        let command = root.appendingPathComponent("scripts/traveler-assistant")
        var arguments = [mode]
        if history { arguments.append("--include-history") }
        if let query = query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--query", query]
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = command
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.standardOutput = output
            process.standardError = errors
            errors.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self.consumeProgressChunk(chunk) }
            }
            do {
                try process.run()
                process.waitUntilExit()
                errors.fileHandleForReading.readabilityHandler = nil
                let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let remainder = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    if !remainder.isEmpty { self.consumeProgressChunk(remainder) }
                    self.consume(out, stderr: self.rawStderr)
                }
            } catch {
                DispatchQueue.main.async { self.fail("无法启动扫描程序：\(error.localizedDescription)") }
            }
        }
    }

    private func consumeProgressChunk(_ chunk: String) {
        stderrBuffer += chunk
        let parts = stderrBuffer.components(separatedBy: "\n")
        stderrBuffer = parts.last ?? ""
        for line in parts.dropLast() where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               event["event"] as? String == "progress",
               let message = event["message"] as? String {
                appendActivity(message)
            } else {
                rawStderr += line + "\n"
            }
        }
    }

    private func appendActivity(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        activityLines.append("[\(formatter.string(from: Date()))] \(message)")
        status = message
        details = activityLines.joined(separator: "\n")
    }

    private func consume(_ output: String, stderr: String) {
        running = false
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail(stderr.isEmpty ? "无法解析扫描结果" : stderr)
            return
        }
        if let fatal = object["fatal"] as? [String: Any] {
            fail(fatal["message"] as? String ?? "发生严重异常")
            return
        }
        let errors = object["errors"] as? [[String: Any]] ?? []
        let reports = object["reports"] as? [[String: Any]] ?? []
        var lines: [String] = []
        for item in reports {
            let order = item["order_name"] as? String ?? "未知订单"
            let factory = item["factory_order"] as? String ?? ""
            if let created = item["created"] as? String {
                lines.append("✅ \(order)  \(factory)\n    已生成：\(created)")
            } else if let updated = item["updated"] as? String {
                lines.append("✅ \(order)  \(factory)\n    已更新：\(updated)\n    旧版本已备份。")
            } else if item["action_required"] as? Bool == true {
                lines.append("🟠 \(order)  \(factory)\n    源报表有变化，等待你比较和决定。")
                pendingOrder = order
            } else {
                lines.append("✓ \(order)  \(factory)\n    已检查")
            }
            let ignored = item["ignored_fittings"] as? [[String: Any]] ?? []
            if !ignored.isEmpty {
                let names = ignored.compactMap { $0["name"] as? String }.joined(separator: "、")
                lines.append("    提醒：未写入五金：\(names)")
            }
            let warnings = item["warnings"] as? [String] ?? []
            lines.append(contentsOf: warnings.map { "    提醒：\($0)" })
        }
        for item in errors {
            lines.append("❌ \(item["message"] as? String ?? "未知异常")")
        }
        hasError = !errors.isEmpty
        if hasError { status = "发现 \(errors.count) 项异常" }
        else if reports.contains(where: { $0["created"] != nil || $0["updated"] != nil }) {
            status = reports.contains(where: { $0["updated"] != nil }) ? "Traveler 已更新并备份旧版本" : "新 Traveler 已安全生成"
        } else if reports.isEmpty { status = "扫描完成，没有发现新变化" }
        else { status = "扫描完成，共检查 \(reports.count) 个工厂单" }
        let resultText = lines.isEmpty ? "没有待处理项目。" : lines.joined(separator: "\n\n")
        details = (activityLines + ["", "—— 本次任务结果 ——", resultText]).joined(separator: "\n")
        if hasError || reports.contains(where: { $0["created"] != nil || $0["updated"] != nil }) {
            let notice = NSUserNotification()
            notice.title = "工作流程助手"
            notice.informativeText = status
            NSUserNotificationCenter.default.deliver(notice)
        }
    }

    private func fail(_ message: String) {
        running = false
        hasError = true
        status = "运行失败"
        details = (activityLines + ["", "❌ \(message)"]).joined(separator: "\n")
    }

    func openOrders() {
        NSWorkspace.shared.open(URL(fileURLWithPath: orderRoot))
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30)).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("工作流程助手").font(.title2).fontWeight(.semibold)
                    Text("生产订单与Traveler管理").foregroundColor(.secondary)
                }
                Spacer()
                Button("打开订单文件夹") { model.openOrders() }
            }.padding(24)
            Divider()

            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("查询与扫描", systemImage: "magnifyingglass")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("支持 PP0047、F2607020183 或 PP0047-KITCHEN")
                            .font(.caption).foregroundColor(.secondary)
                        HStack {
                            TextField("输入订单号、工厂单号或 PP 空间名称", text: $model.query)
                                .textFieldStyle(.roundedBorder)
                            Button("查询") { model.execute("preview", history: true, query: model.query) }
                                .disabled(model.running || model.query.isEmpty)
                        }
                        HStack {
                            Button("预览新变化") { model.execute("preview") }.disabled(model.running)
                            Button("扫描并生成新订单") {
                                let targeted = !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                model.execute("scan", history: targeted, query: targeted ? model.query : nil)
                            }
                                .buttonStyle(.borderedProminent).disabled(model.running)
                            if model.running { ProgressView().controlSize(.small) }
                        }
                        if let pending = model.pendingOrder {
                            Divider()
                            Text("\(pending) 有版本差异，请确认后选择更新方式。")
                                .font(.caption).foregroundColor(.orange)
                            HStack {
                                Button("更新自动字段") { model.execute("update", history: true, query: pending) }
                                    .disabled(model.running)
                                Button("按模板重新生成") { model.execute("rebuild", history: true, query: pending) }
                                    .disabled(model.running)
                            }
                        }
                    }.padding(8)
                }

                HStack {
                    Circle().fill(model.hasError ? Color.red : Color.green).frame(width: 10, height: 10)
                    Text(model.status).fontWeight(.semibold)
                    Spacer()
                }.padding(14).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(10)

                GroupBox(label: Label("运行结果", systemImage: model.hasError ? "exclamationmark.triangle" : "list.bullet.rectangle")) {
                    ScrollView {
                        Text(model.details).frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled).padding(10)
                    }
                }
            }.padding(24)
        }
        .frame(minWidth: 760, minHeight: 600)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let minHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundColor(.primary)
            Divider()
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct RuleNumberRow: View {
    let label: String
    @Binding var value: Double
    var unit = "mm"

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            Text(unit).foregroundColor(.secondary).frame(width: 28, alignment: .leading)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("配置中心").font(.largeTitle).fontWeight(.bold)
                        Text("常规设置与业务规则保存在本机，不写入项目源码。")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        model.loadSettings()
                        model.loadBusinessRules()
                        model.settingsStatus = "已重新载入本机设置和业务规则。"
                    } label: {
                        Label("重新载入", systemImage: "arrow.clockwise")
                    }
                }

                VStack(spacing: 18) {
                    HStack(alignment: .top, spacing: 18) {
                    SettingsCard(title: "运行范围", symbol: "slider.horizontal.3", minHeight: 190) {
                        VStack(alignment: .leading, spacing: 12) {
                            DatePicker("初始扫描日期", selection: $model.initialDate, displayedComponents: .date)
                            TextField("公司 Wi-Fi", text: $model.companyWiFi)
                                .textFieldStyle(.roundedBorder)
                            RuleNumberRow(label: "可疑尺寸容差", value: $model.leftoverThreshold)
                            Text("程序只在你手工点击运行后执行。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    SettingsCard(title: "AIMES账户", symbol: "lock.shield", minHeight: 190) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("用户名", text: $model.aimesUsername)
                                .textFieldStyle(.roundedBorder)
                            SecureField("输入新密码", text: $model.aimesPassword)
                                .textFieldStyle(.roundedBorder)
                            Button("更新钥匙串密码") { model.saveAimesPassword() }
                                .disabled(model.aimesPassword.isEmpty)
                            Text("用户名保存在本机设置；密码只保存在macOS钥匙串。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    }

                    HStack(alignment: .top, spacing: 18) {
                    SettingsCard(title: "文件位置", symbol: "folder", minHeight: 405) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("服务器目录").font(.caption).foregroundColor(.secondary)
                            TextField("", text: $model.sourceRoot).textFieldStyle(.roundedBorder)
                            Text("订单目录").font(.caption).foregroundColor(.secondary)
                            TextField("", text: $model.orderRoot).textFieldStyle(.roundedBorder)
                            Text("Traveler模板").font(.caption).foregroundColor(.secondary)
                            TextField("", text: $model.templatePath).textFieldStyle(.roundedBorder)
                            Text("备份目录").font(.caption).foregroundColor(.secondary)
                            TextField("", text: $model.backupRoot).textFieldStyle(.roundedBorder)
                        }
                    }

                    SettingsCard(title: "板材规则", symbol: "square.3.layers.3d", minHeight: 405) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("允许厚度，使用英文逗号分隔")
                                    .font(.caption).foregroundColor(.secondary)
                                TextField("Plywood厚度", text: $model.plywoodThicknesses)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Panel厚度", text: $model.panelThicknesses)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                RuleNumberRow(label: "Plywood长度", value: $model.plywoodLength)
                                RuleNumberRow(label: "Plywood宽度", value: $model.plywoodWidth)
                                RuleNumberRow(label: "Panel长度", value: $model.panelLength)
                                RuleNumberRow(label: "Panel宽度", value: $model.panelWidth)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("厚度别名")
                                    Spacer()
                                    TextField("", value: $model.aliasSource, format: .number)
                                        .textFieldStyle(.roundedBorder).frame(width: 70)
                                    Image(systemName: "arrow.right")
                                    TextField("", value: $model.aliasTarget, format: .number)
                                        .textFieldStyle(.roundedBorder).frame(width: 70)
                                }
                                HStack {
                                    Text("封边小数位数")
                                    Spacer()
                                    Button {
                                        model.edgeDecimals = max(0, model.edgeDecimals - 1)
                                    } label: {
                                        Image(systemName: "minus")
                                    }
                                    Text("\(model.edgeDecimals)")
                                        .monospacedDigit()
                                        .frame(width: 24)
                                    Button {
                                        model.edgeDecimals = min(4, model.edgeDecimals + 1)
                                    } label: {
                                        Image(systemName: "plus")
                                    }
                                }
                            }
                        }
                    }
                    }

                    HStack(alignment: .top, spacing: 18) {
                    SettingsCard(title: "Materials换算", symbol: "tablecells", minHeight: 285) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Plywood Total Qty").font(.subheadline).fontWeight(.medium)
                            RuleNumberRow(label: "3/4 Plywood", value: $model.materialPlywood34)
                            RuleNumberRow(label: "5/8 Plywood", value: $model.materialPlywood58)
                            RuleNumberRow(label: "1/4 Plywood", value: $model.materialPlywood14)
                            Divider()
                            Text("Panel Color Table").font(.subheadline).fontWeight(.medium)
                            RuleNumberRow(label: "3/4 Finish Panel", value: $model.materialPanel34)
                            RuleNumberRow(label: "1/4 Finish Panel", value: $model.materialPanel14)
                        }
                    }

                    SettingsCard(title: "五金映射", symbol: "shippingbox", minHeight: 285) {
                        VStack(alignment: .leading, spacing: 10) {
                            fittingRow("Shelf Holder", text: $model.shelfHolderCode)
                            fittingRow("Hinge", text: $model.hingeCode)
                            fittingRow("H-Rail（成对）", text: $model.hRailCode)
                            fittingRow("L-Rail（成对）", text: $model.lRailCode)
                            Text("未列出的五金仍不写入Traveler，并按首次出现或变化提醒。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    }
                }

                HStack(spacing: 12) {
                    if !model.settingsStatus.isEmpty {
                        Text(model.settingsStatus)
                            .font(.callout)
                            .foregroundColor(model.settingsStatus.hasPrefix("❌") ? .red : .secondary)
                    }
                    Spacer()
                    Button("保存全部配置") { model.saveAllSettings() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(.top, 2)
            }
            .padding(26)
        }
        .frame(minWidth: 820, minHeight: 680)
    }

    private func fittingRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("代码", text: text)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        }
    }
}

@main
struct TravelerAssistantApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(model: model)
                    .tabItem { Label("任务", systemImage: "doc.text.magnifyingglass") }
                SettingsView(model: model)
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
        }
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
