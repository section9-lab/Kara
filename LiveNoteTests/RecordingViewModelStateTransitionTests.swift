import XCTest
@testable import LiveNote

@MainActor
final class RecordingViewModelStateTransitionTests: XCTestCase {
    func testProcessingStateIgnoresToggleRecording() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let currentSessionID = viewModel.currentSession.id

        viewModel.recordingState = .processing
        viewModel.toggleRecording()

        XCTAssertEqual(viewModel.recordingState, .processing)
        XCTAssertEqual(viewModel.currentSession.id, currentSessionID)
        XCTAssertEqual(viewModel.statusMessage, "正在处理上一项操作")
    }

    func testProcessingStateIgnoresStopRecording() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let currentSessionID = viewModel.currentSession.id

        viewModel.recordingState = .processing
        viewModel.stopRecording()

        XCTAssertEqual(viewModel.recordingState, .processing)
        XCTAssertEqual(viewModel.currentSession.id, currentSessionID)
        XCTAssertEqual(viewModel.statusMessage, "正在处理上一项操作")
    }

    func testProcessingStateIgnoresStartNewSession() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let currentSessionID = viewModel.currentSession.id

        viewModel.recordingState = .processing
        viewModel.startNewSession()

        XCTAssertEqual(viewModel.recordingState, .processing)
        XCTAssertEqual(viewModel.currentSession.id, currentSessionID)
        XCTAssertEqual(viewModel.statusMessage, "录音结束后才能新建记录")
    }

    func testProcessingStateIgnoresSessionSelection() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let currentSessionID = viewModel.currentSession.id

        viewModel.recordingState = .processing
        viewModel.selectSession(id: UUID())

        XCTAssertEqual(viewModel.recordingState, .processing)
        XCTAssertEqual(viewModel.currentSession.id, currentSessionID)
        XCTAssertEqual(viewModel.statusMessage, "录音结束后才能切换历史记录")
    }

    func testNewViewModelStartsWithNoRecentSessions() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )

        XCTAssertTrue(viewModel.recentSessions.isEmpty)
    }

    func testNonFinalSegmentCannotBeEditedOrHighlighted() {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused")
        )
        let segment = TranscriptSegment(
            text: "临时文本",
            isFinal: false,
            startTime: 0,
            duration: 0
        )

        viewModel.acceptTranscriptionSegment(segment)
        viewModel.segments = [segment]
        viewModel.updateSegmentText(id: segment.id, text: "不应保存")
        viewModel.toggleSegmentHighlight(id: segment.id)

        XCTAssertEqual(viewModel.segments.first?.text, "临时文本")
        XCTAssertEqual(viewModel.segments.first?.isHighlighted, false)
        XCTAssertEqual(viewModel.segments.first?.isEdited, false)
    }
}
