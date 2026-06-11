import SwiftUI
import SwiftData

@main
struct LiveNoteApp: App {
    @State private var appModel = LiveNoteAppModel()
    private let modelContainer: ModelContainer

    init() {
        do {
            let isUITestMode = ProcessInfo.processInfo.arguments.contains("-LiveNoteUITestMode")
            modelContainer = try NoteSessionStore.makeModelContainer(inMemory: isUITestMode)
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: appModel.recordingViewModel(modelContainer: modelContainer))
                .frame(minWidth: 1080, minHeight: 720)
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-LiveNoteUITestMode") {
                        NSApplication.shared.activate()
                    }
                    appModel.activateMenuBar()
                    appModel.activateCursorCompanion()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .modelContainer(modelContainer)
    }
}

@MainActor
final class LiveNoteAppModel {
    private var recordingViewModel: RecordingViewModel?
    private var menuBarController: MenuBarStatusController?
    private var cursorCompanionController: CursorCompanionController?

    init() {
    }

    func recordingViewModel(modelContainer: ModelContainer) -> RecordingViewModel {
        if let recordingViewModel {
            return recordingViewModel
        }

        let sessionStore = NoteSessionStore(modelContext: modelContainer.mainContext)
        UITestFixture.seedIfNeeded(sessionStore: sessionStore)
        let recordingViewModel = RecordingViewModel(sessionStore: sessionStore)
        self.recordingViewModel = recordingViewModel
        self.menuBarController = MenuBarStatusController(viewModel: recordingViewModel)
        return recordingViewModel
    }

    func activateMenuBar() {
        menuBarController?.install()
    }

    func activateCursorCompanion() {
        if cursorCompanionController == nil {
            let controller = CursorCompanionController()
            controller.install()
            cursorCompanionController = controller
        }
    }
}
