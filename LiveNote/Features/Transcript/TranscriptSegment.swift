import Foundation

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    let isFinal: Bool
    let startTime: TimeInterval
    let duration: TimeInterval
    var translatedText: String?
    var translationStatus: TranslationStatus
    var isEdited: Bool
    var isHighlighted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        isFinal: Bool,
        startTime: TimeInterval,
        duration: TimeInterval,
        translatedText: String? = nil,
        translationStatus: TranslationStatus = .notRequested,
        isEdited: Bool = false,
        isHighlighted: Bool = false,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.startTime = startTime
        self.duration = duration
        self.translatedText = translatedText
        self.translationStatus = translationStatus
        self.isEdited = isEdited
        self.isHighlighted = isHighlighted
        self.updatedAt = updatedAt
    }
}

enum TranslationStatus: Equatable, Sendable {
    case notRequested
    case translating
    case translated
    case unavailable(String)
    case failed(String)

    var label: String {
        switch self {
        case .notRequested:
            "未翻译"
        case .translating:
            "翻译中"
        case .translated:
            "已翻译"
        case .unavailable:
            "不可用"
        case .failed:
            "翻译失败"
        }
    }
}

extension TranslationStatus {
    var persistentRawValue: String {
        switch self {
        case .notRequested:
            "notRequested"
        case .translating:
            "translating"
        case .translated:
            "translated"
        case .unavailable:
            "unavailable"
        case .failed:
            "failed"
        }
    }

    var persistentMessage: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            message
        case .notRequested, .translating, .translated:
            nil
        }
    }

    init(persistentRawValue: String, message: String?) {
        switch persistentRawValue {
        case "translating":
            self = .translating
        case "translated":
            self = .translated
        case "unavailable":
            self = .unavailable(message ?? "翻译资源不可用。")
        case "failed":
            self = .failed(message ?? "翻译失败。")
        case "notRequested":
            self = .notRequested
        default:
            self = .notRequested
        }
    }
}
