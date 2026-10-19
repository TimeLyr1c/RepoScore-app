import SwiftUI
import PDFKit

struct ScoreReaderView: View {
    let score: Score
    let url: URL
    @State private var document: PDFDocument?
    @State private var loadFailed = false
    @State private var pageIndex = 0
    @State private var mode: ReadingMode = .single
    @State private var separateCover = true
    @State private var showsSettings = false

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
                VStack(spacing: 0) {
                    PDFSpreadView(document: document, pages: layout.spread(containing: pageIndex),
                                  onPrevious: previousPage, onNext: nextPage)
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
                    .padding().background(.regularMaterial)
                }
            } else if loadFailed {
                ContentUnavailableView("无法打开乐谱", systemImage: "doc.badge.ellipsis",
                                       description: Text("本地副本不存在或无法读取。请返回曲库，重新导入原文件。"))
            } else { ProgressView("正在打开乐谱…") }
        }
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("阅读设置", systemImage: "book") { showsSettings = true }
                    .accessibilityIdentifier("readingSettings").disabled(document == nil)
                    .popover(isPresented: $showsSettings) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("阅读设置").font(.headline)
                            Picker("页面布局", selection: $mode) {
                                Text("单页").tag(ReadingMode.single)
                                Text("双页").tag(ReadingMode.double)
                            }
                            .pickerStyle(.segmented).accessibilityIdentifier("readingMode")
                            Toggle("第一页单独显示", isOn: $separateCover)
                                .disabled(mode == .single).accessibilityIdentifier("separateCover")
                            Text("左右边缘点击翻页，也可左右滑动；放大后以平移阅读为主。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("完成") { showsSettings = false }.frame(maxWidth: .infinity)
                        }
                        .padding().frame(width: 300)
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

    private func previousPage() { pageIndex = layout.previousPage(from: pageIndex) }
    private func nextPage() { pageIndex = layout.nextPage(from: pageIndex) }
}

private struct PDFSpreadView: UIViewRepresentable {
    let document: PDFDocument
    let pages: Range<Int>
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeUIView(context: Context) -> SpreadPDFView { SpreadPDFView() }

    func updateUIView(_ view: SpreadPDFView, context: Context) {
        view.onPrevious = onPrevious
        view.onNext = onNext
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
    private var pageViews: [FittedPDFView] = []
    private var displayedPages: Range<Int> = 0..<0
    private weak var displayedDocument: PDFDocument?
    private let stack = UIStackView()
    private weak var navigationBackGesture: UIGestureRecognizer?
    private var backGestureWasEnabled = true
    private weak var contentBackGesture: UIGestureRecognizer?
    private var contentGestureWasEnabled = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        accessibilityIdentifier = "pdfSpread"
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
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
        for view in pageViews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        pageViews = pages.compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let view = FittedPDFView()
            view.displayMode = .singlePage
            view.autoScales = true
            view.backgroundColor = .clear
            view.document = document
            view.go(to: page)
            view.accessibilityIdentifier = "pdfPage-\(index + 1)"
            stack.addArrangedSubview(view)
            return view
        }
    }

    private var isAtFitScale: Bool {
        pageViews.allSatisfy { $0.scaleFactor <= $0.scaleFactorForSizeToFit * 1.05 }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let tap = gestureRecognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 { return true }
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
        if x < bounds.width * 0.25 { onPrevious?() }
        else if x > bounds.width * 0.75 { onNext?() }
    }

    @objc private func ignoreDoubleTap() {}
}

private final class FittedPDFView: PDFView {
    private var previousSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize && bounds.width > 0 && bounds.height > 0 {
            previousSize = bounds.size
            // Rotation changes scale, never the selected physical page.
            scaleFactor = scaleFactorForSizeToFit
        }
    }
}
