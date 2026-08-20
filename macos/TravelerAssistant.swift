import SwiftUI
import AppKit
import Security

func businessFriendlyMessage(_ raw: String, operation: String) -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = "\(operation)未完成。请重试；如果仍然失败，请检查相关文件、网络和登录状态后再操作。"
    guard !text.isEmpty else { return fallback }
    let lowered = text.lowercased()
    if lowered.contains("permission denied") || lowered.contains("not permitted") {
        return "\(operation)未完成：App 没有访问所需文件或目录的权限。请在系统设置中允许访问后重试。"
    }
    if lowered.contains("no such file") || lowered.contains("file doesn’t exist") || lowered.contains("file doesn't exist") {
        return "\(operation)未完成：找不到所需文件或目录。请确认文件没有被移动或删除后重试。"
    }
    if text.contains("左侧“仓库”菜单未在等待时间内加载完成") {
        return "\(operation)未完成：库存业务工作台已打开，但左侧“仓库”菜单还没有加载完成。请保持库存系统页面可见后重试。"
    }
    if text.contains("左侧“商品”菜单未在等待时间内加载完成") {
        return "\(operation)未完成：库存业务工作台已打开，但左侧“商品”菜单还没有加载完成。请保持库存系统页面可见后重试。"
    }
    if lowered.contains("otheroutbound_menu") || text.contains("仓库菜单已打开，但找不到") {
        return "\(operation)未完成：已找到左侧“仓库”菜单，但“其他出库单”入口没有出现。请保持库存系统页面可见后重试。"
    }
    if text.contains("找不到其他出库单记录列表") || text.contains("记录列表控件未加载完成") {
        return "\(operation)未完成：已进入“其他出库单”，但记录列表还没有加载完成。请保持库存系统页面可见后重试。"
    }
    if text.contains("内嵌表单") || text.contains("编辑表单未加载完成") {
        return "\(operation)未完成：已进入“其他出库单”，但出库表单还没有加载完成。请保持库存系统页面可见后重试。"
    }
    if lowered.contains("timed out") || lowered.contains("timeout") || lowered.contains("network") || lowered.contains("connection refused") {
        return "\(operation)未完成：网络或业务系统暂时没有响应。请确认网络连接正常，稍后重试。"
    }
    if lowered.contains("database is locked") {
        return "\(operation)未完成：订单数据库正在被其他任务使用。请等待当前任务结束后重试。"
    }
    if lowered.contains("keychain") || lowered.contains("osstatus") || text.contains("状态码") {
        return "\(operation)未完成：macOS 钥匙串没有成功保存或读取账号信息。请重新输入密码并保存；仍失败时检查 App 的钥匙串访问权限。"
    }
    let technicalMarkers = [
        "traceback", "error domain=", "nsposixerrordomain", "sqlite3.", "file \"",
        "exit status", "valid json", "json result", "status code", "error code",
        "missing_materials", "material_generation_failed", "exception:", "errno ",
        "cannot access local variable", "unboundlocalerror", "nameerror", "attributeerror", "typeerror",
        " code=", "错误代码", "异常代码",
    ]
    if technicalMarkers.contains(where: { lowered.contains($0) }) {
        return fallback
    }
    let hasChinese = text.unicodeScalars.contains { scalar in
        (0x4E00...0x9FFF).contains(Int(scalar.value))
    }
    return hasChinese ? text : fallback
}

func inventoryMappingSourceFolderPath(_ path: String) -> String {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let components = url.pathComponents
    if let reportIndex = components.lastIndex(where: {
        $0.caseInsensitiveCompare("Report") == .orderedSame
    }), reportIndex > 0 {
        return NSString.path(withComponents: Array(components[..<reportIndex]))
    }
    return url.pathExtension.isEmpty ? url.path : url.deletingLastPathComponent().path
}

func dashboardFailureMessage(_ failureStatus: String, rawError: String, operation: String) -> String {
    let status = failureStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    return status.isEmpty ? businessFriendlyMessage(rawError, operation: operation) : status
}

struct OrderFolderItem: Identifiable {
    let id: String
    let orderId: String
    let modifiedAt: String
}

struct OrderDashboardFactory: Identifiable {
    let id: String
    let factoryOrder: String
    let orderId: String
    let orderName: String
    let nameSource: String
    let reportState: String
    let ownershipStatus: String
    let hasHardware: Bool
    let optimized: Bool
    let outboundStatus: String
    let outboundDocument: String
}

struct OrderInstallationDay: Identifiable, Equatable {
    let id: String
    let date: String
    let installer: String

    init(date: String, installer: String) {
        self.id = "\(date)|\(installer)"
        self.date = date
        self.installer = installer
    }
}

struct OrderDashboardItem: Identifiable {
    let id: String
    let orderId: String
    let orderType: String
    let sourceFolder: String
    let modifiedAt: String
    let validationStatus: String
    let validationMessage: String
    let stage: String
    let materialStatus: String
    let factoryCount: Int
    let optimizedCount: Int
    let shippedCount: Int
    let optimizationProgress: String
    let outboundProgress: String
    let userNote: String
    let plannedInstallationDays: [OrderInstallationDay]
    let actualInstallationDays: [OrderInstallationDay]
    let factories: [OrderDashboardFactory]
}

struct ServerChangePreview: Identifiable {
    let id: String
    let changeType: String
    let kind: String
    let orderId: String
    let sourceFolder: String
    let path: String
    let oldPath: String
    let message: String
    let manualOnly: Bool
    let eventTime: String

    init(
        id: String,
        changeType: String,
        kind: String,
        orderId: String,
        sourceFolder: String,
        path: String,
        oldPath: String = "",
        message: String,
        manualOnly: Bool,
        eventTime: String
    ) {
        self.id = id
        self.changeType = changeType
        self.kind = kind
        self.orderId = orderId
        self.sourceFolder = sourceFolder
        self.path = path
        self.oldPath = oldPath
        self.message = message
        self.manualOnly = manualOnly
        self.eventTime = eventTime
    }
}

struct ServerWriteMaterialPreview: Identifiable {
    let id: String
    let materialID: Int
    let sourceOrderID: String
    let materialType: String
    let color: String
    let thickness: String
    let quantity: Double
    let unit: String
    let edge: String
    let sourcePath: String

    init?(row: [String: Any], index: Int) {
        let materialID = (row["material_id"] as? NSNumber)?.intValue ?? index
        let materialType = row["material_type"] as? String ?? ""
        let color = row["color"] as? String ?? ""
        let thickness = row["thickness"] as? String ?? ""
        guard !materialType.isEmpty || !color.isEmpty else { return nil }
        self.id = "\(materialID)"
        self.materialID = materialID
        self.sourceOrderID = row["source_order_id"] as? String ?? ""
        self.materialType = materialType
        self.color = color
        self.thickness = thickness
        self.quantity = (row["quantity"] as? NSNumber)?.doubleValue ?? 0
        self.unit = row["unit"] as? String ?? ""
        self.edge = row["edge"] as? String ?? ""
        self.sourcePath = row["source_path"] as? String ?? ""
    }
}

struct ServerWriteHardwarePreview: Identifiable {
    let id: String
    let productCode: String
    let name: String
    let spec: String
    let quantity: Double
    let unit: String

    init?(row: [String: Any], index: Int) {
        let code = row["product_code"] as? String ?? ""
        let name = row["name"] as? String ?? ""
        guard !code.isEmpty || !name.isEmpty else { return nil }
        self.id = "\(index)|\(code)|\(name)"
        self.productCode = code
        self.name = name
        self.spec = row["spec"] as? String ?? ""
        self.quantity = (row["quantity"] as? NSNumber)?.doubleValue ?? 0
        self.unit = row["unit"] as? String ?? ""
    }
}

struct ServerWriteFactoryPreview: Identifiable {
    let id: String
    let factoryOrder: String
    let factoryName: String
    let salesOrderName: String
    let sourceFolder: String
    let ownershipStatus: String
    let reportState: String
    let batchID: String
    let hardware: [ServerWriteHardwarePreview]

    init?(row: [String: Any]) {
        let number = row["factory_order"] as? String ?? ""
        guard !number.isEmpty else { return nil }
        self.id = number
        self.factoryOrder = number
        self.factoryName = row["factory_name"] as? String ?? ""
        self.salesOrderName = row["sales_order_name"] as? String ?? ""
        self.sourceFolder = row["source_folder"] as? String ?? ""
        self.ownershipStatus = row["ownership_status"] as? String ?? ""
        self.reportState = row["report_state"] as? String ?? ""
        self.batchID = row["production_batch_id"] as? String ?? (row["production_batch_id"] as? NSNumber)?.stringValue ?? ""
        self.hardware = (row["hardware"] as? [[String: Any]] ?? []).enumerated().compactMap {
            ServerWriteHardwarePreview(row: $0.element, index: $0.offset)
        }
    }
}

struct ServerWriteOrderPreview: Identifiable {
    let id: String
    let orderID: String
    let sourceFolder: String
    let validationStatus: String
    let validationMessage: String
    let materials: [ServerWriteMaterialPreview]
    let factories: [ServerWriteFactoryPreview]

    init(
        id: String,
        orderID: String,
        sourceFolder: String,
        validationStatus: String,
        validationMessage: String,
        materials: [ServerWriteMaterialPreview],
        factories: [ServerWriteFactoryPreview]
    ) {
        self.id = id
        self.orderID = orderID
        self.sourceFolder = sourceFolder
        self.validationStatus = validationStatus
        self.validationMessage = validationMessage
        self.materials = materials
        self.factories = factories
    }

    init?(row: [String: Any]) {
        let orderID = row["order_id"] as? String ?? ""
        guard !orderID.isEmpty else { return nil }
        self.id = orderID
        self.orderID = orderID
        self.sourceFolder = row["source_folder"] as? String ?? ""
        self.validationStatus = row["validation_status"] as? String ?? ""
        self.validationMessage = row["validation_message"] as? String ?? ""
        self.materials = (row["materials"] as? [[String: Any]] ?? []).enumerated().compactMap {
            ServerWriteMaterialPreview(row: $0.element, index: $0.offset)
        }
        self.factories = (row["factories"] as? [[String: Any]] ?? []).compactMap(ServerWriteFactoryPreview.init)
    }
}

struct ServerWritePreview {
    let token: String
    let sourceFolders: [String]
    let materials: [ServerWriteMaterialPreview]
    let orders: [ServerWriteOrderPreview]

    init(token: String, sourceFolders: [String], materials: [ServerWriteMaterialPreview], orders: [ServerWriteOrderPreview]) {
        self.token = token
        self.sourceFolders = sourceFolders
        self.materials = materials
        self.orders = orders
    }

    init?(object: [String: Any]) {
        guard let payload = object["server_write_preview"] as? [String: Any],
              let token = payload["token"] as? String, !token.isEmpty else { return nil }
        let materials = (payload["materials"] as? [[String: Any]] ?? []).enumerated().compactMap {
            ServerWriteMaterialPreview(row: $0.element, index: $0.offset)
        }
        let orders = (payload["orders"] as? [[String: Any]] ?? []).compactMap(ServerWriteOrderPreview.init)
        guard !orders.isEmpty else { return nil }
        self.token = token
        self.sourceFolders = payload["source_folders"] as? [String] ?? []
        self.materials = materials
        self.orders = orders
    }
}

struct ServerFolderChangeGroup: Identifiable {
    let id: String
    let folderPath: String
    let folderName: String
    let orderId: String
    let changes: [ServerChangePreview]
    let manualOnly: Bool

    var requiresManualReview: Bool {
        changes.contains { $0.changeType == "missing_report" }
    }
}

struct PendingCenterItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let status: String
    let folderPath: String
    let folderName: String
    let orderId: String
    let serverGroup: ServerFolderChangeGroup?
    let issues: [CurrentIssue]
    let aimesReviews: [AimesReviewItem]
}

func serverFolderChangeGroups(_ changes: [ServerChangePreview]) -> [ServerFolderChangeGroup] {
    let grouped = Dictionary(grouping: changes) { change in
        change.sourceFolder.isEmpty ? URL(fileURLWithPath: change.path).deletingLastPathComponent().path : change.sourceFolder
    }
    return grouped.map { folderPath, rows in
        let sorted = rows.sorted { lhs, rhs in lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
        let orderID = sorted.map(\.orderId).first(where: { !$0.isEmpty }) ?? ""
        return ServerFolderChangeGroup(
            id: folderPath,
            folderPath: folderPath,
            folderName: URL(fileURLWithPath: folderPath).lastPathComponent,
            orderId: orderID,
            changes: sorted,
            manualOnly: sorted.allSatisfy(\.manualOnly)
        )
    }
    .sorted { lhs, rhs in lhs.folderPath.localizedStandardCompare(rhs.folderPath) == .orderedAscending }
}

func buildPendingCenterItems(
    serverChanges: [ServerChangePreview],
    currentIssues: [CurrentIssue],
    aimesReviews: [AimesReviewItem]
) -> [PendingCenterItem] {
    let groups = serverFolderChangeGroups(serverChanges)
    var attachedIssueIDs = Set<String>()
    var attachedAimesIDs = Set<String>()
    var result: [PendingCenterItem] = []

    func belongs(_ issue: CurrentIssue, to group: ServerFolderChangeGroup) -> Bool {
        guard !issue.path.isEmpty else { return false }
        return issue.path == group.folderPath || issue.path.hasPrefix(group.folderPath + "/")
    }

    for group in groups {
        let issues = currentIssues.filter { issue in
            guard belongs(issue, to: group) else { return false }
            attachedIssueIDs.insert(issue.id)
            return true
        }
        let factoryOrders = Set(issues.map(\.factoryOrder).filter { !$0.isEmpty })
        let reviews = aimesReviews.filter { item in
            guard !item.factoryOrder.isEmpty, factoryOrders.contains(item.factoryOrder) else { return false }
            attachedAimesIDs.insert(item.id)
            return true
        }
        let status: String
        if !reviews.isEmpty || issues.contains(where: { $0.kind == "factory_ownership" || $0.kind == "server_missing_report" }) {
            status = "需人工确认"
        } else if issues.contains(where: { $0.kind == "temporary_processing" && $0.message.contains("未映射材料") }) {
            status = "需人工处理"
        } else if !issues.isEmpty {
            status = "处理失败"
        } else {
            status = "待扫描处理"
        }
        let source = reviews.isEmpty ? "Server" : "Server · AIMES"
        result.append(PendingCenterItem(
            id: "folder:\(group.folderPath)",
            title: group.orderId.isEmpty ? group.folderName : group.orderId,
            subtitle: "\(source) · \(group.folderName)",
            status: status,
            folderPath: group.folderPath,
            folderName: group.folderName,
            orderId: group.orderId,
            serverGroup: group,
            issues: issues,
            aimesReviews: reviews
        ))
    }

    for issue in currentIssues where !attachedIssueIDs.contains(issue.id) {
        let location = issue.path.isEmpty ? "" : URL(fileURLWithPath: issue.path).deletingLastPathComponent().path
        let folderName = location.isEmpty ? "" : URL(fileURLWithPath: location).lastPathComponent
        result.append(PendingCenterItem(
            id: "issue:\(issue.id)",
            title: issue.factoryOrder.isEmpty ? (issue.orderId.isEmpty ? "当前问题" : issue.orderId) : issue.factoryOrder,
            subtitle: issue.kind == "factory_ownership" ? "订单归属问题" : (issue.kind == "server_missing_report" ? "报表检查" : (issue.message.contains("未映射材料") ? "出库前需要材料映射" : "订单处理问题")),
            status: issue.kind == "factory_ownership" || issue.kind == "server_missing_report" ? "需人工确认" : (issue.message.contains("未映射材料") ? "需人工处理" : "处理失败"),
            folderPath: location,
            folderName: folderName,
            orderId: issue.orderId,
            serverGroup: nil,
            issues: [issue],
            aimesReviews: []
        ))
    }

    for item in aimesReviews where !attachedAimesIDs.contains(item.id) {
        result.append(PendingCenterItem(
            id: "aimes:\(item.id)",
            title: item.factoryOrder.isEmpty ? "AIMES 工厂单" : item.factoryOrder,
            subtitle: "AIMES · 工厂单待确认",
            status: "需人工确认",
            folderPath: "",
            folderName: "",
            orderId: item.suggestedOrderID,
            serverGroup: nil,
            issues: [],
            aimesReviews: [item]
        ))
    }

    return result
}

struct CurrentIssue: Identifiable, Equatable {
    let id: String
    let kind: String
    let orderId: String
    let factoryOrder: String
    let path: String
    let message: String
    let firstSeen: String
    let lastSeen: String
}

struct AimesReviewItem: Identifiable, Equatable {
    let id: String
    let ignoreKey: String
    let factoryOrder: String
    let factoryName: String
    let salesOrderName: String
    let reason: String
    let suggestedOrderID: String
    let ignoredAt: String
    let sourcePath: String
}

func aimesReviewItems(_ object: [String: Any], key: String) -> [AimesReviewItem] {
    (object[key] as? [[String: Any]] ?? []).compactMap { row in
        guard let ignoreKey = row["ignore_key"] as? String, !ignoreKey.isEmpty else { return nil }
        return AimesReviewItem(
            id: ignoreKey,
            ignoreKey: ignoreKey,
            factoryOrder: row["factory_order"] as? String ?? "",
            factoryName: row["factory_name"] as? String ?? "",
            salesOrderName: row["sales_order_name"] as? String ?? "",
            reason: row["reason"] as? String ?? "需要人工确认",
            suggestedOrderID: row["suggested_order_id"] as? String ?? "",
            ignoredAt: row["ignored_at"] as? String ?? "",
            sourcePath: object["aimes_source_file"] as? String ?? ""
        )
    }
}

func aimesReviewItemsFromWarnings(_ warnings: [[String: Any]]) -> [AimesReviewItem] {
    warnings.compactMap { row in
        let ignoreKey = row["ignore_key"] as? String ?? ""
        let factoryOrder = row["factory_order"] as? String ?? ""
        guard !ignoreKey.isEmpty, !factoryOrder.isEmpty else { return nil }
        return AimesReviewItem(
            id: ignoreKey,
            ignoreKey: ignoreKey,
            factoryOrder: factoryOrder,
            factoryName: row["factory_name"] as? String ?? "",
            salesOrderName: row["sales_order_name"] as? String ?? "",
            reason: row["reason"] as? String ?? "销售单名称格式不符合规则",
            suggestedOrderID: row["suggested_order_id"] as? String ?? "",
            ignoredAt: "",
            sourcePath: ""
        )
    }
}

func dashboardActivitySteps(_ object: [String: Any], includeChanges: Bool = true) -> [InventoryStep] {
    guard includeChanges else { return [] }
    return (object["changes"] as? [[String: Any]] ?? []).map { row in
        let observed = row["observed_at"] as? String ?? ""
        let time = observed.split(separator: "T").last.map(String.init) ?? observed
        let severity = row["severity"] as? String ?? "info"
        let kind = row["kind"] as? String ?? ""
        let rawMessage = row["message"] as? String ?? "订单数据发生变化"
        let orderID = row["order_id"] as? String ?? ""
        let factoryOrder = row["factory_order"] as? String ?? ""
        let path = row["path"] as? String ?? ""
        let title: String
        switch kind {
        case "order_validation": title = "订单校验"
        case "aimes", "aimes_order_assignment": title = "AIMES"
        case "report_error": title = "报表检查"
        case "report_empty": title = "报表检查"
        default: title = "订单数据更新"
        }
        var detail = businessFriendlyMessage(rawMessage, operation: "处理订单数据")
        if !path.isEmpty {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            if !fileName.isEmpty && !detail.contains(fileName) {
                detail += "（文件：\(fileName)）"
            }
        }
        var operationDetails = [
            "更新对象：订单号 \(orderID.isEmpty ? "未识别" : orderID)，工厂单号 \(factoryOrder.isEmpty ? "未识别" : factoryOrder)。",
            "更新内容：\(detail)",
        ]
        if !path.isEmpty {
            operationDetails.append("读取文件：\(path)")
        }
        return InventoryStep(
            time: String(time.prefix(8)),
            title: title,
            detail: detail,
            state: severity == "error" ? "failure" : (severity == "warning" ? "warning" : "success"),
            paths: path.isEmpty ? [] : [path],
            operationDetails: operationDetails
        )
    }
}

func serverChangePreviews(_ rows: [[String: Any]]) -> [ServerChangePreview] {
    rows.compactMap { row in
        guard let id = row["id"] as? String, let path = row["path"] as? String else { return nil }
        return ServerChangePreview(
            id: id,
            changeType: row["change_type"] as? String ?? "modified",
            kind: row["kind"] as? String ?? "file",
            orderId: row["order_id"] as? String ?? "",
            sourceFolder: row["source_folder"] as? String ?? "",
            path: path,
            oldPath: row["old_path"] as? String ?? "",
            message: businessFriendlyMessage(
                row["message"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
                operation: "扫描 Server"
            ),
            manualOnly: row["manual_only"] as? Bool ?? false,
            eventTime: row["event_time"] as? String ?? ""
        )
    }
}

func serverChangeTypeName(_ type: String) -> String {
    switch type {
    case "added": return "新增"
    case "removed": return "删除"
    case "renamed": return "改名"
    case "missing_report": return "缺少报表"
    default: return "修改"
    }
}

struct OrderPreviewIssue: Equatable {
    let orderId: String
    let code: String
    let message: String
}

func orderPreviewIssues(_ object: [String: Any]) -> [OrderPreviewIssue] {
    (object["errors"] as? [[String: Any]] ?? []).map {
        OrderPreviewIssue(
            orderId: $0["order_id"] as? String ?? "",
            code: $0["code"] as? String ?? "",
            message: $0["message"] as? String ?? "订单校验失败"
        )
    }
}

struct OrderMaterialPreview: Identifiable {
    let id = UUID()
    let kind: String
    let thickness: Double
    let color: String
    let quantity: Double
}

func orderMaterialDisplayName(_ row: OrderMaterialPreview) -> String {
    let thickness = row.thickness
    if row.kind == "panel" {
        return row.color.isEmpty ? "Panel" : row.color
    }
    if abs(thickness - 18) < 0.01 { return "柜体板" }
    if abs(thickness - 14.5) < 0.01 { return "抽屉板" }
    if abs(thickness - 5.4) < 0.01 { return "背板" }
    return "Plywood"
}

func orderedMaterialRows(_ rows: [OrderMaterialPreview]) -> [OrderMaterialPreview] {
    rows.sorted {
        let leftRank: Int
        let rightRank: Int
        if $0.kind == "plywood" {
            leftRank = abs($0.thickness - 18) < 0.01 ? 0 : abs($0.thickness - 14.5) < 0.01 ? 1 : abs($0.thickness - 5.4) < 0.01 ? 2 : 3
        } else {
            leftRank = 10
        }
        if $1.kind == "plywood" {
            rightRank = abs($1.thickness - 18) < 0.01 ? 0 : abs($1.thickness - 14.5) < 0.01 ? 1 : abs($1.thickness - 5.4) < 0.01 ? 2 : 3
        } else {
            rightRank = 10
        }
        if leftRank != rightRank { return leftRank < rightRank }
        if $0.kind == "panel", $1.kind == "panel" {
            let leftColor = $0.color.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let rightColor = $1.color.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let colorOrder = leftColor.localizedStandardCompare(rightColor)
            if colorOrder != .orderedSame { return colorOrder == .orderedAscending }
            let leftThicknessRank = orderDetailPanelThicknessRank($0.thickness)
            let rightThicknessRank = orderDetailPanelThicknessRank($1.thickness)
            if leftThicknessRank != rightThicknessRank { return leftThicknessRank < rightThicknessRank }
            if abs($0.thickness - $1.thickness) > 0.01 { return $0.thickness < $1.thickness }
        }
        return $0.color.localizedStandardCompare($1.color) == .orderedAscending
    }
}

func orderedEdgeColors(_ colors: [String], matching panels: [OrderMaterialPreview]) -> [String] {
    var order: [String] = []
    for panel in panels where panel.kind == "panel" {
        let color = panel.color.trimmingCharacters(in: .whitespacesAndNewlines)
        if !color.isEmpty && !order.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) {
            order.append(color)
        }
    }
    let remaining = colors.filter { color in !order.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return order + remaining
}

func panelColorsNeedingThicknessWarning(_ rows: [OrderMaterialPreview]) -> Set<String> {
    let panels = rows.filter { $0.kind == "panel" && !$0.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let grouped = Dictionary(grouping: panels) {
        $0.color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    return Set(grouped.compactMap { color, items in
        let hasDoorPanel = items.contains { abs($0.thickness - 19.1) < 0.01 }
        let hasBackPanel = items.contains { abs($0.thickness - 8) < 0.01 || abs($0.thickness - 9) < 0.01 }
        return hasDoorPanel && hasBackPanel ? color : nil
    })
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

struct OrderStockPreview: Identifiable {
    let id: String
    let productCode: String
    let productName: String
    let unit: String
    let travelerNames: [String]
    let required: Double
    let available: Double
    let shortage: Double
    let sufficient: Bool
}

struct OrderCostLine: Identifiable {
    let id = UUID()
    let category: String
    let factoryOrder: String
    let roomName: String
    let name: String
    let spec: String
    let quantity: Double
    let unit: String
    let productCode: String
    let costPrice: Double?
    let amount: Double?
    let missing: String
}

struct OrderCostFactoryTotal: Identifiable {
    let id: String
    let factoryOrder: String
    let total: Double
    let hasMissing: Bool
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

func groupInventoryTravelersByNewest(_ travelers: [InventoryTraveler]) -> [(String, [InventoryTraveler])] {
    Dictionary(grouping: travelers, by: \.ppFolder)
        .map { folder, files in
            let sortedFiles = files.sorted {
                if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
                return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
            return (folder, sortedFiles)
        }
        .sorted {
            let leftDate = $0.1.first?.modifiedAt ?? ""
            let rightDate = $1.1.first?.modifiedAt ?? ""
            if leftDate != rightDate { return leftDate > rightDate }
            return $0.0.localizedStandardCompare($1.0) == .orderedAscending
        }
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

func inventoryPreviewCategoryRank(_ row: InventoryPreviewRow) -> Int {
    let name = row.travelerName.trimmingCharacters(in: .whitespacesAndNewlines)
    if row.section == "五金" { return 3 }
    if name.localizedCaseInsensitiveContains("Edge banding") { return 2 }
    if name.localizedCaseInsensitiveContains("Plywood") { return 0 }
    if row.section == "板材与封边" { return 1 }
    return 4
}

func inventoryPreviewPlywoodRank(_ row: InventoryPreviewRow) -> Int {
    let name = row.travelerName.lowercased()
    if name.hasPrefix("18mm") { return 0 }
    if name.hasPrefix("14.5mm") { return 1 }
    if name.hasPrefix("5.4mm") { return 2 }
    return 3
}

func sortedInventoryPreviewRows(_ rows: [InventoryPreviewRow]) -> [InventoryPreviewRow] {
    rows.sorted {
        let leftCategory = inventoryPreviewCategoryRank($0)
        let rightCategory = inventoryPreviewCategoryRank($1)
        if leftCategory != rightCategory { return leftCategory < rightCategory }
        if leftCategory == 0 {
            let leftPlywood = inventoryPreviewPlywoodRank($0)
            let rightPlywood = inventoryPreviewPlywoodRank($1)
            if leftPlywood != rightPlywood { return leftPlywood < rightPlywood }
        }
        let nameOrder = $0.travelerName.localizedStandardCompare($1.travelerName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return $0.productCode.localizedStandardCompare($1.productCode) == .orderedAscending
    }
}

struct InventoryProductCandidate: Identifiable {
    let id: String
    let code: String
    let name: String
    let spec: String
    let category: String
    let unit: String
}

struct InventoryIgnoredMapping: Identifiable {
    let id: String
    let name: String
    let reason: String
}

struct InventoryManualMapping: Identifiable {
    let id: String
    let name: String
    let productCode: String
}

struct InventoryStep: Identifiable {
    let id: UUID
    let time: String
    let title: String
    let detail: String
    let state: String
    let paths: [String]
    let operationDetails: [String]
    let contextDetails: [String]
    let startedAt: Date?
    let duration: TimeInterval?

    init(
        id: UUID = UUID(),
        time: String,
        title: String,
        detail: String,
        state: String,
        paths: [String] = [],
        operationDetails: [String] = [],
        contextDetails: [String] = [],
        startedAt: Date? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.detail = detail
        self.state = state
        self.paths = paths
        self.operationDetails = operationDetails
        self.contextDetails = contextDetails
        self.startedAt = startedAt
        self.duration = duration
    }
}

func operationDurationText(_ duration: TimeInterval) -> String {
    let rounded = max(0, duration).rounded(toPlaces: 2)
    return String(format: "%.2f 秒", rounded)
}

struct DashboardOperationDuration: Equatable, Identifiable {
    let id: String
    let label: String
    let duration: TimeInterval

    init(id: String? = nil, label: String, duration: TimeInterval) {
        self.label = label
        self.duration = max(0, duration)
        self.id = id ?? "\(label)-\(UUID().uuidString)"
    }
}

func dashboardFlatOperationDurations(_ stages: [[String: Any]]) -> [DashboardOperationDuration] {
    stages.compactMap { stage -> DashboardOperationDuration? in
        guard let label = stage["label"] as? String, !label.isEmpty else { return nil }
        let stageKey = stage["stage"] as? String ?? ""
        guard stageKey != "attempt", stageKey != "total", !label.contains("总计用时") else { return nil }
        let duration = (stage["duration_seconds"] as? NSNumber)?.doubleValue ?? 0
        return DashboardOperationDuration(label: label, duration: duration)
    }
}

private struct DashboardOperationStart {
    let label: String
    let startedAt: Date
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

func dashboardClockTime(_ date: Date = Date()) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
}

/// Format persisted ISO timestamps only at the presentation boundary.
/// Storage, sorting, and comparisons continue to use the original value.
func appDisplayTimestamp(_ value: String) -> String {
    value.replacingOccurrences(of: "T", with: " ")
}

func updatingLatestRunningStep(_ steps: [InventoryStep], detail: String) -> [InventoryStep]? {
    guard let index = steps.lastIndex(where: { $0.state == "running" }) else { return nil }
    var updated = steps
    let current = updated[index]
    updated[index] = InventoryStep(
        id: current.id,
        time: current.time,
        title: current.title,
        detail: detail,
        state: "running",
        paths: current.paths,
        operationDetails: current.operationDetails,
        contextDetails: current.contextDetails,
        startedAt: current.startedAt,
        duration: current.duration
    )
    return updated
}

func appendingInventoryProgressStep(_ steps: [InventoryStep], message: String) -> [InventoryStep] {
    var updated = steps
    if let index = updated.lastIndex(where: { $0.state == "running" }) {
        let current = updated[index]
        updated[index] = InventoryStep(
            id: current.id,
            time: current.time,
            title: current.title,
            detail: current.detail,
            state: "success",
            paths: current.paths,
            operationDetails: current.operationDetails,
            contextDetails: current.contextDetails,
            startedAt: current.startedAt,
            duration: current.duration
        )
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    updated.append(InventoryStep(
        time: formatter.string(from: Date()),
        title: "后台操作",
        detail: message,
        state: "running",
        startedAt: Date()
    ))
    return updated
}

func orderUpdateActionReady(existingTravelerPath: String, selectedOrderPath: String, selectedOrderId: String) -> Bool {
    !existingTravelerPath.isEmpty && !selectedOrderPath.isEmpty && !selectedOrderId.isEmpty
}

func orderTravelerOpenActionReady(existingTravelerPath: String) -> Bool {
    let path = existingTravelerPath.trimmingCharacters(in: .whitespacesAndNewlines)
    return !path.isEmpty && FileManager.default.fileExists(atPath: path)
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

struct AssistantTaskItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var status: String = "排队中"
}

final class AppModel: ObservableObject {
    @Published var assistantInput = ""
    @Published var assistantOutput = "输入或说出一条指令。"
    @Published var assistantOrderPreview: AssistantOrderResult?
    @Published var assistantOrderList: [OrderFolderItem] = []
    @Published var assistantStockRows: [OrderStockPreview] = []
    @Published var assistantStockOrderId = ""
    @Published var assistantStockTraveler = ""
    @Published var assistantRunning = false
    @Published var assistantPendingApproval = false
    @Published var assistantTokenSummary = "本次 0 Token"
    @Published var assistantUsageSummary = "本周 0 · 本月 0 · 累计 0 Token"
    @Published var assistantTasks: [AssistantTaskItem] = []
    @Published var assistantActiveTaskID: UUID?
    var assistantProcess: Process?
    var assistantWriteInProgress = false
    @Published var initialDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 22))!
    @Published var sourceRoot = "/Volumes/server/Optimized Orders"
    @Published var orderRoot = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Order"
    @Published var backupRoot = "/Volumes/server/g/pp-flowhub/database-backups"
    @Published var settingsStatus = ""
    @Published var operationLogEnabled = true
    @Published private(set) var operationLogSizeText = "0 bytes"
    @Published var inventoryTravelers: [InventoryTraveler] = []
    @Published var selectedInventoryPaths: Set<String> = []
    @Published var selectedInventoryOrderID = ""
    @Published var selectedInventoryDocumentRemarks: Set<String> = []
    @Published var selectedInventoryFactoryOrders: Set<String> = []
    @Published var inventoryPreviewRows: [InventoryPreviewRow] = []
    @Published var inventoryErrors: [String] = []
    @Published var inventoryWriteBlocked = false
    @Published var inventoryWriteCompleted = false
    @Published var inventoryRunning = false
    @Published var inventoryStatus = "尚未载入 Traveler"
    @Published var inventorySuccessMessage = ""
    @Published var inventoryCatalogStatus = "商品资料尚未检查"
    @Published var inventoryChromeStatus = "库存专用 Chrome 尚未打开"
    private var inventoryChromeOpenedByApp = false
    @Published var showInventoryHistory = false
    @Published var jdyUsername = ""
    @Published var jdyPassword = ""
    @Published var aimesUsername = ""
    @Published var aimesPassword = ""
    @Published var inventorySteps: [InventoryStep] = []
    @Published var inventoryProductCandidates: [InventoryProductCandidate] = []
    @Published var inventoryProductSearchStatus = ""
    @Published var inventoryIgnoredMappings: [InventoryIgnoredMapping] = []
    @Published var inventoryManualMappings: [InventoryManualMapping] = []
    @Published var inventoryMappingRequestPath = ""
    @Published var showInventoryMappingWorkspace = false
    @Published var inventoryMappingTargetNames: [String] = []
    private var pendingInventoryMappingFolder = ""
    private var pendingDashboardOutboundRefresh = false
    @Published var orderFolders: [OrderFolderItem] = []
    @Published var dashboardOrders: [OrderDashboardItem] = []
    @Published var dashboardChanges: [String] = []
    @Published var dashboardActivity: [InventoryStep] = []
    @Published var dashboardOperationDetails: [String: [String]] = [:]
    @Published private(set) var dashboardOperationDurations: [String: TimeInterval] = [:]
    @Published private(set) var dashboardOperationStageDurations: [String: [DashboardOperationDuration]] = [:]
    private var dashboardOperationStartedAt: [String: DashboardOperationStart] = [:]
    @Published var dashboardSyncStatus = "订单数据尚未同步" {
        didSet { dashboardSyncStatusTime = dashboardClockTime() }
    }
    @Published var dashboardAimesStatus = "AIMES 尚未检查" {
        didSet { dashboardAimesStatusTime = dashboardClockTime() }
    }
    @Published var aimesFailureAlert = ""
    @Published var dashboardServerStatus = "Server 尚未扫描" {
        didSet { dashboardServerStatusTime = dashboardClockTime() }
    }
    @Published private(set) var dashboardSyncStatusTime = dashboardClockTime()
    @Published private(set) var dashboardAimesStatusTime = dashboardClockTime()
    @Published private(set) var dashboardServerStatusTime = dashboardClockTime()
    @Published var pendingServerChanges: [ServerChangePreview] = []
    @Published var selectedServerFolderPaths: Set<String> = []
    @Published var includeHardwareForServerProcessing = true
    @Published var pendingServerFolderURL: URL?
    @Published var showServerProcessingOptions = false
    @Published var serverWritePreview: ServerWritePreview?
    @Published var showServerWriteConfirmation = false
    @Published var serverWriteConfirmationNotice = ""
    @Published var serverWriteConfirmationNoticeIsError = false
    @Published var serverWriteConfirmationFinished = false
    @Published var currentIssues: [CurrentIssue] = []
    @Published var showPendingCenterPrompt = false
    @Published var showCurrentIssuesPrompt = false
    @Published var showServerChangesPrompt = false
    @Published var pendingAimesReviews: [AimesReviewItem] = []
    @Published var ignoredAimesFactories: [AimesReviewItem] = []
    @Published var assignedAimesFactories: [AimesReviewItem] = []
    @Published var aimesFormatWarnings: [AimesReviewItem] = []
    @Published var aimesWarnings: [[String: Any]] = []
    @Published var selectedAimesReviewIDs: Set<String> = []
    @Published var showAimesReviewPrompt = false
    @Published var orderSourceKind = "owned"
    @Published var selectedOrderPath = ""
    @Published var selectedOrderId = ""
    @Published var orderMaterialsFile = ""
    @Published var orderMaterials: [OrderMaterialPreview] = []
    @Published var orderEdgeBanding: [String: Double] = [:]
    @Published var orderFactories: [OrderFactoryPreview] = []
    @Published var orderFittings: [OrderFittingPreview] = []
    @Published var orderWarnings: [String] = []
    @Published var orderStockRows: [OrderStockPreview] = []
    @Published var orderSteps: [InventoryStep] = []
    @Published var orderRunning = false
    @Published var orderPreviewValidated = false
    @Published var orderDetailWaiting = false
    @Published var orderMissingMaterial = false
    @Published var orderCostStatus = ""
    @Published var orderCostTotal: Double?
    @Published var orderCostKnown: Double = 0
    @Published var orderCostLines: [OrderCostLine] = []
    @Published var orderCostFactoryTotals: [OrderCostFactoryTotal] = []
    @Published var orderCostMissingItems: [String] = []
    @Published var orderCostExportPath = ""
    @Published var showCostSheet = false
    @Published var selectedOrderIsOptimized = false
    @Published var selectedOrderIsCompleted = false
    @Published var orderStatus = "点击刷新读取服务器订单文件夹"
    @Published var orderError = ""
    @Published var orderCreatedPath = ""
    @Published var orderExistingTravelerPath = ""
    @Published var showMaterialGenerationPrompt = false
    @Published var todoItems: [TodoItem] = []
    @Published var todoStatus = ""
    @Published var showBackupReminder = false
    @Published var backupReminderStatus = ""
    @Published var backupStatus = ""
    private var inventoryStderrBuffer = ""
    private var inventoryRawErrors = ""
    private var orderStderrBuffer = ""
    private var orderRawErrors = ""
    private var pendingOrderDetailItem: OrderDashboardItem?
    private var orderDetailRetryScheduled = false
    private var dashboardStartupStarted = false

    var pendingCenterItems: [PendingCenterItem] {
        buildPendingCenterItems(
            serverChanges: pendingServerChanges,
            currentIssues: currentIssues,
            aimesReviews: pendingAimesReviews
        )
    }

    var orderPreviewReady: Bool {
        !selectedOrderId.isEmpty && !orderMaterials.isEmpty
    }

    var orderCanGenerateTraveler: Bool {
        !orderRunning && !selectedOrderId.isEmpty
    }

    var orderTravelerOpenReady: Bool {
        orderTravelerOpenActionReady(existingTravelerPath: orderExistingTravelerPath)
    }

    var activeOwnedSourceRoot: String {
        sourceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var activeCutToSizeRoot: String {
        return URL(fileURLWithPath: sourceRoot, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("CUT TO SIZE", isDirectory: true).path
    }

    var activeOrderRoot: String {
        orderRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var activeBackupRoot: String {
        backupRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var databaseBackupRoot: String {
        NSHomeDirectory() + "/Documents/pp-flowhub/data/database-backups"
    }

    init() {
        loadSettings()
        OperationLogWriter.shared.setEnabled(operationLogEnabled)
        OperationLogWriter.shared.record(
            "app.started",
            message: "App 启动",
            details: ["operation_log_enabled": operationLogEnabled]
        )
        loadTodoItems()
        loadAssistantUsage()
    }

    func checkBackupReminder() {
        runOrder(["backup-status"]) { object in
            if object["requires_user_attention"] as? Bool == true {
                self.backupReminderStatus = "今日尚无成功的本机数据库备份。"
                self.showBackupReminder = true
            }
        }
    }

    func performBackup() {
        guard !orderRunning else {
            backupStatus = "⚠️ 当前正在扫描或同步，请等待任务完成后再备份。"
            return
        }
        backupStatus = "正在备份数据库…"
        runOrder(["backup-now"], failureStatus: "数据库备份失败", onFailure: {
            let message = businessFriendlyMessage(self.orderError, operation: "数据库备份")
            self.backupStatus = "⚠️ \(message)"
            self.backupReminderStatus = message
        }) { object in
            let path = object["path"] as? String ?? self.databaseBackupRoot
            self.backupStatus = "✅ 数据库备份完成：\(path)"
            self.backupReminderStatus = self.backupStatus
            self.showBackupReminder = false
        }
    }

    private var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/pp-flowhub/data/settings.json")
    }

    var todoDataURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/pp-flowhub/data/todo-items.json")
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
            todoStatus = businessFriendlyMessage(error.localizedDescription, operation: "读取待办")
        }
    }

    func addTodo(content: String, deadline: Date?) {
        logUserAction("点击添加待办", details: ["deadline_present": deadline != nil])
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            todoStatus = "请输入任务内容"
            return
        }
        todoItems.append(TodoItem(content: value, deadline: deadline))
        saveTodoItems()
    }

    func updateTodo(_ item: TodoItem, content: String, deadline: Date?) {
        logUserAction("点击保存待办编辑", details: ["deadline_present": deadline != nil])
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
        logUserAction("点击切换待办完成状态")
        guard let index = todoItems.firstIndex(where: { $0.id == item.id }) else { return }
        todoItems[index].completedAt = todoItems[index].completedAt == nil ? Date() : nil
        saveTodoItems()
    }

    func deleteTodo(_ item: TodoItem) {
        logUserAction("点击删除待办")
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
            OperationLogWriter.shared.record(
                "file.write",
                message: "保存待办数据",
                details: ["file": todoDataURL.path, "item_count": todoItems.count]
            )
            todoStatus = ""
        } catch {
            todoStatus = businessFriendlyMessage(error.localizedDescription, operation: "保存待办")
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
        sourceRoot = values["server_source_root"] as? String
            ?? values["source_root"] as? String
            ?? sourceRoot
        orderRoot = values["production_order_root"] as? String
            ?? values["order_root"] as? String
            ?? orderRoot
        backupRoot = values["production_backup_root"] as? String
            ?? values["backup_root"] as? String
            ?? backupRoot
        jdyUsername = values["jdy_username"] as? String ?? jdyUsername
        aimesUsername = values["aimes_username"] as? String ?? aimesUsername
        operationLogEnabled = values["operation_log_enabled"] as? Bool ?? operationLogEnabled
    }

    func saveSettings() {
        logUserAction("点击保存设置")
        let values: [String: Any] = [
            "initial_date": Self.dateFormatter.string(from: initialDate),
            "source_root": activeOwnedSourceRoot,
            "server_source_root": sourceRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            "order_root": activeOrderRoot,
            "production_order_root": orderRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            "backup_root": activeBackupRoot,
            "production_backup_root": backupRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            "jdy_username": jdyUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            "aimes_username": aimesUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            "operation_log_enabled": operationLogEnabled,
        ]
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            OperationLogWriter.shared.record(
                "file.write",
                message: "保存设置文件",
                details: ["file": settingsURL.path]
            )
            settingsStatus = "✅ 设置已保存，下次任务立即生效。"
        } catch {
            settingsStatus = "❌ \(businessFriendlyMessage(error.localizedDescription, operation: "保存设置"))"
        }
    }

    var operationLogURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/pp-flowhub/data/operation-log.jsonl")
    }

    func setOperationLogEnabled(_ enabled: Bool) {
        guard enabled != operationLogEnabled else { return }
        if !enabled {
            OperationLogWriter.shared.record(
                "user.operation_log.disabled",
                message: "用户关闭操作日志",
                details: ["enabled_after_change": false],
                force: true
            )
        }
        operationLogEnabled = enabled
        OperationLogWriter.shared.setEnabled(enabled)
        saveSettings()
        if enabled {
            OperationLogWriter.shared.record(
                "user.operation_log.enabled",
                message: "用户开启操作日志",
                details: ["enabled_after_change": true]
            )
        }
    }

    func refreshOperationLogInfo() {
        operationLogSizeText = OperationLogReader.fileSizeText(from: operationLogURL)
    }

    func trimOperationLog() {
        guard !orderRunning && !inventoryRunning && !assistantRunning else {
            settingsStatus = "⚠️ 当前有任务正在运行，请完成后再清理操作日志。"
            return
        }
        do {
            let result = try OperationLogWriter.shared.trimLogToRecentDays(3)
            OperationLogWriter.shared.record(
                "user.action",
                message: "清理操作日志，仅保留近三天",
                details: [
                    "removed_entries": result.removedEntries,
                    "retained_entries": result.retainedEntries,
                ]
            )
            refreshOperationLogInfo()
            settingsStatus = "✅ 操作日志已清理，仅保留近三天，删除 (result.removedEntries) 条。"
        } catch {
            refreshOperationLogInfo()
            settingsStatus = "❌ 操作日志清理失败：(error.localizedDescription)"
        }
    }

    func logUserAction(_ action: String, details: [String: Any] = [:]) {
        OperationLogWriter.shared.record("user.action", message: action, details: details)
    }

    func newOperationID(_ name: String, details: [String: Any] = [:]) -> String {
        let operationID = UUID().uuidString
        OperationLogWriter.shared.record(
            "operation.started",
            message: name,
            details: details,
            operationID: operationID
        )
        return operationID
    }

    func environmentForOperation(_ operationID: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in OperationLogWriter.shared.environment(operationID: operationID) {
            environment[key] = value
        }
        return environment
    }

    func saveAllSettings() {
        logUserAction("点击保存全部配置")
        saveSettings()
        if !jdyPassword.isEmpty {
            saveJdyPassword()
        }
        if !aimesPassword.isEmpty {
            saveAimesPassword()
        } else if settingsStatus.hasPrefix("✅") {
            settingsStatus = "✅ 常规设置已保存；未修改钥匙串密码。"
        }
    }

    func saveJdyPassword() {
        logUserAction("点击更新库存系统钥匙串密码", details: ["input_present": !jdyPassword.isEmpty])
        let account = jdyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else {
            settingsStatus = "❌ 请先填写并保存库存系统用户名。"
            return
        }
        guard !jdyPassword.isEmpty else {
            settingsStatus = "❌ 请输入新的库存系统密码。"
            return
        }
        let service = "com.pacificpride.workflow-assistant.jdy"
        let baseIdentity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var dataProtectionIdentity = baseIdentity
        dataProtectionIdentity[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dataProtectionIdentity as CFDictionary)
        var identity = baseIdentity
        identity[kSecUseDataProtectionKeychain as String] = false
        guard let passwordData = jdyPassword.data(using: .utf8) else {
            settingsStatus = "❌ 密码无法转换为钥匙串数据。"
            return
        }
        let update: [String: Any] = [kSecValueData as String: passwordData]
        var status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = passwordData
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            settingsStatus = "❌ 库存系统密码没有保存成功。请确认已登录 macOS 用户账户，并允许 App 使用钥匙串后重试。"
            return
        }
        var verification = identity
        verification[kSecReturnData as String] = true
        verification[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let verifyStatus = SecItemCopyMatching(verification as CFDictionary, &result)
        guard verifyStatus == errSecSuccess, result is Data else {
            settingsStatus = "❌ 库存系统密码保存后未能通过验证。请重新输入并保存；仍失败时检查 App 的钥匙串访问权限。"
            return
        }
        jdyPassword = ""
        settingsStatus = "✅ 库存系统密码已保存到本机登录钥匙串，并通过回读验证。"
    }

    func saveAimesPassword() {
        logUserAction("点击保存 AIMES 密码", details: ["input_present": !aimesPassword.isEmpty])
        let account = aimesUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { settingsStatus = "❌ 请先填写 AIMES 用户名。"; return }
        guard !aimesPassword.isEmpty else { settingsStatus = "❌ 请输入 AIMES 密码。"; return }
        saveSettings()
        let service = "com.pacificpride.ppflowhub.aimes"
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = aimesPassword.data(using: .utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            settingsStatus = "❌ AIMES 密码保存失败。"
            return
        }
        aimesPassword = ""
        settingsStatus = "✅ AIMES 密码已保存到 macOS 钥匙串。"
    }

    private func applyDashboardObject(_ object: [String: Any], includeChanges: Bool = true) {
        applyDashboardOperationTrace(object)
        applyCurrentIssues(from: object)
        let rows = object["orders"] as? [[String: Any]] ?? []
        dashboardOrders = rows.compactMap { row in
            guard let orderID = row["order_id"] as? String, !orderID.isEmpty else { return nil }
            let factories = (row["factories"] as? [[String: Any]] ?? []).compactMap { factory -> OrderDashboardFactory? in
                guard let number = factory["factory_order"] as? String, !number.isEmpty else { return nil }
                return OrderDashboardFactory(
                    id: number,
                    factoryOrder: number,
                    orderId: factory["order_id"] as? String ?? orderID,
                    orderName: factory["order_name"] as? String ?? "",
                    nameSource: factory["name_source"] as? String ?? "",
                    reportState: factory["report_state"] as? String ?? "未发现",
                    ownershipStatus: factory["ownership_status"] as? String ?? "待确认",
                    hasHardware: (factory["has_hardware"] as? NSNumber)?.boolValue ?? false,
                    optimized: (factory["optimized"] as? NSNumber)?.boolValue ?? false,
                    outboundStatus: factory["outbound_status"] as? String ?? "未查询",
                    outboundDocument: factory["outbound_document"] as? String ?? ""
                )
            }
            let number = { (key: String) -> Int in
                (row[key] as? NSNumber)?.intValue ?? 0
            }
            let installationDays = { (dateType: String) -> [OrderInstallationDay] in
                let installation = row["installation"] as? [String: Any] ?? [:]
                let summary = installation[dateType] as? [String: Any] ?? [:]
                return (summary["days"] as? [[String: Any]] ?? []).compactMap { value in
                    guard let date = value["date"] as? String, !date.isEmpty else { return nil }
                    return OrderInstallationDay(
                        date: date,
                        installer: value["installer"] as? String ?? ""
                    )
                }
            }
            return OrderDashboardItem(
                id: orderID,
                orderId: orderID,
                orderType: row["order_type"] as? String ?? "owned",
                sourceFolder: row["source_folder"] as? String ?? "",
                modifiedAt: row["modified_at"] as? String ?? "",
                validationStatus: row["validation_status"] as? String ?? "待同步",
                validationMessage: {
                    let message = row["validation_message"] as? String ?? ""
                    return message.isEmpty
                        ? ""
                        : businessFriendlyMessage(message, operation: "校验订单")
                }(),
                stage: row["stage"] as? String ?? "已设计",
                materialStatus: row["material_status"] as? String ?? "待校验",
                factoryCount: number("factory_count"),
                optimizedCount: number("optimized_count"),
                shippedCount: number("shipped_count"),
                optimizationProgress: row["optimization_progress"] as? String ?? "—",
                outboundProgress: row["outbound_progress"] as? String ?? "—",
                userNote: row["user_note"] as? String ?? "",
                plannedInstallationDays: installationDays("planned"),
                actualInstallationDays: installationDays("actual"),
                factories: factories
            )
        }
        guard includeChanges else { return }
        dashboardChanges = (object["changes"] as? [[String: Any]] ?? []).compactMap {
            guard let message = $0["message"] as? String else { return nil }
            return businessFriendlyMessage(message, operation: "处理 Server 变化")
        }
        dashboardActivity = dashboardActivitySteps(object)
    }

    private func presentServerWritePreview(_ object: [String: Any]) {
        guard let preview = ServerWritePreview(object: object) else {
            dashboardServerStatus = "⚠️ Server 文件中没有可确认的订单和工厂单"
            dashboardSyncStatus = dashboardServerStatus
            return
        }
        serverWritePreview = preview
        serverWriteConfirmationNotice = ""
        serverWriteConfirmationNoticeIsError = false
        serverWriteConfirmationFinished = false
        showServerWriteConfirmation = true
        dashboardServerStatus = "Server 数据已解析，请核对预览内容后确认材料"
        dashboardSyncStatus = dashboardServerStatus
    }

    private func applyCurrentIssues(from object: [String: Any]) {
        guard let rows = object["current_issues"] as? [[String: Any]] else { return }
        currentIssues = rows.compactMap { row in
            guard let issueKey = row["issue_key"] as? String, !issueKey.isEmpty else { return nil }
            return CurrentIssue(
                id: issueKey,
                kind: row["kind"] as? String ?? "",
                orderId: row["order_id"] as? String ?? "",
                factoryOrder: row["factory_order"] as? String ?? "",
                path: row["path"] as? String ?? "",
                message: row["message"] as? String ?? "当前问题需要处理",
                firstSeen: row["first_seen"] as? String ?? "",
                lastSeen: row["last_seen"] as? String ?? ""
            )
        }
    }

    private func applyDashboardOperationTrace(_ object: [String: Any]) {
        guard let trace = object["operation_trace"] as? [String: Any] else { return }
        for entry in trace {
            guard let details = entry.value as? [String] else { continue }
            var merged = dashboardOperationDetails[entry.key] ?? []
            for detail in details where !merged.contains(detail) {
                merged.append(detail)
            }
            dashboardOperationDetails[entry.key] = merged
        }
    }

    private func applyAimesReviewObject(_ object: [String: Any], presentIfNeeded: Bool = true) {
        pendingAimesReviews = aimesReviewItems(object, key: "aimes_issues")
        ignoredAimesFactories = aimesReviewItems(object, key: "ignored_aimes")
        assignedAimesFactories = aimesReviewItems(object, key: "assigned_aimes")
        aimesWarnings = object["aimes_warnings"] as? [[String: Any]] ?? []
        aimesFormatWarnings = aimesReviewItemsFromWarnings(aimesWarnings)
        selectedAimesReviewIDs.formIntersection(Set(pendingAimesReviews.map(\.id)))
        if presentIfNeeded && pendingAimesReviews.isEmpty && !aimesFormatWarnings.isEmpty {
            showAimesReviewPrompt = true
        }
        if shouldPresentPendingCenterAfterAimes(
            presentIfNeeded: presentIfNeeded,
            pendingAimesReviews: pendingAimesReviews
        ) {
            showPendingCenterPrompt = true
        }
    }

    private func closePendingCenterIfEmpty() {
        if pendingCenterItems.isEmpty {
            showPendingCenterPrompt = false
        }
    }

    private func beginDashboardOperation(_ source: String, label: String, continuing: Bool = false) {
        if !continuing {
            dashboardOperationStageDurations[source] = []
            dashboardOperationDurations[source] = 0
            dashboardOperationDetails[source] = []
        }
        dashboardOperationStartedAt[source] = DashboardOperationStart(label: label, startedAt: Date())
    }

    private func finishDashboardOperation(_ source: String) {
        guard let start = dashboardOperationStartedAt.removeValue(forKey: source) else { return }
        let duration = max(0, Date().timeIntervalSince(start.startedAt))
        var stages = dashboardOperationStageDurations[source] ?? []
        stages.append(DashboardOperationDuration(label: start.label, duration: duration))
        dashboardOperationStageDurations[source] = stages
        dashboardOperationDurations[source] = stages.reduce(0) { $0 + $1.duration }
    }

    private func discardDashboardOperationTimer(_ source: String) {
        dashboardOperationStartedAt.removeValue(forKey: source)
    }

    private func applyAuthoritativeDashboardTiming(
        _ source: String,
        seconds: Double,
        stages: [[String: Any]]
    ) {
        let duration = max(0, seconds)
        dashboardOperationDurations[source] = duration
        let parsed = dashboardFlatOperationDurations(stages)
        dashboardOperationStageDurations[source] = parsed
    }

    func startOrderDashboard() {
        guard !dashboardStartupStarted else { return }
        dashboardStartupStarted = true
        loadOrderDashboardCache()
    }

    func loadOrderDashboardCache() {
        beginDashboardOperation("sync", label: "读取本地订单缓存")
        dashboardSyncStatus = "正在读取本地订单缓存…"
        runOrder(["list-index"], onFailure: {
            self.finishDashboardOperation("sync")
            self.dashboardStartupStarted = false
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "读取本地订单缓存"))"
        }) { object in
            self.finishDashboardOperation("sync")
            self.applyDashboardObject(object, includeChanges: false)
            // The cache is only an initial display snapshot.  Do not open the
            // actionable pending center until the following AIMES/Server
            // startup refresh has completed; otherwise the sheet opens while
            // orderRunning is still true and presents stale data as locked UI.
            self.applyAimesReviewObject(object, presentIfNeeded: false)
            self.dashboardSyncStatus = "✅ 已显示本地缓存；正在后台检查数据"
            self.runDailyBackupAfterLocalCache {
                self.syncDashboardAimes(force: false, scanServerAfter: true)
            }
        }
    }

    func refreshDashboardOrdersAfterOutbound() {
        guard !orderRunning else {
            pendingDashboardOutboundRefresh = true
            dashboardSyncStatus = "出库已完成，订单列表将在当前后台操作结束后刷新"
            return
        }
        pendingDashboardOutboundRefresh = false
        beginDashboardOperation("sync", label: "刷新出库后的订单列表")
        dashboardSyncStatus = "正在刷新出库后的订单列表…"
        runOrder(["list-index"], failureStatus: "订单列表刷新失败", onFailure: {
            self.finishDashboardOperation("sync")
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "刷新订单列表"))"
        }) { object in
            self.finishDashboardOperation("sync")
            self.applyDashboardObject(object, includeChanges: false)
            self.dashboardSyncStatus = "✅ 出库完成，订单列表已刷新"
        }
    }

    private func startPendingDashboardOutboundRefreshIfNeeded() {
        guard pendingDashboardOutboundRefresh else { return }
        pendingDashboardOutboundRefresh = false
        DispatchQueue.main.async {
            self.refreshDashboardOrdersAfterOutbound()
        }
    }

    private func runDailyBackupAfterLocalCache(completion: @escaping () -> Void) {
        runOrder(["backup-status"], failureStatus: "数据库备份状态检查失败", onFailure: {
            let message = businessFriendlyMessage(self.orderError, operation: "检查数据库备份")
            self.backupReminderStatus = message
            self.showBackupReminder = true
            completion()
        }) { object in
            guard object["requires_user_attention"] as? Bool == true else {
                completion()
                return
            }
            self.backupReminderStatus = "今日尚无成功的本机数据库备份，正在自动备份…"
            self.runOrder(["backup-now"], failureStatus: "数据库备份失败", onFailure: {
                let message = businessFriendlyMessage(self.orderError, operation: "自动数据库备份")
                self.backupReminderStatus = message
                self.showBackupReminder = true
                completion()
            }) { object in
                let path = object["path"] as? String ?? self.databaseBackupRoot
                self.backupReminderStatus = "✅ 今日数据库备份已完成：\(path)"
                completion()
            }
        }
    }

    func autoResolveCurrentIssue(_ issue: CurrentIssue) {
        guard !orderRunning else { return }
        beginDashboardOperation("sync", label: "自动处理当前问题")
        dashboardSyncStatus = "正在自动处理当前问题：\(issue.factoryOrder.isEmpty ? issue.message : issue.factoryOrder)…"
        runOrder(["auto-resolve-issue", "--issue-key", issue.id], onFailure: {
            self.finishDashboardOperation("sync")
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "自动处理当前问题"))"
        }) { object in
            self.finishDashboardOperation("sync")
            self.applyDashboardObject(object, includeChanges: false)
            self.closePendingCenterIfEmpty()
            self.dashboardSyncStatus = self.pendingCenterItems.isEmpty ? "✅ 当前问题已自动处理" : "⚠️ 待处理中心仍有项目需要处理"
        }
    }

    func resolveCurrentIssue(_ issue: CurrentIssue, orderID: String) {
        let trimmed = orderID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (issue.kind != "factory_ownership" || !trimmed.isEmpty), !orderRunning else { return }
        beginDashboardOperation("sync", label: "保存人工归属")
        dashboardSyncStatus = "正在保存 \(issue.factoryOrder) 的人工归属…"
        var arguments = ["resolve-issue", "--issue-key", issue.id]
        if !trimmed.isEmpty { arguments += ["--order-id", trimmed] }
        runOrder(arguments, onFailure: {
            self.finishDashboardOperation("sync")
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "确认工厂单归属"))"
        }) { object in
            self.finishDashboardOperation("sync")
            self.applyDashboardObject(object, includeChanges: false)
            self.closePendingCenterIfEmpty()
            self.dashboardSyncStatus = self.pendingCenterItems.isEmpty ? "✅ 当前问题已处理" : "⚠️ 待处理中心仍有项目需要处理"
        }
    }

    func syncDashboardAimes(force: Bool, scanServerAfter: Bool = false) {
        logUserAction(force ? "点击再次获取 AIMES" : "触发 AIMES 后台获取", details: ["force": force])
        beginDashboardOperation("aimes", label: "获取 AIMES")
        dashboardAimesStatus = force ? "正在获取 AIMES…" : "正在检查今日 AIMES 获取记录…"
        let arguments = force
            ? ["sync-aimes", "--refresh-aimes"]
            : ["sync-aimes", "--aimes-if-needed"]
        runOrder(arguments, onFailure: {
            self.finishDashboardOperation("aimes")
            let message = businessFriendlyMessage(self.orderError, operation: "获取 AIMES 数据")
            self.aimesFailureAlert = message
            self.dashboardAimesStatus = "⚠️ \(message)"
            self.dashboardSyncStatus = self.dashboardAimesStatus
            if scanServerAfter { self.scanDashboardServer(background: true) }
        }) { object in
            let aimes = object["aimes"] as? [String: Any] ?? [:]
            if let seconds = aimes["duration_seconds"] as? NSNumber {
                self.discardDashboardOperationTimer("aimes")
                self.applyAuthoritativeDashboardTiming(
                    "aimes",
                    seconds: seconds.doubleValue,
                    stages: object["aimes_stage_durations"] as? [[String: Any]] ?? []
                )
            } else {
                self.finishDashboardOperation("aimes")
            }
            self.applyAimesReviewObject(object, presentIfNeeded: !scanServerAfter)
            let attempted = (aimes["attempted"] as? NSNumber)?.boolValue ?? false
            let succeeded = (aimes["succeeded"] as? NSNumber)?.boolValue ?? false
            let skipped = (aimes["skipped_today"] as? NSNumber)?.boolValue ?? false
            let changed = (aimes["changed"] as? NSNumber)?.boolValue ?? false
            let count = (aimes["count"] as? NSNumber)?.intValue ?? 0
            let issueCount = (aimes["issue_count"] as? NSNumber)?.intValue ?? self.pendingAimesReviews.count
            let warningCount = (aimes["warning_count"] as? NSNumber)?.intValue
                ?? ((object["aimes_warnings"] as? [[String: Any]])?.count ?? 0)
            let error = aimes["error"] as? String ?? ""
            if succeeded && changed {
                self.applyDashboardObject(object)
            }
            if warningCount > 0 {
                self.dashboardAimesStatus = "⚠️ 获取 AIMES 数据成功，发现 \(warningCount) 条销售单格式异常，已跳过且未写入数据库"
            } else if issueCount > 0 {
                self.dashboardAimesStatus = "⚠️ 获取 AIMES 数据成功，有 \(issueCount) 条工厂单需要人工确认"
            } else if succeeded && changed {
                self.dashboardAimesStatus = "✅ 获取 AIMES 数据成功，已更新最近 50 条（\(count) 条）"
            } else if skipped {
                self.dashboardAimesStatus = "✅ 今天已成功获取过 AIMES，本次略过"
            } else if succeeded && attempted {
                self.dashboardAimesStatus = "✅ 获取 AIMES 数据成功，最近 50 条无变化（\(count) 条）"
            } else {
                let message = businessFriendlyMessage(error, operation: "获取 AIMES 数据")
                if attempted && !succeeded {
                    self.aimesFailureAlert = message
                }
                self.dashboardAimesStatus = "⚠️ 尝试获取 AIMES 数据失败：\(message)"
            }
            self.dashboardSyncStatus = self.dashboardAimesStatus
            if scanServerAfter { self.scanDashboardServer(background: true) }
        }
    }

    func toggleAimesReviewSelection(_ item: AimesReviewItem) {
        logUserAction("点击选择 AIMES 待确认记录")
        if selectedAimesReviewIDs.contains(item.id) {
            selectedAimesReviewIDs.remove(item.id)
        } else {
            selectedAimesReviewIDs.insert(item.id)
        }
    }

    func ignoreSelectedAimesFactories() {
        logUserAction("点击忽略选中的 AIMES 工厂单")
        let keys = pendingAimesReviews
            .filter { selectedAimesReviewIDs.contains($0.id) }
            .map(\.ignoreKey)
        guard !keys.isEmpty else { return }
        var arguments = ["ignore-aimes"]
        for key in keys {
            arguments += ["--ignore-key", key]
        }
        beginDashboardOperation("aimes", label: "保存 AIMES 忽略记录")
        dashboardAimesStatus = "正在保存 AIMES 忽略记录…"
        runOrder(arguments, failureStatus: "AIMES 忽略记录保存失败", onFailure: {
            self.finishDashboardOperation("aimes")
            self.dashboardAimesStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "保存 AIMES 忽略记录"))"
        }) { object in
            self.finishDashboardOperation("aimes")
            self.applyDashboardObject(object)
            self.applyAimesReviewObject(object, presentIfNeeded: false)
            self.selectedAimesReviewIDs.removeAll()
            self.dashboardAimesStatus = "✅ 已忽略 \(keys.count) 条 AIMES 工厂单"
            self.dashboardSyncStatus = self.dashboardAimesStatus
            self.closePendingCenterIfEmpty()
        }
    }

    func restoreAimesFactory(_ item: AimesReviewItem) {
        logUserAction("点击恢复 AIMES 工厂单提醒", details: ["factory_order_present": !item.factoryOrder.isEmpty])
        beginDashboardOperation("aimes", label: "恢复 AIMES 忽略记录")
        dashboardAimesStatus = "正在恢复 AIMES 工厂单提醒…"
        runOrder(
            ["restore-aimes-ignore", "--ignore-key", item.ignoreKey],
            failureStatus: "AIMES 忽略记录恢复失败",
            onFailure: {
                self.finishDashboardOperation("aimes")
                self.dashboardAimesStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "恢复 AIMES 工厂单提醒"))"
            }
        ) { object in
            self.finishDashboardOperation("aimes")
            self.applyDashboardObject(object)
            self.applyAimesReviewObject(object, presentIfNeeded: false)
            self.dashboardAimesStatus = "✅ 已恢复 \(item.factoryOrder.isEmpty ? "所选记录" : item.factoryOrder)，下次获取时重新校验"
            self.dashboardSyncStatus = self.dashboardAimesStatus
        }
    }

    func assignAimesFactoryToSuggestedOrder(_ item: AimesReviewItem) {
        guard !item.suggestedOrderID.isEmpty else { return }
        assignAimesFactoryToOrder(item, orderID: item.suggestedOrderID)
    }

    func assignAimesFactoryToOrder(_ item: AimesReviewItem, orderID: String) {
        let trimmedOrderID = orderID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedOrderID.isEmpty else { return }
        logUserAction("点击确认 AIMES 工厂单归属", details: [
            "suggestion_present": !item.suggestedOrderID.isEmpty,
            "manual_order_id": trimmedOrderID,
        ])
        beginDashboardOperation("aimes", label: "确认 AIMES 工厂单归属")
        dashboardAimesStatus = "正在确认 \(item.factoryOrder) 的订单归属…"
        runOrder(
            [
                "assign-aimes-order",
                "--ignore-key", item.ignoreKey,
                "--order-id", trimmedOrderID,
            ],
            failureStatus: "AIMES 工厂单归属保存失败",
            onFailure: {
                self.finishDashboardOperation("aimes")
                self.dashboardAimesStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "保存 AIMES 工厂单归属"))"
            }
        ) { object in
            self.finishDashboardOperation("aimes")
            self.applyDashboardObject(object)
            self.applyAimesReviewObject(object, presentIfNeeded: false)
            self.showAimesReviewPrompt = false
            self.dashboardAimesStatus = trimmedOrderID == item.suggestedOrderID
                ? "✅ 已将 \(item.factoryOrder) 按建议归入 \(trimmedOrderID)"
                : "✅ 已将 \(item.factoryOrder) 手工归入 \(trimmedOrderID)"
            self.dashboardSyncStatus = self.dashboardAimesStatus
            self.closePendingCenterIfEmpty()
        }
    }

    func restoreAimesFactoryAssignment(_ item: AimesReviewItem) {
        logUserAction("点击撤销 AIMES 工厂单归属")
        beginDashboardOperation("aimes", label: "撤销 AIMES 工厂单归属")
        dashboardAimesStatus = "正在撤销 \(item.factoryOrder) 的建议归属…"
        runOrder(
            ["restore-aimes-assignment", "--ignore-key", item.ignoreKey],
            failureStatus: "AIMES 建议归属撤销失败",
            onFailure: {
                self.finishDashboardOperation("aimes")
                self.dashboardAimesStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "撤销 AIMES 工厂单归属"))"
            }
        ) { object in
            self.finishDashboardOperation("aimes")
            self.applyDashboardObject(object)
            self.applyAimesReviewObject(object, presentIfNeeded: false)
            self.dashboardAimesStatus = "✅ 已撤销 \(item.factoryOrder) 的建议归属"
            self.dashboardSyncStatus = self.dashboardAimesStatus
        }
    }

    func scanDashboardServer(background: Bool = false, presentIfNeeded: Bool = true) {
        logUserAction(background ? "触发后台扫描 Server" : "点击扫描 Server", details: ["background": background])
        beginDashboardOperation("server", label: "扫描 Server")
        dashboardServerStatus = background ? "正在后台扫描 Server 变化…" : "正在扫描 Server 变化…"
        runOrder(["scan-server"], onFailure: {
            self.finishDashboardOperation("server")
            self.dashboardServerStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "扫描 Server"))"
            self.dashboardSyncStatus = self.dashboardServerStatus
        }) { object in
            self.finishDashboardOperation("server")
            let server = object["server"] as? [String: Any] ?? [:]
            self.applyCurrentIssues(from: object)
            self.applyDashboardOperationTrace(object)
            let rows = server["changes"] as? [[String: Any]] ?? []
            self.pendingServerChanges = serverChangePreviews(rows)
            self.selectedServerFolderPaths.removeAll()
            // A scan is metadata-only. Never call sync-index here: that would
            // parse Server workbooks and write production order/factory facts
            // before the user has confirmed an individual factory order.
            if self.pendingServerChanges.isEmpty {
                self.closePendingCenterIfEmpty()
                self.dashboardServerStatus = "✅ Server 扫描完成，没有待处理变化"
                self.dashboardSyncStatus = "✅ Server 扫描完成；未写入新的订单或工厂单事实"
            } else {
                self.dashboardServerStatus = "⚠️ Server 发现 \(self.pendingServerChanges.count) 项待逐单确认变化"
                self.dashboardSyncStatus = "请在待处理中心预览并逐单确认写入"
                if presentIfNeeded { self.showPendingCenterPrompt = true }
            }
        }
    }

    func toggleServerFolderSelection(_ folderPath: String) {
        logUserAction("点击选择 Server 文件夹")
        guard let group = serverFolderChangeGroups(pendingServerChanges).first(where: { $0.folderPath == folderPath }),
              !group.requiresManualReview else { return }
        if selectedServerFolderPaths.contains(folderPath) {
            selectedServerFolderPaths.remove(folderPath)
        } else {
            selectedServerFolderPaths.insert(folderPath)
        }
    }

    func selectAllServerFolders() {
        logUserAction("点击全选 Server 文件夹")
        selectedServerFolderPaths = Set(
            serverFolderChangeGroups(pendingServerChanges)
                .filter { !$0.requiresManualReview }
                .map(\.folderPath)
        )
    }

    func clearServerFolderSelection() {
        logUserAction("点击取消全选 Server 文件夹")
        selectedServerFolderPaths.removeAll()
    }

    func processPendingServerChanges() {
        logUserAction("点击自动处理待处理 Server 变化")
        let selectedFolders = selectedServerFolderPaths.filter { folder in
            serverFolderChangeGroups(pendingServerChanges).contains {
                $0.folderPath == folder && !$0.requiresManualReview
            }
        }
        guard !selectedFolders.isEmpty else {
            dashboardServerStatus = "⚠️ 请先选择要自动处理的文件夹"
            dashboardSyncStatus = dashboardServerStatus
            showPendingCenterPrompt = true
            return
        }
        beginDashboardOperation("server", label: "预览 Server 变化")
        showPendingCenterPrompt = false
        dashboardServerStatus = "正在预览 Server 变化；正式数据库暂不写入…"
        dashboardSyncStatus = dashboardServerStatus
        var arguments = ["preview-server-changes"]
        arguments += ["--include-hardware", "true"]
        for folder in selectedFolders.sorted() {
            arguments += ["--server-folder", folder]
        }
        runOrder(arguments, failureStatus: "Server 变化预览失败", onFailure: {
            self.finishDashboardOperation("server")
            self.dashboardServerStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "预览 Server 变化"))"
            self.dashboardSyncStatus = self.dashboardServerStatus
        }) { object in
            self.finishDashboardOperation("server")
            self.presentServerWritePreview(object)
        }
    }

    func confirmServerWrite(orderID: String, factoryOrder: String) {
        guard let preview = serverWritePreview, !orderRunning else { return }
        let trimmedOrder = orderID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedFactory = factoryOrder.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedOrder.isEmpty, !trimmedFactory.isEmpty else { return }
        beginDashboardOperation("server", label: "确认写入 Server 工厂单")
        dashboardServerStatus = "正在写入订单 \(trimmedOrder) 的工厂单 \(trimmedFactory)…"
        dashboardSyncStatus = dashboardServerStatus
        runOrder(
            [
                "confirm-server-preview",
                "--preview-token", preview.token,
                "--order-id", trimmedOrder,
                "--factory-order", trimmedFactory,
                "--confirm-write",
            ],
            failureStatus: "Server 工厂单写入失败",
            onFailure: {
                self.finishDashboardOperation("server")
                let message = businessFriendlyMessage(self.orderError, operation: "确认 Server 工厂单写入")
                self.serverWriteConfirmationNotice = "❌ \(message)"
                self.serverWriteConfirmationNoticeIsError = true
                self.serverWriteConfirmationFinished = false
                self.dashboardServerStatus = "⚠️ \(message)"
                self.dashboardSyncStatus = self.dashboardServerStatus
            }
        ) { object in
            self.finishDashboardOperation("server")
            let remainingOrders = self.serverWritePreview?.orders.compactMap { order -> ServerWriteOrderPreview? in
                guard order.orderID == trimmedOrder else { return order }
                let remainingFactories = order.factories.filter { $0.factoryOrder != trimmedFactory }
                guard !remainingFactories.isEmpty else { return nil }
                return ServerWriteOrderPreview(
                    id: order.id,
                    orderID: order.orderID,
                    sourceFolder: order.sourceFolder,
                    validationStatus: order.validationStatus,
                    validationMessage: order.validationMessage,
                    materials: order.materials,
                    factories: remainingFactories
                )
            }
            self.serverWritePreview = remainingOrders.map {
                ServerWritePreview(
                    token: preview.token,
                    sourceFolders: preview.sourceFolders,
                    materials: preview.materials,
                    orders: $0
                )
            }
            if self.serverWritePreview == nil {
                self.showServerWriteConfirmation = false
            }
            self.serverWriteConfirmationNotice = "✅ 已成功写入 \(trimmedOrder) / \(trimmedFactory)"
            self.serverWriteConfirmationNoticeIsError = false
            self.serverWriteConfirmationFinished = self.serverWritePreview == nil
            self.dashboardServerStatus = "✅ 已确认写入 \(trimmedOrder) / \(trimmedFactory)"
            self.dashboardSyncStatus = self.dashboardServerStatus
            self.refreshDashboardAfterServerWrite()
            _ = object
        }
    }

    func confirmServerMaterialPreview() {
        guard let preview = serverWritePreview, !orderRunning else { return }
        beginDashboardOperation("server", label: "确认写入 Server 材料")
        dashboardServerStatus = "正在写入 Server 订单材料…"
        dashboardSyncStatus = dashboardServerStatus
        runOrder(
            [
                "confirm-server-material-preview",
                "--preview-token", preview.token,
                "--confirm-write",
            ],
            failureStatus: "Server 材料写入失败",
            onFailure: {
                self.finishDashboardOperation("server")
                let message = businessFriendlyMessage(self.orderError, operation: "确认 Server 材料写入")
                self.serverWriteConfirmationNotice = "❌ \(message)"
                self.serverWriteConfirmationNoticeIsError = true
                self.serverWriteConfirmationFinished = false
                self.dashboardServerStatus = "⚠️ \(message)"
                self.dashboardSyncStatus = self.dashboardServerStatus
            }
        ) { object in
            self.finishDashboardOperation("server")
            let orders = (object["orders"] as? [String]) ?? []
            let orderText = orders.isEmpty ? "订单材料" : orders.joined(separator: "、")
            self.serverWriteConfirmationNotice = "✅ 已成功写入 \(orderText) 的材料"
            self.serverWriteConfirmationNoticeIsError = false
            self.serverWriteConfirmationFinished = true
            self.dashboardServerStatus = "✅ 已确认写入 \(orderText) 的材料"
            self.dashboardSyncStatus = self.dashboardServerStatus
            self.showServerWriteConfirmation = false
            self.refreshDashboardAfterServerWrite()
        }
    }

    func refreshDashboardAfterServerWrite() {
        guard !orderRunning else { return }
        beginDashboardOperation("sync", label: "刷新 Server 写入后的订单列表")
        dashboardSyncStatus = "正在刷新 Server 写入后的订单列表…"
        runOrder(["list-index"], failureStatus: "Server 写入后的订单列表刷新失败", onFailure: {
            self.finishDashboardOperation("sync")
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "刷新 Server 写入后的订单列表"))"
        }) { object in
            self.finishDashboardOperation("sync")
            self.applyDashboardObject(object, includeChanges: false)
            self.dashboardSyncStatus = "✅ 订单列表已刷新；正在刷新待处理中心…"
            self.scanDashboardServer(background: true, presentIfNeeded: false)
        }
    }

    private func applyServerIndexResult(_ object: [String: Any]) {
        applyDashboardObject(object, includeChanges: true)
        applyAimesReviewObject(object)
    }

    func prepareSelectedServerFolder(_ folderURL: URL) {
        pendingServerFolderURL = folderURL
        includeHardwareForServerProcessing = true
        showServerProcessingOptions = true
    }

    func processSelectedServerFolder(_ folderURL: URL, includeHardware: Bool) {
        logUserAction("点击处理 Server 文件夹", details: ["include_hardware": includeHardware])
        guard !orderRunning else { return }
        let folderPath = folderURL.standardizedFileURL.path
        let folderName = folderURL.lastPathComponent
        let hasSecurityScope = folderURL.startAccessingSecurityScopedResource()
        beginDashboardOperation("server", label: "预览 Server 文件夹")
        showPendingCenterPrompt = false
        dashboardServerStatus = "正在预览 Server 文件夹：\(folderName)；正式数据库暂不写入…"
        dashboardSyncStatus = dashboardServerStatus
        runOrder(
            [
                "preview-server-changes", "--server-folder", folderPath,
                "--include-hardware", includeHardware ? "true" : "false",
            ],
            failureStatus: "Server 文件夹预览失败",
            onFailure: {
                self.finishDashboardOperation("server")
                if hasSecurityScope { folderURL.stopAccessingSecurityScopedResource() }
                self.dashboardSyncStatus = self.dashboardServerStatus
                self.dashboardActivity.insert(
                    InventoryStep(
                        time: dashboardClockTime(),
                        title: "Server 文件夹处理",
                        detail: self.dashboardSyncStatus,
                        state: "failure",
                        paths: [folderPath]
                    ),
                    at: 0
                )
            }
        ) { object in
            self.finishDashboardOperation("server")
            if hasSecurityScope { folderURL.stopAccessingSecurityScopedResource() }
            self.presentServerWritePreview(object)
        }
    }

    func ignoreServerFolder(_ folderPath: String) {
        logUserAction("点击忽略 Server 文件夹")
        guard !orderRunning else { return }
        beginDashboardOperation("server", label: "记录 Server 忽略设置")
        dashboardServerStatus = "正在记录忽略设置：(URL(fileURLWithPath: folderPath).lastPathComponent)…"
        dashboardSyncStatus = dashboardServerStatus
        runOrder(
            ["ignore-server-folder", "--folder", folderPath],
            failureStatus: "忽略 Server 文件夹失败",
            onFailure: {
                self.finishDashboardOperation("server")
                self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "忽略 Server 文件夹"))"
            }
        ) { object in
            self.finishDashboardOperation("server")
            self.applyCurrentIssues(from: object)
            let rows = object["pending_server_changes"] as? [[String: Any]] ?? []
            self.pendingServerChanges = serverChangePreviews(rows)
            self.selectedServerFolderPaths.remove(folderPath)
            self.closePendingCenterIfEmpty()
            self.dashboardServerStatus = "✅ 已忽略文件夹；未来一个月内发生变化会重新提醒"
            self.dashboardSyncStatus = self.dashboardServerStatus
        }
    }

    func loadInventory() {
        logUserAction("点击刷新 Traveler 列表")
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
                let message = businessFriendlyMessage(
                    $0["message"] as? String ?? "Traveler 格式异常，请检查文件内容后重试。",
                    operation: "读取 Traveler"
                )
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
            self.activatePendingInventoryMapping()
        }
    }

    func requestInventoryMapping(folderPath: String, message: String = "") {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showPendingCenterPrompt = false
        showServerChangesPrompt = false
        // Current-issue paths can point to a report file (or the Report
        // directory) inside a standard order. Reprocessing must start from
        // the order folder so sync-index refreshes both the order status and
        // the active-issue list.
        pendingInventoryMappingFolder = inventoryMappingSourceFolderPath(trimmed)
        inventoryMappingRequestPath = trimmed
        inventoryMappingTargetNames = inventoryMappingNames(from: message)
        showInventoryMappingWorkspace = true
    }

    func closeInventoryMappingWorkspace() {
        showInventoryMappingWorkspace = false
        pendingInventoryMappingFolder = ""
        inventoryMappingRequestPath = ""
        inventoryMappingTargetNames = []
    }

    private func inventoryMappingNames(from message: String) -> [String] {
        guard let markerRange = message.range(of: "处理：") else { return [] }
        let remainder = message[markerRange.upperBound...]
        let payload = remainder.split(whereSeparator: { $0 == "；" || $0 == "。" }).first ?? Substring()
        return payload
            .split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func rereadPendingSourceFolder() {
        guard !pendingInventoryMappingFolder.isEmpty else { return }
        let candidate = URL(fileURLWithPath: pendingInventoryMappingFolder)
        var isDirectory = ObjCBool(false)
        let path = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? candidate.path
            : candidate.deletingLastPathComponent().path
        pendingInventoryMappingFolder = ""
        beginDashboardOperation("server", label: "重新读取订单文件")
        runOrder(["process-server-folder", "--folder", path, "--include-hardware", "true"], failureStatus: "重新读取订单文件失败", onFailure: {
            self.finishDashboardOperation("server")
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "重新读取订单文件"))"
        }) { object in
            self.finishDashboardOperation("server")
            self.applyDashboardObject(object)
            self.refreshDashboardOrdersAfterInventoryMapping()
        }
    }

    private func refreshDashboardOrdersAfterInventoryMapping() {
        beginDashboardOperation("sync", label: "刷新订单列表")
        dashboardSyncStatus = "正在刷新订单列表…"
        runOrder(["list-index"], failureStatus: "订单列表刷新失败", onFailure: {
            self.finishDashboardOperation("sync")
            self.dashboardSyncStatus = "⚠️ \(businessFriendlyMessage(self.orderError, operation: "刷新订单列表"))"
        }) { object in
            self.finishDashboardOperation("sync")
            self.applyDashboardObject(object, includeChanges: false)
            self.closePendingCenterIfEmpty()
            self.dashboardSyncStatus = self.pendingCenterItems.isEmpty
                ? "✅ 已重新读取订单文件并刷新订单列表"
                : "✅ 订单列表已刷新；待处理中心仍有项目需要处理"
        }
    }

    func activatePendingInventoryMapping() {
        guard !pendingInventoryMappingFolder.isEmpty else { return }
        guard !inventoryRunning else { return }
        let requestedURL = URL(fileURLWithPath: pendingInventoryMappingFolder)
        var isDirectory = ObjCBool(false)
        let pointsToDirectory = FileManager.default.fileExists(
            atPath: requestedURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        let requestedFolderURL = pointsToDirectory ? requestedURL : requestedURL.deletingLastPathComponent()
        let folderName = requestedFolderURL.lastPathComponent
        let normalizedFolderPath = requestedFolderURL.standardizedFileURL.path.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let normalizedFolderName = folderName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let candidates = inventoryTravelers.filter { traveler in
            let travelerFolderURL = URL(fileURLWithPath: traveler.id).deletingLastPathComponent()
            let travelerFolderPath = travelerFolderURL.standardizedFileURL.path.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            return travelerFolderPath == normalizedFolderPath
                || travelerFolderURL.lastPathComponent.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ) == normalizedFolderName
        }
        guard let traveler = candidates.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first else {
            inventoryStatus = "未找到 \(folderName) 对应的 Traveler，请先刷新 Traveler 列表"
            return
        }
        inventoryMappingRequestPath = ""
        selectedInventoryOrderID = ""
        selectedInventoryPaths = [traveler.id]
        inventoryPreviewRows = []
        inventoryErrors = []
        previewSelectedInventory()
    }

    func openInventoryChrome() {
        guard !inventoryRunning else { return }
        inventoryChromeStatus = "正在打开库存专用 Chrome…"
        runInventory(["open-chrome"], manageRunning: false, onFailure: { reason in
            self.inventoryChromeStatus = "❌ \(reason)"
        }) { object in
            if object["launched"] as? Bool == true {
                self.inventoryChromeOpenedByApp = true
            }
            self.inventoryChromeStatus = ""
        }
    }

    func updateInventoryCatalog() {
        logUserAction("点击更新商品资料")
        beginInventoryOperation("更新商品资料")
        inventoryCatalogStatus = "正在更新商品资料…"
        runInventory(["update-products"], onFailure: { reason in
            let status = inventoryCatalogUpdateFailureStatus(reason)
            self.inventoryCatalogStatus = status
        }) { object in
            let count = object["count"] as? Int ?? 0
            let added = object["added_count"] as? Int ?? 0
            let updated = object["updated_count"] as? Int ?? 0
            let removed = object["removed_count"] as? Int ?? 0
            let status = inventoryCatalogUpdateSuccessStatus(
                count,
                added: added,
                updated: updated,
                removed: removed
            )
            self.inventoryCatalogStatus = status
            self.inventoryStatus = status
            self.finishRunningInventoryStep(
                "已导出、校验并替换本地商品资料，共 \(count) 个商品；新增 \(added) 个，更新 \(updated) 个，删除 \(removed) 个",
                "success"
            )
        }
        inventoryStatus = "正在在线更新商品资料…"
    }

    func closeInventoryChromeOnQuit() {
        guard inventoryChromeOpenedByApp else { return }
        let command = projectRoot.appendingPathComponent("scripts/pp-flowhub")
        let process = Process()
        process.executableURL = command
        process.arguments = ["inventory", "close-chrome"]
        process.currentDirectoryURL = projectRoot
        process.environment = ProcessInfo.processInfo.environment
        do {
            try process.run()
            process.waitUntilExit()
            OperationLogWriter.shared.record(
                "inventory.chrome.close",
                message: process.terminationStatus == 0
                    ? "退出 App 时已关闭库存专用 Chrome"
                    : "退出 App 时关闭库存专用 Chrome 失败",
                details: ["exit_status": process.terminationStatus],
                force: true
            )
        } catch {
            OperationLogWriter.shared.record(
                "inventory.chrome.close",
                message: "退出 App 时无法关闭库存专用 Chrome",
                details: ["error": error.localizedDescription],
                force: true
            )
        }
        inventoryChromeOpenedByApp = false
    }

    func refreshInventoryCatalogStatus() {
        guard !inventoryRunning, inventoryCatalogStatus == "商品资料尚未检查" else { return }
        runInventory(["list-names"], manageRunning: false) { object in
            guard let catalog = object["catalog"] as? [String: Any],
                  let count = catalog["count"] as? Int else { return }
            let stale = catalog["stale"] as? Bool ?? false
            self.inventoryCatalogStatus = "\(count) 个商品" + (stale ? " · 已超过30天，请更新" : " · 资料有效")
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
        if !selectedInventoryOrderID.isEmpty {
            previewOrderInventory(
                orderID: selectedInventoryOrderID,
                factoryOrderNames: Array(selectedInventoryDocumentRemarks),
                factoryOrders: Array(selectedInventoryFactoryOrders)
            )
            return
        }
        inventorySteps.removeAll()
        inventoryStderrBuffer = ""
        inventoryRawErrors = ""
        inventoryPreviewRows = []
        inventoryErrors = []
        inventoryWriteBlocked = false
        inventoryWriteCompleted = false
        selectedInventoryOrderID = ""
        beginInventoryOperation("预检所选 Traveler")
        let paths = Array(selectedInventoryPaths).sorted()
        guard !paths.isEmpty else {
            inventoryStatus = "请先选择至少一份 Traveler"
            addInventoryStep("选择文件", "没有选择 Traveler，任务未开始", "failure")
            return
        }
        addInventoryStep("选择文件", "已选择 \(paths.count) 份 Traveler", "success")
        previewNext(
            paths,
            index: 0,
            selectedDocumentRemarks: selectedInventoryDocumentRemarks,
            accumulated: []
        )
    }

    func previewOrderInventory(
        orderID: String,
        factoryOrderNames: [String],
        factoryOrders: [String] = []
    ) {
        selectedInventoryOrderID = orderID
        selectedInventoryPaths = []
        selectedInventoryDocumentRemarks = Set(factoryOrderNames.filter { !$0.isEmpty })
        selectedInventoryFactoryOrders = Set(factoryOrders.filter { !$0.isEmpty })
        inventorySteps.removeAll()
        inventoryStderrBuffer = ""
        inventoryRawErrors = ""
        inventoryPreviewRows = []
        inventoryErrors = []
        inventoryWriteBlocked = false
        inventoryWriteCompleted = false
        beginInventoryOperation("预检订单出库数据")
        addInventoryStep("读取数据库订单事实", "正在读取 " + orderID + " 的材料、封边和所选工厂单五金", "running")
        var arguments = ["order-preview", "--order-id", orderID]
        for factoryOrder in selectedInventoryFactoryOrders.sorted() {
            arguments += ["--factory-order", factoryOrder]
        }
        runInventory(arguments) { object in
            self.applyInventoryPreviewObject(object, accumulated: [])
            self.inventoryStatus = self.inventoryErrors.isEmpty
                ? "订单出库数据预检通过，共 " + String(self.inventoryPreviewRows.count) + " 行"
                : "订单出库数据预检未通过，请先处理 " + String(self.inventoryErrors.count) + " 项异常"
            self.finishInventoryStep(
                named: "预检订单出库数据",
                detail: self.inventoryErrors.isEmpty ? "订单出库数据预检完成" : "订单出库数据预检未通过",
                state: self.inventoryErrors.isEmpty ? "success" : "failure"
            )
        }
    }

    func loadOutboundScope(
        orderID: String,
        factoryOrders: [String],
        completion: @escaping ([String: Any]?) -> Void
    ) {
        let normalizedOrderID = orderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOrderID.isEmpty else {
            completion(nil)
            return
        }
        var arguments = ["get-outbound-scope", "--order-id", normalizedOrderID]
        for factoryOrder in factoryOrders where !factoryOrder.isEmpty {
            arguments += ["--factory-order", factoryOrder]
        }
        runInventory(arguments, onFailure: { message in
            self.inventoryStatus = "❌ (message)"
            completion(nil)
        }) { object in
            completion(object)
        }
    }

    func saveOutboundScope(
        orderID: String,
        scopeType: String,
        requirement: String,
        factoryOrder: String = "",
        reason: String,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        guard !orderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var arguments = [
            "set-outbound-scope",
            "--order-id", orderID,
            "--scope-type", scopeType,
            "--requirement", requirement,
        ]
        if !factoryOrder.isEmpty { arguments += ["--factory-order", factoryOrder] }
        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--reason", reason]
        }
        runInventory(arguments, onFailure: { message in
            self.inventoryStatus = "❌ (message)"
            completion(false)
        }) { object in
            self.inventoryStatus = "✅ 出库范围已保存"
            self.addInventoryStep("保存出库范围", object["material"] != nil ? "订单材料范围已更新" : "工厂单出库范围已更新", "success")
            completion(true)
        }
    }

    func openAndFillSelectedInventory() {
        logUserAction("点击确认写入库存系统", details: ["confirm_save": true])
        let paths = Array(selectedInventoryPaths).sorted()
        let orderID = selectedInventoryOrderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !orderID.isEmpty || paths.count == 1 else {
            inventoryStatus = "出库操作需要一次只选择一份 Traveler"
            return
        }
        guard inventoryErrors.isEmpty, !inventoryPreviewRows.isEmpty else {
            inventoryStatus = "请先完成预检并处理全部异常"
            return
        }
        guard !inventoryWriteCompleted else {
            inventoryStatus = "本次出库已经完成，不能重复操作"
            return
        }
        let isRetry = inventoryWriteBlocked
        inventoryWriteBlocked = false
        if isRetry {
            inventorySuccessMessage = ""
            addInventoryStep("重试真实写入库存系统", "复用当前预检数据，继续处理未完成的出库单", "running")
        } else {
            beginInventoryOperation("真实写入库存系统")
        }
        addInventoryStep("安全确认", "用户已明确确认保存真实出库单", "success")
        inventoryStatus = "正在后台填写并保存库存出库单…"
        var arguments = ["outbound"]
        if !orderID.isEmpty {
            arguments += ["--order-id", orderID]
        } else {
            arguments += ["--traveler", paths[0]]
        }
        for remark in selectedInventoryDocumentRemarks.sorted() {
            arguments += ["--document-remark", remark]
        }
        for factoryOrder in selectedInventoryFactoryOrders.sorted() {
            arguments += ["--factory-order", factoryOrder]
        }
        arguments.append("--confirm-save")
        runInventory(arguments, onFailure: { reason in
            self.inventoryWriteBlocked = true
            self.inventoryWriteCompleted = false
            self.inventoryStatus = "❌ \(reason)；当前预检数据仍保留，可点击“重试出库”"
        }) { object in
            self.finishRunningInventoryStep(
                self.inventorySteps.last(where: { $0.state == "running" })?.detail ?? "库存系统后台操作已完成",
                "success"
            )
            if object["customer_supplied"] as? Bool == true {
                self.inventoryWriteCompleted = true
                self.inventoryStatus = "✅ 客户材料出库已记录（仅更新数据库）"
                self.inventorySuccessMessage = "客户提供材料且没有需要出库的五金，未创建库存系统出库单。"
                self.addInventoryStep("✅ 出库状态已记录", "客户材料已确认出库；仅更新数据库，未打开库存系统", "success")
            } else if object["no_outbound_required"] as? Bool == true {
                self.inventoryWriteCompleted = true
                self.inventoryStatus = "✅ 本订单已明确标记为无需出库"
                self.addInventoryStep("任务完成", "已记录无需出库决定，未打开库存系统", "success")
            } else if object["saved"] as? Bool == true {
                let results = object["results"] as? [[String: Any]] ?? []
                let numbers = results.compactMap { $0["documentNumber"] as? String }
                let detail = results.map { result -> String in
                    let remark = result["remark"] as? String ?? "未知备注"
                    let number = result["documentNumber"] as? String ?? "未知单号"
                    if result["unchanged"] as? Bool == true {
                        return "\(remark)：\(number) 无变化，已跳过"
                    }
                    return "\(remark)：\(number) \(result["updated"] as? Bool == true ? "已更新" : "已新增")"
                }.joined(separator: "；")
                let numberText = numbers.isEmpty ? "未知单号" : numbers.joined(separator: "、")
                self.inventoryWriteCompleted = true
                self.inventoryStatus = "✅✅ 出库处理成功！\(numberText)"
                self.inventorySuccessMessage = "出库处理成功！\(detail)"
                self.addInventoryStep("✅ 出库处理成功", "\(detail)；本机同步记录已更新", "success")
                if orderID.isEmpty {
                    self.markInventoryTravelerSaved(path: paths[0], documentNumber: numberText)
                    self.addInventoryStep("左侧状态已更新", "当前 Traveler 已立即标记为“已出库”", "success")
                } else {
                    self.addInventoryStep("订单状态已更新", "数据库订单出库记录已保存，已出库工厂单状态将重新同步", "success")
                }
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
        let nameArgument = selectedInventoryOrderID.isEmpty ? "--traveler-name" : "--item-name"
        for name in uniqueNames {
            arguments += [nameArgument, name]
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
            self.rereadPendingSourceFolder()
        }
    }

    func refreshInventoryMappings() {
        runInventory(["list-mappings"]) { object in
            let manual = object["manual"] as? [String: Any] ?? [:]
            self.inventoryManualMappings = manual.keys.sorted().map { name in
                InventoryManualMapping(
                    id: name,
                    name: name,
                    productCode: manual[name] as? String ?? ""
                )
            }
            let ignored = object["ignored"] as? [String: Any] ?? [:]
            self.inventoryIgnoredMappings = ignored.keys.sorted().map { name in
                InventoryIgnoredMapping(
                    id: name,
                    name: name,
                    reason: ignored[name] as? String ?? ""
                )
            }
        }
    }

    func saveSettingsManualMapping(name: String, productCode: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = productCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedName.isEmpty, !trimmedCode.isEmpty else {
            settingsStatus = "❌ 映射名称和商品 SKU 不能为空。"
            return
        }
        beginInventoryOperation("保存材料映射")
        runInventory(["set-mapping", "--item-name", trimmedName, "--product-code", trimmedCode]) { _ in
            self.settingsStatus = "✅ 材料映射已保存：\(trimmedName) → \(trimmedCode)"
            self.refreshInventoryMappings()
        }
    }

    func updateSettingsManualMapping(oldName: String, name: String, productCode: String) {
        let trimmedOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = productCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedOldName.isEmpty, !trimmedName.isEmpty, !trimmedCode.isEmpty else {
            settingsStatus = "❌ 映射名称和商品 SKU 不能为空。"
            return
        }
        beginInventoryOperation("修改材料映射")
        runInventory([
            "update-mapping", "--old-name", trimmedOldName,
            "--item-name", trimmedName, "--product-code", trimmedCode,
        ]) { _ in
            self.settingsStatus = "✅ 材料映射已修改：\(trimmedName) → \(trimmedCode)"
            self.refreshInventoryMappings()
        }
    }

    func removeSettingsManualMapping(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        beginInventoryOperation("删除材料映射")
        runInventory(["remove-mapping", "--item-name", trimmedName]) { _ in
            self.settingsStatus = "✅ 已删除材料映射：\(trimmedName)"
            self.refreshInventoryMappings()
        }
    }

    func saveInventoryIgnoredMapping(name: String, reason: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            settingsStatus = "❌ 忽略项目名称不能为空。"
            return
        }
        let pendingSourceFolder = pendingInventoryMappingFolder
        beginInventoryOperation("保存全局忽略项目")
        runInventory([
            "ignore-item",
            "--item-name", trimmedName,
            "--reason", reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "用户在设置中选择全局忽略"
                : reason.trimmingCharacters(in: .whitespacesAndNewlines),
        ]) { _ in
            self.settingsStatus = "✅ 全局忽略项目已保存：\(trimmedName)"
            self.inventoryMappingTargetNames.removeAll { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }
            if !pendingSourceFolder.isEmpty {
                self.rereadPendingSourceFolder()
            } else {
                self.refreshInventoryMappings()
            }
        }
    }

    func updateInventoryIgnoredMapping(oldName: String, name: String, reason: String) {
        let trimmedOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOldName.isEmpty, !trimmedName.isEmpty else {
            settingsStatus = "❌ 忽略项目名称不能为空。"
            return
        }
        beginInventoryOperation("修改全局忽略项目")
        runInventory([
            "update-ignore",
            "--old-name", trimmedOldName,
            "--name", trimmedName,
            "--ignored", "true",
            "--reason", reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "用户在设置中选择全局忽略"
                : reason.trimmingCharacters(in: .whitespacesAndNewlines),
        ]) { _ in
            self.settingsStatus = "✅ 全局忽略项目已修改：(trimmedName)"
            self.refreshInventoryMappings()
        }
    }

    func removeInventoryIgnoredMapping(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        beginInventoryOperation("删除全局忽略项目")
        runInventory(["unignore-item", "--item-name", trimmedName]) { _ in
            self.settingsStatus = "✅ 已删除全局忽略项目：(trimmedName)"
            self.refreshInventoryMappings()
        }
    }

    func searchInventoryProducts(_ query: String) {
        logUserAction("点击搜索库存商品", details: ["query_present": !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty])
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
        logUserAction("点击保存材料映射", details: ["traveler_name_present": !travelerName.isEmpty, "product_code_present": !productCode.isEmpty])
        beginInventoryOperation("保存材料映射")
        addInventoryStep("确认映射", "\(travelerName) → \(productCode)", "running")
        let nameArgument = selectedInventoryOrderID.isEmpty ? "--traveler-name" : "--item-name"
        runInventory([
            "set-mapping", nameArgument, travelerName,
            "--product-code", productCode,
        ]) { object in
            let product = object["product"] as? [String: Any] ?? [:]
            let name = product["name"] as? String ?? productCode
            self.finishRunningInventoryStep("已映射到 \(productCode) \(name)", "success")
            self.inventoryStatus = "映射已保存，正在重新预检"
            self.inventoryMappingTargetNames.removeAll { $0.caseInsensitiveCompare(travelerName) == .orderedSame }
            self.previewSelectedInventory()
            self.rereadPendingSourceFolder()
        }
    }

    @discardableResult
    private func consumeInventoryPreviewObject(
        _ object: [String: Any],
        accumulated: [InventoryPreviewRow]
    ) -> [InventoryPreviewRow] {
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
        let excluded = object["excluded_items"] as? [[String: Any]] ?? []
        next += excluded.map {
            InventoryPreviewRow(
                travelerName: $0["name"] as? String ?? "",
                productCode: "—",
                productName: "不进入出库单",
                quantity: $0["quantity"] as? Double ?? 0,
                source: $0["reason"] as? String ?? "已确认的出库范围外项目",
                status: $0["status"] as? String ?? "不出库",
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
                source: businessFriendlyMessage(
                    $0["message"] as? String ?? "未找到唯一库存商品，请补充商品映射或选择忽略。",
                    operation: "校验库存材料"
                ),
                status: "未映射",
                section: $0["section"] as? String ?? ""
            )
        }
        if object["ready"] as? Bool != true {
            inventoryErrors += missing.map {
                businessFriendlyMessage(
                    $0["message"] as? String ?? "存在未映射材料，请补充商品映射或选择忽略。",
                    operation: "校验库存材料"
                )
            }
        }
        let sourceIsDatabase = (object["source_type"] as? String) == "database"
        finishRunningInventoryStep(
            object["ready"] as? Bool == true
                ? (sourceIsDatabase ? "数据库事实、数量和商品映射检查通过" : "文件结构、数量和商品映射检查通过")
                : "存在未映射或无效材料",
            object["ready"] as? Bool == true ? "success" : "failure"
        )
        return next
    }

    private func applyInventoryPreviewObject(
        _ object: [String: Any],
        accumulated: [InventoryPreviewRow]
    ) {
        inventoryPreviewRows = sortedInventoryPreviewRows(
            consumeInventoryPreviewObject(object, accumulated: accumulated)
        )
        inventoryStatus = inventoryErrors.isEmpty
            ? "订单出库数据预检通过，共 \(inventoryPreviewRows.count) 行"
            : "订单出库数据预检未通过，请先处理 \(inventoryErrors.count) 项异常"
    }

    private func previewNext(
        _ paths: [String],
        index: Int,
        selectedDocumentRemarks: Set<String> = [],
        accumulated: [InventoryPreviewRow]
    ) {
        guard index < paths.count else {
            inventoryPreviewRows = sortedInventoryPreviewRows(accumulated)
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
        var previewArguments = ["preview", "--traveler", paths[index]]
        for remark in selectedDocumentRemarks.sorted() {
            previewArguments += ["--document-remark", remark]
        }
        runInventory(previewArguments, manageRunning: index == 0) { object in
            let next = self.consumeInventoryPreviewObject(object, accumulated: accumulated)
            self.previewNext(
                paths,
                index: index + 1,
                selectedDocumentRemarks: selectedDocumentRemarks,
                accumulated: next
            )
        }
    }

    private func runInventory(
        _ arguments: [String],
        manageRunning: Bool = true,
        onFailure: ((String) -> Void)? = nil,
        completion: @escaping ([String: Any]) -> Void
    ) {
        if manageRunning {
            guard !inventoryRunning else { return }
            inventoryRunning = true
            inventoryStatus = selectedInventoryOrderID.isEmpty
                ? "正在检查 Traveler 和商品资料…"
                : "正在检查订单数据库和商品资料…"
            inventoryStderrBuffer = ""
            inventoryRawErrors = ""
        }
        let root = projectRoot
        let command = root.appendingPathComponent("scripts/pp-flowhub")
        let operationID = newOperationID(
            "库存后台操作",
            details: ["command": "inventory", "argument_count": arguments.count, "write_requested": arguments.contains("--confirm-save")]
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = command
            process.arguments = ["inventory"] + arguments
            process.currentDirectoryURL = root
            process.environment = self.environmentForOperation(operationID)
            process.standardOutput = output
            process.standardError = errors
            errors.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self.consumeInventoryLogChunk(chunk) }
            }
            do {
                try process.run()
                let timeoutLock = NSLock()
                var timedOut = false
                let timeoutWork = DispatchWorkItem {
                    timeoutLock.lock()
                    timedOut = process.isRunning
                    timeoutLock.unlock()
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    // Browser page waits are capped at 60 seconds; keep the
                    // outer App deadline longer so one page wait can return
                    // its specific diagnostic before the App cancels it.
                    deadline: .now() + 90,
                    execute: timeoutWork
                )
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeoutWork.cancel()
                errors.fileHandleForReading.readabilityHandler = nil
                let remainder = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.inventoryRunning = false
                    if !remainder.isEmpty { self.consumeInventoryLogChunk(remainder + "\n") }
                    if !self.inventoryStderrBuffer.isEmpty {
                        self.consumeInventoryLogChunk("\n")
                    }
                    timeoutLock.lock()
                    let operationTimedOut = timedOut
                    timeoutLock.unlock()
                    if operationTimedOut {
                        let reason = "库存系统操作超过 90 秒未完成，请检查网络、登录状态或库存系统页面后重试。"
                        self.inventoryStatus = "❌ \(reason)"
                        self.finishRunningInventoryStep(reason, "failure")
                        onFailure?(reason)
                        return
                    }
                    let errorText = self.inventoryRawErrors.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        let reason = businessFriendlyMessage(errorText, operation: "读取库存结果")
                        self.inventoryStatus = "❌ \(reason)"
                        self.finishRunningInventoryStep(reason, "failure")
                        onFailure?(reason)
                        return
                    }
                    if let fatal = object["fatal"] as? [String: Any] {
                        let reason = businessFriendlyMessage(
                            fatal["message"] as? String ?? "库存预检未通过，请检查 Traveler 和商品资料后重试。",
                            operation: "库存操作"
                        )
                        self.inventoryStatus = "❌ \(reason)"
                        self.finishRunningInventoryStep(reason, "failure")
                        onFailure?(reason)
                        return
                    }
                    completion(object)
                }
            } catch {
                DispatchQueue.main.async {
                    self.inventoryRunning = false
                    let reason = businessFriendlyMessage(error.localizedDescription, operation: "启动库存操作")
                    self.inventoryStatus = "❌ \(reason)"
                    self.finishRunningInventoryStep(reason, "failure")
                    onFailure?(reason)
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
        OperationLogWriter.shared.record(
            "app.step",
            message: title,
            details: ["detail": detail, "state": state, "workflow": "inventory"]
        )
    }

    private func finishRunningInventoryStep(_ detail: String, _ state: String) {
        OperationLogWriter.shared.record(
            "app.step.finished",
            message: state == "failure" ? "库存步骤失败" : "库存步骤完成",
            details: ["detail": detail, "state": state, "workflow": "inventory"]
        )
        guard let index = inventorySteps.lastIndex(where: { $0.state == "running" }) else {
            addInventoryStep(state == "failure" ? "操作失败" : "操作完成", detail, state)
            return
        }
        let current = inventorySteps[index]
        inventorySteps[index] = InventoryStep(time: current.time, title: current.title, detail: detail, state: state)
    }

    private func finishInventoryStep(named title: String, detail: String, state: String) {
        guard let index = inventorySteps.lastIndex(where: { $0.title == title && $0.state == "running" }) else {
            return
        }
        let current = inventorySteps[index]
        inventorySteps[index] = InventoryStep(
            id: current.id,
            time: current.time,
            title: current.title,
            detail: detail,
            state: state,
            paths: current.paths,
            operationDetails: current.operationDetails,
            contextDetails: current.contextDetails,
            startedAt: current.startedAt,
            duration: current.startedAt.map { max(0, Date().timeIntervalSince($0)) }
        )
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
            inventorySteps = appendingInventoryProgressStep(inventorySteps, message: message)
        }
    }

    private func addOrderStep(_ title: String, _ detail: String, _ state: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let now = Date()
        orderSteps.append(InventoryStep(
            time: formatter.string(from: now),
            title: title,
            detail: detail,
            state: state,
            startedAt: state == "running" ? now : nil,
            duration: state == "running" ? nil : 0
        ))
        OperationLogWriter.shared.record(
            "app.step",
            message: title,
            details: ["detail": detail, "state": state, "workflow": "order"]
        )
    }

    private func finishOrderStep(_ detail: String, _ state: String) {
        OperationLogWriter.shared.record(
            "app.step.finished",
            message: state == "failure" ? "订单步骤失败" : "订单步骤完成",
            details: ["detail": detail, "state": state, "workflow": "order"]
        )
        guard let index = orderSteps.lastIndex(where: { $0.state == "running" }) else {
            addOrderStep(state == "failure" ? "操作失败" : "操作完成", detail, state)
            return
        }
        let current = orderSteps[index]
        let now = Date()
        let elapsed = current.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        orderSteps[index] = InventoryStep(
            id: current.id,
            time: current.time,
            title: current.title,
            detail: detail,
            state: state,
            paths: current.paths,
            operationDetails: current.operationDetails,
            contextDetails: current.contextDetails,
            startedAt: current.startedAt,
            duration: elapsed
        )
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
            if let updated = updatingLatestRunningStep(orderSteps, detail: message) {
                orderSteps = updated
            } else {
                addOrderStep("后台操作", message, "running")
            }
        }
    }

    private func runOrder(
        _ arguments: [String],
        failureStatus: String = "校验未通过",
        onFailure: (() -> Void)? = nil,
        completion: @escaping ([String: Any]) -> Void
    ) {
        guard !orderRunning else { return }
        orderRunning = true
        orderError = ""
        orderCreatedPath = ""
        orderStderrBuffer = ""
        orderRawErrors = ""
        let root = projectRoot
        let command = root.appendingPathComponent("scripts/pp-flowhub")
        let operationID = newOperationID(
            "订单后台操作",
            details: ["command": "order", "argument_count": arguments.count]
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = command
            process.arguments = ["order"] + arguments
            process.currentDirectoryURL = root
            process.environment = self.environmentForOperation(operationID)
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
                    defer { self.startPendingDashboardOutboundRefreshIfNeeded() }
                    if !remainder.isEmpty { self.consumeOrderLogChunk(remainder + "\n") }
                    if !self.orderStderrBuffer.isEmpty { self.consumeOrderLogChunk("\n") }
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        let reason = businessFriendlyMessage(self.orderRawErrors, operation: "读取订单结果")
                        self.orderError = reason
                        self.orderStatus = failureStatus
                        self.finishOrderStep(reason, "failure")
                        onFailure?()
                        return
                    }
                    if let fatal = object["fatal"] as? [String: Any] {
                        let code = fatal["code"] as? String ?? ""
                        let reason = businessFriendlyMessage(
                            fatal["message"] as? String ?? "订单校验未通过，请检查订单报表后重试。",
                            operation: "订单操作"
                        )
                        self.orderError = reason
                        if code == "missing_materials" {
                            self.orderStatus = "未找到 material 文件"
                        } else if code == "material_generation_failed" {
                            self.orderStatus = "自动生成失败，请手动生成 material 文件"
                        } else {
                            self.orderStatus = failureStatus
                        }
                        self.finishOrderStep(reason, "failure")
                        if code == "missing_materials" && !self.selectedOrderPath.isEmpty {
                            self.showMaterialGenerationPrompt = true
                        }
                        onFailure?()
                        return
                    }
                    completion(object)
                }
            } catch {
                DispatchQueue.main.async {
                    self.orderRunning = false
                    defer { self.startPendingDashboardOutboundRefreshIfNeeded() }
                    let reason = businessFriendlyMessage(error.localizedDescription, operation: "启动订单操作")
                    self.orderError = reason
                    self.orderStatus = "无法启动订单读取功能"
                    self.finishOrderStep(reason, "failure")
                    onFailure?()
                }
            }
        }
    }

    func loadOrderFolders() {
        logUserAction("点击刷新订单文件夹列表")
        orderSteps.removeAll()
        selectedOrderPath = ""
        selectedOrderId = ""
        orderMaterials = []
        orderFittings = []
        orderFactories = []
        orderEdgeBanding = [:]
        orderWarnings = []
        orderExistingTravelerPath = ""
        orderPreviewValidated = false
        orderMissingMaterial = false
        selectedOrderIsOptimized = false
        selectedOrderIsCompleted = false
        let source = orderSourceKind == "cutToSize" ? activeCutToSizeRoot : activeOwnedSourceRoot
        orderStatus = "正在读取服务器文件夹列表…"
        addOrderStep(
            "读取服务器目录",
            "只读取订单文件夹名称，不打开 Excel：\(source)",
            "running"
        )
        let arguments = ["list", "--source-root", source]
        runOrder(arguments) { object in
            let rows = object["orders"] as? [[String: Any]] ?? []
            self.orderFolders = rows.map {
                OrderFolderItem(
                    id: $0["path"] as? String ?? UUID().uuidString,
                    orderId: $0["order_id"] as? String ?? "",
                    modifiedAt: $0["modified_at"] as? String ?? ""
                )
            }
            self.orderStatus = "已读取 \(rows.count) 个服务器订单文件夹；点击后才会校验 Excel"
            let kind = self.orderSourceKind == "cutToSize" ? "来料加工" : "自有"
            self.finishOrderStep("找到 \(rows.count) 个\(kind)订单文件夹", "success")
        }
    }

    func previewOrderFolder(_ item: OrderFolderItem, recordSelection: Bool = true) {
        orderSteps.removeAll()
        selectedOrderPath = item.id
        selectedOrderId = item.orderId
        orderMaterials = []
        orderFittings = []
        orderFactories = []
        orderEdgeBanding = [:]
        orderWarnings = []
        orderStockRows = []
        orderMaterialsFile = ""
        orderExistingTravelerPath = findLocalOrderTraveler(item.orderId)
        orderPreviewValidated = false
        orderMissingMaterial = false
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
        addOrderStep(
            "读取并校验",
            item.orderId.hasPrefix("CS") ? "material 板材与封边数量" : "material、板材清单和 Fittingslist",
            "running"
        )
        runOrder(["preview-related", "--folder", item.id]) { object in
            let issues = orderPreviewIssues(object)
            if let issue = issues.first(where: { $0.orderId == item.orderId }) ?? issues.first {
                let reason = businessFriendlyMessage(issue.message, operation: "校验订单")
                self.orderError = reason
                self.finishOrderStep(reason, "failure")
                if issue.code == "missing_materials" {
                    self.orderStatus = "未找到 material 文件"
                    self.orderMissingMaterial = true
                    self.showMaterialGenerationPrompt = true
                } else {
                    self.orderStatus = "校验未通过"
                }
                for additional in issues where additional != issue {
                    self.addOrderStep(
                        "关联订单校验失败",
                        businessFriendlyMessage(additional.message, operation: "校验关联订单"),
                        "failure"
                    )
                }
                return
            }
            self.applyOrderPreview(object, targetOrderID: item.orderId)
            self.orderPreviewValidated = true
            self.orderMissingMaterial = false
            let existing = !self.orderExistingTravelerPath.isEmpty
            if item.orderId.hasPrefix("CS") {
                self.orderStatus = existing
                    ? "\(item.orderId) 板材和封边校验通过，可更新 Traveler"
                    : "\(item.orderId) 板材和封边校验通过，可生成 Traveler"
                self.finishOrderStep("来料加工订单无五金，板材与封边数量已读取", "success")
            } else {
                self.orderStatus = existing
                    ? "\(item.orderId) 校验通过，已找到本机 Traveler，可直接更新"
                    : "\(item.orderId) 校验通过，可以选择忽略五金或生成 Traveler"
                self.finishOrderStep(
                    "发现 \(self.orderFactories.count) 个工厂单、\(self.orderFittings.count) 项五金",
                    self.orderWarnings.isEmpty ? "success" : "warning"
                )
            }
            for warning in self.orderWarnings {
                self.addOrderStep("数据选择提醒", warning, "warning")
            }
        }
    }

    private func findLocalOrderTraveler(_ orderId: String) -> String {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: activeOrderRoot, isDirectory: true)
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

    private func applyOrderPreview(_ object: [String: Any], targetOrderID: String? = nil) {
        let payload: [String: Any]
        if let targetOrderID,
           let related = object["orders"] as? [[String: Any]],
           let selected = related.first(where: { ($0["order_id"] as? String)?.caseInsensitiveCompare(targetOrderID) == .orderedSame }) {
            payload = selected
            selectedOrderId = targetOrderID
        } else {
            payload = object
            selectedOrderId = object["order_id"] as? String ?? selectedOrderId
        }
        orderMaterialsFile = payload["materials_file"] as? String ?? ""
        if let existing = payload["existing_traveler"] as? String, !existing.isEmpty {
            orderExistingTravelerPath = existing
        }
        orderWarnings = payload["warnings"] as? [String] ?? []
        orderMaterials = (payload["materials"] as? [[String: Any]] ?? []).map {
            OrderMaterialPreview(
                kind: $0["kind"] as? String ?? "",
                thickness: ($0["thickness"] as? NSNumber)?.doubleValue ?? 0,
                color: $0["color"] as? String ?? "",
                quantity: ($0["quantity"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        orderEdgeBanding = (payload["edge_banding"] as? [String: NSNumber] ?? [:])
            .mapValues(\.doubleValue)
        var factories: [OrderFactoryPreview] = []
        var fittings: [OrderFittingPreview] = []
        for factory in payload["factories"] as? [[String: Any]] ?? [] {
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

    func loadOrderDetailFromDatabase(_ item: OrderDashboardItem) {
        selectedOrderPath = item.sourceFolder
        selectedOrderId = item.orderId
        selectedOrderIsOptimized = item.stage == "已优化"
        selectedOrderIsCompleted = orderDashboardIsCompleted(item.stage)
        if orderRunning {
            pendingOrderDetailItem = item
            orderDetailWaiting = true
            orderStatus = "正在扫描，扫描完成后自动读取详情…"
            schedulePendingOrderDetailRetry()
            return
        }
        pendingOrderDetailItem = nil
        orderDetailWaiting = false
        orderExistingTravelerPath = ""
        orderPreviewValidated = false
        orderMaterials = []
        orderFittings = []
        orderFactories = []
        orderEdgeBanding = [:]
        orderStatus = "正在读取数据库详情…"
        runOrder(["detail", "--order-id", item.orderId], onFailure: {
            self.orderDetailWaiting = false
        }) { object in
            let materialRows = object["materials"] as? [[String: Any]] ?? []
            let hardwareRows = object["hardware"] as? [[String: Any]] ?? []
            let factories = item.factories.map { factory -> [String: Any] in
                let rows = hardwareRows.filter { ($0["factory_order"] as? String ?? "").caseInsensitiveCompare(factory.factoryOrder) == .orderedSame }
                var occurrences: [String: Int] = [:]
                return [
                    "factory_order": factory.factoryOrder,
                    "order_name": factory.orderName,
                    "fittings": rows.map {
                        let name = $0["name"] as? String ?? ""
                        let code = $0["product_code"] as? String ?? ""
                        let size = $0["spec"] as? String ?? ""
                        let signature = "\(factory.factoryOrder)|\(code)|\(name)|\(size)"
                        let occurrence = occurrences[signature, default: 0]
                        occurrences[signature] = occurrence + 1
                        return ["key": "\(signature)|\(occurrence)", "name": name, "code": code, "size": size, "unit": $0["unit"] as? String ?? "", "quantity": $0["quantity"] as? NSNumber ?? 0, "ignored": false]
                    }
                ]
            }
            let materials: [[String: Any]] = materialRows.compactMap { row in
                guard let kind = row["material_type"] as? String else { return nil }
                let thickness = Double(row["thickness"] as? String ?? "") ?? (row["thickness"] as? NSNumber)?.doubleValue ?? 0
                return ["kind": kind, "thickness": thickness, "color": row["color"] as? String ?? "", "quantity": row["quantity"] as? NSNumber ?? 0]
            }
            var edges: [String: NSNumber] = [:]
            for row in materialRows where (row["material_type"] as? String) == "edge" {
                let color = row["color"] as? String ?? ""
                edges[color] = row["quantity"] as? NSNumber ?? 0
            }
            let payload: [String: Any] = ["order_id": item.orderId, "materials": materials, "edge_banding": edges, "factories": factories, "warnings": []]
            self.applyOrderPreview(payload, targetOrderID: item.orderId)
            self.orderDetailWaiting = false
            self.orderPreviewValidated = !materialRows.isEmpty || item.stage == "已设计"
            self.orderStatus = materialRows.isEmpty ? "数据库暂无已保存材料明细，请重新同步源文件" : "已读取数据库中的材料、五金和订单状态"
            self.finishOrderStep(self.orderStatus, materialRows.isEmpty ? "warning" : "success")
        }
    }

    private func schedulePendingOrderDetailRetry() {
        guard !orderDetailRetryScheduled else { return }
        orderDetailRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.orderDetailRetryScheduled = false
            guard let item = self.pendingOrderDetailItem else { return }
            guard self.selectedOrderId.caseInsensitiveCompare(item.orderId) == .orderedSame else {
                self.pendingOrderDetailItem = nil
                return
            }
            if self.orderRunning {
                self.schedulePendingOrderDetailRetry()
            } else {
                self.loadOrderDetailFromDatabase(item)
            }
        }
    }

    func saveOrderAnnotations(
        orderID: String,
        userNote: String,
        plannedDays: [OrderInstallationDay],
        actualDays: [OrderInstallationDay]
    ) {
        let encode: ([OrderInstallationDay]) -> String = { days in
            let payload = days.map { ["date": $0.date, "installer": $0.installer] }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let value = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return value
        }
        let targetOrderID = orderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetOrderID.isEmpty else {
            orderStatus = "无法保存订单信息：没有选择订单"
            return
        }
        orderStatus = "正在保存订单备注和安装安排…"
        addOrderStep("保存订单信息", "正在保存备注、计划安装日期和实际安装日期", "running")
        runOrder(
            [
                "save-order-annotations",
                "--order-id", targetOrderID,
                "--note", userNote,
                "--planned-installation-days", encode(plannedDays),
                "--actual-installation-days", encode(actualDays),
            ],
            failureStatus: "订单备注和安装安排保存失败"
        ) { object in
            self.applyDashboardObject(object, includeChanges: false)
            self.orderStatus = "订单备注和安装安排已保存"
            self.finishOrderStep("订单备注和安装安排已保存", "success")
        }
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
        logUserAction("点击生成 Traveler")
        guard orderCanGenerateTraveler else {
            orderStatus = "请先选择订单"
            addOrderStep("无法生成 Traveler", "请先选择订单详情", "failure")
            return
        }
        let targetOrderID = selectedOrderId
        orderStatus = "正在从数据库生成 Traveler…"
        addOrderStep("从数据库生成 Traveler", "正在读取当前订单已保存的材料和五金", "running")
        runOrder(["generate-db", "--order-id", targetOrderID], failureStatus: "数据库 Traveler 生成失败") { object in
            let path = object["traveler"] as? String ?? object["created"] as? String ?? ""
            guard !path.isEmpty else {
                self.finishOrderStep("生成结果没有返回 Excel 文件路径", "failure")
                return
            }
            self.orderCreatedPath = path
            self.orderExistingTravelerPath = path
            self.orderStatus = "Traveler 已生成，正在打开 Excel"
            self.finishOrderStep("Traveler 已从数据库生成，用户可在 Excel 中打印或另存", "success")
            self.openSelectedOrderTraveler()
        }
    }

    func generateMissingMaterial() {
        logUserAction("点击自动生成 material 文件")
        guard !selectedOrderPath.isEmpty, !selectedOrderId.isEmpty else { return }
        showMaterialGenerationPrompt = false
        orderError = ""
        orderStatus = "正在从 Report 自动生成 material…"
        addOrderStep(
            "自动生成 material",
            "正在读取 Report 中的板材清单和封边统计",
            "running"
        )
        runOrder([
            "generate-material", "--folder", selectedOrderPath,
            "--order-id", selectedOrderId,
        ]) { object in
            let path = object["materials_file"] as? String ?? ""
            self.finishOrderStep("已生成：\(path)", "success")
            self.orderStatus = "material 已生成，正在重新校验订单…"
            guard let current = self.orderFolders.first(where: { $0.id == self.selectedOrderPath }) else { return }
            self.previewOrderFolder(current, recordSelection: false)
        }
    }

    func checkSelectedOrderStock() {
        logUserAction("点击查询材料库存")
        guard !selectedOrderIsCompleted else {
            addOrderStep("无法查询库存", "订单已出货，只能计算成本", "failure")
            return
        }
        guard orderPreviewReady else {
            addOrderStep("无法查询库存", "请先选择订单并完成材料校验", "failure")
            return
        }
        orderStockRows = []
        orderStatus = "正在查询材料库存…"
        addOrderStep("查询实时库存", "正在汇总当前订单的板材、封边和五金", "running")
        runOrder(
            ["stock-check", "--folder", selectedOrderPath],
            failureStatus: "库存查询失败，可手工重试"
        ) { object in
            self.orderStockRows = (object["rows"] as? [[String: Any]] ?? []).map { row in
                let code = row["productCode"] as? String ?? UUID().uuidString
                return OrderStockPreview(
                    id: code,
                    productCode: code,
                    productName: row["productName"] as? String ?? "",
                    unit: row["unit"] as? String ?? "",
                    travelerNames: row["travelerNames"] as? [String] ?? [],
                    required: (row["requiredQuantity"] as? NSNumber)?.doubleValue ?? 0,
                    available: (row["availableQuantity"] as? NSNumber)?.doubleValue ?? 0,
                    shortage: (row["shortageQuantity"] as? NSNumber)?.doubleValue ?? 0,
                    sufficient: row["sufficient"] as? Bool ?? false
                )
            }
            let shortages = self.orderStockRows.filter { !$0.sufficient }.count
            self.orderStatus = shortages == 0 ? "材料和五金库存查询完成" : "材料和五金库存查询完成，存在库存不足"
            self.finishOrderStep(
                shortages == 0
                    ? "当前订单的板材、封边和五金库存全部充足"
                    : "\(shortages) 项库存不足，请查看下方比对结果",
                shortages == 0 ? "success" : "warning"
            )
        }
    }

    func calculateSelectedOrderCost(export: Bool = false) {
        let orderID = selectedOrderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !orderID.isEmpty else { return }
        logUserAction(export ? "导出订单成本" : "计算订单成本", details: ["order_id_present": true])
        orderCostStatus = export ? "正在生成成本 Excel…" : "正在读取数据库成本…"
        addOrderStep(export ? "导出成本 Excel" : "计算成本", "按数据库材料、五金和 cost_price 计算", "running")
        runOrder([
            export ? "cost-export" : "cost", "--order-id", orderID
        ], failureStatus: "成本计算失败") { object in
            self.applyOrderCost(object)
            if export {
                self.orderCostExportPath = object["export_path"] as? String ?? ""
                self.orderCostStatus = self.orderCostExportPath.isEmpty
                    ? "成本已计算，但没有返回 Excel 路径"
                    : "成本 Excel 已导出"
                self.finishOrderStep(self.orderCostStatus, self.orderCostExportPath.isEmpty ? "warning" : "success")
                if !self.orderCostExportPath.isEmpty {
                    NSWorkspace.shared.open(URL(fileURLWithPath: self.orderCostExportPath))
                }
            } else {
                self.orderCostStatus = "成本计算完成"
                self.finishOrderStep(
                    self.orderCostMissingItems.isEmpty ? "订单成本计算完成" : "成本计算完成，但存在待补充项目",
                    self.orderCostMissingItems.isEmpty ? "success" : "warning"
                )
                self.showCostSheet = true
            }
        }
    }

    private func applyOrderCost(_ object: [String: Any]) {
        orderCostTotal = (object["total_cost"] as? NSNumber)?.doubleValue
        orderCostKnown = (object["known_cost"] as? NSNumber)?.doubleValue ?? 0
        orderCostMissingItems = (object["missing_items"] as? [[String: Any]] ?? []).map { row in
            let name = row["name"] as? String ?? "未命名项目"
            let quantity = (row["quantity"] as? NSNumber)?.doubleValue ?? 0
            let unit = row["unit"] as? String ?? ""
            let missing = row["missing"] as? String ?? "成本资料缺失"
            return "\(name) \(quantity.formatted())\(unit)：\(missing)"
        }
        orderCostLines = (object["factory_lines"] as? [[String: Any]] ?? []).map { row in
            OrderCostLine(
                category: row["category"] as? String ?? "",
                factoryOrder: row["factory_order"] as? String ?? "",
                roomName: row["room_name"] as? String ?? "",
                name: row["name"] as? String ?? "",
                spec: row["spec"] as? String ?? "",
                quantity: (row["quantity"] as? NSNumber)?.doubleValue ?? 0,
                unit: row["unit"] as? String ?? "",
                productCode: row["product_code"] as? String ?? "",
                costPrice: (row["cost_price"] as? NSNumber)?.doubleValue,
                amount: (row["amount"] as? NSNumber)?.doubleValue,
                missing: row["missing"] as? String ?? ""
            )
        }
        orderCostFactoryTotals = (object["factory_totals"] as? [[String: Any]] ?? []).map { row in
            let factory = row["factory_order"] as? String ?? "材料汇总"
            return OrderCostFactoryTotal(
                id: factory,
                factoryOrder: factory,
                total: (row["total"] as? NSNumber)?.doubleValue ?? 0,
                hasMissing: row["has_missing"] as? Bool ?? false
            )
        }
    }

    func openSelectedOrderTraveler() {
        logUserAction("打开已生成 Traveler")
        guard !orderExistingTravelerPath.isEmpty else {
            addOrderStep("无法查看 Traveler", "当前订单尚未生成 Traveler", "failure")
            return
        }
        let url = URL(fileURLWithPath: orderExistingTravelerPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            addOrderStep("无法查看 Traveler", "文件不存在：\(url.path)", "failure")
            return
        }
        if NSWorkspace.shared.open(url) {
            addOrderStep("查看 Traveler", url.lastPathComponent, "success")
        } else {
            addOrderStep("无法查看 Traveler", "系统未能打开：\(url.path)", "failure")
        }
    }

    func openDashboardLocation(_ path: String) {
        logUserAction("点击打开所在文件夹")
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory)
        let url = URL(fileURLWithPath: trimmed)
        let folderURL = exists && isDirectory.boolValue ? url : url.deletingLastPathComponent()
        if !NSWorkspace.shared.open(folderURL) {
            orderError = "无法打开文件夹：(folderURL.path)"
        }
    }

    var projectRoot: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("project")
        if let bundled = bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

}

enum AppLayout {
    static let headerHeight: CGFloat = 64
    static let topNavHeight: CGFloat = headerHeight
    static let topPageTitleFontSize: CGFloat = 19
    static let headerActionSize: CGFloat = 44
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 250
    static let sidebarMaxWidth: CGFloat = 280
    static let contentMinWidth: CGFloat = 500
    static let contentPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12
    static let controlHeight: CGFloat = 44
    static let actionButtonWidth: CGFloat = 96
    static let inventoryActionMinWidth: CGFloat = 132
    static let actionSpacing: CGFloat = 10
    static let cardCornerRadius: CGFloat = 10
    static let statusHeight: CGFloat = 44
    static let operationRowHeight: CGFloat = 56
    static let operationVisibleRows = 3
    static let operationListHeight: CGFloat = operationRowHeight * CGFloat(operationVisibleRows)
    static let operationLogHeight: CGFloat = 196
    static let inventoryPreviewMinHeight: CGFloat = 320
    static let todoDeadlineColumnWidth: CGFloat = 270
    static let todoListMaxHeight: CGFloat = 340
    static let todoInputMinHeight: CGFloat = 92
    static let todoTableHeaderFontSize: CGFloat = 17
    static let todoTableBodyFontSize: CGFloat = 16
    static let materialNameFontSize: CGFloat = 18
    // Match the current production workspace size; keep a safe minimum so the
    // leading icon, navigation, and action controls never get clipped.
    static let windowMinWidth: CGFloat = 1180
    static let windowMinHeight: CGFloat = 760
    static let windowIdealWidth: CGFloat = 1760
    static let windowIdealHeight: CGFloat = 1360
    static let inventoryOrderContextWidth: CGFloat = 735
}

func inventoryActionColumnCount(availableWidth: CGFloat) -> Int {
    max(1, Int((availableWidth + AppLayout.actionSpacing) /
        (AppLayout.inventoryActionMinWidth + AppLayout.actionSpacing)))
}

enum AppPalette {
    static let interfaceColorScheme: ColorScheme = .light
    static let accent = Color(red: 0.23, green: 0.43, blue: 0.91)
    static let cyan = Color(red: 0.10, green: 0.55, blue: 0.65)
    static let background = Color(red: 0.972, green: 0.965, blue: 0.945)
    static let surface = Color.white
    static let subtleSurface = Color(red: 0.956, green: 0.960, blue: 0.968)
    static let separator = Color(red: 0.885, green: 0.895, blue: 0.915)
    static let success = Color(red: 0.18, green: 0.56, blue: 0.39)
    static let warning = Color(red: 0.76, green: 0.47, blue: 0.08)
    static let danger = Color(red: 0.76, green: 0.27, blue: 0.27)
    static let ignored = Color.gray
}

func inventoryCatalogUpdateSuccessStatus(_ count: Int) -> String {
    "✅ 商品资料更新成功，共 \(count) 个商品"
}

func inventoryCatalogUpdateSuccessStatus(
    _ count: Int,
    added: Int,
    updated: Int,
    removed: Int
) -> String {
    "✅ 商品资料更新成功，共 \(count) 个商品（新增 \(added)，更新 \(updated)，删除 \(removed)）"
}

func inventoryCatalogUpdateFailureStatus(_ reason: String) -> String {
    "❌ 商品资料更新失败：\(reason)"
}

enum SettingsStatusKind: Equatable {
    case neutral
    case info
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .info: return AppPalette.accent
        case .success: return AppPalette.success
        case .warning: return AppPalette.warning
        case .danger: return AppPalette.danger
        }
    }

    var symbol: String {
        switch self {
        case .neutral: return "info.circle"
        case .info: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.circle.fill"
        }
    }
}

func settingsStatusKind(_ status: String) -> SettingsStatusKind {
    let text = status.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("✅") { return .success }
    if text.hasPrefix("❌") { return .danger }
    if text.hasPrefix("⚠️") || text.localizedCaseInsensitiveContains("警告") { return .warning }
    if text.localizedCaseInsensitiveContains("正在") || text.hasSuffix("…") { return .info }
    return .neutral
}

func settingsStatusDisplayText(_ status: String) -> String {
    status
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "^(✅|❌|⚠️|ℹ️)\\s*", with: "", options: .regularExpression)
}

struct SettingsStatusBanner: View {
    let status: String

    var body: some View {
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let kind = settingsStatusKind(status)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: kind.symbol)
                    .foregroundColor(kind.color)
                    .frame(width: 18)
                Text(settingsStatusDisplayText(status))
                    .font(.callout)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(kind.color.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(kind.color.opacity(0.24), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(settingsStatusDisplayText(status))
        }
    }
}

extension View {
    func appPageFrame() -> some View {
        frame(minHeight: AppLayout.windowMinHeight - AppLayout.topNavHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppPalette.background)
    }

    func appInputField(maxWidth: CGFloat? = nil) -> some View {
        frame(maxWidth: maxWidth, minHeight: AppLayout.controlHeight, maxHeight: AppLayout.controlHeight)
    }

    func appActionButton(minWidth: CGFloat = AppLayout.actionButtonWidth) -> some View {
        controlSize(.regular)
            .frame(minWidth: minWidth, minHeight: AppLayout.controlHeight)
    }

    func inventoryActionButton(minWidth: CGFloat = AppLayout.inventoryActionMinWidth) -> some View {
        controlSize(.regular)
            .frame(
                minWidth: minWidth,
                maxWidth: .infinity,
                minHeight: AppLayout.controlHeight,
                maxHeight: AppLayout.controlHeight
            )
    }
}

struct AppSurfaceCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            )
    }
}

struct AppStatusBadge: View {
    enum Kind { case neutral, info, success, warning, danger }

    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .neutral: return .secondary
        case .info: return AppPalette.accent
        case .success: return AppPalette.success
        case .warning: return AppPalette.warning
        case .danger: return AppPalette.danger
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .frame(minHeight: 26)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .accessibilityLabel(text)
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ScrollingTextOnHover: View {
    let text: String
    var font: Font = .body
    var foreground: Color = .primary

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isHovering = false
    @State private var scrollTask: Task<Void, Never>?

    private var overflow: CGFloat {
        max(0, textWidth - containerWidth)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(foreground)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textProxy in
                            Color.clear.preference(key: WidthPreferenceKey.self, value: textProxy.size.width)
                        }
                    )
                    .offset(x: offset)
            }
                // GeometryReader can receive a narrow proposal inside an HStack. Make that
                // proposal the explicit clipping boundary so a long filename never paints
                // over the status column or the adjacent split-view pane.
                .frame(width: max(0, proxy.size.width), height: proxy.size.height, alignment: .leading)
                .clipped()
                .onPreferenceChange(WidthPreferenceKey.self) { textWidth = $0 }
                .onAppear { containerWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in containerWidth = width }
                .onHover { hover in
                    isHovering = hover
                    if hover {
                        startScrolling()
                    } else {
                        stopScrolling()
                    }
                }
        }
        .frame(height: 20)
    }

    private func startScrolling() {
        scrollTask?.cancel()
        offset = 0
        guard overflow > 4 else { return }
        scrollTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            while !Task.isCancelled && isHovering {
                let duration = max(1.2, Double(overflow) / 36)
                await MainActor.run {
                    withAnimation(.linear(duration: duration)) {
                        offset = -overflow
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.45) * 1_000_000_000))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }

    private func stopScrolling() {
        scrollTask?.cancel()
        scrollTask = nil
        withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
    }
}

struct InventoryActionGrid<Content: View>: View {
    let minColumnWidth: CGFloat
    @ViewBuilder let content: Content

    init(
        minColumnWidth: CGFloat = AppLayout.inventoryActionMinWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.minColumnWidth = minColumnWidth
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppLayout.actionSpacing) {
            Spacer(minLength: 0)
            content.frame(minWidth: minColumnWidth)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct AppPageHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Color.clear.frame(height: 0)
    }
}

struct OperationLogCard: View {
    let steps: [InventoryStep]
    let emptyText: String
    let showsDuration: Bool

    init(steps: [InventoryStep], emptyText: String, showsDuration: Bool = false) {
        self.steps = steps
        self.emptyText = emptyText
        self.showsDuration = showsDuration
    }

    var body: some View {
        GroupBox {
            SelectableOperationLogView(steps: steps, emptyText: emptyText, showsDuration: showsDuration)
                .padding(6)
        }
        .frame(maxWidth: .infinity)
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
                subtitle: "选择订单、预检材料并生成或更新 Traveler"
            ) {
                AppStatusBadge(
                    text: "服务器",
                    kind: .success
                )
                if model.orderRunning { ProgressView().controlSize(.small) }
            }
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("服务器订单").font(.headline)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("订单类型", selection: $model.orderSourceKind) {
                            Text("自有订单").tag("owned")
                            Text("来料加工").tag("cutToSize")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                        .disabled(model.orderRunning)
                        .onChange(of: model.orderSourceKind) { _, _ in
                            model.loadOrderFolders()
                        }
                        Spacer(minLength: 0)
                    }
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
                                            Text(appDisplayTimestamp(item.modifiedAt)).font(.caption2).foregroundColor(.secondary)
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
                            .fill(model.orderError.isEmpty ? (model.orderPreviewReady ? AppPalette.success : Color.secondary) : AppPalette.danger)
                            .frame(width: 10, height: 10)
                        Text(model.orderStatus)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        HStack(spacing: 6) {
                            Button("查询材料库存") {
                                model.checkSelectedOrderStock()
                            }
                            .buttonStyle(.bordered)
                            .appActionButton(minWidth: 128)
                            .disabled(model.orderRunning || !model.orderPreviewReady)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: AppLayout.statusHeight)

                    OperationLogCard(
                        steps: model.orderSteps,
                        emptyText: "选择订单后，这里会显示读取、校验和生成过程。",
                        showsDuration: true
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !model.selectedOrderId.isEmpty {
                                GroupBox(label: centeredTitle("订单基本信息", systemImage: "doc.text")) {
                                    VStack(alignment: .leading, spacing: 14) {
                                        HStack(spacing: 12) {
                                            let relatedOrderIDs = model.selectedOrderId.split(separator: "、")
                                            let hasRelatedOrders = relatedOrderIDs.count > 1
                                            summaryCard(
                                                title: hasRelatedOrders ? "关联订单（\(relatedOrderIDs.count) 个）" : "订单号",
                                                value: model.selectedOrderId,
                                                detail: URL(fileURLWithPath: model.orderMaterialsFile).lastPathComponent,
                                                color: hasRelatedOrders ? AppPalette.warning : AppPalette.accent,
                                                warning: hasRelatedOrders
                                            )
                                            summaryCard(
                                                title: "工厂单",
                                                value: "\(model.orderFactories.count)",
                                                detail: "已识别并校验",
                                                color: AppPalette.accent
                                            )
                                            summaryCard(
                                                title: "材料项目",
                                                value: "\(model.orderMaterials.count + model.orderEdgeBanding.count)",
                                                detail: "板材与封边",
                                                color: AppPalette.accent
                                            )
                                            summaryCard(
                                                title: "本机 Traveler",
                                                value: model.orderExistingTravelerPath.isEmpty ? "未生成" : "已存在",
                                                detail: model.orderExistingTravelerPath.isEmpty
                                                    ? "生成后保存在订单目录"
                                                    : URL(fileURLWithPath: model.orderExistingTravelerPath).lastPathComponent,
                                                color: model.orderExistingTravelerPath.isEmpty ? .secondary : AppPalette.accent
                                            )
                                        }

                                        if !model.orderFactories.isEmpty {
                                            subsectionTitle("工厂单号与名称", color: AppPalette.accent)
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
                                                    .background(AppPalette.accent.opacity(0.06))
                                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                                }
                                            }
                                        }

                                        if !model.orderMaterials.isEmpty {
                                            let warningColors = panelColorsNeedingThicknessWarning(model.orderMaterials)
                                            subsectionTitle("板材用量", color: AppPalette.accent)
                                            LazyVGrid(
                                                columns: [GridItem(.adaptive(minimum: 175, maximum: 240), spacing: 9)],
                                                alignment: .leading,
                                                spacing: 9
                                            ) {
                                                ForEach(orderedMaterialRows(model.orderMaterials)) { row in
                                                    let isColoredPanel = row.kind == "panel"
                                                    let normalizedColor = row.color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                                    let warnsAboutThickness = isColoredPanel && warningColors.contains(normalizedColor)
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        HStack(spacing: 6) {
                                                            Image(systemName: isColoredPanel ? "rectangle.stack.fill" : "square.stack.3d.up.fill")
                                                                .foregroundColor(AppPalette.accent)
                                                            Text(orderMaterialDisplayName(row))
                                                            .font(.system(size: AppLayout.materialNameFontSize))
                                                            .fontWeight(isColoredPanel ? .bold : .semibold)
                                                            .foregroundColor(.primary)
                                                            .lineLimit(2)
                                                        }
                                                        HStack(alignment: .firstTextBaseline) {
                                                            Text("规格 \(row.thickness.formatted())mm")
                                                                .font(.caption)
                                                                .fontWeight(.medium)
                                                                .foregroundColor(warnsAboutThickness ? AppPalette.danger : .secondary)
                                                            Spacer()
                                                            Text("\(row.quantity.formatted()) 张")
                                                                .font(.title3).fontWeight(.bold)
                                                                .foregroundColor(AppPalette.accent)
                                                        }
                                                    }
                                                    .padding(11)
                                                    .background(AppPalette.accent.opacity(isColoredPanel ? 0.12 : 0.06))
                                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 9)
                                                            .stroke(
                                                                AppPalette.accent.opacity(isColoredPanel ? 0.36 : 0.16),
                                                                lineWidth: isColoredPanel ? 1.5 : 1
                                                            )
                                                    )
                                                }
                                            }
                                        }

                                        if !model.orderEdgeBanding.isEmpty {
                                            subsectionTitle("封边用量", color: AppPalette.accent)
                                            LazyVGrid(
                                                columns: [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 9)],
                                                alignment: .leading,
                                                spacing: 9
                                            ) {
                                                ForEach(orderedEdgeColors(Array(model.orderEdgeBanding.keys), matching: orderedMaterialRows(model.orderMaterials)), id: \.self) { color in
                                                    HStack {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(color)
                                                                .font(.system(size: AppLayout.materialNameFontSize, weight: .semibold))
                                                                .lineLimit(1)
                                                            Text("Edge Banding").font(.caption2).foregroundColor(.secondary)
                                                        }
                                                        Spacer()
                                                        Text("\((model.orderEdgeBanding[color] ?? 0).formatted())m")
                                                            .font(.title3).fontWeight(.bold).foregroundColor(AppPalette.accent)
                                                    }
                                                    .padding(10)
                                                    .background(AppPalette.accent.opacity(0.06))
                                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 9)
                                                            .stroke(AppPalette.accent.opacity(0.16), lineWidth: 1)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                }
                            }

                            if !model.orderStockRows.isEmpty {
                                GroupBox(label: centeredTitle("所需材料与实时库存", systemImage: "shippingbox.and.arrow.backward")) {
                                    VStack(spacing: 0) {
                                        HStack(spacing: 10) {
                                            Text("商品").frame(maxWidth: .infinity, alignment: .leading)
                                            Text("编号").frame(width: 86, alignment: .leading)
                                            Text("单位").frame(width: 50, alignment: .center)
                                            Text("所需").frame(width: 72, alignment: .trailing)
                                            Text("库存").frame(width: 72, alignment: .trailing)
                                            Text("结果").frame(width: 90, alignment: .trailing)
                                        }
                                        .font(.caption).foregroundColor(.secondary)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        Divider()
                                        ForEach(model.orderStockRows) { row in
                                            HStack(spacing: 10) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(row.productName).fontWeight(.medium).lineLimit(1)
                                                    Text(row.travelerNames.joined(separator: "、"))
                                                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                Text(row.productCode).frame(width: 86, alignment: .leading)
                                                Text(row.unit.isEmpty ? "—" : row.unit).frame(width: 50, alignment: .center)
                                                Text(row.required.formatted()).frame(width: 72, alignment: .trailing)
                                                Text(row.available.formatted()).frame(width: 72, alignment: .trailing)
                                                Text(row.sufficient ? "充足" : "缺 \(row.shortage.formatted())")
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(row.sufficient ? AppPalette.success : AppPalette.warning)
                                                    .frame(width: 90, alignment: .trailing)
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 8)
                                            Divider()
                                        }
                                    }
                                    .padding(8)
                                }
                            }

                            if !model.orderFittings.isEmpty {
                                GroupBox(label: centeredTitle("各工厂单五金预览", systemImage: "wrench.and.screwdriver")) {
                                    VStack(spacing: 12) {
                                        ForEach(model.orderFactories) { factory in
                                            let rows = model.orderFittings.filter { $0.factoryOrder == factory.factoryOrder }
                                            VStack(spacing: 0) {
                                                HStack {
                                                    Text("\(factory.factoryOrder) · \(factory.orderName)")
                                                        .fontWeight(.semibold)
                                                        .lineLimit(1)
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
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .appPageFrame()
        .onAppear {
            if model.orderFolders.isEmpty { model.loadOrderFolders() }
        }
        .onChange(of: model.selectedOrderPath) { _, _ in
            selectedFittingIDs.removeAll()
        }
        .alert("未找到 material 文件", isPresented: $model.showMaterialGenerationPrompt) {
            Button("自动生成") {
                model.generateMissingMaterial()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前订单没有 material 文件。是否从 Report 文件夹的板材清单和封边统计自动生成？如果目录结构过于复杂无法读取，系统会提示你手动生成。")
        }
    }

    private func summaryCard(title: String, value: String, detail: String, color: Color, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 5) {
                if warning { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(color) }
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .lineLimit(2)
                    .frame(height: 44, alignment: .top)
            }
            Text(detail.isEmpty ? "—" : detail)
                .font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .leading)
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

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundColor(.primary)
            Divider()
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        )
    }
}

struct InventoryStepRowView: View {
    let step: InventoryStep
    let showsDuration: Bool

    init(step: InventoryStep, showsDuration: Bool = false) {
        self.step = step
        self.showsDuration = showsDuration
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            icon.frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.title).fontWeight(.medium)
                    Spacer()
                    Text(step.time).font(.caption2).foregroundColor(.secondary)
                }
                Text(detailText)
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
                    "[\(step.time)] \(step.title)\n\(detailText)",
                    forType: .string
                )
            }
        }
    }

    private var detailText: String {
        guard showsDuration else { return step.detail }
        let elapsed = step.duration ?? step.startedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        return "\(step.detail)（用时 \(operationDurationText(elapsed))）"
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case "success":
            Image(systemName: "checkmark.circle.fill").foregroundColor(AppPalette.success)
        case "failure":
            Image(systemName: "xmark.circle.fill").foregroundColor(AppPalette.danger)
        case "warning":
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(AppPalette.warning)
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

struct OperationLogAutoScroller: NSViewRepresentable {
    let revision: String

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = revision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let scrollView = nsView.enclosingScrollView,
                  let documentView = scrollView.documentView else { return }
            documentView.layoutSubtreeIfNeeded()
            let clipView = scrollView.contentView
            let targetY = documentView.isFlipped
                ? max(documentView.bounds.minY, documentView.bounds.maxY - clipView.bounds.height)
                : documentView.bounds.minY
            clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

struct SelectableOperationLogView: View {
    let steps: [InventoryStep]
    let emptyText: String
    let showsDuration: Bool
    @State private var selectedIDs: Set<UUID> = []

    init(steps: [InventoryStep], emptyText: String, showsDuration: Bool = false) {
        self.steps = steps
        self.emptyText = emptyText
        self.showsDuration = showsDuration
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
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
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(steps) { step in
                            Button {
                                select(step.id)
                            } label: {
                                InventoryStepRowView(step: step, showsDuration: showsDuration)
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
                        }
                        OperationLogAutoScroller(revision: scrollRevision)
                            .frame(height: 1)
                    }
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
        .onChange(of: steps.map(\.id)) { _, ids in
            selectedIDs = selectedIDs.intersection(Set(ids))
        }
    }

    private var scrollRevision: String {
        steps.map { "\($0.id.uuidString)|\($0.state)|\($0.title)|\($0.detail)|\($0.duration ?? -1)" }
            .joined(separator: "\n")
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
            .map { step in
                let detail: String
                if showsDuration {
                    let elapsed = step.duration ?? step.startedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
                    detail = "\(step.detail)（用时 \(operationDurationText(elapsed))）"
                } else {
                    detail = step.detail
                }
                return "[\(step.time)] \(step.title)\n\(detail)"
            }
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
                    ScrollingTextOnHover(text: item.fileName)
                    if !item.orderName.isEmpty {
                        ScrollingTextOnHover(text: item.orderName, font: .caption, foreground: .secondary)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 22, alignment: .center)
                Spacer(minLength: 4)
                Text(item.status)
                    .font(.caption)
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
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
                    .appInputField()
                    .onSubmit { model.searchInventoryProducts(query) }
                Button("搜索") { model.searchInventoryProducts(query) }
                    .buttonStyle(.borderedProminent)
                    .appActionButton(minWidth: 72)
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

struct PendingInventoryMappingTarget: Identifiable {
    let name: String
    var id: String { name }
}

struct PendingInventoryMappingWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var mappingTarget: PendingInventoryMappingTarget?
    @State private var ignoreTarget: PendingInventoryMappingTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("处理订单文件映射")
                        .font(.title2.weight(.semibold))
                    Text("缺失材料可以设置库存商品映射，也可以加入全局忽略清单。保存后系统会重新读取原订单文件。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                AppStatusBadge(text: "\(model.inventoryMappingTargetNames.count) 项", kind: .warning)
            }

            if !model.inventoryMappingRequestPath.isEmpty {
                Text(model.inventoryMappingRequestPath)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if model.inventoryMappingTargetNames.isEmpty {
                ContentUnavailableView(
                    "没有读取到材料名称",
                    systemImage: "questionmark.folder",
                    description: Text("请关闭窗口后重新扫描；也可以到设置中手工维护材料映射。")
                )
            } else {
                AppSurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(model.inventoryMappingTargetNames, id: \.self) { name in
                            HStack(spacing: 10) {
                                Text(name)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("处理映射") {
                                    mappingTarget = PendingInventoryMappingTarget(name: name)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.inventoryRunning)
                                Button("忽略") {
                                    ignoreTarget = PendingInventoryMappingTarget(name: name)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.inventoryRunning)
                            }
                            .padding(12)
                            if name != model.inventoryMappingTargetNames.last {
                                Divider()
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("关闭") { model.closeInventoryMappingWorkspace() }
                    .appActionButton(minWidth: 80)
            }
        }
        .padding(20)
        .background(AppPalette.background)
        .sheet(item: $mappingTarget) { target in
            InventoryMappingSheet(
                model: model,
                travelerName: target.name,
                isPresented: Binding(
                    get: { mappingTarget != nil },
                    set: { if !$0 { mappingTarget = nil } }
                )
            )
        }
        .sheet(item: $ignoreTarget) { target in
            PendingInventoryIgnoreSheet(
                model: model,
                travelerName: target.name
            )
        }
    }
}

struct PendingInventoryIgnoreSheet: View {
    @ObservedObject var model: AppModel
    let travelerName: String
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "用户在待处理中心选择全局忽略"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("忽略未映射材料")
                        .font(.title2.weight(.semibold))
                    Text("加入全局忽略后，所有订单都不会再要求处理“\(travelerName)”。")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .appActionButton(minWidth: 72)
            }

            AppSurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("材料名称").font(.caption).foregroundColor(.secondary)
                    Text(travelerName).font(.headline)
                    Text("忽略原因").font(.caption).foregroundColor(.secondary)
                    TextField("请输入忽略原因", text: $reason)
                        .textFieldStyle(.roundedBorder)
                        .appInputField()
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .appActionButton(minWidth: 80)
                Button("加入全局忽略") {
                    model.saveInventoryIgnoredMapping(name: travelerName, reason: reason)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.inventoryRunning || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(AppPalette.background)
    }
}

struct InventoryView: View {
    @ObservedObject var model: AppModel
    let onClose: (() -> Void)?
    let orderContextID: String
    let orderContextFactoryNames: [String]
    let orderContextFactoryOrders: [String]
    @State private var confirmRealSave = false
    @State private var acknowledgedRealSave = false
    @State private var showInventoryMappingSheet = false
    @State private var mappingTravelerName = ""

    init(
        model: AppModel,
        onClose: (() -> Void)? = nil,
        orderContextID: String = "",
        orderContextFactoryNames: [String] = [],
        orderContextFactoryOrders: [String] = []
    ) {
        self.model = model
        self.onClose = onClose
        self.orderContextID = orderContextID
        self.orderContextFactoryNames = orderContextFactoryNames
        self.orderContextFactoryOrders = orderContextFactoryOrders
    }

    private var selectedTravelerCount: Int {
        model.selectedInventoryOrderID.isEmpty ? 0 : 1
    }

    private var hasMappedOutboundRows: Bool {
        model.inventoryPreviewRows.contains { $0.status == "已映射" }
    }

    private var hasConfirmedNoOutboundRows: Bool {
        model.inventoryPreviewRows.contains {
            ["客户提供", "余料生产", "不需要出库", "不出库"].contains($0.status)
        }
    }

    private var customerSuppliedOnly: Bool {
        let statuses = Set(model.inventoryPreviewRows.map(\.status))
        return statuses.contains("客户提供")
            && !statuses.contains("已映射")
            && !statuses.contains("未映射")
    }

    private var confirmationTitle: String {
        if model.inventoryWriteBlocked { return "重试出库" }
        return customerSuppliedOnly || hasMappedOutboundRows ? "确认出库" : "确认无需出库"
    }

    private var selectedTravelerDisplayName: String {
        orderContextID.isEmpty ? "当前订单" : orderContextID
    }

    @ViewBuilder
    private func previewRowContent(_ row: InventoryPreviewRow) -> some View {
        HStack(spacing: 8) {
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
            .frame(width: 250, alignment: .leading)
            Text(row.quantity.formatted())
                .frame(width: 58, alignment: .trailing)
            if row.status == "未映射" {
                Button("处理映射") {
                    mappingTravelerName = row.travelerName
                    showInventoryMappingSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.inventoryRunning)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(row.status == "未映射" ? AppPalette.warning.opacity(0.16) :
                    row.status == "已忽略" ? Color.gray.opacity(0.10) : Color.clear)
    }

    var body: some View {
        VStack(spacing: 0) {
                AppPageHeader(
                    systemImage: "shippingbox.fill",
                    title: "订单出库",
                    subtitle: "订单 \(model.selectedOrderId)"
            ) {
                AppStatusBadge(
                    text: model.inventoryWriteCompleted
                        ? "已出库"
                        : (model.inventoryWriteBlocked
                            ? "出库失败，可重试"
                            : (model.inventoryErrors.isEmpty ? "库存工作台就绪" : "需要处理错误")),
                    kind: model.inventoryWriteCompleted
                        ? .success
                        : (model.inventoryWriteBlocked || !model.inventoryErrors.isEmpty ? .danger : .success)
                )
                if model.inventoryRunning { ProgressView().controlSize(.small) }
            }
            Divider()
            HStack(spacing: 10) {
                outboundStep(1, "选择工厂单", active: selectedTravelerCount == 0)
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                outboundStep(2, "数据预检", active: selectedTravelerCount > 0 && !model.inventoryPreviewRows.isEmpty && !model.inventoryWriteCompleted)
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                outboundStep(3, "确认出库", active: confirmRealSave || model.inventoryWriteCompleted || model.inventoryWriteBlocked)
                Spacer()
                if model.inventoryPreviewRows.contains(where: { $0.status == "未映射" }) {
                    AppStatusBadge(text: "映射阻断", kind: .danger)
                } else if !model.inventoryPreviewRows.isEmpty {
                    AppStatusBadge(text: "预检完成", kind: .success)
                }
                if let onClose {
                    Button("关闭", systemImage: "xmark") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .appActionButton(minWidth: 84)
                    .disabled(model.inventoryRunning)
                    .help(model.inventoryRunning ? "库存操作进行中，暂不能关闭" : "关闭出库界面")
                }
            }
            .padding(.horizontal, AppLayout.contentPadding)
            .frame(height: 54)
            .background(AppPalette.surface)
            .overlay(Divider(), alignment: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    OperationLogCard(
                        steps: model.inventorySteps,
                        emptyText: "正在读取订单选择并执行材料、商品映射校验。"
                    )

                    GroupBox(label: centeredTitle(
                        "本次出库预览",
                        systemImage: "tablecells"
                    )) {
                        VStack(alignment: .leading, spacing: 10) {
                        if model.inventoryPreviewRows.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 36)).foregroundColor(.secondary)
                                Text("正在载入本次出库选择")
                                Text("数量为 0 的项目不显示；未映射问题请返回订单文件读取阶段处理。")
                                    .font(.caption).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            HStack {
                                Text("订单材料").frame(maxWidth: .infinity, alignment: .leading)
                                Text("状态").frame(width: 58, alignment: .leading)
                                Text("商品编号").frame(width: 82, alignment: .leading)
                                Text("本地映射商品／说明").frame(width: 250, alignment: .leading)
                                Text("数量").frame(width: 58, alignment: .trailing)
                            }.font(.caption).foregroundColor(.secondary)
                            Divider()
                            ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                    ForEach(model.inventoryPreviewRows) { row in
                                        previewRowContent(row)
                                        .overlay(Divider(), alignment: .bottom)
                                    }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            }
                            .scrollIndicators(.automatic)
                            .frame(minHeight: 0,
                                   maxHeight: .infinity,
                                   alignment: .top)
                            .layoutPriority(1)
                        }
                        InventoryActionGrid(minColumnWidth: 156) {
                            Button(confirmationTitle) { confirmRealSave = true }
                                .buttonStyle(.borderedProminent)
                                .inventoryActionButton(minWidth: 156)
                                .disabled(model.inventoryRunning || selectedTravelerCount != 1 ||
                                          (!hasMappedOutboundRows && !hasConfirmedNoOutboundRows) ||
                                          !model.inventoryErrors.isEmpty ||
                                          model.inventoryWriteCompleted)
                        }
                        if model.inventoryPreviewRows.contains(where: { $0.status == "未映射" }) {
                            Label("未映射问题请返回订单文件读取阶段处理", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundColor(AppPalette.warning)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(AppLayout.contentPadding)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            minHeight: 0,
            alignment: .top
        )
        .onAppear {
            model.previewOrderInventory(
                orderID: orderContextID,
                factoryOrderNames: orderContextFactoryNames,
                factoryOrders: orderContextFactoryOrders
            )
        }
        .sheet(isPresented: $showInventoryMappingSheet) {
            InventoryMappingSheet(
                model: model,
                travelerName: mappingTravelerName,
                isPresented: $showInventoryMappingSheet
            )
        }
        .sheet(isPresented: $confirmRealSave, onDismiss: { acknowledgedRealSave = false }) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(confirmationTitle).font(.title2).fontWeight(.semibold)
                        Text(customerSuppliedOnly
                            ? "确认后只更新数据库中的出库状态，不创建库存系统出库单。"
                            : (hasMappedOutboundRows ? "保存后会影响库存，写入开始后不可取消。" : "本次只记录无需出库决定，不会打开库存系统。"))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    AppStatusBadge(text: "高风险操作", kind: .danger)
                }

                AppSurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(customerSuppliedOnly
                            ? "请再次核对客户材料范围"
                            : (hasMappedOutboundRows ? "请再次核对材料映射和库存警告" : "请再次核对无需出库原因"), systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundColor(AppPalette.warning)
                        Text(customerSuppliedOnly
                            ? "系统会将本次客户材料确认记录为“已出库”，但不会创建库存系统出库单。"
                            : (!hasMappedOutboundRows
                            ? "系统不会创建库存出库单，只会保存当前已确认的出库范围决定和原因。"
                            : "系统会按当前订单数据库事实和所选工厂单创建真实的“其他出库单”。库存不足允许继续，但相关警告会写入本机操作记录。"))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 0) {
                    confirmationRow("订单", selectedTravelerDisplayName)
                    Divider()
                    confirmationRow("材料行", "\(model.inventoryPreviewRows.count)")
                    Divider()
                    confirmationRow("操作性质", customerSuppliedOnly ? "数据库记录 · 显示已出库" : (hasMappedOutboundRows ? "真实写入 · 不可取消" : "保存范围决定 · 不写库存"), valueColor: hasMappedOutboundRows && !customerSuppliedOnly ? AppPalette.danger : AppPalette.accent)
                }
                .padding(.horizontal, 14)
                .background(AppPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppPalette.separator))

                Toggle(
                    customerSuppliedOnly ? "我已核对客户材料范围，并确认本次只更新数据库。" : "我已核对材料映射与库存警告，并理解写入开始后不可取消。",
                    isOn: $acknowledgedRealSave
                )
                .toggleStyle(.checkbox)

                HStack(spacing: 8) {
                    Button("取消") { confirmRealSave = false }
                        .appActionButton(minWidth: 80)
                    Button("确认出库") {
                        confirmRealSave = false
                        model.openAndFillSelectedInventory()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.danger)
                    .appActionButton(minWidth: 156)
                    .disabled(!acknowledgedRealSave)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(width: 560)
            .background(AppPalette.background)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "已出库": return AppPalette.success
        case "需要更新": return AppPalette.warning
        case "失败", "结果未知", "原单据不可编辑": return AppPalette.danger
        default: return .secondary
        }
    }

    private func outboundStep(_ number: Int, _ title: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundColor(active ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background(active ? AppPalette.accent : AppPalette.subtleSurface)
                .clipShape(Circle())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(active ? AppPalette.accent : .secondary)
        }
    }

    private func confirmationRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundColor(valueColor).lineLimit(1)
        }
        .frame(minHeight: 44)
    }

    private func previewStatusColor(_ status: String) -> Color {
        switch status {
        case "已映射": return AppPalette.success
        case "未映射": return AppPalette.warning
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
            Image(systemName: "checkmark.circle.fill").foregroundColor(AppPalette.success)
        case "failure":
            Image(systemName: "xmark.circle.fill").foregroundColor(AppPalette.danger)
        case "warning":
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(AppPalette.warning)
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
                title: "待办",
                subtitle: "按截止时间和阻断程度安排需要处理的工作"
            ) {
                AppStatusBadge(text: "\(openCount) 项未完成", kind: openCount > 0 ? .warning : .success)
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("截止时间")
                                .frame(width: AppLayout.todoDeadlineColumnWidth, alignment: .center)
                            Divider()
                            Text("任务内容")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .font(.system(size: AppLayout.todoTableHeaderFontSize, weight: .semibold))
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
                .frame(minHeight: 220, idealHeight: 300, maxHeight: AppLayout.todoListMaxHeight)

                HStack(spacing: 10) {
                    Button(selectedItem?.completedAt == nil ? "完成任务" : "恢复任务") {
                        if let selectedItem { model.toggleTodoCompletion(selectedItem) }
                    }
                    .buttonStyle(.borderedProminent)
                    .appActionButton()
                    .disabled(selectedItem == nil)

                    Button("编辑") {
                        editingItem = selectedItem
                    }
                    .appActionButton(minWidth: 72)
                    .disabled(selectedItem == nil)

                    Button("删除", role: .destructive) {
                        pendingDelete = selectedItem
                    }
                    .appActionButton(minWidth: 72)
                    .disabled(selectedItem == nil)

                    Spacer()
                    if let message = todoSelectionMessage {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }

                GroupBox(label: Label("添加待办", systemImage: "plus.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Text("任务内容")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("设置截止时间", isOn: $hasDeadline)
                                .toggleStyle(.checkbox)
                                .fixedSize()
                            DatePicker(
                                "截止时间",
                                selection: $newDeadline,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .frame(width: 190, height: AppLayout.controlHeight)
                            .disabled(!hasDeadline)
                            .opacity(hasDeadline ? 1 : 0.45)
                        }

                        TextEditor(text: $newContent)
                            .font(.body)
                            .padding(7)
                            .frame(minHeight: AppLayout.todoInputMinHeight, idealHeight: 100, maxHeight: 112)
                            .background(AppPalette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                            )

                        HStack {
                            Spacer()
                            Button {
                                addTodo()
                            } label: {
                                Label("添加待办事项", systemImage: "plus")
                            }
                            .appActionButton(minWidth: 132)
                            .buttonStyle(.borderedProminent)
                            .disabled(newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(12)
                }

                if !model.todoStatus.isEmpty {
                    Label(model.todoStatus, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(AppPalette.danger)
                }
            }
            .padding(AppLayout.contentPadding)
        }
        .appPageFrame()
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(deadlineColor(item))
                }
            }
            .padding(.horizontal, 14)
            .frame(width: AppLayout.todoDeadlineColumnWidth, alignment: .leading)

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
        .font(.system(size: AppLayout.todoTableBodyFontSize))
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
        if days < 0 { return AppPalette.danger }
        if days <= 1 { return AppPalette.warning }
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
                .appInputField()
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
                .appActionButton(minWidth: 72)
                Button("保存") {
                    model.updateTodo(item, content: content, deadline: hasDeadline ? deadline : nil)
                    if model.todoStatus.isEmpty { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .appActionButton()
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showOperationLog = false
    @State private var showIgnoredHardwareList = false
    @State private var showManualMappingList = false

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                systemImage: "gearshape",
                title: "设置",
                subtitle: "连接、数据来源与安全边界"
            ) {
                AppStatusBadge(
                    text: "生产数据源",
                    kind: .success
                )
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    HStack(alignment: .top, spacing: AppLayout.sectionSpacing) {
                        VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                            SettingsCard(title: "运行范围", symbol: "slider.horizontal.3") {
                                VStack(alignment: .leading, spacing: 10) {
                                    DatePicker("初始扫描日期", selection: $model.initialDate, displayedComponents: .date)
                                        .appInputField(maxWidth: 300)
                                    Text("程序只在你手工点击运行后执行。")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }

                            SettingsCard(title: "文件位置", symbol: "folder") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("服务器目录").font(.caption).foregroundColor(.secondary)
                                    TextField("服务器订单目录", text: $model.sourceRoot)
                                        .textFieldStyle(.roundedBorder).appInputField()
                                    Text("订单目录").font(.caption).foregroundColor(.secondary)
                                    TextField("Traveler 保存目录", text: $model.orderRoot)
                                        .textFieldStyle(.roundedBorder).appInputField()
                                    Text("Traveler 文件备份目录").font(.caption).foregroundColor(.secondary)
                                    TextField("Traveler 备份目录", text: $model.backupRoot)
                                        .textFieldStyle(.roundedBorder).appInputField()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        SettingsCard(title: "系统账户", symbol: "lock.shield") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("库存系统").font(.subheadline).fontWeight(.semibold)
                                        TextField("用户名", text: $model.jdyUsername)
                                            .textFieldStyle(.roundedBorder)
                                            .appInputField()
                                        SecureField("输入新密码", text: $model.jdyPassword)
                                            .textFieldStyle(.roundedBorder)
                                            .appInputField()
                                        Button("更新库存系统钥匙串密码") { model.saveJdyPassword() }
                                            .buttonStyle(.bordered)
                                            .appActionButton(minWidth: 0)
                                            .frame(maxWidth: .infinity)
                                            .disabled(model.jdyPassword.isEmpty)
                                        Button("打开库存专用 Chrome") { model.openInventoryChrome() }
                                            .buttonStyle(.bordered)
                                            .appActionButton(minWidth: 0)
                                            .frame(maxWidth: .infinity)
                                            .disabled(model.inventoryRunning)
                                        if model.inventoryChromeStatus.hasPrefix("❌") {
                                            Text(model.inventoryChromeStatus)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("AIMES").font(.subheadline).fontWeight(.semibold)
                                        TextField("用户名", text: $model.aimesUsername)
                                            .textFieldStyle(.roundedBorder).appInputField()
                                        SecureField("输入新密码", text: $model.aimesPassword)
                                            .textFieldStyle(.roundedBorder).appInputField()
                                        Button("保存 AIMES 密码") { model.saveAimesPassword() }
                                            .buttonStyle(.bordered)
                                            .appActionButton(minWidth: 0)
                                            .frame(maxWidth: .infinity)
                                            .disabled(model.aimesPassword.isEmpty)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                Button("管理 AIMES 待确认与忽略记录") {
                                    model.showPendingCenterPrompt = true
                                }
                                .buttonStyle(.bordered).appActionButton(minWidth: 176)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        SettingsCard(title: "库存商品资料与全局忽略", symbol: "shippingbox") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("从库存系统更新商品名称、SKU、规格、类别和单位等资料。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 8) {
                                    SettingsStatusBanner(status: model.inventoryCatalogStatus)
                                    HStack(spacing: 10) {
                                        Spacer(minLength: 0)
                                        if model.inventoryRunning {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Button("更新商品资料") {
                                            model.updateInventoryCatalog()
                                        }
                                        .buttonStyle(.bordered)
                                        .appActionButton(minWidth: 112)
                                        .disabled(model.inventoryRunning)
                                    }
                                }
                                Divider()
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("材料映射")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("将订单材料名称对应到商品资料中的启用 SKU。")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(model.inventoryManualMappings.count) 项")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button("查看") { showManualMappingList = true }
                                        .buttonStyle(.bordered)
                                        .appActionButton(minWidth: 72)
                                }
                                Divider()
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("五金全局忽略列表")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("列表中的名称或来源编码会对所有订单生效；命中后不写入有效数据库，也不参与出库。")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(model.inventoryIgnoredMappings.count) 项")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button("查看") { showIgnoredHardwareList = true }
                                        .buttonStyle(.bordered)
                                        .appActionButton(minWidth: 72)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    SettingsCard(title: "数据库备份", symbol: "externaldrive.badge.timemachine") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("本机数据库备份目录")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(model.databaseBackupRoot)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text("App 每天首次启动时，在本地订单缓存读取完成后自动备份；只保留最近三天每日备份，以及最近 30 天内每周一份。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 10) {
                                if !model.backupStatus.isEmpty {
                                    Text(model.backupStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Button("立即备份") { model.performBackup() }
                                    .buttonStyle(.bordered)
                                    .appActionButton(minWidth: 96)
                                    .disabled(model.orderRunning)
                            }
                        }
                    }

                    SettingsCard(title: "操作日志", symbol: "list.bullet.rectangle") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(
                                    "记录用户操作和后台执行步骤",
                                    isOn: Binding(
                                        get: { model.operationLogEnabled },
                                        set: { model.setOperationLogEnabled($0) }
                                    )
                                )
                                .toggleStyle(.checkbox)
                                Spacer(minLength: 0)
                                Button("查看") {
                                    model.logUserAction("查看操作日志")
                                    showOperationLog = true
                                }
                                .buttonStyle(.bordered)
                                .appActionButton(minWidth: 72)
                            }
                            Text("用于发生错误时按时间顺序回溯。不会记录密码、用户名、备注、语音原文或网页输入内容。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("文件：\(model.operationLogURL.path)")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            Divider()
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("日志文件大小")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(model.operationLogSizeText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button("清理至近三天") {
                                    model.trimOperationLog()
                                }
                                .buttonStyle(.bordered)
                                .appActionButton(minWidth: 112)
                                .disabled(model.orderRunning || model.inventoryRunning || model.assistantRunning)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        SettingsStatusBanner(status: model.settingsStatus)
                        Spacer(minLength: 0)
                        Button("保存全部配置") { model.saveAllSettings() }
                            .buttonStyle(.borderedProminent)
                            .appActionButton(minWidth: 132)
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(maxWidth: 1220)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .appPageFrame()
        .onAppear {
            model.refreshInventoryCatalogStatus()
            model.refreshInventoryMappings()
            model.refreshOperationLogInfo()
        }
        .sheet(isPresented: $showOperationLog) {
            OperationLogViewerView(url: model.operationLogURL)
        }
        .sheet(isPresented: $showIgnoredHardwareList) {
            InventoryIgnoredMappingsSheet(model: model)
        }
        .sheet(isPresented: $showManualMappingList) {
            InventoryManualMappingsSheet(model: model)
        }
    }

}

struct InventoryIgnoredMappingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var reason = ""
    @State private var editingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("五金全局忽略列表")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("统一管理所有订单生效的忽略项目")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .appActionButton(minWidth: 72)
            }
            Divider()
            HStack(spacing: 8) {
                TextField("五金名称或来源编码", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .appInputField()
                TextField("忽略原因", text: $reason)
                    .textFieldStyle(.roundedBorder)
                    .appInputField()
                Button(editingName.isEmpty ? "增加" : "保存修改") {
                    if editingName.isEmpty {
                        model.saveInventoryIgnoredMapping(name: name, reason: reason)
                    } else {
                        model.updateInventoryIgnoredMapping(oldName: editingName, name: name, reason: reason)
                    }
                    clearEditor()
                }
                .buttonStyle(.bordered)
                .appActionButton(minWidth: 76)
                .disabled(model.inventoryRunning || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !editingName.isEmpty {
                    Button("取消") { clearEditor() }
                        .appActionButton(minWidth: 56)
                }
            }
            if model.inventoryIgnoredMappings.isEmpty {
                ContentUnavailableView("当前没有全局忽略项目", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.inventoryIgnoredMappings) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).fontWeight(.medium)
                                    Text(item.reason.isEmpty ? "未填写原因" : item.reason)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button("修改") {
                                    editingName = item.name
                                    name = item.name
                                    reason = item.reason
                                }
                                .appActionButton(minWidth: 56)
                                .disabled(model.inventoryRunning)
                                Button("删除") { model.removeInventoryIgnoredMapping(name: item.name) }
                                    .appActionButton(minWidth: 56)
                                    .disabled(model.inventoryRunning)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 640, minHeight: 400)
        .onAppear { model.refreshInventoryMappings() }
    }

    private func clearEditor() {
        name = ""
        reason = ""
        editingName = ""
    }
}

struct InventoryManualMappingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var productCode = ""
    @State private var editingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("材料映射")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("统一管理订单材料名称与商品 SKU 的对应关系")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .appActionButton(minWidth: 72)
            }
            Divider()
            HStack(spacing: 8) {
                TextField("材料名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .appInputField()
                TextField("商品 SKU", text: $productCode)
                    .textFieldStyle(.roundedBorder)
                    .appInputField()
                Button(editingName.isEmpty ? "增加" : "保存修改") {
                    if editingName.isEmpty {
                        model.saveSettingsManualMapping(name: name, productCode: productCode)
                    } else {
                        model.updateSettingsManualMapping(
                            oldName: editingName,
                            name: name,
                            productCode: productCode
                        )
                    }
                    clearEditor()
                }
                .buttonStyle(.bordered)
                .appActionButton(minWidth: 76)
                .disabled(model.inventoryRunning || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          productCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !editingName.isEmpty {
                    Button("取消") { clearEditor() }
                        .appActionButton(minWidth: 56)
                }
            }
            if model.inventoryManualMappings.isEmpty {
                ContentUnavailableView("当前没有材料映射", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.inventoryManualMappings) { item in
                            HStack(spacing: 10) {
                                Text(item.name)
                                    .fontWeight(.medium)
                                Spacer(minLength: 0)
                                Text(item.productCode)
                                    .font(.body.monospaced())
                                    .foregroundColor(AppPalette.accent)
                                Button("修改") {
                                    editingName = item.name
                                    name = item.name
                                    productCode = item.productCode
                                }
                                .appActionButton(minWidth: 56)
                                .disabled(model.inventoryRunning)
                                Button("删除") { model.removeSettingsManualMapping(name: item.name) }
                                    .appActionButton(minWidth: 56)
                                    .disabled(model.inventoryRunning)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 440)
        .onAppear { model.refreshInventoryMappings() }
    }

    private func clearEditor() {
        name = ""
        productCode = ""
        editingName = ""
    }
}

struct OperationLogViewerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [OperationLogEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("操作日志").font(.title2).fontWeight(.semibold)
                    Text("按时间查看工作流程助手执行过的操作")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .appActionButton(minWidth: 72)
            }
            Divider()
            if entries.isEmpty {
                ContentUnavailableView(
                    "暂无操作日志",
                    systemImage: "list.bullet.rectangle",
                    description: Text("完成一次操作后，记录会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    Text("时间")
                        .frame(width: 150, alignment: .leading)
                    Text("操作内容")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries.reversed()) { entry in
                            HStack(alignment: .top, spacing: 14) {
                                Text(entry.displayTime)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 150, alignment: .leading)
                                Text(entry.operation)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { entries = OperationLogReader.entries(from: url) }
    }
}

let appDefaultSectionRawValue = "orders"

#if !TESTING
enum AppSection: String, CaseIterable, Identifiable {
    case assistant
    case orders
    case todo
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: return "助手"
        case .orders: return "订单中心"
        case .todo: return "待办"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .assistant: return "waveform.and.mic"
        case .orders: return "rectangle.3.group"
        case .todo: return "checklist"
        case .settings: return "gearshape"
        }
    }

    var pageTitle: String {
        switch self {
        case .assistant: return "PP FlowHub"
        case .orders: return "订单中心"
        case .todo: return "待办事项"
        case .settings: return "配置中心"
        }
    }

    var subtitle: String {
        switch self {
        case .assistant: return "文字、语音与本地优先助手"
        case .orders: return "查看订单、工厂单、材料、库存与出货状态"
        case .todo: return "记录需要处理的工作"
        case .settings: return "当前运行所需的本机设置"
        }
    }

    var isWorkSection: Bool {
        switch self {
        case .settings: return false
        default: return true
        }
    }

}

struct TopNavigationBar: View {
    @Binding var selection: AppSection
    @ObservedObject var model: AppModel
    @State private var showDesignNotes = false

    var body: some View {
        HStack(spacing: 26) {
            HStack(spacing: 10) {
                Image(systemName: selection.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(AppPalette.accent)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.pageTitle)
                        .font(.system(size: AppLayout.topPageTitleFontSize, weight: .semibold))
                        .lineLimit(1)
                    Text(selection.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 220, idealWidth: 330, maxWidth: 390, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(AppSection.allCases) { section in
                        navButton(section)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)

            Spacer(minLength: 12)
            contextualStatus
            if selection == .orders && !model.pendingCenterItems.isEmpty {
                Button {
                    model.showPendingCenterPrompt = true
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppPalette.warning)
                        .frame(width: AppLayout.headerActionSize, height: AppLayout.headerActionSize)
                        .background(AppPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.separator))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("有 \(model.pendingCenterItems.count) 个待处理项目")
                .help("打开待处理中心，查看 Server 文件夹和需要人工确认的问题")
            }
            Button { showDesignNotes = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: AppLayout.headerActionSize, height: AppLayout.headerActionSize)
                    .background(AppPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.separator))
            }
            .buttonStyle(.plain)
            .help("界面设计说明")
        }
        .padding(.horizontal, 24)
        .frame(height: AppLayout.headerHeight)
        .background(AppPalette.surface.opacity(0.97))
        .overlay(Divider(), alignment: .bottom)
        .sheet(isPresented: $showDesignNotes) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("界面设计说明").font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button("关闭") { showDesignNotes = false }.appActionButton(minWidth: 72)
                }
                designNote("信息架构", "助手页面显示订单统计和文字、语音操作入口；订单中心保留筛选、详情和业务操作；待办与设置保留独立导航。")
                designNote("响应式策略", "桌面保留高信息密度的列表与详情工作台；窗口变窄时优先保留主任务区域并允许内容滚动。")
                designNote("安全处理", "映射缺失继续作为阻断错误，库存不足继续明确警告；写文件与写库存仍使用原有本机确认边界。")
                designNote("视觉语言", "温暖浅灰背景、白色细边框卡片、冷蓝主操作色；琥珀与红色只用于风险和不可逆操作。")
            }
            .padding(24)
            .frame(width: 560)
            .background(AppPalette.background)
        }
        .sheet(isPresented: $model.showPendingCenterPrompt) {
            PendingCenterSheet(model: model)
                .frame(minWidth: 900, minHeight: 640)
        }
        .sheet(isPresented: $model.showServerWriteConfirmation) {
            ServerWriteConfirmationSheet(model: model)
                .frame(minWidth: 980, minHeight: 650)
        }
        .sheet(isPresented: $model.showInventoryMappingWorkspace) {
            PendingInventoryMappingWorkspace(model: model)
                .frame(minWidth: 620, minHeight: 420)
        }
        .sheet(isPresented: $model.showAimesReviewPrompt) {
            AimesReviewSheet(model: model)
                .frame(minWidth: 900, minHeight: 620)
        }
    }

    @ViewBuilder
    private var contextualStatus: some View {
        switch selection {
        case .assistant:
            AppStatusBadge(
                text: model.assistantRunning ? "任务执行中" : "助手就绪",
                kind: model.assistantRunning ? .info : .success
            )
        case .orders:
            EmptyView()
        case .todo:
            AppStatusBadge(
                text: "\(model.todoItems.filter { $0.completedAt == nil }.count) 项未完成",
                kind: .warning
            )
        case .settings:
            Button {
                model.loadSettings()
                model.settingsStatus = "已重新载入本机设置。"
            } label: {
                Label("重新载入", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .appActionButton(minWidth: 96)
        }
    }

    @ViewBuilder
    private func navButton(_ section: AppSection) -> some View {
        Button { selection = section } label: {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Text(section.title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    if section == .todo {
                        Text("\(model.todoItems.filter { $0.completedAt == nil }.count)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundColor(selection == section ? AppPalette.accent : .secondary)
                    }
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: AppLayout.headerHeight - 2)
                Rectangle()
                    .fill(selection == section ? AppPalette.accent : Color.clear)
                    .frame(height: 2)
            }
            .foregroundColor(selection == section ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func designNote(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(text).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct TravelerAssistantApp: App {
    @StateObject private var model = AppModel()
    @State private var selection = AppSection(rawValue: appDefaultSectionRawValue) ?? .orders

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                TopNavigationBar(selection: $selection, model: model)
                Divider()
                switch selection {
                case .assistant: AssistantView(model: model)
                case .orders: OrderDashboardView(model: model)
                case .todo: TodoView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
            .controlSize(.regular)
            .tint(AppPalette.accent)
            // The approved design is a light workspace with fixed white surfaces.
            // Keep semantic primary/secondary text in the matching light palette;
            // otherwise macOS dark mode produces white text on these white cards.
            .preferredColorScheme(AppPalette.interfaceColorScheme)
            .background(AppPalette.background)
            .frame(
                minWidth: AppLayout.windowMinWidth,
                idealWidth: AppLayout.windowIdealWidth,
                minHeight: AppLayout.windowMinHeight,
                idealHeight: AppLayout.windowIdealHeight
            )
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.closeInventoryChromeOnQuit()
            }
            .alert("今日未完成数据库备份", isPresented: $model.showBackupReminder) {
                Button("立即备份") { model.performBackup() }
                Button("稍后提醒", role: .cancel) {}
            } message: {
                Text(model.backupReminderStatus)
            }
        }
        .defaultSize(width: AppLayout.windowIdealWidth, height: AppLayout.windowIdealHeight)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
#endif
#if DEBUG && !TESTING
#Preview {
    OrderWorkflowView(model: AppModel())
}
#endif
