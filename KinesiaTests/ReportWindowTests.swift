import XCTest
@testable import Kinesia

final class ReportWindowTests: XCTestCase {

    private let utc = ReportFixtures.utc

    private func window(days: Int, endingOn offset: Int) throws -> ReportWindow {
        try XCTUnwrap(ReportWindow(days: days, endingOn: ReportFixtures.day(offset), calendar: utc))
    }

    // MARK: - Shape

    func testASevenDayWindowHoldsSevenDays() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertEqual(window.dayCount, 7)
        XCTAssertEqual(window.days, (0..<7).map(ReportFixtures.day))
    }

    func testTheLastDayIsTheDayContainingTheEndInstant() throws {
        let window = try XCTUnwrap(
            ReportWindow(days: 7, endingOn: ReportFixtures.instant(6, hour: 23), calendar: utc)
        )
        XCTAssertEqual(window.days.last, ReportFixtures.day(6))
    }

    func testStartIsLocalMidnightOfTheFirstDay() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertEqual(window.start, ReportFixtures.day(0))
    }

    // end is the midnight after the last day, so a check-in late on the last day is inside.
    func testEndIsTheMidnightAfterTheLastDay() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertEqual(window.end, ReportFixtures.day(7))
    }

    func testAOneDayWindowHoldsOneDay() throws {
        let window = try window(days: 1, endingOn: 3)
        XCTAssertEqual(window.dayCount, 1)
        XCTAssertEqual(window.days, [ReportFixtures.day(3)])
    }

    func testEveryDayInTheWindowIsLocalMidnight() throws {
        let window = try window(days: 14, endingOn: 13)
        for day in window.days {
            XCTAssertEqual(day, utc.startOfDay(for: day))
        }
    }

    func testTheDaysComeBackOldestFirst() throws {
        let window = try window(days: 30, endingOn: 29)
        XCTAssertEqual(window.days, window.days.sorted())
    }

    // MARK: - Boundaries

    func testStartIsInsideTheWindow() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertTrue(window.contains(window.start))
    }

    func testEndIsOutsideTheWindow() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertFalse(window.contains(window.end))
    }

    func testOneSecondBeforeTheEndIsInside() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertTrue(window.contains(window.end.addingTimeInterval(-1)))
    }

    func testOneSecondBeforeTheStartIsOutside() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertFalse(window.contains(window.start.addingTimeInterval(-1)))
    }

    // Two adjacent windows must not both claim a check-in at midnight.
    func testAdjacentWindowsDoNotOverlap() throws {
        let first = try window(days: 7, endingOn: 6)
        let second = try window(days: 7, endingOn: 13)

        XCTAssertEqual(first.end, second.start)
        XCTAssertFalse(first.contains(second.start))
        XCTAssertTrue(second.contains(second.start))
    }

    // MARK: - Rejected input

    func testZeroDaysIsRejected() {
        XCTAssertNil(ReportWindow(days: 0, endingOn: ReportFixtures.day(0), calendar: utc))
    }

    func testANegativeNumberOfDaysIsRejected() {
        XCTAssertNil(ReportWindow(days: -7, endingOn: ReportFixtures.day(0), calendar: utc))
    }

    // MARK: - Days with no data

    // The window is a calendar range and does not look at sessions, so a day with no check-in
    // is still in the list and a chart can draw it as no data.
    func testDaysWithNoSessionsAreStillInTheWindow() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertEqual(window.dayCount, 7)
        XCTAssertTrue(window.days.contains(ReportFixtures.day(3)))
    }

    // MARK: - Daylight saving

    // America/New_York loses an hour on 9 March 2025 and gains one on 2 November 2025.
    // A window across either still holds the right number of days, each at local midnight.
    func testAWindowAcrossSpringForwardKeepsItsDayCount() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        var noon = DateComponents()
        noon.year = 2025; noon.month = 3; noon.day = 12; noon.hour = 12
        let endingOn = try XCTUnwrap(newYork.date(from: noon))

        let window = try XCTUnwrap(ReportWindow(days: 7, endingOn: endingOn, calendar: newYork))
        XCTAssertEqual(window.dayCount, 7)
        for day in window.days {
            XCTAssertEqual(day, newYork.startOfDay(for: day))
        }
    }

    func testAWindowAcrossFallBackKeepsItsDayCount() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        var noon = DateComponents()
        noon.year = 2025; noon.month = 11; noon.day = 5; noon.hour = 12
        let endingOn = try XCTUnwrap(newYork.date(from: noon))

        let window = try XCTUnwrap(ReportWindow(days: 7, endingOn: endingOn, calendar: newYork))
        XCTAssertEqual(window.dayCount, 7)
        for day in window.days {
            XCTAssertEqual(day, newYork.startOfDay(for: day))
        }
    }

    // The spring-forward day is 23 hours, so a 7-day window is not 7 * 86400 seconds.
    // This is why the window never divides by 86400.
    func testAWindowAcrossSpringForwardIsNotSevenTimesEightySixThousandFourHundred() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        var noon = DateComponents()
        noon.year = 2025; noon.month = 3; noon.day = 12; noon.hour = 12
        let endingOn = try XCTUnwrap(newYork.date(from: noon))

        let window = try XCTUnwrap(ReportWindow(days: 7, endingOn: endingOn, calendar: newYork))
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 7 * 86_400 - 3_600, accuracy: 1)
    }

    // MARK: - Epochs for Core Data predicates

    func testTheEpochsMatchTheDates() throws {
        let window = try window(days: 7, endingOn: 6)
        XCTAssertEqual(window.startEpoch, window.start.timeIntervalSince1970)
        XCTAssertEqual(window.endEpoch, window.end.timeIntervalSince1970)
    }

    // MARK: - Lengths and scales

    func testEveryLengthHasALabelAndMatchesItsDayCount() {
        for length in ReportWindowLength.allCases {
            XCTAssertFalse(length.label.isEmpty)
            XCTAssertEqual(length.days, length.rawValue)
            XCTAssertGreaterThan(length.days, 0)
        }
    }

    func testTrailingBuildsAWindowOfTheLengthsDays() throws {
        for length in ReportWindowLength.allCases {
            let window = try XCTUnwrap(
                ReportWindow.trailing(length, endingOn: ReportFixtures.day(0), calendar: utc)
            )
            XCTAssertEqual(window.dayCount, length.days, length.label)
        }
    }

    // Each chart offers its own spans, so the report's 7/14/30 selector does not govern the
    // trend or the PDQ-8 chart.
    func testEachScaleOffersItsOwnSpans() {
        XCTAssertEqual(ReportWindowScale.day.lengths, [.week, .twoWeeks, .month])
        XCTAssertEqual(ReportWindowScale.trend.lengths, [.month, .threeMonths, .sixMonths])
        XCTAssertEqual(ReportWindowScale.survey.lengths, [.sixMonths, .year, .twoYears])
    }

    func testEveryScaleDefaultIsOneOfItsOwnSpans() {
        for scale in ReportWindowScale.allCases {
            XCTAssertTrue(
                scale.lengths.contains(scale.defaultLength),
                "\(scale.rawValue) default is not in its own list"
            )
        }
    }

    func testTheDayScaleDefaultsToSevenDays() {
        XCTAssertEqual(ReportWindowScale.day.defaultLength, .week)
    }

    func testTheLongerScalesStartLongerThanTheDayScale() {
        XCTAssertGreaterThan(
            ReportWindowScale.trend.defaultLength.days,
            ReportWindowScale.day.defaultLength.days
        )
        XCTAssertGreaterThan(
            ReportWindowScale.survey.defaultLength.days,
            ReportWindowScale.trend.defaultLength.days
        )
    }

    func testEachScalesSpansAreInAscendingOrder() {
        for scale in ReportWindowScale.allCases {
            XCTAssertEqual(
                scale.lengths.map(\.days),
                scale.lengths.map(\.days).sorted(),
                scale.rawValue
            )
        }
    }

    func testTrailingByScaleUsesThatScalesDefault() throws {
        for scale in ReportWindowScale.allCases {
            let window = try XCTUnwrap(
                ReportWindow.trailing(scale: scale, endingOn: ReportFixtures.day(0), calendar: utc)
            )
            XCTAssertEqual(window.dayCount, scale.defaultLength.days, scale.rawValue)
        }
    }

    // Each chart holds its own window, so two charts can show different spans at once.
    func testTwoScalesProduceDifferentWindowsEndingOnTheSameDay() throws {
        let endingOn = ReportFixtures.day(0)
        let day = try XCTUnwrap(ReportWindow.trailing(scale: .day, endingOn: endingOn, calendar: utc))
        let trend = try XCTUnwrap(ReportWindow.trailing(scale: .trend, endingOn: endingOn, calendar: utc))

        XCTAssertEqual(day.end, trend.end)
        XCTAssertNotEqual(day.start, trend.start)
        XCTAssertLessThan(trend.start, day.start)
    }
}
