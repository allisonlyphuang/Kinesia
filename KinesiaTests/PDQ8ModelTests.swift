import CoreData
import XCTest
@testable import Kinesia

@MainActor
final class PDQ8ModelTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = try TestCoreDataStack.makeInMemoryContainer()
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    private let completionDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel() -> PDQ8Model {
        PDQ8Model(context: context, now: { self.completionDate })
    }

    private func answerEverything(_ model: PDQ8Model, with response: PDQ8Response = .sometimes) {
        for _ in model.items {
            model.select(response)
            model.advance()
        }
    }

    // MARK: - Progress

    func testStartsOnTheFirstItemWithNothingAnswered() {
        let model = makeModel()

        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertEqual(model.currentItem, PDQ8Item.allCases[0])
        XCTAssertNil(model.currentResponse)
        XCTAssertEqual(model.answeredCount, 0)
        XCTAssertFalse(model.isComplete)
        XCTAssertFalse(model.isLastItem)
    }

    /// Selecting does not advance: an auto-advance makes a mis-tap unrecoverable.
    func testSelectingAnAnswerDoesNotAdvance() {
        let model = makeModel()
        model.select(.often)

        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertEqual(model.currentResponse, .often)
    }

    func testAnAnswerCanBeChangedBeforeMovingOn() {
        let model = makeModel()
        model.select(.often)
        model.select(.never)

        XCTAssertEqual(model.currentResponse, .never)
        XCTAssertEqual(model.answeredCount, 1)
    }

    func testGoingBackShowsThePreviousAnswer() {
        let model = makeModel()
        model.select(.always)
        model.advance()
        model.select(.never)
        model.goBack()

        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertEqual(model.currentResponse, .always)
    }

    func testGoingBackFromTheFirstItemDoesNothing() {
        let model = makeModel()
        model.goBack()
        XCTAssertEqual(model.currentIndex, 0)
    }

    func testAdvancingPastTheLastItemDoesNothing() {
        let model = makeModel()
        answerEverything(model)

        XCTAssertEqual(model.currentIndex, model.items.count - 1)
        XCTAssertTrue(model.isLastItem)
        model.advance()
        XCTAssertEqual(model.currentIndex, model.items.count - 1)
    }

    func testIsCompleteOnlyAfterEveryItemIsAnswered() {
        let model = makeModel()
        for index in 0..<model.items.count {
            XCTAssertEqual(model.isComplete, false, "complete after \(index) answers")
            model.select(.sometimes)
            model.advance()
        }
        XCTAssertTrue(model.isComplete)
    }

    // MARK: - Submitting

    func testSubmittingACompleteQuestionnaireSavesOneRow() throws {
        let model = makeModel()
        answerEverything(model, with: .sometimes)

        XCTAssertTrue(model.submit())
        XCTAssertNil(model.saveError)
        XCTAssertEqual(model.savedScore?.rawSum, 16)
        XCTAssertEqual(try context.count(for: PDQ8Log.fetchRequest()), 1)

        let log = try XCTUnwrap(try PDQ8Store.fetchLatest(in: context))
        XCTAssertEqual(log.timestamp, completionDate.timeIntervalSince1970)
        XCTAssertEqual(log.rawSum, 16)
    }

    /// A partially answered questionnaire is discarded, not scored with the gaps as zeros.
    func testSubmittingAnIncompleteQuestionnaireWritesNothing() throws {
        let model = makeModel()
        model.select(.often)
        model.advance()
        model.select(.often)

        XCTAssertFalse(model.submit())
        XCTAssertNotNil(model.saveError)
        XCTAssertNil(model.savedScore)
        XCTAssertEqual(try context.count(for: PDQ8Log.fetchRequest()), 0)
    }

    func testTheSavedItemScoresMatchWhatWasAnswered() throws {
        let model = makeModel()
        let answers: [PDQ8Response] = [.never, .occasionally, .sometimes, .often, .always, .never, .often, .sometimes]
        for answer in answers {
            model.select(answer)
            model.advance()
        }

        XCTAssertTrue(model.submit())
        let log = try XCTUnwrap(try PDQ8Store.fetchLatest(in: context))
        XCTAssertEqual(try log.decodedScore().itemScores, [0, 1, 2, 3, 4, 0, 3, 2])
    }

    func testResetClearsEverything() {
        let model = makeModel()
        answerEverything(model)
        XCTAssertTrue(model.submit())

        model.reset()

        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertEqual(model.answeredCount, 0)
        XCTAssertNil(model.savedScore)
        XCTAssertNil(model.saveError)
    }
}
