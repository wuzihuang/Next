import CryptoKit
import Foundation

/// 补屏 A · MHMDA consent — the seventh onboarding screen, and the switch in Settings › Data.
///
/// The board's four rules that this file carries:
///  01 the screen comes before HealthKit's dialog and before the first readOriginData();
///     pairing is not permission.
///  05 a decision is stored with consent_version · granted_at · text_sha256 · locale.
///  06 withdrawing is not deleting. Withdraw stops collection; /v1/turn answers 403; the
///     panel degrades to NOT COLLECTING in place. Deleting is a separate tap on the same screen.
///  edge 1 declining is not a dead end: onboarding can finish, the band stays paired, and
///     nothing is ever read — 「—— 是沉默」 taken to its limit.
///
/// Decisions are appended, never edited: each row is one answer, and the newest wins. That
/// is also what a plaintiff reads first.
@MainActor
final class ConsentStore: ObservableObject {
    static let shared = ConsentStore()
    static let version = "1.0.0"
    static let locale = "en-US"

    enum Choice: String { case granted, declined, withdrawn }

    @Published private(set) var choice: Choice?
    var granted: Bool { choice == .granted }
    /// True once the screen has been answered at all — an account that predates the screen
    /// has nil here and is shown it as a delta (edge 3).
    var decided: Bool { choice != nil }

    private static let key = "nb.consent"
    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.key)
        if raw?["version"] as? String == Self.version, let c = raw?["choice"] as? String {
            choice = Choice(rawValue: c)
        }
    }

    func record(_ c: Choice, msOnScreen: Int?) async {
        choice = c
        var stored: [String: Any] = ["version": Self.version, "choice": c.rawValue,
                                     "at": ISO8601DateFormatter().string(from: Date())]
        if let msOnScreen { stored["msOnScreen"] = msOnScreen }
        UserDefaults.standard.set(stored, forKey: Self.key)
        // Rule 05 · the decision is on the phone first and on the server as soon as it can
        // be. ⚠️ The row used to be sent once, behind a `try?`, and the account that found
        // the band bug had two decisions in analytics and none in consents: a write that
        // failed for any reason — no session yet, the radio, the table not there — was gone.
        // Now it stays pending until the server has taken it.
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        await flushPending()
        switch c {
        case .granted, .declined:
            await Analytics.shared.track("CONSENT_RESULT", ["VERSION": Self.version, "CHOICE": c.rawValue.uppercased(),
                                                            "MS_ON_SCREEN": msOnScreen ?? 0])
        case .withdrawn:
            await Analytics.shared.track("CONSENT_WITHDRAWN", ["VERSION": Self.version])
        }
    }

    private static let pendingKey = "nb.consent.pendingUpload"

    /// The stored decision, sent to the server if it has not been taken yet. Called right
    /// after a decision and every time the app comes forward, so a decision made before the
    /// session existed still lands. Append-only table: the row carries the moment it was
    /// decided, not the moment it finally uploaded.
    func flushPending() async {
        guard UserDefaults.standard.bool(forKey: Self.pendingKey),
              let raw = UserDefaults.standard.dictionary(forKey: Self.key),
              let choice = raw["choice"] as? String,
              let uid = await SupabaseClient.shared.currentUserId else { return }
        var row: [String: Any] = [
            "user_id": uid,
            "consent_version": raw["version"] as? String ?? Self.version,
            "choice": choice,
            "text_sha256": Self.textSHA256,
            "locale": Self.locale,
        ]
        if let at = raw["at"] as? String { row["decided_at"] = at }
        if let ms = raw["msOnScreen"] as? Int { row["ms_on_screen"] = ms }
        do {
            _ = try await SupabaseClient.shared.insert("consents", rows: [row], returning: false)
            UserDefaults.standard.set(false, forKey: Self.pendingKey)
        } catch {
            BandLog.shared.record("insert consents", error: error)
        }
    }

    /// 11 · DELETE EVERYTHING. Rule 06 draws the line the other way round — withdrawing is
    /// not deleting — but deleting is deleting: the decision, its hash and its timestamp are
    /// the account's, and the row on the server went with the account.
    /// ⚠️ The pending flag has to go with it, or flushPending() would post this consent to
    /// whichever account signs in next on this phone.
    func purge() {
        choice = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    /// The hash of exactly what was on the screen, so a later edit to the copy is a new consent.
    static var textSHA256: String {
        let d = Data(ConsentCopy.all.joined(separator: "\n").utf8)
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}

/// The screen's words, verbatim from the board. One list, so the hash and the screen agree.
enum ConsentCopy {
    static let eyebrow = "NOTHING READ YET"
    static let title = "What HOOP collects"
    static let lede = "Nothing has been read yet — not from the band, not from Apple Health. This is the complete list, and what each item is for."

    struct Item { let name: String; let why: String }
    struct Section { let head: String; let items: [Item] }

    static let sections: [Section] = [
        Section(head: "FROM APPLE HEALTH · READ ONLY", items: [
            Item(name: "Sex, date of birth, height, weight",
                 why: "Every calorie and body-composition number is built from these four. HOOP reads them and never writes anything back to Health."),
        ]),
        Section(head: "FROM THE BAND", items: [
            Item(name: "Heart rate", why: "One reading about every five minutes, all day."),
            Item(name: "Heart rate variability, including raw beat-to-beat intervals",
                 why: "The single best signal for how recovered you are. We keep the raw intervals because the score alone cannot be recalculated later."),
            Item(name: "Steps, distance, calories and movement intensity",
                 why: "Your daily load, and the burn side of energy balance."),
            Item(name: "Sleep signals",
                 why: "Used for one thing: how much your Body Battery recharged overnight. HOOP does not show sleep stages, sleep scores or sleep duration."),
            Item(name: "Body composition — 14 measures from the band's bioimpedance sensor",
                 why: "Body fat, muscle, water, bone, protein, metabolic rate and more. Only when you start a measurement yourself. Never in the background."),
            Item(name: "Skin temperature", why: "One hidden input to Body Battery. It is never shown as a number."),
        ]),
        Section(head: "FROM YOU", items: [
            Item(name: "Meals — your words and your photos",
                 why: "Photos are read to estimate the food, kept where only you can open them, and deleted after 30 days. Location tags are removed on upload."),
            Item(name: "What you say out loud", why: "Turned into text so HOOP can answer. The recording is never stored."),
            Item(name: "How you use the app", why: "Which screens you open and what fails, so we can fix it."),
            Item(name: "Band battery and firmware version — not health data",
                 why: "So the app can tell you to charge it or update it."),
        ]),
    ]

    struct Note { let head: String; let body: String }
    static let notes: [Note] = [
        Note(head: "WHAT WE DON'T TOUCH",
             body: "The KR96 PRO hardware can also read blood pressure, blood oxygen, blood glucose and ECG. HOOP never turns those on, never stores them and never shows them. They are not in this app."),
        Note(head: "WHAT WE NEVER DO",
             body: "We never sell your health data.\nWe never give it to advertising networks or data brokers.\nWe never write anything back to Apple Health."),
        Note(head: "WHERE IT GOES",
             body: "Your phone and our servers. When you ask HOOP a question, only the numbers it needs go to the model that writes the answer, and it is not allowed to keep them or train on them."),
    ]

    static let agree = "I agree to let HOOP collect the health data listed on this screen."
    static let ifNot = "If you don't agree, HOOP reads nothing. Your band stays paired and stays silent, every screen stays blank, and you can come back to this screen from Settings."
    static let withdraw = "You can withdraw at any time in Settings › Data. Withdrawing stops collection. Deleting what we already have is a separate tap on the same screen."
    static let cta = "Continue"

    static var all: [String] {
        [eyebrow, title, lede]
        + sections.flatMap { [$0.head] + $0.items.flatMap { [$0.name, $0.why] } }
        + notes.flatMap { [$0.head, $0.body] }
        + [agree, ifNot, withdraw, cta]
    }
}
