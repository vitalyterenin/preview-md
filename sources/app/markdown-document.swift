import AppKit

final class MarkdownDocument: NSDocument, NSWindowDelegate {
    private var markdown = ""
    private weak var previewController: MarkdownPreviewViewController?
    private var checkedInitialWindowSize = false

    override class var autosavesInPlace: Bool { false }

    override func read(from url: URL, ofType typeName: String) throws {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) {
                markdown = text
                return
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    override func makeWindowControllers() {
        let previewController = MarkdownPreviewViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 900, height: 650)
        let hasUsableSavedFrame: Bool
        if let fileURL {
            DocumentState.migrateLegacySmallWindowFrameIfNeeded(for: fileURL)
            if let savedFrame = DocumentState.savedWindowFrame(for: fileURL) {
                window.setFrame(from: savedFrame)
                hasUsableSavedFrame = true
            } else {
                hasUsableSavedFrame = false
            }
        } else {
            hasUsableSavedFrame = false
        }
        window.delegate = self
        window.contentViewController = previewController
        self.previewController = previewController
        previewController.editRequested = { [weak self] in
            self?.openInVSCode(nil)
        }
        let windowController = NSWindowController(window: window)
        addWindowController(windowController)
        previewController.show(markdown: markdown, fileURL: fileURL)
        if !hasUsableSavedFrame {
            DispatchQueue.main.async {
                window.setContentSize(NSSize(width: 1200, height: 900))
                window.center()
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame(notification)
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame(notification)
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame(notification)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !checkedInitialWindowSize else { return }
        checkedInitialWindowSize = true
        DispatchQueue.main.async { [weak self] in
            self?.expandSmallWindowIfNeeded(notification)
        }
    }

    private func saveWindowFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let fileURL else { return }
        window.saveFrame(usingName: DocumentState.windowAutosaveName(for: fileURL))
    }

    private func expandSmallWindowIfNeeded(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.frame.width <= 700 || window.frame.height <= 560 else { return }
        window.setContentSize(NSSize(width: 1200, height: 900))
        window.center()
        saveWindowFrame(notification)
    }

    @objc private func openInVSCode(_ sender: Any?) {
        guard let fileURL else { return }

        let codeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
            ?? URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        guard FileManager.default.fileExists(atPath: codeURL.path) else {
            let alert = NSAlert()
            alert.messageText = "VS Code is not installed."
            alert.informativeText = "Install Visual Studio Code to edit this document."
            alert.runModal()
            return
        }

        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: codeURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self.presentError(error)
            }
        }
    }
}
