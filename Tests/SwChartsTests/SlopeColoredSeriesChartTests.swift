import XCTest
@testable import SwCharts

final class SlopeColoredSeriesChartTests: XCTestCase {

    private func points(_ values: [Double]) -> [SeriesPoint] {
        values.enumerated().map { index, value in
            SeriesPoint(x: Double(index + 1), value: value)
        }
    }

    // MARK: - segments(from:)

    func testFewerThanTwoPointsHasNoSegments() {
        XCTAssertTrue(SlopeColoredSeriesChart.segments(from: []).isEmpty)
        XCTAssertTrue(SlopeColoredSeriesChart.segments(from: points([5])).isEmpty)
    }

    func testSegmentCountIsOneFewerThanPoints() {
        XCTAssertEqual(SlopeColoredSeriesChart.segments(from: points([1, 2, 3, 4])).count, 3)
    }

    func testSegmentsSpanConsecutivePointsInOrder() {
        let input = points([10, 20, 30])
        let segments = SlopeColoredSeriesChart.segments(from: input)
        XCTAssertEqual(segments.map(\.id), [0, 1])
        XCTAssertEqual(segments.first?.start, input[0])
        XCTAssertEqual(segments.first?.end, input[1])
        XCTAssertEqual(segments.last?.end, input[2])
    }

    // MARK: - Trend direction

    func testRisingAndFallingSegments() {
        let segments = SlopeColoredSeriesChart.segments(from: points([1, 5, 2]))
        XCTAssertTrue(segments[0].isRising)
        XCTAssertFalse(segments[1].isRising)
    }

    func testFlatSegmentCountsAsRising() {
        let segments = SlopeColoredSeriesChart.segments(from: points([3, 3]))
        XCTAssertTrue(segments[0].isRising)
    }
}
