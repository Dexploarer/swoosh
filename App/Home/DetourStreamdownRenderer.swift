// DetourStreamdownRenderer.swift — native streaming markdown renderer (0.5A)

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct DetourStreamdownRenderer: View {
    let markdown: String

    private var blocks: [DetourStreamBlock] {
        DetourStreamdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: DetourStreamBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(attributed(text))
                .font(level == 1 ? .title3.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, block.id == 0 ? 0 : 4)
        case .paragraph(let text):
            Text(attributed(text))
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, let checked):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: checked == nil ? "circle.fill" : checked == true ? "checkmark.square.fill" : "square")
                    .font(.system(size: checked == nil ? 5 : 13, weight: .semibold))
                    .foregroundStyle(checked == true ? .green : .secondary)
                    .frame(width: 16, height: 19)
                Text(attributed(text))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .quote(let text):
            Text(attributed(text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.secondary.opacity(0.35)).frame(width: 2)
                }
        case .code(let language, let value):
            codeBlock(language: language, value: value)
        case .table(let rows):
            tableBlock(rows)
        }
    }

    private func codeBlock(language: String?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text((language?.isEmpty == false ? language : "code") ?? "code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(value)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(value)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.90))
                    .textSelection(.enabled)
                    .padding(.bottom, 1)
            }
        }
        .padding(12)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func tableBlock(_ rows: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if !DetourStreamdownParser.isDivider(row) {
                        Text(row)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func attributed(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value)) ?? AttributedString(value)
    }

    private func copy(_ value: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

private struct DetourStreamBlock: Identifiable {
    let id: Int
    let kind: DetourStreamBlockKind
}

private enum DetourStreamBlockKind {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, checked: Bool?)
    case quote(String)
    case code(language: String?, value: String)
    case table([String])
}

private enum DetourStreamdownParser {
    static func parse(_ raw: String) -> [DetourStreamBlock] {
        let lines = healed(raw).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [DetourStreamBlock] = []
        var paragraph: [String] = []
        var table: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false

        func append(_ kind: DetourStreamBlockKind) {
            blocks.append(DetourStreamBlock(id: blocks.count, kind: kind))
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        func flushTable() {
            guard !table.isEmpty else { return }
            append(.table(table))
            table.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushTable()
                if inCode {
                    append(.code(language: language, value: code.joined(separator: "\n")))
                    code.removeAll()
                    language = nil
                    inCode = false
                } else {
                    language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                flushTable()
                continue
            }
            if trimmed.contains("|"), trimmed.split(separator: "|").count > 1 {
                flushParagraph()
                table.append(trimmed)
                continue
            }
            flushTable()
            if let heading = heading(trimmed) {
                flushParagraph()
                append(.heading(level: heading.level, text: heading.text))
            } else if let bullet = bullet(trimmed) {
                flushParagraph()
                append(.bullet(text: bullet.text, checked: bullet.checked))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if inCode {
            append(.code(language: language, value: code.joined(separator: "\n")))
        }
        flushParagraph()
        flushTable()
        return blocks
    }

    static func isDivider(_ row: String) -> Bool {
        row.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
            .isEmpty
    }

    private static func healed(_ raw: String) -> String {
        var value = raw
        if value.components(separatedBy: "```").count.isMultiple(of: 2) {
            value += "\n```"
        }
        if !value.isEmpty, value.components(separatedBy: "**").count.isMultiple(of: 2) {
            value += "**"
        }
        return value
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func bullet(_ line: String) -> (text: String, checked: Bool?)? {
        if line.hasPrefix("- [ ] ") { return (String(line.dropFirst(6)), false) }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return (String(line.dropFirst(6)), true) }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return (String(line.dropFirst(2)), nil) }
        return nil
    }
}
