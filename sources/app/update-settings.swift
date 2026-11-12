import AppKit
import Sparkle

@MainActor
final class UpdateSettingsController: NSWindowController {
    let updaterController: SPUStandardUpdaterController
    let checkButton = NSButton(title: "Check for Updates…", target: nil, action: nil)
    let automaticChecks = NSButton(checkboxWithTitle: "Automatically Check for Updates", target: nil, action: nil)
    let automaticInstallation = NSButton(checkboxWithTitle: "Automatically Install Updates", target: nil, action: nil)
    let versionLabel: NSTextField
    private var observations: [NSKeyValueObservation] = []

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater, updaterDelegate: nil, userDriverDelegate: nil
        )
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        versionLabel = NSTextField(labelWithString: "Version \(version)")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 230),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Software Updates"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let heading = NSTextField(labelWithString: "Software Updates")
        heading.font = .boldSystemFont(ofSize: 17)
        let stack = NSStackView(views: [heading, checkButton, automaticChecks, automaticInstallation, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24)
        ])
        checkButton.target = updaterController
        checkButton.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        automaticChecks.target = self
        automaticChecks.action = #selector(changeAutomaticChecks(_:))
        automaticInstallation.target = self
        automaticInstallation.action = #selector(changeAutomaticInstallation(_:))
        let updater = updaterController.updater
        observations = [
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            },
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        ]
        refresh()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(startingUpdater:)") }

    func refresh() {
        let updater = updaterController.updater
        checkButton.isEnabled = updater.canCheckForUpdates
        automaticChecks.state = updater.automaticallyChecksForUpdates ? .on : .off
        automaticInstallation.state = updater.automaticallyDownloadsUpdates ? .on : .off
        automaticInstallation.isEnabled = updater.automaticallyChecksForUpdates
    }

    @objc private func changeAutomaticChecks(_ sender: NSButton) {
        updaterController.updater.automaticallyChecksForUpdates = sender.state == .on
        refresh()
    }

    @objc private func changeAutomaticInstallation(_ sender: NSButton) {
        updaterController.updater.automaticallyDownloadsUpdates = sender.state == .on
        refresh()
    }

    func present() {
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Used only in an isolated, unique test bundle by scripts/check-app.py.
    func verifySettings(stage: String) {
        precondition(Bundle.main.bundleIdentifier?.contains(".settings-test.") == true)
        let updater = updaterController.updater
        refresh()
        precondition(checkButton.title == "Check for Updates…")
        precondition(checkButton.isEnabled)
        precondition(checkButton.target === updaterController)
        precondition(checkButton.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        precondition(versionLabel.stringValue == "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!)")
        if stage == "fresh" {
            precondition(updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates)
            precondition(updater.updateCheckInterval == 14400)
            automaticInstallation.performClick(nil)
            precondition(!updater.automaticallyDownloadsUpdates)
            automaticChecks.performClick(nil)
            precondition(!updater.automaticallyChecksForUpdates)
        } else if stage == "relaunch" {
            precondition(!updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates)
            precondition(!automaticInstallation.isEnabled)
            let manualReadiness = checkButton.isEnabled
            automaticChecks.performClick(nil)
            precondition(updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates)
            precondition(automaticInstallation.isEnabled && checkButton.isEnabled == manualReadiness)
            automaticInstallation.performClick(nil)
            precondition(updater.automaticallyDownloadsUpdates)
            automaticChecks.performClick(nil)
            precondition(!automaticInstallation.isEnabled && !updater.automaticallyDownloadsUpdates)
            precondition(UserDefaults.standard.bool(forKey: "SUAutomaticallyUpdate"))
            precondition(checkButton.isEnabled == manualReadiness)
        } else {
            precondition(!updater.automaticallyChecksForUpdates)
            precondition(UserDefaults.standard.bool(forKey: "SUAutomaticallyUpdate"))
            precondition(!automaticInstallation.isEnabled)
            let manualReadiness = checkButton.isEnabled
            automaticChecks.performClick(nil)
            precondition(updater.automaticallyDownloadsUpdates)
            precondition(automaticInstallation.isEnabled && automaticInstallation.state == .on)
            precondition(checkButton.isEnabled == manualReadiness)
        }
        // Read Sparkle's actual state again, including changes made outside our controls.
        if stage == "resume" {
            updater.automaticallyDownloadsUpdates = false
            refresh()
            precondition(automaticInstallation.state == .off)
        }
        window?.orderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.display()
        for control in [checkButton, automaticChecks, automaticInstallation, versionLabel] as [NSView] {
            precondition(!control.isHidden && control.frame.width > 0 && control.frame.height > 0)
            precondition(window!.contentView!.bounds.contains(control.convert(control.bounds, to: window!.contentView)))
        }
        UserDefaults.standard.synchronize()
        print("Verified update settings: \(stage)")
    }
}
