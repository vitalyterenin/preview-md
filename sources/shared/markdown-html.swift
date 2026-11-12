import Foundation

enum MarkdownHTML {
    private struct CodeFence {
        let marker: Character
        let length: Int
        let language: String
    }

    static func document(
        markdown: String,
        title: String,
        fillsAvailableWidth: Bool = false,
        tableColumnWidths: [[Double]] = []
    ) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(title))</title>
          <style>\(styleSheet)</style>
        </head>
        <body class="\(fillsAvailableWidth ? "fluid-layout" : "")">
          <main>\(renderBlocks(markdown))</main>
          <script>\(tableInteractionScript(tableColumnWidths))</script>
        </body>
        </html>
        """
    }

    static func emptyDocument() -> String {
        document(
            markdown: "# PreviewMD\n\nOpen a Markdown file to read it as a formatted document.",
            title: "PreviewMD"
        )
    }

    static func errorDocument(message: String) -> String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><style>\(styleSheet)</style></head>
        <body><main><h1>Unable to open the file</h1><p>\(escape(message))</p></main></body></html>
        """
    }

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [String] = []
        var index = 0
        var tableIdentifier = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = codeFence(in: trimmed) {
                index += 1
                var code: [String] = []
                while index < lines.count && !isClosingCodeFence(lines[index], for: fence) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                let className = fence.language.isEmpty ? "" : " class=\"language-\(escape(fence.language))\""
                blocks.append("<pre><code\(className)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            if let table = renderTable(startingAt: index, lines: lines, identifier: tableIdentifier) {
                blocks.append(table.html)
                index = table.nextIndex
                tableIdentifier += 1
                continue
            }

            if let heading = heading(in: trimmed) {
                blocks.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append("<hr>")
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let quote = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quote.hasPrefix(">") else { break }
                    quoteLines.append(String(quote.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append("<blockquote>\(renderBlocks(quoteLines.joined(separator: "\n")))</blockquote>")
                continue
            }

            if let firstItem = listItem(in: line) {
                let ordered = firstItem.ordered
                var items: [String] = []
                while index < lines.count, let item = listItem(in: lines[index]), item.ordered == ordered {
                    items.append("<li>\(renderInline(item.text))</li>")
                    index += 1
                }
                let tag = ordered ? "ol" : "ul"
                blocks.append("<\(tag)>\(items.joined())</\(tag)>")
                continue
            }

            var paragraph: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty || (paragraph.isEmpty ? false : startsBlock(candidate)) {
                    break
                }
                paragraph.append(candidateTrimmed)
                index += 1
            }
            blocks.append("<p>\(renderInline(paragraph.joined(separator: " ")))</p>")
        }

        return blocks.joined(separator: "\n")
    }

    private static func renderTable(startingAt index: Int, lines: [String], identifier: Int) -> (html: String, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let headers = tableCells(in: lines[index])
        guard headers.count >= 2,
              let alignments = tableAlignments(for: lines[index + 1], columnCount: headers.count) else {
            return nil
        }

        var nextIndex = index + 2
        var rows: [[String]] = []
        while nextIndex < lines.count {
            let row = lines[nextIndex]
            guard !row.trimmingCharacters(in: .whitespaces).isEmpty,
                  row.contains("|") else { break }
            let cells = tableCells(in: row)
            guard cells.count >= 2 else { break }
            rows.append(normalizeTableCells(cells, columnCount: headers.count))
            nextIndex += 1
        }

        let normalizedHeaders = normalizeTableCells(headers, columnCount: headers.count)
        let headerHTML = zip(normalizedHeaders, alignments).map { cell, alignment in
            "<th\(alignment)>\(renderInline(cell))</th>"
        }.joined()
        let rowsHTML = rows.map { row in
            let cells = zip(row, alignments).map { cell, alignment in
                "<td\(alignment)>\(renderInline(cell))</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined(separator: "\n")

        return ("<div class=\"table-frame\" data-table-id=\"\(identifier)\"><table><thead><tr>\(headerHTML)</tr></thead><tbody>\(rowsHTML)</tbody></table></div>", nextIndex)
    }

    private static func tableCells(in line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.first == "|" { content.removeFirst() }
        if content.last == "|" { content.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in content {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func tableAlignments(for separator: String, columnCount: Int) -> [String]? {
        let columns = tableCells(in: separator)
        guard columns.count == columnCount else { return nil }

        var alignments: [String] = []
        for column in columns {
            let compact = column.replacingOccurrences(of: " ", with: "")
            let hasLeadingColon = compact.hasPrefix(":")
            let hasTrailingColon = compact.hasSuffix(":")
            let dashes = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard dashes.count >= 3, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (hasLeadingColon, hasTrailingColon) {
            case (true, true): alignments.append(" style=\"text-align:center\"")
            case (false, true): alignments.append(" style=\"text-align:right\"")
            default: alignments.append("")
            }
        }
        return alignments
    }

    private static func normalizeTableCells(_ cells: [String], columnCount: Int) -> [String] {
        Array((cells + Array(repeating: "", count: max(0, columnCount - cells.count))).prefix(columnCount))
    }

    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return codeFence(in: trimmed) != nil
            || heading(in: trimmed) != nil
            || trimmed.hasPrefix(">")
            || isHorizontalRule(trimmed)
            || listItem(in: line) != nil
    }

    private static func codeFence(in line: String) -> CodeFence? {
        guard let marker = line.first, marker == "`" || marker == "~" else { return nil }

        var length = 0
        for character in line {
            guard character == marker else { break }
            length += 1
        }
        guard length >= 3 else { return nil }

        let language = String(line.dropFirst(length)).trimmingCharacters(in: .whitespaces)
        return CodeFence(marker: marker, length: length, language: language)
    }

    private static func isClosingCodeFence(_ line: String, for openingFence: CodeFence) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == openingFence.marker else { return false }

        var length = 0
        for character in trimmed {
            guard character == openingFence.marker else { break }
            length += 1
        }
        guard length >= openingFence.length else { return false }
        return trimmed.dropFirst(length).allSatisfy(\.isWhitespace)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level), line.dropFirst(level).first?.isWhitespace == true else { return nil }
        return (level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let character = compact.first, ["-", "*", "_"].contains(character) else {
            return false
        }
        return compact.allSatisfy { $0 == character }
    }

    private static func listItem(in line: String) -> (ordered: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return (false, String(trimmed.dropFirst(marker.count)))
        }

        let pieces = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2, let last = pieces[0].last, last == "." || last == ")" else { return nil }
        let number = pieces[0].dropLast()
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return (true, String(pieces[1]))
    }

    private static func renderInline(_ text: String) -> String {
        var protectedCode: [String] = []
        var output = escape(text)

        output = replace(pattern: "`([^`]+)`", in: output) { match in
            let token = "\u{E000}\(protectedCode.count)\u{E001}"
            protectedCode.append("<code>\(match[1])</code>")
            return token
        }

        output = replace(pattern: "!\\[([^]]*)\\]\\(([^ )]+)(?:\\s+\\\"[^\\\"]*\\\")?\\)", in: output) { match in
            "<img src=\"\(safeURL(match[2]))\" alt=\"\(match[1])\">"
        }
        output = replace(pattern: "\\[([^]]+)\\]\\(([^ )]+)\\)", in: output) { match in
            "<a href=\"\(safeURL(match[2]))\">\(match[1])</a>"
        }
        output = replace(pattern: "\\*\\*(.+?)\\*\\*|__(.+?)__", in: output) { match in
            "<strong>\(match[1].isEmpty ? match[2] : match[1])</strong>"
        }
        output = replace(pattern: "~~(.+?)~~", in: output) { match in
            "<del>\(match[1])</del>"
        }
        output = replace(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)|(?<!_)_([^_]+)_(?!_)", in: output) { match in
            "<em>\(match[1].isEmpty ? match[2] : match[1])</em>"
        }

        for index in protectedCode.indices.reversed() {
            output = output.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: protectedCode[index])
        }
        return output
    }

    private static func replace(pattern: String, in text: String, transform: ([String]) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = expression.matches(in: text, range: range).reversed()
        var output = text

        for match in matches {
            let captures = (0..<match.numberOfRanges).map { index -> String in
                let captureRange = match.range(at: index)
                guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: output) else { return "" }
                return String(output[swiftRange])
            }
            guard let matchRange = Range(match.range, in: output) else { continue }
            output.replaceSubrange(matchRange, with: transform(captures))
        }
        return output
    }

    private static func safeURL(_ url: String) -> String {
        let decoded = url.replacingOccurrences(of: "&amp;", with: "&")
        guard let scheme = URL(string: decoded)?.scheme?.lowercased() else { return url }
        return ["http", "https", "mailto", "file"].contains(scheme) ? url : "#"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func tableInteractionScript(_ tableColumnWidths: [[Double]]) -> String {
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
          const minimumColumnPixels = 72;
          const frames = Array.from(document.querySelectorAll('.table-frame'));

          window.previewMD = {
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
            if (handler) handler.postMessage({ type: 'tableColumnWidths', tables: allWidths() });
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
                const right = Math.max(minimumPercent, startingWidths[index + 1] - delta);
                const appliedDelta = left - startingWidths[index];
                const nextWidths = [...startingWidths];
                nextWidths[index] = left;
                nextWidths[index + 1] = startingWidths[index + 1] - appliedDelta;
                if (right < minimumPercent) return;
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
    th:last-child, td:last-child { border-right: 0; } tbody tr:last-child td { border-bottom: 0; }
    .table-resize-handle { pointer-events: none; position: absolute; top: 0; bottom: 0; z-index: 2; width: 12px; }
    .table-resize-handle::after { content: ""; position: absolute; top: 0; bottom: 0; left: 5px; width: 1px; background: transparent; }
    .table-resize-handle.is-hovered::after, .resizing-table .table-resize-handle.is-hovered::after { background: #0969da; }
    .resizing-table, .resizing-table * { user-select: none !important; }
    img { max-width: 100%; border-radius: 8px; }
    @media (prefers-color-scheme: dark) {
      body { background: #1e1e1e; color: #e6edf3; } a { color: #58a6ff; }
      code, pre, th { background: #2b2b2b; } blockquote { color: #a7b0ba; border-color: #4b5563; } hr, .table-frame, th, td { border-color: #3b434c; }
    }
    @media (max-width: 640px) { main { padding: 32px 22px 56px; } body { font-size: 16px; } }
    """
}
