import Foundation
@preconcurrency import Translation

@MainActor
protocol TranslationServiceProtocol {
    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationReadiness
    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String
}

enum TranslationReadiness: Equatable, Sendable {
    case installed
    case supported
    case unsupported
}

final class SystemTranslationService: TranslationServiceProtocol {
    private let availabilityChecker = LanguageAvailability()

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationReadiness {
        let status = await availabilityChecker.status(from: source, to: target)
        return Self.mapStatus(status)
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranslationPipelineError.emptyInput
        }

        let readiness = await availability(from: source, to: target)
        guard readiness != .unsupported else {
            throw TranslationPipelineError.unsupportedLanguagePair
        }

        let session = TranslationSession(installedSource: source, target: target)

        do {
            try await session.prepareTranslation()
            let response = try await session.translate(trimmedText)
            return response.targetText
        } catch {
            throw TranslationPipelineError.fromSystemError(error)
        }
    }

    private static func mapStatus(_ status: LanguageAvailability.Status) -> TranslationReadiness {
        switch status {
        case .installed:
            .installed
        case .supported:
            .supported
        case .unsupported:
            .unsupported
        @unknown default:
            .unsupported
        }
    }

}

enum TranslationPipelineError: LocalizedError {
    case emptyInput
    case unsupportedLanguagePair
    case languageAssetsNotInstalled
    case unableToIdentifyLanguage
    case systemTranslationFailed(String)

    static func fromSystemError(_ error: any Error) -> TranslationPipelineError {
        if let pipelineError = error as? TranslationPipelineError {
            return pipelineError
        }

        if TranslationError.notInstalled ~= error {
            return .languageAssetsNotInstalled
        }

        if TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error
            || TranslationError.unsupportedLanguagePairing ~= error {
            return .unsupportedLanguagePair
        }

        if TranslationError.nothingToTranslate ~= error {
            return .emptyInput
        }

        if TranslationError.unableToIdentifyLanguage ~= error {
            return .unableToIdentifyLanguage
        }

        return .systemTranslationFailed(error.localizedDescription)
    }

    var isAvailabilityIssue: Bool {
        switch self {
        case .unsupportedLanguagePair, .languageAssetsNotInstalled:
            true
        case .emptyInput, .unableToIdentifyLanguage, .systemTranslationFailed:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "没有可翻译的文本。"
        case .unsupportedLanguagePair:
            "当前语言方向不支持系统翻译。"
        case .languageAssetsNotInstalled:
            "系统翻译资源未安装。请在 macOS 系统翻译提示中下载中文和目标语言资源后重试。"
        case .unableToIdentifyLanguage:
            "系统无法识别这段文本的语言，请确认原文是中文后重试。"
        case .systemTranslationFailed(let message):
            if message.isEmpty || message == "Unable to Translate" {
                "系统翻译暂时失败。请确认翻译资源已下载，或稍后重试。"
            } else {
                message
            }
        }
    }
}
