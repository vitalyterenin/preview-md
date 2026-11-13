import AppKit
import WebKit

extension ReadingSmoke {
    @MainActor static func runObsidian(root: URL) async throws {
        try ObsidianFragmentChecks.run(root: root)
        let vault = root.appendingPathComponent("synthetic-vault")
        for path in [".obsidian", "notes", "assets", "one", "two"] {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let home = vault.appendingPathComponent("home.md")
        let target = vault.appendingPathComponent("notes/Заметка.md")
        let svg = vault.appendingPathComponent("assets/diagram.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"40\"><rect width=\"120\" height=\"40\" fill=\"red\"/></svg>".write(to: svg, atomically:true, encoding:.utf8)
        let targetText = """
        # Заметка

        ## Раздел

        TRANSCLUDED-HEADING

        A named paragraph with **formatting**. ^target

        ## Unrelated

        SHOULD-NOT-BE-IN-SECTION

        - List one
        - List two

        ^list-block
        """
        try targetText.write(to: target, atomically:true, encoding:.utf8)
        try "# Whole\n\nWHOLE-NOTE\n\n![[home]]".write(to:vault.appendingPathComponent("whole.md"), atomically:true, encoding:.utf8)
        for path in ["one/duplicate.md", "two/duplicate.md"] { try "# Duplicate".write(to: vault.appendingPathComponent(path), atomically:true, encoding:.utf8) }
        let source = """
        ---
        название: "Synthetic Russian properties"
        количество: 7
        готово: true
        дата: 2026-11-13
        quoted: "true"
        aliases: [Дом, Home]
        связи:
          - "[[Заметка|Linked property]]"
          - another value
        описание: |
          Literal **text**, not Markdown.
          Second line.
        ---
        # Home

        [[Заметка|Short link]] · [[notes/Заметка#Раздел|Heading link]] · [[Заметка#^target|Block link]]

        [Markdown vault link](notes/Заметка.md#Раздел)

        ![[diagram.svg|80x30]]

        ![[notes/Заметка#Раздел]]

        ![[Заметка#^target]]

        ![[Заметка#^list-block]]

        ![[whole]]

        > [!warning]- Folded **title**
        > FOLDED-BODY
        >
        > > [!tip]+ Nested
        > > NESTED-BODY

        A ==highlight with **bold**== and %%SECRET-COMMENT%% visible text.

        - [x] Complete task
        - [ ] Incomplete task

        A footnote.[^note]

        [^note]: FOOTNOTE-CONTENT

        [[missing]] · [[duplicate]] · ![[movie.mp4]]

        ```md
        [[literal-code]] ==literal-highlight== %%literal-comment%%
        ```

        `[[inline-code]]`
        """
        try source.write(to: home, atomically:true, encoding:.utf8)
        let originals = [home, target, svg].map { ($0, try! Data(contentsOf: $0)) }
        let detected = MarkdownProfile.resolve(.auto, source: source, fileURL: home)
        try expect(detected.profile == .obsidian && detected.reason.contains("vault"), "Vault context must choose Obsidian")
        let outside = root.appendingPathComponent("outside.md")
        try expect(MarkdownProfile.resolve(.auto, source: "A paragraph. ^block-id", fileURL: outside).profile == .obsidian, "A standalone linked note with a block ID needs Obsidian anchors outside a vault")
        for code in ["```md\n[[note]] ==mark== %%comment%%\n```", "`[[note]]` and `==mark==`", "    [[note]]\n", "\\[[escaped]]", "``Русский [[note]]``"] {
            try expect(MarkdownProfile.resolve(.auto, source: code, fileURL: outside).profile == .commonMark, "Code/escaped markers must not trigger Auto: " + code)
        }
        try expect(MarkdownProfile.resolve(.auto, source: "[[note]]", fileURL: outside).profile == .obsidian, "Outside-vault wikilink detection")
        try expect(MarkdownProfile.resolve(.auto, source: "| A | B |\n| --- | --- |", fileURL: outside).profile == .github, "Auto detects a pipe table")
        let common = MarkdownHTML.render("~~strike~~\n\n- [x] task\n\n| A | B |\n| --- | --- |\n\n[[Заметка]]\n\n==mark==", fileURL: home, profile: .commonMark).html
        try expect(!common.contains("<del>") && !common.contains("<table>") && !common.contains("checkbox") && !common.contains("<mark>") && !common.contains("wikilink"), "CommonMark override must disable all dialect extensions")
        let github = MarkdownHTML.render("- [x] Task\n\n~~strike~~\n\n[[Заметка]]\n\n==mark==", fileURL: home, profile: .github).html
        try expect(github.contains("checkbox") && github.contains("<del>") && !github.contains("wikilink") && !github.contains("<mark>"), "GitHub mode controls extensions")
        let rendered = MarkdownHTML.render(source, fileURL: home)
        try expect(rendered.html.contains("properties") && rendered.html.contains("количество") && rendered.html.contains("Number") && rendered.html.contains("Checkbox"), "Typed YAML properties")
        try expect(rendered.html.contains("Literal **text**, not Markdown."), "Property text must remain literal")
        try expect(rendered.html.contains("Missing target") && rendered.html.contains("Ambiguous target") && rendered.html.contains("Embed cycle"), "Missing/ambiguous/cyclic targets must be explained")
        try expect(!rendered.html.contains("SECRET-COMMENT"), "Obsidian comments must be hidden")
        try expect(rendered.html.contains("literal-code") && rendered.html.contains("literal-comment"), "OFM examples in code must remain literal")
        try expect(!rendered.html.contains("SHOULD-NOT-BE-IN-SECTION"), "Section transclusion must stop at the next peer heading")
        let heading = MarkdownHTML.render("# [[Заметка|Named heading]]", fileURL: home, profile: .obsidian).html
        try expect(heading.contains("id=\"named-heading\""), "Wiki label in a heading must have a stable readable anchor")
        let selfEmbed = MarkdownHTML.render("# Intro\n\n![[#Excerpt]]\n\n## Excerpt\n\nSelf section", fileURL: home, profile: .obsidian).html
        // The saved home does not contain Excerpt; missing sections stay explicit.
        try expect(selfEmbed.contains("Missing or ambiguous section"), "Unsaved section references must not silently embed a different block")
        let repeatedTables = vault.appendingPathComponent("tables.md")
        try "| A | B |\n| --- | --- |\n| A[^f] | B |\n\n[^f]: Footnote".write(to: repeatedTables, atomically:true, encoding:.utf8)
        let embeddedTables = "![[tables]]\n\n![[tables]]"
        let firstTableRender = MarkdownHTML.render(embeddedTables,fileURL:home,profile:.obsidian)
        let secondTableRender = MarkdownHTML.render(embeddedTables,fileURL:home,profile:.obsidian)
        try expect(firstTableRender.tableIdentifiers == secondTableRender.tableIdentifiers, "Embedded footnote IDs cannot invalidate table preferences between renders")
        let resolver = VaultResolver(fileURL: home)
        for bad in ["../outside.md", "/etc/passwd", "javascript:alert(1)", "file:///etc/passwd", "../../outside"] {
            if case .found = resolver.resolve(bad, from: home) { throw Failure(description: "Unsafe target accepted: " + bad) }
        }
        try "OUTSIDE PRIVATE FIXTURE".write(to:outside,atomically:true,encoding:.utf8)
        try FileManager.default.createSymbolicLink(at:vault.appendingPathComponent("escape.md"),withDestinationURL:outside)
        if case .found = VaultResolver(fileURL:home).resolve("./escape.md",from:home) { throw Failure(description:"Symlink escaped vault") }
        try Data(contentsOf: svg).write(to: root.appendingPathComponent("outside.svg"))
        let escapedImage = MarkdownHTML.render("![No escape](../outside.svg)", fileURL:home, profile:.obsidian).html
        try expect(!escapedImage.contains("base64,"), "Markdown image traversal cannot embed outside data")
        let selfNote = vault.appendingPathComponent("self.md")
        let selfSource = "# Self\n\n![[#Excerpt]]\n\n## Excerpt\n\nSELF-EXCERPT"
        try selfSource.write(to:selfNote,atomically:true,encoding:.utf8)
        let selfHTML = MarkdownHTML.render(selfSource,fileURL:selfNote,profile:.obsidian).html
        try expect(selfHTML.contains("note-embed") && !selfHTML.contains("Embed cycle"), "A same-note section embed is allowed when not recursive")
        let repeated = MarkdownHTML.render(String(repeating:"![[whole]]\n\n",count:70),fileURL:home,profile:.obsidian).html
        try expect(repeated.contains("Embed count limit"), "Fan-out has a global render budget")
        let duplicates = MarkdownHTML.render("---\nkey: one\nkey: two\n---\nBody",fileURL:home,profile:.obsidian).html
        try expect(duplicates.contains("Properties could not be read") && duplicates.contains("key: one") && duplicates.contains("key: two"), "Duplicate YAML keys preserve both original values")
        let malformed = MarkdownHTML.render("---\nbroken: [unterminated\n---\n# Readable body", fileURL:home, profile:.obsidian).html
        try expect(malformed.contains("Properties could not be read") && malformed.contains("unterminated") && malformed.contains("Readable body"), "Malformed YAML must preserve source and readable body")
        let aliases = MarkdownHTML.render("---\na: &a [one]\nb: *a\n---\n# Alias fallback",fileURL:home,profile:.obsidian).html
        try expect(aliases.contains("YAML aliases") && aliases.contains("Alias fallback"), "Alias expansion must be bounded by readable fallback")
        let webReader = ReaderWindow()
        webReader.open(home)
        let web = webReader.preview.webView
        try await wait("Obsidian properties and embeds") { try await js(web,"document.querySelectorAll('.properties .property').length === 8 && document.body.innerText.includes('TRANSCLUDED-HEADING')") as? Bool == true }
        try await wait("Obsidian image decoded") { try await js(web,"document.images[0]?.complete && document.images[0]?.naturalWidth > 0 && document.images[0]?.width === 80 && document.images[0]?.height === 30") as? Bool == true }
        try expect(try await js(web,"document.querySelector('mark strong')?.textContent === 'bold'") as? Bool == true,"Highlight keeps nested Markdown")
        try expect(try await js(web,"document.querySelector('details.callout')?.open === false && document.querySelector('summary')?.textContent.includes('Folded title')") as? Bool == true,"Folded callout has a real summary and starts closed")
        _ = try await js(web,"document.querySelector('summary').click()")
        try expect(try await js(web,"document.querySelector('details.callout').open") as? Bool == true,"Callout opens with native details behavior")
        try expect(try await js(web,"document.querySelectorAll('input[type=checkbox]').length === 3 && [...document.querySelectorAll('input[type=checkbox]')].every(x => x.disabled)") as? Bool == true,"Tasks and properties remain read-only")
        try expect(try await js(web,"document.body.innerText.includes('FOOTNOTE-CONTENT') && document.querySelectorAll('.note-embed').length >= 4") as? Bool == true,"Footnotes and whole/section/block/list embeds render")
        let config = WKFindConfiguration()
        let found: Bool = await withCheckedContinuation { continuation in web.find("TRANSCLUDED-HEADING",configuration:config) { continuation.resume(returning:$0.matchFound) } }
        try expect(found,"Find searches transcluded text")
        _ = try await js(web,"[...document.querySelectorAll('a')].find(x => x.textContent === 'Block link').click()")
        try await wait("Wikilink navigates to actual note") { guard webReader.snapshot?.url == target else { return false }; return (try? await js(web,"document.getElementById('block-target') !== null")) as? Bool == true }
        webReader.back()
        try await wait("Back returns to home") { guard webReader.snapshot?.url == home else { return false }; return (try? await js(web,"document.querySelector('.properties') !== null")) as? Bool == true }
        _ = try await js(web, "scrollTo(0,200)")
        webReader.preview.setProfile(.commonMark)
        try await wait("Manual CommonMark override") { guard webReader.preview.resolvedProfile == .commonMark else { return false }; return (try? await js(web,"document.querySelector('.properties') === null")) as? Bool == true }
        try await wait("Profile override preserves scroll") { abs((try await js(web, "scrollY") as? Double ?? 0) - 200) < 5 }
        let reopened = ReaderWindow(); reopened.open(home)
        try await wait("Profile override survives reopening") { reopened.preview.resolvedProfile == .commonMark && reopened.snapshot?.url == home }
        reopened.close()
        try expect(MarkdownProfile.preference(for:home) == .commonMark && MarkdownProfile.preference(for:target) == .auto,"Profile persists per document")
        webReader.preview.setProfile(.obsidian)
        try await wait("Manual Obsidian override") { guard webReader.preview.resolvedProfile == .obsidian else { return false }; return (try? await js(web,"document.querySelector('.properties') !== null")) as? Bool == true }
        try targetText.replacingOccurrences(of:"TRANSCLUDED-HEADING",with:"EMBED-UPDATED").write(to:target,atomically:true,encoding:.utf8)
        webReader.reload(force:false)
        try await wait("Changed embed refreshes when host bytes are unchanged") { try await js(web,"document.body.innerText.includes('EMBED-UPDATED')") as? Bool == true }
        webReader.close()
        let quick = WKWebView()
        quick.loadHTMLString(MarkdownHTML.document(content:rendered,title:"Obsidian Quick Look context"),baseURL:nil)
        try await wait("Shared Quick Look HTML context") { try await js(quick,"document.querySelector('.properties') !== null && document.images[0]?.naturalWidth > 0 && document.body.innerText.includes('TRANSCLUDED-HEADING')") as? Bool == true }
        // Restore only the test's deliberate source edit before byte comparison.
        try originals[1].1.write(to:target)
        for (url,bytes) in originals { try expect(try Data(contentsOf:url) == bytes,"Rendering/navigation changed source: " + url.lastPathComponent) }
        print("Verified Obsidian Auto/overrides, typed YAML, vault resolution/ambiguity/boundaries, links/Back/Find, embeds/cycles, callout folding, highlights/comments/tasks/footnotes and read-only source")
    }
}
