import Foundation
import SwiftUI

/// In-app language. English is the default and the source of truth.
///
/// Stored as `en` / `zh-Hans` under `nb.language`. Older builds wrote the display names
/// `English` / `简体中文`; those values are still read and migrated on first access.
///
/// Views must observe `AppLanguage.shared` (or sit under a `.id(locale)` rebuild) so a
/// change in Settings redraws every screen. A static `isEnglish` read alone will not.
enum AppLocale: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// BCP-47 sent to Edge Functions and written to `profiles.locale`.
    var serverLocale: String {
        switch self {
        case .english: return "en-US"
        case .simplifiedChinese: return "zh-CN"
        }
    }

    var swiftLocale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .simplifiedChinese: return Locale(identifier: "zh_Hans_CN")
        }
    }

    /// Language names stay in their own language in the picker.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// Short label shown on the Profile row.
    var rowLabel: String {
        switch self {
        case .english: return "ENGLISH"
        case .simplifiedChinese: return "简体中文"
        }
    }

    var usesCJKFont: Bool {
        self == .simplifiedChinese
    }

    static func parse(_ raw: String?) -> AppLocale {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "zh-Hans", "zh-CN", "zh", "简体中文": return .simplifiedChinese
        case "en", "en-US", "English": return .english
        default:
            return value.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
        }
    }
}

final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    static let key = "nb.language"

    @Published private(set) var locale: AppLocale

    var isEnglish: Bool { locale == .english }
    var serverLocale: String { locale.serverLocale }
    var usesCJKFont: Bool { locale.usesCJKFont }
    var swiftLocale: Locale { locale.swiftLocale }

    /// Compatibility for existing call sites that read the static enum.
    static var isEnglish: Bool { shared.isEnglish }
    static var locale: String { shared.serverLocale }

    static func sync() { shared.syncProfile() }

    private init() {
        locale = Self.resolveLaunchLocale()
        persist(locale)
    }

    func set(_ next: AppLocale) {
        guard next != locale else {
            syncProfile()
            return
        }
        locale = next
        persist(next)
        objectWillChange.send()
        syncProfile()
    }

    /// The profile row is the server's fallback for a client that sends no locale, and the
    /// only copy a second device would see. Written when the sheet changes, never on launch.
    func syncProfile() {
        Task {
            guard let uid = await SupabaseClient.shared.currentUserId else { return }
            _ = try? await SupabaseClient.shared.patchWhere(
                "profiles", column: "user_id", equals: uid, row: ["locale": serverLocale]
            )
        }
    }

    private func persist(_ value: AppLocale) {
        UserDefaults.standard.set(value.rawValue, forKey: Self.key)
    }

    private static func resolveLaunchLocale() -> AppLocale {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["NB_DEBUG_LANG"] {
            return AppLocale.parse(forced)
        }
        #endif
        return AppLocale.parse(UserDefaults.standard.string(forKey: key))
    }
}
