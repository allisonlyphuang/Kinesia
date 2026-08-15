import XCTest
@testable import Kinesia

@MainActor
final class BradykinesiaAnalyzerTests: XCTestCase {
    func testTapIntervalsForRegularTapping() throws {
        let intervals = try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.5, 1, 1.5, 2])))
        XCTAssertEqual(intervals.count, 4)
        intervals.forEach { XCTAssertEqual($0, 0.5, accuracy: 0.000_001) }
    }

    func testTapIntervalsForIrregularTapping() throws {
        let intervals = try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.25, 0.75, 1.5])))
        XCTAssertEqual(intervals, [0.25, 0.5, 0.75])
    }

    func testTapIntervalsForZeroTapsAreEmpty() throws {
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: [])), [])
    }

    func testTapIntervalsForOneTapAreEmpty() throws {
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0]))), [])
    }

    func testTapIntervalsForTwoTapsContainOneInterval() throws {
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.5]))), [0.5])
    }

    func testTapIntervalsRejectRepeatedTimestampWithoutDroppingIt() {
        XCTAssertNil(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 0.5, 0.5, 1])))
    }

    func testTapIntervalsRejectBackwardsTimestampWithoutSorting() {
        XCTAssertNil(BradykinesiaAnalyzer.tapIntervals(from: samples([0, 1, 0.75])))
    }

    func testTapIntervalsRejectNonFiniteTimestamp() {
        XCTAssertNil(BradykinesiaAnalyzer.tapIntervals(from: samples([0, .nan, 1])))
    }
        
    func testCorrectTapsCountPerfectAlternationFromTheRight() {
        XCTAssertEqual(
            BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.right, .left, .right, .left])),
            4
        )
    }

    func testCorrectTapsRequireTheSequenceToOpenOnTheRight() {
        // The opening tap is on the wrong side and is lost; the rest fall into rhythm.
        XCTAssertEqual(
            BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.left, .right, .left, .right])),
            3
        )
    }

    func testMissesAreNotCountedAndDoNotAdvanceTheExpectedTarget() {
        // After the miss, `.left` is still the target that was owed.
        XCTAssertEqual(
            BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.right, .miss, .left])),
            2
        )
    }

    func testWrongTargetHitsAreNotCountedAndDoNotAdvanceTheExpectedTarget() {
        XCTAssertEqual(
            BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.right, .right, .left])),
            2
        )
    }

    func testCorrectTapsForSingleAndEmptySequences() {
        XCTAssertEqual(BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.right])), 1)
        XCTAssertEqual(BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.left])), 0)
        XCTAssertEqual(BradykinesiaAnalyzer.correctTapCount(from: targetSamples([.miss, .miss])), 0)
        XCTAssertEqual(BradykinesiaAnalyzer.correctTapCount(from: []), 0)
    }

    func testCorrectTapsNeverExceedTotalTaps() {
        let trial = trial(timestamps: [0, 0.5, 1, 1.5, 2])
        let metrics = BradykinesiaAnalyzer.analyze(trial)
        XCTAssertLessThanOrEqual(metrics.numCorrectTaps, metrics.numTaps)
    }

    func testAnalyzeRegularTrial() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0, 0.5, 1, 1.5, 2]))
        let stats = try XCTUnwrap(metrics.tapInterStats)

        XCTAssertEqual(metrics.numTaps, 5)
        XCTAssertEqual(metrics.tapIntervals, [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(stats.min, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.max, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.mean, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.median, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0, accuracy: 0.000_001)
        let coefficientOfVariation = try XCTUnwrap(metrics.cvTapInter)
        XCTAssertEqual(coefficientOfVariation, 0, accuracy: 0.000_001)
        XCTAssertNil(metrics.skewTapInter)
        XCTAssertEqual(metrics.numCorrectTaps, 0)
    }

    func testAnalyzeIrregularTrial() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0, 0.25, 0.75, 1.5]))
        let stats = try XCTUnwrap(metrics.tapInterStats)

        XCTAssertEqual(metrics.tapIntervals, [0.25, 0.5, 0.75])
        XCTAssertEqual(stats.mean, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.median, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.stdev, 0.25, accuracy: 0.000_001)
        let coefficientOfVariation = try XCTUnwrap(metrics.cvTapInter)
        let skewness = try XCTUnwrap(metrics.skewTapInter)
        XCTAssertEqual(coefficientOfVariation, sqrt(2.0 / 3.0) / 2 * 100, accuracy: 0.000_001)
        XCTAssertEqual(skewness, 0, accuracy: 0.000_001)
    }

    func testAnalyzeInsufficientTapCounts() {
        let zeroTapMetrics = BradykinesiaAnalyzer.analyze(trial(timestamps: []))
        XCTAssertEqual(zeroTapMetrics.numTaps, 0)
        XCTAssertEqual(zeroTapMetrics.tapIntervals, [])
        XCTAssertNil(zeroTapMetrics.tapInterStats)
        XCTAssertNil(zeroTapMetrics.cvTapInter)
        XCTAssertNil(zeroTapMetrics.skewTapInter)

        let oneTapMetrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0]))
        XCTAssertEqual(oneTapMetrics.numTaps, 1)
        XCTAssertEqual(oneTapMetrics.tapIntervals, [])
        XCTAssertNil(oneTapMetrics.tapInterStats)
        XCTAssertNil(oneTapMetrics.cvTapInter)
        XCTAssertNil(oneTapMetrics.skewTapInter)

        let twoTapMetrics = BradykinesiaAnalyzer.analyze(trial(timestamps: [0, 0.5]))
        XCTAssertEqual(twoTapMetrics.numTaps, 2)
        XCTAssertEqual(twoTapMetrics.tapIntervals, [0.5])
        XCTAssertNil(twoTapMetrics.tapInterStats)
        XCTAssertNil(twoTapMetrics.cvTapInter)
        XCTAssertNil(twoTapMetrics.skewTapInter)
    }

    func testAnalyzeInvalidTimestampsPreservesTapCountAndMakesTemporalMetricsUnavailable() {
        let sourceSamples = samples([0, 0.5, 0.5, 1])
        let metrics = BradykinesiaAnalyzer.analyze(trial(samples: sourceSamples))

        XCTAssertEqual(metrics.numTaps, sourceSamples.count)
        XCTAssertNil(metrics.tapIntervals)
        XCTAssertNil(metrics.tapInterStats)
        XCTAssertNil(metrics.cvTapInter)
        XCTAssertNil(metrics.skewTapInter)
    }

    func testEuclideanDistanceIsFiniteSafe() throws {
        let origin = TapSample(t: 0, x: 0, y: 0, target: .left)
        let threeFour = TapSample(t: 1, x: 3, y: 4, target: .right)

        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.euclideanDistance(from: origin, to: threeFour)), 5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(BradykinesiaAnalyzer.euclideanDistance(from: origin, to: origin)), 0, accuracy: 0.000_001)
        XCTAssertNil(BradykinesiaAnalyzer.euclideanDistance(
            from: origin,
            to: TapSample(t: 1, x: .nan, y: 4, target: .miss)
        ))
    }

    func testPaperSpatialPartitionAndDriftPreserveOriginalOrder() throws {
        let sourceSamples = spatialSamples([
            (0, 0), (10, 0), (0, 3), (10, 4), (0, 7), (10, 9)
        ])
        let partition = try XCTUnwrap(BradykinesiaAnalyzer.paperSpatialPartition(from: sourceSamples))
        let metrics = BradykinesiaAnalyzer.analyze(trial(samples: sourceSamples))
        let leftDrift = try XCTUnwrap(metrics.leftDrift)
        let rightDrift = try XCTUnwrap(metrics.rightDrift)
        let leftStats = try XCTUnwrap(metrics.driftLeftStats)
        let rightStats = try XCTUnwrap(metrics.driftRightStats)

        XCTAssertEqual(partition.meanX, 5, accuracy: 0.000_001)
        XCTAssertEqual(partition.leftSamples.map(\.x), [0, 0, 0])
        XCTAssertEqual(partition.leftSamples.map(\.y), [0, 3, 7])
        XCTAssertEqual(partition.rightSamples.map(\.x), [10, 10, 10])
        XCTAssertEqual(partition.rightSamples.map(\.y), [0, 4, 9])
        XCTAssertEqual(leftDrift, [3, 4])
        XCTAssertEqual(rightDrift, [4, 5])
        XCTAssertEqual(leftStats.mean, 3.5, accuracy: 0.000_001)
        XCTAssertEqual(leftStats.median, 3.5, accuracy: 0.000_001)
        XCTAssertEqual(rightStats.mean, 4.5, accuracy: 0.000_001)
        XCTAssertEqual(rightStats.median, 4.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.cvDriftLeft), 100.0 / 7.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.cvDriftRight), 100.0 / 9.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.skewDriftLeft), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.skewDriftRight), 0, accuracy: 0.000_001)
    }

    func testPaperSpatialMetricsIgnoreTapTargetClassification() throws {
        let coordinates = [(0.0, 0.0), (10.0, 0.0), (0.0, 3.0), (10.0, 4.0), (0.0, 7.0), (10.0, 9.0)]
        let firstSamples = spatialSamples(
            coordinates,
            targets: [.left, .right, .left, .right, .left, .right]
        )
        let secondSamples = spatialSamples(
            coordinates,
            targets: [.miss, .miss, .right, .left, .miss, .left]
        )
        let firstPartition = try XCTUnwrap(BradykinesiaAnalyzer.paperSpatialPartition(from: firstSamples))
        let secondPartition = try XCTUnwrap(BradykinesiaAnalyzer.paperSpatialPartition(from: secondSamples))
        let first = BradykinesiaAnalyzer.analyze(trial(samples: firstSamples))
        let second = BradykinesiaAnalyzer.analyze(trial(samples: secondSamples))

        XCTAssertEqual(firstPartition.meanX, secondPartition.meanX, accuracy: 0.000_001)
        XCTAssertEqual(firstPartition.leftSamples.map(\.x), secondPartition.leftSamples.map(\.x))
        XCTAssertEqual(firstPartition.leftSamples.map(\.y), secondPartition.leftSamples.map(\.y))
        XCTAssertEqual(firstPartition.rightSamples.map(\.x), secondPartition.rightSamples.map(\.x))
        XCTAssertEqual(firstPartition.rightSamples.map(\.y), secondPartition.rightSamples.map(\.y))
        XCTAssertEqual(first.leftDrift, second.leftDrift)
        XCTAssertEqual(first.rightDrift, second.rightDrift)
        XCTAssertEqual(first.cvDriftLeft, second.cvDriftLeft)
        XCTAssertEqual(first.cvDriftRight, second.cvDriftRight)
        XCTAssertEqual(first.skewDriftLeft, second.skewDriftLeft)
        XCTAssertEqual(first.skewDriftRight, second.skewDriftRight)
        XCTAssertEqual(first.corXY, second.corXY)
        assertStats(first.driftLeftStats, equals: second.driftLeftStats)
        assertStats(first.driftRightStats, equals: second.driftRightStats)
    }

    func testPearsonCorrelationHandlesPerfectPositiveAndNegativeRelationships() throws {
        let positive = try XCTUnwrap(BradykinesiaAnalyzer.pearsonCorrelationXY(from: spatialSamples([
            (1, 2), (2, 4), (3, 6)
        ])))
        let negative = try XCTUnwrap(BradykinesiaAnalyzer.pearsonCorrelationXY(from: spatialSamples([
            (1, 6), (2, 4), (3, 2)
        ])))

        XCTAssertEqual(positive, 1, accuracy: 0.000_001)
        XCTAssertEqual(negative, -1, accuracy: 0.000_001)
    }

    func testPearsonCorrelationIsUnavailableForInsufficientConstantOrInvalidCoordinates() {
        XCTAssertNil(BradykinesiaAnalyzer.pearsonCorrelationXY(from: []))
        XCTAssertNil(BradykinesiaAnalyzer.pearsonCorrelationXY(from: spatialSamples([(1, 2)])))
        XCTAssertNil(BradykinesiaAnalyzer.pearsonCorrelationXY(from: spatialSamples([(2, 1), (2, 2), (2, 3)])))
        XCTAssertNil(BradykinesiaAnalyzer.pearsonCorrelationXY(from: spatialSamples([(1, 2), (2, 2), (3, 2)])))
        XCTAssertNil(BradykinesiaAnalyzer.pearsonCorrelationXY(from: spatialSamples([(1, 2), (.infinity, 3)])))
    }

    func testSpatialMetricsHandleEmptyAndOneSampleTrials() throws {
        let emptyMetrics = BradykinesiaAnalyzer.analyze(trial(samples: []))
        XCTAssertEqual(emptyMetrics.leftDrift, [])
        XCTAssertEqual(emptyMetrics.rightDrift, [])
        XCTAssertNil(emptyMetrics.corXY)

        let oneSample = spatialSamples([(10, 4)])
        let partition = try XCTUnwrap(BradykinesiaAnalyzer.paperSpatialPartition(from: oneSample))
        let oneSampleMetrics = BradykinesiaAnalyzer.analyze(trial(samples: oneSample))
        XCTAssertEqual(partition.meanX, 10, accuracy: 0.000_001)
        XCTAssertTrue(partition.leftSamples.isEmpty)
        XCTAssertEqual(partition.rightSamples.map(\.x), [10])
        XCTAssertEqual(oneSampleMetrics.leftDrift, [])
        XCTAssertEqual(oneSampleMetrics.rightDrift, [])
        XCTAssertNil(oneSampleMetrics.driftLeftStats)
        XCTAssertNil(oneSampleMetrics.driftRightStats)
    }

    func testSpatialMetricsHandleSideInsufficiencyAndOneDrift() throws {
        let oneLeft = BradykinesiaAnalyzer.analyze(trial(samples: spatialSamples([
            (0, 0), (10, 0), (10, 4), (10, 9)
        ])))
        XCTAssertEqual(oneLeft.leftDrift, [])
        XCTAssertNil(oneLeft.driftLeftStats)
        XCTAssertNil(oneLeft.cvDriftLeft)
        XCTAssertNil(oneLeft.skewDriftLeft)
        XCTAssertEqual(try XCTUnwrap(oneLeft.rightDrift), [4, 5])
        XCTAssertNotNil(oneLeft.driftRightStats)

        let oneRight = BradykinesiaAnalyzer.analyze(trial(samples: spatialSamples([
            (0, 0), (0, 3), (0, 7), (10, 0)
        ])))
        XCTAssertEqual(try XCTUnwrap(oneRight.leftDrift), [3, 4])
        XCTAssertEqual(oneRight.rightDrift, [])
        XCTAssertNil(oneRight.driftRightStats)
        XCTAssertNil(oneRight.cvDriftRight)
        XCTAssertNil(oneRight.skewDriftRight)

        let oneDrift = BradykinesiaAnalyzer.analyze(trial(samples: spatialSamples([
            (0, 0), (10, 0), (0, 3)
        ])))
        XCTAssertEqual(try XCTUnwrap(oneDrift.leftDrift), [3])
        XCTAssertNil(oneDrift.driftLeftStats)
        XCTAssertNil(oneDrift.cvDriftLeft)
        XCTAssertNil(oneDrift.skewDriftLeft)
    }

    func testConstantPositiveDriftHasZeroCVAndUnavailableSkewness() throws {
        let metrics = BradykinesiaAnalyzer.analyze(trial(samples: spatialSamples([
            (0, 0), (10, 0), (0, 2), (10, 5), (0, 4), (10, 10)
        ])))
        let leftStats = try XCTUnwrap(metrics.driftLeftStats)

        XCTAssertEqual(try XCTUnwrap(metrics.leftDrift), [2, 2])
        XCTAssertEqual(leftStats.mean, 2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.cvDriftLeft), 0, accuracy: 0.000_001)
        XCTAssertNil(metrics.skewDriftLeft)
    }

    func testTemporalAndSpatialValidityRemainIndependent() throws {
        let invalidTimestamps = spatialSamples(
            [(0, 0), (10, 0), (0, 3), (10, 4)],
            timestamps: [0, 0.5, 0.5, 1]
        )
        let spatiallyValid = BradykinesiaAnalyzer.analyze(trial(samples: invalidTimestamps))
        XCTAssertEqual(spatiallyValid.numTaps, 4)
        XCTAssertNil(spatiallyValid.tapIntervals)
        XCTAssertNil(spatiallyValid.tapInterStats)
        XCTAssertEqual(try XCTUnwrap(spatiallyValid.leftDrift), [3])
        XCTAssertEqual(try XCTUnwrap(spatiallyValid.rightDrift), [4])
        XCTAssertNotNil(spatiallyValid.corXY)

        let invalidCoordinates = [
            TapSample(t: 0, x: 0, y: 0, target: .left),
            TapSample(t: 0.5, x: .nan, y: 2, target: .miss),
            TapSample(t: 1, x: 10, y: 4, target: .right)
        ]
        let temporallyValid = BradykinesiaAnalyzer.analyze(trial(samples: invalidCoordinates))
        XCTAssertEqual(try XCTUnwrap(temporallyValid.tapIntervals), [0.5, 0.5])
        XCTAssertNotNil(temporallyValid.tapInterStats)
        XCTAssertNil(temporallyValid.leftDrift)
        XCTAssertNil(temporallyValid.rightDrift)
        XCTAssertNil(temporallyValid.driftLeftStats)
        XCTAssertNil(temporallyValid.driftRightStats)
        XCTAssertNil(temporallyValid.cvDriftLeft)
        XCTAssertNil(temporallyValid.cvDriftRight)
        XCTAssertNil(temporallyValid.skewDriftLeft)
        XCTAssertNil(temporallyValid.skewDriftRight)
        XCTAssertNil(temporallyValid.corXY)
    }

    /// Only `target` matters for correct-tap scoring, so timing and coordinates are filler.
    private func targetSamples(_ targets: [TapTarget]) -> [TapSample] {
        targets.enumerated().map { index, target in
            TapSample(t: Double(index), x: 0, y: 0, target: target)
        }
    }
    
    private func samples(_ timestamps: [TimeInterval]) -> [TapSample] {
        timestamps.enumerated().map { index, timestamp in
            TapSample(t: timestamp, x: Double(index), y: 0, target: .left)
        }
    }

    private func spatialSamples(
        _ coordinates: [(Double, Double)],
        targets: [TapTarget]? = nil,
        timestamps: [TimeInterval]? = nil
    ) -> [TapSample] {
        if let targets {
            precondition(targets.count == coordinates.count)
        }
        if let timestamps {
            precondition(timestamps.count == coordinates.count)
        }

        return coordinates.enumerated().map { index, coordinate in
            TapSample(
                t: timestamps?[index] ?? Double(index),
                x: coordinate.0,
                y: coordinate.1,
                target: targets?[index] ?? .left
            )
        }
    }

    private func trial(timestamps: [TimeInterval]) -> TapTrial {
        trial(samples: samples(timestamps))
    }

    private func trial(samples: [TapSample]) -> TapTrial {
        TapTrial(
            samples: samples,
            leftCenter: TapPoint(x: 10, y: 20),
            rightCenter: TapPoint(x: 30, y: 20),
            targetRadius: 15,
            startedAt: 0,
            hand: .right,
            screenScale: 3
        )
    }

    private func assertStats(
        _ first: SummaryStats?,
        equals second: SummaryStats?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let first, let second else {
            XCTAssertNil(first, file: file, line: line)
            XCTAssertNil(second, file: file, line: line)
            return
        }

        XCTAssertEqual(first.min, second.min, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.max, second.max, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.mean, second.mean, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.median, second.median, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.p25, second.p25, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.p75, second.p75, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.stdev, second.stdev, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.range, second.range, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(first.iqr, second.iqr, accuracy: 0.000_001, file: file, line: line)
    }
}
