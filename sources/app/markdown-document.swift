import Foundation

/// Disk state is shared by explicit opening and refreshing; reading never writes Markdown.
struct MarkdownSnapshot {
    let url: URL
    let data: Data
    let text: String

    static func read(_ url: URL) throws -> MarkdownSnapshot {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) {
                return MarkdownSnapshot(url: url.standardizedFileURL, data: data, text: text)
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
