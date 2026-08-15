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
    let handOrder: [CurrentHand]
    let screenScale: Double
    let countdownSeconds: Int
    let captureDuration: TimeInterval

    init(
        leftCenter: TapPoint,
        rightCenter: TapPoint,
        targetRadius: Double,
        handOrder: [CurrentHand],
        screenScale: Double,
        countdownSeconds: Int = 3,
        captureDuration: TimeInterval = 20
    ) {
        precondition(countdownSeconds >= 0)
        precondition(captureDuration.isFinite && captureDuration > 0)
        precondition(!handOrder.isEmpty)
        precondition(Set(handOrder).count == handOrder.count)

        self.leftCenter = leftCenter
        self.rightCenter = rightCenter
        self.targetRadius = targetRadius
        self.handOrder = handOrder
        self.screenScale = screenScale
        self.countdownSeconds = countdownSeconds
        self.captureDuration = captureDuration
    }
}


struct HandAttempt {
    let hand: CurrentHand
    let trial: TapTrial
    let metrics: BradykinesiaMetrics
    let startedAt: Date // wall clock
    let completedAt: Date // wall clock
    let monotonicCompletedAt: TimeInterval
}

@MainActor
final class BradykinesiaTestModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case countdown(CurrentHand)
        case running(CurrentHand)
        case rest(nextHand: CurrentHand)
        case finished
        case failed
    }

    typealias PersistenceAction = ([HandAttempt], NSManagedObjectContext) throws -> TestSession

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var persistenceError: Error?

    private(set) var configuration: BradykinesiaTestConfiguration
    private(set) var capturedSamples: [TapSample] = []
    private(set) var monotonicStartedAt: TimeInterval?
    private(set) var wallClockStartedAt: Date?
    @Published private(set) var completedAttempts: [HandAttempt] = []

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
        self.persistenceAction = persistenceAction ?? { attempts, context in
            try BradykinesiaStore.save(attempts: attempts, in: context)
        }
    }

    deinit {
        lifecycleTask?.cancel()
    }

    var isCaptureActive: Bool {
        if case .running = phase { return true }
        return false
    }
    
    var activeHand: CurrentHand? {
        switch phase {
        case.countdown(let hand), . running(let hand), .rest(let hand): return hand
        case .ready, .finished, .failed: return nil
        }
    }
    
    private func nextHand() -> CurrentHand? {
        let done = Set(completedAttempts.map(\.hand))
        return configuration.handOrder.first {
            !done.contains($0)
        }
    }

    /// Updates the target geometry immediately before a new attempt begins.
    /// Geometry is intentionally locked once countdown/capture has started so the raw trial
    /// always describes the same targets that the participant saw.
    func configure(_ configuration: BradykinesiaTestConfiguration) {
        switch phase {
        case .ready, .rest:
            self.configuration = configuration
        default:
            return
        }
    }
    
    private func persistAllAttempts() {
        do {
            _ = try persistenceAction(completedAttempts, context)
            persistenceError = nil
            secondsRemaining = 0
            phase = .finished
        } catch {
            persistenceError = error
            phase = .failed
        }
    }

    func start() {
        guard let first = configuration.handOrder.first else { return }
        beginCountdown(for: first)
    }

    func beginCountdown(for hand: CurrentHand) {
        switch phase {
        case .ready, .rest:
            break
        default:
            return
        }
        guard nextHand() == hand else {
            return
        }
        

        clearTrialState()
        if configuration.countdownSeconds > 0 {
            phase = .countdown(hand)
            secondsRemaining = configuration.countdownSeconds
        } else {
            beginRunning(hand)
        }

        if automaticallyScheduleTimers {
            scheduleLifecycle()
        }
    }

    /// Advances one production countdown second. Tests invoke this directly instead of waiting.
    func countdownTick() {
        guard case .countdown(let hand) = phase else {
            return
        }

        if secondsRemaining > 1 {
            secondsRemaining -= 1
        } else {
            beginRunning(hand)
        }
    }
    
    private func beginRunning(_ hand: CurrentHand) {
        capturedSamples = []
        monotonicStartedAt = monotonicNow()
        wallClockStartedAt = wallClockNow()
        phase = .running(hand)
        secondsRemaining = Int(ceil(configuration.captureDuration))
    }

    func recordTap(_ sample: TapSample) {
        guard case .running = phase else {
            return
        }
        capturedSamples.append(sample)
    }

    /// Completes the live capture window exactly once. Tests call this directly instead of waiting 20 seconds.
    func completeRunningWindow() {
        guard case .running(let hand) = phase, !isFinishing,
              let monotonicStartedAt,
              let wallClockStartedAt else {
            return
        }
        
        isFinishing = true
        lifecycleTask?.cancel()
        lifecycleTask = nil
        
        let completedAt = wallClockNow()
        let monotonicCompletedAt = monotonicNow()
        let trial = TapTrial(
            samples: capturedSamples,
            leftCenter: configuration.leftCenter,
            rightCenter: configuration.rightCenter,
            targetRadius: configuration.targetRadius,
            startedAt: monotonicStartedAt,
            hand: hand,
            screenScale: configuration.screenScale
        )
        completedAttempts.append(HandAttempt(
            hand: hand,
            trial: trial,
            metrics: BradykinesiaAnalyzer.analyze(trial),
            startedAt: wallClockStartedAt,
            completedAt: completedAt,
            monotonicCompletedAt: monotonicCompletedAt
        ))
        
        isFinishing = false
        if let next = nextHand() {
            phase = .rest(nextHand: next)
        } else {
            persistAllAttempts()
        }
    }
        
    func reset() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        phase = .ready
        completedAttempts = []
        persistenceError = nil
        clearTrialState()
    }

    private func scheduleLifecycle() {
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else {
                return
            }

            while case .countdown = self.phase {
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

            guard case .running = self.phase else {
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
                guard !Task.isCancelled, case .running = self.phase else {
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
        monotonicStartedAt = nil
        wallClockStartedAt = nil
        secondsRemaining = 0
        isFinishing = false
    }
}
