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
    func testContainerFailureShowsDiagnosticScreenWithoutHome() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-dz-ui-testing",
            "-dz-force-container-failure",
        ]
        app.launch()

        let failureScreen = app.descendants(matching: .any)["model-container-failure-screen"].firstMatch
        XCTAssertTrue(failureScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["无法打开本地数据"].exists)

        let diagnostic = app.descendants(matching: .any)["model-container-failure-diagnostic"].firstMatch
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5))
        XCTAssertTrue(diagnostic.label.contains("Forced ModelContainer failure"))
        XCTAssertFalse(app.descendants(matching: .any)["home-browsing-screen"].firstMatch.exists)
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
        let app = launchUITestApp(fixture: "today-plan-ready")

        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["上次完成 · 12 月 30 日"].exists)
        XCTAssertTrue(todayPlanStartButton(in: app).exists)
        XCTAssertFalse(app.buttons["continue-workout-card"].exists)
    }

    @MainActor
    func testTodayPlanCardBodyNavigatesToTrainingScheduleAndDayDetail() throws {
        let app = launchUITestApp(fixture: "today-plan-ready")

        XCTAssertTrue(todayPlanCardBody(in: app).waitForExistence(timeout: 5))
        todayPlanCardBody(in: app).tap()

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5))
        tapTodayScheduleRow(in: app)
        XCTAssertTrue(waitForElement(identifier: "training-schedule-day-detail", in: app).exists)
    }

    @MainActor
    func testStartTodayPlanCompletesAndSyncsHomeAndSchedule() throws {
        let app = launchUITestApp(fixture: "today-plan-ready")

        XCTAssertTrue(todayPlanStartButton(in: app).waitForExistence(timeout: 5))
        todayPlanStartButton(in: app).tap()

        XCTAssertTrue(app.staticTexts["本次训练 · SESSION"].waitForExistence(timeout: 5))
        app.buttons["结束训练"].tap()

        XCTAssertTrue(app.staticTexts["✓ 已完成"].waitForExistence(timeout: 5))
        XCTAssertFalse(todayPlanStartButton(in: app).exists)

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
    func testHomeRecentTrainingShowsLatestValidCompletedRecords() throws {
        let app = launchUITestApp(fixture: "recent-training-mixed")

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElement(identifier: "home-recent-row-0", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-recent-empty-state"].firstMatch.exists)

        waitForElement(identifier: "home-recent-history-link", in: app).tap()
        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateCarouselCardStartsWorkout() throws {
        let app = launchUITestApp(fixture: "today-plan-no-cycle")

        waitForElement(identifier: "template-Push A", in: app).tap()

        XCTAssertTrue(currentWorkoutScreen(in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreatingTemplateFromEmptyStateReturnsToEditMode() throws {
        let app = launchUITestApp(fixture: "templates-empty")

        XCTAssertTrue(waitForElement(identifier: "home-template-empty-state", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-template-carousel"].firstMatch.exists)

        waitForElement(identifier: "home-template-edit-button", in: app).tap()
        waitForElement(identifier: "template-add-button", in: app).tap()

        let nameField = app.textFields["模板名称"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Custom Upper")
        app.buttons["保存"].tap()

        XCTAssertTrue(waitForElement(identifier: "template-editing-list", in: app).exists)
        XCTAssertTrue(waitForElement(identifier: "template-edit-Custom Upper", in: app).exists)
    }

    @MainActor
    func testTemplateConflictDialogOptionsRouteCorrectly() throws {
        let app = launchUITestApp(fixture: "template-open-session-no-cycle")
        tapTemplate(named: "Pull A", in: app)

        XCTAssertTrue(app.staticTexts["已有未结束的训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["结束当前并新建"].waitForExistence(timeout: 5))
        app.buttons["结束当前并新建"].tap()

        assertCurrentWorkout(named: "Pull A", in: app)
    }

    @MainActor
    func testOverrideToPullThenStartFromHomeCompletesAndSyncsHomeAndSchedule() throws {
        let app = launchUITestApp(fixture: "training-day-override-ready")

        openTodayScheduleDayDetail(in: app)
        setTodayOverrideToPullA(in: app)
        returnHome(in: app)

        assertTodayPlanCardContains("Pull A", in: app)
        XCTAssertTrue(todayPlanStartButton(in: app).waitForExistence(timeout: 5))
        todayPlanStartButton(in: app).tap()

        XCTAssertTrue(
            app.navigationBars["Pull A"].waitForExistence(timeout: 3)
                || app.staticTexts["Pull A"].waitForExistence(timeout: 3)
        )
        app.buttons["结束训练"].tap()

        XCTAssertTrue(app.staticTexts["✓ 已完成"].waitForExistence(timeout: 5))
        XCTAssertFalse(todayPlanStartButton(in: app).exists)

        todayPlanCardBody(in: app).tap()

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pull A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["✓ 已完成"].exists)
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
        let identifiedElement = app.descendants(matching: .any)["today-plan-card-body"].firstMatch
        if identifiedElement.exists {
            return identifiedElement
        }

        let labelledCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "今日计划卡")
        ).firstMatch
        if labelledCard.exists {
            return labelledCard
        }

        return app.staticTexts["今日计划"].firstMatch
    }

    private func todayPlanStartButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedElement = app.descendants(matching: .any)["today-plan-start-button"].firstMatch
        if identifiedElement.exists {
            return identifiedElement
        }

        return app.buttons["开始训练"].firstMatch
    }

    private func homeScreen(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home-browsing-screen"].firstMatch
    }

    private func currentWorkoutScreen(in app: XCUIApplication) -> XCUIElement {
        app.buttons["结束训练"].firstMatch
    }

    @MainActor
    private func assertCurrentWorkout(
        named templateName: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(currentWorkoutScreen(in: app).waitForExistence(timeout: 5), file: file, line: line)

        if app.navigationBars[templateName].waitForExistence(timeout: 1) {
            return
        }

        XCTAssertTrue(app.staticTexts[templateName].waitForExistence(timeout: 1), file: file, line: line)
    }

    @MainActor
    private func tapTemplate(
        named templateName: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let template = app.descendants(matching: .any)["template-\(templateName)"].firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 5), file: file, line: line)

        if template.isHittable == false {
            let carousel = waitForElement(identifier: "home-template-carousel", in: app, file: file, line: line)
            for _ in 0..<4 where template.isHittable == false {
                carousel.swipeLeft()
            }
        }

        XCTAssertTrue(template.isHittable, file: file, line: line)
        template.tap()
    }

    private func openTodayScheduleDayDetail(in app: XCUIApplication) {
        if app.scrollViews["training-schedule-screen"].exists == false {
            openTrainingSchedule(in: app)
        }

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5))
        tapTodayScheduleRow(in: app)
        XCTAssertTrue(waitForElement(identifier: "training-schedule-day-detail", in: app).exists)
    }

    private func tapTodayScheduleRow(in app: XCUIApplication) {
        let identifiedRow = app.descendants(matching: .any)["training-schedule-day-2026-01-01"].firstMatch
        if identifiedRow.waitForExistence(timeout: 1) {
            identifiedRow.tap()
            return
        }

        let weekList = waitForElement(identifier: "training-schedule-week-list", in: app)
        weekList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }

    private func setTodayOverrideToPullA(in app: XCUIApplication) {
        waitForElement(identifier: "training-day-override-template-button", in: app).tap()
        XCTAssertTrue(waitForElement(identifier: "training-day-override-template-picker", in: app).exists)
        waitForElement(identifier: "training-day-template-Pull A", in: app).tap()
    }

    private func openTrainingSchedule(in app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        waitForElement(identifier: "training-schedule-entry", in: app).tap()
    }

    private func returnHome(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if homeScreen(in: app).waitForExistence(timeout: 1) {
            return
        }

        for _ in 0..<4 {
            tapBackButton(in: app, file: file, line: line)
            if homeScreen(in: app).waitForExistence(timeout: 2) {
                return
            }
        }

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5), file: file, line: line)
    }

    private func tapBackButton(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let screenMidX = app.frame.midX
        let backButton = app.navigationBars.buttons.allElementsBoundByIndex.first { button in
            button.exists && button.isHittable && button.frame.midX < screenMidX
        }

        XCTAssertNotNil(backButton, "Expected a left-side navigation back button", file: file, line: line)
        backButton?.tap()
    }

    @discardableResult
    private func waitForElement(
        identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(identifier)", file: file, line: line)

        return element
    }

    private func assertTodayPlanCardContains(
        _ text: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let card = todayPlanCardBody(in: app)
        guard card.waitForExistence(timeout: 2) else {
            XCTAssertTrue(
                app.staticTexts[text].waitForExistence(timeout: 5),
                "Today plan should show \(text)",
                file: file,
                line: line
            )
            return
        }

        let cardText = card.descendants(matching: .staticText)[text].firstMatch
        XCTAssertTrue(
            card.label.contains(text) || cardText.waitForExistence(timeout: 2),
            "Today plan card should show \(text). Current label: \(card.label)",
            file: file,
            line: line
        )
    }

}
