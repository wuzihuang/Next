import Foundation

/// English-as-key lookup. The English string in source is the catalog key.
///
/// Adding a language: drop `L10n/Tables/<code>.json` mapping English → that language,
/// then add a case on `AppLocale`. Missing keys fall back to English.
///
/// Interpolation: `L("%@ LEFT", Fmt.kcal(n))` with `"%@ LEFT"` / `"还剩 %@"` in the table.
enum L10n {
    private static let tables: [AppLocale: [String: String]] = {
        var loaded: [AppLocale: [String: String]] = [:]
        if let zh = loadTable("zh-Hans") {
            loaded[.simplifiedChinese] = zh
        }
        return loaded
    }()

    static func t(_ key: String) -> String {
        lookup(key)
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        t(key, args: args)
    }

    static func t(_ key: String, args: [CVarArg]) -> String {
        let template = lookup(key)
        guard !args.isEmpty else { return template }
        return String(format: template, locale: AppLanguage.shared.swiftLocale, arguments: args)
    }

    static func hasTranslation(_ key: String, locale: AppLocale = AppLanguage.shared.locale) -> Bool {
        locale == .english || tables[locale]?[key] != nil
    }

    private static func lookup(_ key: String) -> String {
        let locale = AppLanguage.shared.locale
        if locale == .english { return key }
        return tables[locale]?[key] ?? key
    }

    private static func loadTable(_ name: String) -> [String: String]? {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "L10n/Tables")
                ?? bundle.url(forResource: name, withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}

func L(_ key: String) -> String { L10n.t(key) }

func L(_ key: String, _ args: CVarArg...) -> String { L10n.t(key, args: args) }
