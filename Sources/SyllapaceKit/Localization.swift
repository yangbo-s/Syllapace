import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .system: L10n.string("Follow system")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    public func resolved(preferredLanguages: [String]? = nil) -> AppLanguage {
        guard self == .system else { return self }
        // An explicit app language may override AppleLanguages in this app's
        // domain. Follow system must read the global domain, not that override.
        let languages = preferredLanguages ?? L10n.systemPreferredLanguages
        for identifier in languages {
            let code = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if code == "zh" || code.hasPrefix("zh-") { return .simplifiedChinese }
            if code == "en" || code.hasPrefix("en-") { return .english }
        }
        return .english
    }

    public var locale: Locale {
        Locale(identifier: resolved() == .simplifiedChinese ? "zh_Hans_CN" : "en_US")
    }
}

/// Explicit bundle lookup keeps SwiftUI, AppKit and async service errors on the
/// same language. User content never passes through this lookup.
public enum L10n {
    public static let preferenceKey = "appLanguage"
    public static var systemPreferredLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }
    static let resourceBundle: Bundle = {
        // SwiftPM's accessor can contain an absolute build path. The installed
        // app owns a copy under Resources, which must work after relocation.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Syllapace_SyllapaceKit.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    public static var language: AppLanguage {
        let value = ProcessInfo.processInfo.environment["APP_LANGUAGE"]
            ?? UserDefaults.standard.string(forKey: preferenceKey) ?? "system"
        return (AppLanguage(rawValue: value) ?? .system).resolved()
    }
    public static var locale: Locale { language.locale }

    public static func string(_ key: String, language: AppLanguage? = nil) -> String {
        let language = (language ?? self.language).resolved()
        guard let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments, language: language)
    }

    public static func format(_ key: String, arguments: [CVarArg], language: AppLanguage) -> String {
        String(format: string(key, language: language), locale: language.locale, arguments: arguments)
    }

    public static func date(_ date: Date, dateOnly: Bool = false) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: dateOnly ? .omitted : .shortened).locale(locale))
    }

    public static func relativeDate(_ date: Date) -> String {
        date.formatted(Date.RelativeFormatStyle(presentation: .numeric, locale: locale))
    }
}

public extension EventKind {
    var localizedName: String { L10n.string(rawValue.capitalized) }
}

public extension Course {
    // The built-in Personal course keeps its stable archived name and ID.
    var localizedName: String { id == "personal" && name == "Personal" ? L10n.string("Personal") : name }
    var localizedCode: String { id == "personal" && code == "Personal" ? L10n.string("Personal") : code }
}
