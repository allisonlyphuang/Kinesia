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
        XCTAssertEqual(stats.range, 3, accuracy: 0.000_001)
        XCTAssertEqual(stats.iqr, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, sqrt(5.0 / 3.0), accuracy: 0.000_001)
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
    }

    func testComputeReturnsNilForNaN() {
        XCTAssertNil(SummaryStats.compute([1, .nan, 3]))
    }

    func testComputeReturnsNilForInfinity() {
        XCTAssertNil(SummaryStats.compute([1, .infinity, 3]))
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
