import Foundation

/// A per-render index of file names only. No vault settings, plugins or note
/// bodies are indexed; symlinks and paths escaping the selected root are refused.
final class VaultResolver {
    struct Target { let url: URL; let fragment: String? }
    enum Resolution { case found(Target), failure(String) }
    let root: URL
    private var files: [URL]?
    private var indexIncomplete = false
    private var reads = 0
    private var bytesRead = 0
    private var embeds = 0
    func claimEmbed() -> Bool { embeds += 1; return embeds <= 64 }
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg"]

    init(fileURL: URL) { root = Self.vaultRoot(for: fileURL) ?? fileURL.deletingLastPathComponent().resolvingSymlinksInPath() }
    static func vaultRoot(for file: URL) -> URL? {
        var directory = file.deletingLastPathComponent().resolvingSymlinksInPath()
        while directory.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".obsidian").path, isDirectory: &isDirectory), isDirectory.boolValue { return directory }
            directory.deleteLastPathComponent()
        }
        return nil
    }
    func contains(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved.hasPrefix(root.path + "/")
    }
    private func indexedFiles() -> [URL] {
        if let files { return files }
        var result: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        if let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { [weak self] _, _ in self?.indexIncomplete = true; return true }) {
            var visited = 0
            for case let url as URL in items {
                visited += 1
                if visited > 20000 { indexIncomplete = true; break }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { indexIncomplete = true; continue }
                if values.isSymbolicLink == true { items.skipDescendants(); continue }
                if values.isRegularFile == true && contains(url) { result.append(url.standardizedFileURL) }
            }
        } else { indexIncomplete = true }
        files = result
        return result
    }
    func resolve(_ raw: String, from current: URL) -> Resolution {
        let value = raw.removingPercentEncoding ?? raw
        let pieces = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces[0]).trimmingCharacters(in: .whitespaces)
        let fragment = pieces.count > 1 ? String(pieces[1]) : nil
        if path.isEmpty { return .found(Target(url: current, fragment: fragment)) }
        guard !path.hasPrefix("/"), !path.contains(":"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure("Unsupported or unsafe target: " + raw)
        }
        let names = (path as NSString).pathExtension.isEmpty ? [path + ".md", path + ".markdown", path + ".mdown", path + ".mkdn"] : [path]
        if path.contains("/") {
            let base = path.hasPrefix("./") || path.hasPrefix("../") ? current.deletingLastPathComponent() : root
            let candidates = names.map { base.appendingPathComponent($0).standardizedFileURL }
            guard candidates.allSatisfy(contains) else { return .failure("Target is outside the vault or document folder: " + raw) }
            return choose(candidates.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }, raw: raw, fragment: fragment)
        }
        // Do not silently pick a nearby duplicate. A path is required when a
        // basename occurs more than once anywhere in the allowed scope.
        let candidates = indexedFiles().filter { file in names.contains(where: { name in name.caseInsensitiveCompare(file.lastPathComponent) == .orderedSame }) }
        if indexIncomplete { return .failure("Vault index is incomplete; use an explicit relative path: " + raw) }
        return choose(candidates, raw: raw, fragment: fragment)
    }
    private func choose(_ candidates: [URL], raw: String, fragment: String?) -> Resolution {
        if candidates.count == 1 { return .found(Target(url: candidates[0], fragment: fragment)) }
        if candidates.isEmpty { return .failure("Missing target: " + raw) }
        let paths = candidates.prefix(4).map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }.sorted().joined(separator: ", ")
        return .failure("Ambiguous target: \(raw). Use a path (\(paths)).")
    }
    func read(_ url: URL) throws -> String {
        reads += 1
        guard reads <= 64, contains(url), let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        bytesRead += size
        guard bytesRead <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try String(contentsOf: url, encoding: .utf8)
    }
    static func navigationURL(_ target: Target) -> String {
        var parts = URLComponents(url: target.url, resolvingAgainstBaseURL: true)!
        if let fragment = target.fragment { parts.fragment = fragment.hasPrefix("^") ? "block-" + fragment.dropFirst() : MarkdownHTML.anchor(fragment) }
        return parts.url!.absoluteString
    }
}
