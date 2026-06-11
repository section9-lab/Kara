import Foundation
import SwiftData

@Model
final class PersistentNoteSession {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var sourceLanguageName: String
    var targetLanguageName: String
    var duration: TimeInterval
    var statusRawValue: String
    var segmentCount: Int
    var highlightedCount: Int
    var segments: [PersistentTranscriptSegment]

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        sourceLanguageName: String,
        targetLanguageName: String,
        duration: TimeInterval,
        statusRawValue: String,
        segmentCount: Int,
        highlightedCount: Int,
        segments: [PersistentTranscriptSegment] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceLanguageName = sourceLanguageName
        self.targetLanguageName = targetLanguageName
        self.duration = duration
        self.statusRawValue = statusRawValue
        self.segmentCount = segmentCount
        self.highlightedCount = highlightedCount
        self.segments = segments
    }
}

@Model
final class PersistentTranscriptSegment {
    var id: UUID
    var text: String
    var isFinal: Bool
    var startTime: TimeInterval
    var duration: TimeInterval
    var translatedText: String?
    var translationStatusRawValue: String
    var translationStatusMessage: String?
    var isEdited: Bool
    var isHighlighted: Bool
    var updatedAt: Date
    var sessionID: UUID

    init(
        id: UUID,
        text: String,
        isFinal: Bool,
        startTime: TimeInterval,
        duration: TimeInterval,
        translatedText: String?,
        translationStatusRawValue: String,
        translationStatusMessage: String?,
        isEdited: Bool,
        isHighlighted: Bool,
        updatedAt: Date,
        sessionID: UUID
    ) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.startTime = startTime
        self.duration = duration
        self.translatedText = translatedText
        self.translationStatusRawValue = translationStatusRawValue
        self.translationStatusMessage = translationStatusMessage
        self.isEdited = isEdited
        self.isHighlighted = isHighlighted
        self.updatedAt = updatedAt
        self.sessionID = sessionID
    }
}

