import Foundation
import QuickLookUI
import UniformTypeIdentifiers

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        do {
            let data = try Data(contentsOf: request.fileURL)
            guard let markdown = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .utf16LittleEndian)
                ?? String(data: data, encoding: .utf16BigEndian) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }

            let html = MarkdownHTML.document(
                markdown: markdown,
                title: request.fileURL.deletingPathExtension().lastPathComponent,
                tableColumnWidths: DocumentState.tableColumnWidths(fromSidecarFor: request.fileURL) ?? []
            )
            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 900, height: 700)
            ) { _ in
                Data(html.utf8)
            }
            reply.title = request.fileURL.lastPathComponent
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }
}
