import AppKit
import WebKit

private final class ZoomableWebView: WKWebView {
    var commandKeyHandler: ((String) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let hasCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if hasCommand,
           let key = event.charactersIgnoringModifiers,
           commandKeyHandler?(key) == true {
            return
        }
        super.keyDown(with: event)
    }
}

class MarkdownPreviewViewController: NSViewController {
    private let webView: ZoomableWebView
    private let userContentController: WKUserContentController
    private let readingWidthButton: NSButton
    private let editButton: NSButton
    private let minimumZoom: CGFloat = 0.6
    private let maximumZoom: CGFloat = 2.0
    private let zoomStep: CGFloat = 0.1
    private var zoomPreferenceKey: String?
    private var readingWidthPreferenceKey: String?
    private var documentURL: URL?
    private(set) var readingWidthMode: DocumentState.ReadingWidthMode = .fixed
    var readingWidthModeDidChange: ((DocumentState.ReadingWidthMode) -> Void)?
    var editRequested: (() -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        userContentController = WKUserContentController()
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = ZoomableWebView(frame: .zero, configuration: configuration)
        readingWidthButton = NSButton(title: "Width: 800", target: nil, action: nil)
        editButton = NSButton(title: "Edit", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        userContentController.add(self, name: "previewMD")
        readingWidthButton.target = self
        readingWidthButton.action = #selector(toggleReadingWidth(_:))
        readingWidthButton.bezelStyle = .rounded
        readingWidthButton.toolTip = "Switch between an 800 px reading column and window width"
        editButton.target = self
        editButton.action = #selector(requestEdit(_:))
        editButton.bezelStyle = .rounded
        webView.commandKeyHandler = { [weak self] key in
            switch key.lowercased() {
            case "+", "=":
                self?.zoomIn(nil)
            case "-":
                self?.zoomOut(nil)
            case "0":
                self?.resetZoom(nil)
            case "w":
                self?.view.window?.performClose(nil)
            case "q":
                NSApp.terminate(nil)
            default:
                return false
            }
            return true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        userContentController.removeScriptMessageHandler(forName: "previewMD")
    }

    override func loadView() {
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")

        let container = NSView()
        let header = NSVisualEffectView()
        header.material = .titlebar
        header.blendingMode = .withinWindow
        header.state = .active

        let controls = NSStackView(views: [readingWidthButton, editButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        header.translatesAutoresizingMaskIntoConstraints = false
        controls.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(controls)
        container.addSubview(header)
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 42),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            controls.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    func show(markdown: String, fileURL: URL?) {
        let title = fileURL?.deletingPathExtension().lastPathComponent ?? "PreviewMD"
        let baseURL = fileURL?.deletingLastPathComponent()
        zoomPreferenceKey = fileURL.map(DocumentState.zoomPreferenceKey(for:))
        readingWidthPreferenceKey = fileURL.map(DocumentState.readingWidthPreferenceKey(for:))
        documentURL = fileURL
        restoreZoom()
        restoreReadingWidthMode()
        updateHeaderControls()
        webView.loadHTMLString(
            MarkdownHTML.document(
                markdown: markdown,
                title: title,
                fillsAvailableWidth: readingWidthMode == .fluid,
                tableColumnWidths: restoredTableColumnWidths()
            ),
            baseURL: baseURL
        )
    }

    func showEmptyState() {
        zoomPreferenceKey = nil
        readingWidthPreferenceKey = nil
        documentURL = nil
        readingWidthMode = .fixed
        webView.pageZoom = 1
        updateHeaderControls()
        webView.loadHTMLString(MarkdownHTML.emptyDocument(), baseURL: nil)
    }

    func showError(_ error: Error) {
        zoomPreferenceKey = nil
        readingWidthPreferenceKey = nil
        documentURL = nil
        readingWidthMode = .fixed
        webView.pageZoom = 1
        updateHeaderControls()
        webView.loadHTMLString(MarkdownHTML.errorDocument(message: error.localizedDescription), baseURL: nil)
    }

    @objc func zoomIn(_ sender: Any?) {
        changeZoom(by: zoomStep)
    }

    @objc func zoomOut(_ sender: Any?) {
        changeZoom(by: -zoomStep)
    }

    @objc func resetZoom(_ sender: Any?) {
        webView.pageZoom = 1
        saveZoom()
    }

    @objc func toggleReadingWidth(_ sender: Any?) {
        readingWidthMode = readingWidthMode == .fixed ? .fluid : .fixed
        if let readingWidthPreferenceKey {
            UserDefaults.standard.set(readingWidthMode.rawValue, forKey: readingWidthPreferenceKey)
        }
        let mode = readingWidthMode == .fluid ? "fluid" : "fixed"
        webView.evaluateJavaScript("window.previewMD && window.previewMD.setReadingWidthMode('\(mode)')")
        updateHeaderControls()
        readingWidthModeDidChange?(readingWidthMode)
    }

    @objc private func requestEdit(_ sender: Any?) {
        editRequested?()
    }

    private func changeZoom(by amount: CGFloat) {
        webView.pageZoom = min(maximumZoom, max(minimumZoom, webView.pageZoom + amount))
        saveZoom()
    }

    private func restoreZoom() {
        guard let zoomPreferenceKey,
              let value = UserDefaults.standard.object(forKey: zoomPreferenceKey) as? NSNumber else {
            webView.pageZoom = 1
            return
        }
        webView.pageZoom = min(maximumZoom, max(minimumZoom, CGFloat(value.doubleValue)))
    }

    private func saveZoom() {
        guard let zoomPreferenceKey else { return }
        UserDefaults.standard.set(Double(webView.pageZoom), forKey: zoomPreferenceKey)
    }

    private func restoreReadingWidthMode() {
        guard let readingWidthPreferenceKey,
              let value = UserDefaults.standard.string(forKey: readingWidthPreferenceKey),
              let restoredMode = DocumentState.ReadingWidthMode(rawValue: value) else {
            readingWidthMode = .fixed
            return
        }
        readingWidthMode = restoredMode
    }

    private func restoredTableColumnWidths() -> [[Double]] {
        guard let documentURL else { return [] }
        if let widths = DocumentState.tableColumnWidths(fromSidecarFor: documentURL) {
            return widths
        }
        guard let data = UserDefaults.standard.data(forKey: DocumentState.tableColumnWidthsPreferenceKey(for: documentURL)),
              let widths = try? JSONDecoder().decode([[Double]].self, from: data) else {
            return []
        }
        if !widths.isEmpty {
            try? DocumentState.saveTableColumnWidths(widths, for: documentURL)
        }
        return widths
    }

    private func saveTableColumnWidths(_ widths: [[Double]]) {
        guard let documentURL else { return }
        do {
            try DocumentState.saveTableColumnWidths(widths, for: documentURL)
        } catch {
            NSLog("PreviewMD could not save table widths: \(error.localizedDescription)")
        }
    }

    private func updateHeaderControls() {
        readingWidthButton.title = readingWidthMode == .fixed ? "Width: 800" : "Width: Window"
        readingWidthButton.sizeToFit()
        editButton.isEnabled = readingWidthPreferenceKey != nil
        editButton.sizeToFit()
    }
}

extension MarkdownPreviewViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "previewMD",
              let body = message.body as? [String: Any],
              body["type"] as? String == "tableColumnWidths",
              let tables = body["tables"] as? [[Any]] else { return }

        let widths = tables.compactMap { table -> [Double]? in
            let values = table.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard values.count == table.count,
                  values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
            return values
        }
        guard widths.count == tables.count else { return }
        saveTableColumnWidths(widths)
    }
}
