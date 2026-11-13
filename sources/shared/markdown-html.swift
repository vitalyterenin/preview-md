import Foundation
import CryptoKit
import CMark

struct RenderedMarkdown {
    let html: String
    let tableIdentifiers: [String]
    var decision = ProfileDecision(profile: .commonMark, reason: "CommonMark")
}

enum MarkdownHTML {
    static func render(_ markdown: String, fileURL: URL? = nil, profile: MarkdownProfile = .auto,
                       resolver: VaultResolver? = nil, stack: [String] = [], decorateTables: Bool = true) -> RenderedMarkdown {
        let decision = MarkdownProfile.resolve(profile, source: markdown, fileURL: fileURL)
        let vault = decision.profile == .obsidian ? (resolver ?? fileURL.map(VaultResolver.init)) : nil
        let chain = stack.isEmpty ? fileURL.map { [$0.resolvingSymlinksInPath().absoluteString] } ?? [] : stack
        let prepared = decision.profile == .obsidian ? ObsidianMarkdown.prepare(markdown, fileURL: fileURL, resolver: vault, stack: chain) : nil
        let source = prepared?.source ?? markdown
        let options = decision.profile == .commonMark ? CMARK_OPT_DEFAULT : CMARK_OPT_FOOTNOTES
        let parser = MarkdownSyntax.parser(profile: decision.profile)
        defer { cmark_parser_free(parser) }
        source.withCString { cmark_parser_feed(parser, $0, source.utf8.count) }
        let root = cmark_parser_finish(parser)!
        defer { cmark_node_free(root) }
        if decision.profile == .obsidian { ObsidianMarkdown.decorateTree(root, source: source) }
        let iterator = cmark_iter_new(root)!
        defer { cmark_iter_free(iterator) }
        var replacements: [(String, String)] = []
        var headings: [String] = []
        var usedAnchors = Set<String>()
        while cmark_iter_next(iterator) != CMARK_EVENT_DONE {
            guard cmark_iter_get_event_type(iterator) == CMARK_EVENT_ENTER,
                  let node = cmark_iter_get_node(iterator) else { continue }
            let kind = String(cString: cmark_node_get_type_string(node))
            if kind == "heading" {
                var text = ""
                func collect(_ parent: OpaquePointer) {
                    var child = cmark_node_first_child(parent)
                    while let current = child {
                        if let literal = cmark_node_get_literal(current) { text += String(cString: literal) }
                        collect(current)
                        child = cmark_node_next(current)
                    }
                }
                collect(node)
                text = prepared?.headingText(text) ?? text
                let base = anchor(text)
                var id = base
                var suffix = 1
                while usedAnchors.contains(id) { id = "\(base)-\(suffix)"; suffix += 1 }
                usedAnchors.insert(id)
                headings.append(id)
            }
            if kind == "link" || kind == "image", let raw = cmark_node_get_url(node) {
                let value = String(cString: raw)
                let destination: String
                if let vault, let fileURL, URL(string: value)?.scheme == nil, !value.hasPrefix("#") {
                    switch vault.resolve(value, from: fileURL) {
                    case .found(let target): destination = kind == "image" ? imageURL(target.url.absoluteString, relativeTo: fileURL) : VaultResolver.navigationURL(target)
                    case .failure: destination = kind == "image" ? "" : "previewmd-invalid:unresolved"
                    }
                } else if let vault, let candidate = URL(string: value), candidate.isFileURL, !vault.contains(candidate) {
                    destination = kind == "image" ? "" : "previewmd-invalid:outside-vault"
                } else {
                    destination = kind == "image" ? imageURL(value, relativeTo: fileURL) : safeLink(value)
                }
                // Only app-validated attributes are substituted after cmark's safe renderer.
                // Random tokens prevent document text from impersonating an asset placeholder.
                let token = "previewmd-" + UUID().uuidString
                cmark_node_set_url(node, token)
                replacements.append((token, escape(destination)))
            }
        }
        let result = cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser))!
        var html = String(cString: result)
        free(result)
        for (token, value) in replacements { html = html.replacingOccurrences(of: token, with: value) }
        let headingPattern = try! NSRegularExpression(pattern: "<h[1-6]>")
        for (match, id) in zip(headingPattern.matches(in: html, range: NSRange(html.startIndex..., in: html)), headings).reversed() {
            let range = Range(match.range, in: html)!
            let tag = String(html[range].dropLast()) + " id=\"\(escape(id))\">"
            html.replaceSubrange(range, with: tag)
        }
        if let prepared {
            for replacement in prepared.replacements {
                if replacement.block { html = html.replacingOccurrences(of: "<p>" + replacement.token + "</p>", with: replacement.html) }
                html = html.replacingOccurrences(of: replacement.token, with: replacement.html)
            }
            html = prepared.prefix + html
        }
        guard decorateTables else { return RenderedMarkdown(html: html, tableIdentifiers: [], decision: decision) }
        var tableIDs: [String] = []
        let tables = try! NSRegularExpression(pattern: "<table>.*?</table>", options: .dotMatchesLineSeparators)
        let matches = tables.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            let table = String(html[Range(match.range, in: html)!])
            tableIDs.append(SHA256.hash(data: Data(table.utf8)).map { String(format: "%02x", $0) }.joined())
        }
        for (match, id) in zip(matches, tableIDs).reversed() {
            let range = Range(match.range, in: html)!
            html.replaceSubrange(range, with: "<div class=\"table-frame\" data-table-id=\"\(id)\">\(html[range])</div>")
        }
        return RenderedMarkdown(html: html, tableIdentifiers: tableIDs, decision: decision)
    }

    static func anchor(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let value = String(text.lowercased().unicodeScalars.filter { allowed.contains($0) }).replacingOccurrences(of: " ", with: "-")
        return value.isEmpty ? "section" : value
    }

    static func safeLink(_ value: String) -> String {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value) else { return "previewmd-invalid:blocked" }
        guard let scheme = url.scheme?.lowercased() else { return value }
        return ["http", "https", "mailto", "file"].contains(scheme) ? value : "previewmd-invalid:blocked"
    }

    static func imageURL(_ value: String, relativeTo fileURL: URL?) -> String {
        guard let url = URL(string: value, relativeTo: fileURL?.deletingLastPathComponent())?.absoluteURL else { return "" }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url.absoluteString }
        guard url.isFileURL else { return "" }
        let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml"]
        guard let type = types[url.pathExtension.lowercased()],
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true,
              let size = values.fileSize, size <= 20 * 1024 * 1024,
              let data = try? Data(contentsOf: url), data.count <= 20 * 1024 * 1024 else { return "" }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    static func document(markdown: String, title: String, fillsAvailableWidth: Bool = false,
                         tableColumnWidths: [[Double]] = [], fileURL: URL? = nil) -> String {
        document(content: render(markdown, fileURL: fileURL), title: title,
                 fillsAvailableWidth: fillsAvailableWidth, tableColumnWidths: tableColumnWidths)
    }

    static func document(content: RenderedMarkdown, title: String, fillsAvailableWidth: Bool = false,
                         tableColumnWidths: [[Double]] = [], messageToken: String = "") -> String {
        let nonce = UUID().uuidString
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; script-src 'nonce-\(nonce)'; base-uri 'none'">
        <title>\(escape(title))</title><style>\(styleSheet)</style></head>
        <body class="\(fillsAvailableWidth ? "fluid-layout" : "")"><main>\(content.html)</main>
        <script nonce="\(nonce)">\(tableInteractionScript(tableColumnWidths, messageToken: messageToken))</script></body></html>
        """
    }

    static func emptyDocument() -> String {
        document(markdown: "# PreviewMD\n\nOpen a Markdown file to read it. Use Open… or Command-O.", title: "PreviewMD")
    }

    static func errorDocument(message: String) -> String {
        document(content: RenderedMarkdown(html: "<h1>Unable to open the file</h1><p>\(escape(message))</p>", tableIdentifiers: []), title: "PreviewMD")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func tableInteractionScript(_ tableColumnWidths: [[Double]], messageToken: String) -> String {
        let encodedWidths: String
        if let data = try? JSONEncoder().encode(tableColumnWidths),
           let string = String(data: data, encoding: .utf8) {
            encodedWidths = string
        } else {
            encodedWidths = "[]"
        }

        return """
        (() => {
          const storedWidths = \(encodedWidths);
          const messageToken = \(String(data: try! JSONEncoder().encode(messageToken), encoding: .utf8)!);
          let scrollTimer;
          addEventListener('scroll', () => {
            clearTimeout(scrollTimer);
            scrollTimer = setTimeout(() => window.webkit?.messageHandlers?.previewMD?.postMessage({ type: 'position', token: messageToken, position: { x: scrollX, y: scrollY } }), 100);
          });
          const minimumColumnPixels = 72;
          document.querySelectorAll('img').forEach((img) => {
            const failed = () => {
              const fallback = document.createElement('span');
              fallback.className = 'image-error';
              fallback.textContent = `Image unavailable: ${img.alt || 'unnamed image'}`;
              img.replaceWith(fallback);
            };
            img.addEventListener('error', failed);
            if (img.complete && img.naturalWidth === 0) failed();
          });
          const frames = Array.from(document.querySelectorAll('.table-frame'));

          window.previewMD = {
            documentToken: messageToken,
            position() { return { x: scrollX, y: scrollY }; },
            restorePosition(position) { scrollTo(position.x || 0, position.y || 0); },
            goToAnchor(fragment) {
              const target = document.getElementById(fragment);
              if (target) target.scrollIntoView();
              return !!target;
            },
            setReadingWidthMode(mode) {
              document.body.classList.toggle('fluid-layout', mode === 'fluid');
            }
          };

          const normalise = (widths) => {
            const total = widths.reduce((sum, width) => sum + width, 0);
            return total > 0 ? widths.map((width) => (width / total) * 100) : widths;
          };

          const allWidths = () => frames.map((frame) =>
            Array.from(frame.querySelectorAll('col')).map((column) => Number.parseFloat(column.style.width))
          );

          const persist = () => {
            const handler = window.webkit?.messageHandlers?.previewMD;
            if (handler) handler.postMessage({ type: 'tableColumnWidths', token: messageToken, tables: allWidths(), identifiers: frames.map(f => f.dataset.tableId) });
          };

          frames.forEach((frame, frameIndex) => {
            const table = frame.querySelector('table');
            const headers = Array.from(table.querySelectorAll('thead th'));
            if (headers.length < 2) return;

            const colgroup = document.createElement('colgroup');
            const saved = storedWidths[frameIndex];
            const validSaved = Array.isArray(saved)
              && saved.length === headers.length
              && saved.every((width) => Number.isFinite(width) && width > 0);
            const measured = headers.map((header) => header.getBoundingClientRect().width);
            const widths = normalise(validSaved ? saved : measured);
            widths.forEach((width) => {
              const column = document.createElement('col');
              column.style.width = `${width}%`;
              colgroup.append(column);
            });
            table.prepend(colgroup);

            const columns = () => Array.from(colgroup.querySelectorAll('col'));
            const readWidths = () => columns().map((column) => Number.parseFloat(column.style.width));
            const writeWidths = (nextWidths) => {
              normalise(nextWidths).forEach((width, index) => {
                columns()[index].style.width = `${width}%`;
              });
            };

            const handles = [];
            for (let index = 0; index < headers.length - 1; index += 1) {
              const handle = document.createElement('div');
              handle.className = 'table-resize-handle';
              handle.setAttribute('role', 'separator');
              handle.setAttribute('aria-label', `Resize column ${index + 1}`);
              handle.tabIndex = 0;
              handle.setAttribute('aria-orientation', 'vertical');
              handle.addEventListener('keydown', (event) => {
                if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
                event.preventDefault();
                const widths = readWidths();
                const delta = event.key === 'ArrowRight' ? 2 : -2;
                if (widths[index] + delta < 5 || widths[index + 1] - delta < 5) return;
                widths[index] += delta; widths[index + 1] -= delta;
                writeWidths(widths); positionHandles(); persist();
              });
              frame.append(handle);
              handles.push(handle);
            }

            const dividerIndexAt = (event) => headers.findIndex((header, index) =>
              index < headers.length - 1
              && Math.abs(event.clientX - header.getBoundingClientRect().right) <= 10
            );

            const setHoveredDivider = (index) => {
              handles.forEach((handle, handleIndex) => {
                handle.classList.toggle('is-hovered', handleIndex === index);
              });
              table.style.cursor = index >= 0 ? 'col-resize' : '';
            };

            const beginResize = (index, event) => {
              event.preventDefault();
              event.stopPropagation();
              const startingWidths = readWidths();
              const startingX = event.clientX;
              const tableWidth = table.getBoundingClientRect().width;
              const minimumPercent = (minimumColumnPixels / tableWidth) * 100;
              document.body.classList.add('resizing-table');

              const move = (moveEvent) => {
                const delta = ((moveEvent.clientX - startingX) / tableWidth) * 100;
                const left = Math.max(minimumPercent, startingWidths[index] + delta);
                const appliedDelta = left - startingWidths[index];
                const nextWidths = [...startingWidths];
                nextWidths[index] = left;
                nextWidths[index + 1] = startingWidths[index + 1] - appliedDelta;
                if (nextWidths[index + 1] < minimumPercent) return;
                writeWidths(nextWidths);
                positionHandles();
              };
              const finish = () => {
                document.removeEventListener('mousemove', move);
                document.removeEventListener('mouseup', finish);
                document.body.classList.remove('resizing-table');
                setHoveredDivider(-1);
                persist();
              };
              document.addEventListener('mousemove', move);
              document.addEventListener('mouseup', finish);
            };

            table.addEventListener('mousemove', (event) => {
              setHoveredDivider(dividerIndexAt(event));
            });
            table.addEventListener('mouseleave', () => setHoveredDivider(-1));
            handles.forEach((handle, index) => handle.addEventListener('mousedown', (event) => { if (event.button === 0) beginResize(index, event); }));
            table.addEventListener('mousedown', (event) => {
              if (event.button !== 0) return;
              const index = dividerIndexAt(event);
              if (index >= 0) beginResize(index, event);
            });

            const positionHandles = () => {
              let offset = 0;
              readWidths().slice(0, -1).forEach((width, index) => {
                offset += width;
                handles[index].style.left = `calc(${offset}% - 6px)`;
              });
            };
            new ResizeObserver(positionHandles).observe(table);
            positionHandles();
          });
        })();
        """
    }

    private static let styleSheet = """
    :root { color-scheme: light dark; }
    .properties, .note-embed { border: 1px solid #8886; border-radius: 8px; padding: 16px; margin-bottom: 1.2em; }
    .properties h2 { font-size: 1em; margin: 0 0 12px; } .properties dl { margin: 0; }
    .property { display: grid; grid-template-columns: minmax(100px, 25%) 1fr; gap: 12px; margin: 8px 0; }
    .property dt { font-weight: 600; overflow-wrap: anywhere; } .property dd { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; }
    .property-type { font-size: .75em; opacity: .65; } .property ul { margin: 0; }
    .note-embed header { font-size: .8em; margin-bottom: 12px; } .render-warning { display: block; border-left: 3px solid #d29922; padding: 8px 12px; }
    .render-warning pre { white-space: pre-wrap; } .callout { border-left: 4px solid #3b82b6; border-radius: 6px; background: #3b82b615; margin: 16px 0; padding: 12px 16px; }
    .callout[data-callout="warning"], .callout[data-callout="danger"], .callout[data-callout="error"] { border-color: #d29922; }
    .callout-title, .callout summary { font-weight: 600; margin-bottom: 8px; } .callout summary { cursor: pointer; }
    mark { background: #f4cf5e80; color: inherit; } input[type="checkbox"] { accent-color: #3b82b6; }

    body { margin: 0; background: #ffffff; color: #1f2328; font: 17px/1.65 -apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif; }
    main { box-sizing: border-box; width: min(100%, 888px); margin: 0 auto; padding: 52px 44px 80px; }
    body.fluid-layout main { width: 100%; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.8em 0 .6em; letter-spacing: -.02em; }
    h1 { font-size: 2.1em; margin-top: 0; } h2 { font-size: 1.6em; } h3 { font-size: 1.3em; }
    p, ul, ol, blockquote, pre { margin: 0 0 1.1em; }
    ul, ol { padding-left: 1.45em; } li + li { margin-top: .24em; }
    a { color: #0969da; text-decoration: none; } a:hover { text-decoration: underline; }
    code { font: .88em/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; padding: .15em .34em; border-radius: 5px; background: #f1f3f5; }
    pre { overflow: auto; padding: 16px 18px; border-radius: 10px; background: #f6f8fa; } pre code { padding: 0; background: transparent; }
    blockquote { padding-left: 1em; color: #57606a; border-left: 3px solid #d0d7de; } blockquote > :last-child { margin-bottom: 0; }
    hr { height: 1px; margin: 2em 0; border: 0; background: #d8dee4; }
    .table-frame { position: relative; margin: 0 0 1.2em; overflow: hidden; border: 1px solid #d8dee4; border-radius: 8px; }
    table { width: 100%; margin: 0; border-collapse: collapse; table-layout: fixed; }
    th, td { padding: .55em .7em; text-align: left; border-right: 1px solid #d8dee4; border-bottom: 1px solid #d8dee4; vertical-align: top; } th { font-weight: 600; background: #f6f8fa; }
    th[align="right"], td[align="right"] { text-align: right; } th[align="center"], td[align="center"] { text-align: center; }
    th:last-child, td:last-child { border-right: 0; } tbody tr:last-child td { border-bottom: 0; }
    .table-resize-handle { pointer-events: auto; position: absolute; top: 0; bottom: 0; z-index: 2; width: 12px; }
    .table-resize-handle::after { content: ""; position: absolute; top: 0; bottom: 0; left: 5px; width: 1px; background: transparent; }
    .table-resize-handle.is-hovered::after, .resizing-table .table-resize-handle.is-hovered::after { background: #0969da; }
    .resizing-table, .resizing-table * { user-select: none !important; }
    img { max-width: 100%; border-radius: 8px; } .image-error { display: block; padding: 12px; border: 1px solid currentColor; } .table-resize-handle:focus-visible { outline: 2px solid #0969da; } th, td { overflow-wrap: anywhere; }
    @media (prefers-color-scheme: dark) {
      body { background: #1e1e1e; color: #e6edf3; } a { color: #58a6ff; }
      code, pre, th { background: #2b2b2b; } blockquote { color: #a7b0ba; border-color: #4b5563; } hr, .table-frame, th, td { border-color: #3b434c; }
    }
    @media (max-width: 640px) { main { padding: 32px 22px 56px; } body { font-size: 16px; } }
    """
}
