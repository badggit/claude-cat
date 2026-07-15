import XCTest
import ClaudeCatCore

final class ScaffoldTests: XCTestCase {
    // Smoke test proving the test target links against ClaudeCatCore on Linux.
    func testVersionIsNonEmpty() {
        XCTAssertFalse(ClaudeCatVersion.current.isEmpty)
    }
}
