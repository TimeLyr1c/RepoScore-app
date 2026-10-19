import SwiftUI
import PDFKit

struct ScoreReaderView: View {
    let score: Score
    let url: URL
    @State private var document: PDFDocument?
    @State private var loadFailed = false
    @State private var pageIndex = 0
    @State private var preference: ReadingPreference = .automatic
    @State private var separateCover = true
    @State private var showsSettings = false
    @State private var showsControls = true
    @State private var isLandscape = false

    private var mode: ReadingMode { preference.mode(isLandscape: isLandscape) }

    private var layout: PageLayout {
        PageLayout(pageCount: document?.pageCount ?? score.pageCount, mode: mode, separateCover: separateCover)
    }

    private var pageLabel: String {
        let pages = layout.spread(containing: pageIndex)
        if pages.count == 1 { return "\(pages.lowerBound + 1) / \(layout.pageCount)" }
        return "\(pages.lowerBound + 1)–\(pages.upperBound) / \(layout.pageCount)"
    }

    var body: some View {
        Group {
            if let document {
                // The page always lays out against the full screen; controls float above it.
                PDFSpreadView(document: document, pages: layout.spread(containing: pageIndex),
                              onPrevious: { turn(previousPage) }, onNext: { turn(nextPage) },
                              onToggleControls: { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } })
                    .ignoresSafeArea()
            } else if loadFailed {
                ContentUnavailableView("无法打开乐谱", systemImage: "doc.badge.ellipsis",
                                       description: Text("本地副本不存在或无法读取。请返回曲库，重新导入原文件。"))
            } else { ProgressView("正在打开乐谱…") }
        }
        .overlay(alignment: .bottom) { if showsControls && document != nil { controls } }
        .background { GeometryReader { proxy in
            Color(uiColor: .systemBackground)
                .onAppear { isLandscape = proxy.size.width > proxy.size.height }
                .onChange(of: proxy.size) { _, size in isLandscape = size.width > size.height }
        }.ignoresSafeArea() }
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsControls || document == nil ? .visible : .hidden, for: .navigationBar)
        .statusBarHidden(!showsControls && document != nil)
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("阅读设置", systemImage: "book") { showsSettings = true }
                    .accessibilityIdentifier("readingSettings").disabled(document == nil)
                    .popover(isPresented: $showsSettings) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("阅读设置").font(.headline)
                            Picker("页面布局", selection: $preference) {
                                Text("自动").tag(ReadingPreference.automatic)
                                Text("单页").tag(ReadingPreference.single)
                                Text("双页").tag(ReadingPreference.double)
                            }
                            .pickerStyle(.segmented).accessibilityIdentifier("readingMode")
                            Toggle("第一页单独显示", isOn: $separateCover)
                                .disabled(preference == .single).accessibilityIdentifier("separateCover")
                            Text("自动：横屏双页，竖屏单页。点按中间显示或隐藏工具栏；左右边缘点击或左右滑动翻页，放大后以平移阅读为主。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("完成") { showsSettings = false }.frame(maxWidth: .infinity)
                        }
                        .padding().frame(width: 320)
                    }
            }
        }
        .task(id: score.id) {
            let loaded = await Task.detached(priority: .userInitiated) { PDFDocument(url: url) }.value
            guard !Task.isCancelled else { return }
            if let loaded, !loaded.isLocked, loaded.pageCount > 0 { document = loaded }
            else { loadFailed = true }
        }
    }

    private var controls: some View {
        HStack {
            Button("上一页", systemImage: "chevron.left", action: previousPage)
                .disabled(layout.spread(containing: pageIndex).lowerBound == 0)
            Spacer()
            Text(pageLabel).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityIdentifier("pageIndicator")
            Spacer()
            Button("下一页", systemImage: "chevron.right", action: nextPage)
                .disabled(layout.spread(containing: pageIndex).upperBound == layout.pageCount)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: 480)
        .padding(.horizontal).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Tap and swipe turns mean the reader is reading, so the controls get out of the way.
    private func turn(_ action: () -> Void) {
        action()
        if showsControls { withAnimation(.easeInOut(duration: 0.2)) { showsControls = false } }
    }

    private func previousPage() { pageIndex = layout.previousPage(from: pageIndex) }
    private func nextPage() { pageIndex = layout.nextPage(from: pageIndex) }
}

private struct PDFSpreadView: UIViewRepresentable {
    let document: PDFDocument
    let pages: Range<Int>
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToggleControls: () -> Void

    func makeUIView(context: Context) -> SpreadPDFView { SpreadPDFView() }

    func updateUIView(_ view: SpreadPDFView, context: Context) {
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onToggleControls = onToggleControls
        view.display(document: document, pages: pages)
    }

    static func dismantleUIView(_ view: SpreadPDFView, coordinator: ()) {
        view.restoreNavigationGesture()
    }
}

/// PDFKit renders each physical page. The container owns pairing and navigation.
private final class SpreadPDFView: UIView, UIGestureRecognizerDelegate {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onToggleControls: (() -> Void)?
    private var pageViews: [FittedPDFView] = []
    private var displayedPages: Range<Int> = 0..<0
    private weak var displayedDocument: PDFDocument?
    private weak var navigationBackGesture: UIGestureRecognizer?
    private var backGestureWasEnabled = true
    private weak var contentBackGesture: UIGestureRecognizer?
    private var contentGestureWasEnabled = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Matches the page paper in light mode, so the letterbox left by aspect fit reads as page.
        backgroundColor = .systemBackground
        accessibilityIdentifier = "pdfSpread"
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            addGestureRecognizer(swipe)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(ignoreDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { restoreNavigationGesture(); return }
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController,
               let gesture = controller.navigationController?.interactivePopGestureRecognizer {
                if navigationBackGesture == nil {
                    navigationBackGesture = gesture
                    backGestureWasEnabled = gesture.isEnabled
                }
                // Reading swipes turn pages; the navigation bar's back button remains available.
                gesture.isEnabled = false
                if #available(iOS 26.0, *),
                   let content = controller.navigationController?.interactiveContentPopGestureRecognizer {
                    if contentBackGesture == nil {
                        contentBackGesture = content
                        contentGestureWasEnabled = content.isEnabled
                    }
                    content.isEnabled = false
                }
                break
            }
            responder = current.next
        }
    }

    func restoreNavigationGesture() {
        navigationBackGesture?.isEnabled = backGestureWasEnabled
        navigationBackGesture = nil
        contentBackGesture?.isEnabled = contentGestureWasEnabled
        contentBackGesture = nil
    }

    func display(document: PDFDocument, pages: Range<Int>) {
        guard displayedDocument !== document || displayedPages != pages else { return }
        displayedDocument = document
        displayedPages = pages
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = pages.compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let view = FittedPDFView(page: page)
            view.document = document
            view.go(to: page)
            view.accessibilityIdentifier = "pdfPage-\(index + 1)"
            addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    /// Sizes the spread as one sheet: pages share a height, touch at the spine and fill the
    /// container as far as the combined aspect ratio allows.
    override func layoutSubviews() {
        super.layoutSubviews()
        let sizes = pageViews.map(\.pageSize)
        guard bounds.width > 0, bounds.height > 0, let height = sizes.map(\.height).max(), height > 0 else { return }
        let widths = sizes.map { $0.width * height / max($0.height, 1) }
        let total = widths.reduce(0, +)
        guard total > 0 else { return }
        let scale = min(bounds.width / total, bounds.height / height)
        var x = (bounds.width - total * scale) / 2
        let y = (bounds.height - height * scale) / 2
        for (view, width) in zip(pageViews, widths) {
            view.frame = CGRect(x: x, y: y, width: width * scale, height: height * scale)
            x += width * scale
        }
    }

    private var isAtFitScale: Bool {
        pageViews.allSatisfy { $0.scaleFactor <= $0.scaleFactorForSizeToFit * 1.05 }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Taps always begin so the center can reveal controls while zoomed; edge taps check scale.
        if gestureRecognizer is UITapGestureRecognizer { return true }
        return isAtFitScale
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Leave PDFKit's zoom/selection intact; our taps wait for double taps to fail.
        gestureRecognizer is UITapGestureRecognizer
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .left { onNext?() }
        else { onPrevious?() }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        let isEdge = x < bounds.width * 0.25 || x > bounds.width * 0.75
        if isEdge && !isAtFitScale { return }
        if x < bounds.width * 0.25 { onPrevious?() }
        else if x > bounds.width * 0.75 { onNext?() }
        else { onToggleControls?() }
    }

    @objc private func ignoreDoubleTap() {}
}

private final class FittedPDFView: PDFView {
    /// Displayed page size in points, accounting for the page's rotation.
    let pageSize: CGSize
    private var previousSize: CGSize = .zero

    init(page: PDFPage) {
        let box = page.bounds(for: .cropBox).size
        pageSize = page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
        super.init(frame: .zero)
        displayMode = .singlePage
        autoScales = true
        // No gray page-break gutter or shadow: the view is sized to the page, so it fits edge to edge.
        displaysPageBreaks = false
        pageShadowsEnabled = false
        pageBreakMargins = .zero
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The reader ignores safe areas; keep PDFKit's scroll view from insetting the page.
        for case let scroll as UIScrollView in subviews where scroll.contentInsetAdjustmentBehavior != .never {
            scroll.contentInsetAdjustmentBehavior = .never
        }
        if bounds.size != previousSize && bounds.width > 0 && bounds.height > 0 {
            previousSize = bounds.size
            // Rotation changes scale, never the selected physical page.
            scaleFactor = scaleFactorForSizeToFit
        }
    }
}
