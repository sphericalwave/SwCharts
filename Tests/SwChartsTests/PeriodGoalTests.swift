import XCTest
@testable import SwCharts

final class PeriodGoalTests: XCTestCase {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private lazy var cal = PeriodBucketer.standardCalendar(timeZone: newYork)
    private lazy var bucketer = PeriodBucketer(calendar: cal)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func bucket(_ start: Date, _ end: Date, _ value: Double?, partial: Bool = false) -> PeriodBucket {
        PeriodBucket(start: start, end: end, value: value, isPartial: partial)
    }

    // MARK: - Aggregation

    func testMaxAndMinCombine() {
        XCTAssertEqual(MetricAggregation.max.combine([3, 9, 4]), 9)
        XCTAssertEqual(MetricAggregation.min.combine([3, 9, 4]), 3)
        XCTAssertNil(MetricAggregation.max.combine([]))
        XCTAssertEqual(MetricAggregation.max.label, "max")
        XCTAssertEqual(MetricAggregation.min.label, "min")
    }

    func testMaxBucketsTakeTheBestDay() {
        let now = date(2026, 10, 8, 15)
        let samples = [DatedSample(date: date(2026, 10, 5, 9), value: 200),
                       DatedSample(date: date(2026, 10, 5, 18), value: 225),
                       DatedSample(date: date(2026, 10, 7, 9), value: 215)]
        let week = bucketer.buckets(for: samples, period: .week, aggregation: .max, now: now).last
        XCTAssertEqual(week?.value, 225)
        let day = bucketer.buckets(for: samples, period: .day, aggregation: .max, now: now)
            .first { $0.start == date(2026, 10, 5) }
        XCTAssertEqual(day?.value, 225, "a day's samples collapse with the same rule")
    }

    // MARK: - Target scaling

    func testSumGoalScalesWithBucketLength() {
        let goal = PeriodGoal(2.5)
        let day = bucket(date(2026, 10, 8), date(2026, 10, 9), 1)
        let week = bucket(date(2026, 10, 5), date(2026, 10, 12), 1)
        let feb = bucket(date(2026, 2, 1), date(2026, 3, 1), 1)
        let oct = bucket(date(2026, 10, 1), date(2026, 11, 1), 1)
        XCTAssertEqual(goal.target(for: day, aggregation: .sum, calendar: cal), 2.5)
        XCTAssertEqual(goal.target(for: week, aggregation: .sum, calendar: cal), 17.5)
        XCTAssertEqual(goal.target(for: feb, aggregation: .sum, calendar: cal), 70)
        XCTAssertEqual(goal.target(for: oct, aggregation: .sum, calendar: cal), 77.5)
    }

    func testSumGoalScalingIsDSTSafe() {
        // The week containing the Nov 1 2026 fall-back has 7 days, not 7×24h±1.
        let week = bucket(date(2026, 10, 26), date(2026, 11, 2), 1)
        XCTAssertEqual(PeriodGoal(10).target(for: week, aggregation: .sum, calendar: cal), 70)
    }

    func testLevelGoalsAreNotScaled() {
        let week = bucket(date(2026, 10, 5), date(2026, 10, 12), 1)
        for aggregation in [MetricAggregation.average, .max, .min] {
            XCTAssertEqual(PeriodGoal(100).target(for: week, aggregation: aggregation, calendar: cal), 100)
        }
    }

    func testBucketerWindowsScaleWeeksBySeven() {
        let buckets = bucketer.buckets(for: [], period: .week, aggregation: .sum, now: date(2026, 10, 8))
        let targets = buckets.map { PeriodGoal(1).target(for: $0, aggregation: .sum, calendar: cal) }
        XCTAssertTrue(targets.allSatisfy { $0 == 7 })
    }

    // MARK: - Outcome

    func testCompleteBucketsHitOrMiss() {
        let week = (date(2026, 9, 28), date(2026, 10, 5))
        let atLeast = PeriodGoal(2)
        XCTAssertEqual(atLeast.outcome(for: bucket(week.0, week.1, 14), aggregation: .sum, calendar: cal), .hit)
        XCTAssertEqual(atLeast.outcome(for: bucket(week.0, week.1, 13.9), aggregation: .sum, calendar: cal), .miss)
        let atMost = PeriodGoal(2000, direction: .atMost)
        XCTAssertEqual(atMost.outcome(for: bucket(week.0, week.1, 1900), aggregation: .average, calendar: cal), .hit)
        XCTAssertEqual(atMost.outcome(for: bucket(week.0, week.1, 2100), aggregation: .average, calendar: cal), .miss)
    }

    func testEmptyBucketHasNoOutcome() {
        XCTAssertNil(PeriodGoal(1).outcome(for: bucket(date(2026, 10, 5), date(2026, 10, 12), nil),
                                           aggregation: .sum, calendar: cal))
    }

    func testPartialSumBucketOnlyCountsOnceDecided() {
        let start = date(2026, 10, 5), end = date(2026, 10, 12)
        let atLeast = PeriodGoal(2)   // 14 for the week
        XCTAssertNil(atLeast.outcome(for: bucket(start, end, 10, partial: true), aggregation: .sum, calendar: cal),
                     "still climbing")
        XCTAssertEqual(atLeast.outcome(for: bucket(start, end, 14, partial: true), aggregation: .sum, calendar: cal), .hit)

        let atMost = PeriodGoal(2, direction: .atMost)
        XCTAssertNil(atMost.outcome(for: bucket(start, end, 10, partial: true), aggregation: .sum, calendar: cal),
                     "could still go over")
        XCTAssertEqual(atMost.outcome(for: bucket(start, end, 15, partial: true), aggregation: .sum, calendar: cal), .miss)
    }

    func testPartialMaxAndMinBucketsOnlyCountOnceDecided() {
        let start = date(2026, 10, 5), end = date(2026, 10, 12)
        XCTAssertEqual(PeriodGoal(225).outcome(for: bucket(start, end, 230, partial: true), aggregation: .max, calendar: cal), .hit)
        XCTAssertNil(PeriodGoal(225).outcome(for: bucket(start, end, 200, partial: true), aggregation: .max, calendar: cal))
        XCTAssertEqual(PeriodGoal(60, direction: .atMost).outcome(for: bucket(start, end, 55, partial: true), aggregation: .min, calendar: cal), .hit)
        XCTAssertNil(PeriodGoal(60, direction: .atMost).outcome(for: bucket(start, end, 65, partial: true), aggregation: .min, calendar: cal))
    }

    func testPartialAverageBucketIsJudgedSoFar() {
        let b = bucket(date(2026, 10, 5), date(2026, 10, 12), 90, partial: true)
        XCTAssertEqual(PeriodGoal(100).outcome(for: b, aggregation: .average, calendar: cal), .miss)
    }

    // MARK: - View helpers

    func testFullBucketStretchesPartialWeekAndMonth() {
        let partialWeek = bucket(date(2026, 10, 5), date(2026, 10, 12), 3, partial: true)
        XCTAssertEqual(PeriodChartView.fullBucket(partialWeek, period: .week, calendar: cal).end, date(2026, 10, 12))
        let oct = bucket(date(2026, 10, 1), date(2026, 11, 1), 3, partial: true)
        let full = PeriodChartView.fullBucket(oct, period: .month, calendar: cal)
        XCTAssertEqual(PeriodGoal(1).target(for: full, aggregation: .sum, calendar: cal), 31)
    }
}
