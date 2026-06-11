import Foundation

struct NoteSession: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var sourceLanguageName: String
    var targetLanguageName: String
    var duration: TimeInterval
    var status: NoteSessionStatus
    var segmentCount: Int
    var highlightedCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sourceLanguageName: String = "中文",
        targetLanguageName: String = "英文",
        duration: TimeInterval = 0,
        status: NoteSessionStatus = .draft,
        segmentCount: Int = 0,
        highlightedCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceLanguageName = sourceLanguageName
        self.targetLanguageName = targetLanguageName
        self.duration = duration
        self.status = status
        self.segmentCount = segmentCount
        self.highlightedCount = highlightedCount
    }
}

enum NoteSessionStatus: String, Equatable, Sendable {
    case draft
    case recording
    case paused
    case completed

    var label: String {
        switch self {
        case .draft:
            "草稿"
        case .recording:
            "录音中"
        case .paused:
            "已暂停"
        case .completed:
            "已完成"
        }
    }
}

extension NoteSessionStatus {
    init(persistentRawValue: String) {
        self = NoteSessionStatus(rawValue: persistentRawValue) ?? .draft
    }
}
