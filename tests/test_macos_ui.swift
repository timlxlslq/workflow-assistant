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
        testMaterialDisplayNames()
        testSharedPageHeaderHeight()
        testFullPageHeaderBoundaryAlignment()
        testOperationLogScrollsAfterAppending()
        print("macOS UI regression tests passed")
    }

    private static func testMaterialDisplayNames() {
        require(AppLayout.headerHeight == 68, "四个页面的共享页头高度应为 68")
        require(AppLayout.todoDeadlineColumnWidth >= 270, "截止时间列不足以同时显示时间和过期提醒")
        require(AppLayout.todoListMaxHeight == 340, "待办列表高度未按要求压缩")
        require(AppLayout.todoInputMinHeight >= 92, "新增待办输入框高度不足三行")
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
            require(
                abs(hosting.fittingSize.height - AppLayout.headerHeight) <= 0.5,
                "页面共享页头高度不一致：\(hosting.fittingSize.height)"
            )
        }
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
