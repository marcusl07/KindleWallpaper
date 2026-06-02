import XCTest
@testable import KindleWall

final class ScheduleSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "LeafTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testRotationScheduleModeReadsCurrentAndLegacyStoredValues() {
        XCTAssertEqual(RotationScheduleMode.fromStoredValue("manual"), .manual)
        XCTAssertEqual(RotationScheduleMode.fromStoredValue("on_launch"), .onLaunch)
        XCTAssertEqual(RotationScheduleMode.fromStoredValue("every_30_minutes"), .everyInterval)
        XCTAssertEqual(RotationScheduleMode.fromStoredValue(NSNumber(value: 1)), .daily)
        XCTAssertEqual(RotationScheduleMode.fromStoredValue(NSNumber(value: 3)), .everyInterval)
        XCTAssertNil(RotationScheduleMode.fromStoredValue("unknown"))
        XCTAssertNil(RotationScheduleMode.fromStoredValue(NSNumber(value: 99)))
    }

    func testScheduleDefaultsAndClampingPreserveStoredBehavior() {
        XCTAssertEqual(defaults.rotationScheduleMode, .daily)
        XCTAssertEqual(defaults.scheduleDailyHour, 9)
        XCTAssertEqual(defaults.scheduleDailyMinute, 0)
        XCTAssertEqual(defaults.scheduleIntervalMinutes, 30)

        defaults.scheduleDailyHour = -10
        defaults.scheduleDailyMinute = 99
        defaults.scheduleIntervalMinutes = 0

        XCTAssertEqual(defaults.scheduleDailyHour, 0)
        XCTAssertEqual(defaults.scheduleDailyMinute, 59)
        XCTAssertEqual(defaults.scheduleIntervalMinutes, 1)

        defaults.scheduleDailyHour = 40
        defaults.scheduleIntervalMinutes = 24 * 60

        XCTAssertEqual(defaults.scheduleDailyHour, 23)
        XCTAssertEqual(defaults.scheduleIntervalMinutes, (23 * 60) + 59)
    }

    func testLastChangedAtReadsSupportedLegacyFormats() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.lastChangedAt = timestamp
        XCTAssertEqual(defaults.lastChangedAt?.timeIntervalSince1970, timestamp.timeIntervalSince1970)

        defaults.set("1700000001", forKey: "lastChangedAt")
        XCTAssertEqual(defaults.lastChangedAt?.timeIntervalSince1970, 1_700_000_001)

        defaults.set("2024-01-02T03:04:05Z", forKey: "lastChangedAt")
        XCTAssertEqual(defaults.lastChangedAt?.timeIntervalSince1970, 1_704_164_645)

        defaults.lastChangedAt = nil
        XCTAssertNil(defaults.object(forKey: "lastChangedAt"))
    }

    func testCapitalizeHighlightTextReadsBooleansAndLegacyStrings() {
        XCTAssertFalse(defaults.capitalizeHighlightText)

        defaults.set(" yes ", forKey: "capitalizeHighlightText")
        XCTAssertTrue(defaults.capitalizeHighlightText)

        defaults.set("0", forKey: "capitalizeHighlightText")
        XCTAssertFalse(defaults.capitalizeHighlightText)

        defaults.capitalizeHighlightText = true
        XCTAssertTrue(defaults.capitalizeHighlightText)
    }
}
