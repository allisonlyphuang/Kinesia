import XCTest
@testable import Kinesia

/// Copy is data, so it can be checked like data. These guard the two things that actually matter:
/// nothing is blank, and nothing speaks to the patient in clinical language.
final class AkinesiaCopyTests: XCTestCase {

    private var allStrings: [String] {
        var strings = AkinesiaCopy.setup
        strings += [
            AkinesiaCopy.title,
            AkinesiaCopy.startButton,
            AkinesiaCopy.returnHome,
            AkinesiaCopy.saveFailed,
            AkinesiaCopy.practiceIntro(rounds: 2),
            AkinesiaCopy.progress(round: 5, of: 12),
            AkinesiaCopy.practiceProgress(round: 1, of: 2),
            AkinesiaCopy.finished(caught: 11, of: 12)
        ]
        strings += [
            AkinesiaTestModel.RoundFeedback.caught,
            .falseStart, .slip, .missed, .interrupted
        ].map(AkinesiaCopy.feedback)
        return strings
    }

    func testNoStringIsEmpty() {
        for string in allStrings {
            XCTAssertFalse(string.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testNoStringUsesClinicalOrInternalVocabulary() {
        // The patient should never read our variable names or the research terms behind them.
        let banned = [
            "akinesia", "bradykinesia", "reaction time", "movement time", "trial", "valid",
            "invalid", "anticipation", "lapse", "foreperiod", "stimulus", "latency", "metric",
            "parkinson", "cue onset", "lift-off", "capture"
        ]
        for string in allStrings {
            let lowered = string.lowercased()
            for word in banned {
                XCTAssertFalse(lowered.contains(word), "\"\(string)\" contains \"\(word)\"")
            }
        }
    }

    func testEveryRoundOutcomeHasSomethingToSay() {
        let feedbacks: [AkinesiaTestModel.RoundFeedback] = [.caught, .falseStart, .slip, .missed, .interrupted]
        let messages = Set(feedbacks.map(AkinesiaCopy.feedback))
        XCTAssertEqual(messages.count, feedbacks.count, "two outcomes share a message")
    }

    func testFailureMessagesDoNotBlameThePatient() {
        // A false start is the game's fault, not theirs.
        let blaming = ["you failed", "you were wrong", "incorrect", "error", "you didn't", "too slow"]
        for feedback in [AkinesiaTestModel.RoundFeedback.falseStart, .slip, .missed] {
            let lowered = AkinesiaCopy.feedback(feedback).lowercased()
            for phrase in blaming {
                XCTAssertFalse(lowered.contains(phrase), "\(feedback) message blames the patient")
            }
        }
    }

    func testPracticeIntroAgreesWithItsCount() {
        XCTAssertTrue(AkinesiaCopy.practiceIntro(rounds: 1).contains("firefly"))
        XCTAssertTrue(AkinesiaCopy.practiceIntro(rounds: 2).contains("fireflies"))
    }

    func testPracticeProgressIsDistinctFromScoredProgress() {
        // Telling someone they are on scored round 1 of 12 while they are still warming up is
        // both wrong and discouraging.
        let practice = AkinesiaCopy.practiceProgress(round: 1, of: 2)
        let scored = AkinesiaCopy.progress(round: 1, of: 12)
        XCTAssertNotEqual(practice, scored)
        XCTAssertTrue(practice.lowercased().contains("practice"))
        XCTAssertFalse(scored.lowercased().contains("practice"))
    }

    func testProgressAndFinishedReportTheNumbersGiven() {
        XCTAssertTrue(AkinesiaCopy.progress(round: 5, of: 12).contains("5"))
        XCTAssertTrue(AkinesiaCopy.progress(round: 5, of: 12).contains("12"))
        XCTAssertTrue(AkinesiaCopy.finished(caught: 11, of: 12).contains("11"))
    }
}
