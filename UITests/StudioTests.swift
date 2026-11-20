import XCTest

final class StudioTests: XCTestCase {
    @MainActor
    func testSampleEditingAndExport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let compare = app.buttons["compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["PREVIEW"].exists)
        let initial = app.screenshot()
        let screenshot = XCTAttachment(screenshot: initial)
        screenshot.name = "DitherPhil editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["collapse"].tap()
        XCTAssertFalse(app.buttons["algorithm"].exists)
        app.buttons["collapse"].tap()
        app.buttons["palette"].tap()
        let colors = XCTAttachment(screenshot: app.screenshot())
        colors.name = "DitherPhil palettes"
        colors.lifetime = .keepAlways
        add(colors)
        app.buttons["Amber"].tap()
        app.buttons["library"].tap()
        let name = app.textFields["Preset name"]
        name.tap()
        name.typeText("Studio test")
        let save = app.buttons["Save preset"]
        if save.exists { save.tap() } else { app.buttons["Update preset"].tap() }
        app.buttons["Studio test"].tap()

        compare.tap()
        XCTAssertEqual(compare.value as? String, "Original")

        app.buttons["Color"].tap()
        let exposure = app.sliders["Exposure"]
        XCTAssertTrue(exposure.exists)
        exposure.adjust(toNormalizedSliderPosition: 0.67)
        XCTAssertEqual(compare.value as? String, "Preview")
        app.buttons["Dither"].tap()
        let cellSize = app.sliders["Cell size"]
        XCTAssertGreaterThanOrEqual(cellSize.frame.height, 44)
        XCTAssertEqual(cellSize.value as? String, "4 px")
        cellSize.adjust(toNormalizedSliderPosition: 0.65)
        XCTAssertNotEqual(cellSize.value as? String, "4 px")
        let algorithm = app.buttons["algorithm"]
        XCTAssertGreaterThanOrEqual(algorithm.frame.height, 44)
        XCTAssertGreaterThanOrEqual(compare.frame.height, 44)
        algorithm.tap()
        app.buttons["Atkinson"].tap()

        let output = app.buttons["Output"]
        XCTAssertGreaterThanOrEqual(output.frame.height, 44)
        output.tap()
        app.buttons["resolution"].tap()
        app.buttons["640 px"].tap()
        XCTAssertEqual(app.staticTexts["preview-dimensions"].value as? String, "640 × 640")

        app.buttons["export"].tap()
        let savePhoto = app.buttons["save-photos"]
        XCTAssertTrue(savePhoto.waitForExistence(timeout: 20))
        XCTAssertTrue(savePhoto.isHittable)
        let export = XCTAttachment(screenshot: app.screenshot())
        export.name = "DitherPhil export"
        export.lifetime = .keepAlways
        add(export)
        savePhoto.tap()
        let saved = app.buttons.matching(NSPredicate(format: "label == %@", "Saved to Photos")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["share-file"].waitForExistence(timeout: 20))

        app.buttons["Done"].tap()
        app.buttons["Dither"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let inspectorOnRight = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            algorithm.frame.minX >= compare.frame.maxX
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [inspectorOnRight], timeout: 5), .completed)
    }

    @MainActor
    func testChooseInterfaceLanguage() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["library"].tap()
        app.buttons["studio-language"].tap()
        app.buttons["日本語"].tap()
        let done = app.buttons["完了"]
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        done.tap()
        XCTAssertTrue(app.buttons["色"].exists)
        app.buttons["library"].tap()
        app.buttons["studio-language"].tap()
        app.buttons["システム設定"].tap()
        app.buttons["Done"].tap()
    }

}
