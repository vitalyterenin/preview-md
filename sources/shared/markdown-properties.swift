import Foundation
import Yams
import CYaml

struct MarkdownProperties {
    let body: String
    let html: String

    static func extract(_ source: String, resolver: VaultResolver?, fileURL: URL?) -> MarkdownProperties {
        let lines = source.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return .init(body: source, html: "") }
        guard let end = lines.dropFirst().firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else {
            return .init(body: "", html: failure("Unclosed YAML properties", source: source))
        }
        let yaml = lines[1..<end].joined(separator: "\n")
        let body = lines.dropFirst(end + 1).joined(separator: "\n")
        do {
            try preflight(yaml)
            guard let root = try Yams.compose(yaml: yaml, .default.replacing(.bool, with: "^(?:true|True|TRUE|false|False|FALSE)$")), case .mapping(let properties) = root else {
                throw ParseFailure(message: "Properties must be a YAML mapping")
            }
            var keys = Set<String>()
            let rows = try properties.map { pair -> String in
                guard let key = pair.key.string, keys.insert(key).inserted else { throw ParseFailure(message: "Properties need unique text keys") }
                return "<div class=\"property\"><dt>\(MarkdownHTML.escape(key))</dt><dd>\(value(pair.value, resolver: resolver, fileURL: fileURL))</dd></div>"
            }.joined()
            return .init(body: body, html: "<section class=\"properties\" aria-label=\"Properties\"><h2>Properties</h2><dl>\(rows)</dl></section>")
        } catch {
            return .init(body: body, html: failure("Properties could not be read: " + error.localizedDescription, source: lines[0...end].joined(separator: "\n")))
        }
    }
    private struct ParseFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
    /// Parse events before composing nodes. This bounds recursion and rejects YAML
    /// alias expansion; the raw frontmatter remains readable on any failure.
    private static func preflight(_ yaml: String) throws {
        guard yaml.utf8.count <= 256 * 1024 else { throw ParseFailure(message: "Properties exceed the 256 KiB limit") }
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) == 1 else { throw ParseFailure(message: "Could not initialize YAML parser") }
        defer { yaml_parser_delete(&parser) }
        try Array(yaml.utf8).withUnsafeBufferPointer { buffer in
            yaml_parser_set_input_string(&parser, buffer.baseAddress, buffer.count)
            var depth = 0, count = 0
            while true {
                var event = yaml_event_t()
                guard yaml_parser_parse(&parser, &event) == 1 else { throw ParseFailure(message: "Invalid YAML syntax") }
                let type = event.type
                yaml_event_delete(&event)
                count += 1
                if type == YAML_MAPPING_START_EVENT || type == YAML_SEQUENCE_START_EVENT { depth += 1 }
                if type == YAML_MAPPING_END_EVENT || type == YAML_SEQUENCE_END_EVENT { depth -= 1 }
                guard count <= 4096, depth <= 32, type != YAML_ALIAS_EVENT else { throw ParseFailure(message: "YAML aliases or excessive nesting are not supported") }
                if type == YAML_STREAM_END_EVENT { break }
            }
        }
    }
    private static func failure(_ message: String, source: String) -> String {
        "<section class=\"render-warning\"><strong>\(MarkdownHTML.escape(message))</strong><pre>\(MarkdownHTML.escape(source))</pre></section>"
    }
    private static func value(_ node: Node, resolver: VaultResolver?, fileURL: URL?, depth: Int = 0) -> String {
        guard depth < 32 else { return "Nested value limit" }
        switch node {
        case .scalar(let scalar):
            let tag = node.tag.description.split(separator: ":").last.map(String.init) ?? "text"
            let type = ["str": "Text", "bool": "Checkbox", "int": "Number", "float": "Number", "timestamp": scalar.string.contains("T") || scalar.string.contains(" ") ? "Date & time" : "Date", "null": "Empty"][tag] ?? "Text"
            var html = MarkdownHTML.escape(scalar.string)
            if tag == "bool" { html = "<input type=\"checkbox\" disabled \(node.bool == true ? "checked" : "") aria-label=\"\(MarkdownHTML.escape(scalar.string))\"> " + html }
            else if scalar.string.hasPrefix("[["), scalar.string.hasSuffix("]]"), let resolver, let fileURL {
                html = ObsidianMarkdown.link(String(scalar.string.dropFirst(2).dropLast(2)), resolver: resolver, fileURL: fileURL)
            } else if let url = URL(string: scalar.string), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                html = "<a href=\"\(MarkdownHTML.escape(MarkdownHTML.safeLink(scalar.string)))\">\(html)</a>"
            }
            return "<span class=\"property-type\">\(type)</span> " + html
        case .sequence(let values):
            return "<span class=\"property-type\">List</span><ul>" + values.map { "<li>" + value($0, resolver: resolver, fileURL: fileURL, depth: depth + 1) + "</li>" }.joined() + "</ul>"
        case .mapping(let values):
            return "<span class=\"property-type\">Mapping</span><dl>" + values.map { "<dt>\(MarkdownHTML.escape($0.key.string ?? "Key"))</dt><dd>\(value($0.value, resolver: resolver, fileURL: fileURL, depth: depth + 1))</dd>" }.joined() + "</dl>"
        case .alias: return "YAML alias not expanded"
        }
    }
}
