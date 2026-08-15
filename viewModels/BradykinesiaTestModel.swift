//
//  BradykinesiaTestModel.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import Combine
import CoreData
import Foundation

struct BradykinesiaTestConfiguration {
    let leftCenter: TapPoint
    let rightCenter: TapPoint
    let targetRadius: Double
    let hand: String
    let screenScale: Double
    let countdownSeconds: Int
    let captureDuration: TimeInterval

    init(
        leftCenter: TapPoint,
        rightCenter: TapPoint,
        targetRadius: Double,
        hand: String,
        screenScale: Double,
        countdownSeconds: Int = 3,
        captureDuration: TimeInterval = 20
    ) {
        precondition(countdownSeconds >= 0)
        precondition(captureDuration.isFinite && captureDuration > 0)

        self.leftCenter = leftCenter
        self.rightCenter = rightCenter
        self.targetRadius = targetRadius
        self.hand = hand
        self.screenScale = screenScale
        self.countdownSeconds = countdownSeconds
        self.captureDuration = captureDuration
    }
}

@MainActor
final class BradykinesiaTestModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case countdown
        case running
        case finished
        case failed
    }

    typealias PersistenceAction = (TapTrial, BradykinesiaMetrics, Date, Date, NSManagedObjectContext) throws -> BradykinesiaResult

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var persistenceError: Error?
    @Published private(set) var metrics: BradykinesiaMetrics?
    @Published private(set) var persistedResult: BradykinesiaResult?

    private(set) var configuration: BradykinesiaTestConfiguration
    private(set) var capturedSamples: [TapSample] = []
    private(set) var completedTrial: TapTrial?
    private(set) var monotonicStartedAt: TimeInterval?
    private(set) var wallClockStartedAt: Date?
    private(set) var wallClockCompletedAt: Date?

    private let context: NSManagedObjectContext
    private let monotonicNow: () -> TimeInterval
    private let wallClockNow: () -> Date
    private let persistenceAction: PersistenceAction
    private let automaticallyScheduleTimers: Bool
    private var lifecycleTask: Task<Void, Never>?
    private var isFinishing = false

    init(
        configuration: BradykinesiaTestConfiguration,
        context: NSManagedObjectContext,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wallClockNow: @escaping () -> Date = { Date() },
        automaticallyScheduleTimers: Bool = true,
        persistenceAction: PersistenceAction? = nil
    ) {
        self.configuration = configuration
        self.context = context
        self.monotonicNow = monotonicNow
        self.wallClockNow = wallClockNow
        self.automaticallyScheduleTimers = automaticallyScheduleTimers
        self.persistenceAction = persistenceAction ?? { trial, metrics, startedAt, completedAt, context in
            try BradykinesiaStore.save(
                trial: trial,
                metrics: metrics,
                startedAt: startedAt,
                completedAt: completedAt,
                in: context
            )
        }
    }

    deinit {
        lifecycleTask?.cancel()
    }

    var isCaptureActive: Bool {
        phase == .running
    }

    /// Updates the target geometry immediately before a new attempt begins.
    /// Geometry is intentionally locked once countdown/capture has started so the raw trial
    /// always describes the same targets that the participant saw.
    func configure(_ configuration: BradykinesiaTestConfiguration) {
        guard phase == .ready else {
            return
        }
        self.configuration = configuration
    }

    func start() {
        beginCountdown()
    }

    func beginCountdown() {
        guard phase == .ready else {
            return
        }

        clearTrialState()
        if configuration.countdownSeconds > 0 {
            phase = .countdown
            secondsRemaining = configuration.countdownSeconds
        } else {
            beginRunning()
        }

        if automaticallyScheduleTimers {
            scheduleLifecycle()
        }
    }

    /// Advances one production countdown second. Tests invoke this directly instead of waiting.
    func countdownTick() {
        guard phase == .countdown else {
            return
        }

        if secondsRemaining > 1 {
            secondsRemaining -= 1
        } else {
            beginRunning()
        }
    }

    func recordTap(_ sample: TapSample) {
        guard phase == .running else {
            return
        }
        capturedSamples.append(sample)
    }

    /// Completes the live capture window exactly once. Tests call this directly instead of waiting 20 seconds.
    func completeRunningWindow() {
        guard phase == .running, !isFinishing,
              let monotonicStartedAt,
              let wallClockStartedAt else {
            return
        }

        isFinishing = true
        lifecycleTask?.cancel()
        lifecycleTask = nil

        let completedAt = wallClockNow()
        let trial = TapTrial(
            samples: capturedSamples,
            leftCenter: configuration.leftCenter,
            rightCenter: configuration.rightCenter,
            targetRadius: configuration.targetRadius,
            startedAt: monotonicStartedAt,
            hand: configuration.hand,
            screenScale: configuration.screenScale
        )
        let analyzedMetrics = BradykinesiaAnalyzer.analyze(trial)

        completedTrial = trial
        metrics = analyzedMetrics
        wallClockCompletedAt = completedAt

        do {
            persistedResult = try persistenceAction(
                trial,
                analyzedMetrics,
                wallClockStartedAt,
                completedAt,
                context
            )
            persistenceError = nil
            secondsRemaining = 0
            phase = .finished
        } catch {
            persistenceError = error
            phase = .failed
        }
    }

    func reset() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        phase = .ready
        clearTrialState()
    }

    private func beginRunning() {
        capturedSamples = []
        monotonicStartedAt = monotonicNow()
        wallClockStartedAt = wallClockNow()
        phase = .running
        secondsRemaining = Int(ceil(configuration.captureDuration))
    }

    private func scheduleLifecycle() {
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else {
                return
            }

            while self.phase == .countdown {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                self.countdownTick()
            }

            guard self.phase == .running else {
                return
            }
            var remainingDuration = configuration.captureDuration
            while remainingDuration > 0 {
                let nextTickDuration = min(1, remainingDuration)
                do {
                    try await Task.sleep(nanoseconds: UInt64(nextTickDuration * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled, self.phase == .running else {
                    return
                }

                remainingDuration -= nextTickDuration
                self.secondsRemaining = Int(ceil(max(0, remainingDuration)))
            }

            self.completeRunningWindow()
        }
    }

    private func clearTrialState() {
        capturedSamples = []
        completedTrial = nil
        monotonicStartedAt = nil
        wallClockStartedAt = nil
        wallClockCompletedAt = nil
        metrics = nil
        persistedResult = nil
        persistenceError = nil
        secondsRemaining = 0
        isFinishing = false
    }
}
