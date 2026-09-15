import Foundation
import SwiftUI
import os

/// The agent side. In production every AI call is an Edge Function on Supabase running the
/// Vercel AI SDK against qwen3.8-flash; the app never talks to a model directly and never
/// holds a model key.
///
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    @Published var lastError: String?
    @Published private(set) var lastErrorCode: String?
    /// ADR 0022 · with TURN_IN_PROGRESS the server names how long its lease has left.
    @Published private(set) var lastRetryAfter: Int?
    @Published var thinking = false
    private var activeTurnID: UUID?
    private var coachHandoffReceived = false

    func thoughts(for turnID: UUID) -> [Thought] {
        activeTurnID == turnID ? thoughts : []
    }

    private func receiveCoachHandoff(surface: String, onHandoff: (() -> Void)?) {
        guard surface == "panel", !coachHandoffReceived else { return }
        coachHandoffReceived = true
        thoughts = []
        reading = nil
        onHandoff?()
    }

    /// The tool she is reading right now, while she reads it. 07 · 16 · the panel says what
    /// it is doing instead of showing a spinner over an empty box.
    @Published var reading: String?

    /// 07 · 16 · 02 · her own reasoning, a line at a time, as the server cuts it from the
    /// model's reasoning stream. The THINKING screen prints these at its foot and nothing
    /// else; `reading` is what it falls back to on a turn that streamed no thoughts.
    @Published var thoughts: [Thought] = []
    struct Thought: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// When it landed — the screen types it out from this instant.
        let at: Date
    }
    /// The screen shows four; a fifth pushes the oldest off. Six kept so the exit has a frame.
    private static let thoughtsKept = 6

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NB_DEBUG_PANEL"] == "thinking" { debugPlayThoughts() }
        #endif
    }

    #if DEBUG
    /// `NB_DEBUG_PANEL=thinking` pins the singularity with no turn running, so nothing would
    /// ever stream. This plays a scripted reasoning at the wire's pace — one line every
    /// 1.7 s, looping — so the stream and its ripples can be photographed against the board.
    /// The text is the board's own sample, not a claim about anyone's night.
    func debugPlayThoughts() {
        guard Band.allowsSeed else { return }
        let script = [
            "Slept 5h12 · 1h40 under your week",
            "HRV 38 → 31 · two nights down",
            "Stress peaked 22:40 · still up at 1am",
            "So it is the sleep, not the strain",
            "Checking whether strain adds to it",
            "Training load was light all week",
        ]
        Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                thoughts.append(Thought(text: script[i % script.count], at: Date()))
                if thoughts.count > Self.thoughtsKept { thoughts.removeFirst(thoughts.count - Self.thoughtsKept) }
                i += 1
                try? await Task.sleep(nanoseconds: 1_700_000_000)
            }
        }
    }
    #endif

    /// Only acknowledgment and server calculation readiness can promote a pending record.
    /// Local live estimates are never submitted as authoritative health facts.
    private func pendingOperationCount(owner: String) -> Int? {
        let kinds = ["meal", "weigh-in", "body-composition", "band-domain", "band-sleep", "plan-check"]
        do {
            let local = try LocalDataStore.shared()
            return try kinds.reduce(0) { $0 + (try local.operations(account: owner, kind: $1)).count }
        } catch { return nil }
    }

    /// A normal turn sends local availability without uploading or waiting on settlement.
    /// Health reads can explicitly request preparation; the daily plan still prepares first.
    private func freshnessSnapshot(owner: String) -> [String: Any] {
        let pending = pendingOperationCount(owner: owner)
        return ["status": !Reachability.shared.isOnline ? "offline"
                    : pending == nil ? "failed" : pending! > 0 ? "pending" : "not_requested",
                "pending_operations": pending.map { $0 as Any } ?? NSNull()]
    }

    func prepareFreshness(day: UserDay, owner: String,
                          isAuthorized: @escaping @MainActor () -> Bool = { true }) async -> [String: Any] {
        var calculationPending: Bool?
        let status: AIFreshnessStatus
        if !Reachability.shared.isOnline { status = .offline }
        else {
            status = await AIFreshnessPolicy.prepare {
                @MainActor func eligible() -> Bool {
                    !Task.isCancelled && isAuthorized() && ConsentStore.shared.granted
                        && SupabaseClient.currentUserIdSnapshot() == owner
                }
                guard eligible() else { return .cancelled }
                await WeighInQueue.shared.flush()
                guard eligible() else { return .cancelled }
                await BodyCompositionQueue.shared.flush()
                guard eligible() else { return .cancelled }
                await Repository.shared.flushPendingEvidence()
                guard eligible() else { return .cancelled }
                do {
                    let db = SupabaseClient.shared
                    _ = try await db.rpc("settle_now", args: ["p_days": 1], expectedOwner: owner)
                    guard eligible() else { return .cancelled }
                    let rows = try await db.rpc("calculation_status", args: ["p_from": day.key, "p_to": day.key], expectedOwner: owner) as? [[String: Any]]
                    guard eligible() else { return .cancelled }
                    guard let rows, !rows.isEmpty else { return .failed }
                    calculationPending = rows.contains { ($0["pending"] as? Bool) != false }
                    guard let pending = self.pendingOperationCount(owner: owner) else { return .failed }
                    return pending == 0 && calculationPending == false ? .ready : .pending
                } catch { return Task.isCancelled ? .cancelled : .failed }
            }
        }
        let domains = BandDomainSyncState.load(userId: owner, deviceKey: BoundBand.identifier ?? "unknown", day: day.key)
        let iso = ISO8601DateFormatter()
        return [
            "status": status.rawValue,
            "pending_operations": pendingOperationCount(owner: owner).map { $0 as Any } ?? NSNull(),
            "calculation_pending": calculationPending.map { $0 as Any } ?? NSNull(),
            "checked_at": iso.string(from: Date()),
            "domains": domains.prefix(5).map { state -> [String: Any] in
                ["domain": state.domain, "status": state.status.rawValue,
                 "attempted_at": iso.string(from: state.attemptedAt),
                 "acknowledged_end": state.acknowledgedEnd.map { iso.string(from: $0) } ?? NSNull()]
            },
        ]
    }

    // MARK: a conversational turn

    /// ADR 0018 · one user action is one turn, even when the turn pauses for the phone. A
    /// `tool.request` runs here through `PhoneToolRunner`, and the same Idempotency-Key goes
    /// back with the result until the server answers with a frame.
    func turn(_ text: String, day: UserDay, store: DataStore,
              imageDataURL: String? = nil, surface: String = "panel",
              history: [[String: String]] = [], conversationID: UUID? = nil, turnID: UUID = UUID(),
              prepareData: Bool = true, onCoachHandoff: (() -> Void)? = nil) async -> PanelWidget? {
        #if DEBUG
        let latencyStarted = Date()
        os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
            .notice("NB latency · turn start")
        #endif
        // The draft outlives the turn that made it: "确认，记下来" is a new turn, and the panel
        // is THINKING by the time the phone runs panel.confirm. A draft expires with its frame.
        if let draft = mealDraft, Date().timeIntervalSince(draft.at) > Self.draftLifetime { mealDraft = nil }
        activeTurnID = turnID
        coachHandoffReceived = false
        let phoneScope = PhoneToolRunner.shared.beginTurn(turnID)
        thinking = true
        thoughts = []
        reading = nil
        lastError = nil
        lastErrorCode = nil
        lastRetryAfter = nil
        defer {
            PhoneToolRunner.shared.finishTurn(turnID)
            if activeTurnID == turnID {
                thinking = false
                reading = nil
                activeTurnID = nil
            }
        }

        #if DEBUG && targetEnvironment(simulator)
        if Band.allowsSeed, surface == "panel",
           let fixture = ProcessInfo.processInfo.environment["NB_DEBUG_COACH_HANDOFF"],
           ["1", "failure"].contains(fixture) {
            receiveCoachHandoff(surface: surface, onHandoff: onCoachHandoff)
            // The event and the persisted frame both identify the handoff on a replay.
            receiveCoachHandoff(surface: surface, onHandoff: onCoachHandoff)
            thoughts = [Thought(text: "Continuing your conversation", at: Date())]
            try? await Task.sleep(for: .milliseconds(1_200))
            if fixture == "failure" {
                lastError = "I couldn't complete this reply. Please try again."
                return nil
            }
            return widget(from: ["type": "text", "title": "AI COACH", "sentence": "",
                                 "data": ["headline": "AI COACH", "sub": "Tell me what happened. I'm listening."],
                                 "locale": "en-US", "target": "profile", "handoff": "chat"])
        }
        #endif

        let dayKey = Self.dayFormatter.string(from: day.start)
        guard ConsentStore.shared.granted, let requestOwner = await SupabaseClient.shared.currentUserId else {
            guard activeTurnID == turnID else { return nil }
            lastError = L("Please sign in and allow access to your data.")
            return nil
        }
        guard phoneScope.session.owner == requestOwner else { return nil }
        AISession.shared.settleIfDue()
        // ADR 0022 · a replay of the day's set asks for the stored result, not for fresh data.
        var freshness = surface == "plan" && prepareData
            ? await prepareFreshness(day: day, owner: requestOwner)
            : freshnessSnapshot(owner: requestOwner)
        freshness["device"] = PhoneToolRunner.shared.deviceState(store: store)
        guard activeTurnID == turnID, !Task.isCancelled, ConsentStore.shared.granted,
              SupabaseClient.currentRequestSessionSnapshot() == phoneScope.session else { return nil }

        var payload: [String: Any] = [
            "text": text, "dayKey": dayKey, "locale": AppLanguage.locale,
            "surface": surface, "freshness": freshness,
            "session_id": AISession.shared.idForTurn().uuidString.lowercased(),
        ]
        if surface == "chat" { payload["history"] = history }
        if let conversationID { payload["conversation_id"] = conversationID.uuidString }
        if let imageDataURL { payload["image"] = imageDataURL }

        // The same body every time: the server hashes text + conversation into the lease.
        var toolResult: [String: Any]?
        for hop in 0...Self.maxResumes {
            var attempt = payload
            if let toolResult { attempt["tool_result"] = toolResult }
            let outcome = await stream(attempt, owner: requestOwner, turnID: turnID, day: day,
                                       surface: surface, text: text, onCoachHandoff: onCoachHandoff)
            guard activeTurnID == turnID else { return nil }
            switch outcome {
            case .frame(let widget):
                #if DEBUG
                os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                    .notice("NB latency · turn done ms=\(Int(Date().timeIntervalSince(latencyStarted) * 1_000), privacy: .public) hops=\(hop, privacy: .public)")
                #endif
                return widget
            case .suspended(let request):
                guard hop < Self.maxResumes else {
                    lastErrorCode = "RESUME_BUDGET"
                    lastError = L("Could not complete that request. Please try again.")
                    return surface == "chat" || coachHandoffReceived ? nil : offlineFrame(text)
                }
                reading = request.name
                // #27 · the advice turn is the one turn the user never asked for: it runs
                // itself when the day opens and after a sync. The server no longer offers it
                // phone tools; this is the second lock, because an effect on the band that
                // nobody requested must not survive one hole on one side.
                let result = surface == "plan"
                    ? PhoneToolRunner.Result.fail("UNSUPPORTED",
                        L("Suggestions cannot change the band or the app. Say what to do; the user decides."))
                    : await PhoneToolRunner.shared.run(request, scope: phoneScope, store: store)
                guard activeTurnID == turnID, ConsentStore.shared.granted,
                      SupabaseClient.currentRequestSessionSnapshot() == phoneScope.session else { return nil }
                toolResult = result.payload(callID: request.callID)
                thoughts = []
            case .failed(let widget):
                return widget
            }
        }
        return surface == "chat" || coachHandoffReceived ? nil : offlineFrame(text)
    }

    static let maxResumes = 3

    private enum Outcome {
        case frame(PanelWidget?)
        case suspended(PhoneToolRunner.Request)
        case failed(PanelWidget?)
    }

    private func stream(_ payload: [String: Any], owner requestOwner: String, turnID: UUID,
                        day: UserDay, surface: String, text: String,
                        onCoachHandoff: (() -> Void)?) async -> Outcome {
        #if DEBUG
        let latencyStarted = Date()
        var loggedFirstEvent = false
        var loggedFirstThought = false
        var loggedFirstTool = false
        #endif
        func handOffToCoach() {
            receiveCoachHandoff(surface: surface, onHandoff: onCoachHandoff)
        }
        do {
            // ⚠️ `turn` streams. It had been called as though it returned one JSON object,
            // so the parse threw on the very first `event:` line and every server turn —
            // including the ones the server logged as OK — fell through to the offline
            // frame. The DEBUG path masked it by answering in its place.
            var frame: [String: Any]?
            var responseFailed = false
            var request: PhoneToolRunner.Request?
            for try await chunk in SupabaseClient.shared.streamFunction("turn", payload: payload, expectedOwner: requestOwner, requestID: turnID) {
                guard activeTurnID == turnID, !Task.isCancelled, ConsentStore.shared.granted,
                      SupabaseClient.currentUserIdSnapshot() == requestOwner else { return .failed(nil) }
                let parts = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let data = parts[1].data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                #if DEBUG
                let event = String(parts[0])
                let elapsedMs = Int(Date().timeIntervalSince(latencyStarted) * 1_000)
                if !loggedFirstEvent {
                    loggedFirstEvent = true
                    os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                        .notice("NB latency · turn first_event=\(event, privacy: .public) ms=\(elapsedMs, privacy: .public)")
                }
                if event == "thought", !loggedFirstThought {
                    loggedFirstThought = true
                    os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                        .notice("NB latency · turn first_thought ms=\(elapsedMs, privacy: .public)")
                }
                if event == "tool", !loggedFirstTool {
                    loggedFirstTool = true
                    os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                        .notice("NB latency · turn first_tool ms=\(elapsedMs, privacy: .public)")
                }
                #endif

                switch String(parts[0]) {
                case "coach.handoff":
                    handOffToCoach()
                case "tool":
                    // 07 · 16 · she names what she is reading while she reads it.
                    if let name = obj["name"] as? String { reading = name }
                case "thought":
                    // 07 · 16 · 02 · one line of her reasoning, whole, in the moment it was.
                    if let t = obj["text"] as? String, !t.isEmpty {
                        thoughts = Array((thoughts + [Thought(text: t, at: Date())]).suffix(Self.thoughtsKept))
                    }
                case "tool.request":
                    // ADR 0018 · the turn is pausing for the phone.
                    request = PhoneToolRunner.Request(obj)
                case "screen.render":
                    frame = obj["envelope"] as? [String: Any]
                    if frame?["handoff"] as? String == "chat" { handOffToCoach() }
                    #if DEBUG
                    os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                        .notice("NB latency · turn render ms=\(elapsedMs, privacy: .public)")
                    #endif
                case "error":
                    responseFailed = true
                    // A degraded frame is still a frame — S4's absence law, not a failure.
                    if let fb = obj["fallback_frame"] as? [String: Any], frame == nil { frame = fb }
                    if frame?["handoff"] as? String == "chat" { handOffToCoach() }
                    lastErrorCode = obj["code"] as? String
                    let fallback = obj["fallback_frame"] as? [String: Any]
                    let coachError = (fallback?["data"] as? [String: Any])?["sub"] as? String
                    lastError = ((surface == "chat" || coachHandoffReceived) ? coachError : nil)
                        ?? fallback?["sentence"] as? String
                        ?? obj["reason"] as? String
                        ?? L("Could not complete that request. Please try again.")
                default:
                    break
                }
            }
            guard activeTurnID == turnID else { return .failed(nil) }
            reading = nil
            if let request, frame == nil, !responseFailed { return .suspended(request) }
            if responseFailed && (surface == "chat" || coachHandoffReceived || lastErrorCode == "RATE_LIMITED") { return .failed(nil) }
            if let frame {
                // ⚠️ A frame this build cannot decode — a type the server learned after the
                // app shipped, or a malformed envelope — used to come back as nil, and Home
                // then left the panel on THINKING forever. Every envelope carries a title
                // and a sentence; print those rather than hang.
                let w = widget(from: frame) ?? undecodedFrame(frame)
                if !responseFailed, let w, let fields = frame["data"] as? [String: Any],
                   let draftID = fields["draft_id"] as? String, UUID(uuidString: draftID) != nil,
                   let macros = fields["macros"] as? [String: Any] {
                    var output = fields
                    output["protein_g"] = macros["p"]
                    output["carb_g"] = macros["c"]
                    output["fat_g"] = macros["f"]
                    mealDraft = MealDraft(frameID: w.id, mealID: UUID(), day: day, owner: requestOwner, output: output)
                }
                #if DEBUG
                os.Logger(subsystem: "com.nextbody.hoop", category: "turn")
                    .notice("NB turn · type=\((frame["type"] as? String) ?? "?", privacy: .public) title=\((frame["title"] as? String) ?? "", privacy: .public) sentence=\((frame["sentence"] as? String) ?? "", privacy: .public) decoded=\(w != nil, privacy: .public)")
                #endif
                return responseFailed ? .failed(w) : .frame(w)
            }
        } catch {
            guard activeTurnID == turnID else { return .failed(nil) }
            reading = nil
            if case SupabaseClient.Failure.http(let status, let body) = error {
                let fields = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
                lastErrorCode = fields?["error"] as? String
                lastRetryAfter = fields?["retry_after"] as? Int
                // ADR 0018 · the server still holds a suspended turn for this key: run its tool.
                if status == 409, lastErrorCode == "TURN_SUSPENDED",
                   let raw = fields?["tool_request"] as? [String: Any], let request = PhoneToolRunner.Request(raw) {
                    return .suspended(request)
                }
                if status == 402 || lastErrorCode == "SUBSCRIPTION_REQUIRED" {
                    lastErrorCode = "SUBSCRIPTION_REQUIRED"
                    lastError = L("NextBody Pro is required for AI.")
                    BillingStore.shared.handleServerDenial(
                        introClaimed: fields?["intro_claimed"] as? Bool,
                        presentCard: surface != "plan")
                    return .failed(nil)
                }
                if status == 429 {
                    lastErrorCode = "RATE_LIMITED"
                    lastError = (fields?["fallback_frame"] as? [String: Any])?["sentence"] as? String
                        ?? L("Your AI allowance is unavailable. Please try again later.")
                    return .failed(nil)
                }
                // A rejected photo is a photo problem, not a mystery. Saying so is the
                // difference between retrying forever and picking a smaller picture.
                if status == 413 || lastErrorCode == "IMAGE_TOO_LARGE" {
                    lastError = L("That photo was too large to send. Try a smaller one.")
                } else {
                    lastError = L("Could not complete that request. Please try again.")
                }
            } else {
                lastError = error.localizedDescription
            }
        }
        return .failed(surface == "chat" || coachHandoffReceived ? nil : offlineFrame(text))
    }

    private struct MealDraft {
        let frameID: UUID
        let mealID: UUID
        let day: UserDay
        let owner: String
        let output: [String: Any]
        var at = Date()
    }
    private var mealDraft: MealDraft?
    /// 07 · a frame lives 20 minutes; so does the draft it carries.
    static let draftLifetime: TimeInterval = 20 * 60
    /// The frame whose food draft is still waiting for CONFIRM, if any — for a voice confirm.
    var pendingMealDraftFrameID: UUID? {
        guard let draft = mealDraft, Date().timeIntervalSince(draft.at) <= Self.draftLifetime,
              draft.owner == SupabaseClient.currentUserIdSnapshot() else { return nil }
        return draft.frameID
    }
    var pendingMealDraftLabel: String? {
        guard pendingMealDraftFrameID != nil, let output = mealDraft?.output else { return nil }
        let kcal = (output["kcal"] as? Double) ?? (output["kcal"] as? Int).map(Double.init) ?? 0
        return "\(output["name"] as? String ?? "") · \(Fmt.kcal(kcal)) KCAL"
    }

    func canConfirmMeal(frameID: UUID) -> Bool {
        mealDraft?.frameID == frameID
            && mealDraft?.owner == SupabaseClient.currentUserIdSnapshot()
    }

    /// Confirmation persists exactly the model-selected tool's draft, without another AI call.
    func confirmMeal(frameID: UUID, slot: MealEntry.Slot, into store: DataStore) -> PanelWidget? {
        guard let draft = mealDraft, canConfirmMeal(frameID: frameID), ConsentStore.shared.granted else { return nil }
        do {
            let logged = try logMealDraft(draft.output, slot: slot, day: draft.day, owner: draft.owner, mealID: draft.mealID, into: store)
            mealDraft = nil
            return loggedFrame(name: logged.name, kcal: logged.kcal, store: store)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    struct LoggedMeal { let id: UUID; let name: String; let kcal: Double }

    /// ADR 0018 · the one write path for a meal draft: the CONFIRM tap on a food frame and the
    /// `meal.log` phone tool both land here. The draft is the server's estimate; nothing is
    /// re-estimated on the way in.
    @discardableResult
    func logMealDraft(_ output: [String: Any], slot: MealEntry.Slot, day: UserDay, owner: String? = nil,
                      mealID: UUID = UUID(), into store: DataStore) throws -> LoggedMeal {
        guard let owner = owner ?? SupabaseClient.currentUserIdSnapshot() else {
            throw LocalDataStore.Failure.database(L("Please sign in and allow access to your data."))
        }
        let submitted = try MealQueue.shared.confirmDraft(output, mealID: mealID, day: day,
            slot: slot, owner: owner, into: store)
        return LoggedMeal(id: submitted.id, name: submitted.fields["name"] as? String ?? "",
                          kcal: numberOf(submitted.fields["kcal"]) ?? 0)
    }

    /// 05 · speech in, one sentence out. The clip goes to `asr` and is deleted the moment the
    /// transcript is back; nothing about the audio outlives the turn.
    ///
    /// `NO_SPEECH` is not an error to apologise for — the board's word for it is
    /// 「DIDN'T CATCH THAT」 and the dock simply returns to idle. Silence and a refusal look the
    /// same from here on purpose: both mean there is nothing to say yet.
    /// ⚠️ Silence and a failure are not the same answer. The first version folded a 401, a
    /// 503 and a dropped upload into `nil`, and the dock told her NOTHING HEARD for every one
    /// of them — which sends her back to say it again louder, when the microphone was never
    /// the problem. Only the server's own NO_SPEECH is silence; the rest is `.failed`.
    enum Transcript: Equatable {
        case text(String)
        case silence
        case failed(String)
    }

    func beginStreamingTranscription(operationID: UUID = UUID()) async -> ASRStreamingSession? {
        try? await SupabaseClient.shared.asrStreamingSession(requestID: operationID)
    }

    func transcribe(_ clip: URL, stream: ASRStreamingSession?, operationID: UUID = UUID()) async -> Transcript {
        guard let stream else { return await transcribe(clip, operationID: operationID) }
        #if DEBUG
        let latencyStarted = Date()
        #endif
        switch await stream.finish() {
        case .text(let text):
            try? FileManager.default.removeItem(at: clip)
            #if DEBUG
            let elapsedMs = Int(Date().timeIntervalSince(latencyStarted) * 1_000)
            os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                .notice("NB latency · asr stream response ms=\(elapsedMs, privacy: .public)")
            #endif
            return .text(text)
        case .silence:
            try? FileManager.default.removeItem(at: clip)
            return .silence
        case .failed(let reason):
            #if DEBUG
            os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                .error("NB latency · asr stream fallback reason=\(reason, privacy: .public)")
            #endif
            return await transcribe(clip, operationID: operationID)
        }
    }

    func transcribe(_ clip: URL, operationID: UUID = UUID()) async -> Transcript {
        #if DEBUG
        let latencyStarted = Date()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: clip.path)[.size] as? NSNumber)?.intValue ?? 0
        os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
            .notice("NB latency · asr start bytes=\(bytes, privacy: .public)")
        #endif
        defer { try? FileManager.default.removeItem(at: clip) }
        do {
            let out = try await SupabaseClient.shared.uploadFunction(
                "asr", fileURL: clip, field: "audio", filename: "clip.wav", mime: "audio/wav", requestID: operationID)
            #if DEBUG
            let elapsedMs = Int(Date().timeIntervalSince(latencyStarted) * 1_000)
            os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                .notice("NB latency · asr response ms=\(elapsedMs, privacy: .public)")
            #endif
            if let err = out["error"] as? String {
                #if DEBUG
                NSLog("NB asr · \(err)")
                #endif
                return err == "NO_SPEECH" ? .silence : .failed(err)
            }
            let text = (out["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? .silence : .text(text)
        } catch {
            if case SupabaseClient.Failure.http(let status, let body) = error {
                let fields = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
                if status == 402 || fields?["error"] as? String == "SUBSCRIPTION_REQUIRED" {
                    lastErrorCode = "SUBSCRIPTION_REQUIRED"
                    lastError = L("NextBody Pro is required for AI.")
                    BillingStore.shared.handleServerDenial(
                        introClaimed: fields?["intro_claimed"] as? Bool,
                        presentCard: true)
                } else if status == 429 {
                    lastErrorCode = "RATE_LIMITED"
                    lastError = (fields?["fallback_frame"] as? [String: Any])?["sentence"] as? String
                        ?? L("Your AI allowance is unavailable. Please try again later.")
                } else {
                    lastError = L("Could not complete that request. Please try again.")
                }
            } else {
                lastError = L("Could not complete that request. Please try again.")
            }
            #if DEBUG
            let elapsedMs = Int(Date().timeIntervalSince(latencyStarted) * 1_000)
            os.Logger(subsystem: "com.nextbody.hoop", category: "ai-latency")
                .error("NB latency · asr failed ms=\(elapsedMs, privacy: .public)")
            NSLog("NB asr · upload failed: \(error)")
            #endif
            return .failed(lastError ?? error.localizedDescription)
        }
    }

    // MARK: envelope decoding

    func widget(from env: [String: Any]) -> PanelWidget? {
        guard let typeRaw = env["type"] as? String,
              let type = PanelType(rawValue: typeRaw),
              let title = env["title"] as? String,
              let sentence = env["sentence"] as? String else { return nil }
        // ⚠️ The two locks that kept sleep off the screen are both gone (2026-09-03, the
        // user's own ruling in front of board 07). A sleep frame draws like any other.

        // F0 rule 06 · no target, no screen. The server states this on the Envelope schema and
        // enforces it on its own fixed frames; enforcing it here too means a malformed frame is
        // dropped rather than drawn with a destination this side invented.
        guard let targetRaw = env["target"] as? String,
              let target = Destination(envelopeTarget: targetRaw) else { return nil }

        var accent: Color?
        if let hex = env["accent"] as? String, hex.hasPrefix("#"),
           let v = UInt32(hex.dropFirst(), radix: 16) { accent = Color(hex: v) }

        let data = env["data"] as? [String: Any] ?? [:]
        // 07 · 09 · C · rule 2 · data.label 压过 title, on the four types the board names.
        let label = (data["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let titled = [.metric, .ring, .cells, .table].contains(type) ? (label ?? title) : title
        // 13 col 01 · a curve that arrives with a split is night then day: violet, then lime.
        let split = data["split"] as? Int

        // 07 · rule 6 and 07 · 20 · the two types that carry their own skeleton.
        var headline: HeadlineBlock?
        if type == .text, let h = (data["headline"] as? String), !h.isEmpty {
            headline = HeadlineBlock(eyebrow: (data["eyebrow"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                     headline: String(h.prefix(14)),
                                     sub: (data["sub"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        var plate: PlateBlock?
        if type == .food, let name = (data["name"] as? String), !name.isEmpty {
            let m = data["macros"] as? [String: Any] ?? [:]
            let num = { (any: Any?) -> Double? in (any as? Double) ?? (any as? Int).map(Double.init) }
            plate = PlateBlock(name: name,
                               portion: (data["portion"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                               kcal: num(data["kcal"]),
                               protein: num(m["p"] ?? data["protein_g"]),
                               carb: num(m["c"] ?? data["carb_g"]),
                               fat: num(m["f"] ?? data["fat_g"]),
                               pctOfBudget: (data["pct_of_budget"] as? Int)
                                 ?? (data["pct_of_budget"] as? Double).map { Int($0) })
        }

        return PanelWidget(
            type: type,
            title: String(titled.prefix(18)),
            tag: (env["tag"] as? String).flatMap(PanelTag.init(rawValue:)),
            sentence: String(sentence.prefix(48)),
            footer: (env["footer"] as? String).map { String($0.prefix(42)) },
            action: (env["action"] as? String).map { String($0.prefix(32)) },
            hero: (data["hero"]).map { "\($0)" }.flatMap { $0.isEmpty ? nil : $0 },
            accentOverride: accent ?? (split != nil ? NB.violet1 : nil),
            curveSplit: split,
            curveSecondary: split != nil ? NB.lime1 : nil,
            curveMark: (data["mark"] as? Double) ?? (data["mark"] as? Int).map(Double.init),
            curveMarks: (data["marks"] as? [Int]) ?? [],
            targetOverride: target,
            data: Self.decodeData(data, type: type),
            headline: headline,
            plate: plate,
            ttlMinutes: (env["ttl_min"] as? Int) ?? 20,
            priority: (env["priority"] as? String) == "alert" ? .alert : .normal,
            envelopeData: try? JSONSerialization.data(withJSONObject: env))
    }

    /// ⚠️ Tolerant on purpose, in both directions. The contract's shape is pairs —
    /// `bins[[label, v]]`, `series[[t, v]]` — and a model reaching for clarity sends
    /// `points: [{label, value}]` instead. Insisting on one form meant a frame whose
    /// sentence and footer were perfectly correct drew an empty panel with a 0 in it, which
    /// is a worse outcome than reading both. The tool schema now states the contract; this
    /// reads whichever arrives.
    private static func numbers(_ any: Any?) -> [Double] {
        guard let rows = any as? [Any] else { return [] }
        return rows.compactMap { row in
            if let n = row as? Double { return n }
            if let n = row as? Int { return Double(n) }
            if let pair = row as? [Any] { return (pair.last as? Double) ?? (pair.last as? Int).map(Double.init) }
            if let obj = row as? [String: Any] {
                for k in ["value", "v", "y", "kcal", "load", "level", "minutes"] {
                    if let n = obj[k] as? Double { return n }
                    if let n = obj[k] as? Int { return Double(n) }
                }
            }
            return nil
        }
    }

    private static func labelled(_ any: Any?) -> [(String, Double)] {
        guard let rows = any as? [Any] else { return [] }
        return rows.enumerated().compactMap { i, row in
            if let pair = row as? [Any], pair.count >= 2 {
                let v = (pair[1] as? Double) ?? (pair[1] as? Int).map(Double.init)
                return v.map { ("\(pair[0])", $0) }
            }
            if let obj = row as? [String: Any] {
                let label = (obj["label"] as? String) ?? (obj["dayKey"] as? String)
                    ?? (obj["slot"] as? String) ?? (obj["name"] as? String) ?? "\(i + 1)"
                for k in ["value", "v", "y", "kcal", "load", "minutes"] {
                    if let n = obj[k] as? Double { return (label, n) }
                    if let n = obj[k] as? Int { return (label, Double(n)) }
                }
            }
            return nil
        }
    }

    static func decodeData(_ d: [String: Any], type: PanelType) -> PanelData {
        switch type.renderer {
        case .curve:
            let s = numbers(d["series"] ?? d["points"] ?? d["samples"])
            return .series(s)
        case .pair, .dual:
            // The contract's dual shape is a{label,series} b{label,series}; the server also
            // sends hi/lo. Read either.
            let unwrap = { (x: Any?) -> [Double] in numbers((x as? [String: Any])?["series"] ?? x) }
            return .pair(hi: unwrap(d["hi"] ?? d["a"]), lo: unwrap(d["lo"] ?? d["b"]))
        case .column:
            return .bins(labelled(d["bins"] ?? d["points"] ?? d["days"] ?? d["series"]))
        case .arc:
            let v = ["value", "level", "current", "load"].compactMap { key -> Double? in
                (d[key] as? Double) ?? (d[key] as? Int).map(Double.init)
            }.first ?? 0
            let goal = ["goal", "target", "max"].compactMap { key -> Double? in
                (d[key] as? Double) ?? (d[key] as? Int).map(Double.init)
            }.first ?? 100
            // 09 · gauge 额外吃 zones · [[from, to, name], …]. Without them a gauge is a ring.
            if type == .gauge, let zs = d["zones"] as? [[Any]] {
                let zones = zs.compactMap { z -> (Double, Double, String)? in
                    guard z.count >= 3,
                          let lo = (z[0] as? Double) ?? (z[0] as? Int).map(Double.init),
                          let hi = (z[1] as? Double) ?? (z[1] as? Int).map(Double.init) else { return nil }
                    return (lo, hi, "\(z[2])")
                }
                if !zones.isEmpty { return .gauge(value: v, zones: zones) }
            }
            return .ring(value: v, goal: goal, unit: (d["unit"] as? String) ?? "")
        case .stack:
            let source = d["parts"] ?? d["macros"] ?? d["rows"]
            // 10 · the night's three segments are the violet family with grey for awake;
            // 22 / 23 · macros and energy cycle the domain colours. The label decides,
            // because the server may send the three in any order.
            let sleepTint: [String: Color] = ["DEEP": NB.violet1,
                                              "LIGHT": NB.violet1.opacity(0.55),
                                              "AWAKE": NB.white.opacity(0.45)]
            let parts = labelled(source).enumerated().map { i, p in
                (p.0, p.1, type == .split
                    ? (sleepTint[p.0.uppercased()] ?? NB.violet1.opacity(0.35))
                    : [NB.cyan1, NB.violet1, NB.optimal2, NB.ember1][i % 4])
            }
            return .parts(parts)
        case .grid:
            let cells = (d["cells"] as? [[Int]])?.flatMap { $0 }
                ?? (d["cells"] as? [Int])
                ?? numbers(d["grid"] ?? d["points"]).map { Int($0) }
            return .cells(rows: (d["rows"] as? Int) ?? 7, cols: (d["cols"] as? Int) ?? 12,
                          values: cells, levels: (d["scale"] as? Int) ?? 4)
        case .strip:
            let stages = numbers(d["minutes"] ?? d["stages"] ?? d["zones"])
            return .strip(stages.enumerated().map { ($0.offset, $0.element) })
        case .lanes:
            // 12 · lanes arrive as [[lane, minutes], …]; a flat [lane, min, lane, min] is
            // read too, because that is the shape a model reaches for when it invents one.
            var runs: [(Int, Double)] = []
            if let rows = d["lanes"] as? [[Any]] {
                runs = rows.compactMap { r in
                    guard r.count >= 2,
                          let l = (r[0] as? Int) ?? (r[0] as? Double).map(Int.init),
                          let m = (r[1] as? Double) ?? (r[1] as? Int).map(Double.init) else { return nil }
                    return (l, m)
                }
            } else {
                let flat = numbers(d["lanes"] ?? d["stages"] ?? d["minutes"])
                runs = stride(from: 0, to: max(0, flat.count - 1), by: 2).map { (Int(flat[$0]), flat[$0 + 1]) }
            }
            return .lanes(runs: runs, from: (d["from"] as? String) ?? "", to: (d["to"] as? String) ?? "")
        case .columns:
            let mins = numbers(d["minutes"] ?? d["zones"] ?? d["stages"])
            return .zones(mins.isEmpty ? [] : mins)
        case .trace:
            return .trace(samples: numbers(d["samples"] ?? d["series"]),
                          hz: (d["hz"] as? Double) ?? 125)
        case .rows:
            // ADR 0018 · a plan frame's tasks read as rows: title, then the one-line how.
            let raw = (d["rows"] ?? d["items"] ?? d["logged"] ?? d["events"] ?? d["points"] ?? (type == .plan ? d["tasks"] : nil))
            let rows = (raw as? [[String: Any]])?.map { r -> PanelData.RowItem in
                let label = (r["label"] as? String) ?? (r["name"] as? String)
                    ?? (r["slot"] as? String) ?? (r["dayKey"] as? String) ?? ""
                let value = r["value"] ?? r["kcal"] ?? r["v"] ?? r["minutes"] ?? r["sub"] ?? ""
                return PanelData.RowItem(label: label, value: "\(value)",
                                         spark: numbers(r["spark"]).isEmpty ? nil : numbers(r["spark"]))
            } ?? []
            return .rows(rows)
        case .meter:
            // A sub-score with no full value is scored out of 100 — every score in the
            // contract is. A part with no number at all is dropped, not zeroed.
            let parts = ((d["parts"] as? [[String: Any]]) ?? []).compactMap { p -> (String, Double, Double)? in
                guard let v = (p["value"] as? Double) ?? (p["value"] as? Int).map(Double.init) else { return nil }
                let mx = (p["max"] as? Double) ?? (p["max"] as? Int).map(Double.init) ?? 100
                return ((p["label"] as? String) ?? "", v, mx)
            }
            return .meter(parts: parts)
        case .scatter:
            let pts = ((d["points"] as? [[Any]]) ?? []).compactMap { pair -> CGPoint? in
                guard pair.count >= 2,
                      let x = (pair[0] as? Double) ?? (pair[0] as? Int).map(Double.init),
                      let y = (pair[1] as? Double) ?? (pair[1] as? Int).map(Double.init) else { return nil }
                return CGPoint(x: x, y: y)
            }
            let lo = (d["lo"] as? Double) ?? (d["lo"] as? Int).map(Double.init) ?? 0
            let hi = (d["hi"] as? Double) ?? (d["hi"] as? Int).map(Double.init) ?? 0
            let stats = ((d["stats"] as? [[String: Any]]) ?? []).map {
                (($0["label"] as? String) ?? "", "\($0["value"] ?? "")")
            }
            return .scatter(points: pts, lo: lo, hi: hi, stats: stats)
        case .matrix:
            let cells = (d["cells"] as? [[Int]])?.flatMap { $0 } ?? (d["cells"] as? [Int]) ?? []
            let labels = (d["rowLabels"] as? [String]) ?? []
            return .matrix(rows: (d["rows"] as? Int) ?? labels.count,
                           cols: (d["cols"] as? Int) ?? 7, values: cells, rowLabels: labels)
        case .verdict:
            return .verdict(word: (d["word"] as? String) ?? "",
                            options: (d["options"] as? [String]) ?? [],
                            confidence: (d["confidence"] as? Int) ?? 0,
                            steps: (d["steps"] as? Int) ?? 3)
        case .number:
            return .none
        }
    }

    // MARK: honest failure

    /// The envelope arrived and said something; only its shape was unknown to this build.
    private func undecodedFrame(_ env: [String: Any]) -> PanelWidget? {
        let sentence = (env["sentence"] as? String) ?? ""
        let title = (env["title"] as? String) ?? ""
        guard !sentence.isEmpty || !title.isEmpty else { return nil }
        #if DEBUG
        os.Logger(subsystem: "com.nextbody.hoop", category: "turn")
            .error("NB turn · undecodable type=\((env["type"] as? String) ?? "?", privacy: .public)")
        #endif
        return PanelWidget(type: .text, title: title.isEmpty ? L("AI COACH") : title, tag: nil,
                           sentence: sentence,
                           footer: (env["footer"] as? String).map { String($0.prefix(42)) },
                           action: nil,
                           targetOverride: (env["target"] as? String).flatMap(Destination.init(envelopeTarget:)),
                           data: .none,
                           headline: ((env["data"] as? [String: Any])?["headline"] as? String).map {
                               HeadlineBlock(headline: String($0.prefix(14)))
                           })
    }

    /// A failed turn has not saved a meal or scheduled another model call.
    private func offlineFrame(_ text: String) -> PanelWidget {
        PanelWidget(type: .text, title: L("OFFLINE"), tag: .fuel,
                    sentence: L("Could not complete that request. Please try again."),
                    footer: String(text.prefix(42)), action: nil, data: .none)
    }

    private func loggedFrame(name: String, kcal: Double, store: DataStore) -> PanelWidget {
        let left = store.today.nextMeal
        return PanelWidget(
            type: .meal, title: L("LOGGED"), tag: .fuel,
            sentence: L("%@ KCAL. %@ LEFT.", Fmt.kcal(kcal), Fmt.kcal(left)),
            footer: String(name.prefix(42)), action: L("OPEN FUEL"),
            data: .rows([.init(label: name, value: Fmt.kcal(kcal))]))
    }

    private func numberOf(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
