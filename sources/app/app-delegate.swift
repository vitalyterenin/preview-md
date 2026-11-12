import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let previewController = MarkdownPreviewViewController()
    private var window: NSWindow!
    private var keyboardMonitor: Any?
    private var checkedInitialWindowSize = false
    private var openedFileURL: URL?
    private var updateSettings: UpdateSettingsController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        updateSettings = UpdateSettingsController()
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installKeyboardShortcuts()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PreviewMD"
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 900, height: 650)
        window.setFrameAutosaveName("PreviewMD.MainWindow")
        window.delegate = self
        window.contentViewController = previewController
        previewController.editRequested = { [weak self] in
            self?.openInVSCode(nil)
        }
        previewController.showEmptyState()
        DispatchQueue.main.async { [weak self] in
            self?.expandSmallMainWindowIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !checkedInitialWindowSize else { return }
        checkedInitialWindowSize = true
        DispatchQueue.main.async { [weak self] in
            self?.expandSmallMainWindowIfNeeded()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        open(url)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let filename = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        open(URL(fileURLWithPath: filename))
        sender.reply(toOpenOrPrint: .success)
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
    }

    @objc private func zoomIn(_ sender: Any?) {
        activePreviewController?.zoomIn(sender)
    }

    @objc private func zoomOut(_ sender: Any?) {
        activePreviewController?.zoomOut(sender)
    }

    @objc private func resetZoom(_ sender: Any?) {
        activePreviewController?.resetZoom(sender)
    }

    private func open(_ url: URL) {
        do {
            let markdown = try readMarkdown(from: url)
            openedFileURL = url
            previewController.show(markdown: markdown, fileURL: url)
            window.title = url.lastPathComponent
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            openedFileURL = nil
            previewController.showError(error)
            window.title = "PreviewMD"
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func readMarkdown(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private var activePreviewController: MarkdownPreviewViewController? {
        NSApp.keyWindow?.contentViewController as? MarkdownPreviewViewController
    }

    private func expandSmallMainWindowIfNeeded() {
        guard window.frame.width <= 700 || window.frame.height <= 560 else { return }
        window.setContentSize(NSSize(width: 1200, height: 900))
        window.center()
        window.saveFrame(usingName: "PreviewMD.MainWindow")
    }

    @objc private func openInVSCode(_ sender: Any?) {
        guard let openedFileURL else { return }

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
            [openedFileURL],
            withApplicationAt: codeURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                NSApp.presentError(error)
            }
        }
    }

    private func installKeyboardShortcuts() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  let key = event.charactersIgnoringModifiers else {
                return event
            }

            switch key.lowercased() {
            case "+", "=":
                self?.zoomIn(nil)
            case "-":
                self?.zoomOut(nil)
            case "0":
                self?.resetZoom(nil)
            case "w":
                NSApp.keyWindow?.performClose(nil)
            case "q":
                NSApp.terminate(nil)
            default:
                return event
            }
            return nil
        }
    }

    @MainActor @objc private func showSoftwareUpdates(_ sender: Any?) {
        updateSettings?.present()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")

        let applicationSubmenu = NSMenu(title: "PreviewMD")
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsSubmenu = NSMenu(title: "Settings")
        let softwareUpdates = NSMenuItem(title: "Software Updates…", action: #selector(showSoftwareUpdates(_:)), keyEquivalent: ",")
        softwareUpdates.target = self
        settingsSubmenu.addItem(softwareUpdates)
        settings.submenu = settingsSubmenu
        applicationSubmenu.addItem(settings)
        applicationSubmenu.addItem(.separator())
        applicationSubmenu.addItem(withTitle: "Quit PreviewMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationMenu = NSMenuItem(title: "PreviewMD", action: nil, keyEquivalent: "")
        applicationMenu.submenu = applicationSubmenu
        mainMenu.addItem(applicationMenu)

        let fileSubmenu = NSMenu(title: "File")
        fileSubmenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileSubmenu.addItem(.separator())
        fileSubmenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenu = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenu.submenu = fileSubmenu
        mainMenu.addItem(fileMenu)

        let viewSubmenu = NSMenu(title: "View")
        viewSubmenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        viewSubmenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewSubmenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom(_:)), keyEquivalent: "0")
        let viewMenu = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenu.submenu = viewSubmenu
        mainMenu.addItem(viewMenu)
        NSApp.mainMenu = mainMenu
    }
}

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
