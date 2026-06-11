import Foundation
@testable import LiveNote

@MainActor
final class MockTranslationService: TranslationServiceProtocol {
    let result: String
    let error: (any Error)?
    private(set) var requests: [String] = []
    private(set) var targetLanguages: [Locale.Language] = []

    init(result: String, error: (any Error)? = nil) {
        self.result = result
        self.error = error
    }

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationReadiness {
        .installed
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        requests.append(text)
        targetLanguages.append(target)
        if let error {
            throw error
        }
        return result
    }
}
