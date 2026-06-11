import XCTest
@testable import LiveNote

@MainActor
final class SessionExportTests: XCTestCase {
    func testBuildMarkdownExportIncludesSelectedSections() throws {
        let package = try SessionExportBuilder().build(
            session: sampleSession,
            segments: sampleSegments,
            format: .markdown,
            options: SessionExportOptions()
        )

        XCTAssertEqual(package.filename, "产品评审.md")
        XCTAssertTrue(package.contents.contains("# 产品评审"))
        XCTAssertTrue(package.contents.contains("## 原文"))
        XCTAssertTrue(package.contents.contains("- [00:03] 讨论发布计划"))
        XCTAssertTrue(package.contents.contains("## 译文"))
        XCTAssertTrue(package.contents.contains("Discuss the launch plan"))
    }

    func testBuildTxtExportCanLimitSections() throws {
        let options = SessionExportOptions(
            includesTranscript: true,
            includesTranslation: false
        )

        let package = try SessionExportBuilder().build(
            session: sampleSession,
            segments: sampleSegments,
            format: .txt,
            options: options
        )

        XCTAssertEqual(package.filename, "产品评审.txt")
        XCTAssertTrue(package.contents.contains("原文"))
        XCTAssertTrue(package.contents.contains("[00:03] 讨论发布计划"))
        XCTAssertFalse(package.contents.contains("译文"))
    }

    func testBuildExportRejectsEmptySelection() throws {
        let options = SessionExportOptions(
            includesTranscript: false,
            includesTranslation: false
        )

        XCTAssertThrowsError(
            try SessionExportBuilder().build(
                session: sampleSession,
                segments: sampleSegments,
                format: .markdown,
                options: options
            )
        ) { error in
            XCTAssertEqual(error as? SessionExportError, .emptySelection)
        }
    }

    func testBuildExportRejectsEmptyContent() throws {
        let emptySession = NoteSession(title: "空记录")
        let options = SessionExportOptions(
            includesTranscript: true,
            includesTranslation: false
        )

        XCTAssertThrowsError(
            try SessionExportBuilder().build(
                session: emptySession,
                segments: [],
                format: .txt,
                options: options
            )
        ) { error in
            XCTAssertEqual(error as? SessionExportError, .emptyContent)
        }
    }

    func testViewModelWritesExportFile() throws {
        let viewModel = RecordingViewModel(
            translationService: MockTranslationService(result: "Discuss the launch plan")
        )
        viewModel.acceptTranscriptionSegment(sampleSegments[0])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        viewModel.exportCurrentSession(
            format: .markdown,
            options: SessionExportOptions(
                includesTranscript: true,
                includesTranslation: false
            ),
            destinationURL: url
        )

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("讨论发布计划"))
        XCTAssertTrue(viewModel.exportStatusMessage.contains("已导出到"))

        try? FileManager.default.removeItem(at: url)
    }

    private var sampleSession: NoteSession {
        NoteSession(
            title: "产品评审",
            sourceLanguageName: "中文",
            targetLanguageName: "英文",
            duration: 125,
            status: .completed,
            segmentCount: 2,
            highlightedCount: 1
        )
    }

    private var sampleSegments: [TranscriptSegment] {
        [
            TranscriptSegment(
                text: "讨论发布计划",
                isFinal: true,
                startTime: 3,
                duration: 2,
                translatedText: "Discuss the launch plan",
                translationStatus: .translated,
                isHighlighted: true
            ),
            TranscriptSegment(
                text: "临时文本",
                isFinal: false,
                startTime: 8,
                duration: 1
            )
        ]
    }

}
