//
//  FinanceUITests.swift
//  FinanceUITests
//
//  Created by Ismael Pérez on 11/02/2026.
//

import XCTest

final class FinanceUITests: XCTestCase {

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
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCalendarSwipeChangesExactlyOneMonth() throws {
        let app = XCUIApplication()
        app.launch()

        if app.alerts.buttons["No permitir"].exists {
            app.alerts.buttons["No permitir"].tap()
        }
        if app.alerts.buttons["Aceptar"].exists {
            app.alerts.buttons["Aceptar"].tap()
        }
        app.tabBars.buttons["Calendario"].tap()

        let monthNames = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
        let monthPattern = "^(Enero|Febrero|Marzo|Abril|Mayo|Junio|Julio|Agosto|Septiembre|Octubre|Noviembre|Diciembre) de [0-9]{4}$"

        func visibleMonth() -> String? {
            let heading = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", monthPattern)).firstMatch
            return heading.exists ? heading.label : nil
        }

        func nextMonth(after label: String, direction: Int) -> String? {
            let parts = label.components(separatedBy: " de ")
            guard parts.count == 2,
                  let index = monthNames.firstIndex(of: parts[0]),
                  let year = Int(parts[1]) else { return nil }
            let nextIndex = index + direction
            let nextYear = year + (nextIndex < 0 ? -1 : nextIndex >= 12 ? 1 : 0)
            return "\(monthNames[(nextIndex + 12) % 12]) de \(nextYear)"
        }

        XCTAssertNotNil(visibleMonth(), "No se encontró la cabecera del calendario")

        for direction in [1, 1, 1, -1, -1, -1] {
            guard let before = visibleMonth(), let expected = nextMonth(after: before, direction: direction) else {
                XCTFail("No se pudo leer el mes visible")
                return
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: direction == 1 ? 0.80 : 0.20, dy: 0.40))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: direction == 1 ? 0.20 : 0.80, dy: 0.40))
            start.press(forDuration: 0.01, thenDragTo: end)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            XCTAssertEqual(visibleMonth(), expected, "Un deslizamiento desde \(before) debe mostrar \(expected)")
        }
    }
}
