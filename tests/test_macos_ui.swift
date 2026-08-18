import AppKit
import SwiftUI

private final class OperationLogHarnessModel: ObservableObject {
    @Published var steps: [InventoryStep]

    init(steps: [InventoryStep]) {
        self.steps = steps
    }
}

private struct OperationLogHarnessView: View {
    @ObservedObject var model: OperationLogHarnessModel

    var body: some View {
        SelectableOperationLogView(steps: model.steps, emptyText: "empty")
            .frame(width: 720, height: AppLayout.operationLogHeight)
    }
}

private final class HeaderBoundaryProbeBox {
    weak var view: NSView?
}

private struct HeaderBoundaryProbe: NSViewRepresentable {
    let box: HeaderBoundaryProbeBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

private struct PageLayoutHarness: View {
    let box: HeaderBoundaryProbeBox
    let flexibleContent: Bool

    var body: some View {
        TabView {
            VStack(spacing: 0) {
                AppPageHeader(systemImage: "square", title: "页面", subtitle: "完整页面布局测试") {
                    Button("操作") {}
                }
                HeaderBoundaryProbe(box: box).frame(height: 1)
                if flexibleContent {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.clear.frame(height: 420)
                }
            }
            .appPageFrame()
            .tabItem { Text("页面") }
        }
        .frame(width: AppLayout.windowMinWidth, height: 900)
    }
}

@main
private struct MacOSUIRegressionTests {
    static func main() {
        testInventoryTravelerNewestFirst()
        testPushToTalkShortcut()
        testSpeechCommandCanonicalization()
        testAssistantOrderResultParsing()
        testAssistantCompactHelpAndCancelRules()
        testMaterialDisplayNames()
        testOrderDetailMaterialRows()
        testOrderDashboardRules()
        testOrderOutboundFactorySelection()
        testSharedPageHeaderHeight()
        testInventoryActionLayoutRules()
        testProductionOrderPaths()
        testRelatedPreviewMissingMaterialIssue()
        testPP0067MissingMaterialShowsPrompt()
        testStockFailureKeepsManualRetryEnabled()
        testExistingTravelerCanBeUpdatedAfterPreviewFailure()
        testDashboardTravelerActionsUseDatabaseFacts()
        testFullPageHeaderBoundaryAlignment()
        testOperationLogScrollsAfterAppending()
        testOperationLogReader()
        testRunningProgressReusesOperationRow()
        testInventoryProgressKeepsStageHistory()
        testOrderOperationDurationFormatting()
        print("macOS UI regression tests passed")
    }

    private static func testPushToTalkShortcut() {
        require(isPushToTalkShortcut(keyCode: 49, modifiers: .option), "⌥Space 应触发按住说话")
        require(!isPushToTalkShortcut(keyCode: 49, modifiers: .command), "⌘Space 不应被语音输入占用")
        require(!isPushToTalkShortcut(keyCode: 36, modifiers: .option), "⌥Return 不应触发语音输入")
    }

    private static func testSpeechCommandCanonicalization() {
        require(canonicalSpeechCommand("查找 PP 0零6八") == "查找PP0068", "语音订单号未规范化为 PP0068")
        require(canonicalSpeechCommand("查找 P P 零 零 六 八") == "查找PP0068", "分开识别的 PP 未规范化")
        require(canonicalSpeechCommand("查找 PP 0零35杠二") == "查找PP0035-2", "语音分单号未规范化")
    }

    private static func testAssistantOrderResultParsing() {
        let object: [String: Any] = [
            "order_id": "PP0068",
            "materials_file": "/orders/PP0068 materials.xlsx",
            "materials": [["kind": "panel", "thickness": 19.1, "color": "Basalto", "quantity": 6]],
            "edge_banding": ["Basalto": 22.5],
            "factories": [[
                "factory_order": "F100",
                "order_name": "PP0068-Kitchen",
                "fittings": [["key": "hinge", "name": "Hinge", "code": "71T950A", "quantity": 4]],
            ]],
            "warnings": [],
        ]
        guard let result = AssistantOrderResult(object: object) else {
            fatalError("助手订单预览数据解析失败")
        }
        require(result.orderId == "PP0068", "助手预览订单号错误")
        require(result.materials.count == 1, "助手预览板材数据缺失")
        require(result.factories.count == 1 && result.fittings.count == 1, "助手预览工厂单或五金数据缺失")
    }

    private static func testAssistantCompactHelpAndCancelRules() {
        require(assistantCommandHints.count >= 5, "悬停命令示例内容不完整")
        require(assistantCommandHints.contains(where: { $0.contains("Find order") }), "命令示例缺少英文命令")
        require(assistantTaskShowsHeaderCancel("排队中"), "排队任务应允许在顶部取消")
        require(assistantTaskShowsHeaderCancel("执行中"), "可中断执行任务应显示顶部取消")
        require(!assistantTaskShowsHeaderCancel("等待确认"), "等待确认时不应同时显示两个取消按钮")
    }

    private static func testMaterialDisplayNames() {
        require(AppLayout.headerHeight == 64, "顶部导航与页面标题栏应采用 64pt 紧凑高度")
        require(AppLayout.topNavHeight == AppLayout.headerHeight, "顶部导航与页面页头应合并为单层")
        require(AppLayout.topPageTitleFontSize >= 19, "顶部页面标题字号仍然过小")
        require(AppLayout.headerActionSize == 44, "顶部图标操作按钮应保持统一的 44pt 尺寸")
        require(AppLayout.controlHeight == 44, "关键按钮与输入框应保持 44pt 操作目标")
        require(AppPalette.interfaceColorScheme == .light, "固定白色表面必须配套浅色文字环境")
        require(AppLayout.inventoryPreviewMinHeight >= 320, "库存预览区最小高度不足")
        require(AppLayout.windowMinWidth >= 1180, "窗口最小宽度不足以容纳导航和操作控件")
        require(AppLayout.windowIdealWidth == 1760, "默认窗口宽度应与当前生产工作区一致")
        require(AppLayout.windowIdealHeight == 1360, "默认窗口高度应与当前生产工作区一致")
        require(AppLayout.todoDeadlineColumnWidth >= 270, "截止时间列不足以同时显示时间和过期提醒")
        require(AppLayout.todoListMaxHeight == 340, "待办列表高度未按要求压缩")
        require(AppLayout.todoInputMinHeight >= 92, "新增待办输入框高度不足三行")
        require(
            inventoryCatalogUpdateSuccessStatus(5) == "✅ 商品资料更新成功，共 5 个商品",
            "商品资料成功提示未包含明确结果和数量"
        )
        require(
            inventoryCatalogUpdateSuccessStatus(5, added: 2, updated: 1, removed: 3)
                == "✅ 商品资料更新成功，共 5 个商品（新增 2，更新 1，删除 3）",
            "商品资料成功提示未包含新增、更新和删除摘要"
        )
        require(
            inventoryCatalogUpdateFailureStatus("连接失败") == "❌ 商品资料更新失败：连接失败",
            "商品资料失败提示未包含明确错误"
        )
        require(settingsStatusKind("✅ 设置已保存") == .success, "成功状态未统一识别")
        require(settingsStatusKind("❌ 保存失败") == .danger, "错误状态未统一识别")
        require(settingsStatusKind("正在更新商品资料…") == .info, "进行中状态未统一识别")
        require(
            settingsStatusDisplayText("❌ 商品资料更新失败：连接失败") == "商品资料更新失败：连接失败",
            "统一状态提示没有移除重复状态图标"
        )
        require(AppLayout.todoTableHeaderFontSize >= 17, "待办表格标题字体仍然过小")
        require(AppLayout.todoTableBodyFontSize >= 16, "待办表格内容字体仍然过小")
        require(AppLayout.materialNameFontSize >= 18, "板材与封边名称字体仍然过小")
        func material(_ kind: String, _ thickness: Double, _ color: String = "") -> OrderMaterialPreview {
            OrderMaterialPreview(kind: kind, thickness: thickness, color: color, quantity: 1)
        }
        require(orderMaterialDisplayName(material("plywood", 18)) == "柜体板", "18mm Plywood 名称错误")
        require(orderMaterialDisplayName(material("plywood", 14.5)) == "抽屉板", "14.5mm Plywood 名称错误")
        require(orderMaterialDisplayName(material("plywood", 5.4)) == "背板", "5.4mm Plywood 名称错误")
        require(orderMaterialDisplayName(material("panel", 19.1, "Woodline 4")) == "Woodline 4", "19.1mm Panel 应只显示颜色")
        require(orderMaterialDisplayName(material("panel", 8, "Ivory Oak")) == "Ivory Oak", "8mm Panel 应只显示颜色")
        require(orderMaterialDisplayName(material("panel", 9, "Basalto")) == "Basalto", "9mm Panel 应只显示颜色")

        let mixed = [
            material("panel", 19.1, "Woodline 4"),
            material("panel", 9, " woodline 4 "),
            material("panel", 19.1, "Basalto"),
        ]
        require(panelColorsNeedingThicknessWarning(mixed) == Set(["woodline 4"]), "同色门板与背板未触发规格警示")
    }

    private static func testOrderDetailMaterialRows() {
        let rows = [
            OrderMaterialPreview(kind: "panel", thickness: 19.1, color: "Woodline 4", quantity: 2),
            OrderMaterialPreview(kind: "plywood", thickness: 5.4, color: "", quantity: 3),
            OrderMaterialPreview(kind: "panel", thickness: 19.1, color: "Basalto", quantity: 1),
            OrderMaterialPreview(kind: "plywood", thickness: 18, color: "", quantity: 4),
        ]
        require(
            orderDetailPlywoodRows(rows).map { orderMaterialDisplayName($0) } == ["柜体板", "背板"],
            "订单详情 Plywood 未保持厚度顺序"
        )
        require(
            orderDetailPanelRows(rows).map(\.color) == ["Basalto", "Woodline 4"],
            "订单详情 Panel 未按颜色排序"
        )
        require(
            orderDetailEdgeColors(["Woodline 4", "Basalto", "Ivory Oak"]) == ["Basalto", "Ivory Oak", "Woodline 4"],
            "订单详情封边条未按颜色排序"
        )
    }

    private static func testOrderDashboardRules() {
        require(dashboardStatusIsInProgress("正在后台扫描 Server 变化…"), "进行中的 Server 状态未被识别")
        require(!dashboardStatusIsInProgress("✅ Server 扫描完成"), "已完成的 Server 状态被误判为进行中")
        require(dashboardMessageHoverDelay == 1.0, "消息悬停详情必须停留超过一秒后才显示")
        let materials = [
            OrderMaterialPreview(kind: "panel", thickness: 19.1, color: "Basalto SM", quantity: 7),
            OrderMaterialPreview(kind: "panel", thickness: 19.1, color: " basalto sm ", quantity: 1),
            OrderMaterialPreview(kind: "panel", thickness: 19.1, color: "Woodline 4", quantity: 2),
        ]
        require(orderDashboardPanelColors(materials) == ["Basalto SM", "Woodline 4"], "订单中心 Panel 颜色未按颜色去重")

        let stockRows = [
            OrderStockPreview(id: "A", productCode: "A", productName: "Basalto SM", unit: "张", travelerNames: [], required: 7, available: 6, shortage: 1, sufficient: false),
            OrderStockPreview(id: "B", productCode: "B", productName: "封边条", unit: "m", travelerNames: [], required: 222, available: 640, shortage: 0, sufficient: true),
        ]
        require(orderDashboardShortageCount(stockRows) == 1, "库存比对弹窗未正确统计不足项目")
        require(orderDashboardStatus(previewValidated: true, hasError: false, isExistingTraveler: true) == "已优化", "订单中心已校验状态错误")
        require(orderDashboardStatus(previewValidated: false, hasError: true, isExistingTraveler: false) == "数据异常", "订单中心异常状态错误")
        require(orderDashboardStatuses.count == 9, "订单状态列表数量发生意外变化")
        require(orderDashboardStatuses.first == "已设计" && orderDashboardStatuses.last == "数据异常", "订单状态列表顺序错误")
        require(orderDashboardMetricColumnCount == 8, "订单指标卡必须固定为一行 8 列")
        require(orderDashboardMetricColumns.count == orderDashboardMetricColumnCount, "订单指标卡列配置数量错误")
        require(
            orderDashboardProgressFraction(completed: 1, total: 1) == 1,
            "订单中心已完成优化的进度条比例错误"
        )
        require(
            orderDashboardProgressFraction(completed: 1, total: 2) == 0.5,
            "订单中心部分优化的进度条比例错误"
        )
        require(
            orderDashboardProgressFraction(completed: 3, total: 2) == 1
                && orderDashboardProgressFraction(completed: -1, total: 2) == 0,
            "订单中心进度条比例未限制在有效范围"
        )
        require(
            orderDashboardMetricsFit(width: AppLayout.windowMinWidth, horizontalPadding: AppLayout.contentPadding),
            "订单指标卡在最小窗口宽度下无法保持一行显示"
        )
        let reviewObject: [String: Any] = [
            "aimes_issues": [[
                "ignore_key": "factory:F200",
                "factory_order": "F200",
                "factory_name": "TEST ROOM",
                "sales_order_name": "BAD-ORDER",
                "reason": "销售单名称不符合规则",
                "suggested_order_id": "CS001",
            ]],
            "ignored_aimes": [[
                "ignore_key": "factory:F201",
                "factory_order": "F201",
                "factory_name": "OFFICE TEST",
                "sales_order_name": "PP0035",
                "reason": "名称包含 test",
                "ignored_at": "2026-08-10T12:00:00",
            ]],
            "assigned_aimes": [[
                "ignore_key": "factory:F202",
                "factory_order": "F202",
                "factory_name": "CS001-Unnamed",
                "sales_order_name": "SHERRY 001",
                "reason": "已按工厂单名称确认归入 CS001",
                "suggested_order_id": "CS001",
                "ignored_at": "2026-08-10T13:00:00",
            ]],
        ]
        let pendingReviews = aimesReviewItems(reviewObject, key: "aimes_issues")
        let ignoredReviews = aimesReviewItems(reviewObject, key: "ignored_aimes")
        let assignedReviews = aimesReviewItems(reviewObject, key: "assigned_aimes")
        require(pendingReviews.count == 1 && pendingReviews[0].factoryOrder == "F200", "AIMES 待确认清单解析错误")
        require(
            !shouldPresentPendingCenterAfterAimes(presentIfNeeded: true, pendingAimesReviews: []),
            "仅有 Server 待处理项目时，获取 AIMES 不应弹出待处理中心"
        )
        require(
            shouldPresentPendingCenterAfterAimes(presentIfNeeded: true, pendingAimesReviews: pendingReviews),
            "存在 AIMES 待确认记录时，应允许获取 AIMES 后打开待处理中心"
        )
        require(pendingReviews[0].suggestedOrderID == "CS001", "AIMES 工厂单名称建议订单号解析错误")
        require(ignoredReviews.count == 1 && !ignoredReviews[0].ignoredAt.isEmpty, "AIMES 已忽略记录解析错误")
        require(assignedReviews.count == 1 && assignedReviews[0].suggestedOrderID == "CS001", "AIMES 已确认建议归属解析错误")
        let warningReviews = aimesReviewItemsFromWarnings([[
            "ignore_key": "factory:F203",
            "factory_order": "F203",
            "factory_name": "CS001-Unnamed",
            "sales_order_name": "SHERRY 001",
            "reason": "销售单名称不是标准订单号",
            "suggested_order_id": "CS001",
        ]])
        require(
            warningReviews.count == 1
                && warningReviews[0].salesOrderName == "SHERRY 001"
                && warningReviews[0].suggestedOrderID == "CS001",
            "销售单格式异常没有转换为可人工处理记录"
        )
        let aimesActionDetails = dashboardAimesActionDetails(
            pending: pendingReviews,
            ignored: ignoredReviews,
            assigned: assignedReviews
        )
        require(aimesActionDetails.contains("已忽略 1 条："), "AIMES 已忽略数量详情缺失")
        require(aimesActionDetails.contains(where: { $0.contains("F201") && $0.contains("OFFICE TEST") }), "AIMES 已忽略具体工厂单详情缺失")
        let warningDetails = dashboardAimesWarningDetails([[
            "factory_order": "F2606150155",
            "factory_name": "PP0018 DRAWER",
            "sales_order_name": "PP0018 DRAWER",
            "reason": "销售单名称不是标准订单号",
        ]])
        require(warningDetails.contains(where: { $0.contains("PP0018 DRAWER") && $0.contains("销售单名称") }), "销售单格式异常详情没有显示销售单名称")
        let aimesPerformanceMessages = dashboardMessages(
            syncStatus: "订单数据同步完成",
            syncTime: "12:02:00",
            aimesStatus: "⚠️ AIMES 发现 1 条销售单格式异常",
            aimesTime: "12:02:01",
            serverStatus: "Server 尚未扫描",
            serverTime: "12:02:02",
            activity: [],
            contextDetailsBySource: ["aimes": warningDetails],
            durationsBySource: ["aimes": 61.95],
            operationDurationsBySource: ["aimes": [
                DashboardOperationDuration(label: "启动 AIMES 浏览器", duration: 0.74),
                DashboardOperationDuration(label: "登录 AIMES", duration: 35.10),
                DashboardOperationDuration(label: "读取 AIMES 工厂订单表格", duration: 1.20),
            ]]
        )
        let aimesPerformance = aimesPerformanceMessages.first(where: { $0.source == "aimes" })
        require(dashboardMessageDetailText(aimesPerformance!).contains("启动 AIMES 浏览器：0.74 秒"), "AIMES 阶段耗时没有进入消息列表")
        let aimesSummary = dashboardMessageSummaryText(aimesPerformance!)
        require(aimesSummary.contains("总计用时 61.95 秒"), "消息标题没有显示 AIMES 总计用时")
        require(!aimesSummary.contains("启动 AIMES 浏览器"), "消息标题不应显示阶段明细")
        require(aimesPerformance?.contextDetails.contains(where: { $0.contains("PP0018 DRAWER") }) == true, "销售单异常明细没有进入消息上下文")
        let duplicateStatusMessages = dashboardMessages(
            syncStatus: "⚠️ AIMES 发现 1 条销售单格式异常",
            syncTime: "12:03:00",
            aimesStatus: "⚠️ AIMES 发现 1 条销售单格式异常",
            aimesTime: "12:03:01",
            serverStatus: "Server 尚未扫描",
            serverTime: "12:03:02",
            activity: [],
            durationsBySource: ["sync": 0.66, "aimes": 17.36],
            operationDurationsBySource: ["aimes": [
                DashboardOperationDuration(label: "登录 AIMES", duration: 9.99),
            ]]
        )
        let duplicateAimes = duplicateStatusMessages.first(where: { $0.source == "aimes" })
        require(duplicateStatusMessages.filter { $0.detail.contains("销售单格式异常") }.count == 1, "相同状态消息没有正确去重")
        require(duplicateAimes?.duration == 17.36, "相同状态去重时错误保留了订单数据耗时")
        require(duplicateAimes?.operationDurations.first?.label == "登录 AIMES", "相同状态去重时 AIMES 阶段明细丢失")

        let serverFolder = "/Volumes/server/Optimized Orders/pp0035-2"
        let serverChanges = [
            ServerChangePreview(
                id: "added:\(serverFolder)",
                changeType: "added",
                kind: "folder",
                orderId: "PP0035-2",
                sourceFolder: serverFolder,
                path: serverFolder,
                message: "新增订单文件夹",
                manualOnly: false,
                eventTime: "2026-08-12T10:00:00"
            ),
            ServerChangePreview(
                id: "modified:\(serverFolder)/material.xlsx",
                changeType: "modified",
                kind: "material",
                orderId: "PP0035-2",
                sourceFolder: serverFolder,
                path: "\(serverFolder)/material.xlsx",
                message: "材料发生变化",
                manualOnly: false,
                eventTime: "2026-08-12T10:01:00"
            ),
        ]
        let folderIssue = CurrentIssue(
            id: "order_validation:\(serverFolder)",
            kind: "order_validation",
            orderId: "PP0035-2",
            factoryOrder: "",
            path: "\(serverFolder)/material.xlsx",
            message: "材料映射失败，请检查 material。",
            firstSeen: "2026-08-12T10:00:00",
            lastSeen: "2026-08-12T10:00:00"
        )
        let unifiedItems = buildPendingCenterItems(
            serverChanges: serverChanges,
            currentIssues: [folderIssue],
            aimesReviews: []
        )
        require(unifiedItems.count == 1, "同一 Server 文件夹不应同时显示为多个待处理项目")
        require(unifiedItems[0].serverGroup?.changes.count == 2, "待处理中心没有保留文件变化明细")
        require(unifiedItems[0].issues.count == 1 && unifiedItems[0].status == "处理失败", "文件夹失败原因没有合并到主记录")
        let withSeparateAimes = buildPendingCenterItems(
            serverChanges: serverChanges,
            currentIssues: [folderIssue],
            aimesReviews: pendingReviews
        )
        require(withSeparateAimes.count == 2, "AIMES 独立待确认记录没有进入统一待处理中心")
        require(withSeparateAimes.contains(where: { $0.aimesReviews.count == 1 }), "AIMES 待确认记录类型丢失")
        let dashboardLog = dashboardActivitySteps([
            "changes": [[
                "observed_at": "2026-08-10T12:34:56",
                "severity": "warning",
                "kind": "order_validation",
                "order_id": "PP0063-2",
                "factory_order": "F2607270215",
                "path": "/Volumes/server/Optimized Orders/pp0063-2/materials.xlsx",
                "message": "订单报表需要检查，请补充 material 后重新处理。",
            ]],
        ])
        require(dashboardLog.count == 1, "看板操作记录没有解析数据变化")
        require(dashboardLog[0].time == "12:34:56" && dashboardLog[0].state == "warning", "看板操作记录时间或状态错误")
        require(
            dashboardLog[0].operationDetails.contains(where: { $0.contains("PP0063-2") && $0.contains("F2607270215") }),
            "订单更新悬停详情没有显示订单号和工厂单号"
        )
        require(
            dashboardLog[0].operationDetails.contains(where: { $0.contains("materials.xlsx") }),
            "订单更新悬停详情没有显示来源文件"
        )
        require(
            dashboardActivitySteps(["changes": [["message": "历史消息"]]], includeChanges: false).isEmpty,
            "读取本地缓存时不应把历史消息放进本次消息记录"
        )
        let combinedDashboardMessages = dashboardMessages(
            syncStatus: "✅ 已显示本地缓存；后台检查完成",
            syncTime: "12:00:01",
            aimesStatus: "✅ 今天已成功获取过 AIMES，本次略过",
            aimesTime: "12:00:02",
            serverStatus: "⚠️ 服务器目录不可访问",
            serverTime: "12:00:03",
            activity: dashboardLog
        )
        require(combinedDashboardMessages.count == 4, "当前状态和历史记录没有合并到同一个消息框")
        require(combinedDashboardMessages.suffix(3).map(\.source) == ["sync", "aimes", "server"], "当前状态没有按更新时间排列到消息底部")
        require(!combinedDashboardMessages[1].detail.hasPrefix("✅"), "消息记录正文不应重复显示状态图标")
        require(combinedDashboardMessages.suffix(3).allSatisfy { !$0.time.isEmpty }, "当前状态消息没有显示时间")
        let tracedDashboardMessages = dashboardMessages(
            syncStatus: "✅ 订单数据同步完成",
            syncTime: "12:01:00",
            aimesStatus: "AIMES 尚未检查",
            aimesTime: "12:01:01",
            serverStatus: "✅ Server 变化已处理（2 项）",
            serverTime: "12:01:02",
            activity: [],
            operationDetailsBySource: ["server": ["从 Server 目录读取订单号 1 个、工厂单号 2 个的报表。", "写入到了 order-index.sqlite3。"]],
            manualPathsBySource: ["server": ["/Volumes/server/PP0035-2/material.xlsx", ""]],
            contextDetailsBySource: ["server": ["Server 已完成扫描，当前没有新增、修改或删除的订单文件。"]]
        )
        let tracedServer = tracedDashboardMessages.first(where: { $0.source == "server" })
        require(tracedServer?.operationDetails.count == 2, "自动处理详情没有附加到看板消息")
        require(tracedServer?.manualPaths == ["/Volumes/server/PP0035-2/material.xlsx"], "人工处理文件路径没有附加到看板消息")
        require(tracedServer?.contextDetails.count == 1, "看板处理结果摘要没有附加到消息")
        let performanceTrace = dashboardMessages(
            syncStatus: "订单数据同步完成",
            syncTime: "12:01:00",
            aimesStatus: "AIMES 尚未检查",
            aimesTime: "12:01:01",
            serverStatus: "Server 扫描完成",
            serverTime: "12:01:02",
            activity: [],
            operationDetailsBySource: ["server": [
                "快速检查 8 个相关 Excel 文件，复用 2 个订单文件夹，深度扫描 1 个订单文件夹，总用时 0.12 秒。",
                "扫描范围：订单文件夹 3 个，相关 Excel 文件 8 个（目录：/Volumes/server/Optimized Orders）。",
                "变化统计：新增 1 个，修改 2 个，删除 0 个。",
            ]],
            durationsBySource: ["server": 20.205],
            operationDurationsBySource: ["server": [
                DashboardOperationDuration(label: "扫描 Server", duration: 18.485),
                DashboardOperationDuration(label: "更新 Server 订单索引", duration: 1.720),
            ]]
        )
        let performanceServer = performanceTrace.first(where: { $0.source == "server" })
        require(performanceServer?.operationDetails.contains("快速检查 8 个相关 Excel 文件，复用 2 个订单文件夹，深度扫描 1 个订单文件夹，总用时 0.12 秒。") == true, "Server 扫描方式统计没有进入悬停详情")
        require(performanceServer?.operationDetails.contains("扫描范围：订单文件夹 3 个，相关 Excel 文件 8 个（目录：/Volumes/server/Optimized Orders）。") == true, "Server 扫描范围统计没有进入悬停详情")
        require(performanceServer?.operationDetails.contains("变化统计：新增 1 个，修改 2 个，删除 0 个。") == true, "Server 变化数量统计没有进入悬停详情")
        require(dashboardMessageDetailText(performanceServer!).contains("用时 20.20 秒"), "订单消息没有显示总操作用时")
        require(performanceServer?.operationDurations.map(\.label) == ["扫描 Server", "更新 Server 订单索引"], "Server 后台阶段没有完整保留")
        require(performanceServer?.operationDurations.map(\.duration) == [18.485, 1.720], "Server 后台阶段耗时没有完整保留")
        require(dashboardMessageVisibleRowCount == 3, "消息记录框必须一次显示 3 条记录")
        require(dashboardMessageViewportHeight == dashboardMessageRowHeight * 3, "消息记录框高度与三条记录不匹配")
        let deduplicatedMessages = dashboardMessages(
            syncStatus: "⚠️ 服务器目录不可访问",
            syncTime: "12:00:01",
            aimesStatus: "✅ AIMES 获取成功",
            aimesTime: "12:00:02",
            serverStatus: "⚠️ 服务器目录不可访问",
            serverTime: "12:00:03",
            activity: []
        )
        require(deduplicatedMessages.count == 2, "相同状态消息没有自动去重")
        let runningDisplay = dashboardCurrentOperation(messages: [
            DashboardMessage(id: "1", source: "aimes", time: "12:00:00", title: "AIMES", detail: "正在获取数据…", state: "info"),
            DashboardMessage(id: "2", source: "server", time: "12:00:01", title: "Server", detail: "扫描完成", state: "success"),
        ], isRunning: true)
        require(runningDisplay?.isRunning == true && runningDisplay?.message.id == "1", "进行中操作没有优先显示")
        let runningMessages = dashboardMessages(
            syncStatus: "订单数据同步完成",
            syncTime: "12:01:00",
            aimesStatus: "AIMES 尚未检查",
            aimesTime: "12:01:01",
            serverStatus: "正在自动处理 Server 变化并解析相关报表…",
            serverTime: "12:01:02",
            activity: []
        )
        let visibleWhileRunning = dashboardVisibleMessages(runningMessages, isRunning: true)
        require(!visibleWhileRunning.contains(where: { dashboardStatusIsInProgress($0.detail) }), "进行中的操作不应显示在消息列表")
        require(dashboardVisibleMessages(runningMessages, isRunning: false).count == runningMessages.count, "操作完成后不应隐藏消息记录")
        let serverRows = serverChangePreviews([
            [
                "id": "added:/Volumes/server/CS003 PP0047",
                "change_type": "added",
                "kind": "folder",
                "order_id": "CS003、PP0047",
                "source_folder": "/Volumes/server/CS003 PP0047",
                "path": "/Volumes/server/CS003 PP0047",
                "message": "Server 混单文件夹新增：CS003 PP0047",
                "manual_only": false,
                "event_time": "2026-08-12T10:00:00",
                "mixed_order": true,
            ],
            [
                "id": "added:/Volumes/server/b12",
                "change_type": "added",
                "kind": "folder",
                "order_id": "",
                "source_folder": "/Volumes/server/b12",
                "path": "/Volumes/server/b12",
                "message": "Server 临时订单文件夹新增：b12",
                "manual_only": true,
                "event_time": "2026-08-12T10:02:00",
            ],
            [
                "id": "missing_report:/Volumes/server/CS003 PP0047",
                "change_type": "missing_report",
                "kind": "folder",
                "order_id": "CS003、PP0047",
                "source_folder": "/Volumes/server/CS003 PP0047",
                "path": "/Volumes/server/CS003 PP0047",
                "message": "Server 混单文件夹缺少可识别的报表",
                "manual_only": false,
                "event_time": "2026-08-12T10:00:00",
                "mixed_order": true,
            ],
        ])
        require(serverRows.count == 3 && !serverRows[0].manualOnly && serverRows[1].manualOnly, "Server 混单与临时目录状态解析错误")
        require(serverRows[0].orderId == "CS003、PP0047", "Server 混单订单号没有保留完整订单集合")
        require(serverRows[0].eventTime == "2026-08-12T10:00:00", "Server 文件变化时间没有保留")
        let groupedServerRows = serverFolderChangeGroups(serverRows)
        require(groupedServerRows.count == 2, "Server 待处理变化没有按文件夹分组")
        require(groupedServerRows.allSatisfy { $0.changes.count == 2 || $0.changes.count == 1 }, "Server 文件夹分组没有保留文件变化明细")
        require(groupedServerRows.contains { $0.requiresManualReview }, "缺少报表的混单文件夹没有标记为人工检查")
        let completedDisplay = dashboardCurrentOperation(messages: combinedDashboardMessages, isRunning: false)
        require(completedDisplay?.isRunning == false && completedDisplay?.message.state == "warning", "空闲时没有显示最近成功或失败结果")
        require(!dashboardMessageScrollKey(combinedDashboardMessages).isEmpty, "消息变化无法触发自动滚动")
        let reviewModel = AppModel()
        reviewModel.toggleAimesReviewSelection(pendingReviews[0])
        require(reviewModel.selectedAimesReviewIDs == Set(["factory:F200"]), "AIMES 待确认记录无法选中")
        reviewModel.toggleAimesReviewSelection(pendingReviews[0])
        require(reviewModel.selectedAimesReviewIDs.isEmpty, "AIMES 待确认记录无法取消选择")
        require(
            orderDashboardStatusHelp(status: "数据异常", validationMessage: "缺少 material，请补充后重新扫描 Server。")
                == "缺少 material，请补充后重新扫描 Server。",
            "数据异常悬停提示没有使用数据库中的业务原因"
        )
        require(orderDashboardStatusHelp(status: "已优化", validationMessage: "不应显示").isEmpty, "正常状态不应显示异常提示")
        let technical = businessFriendlyMessage(
            "Traceback: Error Domain=NSPOSIXErrorDomain Code=2, status code 500",
            operation: "订单操作"
        )
        require(technical.contains("订单操作未完成"), "底层错误没有转换为业务提示")
        require(!technical.lowercased().contains("traceback") && !technical.contains("500"), "业务提示仍泄露底层错误代码")
        require(
            businessFriendlyMessage("未找到 material 文件，请补充后重试。", operation: "订单操作").contains("material"),
            "可执行的中文业务提示不应被覆盖"
        )
        require(
            dashboardFailureMessage(
                "更新 Server 订单索引失败",
                rawError: "订单操作未完成。请重试；如果仍然失败，请检查相关文件、网络和登录状态后再操作。",
                operation: "更新 Server 订单索引"
            ) == "更新 Server 订单索引失败",
            "Server 订单索引失败没有显示当前阶段的失败文案"
        )
        require(
            businessFriendlyMessage(
                "locator.waitFor: Timeout 10000ms exceeded #storage/otherOutbound_menu",
                operation: "库存操作"
            ).contains("库存操作未完成") &&
                businessFriendlyMessage(
                    "locator.waitFor: Timeout 10000ms exceeded #storage/otherOutbound_menu",
                    operation: "库存操作"
                ).contains("左侧“仓库”菜单"),
            "出库菜单超时没有转换为可执行的阶段提示"
        )
        let leakedPythonDetail = businessFriendlyMessage(
            "Excel 文件无法读取，请检查文件是否损坏或仍在编辑：cannot access local variable 'order_hint' where it is not associated with a value",
            operation: "订单数据"
        )
        require(
            leakedPythonDetail.contains("订单数据未完成") && !leakedPythonDetail.contains("order_hint"),
            "中文错误消息仍泄露 Python 局部变量名"
        )
        require(
            appDisplayTimestamp("2026-07-31T14:57:15") == "2026-07-31 14:57:15",
            "时间显示没有将 ISO 的 T 替换为空格"
        )
        let fileSpecificActivity = dashboardActivitySteps([
            "changes": [[
                "observed_at": "2026-08-12T11:11:40",
                "severity": "warning",
                "kind": "report_error",
                "path": "/Volumes/server/Optimized Orders/Report/Fittingslist.xlsx",
                "message": "Fittingslist Fittingslist.xlsx 无法读取，请检查文件格式。",
            ]],
        ])
        require(
            fileSpecificActivity.first?.detail.contains("Fittingslist.xlsx") == true,
            "Excel 读取失败详情没有显示具体文件名"
        )
        require(orderDashboardExpandedID(current: nil, tapped: "PP0035-2") == "PP0035-2", "点击折叠订单行应展开")
        require(orderDashboardExpandedID(current: "PP0035-2", tapped: "PP0035-2") == nil, "再次点击同一订单行应折叠")
        require(orderDashboardExpandedID(current: "PP0035", tapped: "PP0035-2") == "PP0035-2", "点击其他订单行应切换展开项")
        require(orderDashboardExpandedID(current: "PP0035-2", tapped: "PP0035-2", forceOpen: true) == "PP0035-2", "强制打开不应意外折叠")
        require(appSectionShowsInTopNavigation("assistant"), "助手页面必须保留顶部导航")
        require(appSectionShowsInTopNavigation("orders"), "订单中心必须继续保留顶部导航")
        require(appDefaultSectionRawValue == "orders", "App 默认页面必须继续是订单中心")
        _ = OrderDashboardMetricsView(model: AppModel())
        _ = OrderDashboardView(model: AppModel())
    }

    private static func testOrderOutboundFactorySelection() {
        require(orderDashboardFactorySelectionColumnWidth >= 48, "工厂单选择框列宽过窄")
        let first = toggledOrderFactorySelection([], factoryOrder: "F100")
        let both = toggledOrderFactorySelection(first, factoryOrder: "F200")
        let removed = toggledOrderFactorySelection(both, factoryOrder: "F100")
        require(first == Set(["F100"]), "首次点击工厂单应建立选择")
        require(both == Set(["F100", "F200"]), "工厂单应支持多选")
        require(removed == Set(["F200"]), "再次点击已选工厂单应取消选择")
        let factories = [
            OrderFactoryPreview(id: "F100", factoryOrder: "F100", orderName: "PP0099-KITCHEN"),
            OrderFactoryPreview(id: "F200", factoryOrder: "F200", orderName: "PP0099-OFFICE"),
        ]
        require(
            selectedOrderFactoryNames(factories, selected: both) == ["PP0099-KITCHEN", "PP0099-OFFICE"],
            "出库上下文应传入所选工厂单名称"
        )
        require(
            orderDashboardHasShippedSelection(["F100"], statuses: ["F100": "已出库", "F200": "需要更新"]),
            "已出库工厂单必须阻止再次出库"
        )
        require(
            !orderDashboardHasShippedSelection(["F200"], statuses: ["F100": "已出库", "F200": "需要更新"]),
            "需要更新工厂单应允许进入更新出库"
        )
        require(
            !orderDashboardStageMatchesFilter("已出货", statusFilter: "未完成订单")
                && orderDashboardStageMatchesFilter("已出货", statusFilter: "已出货")
                && orderDashboardStageMatchesFilter("已优化", statusFilter: "未完成订单"),
            "订单中心默认列表没有隐藏已完成订单，或状态筛选无法查看已出货订单"
        )
    }

    private static func testInventoryTravelerNewestFirst() {
        let rows = [
            traveler("old-a", folder: "PP0001", modifiedAt: "2026-07-01T10:00:00"),
            traveler("new-a", folder: "PP0001", modifiedAt: "2026-07-03T10:00:00"),
            traveler("newest", folder: "PP0002", modifiedAt: "2026-07-04T10:00:00"),
            traveler("old-b", folder: "PP0002", modifiedAt: "2026-07-02T10:00:00"),
        ]
        let grouped = groupInventoryTravelersByNewest(rows)
        require(grouped.map(\.0) == ["PP0002", "PP0001"], "Traveler 文件夹未按最新文件时间降序")
        require(grouped[0].1.map(\.fileName) == ["newest", "old-b"], "PP0002 内文件未按时间降序")
        require(grouped[1].1.map(\.fileName) == ["new-a", "old-a"], "PP0001 内文件未按时间降序")
    }

    private static func testSharedPageHeaderHeight() {
        let headers = [
            AnyView(AppPageHeader(systemImage: "folder", title: "生产文件", subtitle: "测试") {
                Button("刷新") {}
            }),
            AnyView(AppPageHeader(systemImage: "shippingbox", title: "出库", subtitle: "测试") {
                Text("商品资料")
                Button("更新") {}
                Button("刷新") {}
            }),
            AnyView(AppPageHeader(systemImage: "checkmark.square", title: "待办事项", subtitle: "测试") {
                Label("1 项未完成", systemImage: "circle.dashed")
            }),
            AnyView(AppPageHeader(systemImage: "gearshape", title: "设置", subtitle: "测试") {
                Button("重新载入") {}
            }),
        ]
        for header in headers {
            let hosting = NSHostingView(rootView: header.frame(width: AppLayout.windowMinWidth))
            hosting.layoutSubtreeIfNeeded()
            require(hosting.fittingSize.height <= 0.5, "底部重复页头未移除：\(hosting.fittingSize.height)")
        }
    }

    private static func testInventoryActionLayoutRules() {
        require(AppLayout.inventoryActionMinWidth >= 128, "库存按钮最小宽度过窄")
        require(AppLayout.actionSpacing == 10, "库存按钮间距未统一")
        require(AppLayout.inventoryOrderContextWidth == 735, "上下文出库窗口宽度未缩小到 735pt")
        require(
            AppLayout.inventoryOrderContextWidth - AppLayout.contentPadding * 2 >= 4 * 156 + 3 * AppLayout.actionSpacing,
            "735pt 出库窗口不足以让四个操作按钮保持一排"
        )
        require(
            inventoryActionColumnCount(availableWidth: 420) >= 2,
            "库存操作区在常规宽度下未能并排按钮"
        )
        require(
            inventoryActionColumnCount(availableWidth: AppLayout.inventoryActionMinWidth) == 1,
            "库存操作区在窄窗口下未换行为单列"
        )
        _ = InventoryView(model: AppModel(), onClose: {})
    }

    private static func testRunningProgressReusesOperationRow() {
        let id = UUID()
        let steps = [
            InventoryStep(id: id, time: "12:00:00", title: "查询实时库存", detail: "任务已开始", state: "running")
        ]
        guard let updated = updatingLatestRunningStep(steps, detail: "正在后台连接库存系统") else {
            fail("后台进度没有找到正在执行的操作行")
        }
        require(updated.count == 1, "后台进度不应新增重复操作行")
        require(updated[0].id == id, "后台进度更新不应更换操作行标识")
        require(updated[0].state == "running", "后台进度不应被标记为成功")
        require(updated[0].detail == "正在后台连接库存系统", "后台进度文案未更新")
    }

    private static func testInventoryProgressKeepsStageHistory() {
        let steps = [
            InventoryStep(time: "12:00:00", title: "库存操作", detail: "任务已开始", state: "running")
        ]
        let updated = appendingInventoryProgressStep(steps, message: "登录页面：实际耗时 2.00 秒")
        require(updated.count == 2, "库存分阶段进度不应覆盖上一条记录")
        require(updated[0].state == "success", "上一阶段完成后应保留为已完成")
        require(updated[1].state == "running", "最新库存阶段应保持执行中")
        require(updated[1].detail.contains("实际耗时"), "库存阶段应显示实际耗时")
    }

    private static func testOrderOperationDurationFormatting() {
        require(operationDurationText(1.236) == "1.24 秒", "操作用时没有按最多两位小数显示")
        require(operationDurationText(2) == "2.00 秒", "整秒操作用时格式错误")
    }

    private static func testProductionOrderPaths() {
        let model = AppModel()
        model.sourceRoot = "/Volumes/server/Optimized Orders"
        model.orderRoot = "/production/Order"
        model.backupRoot = "/production/Backups"
        require(model.activeOwnedSourceRoot == "/Volumes/server/Optimized Orders", "服务器目录错误")
        require(model.activeCutToSizeRoot == "/Volumes/server/CUT TO SIZE", "来料加工目录错误")
        require(model.activeOrderRoot == "/production/Order", "Traveler 目录错误")
        require(model.activeBackupRoot == "/production/Backups", "备份目录错误")
    }

    private static func testStockFailureKeepsManualRetryEnabled() {
        let model = AppModel()
        model.selectedOrderPath = "/orders/PP0067"
        model.selectedOrderId = "PP0067"
        model.orderMaterials = [
            OrderMaterialPreview(kind: "plywood", thickness: 18, color: "", quantity: 2)
        ]
        model.orderFactories = [OrderFactoryPreview(id: "F0067", factoryOrder: "F0067", orderName: "PP0067")]
        model.orderPreviewValidated = true
        model.orderError = "库存系统登录未成功"
        model.orderRunning = false
        require(model.orderPreviewReady, "库存查询失败不应清除已通过的订单预检状态")
        require(!model.orderRunning && model.orderPreviewReady, "库存查询失败后应允许再次手工点击查询")
    }

    private static func testExistingTravelerCanBeUpdatedAfterPreviewFailure() {
        require(
            orderUpdateActionReady(
                existingTravelerPath: "/orders/PP0067/Work Order Traveler(PP0067).xlsx",
                selectedOrderPath: "/orders/PP0067",
                selectedOrderId: "PP0067"
            ),
            "已有 Traveler 时，即使预览校验失败也应允许执行更新"
        )
        require(
            !orderUpdateActionReady(existingTravelerPath: "", selectedOrderPath: "/orders/PP0067", selectedOrderId: "PP0067"),
            "没有现有 Traveler 时不应绕过生成前校验"
        )
    }

    private static func testDashboardTravelerActionsUseDatabaseFacts() {
        let model = AppModel()
        model.selectedOrderId = "CS005"
        model.orderExistingTravelerPath = ""
        require(model.orderCanGenerateTraveler, "选中订单后应允许从数据库生成 Traveler")

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("traveler-action-\(UUID().uuidString).xlsx")
        FileManager.default.createFile(atPath: temporary.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temporary) }
        require(orderTravelerOpenActionReady(existingTravelerPath: temporary.path), "存在 Traveler 文件时打开按钮应启用")
    }

    private static func testRelatedPreviewMissingMaterialIssue() {
        let response: [String: Any] = [
            "order_id": "PP0067",
            "orders": [],
            "errors": [[
                "order_id": "PP0067",
                "code": "missing_materials",
                "message": "PP0067 根目录找不到文件名包含 material 的 Excel",
            ]],
        ]
        let issues = orderPreviewIssues(response)
        require(issues.count == 1, "preview-related 的 errors 没有被界面识别")
        require(issues[0].orderId == "PP0067", "缺少 material 的订单号解析错误")
        require(issues[0].code == "missing_materials", "缺少 material 的错误码解析错误")
    }

    private static func testPP0067MissingMaterialShowsPrompt() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-ui-missing-material-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("PP0067", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            fail("无法创建缺少 material 的隔离测试目录：\(error)")
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel()
        model.previewOrderFolder(OrderFolderItem(id: folder.path, orderId: "PP0067", modifiedAt: ""))
        let deadline = Date().addingTimeInterval(8)
        while model.orderRunning && Date() < deadline {
            pumpRunLoop(for: 0.05)
        }
        require(!model.orderRunning, "PP0067 后台预览超时")
        require(model.orderError.contains("material"), "PP0067 缺少 material 没有进入错误状态")
        require(model.showMaterialGenerationPrompt, "PP0067 缺少 material 没有显示自动生成提示")
    }

    private static func testFullPageHeaderBoundaryAlignment() {
        let fixedBoundary = headerBoundaryY(flexibleContent: false)
        let flexibleBoundary = headerBoundaryY(flexibleContent: true)
        require(
            abs(fixedBoundary - flexibleBoundary) <= 0.5,
            "完整页面内容高度改变了页头分隔线位置：fixed=\(fixedBoundary), flexible=\(flexibleBoundary)"
        )
    }

    private static func headerBoundaryY(flexibleContent: Bool) -> CGFloat {
        let box = HeaderBoundaryProbeBox()
        let hosting = NSHostingView(rootView: PageLayoutHarness(box: box, flexibleContent: flexibleContent))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: AppLayout.windowMinWidth, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        pumpRunLoop(for: 0.15)
        guard let probe = box.view else { fail("未找到完整页面页头边界探针") }
        let boundary = probe.convert(probe.bounds, to: hosting).maxY
        window.close()
        return boundary
    }

    private static func testOperationLogScrollsAfterAppending() {
        let initial = (0..<8).map { step($0) }
        let model = OperationLogHarnessModel(steps: initial)
        let hosting = NSHostingView(rootView: OperationLogHarnessView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: AppLayout.operationLogHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        pumpRunLoop(for: 0.2)

        guard let scrollView = firstScrollView(in: hosting),
              let documentView = scrollView.documentView else {
            fail("未找到操作记录的 NSScrollView")
        }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        model.steps.append(step(8))
        pumpRunLoop(for: 0.3)
        documentView.layoutSubtreeIfNeeded()

        let visibleBottom = scrollView.contentView.bounds.maxY
        let documentBottom = documentView.bounds.maxY
        require(
            abs(visibleBottom - documentBottom) <= 2,
            "追加记录后未滚动到底部：visible=\(visibleBottom), document=\(documentBottom)"
        )

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let last = model.steps.count - 1
        model.steps[last] = InventoryStep(
            time: model.steps[last].time,
            title: model.steps[last].title,
            detail: "updated detail",
            state: "success"
        )
        pumpRunLoop(for: 0.3)
        documentView.layoutSubtreeIfNeeded()
        require(
            abs(scrollView.contentView.bounds.maxY - documentView.bounds.maxY) <= 2,
            "更新运行中记录后未滚动到底部"
        )
        window.close()
    }

    private static func testOperationLogReader() {
        let line = "{\"event\":\"user.action\",\"message\":\"点击保存设置\",\"timestamp\":\"2026-08-13T15:30:45.123-07:00\"}"
        guard let entry = OperationLogReader.parse(line: line) else {
            fatalError("操作日志 JSONL 读取失败")
        }
        require(entry.operation == "点击保存设置", "操作日志查看页未显示用户可理解的操作内容")
        require(entry.displayTime == "2026-08-13 15:30:45", "操作日志时间未格式化为本地可读格式")
        require(OperationLogReader.parse(line: "不是 JSON") == nil, "无效操作日志行不应导致读取失败")
    }

    private static func traveler(_ name: String, folder: String, modifiedAt: String) -> InventoryTraveler {
        InventoryTraveler(
            id: folder + name,
            ppFolder: folder,
            fileName: name,
            orderName: "",
            modifiedAt: modifiedAt,
            status: "未出库",
            documentNumber: ""
        )
    }

    private static func step(_ index: Int) -> InventoryStep {
        InventoryStep(time: "08:00:\(index)", title: "step \(index)", detail: "detail \(index)", state: "success")
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    private static func pumpRunLoop(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
