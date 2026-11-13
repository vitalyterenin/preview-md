import AppKit
import WebKit

final class MarkdownPreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler, NSSearchFieldDelegate {
    let webView: WKWebView
    private let messages = WKUserContentController()
    private let openButton = NSButton(title: "Open…", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)
    private let widthButton = NSButton(title: "Width: 800", target: nil, action: nil)
    private let editButton = NSButton(title: "Open in Editor…", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let profilePicker = NSPopUpButton()
    private let profileReason = NSTextField(labelWithString: "")
    private(set) var resolvedProfile = MarkdownProfile.commonMark
    var profileChanged: (() -> Void)?
    private let findField = NSSearchField()
    private let findResult = NSTextField(labelWithString: "")
    private let findBar = NSStackView()
    private var readFailure: String?
    private var documentURL: URL?
    private var messageToken = UUID().uuidString
    private var tableIdentifiers: [String] = []
    private var pendingPosition: [String: Double] = [:]
    private var pendingAnchor: String?
    private(set) var readingWidthMode: DocumentState.ReadingWidthMode = .fixed
    var openRequested: (() -> Void)?
    var backRequested: (() -> Void)?
    var reloadRequested: (() -> Void)?
    var editRequested: (() -> Void)?
    var linkRequested: ((URL) -> Void)?
    var canGoBack = false { didSet { backButton.isEnabled = canGoBack } }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = messages
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        messages.add(WeakMessageHandler(self), name: "previewMD")
        webView.navigationDelegate = self
        for (button, action) in [(openButton, #selector(openFile)), (backButton, #selector(back)),
                                 (reloadButton, #selector(reload)), (widthButton, #selector(toggleReadingWidth(_:))),
                                 (editButton, #selector(edit))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
        }
        widthButton.toolTip = "Switch between an 800 px reading column and window width"
        editButton.toolTip = "Open this file in VS Code, or choose another installed editor"
        profilePicker.addItems(withTitles: MarkdownProfile.allCases.map(\.rawValue))
        profilePicker.target = self; profilePicker.action = #selector(selectProfile)
        profilePicker.setAccessibilityLabel("Markdown profile")
        profileReason.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        profileReason.textColor = .secondaryLabelColor
        findField.placeholderString = "Find in document"
        findField.delegate = self
        findField.target = self; findField.action = #selector(findNext)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func loadView() {
        let container = NSView()
        let controls = NSStackView(views: [openButton, backButton, reloadButton, widthButton, editButton])
        controls.spacing = 8
        let previous = NSButton(title: "Previous", target: self, action: #selector(findPrevious))
        let next = NSButton(title: "Next", target: self, action: #selector(findNext))
        let done = NSButton(title: "Done", target: self, action: #selector(hideFind))
        [findField, previous, next, findResult, done].forEach { findBar.addArrangedSubview($0) }
        findBar.spacing = 8; findBar.isHidden = true
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("reading-status")
        statusLabel.isHidden = true
        let profiles = NSStackView(views: [profilePicker, profileReason]); profiles.spacing = 8
        let header = NSStackView(views: [controls, profiles, findBar, statusLabel])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        [header, webView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; container.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor), header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor), webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor), webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
        updateControls()
    }

    func show(markdown: String, fileURL: URL, position: [String: Double]? = nil, anchor: String? = nil) {
        readFailure = nil
        documentURL = fileURL
        messageToken = UUID().uuidString
        pendingPosition = position ?? DocumentState.position(for: fileURL)
        pendingAnchor = anchor
        let defaults = UserDefaults.standard
        webView.pageZoom = min(2, max(0.6, (defaults.object(forKey: DocumentState.zoomPreferenceKey(for: fileURL)) as? NSNumber)?.doubleValue ?? 1))
        readingWidthMode = DocumentState.ReadingWidthMode(rawValue: defaults.string(forKey: DocumentState.readingWidthPreferenceKey(for: fileURL)) ?? "") ?? .fixed
        let requested = MarkdownProfile.preference(for: fileURL)
        profilePicker.selectItem(withTitle: requested.rawValue)
        let content = MarkdownHTML.render(markdown, fileURL: fileURL, profile: requested)
        resolvedProfile = content.decision.profile
        profileReason.stringValue = "\(content.decision.profile.rawValue) · \(content.decision.reason)"
        tableIdentifiers = content.tableIdentifiers
        let restored = DocumentState.restoreTableColumnWidths(for: fileURL, identifiers: tableIdentifiers)
        showNotice(restored.warning)
        updateControls()
        webView.loadHTMLString(MarkdownHTML.document(content: content, title: fileURL.lastPathComponent,
                                                    fillsAvailableWidth: readingWidthMode == .fluid,
                                                    tableColumnWidths: restored.widths, messageToken: messageToken), baseURL: fileURL)
    }

    func showEmptyState() {
        readFailure = nil
        documentURL = nil; tableIdentifiers = []; webView.pageZoom = 1
        updateControls(); showNotice(nil)
        webView.loadHTMLString(MarkdownHTML.emptyDocument(), baseURL: nil)
    }

    func showError(_ error: Error) {
        if documentURL != nil {
            readFailure = "Showing the last readable version. " + error.localizedDescription + " Use Reload to retry."
            showNotice(nil)
        }
        else { webView.loadHTMLString(MarkdownHTML.errorDocument(message: error.localizedDescription), baseURL: nil) }
    }

    func showNotice(_ message: String?) {
        let combined = [readFailure, message].compactMap { $0 }.joined(separator: "\n")
        statusLabel.stringValue = combined
        statusLabel.isHidden = combined.isEmpty
    }

    func capturePosition(_ completion: @escaping ([String: Double]) -> Void) {
        let url = documentURL
        webView.evaluateJavaScript("window.previewMD?.position()") { result, _ in
            let position = result as? [String: Double] ?? [:]
            if let url, !position.isEmpty { DocumentState.savePosition(position, for: url) }
            completion(position)
        }
    }

    func goToAnchor(_ anchor: String) {
        let quoted = String(data: try! JSONEncoder().encode(anchor), encoding: .utf8)!
        webView.evaluateJavaScript("window.previewMD?.goToAnchor(\(quoted))") { [weak self] result, _ in
            if result as? Bool != true { self?.showNotice("The linked section was not found in this document.") }
        }
    }

    @objc func showFind(_ sender: Any?) {
        guard documentURL != nil else { return }
        findBar.isHidden = false
        view.window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }
    @objc private func hideFind() { findBar.isHidden = true; view.window?.makeFirstResponder(webView) }
    @objc func findNext() { find(backwards: false) }
    @objc func findPrevious() { find(backwards: true) }
    func controlTextDidChange(_ obj: Notification) { find(backwards: false) }
    private func find(backwards: Bool) {
        guard !findField.stringValue.isEmpty else { findResult.stringValue = ""; return }
        let config = WKFindConfiguration(); config.backwards = backwards; config.caseSensitive = false; config.wraps = true
        webView.find(findField.stringValue, configuration: config) { [weak self] result in
            self?.findResult.stringValue = result.matchFound ? "Match found" : "No matches"
        }
    }

    @objc private func selectProfile() {
        guard let title = profilePicker.titleOfSelectedItem, let profile = MarkdownProfile(rawValue: title) else { return }
        setProfile(profile)
    }
    func setProfile(_ profile: MarkdownProfile) {
        guard let documentURL else { return }
        MarkdownProfile.save(profile, for: documentURL)
        profileChanged?()
    }

    @objc private func openFile() { openRequested?() }
    @objc private func back() { backRequested?() }
    @objc private func reload() { reloadRequested?() }
    @objc private func edit() { editRequested?() }
    @objc func zoomIn(_ sender: Any?) { changeZoom(0.1) }
    @objc func zoomOut(_ sender: Any?) { changeZoom(-0.1) }
    @objc func resetZoom(_ sender: Any?) { webView.pageZoom = 1; saveZoom() }
    private func changeZoom(_ amount: CGFloat) { webView.pageZoom = min(2, max(0.6, webView.pageZoom + amount)); saveZoom() }
    private func saveZoom() {
        if let documentURL { UserDefaults.standard.set(Double(webView.pageZoom), forKey: DocumentState.zoomPreferenceKey(for: documentURL)) }
    }
    @objc func toggleReadingWidth(_ sender: Any?) {
        readingWidthMode = readingWidthMode == .fixed ? .fluid : .fixed
        if let documentURL { UserDefaults.standard.set(readingWidthMode.rawValue, forKey: DocumentState.readingWidthPreferenceKey(for: documentURL)) }
        webView.evaluateJavaScript("window.previewMD?.setReadingWidthMode('\(readingWidthMode.rawValue)')")
        updateControls()
    }
    private func updateControls() {
        profilePicker.isEnabled = documentURL != nil
        if documentURL == nil { profileReason.stringValue = "Choose a profile after opening a document" }
        widthButton.title = readingWidthMode == .fixed ? "Width: 800" : "Width: Window"
        [widthButton, editButton, reloadButton].forEach { $0.isEnabled = documentURL != nil }
        backButton.isEnabled = canGoBack
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let encoded = String(data: try! JSONEncoder().encode(pendingPosition), encoding: .utf8)!
        webView.evaluateJavaScript("window.previewMD?.restorePosition(\(encoded))")
        if let anchor = pendingAnchor { goToAnchor(anchor); pendingAnchor = nil }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            if let url = navigationAction.request.url { linkRequested?(url) }
            return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "previewMD", let documentURL,
              let body = message.body as? [String: Any], body["token"] as? String == messageToken else { return }
        if body["type"] as? String == "position", let position = body["position"] as? [String: Double] {
            DocumentState.savePosition(position, for: documentURL)
        }
        guard body["type"] as? String == "tableColumnWidths", let widths = body["tables"] as? [[Double]],
              let identifiers = body["identifiers"] as? [String], identifiers == tableIdentifiers else { return }
        do {
            try DocumentState.saveTableColumnWidths(widths, for: documentURL, identifiers: identifiers)
            showNotice(nil)
        } catch { showNotice("Table widths apply for this session only. Could not save preferences: " + error.localizedDescription) }
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
