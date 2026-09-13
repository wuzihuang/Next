import SwiftUI

/// Prints a chat-sized Markdown document in the thread's type ramp.
struct ChatMarkdownView: View {
    let source: String
    var family: NBFont.Family = .ui
    var size: CGFloat = 15
    var color: Color = NB.text1
    var accessibilityName: String = "chat.markdown"
    var expands: Bool = true

    var body: some View {
        let document = ChatMarkdown.parse(source)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
        .accessibilityIdentifier(accessibilityName)
        .accessibilityValue(ChatMarkdown.plainText(source))
    }

    @ViewBuilder
    private func blockView(_ block: ChatMarkdown.Block) -> some View {
        switch block {
        case let .heading(level, inlines):
            inlineText(inlines, size: headingSize(level), weight: 700)
                .foregroundStyle(color)
        case let .paragraph(inlines):
            inlineText(inlines, size: size, weight: 400)
                .lineSpacing(6)
        case let .bullet(inlines):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(NB.lime1)
                    .frame(width: 5, height: 5)
                    .padding(.bottom, 1)
                inlineText(inlines, size: size, weight: 400)
            }
        case let .numbered(n, inlines):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .font(NBFont.dot(600, size - 2))
                    .foregroundStyle(NB.lime1)
                inlineText(inlines, size: size, weight: 400)
            }
        case let .quote(inlines):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(NB.lime1.opacity(0.55))
                    .frame(width: 2)
                inlineText(inlines, size: size, weight: 400)
                    .foregroundStyle(NB.text2)
            }
        case let .code(_, text):
            Text(text.isEmpty ? " " : text)
                .font(.system(size: size * 0.86, design: .monospaced))
                .foregroundStyle(NB.lime1)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NB.carbon, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(NB.hairline, lineWidth: 1))
        case .thematicBreak:
            Hairline()
                .padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 22
        case 2: 18
        case 3: 16
        default: size
        }
    }

    private func inlineText(_ inlines: [ChatMarkdown.Inline], size: CGFloat, weight: Int) -> Text {
        inlines.reduce(Text("")) { $0 + render($1, size: size, weight: weight) }
    }

    private func render(_ inline: ChatMarkdown.Inline, size: CGFloat, weight: Int) -> Text {
        switch inline {
        case let .text(text):
            return Text(text)
                .font(NBFont.named(family, weight, size))
                .foregroundColor(color)
        case let .strong(inner):
            return inlineText(inner, size: size, weight: 700)
        case let .emphasis(inner):
            return inlineText(inner, size: size, weight: weight)
                .italic()
        case let .code(text):
            return Text(text)
                .font(.system(size: size * 0.92, design: .monospaced))
                .foregroundColor(NB.lime1)
        case let .link(text, destination):
            var attributed = AttributedString(text)
            attributed.font = NBFont.named(family, 500, size)
            attributed.foregroundColor = NB.lime1
            attributed.underlineStyle = .single
            if let url = URL(string: destination) {
                attributed.link = url
            }
            return Text(attributed)
        }
    }
}
