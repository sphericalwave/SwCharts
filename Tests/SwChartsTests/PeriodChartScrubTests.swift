import SwiftUI
import XCTest
@testable import SwCharts

/// Press-and-drag reading: nothing is selected until the short hold
/// completes, and the hold is brief enough to feel immediate.
final class PeriodChartScrubTests: XCTestCase {

    func testHoldInProgressSelectsNothing() {
        XCTAssertFalse(PeriodChartView.scrubActive(.first(true)))
        XCTAssertFalse(PeriodChartView.scrubActive(.first(false)))
        XCTAssertNil(PeriodChartView.scrubX(.first(true)))
        XCTAssertNil(PeriodChartView.scrubX(.first(false)))
    }

    func testHoldCompleteBeforeMovingScrubsWithoutLocation() {
        XCTAssertTrue(PeriodChartView.scrubActive(.second(true, nil)))
        XCTAssertNil(PeriodChartView.scrubX(.second(true, nil)))
    }

    func testFailedHoldIsNotScrubbing() {
        XCTAssertFalse(PeriodChartView.scrubActive(.second(false, nil)))
        XCTAssertNil(PeriodChartView.scrubX(.second(false, nil)))
    }

    func testHoldIsShortAndSlopIsSmall() {
        XCTAssertGreaterThan(PeriodChartView.scrubHoldDuration, 0)
        XCTAssertLessThanOrEqual(PeriodChartView.scrubHoldDuration, 0.25)
        XCTAssertLessThanOrEqual(PeriodChartView.scrubHoldSlop, 12)
    }
}
