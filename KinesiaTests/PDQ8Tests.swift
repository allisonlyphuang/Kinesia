import XCTest
@testable import Kinesia

/// PDQ-8 scoring arithmetic. Pure: no Core Data, no view.
final class PDQ8Tests: XCTestCase {

    private func responses(_ values: [PDQ8Response]) -> [PDQ8Item: PDQ8Response] {
        Dictionary(uniqueKeysWithValues: zip(PDQ8Item.allCases, values))
    }

    // MARK: - Instrument shape

    func testThereAreExactlyEightItems() {
        XCTAssertEqual(PDQ8Item.allCases.count, 8)
        XCTAssertEqual(PDQ8Score.itemCount, 8)
    }

    func testThereAreFiveResponsesScoredZeroToFour() {
        XCTAssertEqual(PDQ8Response.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
        XCTAssertEqual(PDQ8Score.maximumItemScore, 4)
    }

    func testEveryItemHasAPromptAndADimension() {
        for item in PDQ8Item.allCases {
            XCTAssertFalse(item.prompt.isEmpty, "\(item) has no prompt")
            XCTAssertFalse(item.dimension.isEmpty, "\(item) has no dimension")
        }
    }

    /// One item per PDQ-39 dimension is the definition of the short form.
    func testEveryItemCoversADifferentDimension() {
        let dimensions = PDQ8Item.allCases.map(\.dimension)
        XCTAssertEqual(Set(dimensions).count, dimensions.count)
    }

    func testEveryResponseHasALabel() {
        for response in PDQ8Response.allCases {
            XCTAssertFalse(response.label.isEmpty)
        }
    }

    // MARK: - Scoring

    func testAllNeverScoresZero() throws {
        let score = try PDQ8Score.compute(from: responses(Array(repeating: .never, count: 8)))
        XCTAssertEqual(score.rawSum, 0)
        XCTAssertEqual(score.scoreIndex, 0, accuracy: 1e-9)
    }

    func testAllAlwaysScoresTheMaximum() throws {
        let score = try PDQ8Score.compute(from: responses(Array(repeating: .always, count: 8)))
        XCTAssertEqual(score.rawSum, 32)
        XCTAssertEqual(score.scoreIndex, 100, accuracy: 1e-9)
    }

    func testAllSometimesScoresTheMidpoint() throws {
        let score = try PDQ8Score.compute(from: responses(Array(repeating: .sometimes, count: 8)))
        XCTAssertEqual(score.rawSum, 16)
        XCTAssertEqual(score.scoreIndex, 50, accuracy: 1e-9)
    }

    func testScoreIndexIsRawSumOverThirtyTwoAsAPercentage() throws {
        let mixed: [PDQ8Response] = [.never, .occasionally, .sometimes, .often, .always, .never, .often, .sometimes]
        let score = try PDQ8Score.compute(from: responses(mixed))
        XCTAssertEqual(score.rawSum, 0 + 1 + 2 + 3 + 4 + 0 + 3 + 2)
        XCTAssertEqual(score.scoreIndex, 15.0 / 32.0 * 100, accuracy: 1e-9)
    }

    func testItemScoresArePreservedInItemOrder() throws {
        let mixed: [PDQ8Response] = [.always, .never, .often, .never, .never, .never, .never, .never]
        let score = try PDQ8Score.compute(from: responses(mixed))
        XCTAssertEqual(score.itemScores, [4, 0, 3, 0, 0, 0, 0, 0])
    }

    // MARK: - Refusing to score a partial questionnaire

    /// A missing item is not a zero. Scoring seven items out of eight would understate the index
    /// and the trend chart would show an improvement that did not happen.
    func testAMissingItemIsRejectedRatherThanTreatedAsZero() {
        var partial = responses(Array(repeating: .often, count: 8))
        partial[.cramps] = nil

        XCTAssertThrowsError(try PDQ8Score.compute(from: partial)) { error in
            XCTAssertEqual(error as? PDQ8Error, .incompleteResponses(answered: 7, expected: 8))
        }
    }

    func testAnEmptyQuestionnaireIsRejected() {
        XCTAssertThrowsError(try PDQ8Score.compute(from: [:])) { error in
            XCTAssertEqual(error as? PDQ8Error, .incompleteResponses(answered: 0, expected: 8))
        }
    }

    // MARK: - Decoding stored values

    func testComputeFromStoredItemScoresMatchesTheOriginal() throws {
        let original = try PDQ8Score.compute(from: responses([.never, .often, .always, .sometimes, .never, .occasionally, .often, .never]))
        let roundTripped = try PDQ8Score.compute(itemScores: original.itemScores)
        XCTAssertEqual(roundTripped, original)
    }

    func testTooFewStoredItemScoresAreRejected() {
        XCTAssertThrowsError(try PDQ8Score.compute(itemScores: [0, 1, 2])) { error in
            XCTAssertEqual(error as? PDQ8Error, .incompleteResponses(answered: 3, expected: 8))
        }
    }

    func testTooManyStoredItemScoresAreRejected() {
        XCTAssertThrowsError(try PDQ8Score.compute(itemScores: Array(repeating: 1, count: 9)))
    }

    func testAnOutOfRangeStoredItemScoreIsRejected() {
        var scores: [Int16] = Array(repeating: 0, count: 8)
        scores[3] = 5
        XCTAssertThrowsError(try PDQ8Score.compute(itemScores: scores)) { error in
            XCTAssertEqual(error as? PDQ8Error, .itemScoreOutOfRange(item: 3, score: 5))
        }
    }

    func testANegativeStoredItemScoreIsRejected() {
        var scores: [Int16] = Array(repeating: 0, count: 8)
        scores[0] = -1
        XCTAssertThrowsError(try PDQ8Score.compute(itemScores: scores)) { error in
            XCTAssertEqual(error as? PDQ8Error, .itemScoreOutOfRange(item: 0, score: -1))
        }
    }

    func testTheBoundaryItemScoresAreAccepted() {
        XCTAssertNoThrow(try PDQ8Score.compute(itemScores: Array(repeating: 0, count: 8)))
        XCTAssertNoThrow(try PDQ8Score.compute(itemScores: Array(repeating: 4, count: 8)))
    }
}
