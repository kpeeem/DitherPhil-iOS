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
        let render = app.buttons["render-file"]
        XCTAssertTrue(render.waitForExistence(timeout: 6))
        XCTAssertTrue(render.isHittable)
        XCTAssertGreaterThanOrEqual(render.frame.height, 44)
        let export = XCTAttachment(screenshot: app.screenshot())
        export.name = "DitherPhil export"
        export.lifetime = .keepAlways
        add(export)
        render.tap()
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
}
