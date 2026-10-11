import XCTest
@testable import Kinesia

@MainActor
final class SummaryStatsTests: XCTestCase {
    func testComputeReturnsExpectedDescriptiveStatistics() throws {
        let stats = try XCTUnwrap(SummaryStats.compute([1, 2, 3, 4]))

        XCTAssertEqual(stats.min, 1, accuracy: 0.000_001)
        XCTAssertEqual(stats.max, 4, accuracy: 0.000_001)
        XCTAssertEqual(stats.mean, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.median, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.p25, 1.75, accuracy: 0.000_001)
        XCTAssertEqual(stats.p75, 3.25, accuracy: 0.000_001)
        // 0.9 * (4 - 1) = 2.7, so 30% of sorted[2] plus 70% of sorted[3].
        XCTAssertEqual(stats.p90, 3.7, accuracy: 0.000_001)
        XCTAssertEqual(stats.range, 3, accuracy: 0.000_001)
        XCTAssertEqual(stats.iqr, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, sqrt(5.0 / 3.0), accuracy: 0.000_001)
        // Deviations from the median of 2.5 are [1.5, 0.5, 0.5, 1.5]; their median is 1.
        XCTAssertEqual(stats.mad, 1, accuracy: 0.000_001)
    }

    func testComputeReturnsNilForEmptyInput() {
        XCTAssertNil(SummaryStats.compute([]))
    }

    func testComputeReturnsNilForOneValue() {
        XCTAssertNil(SummaryStats.compute([5]))
    }

    func testComputeHandlesConstantValues() throws {
        let stats = try XCTUnwrap(SummaryStats.compute([2, 2, 2, 2]))

        XCTAssertEqual(stats.mean, 2, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0, accuracy: 0.000_001)
        XCTAssertEqual(stats.range, 0, accuracy: 0.000_001)
        XCTAssertEqual(stats.iqr, 0, accuracy: 0.000_001)
        XCTAssertEqual(stats.p90, 2, accuracy: 0.000_001)
        XCTAssertEqual(stats.mad, 0, accuracy: 0.000_001)
    }

    func testComputeReturnsNilForNaN() {
        XCTAssertNil(SummaryStats.compute([1, .nan, 3]))
    }

    func testComputeReturnsNilForInfinity() {
        XCTAssertNil(SummaryStats.compute([1, .infinity, 3]))
    }

    func testNinetiethPercentileInterpolatesForOddCount() throws {
        // 0.9 * (5 - 1) = 3.6, so 40% of sorted[3] plus 60% of sorted[4].
        let stats = try XCTUnwrap(SummaryStats.compute([1, 2, 3, 4, 5]))
        XCTAssertEqual(stats.p90, 4.6, accuracy: 0.000_001)
    }

    func testNinetiethPercentileIsBoundedByTheExtremesForTwoValues() throws {
        let stats = try XCTUnwrap(SummaryStats.compute([1, 2]))
        XCTAssertEqual(stats.p90, 1.9, accuracy: 0.000_001)
    }

    func testNinetiethPercentileIgnoresInputOrder() throws {
        let ascending = try XCTUnwrap(SummaryStats.compute([1, 2, 3, 4]))
        let shuffled = try XCTUnwrap(SummaryStats.compute([4, 1, 3, 2]))
        XCTAssertEqual(ascending.p90, shuffled.p90, accuracy: 0.000_001)
        XCTAssertEqual(ascending.mad, shuffled.mad, accuracy: 0.000_001)
    }

    func testMedianAbsoluteDeviationUsesMedianOfDeviationsForOddCount() throws {
        // Median 3; deviations [2, 1, 0, 1, 2] have a median of 1.
        let result = try XCTUnwrap(SummaryStats.medianAbsoluteDeviation([1, 2, 3, 4, 5]))
        XCTAssertEqual(result, 1, accuracy: 0.000_001)
    }

    func testMedianAbsoluteDeviationIsRobustToAnOutlier() throws {
        // A single extreme value inflates the standard deviation but leaves MAD unchanged.
        let stats = try XCTUnwrap(SummaryStats.compute([1, 2, 3, 4, 100]))
        XCTAssertEqual(stats.mad, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(stats.stdev, 40)
    }

    func testMedianAbsoluteDeviationIsZeroForConstantAndSingleValues() throws {
        let constant = try XCTUnwrap(SummaryStats.medianAbsoluteDeviation([7, 7, 7]))
        XCTAssertEqual(constant, 0, accuracy: 0.000_001)

        let single = try XCTUnwrap(SummaryStats.medianAbsoluteDeviation([5]))
        XCTAssertEqual(single, 0, accuracy: 0.000_001)
    }

    func testMedianAbsoluteDeviationReturnsNilForEmptyOrNonFiniteInput() {
        XCTAssertNil(SummaryStats.medianAbsoluteDeviation([]))
        XCTAssertNil(SummaryStats.medianAbsoluteDeviation([1, .nan, 3]))
        XCTAssertNil(SummaryStats.medianAbsoluteDeviation([1, .infinity, 3]))
    }

    func testPopulationStandardDeviationUsesPopulationDenominator() throws {
        let result = try XCTUnwrap(SummaryStats.populationStandardDeviation([1, 2, 3]))
        XCTAssertEqual(result, sqrt(2.0 / 3.0), accuracy: 0.000_001)
    }

    func testPaperCoefficientOfVariationUsesPopulationStandardDeviation() throws {
        let result = try XCTUnwrap(SummaryStats.paperCoefficientOfVariation([1, 2, 3]))
        XCTAssertEqual(result, sqrt(2.0 / 3.0) / 2 * 100, accuracy: 0.000_001)
    }

    func testPaperPopulationSkewnessIsZeroForSymmetricValues() throws {
        let result = try XCTUnwrap(SummaryStats.paperPopulationSkewness([1, 2, 3]))
        XCTAssertEqual(result, 0, accuracy: 0.000_001)
    }

    func testCoefficientOfVariationReturnsNilForZeroMean() {
        XCTAssertNil(SummaryStats.paperCoefficientOfVariation([-1, 1]))
    }

    func testConstantValuesHaveZeroPopulationStandardDeviationAndNoSkewness() throws {
        let stdev = try XCTUnwrap(SummaryStats.populationStandardDeviation([5, 5, 5]))
        XCTAssertEqual(stdev, 0, accuracy: 0.000_001)
        XCTAssertNil(SummaryStats.paperPopulationSkewness([5, 5, 5]))
    }

    func testPaperHelpersReturnNilForNonFiniteValues() {
        XCTAssertNil(SummaryStats.populationStandardDeviation([1, .nan, 3]))
        XCTAssertNil(SummaryStats.paperCoefficientOfVariation([1, .infinity, 3]))
        XCTAssertNil(SummaryStats.paperPopulationSkewness([1, .nan, 3]))
    }
}
