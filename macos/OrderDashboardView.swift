import SwiftUI
import AppKit
import UniformTypeIdentifiers

let orderDashboardStatuses = [
    "已设计",
    "已拆单待优化",
    "部分优化",
    "已优化",
    "部分出货",
    "已出货",
    "待人工处理",
    "待确认",
    "数据异常",
]

let orderDashboardMetricColumnCount = 8
let orderDashboardMetricMinimumWidth: CGFloat = 110
let orderDashboardMetricSpacing: CGFloat = 10
// Give the factory identity/status columns practical minimum widths. The
// order-level Panel colors are shown above the table, so the table no longer
// needs a separate color column.
let orderDashboardFactoryColumnWidths: [CGFloat] = [150, 220, 110, 110, 110]
let orderDashboardFactorySelectionColumnWidth: CGFloat = 54
let dashboardMessageVisibleRowCount = 3
let dashboardMessageRowHeight: CGFloat = 74
let dashboardMessageViewportHeight = CGFloat(dashboardMessageVisibleRowCount) * dashboardMessageRowHeight
let dashboardMessageHoverDelay: TimeInterval = 1.0
let dashboardMessageHoverCloseGrace: TimeInterval = 1.2
let orderDashboardMetricColumns = Array(
    repeating: GridItem(.flexible(minimum: orderDashboardMetricMinimumWidth), spacing: orderDashboardMetricSpacing),
    count: orderDashboardMetricColumnCount
)

let orderDetailGridColumnCount = 4
let orderDetailCardMinHeight: CGFloat = 50

func orderDashboardMetricsFit(width: CGFloat, horizontalPadding: CGFloat) -> Bool {
    let cards = CGFloat(orderDashboardMetricColumnCount) * orderDashboardMetricMinimumWidth
    let gaps = CGFloat(orderDashboardMetricColumnCount - 1) * orderDashboardMetricSpacing
    return width - horizontalPadding * 2 >= cards + gaps
}

func orderDashboardPanelColors(_ materials: [OrderMaterialPreview]) -> [String] {
    var result: [String] = []
    for material in materials where material.kind == "panel" {
        let color = material.color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !color.isEmpty, !result.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) else { continue }
        result.append(color)
    }
    return result
}

func orderDetailPlywoodRows(_ rows: [OrderMaterialPreview]) -> [OrderMaterialPreview] {
    orderedMaterialRows(rows.filter { $0.kind == "plywood" })
}

func orderDetailPanelRows(_ rows: [OrderMaterialPreview]) -> [OrderMaterialPreview] {
    rows
        .filter { $0.kind == "panel" }
        .sorted {
            let leftColor = $0.color.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightColor = $1.color.trimmingCharacters(in: .whitespacesAndNewlines)
            let colorOrder = leftColor.localizedStandardCompare(rightColor)
            if colorOrder != .orderedSame { return colorOrder == .orderedAscending }
            if abs($0.thickness - $1.thickness) > 0.01 { return $0.thickness < $1.thickness }
            return $0.quantity < $1.quantity
        }
}

func orderDetailEdgeColors(_ colors: [String]) -> [String] {
    colors.sorted {
        let left = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = $1.trimmingCharacters(in: .whitespacesAndNewlines)
        return left.localizedStandardCompare(right) == .orderedAscending
    }
}

func orderDashboardShortageCount(_ rows: [OrderStockPreview]) -> Int {
    rows.filter { !$0.sufficient }.count
}

func orderDashboardStatus(previewValidated: Bool, hasError: Bool, isExistingTraveler: Bool) -> String {
    if hasError { return "数据异常" }
    if previewValidated { return "已优化" }
    return "待校验"
}

func orderDashboardExpandedID(current: String?, tapped: String, forceOpen: Bool = false) -> String? {
    if !forceOpen, current == tapped { return nil }
    return tapped
}

struct OrderDashboardClickContainer<Content: View>: NSViewRepresentable {
    let content: Content
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    init(
        onSingleClick: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleClick: onSingleClick, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let doubleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleClick)
        )
        doubleClick.numberOfClicksRequired = 2
        let singleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.singleClick)
        )
        singleClick.numberOfClicksRequired = 1
        singleClick.delegate = context.coordinator
        doubleClick.delegate = context.coordinator
        container.addGestureRecognizer(doubleClick)
        container.addGestureRecognizer(singleClick)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSingleClick = onSingleClick
        context.coordinator.onDoubleClick = onDoubleClick
        if let hosting = nsView.subviews.compactMap({ $0 as? NSHostingView<Content> }).first {
            hosting.rootView = content
        }
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var onSingleClick: () -> Void
        var onDoubleClick: () -> Void

        init(onSingleClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) {
            self.onSingleClick = onSingleClick
            self.onDoubleClick = onDoubleClick
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            gestureRecognizer is NSClickGestureRecognizer
                && (gestureRecognizer as? NSClickGestureRecognizer)?.numberOfClicksRequired == 1
                && otherGestureRecognizer is NSClickGestureRecognizer
                && (otherGestureRecognizer as? NSClickGestureRecognizer)?.numberOfClicksRequired == 2
        }

        @objc func singleClick() { onSingleClick() }
        @objc func doubleClick() { onDoubleClick() }
    }
}

func toggledOrderFactorySelection(_ selected: Set<String>, factoryOrder: String) -> Set<String> {
    var next = selected
    if next.contains(factoryOrder) {
        next.remove(factoryOrder)
    } else {
        next.insert(factoryOrder)
    }
    return next
}

func selectedOrderFactoryNames(_ factories: [OrderFactoryPreview], selected: Set<String>) -> [String] {
    factories
        .filter { selected.contains($0.factoryOrder) }
        .map(\.orderName)
        .filter { !$0.isEmpty }
}

func orderDashboardHasShippedSelection(
    _ selected: Set<String>,
    statuses: [String: String]
) -> Bool {
    selected.contains { statuses[$0] == "已出库" }
}

func orderDashboardStageMatchesFilter(_ stage: String, statusFilter: String) -> Bool {
    if statusFilter == "未完成订单" || statusFilter == "全部状态" {
        return stage != "已出货"
    }
    return stage == statusFilter
}

func orderDashboardStatusHelp(status: String, validationMessage: String) -> String {
    guard status == "数据异常" else { return "" }
    let message = validationMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    return message.isEmpty
        ? "订单数据未能通过校验。请检查订单报表后重新扫描 Server。"
        : message
}

func orderDashboardProgressFraction(completed: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    return min(max(Double(completed) / Double(total), 0), 1)
}

private struct OrderDashboardProgressBar: View {
    let completed: Int
    let total: Int

    private var fraction: Double {
        orderDashboardProgressFraction(completed: completed, total: total)
    }

    private var progressColor: Color {
        completed >= total ? AppPalette.success : AppPalette.warning
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppPalette.separator)
                Capsule()
                    .fill(progressColor)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(width: 76, height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("优化进度")
        .accessibilityValue("\(completed) / \(total)")
    }
}

func shouldPresentPendingCenterAfterAimes(
    presentIfNeeded: Bool,
    pendingAimesReviews: [AimesReviewItem]
) -> Bool {
    presentIfNeeded && !pendingAimesReviews.isEmpty
}

struct DashboardMessage: Identifiable {
    let id: String
    let source: String
    let time: String
    let title: String
    let detail: String
    let state: String
    let manualPaths: [String]
    let operationDetails: [String]
    let contextDetails: [String]
    let duration: TimeInterval?
    let operationDurations: [DashboardOperationDuration]

    init(
        id: String,
        source: String,
        time: String,
        title: String,
        detail: String,
        state: String,
        manualPaths: [String] = [],
        operationDetails: [String] = [],
        contextDetails: [String] = [],
        duration: TimeInterval? = nil,
        operationDurations: [DashboardOperationDuration] = []
    ) {
        self.id = id
        self.source = source
        self.time = time
        self.title = title
        self.detail = detail
        self.state = state
        self.manualPaths = Array(Set(manualPaths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
        self.operationDetails = operationDetails
        self.contextDetails = contextDetails
        self.duration = duration
        self.operationDurations = operationDurations
    }
}

struct DashboardOperationDisplay {
    let message: DashboardMessage
    let isRunning: Bool
}

func dashboardMessageState(_ text: String) -> String {
    if text.hasPrefix("❌") { return "failure" }
    if text.hasPrefix("⚠️") { return "warning" }
    if text.hasPrefix("✅") { return "success" }
    return "info"
}

func dashboardMessageDetail(_ text: String) -> String {
    for marker in ["✅", "⚠️", "❌"] where text.hasPrefix(marker) {
        return String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
}

func dashboardStatusIsInProgress(_ text: String) -> Bool {
    let detail = dashboardMessageDetail(text)
    return detail.contains("正在") || detail.contains("处理中")
}

func dashboardMessages(
    syncStatus: String,
    syncTime: String,
    aimesStatus: String,
    aimesTime: String,
    serverStatus: String,
    serverTime: String,
    activity: [InventoryStep],
    operationDetailsBySource: [String: [String]] = [:],
    manualPathsBySource: [String: [String]] = [:],
    contextDetailsBySource: [String: [String]] = [:],
    durationsBySource: [String: TimeInterval] = [:],
    operationDurationsBySource: [String: [DashboardOperationDuration]] = [:]
) -> [DashboardMessage] {
    // When the AIMES status is also copied into syncStatus, prefer the AIMES
    // message so its authoritative duration, stages, and warning details are
    // not discarded by the duplicate-detail filter below.
    let statuses = [
        ("aimes", "AIMES", aimesStatus, aimesTime),
        ("sync", "订单数据", syncStatus, syncTime),
        ("server", "Server", serverStatus, serverTime),
    ]
    var seenDetails: Set<String> = []
    var currentStatuses: [DashboardMessage] = []
    for (source, title, rawDetail, time) in statuses {
        let detail = dashboardMessageDetail(rawDetail).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty, seenDetails.insert(detail).inserted else { continue }
        currentStatuses.append(DashboardMessage(
            id: "status:\(source)",
            source: source,
            time: time,
            title: title,
            detail: detail,
            state: dashboardMessageState(rawDetail),
            manualPaths: manualPathsBySource[source] ?? [],
            operationDetails: operationDetailsBySource[source] ?? [],
            contextDetails: contextDetailsBySource[source] ?? [],
            duration: durationsBySource[source],
            operationDurations: operationDurationsBySource[source] ?? []
        ))
    }
    currentStatuses.sort { ($0.time, $0.id) < ($1.time, $1.id) }
    let history = activity.reversed().map { step in
        DashboardMessage(
            id: "activity:\(step.id.uuidString)",
            source: "activity",
            time: step.time,
            title: step.title,
            detail: step.detail,
            state: step.state,
            manualPaths: step.paths,
            operationDetails: step.operationDetails,
            contextDetails: step.contextDetails,
            duration: step.duration,
            operationDurations: []
        )
    }
    return history + currentStatuses
}

func dashboardVisibleMessages(_ messages: [DashboardMessage], isRunning: Bool) -> [DashboardMessage] {
    guard isRunning else { return messages }
    return messages.filter { !dashboardStatusIsInProgress($0.detail) }
}

func dashboardCurrentOperation(
    messages: [DashboardMessage],
    isRunning: Bool
) -> DashboardOperationDisplay? {
    if isRunning,
       let running = messages.last(where: { dashboardStatusIsInProgress($0.detail) }) {
        return DashboardOperationDisplay(message: running, isRunning: true)
    }
    if let completed = messages.last(where: { ["success", "warning", "failure"].contains($0.state) }) {
        return DashboardOperationDisplay(message: completed, isRunning: false)
    }
    return messages.last.map { DashboardOperationDisplay(message: $0, isRunning: false) }
}

func dashboardMessageScrollKey(_ messages: [DashboardMessage]) -> String {
    messages.map {
        let stageKey = $0.operationDurations
            .map { "\($0.label):\($0.duration)" }
            .joined(separator: ";")
        return "\($0.id)|\($0.time)|\($0.detail)|\($0.operationDetails.joined(separator: "|"))|\($0.contextDetails.joined(separator: "|"))|\($0.duration ?? -1)|\(stageKey)"
    }.joined(separator: "\n")
}

func dashboardMessageDetailText(_ message: DashboardMessage) -> String {
    var detail = message.detail
    if let duration = message.duration {
        detail += "（总用时 \(operationDurationText(duration))）"
    }
    if message.source == "aimes", !message.operationDurations.isEmpty {
        let stages = message.operationDurations.map {
            "\($0.label)：\(operationDurationText($0.duration))"
        }.joined(separator: "；")
        detail += "；阶段：\(stages)"
    }
    return detail
}

func dashboardMessageSummaryText(_ message: DashboardMessage) -> String {
    var summary = message.detail
    if let duration = message.duration {
        summary += "（总计用时 \(operationDurationText(duration))）"
    }
    return summary
}

func dashboardAimesReviewDetail(_ item: AimesReviewItem, status: String) -> String {
    let factoryOrder = item.factoryOrder.isEmpty ? "工厂单号为空" : item.factoryOrder
    let factoryName = item.factoryName.isEmpty ? "名称为空" : item.factoryName
    let salesOrder = item.salesOrderName.isEmpty ? "销售单名称为空" : item.salesOrderName
    var detail = "\(status)：工厂单 \(factoryOrder)，工厂单名称“\(factoryName)”；销售单名称“\(salesOrder)”"
    if !item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        detail += "；原因：\(item.reason)"
    }
    return detail
}

func dashboardAimesActionDetails(
    pending: [AimesReviewItem],
    ignored: [AimesReviewItem],
    assigned: [AimesReviewItem]
) -> [String] {
    var details: [String] = []
    if !pending.isEmpty {
        details.append("待人工确认 \(pending.count) 条：")
        details += pending.map { dashboardAimesReviewDetail($0, status: "待确认") }
    }
    if !ignored.isEmpty {
        details.append("已忽略 \(ignored.count) 条：")
        details += ignored.map { dashboardAimesReviewDetail($0, status: "已忽略") }
    }
    if !assigned.isEmpty {
        details.append("已确认 \(assigned.count) 条：")
        details += assigned.map { dashboardAimesReviewDetail($0, status: "已确认归属") }
    }
    return details
}

func dashboardAimesWarningDetails(_ warnings: [[String: Any]]) -> [String] {
    guard !warnings.isEmpty else { return [] }
    var details = ["销售单格式异常 " + String(warnings.count) + " 条，均未写入数据库："]
    details += warnings.map { warning in
        let factoryOrder = warning["factory_order"] as? String ?? "工厂单号为空"
        let factoryName = warning["factory_name"] as? String ?? "名称为空"
        let salesOrder = warning["sales_order_name"] as? String ?? "销售单名称为空"
        let reason = warning["reason"] as? String ?? "销售单名称格式不符合规则"
        let displayedFactoryOrder = factoryOrder.isEmpty ? "工厂单号为空" : factoryOrder
        let displayedFactoryName = factoryName.isEmpty ? "名称为空" : factoryName
        let displayedSalesOrder = salesOrder.isEmpty ? "销售单名称为空" : salesOrder
        return "工厂单 " + displayedFactoryOrder + "，工厂单名称“" + displayedFactoryName + "”；销售单名称“" + displayedSalesOrder + "”；原因：" + reason
    }
    return details
}

private struct DashboardMessageTracePopover: View {
    let message: DashboardMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if message.state == "warning" || message.state == "failure" {
                    Text("需要人工处理")
                        .font(.headline)
                        .foregroundColor(AppPalette.warning)
                }
                Text(dashboardMessageDetailText(message))
                    .fixedSize(horizontal: false, vertical: true)
                if !message.operationDurations.isEmpty {
                    Text("后台操作耗时")
                        .font(.headline)
                    ForEach(message.operationDurations) { operation in
                        dashboardTraceBullet("\(operation.label)：\(operationDurationText(operation.duration))")
                    }
                }
                if message.manualPaths.isEmpty {
                    Text("当前消息没有可打开的本地文件路径；请按上面的说明处理。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("相关文件或文件夹")
                        .font(.subheadline.weight(.semibold))
                    ForEach(message.manualPaths, id: \.self) { path in
                        Text(path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !message.operationDetails.isEmpty {
                    Text("自动处理详情")
                        .font(.headline)
                    ForEach(message.operationDetails, id: \.self) { detail in
                        dashboardTraceBullet(detail)
                    }
                }
                if !message.contextDetails.isEmpty {
                    Text("相关处理记录")
                        .font(.headline)
                    ForEach(message.contextDetails, id: \.self) { detail in
                        dashboardTraceBullet(detail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 520, alignment: .leading)
        .frame(maxHeight: 560, alignment: .leading)
        .background(AppPalette.surface)
    }

    private func dashboardTraceBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private final class DashboardMessageTraceTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
        super.mouseExited(with: event)
    }
}

private struct DashboardMessageTracePanelPresenter: NSViewRepresentable {
    let message: DashboardMessage
    @Binding var isPresented: Bool
    let onPanelEntered: () -> Void
    let onPanelExited: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            anchorView: nsView,
            message: message,
            isPresented: isPresented,
            onPanelEntered: onPanelEntered,
            onPanelExited: onPanelExited
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject {
        private var panel: NSPanel?
        private var hostingController: NSHostingController<AnyView>?
        private weak var anchorView: NSView?
        private var message: DashboardMessage?
        private var isPresented = false
        private var onPanelEntered: (() -> Void)?
        private var onPanelExited: (() -> Void)?

        func update(
            anchorView: NSView,
            message: DashboardMessage,
            isPresented: Bool,
            onPanelEntered: @escaping () -> Void,
            onPanelExited: @escaping () -> Void
        ) {
            self.anchorView = anchorView
            self.message = message
            self.isPresented = isPresented
            self.onPanelEntered = onPanelEntered
            self.onPanelExited = onPanelExited

            guard isPresented else {
                close()
                return
            }
            presentIfNeeded()
            if panel != nil {
                updatePosition()
            }
        }

        private func presentIfNeeded() {
            guard panel == nil,
                  let message,
                  let anchorView,
                  anchorView.window != nil else { return }
            let hostingController = NSHostingController(
                rootView: AnyView(
                    DashboardMessageTracePopover(
                        message: message
                    )
                )
            )
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            panel.setContentSize(NSSize(width: 520, height: max(120, fittingSize.height)))

            let trackingView = DashboardMessageTraceTrackingView(frame: panel.contentView?.bounds ?? .zero)
            trackingView.autoresizingMask = [.width, .height]
            trackingView.onMouseEntered = { [weak self] in self?.onPanelEntered?() }
            trackingView.onMouseExited = { [weak self] in self?.onPanelExited?() }
            hostingController.view.frame = trackingView.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            trackingView.addSubview(hostingController.view)
            panel.contentView = trackingView

            self.hostingController = hostingController
            self.panel = panel
            updatePosition()
            panel.orderFront(nil)
        }

        private func updatePosition() {
            guard let panel, let anchorView, anchorView.window != nil else { return }
            // Keep the message row as the hover lifetime anchor. Placement is
            // intentionally pointer-based below for the established UI
            // behavior; the close grace and panel tracking prevent small
            // pointer movements from closing the detail immediately.
            let screenPoint = NSEvent.mouseLocation
            let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let gap: CGFloat = 14
            // Keep the previous placement behavior: position relative to the
            // current pointer and flip left/right when the screen edge clips
            // the panel. The row remains the hover lifetime anchor.
            var originX = screenPoint.x + gap
            var originY = screenPoint.y - panel.frame.height - gap
            if originX + panel.frame.width > visibleFrame.maxX {
                originX = screenPoint.x - panel.frame.width - gap
            }
            if originY < visibleFrame.minY {
                originY = screenPoint.y + gap
            }
            originX = min(max(originX, visibleFrame.minX + 8), visibleFrame.maxX - panel.frame.width - 8)
            originY = min(max(originY, visibleFrame.minY + 8), visibleFrame.maxY - panel.frame.height - 8)
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        func close() {
            panel?.orderOut(nil)
            panel = nil
            hostingController = nil
        }

        deinit {
            close()
        }
    }
}

private struct DashboardMessageTraceHost<Content: View>: View {
    let message: DashboardMessage
    @Binding var activeMessageID: String?
    @ViewBuilder let content: () -> Content
    @State private var anchorHovering = false
    @State private var panelHovering = false
    @State private var showPopover = false
    @State private var hoverGeneration = 0

    var body: some View {
        content()
            // Keep the hover tracking area at the full row width instead of
            // the content's intrinsic width.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    beginHover()
                } else {
                    endHover()
                }
            }
            .onChange(of: activeMessageID) { _, activeID in
                guard activeID != message.id else { return }
                anchorHovering = false
                panelHovering = false
                hoverGeneration += 1
                showPopover = false
            }
            .background(
                DashboardMessageTracePanelPresenter(
                    message: message,
                    isPresented: $showPopover,
                    onPanelEntered: panelEntered,
                    onPanelExited: panelExited
                )
            )
    }

    private func beginHover() {
        guard !anchorHovering else { return }
        activeMessageID = message.id
        anchorHovering = true
        showPopover = false
        hoverGeneration += 1
        let generation = hoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + dashboardMessageHoverDelay) {
            guard generation == hoverGeneration, anchorHovering else { return }
            showPopover = true
        }
    }

    private func endHover() {
        guard activeMessageID == message.id else { return }
        anchorHovering = false
        hoverGeneration += 1
        schedulePopoverClose()
    }

    private func schedulePopoverClose() {
        let generation = hoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + dashboardMessageHoverCloseGrace) {
            guard generation == hoverGeneration, !panelHovering else { return }
            showPopover = false
            if activeMessageID == message.id {
                activeMessageID = nil
            }
        }
    }

    private func panelEntered() {
        guard activeMessageID == nil || activeMessageID == message.id else { return }
        activeMessageID = message.id
        panelHovering = true
        hoverGeneration += 1
    }

    private func panelExited() {
        guard activeMessageID == message.id else { return }
        panelHovering = false
        hoverGeneration += 1
        schedulePopoverClose()
    }
}

struct OrderDashboardView: View {
    @ObservedObject var model: AppModel
    @State private var expandedOrderID: String?
    @State private var detailOrder: OrderDashboardItem?
    @State private var selectedFactoryID: String?
    @State private var selectedFactoryIDs: Set<String> = []
    @State private var searchText = ""
    @State private var statusFilter = "未完成订单"
    @State private var showFactoryStock = false
    @State private var showInventoryWorkspace = false
    @State private var showOutboundScope = false
    @State private var showServerFolderImporter = false
    @State private var activeMessageID: String?

    private var filteredOrders: [OrderDashboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.dashboardOrders.filter { item in
            let factoryText = item.factories.map { "\($0.factoryOrder) \($0.orderName)" }.joined(separator: " ")
            let matchesQuery = query.isEmpty || item.orderId.lowercased().contains(query) || item.sourceFolder.lowercased().contains(query) || factoryText.lowercased().contains(query)
            let matchesStatus = orderDashboardStageMatchesFilter(item.stage, statusFilter: statusFilter)
            return matchesQuery && matchesStatus
        }
    }

    private var selectedFactory: OrderFactoryPreview? {
        model.orderFactories.first { $0.factoryOrder == selectedFactoryID }
    }

    private var selectedOutboundFactories: [OrderFactoryPreview] {
        model.orderFactories.filter { selectedFactoryIDs.contains($0.factoryOrder) }
    }

    @ViewBuilder
    private func traceHost<Content: View>(
        for message: DashboardMessage,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if !dashboardStatusIsInProgress(message.detail),
           (message.state == "warning" || message.state == "failure"
            || !message.manualPaths.isEmpty
            || !message.operationDetails.isEmpty
            || !message.contextDetails.isEmpty) {
            DashboardMessageTraceHost(
                message: message,
                activeMessageID: $activeMessageID,
                content: content
            )
        } else {
            content()
        }
    }

    var body: some View {
        dashboardSections
            .padding(AppLayout.contentPadding)
        .appPageFrame()
        .onAppear { model.startOrderDashboard() }
        .sheet(item: $detailOrder) { item in
            OrderDashboardDetailPage(
                model: model,
                order: item
            )
            .frame(minWidth: 960, minHeight: 680)
        }
        .sheet(isPresented: $model.showCostSheet) {
            OrderCostSheet(model: model)
                .frame(minWidth: 780, idealWidth: 980, minHeight: 560, idealHeight: 720)
        }
        .sheet(isPresented: $showFactoryStock) {
            FactoryStockComparisonSheet(
                model: model,
                orderID: model.selectedOrderId
            )
            .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 640)
        }
        .sheet(isPresented: $showInventoryWorkspace) {
            InventoryView(
                model: model,
                onClose: { showInventoryWorkspace = false },
                orderContextID: model.selectedOrderId,
                orderContextFactoryNames: selectedOutboundFactories.map(\.orderName),
                orderContextFactoryOrders: selectedFactoryIDs.sorted()
            )
                .frame(width: AppLayout.inventoryOrderContextWidth, height: 720)
        }
        .sheet(isPresented: $showOutboundScope) {
            OutboundScopeSheet(
                model: model,
                orderID: model.selectedOrderId,
                orderType: model.dashboardOrders.first(where: { $0.orderId == model.selectedOrderId })?.orderType ?? "owned",
                factoryOrders: selectedFactoryIDs.sorted()
            )
            .frame(width: 520, height: 430)
        }
        .alert(
            "AIMES 获取失败",
            isPresented: Binding(
                get: { !model.aimesFailureAlert.isEmpty },
                set: { if !$0 { model.aimesFailureAlert = "" } }
            )
        ) {
            Button("知道了") { model.aimesFailureAlert = "" }
        } message: {
            Text("本次未能获取最新 AIMES 数据，Server 扫描将继续使用最近一次成功缓存。\n\n\(model.aimesFailureAlert)")
        }
        .fileImporter(
            isPresented: $showServerFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let folder = urls.first else { return }
            model.prepareSelectedServerFolder(folder)
        }
        .sheet(isPresented: $model.showServerProcessingOptions) {
            ServerProcessingOptionsSheet(model: model)
                .frame(width: 520, height: 300)
        }
    }

    private var dashboardSections: some View {
        VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
            toolbar
            dashboardActivityLog
            orderTable
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索订单号、工厂单号或工厂单名称", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: 360, height: AppLayout.controlHeight)
            .background(AppPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.separator))

            Picker("状态", selection: $statusFilter) {
                Text("未完成订单").tag("未完成订单")
                ForEach(orderDashboardStatuses, id: \.self) { status in
                    Text(status).tag(status)
                }
            }
            .labelsHidden()
            .frame(width: 130, height: AppLayout.controlHeight)

            Spacer(minLength: 0)
            Button {
                model.syncDashboardAimes(force: true)
            } label: {
                Label("获取 AIMES", systemImage: "arrow.triangle.2.circlepath")
            }
            .appActionButton(minWidth: 126)
            .disabled(model.orderRunning)
            if !model.aimesFormatWarnings.isEmpty
                || !model.pendingAimesReviews.isEmpty
                || !model.assignedAimesFactories.isEmpty {
                Button {
                    model.showAimesReviewPrompt = true
                } label: {
                    Label("处理 AIMES 异常", systemImage: "person.crop.circle.badge.questionmark")
                }
                .appActionButton(minWidth: 138)
                .disabled(model.orderRunning)
            }
            Button {
                model.scanDashboardServer()
            } label: {
                Label("扫描 Server", systemImage: "externaldrive")
            }
            .appActionButton(minWidth: 132)
            .disabled(model.orderRunning)
            Button {
                showServerFolderImporter = true
            } label: {
                Label("处理文件夹", systemImage: "folder.badge.gearshape")
            }
            .appActionButton(minWidth: 132)
            .disabled(model.orderRunning)
        }
    }

    private var dashboardActivityLog: some View {
        let serverGroups = serverFolderChangeGroups(model.pendingServerChanges)
        let aimesManualPaths = (
            model.pendingAimesReviews + model.ignoredAimesFactories + model.assignedAimesFactories
        ).map(\.sourcePath)
        let serverManualPaths = model.pendingServerChanges.map(\.path)
        // The sync status row represents the latest warning/error. Attach only
        // that activity's file path; do not aggregate paths from unrelated
        // Server/AIMES operations into the hovered message.
        let latestActivityPaths = model.dashboardActivity.first {
            $0.state == "failure" || $0.state == "warning"
        }?.paths ?? []
        let aimesActionDetails: [String] = dashboardStatusIsInProgress(model.dashboardAimesStatus)
            ? []
            : dashboardAimesActionDetails(
                pending: model.pendingAimesReviews,
                ignored: model.ignoredAimesFactories,
                assigned: model.assignedAimesFactories
            ) + dashboardAimesWarningDetails(model.aimesWarnings)
        let serverActionDetails: [String] = {
            if dashboardStatusIsInProgress(model.dashboardServerStatus) {
                return []
            }
            if model.pendingServerChanges.isEmpty {
                return ["Server 已完成扫描，当前没有新增、修改或删除的订单文件。"]
            }
            return ["待处理 Server 变化 \(serverGroups.count) 个文件夹："] + serverGroups.map {
                let handling = $0.manualOnly ? "（临时文件夹）" : ""
                let names = $0.changes.map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: "、")
                return "\($0.folderName)\(handling)：\(names)"
            }
        }()
        let messages = dashboardMessages(
            syncStatus: model.dashboardSyncStatus,
            syncTime: model.dashboardSyncStatusTime,
            aimesStatus: model.dashboardAimesStatus,
            aimesTime: model.dashboardAimesStatusTime,
            serverStatus: model.dashboardServerStatus,
            serverTime: model.dashboardServerStatusTime,
            activity: model.dashboardActivity,
            operationDetailsBySource: model.dashboardOperationDetails,
            manualPathsBySource: [
                "sync": latestActivityPaths,
                "aimes": aimesManualPaths,
                "server": serverManualPaths,
            ],
            contextDetailsBySource: [
                "sync": [],
                "aimes": aimesActionDetails,
                "server": serverActionDetails,
            ],
            durationsBySource: model.dashboardOperationDurations,
            operationDurationsBySource: model.dashboardOperationStageDurations
        )
        let visibleMessages = dashboardVisibleMessages(messages, isRunning: model.orderRunning)
        let currentOperation = dashboardCurrentOperation(messages: messages, isRunning: model.orderRunning)
        let scrollKey = dashboardMessageScrollKey(visibleMessages)
        return AppSurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                currentOperationRow(currentOperation)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if visibleMessages.isEmpty {
                                Text("暂无订单消息")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: dashboardMessageViewportHeight, alignment: .topLeading)
                                    .padding(12)
                            } else {
                                ForEach(visibleMessages) { message in
                                    traceHost(for: message) {
                                        HStack(alignment: .center, spacing: 10) {
                                        Image(systemName: activityIcon(message.state))
                                            .foregroundColor(activityColor(message.state))
                                            .frame(width: 20, height: 22)
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 10) {
                                                Text(message.title)
                                                    .font(.callout.weight(.semibold))
                                                Spacer(minLength: 0)
                                                Text(message.time)
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(dashboardMessageDetailText(message))
                                                .font(.callout)
                                                .foregroundColor(message.state == "failure" ? AppPalette.danger : .primary)
                                                .lineLimit(message.source == "aimes" ? 2 : 1)
                                        }
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: dashboardMessageRowHeight)
                                    }
                                    .id(message.id)
                                    if message.id != visibleMessages.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    .frame(height: dashboardMessageViewportHeight)
                    .onAppear { scrollMessagesToBottom(proxy, messages: messages) }
                    .onChange(of: scrollKey) { _, _ in
                        scrollMessagesToBottom(proxy, messages: messages)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentOperationRow(_ display: DashboardOperationDisplay?) -> some View {
        if let display {
            HStack(spacing: 10) {
                currentOperationIcon(display)
                Text(display.isRunning ? "当前操作" : "最近结果")
                    .font(.callout.weight(.semibold))
                Text(dashboardMessageSummaryText(display.message))
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(display.message.time)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(AppPalette.subtleSurface)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "pause.circle.fill").foregroundColor(.secondary)
                Text("当前无正在进行的操作").font(.callout).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(AppPalette.subtleSurface)
        }
    }

    @ViewBuilder
    private func currentOperationIcon(_ display: DashboardOperationDisplay) -> some View {
        if display.isRunning {
            TimelineView(.animation) { context in
                let degrees = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1) * 360
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(AppPalette.accent)
                    .rotationEffect(.degrees(degrees))
                    .frame(width: 20)
                    .accessibilityLabel("操作进行中")
            }
        } else {
            Image(systemName: activityIcon(display.message.state))
                .foregroundColor(activityColor(display.message.state))
                .frame(width: 20)
        }
    }

    private func scrollMessagesToBottom(_ proxy: ScrollViewProxy, messages: [DashboardMessage]) {
        guard let lastID = messages.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func activityIcon(_ state: String) -> String {
        switch state {
        case "failure": return "xmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "success": return "checkmark.circle.fill"
        default: return "info.circle.fill"
        }
    }

    private func activityColor(_ state: String) -> Color {
        switch state {
        case "failure": return AppPalette.danger
        case "warning": return AppPalette.warning
        case "success": return AppPalette.success
        default: return AppPalette.accent
        }
    }

    private var orderTable: some View {
        AppSurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                orderTableHeader
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredOrders.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("没有符合条件的订单").fontWeight(.semibold)
                                Text("请调整搜索或状态筛选条件").font(.caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            ForEach(filteredOrders) { item in
                                orderRow(item)
                                if item.id != filteredOrders.last?.id { Divider() }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var orderTableHeader: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 40)
            tableHeader("订单")
            tableHeader("状态")
            tableHeader("工厂单")
            tableHeader("优化进度")
            tableHeader("材料")
            tableHeader("出货进度")
            tableHeader("更新时间")
            tableHeader("操作")
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.vertical, 11)
        .background(AppPalette.subtleSurface)
    }

    private func orderRow(_ item: OrderDashboardItem) -> some View {
        let isExpanded = expandedOrderID == item.orderId
        let isSelected = model.selectedOrderId.caseInsensitiveCompare(item.orderId) == .orderedSame
            && model.selectedOrderPath == item.sourceFolder
        let status = item.stage
        return VStack(spacing: 0) {
            OrderDashboardClickContainer(
                onSingleClick: { toggleExpanded(item) },
                onDoubleClick: { openOrderDetail(item) }
            ) {
                HStack(spacing: 0) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 28, height: 28)
                        .frame(width: 40)

                    tableCell {
                        VStack(spacing: 3) {
                            Text(item.orderId).font(.headline).foregroundColor(AppPalette.accent)
                            Text(item.orderType == "cutToSize" ? "来料加工" : (item.orderType == "temporary" ? "临时任务" : "自有订单"))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    tableCell {
                        AppStatusBadge(text: status, kind: statusKind(status))
                            .help(orderDashboardStatusHelp(
                                status: status,
                                validationMessage: item.validationMessage
                            ))
                    }
                    tableCell {
                        Text(item.factoryCount > 0 ? "\(item.factoryCount)" : "—")
                            .fontWeight(.semibold)
                    }
                    tableCell {
                        VStack(spacing: 4) {
                            Text(item.optimizationProgress)
                                .fontWeight(.semibold)
                            if item.factoryCount > 0 {
                                OrderDashboardProgressBar(
                                    completed: item.optimizedCount,
                                    total: item.factoryCount
                                )
                            }
                        }
                    }
                    tableCell {
                        VStack(spacing: 3) {
                            Text(item.materialStatus)
                            if !item.validationStatus.isEmpty { Text(item.validationStatus).font(.caption2).foregroundColor(.secondary) }
                        }
                    }
                    tableCell {
                        VStack(spacing: 3) {
                            Text(item.outboundProgress)
                            if item.factoryCount > 0 {
                                Text(item.shippedCount == item.factoryCount ? "已出库" : item.shippedCount > 0 ? "部分出库" : "未出库")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    tableCell {
                        Text(item.modifiedAt.isEmpty ? "—" : appDisplayTimestamp(item.modifiedAt)).lineLimit(1)
                    }
                    tableCell {
                        Text(isExpanded ? "收起详情" : "查看详情")
                        .foregroundColor(AppPalette.accent)
                    }
                }
                .padding(.vertical, 11)
                .background(isSelected ? AppPalette.accent.opacity(0.045) : AppPalette.surface)
                .contentShape(Rectangle())
            }

            if isExpanded {
                OrderDashboardDetailCard(
                    model: model,
                    dashboardFactories: item.factories,
                    selectedFactoryID: $selectedFactoryID,
                    selectedFactoryIDs: $selectedFactoryIDs,
                    onQueryStock: { showFactoryStock = true; model.checkSelectedOrderStock() },
                    onOpenOutbound: { showInventoryWorkspace = true },
                    onOpenScope: { showOutboundScope = true },
                    orderType: item.orderType
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func prepareSelectedOrder(_ item: OrderDashboardItem) {
        selectedFactoryID = nil
        selectedFactoryIDs = []
        model.selectedOrderIsOptimized = item.stage == "已优化"
        model.loadOrderDetailFromDatabase(item)
    }

    private func toggleExpanded(_ item: OrderDashboardItem) {
        let next = orderDashboardExpandedID(current: expandedOrderID, tapped: item.orderId)
        expandedOrderID = next
        guard next != nil else { return }
        prepareSelectedOrder(item)
    }

    private func openOrderDetail(_ item: OrderDashboardItem) {
        prepareSelectedOrder(item)
        detailOrder = item
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title).frame(maxWidth: .infinity, alignment: .center)
    }

    private func tableCell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private func statusKind(_ status: String) -> AppStatusBadge.Kind {
        switch status {
        case "已优化", "部分出货", "已出货": return .info
        case "数据异常": return .danger
        case "部分优化", "待确认": return .warning
        default: return .neutral
        }
    }
}

struct OrderDashboardMetricsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let shortageCount = orderDashboardShortageCount(model.orderStockRows)
        LazyVGrid(columns: orderDashboardMetricColumns, spacing: orderDashboardMetricSpacing) {
            metric("全部订单", "\(model.dashboardOrders.count)", .primary)
            metric("已设计", "\(model.dashboardOrders.filter { $0.stage == "已设计" }.count)", .secondary)
            metric("待优化", "\(model.dashboardOrders.filter { $0.stage == "已拆单待优化" || $0.stage == "部分优化" }.count)", .secondary)
            metric("已优化", "\(model.dashboardOrders.filter { $0.stage == "已优化" || $0.stage == "部分出货" || $0.stage == "已出货" }.count)", AppPalette.accent)
            metric("库存不足", "\(shortageCount)", shortageCount > 0 ? AppPalette.danger : AppPalette.success)
            metric("部分出货", "\(model.dashboardOrders.filter { $0.stage == "部分出货" }.count)", AppPalette.warning)
            metric("已出货", "\(model.dashboardOrders.filter { $0.stage == "已出货" }.count)", AppPalette.success)
            metric("数据异常", "\(model.dashboardOrders.filter { $0.stage == "数据异常" || $0.stage == "待确认" }.count)", model.dashboardOrders.contains { $0.stage == "数据异常" || $0.stage == "待确认" } ? AppPalette.danger : .primary)
        }
        .onAppear { model.startOrderDashboard() }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        AppSurfaceCard(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(value).font(.title2.weight(.semibold)).foregroundColor(color)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        }
    }
}

struct OrderDashboardDetailPage: View {
    @ObservedObject var model: AppModel
    let order: OrderDashboardItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                orderIdentityCard
                if model.orderDetailWaiting,
                   model.selectedOrderId.caseInsensitiveCompare(order.orderId) == .orderedSame {
                    AppSurfaceCard(padding: 12) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在扫描，扫描完成后自动读取详情")
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                boardAndEdgeSection
                ScrollView(.vertical) {
                    hardwareSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(
                width: min(max(0, geometry.size.width - AppLayout.contentPadding * 2), 1120),
                height: max(0, geometry.size.height - AppLayout.contentPadding * 2),
                alignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, AppLayout.contentPadding)
        }
        .appPageFrame()
    }

    private var orderIdentityCard: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                Text("订单 (\(order.orderId))")
                    .font(.title2.weight(.semibold))
                AppStatusBadge(text: order.stage, kind: order.stage == "数据异常" ? .danger : .info)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("生成 Traveler") { model.generateSelectedOrder() }
                    .buttonStyle(.borderedProminent)
                    .appActionButton(minWidth: 112)
                    .disabled(!model.orderCanGenerateTraveler)
                Button("关闭") { dismiss() }
                    .appActionButton(minWidth: 80)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var boardAndEdgeSection: some View {
        AppSurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("板材与封边")
                    .font(.headline)
                    .foregroundColor(AppPalette.accent)
                if model.orderMaterials.isEmpty && model.orderEdgeBanding.isEmpty {
                    Text("数据库中暂无材料明细")
                        .foregroundColor(.secondary)
                } else {
                    materialRow(title: "Plywood", rows: orderDetailPlywoodRows(model.orderMaterials))
                    materialRow(title: "Panel", rows: orderDetailPanelRows(model.orderMaterials))
                    edgeBandingRow
                }
            }
        }
    }

    @ViewBuilder
    private func materialRow(title: String, rows: [OrderMaterialPreview]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: orderDetailGridColumnCount),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(rows) { row in
                        orderDetailCard(
                            name: orderMaterialDisplayName(row),
                            subtitle: "\(row.thickness.formatted())mm",
                            value: row.quantity.formatted()
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var edgeBandingRow: some View {
        let colors = orderDetailEdgeColors(Array(model.orderEdgeBanding.keys))
        if !colors.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("封边条")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: orderDetailGridColumnCount),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(colors, id: \.self) { color in
                        orderDetailCard(
                            name: color.isEmpty ? "封边" : color,
                            subtitle: "Edge Banding",
                            value: "\((model.orderEdgeBanding[color] ?? 0).formatted()) m"
                        )
                    }
                }
            }
        }
    }

    private var hardwareSection: some View {
        AppSurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("五金")
                    .font(.headline)
                    .foregroundColor(AppPalette.accent)
                VStack(alignment: .leading, spacing: 12) {
                    if model.orderFactories.isEmpty {
                        hardwareFactorySection(title: "暂无工厂单", rows: [])
                    } else {
                        ForEach(model.orderFactories) { factory in
                            hardwareFactorySection(
                                title: "\(factory.factoryOrder) · \(factory.orderName)",
                                rows: model.orderFittings.filter { $0.factoryOrder == factory.factoryOrder }
                            )
                        }
                    }
                }
            }
        }
    }

    private func hardwareFactorySection(title: String, rows: [OrderFittingPreview]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: orderDetailGridColumnCount),
                alignment: .leading,
                spacing: 10
            ) {
                if rows.isEmpty {
                    orderDetailCard(name: "暂无五金", subtitle: "", value: "—")
                } else {
                    ForEach(rows) { row in
                        orderDetailCard(
                            name: row.name.isEmpty ? row.code : row.name,
                            subtitle: "",
                            value: row.quantity.formatted()
                        )
                    }
                }
            }
        }
    }

    private func orderDetailCard(name: String, subtitle: String, value: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(AppPalette.accent)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: orderDetailCardMinHeight, alignment: .leading)
        .background(AppPalette.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OrderDashboardDetailCard: View {
    @ObservedObject var model: AppModel
    let dashboardFactories: [OrderDashboardFactory]
    @Binding var selectedFactoryID: String?
    @Binding var selectedFactoryIDs: Set<String>
    let onQueryStock: () -> Void
    let onOpenOutbound: () -> Void
    let onOpenScope: () -> Void
    let orderType: String

    var body: some View {
        AppSurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                detailActions
                factoriesPanel
            }
        }
    }

    private var detailActions: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Button("查询库存") { onQueryStock() }
                    .appActionButton(minWidth: 96)
                    .disabled(model.selectedOrderId.isEmpty || model.orderRunning || !model.orderPreviewReady)
                Button("计算成本") {
                    model.calculateSelectedOrderCost()
                }
                .appActionButton(minWidth: 96)
                .disabled(model.selectedOrderId.isEmpty || model.orderRunning)
                Button("设置出库范围") { onOpenScope() }
                    .appActionButton(minWidth: 112)
                    .disabled(model.selectedOrderId.isEmpty || model.orderRunning)
                Button("创建出库") { onOpenOutbound() }
                    .buttonStyle(.borderedProminent)
                    .appActionButton(minWidth: 96)
                    .disabled(
                        selectedFactoryIDs.isEmpty
                        || orderDashboardHasShippedSelection(
                            selectedFactoryIDs,
                            statuses: Dictionary(uniqueKeysWithValues: dashboardFactories.map {
                                ($0.factoryOrder, $0.outboundStatus)
                            })
                        )
                    )
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            panelColorsSummary
        }
    }

    private var panelColorsSummary: some View {
        let colors = orderDashboardPanelColors(model.orderMaterials)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Panel颜色")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Text(colors.isEmpty ? "—" : colors.joined(separator: "、"))
                .font(.title3.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var factoriesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            factoryTable
        }
    }

    private var factoryTable: some View {
        VStack(spacing: 0) {
            factoryTableRow(isHeader: true, factory: nil)
            Divider()
            ForEach(dashboardFactories) { factory in
                Button {
                    selectedFactoryIDs = toggledOrderFactorySelection(
                        selectedFactoryIDs,
                        factoryOrder: factory.factoryOrder
                    )
                    selectedFactoryID = selectedFactoryIDs.sorted().first
                } label: {
                    factoryTableRow(
                        isHeader: false,
                        dashboardFactory: factory,
                        selected: selectedFactoryIDs.contains(factory.factoryOrder)
                    )
                }
                .buttonStyle(.plain)
                .disabled(factory.outboundStatus == "已出库")
                .help(factory.outboundStatus == "已出库" ? "该工厂单已出库，不能重复出库" : "选择该工厂单")
                .background(selectedFactoryIDs.contains(factory.factoryOrder) ? AppPalette.accent.opacity(0.10) : Color.clear)
                Divider()
            }
        }
        .background(AppPalette.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.separator))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func factoryTableRow(
        isHeader: Bool,
        factory: OrderFactoryPreview? = nil,
        dashboardFactory: OrderDashboardFactory? = nil,
        selected: Bool = false
    ) -> some View {
        let factoryOrder = dashboardFactory?.factoryOrder ?? factory?.factoryOrder ?? ""
        let factoryName = dashboardFactory?.orderName ?? factory?.orderName ?? ""
        let optimization = dashboardFactory == nil
            ? (model.orderPreviewValidated ? "已优化" : "待校验")
            : (dashboardFactory?.optimized == true ? "已优化" : "待优化")
        let outbound = dashboardFactory?.outboundStatus ?? "未查询"
        HStack(spacing: 0) {
            Image(systemName: isHeader ? "square" : (selected ? "checkmark.square.fill" : "square"))
                .font(.system(size: isHeader ? 1 : 20, weight: .medium))
                .foregroundColor(selected ? AppPalette.accent : .secondary)
                .opacity(isHeader ? 0 : 1)
                .frame(width: orderDashboardFactorySelectionColumnWidth, alignment: .center)
            factoryCell(isHeader ? "工厂单" : factoryOrder, width: orderDashboardFactoryColumnWidths[0])
            factoryCell(isHeader ? "名称" : factoryName, width: orderDashboardFactoryColumnWidths[1])
            factoryCell(isHeader ? "拆单" : "已拆单", width: orderDashboardFactoryColumnWidths[2], status: !isHeader)
            factoryCell(isHeader ? "优化" : optimization, width: orderDashboardFactoryColumnWidths[3], status: !isHeader && optimization == "已优化")
            factoryCell(isHeader ? "出库" : outbound, width: orderDashboardFactoryColumnWidths[4], status: !isHeader && outbound == "已出库")
        }
        .font(isHeader ? .caption.weight(.semibold) : .caption)
        .foregroundColor(isHeader ? .secondary : .primary)
        .padding(.vertical, isHeader ? 9 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func factoryCell(_ text: String, width: CGFloat? = nil, status: Bool = false) -> some View {
        HStack(spacing: 5) {
            if status { Circle().fill(AppPalette.success).frame(width: 7, height: 7) }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .frame(minWidth: width ?? 0, maxWidth: width ?? .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

}

struct OutboundScopeSheet: View {
    @ObservedObject var model: AppModel
    let orderID: String
    let orderType: String
    let factoryOrders: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var scopeType = "material"
    @State private var requirement = "required"
    @State private var factoryOrder = ""
    @State private var reason = ""

    private var incomingProcessing: Bool { orderType == "cutToSize" }
    private var noOutboundDecision: Bool {
        requirement == "customer_supplied" || requirement == "remainder" || requirement == "not_required"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置出库范围").font(.title2.weight(.semibold))
            Text("先保留订单文件读取的材料事实，再单独决定哪些项目进入出库单。数据库没有材料时不会自动判定为余料生产。")
                .font(.caption).foregroundColor(.secondary)
            Picker("范围", selection: $scopeType) {
                Text("板材与封边").tag("material")
                Text("五金").tag("hardware")
            }
            .pickerStyle(.segmented)
            if scopeType == "hardware" {
                Picker("工厂单", selection: $factoryOrder) {
                    Text("请选择工厂单").tag("")
                    ForEach(factoryOrders, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("出库决定", selection: $requirement) {
                Text("需要出库").tag("required")
                if scopeType == "material" && incomingProcessing {
                    Text("客户提供，不出库").tag("customer_supplied")
                }
                Text("余料生产，不出库").tag("remainder")
                Text("其他原因，不出库").tag("not_required")
            }
            .pickerStyle(.radioGroup)
            if noOutboundDecision {
                TextField("必须填写原因，例如：客户提供板材和封边", text: $reason)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    model.saveOutboundScope(
                        orderID: orderID,
                        scopeType: scopeType,
                        requirement: requirement,
                        factoryOrder: factoryOrder,
                        reason: reason
                    ) { success in
                        if success { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.inventoryRunning || orderID.isEmpty || (scopeType == "hardware" && factoryOrder.isEmpty) || (noOutboundDecision && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(22)
        .onChange(of: scopeType) { _, value in
            if value == "hardware" && requirement == "customer_supplied" { requirement = "required" }
            if value == "material" { factoryOrder = "" }
        }
    }
}

struct PendingCenterSheet: View {
    @ObservedObject var model: AppModel
    @State private var expandedIDs: Set<String> = []
    @State private var orderIDs: [String: String] = [:]

    private var items: [PendingCenterItem] { model.pendingCenterItems }
    private var serverItems: [PendingCenterItem] { items.filter { $0.serverGroup != nil } }
    private var selectedServerCount: Int {
        serverItems.filter {
            model.selectedServerFolderPaths.contains($0.folderPath) && !($0.serverGroup?.requiresManualReview ?? false)
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("待处理中心")
                        .font(.title2.weight(.semibold))
                    Text("Server 文件夹、订单问题和 AIMES 待确认统一显示；后台仍按待扫描处理、需人工确认和处理失败分别保留状态。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                AppStatusBadge(text: "\(items.count) 项", kind: .warning)
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "当前没有待处理项目",
                    systemImage: "checkmark.circle",
                    description: Text("Server 扫描、订单校验和 AIMES 获取后会自动更新这里。")
                )
            } else {
                AppSurfaceCard(padding: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                pendingItemRow(item)
                                if item.id != items.last?.id { Divider() }
                            }
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Text("文件夹按一条主记录显示；展开后查看文件变化、失败原因和人工确认动作。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("出库包含五金件", isOn: $model.includeHardwareForServerProcessing)
                    .toggleStyle(.checkbox)
                    .help("关闭后，Traveler 不写入五金，出库也不会包含五金")
                if !model.pendingAimesReviews.isEmpty && !model.selectedAimesReviewIDs.isEmpty {
                    Button("忽略选中的 AIMES") { model.ignoreSelectedAimesFactories() }
                        .buttonStyle(.bordered)
                        .disabled(model.orderRunning)
                }
                Button("稍后处理") { model.showPendingCenterPrompt = false }
                    .appActionButton(minWidth: 108)
                    // Closing the informational sheet must remain available
                    // while background AIMES/Server work is running.
                    .disabled(false)
                Button("自动处理已选文件夹") { model.processPendingServerChanges() }
                    .buttonStyle(.borderedProminent)
                    .appActionButton(minWidth: 150)
                    .disabled(model.orderRunning || selectedServerCount == 0)
            }
        }
        .padding(20)
        .background(AppPalette.background)
    }

    @ViewBuilder
    private func pendingItemRow(_ item: PendingCenterItem) -> some View {
        let expanded = expandedIDs.contains(item.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                if let serverGroup = item.serverGroup, !serverGroup.requiresManualReview {
                    let selected = model.selectedServerFolderPaths.contains(item.folderPath)
                    Button {
                        model.toggleServerFolderSelection(item.folderPath)
                    } label: {
                        Image(systemName: selected ? "checkmark.square.fill" : "square")
                            .foregroundColor(selected ? AppPalette.accent : .secondary)
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("选择此文件夹自动处理")
                } else {
                    Image(systemName: item.status == "需人工确认" ? "person.crop.circle.badge.questionmark" : "exclamationmark.triangle.fill")
                        .foregroundColor(item.status == "需人工确认" ? AppPalette.warning : AppPalette.danger)
                        .frame(width: 24, height: 24)
                }

                Button {
                    if expanded { expandedIDs.remove(item.id) } else { expandedIDs.insert(item.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.title).font(.headline)
                            Text(item.status)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(item.status == "处理失败" ? AppPalette.danger : AppPalette.warning)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        Text(item.subtitle).font(.callout).foregroundColor(.secondary)
                        if !item.folderPath.isEmpty {
                            Text(item.folderPath)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if expanded {
                pendingItemDetails(item)
                    .padding(.leading, 58)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func pendingItemDetails(_ item: PendingCenterItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group = item.serverGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server 文件变化（\(group.changes.count) 项）")
                        .font(.subheadline.weight(.semibold))
                    ForEach(group.changes) { change in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: changeIcon(change.changeType))
                                .foregroundColor(changeColor(change.changeType))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                                    let timeSuffix = change.eventTime.isEmpty ? "" : " · \(changeTimeLabel(change))"
                                                    Text("\(changeTypeName(change.changeType))：\(URL(fileURLWithPath: change.path).lastPathComponent)\(timeSuffix)")
                                                        .font(.caption)
                                                    Text(change.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            ForEach(item.issues) { issue in
                issueDetails(issue)
            }

            ForEach(item.aimesReviews) { review in
                aimesDetails(review)
            }
        }
    }

    @ViewBuilder
    private func issueDetails(_ issue: CurrentIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: issue.kind == "factory_ownership" ? "person.crop.circle.badge.questionmark" : "exclamationmark.triangle.fill")
                    .foregroundColor(issue.kind == "factory_ownership" ? AppPalette.warning : AppPalette.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.kind == "factory_ownership" ? "订单归属问题" : (issue.kind == "server_missing_report" ? "报表检查" : (issue.message.contains("未映射材料") ? "出库前需要材料映射" : "处理失败")))
                        .font(.subheadline.weight(.semibold))
                    Text(issue.message).fixedSize(horizontal: false, vertical: true)
                    if !issue.path.isEmpty {
                        Text(issue.path)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            HStack(spacing: 8) {
                if !issue.path.isEmpty {
                    Button("打开所在文件夹") { model.openDashboardLocation(issue.path) }
                        .buttonStyle(.link)
                }
                if issue.kind == "factory_ownership" {
                    TextField("确认订单号，如 PP0037", text: Binding(
                        get: { orderIDs[issue.id] ?? "" },
                        set: { orderIDs[issue.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    Button("自动处理") { model.autoResolveCurrentIssue(issue) }
                        .buttonStyle(.bordered)
                        .disabled(model.orderRunning)
                    Button("确认归属") { model.resolveCurrentIssue(issue, orderID: orderIDs[issue.id] ?? "") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.orderRunning || (orderIDs[issue.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if issue.kind == "server_missing_report" {
                    Button("忽略此文件夹（观察一个月）") { model.ignoreServerFolder(issue.path) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.orderRunning)
                } else if issue.kind == "temporary_processing" && issue.message.contains("未映射材料") {
                    Button("打开订单文件映射") { model.requestInventoryMapping(folderPath: issue.path) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.orderRunning)
                } else if issue.kind == "material_mapping" || issue.kind == "hardware_mapping" {
                    Button("处理订单文件映射") { model.requestInventoryMapping(folderPath: issue.path) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.orderRunning)
                } else {
                    Button("标记已处理") { model.resolveCurrentIssue(issue, orderID: "") }
                        .buttonStyle(.bordered)
                        .disabled(model.orderRunning)
                }
            }
        }
        .padding(10)
        .background(AppPalette.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func aimesDetails(_ item: AimesReviewItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.toggleAimesReviewSelection(item) } label: {
                Image(systemName: model.selectedAimesReviewIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(model.selectedAimesReviewIDs.contains(item.id) ? AppPalette.accent : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text("AIMES 待确认 · \(item.factoryOrder.isEmpty ? "工厂单号为空" : item.factoryOrder)")
                    .font(.subheadline.weight(.semibold))
                Text("工厂单名称：\(item.factoryName.isEmpty ? "名称为空" : item.factoryName)")
                    .font(.caption)
                Text("销售单名称：\(item.salesOrderName.isEmpty ? "空" : item.salesOrderName)")
                    .font(.caption)
                Text(item.reason).font(.caption).foregroundColor(AppPalette.warning)
            }
            Spacer(minLength: 8)
            if !item.suggestedOrderID.isEmpty {
                Button("按 \(item.suggestedOrderID) 处理") { model.assignAimesFactoryToSuggestedOrder(item) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.orderRunning)
            }
        }
        .padding(10)
        .background(AppPalette.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func changeTypeName(_ type: String) -> String {
        switch type {
        case "added": return "新增"
        case "removed": return "删除"
        case "renamed": return "改名"
        case "missing_report": return "缺少报表"
        default: return "修改"
        }
    }

    private func changeIcon(_ type: String) -> String {
        switch type {
        case "added": return "plus.circle.fill"
        case "removed": return "minus.circle.fill"
        case "renamed": return "arrow.right.circle.fill"
        case "missing_report": return "doc.questionmark.fill"
        default: return "pencil.circle.fill"
        }
    }

    private func changeColor(_ type: String) -> Color {
        switch type {
        case "added": return AppPalette.success
        case "removed": return AppPalette.danger
        case "renamed": return AppPalette.accent
        case "missing_report": return AppPalette.warning
        default: return AppPalette.warning
        }
    }

    private func changeTimeLabel(_ change: ServerChangePreview) -> String {
        switch change.changeType {
        case "added": return "创建时间：\(appDisplayTimestamp(change.eventTime))"
        case "modified": return "修改时间：\(appDisplayTimestamp(change.eventTime))"
        case "renamed": return "改名时间：\(appDisplayTimestamp(change.eventTime))"
        default: return "记录时间：\(appDisplayTimestamp(change.eventTime))"
        }
    }
}

struct OrderCostSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("订单成本 (\(model.selectedOrderId))")
                        .font(.title2.weight(.semibold))
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button("导出 Excel") {
                        model.calculateSelectedOrderCost(export: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.orderRunning)
                    Button("关闭") { model.showCostSheet = false }
                        .appActionButton(minWidth: 72)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    costCard("总成本", value: model.orderCostTotal.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "待补充", warning: model.orderCostTotal == nil)
                    costCard("已确认成本", value: model.orderCostKnown.formatted(.number.precision(.fractionLength(2))), warning: false)
                    costCard("成本行数", value: model.orderCostLines.count.formatted(), warning: false)
                    costCard("状态", value: model.orderCostMissingItems.isEmpty ? "已完成" : "待补充", warning: !model.orderCostMissingItems.isEmpty)
                }
                .padding(.trailing, 12)

                if !model.orderCostMissingItems.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.orderCostMissingItems, id: \.self) { item in
                                Label(item, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(AppPalette.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                GroupBox("成本来源") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("材料类型").frame(maxWidth: .infinity, alignment: .center)
                            Text("成本").frame(width: 110, alignment: .center)
                            Text("状态").frame(width: 90, alignment: .center)
                        }
                        .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        .padding(.vertical, 7)
                        Divider()
                        ForEach(orderCostSourceTotals) { row in
                            HStack {
                                Text(row.factoryOrder).lineLimit(1).frame(maxWidth: .infinity, alignment: .center)
                                Text(row.hasMissing ? "待补充" : row.total.formatted(.number.precision(.fractionLength(2))))
                                    .frame(width: 110, alignment: .center)
                                Text(row.hasMissing ? "待补充" : "已完成")
                                    .foregroundColor(row.hasMissing ? AppPalette.warning : AppPalette.success)
                                    .frame(width: 90, alignment: .center)
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }

                GroupBox("成本明细") {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            costLineHeader
                            ForEach(model.orderCostLines) { row in
                                costLine(row)
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .frame(minWidth: 700, idealWidth: 900, minHeight: 560, idealHeight: 720)
        .background(AppPalette.background)
    }

    private func costCard(_ title: String, value: String, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundColor(warning ? AppPalette.warning : AppPalette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.separator))
    }

    private var costLineHeader: some View {
        HStack(spacing: 8) {
            Text("类别").frame(width: 70, alignment: .center)
            Text("商品").frame(maxWidth: .infinity, alignment: .center)
            Text("数量").frame(width: 75, alignment: .center)
            Text("单位").frame(width: 55, alignment: .center)
            Text("单价").frame(width: 80, alignment: .center)
            Text("金额").frame(width: 100, alignment: .center)
        }
        .font(.caption.weight(.semibold)).foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.vertical, 7)
    }

    private func costLine(_ row: OrderCostLine) -> some View {
        HStack(spacing: 8) {
            Text(row.category)
                .frame(width: 70, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).lineLimit(1)
                if !row.productCode.isEmpty { Text(row.productCode).font(.caption2).foregroundColor(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.quantity.formatted())
                .frame(width: 75, alignment: .center)
            Text(row.unit)
                .frame(width: 55, alignment: .center)
            Text(row.costPrice?.formatted(.number.precision(.fractionLength(2))) ?? "—")
                .frame(width: 80, alignment: .center)
            VStack(alignment: .center, spacing: 2) {
                Text(row.amount?.formatted(.number.precision(.fractionLength(2))) ?? "待补充")
                    .foregroundColor(row.amount == nil ? AppPalette.warning : .primary)
                if !row.missing.isEmpty {
                    Text(row.missing)
                        .font(.caption2)
                        .foregroundColor(AppPalette.warning)
                        .lineLimit(1)
                }
            }
                .frame(width: 100, alignment: .center)
        }
        .font(.caption)
        .padding(.vertical, 7)
    }

    private var orderCostSourceTotals: [OrderCostFactoryTotal] {
        [
            sourceTotal(
                id: "materials",
                title: "板材及封边条",
                categories: ["板材", "封边条"]
            ),
            sourceTotal(
                id: "hardware",
                title: "五金",
                categories: ["五金"]
            ),
        ]
    }

    private func sourceTotal(
        id: String,
        title: String,
        categories: [String]
    ) -> OrderCostFactoryTotal {
        let lines = model.orderCostLines.filter { categories.contains($0.category) }
        return OrderCostFactoryTotal(
            id: id,
            factoryOrder: title,
            total: lines.reduce(0) { $0 + ($1.amount ?? 0) },
            hasMissing: lines.contains { !$0.missing.isEmpty }
        )
    }
}

struct ServerProcessingOptionsSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("处理 Server 文件夹")
                .font(.title2.weight(.semibold))
            Text("系统将重新读取报表并写入中央数据库；Traveler 仅在需要打印或导出时按需生成。")
                .font(.callout)
                .foregroundColor(.secondary)
            Toggle("出库包含五金件", isOn: $model.includeHardwareForServerProcessing)
                .toggleStyle(.checkbox)
            Text("关闭后，即使文件夹中有 Fittingslist，本次也不会写入五金事实，库存出库不会包含五金。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("取消") {
                    model.showServerProcessingOptions = false
                    model.pendingServerFolderURL = nil
                }
                .appActionButton(minWidth: 88)
                Button("开始处理") {
                    guard let folder = model.pendingServerFolderURL else { return }
                    model.showServerProcessingOptions = false
                    model.pendingServerFolderURL = nil
                    model.processSelectedServerFolder(
                        folder,
                        includeHardware: model.includeHardwareForServerProcessing
                    )
                }
                .buttonStyle(.borderedProminent)
                .appActionButton(minWidth: 100)
                .disabled(model.orderRunning)
            }
        }
        .padding(24)
        .background(AppPalette.background)
    }
}

struct AimesReviewSheet: View {
    @ObservedObject var model: AppModel
    @State private var manualOrderIDs: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AIMES 工厂单管理")
                        .font(.title2.weight(.semibold))
                    Text("待确认记录不会进入订单看板。请核对 AIMES 原始信息后，选择建议归属、稍后处理或永久忽略。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !model.pendingAimesReviews.isEmpty {
                    AppStatusBadge(text: "\(model.pendingAimesReviews.count) 条待确认", kind: .warning)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pendingSection
                    formatWarningSection
                    assignedSection
                    ignoredSection
                }
            }

            HStack {
                Text("选择“稍后处理”不会保存忽略记录，下次获取 AIMES 时仍会提醒。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(model.pendingAimesReviews.isEmpty ? "关闭" : "稍后处理") {
                    model.showAimesReviewPrompt = false
                }
                .appActionButton(minWidth: 108)
                if !model.pendingAimesReviews.isEmpty {
                    Button("忽略选中") { model.ignoreSelectedAimesFactories() }
                        .buttonStyle(.borderedProminent)
                        .appActionButton(minWidth: 118)
                        .disabled(model.orderRunning || model.selectedAimesReviewIDs.isEmpty)
                }
            }
        }
        .padding(20)
        .background(AppPalette.background)
    }

    @ViewBuilder
    private var formatWarningSection: some View {
        if !model.aimesFormatWarnings.isEmpty {
            Text("销售单格式异常（需要人工确认）")
                .font(.headline)
            AppSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(model.aimesFormatWarnings) { item in
                        VStack(alignment: .leading, spacing: 9) {
                            aimesIdentity(item)
                            Text("原始销售单名称会保留用于追溯；确认后业务映射使用你输入的订单号。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                TextField(
                                    "订单号，如 PP0037 或 CS001",
                                    text: Binding(
                                        get: { manualOrderIDs[item.id] ?? item.suggestedOrderID },
                                        set: { manualOrderIDs[item.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                if !item.suggestedOrderID.isEmpty {
                                    Text("建议：\(item.suggestedOrderID)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Button("确认归属") {
                                    model.assignAimesFactoryToOrder(
                                        item,
                                        orderID: manualOrderIDs[item.id] ?? item.suggestedOrderID
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    model.orderRunning
                                        || (manualOrderIDs[item.id] ?? item.suggestedOrderID)
                                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                            }
                        }
                        .padding(12)
                        if item.id != model.aimesFormatWarnings.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if model.pendingAimesReviews.isEmpty {
            AppSurfaceCard(padding: 16) {
                Text("当前没有待确认的 AIMES 工厂单。")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack {
                Text("待确认")
                    .font(.headline)
                Spacer()
                Button("全选") {
                    model.selectedAimesReviewIDs = Set(model.pendingAimesReviews.map(\.id))
                }
                .buttonStyle(.link)
                Button("取消全选") { model.selectedAimesReviewIDs.removeAll() }
                    .buttonStyle(.link)
            }
            AppSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(model.pendingAimesReviews) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                model.toggleAimesReviewSelection(item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                Image(systemName: model.selectedAimesReviewIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(model.selectedAimesReviewIDs.contains(item.id) ? AppPalette.accent : .secondary)
                                    .frame(width: 22, height: 22)
                                aimesIdentity(item)
                                Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if !item.suggestedOrderID.isEmpty {
                                Button("按 \(item.suggestedOrderID) 处理") {
                                    model.assignAimesFactoryToSuggestedOrder(item)
                                }
                                .buttonStyle(.borderedProminent)
                                .appActionButton(minWidth: 132)
                                .disabled(model.orderRunning)
                            }
                        }
                        .padding(12)
                        if item.id != model.pendingAimesReviews.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assignedSection: some View {
        if !model.assignedAimesFactories.isEmpty {
            Text("已按工厂单名称确认归属")
                .font(.headline)
            AppSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(model.assignedAimesFactories) { item in
                        HStack(alignment: .top, spacing: 12) {
                            aimesIdentity(item, timestampLabel: "确认时间")
                            Spacer(minLength: 12)
                            Button("撤销归属") { model.restoreAimesFactoryAssignment(item) }
                                .appActionButton(minWidth: 92)
                                .disabled(model.orderRunning)
                        }
                        .padding(12)
                        if item.id != model.assignedAimesFactories.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ignoredSection: some View {
        if !model.ignoredAimesFactories.isEmpty {
            Text("已忽略，可随时恢复")
                .font(.headline)
            AppSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(model.ignoredAimesFactories) { item in
                        HStack(alignment: .top, spacing: 12) {
                            aimesIdentity(item, timestampLabel: "忽略时间")
                            Spacer(minLength: 12)
                            Button("恢复") { model.restoreAimesFactory(item) }
                                .appActionButton(minWidth: 72)
                                .disabled(model.orderRunning)
                        }
                        .padding(12)
                        if item.id != model.ignoredAimesFactories.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func aimesIdentity(_ item: AimesReviewItem, timestampLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(item.factoryOrder.isEmpty ? "工厂单号为空" : item.factoryOrder)
                    .fontWeight(.semibold)
                Text(item.factoryName.isEmpty ? "名称为空" : item.factoryName)
                    .foregroundColor(.secondary)
            }
            Text("销售单名称：\(item.salesOrderName.isEmpty ? "空" : item.salesOrderName)")
            Text(item.reason)
                .font(.caption)
                .foregroundColor(AppPalette.warning)
            if let timestampLabel, !item.ignoredAt.isEmpty {
                Text("\(timestampLabel)：\(appDisplayTimestamp(item.ignoredAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CurrentIssuesSheet: View {
    @ObservedObject var model: AppModel
    @State private var orderIDs: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前未解决问题")
                        .font(.title2.weight(.semibold))
                    Text("这里只显示当前仍存在的问题；历史操作记录保留在数据库中，但不会在新打开 App 时重复显示。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                AppStatusBadge(text: "\(model.currentIssues.count) 项", kind: .warning)
            }

            if model.currentIssues.isEmpty {
                ContentUnavailableView("当前没有未解决问题", systemImage: "checkmark.circle", description: Text("系统会在扫描和处理 Server 时自动更新此列表。"))
            } else {
                AppSurfaceCard(padding: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.currentIssues) { issue in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: issue.kind == "factory_ownership" ? "person.crop.circle.badge.questionmark" : "exclamationmark.triangle.fill")
                                            .foregroundColor(AppPalette.warning)
                                            .frame(width: 22, height: 22)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(issue.factoryOrder.isEmpty ? (issue.orderId.isEmpty ? "当前问题" : issue.orderId) : issue.factoryOrder)
                                                .font(.headline)
                                            Text(issue.message)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if !issue.path.isEmpty {
                                                Text(issue.path)
                                                    .font(.caption.monospaced())
                                                    .foregroundColor(.secondary)
                                                    .textSelection(.enabled)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                    HStack(spacing: 10) {
                                        if !issue.path.isEmpty {
                                            Button("打开所在文件夹") { model.openDashboardLocation(issue.path) }
                                                .buttonStyle(.link)
                                        }
                                        if issue.kind == "factory_ownership" {
                                            TextField(
                                                "确认订单号，如 PP0037",
                                                text: Binding(
                                                    get: { orderIDs[issue.id] ?? "" },
                                                    set: { orderIDs[issue.id] = $0 }
                                                )
                                            )
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 180)
                                            Button("自动处理") { model.autoResolveCurrentIssue(issue) }
                                                .buttonStyle(.bordered)
                                                .disabled(model.orderRunning)
                                            Button("确认归属") { model.resolveCurrentIssue(issue, orderID: orderIDs[issue.id] ?? "") }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(model.orderRunning || (orderIDs[issue.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        } else if issue.kind == "material_mapping" || issue.kind == "hardware_mapping" {
                                            Button("处理订单文件映射") { model.requestInventoryMapping(folderPath: issue.path) }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(model.orderRunning)
                                        } else {
                                            Button("标记已处理") { model.resolveCurrentIssue(issue, orderID: "") }
                                                .buttonStyle(.bordered)
                                                .disabled(model.orderRunning)
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(14)
                                if issue.id != model.currentIssues.last?.id { Divider() }
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("关闭") { model.showCurrentIssuesPrompt = false }
                    .appActionButton(minWidth: 80)
            }
        }
        .padding(20)
        .background(AppPalette.background)
    }
}

struct ServerChangesSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let groups = serverFolderChangeGroups(model.pendingServerChanges)
        let selectedCount = groups.filter { model.selectedServerFolderPaths.contains($0.folderPath) }.count
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("发现 Server 数据变化")
                        .font(.title2.weight(.semibold))
                    Text("以下变化尚未解析，也没有修改订单数据库。点击“自动处理”后，系统才会读取相关报表并更新看板。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                AppStatusBadge(text: "\(groups.count) 个文件夹待处理", kind: .warning)
            }

            HStack(spacing: 10) {
                Text("请选择要自动处理的文件夹（已选 \(selectedCount) 个）")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("全选") { model.selectAllServerFolders() }
                    .buttonStyle(.link)
                    .disabled(groups.isEmpty || selectedCount == groups.count)
                Button("取消全选") { model.clearServerFolderSelection() }
                    .buttonStyle(.link)
                    .disabled(selectedCount == 0)
            }

            AppSurfaceCard(padding: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            let selected = model.selectedServerFolderPaths.contains(group.folderPath)
                            Button {
                                model.toggleServerFolderSelection(group.folderPath)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selected ? AppPalette.accent : .secondary)
                                        .font(.system(size: 20, weight: .semibold))
                                        .frame(width: 22, height: 22)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(group.manualOnly ? "临时订单文件夹" : (group.orderId.isEmpty ? "混单文件夹" : group.orderId))
                                                .fontWeight(.semibold)
                                            Text(group.folderName)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Text("包含 \(group.changes.count) 项变化：")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        ForEach(group.changes) { change in
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: changeIcon(change.changeType))
                                                    .foregroundColor(changeColor(change.changeType))
                                                    .frame(width: 16)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(serverChangeTypeName(change.changeType))：\(URL(fileURLWithPath: change.path).lastPathComponent)")
                                                        .font(.caption)
                                                    Text(change.path)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        if group.manualOnly {
                                            Text("自动处理时将校验文件格式，优先读取 material；缺少时从 Report 生成材料并尝试出库，失败会保留在待处理清单。")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .padding(12)
                            .buttonStyle(.plain)
                            if group.id != groups.last?.id { Divider() }
                        }
                    }
                }
            }

            HStack {
                Text("选择“稍后处理”后，下次扫描仍会再次提醒；只有勾选的文件夹会进入自动处理，失败的文件夹会继续保留。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("稍后处理") { model.showServerChangesPrompt = false }
                    .appActionButton(minWidth: 108)
                    .disabled(model.orderRunning)
                Button("自动处理") { model.processPendingServerChanges() }
                    .buttonStyle(.borderedProminent)
                    .appActionButton(minWidth: 118)
                    .disabled(model.orderRunning || selectedCount == 0)
            }
        }
        .padding(20)
        .background(AppPalette.background)
    }

    private func changeIcon(_ type: String) -> String {
        switch type {
        case "added": return "plus.circle.fill"
        case "removed": return "minus.circle.fill"
        default: return "pencil.circle.fill"
        }
    }

    private func changeColor(_ type: String) -> Color {
        switch type {
        case "added": return AppPalette.success
        case "removed": return AppPalette.danger
        default: return AppPalette.warning
        }
    }
}

struct FactoryStockComparisonSheet: View {
    @ObservedObject var model: AppModel
    let orderID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    AppStatusBadge(text: "库存比对", kind: .info)
                    Text("订单 \(orderID) 库存汇总").font(.title2.weight(.semibold))
                    Text("板材、封边和五金均按订单汇总，不按工厂单拆分")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if model.orderRunning { ProgressView().controlSize(.small) }
            }

            if model.orderStockRows.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(model.orderStatus.isEmpty ? "正在查询订单材料和五金库存…" : model.orderStatus)
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                AppSurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        stockHeader
                        Divider()
                        ForEach(model.orderStockRows) { row in
                            stockRow(row)
                            Divider()
                        }
                    }
                }
            }

            HStack {
                Text("库存查询失败时，按钮保持可用，允许手工再次查询。")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("再次查询") { model.checkSelectedOrderStock() }
                    .appActionButton(minWidth: 112)
                    .disabled(model.orderRunning || !model.orderPreviewReady)
            }
        }
        .padding(20)
        .background(AppPalette.background)
    }

    private var stockHeader: some View {
        HStack(spacing: 0) {
            Text("商品").frame(maxWidth: .infinity, alignment: .center)
            Text("单位").frame(width: 60, alignment: .center)
            Text("需求").frame(width: 80, alignment: .center)
            Text("库存").frame(width: 80, alignment: .center)
            Text("结果").frame(width: 100, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.vertical, 10)
        .background(AppPalette.subtleSurface)
    }

    private func stockRow(_ row: OrderStockPreview) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.productName).fontWeight(.medium)
                Text(row.productCode).font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.unit.isEmpty ? "—" : row.unit).frame(width: 60, alignment: .center)
            Text(row.required.formatted()).frame(width: 80, alignment: .center)
            Text(row.available.formatted()).frame(width: 80, alignment: .center)
            Text(row.sufficient ? "充足" : "缺 \(row.shortage.formatted())")
                .fontWeight(.semibold)
                .foregroundColor(row.sufficient ? AppPalette.success : AppPalette.warning)
                .frame(width: 100, alignment: .center)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(row.sufficient ? Color.clear : AppPalette.danger.opacity(0.06))
    }
}
