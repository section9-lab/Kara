import Foundation
import SwiftData

@MainActor
protocol NoteSessionStoreProtocol {
    func loadSessions() throws -> [NoteSession]
    func loadSegments(for sessionID: UUID) throws -> [TranscriptSegment]
    func save(session: NoteSession, segments: [TranscriptSegment]) throws
    func deleteSession(id: UUID) throws
    func deleteAllSessions() throws
}

@MainActor
final class NoteSessionStore: NoteSessionStoreProtocol {
    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            PersistentNoteSession.self,
            PersistentTranscriptSegment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadSessions() throws -> [NoteSession] {
        var descriptor = FetchDescriptor<PersistentNoteSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map(NoteSession.init(persistentSession:))
    }

    func loadSegments(for sessionID: UUID) throws -> [TranscriptSegment] {
        let descriptor = FetchDescriptor<PersistentTranscriptSegment>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.sessionID == sessionID }
            .map(TranscriptSegment.init(persistentSegment:))
    }

    func save(session: NoteSession, segments: [TranscriptSegment]) throws {
        let persistentSession = try findOrCreateSession(id: session.id)
        persistentSession.update(from: session)

        let existingSegments = Dictionary(
            persistentSession.segments.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var savedSegmentIDs = Set<UUID>()

        for segment in segments {
            let persistentSegment = existingSegments[segment.id] ?? PersistentTranscriptSegment(
                from: segment,
                sessionID: session.id
            )
            persistentSegment.update(from: segment)
            persistentSegment.sessionID = session.id

            if existingSegments[segment.id] == nil {
                modelContext.insert(persistentSegment)
                persistentSession.segments.append(persistentSegment)
            }

            savedSegmentIDs.insert(segment.id)
        }

        for segment in persistentSession.segments where !savedSegmentIDs.contains(segment.id) {
            modelContext.delete(segment)
        }

        try modelContext.save()
    }

    func deleteSession(id: UUID) throws {
        guard let session = try findSession(id: id) else {
            return
        }

        for segment in session.segments {
            modelContext.delete(segment)
        }

        modelContext.delete(session)
        try modelContext.save()
    }

    func deleteAllSessions() throws {
        let sessionDescriptor = FetchDescriptor<PersistentNoteSession>()
        for session in try modelContext.fetch(sessionDescriptor) {
            modelContext.delete(session)
        }

        let segmentDescriptor = FetchDescriptor<PersistentTranscriptSegment>()
        for segment in try modelContext.fetch(segmentDescriptor) {
            modelContext.delete(segment)
        }

        try modelContext.save()
    }

    private func findSession(id: UUID) throws -> PersistentNoteSession? {
        let descriptor = FetchDescriptor<PersistentNoteSession>()
        return try modelContext.fetch(descriptor).first { $0.id == id }
    }

    private func findOrCreateSession(id: UUID) throws -> PersistentNoteSession {
        if let existingSession = try findSession(id: id) {
            return existingSession
        }

        let session = PersistentNoteSession(
            id: id,
            title: "",
            createdAt: .now,
            updatedAt: .now,
            sourceLanguageName: "中文",
            targetLanguageName: "英文",
            duration: 0,
            statusRawValue: NoteSessionStatus.draft.rawValue,
            segmentCount: 0,
            highlightedCount: 0
        )
        modelContext.insert(session)
        return session
    }
}

extension NoteSession {
    init(persistentSession: PersistentNoteSession) {
        self.init(
            id: persistentSession.id,
            title: persistentSession.title,
            createdAt: persistentSession.createdAt,
            updatedAt: persistentSession.updatedAt,
            sourceLanguageName: persistentSession.sourceLanguageName,
            targetLanguageName: persistentSession.targetLanguageName,
            duration: persistentSession.duration,
            status: NoteSessionStatus(persistentRawValue: persistentSession.statusRawValue),
            segmentCount: persistentSession.segmentCount,
            highlightedCount: persistentSession.highlightedCount
        )
    }
}

extension TranscriptSegment {
    init(persistentSegment: PersistentTranscriptSegment) {
        self.init(
            id: persistentSegment.id,
            text: persistentSegment.text,
            isFinal: persistentSegment.isFinal,
            startTime: persistentSegment.startTime,
            duration: persistentSegment.duration,
            translatedText: persistentSegment.translatedText,
            translationStatus: TranslationStatus(
                persistentRawValue: persistentSegment.translationStatusRawValue,
                message: persistentSegment.translationStatusMessage
            ),
            isEdited: persistentSegment.isEdited,
            isHighlighted: persistentSegment.isHighlighted,
            updatedAt: persistentSegment.updatedAt
        )
    }
}

private extension PersistentNoteSession {
    func update(from session: NoteSession) {
        title = session.title
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        sourceLanguageName = session.sourceLanguageName
        targetLanguageName = session.targetLanguageName
        duration = session.duration
        statusRawValue = session.status.rawValue
        segmentCount = session.segmentCount
        highlightedCount = session.highlightedCount
    }
}

private extension PersistentTranscriptSegment {
    convenience init(from segment: TranscriptSegment, sessionID: UUID) {
        self.init(
            id: segment.id,
            text: segment.text,
            isFinal: segment.isFinal,
            startTime: segment.startTime,
            duration: segment.duration,
            translatedText: segment.translatedText,
            translationStatusRawValue: segment.translationStatus.persistentRawValue,
            translationStatusMessage: segment.translationStatus.persistentMessage,
            isEdited: segment.isEdited,
            isHighlighted: segment.isHighlighted,
            updatedAt: segment.updatedAt,
            sessionID: sessionID
        )
    }

    func update(from segment: TranscriptSegment) {
        text = segment.text
        isFinal = segment.isFinal
        startTime = segment.startTime
        duration = segment.duration
        translatedText = segment.translatedText
        translationStatusRawValue = segment.translationStatus.persistentRawValue
        translationStatusMessage = segment.translationStatus.persistentMessage
        isEdited = segment.isEdited
        isHighlighted = segment.isHighlighted
        updatedAt = segment.updatedAt
    }
}
