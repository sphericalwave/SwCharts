import XCTest
@testable import SwCharts

final class CatmullRomSplineTests: XCTestCase {

    private func series(_ values: [Double], xs: [Double]? = nil) -> [SeriesPoint] {
        values.enumerated().map { index, value in
            SeriesPoint(x: xs?[index] ?? Double(index), value: value)
        }
    }

    // MARK: - Shape

    func testFewerThanTwoPointsHasNoSegments() {
        XCTAssertTrue(CatmullRomSpline.segments(through: [SeriesPoint]()).isEmpty)
        XCTAssertTrue(CatmullRomSpline.segments(through: series([5])).isEmpty)
    }

    func testOneSampledSegmentPerPair() {
        let segments = CatmullRomSpline.segments(through: series([1, 4, 2, 8]), samplesPerSegment: 10)
        XCTAssertEqual(segments.count, 3)
        XCTAssertTrue(segments.allSatisfy { $0.count == 11 })
    }

    // MARK: - Endpoints

    func testSegmentsStartAndEndExactlyOnTheirPoints() {
        let points = series([2_100, 2_700, 2_250, 3_200, 1_950, 2_480],
                            xs: [0, 1, 2, 4, 5, 9])
        let segments = CatmullRomSpline.segments(through: points)
        for (index, segment) in segments.enumerated() {
            XCTAssertEqual(segment.first, points[index])
            XCTAssertEqual(segment.last, points[index + 1])
        }
    }

    func testDatedOverloadHitsTheSameDates() {
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let points = [0.0, 5, 3].enumerated().map {
            ChartPoint(start: reference.addingTimeInterval(Double($0.offset) * 86_400), value: $0.element)
        }
        let segments = CatmullRomSpline.segments(through: points)
        XCTAssertEqual(segments.first?.first, points[0])
        XCTAssertEqual(segments.last?.last, points[2])
        XCTAssertEqual(segments[0].last, segments[1].first)
    }

    // MARK: - Continuity at the joins

    func testNeighbouringSegmentsJoinWithMatchingSlope() {
        // Uneven spacing and an interior rising point with a non-zero tangent.
        let points = series([1, 3, 4, 9, 7, 7.5], xs: [0, 1, 3, 4, 6, 7])
        let samples = 400
        let segments = CatmullRomSpline.segments(through: points, samplesPerSegment: samples)
        for index in 0..<(segments.count - 1) {
            let left = segments[index], right = segments[index + 1]
            XCTAssertEqual(left.last, right.first, "segment \(index) and \(index + 1) don't meet")
            // Second-order one-sided differences, so sample spacing doesn't
            // read as a kink.
            let n = left.count
            let dxIn = left[n - 1].x - left[n - 2].x, dxOut = right[1].x - right[0].x
            let slopeIn = (3 * left[n - 1].value - 4 * left[n - 2].value + left[n - 3].value) / (2 * dxIn)
            let slopeOut = (-3 * right[0].value + 4 * right[1].value - right[2].value) / (2 * dxOut)
            let scale = max(abs(slopeIn), abs(slopeOut), 1)
            XCTAssertEqual(slopeIn / scale, slopeOut / scale, accuracy: 0.001,
                           "kink at point \(index + 1): \(slopeIn) in, \(slopeOut) out")
        }
    }

    func testInteriorRisingPointKeepsANonZeroTangent() {
        // Plain Catmull-Rom where nothing would overshoot: the curve runs
        // through a steady rise, it doesn't flatten at every point.
        let tangents = CatmullRomSpline.tangents(for: series([0, 1, 2, 3]))
        XCTAssertEqual(tangents, [1, 1, 1, 1])
    }

    // MARK: - No overshoot

    func testMonotonicSegmentsStayWithinTheirEndpoints() {
        // The calorie card's shape: flat lows, then a jump, then a drop.
        let points = series([0, 0, 50, 3_000, 3_050, 200, 180, 2_900])
        for (index, segment) in CatmullRomSpline.segments(through: points, samplesPerSegment: 64).enumerated() {
            let lo = min(points[index].value, points[index + 1].value)
            let hi = max(points[index].value, points[index + 1].value)
            for sample in segment {
                XCTAssertGreaterThanOrEqual(sample.value, lo - 1e-9, "segment \(index) dips to \(sample.value)")
                XCTAssertLessThanOrEqual(sample.value, hi + 1e-9, "segment \(index) overshoots to \(sample.value)")
            }
        }
    }

    func testLowToHighJumpNeverDipsBelowZero() {
        let points = series([0, 0, 2_800, 2_750])
        let lowest = CatmullRomSpline.segments(through: points).flatMap { $0 }.map(\.value).min()
        XCTAssertEqual(lowest, 0)
    }

    func testMonotonicSegmentsAreMonotonic() {
        let points = series([10, 12, 40, 41, 90], xs: [0, 1, 2, 5, 6])
        for segment in CatmullRomSpline.segments(through: points, samplesPerSegment: 64) {
            for (a, b) in zip(segment, segment.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.value, a.value - 1e-9)
            }
        }
    }

    func testPeaksLevelOff() {
        let tangents = CatmullRomSpline.tangents(for: series([1, 5, 2]))
        XCTAssertEqual(tangents[1], 0)
    }

    func testRepeatedXGivesAStraightSegment() {
        let segments = CatmullRomSpline.segments(through: series([1, 4, 2], xs: [0, 1, 1]))
        XCTAssertEqual(segments[1].count, 2)
    }
}
