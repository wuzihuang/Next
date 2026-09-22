"""Run the real panel request/turn lifecycle with a controlled asynchronous turn body.

This covers state transitions, not SwiftUI rendering or the ASR/network transport.
Run from the repo root: python3 app/Tests/diagnostics/ai_panel_reentry.py
"""
from pathlib import Path
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[2]
service = (APP / "NextBody/Services/AIService.swift").read_text()
home = (APP / "NextBody/Features/Home/HomeView.swift").read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


# Keep the production entry and defer together; replace only transport/tool work.
entry_start = service.index("        activeTurnID = turnID", service.index("func turn("))
entry_end = service.index("        #if DEBUG && targetEnvironment(simulator)", entry_start)
entry = service[entry_start:entry_end]
reset = block(service, "func prepareForNewRequest()") if "func prepareForNewRequest()" in service else ""
completion = block(home, "withAnimation {\n                if sentImage != nil")

source = r'''
import Foundation
func L(_ text: String) -> String { text }
func withAnimation(_ body: () -> Void) { body() }
enum PanelType { case text }
enum Tag { case fuel }
enum PanelData { case none }
struct PanelWidget {
    var type: PanelType = .text
    var title: String
    var tag: Tag = .fuel
    var sentence: String
    var footer: String? = nil
    var action: String? = nil
    var data: PanelData = .none
    static func thinking(_ text: String) -> Self { Self(title: "THINKING", sentence: text) }
}
@MainActor final class PhoneToolRunner {
    static let shared = PhoneToolRunner()
    var active: UUID?
    func beginTurn(_ id: UUID) -> UUID { active = id; return id }
    func finishTurn(_ id: UUID) { if active == id { active = nil } }
}
@MainActor final class AIService {
    var activeTurnID: UUID?
    var coachHandoffReceived = false
    var thinking = false
    var thoughts: [String] = []
    var reading: String?
    var lastError: String?
    var lastErrorCode: String?
    var lastRetryAfter: Int?
'''
source += reset + "\n"
source += "func run(_ turnID: UUID, body: () async -> Void) async {\n" + entry + "_ = phoneScope\nawait body()\n}\n}\n"
source += "@MainActor final class Home {\nlet ai: AIService\nvar panelRequestID = UUID()\nvar widget: PanelWidget?\ninit(_ ai: AIService) { self.ai = ai }\n"
source += block(home, "private func beginPanelRequest()").replace("private func", "func", 1)
source += "\nfunc complete(frame: PanelWidget?, sentImage: String? = nil, text: String) {\n" + completion + "\n}\n}\n"
source += r'''
@MainActor func run() async {
    var failures = 0
    func check(_ passed: Bool, _ name: String) {
        print("\(passed ? "PASS" : "FAIL"): \(name)")
        if !passed { failures += 1 }
    }
    let ai = AIService(), home = Home(AIService())
    await ai.run(UUID()) {
        ai.thoughts = ["Previous task reasoning"]
        ai.reading = "old.tool"
    }
    check(ai.thoughts.isEmpty && ai.reading == nil && !ai.thinking,
          "completed turn leaves no reasoning for the next transcription")

    let panel = Home(ai)
    ai.thoughts = ["Previous task reasoning"]
    ai.reading = "old.tool"
    ai.lastError = "Old failure"
    _ = panel.beginPanelRequest()
    check(ai.thoughts.isEmpty && ai.reading == nil && ai.lastError == nil,
          "new panel request clears progress synchronously, before ASR or task scheduling")

    let oldID = UUID(), newID = UUID()
    var oldResume: CheckedContinuation<Void, Never>?
    let old = Task { @MainActor in
        await ai.run(oldID) {
            ai.thoughts = ["Old in-flight reasoning"]
            await withCheckedContinuation { oldResume = $0 }
        }
    }
    while oldResume == nil { await Task.yield() }
    _ = panel.beginPanelRequest()
    check(ai.activeTurnID == nil && PhoneToolRunner.shared.active == nil,
          "replacement retires old stream and phone-tool ownership before transcription")
    check(ai.thoughts.isEmpty, "replacement clears in-flight progress while ASR is pending")

    var newerResume: CheckedContinuation<Void, Never>?
    let newer = Task { @MainActor in
        await ai.run(newID) {
            ai.thoughts = ["New task reasoning"]
            await withCheckedContinuation { newerResume = $0 }
        }
    }
    while newerResume == nil { await Task.yield() }
    check(ai.activeTurnID == newID && ai.thoughts == ["New task reasoning"],
          "new task starts immediately with only its own progress")
    oldResume?.resume()
    await old.value
    check(ai.activeTurnID == newID && ai.thinking && ai.thoughts == ["New task reasoning"]
          && PhoneToolRunner.shared.active == newID,
          "old turn's delayed completion cannot clear the new task or its phone-tool ownership")
    newerResume?.resume()
    await newer.value

    home.ai.lastError = "Allowance unavailable"
    home.complete(frame: nil, text: "New task")
    check(home.widget?.title != "THINKING" && home.widget?.sentence == "Allowance unavailable",
          "a finished request with no frame reports its error instead of restarting thinking")
    let answer = PanelWidget(title: "DONE", sentence: "New result")
    home.complete(frame: answer, text: "New task")
    check(home.widget?.sentence == "New result", "successful results still reach the panel")
    if failures > 0 { exit(1) }
}
await run()
'''

with tempfile.TemporaryDirectory(prefix="next-ai-panel-reentry-") as tmp:
    folder = Path(tmp)
    (folder / "main.swift").write_text(source)
    subprocess.run(["swiftc", "-swift-version", "5", str(folder / "main.swift"),
                    "-o", str(folder / "test")], check=True)
    subprocess.run([str(folder / "test")], check=True)
