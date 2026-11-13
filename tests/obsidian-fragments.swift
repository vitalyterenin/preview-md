import Foundation

/// End-to-end fragment checks use only disposable notes, through the public renderer.
enum ObsidianFragmentChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run(root: URL) throws {
        let vault = root.appendingPathComponent("fragment-vault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        let home = vault.appendingPathComponent("home.md")
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func pair(_ name: String, _ source: String, _ fragment: String) throws -> (String, String) {
            let note = vault.appendingPathComponent(name + ".md")
            try source.write(to: note, atomically: true, encoding: .utf8)
            let whole = MarkdownHTML.render(source, fileURL: note, profile: .obsidian).html
            let embed = MarkdownHTML.render("![[\(name)#\(fragment)]]", fileURL: home, profile: .obsidian).html
            check(try Data(contentsOf: note) == Data(source.utf8), name + ": rendering must preserve source bytes")
            return (whole, embed)
        }
        let hidden = try pair("comment", "%%\n# Hidden Heading\nHIDDEN-PROSE\n%%\n\n# Visible\nVISIBLE-PROSE", "Hidden Heading")
        check(!hidden.0.contains("HIDDEN-PROSE"), "Whole note hides commented headings")
        check(hidden.1.contains("Missing or ambiguous section") && !hidden.1.contains("HIDDEN-PROSE"), "Fragment must not expose a commented heading or prose")
        let yaml = try pair("properties", "---\nvalue: |\n  # Fake Heading\n  PROPERTY-TEXT\n---\n# Real\nBODY-TEXT", "Fake Heading")
        check(yaml.0.contains("properties") && yaml.0.contains("PROPERTY-TEXT") && !yaml.0.contains("id=\"fake-heading\""), "YAML heading remains a property value")
        check(yaml.1.contains("Missing or ambiguous section") && !yaml.1.contains("PROPERTY-TEXT"), "Property values cannot be selected as body headings")
        let nested = try pair("nested", "> # Quoted Heading\n> QUOTE-BODY\n\n# Unrelated\nUNRELATED-BODY", "Quoted Heading")
        check(nested.0.contains("UNRELATED-BODY"), "Whole note keeps sections after a quote")
        check(nested.1.contains("QUOTE-BODY") && !nested.1.contains("UNRELATED-BODY"), "Quoted section stops at its enclosing container")
        let code = try pair("code", "A `^literal`\n\nOther", "^literal")
        check(code.0.contains("<code>^literal</code>") && !code.0.contains("id=\"block-literal\""), "Inline-code caret is literal")
        check(code.1.contains("Missing or ambiguous section"), "Inline code cannot supply a block ID")
        let escaped = try pair("escaped", "A \\^literal\n\nOther", "^literal")
        check(escaped.0.contains("A ^literal") && !escaped.0.contains("id=\"block-literal\""), "Escaped caret remains visible")
        check(escaped.1.contains("Missing or ambiguous section"), "Escaped caret cannot supply a block ID")
        for (name, block, tag) in [("list", "- First\n- Second", "<ul>"), ("quote", "> Quoted text", "<blockquote>"), ("table", "| A | B |\n| --- | --- |\n| One | Two |", "<table>")] {
            let named = try pair(name, block + "\n\n^named\n\nUNRELATED-BLOCK", "^named")
            check(named.0.contains("id=\"block-named\"") && named.0.contains(tag), name + ": standalone ID anchors the preceding block")
            check(named.1.contains(tag) && !named.1.contains("UNRELATED-BLOCK") && !named.1.contains("Missing or ambiguous section"), name + ": standalone ID embeds the preceding block only")
        }
        let valid = try pair("valid", "# [[destination|Named heading]]\n\nNamed **paragraph**. ^target\n\n## Child\nCHILD-BODY\n\n# Next\nNEXT-BODY", "Named heading")
        check(valid.0.contains("id=\"named-heading\""), "Wikilink heading retains its label anchor")
        check(valid.1.contains("CHILD-BODY") && valid.1.contains("block-target") && !valid.1.contains("NEXT-BODY"), "Wikilink heading embeds its children and block anchors")
        let visible = try pair("visible", "%%\n# Hidden\nHIDDEN-INSIDE\n%%\n\n# Visible\nVISIBLE-BODY\n\n%% hidden tail %%\n\n# Next\nNEXT-BODY", "Visible")
        check(visible.1.contains("VISIBLE-BODY") && !visible.1.contains("HIDDEN-INSIDE") && !visible.1.contains("hidden tail") && !visible.1.contains("NEXT-BODY"), "Visible section after comments has correct source boundaries")
        let malformed = try pair("malformed", "---\nbroken: [unterminated\n---\n# Readable\nREADABLE-BODY", "Readable")
        check(malformed.0.contains("Properties could not be read") && malformed.0.contains("unterminated"), "Malformed properties retain readable fallback")
        check(malformed.1.contains("READABLE-BODY") && !malformed.1.contains("unterminated"), "Malformed properties do not shift body section boundaries")
        let ambiguous = try pair("ambiguous", "# Same\nFirst\n\n# Same\nSecond", "Same")
        check(ambiguous.1.contains("Missing or ambiguous section"), "Duplicate matching headings remain ambiguous")
        for (name, source, expected) in [
            ("unicode", "Привет 😀 **мир**. ^named", "Привет 😀"),
            ("list-inline", "- First item\n- Named item ^named\n- Last item", "Named item"),
            ("quote-inline", "> Named quote ^named", "Named quote")
        ] {
            let named = try pair(name, source, "^named")
            check(named.0.contains("id=\"block-named\""), name + ": original block anchor exists")
            check(named.1.contains(expected) && !named.1.contains("Missing or ambiguous section"), name + ": source positions retain valid named blocks")
        }
        for (name, source) in [
            ("fenced", "```md\nText ^literal\n```"),
            ("entity", "Text &#94;literal"),
            ("comment-block", "Visible\n\n%%\nHidden ^literal\n%%")
        ] {
            let literal = try pair(name, source, "^literal")
            check(!literal.0.contains("id=\"block-literal\""), name + ": no literal block anchor")
            check(literal.1.contains("Missing or ambiguous section"), name + ": literal/hidden marker cannot be selected")
        }
        try "LEAF-CONTENT".write(to: vault.appendingPathComponent("leaf.md"), atomically: true, encoding: .utf8)
        let budgetSource = "# Selected\n\n![[leaf]]\n\n# Other\n\n" + String(repeating: "![[missing]]\n\n", count: 70)
        let budget = try pair("budget", budgetSource, "Selected")
        check(budget.1.contains("LEAF-CONTENT") && !budget.1.contains("limit") && !budget.1.contains("Missing target"), "Selection cannot resolve unrelated embeds or spend their budgets")
        let tableSource = "# Selected\n\n| A | B |\n| --- | --- |\n| A[^f] | B |\n\n[^f]: Footnote\n\n# Other\nOther"
        try tableSource.write(to: vault.appendingPathComponent("fragment-tables.md"), atomically: true, encoding: .utf8)
        let repeatedTables = "![[fragment-tables#Selected]]\n\n![[fragment-tables#Selected]]"
        let first = MarkdownHTML.render(repeatedTables, fileURL: home, profile: .obsidian)
        let second = MarkdownHTML.render(repeatedTables, fileURL: home, profile: .obsidian)
        check(first.tableIdentifiers.count == 2 && first.tableIdentifiers == second.tableIdentifiers, "Repeated fragment tables and footnote IDs remain deterministic")
        if !failures.isEmpty { throw Failure(description: failures.joined(separator: "\n")) }
        print("Verified semantic heading/block fragments, hidden comments/properties, source escapes, container boundaries and standalone list/quote/table IDs")
    }
}
