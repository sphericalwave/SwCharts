import SwiftUI

/// The D/W/M segmented control for a `PeriodChartView`. Made for the
/// navigation bar's principal slot:
///
/// ```swift
/// @AppStorage("nutritionChartPeriod") private var period: ChartPeriod = .week
///
/// .toolbar {
///     ToolbarItem(placement: .principal) { PeriodPicker(selection: $period) }
/// }
/// ```
public struct PeriodPicker: View {
    @Binding private var selection: ChartPeriod

    /// Three 72pt segments. Public so app-side variants (e.g. a picker that
    /// gates periods) can match it.
    public static let width: CGFloat = 216

    public init(selection: Binding<ChartPeriod>) {
        self._selection = selection
    }

    public var body: some View {
        Picker("Period", selection: $selection) {
            ForEach(ChartPeriod.allCases) { period in
                Text(period.short)
                    .accessibilityLabel(period.rawValue.capitalized)
                    .tag(period)
            }
        }
        .pickerStyle(.segmented)
        // Wide, tall segments: shrink-wrapped to "D"/"W"/"M" each target is
        // barely wider than its letter. 72pt a segment clears the 44pt
        // minimum with room to spare and still fits the principal slot
        // beside a trailing toolbar button.
        .controlSize(.large)
        .frame(width: Self.width)
    }
}

#if DEBUG
#Preview("PeriodPicker") {
    PeriodPicker(selection: .constant(.week))
        .padding()
}
#endif
