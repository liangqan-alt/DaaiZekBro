//
//  DaaiZekBroUITests.swift
//  DaaiZekBroUITests
//
//  Created by liangqan on 2026/5/20.
//

import XCTest

final class DaaiZekBroUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSettingsTrainingScheduleEntryNavigatesToSchedulePage() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let entry = app.buttons["training-schedule-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayPlanCardStates() throws {
        let cases: [(fixture: String, requiredTexts: [String], showsStart: Bool)] = [
            ("today-plan-ready", ["Push A", "上次完成 · 12 月 30 日"], true),
            ("today-plan-completed", ["Push A", "✓ 已完成"], false),
            ("today-plan-offplan", ["Push A", "今日已有其他训练记录"], true),
            ("today-plan-rest", ["今日：休息"], false),
            ("today-plan-rest-workout", ["今日：休息 · 已有训练记录", "计划外训练"], false),
            ("today-plan-invalid", ["计划已失效"], false),
        ]

        for testCase in cases {
            let app = launchUITestApp(fixture: testCase.fixture)
            XCTAssertTrue(app.staticTexts[testCase.requiredTexts[0]].waitForExistence(timeout: 5))

            for text in testCase.requiredTexts {
                XCTAssertTrue(app.staticTexts[text].exists, "Missing \(text) in \(testCase.fixture)")
            }

            XCTAssertEqual(app.buttons["开始训练"].exists, testCase.showsStart)
            XCTAssertFalse(app.buttons["continue-workout-card"].exists)
            app.terminate()
        }

        let noCycleApp = launchUITestApp(fixture: "today-plan-no-cycle")
        XCTAssertFalse(noCycleApp.staticTexts["今日计划"].waitForExistence(timeout: 1))
        noCycleApp.terminate()
    }

    @MainActor
    func testTodayPlanCardBodyNavigatesToTrainingSchedule() throws {
        let app = launchUITestApp(fixture: "today-plan-ready")

        XCTAssertTrue(todayPlanCardBody(in: app).waitForExistence(timeout: 5))
        todayPlanCardBody(in: app).tap()

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartTodayPlanCompletesAndSyncsHomeAndSchedule() throws {
        let app = launchUITestApp(fixture: "today-plan-ready")

        XCTAssertTrue(app.buttons["开始训练"].waitForExistence(timeout: 5))
        app.buttons["开始训练"].tap()

        XCTAssertTrue(app.staticTexts["本次训练 · SESSION"].waitForExistence(timeout: 5))
        app.buttons["结束训练"].tap()

        XCTAssertTrue(app.staticTexts["✓ 已完成"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["开始训练"].exists)

        todayPlanCardBody(in: app).tap()

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["✓ 已完成"].exists)
    }

    @MainActor
    func testOpenSessionShowsContinueCardAndHidesTodayPlanCard() throws {
        let app = launchUITestApp(fixture: "today-plan-open-session")

        XCTAssertTrue(app.buttons["continue-workout-card"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["今日计划"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func launchUITestApp(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-dz-ui-testing",
            "-dz-ui-fixture",
            fixture,
            "-dz-now",
            "2026-01-01T12:00:00+08:00",
        ]
        app.launch()

        return app
    }

    private func todayPlanCardBody(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["今日计划"].firstMatch
    }
}
