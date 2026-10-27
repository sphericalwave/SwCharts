import Foundation

/// One raw observation: when it happened, and its value. Several samples may
/// share a day (three meals, two workouts, a dozen HR readings).
public struct DatedSample: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// One point/bar on a `PeriodChartView`: the half-open interval
/// `start..<end` it covers, its aggregated value, and whether the period is
/// still in progress.
public struct PeriodBucket: Identifiable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// `nil` when no day in the bucket has data — an empty bucket is not zero.
    public let value: Double?
    /// The current, unfinished week or month. Drawn faded and labelled
    /// "so far"; never projected. Always `false` for `.day` buckets.
    public let isPartial: Bool

    public var id: Date { start }

    public init(start: Date, end: Date, value: Double?, isPartial: Bool) {
        self.start = start
        self.end = end
        self.value = value
        self.isPartial = isPartial
    }
}

/// Turns dated samples into the fixed window of buckets for a `ChartPeriod`.
/// Pure: the calendar (and so the time zone) and "now" are injected.
///
/// Rules:
/// - Samples first collapse into one value per local calendar day, using the
///   metric's aggregation (sum of the day's samples, or their mean).
/// - A week/month bucket applies the same aggregation to the daily values
///   that have data. Days without samples are skipped, not counted as zero —
///   a weekly average of HR over 3 logged days is the mean of those 3.
/// - A bucket with no data has `value == nil`.
/// - Weeks start on Monday, at local midnight. Bucket edges come from
///   calendar arithmetic, so DST days (23 h / 25 h) land correctly.
/// - The newest week/month bucket — the one containing `now` — is partial.
public struct PeriodBucketer: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = PeriodBucketer.standardCalendar()) {
        self.calendar = calendar
    }

    /// Gregorian, Monday-first (ISO-style) calendar in `timeZone`.
    public static func standardCalendar(timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    /// The `period.bucketCount` buckets ending with the one containing `now`,
    /// oldest first. Pass `bucketCount` to give one chart a shorter or longer
    /// window (e.g. 14 days) without changing the house default.
    public func buckets(
        for samples: [DatedSample],
        period: ChartPeriod,
        aggregation: MetricAggregation,
        now: Date = .now,
        bucketCount: Int? = nil
    ) -> [PeriodBucket] {
        let daily = dailyValues(samples, aggregation: aggregation)
        let current = calendar.dateInterval(of: period.component, for: now)?.start
            ?? calendar.startOfDay(for: now)

        return (0..<max(bucketCount ?? period.bucketCount, 0)).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: period.component, value: -offset, to: current),
                  let end = calendar.date(byAdding: period.component, value: 1, to: start)
            else { return nil }
            let values = daily.filter { $0.key >= start && $0.key < end }.map(\.value)
            return PeriodBucket(
                start: start,
                end: end,
                value: aggregation.combine(values),
                isPartial: period != .day && offset == 0
            )
        }
    }

    /// One value per local day that has samples, keyed by the day's start.
    func dailyValues(_ samples: [DatedSample], aggregation: MetricAggregation) -> [Date: Double] {
        Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
            .compactMapValues { aggregation.combine($0.map(\.value)) }
    }
}
