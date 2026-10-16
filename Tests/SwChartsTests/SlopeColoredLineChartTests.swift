import XCTest
@testable import SwCharts

final class SlopeColoredLineChartTests: XCTestCase {

    private func points(_ values: [Double]) -> [ChartPoint] {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        return values.enumerated().map { index, value in
            ChartPoint(start: reference.addingTimeInterval(Double(index) * 86_400), value: value)
        }
    }

    // MARK: - segments(from:)

    func testFewerThanTwoPointsHasNoSegments() {
        XCTAssertTrue(SlopeColoredLineChart.segments(from: []).isEmpty)
        XCTAssertTrue(SlopeColoredLineChart.segments(from: points([5])).isEmpty)
    }

    func testSegmentCountIsOneFewerThanPoints() {
        XCTAssertEqual(SlopeColoredLineChart.segments(from: points([1, 2, 3, 4])).count, 3)
    }

    func testSegmentsSpanConsecutivePointsInOrder() {
        let input = points([10, 20, 30])
        let segments = SlopeColoredLineChart.segments(from: input)
        XCTAssertEqual(segments.map(\.id), [0, 1])
        XCTAssertEqual(segments.first?.start, input[0])
        XCTAssertEqual(segments.first?.end, input[1])
        XCTAssertEqual(segments.last?.end, input[2])
    }

    // MARK: - Trend direction

    func testRisingAndFallingSegments() {
        let segments = SlopeColoredLineChart.segments(from: points([1, 5, 2]))
        XCTAssertTrue(segments[0].isRising)
        XCTAssertFalse(segments[1].isRising)
    }

    func testFlatSegmentCountsAsRising() {
        let segments = SlopeColoredLineChart.segments(from: points([3, 3]))
        XCTAssertTrue(segments[0].isRising)
    }

    // MARK: - current + projection

    func testCurrentJoinsTheLine() {
        let history = points([1, 2])
        let current = ChartPoint(start: history[1].start.addingTimeInterval(86_400), value: 3)
        XCTAssertEqual(SlopeColoredLineChart.linePoints(history, current: current), history + [current])
        XCTAssertEqual(SlopeColoredLineChart.linePoints(history, current: nil), history)
    }

    func testProjectionAnchorsOnLastLinePoint() {
        let line = points([1, 2])
        let ahead = points([5, 6, 7]).suffix(1).map { $0 }
        XCTAssertEqual(SlopeColoredLineChart.projectionPoints(ahead, from: line), [line[1]] + ahead)
        XCTAssertTrue(SlopeColoredLineChart.projectionPoints([], from: line).isEmpty)
        XCTAssertEqual(SlopeColoredLineChart.projectionPoints(ahead, from: []), ahead)
    }
}
