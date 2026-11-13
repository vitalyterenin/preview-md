import AppKit
import WebKit

@main
struct ReadingSmoke {
    @MainActor static func main() {
        precondition(Bundle.main.bundleIdentifier?.contains(".reading-test.") == true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        Task { @MainActor in
            do { try await run(); print("Reading workflow checks passed"); exit(0) }
            catch { fputs("Reading workflow failure: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }
    @MainActor static func js(_ view: WKWebView, _ source: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(source) { value, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value) }
            }
        }
    }
    @MainActor static func wait(_ description: String, _ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 {
            if (try? await condition()) == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure(description: "Timed out: " + description)
    }

    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixture = root.appendingPathComponent("fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let a = fixture.appendingPathComponent("reading a.md"), b = fixture.appendingPathComponent("related.md")
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"40\"><rect width=\"120\" height=\"40\" fill=\"red\"/></svg>"
        try svg.write(to: fixture.appendingPathComponent("image.svg"), atomically: true, encoding: .utf8)
        let source = """
        # Reading task

        Version: BEFORE.

        [Details](#details) [Related](related.md) [Bad](javascript:alert)

        ![Local illustration](image.svg)

        3. Third step
           - Child
             - Grandchild
        4. Fourth step

        [Reference][spec]

        [spec]: https://example.com/spec

        Line one\u{20}\u{20}
        Line two

        | Item | Value |
        | --- | ---: |
        | First | 42 |

        """ + (1...50).map { "\n\nParagraph \($0) has a synthetic passage for scrolling." }.joined() + "\n\n## Details\n\nAPRICOT-731\n\n## Details\n\nSecond section.\n\n## Раздел\n\nText.\n"
        try source.write(to: a, atomically: true, encoding: .utf8)
        try "# Related\n\nCurrent related file.".write(to: b, atomically: true, encoding: .utf8)
        let rendered = MarkdownHTML.render(source, fileURL: a)
        try expect(rendered.html.contains("<ol start=\"3\">"), "Ordered start must survive")
        try expect(rendered.html.components(separatedBy: "<ul>").count == 3, "Nested levels must survive")
        try expect(rendered.html.contains("href=\"https://example.com/spec\""), "Reference link must resolve")
        try expect(rendered.html.contains("<br />"), "Hard break must survive")
        try expect(rendered.html.contains("id=\"details-1\""), "Repeated headings need unique anchors")
        try expect(rendered.html.contains("id=\"раздел\""), "Unicode heading must have anchor")
        try expect(rendered.html.contains("src=\"data:image/svg+xml;base64,"), "Local image must be embedded")
        try expect(!rendered.html.contains("href=\"javascript:"), "Unsafe link must not survive")
        let unsafe = MarkdownHTML.render("<script>alert('x')</script>\n\n<img src=x onerror=alert(1)>")
        try expect(!unsafe.html.contains("<script>") && !unsafe.html.contains("<img"), "Raw HTML cannot become active content")
        let nestedFence = MarkdownHTML.render("````md\n```mermaid\nA-->B\n```\n````")
        try expect(nestedFence.html.contains("```mermaid") && nestedFence.html.contains("A--&gt;B"), "Nested fences remain literal")

        let tablesA = MarkdownHTML.render("| One | Value |\n| --- | --- |\n| A | B |\n\n| Two | Value |\n| --- | --- |\n| C | D |")
        try DocumentState.saveTableColumnWidths([[30,70],[60,40]], for: a, identifiers: tablesA.tableIdentifiers)
        let restored = DocumentState.restoreTableColumnWidths(for: a, identifiers: tablesA.tableIdentifiers.reversed())
        try expect(restored.widths == [[60,40],[30,70]], "Table reordering must preserve identity")
        let duplicates = DocumentState.restoreTableColumnWidths(for: a, identifiers: [tablesA.tableIdentifiers[0],tablesA.tableIdentifiers[0]])
        try expect(duplicates.widths == [[],[]], "Ambiguous tables must not inherit another layout")
        let before = try Data(contentsOf: DocumentState.tableColumnWidthsSidecarURL(for: a))
        try DocumentState.saveTableColumnWidths([[20,80]], for: a, identifiers: ["new-table"])
        let previous = DocumentState.restoreTableColumnWidths(for: a, identifiers: tablesA.tableIdentifiers)
        try expect(previous.widths == [[30,70],[60,40]], "Previous table values must not be discarded")
        try before.write(to: DocumentState.tableColumnWidthsSidecarURL(for: a))
        let bad = fixture.appendingPathComponent("broken.md")
        try "# Broken preferences".write(to: bad, atomically: true, encoding: .utf8)
        let badSidecar = DocumentState.tableColumnWidthsSidecarURL(for: bad)
        try Data("not json".utf8).write(to: badSidecar)
        try expect(DocumentState.restoreTableColumnWidths(for: bad, identifiers: []).warning != nil, "Corrupt sidecar must be reported")
        do { try DocumentState.saveTableColumnWidths([[50,50]], for: bad); throw Failure(description: "Corrupt sidecar was overwritten") }
        catch is Failure { throw Failure(description: "Corrupt sidecar was overwritten") } catch {}
        let malformed = Data("{\"formatVersion\":1,\"tableColumnWidths\":[],\"tableWidthsByID\":\"invalid\"}".utf8)
        try malformed.write(to: badSidecar)
        do { try DocumentState.saveTableColumnWidths([[50,50]], for: bad); throw Failure(description: "Malformed keyed data overwritten") }
        catch is Failure { throw Failure(description: "Malformed keyed data overwritten") } catch {}
        try expect(try Data(contentsOf: badSidecar) == malformed, "Malformed keyed data must remain intact")
        try Data("not json".utf8).write(to: badSidecar)
        try expect(try Data(contentsOf: badSidecar) == Data("not json".utf8), "Corrupt data must remain intact")

        let reader = ReaderWindow()
        reader.open(a)
        let web = reader.preview.webView
        try await wait("document visible") { try await js(web, "document.body.innerText.includes('BEFORE')") as? Bool == true }
        try await wait("local image decoded") { try await js(web, "document.images[0]?.naturalWidth === 120") as? Bool == true }
        try await wait("table wrapped") { try await js(web, "document.querySelectorAll('.table-frame col').length === 2") as? Bool == true }
        try expect(try await js(web, "getComputedStyle(document.querySelector('tbody td:last-child')).textAlign") as? String == "right", "Table alignment must survive the app stylesheet")
        let first = try await js(web, "document.querySelectorAll('ol > li')[1]?.textContent") as? String
        try expect(first?.contains("Fourth step") == true, "Actual WebKit must retain list semantics")
        _ = try await js(web, "scrollTo(0,900)")
        try await wait("scroll set") { (try await js(web, "scrollY") as? Double ?? 0) > 800 }
        try source.replacingOccurrences(of: "BEFORE", with: "AFTER").write(to: a, atomically: true, encoding: .utf8)
        reader.reload(force: false)
        try await wait("atomic save refreshed") { try await js(web, "document.body.innerText.includes('AFTER')") as? Bool == true }
        try await wait("position preserved") { abs((try await js(web, "scrollY") as? Double ?? 0) - 900) < 5 }
        let findConfig = WKFindConfiguration()
        let found: Bool = await withCheckedContinuation { continuation in
            web.find("APRICOT-731", configuration: findConfig) { continuation.resume(returning: $0.matchFound) }
        }
        try expect(found, "Native WebKit find must locate the passage")
        _ = try await js(web, "document.querySelector('a[href=\"#details\"]').click()")
        try await wait("heading anchor reached") { try await js(web, "document.getElementById('details').getBoundingClientRect().top >= 0 && document.getElementById('details').getBoundingClientRect().top < innerHeight") as? Bool == true }
        _ = try await js(web, "document.querySelector('a[href=\"related.md\"]').click()")
        try await wait("neighbor opens") { guard reader.snapshot?.url == b else { return false }; return (try await js(web, "document.body.innerText.includes('Current related')") as? Bool == true) }
        reader.back()
        try await wait("back opens original") { guard reader.snapshot?.url == a else { return false }; return (try await js(web, "document.body.innerText.includes('AFTER')") as? Bool == true) }
        try await wait("back restores passage") { try await js(web, "document.getElementById('details').getBoundingClientRect().top >= 0 && document.getElementById('details').getBoundingClientRect().top < innerHeight") as? Bool == true }
        let moved = fixture.appendingPathComponent("moved.md")
        try FileManager.default.moveItem(at: a, to: moved)
        reader.reload(force: true)
        try expect(try await js(web, "document.body.innerText.includes('AFTER')") as? Bool == true, "Missing file must preserve last readable content")
        func messages(_ view: NSView) -> [String] { (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(messages) }
        try expect(messages(reader.preview.view).contains(where: { $0.contains("last readable version") }), "Stale document must be disclosed")
        _ = try await js(web, "document.querySelector('.table-resize-handle').dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight',bubbles:true}))")
        try await Task.sleep(nanoseconds: 200_000_000)
        try expect(messages(reader.preview.view).contains(where: { $0.contains("last readable version") }), "Saving a layout must not hide a stale-file warning")
        try FileManager.default.moveItem(at: moved, to: a)
        reader.reload(force: true)
        try await wait("recovery clears stale status") { !messages(reader.preview.view).contains(where: { $0.contains("last readable version") }) }

        // Check the real script bridge using keyboard resizing, which is also the
        // accessible equivalent of dragging. The fixture alone owns these sidecars.
        _ = try await js(web, "document.querySelector('.table-resize-handle').dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight',bubbles:true}))")
        try await wait("table persisted through bridge") {
            DocumentState.restoreTableColumnWidths(for: a, identifiers: MarkdownHTML.render(source, fileURL:a).tableIdentifiers).widths.first?.count == 2
        }
        let blockedDir = fixture.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedDir, withIntermediateDirectories: true)
        try Data("obstruction".utf8).write(to: blockedDir.appendingPathComponent(".previewmd"))
        let blocked = blockedDir.appendingPathComponent("blocked.md")
        try "| A | B |\n| --- | --- |\n| x | y |".write(to: blocked, atomically:true, encoding:.utf8)
        reader.open(blocked)
        try await wait("blocked fixture loaded") { guard reader.snapshot?.url == blocked else { return false }; return (try await js(web, "document.querySelector('.table-resize-handle') !== null") as? Bool == true) }
        _ = try await js(web, "document.querySelector('.table-resize-handle').dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight',bubbles:true}))")
        try await wait("save failure visible") { messages(reader.preview.view).contains(where: { $0.contains("session only") }) }
        try expect(try String(contentsOf: blockedDir.appendingPathComponent(".previewmd"), encoding: .utf8) == "obstruction", "Failed save must preserve existing file")
        let independent = ReaderWindow()
        UserDefaults.standard.set(1.4, forKey: DocumentState.zoomPreferenceKey(for: b))
        UserDefaults.standard.set("fluid", forKey: DocumentState.readingWidthPreferenceKey(for: b))
        independent.open(b)
        try await wait("independent window ready") { independent.snapshot?.url == b }
        try expect(abs(independent.preview.webView.pageZoom - 1.4) < 0.01 && independent.preview.readingWidthMode == .fluid, "Per-document preferences must load in each window")
        try expect(abs(reader.preview.webView.pageZoom - 1) < 0.01 && reader.preview.readingWidthMode == .fixed, "Another document's preferences must remain independent")
        independent.preview.zoomIn(nil)
        independent.preview.toggleReadingWidth(nil)
        try expect(abs(UserDefaults.standard.double(forKey: DocumentState.zoomPreferenceKey(for: b)) - 1.5) < 0.01, "Zoom must persist for the right document")
        try expect(UserDefaults.standard.string(forKey: DocumentState.readingWidthPreferenceKey(for: b)) == "fixed", "Width must persist for the right document")
        independent.close()
        reader.close()

        // Quick Look uses these exact HTML bytes without a file base URL.
        let quick = WKWebView()
        quick.loadHTMLString(MarkdownHTML.document(content: rendered, title: "Quick Look"), baseURL: nil)
        try await wait("Quick Look HTML image decoded without file base URL") { try await js(quick, "document.images[0]?.naturalWidth === 120") as? Bool == true }
        quick.loadHTMLString(MarkdownHTML.document(markdown: "![Missing illustration](absent.svg)", title: "Missing", fileURL: a), baseURL: nil)
        try await wait("missing image explanation") { try await js(quick, "document.body.innerText.includes('Image unavailable: Missing illustration')") as? Bool == true }
        try expect(try String(contentsOf: a, encoding: .utf8) == source.replacingOccurrences(of: "BEFORE", with:"AFTER"), "Reader must never change Markdown source")
        try await runObsidian(root: root)
        print("Verified semantics, local SVG in both HTML contexts, CSP-safe markup, table identity/bridge/recovery, native find, atomic refresh/position, links/Back, stale-file recovery and source preservation")
    }
}
