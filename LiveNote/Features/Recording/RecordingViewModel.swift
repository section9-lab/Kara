import Foundation
import Observation
@preconcurrency import Translation

@MainActor
@Observable
final class RecordingViewModel {
    static let sourceLanguage = Locale.Language(identifier: "zh-Hans")

    var recordingState: RecordingState = .ready
    var elapsedSeconds: TimeInterval = 0
    var segments: [TranscriptSegment] = []
    var volatileText = ""
    var targetLanguage: TranslationLanguage = .english
    var focusedSegmentID: UUID?
    var statusMessage = "准备开始实时记录"
    var translationStatusMessage = "等待稳定转写段落"
    var exportStatusMessage = "选择内容后导出当前记录"
    var errorMessage: String?
    var currentSession = NoteSession(title: "新的实时记录")
    var recentSessions: [NoteSession] = []
    var pendingSystemTranslationRequests: [SystemTranslationRequest] = []
    var systemTranslationConfiguration: TranslationSession.Configuration?
    var canToggleRecording: Bool {
        recordingState != .processing
    }
    var canStopRecording: Bool {
        recordingState == .recording || recordingState == .paused
    }
    var canStartNewSession: Bool {
        recordingState == .ready
    }
    var canSelectSession: Bool {
        recordingState == .ready
    }
    var canEditSegments: Bool {
        recordingState != .processing
    }
    var sourceLanguageName: String {
        "中文"
    }
    var targetLanguageName: String {
        targetLanguage.displayName
    }

    private let speechService = SpeechTranscriptionService()
    private let translationService: any TranslationServiceProtocol
    private let sessionStore: (any NoteSessionStoreProtocol)?
    private let exportBuilder = SessionExportBuilder()
    private var timerTask: Task<Void, Never>?
    private var translationTasks: [UUID: Task<Void, Never>] = [:]

    init(
        translationService: any TranslationServiceProtocol = SystemTranslationService(),
        sessionStore: (any NoteSessionStoreProtocol)? = nil
    ) {
        self.translationService = translationService
        self.sessionStore = sessionStore
        loadPersistedSessions()
    }

    func toggleRecording() {
        switch recordingState {
        case .ready:
            startRecording()
        case .recording:
            pauseRecording()
        case .paused:
            startRecording()
        case .processing:
            statusMessage = "正在处理上一项操作"
        }
    }

    func stopRecording() {
        guard canStopRecording else {
            if recordingState == .processing {
                statusMessage = "正在处理上一项操作"
            }
            return
        }

        recordingState = .processing
        statusMessage = "正在结束实时转写"
        stopTimer()

        Task {
            await speechService.stop()
            recordingState = .ready
            volatileText = ""
            statusMessage = "录音已停止"
            updateCurrentSession(status: .completed)
            archiveCurrentSessionIfNeeded()
        }
    }

    private func startRecording() {
        guard canToggleRecording else {
            statusMessage = "正在处理上一项操作"
            return
        }

        errorMessage = nil
        let shouldCreateNewSession = recordingState == .ready
        let stateBeforePreparing = recordingState
        recordingState = .processing
        statusMessage = "正在准备实时转写"

        Task {
            let hasAccess = await ensureMicrophoneAccess()
            guard hasAccess else {
                recordingState = stateBeforePreparing == .paused ? .paused : .ready
                statusMessage = "麦克风权限未开启"
                errorMessage = "请在系统设置中允许 LiveNote 使用麦克风。"
                return
            }

            do {
                if shouldCreateNewSession {
                    elapsedSeconds = 0
                    segments.removeAll()
                    cancelTranslationTasks()
                    translationStatusMessage = "等待稳定转写段落"
                    focusedSegmentID = nil
                    currentSession = NoteSession(title: Self.makeSessionTitle(), targetLanguageName: targetLanguage.displayName)
                    persistCurrentSession()
                }

                try await speechService.start(locale: Locale(identifier: "zh_CN")) { [weak self] segment in
                    guard let self else { return }
                    self.acceptTranscriptionSegment(segment)
                } onError: { [weak self] message in
                    guard let self else { return }
                    self.errorMessage = message
                    self.statusMessage = "实时转写失败"
                    self.recordingState = .ready
                    self.stopTimer()
                    Task {
                        await self.speechService.stop()
                    }
                }

                guard recordingState == .processing else {
                    return
                }

                recordingState = .recording
                statusMessage = "正在监听麦克风"
                updateCurrentSession(status: .recording)
                persistCurrentSession()
                startTimer()
            } catch {
                recordingState = .ready
                statusMessage = "实时转写未启动"
                errorMessage = error.localizedDescription
                stopTimer()
            }
        }
    }

    private func pauseRecording() {
        recordingState = .processing
        statusMessage = "正在暂停实时转写"
        stopTimer()

        Task {
            await speechService.stop()
            recordingState = .paused
            statusMessage = "已暂停"
            updateCurrentSession(status: .paused)
        }
    }

    func acceptTranscriptionSegment(_ segment: TranscriptSegment) {
        if segment.isFinal {
            volatileText = ""

            if appendOrMergeFinalSegment(segment) {
                return
            }

            var finalSegment = segment
            finalSegment.translationStatus = .translating
            segments.append(finalSegment)
            translationStatusMessage = "正在翻译稳定段落"
            updateCurrentSession(status: recordingState == .recording ? .recording : currentSession.status)
            persistCurrentSession()

            translateSegment(finalSegment, in: currentSession.id)
        } else {
            volatileText = segment.text
        }
    }

    private func appendOrMergeFinalSegment(_ segment: TranscriptSegment) -> Bool {
        guard let previousIndex = segments.lastIndex(where: \.isFinal) else {
            return false
        }

        let previous = segments[previousIndex]
        guard shouldMergeFinalSegment(segment, into: previous) else {
            return false
        }

        let mergedText = Self.mergedTranscriptText(previous.text, segment.text)
        let mergedDuration = max(
            previous.duration,
            segment.startTime + segment.duration - previous.startTime
        )
        let mergedSegment = TranscriptSegment(
            id: previous.id,
            text: mergedText,
            isFinal: true,
            startTime: previous.startTime,
            duration: mergedDuration,
            translatedText: nil,
            translationStatus: .translating,
            isEdited: previous.isEdited,
            isHighlighted: previous.isHighlighted,
            updatedAt: .now
        )

        segments[previousIndex] = mergedSegment
        translationStatusMessage = "正在翻译合并后的段落"
        updateCurrentSession(status: recordingState == .recording ? .recording : currentSession.status)
        persistCurrentSession()

        translateSegment(mergedSegment, in: currentSession.id)
        return true
    }

    private func shouldMergeFinalSegment(_ segment: TranscriptSegment, into previous: TranscriptSegment) -> Bool {
        guard !previous.isEdited, !previous.isHighlighted else {
            return false
        }

        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        if Self.startsWithContinuationPunctuation(text) {
            return true
        }

        let gap = segment.startTime - (previous.startTime + previous.duration)
        guard gap >= -0.25, gap <= 0.55 else {
            return false
        }

        return !Self.endsWithSentenceTerminator(previous.text)
            && segment.duration < 0.8
            && text.count <= 10
    }

    private static func mergedTranscriptText(_ first: String, _ second: String) -> String {
        let trimmedFirst = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecond = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFirst.isEmpty else {
            return trimmedSecond
        }
        guard !trimmedSecond.isEmpty else {
            return trimmedFirst
        }

        if startsWithContinuationPunctuation(trimmedSecond) {
            return trimmedFirst + trimmedSecond
        }

        return trimmedFirst + " " + trimmedSecond
    }

    private static func startsWithContinuationPunctuation(_ text: String) -> Bool {
        guard let first = text.first else {
            return false
        }

        return "，,、；;：:）)]}」』".contains(first)
    }

    private static func endsWithSentenceTerminator(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }

        return "。！？!?…".contains(last)
    }

    func updateSegmentText(id: UUID, text: String) {
        guard canEditSegments else {
            statusMessage = "正在处理上一项操作，稍后再编辑"
            return
        }

        guard let index = segments.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard segments[index].isFinal else {
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, segments[index].text != trimmedText else {
            return
        }

        segments[index].text = trimmedText
        segments[index].isEdited = true
        segments[index].updatedAt = .now
        segments[index].translatedText = nil
        segments[index].translationStatus = .translating
        translationStatusMessage = "编辑后正在重新翻译"

        translateSegment(segments[index], in: currentSession.id)
        updateCurrentSession(status: currentSession.status)
        persistCurrentSession()
    }

    func toggleSegmentHighlight(id: UUID) {
        guard canEditSegments else {
            statusMessage = "正在处理上一项操作，稍后再标记重点"
            return
        }

        guard let index = segments.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard segments[index].isFinal else {
            return
        }

        segments[index].isHighlighted.toggle()
        segments[index].updatedAt = .now
        updateCurrentSession(status: currentSession.status)
        persistCurrentSession()
    }

    func focusSegment(id: UUID?) {
        focusedSegmentID = id
    }

    func focusFirstSegment(matching query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            focusedSegmentID = nil
            return
        }

        focusedSegmentID = segments.first { segment in
            segment.text.localizedCaseInsensitiveContains(trimmedQuery)
            || (segment.translatedText?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }?.id
    }

    func focusSourceSegment(ids: [UUID]) {
        focusedSegmentID = ids.first { sourceID in
            segments.contains { $0.id == sourceID }
        }
    }

    func updateTargetLanguage(_ language: TranslationLanguage) {
        guard targetLanguage != language else {
            return
        }

        targetLanguage = language
        currentSession.targetLanguageName = language.displayName
        retranslateAllSegments()
    }

    func retranslateSegment(id: UUID) {
        guard canEditSegments else {
            statusMessage = "正在处理上一项操作，稍后再重新翻译"
            return
        }

        guard let index = segments.firstIndex(where: { $0.id == id }), segments[index].isFinal else {
            return
        }

        segments[index].translatedText = nil
        segments[index].translationStatus = .translating
        segments[index].updatedAt = .now
        translationStatusMessage = "正在重新翻译"
        translateSegment(segments[index], in: currentSession.id)
        persistCurrentSession()
    }

    func retranslateAllSegments() {
        guard canEditSegments else {
            statusMessage = "正在处理上一项操作，稍后再重新翻译"
            return
        }

        let finalSegments = segments.filter(\.isFinal)
        guard !finalSegments.isEmpty else {
            translationStatusMessage = "等待稳定转写段落"
            updateCurrentSession(status: currentSession.status)
            persistCurrentSession()
            return
        }

        for index in segments.indices where segments[index].isFinal {
            segments[index].translatedText = nil
            segments[index].translationStatus = .translating
            segments[index].updatedAt = .now
            translateSegment(segments[index], in: currentSession.id)
        }

        translationStatusMessage = "正在重新翻译全部段落"
        updateCurrentSession(status: currentSession.status)
        persistCurrentSession()
    }

    func deleteSession(id: UUID) {
        guard canStartNewSession else {
            statusMessage = "录音结束后才能删除记录"
            return
        }

        do {
            try sessionStore?.deleteSession(id: id)
        } catch {
            errorMessage = "删除记录失败：\(error.localizedDescription)"
            return
        }

        recentSessions.removeAll { $0.id == id }

        if currentSession.id == id {
            resetToEmptySession()
        } else {
            refreshRecentSessions(excluding: currentSession.id)
        }

        statusMessage = "记录已删除"
    }

    func deleteAllSessions() {
        guard canStartNewSession else {
            statusMessage = "录音结束后才能清空记录"
            return
        }

        do {
            try sessionStore?.deleteAllSessions()
        } catch {
            errorMessage = "清空记录失败：\(error.localizedDescription)"
            return
        }

        recentSessions.removeAll()
        resetToEmptySession()
        statusMessage = "已清空本地记录"
    }

    func startNewSession() {
        guard canStartNewSession else {
            statusMessage = "录音结束后才能新建记录"
            return
        }

        archiveCurrentSessionIfNeeded()
        cancelTranslationTasks()
        elapsedSeconds = 0
        segments.removeAll()
        volatileText = ""
        errorMessage = nil
        statusMessage = "准备开始实时记录"
        translationStatusMessage = "等待稳定转写段落"
        currentSession = NoteSession(title: Self.makeSessionTitle())
        currentSession.targetLanguageName = targetLanguage.displayName
        focusedSegmentID = nil
        persistCurrentSession()
    }

    func selectSession(id: UUID) {
        guard canSelectSession else {
            statusMessage = "录音结束后才能切换历史记录"
            return
        }
        guard id != currentSession.id else {
            return
        }

        archiveCurrentSessionIfNeeded()

        let allSessions = ([currentSession] + recentSessions).reduce(into: [UUID: NoteSession]()) { sessionsByID, session in
            sessionsByID[session.id] = session
        }

        guard let selectedSession = allSessions[id] else {
            errorMessage = "未找到这条历史记录。"
            return
        }

        cancelTranslationTasks()
        currentSession = selectedSession
        elapsedSeconds = selectedSession.duration
        volatileText = ""
        focusedSegmentID = nil
        errorMessage = nil
        statusMessage = selectedSession.segmentCount > 0 ? "已载入历史记录" : "准备开始实时记录"
        translationStatusMessage = "已载入保存的译文"
        targetLanguage = TranslationLanguage.allCases.first { $0.displayName == selectedSession.targetLanguageName } ?? .english

        do {
            segments = try sessionStore?.loadSegments(for: id) ?? []
            refreshRecentSessions(excluding: id)
        } catch {
            segments = []
            errorMessage = "读取历史记录失败：\(error.localizedDescription)"
            refreshRecentSessions(excluding: id)
        }
    }

    func makeExportPackage(
        format: SessionExportFormat,
        options: SessionExportOptions
    ) throws -> SessionExportPackage {
        return try exportBuilder.build(
            session: currentSession,
            segments: segments,
            format: format,
            options: options
        )
    }

    func exportCurrentSession(
        format: SessionExportFormat,
        options: SessionExportOptions,
        destinationURL: URL
    ) {
        do {
            let package = try makeExportPackage(format: format, options: options)
            let data = Data(package.contents.utf8)
            try data.write(to: destinationURL, options: .atomic)
            exportStatusMessage = "已导出到 \(destinationURL.lastPathComponent)"
        } catch let exportError as SessionExportError {
            exportStatusMessage = exportError.localizedDescription
        } catch {
            exportStatusMessage = SessionExportError.writeFailed(error.localizedDescription).localizedDescription
        }
    }

    private func translateSegment(_ segment: TranscriptSegment, in sessionID: UUID) {
        let targetLanguage = targetLanguage.localeLanguage
        translationTasks[segment.id]?.cancel()

        if translationService is SystemTranslationService {
            let request = SystemTranslationRequest(
                segmentID: segment.id,
                sessionID: sessionID,
                sourceText: segment.text,
                sourceLanguage: Self.sourceLanguage,
                targetLanguage: targetLanguage
            )
            enqueueSystemTranslationRequest(request)
            return
        }

        translationTasks[segment.id] = Task { [weak self] in
            guard let self else { return }

            do {
                let translatedText = try await translationService.translate(
                    segment.text,
                    from: Self.sourceLanguage,
                    to: targetLanguage
                )

                updateSegment(
                    id: segment.id,
                    translatedText: translatedText,
                    status: .translated,
                    in: sessionID
                )
                translationStatusMessage = "译文已更新"
            } catch {
                applyTranslationFailure(error, to: segment.id, in: sessionID)
            }

            translationTasks[segment.id] = nil
        }
    }

    func processPendingSystemTranslations(with session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
        } catch {
            if let request = pendingSystemTranslationRequests.first {
                acceptSystemTranslationFailure(error, for: request)
            }
            systemTranslationConfiguration = nil
            return
        }

        while let request = pendingSystemTranslationRequests.first {
            do {
                let response = try await session.translate(request.sourceText)
                acceptSystemTranslation(response.targetText, for: request)
            } catch {
                acceptSystemTranslationFailure(error, for: request)
            }
        }

        systemTranslationConfiguration = nil
    }

    func acceptSystemTranslation(_ translatedText: String, for request: SystemTranslationRequest) {
        updateSegment(
            id: request.segmentID,
            translatedText: translatedText,
            status: .translated,
            in: request.sessionID
        )
        translationStatusMessage = "译文已更新"
        clearSystemTranslationRequest(request)
    }

    func acceptSystemTranslationFailure(_ error: any Error, for request: SystemTranslationRequest) {
        applyTranslationFailure(error, to: request.segmentID, in: request.sessionID)
        clearSystemTranslationRequest(request)
    }

    func clearSystemTranslationRequest(_ request: SystemTranslationRequest) {
        pendingSystemTranslationRequests.removeAll { $0.id == request.id }
        if pendingSystemTranslationRequests.isEmpty {
            systemTranslationConfiguration = nil
        }
    }

    private func enqueueSystemTranslationRequest(_ request: SystemTranslationRequest) {
        pendingSystemTranslationRequests.removeAll { $0.segmentID == request.segmentID && $0.sessionID == request.sessionID }
        pendingSystemTranslationRequests.append(request)

        var configuration = systemTranslationConfiguration ?? TranslationSession.Configuration(
            source: request.sourceLanguage,
            target: request.targetLanguage
        )
        configuration.invalidate()
        systemTranslationConfiguration = configuration
    }

    private func applyTranslationFailure(_ error: any Error, to segmentID: UUID, in sessionID: UUID) {
        let pipelineError = TranslationPipelineError.fromSystemError(error)
        let message = pipelineError.localizedDescription
        let status: TranslationStatus = pipelineError.isAvailabilityIssue ? .unavailable(message) : .failed(message)

        updateSegment(
            id: segmentID,
            translatedText: nil,
            status: status,
            in: sessionID
        )
        translationStatusMessage = message
    }

    private func updateSegment(
        id: UUID,
        translatedText: String?,
        status: TranslationStatus,
        in sessionID: UUID
    ) {
        guard currentSession.id == sessionID else {
            return
        }
        guard let index = segments.firstIndex(where: { $0.id == id }) else {
            return
        }

        segments[index].translatedText = translatedText
        segments[index].translationStatus = status
        segments[index].updatedAt = .now
        updateCurrentSession(status: currentSession.status)
        persistCurrentSession()
    }

    private func ensureMicrophoneAccess() async -> Bool {
        switch PermissionCoordinator.microphoneStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await PermissionCoordinator.requestMicrophoneAccess()
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func cancelTranslationTasks() {
        translationTasks.values.forEach { $0.cancel() }
        translationTasks.removeAll()
        pendingSystemTranslationRequests.removeAll()
        systemTranslationConfiguration = nil
    }

    private func updateCurrentSession(status: NoteSessionStatus) {
        currentSession.duration = elapsedSeconds
        currentSession.status = status
        currentSession.updatedAt = .now
        currentSession.segmentCount = segments.filter(\.isFinal).count
        currentSession.highlightedCount = segments.filter(\.isHighlighted).count
    }

    private func archiveCurrentSessionIfNeeded() {
        updateCurrentSession(status: currentSession.segmentCount > 0 ? currentSession.status : .draft)
        guard currentSession.segmentCount > 0 else {
            return
        }

        recentSessions.removeAll { $0.id == currentSession.id }
        recentSessions.insert(currentSession, at: 0)
        persistCurrentSession()
    }

    private func persistCurrentSession() {
        do {
            try sessionStore?.save(session: currentSession, segments: segments)
        } catch {
            errorMessage = "保存记录失败：\(error.localizedDescription)"
        }
    }

    private func loadPersistedSessions() {
        do {
            let persistedSessions = try sessionStore?.loadSessions() ?? []
            guard let firstSession = persistedSessions.first else {
                return
            }

            currentSession = firstSession
            recentSessions = Array(persistedSessions.dropFirst())
            segments = try sessionStore?.loadSegments(for: firstSession.id) ?? []
            targetLanguage = TranslationLanguage.allCases.first { $0.displayName == firstSession.targetLanguageName } ?? .english
            elapsedSeconds = firstSession.duration
            statusMessage = firstSession.segmentCount > 0 ? "已载入历史记录" : "准备开始实时记录"
            translationStatusMessage = firstSession.segmentCount > 0 ? "已载入保存的译文" : "等待稳定转写段落"
        } catch {
            errorMessage = "读取历史记录失败：\(error.localizedDescription)"
        }
    }

    private func refreshRecentSessions(excluding sessionID: UUID) {
        do {
            let persistedSessions = try sessionStore?.loadSessions() ?? recentSessions
            let refreshedSessions = persistedSessions.filter { $0.id != sessionID }
            recentSessions = refreshedSessions.isEmpty ? recentSessions.filter { $0.id != sessionID } : refreshedSessions
        } catch {
            recentSessions.removeAll { $0.id == sessionID }
        }
    }

    private func resetToEmptySession() {
        cancelTranslationTasks()
        elapsedSeconds = 0
        segments.removeAll()
        volatileText = ""
        focusedSegmentID = nil
        errorMessage = nil
        translationStatusMessage = "等待稳定转写段落"
        currentSession = NoteSession(title: Self.makeSessionTitle(), targetLanguageName: targetLanguage.displayName)
    }

    private static func makeSessionTitle(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return "\(formatter.string(from: date)) 实时记录"
    }
}

struct SystemTranslationRequest: Identifiable, Equatable {
    let id = UUID()
    let segmentID: UUID
    let sessionID: UUID
    let sourceText: String
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language

    var configuration: TranslationSession.Configuration {
        TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
    }
}
