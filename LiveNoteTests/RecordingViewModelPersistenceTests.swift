import XCTest
@testable import LiveNote

@MainActor
final class RecordingViewModelPersistenceTests: XCTestCase {
    func testViewModelPersistsFinalSegmentAndLoadsItOnLaunch() async throws {
        let store = InMemoryNoteSessionStore()
        let firstViewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Stored translation"),
            sessionStore: store
        )

        firstViewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "需要持久化",
                isFinal: true,
                startTime: 0,
                duration: 1
            )
        )

        try await waitFor {
            firstViewModel.segments.first?.translationStatus == .translated
        }

        let relaunchedViewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused"),
            sessionStore: store
        )

        XCTAssertEqual(relaunchedViewModel.currentSession.id, firstViewModel.currentSession.id)
        XCTAssertEqual(relaunchedViewModel.currentSession.segmentCount, 1)
        XCTAssertEqual(relaunchedViewModel.segments.first?.text, "需要持久化")
        XCTAssertEqual(relaunchedViewModel.segments.first?.translatedText, "Stored translation")
        XCTAssertEqual(relaunchedViewModel.statusMessage, "已载入历史记录")
    }

    func testViewModelPersistsEditedAndHighlightedSegmentState() async throws {
        let store = InMemoryNoteSessionStore()
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Updated translation"),
            sessionStore: store
        )

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(
                text: "原始内容",
                isFinal: true,
                startTime: 4,
                duration: 2
            )
        )

        guard let segmentID = viewModel.segments.first?.id else {
            XCTFail("Expected segment.")
            return
        }

        viewModel.updateSegmentText(id: segmentID, text: "编辑后的内容")
        viewModel.toggleSegmentHighlight(id: segmentID)

        try await waitFor {
            viewModel.segments.first?.translatedText == "Updated translation"
        }

        let storedSegments = try store.loadSegments(for: viewModel.currentSession.id)
        XCTAssertEqual(storedSegments.first?.text, "编辑后的内容")
        XCTAssertEqual(storedSegments.first?.isEdited, true)
        XCTAssertEqual(storedSegments.first?.isHighlighted, true)
        XCTAssertEqual(storedSegments.first?.translatedText, "Updated translation")
    }

    func testDeleteAllSessionsClearsStoreAndResetsViewModel() {
        let store = InMemoryNoteSessionStore()
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Unused"),
            sessionStore: store
        )

        viewModel.acceptTranscriptionSegment(
            TranscriptSegment(text: "需要删除", isFinal: true, startTime: 0, duration: 1)
        )
        viewModel.startNewSession()

        XCTAssertFalse(viewModel.recentSessions.isEmpty)

        viewModel.deleteAllSessions()

        XCTAssertTrue(viewModel.recentSessions.isEmpty)
        XCTAssertTrue(viewModel.segments.isEmpty)
        XCTAssertEqual(viewModel.currentSession.segmentCount, 0)
        XCTAssertEqual(viewModel.statusMessage, "已清空本地记录")
        XCTAssertTrue((try? store.loadSessions())?.isEmpty == true)
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

@MainActor
private final class InMemoryNoteSessionStore: NoteSessionStoreProtocol {
    private var sessions: [UUID: NoteSession] = [:]
    private var segmentsBySessionID: [UUID: [TranscriptSegment]] = [:]

    func loadSessions() throws -> [NoteSession] {
        sessions.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadSegments(for sessionID: UUID) throws -> [TranscriptSegment] {
        segmentsBySessionID[sessionID, default: []].sorted { $0.startTime < $1.startTime }
    }

    func save(session: NoteSession, segments: [TranscriptSegment]) throws {
        sessions[session.id] = session
        segmentsBySessionID[session.id] = segments
    }

    func deleteSession(id: UUID) throws {
        sessions[id] = nil
        segmentsBySessionID[id] = nil
    }

    func deleteAllSessions() throws {
        sessions.removeAll()
        segmentsBySessionID.removeAll()
    }
}
