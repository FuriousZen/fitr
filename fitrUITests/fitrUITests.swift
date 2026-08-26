//
//  fitrUITests.swift
//  fitrUITests
//
//  Created by Ryan Nguyen on 3/29/25.
//

import XCTest

final class fitrUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The app opens on either the login form or, when a session is still
    /// cached on the simulator, the dashboard's tab bar. One of the two must
    /// be present; a blank screen or a crash on launch fails here.
    @MainActor
    func testLaunchShowsLoginOrDashboard() throws {
        let app = XCUIApplication()
        app.launch()

        let emailField = app.textFields["Email"]
        let homeTab = app.tabBars.buttons["Home"]
        let reachedAScreen = emailField.waitForExistence(timeout: 15) || homeTab.waitForExistence(timeout: 5)

        XCTAssertTrue(reachedAScreen, "expected the login form or the dashboard after launch")
        if emailField.exists {
            XCTAssertTrue(app.staticTexts["fitr"].exists)
            XCTAssertTrue(app.buttons["Login"].exists)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
