import Foundation

enum DocumentState {
    private struct TableColumnWidthsSidecar: Codable {
        let formatVersion: Int
        let tableColumnWidths: [[Double]]
    }

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

    static func tableColumnWidths(fromSidecarFor url: URL) -> [[Double]]? {
        let sidecarURL = tableColumnWidthsSidecarURL(for: url)
        guard let data = try? Data(contentsOf: sidecarURL),
              let state = try? JSONDecoder().decode(TableColumnWidthsSidecar.self, from: data),
              state.formatVersion == 1 else {
            return nil
        }
        return state.tableColumnWidths
    }

    static func saveTableColumnWidths(_ widths: [[Double]], for url: URL) throws {
        let sidecarURL = tableColumnWidthsSidecarURL(for: url)
        try FileManager.default.createDirectory(
            at: sidecarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(TableColumnWidthsSidecar(formatVersion: 1, tableColumnWidths: widths))
        try data.write(to: sidecarURL, options: .atomic)
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
