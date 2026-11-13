import AppKit
import UniformTypeIdentifiers

final class ReaderWindow: NSWindowController, NSWindowDelegate {
    let preview = MarkdownPreviewViewController()
    private(set) var snapshot: MarkdownSnapshot?
    private var history: [(URL, [String: Double])] = []
    private var generation = 0
    private(set) var isOpening = false
    private var changingFrame = false
    private var failedReload = false
    var closed: (() -> Void)?
    var openRequested: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PreviewMD"; window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = preview; window.delegate = self; window.center()
        preview.profileChanged = { [weak self] in self?.reload(force: true) }
        preview.openRequested = { [weak self] in self?.openRequested?() }
        preview.backRequested = { [weak self] in self?.back() }
        preview.reloadRequested = { [weak self] in self?.reload(force: true) }
        preview.editRequested = { [weak self] in self?.openInEditor() }
        preview.linkRequested = { [weak self] in self?.navigate($0) }
        preview.showEmptyState()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func open(_ url: URL, remember: Bool = false, position: [String: Double]? = nil, anchor: String? = nil) {
        do {
            let next = try MarkdownSnapshot.read(url)
            isOpening = true
            generation += 1
            let expected = generation
            preview.capturePosition { [weak self] previousPosition in
                guard let self, self.generation == expected else { return }
                if remember, let previous = self.snapshot { self.history.append((previous.url, previousPosition)) }
                self.isOpening = false
                self.saveFrame()
                self.snapshot = next
                self.changingFrame = true
                DocumentState.migrateLegacySmallWindowFrameIfNeeded(for: next.url)
                if let frame = DocumentState.savedWindowFrame(for: next.url) { self.window?.setFrame(from: frame) }
                else { self.window?.setContentSize(NSSize(width: 1200, height: 900)); self.window?.center() }
                self.changingFrame = false
                self.window?.title = next.url.lastPathComponent
                self.window?.representedURL = next.url
                self.preview.show(markdown: next.text, fileURL: next.url, position: position, anchor: anchor)
                self.preview.canGoBack = !self.history.isEmpty
                self.showWindow(nil)
            }
        } catch { preview.showError(error); showWindow(nil) }
    }

    func reload(force: Bool) {
        guard !isOpening, let previous = snapshot else { return }
        do {
            let next = try MarkdownSnapshot.read(previous.url)
            guard force || failedReload || preview.resolvedProfile == .obsidian || next.data != previous.data else { return }
            generation += 1
            let expected = generation
            preview.capturePosition { [weak self] position in
                guard let self, self.generation == expected else { return }
                self.snapshot = next
                self.failedReload = false
                self.preview.show(markdown: next.text, fileURL: next.url, position: position)
            }
        } catch { failedReload = true; preview.showError(error) }
    }

    func back() {
        guard let entry = history.last else { return }
        // Preserve the return route if the destination is no longer readable.
        do { _ = try MarkdownSnapshot.read(entry.0) }
        catch { preview.showNotice("Cannot return to the previous document. " + error.localizedDescription); return }
        history.removeLast()
        open(entry.0, position: entry.1)
    }

    func navigate(_ url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return }
        if ["http", "https", "mailto"].contains(scheme) { NSWorkspace.shared.open(url); return }
        guard url.isFileURL else { preview.showNotice("This link type is not supported."); return }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let fragment = components.fragment
        components.fragment = nil
        guard let target = components.url else { return }
        if target.standardizedFileURL == snapshot?.url {
            if let fragment { preview.goToAnchor(fragment) }
            return
        }
        guard ["md", "markdown", "mdown", "mkdn"].contains(target.pathExtension.lowercased()) else {
            preview.showNotice("This local link is not a supported Markdown document. Open the file from Finder.")
            return
        }
        open(target, remember: true, anchor: fragment)
    }

    func openInEditor() {
        guard let url = snapshot?.url else { return }
        let preferred = UserDefaults.standard.url(forKey: "PreviewMD.Editor")
        let code = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
        if let app = preferred ?? code, FileManager.default.fileExists(atPath: app.path) {
            launchEditor(app, file: url)
        } else { chooseEditor() }
    }

    @objc func chooseEditor() {
        guard let url = snapshot?.url, let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a Text Editor"
        panel.message = "Choose an installed editor for this Markdown file. PreviewMD will keep the document open for reading."
        panel.prompt = "Open in Editor"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let app = panel.url else { return }
            guard Bundle(url: app)?.bundleIdentifier != Bundle.main.bundleIdentifier,
                  Bundle(url: app)?.bundleIdentifier != "com.vitalyterenin.preview-md",
                  app.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else {
                self?.preview.showNotice("Choose a text editor rather than PreviewMD."); return
            }
            UserDefaults.standard.set(app, forKey: "PreviewMD.Editor")
            self?.launchEditor(app, file: url)
        }
    }

    private func launchEditor(_ app: URL, file: URL) {
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.preview.showNotice("Could not open the editor. " + error.localizedDescription + " Use File → Choose Editor… to select another app.") } }
        }
    }

    private func saveFrame() {
        guard !changingFrame, let url = snapshot?.url else { return }
        window?.saveFrame(usingName: DocumentState.windowAutosaveName(for: url))
    }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowWillClose(_ notification: Notification) {
        generation += 1; saveFrame(); preview.capturePosition { _ in }; closed?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var readers: [ReaderWindow] = []
    private var pendingURLs: [URL] = []
    private var ready = false
    private var updateSettings: UpdateSettingsController?
    private var active: ReaderWindow? { readers.first { $0.window === NSApp.keyWindow } ?? readers.last }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        updateSettings = UpdateSettingsController()
        buildMainMenu()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        ready = true
        if pendingURLs.isEmpty { _ = newReader() }
        else { let urls = pendingURLs; pendingURLs = []; openFiles(urls) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { if let reader = readers.last { reader.showWindow(nil) } else { _ = newReader() } }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        for reader in readers where reader.window?.isVisible == true { reader.reload(force: false) }
    }
    func application(_ application: NSApplication, open urls: [URL]) { openFiles(urls) }
    func application(_ sender: NSApplication, openFile filename: String) -> Bool { openFiles([URL(fileURLWithPath: filename)]); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        openFiles(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success)
    }
    private func newReader() -> ReaderWindow {
        let reader = ReaderWindow()
        readers.append(reader)
        reader.openRequested = { [weak self] in self?.openDocument(nil) }
        reader.closed = { [weak self, weak reader] in self?.readers.removeAll { $0 === reader } }
        reader.showWindow(nil)
        return reader
    }
    private func openFiles(_ urls: [URL]) {
        guard ready else { pendingURLs.append(contentsOf: urls); return }
        for url in urls {
            if let existing = readers.first(where: { $0.snapshot?.url == url.standardizedFileURL }) {
                existing.reload(force: true); existing.showWindow(nil)
            } else {
                let reader = readers.first { $0.snapshot == nil && !$0.isOpening } ?? newReader()
                reader.open(url)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        if let window = active?.window {
            panel.beginSheetModal(for: window) { [weak self] result in if result == .OK { self?.openFiles(panel.urls) } }
        } else if panel.runModal() == .OK { openFiles(panel.urls) }
    }
    @objc private func reload(_ sender: Any?) { active?.reload(force: true) }
    @objc private func back(_ sender: Any?) { active?.back() }
    @objc private func find(_ sender: Any?) { active?.preview.showFind(sender) }
    @objc private func findNext(_ sender: Any?) { active?.preview.findNext() }
    @objc private func findPrevious(_ sender: Any?) { active?.preview.findPrevious() }
    @objc private func zoomIn(_ sender: Any?) { active?.preview.zoomIn(sender) }
    @objc private func zoomOut(_ sender: Any?) { active?.preview.zoomOut(sender) }
    @objc private func resetZoom(_ sender: Any?) { active?.preview.resetZoom(sender) }
    @objc private func chooseEditor(_ sender: Any?) { active?.chooseEditor() }
    @MainActor @objc private func showUpdates(_ sender: Any?) { updateSettings?.present() }

    private func buildMainMenu() {
        let main = NSMenu(title: "Main Menu")
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        let application = menu("PreviewMD")
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu(title: "Settings"); settings.submenu = settingsMenu; application.addItem(settings)
        add(settingsMenu, "Software Updates…", #selector(showUpdates(_:)), ",")
        application.addItem(.separator())
        application.addItem(withTitle: "Quit PreviewMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = menu("File")
        add(file, "Open…", #selector(openDocument(_:)), "o")
        add(file, "Reload", #selector(reload(_:)), "r")
        add(file, "Choose Editor…", #selector(chooseEditor(_:)))
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = menu("Edit")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, "Find…", #selector(find(_:)), "f")
        add(edit, "Find Next", #selector(findNext(_:)), "g")
        add(edit, "Find Previous", #selector(findPrevious(_:)), "G")
        let view = menu("View")
        add(view, "Back", #selector(back(_:)), "[")
        add(view, "Zoom In", #selector(zoomIn(_:)), "+")
        add(view, "Zoom Out", #selector(zoomOut(_:)), "-")
        add(view, "Actual Size", #selector(resetZoom(_:)), "0")
        let windows = menu("Window"); NSApp.windowsMenu = windows
        NSApp.mainMenu = main
    }
}

#if !PREVIEWMD_TESTING
@main
enum PreviewMDMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if let index = CommandLine.arguments.firstIndex(of: "--updates-smoke"), CommandLine.arguments.count > index + 1 {
            app.finishLaunching()
            let settings = UpdateSettingsController(startingUpdater: true)
            settings.verifySettings(stage: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--preview-updates") {
            app.finishLaunching()
            let settings = UpdateSettingsController(startingUpdater: false)
            settings.present()
            withExtendedLifetime(settings) { app.run() }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

#endif
