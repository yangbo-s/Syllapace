import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Interface localization")
struct LocalizationTests {
    @Test func supportedLanguageResolution() {
        #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN", "en-US"]) == .simplifiedChinese)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["zh_TW"]) == .simplifiedChinese)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-GB", "zh-Hans"]) == .english)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == .english)
        #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english)
        #expect(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"]) == .simplifiedChinese)
    }

    @Test func translatedUIAndProtectedTerms() {
        #expect(L10n.string("Today", language: .english) == "Today")
        #expect(L10n.string("Today", language: .simplifiedChinese) == "今天")
        #expect(L10n.string("Sync Canvas", language: .simplifiedChinese) == "同步 Canvas")
        #expect(L10n.string("API key", language: .simplifiedChinese) == "API key")
        #expect(L10n.string("Apple Calendar", language: .simplifiedChinese) == "Apple Calendar")
        #expect(L10n.string("unknown-key", language: .simplifiedChinese) == "unknown-key")
    }

    @Test func formatsPreserveArgumentsAndSupportChineseWordOrder() {
        let key = "The text of ‘%@’ will be sent directly to %@ using %@. Provider usage charges may apply. Canvas credentials are never included."
        let result = L10n.format(key, arguments: ["100% Canvas notes", "https://example.test/v1", "model-1"], language: .simplifiedChinese)
        #expect(result.contains("“100% Canvas notes”的文本将使用 model-1 直接发送至 https://example.test/v1"))
        #expect(L10n.format("Ready to review: %ld.", arguments: [0], language: .simplifiedChinese) == "待审核候选：0 项。")
        #expect(L10n.format("Ready to review: %ld.", arguments: [1], language: .english) == "Ready to review: 1.")
        #expect(L10n.format("The service returned HTTP %ld. Try again later.", arguments: [503], language: .simplifiedChinese).contains("HTTP 503"))
    }

    @Test func languageTablesHaveMatchingKeysAndFormatTypes() throws {
        func table(_ language: String) throws -> [String: String] {
            let url = try #require(L10n.resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let propertyList = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            return try #require(propertyList as? [String: String])
        }
        let english = try table("en"), chinese = try table("zh-Hans")
        #expect(Set(english.keys) == Set(chinese.keys))
        #expect(english.count >= 200)
        let expression = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|d|@)"#)
        func placeholders(_ text: String) -> [String] {
            expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            }.sorted()
        }
        for (key, value) in english {
            #expect(!chinese[key, default: ""].isEmpty, "Missing Chinese translation: \(key)")
            #expect(placeholders(value) == placeholders(chinese[key, default: ""]), "Format arguments differ: \(key)")
        }
    }

    @Test func userCourseNamesAndStoredDataRemainUnchanged() throws {
        let userCourse = Course(id: "canvas-42", name: "Today", code: "Canvas 中文课")
        #expect(userCourse.localizedName == "Today")
        #expect(userCourse.localizedCode == "Canvas 中文课")
        let builtin = Course(id: "personal", name: "Personal", code: "Personal")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(builtin)
        _ = builtin.localizedName
        _ = builtin.localizedCode
        #expect(try encoder.encode(builtin) == before)
        #expect(builtin.name == "Personal")
    }
}
