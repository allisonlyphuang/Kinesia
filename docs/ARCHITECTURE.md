# Architecture

Covers both implemented tests.

- **Bradykinesia (tapping)** is complete
- **Akinesia (fireflies)** has capture and scoring, still building UI and saving

## Bradykinesia: tapping

### Implemented vertical slice

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

### Bilateral capture

`BradykinesiaTestConfiguration.handOrder` drives the sequence and defaults to `[.right, .left]`. The model runs one hand at a time and parks in `.rest(nextHand:)` between them.

- The rest phase between each hand is **user-driven, not timed**. Switching hands takes an unpredictable amount of time, and an auto-advancing countdown would capture taps while the participant is still repositioning.
- `configure(_:)` accepts new geometry from `.ready` and `.rest` only, so each hand re-locks the target geometry it was actually collected against. Every `TapTrial` records its own geometry.
- `beginCountdown(for:)` rejects any hand other than the one `nextHand()` reports, so a second attempt at an already-completed hand cannot start.
- Nothing is written to Core Data until every hand in `handOrder` has completed. Abandoning mid-test (navigating away during countdown, running, or rest) discards the whole attempt.
- `handOrder: [.right]` runs a single hand through the same code path with no rest phase.

### Persistence

`BradykinesiaStore.save(attempts:in:)` receives already-analyzed attempts. It does not recompute metrics. It validates every attempt before creating anything, JSON-encodes each complete `TapTrial` into a `RawCapture.payload`, and creates one `TestSession` with one `BradykinesiaResult` and one `RawCapture` per hand, committed in a single `context.save()`.

Validation runs before the first object is inserted: non-empty attempts, no duplicate hand, metric/sample tap-count agreement, `Int32` range for both tap counts, a finite positive capture duration, and finite wall-clock timestamps. A failed `context.save()` calls `context.rollback()` so a partially built session cannot survive in the shared `viewContext` and leak into a later save.

All JSON encoding happens before the creation loop, so nothing inside that loop can throw.

Session wall-clock bounds are derived from the attempts: `startedAt` is the earliest hand's start, `completedAt` is the latest hand's completion. `dayStart` is local midnight of the day the test **began**, so a session that crosses midnight is filed under the day the participant experienced it as.

Result fetching is newest-first by explicit wall-clock timestamp. `fetchLatestSession` returns the most recent session that has at least one Bradykinesia result; its results are unordered (a to-many relationship is a set), so consumers sort by `BradykinesiaResult.timestamp` to recover hand order.

### Initial scaffold completion note

The initial scaffold intentionally established the intended data flow but left the analyzer/metric representation incomplete. In particular, the TapInter metric scaffold represented an interval in scalar form while attempting to access summary values such as `.mean` and `.stdev`; `BradykinesiaAnalyzer` was still placeholder/malformed and did not yet produce a typed metric bundle.

The implemented pathway is now:

```text
ordered TapSample array
  → explicit interval and drift sequences
  → SummaryStats plus paper-statistical helpers
  → typed optional BradykinesiaMetrics
```

Optional metrics preserve unavailability explicitly instead of manufacturing zero values.

### Deferred decisions

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
## Akinesia: fireflies
The tapping test measures reaction time to a visual stimulus. 
The patient rests their index finger on a jar in the middle of the screen and holds it until a firefly appears. After a
random wait, a firefly appears around the jar at any point on a circle with a fixed radius. 

| Interval | Measurement |
| --- | --- |
| firefly appears to finger lifts | **Reaction time** |
| finger lifts to firefly tapped | **Movement time** |

### Implemented slice

```text
AkinesiaTestView            (currently building)
  → AkinesiaTestModel       (ready → instructions → practicing → scoring → finished/failed)
  → FireflyBoardView / FireflyBoard
  → RoundRecord / AkinesiaTrial
  → AkinesiaAnalyzer
  → AkinesiaMetrics
  → AkinesiaAttempt
  → (no store yet)
```

### FireflyBoard
`FireflyBoard` is a UIKit view hosted in SwiftUI. UIKit is used instead of SwiftUI because:
- The firefly has to appear in a single screen frame, otherwise there would be no moment of appearance and no defined start. A `CADisplayLink`
shows a pending firefly inside one frame and reports that frame's timestamp
- Finger timestamp uses `UITouch.timestamp`, which iOS records using the hardware.
  event. Reading a clock inside a gesture callback instead would add a varying delay depending on phone activity.
- Reports if a touch has landed, when the home finger moves (lifted, dragged out of the jar, system cancel), if the firefly was displayed on the frame, and the screen's refresh rate.
- A patient who slides to the firefly instead of lifting does not fire a lift event, so it treats the finger crossing outside the jar's edge as the movement start.
- `configure(...)` is called on every SwiftUI redraw, so it compares the requested firefly position against the last one and only spawns a new firefly when the position changed. Otherwise one firefly would report several onsets.

### Session model
`AkinesiaTestModel` runs the session, classifies board events, counts, and sends finished session to `AkinesiaAnalyzer`. 

| Outcome | Meaning | Uses a round? |
| --- | --- | --- |
| completed | firefly was tapped | yes |
| completed, no catch | finger lifted but never reached the firefly; reaction time still counts, only movement time is lost | yes |
| missed | no lift at all within 5 seconds of firefly spawning | yes |
| false start | lifted before the firefly then touched the screen | no, retried |
| slip | lifted before the firefly with no touch following, so the finger came off by accident | no, retried |
| interrupted | the system cancelled the touch, such as a phone call | not recorded at all |
### Scoring
Scoring uses `AkinesiaAnalyzer` :

```text
   0ms         120ms                         2000ms              5000ms
    |------------|-----------------------------|-------------------|
    too fast to  |        real reaction        |   slow enough to  |  no lift at all
    be a real    |                             |   be a lapse in   |
    reaction     |                             |   attention       |
```

- Raw timestamps are kept and scores are applied after. 
- Movement time is collected into its own list and never averaged into the reaction-time statistics.

### Absolute values are not comparable
Phones report reaction times with \~80ms delay, which differs between models. This largely cancels when a patient is compared against their own earlier
sessions on the same phone.

# Medication and PDQ-8

Both exist to feed the clinician view. Neither is a motor test, so neither has a capture layer or
an analyzer; each is a value type, a store, a view model, and a form.

```text
OnboardingMeds → MedicationScheduleModel → MedicationSchedulePlan (validate) → MedicationStore
                                                                              → MedicationSchedule
MedicationLogView → MedicationDayModel → MedicationStore → MedicationLog
OnboardingPDQ8 → PDQ8Model → PDQ8Score (compute) → PDQ8Store → PDQ8Log
```

`MedicationSchedulePlan` and `PDQ8Score` hold every rule. The view models call the same
validation the stores call, so the message a patient sees and the rule the store enforces cannot
drift apart, and both are tested without a Core Data stack.

## Why the schedule is deactivated and not deleted

`MedicationLog.schedule` points at the slot a dose was due at. A patient who moves their 8:00
dose to 9:00 has not changed when last month's doses were due, so `replaceSchedule` sets
`isActive = false` on the old rows and inserts new ones. Deleting would nullify those links and
destroy the adherence history silently.

## Why a dose is filed under the day it was due

A dose scheduled for 23:00 and taken at 00:30 is 90 minutes late. Resolving `scheduledTime`
against the taken day alone would make it 22.5 hours early, and the adherence chart would show a
large negative delay for the most ordinary kind of lateness. `MedicationStore` resolves to the
occurrence **nearest** the taken time across yesterday/today/tomorrow, and files the row under
that occurrence's local midnight, so the dose lands in the column for the day it was due.

## Three states, not two

Not recorded, taken, and skipped are three different facts. The absence of a row means the
patient has not answered yet; it never means the dose was skipped. `MedicationDayModel` rebuilds
its rows from Core Data after every write rather than mutating them in place, so a row that looks
recorded always is.

## Decrement and metrics versioning

`BradykinesiaAnalyzer.tapInterSlope` adds the third tapping component the clinician view needs
alongside speed and rhythm: the OLS slope of tap interval against tap index, in seconds per tap.
It is computed at save time and persisted as one scalar, because recovering it from the
`RawCapture` JSON on every chart redraw would not be acceptable for a week of sessions.

All three result entities now carry a `metricsVersion`. A longitudinal chart spans weeks, and
without a version a formula change mid-window would silently mix two definitions into one line.
Rows written before this change hold `0`, meaning "formulas not identified".
