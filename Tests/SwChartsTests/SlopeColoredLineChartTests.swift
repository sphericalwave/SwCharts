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

    // MARK: - projectionEndMarker

    func testProjectionPathWholeEndsOnTheLastDashedLeg() throws {
        let all = points([1, 2, 5, 9])
        let line = Array(all.prefix(2))
        let path = try XCTUnwrap(SlopeColoredLineChart.projectionPath([all[2], all[3]], from: line, progress: 1))
        XCTAssertEqual(path.points, [all[1], all[2], all[3]].map { $0.centered() })
        XCTAssertEqual(path.leg.from, all[2].centered())
        XCTAssertEqual(path.leg.to, all[3].centered())
        XCTAssertNil(SlopeColoredLineChart.projectionPath([], from: line, progress: 1))
    }

    func testProjectionPathPartwayStopsAlongItsLeg() throws {
        let all = points([1, 2, 6])
        let line = Array(all.prefix(2))
        let from = all[1].centered(), to = all[2].centered()
        let half = try XCTUnwrap(SlopeColoredLineChart.projectionPath([all[2]], from: line, progress: 0.5))
        XCTAssertEqual(half.points.count, 2)
        XCTAssertEqual(half.points[1].value, 4, accuracy: 0.0001)
        XCTAssertEqual(half.points[1].start.timeIntervalSince(from.start),
                       to.start.timeIntervalSince(from.start) / 2, accuracy: 0.001)
        XCTAssertEqual(half.leg.to, to)
        // At the start the tip sits on the line's end, still headed along the leg.
        let start = try XCTUnwrap(SlopeColoredLineChart.projectionPath([all[2]], from: line, progress: 0))
        XCTAssertEqual(start.points.last, from)
        XCTAssertEqual(start.leg.to, to)
    }

    func testMarkerRotationTurnsUpRightGlyphAlongLeg() {
        let origin = CGPoint(x: 10, y: 10)
        func degrees(_ to: CGPoint) -> Double {
            SlopeColoredLineChart.markerRotation(from: origin, to: to).degrees
        }
        XCTAssertEqual(degrees(CGPoint(x: 20, y: 0)), 0, accuracy: 0.001)     // up-right: as drawn
        XCTAssertEqual(degrees(CGPoint(x: 10, y: 0)), -45, accuracy: 0.001)   // straight up
        XCTAssertEqual(degrees(CGPoint(x: 20, y: 10)), 45, accuracy: 0.001)   // flat right
        XCTAssertEqual(degrees(origin), 0, accuracy: 0.001)                   // no leg
    }

    // MARK: - curves(line:projection:)

    func testCurvesSplitSolidLineFromProjection() {
        let all = points([1, 5, 2, 4])
        let curves = SlopeColoredLineChart.curves(line: Array(all.prefix(3)), projection: [all[3]])
        XCTAssertEqual(curves.map(\.isProjection), [false, false, true])
        XCTAssertEqual(curves.map(\.isRising), [true, false, true])
    }

    func testCurvesPassThroughDayCentredPoints() {
        let all = points([1, 5, 2])
        let curves = SlopeColoredLineChart.curves(line: all, projection: [])
        XCTAssertEqual(curves.first?.samples.first, all[0].centered(in: .day))
        XCTAssertEqual(curves.last?.samples.last, all[2].centered(in: .day))
    }

    func testCurvesWithoutProjectionAreAllSolid() {
        let curves = SlopeColoredLineChart.curves(line: points([1, 2, 3]), projection: [])
        XCTAssertFalse(curves.contains { $0.isProjection })
    }
}
