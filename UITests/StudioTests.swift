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

        compare.tap()
        XCTAssertEqual(compare.value as? String, "Original")
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Preview")

        app.buttons["Color"].tap()
        let exposure = app.sliders["Exposure"]
        XCTAssertTrue(exposure.exists)
        exposure.adjust(toNormalizedSliderPosition: 0.67)
        app.buttons["Dither"].tap()
        app.buttons["algorithm"].tap()
        app.buttons["Atkinson"].tap()

        app.buttons["export"].tap()
        let render = app.buttons["render-file"]
        XCTAssertTrue(render.waitForExistence(timeout: 6))
        render.tap()
        XCTAssertTrue(app.buttons["share-file"].waitForExistence(timeout: 20))
    }
}
