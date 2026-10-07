import Combine
import Foundation

nonisolated struct DexterityTestConfiguration: Equatable {
    var route: DexterityRoute
    var coordinateSpace: DexterityCoordinateSpace
    var targetRadius: Double

    var invalidReason: String? {
        guard DexterityAnalyzer.isCalculationValid(route: route) else {
            return "route is invalid"
        }
        guard coordinateSpace.isCalculationValid else {
            return "coordinate space is invalid"
        }
        guard targetRadius.isFinite, targetRadius > 0 else {
            return "target radius is invalid"
        }
        return nil
    }
}

/// Ordered route state. It knows only the configured route and target geometry, never UIKit events or UI rendering.
nonisolated struct DexterityRouteProgress: Equatable {
    let route: DexterityRoute
    let targetRadius: Double
    private(set) var activeSegmentIndex = 0
    private(set) var nextTargetIndex = 1
    private(set) var isCompleted = false

    init?(route: DexterityRoute, targetRadius: Double) {
        guard DexterityAnalyzer.isCalculationValid(route: route),
              targetRadius.isFinite,
              targetRadius > 0 else {
            return nil
        }
        self.route = route
        self.targetRadius = targetRadius
    }

    /// Advances at most one target. The sample is scored by the caller before this method changes ownership.
    mutating func advanceIfExpectedTargetReached(by point: DexterityRoutePoint) {
        guard !isCompleted,
              point.hasFiniteCoordinates,
              let distance = distance(from: point, to: route.points[nextTargetIndex]),
              distance <= targetRadius else {
            return
        }

        if nextTargetIndex == route.points.count - 1 {
            isCompleted = true
        } else {
            activeSegmentIndex += 1
            nextTargetIndex += 1
        }
    }

    private func distance(from point: DexterityRoutePoint, to target: DexterityRoutePoint) -> Double? {
        guard point.hasFiniteCoordinates, target.hasFiniteCoordinates else {
            return nil
        }

        let deltaX = point.x - target.x
        let deltaY = point.y - target.y
        let result = sqrt(deltaX * deltaX + deltaY * deltaY)
        return result.isFinite ? result : nil
    }
}

@MainActor
final class DexterityTestModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case tracing
        case completed
        case ended
        case configurationInvalid(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var activeSegmentIndex: Int?
    @Published private(set) var nextTargetIndex: Int?
    @Published private(set) var currentTracePoints: [DexterityTracePoint] = []
    @Published private(set) var latestSequence: DexteritySequence?

    private(set) var configuration: DexterityTestConfiguration
    private var progress: DexterityRouteProgress?

    init(configuration: DexterityTestConfiguration) {
        self.configuration = configuration
        if let invalidReason = configuration.invalidReason {
            phase = .configurationInvalid(invalidReason)
            progress = nil
            activeSegmentIndex = nil
            nextTargetIndex = nil
        } else {
            phase = .ready
            progress = DexterityRouteProgress(route: configuration.route, targetRadius: configuration.targetRadius)
            activeSegmentIndex = progress?.activeSegmentIndex
            nextTargetIndex = progress?.nextTargetIndex
        }
    }

    var isTraceActive: Bool {
        phase == .tracing
    }

    func handle(_ event: DexterityTouchEvent) {
        switch event {
        case .began(let sample):
            begin(with: sample)
        case .moved(let samples):
            for sample in samples {
                guard phase == .tracing else {
                    return
                }
                appendAndAdvanceIfNeeded(sample)
            }
        case .ended(let sample):
            end(with: sample)
        case .cancelled(let sample):
            cancel(with: sample)
        }
    }

    func reset() {
        currentTracePoints = []
        latestSequence = nil
        if let invalidReason = configuration.invalidReason {
            phase = .configurationInvalid(invalidReason)
            progress = nil
            activeSegmentIndex = nil
            nextTargetIndex = nil
        } else {
            progress = DexterityRouteProgress(route: configuration.route, targetRadius: configuration.targetRadius)
            phase = .ready
            synchronizeProgress()
        }
    }

    private func begin(with sample: DexterityTouchSample) {
        guard phase == .ready,
              let progress,
              let canonical = configuration.coordinateSpace.canonicalPoint(localX: sample.x, localY: sample.y),
              isWithinRadius(canonical, of: configuration.route.points[0]) else {
            return
        }

        currentTracePoints = [tracePoint(from: sample, segmentIndex: progress.activeSegmentIndex)]
        latestSequence = nil
        phase = .tracing
    }

    private func appendAndAdvanceIfNeeded(_ sample: DexterityTouchSample) {
        guard phase == .tracing, let progress else {
            return
        }

        appendIfDistinct(sample, segmentIndex: progress.activeSegmentIndex)
        guard let canonical = configuration.coordinateSpace.canonicalPoint(localX: sample.x, localY: sample.y) else {
            return
        }

        var updatedProgress = progress
        updatedProgress.advanceIfExpectedTargetReached(by: canonical)
        self.progress = updatedProgress
        synchronizeProgress()

        if updatedProgress.isCompleted {
            completeSequence()
        }
    }

    private func end(with sample: DexterityTouchSample) {
        guard phase == .tracing else {
            return
        }

        appendAndAdvanceIfNeeded(sample)
        if phase == .completed {
            return
        }

        finishIncompleteSequence(endedByLift: true, endedByCancellation: false)
    }

    private func cancel(with sample: DexterityTouchSample?) {
        guard phase == .tracing, let progress else {
            return
        }

        if let sample {
            appendIfDistinct(sample, segmentIndex: progress.activeSegmentIndex)
        }
        finishIncompleteSequence(endedByLift: false, endedByCancellation: true)
    }

    private func appendIfDistinct(_ sample: DexterityTouchSample, segmentIndex: Int) {
        let tracePoint = tracePoint(from: sample, segmentIndex: segmentIndex)
        guard currentTracePoints.last != tracePoint else {
            return
        }
        currentTracePoints.append(tracePoint)
    }

    private func completeSequence() {
        latestSequence = DexteritySequence(
            samples: currentTracePoints,
            completed: true,
            endedByLift: false
        )
        phase = .completed
    }

    private func finishIncompleteSequence(endedByLift: Bool, endedByCancellation: Bool) {
        latestSequence = DexteritySequence(
            samples: currentTracePoints,
            completed: false,
            endedByLift: endedByLift,
            endedByCancellation: endedByCancellation
        )
        phase = .ended
    }

    private func synchronizeProgress() {
        activeSegmentIndex = progress?.activeSegmentIndex
        nextTargetIndex = progress?.nextTargetIndex
    }

    private func tracePoint(from sample: DexterityTouchSample, segmentIndex: Int) -> DexterityTracePoint {
        DexterityTracePoint(t: sample.t, x: sample.x, y: sample.y, segmentIndex: segmentIndex)
    }

    private func isWithinRadius(_ point: DexterityRoutePoint, of target: DexterityRoutePoint) -> Bool {
        guard point.hasFiniteCoordinates, target.hasFiniteCoordinates else {
            return false
        }

        let deltaX = point.x - target.x
        let deltaY = point.y - target.y
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        return distance.isFinite && distance <= configuration.targetRadius
    }
}
