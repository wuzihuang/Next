import Foundation

/// Chat-sized Markdown: the AI writes headings, lists, emphasis and fenced code, and the
/// thread has to print them as structure rather than the raw markers.
enum ChatMarkdown {
    struct Document: Equatable {
        var blocks: [Block]
    }

    enum Block: Equatable {
        case heading(level: Int, inlines: [Inline])
        case paragraph([Inline])
        case bullet([Inline])
        case numbered(Int, [Inline])
        case quote([Inline])
        case code(language: String?, text: String)
        case thematicBreak
    }

    enum Inline: Equatable {
        case text(String)
        case strong([Inline])
        case emphasis([Inline])
        case code(String)
        case link(text: String, destination: String)
    }

    static func parse(_ source: String) -> Document {
        Document(blocks: parseBlocks(source))
    }

    /// Marker-free reading order, used for accessibility and for tests that the page
    /// is showing the words rather than `**rate**`.
    static func plainText(_ source: String) -> String {
        parse(source).blocks.map(plain(block:)).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func plain(inlines: [Inline]) -> String {
        inlines.map(plain(inline:)).joined()
    }

    static func plain(inline: Inline) -> String {
        switch inline {
        case let .text(text): text
        case let .strong(inner), let .emphasis(inner): plain(inlines: inner)
        case let .code(text): text
        case let .link(text, _): text
        }
    }

    static func plain(block: Block) -> String {
        switch block {
        case let .heading(_, inlines), let .paragraph(inlines), let .bullet(inlines), let .quote(inlines):
            plain(inlines: inlines)
        case let .numbered(n, inlines):
            "\(n). \(plain(inlines: inlines))"
        case let .code(_, text):
            text
        case .thematicBreak:
            ""
        }
    }
}

private extension ChatMarkdown {
    static func parseBlocks(_ source: String) -> [Block] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language.isEmpty ? nil : language, text: body.joined(separator: "\n")))
                continue
            }
            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }
            if let heading = heading(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    var rest = String(next.dropFirst())
                    if rest.hasPrefix(" ") { rest = String(rest.dropFirst()) }
                    quoted.append(rest)
                    index += 1
                }
                blocks.append(.quote(parseInlines(quoted.joined(separator: "\n"))))
                continue
            }
            if let item = bullet(from: line) {
                blocks.append(item)
                index += 1
                continue
            }
            if let item = numbered(from: line) {
                blocks.append(item)
                index += 1
                continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if nextTrimmed.hasPrefix("```") { break }
                if isThematicBreak(nextTrimmed) { break }
                if heading(from: nextTrimmed) != nil { break }
                if nextTrimmed.hasPrefix(">") { break }
                if bullet(from: next) != nil { break }
                if numbered(from: next) != nil { break }
                paragraph.append(next)
                index += 1
            }
            blocks.append(.paragraph(parseInlines(paragraph.joined(separator: "\n"))))
        }
        return blocks
    }

    static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
    }

    static func heading(from trimmed: String) -> Block? {
        guard trimmed.first == "#" else { return nil }
        var level = 0
        var rest = trimmed
        while rest.first == "#", level < 6 {
            level += 1
            rest = String(rest.dropFirst())
        }
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(level: level, inlines: parseInlines(title))
    }

    static func bullet(from line: String) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let mark = trimmed.first, ["-", "*", "+"].contains(mark) else { return nil }
        let rest = trimmed.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return .bullet(parseInlines(rest.trimmingCharacters(in: .whitespaces)))
    }

    static func numbered(from line: String) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digits = ""
        var rest = trimmed
        while let ch = rest.first, ch.isNumber {
            digits.append(ch)
            rest = String(rest.dropFirst())
        }
        guard !digits.isEmpty, rest.first == ".", digits.count <= 9 else { return nil }
        rest = String(rest.dropFirst())
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return .numbered(Int(digits) ?? 1, parseInlines(rest.trimmingCharacters(in: .whitespaces)))
    }

    static func parseInlines(_ source: String) -> [Inline] {
        var result: [Inline] = []
        var text = ""
        var index = source.startIndex

        func flush() {
            if !text.isEmpty {
                result.append(.text(text))
                text = ""
            }
        }

        while index < source.endIndex {
            let rest = source[index...]
            if rest.hasPrefix("`"), let close = findClose(in: source, from: source.index(after: index), marker: "`") {
                flush()
                result.append(.code(String(source[source.index(after: index)..<close])))
                index = source.index(after: close)
                continue
            }
            if rest.hasPrefix("**") || rest.hasPrefix("__") {
                let marker = rest.hasPrefix("**") ? "**" : "__"
                let innerStart = source.index(index, offsetBy: marker.count)
                if let close = findClose(in: source, from: innerStart, marker: marker), close > innerStart {
                    flush()
                    result.append(.strong(parseInlines(String(source[innerStart..<close]))))
                    index = source.index(close, offsetBy: marker.count)
                    continue
                }
            }
            if rest.hasPrefix("*") || rest.hasPrefix("_") {
                let marker = rest.hasPrefix("*") ? "*" : "_"
                if marker == "_" && !allowsUnderscore(at: index, in: source) {
                    text.append(source[index])
                    index = source.index(after: index)
                    continue
                }
                let innerStart = source.index(after: index)
                if let close = findClose(in: source, from: innerStart, marker: marker), close > innerStart {
                    flush()
                    result.append(.emphasis(parseInlines(String(source[innerStart..<close]))))
                    index = source.index(after: close)
                    continue
                }
            }
            if rest.hasPrefix("["), let link = readLink(in: source, from: index) {
                flush()
                result.append(.link(text: link.text, destination: link.destination))
                index = link.end
                continue
            }
            text.append(source[index])
            index = source.index(after: index)
        }
        flush()
        return result
    }

    static func allowsUnderscore(at index: String.Index, in source: String) -> Bool {
        if index == source.startIndex { return true }
        let previous = source[source.index(before: index)]
        return previous.isWhitespace || previous.isPunctuation
    }

    static func findClose(in source: String, from start: String.Index, marker: String) -> String.Index? {
        var index = start
        while index < source.endIndex {
            let rest = source[index...]
            if marker == "*", rest.hasPrefix("**") {
                index = source.index(index, offsetBy: 2)
                continue
            }
            if marker == "_", rest.hasPrefix("__") {
                index = source.index(index, offsetBy: 2)
                continue
            }
            if rest.hasPrefix(marker) { return index }
            index = source.index(after: index)
        }
        return nil
    }

    static func readLink(in source: String, from start: String.Index) -> (text: String, destination: String, end: String.Index)? {
        guard source[start] == "[" else { return nil }
        var index = source.index(after: start)
        var text = ""
        while index < source.endIndex, source[index] != "]" {
            if source[index] == "\n" { return nil }
            text.append(source[index])
            index = source.index(after: index)
        }
        guard index < source.endIndex else { return nil }
        index = source.index(after: index)
        guard index < source.endIndex, source[index] == "(" else { return nil }
        index = source.index(after: index)
        var destination = ""
        while index < source.endIndex, source[index] != ")" {
            if source[index] == "\n" { return nil }
            destination.append(source[index])
            index = source.index(after: index)
        }
        guard index < source.endIndex else { return nil }
        return (text, destination, source.index(after: index))
    }
}
