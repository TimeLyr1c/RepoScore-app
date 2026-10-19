import XCTest
import UIKit

final class ImportFlowTests: XCTestCase {
    @MainActor
    func testSystemFilePickerCanOpenAndCancelWithoutImporting() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REPOSCORE_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        let importButton = app.buttons["importScore"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()

        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["导入失败"].exists)
    }

    @MainActor
    func testImportedCopyReadsAllPagesAndSurvivesRelaunchWithoutSource() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REPOSCORE_UI_TEST_SESSION"] = UUID().uuidString
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = renderer.pdfData { context in
            for page in 1...3 {
                context.beginPage()
                ("RepoScore — Page \(page)" as NSString).draw(at: CGPoint(x: 50, y: 50))
            }
        }
        app.launchEnvironment["REPOSCORE_UI_TEST_PDF"] = data.base64EncodedString()
        app.launch()
        let score = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI-Test-Score")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        score.tap()
        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        assertPage("1 / 3", in: app)
        app.swipeLeft()
        assertPage("2 / 3", in: app)
        app.swipeRight()
        assertPage("1 / 3", in: app)
        let previous = app.buttons["上一页"]
        let next = app.buttons["下一页"]
        XCTAssertFalse(previous.isEnabled)
        next.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertTrue(NSPredicate(format: "label == %@", "2 / 3").evaluate(with: indicator))
        next.tap()
        assertPage("3 / 3", in: app)
        XCTAssertFalse(next.isEnabled)
        previous.tap()
        assertPage("2 / 3", in: app)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Single-page PDF reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // The seed source was deleted by the app; relaunch without any seed bytes.
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "REPOSCORE_UI_TEST_PDF")
        app.launch()
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        score.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        assertPage("1 / 3", in: app)
    }

    @MainActor
    func testInvalidPDFShowsFailureWithoutLibraryRecord() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REPOSCORE_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["REPOSCORE_UI_TEST_PDF"] = Data("invalid PDF".utf8).base64EncodedString()
        app.launch()
        let alert = app.alerts["导入失败"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["曲库为空"].exists)
    }
    @MainActor
    private func assertPage(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let indicator = app.staticTexts["pageIndicator"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: indicator)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed,
                       "Expected page \(label)", file: file, line: line)
    }

    @MainActor
    private func seededApp(pages: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["REPOSCORE_UI_TEST_SESSION"] = UUID().uuidString
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = renderer.pdfData { context in
            for page in 1...pages {
                context.beginPage()
                ("RepoScore — Page \(page)" as NSString).draw(at: CGPoint(x: 50, y: 50))
            }
        }
        app.launchEnvironment["REPOSCORE_UI_TEST_PDF"] = data.base64EncodedString()
        app.launch()
        return app
    }

    @MainActor
    private func createFolder(_ name: String, in app: XCUIApplication) {
        app.buttons["createFolder"].tap()
        let alert = app.alerts["新建文件夹"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["保存"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNestedFoldersRenameAndMovingScoreSurviveRelaunch() {
        let app = seededApp(pages: 2)
        let score = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI-Test-Score")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        createFolder("Practice", in: app)
        app.buttons["Practice"].tap()
        createFolder("Piano", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Practice"].press(forDuration: 1)
        app.buttons["重命名"].tap()
        let editor = app.alerts["重命名文件夹"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let field = editor.textFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Practice".count) + "Rehearsal")
        editor.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["Rehearsal"].waitForExistence(timeout: 5))
        score.press(forDuration: 1)
        app.buttons["移动"].tap()
        XCTAssertTrue(app.navigationBars["曲库根目录"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'destination-' AND label == 'Rehearsal'")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'destination-' AND label == 'Piano'")).firstMatch.tap()
        app.buttons["confirmMove"].tap()
        XCTAssertFalse(score.exists)

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "REPOSCORE_UI_TEST_PDF")
        app.launch()
        XCTAssertTrue(app.buttons["Rehearsal"].waitForExistence(timeout: 10))
        app.buttons["Rehearsal"].tap()
        app.buttons["Piano"].tap()
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        score.press(forDuration: 1)
        app.buttons["移动"].tap()
        app.buttons["confirmMove"].tap() // Root is a valid destination.
        XCTAssertTrue(app.staticTexts["文件夹为空"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(score.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDoublePagesCoverSwitchEdgeTapAndRotationKeepPosition() {
        let app = seededApp(pages: 5)
        defer { XCUIDevice.shared.orientation = .portrait }
        let score = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI-Test-Score")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        score.tap()
        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        app.buttons["下一页"].tap()
        app.buttons["下一页"].tap() // Physical page 3.
        app.buttons["readingSettings"].tap()
        app.buttons["双页"].tap()
        app.buttons["完成"].tap()
        assertPage("2–3 / 5", in: app)
        app.buttons["readingSettings"].tap()
        let cover = app.switches["separateCover"]
        XCTAssertEqual(cover.value as? String, "1")
        cover.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(cover.value as? String, "0")
        app.buttons["完成"].tap()
        assertPage("3–4 / 5", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        assertPage("3–4 / 5", in: app)
        app.buttons["下一页"].tap()
        assertPage("5 / 5", in: app)
        XCTAssertFalse(app.buttons["下一页"].isEnabled)
        let spread = app.otherElements["pdfSpread"]
        // Tap the left outer edge of the actual reader, not the navigation bar.
        spread.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        assertPage("3–4 / 5", in: app)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Double-page landscape reader"
        attachment.lifetime = .keepAlways
        add(attachment)
        spread.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        assertPage("5 / 5", in: app)
        app.swipeRight()
        assertPage("3–4 / 5", in: app)
        app.buttons["readingSettings"].tap()
        app.buttons["单页"].tap()
        app.buttons["完成"].tap()
        assertPage("3 / 5", in: app)
        XCUIDevice.shared.orientation = .portrait
        assertPage("3 / 5", in: app)
    }

    @MainActor
    func testDuplicateFolderShowsErrorAndPreservesExistingFolder() {
        let app = XCUIApplication()
        app.launchEnvironment["REPOSCORE_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["createFolder"].waitForExistence(timeout: 10))
        createFolder("Practice", in: app)
        app.buttons["createFolder"].tap()
        let editor = app.alerts["新建文件夹"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.textFields.firstMatch.tap()
        editor.textFields.firstMatch.typeText("practice")
        editor.buttons["保存"].tap()
        let error = app.alerts["无法修改曲库"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        error.buttons["好"].tap()
        XCTAssertTrue(app.buttons["Practice"].exists)
        XCTAssertFalse(app.buttons["practice"].exists)
    }

}
