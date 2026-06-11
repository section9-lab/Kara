import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

struct ContentView: View {
    let viewModel: RecordingViewModel

    @State private var isExportPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            TranslationWorkspaceView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                StatusCapsule(
                    recordingState: viewModel.recordingState,
                    elapsedSeconds: viewModel.elapsedSeconds,
                    sourceLanguage: viewModel.sourceLanguageName,
                    targetLanguage: viewModel.targetLanguageName,
                    processingMode: "本机"
                )
                .accessibilityIdentifier("status-capsule")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.toggleRecording()
                } label: {
                    Label(
                        viewModel.recordingState.recordToggleTitle,
                        systemImage: viewModel.recordingState.recordToggleSystemImage
                    )
                }
                .disabled(!viewModel.canToggleRecording)
                .accessibilityIdentifier("record-toggle-button")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.stopRecording()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(!viewModel.canStopRecording)
                .accessibilityIdentifier("record-stop-button")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isExportPresented = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.recordingState == .processing)
                .accessibilityIdentifier("export-button")
            }
        }
        .sheet(isPresented: $isExportPresented) {
            ExportSheetView(viewModel: viewModel)
        }
        .translationTask(viewModel.systemTranslationConfiguration) { session in
            await viewModel.processPendingSystemTranslations(with: session)
        }
    }
}

private extension RecordingState {
    var recordToggleTitle: String {
        switch self {
        case .ready:
            "开始"
        case .recording:
            "暂停"
        case .paused:
            "继续"
        case .processing:
            "处理中"
        }
    }

    var recordToggleSystemImage: String {
        switch self {
        case .ready:
            "record.circle"
        case .recording:
            "pause.fill"
        case .paused:
            "play.fill"
        case .processing:
            "hourglass"
        }
    }
}

private struct SidebarView: View {
    let viewModel: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    viewModel.startNewSession()
                } label: {
                    Label("新建记录", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStartNewSession)
                .accessibilityIdentifier("new-session-button")

                Spacer()

                Button {
                    viewModel.deleteAllSessions()
                } label: {
                    Label("清空记录", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canStartNewSession || (viewModel.recentSessions.isEmpty && viewModel.currentSession.segmentCount == 0))
                .help("清空本地记录")
                .accessibilityIdentifier("clear-sessions-button")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SidebarSectionHeader(title: "当前")
                    SessionRow(session: viewModel.currentSession, isCurrent: true) {
                        viewModel.selectSession(id: viewModel.currentSession.id)
                    }

                    SidebarSectionHeader(title: "最近")
                        .padding(.top, 10)

                    if viewModel.recentSessions.isEmpty {
                        RecentSessionsEmptyState()
                            .accessibilityIdentifier("recent-sessions-empty-state")
                    } else {
                        ForEach(viewModel.recentSessions) { session in
                            SessionRow(
                                session: session,
                                isCurrent: false,
                                onSelect: {
                                    viewModel.selectSession(id: session.id)
                                },
                                onDelete: {
                                    viewModel.deleteSession(id: session.id)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .accessibilityIdentifier("session-sidebar-list")
        }
        .navigationTitle("LiveNote")
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

private struct SessionRow: View {
    let session: NoteSession
    let isCurrent: Bool
    var onSelect: () -> Void
    var onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: isCurrent ? "record.circle" : "doc.text")
                            .foregroundStyle(isCurrent ? .red : .secondary)

                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                            .accessibilityIdentifier(sessionTitleAccessibilityIdentifier)

                        if isCurrent {
                            Text("当前")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.12), in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text(session.status.label)
                        Text(durationText)
                        Text("\(session.segmentCount) 段")

                        if session.highlightedCount > 0 {
                            Label("\(session.highlightedCount)", systemImage: "star.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, shouldShowDeleteButton ? 38 : 10)
                .padding(.vertical, 9)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)

            if shouldShowDeleteButton {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("删除记录", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("删除记录")
                .padding(.trailing, 8)
                .accessibilityIdentifier(deleteAccessibilityIdentifier)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private var shouldShowDeleteButton: Bool {
        !isCurrent && isHovering && onDelete != nil
    }

    private var durationText: String {
        let minutes = Int(session.duration) / 60
        let seconds = Int(session.duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var accessibilityIdentifier: String {
        if isCurrent {
            return "current-session-row"
        }

        if session.title == "产品评审记录" {
            return "recent-session-row-product-review"
        }

        return "recent-session-row-\(session.id.uuidString)"
    }

    private var accessibilityLabel: String {
        let prefix = isCurrent ? "当前会话" : "最近会话"
        return "\(prefix) \(session.title) \(session.status.label) \(durationText) \(session.segmentCount) 段"
    }

    private var deleteAccessibilityIdentifier: String {
        if session.title == "产品评审记录" {
            return "delete-session-product-review"
        }

        return "delete-session-\(session.id.uuidString)"
    }

    private var sessionTitleAccessibilityIdentifier: String {
        if isCurrent {
            return "current-session-title"
        }

        if session.title == "产品评审记录" {
            return "recent-session-title-product-review"
        }

        return "recent-session-title-\(session.id.uuidString)"
    }

    private var rowBackground: some ShapeStyle {
        isCurrent ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)
    }
}

private struct RecentSessionsEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("暂无历史记录", systemImage: "tray")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text("完成一次实时记录后会出现在这里。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("暂无历史记录，完成一次实时记录后会出现在这里。")
        .accessibilityIdentifier("recent-sessions-empty-state")
    }
}

private struct TranslationWorkspaceView: View {
    let viewModel: RecordingViewModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            translationToolbar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if viewModel.segments.isEmpty && viewModel.volatileText.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity, minHeight: 480)
                        } else {
                            ForEach(displayedSegments) { segment in
                                TranslationManuscriptPair(
                                    segment: segment,
                                    targetLanguageName: viewModel.targetLanguageName,
                                    isFocused: viewModel.focusedSegmentID == segment.id,
                                    matchesSearch: segmentMatchesSearch(segment),
                                    onRetranslate: { viewModel.retranslateSegment(id: segment.id) }
                                )
                                .id(segment.id)
                            }

                            if !viewModel.volatileText.isEmpty, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                TranslationManuscriptPair(
                                    segment: TranscriptSegment(
                                        text: viewModel.volatileText,
                                        isFinal: false,
                                        startTime: viewModel.elapsedSeconds,
                                        duration: 0
                                    ),
                                    targetLanguageName: viewModel.targetLanguageName,
                                    isFocused: false,
                                    matchesSearch: false
                                )
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
                .onChange(of: viewModel.focusedSegmentID) { _, segmentID in
                    guard let segmentID else { return }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(segmentID, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("实时翻译")
        .accessibilityIdentifier("translation-panel")
    }

    private var translationToolbar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("实时翻译")
                        .font(.headline)

                    Text(viewModel.translationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("目标语言", selection: Binding(
                    get: { viewModel.targetLanguage },
                    set: { viewModel.updateTargetLanguage($0) }
                )) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .accessibilityIdentifier("target-language-picker")

                Button {
                    viewModel.retranslateAllSegments()
                } label: {
                    Label("全部重译", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.segments.filter(\.isFinal).isEmpty || !viewModel.canEditSegments)
                .accessibilityIdentifier("retranslate-all-button")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索原文或译文", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        viewModel.focusFirstSegment(matching: searchText)
                    }
                    .accessibilityIdentifier("transcript-search-field")

                Text(searchStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    viewModel.focusFirstSegment(matching: searchText)
                } label: {
                    Label("定位", systemImage: "scope")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("定位第一个匹配段落")
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("transcript-search-focus-button")

                Button {
                    searchText = ""
                    viewModel.focusSegment(id: nil)
                } label: {
                    Label("清除", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("清除搜索")
                .disabled(searchText.isEmpty && viewModel.focusedSegmentID == nil)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcript-search-bar")
    }

    private var searchStatusText: String {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return "\(viewModel.segments.filter(\.isFinal).count) 行"
        }

        return "\(matchingSegments.count) 个匹配"
    }

    private var matchingSegments: [TranscriptSegment] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        return viewModel.segments.filter { segment in
            segment.text.localizedCaseInsensitiveContains(trimmedQuery)
            || (segment.translatedText?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private var displayedSegments: [TranscriptSegment] {
        let finalSegments = viewModel.segments.filter(\.isFinal)
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return finalSegments
        }

        return finalSegments.filter(segmentMatchesSearch)
    }

    private func segmentMatchesSearch(_ segment: TranscriptSegment) -> Bool {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return false
        }

        return segment.text.localizedCaseInsensitiveContains(trimmedQuery)
        || (segment.translatedText?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: viewModel.recordingState == .recording ? "waveform" : "mic.circle")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(viewModel.recordingState == .recording ? .red : .secondary)

            VStack(spacing: 8) {
                Text(viewModel.statusMessage)
                    .font(.title2.weight(.semibold))

                Text("\(viewModel.sourceLanguageName) → \(viewModel.targetLanguageName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TranslationManuscriptPair: View {
    let segment: TranscriptSegment
    let targetLanguageName: String
    let isFocused: Bool
    let matchesSearch: Bool
    var onRetranslate: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 46, alignment: .leading)

                Text(segment.text)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .accessibilityLabel("原文：\(segment.text)")

                Spacer(minLength: 12)

                retranslateButton
            }

            Text(translationText)
                .font(.system(size: 18, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(translationForegroundStyle)
                .textSelection(.enabled)
                .padding(.leading, 56)
                .accessibilityLabel("\(targetLanguageName)：\(translationText)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 19)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isFocused {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var retranslateButton: some View {
        if segment.isFinal {
            Button {
                onRetranslate?()
            } label: {
                Label("重译", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("重译")
            .disabled(onRetranslate == nil)
            .opacity(isHovering || isFocused ? 1 : 0.42)
            .accessibilityIdentifier("retranslate-segment-\(segment.id.uuidString)")
        }
    }

    private var translationForegroundStyle: Color {
        if !segment.isFinal || segment.translatedText == nil {
            return .secondary
        }

        return .primary
    }

    private var timeText: String {
        let minutes = Int(segment.startTime) / 60
        let seconds = Int(segment.startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var translationText: String {
        if let translatedText = segment.translatedText, !translatedText.isEmpty {
            return translatedText
        }

        return switch segment.translationStatus {
        case .notRequested:
            "等待稳定转写后翻译为\(targetLanguageName)"
        case .translating:
            "正在生成\(targetLanguageName)译文..."
        case .translated:
            "译文为空"
        case .unavailable(let message), .failed(let message):
            message
        }
    }

    private var rowBackground: some ShapeStyle {
        if isFocused {
            return Color.accentColor.opacity(0.08)
        }

        if matchesSearch {
            return Color.yellow.opacity(0.10)
        }

        return Color.clear
    }
}

private struct TranscriptLinePair: View {
    let segment: TranscriptSegment
    let sourceLanguageName: String
    let targetLanguageName: String
    let isFocused: Bool
    let matchesSearch: Bool
    var onUpdateText: ((String) -> Void)?
    var onToggleHighlight: (() -> Void)?

    @State private var isEditing = false
    @State private var draftText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .trailing, spacing: 5) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if segment.isHighlighted {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("重点")
                }
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 6) {
                if isEditing {
                    TextEditor(text: $draftText)
                        .font(.body)
                        .frame(minHeight: 76)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                        .onSubmit {
                            commitEdit()
                        }

                    HStack(spacing: 8) {
                        Button("保存") {
                            commitEdit()
                        }
                        .keyboardShortcut(.return, modifiers: .command)

                        Button("取消") {
                            draftText = segment.text
                            isEditing = false
                        }
                    }
                    .controlSize(.small)
                } else {
                    Text(segment.text)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(2)
                        .foregroundStyle(segment.isFinal ? .primary : .secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("\(sourceLanguageName)：\(segment.text)")
                }

                Text(translationText)
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(2)
                    .foregroundStyle(translationForegroundStyle)
                    .textSelection(.enabled)
                    .accessibilityLabel("\(targetLanguageName)：\(translationText)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                if segment.isEdited {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("已编辑")
                }

                if segment.isFinal {
                    Button {
                        onToggleHighlight?()
                    } label: {
                        Image(systemName: segment.isHighlighted ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                    .help(segment.isHighlighted ? "取消重点" : "标记重点")
                    .accessibilityLabel(segment.isHighlighted ? "取消重点" : "标记重点")

                    Button {
                        draftText = segment.text
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(isEditing ? "完成编辑" : "编辑这一行")
                    .accessibilityLabel(isEditing ? "完成编辑" : "编辑这一行")
                }
            }
            .frame(width: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isFocused {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .onAppear {
            if draftText.isEmpty {
                draftText = segment.text
            }
        }
    }

    private var translationForegroundStyle: Color {
        if !segment.isFinal || segment.translatedText == nil {
            return .secondary
        }

        return .primary
    }

    private var timeText: String {
        let minutes = Int(segment.startTime) / 60
        let seconds = Int(segment.startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var translationText: String {
        if let translatedText = segment.translatedText, !translatedText.isEmpty {
            return translatedText
        }

        return switch segment.translationStatus {
        case .notRequested:
            "等待稳定转写后翻译为\(targetLanguageName)"
        case .translating:
            "正在生成\(targetLanguageName)译文..."
        case .translated:
            "译文为空"
        case .unavailable(let message), .failed(let message):
            message
        }
    }

    private var rowBackground: some ShapeStyle {
        if isFocused {
            return Color.accentColor.opacity(0.08)
        }

        if matchesSearch {
            return Color.yellow.opacity(0.10)
        }

        return segment.isHighlighted ? Color.yellow.opacity(0.08) : Color.clear
    }

    private func commitEdit() {
        onUpdateText?(draftText)
        isEditing = false
    }
}

private struct ExportSheetView: View {
    let viewModel: RecordingViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var format: SessionExportFormat = .markdown
    @State private var options = SessionExportOptions()
    @State private var localStatusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("导出记录")
                    .font(.title3.weight(.semibold))

                Spacer()

                Picker("格式", selection: $format) {
                    ForEach(SessionExportFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityIdentifier("export-format-picker")
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("原文", isOn: $options.includesTranscript)
                Toggle("译文", isOn: $options.includesTranslation)
            }
            .toggleStyle(.checkbox)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusText == viewModel.exportStatusMessage ? Color.secondary : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("export-status-message")

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    export()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasSelectedContent)
                .accessibilityIdentifier("export-confirm-button")
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear {
            localStatusMessage = ""
        }
    }

    private var hasSelectedContent: Bool {
        options.includesTranscript || options.includesTranslation
    }

    private var statusText: String {
        localStatusMessage.isEmpty ? viewModel.exportStatusMessage : localStatusMessage
    }

    private func export() {
        do {
            let package = try viewModel.makeExportPackage(format: format, options: options)

            if let destinationURL = uiTestExportDestinationURL {
                viewModel.exportCurrentSession(format: format, options: options, destinationURL: destinationURL)
                dismiss()
                return
            }

            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = package.filename
            panel.allowedContentTypes = [format.contentType]

            guard panel.runModal() == .OK, let url = panel.url else {
                localStatusMessage = "已取消导出"
                return
            }

            viewModel.exportCurrentSession(format: format, options: options, destinationURL: url)
            dismiss()
        } catch let exportError as SessionExportError {
            localStatusMessage = exportError.localizedDescription
        } catch {
            localStatusMessage = error.localizedDescription
        }
    }

    private var uiTestExportDestinationURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-LiveNoteUITestMode"),
              let pathIndex = arguments.firstIndex(of: "-LiveNoteExportPath"),
              arguments.indices.contains(arguments.index(after: pathIndex)) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[arguments.index(after: pathIndex)])
    }
}

private extension SessionExportFormat {
    var contentType: UTType {
        switch self {
        case .markdown:
            UTType(filenameExtension: "md") ?? .plainText
        case .txt:
            .plainText
        }
    }
}
