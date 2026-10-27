import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
@testable import SwCharts

/// Renders one screenshot per public view into `Docs/img/` and keeps the
/// README's `<!-- SCREENSHOTS -->` table in sync. The rendering step only runs
/// in CI (guarded by `GEN_SCREENSHOTS=1`) so a normal `swift test` never dirties
/// the working tree. `testRegistryCoversEveryPublicView` runs unconditionally and
/// is the drift gate: add a `public ... : View` without wiring it here and the
/// suite fails.
@MainActor
final class ScreenshotGenTests: XCTestCase {

    /// One entry per public view. Keep in step with the views in `Sources/`.
    private var registry: [(name: String, size: CGSize, view: AnyView)] {
        [
            ("NormalDistributionChart", CGSize(width: 390, height: 320),
             AnyView(Form { NormalDistributionChart(mean: 72, stddev: 8, count: 240) })),
            ("PeriodBarChart", CGSize(width: 390, height: 380),
             AnyView(Form { PeriodBarChart(data: SwChartsSamples.weightData, selection: .constant(.week)) })),
            ("PeriodGoalBarChart", CGSize(width: 390, height: 380),
             AnyView(Form { Section {
                 PeriodGoalBarChart(data: SwChartsSamples.weightData, selection: .constant(.month),
                                    goal: 178, title: "Weight (lbs)", barColor: .green)
             } })),
            ("NetPeriodBarChart", CGSize(width: 390, height: 380),
             AnyView(Form { Section {
                 NetPeriodBarChart(data: SwChartsSamples.netCalorieData, selection: .constant(.week),
                                   title: "Net Calories")
             } })),
            ("SlopeColoredLineChart", CGSize(width: 390, height: 220),
             AnyView(Form { Section {
                 SlopeColoredLineChart(points: SwChartsSamples.weekly, yDomain: 178...183,
                                       yAxisLabel: { String(format: "%.1f", $0) })
             } })),
            ("SlopeColoredSeriesChart", CGSize(width: 390, height: 220),
             AnyView(Form { Section {
                 SlopeColoredSeriesChart(
                     points: [72, 85, 81, 96, 104].enumerated().map { SeriesPoint(x: Double($0 + 1), value: $1) },
                     yDomain: 0...125,
                     xAxisLabel: { "R\(Int($0))" },
                     yAxisLabel: { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) },
                     risingColor: .green, fallingColor: .orange)
             } })),
            ("PeriodChartView", CGSize(width: 390, height: 280),
             AnyView(Form { Section {
                 PeriodChartView(title: "Weight", samples: SwChartsSamples.dailyWeight,
                                 period: .week, aggregation: .average,
                                 risingColor: .orange, fallingColor: .green,
                                 now: SwChartsSamples.now)
             } })),
            ("PeriodPicker", CGSize(width: 390, height: 60),
             AnyView(PeriodPicker(selection: .constant(.week)).padding())),
            ("CalendarHeatmap",CGSize(width: 390, height: 140),
             AnyView(Form { Section {
                 CalendarHeatmap(weeks: 17, today: Date(timeIntervalSince1970: 1_700_000_000), scrollable: false) { day in
                     day.hashValue % 3 == 0 ? 0.85 : 0.08
                 }
             } })),
        ]
    }

    // MARK: Drift gate (always runs)

    func testRegistryCoversEveryPublicView() throws {
        let found = try Self.publicViewNames(in: Self.sourcesDir)
        let covered = Set(registry.map(\.name))
        let missing = found.subtracting(covered).sorted()
        XCTAssertTrue(missing.isEmpty,
            "Public views without a screenshot registry entry: \(missing). " +
            "Add them to ScreenshotGenTests.registry and re-run with GEN_SCREENSHOTS=1.")
    }

    // MARK: Generation (CI only)

    func testGenerateScreenshotsAndReadme() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GEN_SCREENSHOTS"] == "1",
                          "Set GEN_SCREENSHOTS=1 to (re)generate screenshots + README.")

        let imgDir = Self.packageRoot.appendingPathComponent("Docs/img")
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)

        for entry in registry {
            let url = imgDir.appendingPathComponent("\(Self.kebab(entry.name)).png")
            // Render-if-missing keeps existing PNG bytes stable (no CI commit loop);
            // delete a PNG to force a refresh after a view's appearance changes.
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try render(entry.view, size: entry.size, to: url)
        }

        try updateReadmeTable()
    }

    // MARK: Rendering

    private func render(_ view: AnyView, size: CGSize, to url: URL) throws {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height).background(Color.white))
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            throw Failure("ImageRenderer produced no image for \(url.lastPathComponent)")
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("Could not create PNG destination at \(url.path)")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw Failure("Could not write PNG at \(url.path)")
        }
    }

    // MARK: README table

    private func updateReadmeTable() throws {
        let readme = Self.packageRoot.appendingPathComponent("README.md")
        var text = try String(contentsOf: readme, encoding: .utf8)

        let start = "<!-- SCREENSHOTS:START -->"
        let end = "<!-- SCREENSHOTS:END -->"
        guard let s = text.range(of: start), let e = text.range(of: end), s.upperBound <= e.lowerBound else {
            throw Failure("README is missing the \(start) / \(end) markers.")
        }

        var rows = "\n| Component | Preview |\n| --- | --- |\n"
        for name in registry.map(\.name).sorted() {
            rows += "| `\(name)` | ![\(name)](Docs/img/\(Self.kebab(name)).png) |\n"
        }

        text.replaceSubrange(s.upperBound..<e.lowerBound, with: rows)
        try text.write(to: readme, atomically: true, encoding: .utf8)
    }

    // MARK: Source scan

    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SwChartsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root

    static let sourcesDir = packageRoot.appendingPathComponent("Sources")

    /// Names of `public struct X: View` declarations under `dir` (skips comments,
    /// mirrors the exploration heuristic). Generic params before `: View` are handled.
    static func publicViewNames(in dir: URL) throws -> Set<String> {
        let regex = try NSRegularExpression(
            pattern: #"^\s*public\s+struct\s+([A-Za-z_]\w*)\b[^:{]*:\s*[^{]*\bView\b"#)
        var names = Set<String>()
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(line)
                let range = NSRange(s.startIndex..., in: s)
                if let m = regex.firstMatch(in: s, range: range), let r = Range(m.range(at: 1), in: s) {
                    names.insert(String(s[r]))
                }
            }
        }
        return names
    }

    /// `PeriodGoalBarChart` -> `period-goal-bar-chart`.
    static func kebab(_ name: String) -> String {
        var out = ""
        for (i, ch) in name.enumerated() {
            if ch.isUppercase && i != 0 { out += "-" }
            out += ch.lowercased()
        }
        return out
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }
}
