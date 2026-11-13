import Foundation
import CMark

enum MarkdownProfile: String, CaseIterable {
    case auto = "Auto", commonMark = "CommonMark", github = "GitHub", obsidian = "Obsidian"

    static func preference(for url: URL) -> MarkdownProfile {
        MarkdownProfile(rawValue: UserDefaults.standard.string(forKey: key(url)) ?? "") ?? .auto
    }
    static func save(_ profile: MarkdownProfile, for url: URL) { UserDefaults.standard.set(profile.rawValue, forKey: key(url)) }
    private static func key(_ url: URL) -> String { "PreviewMD.Profile." + url.standardizedFileURL.path }

    static func resolve(_ requested: MarkdownProfile, source: String, fileURL: URL?) -> ProfileDecision {
        if requested != .auto { return ProfileDecision(profile: requested, reason: "Manual choice") }
        if let fileURL, VaultResolver.vaultRoot(for: fileURL) != nil {
            return ProfileDecision(profile: .obsidian, reason: "Inside an Obsidian vault")
        }
        let visible = MarkdownSyntax.visibleSource(source)
        if MarkdownSyntax.proseMatches(#"!?\[\[[^\]\n]+\]\]|(?m)^\s*>\s*\[![\w-]+\]|==[^=\n]+==|%%[\s\S]*?%%|(?m)(?:^|\s)\^[A-Za-z0-9-]+\s*$"#, source: source).count > 0 {
            return ProfileDecision(profile: .obsidian, reason: "Obsidian syntax outside code")
        }
        if MarkdownSyntax.matches(#"~~[^~\n]+~~|(?m)^\s*[-*+]\s+\[[ xX]\]\s|^\s*\[\^[^\]]+\]:|^\s*\|?.*\|.*\n\s*\|?\s*:?-{3,}"#, in: visible).count > 0 || visible.contains("https://") {
            return ProfileDecision(profile: .github, reason: "GitHub-style syntax outside code")
        }
        return ProfileDecision(profile: .commonMark, reason: "No dialect-specific syntax detected")
    }
}

struct ProfileDecision {
    let profile: MarkdownProfile
    let reason: String
}

/// cmark owns code/fence/HTML boundaries. Extension matching never scans those
/// ranges, or Markdown link destinations, as if they were prose.
enum MarkdownSyntax {
    static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(text.startIndex..., in: text))) ?? []
    }
    static func withTree<T>(_ source: String, _ body: (OpaquePointer) -> T) -> T {
        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)!
        defer { cmark_parser_free(parser) }
        source.withCString { cmark_parser_feed(parser, $0, source.utf8.count) }
        let root = cmark_parser_finish(parser)!
        defer { cmark_node_free(root) }
        return body(root)
    }
    static func walk(_ node: OpaquePointer, _ visit: (OpaquePointer) -> Void) {
        visit(node)
        var child = cmark_node_first_child(node)
        while let current = child { walk(current, visit); child = cmark_node_next(current) }
    }
    static func kind(_ node: OpaquePointer) -> String { String(cString: cmark_node_get_type_string(node)) }
    static func text(_ node: OpaquePointer) -> String {
        if let value = cmark_node_get_literal(node) { return String(cString: value) }
        var result = ""
        var child = cmark_node_first_child(node)
        while let current = child {
            result += ["softbreak", "linebreak"].contains(kind(current)) ? "\n" : text(current)
            child = cmark_node_next(current)
        }
        return result
    }
    static func visibleSource(_ source: String) -> String {
        var bytes = Array(source.utf8)
        var offsets = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { offsets.append(index + 1) }
        withTree(source) { root in
            walk(root) { node in
                guard ["code", "code_block", "html_inline", "html_block", "link", "image"].contains(kind(node)) else { return }
                let line = Int(cmark_node_get_start_line(node)) - 1
                let endLine = Int(cmark_node_get_end_line(node)) - 1
                guard line >= 0, endLine >= line, endLine < offsets.count else { return }
                let start = min(bytes.count, offsets[line] + max(0, Int(cmark_node_get_start_column(node)) - 1))
                let end = min(bytes.count, offsets[endLine] + Int(cmark_node_get_end_column(node)))
                if end > start { for index in start..<end where bytes[index] != 10 { bytes[index] = 32 } }
            }
        }
        // Preserve UTF-16 offsets used by regex replacements even for non-ASCII code.
        // Replacing byte ranges with spaces can change UTF-16 length, so mask using
        // the original UTF-8 characters' byte positions instead.
        var offset = 0
        return source.unicodeScalars.map { scalar -> String in
            defer { offset += scalar.utf8.count }
            return scalar != "\n" && bytes[offset] == 32 && scalar != " " ? String(repeating: " ", count: scalar.utf16.count) : String(scalar)
        }.joined()
    }
    static func proseMatches(_ pattern: String, source: String) -> [NSTextCheckingResult] {
        let visible = visibleSource(source) as NSString
        let original = source as NSString
        return matches(pattern, in: source).filter { match in
            guard visible.substring(with: match.range) == original.substring(with: match.range) else { return false }
            var index = match.range.location, slashes = 0
            while index > 0 && original.character(at: index - 1) == 92 { slashes += 1; index -= 1 }
            return slashes % 2 == 0
        }
    }
}
