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

struct PreparedDocument {
    let snapshot: MarkdownSnapshot
    let content: RenderedMarkdown
    let requestedProfile: MarkdownProfile
    let token: String
    let html: String
    let warning: String?
}

/// One active preparation and one replaceable pending request per window.
/// Queue ownership lives on the main thread; only immutable request values cross
/// into the system worker pool. Superseded results are rejected by ReaderWindow.
final class DocumentLoader {
    struct Request {
        let url: URL
        let profile: MarkdownProfile
        let previousData: Data?
        let force: Bool
    }
    typealias Preparation = (Request) throws -> PreparedDocument?
    private struct Job {
        let request: Request
        let completion: (Result<PreparedDocument?, Error>) -> Void
    }
    private let queue = DispatchQueue(label: "PreviewMD.DocumentPreparation", qos: .userInitiated,
                                      target: .global(qos: .userInitiated))
    private let prepare: Preparation
    private var pending: Job?
    private(set) var isRunning = false
    var pendingCount: Int { pending == nil ? 0 : 1 }

    init(prepare: @escaping Preparation = DocumentLoader.prepare) { self.prepare = prepare }

    static func prepare(_ request: Request) throws -> PreparedDocument? {
        let next = try MarkdownSnapshot.read(request.url)
        guard request.force || next.data != request.previousData else { return nil }
        let content = MarkdownHTML.render(next.text, fileURL: next.url, profile: request.profile)
        let restored = DocumentState.restoreTableColumnWidths(for: next.url, identifiers: content.tableIdentifiers)
        let token = UUID().uuidString
        let fluid = UserDefaults.standard.string(forKey: DocumentState.readingWidthPreferenceKey(for: next.url)) == "fluid"
        let html = MarkdownHTML.document(content: content, title: next.url.lastPathComponent,
                                         fillsAvailableWidth: fluid, tableColumnWidths: restored.widths, messageToken: token)
        return PreparedDocument(snapshot: next, content: content, requestedProfile: request.profile,
                                token: token, html: html, warning: restored.warning)
    }

    func submit(_ request: Request, completion: @escaping (Result<PreparedDocument?, Error>) -> Void) {
        precondition(Thread.isMainThread)
        let job = Job(request: request, completion: completion)
        if isRunning { pending = job } else { start(job) }
    }

    func cancelPending() {
        precondition(Thread.isMainThread)
        pending = nil
    }

    private func start(_ job: Job) {
        isRunning = true
        queue.async { [self] in
            let result = autoreleasepool { Result { try prepare(job.request) } }
            DispatchQueue.main.async { [self] in
                job.completion(result)
                if let next = pending { pending = nil; start(next) }
                else { isRunning = false }
            }
        }
    }
}
