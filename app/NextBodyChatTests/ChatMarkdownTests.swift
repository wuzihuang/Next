import XCTest
@testable import NextBodyChatCore

final class ChatMarkdownTests: XCTestCase {
    func testStrongEmphasisAndInlineCodeAreStructured() {
        let doc = ChatMarkdown.parse("Heart **rate** looks *steady*. Use `RMSSD`.")
        XCTAssertEqual(doc.blocks, [
            .paragraph([
                .text("Heart "),
                .strong([.text("rate")]),
                .text(" looks "),
                .emphasis([.text("steady")]),
                .text(". Use "),
                .code("RMSSD"),
                .text("."),
            ]),
        ])
        XCTAssertEqual(ChatMarkdown.plainText("Heart **rate** looks *steady*. Use `RMSSD`."),
                       "Heart rate looks steady. Use RMSSD.")
        XCTAssertFalse(ChatMarkdown.plainText("Heart **rate** looks *steady*.").contains("**"))
        XCTAssertFalse(ChatMarkdown.plainText("Heart **rate** looks *steady*.").contains("*steady*"))
    }

    func testHeadingsListsQuotesAndFencedCodeBecomeBlocks() {
        let source = """
        ## Overnight

        - Deep sleep held
        - HRV recovered

        1. First
        2. Second

        > keep the load easy

        ```
        42 ms
        ```
        """
        XCTAssertEqual(ChatMarkdown.parse(source).blocks, [
            .heading(level: 2, inlines: [.text("Overnight")]),
            .bullet([.text("Deep sleep held")]),
            .bullet([.text("HRV recovered")]),
            .numbered(1, [.text("First")]),
            .numbered(2, [.text("Second")]),
            .quote([.text("keep the load easy")]),
            .code(language: nil, text: "42 ms"),
        ])
        XCTAssertEqual(ChatMarkdown.plainText(source), """
        Overnight
        Deep sleep held
        HRV recovered
        1. First
        2. Second
        keep the load easy
        42 ms
        """)
    }

    func testFencedCodeDoesNotInterpretInnerMarkers() {
        let source = """
        ```swift
        let rate = **not bold**
        ```
        """
        XCTAssertEqual(ChatMarkdown.parse(source).blocks, [
            .code(language: "swift", text: "let rate = **not bold**"),
        ])
        XCTAssertEqual(ChatMarkdown.plainText(source), "let rate = **not bold**")
    }

    func testLinkAndNestedEmphasisInsideStrong() {
        let doc = ChatMarkdown.parse("See [Heart](nextbody://heart) and **hold *easy* today**.")
        XCTAssertEqual(doc.blocks, [
            .paragraph([
                .text("See "),
                .link(text: "Heart", destination: "nextbody://heart"),
                .text(" and "),
                .strong([
                    .text("hold "),
                    .emphasis([.text("easy")]),
                    .text(" today"),
                ]),
                .text("."),
            ]),
        ])
        XCTAssertEqual(ChatMarkdown.plainText("See [Heart](nextbody://heart)."), "See Heart.")
    }

    func testUnclosedMarkersStayLiteralAndCJKStillParses() {
        XCTAssertEqual(ChatMarkdown.parse("**oops").blocks, [.paragraph([.text("**oops")])])
        XCTAssertEqual(ChatMarkdown.parse("心率 **平稳**").blocks, [
            .paragraph([
                .text("心率 "),
                .strong([.text("平稳")]),
            ]),
        ])
        XCTAssertEqual(ChatMarkdown.plainText(""), "")
        XCTAssertEqual(ChatMarkdown.parse("just words").blocks, [.paragraph([.text("just words")])])
    }

    func testThematicBreakAndUnderscoreInsideWords() {
        XCTAssertEqual(ChatMarkdown.parse("---").blocks, [.thematicBreak])
        XCTAssertEqual(ChatMarkdown.parse("max_hr_zone stays").blocks, [
            .paragraph([.text("max_hr_zone stays")]),
        ])
        XCTAssertEqual(ChatMarkdown.parse("_easy_").blocks, [
            .paragraph([.emphasis([.text("easy")])]),
        ])
    }
}

final class ChatScrollTargetTests: XCTestCase {
    func testThinkingTakesPriorityOverTheLastMessage() {
        XCTAssertEqual(ChatScrollTarget.id(lastMessageID: UUID(), isThinking: true), ChatScrollTarget.thinking)
    }

    func testLatestMessageIsUsedWhenTheThreadIsIdle() {
        let id = UUID()
        XCTAssertEqual(ChatScrollTarget.id(lastMessageID: id, isThinking: false), id.uuidString)
    }

    func testEmptyThreadFallsBackToTheBottomSentinel() {
        XCTAssertEqual(ChatScrollTarget.id(lastMessageID: nil, isThinking: false), ChatScrollTarget.bottom)
    }
}
