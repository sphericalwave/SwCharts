import XCTest
@testable import SwCharts

final class PeriodBucketerTests: XCTestCase {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private lazy var cal = PeriodBucketer.standardCalendar(timeZone: newYork)
    private lazy var bucketer = PeriodBucketer(calendar: cal)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? cal
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func sample(_ d: Date, _ v: Double) -> DatedSample { DatedSample(date: d, value: v) }

    // Thursday 2026-10-08, mid-afternoon.
    private lazy var now = date(2026, 10, 8, 15, 30)

    // MARK: - ChartPeriod / MetricAggregation

    func testPeriodShortLabelsAndWindows() {
        XCTAssertEqual(ChartPeriod.allCases.map(\.short), ["D", "W", "M"])
        XCTAssertEqual(ChartPeriod.allCases.map(\.bucketCount), [28, 12, 12])
    }

    func testAggregationLabels() {
        XCTAssertEqual(MetricAggregation.sum.label, "total")
        XCTAssertEqual(MetricAggregation.average.label, "avg")
    }

    func testCombineEmptyIsNilNotZero() {
        XCTAssertNil(MetricAggregation.sum.combine([]))
        XCTAssertNil(MetricAggregation.average.combine([]))
        XCTAssertEqual(MetricAggregation.sum.combine([1, 2, 3]), 6)
        XCTAssertEqual(MetricAggregation.average.combine([1, 2, 3]), 2)
    }

    // MARK: - Window shape

    func testDayWindowIs28ContiguousLocalDaysEndingToday() {
        let buckets = bucketer.buckets(for: [], period: .day, aggregation: .sum, now: now)
        XCTAssertEqual(buckets.count, 28)
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 8))
        XCTAssertEqual(buckets.first?.start, date(2026, 9, 11))
        for (a, b) in zip(buckets, buckets.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        XCTAssertTrue(buckets.allSatisfy { !$0.isPartial }, "Day buckets are never partial")
    }

    func testBucketCountOverridesTheDefaultWindow() {
        let buckets = bucketer.buckets(for: [], period: .day, aggregation: .sum, now: now, bucketCount: 14)
        XCTAssertEqual(buckets.count, 14)
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 8))
        XCTAssertEqual(buckets.first?.start, date(2026, 9, 25))
    }

    func testWeekWindowIs12MondayStartedWeeks() {
        let buckets = bucketer.buckets(for: [], period: .week, aggregation: .sum, now: now)
        XCTAssertEqual(buckets.count, 12)
        for b in buckets {
            XCTAssertEqual(cal.component(.weekday, from: b.start), 2, "Weeks start on Monday")
            XCTAssertEqual(cal.component(.hour, from: b.start), 0)
            XCTAssertEqual(cal.dateComponents([.day], from: b.start, to: b.end).day, 7)
        }
        XCTAssertEqual(buckets.last?.start, date(2026, 10, 5))
        XCTAssertEqual(buckets.first?.start, date(2026, 7, 20))
    }

    func testMonthWindowIs12MonthsCrossingYearBoundary() {
        let buckets = bucketer.buckets(for: [], period: .month, aggregation: .sum, now: date(2026, 2, 10))
        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.first?.start, date(2025, 3, 1))
        XCTAssertEqual(buckets.last?.start, date(2026, 2, 1))
        XCTAssertEqual(buckets.last?.end, date(2026, 3, 1))
        XCTAssertTrue(buckets.allSatisfy { cal.component(.day, from: $0.start) == 1 })
    }

    func testOnlyCurrentWeekOrMonthIsPartial() {
        for period in [ChartPeriod.week, .month] {
            let buckets = bucketer.buckets(for: [], period: period, aggregation: .sum, now: now)
            XCTAssertEqual(buckets.filter(\.isPartial).count, 1, "\(period)")
            XCTAssertTrue(buckets.last!.isPartial, "\(period)")
        }
    }

    func testNowExactlyAtMondayMidnightStartsNewPartialWeek() {
        let monday = date(2026, 10, 5)
        let buckets = bucketer.buckets(for: [sample(monday, 5)], period: .week, aggregation: .sum, now: monday)
        XCTAssertEqual(buckets.last?.start, monday)
        XCTAssertEqual(buckets.last?.value, 5)
        XCTAssertTrue(buckets.last!.isPartial)
    }

    // MARK: - Aggregation

    func testSumAddsSamplesAcrossDaysAndWithinADay() {
        let samples = [
            sample(date(2026, 10, 5, 8), 500),   // Mon breakfast
            sample(date(2026, 10, 5, 19), 900),  // Mon dinner
            sample(date(2026, 10, 7, 12), 700),  // Wed
        ]
        let week = bucketer.buckets(for: samples, period: .week, aggregation: .sum, now: now).last!
        XCTAssertEqual(week.value, 2100)

        let days = bucketer.buckets(for: samples, period: .day, aggregation: .sum, now: now)
        XCTAssertEqual(days.first { $0.start == date(2026, 10, 5) }?.value, 1400)
    }

    func testAverageIsMeanOfDailyValuesSkippingEmptyDays() {
        let samples = [
            sample(date(2026, 9, 28, 7), 100),   // Mon: readings 100 and 200 → day 150
            sample(date(2026, 9, 28, 20), 200),
            sample(date(2026, 9, 30, 9), 60),    // Wed: 60
            // Tue, Thu–Sun: no data — must not count as zero.
        ]
        let buckets = bucketer.buckets(for: samples, period: .week, aggregation: .average, now: now)
        let week = buckets.first { $0.start == date(2026, 9, 28) }!
        XCTAssertEqual(week.value, 105) // (150 + 60) / 2, not / 7, and not (100+200+60)/3
    }

    func testMonthAverageWeightsDaysNotSamples() {
        let samples = [
            sample(date(2026, 9, 1, 6), 10), sample(date(2026, 9, 1, 7), 10), sample(date(2026, 9, 1, 8), 10),
            sample(date(2026, 9, 2, 6), 40),
        ]
        let sep = bucketer.buckets(for: samples, period: .month, aggregation: .average, now: now)
            .first { $0.start == date(2026, 9, 1) }!
        XCTAssertEqual(sep.value, 25)
    }

    func testEmptyBucketsAreNil() {
        let samples = [sample(date(2026, 10, 6), 3)]
        let buckets = bucketer.buckets(for: samples, period: .week, aggregation: .sum, now: now)
        XCTAssertEqual(buckets.compactMap(\.value), [3])
        XCTAssertNil(buckets[buckets.count - 2].value)
    }

    func testSamplesOutsideWindowAreIgnored() {
        let samples = [
            sample(date(2026, 9, 10, 23, 59), 99), // day before the 28-day window
            sample(date(2026, 9, 11, 0, 0), 1),    // first day of the window
            sample(date(2026, 10, 9, 0, 1), 99),   // tomorrow
        ]
        let buckets = bucketer.buckets(for: samples, period: .day, aggregation: .sum, now: now)
        XCTAssertEqual(buckets.compactMap(\.value), [1])
    }

    // MARK: - Week boundaries / time zones / DST

    func testSundayLateNightBelongsToTheEndingWeek() {
        let samples = [
            sample(date(2026, 10, 4, 23, 30), 1),  // Sun
            sample(date(2026, 10, 5, 0, 30), 10),  // Mon
        ]
        let buckets = bucketer.buckets(for: samples, period: .week, aggregation: .sum, now: now)
        XCTAssertEqual(buckets[10].value, 1)
        XCTAssertEqual(buckets[10].start, date(2026, 9, 28))
        XCTAssertEqual(buckets[11].value, 10)
    }

    func testBucketingUsesTheCalendarsTimeZone() {
        // 2026-10-05 03:00 UTC is Monday in UTC but Sunday evening in New York.
        let utcCal = PeriodBucketer.standardCalendar(timeZone: TimeZone(identifier: "UTC")!)
        let instant = date(2026, 10, 5, 3, in: utcCal)
        let s = [sample(instant, 1)]

        let ny = bucketer.buckets(for: s, period: .week, aggregation: .sum, now: now)
        let utc = PeriodBucketer(calendar: utcCal).buckets(for: s, period: .week, aggregation: .sum, now: now)
        XCTAssertEqual(ny.firstIndex { $0.value != nil }, 10)
        XCTAssertEqual(utc.firstIndex { $0.value != nil }, 11)
    }

    func testDayBucketsAcrossSpringForwardAreLocalMidnights() {
        // DST starts in New York on Sunday 2026-03-08 (a 23-hour day).
        let buckets = bucketer.buckets(for: [], period: .day, aggregation: .sum, now: date(2026, 3, 20, 12))
        XCTAssertEqual(Set(buckets.map(\.start)).count, 28)
        XCTAssertTrue(buckets.allSatisfy { cal.component(.hour, from: $0.start) == 0 })
        let dstDay = buckets.first { $0.start == date(2026, 3, 8) }!
        XCTAssertEqual(dstDay.end.timeIntervalSince(dstDay.start), 23 * 3600)
    }

    func testWeekBucketsAcrossFallBackStayOnMondayMidnight() {
        // DST ends in New York on Sunday 2026-11-01 (a 25-hour day).
        let samples = [
            sample(date(2026, 11, 1, 23, 30), 1),  // Sun after fall-back → week of Oct 26
            sample(date(2026, 11, 2, 0, 15), 10),  // Mon → week of Nov 2
        ]
        let buckets = bucketer.buckets(for: samples, period: .week, aggregation: .sum, now: date(2026, 11, 20, 9))
        XCTAssertTrue(buckets.allSatisfy {
            cal.component(.weekday, from: $0.start) == 2 && cal.component(.hour, from: $0.start) == 0
        })
        let fallBackWeek = buckets.first { $0.start == date(2026, 10, 26) }!
        XCTAssertEqual(fallBackWeek.value, 1)
        XCTAssertEqual(fallBackWeek.end.timeIntervalSince(fallBackWeek.start), 7 * 86_400 + 3600)
        XCTAssertEqual(buckets.first { $0.start == date(2026, 11, 2) }?.value, 10)
    }

    func testStandardCalendarIsMondayFirst() {
        let c = PeriodBucketer.standardCalendar(timeZone: newYork)
        XCTAssertEqual(c.firstWeekday, 2)
        XCTAssertEqual(c.timeZone, newYork)
    }
}

final class PeriodSummaryTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func buckets(_ values: [Double?], partialLast: Bool = true) -> [PeriodBucket] {
        values.enumerated().map { i, v in
            PeriodBucket(start: t0.addingTimeInterval(Double(i) * 86_400),
                         end: t0.addingTimeInterval(Double(i + 1) * 86_400),
                         value: v,
                         isPartial: partialLast && i == values.count - 1)
        }
    }

    func testEmptyWindow() {
        let s = PeriodSummary(buckets: buckets([nil, nil]), aggregation: .sum)
        XCTAssertNil(s.windowAverage)
        XCTAssertNil(s.latest)
        XCTAssertNil(s.previous)
        XCTAssertNil(s.percentChange)
    }

    func testAverageMetricWindowIncludesPartialAndSkipsEmpty() {
        let s = PeriodSummary(buckets: buckets([10, nil, 20, 30]), aggregation: .average)
        XCTAssertEqual(s.windowAverage, 20)
        XCTAssertEqual(s.latest?.value, 30)
        XCTAssertEqual(s.previous?.value, 20)
        XCTAssertEqual(s.percentChange!, 0.5, accuracy: 1e-9)
    }

    func testSumMetricWindowExcludesPartialAndHasNoChange() {
        let s = PeriodSummary(buckets: buckets([100, 200, 30]), aggregation: .sum)
        XCTAssertEqual(s.windowAverage, 150)
        XCTAssertEqual(s.latest?.value, 30)
        XCTAssertTrue(s.latest!.isPartial)
        XCTAssertNil(s.percentChange, "A running total vs a finished one isn't a like-for-like change")
    }

    func testSumMetricWithOnlyPartialDataStillAverages() {
        let s = PeriodSummary(buckets: buckets([nil, nil, 30]), aggregation: .sum)
        XCTAssertEqual(s.windowAverage, 30)
    }

    func testSumMetricCompleteBucketsHaveChange() {
        let s = PeriodSummary(buckets: buckets([100, 80], partialLast: false), aggregation: .sum)
        XCTAssertEqual(s.windowAverage, 90)
        XCTAssertEqual(s.percentChange!, -0.2, accuracy: 1e-9)
    }

    func testPreviousSkipsEmptyBuckets() {
        let s = PeriodSummary(buckets: buckets([40, nil, nil, 50], partialLast: false), aggregation: .average)
        XCTAssertEqual(s.previous?.value, 40)
        XCTAssertEqual(s.percentChange!, 0.25, accuracy: 1e-9)
    }

    func testZeroPreviousHasNoChange() {
        let s = PeriodSummary(buckets: buckets([0, 5], partialLast: false), aggregation: .average)
        XCTAssertNil(s.percentChange)
    }

    func testNegativePreviousUsesMagnitude() {
        let s = PeriodSummary(buckets: buckets([-100, -50], partialLast: false), aggregation: .average)
        XCTAssertEqual(s.percentChange!, 0.5, accuracy: 1e-9)
    }
}

final class PeriodChartViewHelperTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func bucket(_ i: Int, _ v: Double?) -> PeriodBucket {
        PeriodBucket(start: t0.addingTimeInterval(Double(i) * 100),
                     end: t0.addingTimeInterval(Double(i + 1) * 100), value: v, isPartial: false)
    }

    func testNearestBucketSkipsEmpty() {
        let bs = [bucket(0, 1), bucket(1, nil), bucket(2, 3)]
        XCTAssertEqual(PeriodChartView.bucket(nearest: t0.addingTimeInterval(140), in: bs)?.value, 1)
        XCTAssertEqual(PeriodChartView.bucket(nearest: t0.addingTimeInterval(160), in: bs)?.value, 3)
        XCTAssertNil(PeriodChartView.bucket(nearest: t0, in: [bucket(0, nil)]))
    }

    func testAxisBucketsAlwaysIncludeNewest() {
        let bs = (0..<28).map { bucket($0, 1) }
        XCTAssertEqual(PeriodChartView.axisBuckets(bs, period: .day).map(\.start),
                       [6, 13, 20, 27].map { bs[$0].start })
        let weeks = Array(bs.prefix(12))
        XCTAssertEqual(PeriodChartView.axisBuckets(weeks, period: .week).map(\.start),
                       [2, 5, 8, 11].map { weeks[$0].start })
    }

    func testWholeTicksAreWholeAndAtMostFive() {
        XCTAssertEqual(PeriodChartView.wholeTicks(in: 0...1.15), [0, 1])
        XCTAssertEqual(PeriodChartView.wholeTicks(in: -0.3...2.4), [0, 1, 2])
        XCTAssertEqual(PeriodChartView.wholeTicks(in: 0...12), [0, 3, 6, 9, 12])
        XCTAssertEqual(PeriodChartView.wholeTicks(in: 0.2...0.8), [])
    }

    func testBarDomainStartsAtZeroWithHeadroom() {
        func check(_ values: [Double], _ lo: Double, _ hi: Double) {
            let d = PeriodChartView.barDomain(values: values)
            XCTAssertEqual(d.lowerBound, lo, accuracy: 1e-9)
            XCTAssertEqual(d.upperBound, hi, accuracy: 1e-9)
        }
        check([50, 100], 0, 115)
        check([], 0, 1.15)
        check([-20, 80], -20, 95)
        // All-negative (net calories in deficit): zero stays in the domain
        // because bars hang from it.
        check([-4000, -1000], -4000, 600)
    }
}
