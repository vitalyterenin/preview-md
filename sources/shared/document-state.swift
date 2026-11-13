import Foundation

enum DocumentState {
    enum ReadingWidthMode: String {
        case fixed
        case fluid
    }

    static func windowAutosaveName(for url: URL) -> String {
        "PreviewMD.Window.\(identifier(for: url))"
    }

    static func zoomPreferenceKey(for url: URL) -> String {
        "PreviewMD.Zoom.\(identifier(for: url))"
    }

    static func readingWidthPreferenceKey(for url: URL) -> String {
        "PreviewMD.ReadingWidth.\(identifier(for: url))"
    }

    static func tableColumnWidthsPreferenceKey(for url: URL) -> String {
        "PreviewMD.TableColumnWidths.\(identifier(for: url))"
    }

    static func tableColumnWidthsSidecarURL(for url: URL) -> URL {
        url
            .deletingLastPathComponent()
            .appendingPathComponent(".previewmd", isDirectory: true)
            .appendingPathComponent("\(url.lastPathComponent).json", isDirectory: false)
    }

    struct TableRestoration {
        var widths: [[Double]]
        var warning: String?
    }

    private static func sidecar(for url: URL) throws -> [String: Any] {
        let path = tableColumnWidthsSidecarURL(for: url)
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        let data = try Data(contentsOf: path)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["formatVersion"] as? Int == 1,
              let widths = value["tableColumnWidths"] as? [[Double]], valid(widths) else {
            throw NSError(domain: "PreviewMD", code: 1, userInfo: [NSLocalizedDescriptionKey: "The table preferences are damaged or use an unsupported format. The existing file has been preserved."])
        }
        if let raw = value["tableWidthsByID"] {
            guard let saved = raw as? [String: [Double]], valid(Array(saved.values)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return value
    }

    private static func valid(_ widths: [[Double]]) -> Bool {
        widths.allSatisfy { $0.allSatisfy { $0.isFinite && $0 > 0 } }
    }

    static func tableColumnWidths(fromSidecarFor url: URL) -> [[Double]]? {
        (try? sidecar(for: url))?["tableColumnWidths"] as? [[Double]]
    }

    static func restoreTableColumnWidths(for url: URL, identifiers: [String]) -> TableRestoration {
        do {
            let state = try sidecar(for: url)
            if let saved = state["tableWidthsByID"] as? [String: [Double]] {
                guard valid(Array(saved.values)) else { throw CocoaError(.fileReadCorruptFile) }
                let counts = Dictionary(grouping: identifiers, by: { $0 }).mapValues(\.count)
                return TableRestoration(widths: identifiers.map { counts[$0] == 1 ? saved[$0] ?? [] : [] })
            }
            if let widths = state["tableColumnWidths"] as? [[Double]] { return TableRestoration(widths: widths) }
            if let data = UserDefaults.standard.data(forKey: tableColumnWidthsPreferenceKey(for: url)),
               let widths = try? JSONDecoder().decode([[Double]].self, from: data), valid(widths) {
                return TableRestoration(widths: widths)
            }
            return TableRestoration(widths: [])
        } catch {
            return TableRestoration(widths: [], warning: "Table preferences could not be restored. " + error.localizedDescription)
        }
    }

    static func saveTableColumnWidths(_ widths: [[Double]], for url: URL, identifiers: [String] = []) throws {
        guard valid(widths), identifiers.isEmpty || identifiers.count == widths.count else { throw CocoaError(.fileWriteInvalidFileName) }
        var state = try sidecar(for: url)
        state["formatVersion"] = 1
        state["tableColumnWidths"] = widths
        if !identifiers.isEmpty {
            var saved = state["tableWidthsByID"] as? [String: [Double]] ?? [:]
            let counts = Dictionary(grouping: identifiers, by: { $0 }).mapValues(\.count)
            for (id, columns) in zip(identifiers, widths) where counts[id] == 1 { saved[id] = columns }
            state["tableWidthsByID"] = saved
        }
        let path = tableColumnWidthsSidecarURL(for: url)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
    }

    static func position(for url: URL) -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: "PreviewMD.Position." + identifier(for: url)) as? [String: Double] ?? [:]
    }

    static func savePosition(_ position: [String: Double], for url: URL) {
        UserDefaults.standard.set(position, forKey: "PreviewMD.Position." + identifier(for: url))
    }

    static func migrateLegacySmallWindowFrameIfNeeded(for url: URL) {
        let identifier = identifier(for: url)
        let migrationKey = "PreviewMD.WindowFrameMigration.\(identifier)"
        guard UserDefaults.standard.integer(forKey: migrationKey) < 2 else { return }

        let autosaveName = windowAutosaveName(for: url)
        let frameKey = "NSWindow Frame \(autosaveName)"
        if let frame = UserDefaults.standard.string(forKey: frameKey),
           isLegacySmallFrame(frame) {
            let backupKey = "PreviewMD.LegacyWindowFrame.\(identifier)"
            if UserDefaults.standard.object(forKey: backupKey) == nil {
                UserDefaults.standard.set(frame, forKey: backupKey)
            }
            UserDefaults.standard.removeObject(forKey: frameKey)
        }

        UserDefaults.standard.set(2, forKey: migrationKey)
    }

    static func savedWindowFrame(for url: URL) -> String? {
        guard let frame = UserDefaults.standard.string(forKey: "NSWindow Frame \(windowAutosaveName(for: url))"),
              !isLegacySmallFrame(frame) else {
            return nil
        }
        return frame
    }

    private static func isLegacySmallFrame(_ frame: String) -> Bool {
        let values = frame
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(4)
            .compactMap { Double($0) }
        guard values.count == 4 else { return false }
        return values[2] <= 600 || values[3] <= 480
    }

    private static func identifier(for url: URL) -> String {
        Data(url.standardizedFileURL.path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
