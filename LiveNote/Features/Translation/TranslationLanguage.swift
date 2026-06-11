import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case japanese
    case korean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            "英文"
        case .japanese:
            "日文"
        case .korean:
            "韩文"
        }
    }

    var localeLanguage: Locale.Language {
        switch self {
        case .english:
            Locale.Language(identifier: "en")
        case .japanese:
            Locale.Language(identifier: "ja")
        case .korean:
            Locale.Language(identifier: "ko")
        }
    }
}
