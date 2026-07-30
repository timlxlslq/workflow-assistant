import SwiftUI
import AppKit

struct OrderFolderItem: Identifiable {
    let id: String
    let orderId: String
    let modifiedAt: String
}

struct OrderMaterialPreview: Identifiable {
    let id = UUID()
    let kind: String
    let thickness: Double
    let color: String
    let quantity: Double
}

struct OrderFactoryPreview: Identifiable {
    let id: String
    let factoryOrder: String
    let orderName: String
}

struct OrderFittingPreview: Identifiable {
    let id: String
    let key: String
    let factoryOrder: String
    let orderName: String
    let name: String
    let code: String
    let size: String
    let unit: String
    let quantity: Double
    let ignored: Bool
}

struct InventoryTraveler: Identifiable {
    let id: String
    let ppFolder: String
    let fileName: String
    let orderName: String
    let modifiedAt: String
    let status: String
    let documentNumber: String
}

struct InventoryPreviewRow: Identifiable {
    let id = UUID()
    let travelerName: String
    let productCode: String
    let productName: String
    let quantity: Double
    let source: String
    let status: String
    let section: String
}

struct InventoryProductCandidate: Identifiable {
    let id: String
    let code: String
    let name: String
    let spec: String
    let category: String
    let unit: String
}

struct InventoryStep: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let detail: String
    let state: String
}

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let startedAt: Date
    var deadline: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        content: String,
        startedAt: Date = Date(),
        deadline: Date?,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.startedAt = startedAt
        self.deadline = deadline
        self.completedAt = completedAt
    }
}

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
    @Published var inventoryTravelers: [InventoryTraveler] = []
    @Published var selectedInventoryPaths: Set<String> = []
    @Published var inventoryPreviewRows: [InventoryPreviewRow] = []
    @Published var inventoryErrors: [String] = []
    @Published var inventoryRunning = false
    @Published var inventoryStatus = "尚未载入 Traveler"
    @Published var inventorySuccessMessage = ""
    @Published var inventoryCatalogStatus = "商品资料尚未检查"
    @Published var showInventoryHistory = false
    @Published var jdyUsername = ""
    @Published var jdyPassword = ""
    @Published var inventorySteps: [InventoryStep] = []
    @Published var inventoryProductCandidates: [InventoryProductCandidate] = []
    @Published var inventoryProductSearchStatus = ""
    @Published var orderFolders: [OrderFolderItem] = []
    @Published var selectedOrderPath = ""
    @Published var selectedOrderId = ""
    @Published var orderMaterialsFile = ""
    @Published var orderMaterials: [OrderMaterialPreview] = []
    @Published var orderEdgeBanding: [String: Double] = [:]
    @Published var orderFactories: [OrderFactoryPreview] = []
    @Published var orderFittings: [OrderFittingPreview] = []
    @Published var orderWarnings: [String] = []
    @Published var orderSteps: [InventoryStep] = []
    @Published var orderRunning = false
    @Published var orderStatus = "点击刷新读取服务器订单文件夹"
    @Published var orderError = ""
    @Published var orderCreatedPath = ""
    @Published var orderExistingTravelerPath = ""
    @Published var legacySteps: [InventoryStep] = []
    @Published var todoItems: [TodoItem] = []
    @Published var todoStatus = ""
    private var stderrBuffer = ""
    private var rawStderr = ""
    private var inventoryStderrBuffer = ""
    private var inventoryRawErrors = ""
    private var orderStderrBuffer = ""
    private var orderRawErrors = ""

    init() {
        loadSettings()
        loadBusinessRules()
        loadTodoItems()
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

    var todoDataURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/工作流程助手/data/todo-items.json")
    }

    func loadTodoItems() {
        guard FileManager.default.fileExists(atPath: todoDataURL.path) else {
            todoItems = []
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            todoItems = try decoder.decode([TodoItem].self, from: Data(contentsOf: todoDataURL))
            todoStatus = ""
        } catch {
            todoStatus = "无法读取待办数据：\(error.localizedDescription)"
        }
    }

    func addTodo(content: String, deadline: Date?) {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            todoStatus = "请输入任务内容"
            return
        }
        todoItems.append(TodoItem(content: value, deadline: deadline))
        saveTodoItems()
    }

    func updateTodo(_ item: TodoItem, content: String, deadline: Date?) {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = todoItems.firstIndex(where: { $0.id == item.id }) else {
            todoStatus = "请输入任务内容"
            return
        }
        todoItems[index].content = value
        todoItems[index].deadline = deadline
        saveTodoItems()
    }

    func toggleTodoCompletion(_ item: TodoItem) {
        guard let index = todoItems.firstIndex(where: { $0.id == item.id }) else { return }
        todoItems[index].completedAt = todoItems[index].completedAt == nil ? Date() : nil
        saveTodoItems()
    }

    func deleteTodo(_ item: TodoItem) {
        todoItems.removeAll { $0.id == item.id }
        saveTodoItems()
    }

    private func saveTodoItems() {
        do {
            try FileManager.default.createDirectory(
                at: todoDataURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(todoItems).write(to: todoDataURL, options: .atomic)
            todoStatus = ""
        } catch {
            todoStatus = "无法保存待办数据：\(error.localizedDescription)"
        }
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
        jdyUsername = values["jdy_username"] as? String ?? jdyUsername
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
            "jdy_username": jdyUsername.trimmingCharacters(in: .whitespacesAndNewlines),
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

    func saveJdyPassword() {
        guard !jdyUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            settingsStatus = "❌ 请先填写并保存库存系统用户名。"
            return
        }
        guard !jdyPassword.isEmpty else {
            settingsStatus = "❌ 请输入新的库存系统密码。"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password", "-U", "-a", jdyUsername,
            "-s", "com.pacificpride.workflow-assistant.jdy", "-w", jdyPassword,
        ]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                jdyPassword = ""
                settingsStatus = "✅ 库存系统密码已更新到 macOS 钥匙串。"
            } else {
                settingsStatus = "❌ 钥匙串未能保存库存系统密码。"
            }
        } catch {
            settingsStatus = "❌ 无法调用 macOS 钥匙串：\(error.localizedDescription)"
        }
    }

    func loadInventory() {
        beginInventoryOperation("刷新 Traveler 列表")
        addInventoryStep("读取订单目录", "正在查找 Work Order Traveler 文件", "running")
        runInventory(["list-names"]) { object in
            let rows = object["travelers"] as? [[String: Any]] ?? []
            self.inventoryTravelers = rows.map {
                InventoryTraveler(
                    id: $0["path"] as? String ?? UUID().uuidString,
                    ppFolder: $0["pp_folder"] as? String ?? "",
                    fileName: $0["file_name"] as? String ?? "",
                    orderName: $0["order_name"] as? String ?? "",
                    modifiedAt: $0["modified_at"] as? String ?? "",
                    status: $0["status"] as? String ?? "未出库",
                    documentNumber: $0["document_number"] as? String ?? ""
                )
            }
            self.selectedInventoryPaths = self.selectedInventoryPaths.intersection(Set(self.inventoryTravelers.map(\.id)))
            let errors = object["errors"] as? [[String: Any]] ?? []
            self.inventoryErrors = errors.map {
                let file = URL(fileURLWithPath: $0["path"] as? String ?? "").lastPathComponent
                let message = $0["message"] as? String ?? "Traveler 格式异常"
                return file.isEmpty ? message : "\(file)：\(message)"
            }
            if let catalog = object["catalog"] as? [String: Any],
               let count = catalog["count"] as? Int {
                let stale = catalog["stale"] as? Bool ?? false
                self.inventoryCatalogStatus = "\(count) 个商品" + (stale ? " · 已超过30天，请更新" : " · 资料有效")
            }
            self.inventoryStatus = "已载入 \(rows.count) 份 Traveler" + (errors.isEmpty ? "" : "，\(errors.count) 份需人工处理")
            self.finishRunningInventoryStep("找到 \(rows.count) 份可读取文件", "success")
            self.addInventoryStep("延迟内容校验", "仅载入文件夹和文件名；点击文件后才读取内容及商品映射", "success")
            if !errors.isEmpty {
                self.addInventoryStep("发现异常文件", self.inventoryErrors.joined(separator: "；"), "warning")
            }
            self.finishRunningInventoryStep("Traveler 列表刷新完成", errors.isEmpty ? "success" : "warning")
        }
    }

    func refreshInventoryFolder(_ folder: String) {
        beginInventoryOperation("更新 \(folder) 出库状态")
        addInventoryStep("查询库存系统", "正在按 \(folder) 和工厂单名称查询其他出库单", "running")
        runInventory(["reconcile-folder", "--folder", folder]) { result in
            let found = result["found"] as? [[String: Any]] ?? []
            let notFound = result["not_found"] as? [[String: Any]] ?? []
            let needsReview = result["needs_review"] as? [[String: Any]] ?? []
            self.finishRunningInventoryStep(
                "库存系统查询完成，唯一关联 \(found.count) 份，未找到记录 \(notFound.count) 份",
                needsReview.isEmpty ? "success" : "warning"
            )
            for item in found {
                let name = item["order_name"] as? String ?? ""
                let number = item["document_number"] as? String ?? ""
                self.addInventoryStep("发现已出库", "\(name)：\(number)", "success")
            }
            if !notFound.isEmpty {
                let names = notFound.compactMap { $0["order_name"] as? String }.joined(separator: "、")
                self.addInventoryStep("未发现出库记录", names, "success")
            }
            if !needsReview.isEmpty {
                let details = needsReview.map {
                    let candidates = ($0["candidates"] as? [String] ?? []).joined(separator: " / ")
                    return "\($0["order_name"] as? String ?? "未知工厂单")：\(candidates)"
                }.joined(separator: "；")
                self.addInventoryStep("发现多个候选，请提供正确单据号", details, "warning")
            }
            self.addInventoryStep("更新本机状态", "正在重新读取 \(folder) 全部 Traveler", "running")
            self.reloadInventoryFolder(folder)
        }
    }

    private func reloadInventoryFolder(_ folder: String) {
        runInventory(["list-names"]) { object in
            let rows = object["travelers"] as? [[String: Any]] ?? []
            let refreshed = rows.compactMap { row -> InventoryTraveler? in
                guard (row["pp_folder"] as? String ?? "") == folder else { return nil }
                return InventoryTraveler(
                    id: row["path"] as? String ?? UUID().uuidString,
                    ppFolder: folder,
                    fileName: row["file_name"] as? String ?? "",
                    orderName: row["order_name"] as? String ?? "",
                    modifiedAt: row["modified_at"] as? String ?? "",
                    status: row["status"] as? String ?? "未出库",
                    documentNumber: row["document_number"] as? String ?? ""
                )
            }
            let otherFolders = self.inventoryTravelers.filter { $0.ppFolder != folder }
            self.inventoryTravelers = otherFolders + refreshed
            let issued = refreshed.filter { $0.status == "已出库" }.count
            let needsUpdate = refreshed.filter { $0.status == "需要更新" }.count
            self.inventoryStatus = "\(folder) 状态已更新"
            self.finishRunningInventoryStep(
                "共 \(refreshed.count) 份：已出库 \(issued) 份、需要更新 \(needsUpdate) 份、其余 \(max(0, refreshed.count - issued - needsUpdate)) 份",
                "success"
            )
        }
    }

    func previewSelectedInventory() {
        inventoryPreviewRows = []
        inventoryErrors = []
        beginInventoryOperation("预检所选 Traveler")
        let paths = Array(selectedInventoryPaths).sorted()
        guard !paths.isEmpty else {
            inventoryStatus = "请先选择至少一份 Traveler"
            addInventoryStep("选择文件", "没有选择 Traveler，任务未开始", "failure")
            return
        }
        addInventoryStep("选择文件", "已选择 \(paths.count) 份 Traveler", "success")
        previewNext(paths, index: 0, accumulated: [])
    }

    func openAndFillSelectedInventory(confirmSave: Bool = false) {
        let paths = Array(selectedInventoryPaths).sorted()
        guard paths.count == 1 else {
            inventoryStatus = "浏览器模拟填写时请一次只选择一份 Traveler"
            return
        }
        guard inventoryErrors.isEmpty, !inventoryPreviewRows.isEmpty else {
            inventoryStatus = "请先完成预检并处理全部异常"
            return
        }
        beginInventoryOperation(confirmSave ? "真实写入库存系统" : "后台模拟填写")
        addInventoryStep("安全确认", confirmSave ? "用户已明确确认保存真实出库单" : "本次将在保存前停止", "success")
        inventoryStatus = confirmSave ? "正在后台填写并保存库存出库单…" : "正在后台填写；本次绝不会点击保存…"
        var arguments = ["outbound", "--traveler", paths[0]]
        if confirmSave { arguments.append("--confirm-save") }
        runInventory(arguments) { object in
            if object["saved"] as? Bool == false {
                self.inventoryStatus = "模拟填写完成，已在保存前停止"
                self.addInventoryStep("任务完成", "所有字段已填写并核对，未点击保存", "success")
            } else if object["saved"] as? Bool == true {
                let number = object["documentNumber"] as? String ?? "未知单号"
                self.inventoryStatus = "✅✅ 出库成功！单据编号：\(number)"
                self.inventorySuccessMessage = "出库成功！库存单 \(number) 已保存"
                self.addInventoryStep("✅ 出库成功", "单据编号 \(number)，库存及本机同步记录均已更新", "success")
                self.markInventoryTravelerSaved(path: paths[0], documentNumber: number)
                self.addInventoryStep("左侧状态已更新", "当前 Traveler 已立即标记为“已出库”", "success")
            } else {
                self.inventoryStatus = "库存系统模拟填写已结束"
            }
        }
    }

    private func markInventoryTravelerSaved(path: String, documentNumber: String) {
        inventoryTravelers = inventoryTravelers.map { item in
            guard item.id == path else { return item }
            return InventoryTraveler(
                id: item.id,
                ppFolder: item.ppFolder,
                fileName: item.fileName,
                orderName: item.orderName,
                modifiedAt: item.modifiedAt,
                status: "已出库",
                documentNumber: documentNumber
            )
        }
    }

    func setInventoryItemsIgnored(_ names: [String], ignored: Bool) {
        let uniqueNames = Array(Set(names.filter { !$0.isEmpty })).sorted()
        guard !uniqueNames.isEmpty else {
            inventoryStatus = ignored ? "请先选择需要忽略的材料" : "请先选择需要恢复的材料"
            return
        }
        beginInventoryOperation(ignored ? "忽略选中材料" : "恢复选中材料")
        var arguments = [ignored ? "ignore-item" : "unignore-item"]
        for name in uniqueNames {
            arguments += ["--traveler-name", name]
        }
        if ignored {
            arguments += ["--reason", "用户在出库预览中选择忽略"]
        }
        runInventory(arguments) { _ in
            self.addInventoryStep(
                ignored ? "忽略设置已保存" : "忽略设置已取消",
                uniqueNames.joined(separator: "、"),
                "success"
            )
            self.previewSelectedInventory()
        }
    }

    func searchInventoryProducts(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inventoryProductSearchStatus = "请输入商品编号、名称或规格"
            inventoryProductCandidates = []
            return
        }
        inventoryProductSearchStatus = "正在搜索…"
        runInventory(["search-products", "--query", trimmed]) { object in
            let products = object["products"] as? [[String: Any]] ?? []
            self.inventoryProductCandidates = products.map {
                InventoryProductCandidate(
                    id: $0["code"] as? String ?? UUID().uuidString,
                    code: $0["code"] as? String ?? "",
                    name: $0["name"] as? String ?? "",
                    spec: $0["spec"] as? String ?? "",
                    category: $0["category"] as? String ?? "",
                    unit: $0["unit"] as? String ?? ""
                )
            }
            self.inventoryProductSearchStatus = products.isEmpty
                ? "没有找到符合条件的启用商品"
                : "找到 \(products.count) 个商品"
        }
    }

    func saveInventoryMapping(travelerName: String, productCode: String) {
        beginInventoryOperation("保存材料映射")
        addInventoryStep("确认映射", "\(travelerName) → \(productCode)", "running")
        runInventory([
            "set-mapping", "--traveler-name", travelerName,
            "--product-code", productCode,
        ]) { object in
            let product = object["product"] as? [String: Any] ?? [:]
            let name = product["name"] as? String ?? productCode
            self.finishRunningInventoryStep("已映射到 \(productCode) \(name)", "success")
            self.inventoryStatus = "映射已保存，正在重新预检"
            self.previewSelectedInventory()
        }
    }

    private func previewNext(_ paths: [String], index: Int, accumulated: [InventoryPreviewRow]) {
        guard index < paths.count else {
            inventoryPreviewRows = accumulated
            inventoryStatus = inventoryErrors.isEmpty
                ? "预检通过：\(paths.count) 份 Traveler，共 \(accumulated.count) 行待出库材料"
                : "预检未通过，请先处理 \(inventoryErrors.count) 项异常"
            addInventoryStep(
                inventoryErrors.isEmpty ? "预检完成" : "预检停止",
                inventoryErrors.isEmpty ? "全部材料均已找到唯一库存商品，共 \(accumulated.count) 行" : inventoryErrors.joined(separator: "；"),
                inventoryErrors.isEmpty ? "success" : "failure"
            )
            return
        }
        addInventoryStep(
            "读取 Traveler \(index + 1)/\(paths.count)",
            URL(fileURLWithPath: paths[index]).lastPathComponent,
            "running"
        )
        runInventory(["preview", "--traveler", paths[index]], manageRunning: index == 0) { object in
            var next = accumulated
            let items = object["outbound_items"] as? [[String: Any]] ?? []
            next += items.map {
                InventoryPreviewRow(
                    travelerName: $0["traveler_name"] as? String ?? "",
                    productCode: $0["product_code"] as? String ?? "",
                    productName: $0["product_name"] as? String ?? "",
                    quantity: $0["quantity"] as? Double ?? 0,
                    source: $0["match_source"] as? String ?? "",
                    status: "已映射",
                    section: $0["section"] as? String ?? ""
                )
            }
            let ignored = object["ignored_items"] as? [[String: Any]] ?? []
            next += ignored.map {
                InventoryPreviewRow(
                    travelerName: $0["name"] as? String ?? "",
                    productCode: "—",
                    productName: "不写入库存系统",
                    quantity: $0["quantity"] as? Double ?? 0,
                    source: $0["reason"] as? String ?? "已忽略",
                    status: "已忽略",
                    section: $0["section"] as? String ?? ""
                )
            }
            let zeroItems = object["zero_items"] as? [[String: Any]] ?? []
            next += zeroItems.map {
                InventoryPreviewRow(
                    travelerName: $0["name"] as? String ?? "",
                    productCode: "—",
                    productName: "数量为 0，不出库",
                    quantity: 0,
                    source: "Traveler 数量为 0",
                    status: "零数量",
                    section: $0["section"] as? String ?? ""
                )
            }
            let missing = object["missing_items"] as? [[String: Any]] ?? []
            next += missing.compactMap {
                guard let name = $0["name"] as? String, !name.isEmpty else { return nil }
                return InventoryPreviewRow(
                    travelerName: name,
                    productCode: "未找到",
                    productName: "请选择忽略，或补充商品映射",
                    quantity: $0["quantity"] as? Double ?? 0,
                    source: $0["message"] as? String ?? "未找到唯一库存商品",
                    status: "未映射",
                    section: $0["section"] as? String ?? ""
                )
            }
            if object["ready"] as? Bool != true {
                self.inventoryErrors += missing.map { $0["message"] as? String ?? "存在未映射材料" }
            }
            self.finishRunningInventoryStep(
                object["ready"] as? Bool == true ? "文件结构、数量和商品映射检查通过" : "存在未映射或无效材料",
                object["ready"] as? Bool == true ? "success" : "failure"
            )
            self.previewNext(paths, index: index + 1, accumulated: next)
        }
    }

    private func runInventory(_ arguments: [String], manageRunning: Bool = true, completion: @escaping ([String: Any]) -> Void) {
        if manageRunning {
            guard !inventoryRunning else { return }
            inventoryRunning = true
            inventoryStatus = "正在检查 Traveler 和商品资料…"
            inventoryStderrBuffer = ""
            inventoryRawErrors = ""
        }
        let root = projectRoot
        let command = root.appendingPathComponent("scripts/traveler-assistant")
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = command
            process.arguments = ["inventory"] + arguments
            process.currentDirectoryURL = root
            process.standardOutput = output
            process.standardError = errors
            errors.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self.consumeInventoryLogChunk(chunk) }
            }
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errors.fileHandleForReading.readabilityHandler = nil
                let remainder = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.inventoryRunning = false
                    if !remainder.isEmpty { self.consumeInventoryLogChunk(remainder + "\n") }
                    if !self.inventoryStderrBuffer.isEmpty {
                        self.consumeInventoryLogChunk("\n")
                    }
                    let errorText = self.inventoryRawErrors.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        let reason = errorText.isEmpty ? "后台没有返回有效 JSON 结果" : errorText
                        self.inventoryStatus = "❌ 无法解析库存预检结果"
                        self.finishRunningInventoryStep(reason, "failure")
                        return
                    }
                    if let fatal = object["fatal"] as? [String: Any] {
                        let reason = fatal["message"] as? String ?? "库存预检失败"
                        self.inventoryStatus = "❌ \(reason)"
                        self.finishRunningInventoryStep(reason, "failure")
                        return
                    }
                    completion(object)
                }
            } catch {
                DispatchQueue.main.async {
                    self.inventoryRunning = false
                    self.inventoryStatus = "❌ 无法启动库存功能：\(error.localizedDescription)"
                    self.finishRunningInventoryStep(error.localizedDescription, "failure")
                }
            }
        }
    }

    private func beginInventoryOperation(_ title: String) {
        inventorySuccessMessage = ""
        addInventoryStep(title, "任务已开始", "running")
    }

    private func addInventoryStep(_ title: String, _ detail: String, _ state: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        inventorySteps.append(InventoryStep(time: formatter.string(from: Date()), title: title, detail: detail, state: state))
    }

    private func finishRunningInventoryStep(_ detail: String, _ state: String) {
        guard let index = inventorySteps.lastIndex(where: { $0.state == "running" }) else {
            addInventoryStep(state == "failure" ? "操作失败" : "操作完成", detail, state)
            return
        }
        let current = inventorySteps[index]
        inventorySteps[index] = InventoryStep(time: current.time, title: current.title, detail: detail, state: state)
    }

    private func consumeInventoryLogChunk(_ chunk: String) {
        inventoryStderrBuffer += chunk
        let parts = inventoryStderrBuffer.components(separatedBy: "\n")
        inventoryStderrBuffer = parts.last ?? ""
        for line in parts.dropLast() where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["event"] as? String == "progress",
                  let message = event["message"] as? String else {
                inventoryRawErrors += line + "\n"
                continue
            }
            addInventoryStep("后台操作", message, "success")
        }
    }

    private func addOrderStep(_ title: String, _ detail: String, _ state: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        orderSteps.append(InventoryStep(time: formatter.string(from: Date()), title: title, detail: detail, state: state))
    }

    private func finishOrderStep(_ detail: String, _ state: String) {
        guard let index = orderSteps.lastIndex(where: { $0.state == "running" }) else {
            addOrderStep(state == "failure" ? "操作失败" : "操作完成", detail, state)
            return
        }
        let current = orderSteps[index]
        orderSteps[index] = InventoryStep(time: current.time, title: current.title, detail: detail, state: state)
    }

    private func consumeOrderLogChunk(_ chunk: String) {
        orderStderrBuffer += chunk
        let parts = orderStderrBuffer.components(separatedBy: "\n")
        orderStderrBuffer = parts.last ?? ""
        for line in parts.dropLast() where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["event"] as? String == "progress",
                  let message = event["message"] as? String else {
                orderRawErrors += line + "\n"
                continue
            }
            addOrderStep("后台校验", message, "success")
        }
    }

    private func runOrder(_ arguments: [String], completion: @escaping ([String: Any]) -> Void) {
        guard !orderRunning else { return }
        orderRunning = true
        orderError = ""
        orderCreatedPath = ""
        orderStderrBuffer = ""
        orderRawErrors = ""
        let root = projectRoot
        let command = root.appendingPathComponent("scripts/traveler-assistant")
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = command
            process.arguments = ["order"] + arguments
            process.currentDirectoryURL = root
            process.standardOutput = output
            process.standardError = errors
            errors.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self.consumeOrderLogChunk(chunk) }
            }
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errors.fileHandleForReading.readabilityHandler = nil
                let remainder = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.orderRunning = false
                    if !remainder.isEmpty { self.consumeOrderLogChunk(remainder + "\n") }
                    if !self.orderStderrBuffer.isEmpty { self.consumeOrderLogChunk("\n") }
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        let reason = self.orderRawErrors.isEmpty ? "后台没有返回有效结果" : self.orderRawErrors
                        self.orderError = reason
                        self.orderStatus = "读取失败"
                        self.finishOrderStep(reason, "failure")
                        return
                    }
                    if let fatal = object["fatal"] as? [String: Any] {
                        let reason = fatal["message"] as? String ?? "订单校验失败"
                        self.orderError = reason
                        self.orderStatus = "校验未通过"
                        self.finishOrderStep(reason, "failure")
                        return
                    }
                    completion(object)
                }
            } catch {
                DispatchQueue.main.async {
                    self.orderRunning = false
                    self.orderError = error.localizedDescription
                    self.orderStatus = "无法启动订单读取功能"
                    self.finishOrderStep(error.localizedDescription, "failure")
                }
            }
        }
    }

    func loadOrderFolders() {
        selectedOrderPath = ""
        selectedOrderId = ""
        orderMaterials = []
        orderFittings = []
        orderFactories = []
        orderEdgeBanding = [:]
        orderWarnings = []
        orderExistingTravelerPath = ""
        orderStatus = "正在读取服务器文件夹列表…"
        addOrderStep("读取服务器目录", "只读取订单文件夹名称，不打开 Excel", "running")
        runOrder(["list"]) { object in
            let rows = object["orders"] as? [[String: Any]] ?? []
            self.orderFolders = rows.map {
                OrderFolderItem(
                    id: $0["path"] as? String ?? UUID().uuidString,
                    orderId: $0["order_id"] as? String ?? "",
                    modifiedAt: $0["modified_at"] as? String ?? ""
                )
            }
            self.orderStatus = "已读取 \(rows.count) 个订单文件夹；点击后才会校验 Excel"
            self.finishOrderStep("找到 \(rows.count) 个 PP/CS 订单文件夹", "success")
        }
    }

    func previewOrderFolder(_ item: OrderFolderItem, recordSelection: Bool = true) {
        selectedOrderPath = item.id
        selectedOrderId = item.orderId
        orderMaterials = []
        orderFittings = []
        orderFactories = []
        orderEdgeBanding = [:]
        orderWarnings = []
        orderMaterialsFile = ""
        orderExistingTravelerPath = findLocalOrderTraveler(item.orderId)
        orderStatus = "正在校验 \(item.orderId)…"
        if recordSelection {
            addOrderStep("选择订单", "\(item.orderId) · \(item.id)", "success")
            if !orderExistingTravelerPath.isEmpty {
                addOrderStep(
                    "发现本机 Traveler",
                    orderExistingTravelerPath,
                    "success"
                )
            }
        }
        addOrderStep("读取并校验", "materials、板材清单和 Fittingslist", "running")
        runOrder(["preview", "--folder", item.id]) { object in
            self.applyOrderPreview(object)
            self.orderStatus = self.orderExistingTravelerPath.isEmpty
                ? "\(item.orderId) 校验通过，可以选择忽略五金或生成 Traveler"
                : "\(item.orderId) 校验通过，已找到本机 Traveler，可直接更新"
            self.finishOrderStep(
                "发现 \(self.orderFactories.count) 个工厂单、\(self.orderFittings.count) 项五金",
                self.orderWarnings.isEmpty ? "success" : "warning"
            )
            for warning in self.orderWarnings {
                self.addOrderStep("数据选择提醒", warning, "warning")
            }
        }
    }

    private func findLocalOrderTraveler(_ orderId: String) -> String {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: orderRoot, isDirectory: true)
        var folder = root.appendingPathComponent(orderId, isDirectory: true)
        var isDirectory: ObjCBool = false
        if !manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            let folders = (try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            if let matchingFolder = folders.first(where: {
                $0.lastPathComponent.caseInsensitiveCompare(orderId) == .orderedSame
            }) {
                folder = matchingFolder
            } else {
                return ""
            }
        }
        let expectedName = "Work Order Traveler(\(orderId)).xlsx"
        let expected = folder.appendingPathComponent(expectedName)
        if manager.fileExists(atPath: expected.path) {
            return expected.path
        }
        let files = (try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(expectedName) == .orderedSame
        })?.path ?? ""
    }

    private func applyOrderPreview(_ object: [String: Any]) {
        selectedOrderId = object["order_id"] as? String ?? selectedOrderId
        orderMaterialsFile = object["materials_file"] as? String ?? ""
        if let existing = object["existing_traveler"] as? String, !existing.isEmpty {
            orderExistingTravelerPath = existing
        }
        orderWarnings = object["warnings"] as? [String] ?? []
        orderMaterials = (object["materials"] as? [[String: Any]] ?? []).map {
            OrderMaterialPreview(
                kind: $0["kind"] as? String ?? "",
                thickness: ($0["thickness"] as? NSNumber)?.doubleValue ?? 0,
                color: $0["color"] as? String ?? "",
                quantity: ($0["quantity"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        orderEdgeBanding = (object["edge_banding"] as? [String: NSNumber] ?? [:])
            .mapValues(\.doubleValue)
        var factories: [OrderFactoryPreview] = []
        var fittings: [OrderFittingPreview] = []
        for factory in object["factories"] as? [[String: Any]] ?? [] {
            let number = factory["factory_order"] as? String ?? ""
            let name = factory["order_name"] as? String ?? ""
            factories.append(OrderFactoryPreview(id: number, factoryOrder: number, orderName: name))
            for fitting in factory["fittings"] as? [[String: Any]] ?? [] {
                let key = fitting["key"] as? String ?? UUID().uuidString
                fittings.append(OrderFittingPreview(
                    id: number + ":" + key,
                    key: key,
                    factoryOrder: number,
                    orderName: name,
                    name: fitting["name"] as? String ?? "",
                    code: fitting["code"] as? String ?? "",
                    size: fitting["size"] as? String ?? "",
                    unit: fitting["unit"] as? String ?? "",
                    quantity: (fitting["quantity"] as? NSNumber)?.doubleValue ?? 0,
                    ignored: fitting["ignored"] as? Bool ?? false
                ))
            }
        }
        orderFactories = factories
        orderFittings = fittings
    }

    func setOrderFittingsIgnored(_ rows: [OrderFittingPreview], ignored: Bool) {
        let names = Array(Set(rows.map(\.name).filter { !$0.isEmpty })).sorted()
        guard !names.isEmpty else {
            addOrderStep(
                ignored ? "无法忽略五金" : "无法恢复五金",
                "请先选择需要处理的五金",
                "failure"
            )
            return
        }
        addOrderStep(
            ignored ? "全局忽略选中五金" : "恢复选中五金",
            "\(names.joined(separator: "、"))；设置将与出库页面共享，并对所有订单生效",
            "running"
        )
        var arguments = ["set-ignore", "--ignored", ignored ? "true" : "false"]
        for name in names {
            arguments += ["--name", name]
        }
        runOrder(arguments) { _ in
            self.finishOrderStep(
                ignored ? "忽略清单已保存，正在重新读取当前订单" : "已从忽略清单移除，正在重新读取当前订单",
                "success"
            )
            guard let current = self.orderFolders.first(where: { $0.id == self.selectedOrderPath }) else { return }
            self.previewOrderFolder(current, recordSelection: false)
        }
    }

    func generateSelectedOrder() {
        guard !selectedOrderPath.isEmpty, orderError.isEmpty, !orderFactories.isEmpty else {
            orderStatus = "请先选择并通过校验"
            addOrderStep("无法生成 Traveler", "请先选择订单并完成全部校验", "failure")
            return
        }
        let updating = !orderExistingTravelerPath.isEmpty
        let action = updating ? "更新 Traveler" : "生成 Traveler"
        addOrderStep(action, "操作前重新读取全部源文件，避免预览后数据发生变化", "running")
        runOrder([updating ? "update" : "generate", "--folder", selectedOrderPath]) { object in
            self.applyOrderPreview(object)
            self.orderCreatedPath = (object[updating ? "updated" : "created"] as? String) ?? ""
            self.orderExistingTravelerPath = self.orderCreatedPath
            self.orderStatus = updating ? "Traveler 已更新" : "Traveler 已生成"
            let backup = object["backup"] as? String ?? ""
            let detail = backup.isEmpty
                ? "\(updating ? "已更新" : "已生成")：\(self.orderCreatedPath)"
                : "已更新：\(self.orderCreatedPath)；原文件备份：\(backup)"
            self.finishOrderStep(detail, "success")
        }
    }

    func openSelectedOrderTraveler() {
        guard !orderExistingTravelerPath.isEmpty else {
            addOrderStep("无法打开 Traveler", "当前订单尚未生成 Traveler", "failure")
            return
        }
        let url = URL(fileURLWithPath: orderExistingTravelerPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            addOrderStep("无法打开 Traveler", "文件不存在：\(url.path)", "failure")
            return
        }
        if NSWorkspace.shared.open(url) {
            addOrderStep("打开 Traveler", url.lastPathComponent, "success")
        } else {
            addOrderStep("无法打开 Traveler", "系统未能打开：\(url.path)", "failure")
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
        let time = formatter.string(from: Date())
        activityLines.append("[\(time)] \(message)")
        legacySteps.append(InventoryStep(time: time, title: "旧版扫描", detail: message, state: "success"))
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        legacySteps.append(InventoryStep(time: formatter.string(from: Date()), title: "旧版扫描失败", detail: message, state: "failure"))
        details = (activityLines + ["", "❌ \(message)"]).joined(separator: "\n")
    }

    func openOrders() {
        NSWorkspace.shared.open(URL(fileURLWithPath: orderRoot))
    }
}

enum AppLayout {
    static let headerHeight: CGFloat = 86
    static let sidebarMinWidth: CGFloat = 300
    static let sidebarIdealWidth: CGFloat = 340
    static let sidebarMaxWidth: CGFloat = 380
    static let contentMinWidth: CGFloat = 680
    static let contentPadding: CGFloat = 18
    static let statusHeight: CGFloat = 38
    static let operationRowHeight: CGFloat = 56
    static let operationVisibleRows = 3
    static let operationListHeight: CGFloat = operationRowHeight * CGFloat(operationVisibleRows)
    static let operationLogHeight: CGFloat = 242
    static let windowMinWidth: CGFloat = 1060
    static let windowMinHeight: CGFloat = 720
}

struct AppPageHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30)).foregroundColor(.accentColor)
                .frame(width: 36, height: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2).fontWeight(.semibold)
                Text(subtitle).foregroundColor(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 22)
        .frame(
            minHeight: AppLayout.headerHeight,
            idealHeight: AppLayout.headerHeight,
            maxHeight: AppLayout.headerHeight,
            alignment: .center
        )
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(100)
    }
}

struct OperationLogCard: View {
    let steps: [InventoryStep]
    let emptyText: String

    var body: some View {
        GroupBox(label: Label("操作记录", systemImage: "list.number")) {
            SelectableOperationLogView(steps: steps, emptyText: emptyText)
                .padding(6)
        }
        .frame(height: AppLayout.operationLogHeight)
    }
}

struct OrderWorkflowView: View {
    @ObservedObject var model: AppModel
    @State private var selectedFittingIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                systemImage: "folder.badge.gearshape",
                title: "生产文件",
                subtitle: "选择服务器订单，预检后生成一份 Traveler"
            ) {
                Button("刷新订单文件夹") { model.loadOrderFolders() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.orderRunning)
            }
            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("服务器订单").font(.headline)
                    Text("这里只读取文件夹名称；点击订单后才打开 Excel。")
                        .font(.caption).foregroundColor(.secondary)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.orderFolders) { item in
                                Button {
                                    model.previewOrderFolder(item)
                                } label: {
                                    HStack {
                                        Image(systemName: model.selectedOrderPath == item.id ? "folder.fill.badge.checkmark" : "folder.fill")
                                            .foregroundColor(.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.orderId).fontWeight(.semibold)
                                            Text(item.modifiedAt).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(9)
                                    .contentShape(Rectangle())
                                    .background(model.selectedOrderPath == item.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(model.orderRunning)
                            }
                        }
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(
                    minWidth: AppLayout.sidebarMinWidth,
                    idealWidth: AppLayout.sidebarIdealWidth,
                    maxWidth: AppLayout.sidebarMaxWidth
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle()
                            .fill(model.orderError.isEmpty ? (model.orderFactories.isEmpty ? Color.secondary : Color.green) : Color.red)
                            .frame(width: 10, height: 10)
                        Text(model.orderStatus).fontWeight(.semibold)
                        Spacer()
                        if model.orderRunning { ProgressView().controlSize(.small) }
                        Button("打开 Traveler") {
                            model.openSelectedOrderTraveler()
                        }
                        .disabled(model.orderExistingTravelerPath.isEmpty)
                        Button(model.orderExistingTravelerPath.isEmpty ? "生成 Traveler" : "更新 Traveler") {
                            model.generateSelectedOrder()
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.orderRunning || !model.orderError.isEmpty || model.orderFactories.isEmpty)
                    }
                    .frame(height: AppLayout.statusHeight)

                    OperationLogCard(
                        steps: model.orderSteps,
                        emptyText: "选择订单后，这里会显示读取、校验和生成过程。"
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !model.selectedOrderId.isEmpty {
                                GroupBox(label: centeredTitle("订单基本信息", systemImage: "doc.text")) {
                                    VStack(alignment: .leading, spacing: 14) {
                                        HStack(spacing: 12) {
                                            summaryCard(
                                                title: "订单号",
                                                value: model.selectedOrderId,
                                                detail: URL(fileURLWithPath: model.orderMaterialsFile).lastPathComponent,
                                                color: .blue
                                            )
                                            summaryCard(
                                                title: "工厂单",
                                                value: "\(model.orderFactories.count)",
                                                detail: "已识别并校验",
                                                color: .purple
                                            )
                                            summaryCard(
                                                title: "材料项目",
                                                value: "\(model.orderMaterials.count + model.orderEdgeBanding.count)",
                                                detail: "板材与封边",
                                                color: .teal
                                            )
                                            summaryCard(
                                                title: "本机 Traveler",
                                                value: model.orderExistingTravelerPath.isEmpty ? "未生成" : "已存在",
                                                detail: model.orderExistingTravelerPath.isEmpty
                                                    ? "生成后保存在订单目录"
                                                    : URL(fileURLWithPath: model.orderExistingTravelerPath).lastPathComponent,
                                                color: model.orderExistingTravelerPath.isEmpty ? .secondary : .green
                                            )
                                        }

                                        if !model.orderExistingTravelerPath.isEmpty {
                                            HStack(spacing: 7) {
                                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                                Text("已找到可更新的 Traveler")
                                                    .fontWeight(.semibold)
                                                Text(model.orderExistingTravelerPath)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .textSelection(.enabled)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(Color.green.opacity(0.07))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }

                                        if !model.orderFactories.isEmpty {
                                            subsectionTitle("工厂单号与名称", color: .purple)
                                            VStack(spacing: 6) {
                                                ForEach(model.orderFactories) { factory in
                                                    HStack {
                                                        Text(factory.factoryOrder)
                                                            .fontWeight(.semibold)
                                                            .frame(width: 130, alignment: .leading)
                                                        Image(systemName: "arrow.right")
                                                            .font(.caption).foregroundColor(.secondary)
                                                        Text(factory.orderName)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                                    .background(Color.purple.opacity(0.06))
                                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                                }
                                            }
                                        }

                                        if !model.orderMaterials.isEmpty {
                                            subsectionTitle("板材用量", color: .teal)
                                            LazyVGrid(
                                                columns: [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 9)],
                                                alignment: .leading,
                                                spacing: 9
                                            ) {
                                                ForEach(model.orderMaterials) { row in
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text(row.kind == "plywood" ? "Plywood" : (row.color.isEmpty ? "Panel" : row.color))
                                                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                                        HStack(alignment: .firstTextBaseline) {
                                                            Text("\(row.thickness.formatted())mm").fontWeight(.semibold)
                                                            Spacer()
                                                            Text(row.quantity.formatted())
                                                                .font(.title3).fontWeight(.bold)
                                                                .foregroundColor(.teal)
                                                        }
                                                    }
                                                    .padding(10)
                                                    .background(Color.teal.opacity(0.07))
                                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 9)
                                                            .stroke(Color.teal.opacity(0.16), lineWidth: 1)
                                                    )
                                                }
                                            }
                                        }

                                        if !model.orderEdgeBanding.isEmpty {
                                            subsectionTitle("封边用量", color: .orange)
                                            LazyVGrid(
                                                columns: [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 9)],
                                                alignment: .leading,
                                                spacing: 9
                                            ) {
                                                ForEach(model.orderEdgeBanding.keys.sorted(), id: \.self) { color in
                                                    HStack {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(color).fontWeight(.medium).lineLimit(1)
                                                            Text("Edge Banding").font(.caption2).foregroundColor(.secondary)
                                                        }
                                                        Spacer()
                                                        Text("\((model.orderEdgeBanding[color] ?? 0).formatted())m")
                                                            .font(.title3).fontWeight(.bold).foregroundColor(.orange)
                                                    }
                                                    .padding(10)
                                                    .background(Color.orange.opacity(0.07))
                                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 9)
                                                            .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                }
                            }

                            if !model.orderFittings.isEmpty {
                                GroupBox(label: centeredTitle("各工厂单五金预览", systemImage: "wrench.and.screwdriver")) {
                                    VStack(spacing: 12) {
                                        ForEach(model.orderFactories) { factory in
                                            let rows = model.orderFittings.filter { $0.factoryOrder == factory.factoryOrder }
                                            VStack(spacing: 0) {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(factory.factoryOrder).fontWeight(.semibold)
                                                        Text(factory.orderName)
                                                            .font(.caption).foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Text("\(rows.count) 项")
                                                        .font(.caption).foregroundColor(.secondary)
                                                }
                                                .padding(10)
                                                .background(Color.accentColor.opacity(0.08))

                                                HStack {
                                                    Text("选择").frame(width: 44)
                                                    Text("名称").frame(width: 160, alignment: .leading)
                                                    Text("Code").frame(width: 90, alignment: .leading)
                                                    Text("规格").frame(width: 125, alignment: .leading)
                                                    Text("单位").frame(width: 65, alignment: .leading)
                                                    Text("数量").frame(width: 60, alignment: .trailing)
                                                }
                                                .font(.caption).foregroundColor(.secondary).padding(.vertical, 6)
                                                Divider()
                                                ForEach(rows) { row in
                                                    HStack {
                                                        Toggle("", isOn: Binding(
                                                            get: { selectedFittingIDs.contains(row.id) },
                                                            set: { checked in
                                                                if checked { selectedFittingIDs.insert(row.id) }
                                                                else { selectedFittingIDs.remove(row.id) }
                                                            }
                                                        ))
                                                        .labelsHidden().frame(width: 44)
                                                        Text(row.name).frame(width: 160, alignment: .leading)
                                                        Text(row.code).frame(width: 90, alignment: .leading)
                                                        Text(row.size.isEmpty ? "—" : row.size).frame(width: 125, alignment: .leading)
                                                        Text(row.unit).frame(width: 65, alignment: .leading)
                                                        Text(row.quantity.formatted()).frame(width: 60, alignment: .trailing)
                                                    }
                                                    .foregroundColor(row.ignored ? .secondary : .primary)
                                                    .opacity(row.ignored ? 0.55 : 1)
                                                    .background(
                                                        selectedFittingIDs.contains(row.id)
                                                            ? Color.accentColor.opacity(0.10)
                                                            : (row.ignored ? Color.gray.opacity(0.08) : Color.clear)
                                                    )
                                                    .padding(.vertical, 6)
                                                    Divider()
                                                }
                                            }
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9)
                                                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                            )
                                        }
                                        HStack(spacing: 10) {
                                            Button("忽略选中五金") {
                                                let rows = model.orderFittings.filter {
                                                    selectedFittingIDs.contains($0.id) && !$0.ignored
                                                }
                                                model.setOrderFittingsIgnored(rows, ignored: true)
                                                selectedFittingIDs.removeAll()
                                            }
                                            Button("恢复选中五金") {
                                                let rows = model.orderFittings.filter {
                                                    selectedFittingIDs.contains($0.id) && $0.ignored
                                                }
                                                model.setOrderFittingsIgnored(rows, ignored: false)
                                                selectedFittingIDs.removeAll()
                                            }
                                            Spacer()
                                            Label(
                                                "忽略清单与出库页面共享，并对所有订单生效",
                                                systemImage: "arrow.triangle.2.circlepath"
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 2)
                                    }
                                    .padding(8)
                                }
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(minWidth: AppLayout.contentMinWidth)
            }
        }
        .frame(minWidth: AppLayout.windowMinWidth, minHeight: AppLayout.windowMinHeight)
        .onAppear {
            if model.orderFolders.isEmpty { model.loadOrderFolders() }
        }
        .onChange(of: model.selectedOrderPath) { _ in
            selectedFittingIDs.removeAll()
        }
    }

    private func summaryCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
            Text(detail.isEmpty ? "—" : detail)
                .font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.16), lineWidth: 1))
    }

    private func subsectionTitle(_ title: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(color).frame(width: 4, height: 17)
            Text(title).font(.subheadline).fontWeight(.semibold)
        }
    }

    private func centeredTitle(_ title: String, systemImage: String) -> some View {
        HStack {
            Spacer()
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                systemImage: "doc.text.magnifyingglass",
                title: "旧版扫描",
                subtitle: "生产订单与 Traveler 历史扫描"
            ) {
                Button("打开订单文件夹") { model.openOrders() }
            }
            Divider()

            HSplitView {
                AnyView(VStack(alignment: .leading, spacing: 12) {
                    GroupBox(label: Label("查询与扫描", systemImage: "magnifyingglass")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("支持 PP0047、F2607020183 或 PP0047-KITCHEN")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("输入订单号、工厂单号或 PP 空间名称", text: $model.query)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button("查询") { model.execute("preview", history: true, query: model.query) }
                                    .disabled(model.running || model.query.isEmpty)
                                Button("预览新变化") { model.execute("preview") }.disabled(model.running)
                            }
                            HStack {
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
                                Button("更新自动字段") { model.execute("update", history: true, query: pending) }
                                    .disabled(model.running)
                                Button("按模板重新生成") { model.execute("rebuild", history: true, query: pending) }
                                    .disabled(model.running)
                            }
                        }
                        .padding(8)
                    }
                    Spacer()
                }
                .padding(AppLayout.contentPadding)
                .frame(
                    minWidth: AppLayout.sidebarMinWidth,
                    idealWidth: AppLayout.sidebarIdealWidth,
                    maxWidth: AppLayout.sidebarMaxWidth
                ))

                AnyView(VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle().fill(model.hasError ? Color.red : Color.green).frame(width: 10, height: 10)
                        Text(model.status).fontWeight(.semibold)
                        Spacer()
                        if model.running { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: AppLayout.statusHeight)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)

                    OperationLogCard(
                        steps: model.legacySteps,
                        emptyText: "运行旧版扫描后，这里会保留可整行选择和复制的操作记录。"
                    )

                    GroupBox(label: Label("运行结果", systemImage: model.hasError ? "exclamationmark.triangle" : "list.bullet.rectangle")) {
                        ScrollView {
                            Text(model.details).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled).padding(10)
                        }
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(minWidth: AppLayout.contentMinWidth))
            }
        }
        .frame(minWidth: AppLayout.windowMinWidth, minHeight: AppLayout.windowMinHeight)
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

struct InventoryStepRowView: View {
    let step: InventoryStep

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            icon.frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.title).fontWeight(.medium)
                    Spacer()
                    Text(step.time).font(.caption2).foregroundColor(.secondary)
                }
                Text(step.detail)
                    .font(.caption)
                    .foregroundColor(step.state == "failure" ? .red : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: AppLayout.operationRowHeight)
        .contextMenu {
            Button("复制整条记录") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "[\(step.time)] \(step.title)\n\(step.detail)",
                    forType: .string
                )
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case "success":
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case "failure":
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case "warning":
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
        default:
            ProgressView().controlSize(.small)
        }
    }
}

struct InventoryOperationLogView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SelectableOperationLogView(
            steps: model.inventorySteps,
            emptyText: "点击“刷新列表”或左侧 Traveler 后，这里会逐步显示正在做什么。"
        )
    }
}

struct SelectableOperationLogView: View {
    let steps: [InventoryStep]
    let emptyText: String
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("点击记录行即可整行选中；按住 Command 可多选")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("复制选中记录") { copySelected() }
                    .controlSize(.small)
                    .disabled(selectedIDs.isEmpty)
            }
            if steps.isEmpty {
                Text(emptyText)
                    .font(.caption).foregroundColor(.secondary)
                    .padding(10)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: AppLayout.operationListHeight,
                        maxHeight: AppLayout.operationListHeight,
                        alignment: .topLeading
                    )
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(steps) { step in
                                Button {
                                    select(step.id)
                                } label: {
                                    InventoryStepRowView(step: step)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(
                                    selectedIDs.contains(step.id)
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                                .overlay(Divider(), alignment: .bottom)
                                .id(step.id)
                            }
                        }
                    }
                    .onAppear { scrollToLatest(proxy) }
                    .onChange(of: steps.map(\.id)) { _ in scrollToLatest(proxy) }
                }
                .frame(height: AppLayout.operationListHeight)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .onChange(of: steps.map(\.id)) { ids in
            selectedIDs = selectedIDs.intersection(Set(ids))
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = steps.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func select(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        } else {
            selectedIDs = [id]
        }
    }

    private func copySelected() {
        let text = steps
            .filter { selectedIDs.contains($0.id) }
            .map { "[\($0.time)] \($0.title)\n\($0.detail)" }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct InventoryTravelerRowView: View {
    let item: InventoryTraveler
    let selected: Bool
    let disabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: selected ? "doc.text.fill" : "doc.text")
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.fileName).lineLimit(1)
                    if !item.orderName.isEmpty {
                        Text(item.orderName)
                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .frame(minHeight: 22, alignment: .center)
                Spacer()
                Text(item.status)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            .padding(.leading, 24).padding(.trailing, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        switch item.status {
        case "已出库": return .green
        case "需要更新": return .orange
        case "失败", "结果未知", "原单据不可编辑": return .red
        default: return .secondary
        }
    }
}

struct InventoryMappingSheet: View {
    @ObservedObject var model: AppModel
    let travelerName: String
    @Binding var isPresented: Bool
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置库存商品映射").font(.title2).fontWeight(.semibold)
                    Text("Traveler 材料：\(travelerName)").foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { isPresented = false }
            }
            HStack {
                TextField("输入商品编号、名称或规格", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.searchInventoryProducts(query) }
                Button("搜索") { model.searchInventoryProducts(query) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.inventoryRunning)
            }
            Text(model.inventoryProductSearchStatus)
                .font(.caption).foregroundColor(.secondary)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.inventoryProductCandidates) { product in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(product.code).fontWeight(.semibold)
                                    Text(product.name)
                                }
                                Text([product.category, product.spec, product.unit]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("使用此商品") {
                                model.saveInventoryMapping(
                                    travelerName: travelerName,
                                    productCode: product.code
                                )
                                isPresented = false
                            }
                            .disabled(model.inventoryRunning)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 480)
        .onAppear {
            query = travelerName
            model.inventoryProductCandidates = []
            model.searchInventoryProducts(query)
        }
    }
}

struct InventoryView: View {
    @ObservedObject var model: AppModel
    @State private var expandedFolders: Set<String> = []
    @State private var confirmRealSave = false
    @State private var selectedPreviewRows: Set<UUID> = []
    @State private var showMappingSheet = false
    @State private var mappingTravelerName = ""

    private var selectedRows: [InventoryTraveler] {
        model.inventoryTravelers.filter { model.selectedInventoryPaths.contains($0.id) }
    }

    private var groupedTravelers: [(String, [InventoryTraveler])] {
        Dictionary(grouping: model.inventoryTravelers, by: \.ppFolder)
            .map { ($0.key, $0.value.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                systemImage: "shippingbox.fill",
                title: "出库",
                subtitle: "点击 Traveler 自动预检材料，再写入其他出库单"
            ) {
                Text(model.inventoryCatalogStatus)
                    .font(.caption).foregroundColor(.secondary)
                Button("更新商品资料") {
                    model.inventoryStatus = "商品资料在线更新将在浏览器流程接通后启用"
                }
                Button("刷新列表") { model.loadInventory() }
                    .buttonStyle(.borderedProminent)
            }
            // The lower HSplitView changes the visual center of this header on
            // macOS 12. Offset the complete header content without changing
            // any shared section height.
            .offset(y: 4)
            Divider()

            HSplitView {
                AnyView(VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Traveler 文件").font(.headline)
                        Spacer()
                        Text("已选 \(selectedRows.count) 份")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Text("展开订单文件夹，点击 Traveler 后自动预检材料。")
                        .font(.caption).foregroundColor(.secondary)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(groupedTravelers, id: \.0) { folder, files in
                                VStack(spacing: 0) {
                                    HStack(spacing: 8) {
                                        Button {
                                            if expandedFolders.contains(folder) { expandedFolders.remove(folder) }
                                            else { expandedFolders.insert(folder) }
                                        } label: {
                                            HStack(spacing: 8) {
                                            Image(systemName: expandedFolders.contains(folder) ? "chevron.down" : "chevron.right")
                                                .font(.caption).frame(width: 14)
                                            Image(systemName: "folder.fill").foregroundColor(.accentColor)
                                            Text(folder).fontWeight(.semibold)
                                            Spacer()
                                            Text("\(files.count)")
                                                .font(.caption).foregroundColor(.secondary)
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            model.refreshInventoryFolder(folder)
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("查询并更新此文件夹下所有文件的出库状态")
                                        .disabled(model.inventoryRunning)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 9)

                                    if expandedFolders.contains(folder) {
                                        Divider()
                                        ForEach(files) { item in
                                            InventoryTravelerRowView(
                                                item: item,
                                                selected: model.selectedInventoryPaths.contains(item.id),
                                                disabled: model.inventoryRunning
                                            ) {
                                                model.selectedInventoryPaths = [item.id]
                                                model.previewSelectedInventory()
                                            }
                                            Divider().padding(.leading, 24)
                                        }
                                    }
                                }
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(
                    minWidth: AppLayout.sidebarMinWidth,
                    idealWidth: AppLayout.sidebarIdealWidth,
                    maxWidth: AppLayout.sidebarMaxWidth
                ))

                AnyView(VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle()
                            .fill(model.inventoryErrors.isEmpty ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(model.inventorySuccessMessage.isEmpty ? model.inventoryStatus : model.inventorySuccessMessage)
                            .fontWeight(.semibold)
                            .foregroundColor(model.inventorySuccessMessage.isEmpty ? .primary : .green)
                            .lineLimit(1)
                        Spacer()
                        if model.inventoryRunning { ProgressView().controlSize(.small) }
                    }
                    .frame(height: AppLayout.statusHeight)

                    OperationLogCard(
                        steps: model.inventorySteps,
                        emptyText: "点击“刷新列表”或左侧 Traveler 后，这里会逐步显示正在做什么。"
                    )

                    GroupBox(label: centeredTitle("Traveler 全材料预览", systemImage: "tablecells")) {
                        VStack(alignment: .leading, spacing: 10) {
                        Text("\(model.inventoryPreviewRows.count) 行 · 已选 \(selectedPreviewRows.count)")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        if model.inventoryPreviewRows.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 36)).foregroundColor(.secondary)
                                Text("点击左侧 Traveler 即可自动预检")
                                Text("所有材料都会显示；未映射项目需补充映射或选择忽略。")
                                    .font(.caption).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            HStack {
                                Text("").frame(width: 22)
                                Text("Traveler 材料").frame(maxWidth: .infinity, alignment: .leading)
                                Text("状态").frame(width: 58, alignment: .leading)
                                Text("商品编号").frame(width: 82, alignment: .leading)
                                Text("库存商品／说明").frame(width: 190, alignment: .leading)
                                Text("数量").frame(width: 58, alignment: .trailing)
                            }.font(.caption).foregroundColor(.secondary)
                            Divider()
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(model.inventoryPreviewRows) { row in
                                        HStack(spacing: 8) {
                                            Toggle("", isOn: Binding(
                                                get: { selectedPreviewRows.contains(row.id) },
                                                set: { checked in
                                                    if checked { selectedPreviewRows.insert(row.id) }
                                                    else { selectedPreviewRows.remove(row.id) }
                                                }
                                            ))
                                            .labelsHidden()
                                            .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(row.travelerName).lineLimit(1)
                                                Text(row.section).font(.caption2).foregroundColor(.secondary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(row.status)
                                                .font(.caption).fontWeight(.medium)
                                                .foregroundColor(previewStatusColor(row.status))
                                                .frame(width: 58, alignment: .leading)
                                            Text(row.productCode).frame(width: 82, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(row.productName).lineLimit(1)
                                                Text(row.source).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                                            }
                                            .frame(width: 190, alignment: .leading)
                                            Text(row.quantity.formatted())
                                                .frame(width: 58, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 6).padding(.vertical, 7)
                                        .background(row.status == "未映射" ? Color.orange.opacity(0.16) :
                                                    row.status == "已忽略" ? Color.gray.opacity(0.10) : Color.clear)
                                        Divider()
                                    }
                                }
                            }
                        }
                        HStack {
                            Button("忽略选中材料") {
                                let names = model.inventoryPreviewRows
                                    .filter { selectedPreviewRows.contains($0.id) && $0.status != "零数量" }
                                    .map(\.travelerName)
                                model.setInventoryItemsIgnored(names, ignored: true)
                                selectedPreviewRows.removeAll()
                            }
                            Button("恢复选中材料") {
                                let names = model.inventoryPreviewRows
                                    .filter { selectedPreviewRows.contains($0.id) && $0.status == "已忽略" }
                                    .map(\.travelerName)
                                model.setInventoryItemsIgnored(names, ignored: false)
                                selectedPreviewRows.removeAll()
                            }
                            Button("设置映射") {
                                let rows = model.inventoryPreviewRows.filter {
                                    selectedPreviewRows.contains($0.id) && $0.status == "未映射"
                                }
                                if rows.count == 1 {
                                    mappingTravelerName = rows[0].travelerName
                                    showMappingSheet = true
                                } else {
                                    model.inventoryStatus = "请只选择一条“未映射”材料"
                                }
                            }
                            Spacer()
                            if model.inventoryPreviewRows.contains(where: { $0.status == "未映射" }) {
                                Label("未映射材料必须处理后才能出库", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundColor(.orange)
                            }
                        }
                        .disabled(model.inventoryRunning || selectedPreviewRows.isEmpty)
                        HStack {
                            Button("后台模拟填写") { model.openAndFillSelectedInventory() }
                            Button("确认写入库存系统") { confirmRealSave = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(model.inventoryRunning || selectedRows.count != 1 ||
                                  !model.inventoryPreviewRows.contains(where: { $0.status == "已映射" }) ||
                                  !model.inventoryErrors.isEmpty)
                        Text("真实写入会创建库存出库单，并保存本机同步记录。")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(8)
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(minWidth: AppLayout.contentMinWidth))
            }
        }
        .frame(minWidth: AppLayout.windowMinWidth, minHeight: AppLayout.windowMinHeight)
        .onAppear { if model.inventoryTravelers.isEmpty { model.loadInventory() } }
        .onChange(of: model.inventoryPreviewRows.map(\.id)) { _ in
            selectedPreviewRows = selectedPreviewRows.intersection(Set(model.inventoryPreviewRows.map(\.id)))
        }
        .alert("确认真实写入库存系统？", isPresented: $confirmRealSave) {
            Button("取消", role: .cancel) {}
            Button("确认保存", role: .destructive) {
                model.openAndFillSelectedInventory(confirmSave: true)
            }
        } message: {
            Text("将为当前选择的 1 份 Traveler 创建真实的“其他出库单”。保存后会影响库存，且每项网页警告仍会停止任务。")
        }
        .sheet(isPresented: $showMappingSheet) {
            InventoryMappingSheet(
                model: model,
                travelerName: mappingTravelerName,
                isPresented: $showMappingSheet
            )
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "已出库": return .green
        case "需要更新": return .orange
        case "失败", "结果未知", "原单据不可编辑": return .red
        default: return .secondary
        }
    }

    private func previewStatusColor(_ status: String) -> Color {
        switch status {
        case "已映射": return .green
        case "未映射": return .orange
        case "已忽略", "零数量": return .secondary
        default: return .primary
        }
    }

    private func centeredTitle(_ title: String, systemImage: String) -> some View {
        HStack {
            Spacer()
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stepIcon(_ state: String) -> some View {
        switch state {
        case "success":
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case "failure":
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case "warning":
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
        default:
            ProgressView().controlSize(.small)
        }
    }
}

struct TodoView: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: UUID?
    @State private var newContent = ""
    @State private var hasDeadline = false
    @State private var newDeadline = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var editingItem: TodoItem?
    @State private var pendingDelete: TodoItem?

    private var sortedItems: [TodoItem] {
        model.todoItems.sorted { left, right in
            let leftDone = left.completedAt != nil
            let rightDone = right.completedAt != nil
            if leftDone != rightDone { return !leftDone }
            if !leftDone {
                switch (left.deadline, right.deadline) {
                case let (leftDate?, rightDate?):
                    if leftDate != rightDate { return leftDate < rightDate }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }
            return left.startedAt > right.startedAt
        }
    }

    private var selectedItem: TodoItem? {
        guard let selectedID else { return nil }
        return model.todoItems.first { $0.id == selectedID }
    }

    private var openCount: Int {
        model.todoItems.filter { $0.completedAt == nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                systemImage: "checkmark.square.fill",
                title: "待办事项",
                subtitle: "记录需要处理的工作，完成后自动保存完成时间"
            ) {
                Label("\(openCount) 项未完成", systemImage: "circle.dashed")
                    .font(.callout).foregroundColor(.secondary)
            }
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("截止时间")
                                .frame(width: 230, alignment: .leading)
                            Divider()
                            Text("任务内容")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 16)
                        }
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(Color(nsColor: .controlBackgroundColor))
                        Divider()

                        if sortedItems.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 38))
                                    .foregroundColor(.secondary)
                                Text("还没有待办事项")
                                Text("在下方输入任务内容即可添加。")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(sortedItems) { item in
                                        todoRow(item)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(selectedItem?.completedAt == nil ? "完成任务" : "恢复任务") {
                        if let selectedItem { model.toggleTodoCompletion(selectedItem) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedItem == nil)

                    Button("编辑") {
                        editingItem = selectedItem
                    }
                    .disabled(selectedItem == nil)

                    Button("删除", role: .destructive) {
                        pendingDelete = selectedItem
                    }
                    .disabled(selectedItem == nil)

                    Spacer()
                    if let message = todoSelectionMessage {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }

                GroupBox(label: Label("添加待办", systemImage: "plus.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("任务内容")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("输入需要完成的任务", text: $newContent)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .frame(minHeight: 40)
                            .onSubmit { addTodo() }

                        HStack(spacing: 14) {
                            Toggle("设置截止时间", isOn: $hasDeadline)
                                .toggleStyle(.checkbox)
                                .fixedSize()
                            DatePicker(
                                "截止时间",
                                selection: $newDeadline,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .frame(width: 190)
                            .disabled(!hasDeadline)
                            .opacity(hasDeadline ? 1 : 0.45)
                            Spacer()
                            Button {
                                addTodo()
                            } label: {
                                Label("添加待办事项", systemImage: "plus")
                                    .frame(minWidth: 118)
                            }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                            .disabled(newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(12)
                }

                if !model.todoStatus.isEmpty {
                    Label(model.todoStatus, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.red)
                }
            }
            .padding(AppLayout.contentPadding)
        }
        .frame(minWidth: AppLayout.windowMinWidth, minHeight: AppLayout.windowMinHeight)
        .sheet(item: $editingItem) { item in
            TodoEditorSheet(model: model, item: item)
        }
        .alert("删除待办事项？", isPresented: deleteAlertBinding) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let item = pendingDelete {
                    model.deleteTodo(item)
                    if selectedID == item.id { selectedID = nil }
                }
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.content ?? "")
        }
    }

    @ViewBuilder
    private func todoRow(_ item: TodoItem) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(deadlineText(item.deadline))
                    .foregroundColor(deadlineColor(item))
                    .lineLimit(1)
                Spacer()
                if let badge = deadlineBadge(item) {
                    Text(badge)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(deadlineColor(item))
                }
            }
            .padding(.horizontal, 14)
            .frame(width: 230, alignment: .leading)

            Divider()

            HStack(spacing: 10) {
                Button {
                    model.toggleTodoCompletion(item)
                } label: {
                    Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(item.completedAt == nil ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.completedAt == nil ? "标记为已完成" : "恢复为未完成")

                Text(item.content)
                    .strikethrough(item.completedAt != nil)
                    .foregroundColor(item.completedAt == nil ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 54)
        .background(selectedID == item.id ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedID = item.id }
        .contextMenu {
            Button(item.completedAt == nil ? "完成任务" : "恢复任务") {
                model.toggleTodoCompletion(item)
            }
            Button("编辑") { editingItem = item }
            Divider()
            Button("删除") { pendingDelete = item }
        }
        .overlay(Divider(), alignment: .bottom)
        .opacity(item.completedAt == nil ? 1 : 0.62)
    }

    private var todoSelectionMessage: String? {
        guard let selectedItem else { return "点击一行以选择任务" }
        return selectedItem.completedAt == nil ? "未完成" : "已完成"
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func addTodo() {
        model.addTodo(content: newContent, deadline: hasDeadline ? newDeadline : nil)
        guard model.todoStatus.isEmpty else { return }
        newContent = ""
        hasDeadline = false
        newDeadline = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private func deadlineText(_ date: Date?) -> String {
        guard let date else { return "无截止时间" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func deadlineBadge(_ item: TodoItem) -> String? {
        guard item.completedAt == nil, let deadline = item.deadline else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deadlineDay = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: today, to: deadlineDay).day ?? 0
        if days < 0 { return "已逾期" }
        if days == 0 { return "今天到期" }
        if days == 1 { return "明天到期" }
        return nil
    }

    private func deadlineColor(_ item: TodoItem) -> Color {
        guard item.completedAt == nil, let deadline = item.deadline else { return .secondary }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deadlineDay = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: today, to: deadlineDay).day ?? 0
        if days < 0 { return .red }
        if days <= 1 { return .orange }
        return .primary
    }
}

struct TodoEditorSheet: View {
    @ObservedObject var model: AppModel
    let item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date

    init(model: AppModel, item: TodoItem) {
        self.model = model
        self.item = item
        _content = State(initialValue: item.content)
        _hasDeadline = State(initialValue: item.deadline != nil)
        _deadline = State(
            initialValue: item.deadline
                ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())
                ?? Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑待办事项").font(.title2).fontWeight(.semibold)
            TextField("任务内容", text: $content)
                .textFieldStyle(.roundedBorder)
            Toggle("设置截止时间", isOn: $hasDeadline)
                .toggleStyle(.checkbox)
            DatePicker(
                "截止时间",
                selection: $deadline,
                displayedComponents: [.date, .hourAndMinute]
            )
            .disabled(!hasDeadline)
            .opacity(hasDeadline ? 1 : 0.45)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    model.updateTodo(item, content: content, deadline: hasDeadline ? deadline : nil)
                    if model.todoStatus.isEmpty { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                systemImage: "gearshape",
                title: "配置中心",
                subtitle: "常规设置与业务规则保存在本机，不写入项目源码"
            ) {
                Button {
                    model.loadSettings()
                    model.loadBusinessRules()
                    model.settingsStatus = "已重新载入本机设置和业务规则。"
                } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
                }
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 18) {
                    HStack(alignment: .top, spacing: 18) {
                    SettingsCard(title: "运行范围", symbol: "slider.horizontal.3", minHeight: 350) {
                        VStack(alignment: .leading, spacing: 12) {
                            DatePicker("初始扫描日期", selection: $model.initialDate, displayedComponents: .date)
                            TextField("公司 Wi-Fi", text: $model.companyWiFi)
                                .textFieldStyle(.roundedBorder)
                            RuleNumberRow(label: "可疑尺寸容差", value: $model.leftoverThreshold)
                            Text("程序只在你手工点击运行后执行。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    SettingsCard(title: "系统账户", symbol: "lock.shield", minHeight: 350) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AIMES").font(.subheadline).fontWeight(.semibold)
                            TextField("用户名", text: $model.aimesUsername)
                                .textFieldStyle(.roundedBorder)
                            SecureField("输入新密码", text: $model.aimesPassword)
                                .textFieldStyle(.roundedBorder)
                            Button("更新钥匙串密码") { model.saveAimesPassword() }
                                .disabled(model.aimesPassword.isEmpty)
                            Text("用户名保存在本机设置；密码只保存在macOS钥匙串。")
                                .font(.caption).foregroundColor(.secondary)
                            Divider()
                            Text("库存系统").font(.subheadline).fontWeight(.semibold)
                            TextField("用户名", text: $model.jdyUsername)
                                .textFieldStyle(.roundedBorder)
                            SecureField("输入新密码", text: $model.jdyPassword)
                                .textFieldStyle(.roundedBorder)
                            Button("更新库存系统钥匙串密码") { model.saveJdyPassword() }
                                .disabled(model.jdyPassword.isEmpty)
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
                .padding(AppLayout.contentPadding)
            }
        }
        .frame(minWidth: AppLayout.windowMinWidth, minHeight: AppLayout.windowMinHeight)
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
                OrderWorkflowView(model: model)
                    .tabItem { Label("生产文件", systemImage: "folder.badge.gearshape") }
                // TODO(legacy-ui-removal): 旧版扫描入口暂时隐藏。业务逻辑继续备用，
                // 待新版流程稳定并由用户确认后，再删除 ContentView 及旧版界面代码。
                InventoryView(model: model)
                    .tabItem { Label("出库", systemImage: "shippingbox.fill") }
                TodoView(model: model)
                    .tabItem { Label("待办事项", systemImage: "checkmark.square.fill") }
                SettingsView(model: model)
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
        }
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
