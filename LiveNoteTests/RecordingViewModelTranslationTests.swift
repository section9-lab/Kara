import XCTest
@testable import LiveNote

@MainActor
final class RecordingViewModelTranslationTests: XCTestCase {
    func testFinalSegmentTriggersTranslation() async throws {
        let translationService = MockTranslationService(result: "Hello everyone")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "大家好",
                isFinal: true,
                startTime: 0,
                duration: 1.4
            )
        )

        try await waitFor {
            viewModel.segments.first?.translatedText == "Hello everyone"
        }

        XCTAssertEqual(viewModel.segments.first?.translationStatus, .translated)
        XCTAssertEqual(translationService.requests, ["大家好"])
    }

    func testVolatileSegmentDoesNotTriggerTranslation() async throws {
        let translationService = MockTranslationService(result: "Hello everyone")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "大家",
                isFinal: false,
                startTime: 0,
                duration: 0
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.volatileText, "大家")
        XCTAssertTrue(viewModel.segments.isEmpty)
        XCTAssertEqual(translationService.requests, [])
    }

    func testFinalContinuationSegmentMergesBeforeTranslation() async throws {
        let translationService = MockTranslationService(result: "Merged translation")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "它改变了以往逐次预测点击动作的模式",
                isFinal: true,
                startTime: 0,
                duration: 1.8
            )
        )
        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "，该系统为模型提供了一个终端环境",
                isFinal: true,
                startTime: 1.8,
                duration: 0.6
            )
        )

        try await waitFor {
            translationService.requests.last == "它改变了以往逐次预测点击动作的模式，该系统为模型提供了一个终端环境"
        }

        XCTAssertEqual(viewModel.segments.count, 1)
        XCTAssertEqual(viewModel.segments.first?.text, "它改变了以往逐次预测点击动作的模式，该系统为模型提供了一个终端环境")
        XCTAssertEqual(translationService.requests, [
            "它改变了以往逐次预测点击动作的模式",
            "它改变了以往逐次预测点击动作的模式，该系统为模型提供了一个终端环境"
        ])
    }

    func testEditingFinalSegmentMarksEditedAndRetranslates() async throws {
        let translationService = MockTranslationService(result: "Updated translation")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "原始文本",
                isFinal: true,
                startTime: 3,
                duration: 2
            )
        )

        guard let segmentID = viewModel.segments.first?.id else {
            XCTFail("Expected a final segment.")
            return
        }

        viewModel.updateSegmentText(id: segmentID, text: " 修改后的文本 ")

        try await waitFor {
            viewModel.segments.first?.translationStatus == .translated
        }

        XCTAssertEqual(viewModel.segments.first?.text, "修改后的文本")
        XCTAssertEqual(viewModel.segments.first?.translatedText, "Updated translation")
        XCTAssertEqual(viewModel.segments.first?.isEdited, true)
        XCTAssertEqual(translationService.requests, ["原始文本", "修改后的文本"])
    }

    func testChangingTargetLanguageRetranslatesFinalSegments() async throws {
        let translationService = MockTranslationService(result: "Translated")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(text: "第一段", isFinal: true, startTime: 0, duration: 1)
        )

        try await waitFor {
            viewModel.segments.first?.translationStatus == .translated
        }

        viewModel.updateTargetLanguage(.japanese)

        try await waitFor {
            translationService.requests == ["第一段", "第一段"]
        }

        XCTAssertEqual(viewModel.targetLanguage, .japanese)
        XCTAssertEqual(viewModel.currentSession.targetLanguageName, "日文")
        XCTAssertEqual(translationService.targetLanguages.last, TranslationLanguage.japanese.localeLanguage)
    }

    func testRetranslateSegmentOnlyUpdatesRequestedSegment() async throws {
        let translationService = MockTranslationService(result: "Translated")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(text: "第一段", isFinal: true, startTime: 0, duration: 1)
        )
        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(text: "第二段", isFinal: true, startTime: 1, duration: 1)
        )

        try await waitFor {
            translationService.requests.count == 2
        }

        guard let firstSegmentID = viewModel.segments.first?.id else {
            XCTFail("Expected a final segment.")
            return
        }

        viewModel.retranslateSegment(id: firstSegmentID)

        try await waitFor {
            translationService.requests.count == 3
        }

        XCTAssertEqual(translationService.requests, ["第一段", "第二段", "第一段"])
    }

    func testTranslationFailureShowsActionableResourceMessage() async throws {
        let translationService = MockTranslationService(
            result: "",
            error: TranslationPipelineError.languageAssetsNotInstalled
        )
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(text: "需要翻译的文本", isFinal: true, startTime: 0, duration: 1)
        )

        try await waitFor {
            if case .unavailable = viewModel.segments.first?.translationStatus {
                return true
            }
            return false
        }

        guard case .unavailable(let message) = viewModel.segments.first?.translationStatus else {
            XCTFail("Expected translation resource unavailable.")
            return
        }

        XCTAssertTrue(message.contains("系统翻译资源未安装"))
        XCTAssertTrue(viewModel.translationStatusMessage.contains("系统翻译资源未安装"))
    }

    func testSystemTranslationServiceQueuesSwiftUITranslationRequest() {
        let viewModel = RecordingViewModel(translationService: SystemTranslationService())

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(text: "需要系统翻译", isFinal: true, startTime: 0, duration: 1)
        )

        XCTAssertEqual(viewModel.pendingSystemTranslationRequests.count, 1)
        XCTAssertNotNil(viewModel.systemTranslationConfiguration)
        XCTAssertEqual(viewModel.segments.first?.translationStatus, .translating)
    }

    func testFocusFirstSegmentMatchesTextOrTranslation() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let first = TranscriptSegment(
            text: "讨论预算",
            isFinal: true,
            startTime: 0,
            duration: 1,
            translatedText: "Budget"
        )
        let second = TranscriptSegment(
            text: "确认发布时间",
            isFinal: true,
            startTime: 1,
            duration: 1,
            translatedText: "Launch date"
        )
        viewModel.segments = [first, second]

        viewModel.focusFirstSegment(matching: "launch")
        XCTAssertEqual(viewModel.focusedSegmentID, second.id)

        viewModel.focusFirstSegment(matching: "预算")
        XCTAssertEqual(viewModel.focusedSegmentID, first.id)
    }

    func testFocusSourceSegmentUsesFirstExistingSourceID() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let segment = TranscriptSegment(text: "来源段落", isFinal: true, startTime: 0, duration: 1)
        viewModel.segments = [segment]

        viewModel.focusSourceSegment(ids: [UUID(), segment.id])

        XCTAssertEqual(viewModel.focusedSegmentID, segment.id)
    }

    func testHighlightUpdatesCurrentSessionCounts() {
        let translationService = MockTranslationService(result: "Hello everyone")
        let viewModel = RecordingViewModel(translationService: translationService)

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "需要关注",
                isFinal: true,
                startTime: 4,
                duration: 1
            )
        )

        guard let segmentID = viewModel.segments.first?.id else {
            XCTFail("Expected a final segment.")
            return
        }

        viewModel.toggleSegmentHighlight(id: segmentID)

        XCTAssertEqual(viewModel.segments.first?.isHighlighted, true)
        XCTAssertEqual(viewModel.currentSession.segmentCount, 1)
        XCTAssertEqual(viewModel.currentSession.highlightedCount, 1)
    }

    func testStartingNewSessionArchivesCurrentSession() {
        let translationService = MockTranslationService(result: "Hello everyone")
        let viewModel = RecordingViewModel(translationService: translationService)
        let initialRecentCount = viewModel.recentSessions.count

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "第一段",
                isFinal: true,
                startTime: 0,
                duration: 1
            )
        )

        viewModel.startNewSession()

        XCTAssertEqual(viewModel.segments.count, 0)
        XCTAssertEqual(viewModel.recentSessions.count, initialRecentCount + 1)
        XCTAssertEqual(viewModel.recentSessions.first?.segmentCount, 1)
    }

    private func waitFor(
        timeout: Duration = .seconds(2),
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let start = ContinuousClock.now

        while !condition() {
            if ContinuousClock.now - start > timeout {
                XCTFail("Timed out waiting for condition.")
                return
            }

            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
