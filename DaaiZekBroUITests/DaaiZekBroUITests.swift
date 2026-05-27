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

            XCTAssertEqual(todayPlanStartButton(in: app).exists, testCase.showsStart)
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
    func testHomeBrowseModeShowsSliceOneSectionsAndHistoryEntry() throws {
        let app = launchUITestApp(fixture: "today-plan-ready")

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(todayPlanCardBody(in: app).exists)
        XCTAssertTrue(app.staticTexts["训练模板"].exists)
        XCTAssertTrue(waitForElement(identifier: "home-template-edit-button", in: app).exists)
        XCTAssertTrue(app.staticTexts["最近训练"].exists)
        XCTAssertTrue(waitForElement(identifier: "home-recent-empty-state", in: app).exists)
        XCTAssertTrue(app.buttons["设置"].exists)
        XCTAssertFalse(app.navigationBars["训练模板"].exists)

        waitForElement(identifier: "home-recent-history-link", in: app).tap()

        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeRecentTrainingShowsLatestValidCompletedRecords() throws {
        let app = launchUITestApp(fixture: "recent-training-mixed")

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElement(identifier: "home-recent-row-0", in: app).exists)
        XCTAssertTrue(waitForElement(identifier: "home-recent-row-1", in: app).exists)
        XCTAssertTrue(waitForElement(identifier: "home-recent-row-2", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-recent-row-3"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-recent-empty-state"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["2025-12-31 (三) · Push A · 1组 · 1h 2m"].exists)
        XCTAssertTrue(app.staticTexts["2025-12-30 (二) · Pull A · 1组 · 54m"].exists)
        XCTAssertTrue(app.staticTexts["2025-12-29 (一) · Legs A · 1组 · 48m"].exists)
        XCTAssertFalse(app.staticTexts["2025-12-28 (日) · Push A · 1组 · 45m"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Pull A (进行中)")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0组")).firstMatch.exists)

        waitForElement(identifier: "home-recent-row-0", in: app).tap()

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(waitForElement(identifier: "home-recent-history-link", in: app).isHittable)
        XCTAssertFalse(app.navigationBars["训练历史"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["history-detail-weight-unit-picker"].firstMatch.exists)
    }

    @MainActor
    func testHomeAndSettingsHistoryEntriesOpenSameHistoryPage() throws {
        let homeApp = launchUITestApp(fixture: "recent-training-mixed")

        XCTAssertTrue(homeScreen(in: homeApp).waitForExistence(timeout: 5))
        waitForElement(identifier: "home-recent-history-link", in: homeApp).tap()
        XCTAssertTrue(homeApp.navigationBars["训练历史"].waitForExistence(timeout: 5))
        homeApp.terminate()

        let settingsApp = launchUITestApp(fixture: "recent-training-mixed")

        XCTAssertTrue(homeScreen(in: settingsApp).waitForExistence(timeout: 5))
        XCTAssertTrue(settingsApp.buttons["设置"].waitForExistence(timeout: 5))
        settingsApp.buttons["设置"].tap()
        let settingsHistoryEntry = settingsApp.buttons["workout-history-button"]
        XCTAssertTrue(settingsHistoryEntry.waitForExistence(timeout: 5))
        settingsHistoryEntry.tap()
        XCTAssertTrue(settingsApp.navigationBars["训练历史"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeTemplateEditModeMovesActionsToNavigationBar() throws {
        let app = launchUITestApp(fixture: "today-plan-no-cycle")

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElement(identifier: "home-template-carousel", in: app).exists)
        waitForElement(identifier: "home-template-edit-button", in: app).tap()

        XCTAssertTrue(waitForElement(identifier: "template-editing-list", in: app).exists)
        XCTAssertTrue(app.buttons["template-add-button"].exists)
        XCTAssertTrue(app.buttons["完成"].exists)
        XCTAssertFalse(app.buttons["设置"].exists)

        app.buttons["完成"].tap()

        XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["设置"].exists)
        XCTAssertTrue(waitForElement(identifier: "home-template-carousel", in: app).exists)
    }

    @MainActor
    func testTemplateCarouselShowsCardsAndCanSwipeThroughTemplates() throws {
        let app = launchUITestApp(fixture: "today-plan-no-cycle")

        let carousel = waitForElement(identifier: "home-template-carousel", in: app)
        XCTAssertTrue(waitForElement(identifier: "template-Push A", in: app).isHittable)

        let lastSeedTemplate = app.descendants(matching: .any)["template-Legs B"].firstMatch
        for _ in 0..<4 where lastSeedTemplate.isHittable == false {
            carousel.swipeLeft()
        }

        XCTAssertTrue(lastSeedTemplate.waitForExistence(timeout: 2))
        XCTAssertTrue(lastSeedTemplate.isHittable)
    }

    @MainActor
    func testTemplateCarouselCardStartsWorkout() throws {
        let app = launchUITestApp(fixture: "today-plan-no-cycle")

        waitForElement(identifier: "template-Push A", in: app).tap()

        XCTAssertTrue(currentWorkoutScreen(in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeletingOnlyTemplateShowsEmptyStateWithoutCarousel() throws {
        let app = launchUITestApp(fixture: "templates-single")

        let onlyTemplate = waitForElement(identifier: "template-Push A", in: app)
        onlyTemplate.press(forDuration: 1)
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 5))
        app.buttons["删除"].tap()

        XCTAssertTrue(waitForElement(identifier: "home-template-empty-state", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-template-carousel"].firstMatch.exists)
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
        assertTemplateConflictChoice("取消", expectedWorkoutName: nil)
        assertTemplateConflictChoice("继续当前训练", expectedWorkoutName: "Push A")
        assertTemplateConflictChoice("结束当前并新建", expectedWorkoutName: "Pull A")
        assertTemplateConflictChoice("丢弃当前并新建", expectedWorkoutName: "Pull A")
    }

    @MainActor
    func testTrainingScheduleDayDetailOverrideSyncsHomeAndSchedule() throws {
        let app = launchUITestApp(fixture: "training-day-override-ready")

        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 5))

        openTodayScheduleDayDetail(in: app)
        setTodayOverrideToPullA(in: app)
        XCTAssertTrue(app.staticTexts["Pull A"].waitForExistence(timeout: 5))

        returnToTrainingSchedule(in: app)
        XCTAssertTrue(app.staticTexts["Pull A"].waitForExistence(timeout: 5))

        returnHome(in: app)
        assertTodayPlanCardContains("Pull A", in: app)
        XCTAssertTrue(todayPlanStartButton(in: app).waitForExistence(timeout: 5))

        openTodayScheduleDayDetail(in: app)
        waitForElement(identifier: "training-day-override-rest-button", in: app).tap()
        XCTAssertTrue(app.staticTexts["休息"].waitForExistence(timeout: 5))

        returnToTrainingSchedule(in: app)
        XCTAssertTrue(app.staticTexts["休息"].waitForExistence(timeout: 5))

        returnHome(in: app)
        XCTAssertTrue(app.staticTexts["今日：休息"].waitForExistence(timeout: 5))
        XCTAssertFalse(todayPlanStartButton(in: app).exists)

        openTodayScheduleDayDetail(in: app)
        waitForElement(identifier: "training-day-reset-override-button", in: app).tap()
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 5))

        returnToTrainingSchedule(in: app)
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 5))

        returnHome(in: app)
        assertTodayPlanCardContains("Push A", in: app)
        XCTAssertTrue(todayPlanStartButton(in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testTrainingScheduleCompletedDayDetailLocksOverrides() throws {
        let app = launchUITestApp(fixture: "training-day-override-completed")

        openTodayScheduleDayDetail(in: app)

        XCTAssertTrue(waitForElement(identifier: "training-day-override-locked-message", in: app).exists)
        assertUnavailable(identifier: "training-day-override-template-picker", in: app)
        assertUnavailable(identifier: "training-day-override-template-button", in: app)
        assertUnavailable(identifier: "training-day-override-rest-button", in: app)
        assertUnavailable(identifier: "training-day-reset-override-button", in: app)
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
        file: StaticString,
        line: UInt
    ) {
        XCTAssertTrue(currentWorkoutScreen(in: app).waitForExistence(timeout: 5), file: file, line: line)

        if app.navigationBars[templateName].waitForExistence(timeout: 1) {
            return
        }

        XCTAssertTrue(app.staticTexts[templateName].waitForExistence(timeout: 1), file: file, line: line)
    }

    @MainActor
    private func assertTemplateConflictChoice(
        _ buttonTitle: String,
        expectedWorkoutName: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = launchUITestApp(fixture: "template-open-session-no-cycle")
        tapTemplate(named: "Pull A", in: app, file: file, line: line)

        XCTAssertTrue(
            app.staticTexts["已有未结束的训练"].waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        if buttonTitle == "取消" {
            dismissTemplateConflictDialog(in: app, file: file, line: line)
        } else {
            XCTAssertTrue(app.buttons[buttonTitle].waitForExistence(timeout: 5), file: file, line: line)
            app.buttons[buttonTitle].tap()
        }

        if let expectedWorkoutName {
            assertCurrentWorkout(named: expectedWorkoutName, in: app, file: file, line: line)
        } else {
            XCTAssertTrue(homeScreen(in: app).waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertFalse(currentWorkoutScreen(in: app).waitForExistence(timeout: 1), file: file, line: line)
        }

        app.terminate()
    }

    @MainActor
    private func tapTemplate(
        named templateName: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
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

    @MainActor
    private func dismissTemplateConflictDialog(
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) {
        let cancelButton = app.buttons["取消"].firstMatch
        if cancelButton.waitForExistence(timeout: 1) {
            cancelButton.tap()
            return
        }

        let dismissRegion = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5), file: file, line: line)
        dismissRegion.tap()
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

    private func returnToTrainingSchedule(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if app.descendants(matching: .any)["training-schedule-day-detail"].firstMatch.exists {
            tapBackButton(in: app, file: file, line: line)
        }

        XCTAssertTrue(app.scrollViews["training-schedule-screen"].waitForExistence(timeout: 5), file: file, line: line)
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

    private func assertUnavailable(
        identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertFalse(element.exists && element.isEnabled, "\(identifier) should be unavailable", file: file, line: line)
    }
}
