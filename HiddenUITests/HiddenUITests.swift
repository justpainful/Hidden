import UIKit
import XCTest

/// Walks the whole app and photographs every screen.
///
/// The failures that matter here are visual — a screen letterboxed, a control clipped, a
/// surface that renders empty — and compile-only CI cannot see any of them. The tour runs
/// against the deterministic mock library (`-UITestMockLibrary`): `simctl` cannot mark
/// seeded media as hidden, so a real simulator library can never exercise the Hidden flows.
///
/// A missed tap does not stop the tour, but it does fail the run: each step records where it
/// actually landed and the assertions are reported together at the end, so every screenshot
/// after a misstep still exists.
final class HiddenUITests: XCTestCase {

    private var app: XCUIApplication!
    private var missteps: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestMockLibrary", "-skipLock", "-mockCount", "300"]
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: Tours

    func testCaptureEverySurface() throws {
        app.launch()
        settle()
        tour(prefix: "")
        finish()
    }

    /// The same app at the largest accessibility text size, where fixed-height rows clip and
    /// buttons fall off screens that cannot scroll.
    func testLargestTextSize() throws {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        settle()
        capture("ax-01-inbox")
        safeTap(app.buttons["Library"].firstMatch)
        capture("ax-02-library")
        safeTap(app.buttons["Shuffle"].firstMatch)
        capture("ax-03-shuffle")
        safeTap(app.buttons["Insights"].firstMatch)
        capture("ax-04-insights")
        XCTAssertTrue(app.state == .runningForeground, "The app did not survive the large-type tour")
    }

    /// Arabic, right-to-left. The layout must mirror; concatenation and hardcoded left/right
    /// assumptions show up here first.
    func testArabicRightToLeft() throws {
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        settle()
        capture("ar-01-inbox")
        // Tab titles are localized, so reach tabs by position within the tab bar.
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 5) {
            let buttons = tabBar.buttons.allElementsBoundByIndex
            if buttons.count >= 2 { buttons[1].tap(); settle() }
            capture("ar-02-library")
            if buttons.count >= 5 { buttons[4].tap(); settle() }
            capture("ar-03-insights")
        }
        XCTAssertTrue(app.state == .runningForeground, "The app did not survive the RTL tour")
    }

    // MARK: The main tour

    private func tour(prefix: String) {
        capture("\(prefix)01-inbox", expecting: "Inbox")

        // Settings, from the inbox toolbar.
        safeTap(app.buttons["Settings"].firstMatch)
        capture("\(prefix)02-settings")
        openRow("About the Hidden Album")
        capture("\(prefix)03-about")
        dismissAnySheet()
        returnToTabs()

        // Review, when the inbox offers it.
        if safeTap(app.buttons["Review All"].firstMatch) {
            capture("\(prefix)04-review")
            safeTap(app.buttons["Close"].firstMatch)
        }
        returnToTabs()

        // Library.
        safeTap(app.buttons["Library"].firstMatch)
        capture("\(prefix)05-library", expecting: "Library")
        app.swipeUp()
        settle()
        capture("\(prefix)05b-library-scrolled")
        app.swipeDown()
        settle()

        safeTap(app.buttons["Filters"].firstMatch)
        capture("\(prefix)06-filters")
        dismissAnySheet()

        safeTap(app.buttons["asset.tile"].firstMatch)
        capture("\(prefix)07-viewer")
        safeTap(app.buttons["Info"].firstMatch)
        capture("\(prefix)08-info")
        dismissAnySheet()
        safeTap(app.buttons["Close"].firstMatch)
        returnToTabs()

        // Discover.
        safeTap(app.buttons["Discover"].firstMatch)
        capture("\(prefix)09-discover", expecting: "Discover")
        safeTap(app.cells.firstMatch)
        capture("\(prefix)10-collection")
        returnToTabs()

        // Shuffle.
        safeTap(app.buttons["Shuffle"].firstMatch)
        capture("\(prefix)11-shuffle", expecting: "Shuffle")
        if safeTap(app.buttons["Start Shuffle"].firstMatch) {
            sleep(2)
            capture("\(prefix)12-shuffle-session")
            // Controls fade behind the tap-to-toggle; wake them before closing.
            if !safeTap(app.buttons["Close"].firstMatch) {
                app.tap()
                settle()
                safeTap(app.buttons["Close"].firstMatch)
            }
        }
        returnToTabs()

        // Insights.
        safeTap(app.buttons["Insights"].firstMatch)
        capture("\(prefix)13-insights", expecting: "Insights")
        app.swipeUp()
        settle()
        capture("\(prefix)13b-insights-scrolled")

        returnToTabs()
        safeTap(app.buttons["Inbox"].firstMatch)
        capture("\(prefix)14-inbox-again", expecting: "Inbox")
    }

    private func finish() {
        XCTAssertTrue(app.state == .runningForeground, "The app did not survive the tour")
        if !missteps.isEmpty {
            XCTFail("""
                The tour did not reach \(missteps.count) of its surfaces. Each line is a \
                screenshot that shows the wrong screen:
                \(missteps.joined(separator: "\n"))
                """)
        }
    }

    // MARK: Steps

    private var tabBarIsReachable: Bool {
        app.buttons["Inbox"].firstMatch.isHittable
    }

    /// Escape whatever is covering the tabs: sheets first, then full-screen covers, then
    /// pushed screens.
    private func returnToTabs() {
        for _ in 0..<4 {
            if tabBarIsReachable { break }
            dismissAnySheet()
            if tabBarIsReachable { break }
            // A full-screen viewer/session: wake the chrome, then close.
            app.tap()
            settle()
            if safeTap(app.buttons["Close"].firstMatch) { continue }
            app.swipeDown()
            settle()
        }
        for _ in 0..<4 {
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            guard back.exists, back.isHittable else { break }
            back.tap()
            settle()
        }
        dismissAnySheet()
    }

    private func dismissAnySheet() {
        for _ in 0..<3 {
            let done = app.buttons["Done"].firstMatch
            guard done.exists, done.isHittable else { return }
            done.tap()
            settle()
        }
    }

    private func openRow(_ label: String) {
        let target = app.buttons[label].firstMatch
        if !safeTap(target, fallback: app.staticTexts[label].firstMatch) {
            safeTap(app.cells.containing(.staticText, identifier: label).firstMatch)
        }
        settle()
    }

    @discardableResult
    private func safeTap(_ element: XCUIElement, fallback: XCUIElement? = nil) -> Bool {
        if element.waitForExistence(timeout: 6), element.isHittable {
            element.tap()
            settle()
            return true
        }
        if let fallback, fallback.exists, fallback.isHittable {
            fallback.tap()
            settle()
            return true
        }
        return false
    }

    private func settle() {
        sleep(2)
    }

    /// Photograph the screen, then check it is the screen the step went looking for. The
    /// screenshot is taken first on purpose: a capture that landed on the wrong screen is the
    /// most useful picture in the artifact.
    private func capture(_ name: String, expecting screen: String? = nil) {
        let attachment = XCTAttachment(image: XCUIScreen.main.screenshot().image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let screen, !app.navigationBars[screen].waitForExistence(timeout: 5) {
            missteps.append("  \(name).png — expected the \(screen) screen, but it shows \(whereAmI())")
        }
    }

    private func whereAmI() -> String {
        let titles = app.navigationBars.allElementsBoundByIndex
            .map(\.identifier)
            .filter { !$0.isEmpty }
        if titles.isEmpty {
            return tabBarIsReachable ? "an untitled screen" : "a full-screen cover or sheet"
        }
        return titles.joined(separator: " › ")
    }
}
