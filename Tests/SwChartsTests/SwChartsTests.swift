import XCTest
@testable import SwCharts

final class SwChartsTests: XCTestCase {

    // MARK: - ChartTimeframe

    func testShortLabels() {
        XCTAssertEqual(ChartTimeframe.day.short, "D")
        XCTAssertEqual(ChartTimeframe.week.short, "W")
        XCTAssertEqual(ChartTimeframe.month.short, "M")
        XCTAssertEqual(ChartTimeframe.quarter.short, "Q")
        XCTAssertEqual(ChartTimeframe.year.short, "Y")
    }

    // MARK: - PeriodBarChart.DataSet

    func testDataSetPointsForScale() {
        let day = [ChartPoint(start: .now, value: 1)]
        let week = [ChartPoint(start: .now, value: 2), ChartPoint(start: .now, value: 3)]
        let data = PeriodBarChart.DataSet(day: day, week: week)
        XCTAssertEqual(data.points(for: .day), day)
        XCTAssertEqual(data.points(for: .week), week)
        XCTAssertEqual(data.points(for: .month), [])
    }

    // MARK: - PeriodBarLabeler

    func testWeekLabelsAreDates() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 21
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let label = PeriodBarLabeler.label(for: ChartPoint(start: date, value: 0), index: 5, scale: .week)
        XCTAssertEqual(label, "7/21")
    }

    func testMonthLabelShowsYearOnlyAtYearStart() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 1
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(PeriodBarLabeler.label(for: ChartPoint(start: date, value: 0), index: 0, scale: .month), "Jul '26")
        XCTAssertEqual(PeriodBarLabeler.label(for: ChartPoint(start: date, value: 0), index: 3, scale: .month), "Jul")

        var jan = DateComponents()
        jan.year = 2027; jan.month = 1; jan.day = 1
        let janDate = Calendar(identifier: .gregorian).date(from: jan)!
        XCTAssertEqual(PeriodBarLabeler.label(for: ChartPoint(start: janDate, value: 0), index: 6, scale: .month), "Jan '27")
    }

    func testQuarterLabelShowsYearOnlyAtYearStart() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 15
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(PeriodBarLabeler.label(for: ChartPoint(start: date, value: 0), index: 0, scale: .quarter), "Q3 '26")
        XCTAssertEqual(PeriodBarLabeler.label(for: ChartPoint(start: date, value: 0), index: 2, scale: .quarter), "Q3")

        var q1 = DateComponents()
        q1.year = 2027; q1.month = 1; q1.day = 15
        let q1Date = Calendar(identifier: .gregorian).date(from: q1)!
        XCTAssertEqual(PeriodBarLabeler.label(for: ChartPoint(start: q1Date, value: 0), index: 4, scale: .quarter), "Q1 '27")
    }

    // MARK: - PeriodGoalBarChart.paddedDomain

    func testPaddedDomainEmptyIsUnitRange() {
        let d = PeriodGoalBarChart.paddedDomain(points: [], goal: nil)
        XCTAssertEqual(d.lowerBound, 0)
        XCTAssertEqual(d.upperBound, 1)
    }

    func testPaddedDomainSingleValuePadsTenPercent() {
        let d = PeriodGoalBarChart.paddedDomain(
            points: [ChartPoint(start: .now, value: 190)], goal: nil)
        // pad = max(1, 190 * 0.1) = 19
        XCTAssertEqual(d.lowerBound, 171, accuracy: 0.0001)
        XCTAssertEqual(d.upperBound, 209, accuracy: 0.0001)
    }

    func testPaddedDomainIncludesGoalAndPadsFifteenPercent() {
        let points = [ChartPoint(start: .now, value: 190), ChartPoint(start: .now, value: 195)]
        let d = PeriodGoalBarChart.paddedDomain(points: points, goal: 180)
        // lo=180, hi=195, pad = max(1, 15 * 0.15) = 2.25
        XCTAssertEqual(d.lowerBound, 177.75, accuracy: 0.0001)
        XCTAssertEqual(d.upperBound, 197.25, accuracy: 0.0001)
    }

    func testPaddedDomainClampsLowerBoundAtZero() {
        let points = [ChartPoint(start: .now, value: 2), ChartPoint(start: .now, value: 30)]
        let d = PeriodGoalBarChart.paddedDomain(points: points, goal: nil)
        // lo=2, pad = max(1, 28 * 0.15) = 4.2 → 2 - 4.2 = -2.2, clamped to 0
        XCTAssertEqual(d.lowerBound, 0, accuracy: 0.0001)
    }

    func testPaddedDomainDayLabelIsShortDate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 5
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let label = PeriodGoalBarChart.label(
            for: ChartPoint(start: date, value: 0), index: 0, scale: .day)
        XCTAssertEqual(label, "8/5")
    }

    // MARK: - PeriodGoalBarChart.availableScales

    private var twoPointsEveryScale: PeriodGoalBarChart.DataSet {
        let pts = [ChartPoint(start: .now, value: 1), ChartPoint(start: .now, value: 2)]
        return .init(hour: pts, day: pts, week: pts, month: pts, quarter: pts, year: pts)
    }

    func testAvailableScalesDefaultsToEveryScaleWithData() {
        let scales = PeriodGoalBarChart.availableScales(
            data: twoPointsEveryScale, offered: ChartTimeframe.allCases, minimumPoints: 2)
        XCTAssertEqual(scales, ChartTimeframe.allCases)
    }

    func testAvailableScalesDropsUnofferedScaleEvenWithData() {
        let scales = PeriodGoalBarChart.availableScales(
            data: twoPointsEveryScale, offered: [.year, .day, .week], minimumPoints: 2)
        // Timeframe order, not the order offered.
        XCTAssertEqual(scales, [.day, .week, .year])
        let noYear = PeriodGoalBarChart.availableScales(
            data: twoPointsEveryScale, offered: [.day, .week, .month, .quarter], minimumPoints: 2)
        XCTAssertFalse(noYear.contains(.year))
    }

    func testAvailableScalesStillRequiresMinimumPoints() {
        let one = [ChartPoint(start: .now, value: 1)]
        let scales = PeriodGoalBarChart.availableScales(
            data: .init(day: one), offered: [.day], minimumPoints: 2)
        XCTAssertEqual(scales, [])
    }

    // MARK: - NetPeriodBarChart.paddedDomain

    func testNetPaddedDomainEmptyIsSignedUnitRange() {
        let d = NetPeriodBarChart.paddedDomain(points: [])
        XCTAssertEqual(d.lowerBound, -1)
        XCTAssertEqual(d.upperBound, 1)
    }

    func testNetPaddedDomainAllPositiveIncludesZero() {
        let points = [ChartPoint(start: .now, value: 100), ChartPoint(start: .now, value: 200)]
        let d = NetPeriodBarChart.paddedDomain(points: points)
        // values with 0 appended: lo=0, hi=200, pad = max(1, 200*0.15) = 30
        XCTAssertEqual(d.lowerBound, -30, accuracy: 0.0001)
        XCTAssertEqual(d.upperBound, 230, accuracy: 0.0001)
    }

    func testNetPaddedDomainAllNegativeIncludesZero() {
        let points = [ChartPoint(start: .now, value: -100), ChartPoint(start: .now, value: -50)]
        let d = NetPeriodBarChart.paddedDomain(points: points)
        // values with 0 appended: lo=-100, hi=0, pad = max(1, 100*0.15) = 15
        XCTAssertEqual(d.lowerBound, -115, accuracy: 0.0001)
        XCTAssertEqual(d.upperBound, 15, accuracy: 0.0001)
    }

    func testNetPaddedDomainNeverClampsLowerBoundAtZero() {
        let points = [ChartPoint(start: .now, value: -500)]
        let d = NetPeriodBarChart.paddedDomain(points: points)
        XCTAssertLessThan(d.lowerBound, 0)
    }

    // MARK: - ChartPaging

    func testPageSizeValues() {
        XCTAssertEqual(ChartPaging.pageSize(for: .hour), 24)
        XCTAssertEqual(ChartPaging.pageSize(for: .day), 7)
        XCTAssertEqual(ChartPaging.pageSize(for: .week), 4)
        XCTAssertEqual(ChartPaging.pageSize(for: .month), 12)
        XCTAssertEqual(ChartPaging.pageSize(for: .quarter), 4)
        XCTAssertNil(ChartPaging.pageSize(for: .year))
    }

    private func days(_ count: Int, startingYear: Int = 2026, month: Int = 1, day: Int = 1) -> [ChartPoint] {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = startingYear; comps.month = month; comps.day = day
        let start = cal.date(from: comps)!
        return (0..<count).map { i in
            ChartPoint(start: cal.date(byAdding: .day, value: i, to: start)!, value: Double(i))
        }
    }

    func testPagesSingleWhenUnderPageSize() {
        let points = days(3)
        let pages = ChartPaging.pages(points: points, scale: .week) // pageSize 4
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0], points)
    }

    func testPagesChunksFromNewestEnd() {
        let points = days(10)
        let pages = ChartPaging.pages(points: points, scale: .day) // pageSize 7
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].count, 3)
        XCTAssertEqual(pages[1].count, 7)
        XCTAssertEqual(pages[1].last, points.last)
        XCTAssertEqual(pages[0].first, points.first)
    }

    func testPagesUnpagedScaleReturnsSinglePage() {
        let points = days(30)
        let pages = ChartPaging.pages(points: points, scale: .year)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0], points)
    }

    func testPagesEmptyInputReturnsEmpty() {
        XCTAssertEqual(ChartPaging.pages(points: [], scale: .day), [])
    }

    func testDateRangeLabelSameDay() {
        let points = days(1)
        let label = ChartPaging.dateRangeLabel(for: points, scale: .hour)
        XCTAssertEqual(label, "Jan 1")
    }

    func testDateRangeLabelMultiDay() {
        let points = days(7)
        let label = ChartPaging.dateRangeLabel(for: points, scale: .day)
        XCTAssertNotNil(label)
        XCTAssertTrue(label!.contains("Jan"))
    }

    // MARK: - NormalCurve

    func testNormalCurveDegenerateStddevReturnsEmpty() {
        XCTAssertEqual(NormalCurve.points(mean: 5, stddev: 0), [])
        XCTAssertEqual(NormalCurve.ticks(mean: 5, stddev: 0), [])
    }

    func testNormalCurvePeaksAtMean() {
        let points = NormalCurve.points(mean: 10, stddev: 2, samples: 60)
        XCTAssertEqual(points.count, 61)
        let peak = points.max { $0.y < $1.y }!
        XCTAssertEqual(peak.x, 10, accuracy: 0.2)
    }

    func testNormalCurveTicksAreSigmaMultiplesWithinRange() {
        let ticks = NormalCurve.ticks(mean: 0, stddev: 1)
        XCTAssertEqual(ticks, [-2, -1, 0, 1, 2])
    }
}
