import XCTest

final class LiveNoteLaunchUITests: XCTestCase {
    @MainActor
    func testAppLaunchesToRecordingWorkspace() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState",
            "YES",
            "-LiveNoteUITestMode"
        ]
        app.launch()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["准备开始实时记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["record-toggle-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["就绪"].exists)
        XCTAssertTrue(element(identifier: "status-capsule", in: app).exists)
        XCTAssertTrue(element(identifier: "translation-panel", in: app).exists)
        XCTAssertTrue(app.buttons["new-session-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["current-session-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recent-session-row-product-review"].exists)
        XCTAssertTrue(element(containing: "当前会话", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletedSessionSupportsExportAndClear() throws {
        let exportDirectory = URL(fileURLWithPath: "/Users/jackwang/Library/Containers/com.livenote.LiveNote/Data/tmp")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exportURL = exportDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try? FileManager.default.removeItem(at: exportURL)

        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState",
            "YES",
            "-LiveNoteUITestMode",
            "-LiveNoteSeedCompletedSession",
            "-LiveNoteExportPath",
            exportURL.path
        ]
        app.launch()
        app.activate()

        XCTAssertTrue(element(containing: "产品评审记录", in: app).waitForExistence(timeout: 5))

        app.buttons["export-button"].click()
        XCTAssertTrue(app.buttons["export-confirm-button"].waitForExistence(timeout: 5))
        app.buttons["export-confirm-button"].click()

        let contents = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("产品评审记录"))
        XCTAssertTrue(contents.contains("确认下周三前完成导出验收"))

        XCTAssertTrue(app.buttons["clear-sessions-button"].waitForExistence(timeout: 5))
        app.buttons["clear-sessions-button"].click()
        XCTAssertTrue(app.staticTexts["已清空本地记录"].waitForExistence(timeout: 5))

        try? FileManager.default.removeItem(at: exportURL)
    }

    @MainActor
    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }
}
