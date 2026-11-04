import XCTest

final class StackbarUITests: XCTestCase {
  @MainActor
  func testAppLaunches() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.exists)
  }
}
