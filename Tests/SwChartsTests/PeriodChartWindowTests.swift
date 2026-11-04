import XCTest
@testable import SwCharts

final class PeriodChartWindowTests: XCTestCase {

    private func bucket(_ day: Int, _ value: Double?) -> PeriodBucket {
        let start = Date(timeIntervalSince1970: Double(day) * 86_400)
        return PeriodBucket(start: start, end: start.addingTimeInterval(86_400), value: value, isPartial: false)
    }

    func testTrimDropsLeadingEmptyBuckets() {
        let buckets = [bucket(0, nil), bucket(1, nil), bucket(2, 3), bucket(3, nil), bucket(4, 5)]
        let trimmed = PeriodChartView.trimmingLeadingEmpty(buckets)
        XCTAssertEqual(trimmed.map(\.value), [3, nil, 5])
    }

    func testTrimKeepsAllEmptyWindowUnchanged() {
        let buckets = [bucket(0, nil), bucket(1, nil)]
        XCTAssertEqual(PeriodChartView.trimmingLeadingEmpty(buckets), buckets)
    }

    func testTrimLeavesWindowStartingWithDataUnchanged() {
        let buckets = [bucket(0, 1), bucket(1, nil)]
        XCTAssertEqual(PeriodChartView.trimmingLeadingEmpty(buckets), buckets)
    }

    func testBucketCountGivesFourteenDayWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let buckets = PeriodBucketer().buckets(for: [], period: .day, aggregation: .sum,
                                               now: now, bucketCount: 14)
        XCTAssertEqual(buckets.count, 14)
    }
}
