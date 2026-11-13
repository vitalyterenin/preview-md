import AppKit
import WebKit

/// A bounded, deterministic I/O pause, not a replacement renderer. The real
/// file read, parsing, sidecar read and HTML preparation run after release.
private final class PreparationGate {
    private let lock = NSLock()
    private var armed = false
    private var entered = false
    private var afterPreparation = false
    private var semaphore = DispatchSemaphore(value: 0)
    private var calls = 0
    private var offMain = true
    func arm(afterPreparation: Bool = false) { lock.lock(); armed = true; entered = false; self.afterPreparation = afterPreparation; semaphore = DispatchSemaphore(value: 0); lock.unlock() }
    var started: Bool { lock.lock(); defer { lock.unlock() }; return entered }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var stayedOffMain: Bool { lock.lock(); defer { lock.unlock() }; return offMain }
    func release() { lock.lock(); let current = semaphore; lock.unlock(); current.signal() }
    func prepare(_ request: DocumentLoader.Request) throws -> PreparedDocument? {
        lock.lock()
        calls += 1; offMain = offMain && !Thread.isMainThread
        let pause = armed; armed = false
        let after = afterPreparation
        if pause && !after { entered = true }
        let current = semaphore
        lock.unlock()
        if pause && !after, current.wait(timeout: .now() + 5) == .timedOut { throw CocoaError(.fileReadUnknown) }
        let result = try DocumentLoader.prepare(request)
        if pause && after {
            lock.lock(); entered = true; lock.unlock()
            if current.wait(timeout: .now() + 5) == .timedOut { throw CocoaError(.fileReadUnknown) }
        }
        return result
    }
}

extension ReadingSmoke {
    @MainActor static func runLoading(root: URL) async throws {
        let fixture = root.appendingPathComponent("async-reading")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let a = fixture.appendingPathComponent("a.md"), b = fixture.appendingPathComponent("b.md"), c = fixture.appendingPathComponent("c.md")
        for (url, label) in [(a, "ALPHA"), (b, "BETA"), (c, "LATEST")] {
            try ("# " + label + "\n\n| A | B |\n| --- | --- |\n| one | two |\n\n" + String(repeating: "Reading position paragraph.\n\n", count: 70)).write(to: url, atomically: true, encoding: .utf8)
        }
        let gate = PreparationGate()
        let loader = DocumentLoader(prepare: gate.prepare)
        let reader = ReaderWindow(loader: loader)
        let web = reader.preview.webView
        gate.arm(); reader.open(a)
        try await wait("Background preparation starts without blocking main events") { gate.started }
        var mainEventDelivered = false
        DispatchQueue.main.async { mainEventDelivered = true }
        try await wait("Main event delivered while disk preparation is paused") { mainEventDelivered }
        for _ in 0..<40 { reader.open(b) }
        reader.open(c)
        try expect(loader.pendingCount == 1 && gate.count == 1, "Repeated requests must replace one pending operation, not queue 40 reads")
        gate.release()
        try await wait("Only the latest navigation commits") {
            guard reader.snapshot?.url == c && !reader.isLoading && !loader.isRunning else { return false }
            return (try? await js(web, "document.body.innerText.includes('LATEST')")) as? Bool == true
        }
        try expect(gate.count == 2 && gate.stayedOffMain, "Only active and newest pending preparations execute, both off main")
        try expect(DocumentState.position(for: a).isEmpty && DocumentState.position(for: b).isEmpty, "Discarded documents must not acquire another page's position")
        _ = try await js(web, "scrollTo(0,600)")
        gate.arm(); reader.reload(force: true)
        try await wait("Reload pause") { gate.started }
        reader.preview.setProfile(.commonMark)
        reader.preview.setProfile(.github)
        reader.preview.setProfile(.obsidian)
        try expect(loader.pendingCount == 1, "Profile changes coalesce while a reload is running")
        gate.release()
        try await wait("Latest profile commits and retains the position") {
            guard reader.preview.resolvedProfile == .obsidian && !reader.isLoading && !loader.isRunning else { return false }
            return abs(((try? await js(web, "scrollY")) as? Double ?? 0) - 600) < 5
        }
        // Pause after sidecar bytes are captured, then change the live table.
        // An old prepared page must not undo the newer successful save.
        let previousDOMToken = try await js(web, "window.previewMD.documentToken") as? String
        gate.arm(afterPreparation: true); reader.reload(force: true)
        try await wait("Prepared page waits before commit") { gate.started }
        let oldRevision = reader.preview.tablePreferencesRevision
        _ = try await js(web, "document.querySelector('.table-resize-handle').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}))")
        try await wait("Resize is persisted during prepared reload") { reader.preview.tablePreferencesRevision > oldRevision }
        let latestWidths = try await js(web, "JSON.stringify([...document.querySelectorAll('col')].map(x=>x.style.width))") as? String
        gate.release()
        try await wait("Prepared reload reconciles latest table widths") {
            guard !reader.isLoading && !loader.isRunning else { return false }
            guard try await js(web, "window.previewMD.documentToken") as? String != previousDOMToken else { return false }
            return try await js(web, "JSON.stringify([...document.querySelectorAll('col')].map(x=>x.style.width))") as? String == latestWidths
        }
        // Superseded reloads must not overwrite a newer linked-document result.
        gate.arm(); reader.reload(force: true)
        try await wait("Navigation during reload pause") { gate.started }
        reader.navigate(b)
        gate.release()
        try await wait("New navigation supersedes old reload") { reader.snapshot?.url == b && !reader.isLoading && !loader.isRunning }
        try expect(reader.preview.canGoBack, "Committed navigation must preserve one return route")
        let moved = fixture.appendingPathComponent("temporarily-moved.md")
        try FileManager.default.moveItem(at: c, to: moved)
        reader.back()
        try await wait("Failed asynchronous Back completes") { !reader.isLoading }
        try expect(reader.snapshot?.url == b && reader.preview.canGoBack, "Failed Back must preserve the current note and return route")
        try FileManager.default.moveItem(at: moved, to: c)
        reader.back()
        try await wait("Back retries successfully") { reader.snapshot?.url == c && !reader.isLoading && !loader.isRunning }
        gate.arm(); reader.reload(force: true)
        try await wait("Close during active preparation") { gate.started }
        reader.open(a)
        reader.close()
        try expect(loader.pendingCount == 0, "Closing removes pending work")
        gate.release()
        try await wait("Closed reader worker finishes") { !loader.isRunning }
        try expect(reader.window?.isVisible == false && reader.snapshot?.url == c && !reader.isLoading, "Late completion cannot reopen or change a closed reader")
        try await verifyLargeVaultResponsiveness(root: root)
        print("Verified background preparation, bounded latest-only work, profile/navigation/close ownership, position, concurrent table saves and failed Back recovery")
    }
    @MainActor private static func verifyLargeVaultResponsiveness(root: URL) async throws {
        let vault = root.appendingPathComponent("responsive-vault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        for index in 0..<10000 {
            try Data("# Synthetic note\n".utf8).write(to: vault.appendingPathComponent("note-\(index).md"))
        }
        let home = vault.appendingPathComponent("home.md")
        let source = (0..<100).map { "[[note-\($0)]]" }.joined(separator: "\n\n")
        try source.write(to: home, atomically: true, encoding: .utf8)
        let otherURL = root.appendingPathComponent("other-responsive-window.md")
        try "# Other window".write(to: otherURL, atomically: true, encoding: .utf8)
        let other = ReaderWindow(); other.open(otherURL)
        try await wait("Independent window before large render") { other.snapshot?.url == otherURL && !other.isLoading }
        let large = ReaderWindow()
        var lastTick = ProcessInfo.processInfo.systemUptime
        var maximumGap = 0.0, ticks = 0
        var controlWorkedDuringPreparation = false
        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        heartbeat.setEventHandler {
            let now = ProcessInfo.processInfo.systemUptime
            maximumGap = max(maximumGap, now - lastTick); lastTick = now; ticks += 1
        }
        heartbeat.resume()
        defer { heartbeat.cancel(); large.close(); other.close() }
        let started = ProcessInfo.processInfo.systemUptime
        large.open(home)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            other.preview.toggleReadingWidth(nil)
            controlWorkedDuringPreparation = large.isLoading && other.preview.readingWidthMode == .fluid
        }
        try await wait("Large real reader renders all links") {
            guard large.snapshot?.url == home && !large.isLoading else { return false }
            return (try? await js(large.preview.webView, "document.querySelectorAll('a.wikilink').length === 100")) as? Bool == true
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        try expect(controlWorkedDuringPreparation, "Another window's control must work during real vault preparation")
        try expect(ticks >= 5 && maximumGap < 0.1, "Real reader main-thread heartbeat exceeded 100 ms: \(maximumGap)")
        print("Real ReaderWindow 10000-file/100-link load: \(elapsed) s; main-thread maximum heartbeat gap: \(maximumGap) s; ticks: \(ticks)")
    }

}
