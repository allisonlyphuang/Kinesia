import XCTest
@testable import Kinesia

final class ReportFormatTests: XCTestCase {

    // MARK: - Axis numbers

    func testWholeNumbersLoseTheirDecimal() {
        XCTAssertEqual(ReportFormat.axis(4), "4")
        XCTAssertEqual(ReportFormat.axis(0), "0")
        XCTAssertEqual(ReportFormat.axis(-2), "-2")
    }

    func testFractionsKeepOneDecimal() {
        XCTAssertEqual(ReportFormat.axis(4.27), "4.3")
        XCTAssertEqual(ReportFormat.axis(4.21), "4.2")
        XCTAssertEqual(ReportFormat.axis(0.5), "0.5")
    }

    func testNonFiniteNumbersFormatAsNothing() {
        XCTAssertEqual(ReportFormat.axis(.nan), "")
        XCTAssertEqual(ReportFormat.axis(.infinity), "")
    }

    func testSignedNumbersCarryTheirSign() {
        XCTAssertEqual(ReportFormat.signed(25), "+25")
        XCTAssertEqual(ReportFormat.signed(-25), "−25")
        XCTAssertEqual(ReportFormat.signed(0), "0")
    }

    func testClockFormatsMinutesAsHoursAndMinutes() {
        XCTAssertEqual(ReportFormat.clock(minutes: 0), "0:00")
        XCTAssertEqual(ReportFormat.clock(minutes: 90), "1:30")
        XCTAssertEqual(ReportFormat.clock(minutes: 485), "8:05")
    }

    // MARK: - Counting

    // A subtitle reading "1 readings" was visible on device.
    func testOneIsSingular() {
        XCTAssertEqual(ReportFormat.count(1, "reading"), "1 reading")
        XCTAssertEqual(ReportFormat.count(1, "check-in"), "1 check-in")
    }

    func testOtherNumbersArePlural() {
        XCTAssertEqual(ReportFormat.count(0, "reading"), "0 readings")
        XCTAssertEqual(ReportFormat.count(2, "reading"), "2 readings")
        XCTAssertEqual(ReportFormat.count(30, "day"), "30 days")
    }

    func testAnIrregularPluralCanBeGiven() {
        XCTAssertEqual(ReportFormat.count(2, "entry", plural: "entries"), "2 entries")
        XCTAssertEqual(ReportFormat.count(1, "entry", plural: "entries"), "1 entry")
    }

    // MARK: - Axis label density

    // A 30 day window printed 30 overlapping labels on device.
    func testShortWindowsLabelEveryPoint() {
        // A week labels every day, matching the day selector above the first chart.
        XCTAssertEqual(ReportFormat.labelStride(for: 7), 1)
        XCTAssertEqual(ReportFormat.labelStride(for: 6), 1)
        XCTAssertEqual(ReportFormat.labelStride(for: 1), 1)
    }

    func testLongWindowsThinTheLabelsOut() {
        XCTAssertEqual(ReportFormat.labelStride(for: 14), 2)
        XCTAssertEqual(ReportFormat.labelStride(for: 30), 5)
        XCTAssertEqual(ReportFormat.labelStride(for: 90), 13)
    }

    func testNoWindowEverExceedsTheLabelBudget() {
        for count in 1...400 {
            let labels = Int((Double(count) / Double(ReportFormat.labelStride(for: count))).rounded(.up))
            XCTAssertLessThanOrEqual(labels, 7, "\(count) points produced \(labels) labels")
        }
    }

    func testAZeroCountDoesNotDivideByZero() {
        XCTAssertEqual(ReportFormat.labelStride(for: 0), 1)
    }

    // MARK: - Date label choice

    // "Fri 18" is ambiguous once a window spans more than one month.
    func testShortWindowsUseTheWeekday() {
        XCTAssertEqual(
            Date(timeIntervalSince1970: 1_800_000_000).formatted(ReportFormat.dayLabel(for: 7)),
            Date(timeIntervalSince1970: 1_800_000_000).formatted(ReportFormat.weekdayDay)
        )
    }

    func testLongWindowsUseTheMonth() {
        XCTAssertEqual(
            Date(timeIntervalSince1970: 1_800_000_000).formatted(ReportFormat.dayLabel(for: 30)),
            Date(timeIntervalSince1970: 1_800_000_000).formatted(ReportFormat.dayMonth)
        )
    }

    // MARK: - Metric titles

    func testEveryMetricHasAnAxisTitleCarryingItsUnit() {
        for metric in PrimaryMetric.allCases {
            XCTAssertTrue(metric.axisTitle.contains("("), "\(metric) has no unit in brackets")
            XCTAssertFalse(metric.shortTitle.isEmpty)
        }
    }

    // The Measure control has one line, and lineLimit does not reach a menu picker's label,
    // so these have to be short on their own. "Constellation tracing" wrapped to four lines.
    func testPickerTitlesAreShortEnoughForOneLine() {
        for metric in PrimaryMetric.allCases {
            XCTAssertFalse(metric.pickerTitle.isEmpty)
            XCTAssertLessThanOrEqual(metric.pickerTitle.count, 12, "\(metric) is too long for the control")
            XCTAssertLessThanOrEqual(metric.pickerTitle.count, metric.shortTitle.count)
        }
    }

    func testEveryPickerTitleIsDistinct() {
        let titles = PrimaryMetric.allCases.map(\.pickerTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    // The regulatory rule: name the task, not the symptom it is thought to measure.
    func testMetricTitlesNameTheTaskNotTheSymptom() {
        let banned = ["bradykinesia", "akinesia", "dexterity", "severity", "tremor"]
        for metric in PrimaryMetric.allCases {
            for word in banned {
                XCTAssertFalse(metric.shortTitle.lowercased().contains(word))
                XCTAssertFalse(metric.axisTitle.lowercased().contains(word))
                XCTAssertFalse(metric.pickerTitle.lowercased().contains(word))
            }
        }
    }
}
