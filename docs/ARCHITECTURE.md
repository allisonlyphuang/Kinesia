# Bradykinesia architecture

## Implemented vertical slice

```text
HomeView
  → BradykinesiaTestView
  → BradykinesiaTestModel (ready → countdown(hand) → running(hand) → rest(nextHand) → finished/failed)
  → TapCaptureView / RawTouchView
  → TapSample / TapTrial
  → BradykinesiaAnalyzer
  → BradykinesiaMetrics
  → HandAttempt (one per hand)
  → BradykinesiaStore
  → one TestSession + one BradykinesiaResult and one RawCapture per hand
```

`RawTouchView` enables multitouch and emits every `touchesBegan` touch as a `TapSample`. It assigns UI `.left`, `.right`, or `.miss` classification from the displayed target geometry only. `BradykinesiaTestModel` accepts samples only while running, preserves order and misses, prevents overlapping starts and duplicate completion, and invokes the analyzer once per hand and the store exactly once per test.

The production lifecycle uses a configurable 3-second countdown and a 20-second capture duration per hand, each test beginning with the right target. Raw touch time and `TapTrial.startedAt` are monotonic. Wall-clock `Date` values are captured separately for session/result persistence; touch timestamps are never interpreted as Unix time.

## Bilateral capture

`BradykinesiaTestConfiguration.handOrder` drives the sequence and defaults to `[.right, .left]`. The model runs one hand at a time and parks in `.rest(nextHand:)` between them.

- The rest phase between each hand is **user-driven, not timed**. Switching hands takes an unpredictable amount of time, and an auto-advancing countdown would capture taps while the participant is still repositioning.
- `configure(_:)` accepts new geometry from `.ready` and `.rest` only, so each hand re-locks the target geometry it was actually collected against. Every `TapTrial` records its own geometry.
- `beginCountdown(for:)` rejects any hand other than the one `nextHand()` reports, so a second attempt at an already-completed hand cannot start.
- Nothing is written to Core Data until every hand in `handOrder` has completed. Abandoning mid-test (navigating away during countdown, running, or rest) discards the whole attempt.
- `handOrder: [.right]` runs a single hand through the same code path with no rest phase.

## Persistence

`BradykinesiaStore.save(attempts:in:)` receives already-analyzed attempts. It does not recompute metrics. It validates every attempt before creating anything, JSON-encodes each complete `TapTrial` into a `RawCapture.payload`, and creates one `TestSession` with one `BradykinesiaResult` and one `RawCapture` per hand, committed in a single `context.save()`.

Validation runs before the first object is inserted: non-empty attempts, no duplicate hand, metric/sample tap-count agreement, `Int32` range for both tap counts, a finite positive capture duration, and finite wall-clock timestamps. A failed `context.save()` calls `context.rollback()` so a partially built session cannot survive in the shared `viewContext` and leak into a later save.

All JSON encoding happens before the creation loop, so nothing inside that loop can throw.

Session wall-clock bounds are derived from the attempts: `startedAt` is the earliest hand's start, `completedAt` is the latest hand's completion. `dayStart` is local midnight of the day the test **began**, so a session that crosses midnight is filed under the day the participant experienced it as.

Result fetching is newest-first by explicit wall-clock timestamp. `fetchLatestSession` returns the most recent session that has at least one Bradykinesia result; its results are unordered (a to-many relationship is a set), so consumers sort by `BradykinesiaResult.timestamp` to recover hand order.

## Initial scaffold completion note

The initial scaffold intentionally established the intended data flow but left the analyzer/metric representation incomplete. In particular, the TapInter metric scaffold represented an interval in scalar form while attempting to access summary values such as `.mean` and `.stdev`; `BradykinesiaAnalyzer` was still placeholder/malformed and did not yet produce a typed metric bundle.

The implemented pathway is now:

```text
ordered TapSample array
  → explicit interval and drift sequences
  → SummaryStats plus paper-statistical helpers
  → typed optional BradykinesiaMetrics
```

Optional metrics preserve unavailability explicitly instead of manufacturing zero values.

## Concurrency

The calculation layer is pure and `nonisolated`: `BradykinesiaAnalyzer` and `SummaryStats` methods, and the value types in `calculations/` that they operate on, are all explicitly `nonisolated`. The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without those annotations the synthesized protocol conformances on those types would be main-actor-isolated and unusable from the analyzer.

`BradykinesiaTestModel` is `@MainActor`. Views and the store run on the main actor by default.

## Deferred decisions

- MotionQC: schema fields exist on `BradykinesiaResult`, so motion is naturally per-hand; collection and interpretation are deferred and `MotionQC` remains a stub to be later implemented.
- Scoring: there is no normalization, composite score, severity score, or left/right asymmetry index. One session now holds both hands, so asymmetry becomes a query over that session whenever it is defined.
- `TestSession.status`: for now reserved and unwritten. some scenarios where this might be used is in saving each hand as it completes instead of both at the end, persisting abandoned attempts, or other test types.
- Hand order: fixed `[.right, .left]`. Dominant-hand-first or randomized order is not implemented.
- Capture-window drift: the lifecycle timer subtracts nominal one-second ticks rather than measured elapsed time, so the real window is slightly longer than `captureDuration` and varies between runs. `BradykinesiaResult.durationSec` records the actual measured window, which makes the drift visible but does not correct it.

# Dexterity architecture

## Implemented vertical slice

```text
HomeView → DexterityTestView → DexterityTraceSurface
  → DexterityCaptureView → DexterityTestModel → DexteritySessionModel
  → DexteritySessionCapture → DexterityAnalyzer → DexterityStore
  → TestSession + DexterityResult + RawCapture
```

The production flow locks the V1 interaction protocol: right index finger, right hand, one successful practice trace, then three successful scored traces of the fixed `constellation-v1` route. A lift or cancellation ends an attempt; the attempt stays in raw capture data and the current practice/scored round is retried. Only the three completed scored sequences reach primary metrics.

`DexterityCaptureView` is a UIKit bridge so raw samples use local capture coordinates and monotonic `UITouch.timestamp` values. `DexterityTestModel` owns ordered target progress and assigns `segmentIndex` as each sample arrives. The analyzer uses that assignment rather than globally finding the closest segment, preserving correctness for routes with crossings.

The canonical route transform is saved with each capture. Raw samples remain local; geometry and speed are calculated after inverse transformation in canonical route units. This makes RMSE, path length, and speed independent of the rendering scale. Speed is expressed in canonical route units per second, not physical units.

## Dexterity persistence

`DexterityStore.save` validates and JSON-encodes a full `DexteritySessionCapture` before inserting a `TestSession`, one `DexterityResult`, and one `RawCapture` (`kind = "dexterity"`, schema version 1). The one save is atomic; a Core Data failure rolls back the inserted objects. Wall-clock session dates are supplied as `Date`; raw touch timing stays monotonic inside the payload.

The persisted result is based only on the indexed three completed scored attempts. Practice and incomplete/retry attempts remain in the JSON payload for auditability. The store writes `isValid = false`, `invalidReason`, and required numeric placeholders if a structurally complete capture has unavailable required metrics. Consumers must not treat a placeholder zero as a measured value when `isValid` is false.
