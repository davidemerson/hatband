import XCTest

/// Drives the app to pose for the App Store and writes PNGs to the directory
/// named in `HATBAND_SHOTS`. Nothing here asserts anything about correctness;
/// it is a camera, not a test, which is why it has its own scheme and CI never
/// runs it.
///
/// Everything it does, it does through the app's real UI. There is no seeding
/// seam in the shipped code and there should not be one, so the people in the
/// People tab get there the way anyone's would: a card arrives by URL and the
/// review sheet is filled in and saved. That is why the work is split across
/// three test methods, driven in order by `scripts/screenshots.sh` with
/// `simctl openurl` between them.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private var shots: URL {
        get throws {
            let directory = try XCTUnwrap(ProcessInfo.processInfo.environment["HATBAND_SHOTS"],
                                          "set HATBAND_SHOTS to a directory")
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    /// The whole screen at the device's own resolution, which is what App
    /// Store Connect wants: no scaling and no chrome of ours.
    private func shoot(_ name: String) throws {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try png.write(to: try shots.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 15) throws -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "no \(what)")
        element.tap()
        return element
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - 1. Onboarding

    /// The first run. Fill it in as someone would, so the card in every later
    /// screenshot is a card the app actually made and signed.
    func testAOnboards() throws {
        app.launch()
        guard app.staticTexts["Name and address?"].waitForExistence(timeout: 20) else { return }
        try tap(app.buttons["Type it in"], "Type it in")
        try type("Name", "Leopold Bloom")
        try type("Company", "Freeman's Journal")
        try type("Phone, +353 87 123 4567", "+353 87 123 4567")
        try type("Email", "henry.flower@example.ie")
        // The lock defaults on wherever it can, and a screenshot of a locked
        // screen shows none of the app. The feature is the description's to
        // sell; these frames are for what it holds.
        let lock = app.switches["Lock scanned people behind Face ID or passcode"]
        if lock.waitForExistence(timeout: 5), (lock.value as? String) == "1" {
            // The row's centre is its label; the toggle is at the trailing end.
            lock.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(lock.value as? String, "0", "the lock is still on; every tab but Card will be locked")
        try tap(app.buttons["Continue"], "Continue")
        XCTAssertTrue(app.tabBars.buttons["Card"].waitForExistence(timeout: 20), "never reached the tabs")
    }

    // MARK: - 2. Someone's card arrives

    /// `simctl openurl` has just handed the app a card, so activate rather
    /// than launch: launching would terminate the app and lose the review.
    func testBSavesThePendingReview() throws {
        app.activate()
        let place = ProcessInfo.processInfo.environment["HATBAND_PLACE"] ?? ""
        let field = app.textFields["Where (a place or an event)"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), "no review sheet")
        // A coarse fix, so the Where tab has somewhere as well as a name.
        let locating = app.switches.containing(
            NSPredicate(format: "label CONTAINS[c] 'location'")).firstMatch
        if locating.exists {
            if (locating.value as? String) == "0" {
                locating.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            // A fix takes a moment, and saving before it lands writes the
            // meeting with no location at all.
            for _ in 0..<20 where locating.label.contains("Finding") || locating.label.contains("No location") {
                settle(0.5)
            }
        }
        if !place.isEmpty {
            field.tap()
            field.typeText(place)
        }
        try tap(app.buttons["Save"], "Save")
        XCTAssertTrue(app.tabBars.buttons["Card"].waitForExistence(timeout: 20), "review never closed")
    }

    // MARK: - 3. The photographs

    func testCTakesTheScreenshots() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Card"].waitForExistence(timeout: 25), "never reached the tabs")
        settle(2)
        try shoot("01-card")

        try tap(app.tabBars.buttons["People"], "People tab")
        settle()
        try shoot("02-people")

        // The first person, and what the app remembers about meeting them.
        let first = app.collectionViews.buttons.firstMatch
        if first.waitForExistence(timeout: 5) {
            first.tap()
            settle()
            try shoot("03-person")
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
        }

        try tap(app.tabBars.buttons["Where"], "Where tab")
        settle(2.5)
        try shoot("04-where")

        try tap(app.tabBars.buttons["Settings"], "Settings tab")
        settle()
        try shoot("05-settings")

        // The print sheet, over the card: SVG, PNG and a PDF business card.
        try tap(app.tabBars.buttons["Card"], "Card tab")
        settle()
        let printer = app.buttons["Print"]
        if printer.waitForExistence(timeout: 5) {
            printer.tap()
            settle(1.5)
            try shoot("06-print")
        }
    }

    private func type(_ placeholder: String, _ text: String) throws {
        let field = try tap(app.textFields[placeholder], placeholder)
        field.typeText(text)
    }
}
