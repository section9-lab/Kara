import Foundation

@MainActor
enum UITestFixture {
    static func seedIfNeeded(sessionStore: NoteSessionStore) {
        guard ProcessInfo.processInfo.arguments.contains("-LiveNoteSeedCompletedSession") else {
            return
        }

        guard (try? sessionStore.loadSessions().isEmpty) == true else {
            return
        }

        let firstSegment = TranscriptSegment(
            text: "讨论发布计划和预算安排",
            isFinal: true,
            startTime: 0,
            duration: 4,
            translatedText: "Discuss launch plan and budget",
            translationStatus: .translated,
            isHighlighted: true
        )
        let secondSegment = TranscriptSegment(
            text: "确认下周三前完成导出验收",
            isFinal: true,
            startTime: 6,
            duration: 3,
            translatedText: "Confirm export acceptance by next Wednesday",
            translationStatus: .translated
        )

        let session = NoteSession(
            title: "产品评审记录",
            duration: 126,
            status: .completed,
            segmentCount: 2,
            highlightedCount: 1
        )

        do {
            try sessionStore.save(session: session, segments: [firstSegment, secondSegment])
        } catch {
            assertionFailure("UI 测试数据准备失败：\(error.localizedDescription)")
        }
    }
}
