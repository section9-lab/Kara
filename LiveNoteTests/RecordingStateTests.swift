import XCTest
@testable import LiveNote

final class RecordingStateTests: XCTestCase {
    func testRecordingStateLabels() {
        XCTAssertEqual(RecordingState.ready.label, "就绪")
        XCTAssertEqual(RecordingState.recording.label, "录音中")
        XCTAssertEqual(RecordingState.paused.label, "已暂停")
        XCTAssertEqual(RecordingState.processing.label, "整理中")
    }

    func testRecordingStateMenuBarIcons() {
        XCTAssertEqual(RecordingState.ready.menuBarSystemImage, "record.circle")
        XCTAssertEqual(RecordingState.recording.menuBarSystemImage, "record.circle.fill")
        XCTAssertEqual(RecordingState.paused.menuBarSystemImage, "pause.circle.fill")
        XCTAssertEqual(RecordingState.processing.menuBarSystemImage, "arrow.triangle.2.circlepath.circle")
    }

    func testMenuBarElapsedTimeUsesTwoDigitLargestUnit() {
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 0), "00s")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 9), "09s")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 59), "59s")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 60), "01m")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 3_599), "59m")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 3_600), "01h")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 86_399), "23h")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 86_400), "01d")
        XCTAssertEqual(MenuBarElapsedTimeFormatter.compactUnitString(from: 8_640_000), "99d")
    }
}
