import Foundation
import CMark
import CryptoKit

/// A bounded adapter over cmark's block/inline structure. It never evaluates
/// note HTML, plugins, CSS snippets, templates or code fences.
enum ObsidianMarkdown {
    struct Replacement {
        let token: String
        var html: String
        let block: Bool
        var text: String = ""
        var source: String = ""
        var reference: String? = nil
    }
    struct Prepared {
        var source: String
        var prefix: String
        var replacements: [Replacement]

        func headingText(_ raw: String) -> String {
            replacements.reduce(raw) { $0.replacingOccurrences(of: $1.token, with: $1.text) }
        }
        func restoredSource(_ fragment: String) -> String {
            replacements.reduce(fragment) { $0.replacingOccurrences(of: $1.token, with: $1.source) }
        }
    }

    static func prepare(_ source: String, fileURL: URL?, resolver: VaultResolver?, stack: [String]) -> Prepared {
        let properties = MarkdownProperties.extract(source, resolver: resolver, fileURL: fileURL)
        var prepared = prepareSyntax(properties.body)
        prepared.prefix = properties.html
        var embedCounts: [String: Int] = [:]
        for index in prepared.replacements.indices {
            guard let contents = prepared.replacements[index].reference else { continue }
            embedCounts[contents, default: 0] += 1
            if let fileURL, let resolver {
                prepared.replacements[index].html = prepared.replacements[index].block
                    ? embed(contents, resolver: resolver, fileURL: fileURL, stack: stack, instance: embedCounts[contents]!)
                    : link(contents, resolver: resolver, fileURL: fileURL)
            } else {
                prepared.replacements[index].html = warning("A saved local document is required to resolve " + prepared.replacements[index].source)
            }
        }
        return prepared
    }

    /// Selection and rendering share syntax preparation. This stage never reads
    /// linked notes or spends embed budgets; replacements retain their source.
    private static func prepareSyntax(_ body: String) -> Prepared {
        var prepared = Prepared(source: body, prefix: "", replacements: [])
        // Comments may contain Markdown/code; only their opening and closing
        // delimiters must be outside a code span/block.
        let delimiters = Set(MarkdownSyntax.proseMatches("%%", source: prepared.source).map { $0.range.location })
        for match in MarkdownSyntax.matches("%%[\\s\\S]*?%%", in: prepared.source).reversed() {
            let range = match.range
            guard delimiters.contains(range.location), delimiters.contains(NSMaxRange(range) - 2) else { continue }
            prepared.source = (prepared.source as NSString).replacingCharacters(in: range, with: "")
        }
        for match in MarkdownSyntax.proseMatches(#"!?\[\[([^\]\n]+)\]\]"#, source: prepared.source).reversed() {
            let raw = (prepared.source as NSString).substring(with: match.range)
            let contents = (prepared.source as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: "\\|", with: "|")
            let token = "PMOFM" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            prepared.replacements.append(.init(token: token, html: "", block: raw.hasPrefix("!"),
                                              text: contents.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? contents,
                                              source: raw, reference: contents))
            prepared.source = (prepared.source as NSString).replacingCharacters(in: match.range, with: token)
        }
        for match in MarkdownSyntax.proseMatches(#"==([^=\n]+)=="#, source: prepared.source).reversed() {
            let content = (prepared.source as NSString).substring(with: match.range(at: 1))
            let start = "PMMARK" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let end = "PMMARK" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            prepared.replacements.append(.init(token: start, html: "<mark>", block: false, source: "=="))
            prepared.replacements.append(.init(token: end, html: "</mark>", block: false, source: "=="))
            prepared.source = (prepared.source as NSString).replacingCharacters(in: match.range, with: start + content + end)
        }
        return prepared
    }
    static func warning(_ message: String) -> String { "<span class=\"render-warning\">\(MarkdownHTML.escape(message))</span>" }
    static func link(_ contents: String, resolver: VaultResolver, fileURL: URL) -> String {
        let parts = contents.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        switch resolver.resolve(parts[0], from: fileURL) {
        case .found(let target):
            let label = parts.count > 1 ? parts[1] : parts[0]
            return "<a class=\"wikilink\" href=\"\(MarkdownHTML.escape(VaultResolver.navigationURL(target)))\">\(MarkdownHTML.escape(label))</a>"
        case .failure(let message): return warning(message)
        }
    }
    private static func embed(_ contents: String, resolver: VaultResolver, fileURL: URL, stack: [String], instance: Int) -> String {
        let parts = contents.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard resolver.claimEmbed() else { return warning("Embed count limit reached (64)") }
        switch resolver.resolve(parts[0], from: fileURL) {
        case .failure(let message): return warning(message)
        case .found(let target):
            let ext = target.url.pathExtension.lowercased()
            if VaultResolver.imageExtensions.contains(ext) {
                let url = MarkdownHTML.imageURL(target.url.absoluteString, relativeTo: fileURL)
                guard !url.isEmpty else { return warning("Image unavailable: " + parts[0]) }
                var size = ""
                if parts.count > 1, !MarkdownSyntax.matches(#"^\d{1,5}(x\d{1,5})?$"#, in: parts[1]).isEmpty {
                    let dimensions = parts[1].split(separator: "x").compactMap { Int($0) }
                    if let width = dimensions.first { size += " width=\"\(min(4096, max(1, width)))\"" }
                    if dimensions.count == 2 { size += " height=\"\(min(4096, max(1, dimensions[1])))\"" }
                }
                return "<img src=\"\(MarkdownHTML.escape(url))\" alt=\"\(MarkdownHTML.escape(target.url.lastPathComponent))\"\(size)>"
            }
            guard VaultResolver.markdownExtensions.contains(ext) else { return warning("Unsupported embed (open from Finder): " + parts[0]) }
            let canonical = target.url.resolvingSymlinksInPath().absoluteString + (target.fragment.map { "#" + $0 } ?? "")
            guard stack.count < 5, !stack.contains(canonical) else { return warning("Embed cycle or depth limit: " + parts[0]) }
            do {
                var source = try resolver.read(target.url)
                if let fragment = target.fragment {
                    guard let section = section(source, fragment: fragment) else { return warning("Missing or ambiguous section: " + parts[0]) }
                    source = section
                }
                let rendered = MarkdownHTML.render(source, fileURL: target.url, profile: .obsidian, resolver: resolver,
                                                   stack: stack + [canonical], decorateTables: false)
                // Embedded headings/footnotes cannot steal the host's IDs.
                let identity = canonical + ":" + String(instance)
                let prefix = "embed-" + SHA256.hash(data: Data(identity.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() + "-"
                let html = rendered.html.replacingOccurrences(of: "id=\"", with: "id=\"" + prefix)
                    .replacingOccurrences(of: "href=\"#", with: "href=\"#" + prefix)
                return "<section class=\"note-embed\"><header>\(link(contents, resolver: resolver, fileURL: fileURL))</header>\(html)</section>"
            } catch { return warning("Embed could not be read (UTF-8, 2 MiB/note, 64-note limit): " + parts[0]) }
        }
    }

    /// Select from the same semantic body and cmark dialect as rendering. Source
    /// positions refer to prepared text; restoring tokens keeps nested references
    /// unresolved until the selected fragment is actually rendered.
    static func section(_ source: String, fragment: String) -> String? {
        let properties = MarkdownProperties.extract(source, resolver: nil, fileURL: nil)
        let prepared = prepareSyntax(properties.body)
        let lines = prepared.source.components(separatedBy: "\n")
        return MarkdownSyntax.withTree(prepared.source, profile: .obsidian) { root in
            var ranges: [ClosedRange<Int>] = []
            MarkdownSyntax.walk(root) { node in
                let kind = MarkdownSyntax.kind(node)
                if fragment.hasPrefix("^") {
                    guard let marker = blockID(node, lines: lines), "^" + marker.id == fragment else { return }
                    var target = node
                    if marker.standalone, let previous = cmark_node_previous(node) { target = previous }
                    else if let parent = cmark_node_parent(node), MarkdownSyntax.kind(parent) == "item" { target = parent }
                    let start = Int(cmark_node_get_start_line(target)) - 1
                    let end = max(Int(cmark_node_get_end_line(target)), Int(cmark_node_get_end_line(node))) - 1
                    if start >= 0 && end >= start && end < lines.count { ranges.append(start...end) }
                } else if kind == "heading", MarkdownHTML.anchor(prepared.headingText(MarkdownSyntax.text(node))) == MarkdownHTML.anchor(fragment) {
                    let start = Int(cmark_node_get_start_line(node)) - 1
                    let parent = cmark_node_parent(node) ?? root
                    var end = Int(cmark_node_get_end_line(parent)) - 1
                    var next = cmark_node_next(node)
                    while let current = next {
                        if MarkdownSyntax.kind(current) == "heading", cmark_node_get_heading_level(current) <= cmark_node_get_heading_level(node) {
                            end = Int(cmark_node_get_start_line(current)) - 2; break
                        }
                        next = cmark_node_next(current)
                    }
                    if start >= 0 && end >= start && end < lines.count { ranges.append(start...end) }
                }
            }
            guard ranges.count == 1, let range = ranges.first else { return nil }
            return prepared.restoredSource(lines[range].joined(separator: "\n"))
        }
    }

    private struct BlockID {
        let id: String
        let remaining: String
        let standalone: Bool
    }
    /// A terminal text node alone cannot distinguish an escaped caret or an HTML
    /// entity from a real marker. Check its original source line before decorating
    /// or selecting it. cmark columns are UTF-8 byte offsets, including prefixes.
    private static func blockID(_ paragraph: OpaquePointer, lines: [String]) -> BlockID? {
        guard MarkdownSyntax.kind(paragraph) == "paragraph",
              let last = cmark_node_last_child(paragraph), MarkdownSyntax.kind(last) == "text",
              let literal = cmark_node_get_literal(last) else { return nil }
        let text = String(cString: literal)
        guard let match = MarkdownSyntax.matches(#"(?:^|\s)\^([A-Za-z0-9-]+)\s*$"#, in: text).first else { return nil }
        let id = (text as NSString).substring(with: match.range(at: 1))
        let line = Int(cmark_node_get_end_line(paragraph)) - 1
        guard lines.indices.contains(line) else { return nil }
        let raw = String(decoding: lines[line].utf8.prefix(Int(cmark_node_get_end_column(paragraph))), as: UTF8.self)
        guard let original = MarkdownSyntax.matches(#"(?:^|\s)\^([A-Za-z0-9-]+)\s*$"#, in: raw).first,
              (raw as NSString).substring(with: original.range(at: 1)) == id else { return nil }
        let remaining = (text as NSString).replacingCharacters(in: match.range, with: "")
        return BlockID(id: id, remaining: remaining, standalone: remaining.isEmpty && cmark_node_first_child(paragraph) == last)
    }

    static func decorateTree(_ root: OpaquePointer, source: String) {
        let lines = source.components(separatedBy: "\n")
        var nodes: [OpaquePointer] = []
        MarkdownSyntax.walk(root) { nodes.append($0) }
        // Transform children before their parent callout is moved.
        for node in nodes.reversed() {
            if MarkdownSyntax.kind(node) == "paragraph", let marker = blockID(node, lines: lines) { decorateBlockID(node, marker: marker) }
            if MarkdownSyntax.kind(node) == "block_quote" { decorateCallout(node) }
        }
    }
    private static func custom(_ kind: cmark_node_type, enter: String, exit: String = "") -> OpaquePointer {
        let node = cmark_node_new(kind)!
        cmark_node_set_on_enter(node, enter); cmark_node_set_on_exit(node, exit)
        return node
    }
    private static func decorateBlockID(_ paragraph: OpaquePointer, marker: BlockID) {
        guard let last = cmark_node_last_child(paragraph) else { return }
        let anchor = custom(CMARK_NODE_CUSTOM_INLINE, enter: "<span id=\"block-\(marker.id)\"></span>")
        if marker.standalone, let previous = cmark_node_previous(paragraph) {
            let block = custom(CMARK_NODE_CUSTOM_BLOCK, enter: "<div id=\"block-\(marker.id)\">", exit: "</div>")
            cmark_node_insert_before(previous, block); cmark_node_unlink(previous); cmark_node_append_child(block, previous)
            cmark_node_unlink(paragraph)
            // Nodes in this traversal are already visited; release detached nodes now.
            cmark_node_free(paragraph); cmark_node_free(anchor)
        } else { cmark_node_set_literal(last, marker.remaining); cmark_node_prepend_child(paragraph, anchor) }
    }
    private static func decorateCallout(_ quote: OpaquePointer) {
        guard let paragraph = cmark_node_first_child(quote), MarkdownSyntax.kind(paragraph) == "paragraph",
              let first = cmark_node_first_child(paragraph), MarkdownSyntax.kind(first) == "text",
              let raw = cmark_node_get_literal(first) else { return }
        let text = String(cString: raw)
        guard let match = MarkdownSyntax.matches(#"^\[!([A-Za-z0-9-]+)\]([+-]?)\s*"#, in: text).first else { return }
        let type = (text as NSString).substring(with: match.range(at: 1)).lowercased()
        let fold = (text as NSString).substring(with: match.range(at: 2))
        let title = (text as NSString).replacingCharacters(in: match.range, with: "")
        cmark_node_set_literal(first, title.isEmpty ? type.capitalized : title)
        let tag = fold.isEmpty ? "aside" : "details"
        let box = custom(CMARK_NODE_CUSTOM_BLOCK, enter: "<\(tag) class=\"callout\" data-callout=\"\(type)\"\(fold == "+" ? " open" : "")>", exit: "</\(tag)>")
        let heading = custom(CMARK_NODE_CUSTOM_BLOCK, enter: fold.isEmpty ? "<div class=\"callout-title\">" : "<summary>", exit: fold.isEmpty ? "</div>" : "</summary>")
        cmark_node_insert_before(quote, box); cmark_node_append_child(box, heading)
        // Keep inline Markdown in the title; remaining lines form the body.
        while let child = cmark_node_first_child(paragraph) {
            cmark_node_unlink(child)
            if ["softbreak", "linebreak"].contains(MarkdownSyntax.kind(child)) { cmark_node_free(child); break }
            cmark_node_append_child(heading, child)
        }
        while let child = cmark_node_first_child(quote) { cmark_node_unlink(child); cmark_node_append_child(box, child) }
        cmark_node_unlink(quote); cmark_node_free(quote)
    }
}
