# Architecture

Covers the three motor tests, the two self-report writers, and the clinician view that reads
them back.

| Area | State |
| --- | --- |
| Bradykinesia (tapping) | capture, analyzer, store, UI |
| Akinesia (fireflies) | capture, analyzer, store, UI |
| Dexterity (constellation tracing) | capture, analyzer, store, UI |
| Medication and PDQ-8 | value types, stores, forms; no capture layer |
| Clinician view | query, snapshots, derivations, charts, PDF export |

Each motor test follows the same shape: a capture layer that only records, a pure analyzer over
value types, a store that validates everything before inserting anything, and one atomic
`context.save()`. The medication log and the questionnaire skip the first two layers, because
neither records a touch.

## Two clocks, never mixed

Each test reads two unrelated clocks, and a value from one is never used in place of the other.

| Clock | Source | Used for |
| --- | --- | --- |
| Monotonic | `UITouch.timestamp`, `CADisplayLink.timestamp` | every interval inside a capture: tap intervals, reaction time, movement time, swipe speed, measured capture duration |
| Wall clock | `Date` | every stored instant: `startedAt`, `completedAt`, `dayStart`, `timestamp` |

The monotonic clock counts seconds since the device booted. It does not move when the system
clock is corrected, which is why every interval is derived from it, and it is meaningless as a
date, which is why no column stores one. Wall-clock instants are stored as epoch seconds in
`Double` columns.

Two consequences:

- A duration is always the difference of two monotonic readings taken in the same capture.
  `BradykinesiaResult.durationSec` and the akinesia session duration are both computed that way
  and validated as finite and positive before the row is written.
- Raw payloads keep their monotonic timestamps. A reader decoding `RawCapture.payload` gets
  seconds-since-boot, and the session's own wall-clock fields say when the capture happened.

All three stores reject a non-finite wall-clock timestamp before inserting anything, and the two
that record a timed capture window also reject a non-positive measured duration. A mixed-up
clock fails the save rather than producing a row that looks plausible.

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

### From samples to metrics

```text
ordered TapSample array
  → explicit interval and drift sequences
  → SummaryStats plus paper-statistical helpers
  → typed optional BradykinesiaMetrics
```

The sequences are built explicitly rather than derived on demand, so an interval is a value in a
list and not a scalar that summary statistics are read off of. Every derived metric on
`BradykinesiaMetrics` is optional, which states unavailability instead of manufacturing a zero:
non-increasing timestamps make the temporal metrics `nil` and leave `numTaps` and the raw samples
intact.

### Deferred decisions

- MotionQC: schema fields exist on `BradykinesiaResult`, so motion is naturally per-hand; collection and interpretation are deferred and `MotionQC` remains a stub to be later implemented. `capture/MotionQC.swift` is in the project navigator but in no target's Sources phase, so it does not compile today. Nothing references it, so that is harmless until the stub is filled in.
- Scoring: there is no normalization, composite score, severity score, or left/right asymmetry index. One session now holds both hands, so asymmetry becomes a query over that session whenever it is defined.
- `TestSession.status`: reserved and unwritten. It would carry meaning if a hand were saved as it completes rather than both at the end, if abandoned attempts were persisted, or if sessions held other test types. Until a vocabulary is defined, the stored `0` says nothing.
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
HomeView
  → AkinesiaTestView
  → AkinesiaTestModel       (ready → instructions → practicing → scoring → finished/failed)
  → FireflyBoardView / FireflyBoard
  → RoundRecord / AkinesiaTrial
  → AkinesiaAnalyzer
  → AkinesiaMetrics
  → AkinesiaAttempt
  → AkinesiaStore
  → one TestSession + one AkinesiaResult + one RawCapture
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

### Akinesia persistence

`AkinesiaStore.save(attempt:in:)` takes an already-analyzed `AkinesiaAttempt` and writes one
`TestSession`, one `AkinesiaResult`, and one `RawCapture` (`kind = "akinesia"`, the full
`AkinesiaTrial` as JSON) in a single `context.save()`, with `context.rollback()` on failure.

Validation runs before the first insert: at least one round, metric round counts agreeing with
the trial's own rounds, the seven outcome counts summing to `numRounds`, every count inside
`Int32`, finite wall-clock timestamps, and a finite positive session duration measured on the
monotonic clock.

Reaction-time and movement-time statistics are written as two independent bundles. A bundle
holding a non-finite value is treated as unavailable: its columns take the placeholder zero, and
`invalidReason` names which bundle was missing. Movement time can be unavailable while reaction
time is present, because a round where the patient lifted but never reached the firefly still has
a reaction time. `reactionTimeP90` is written; there is no movement-time P90 column.

The medication context comes from `BradykinesiaStore.mostRecentDose`, so both tests resolve a
dose by one rule.

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

All three result entities carry a `metricsVersion`. A longitudinal chart spans weeks, and
without a version a formula change mid-window would silently mix two definitions into one line.
Rows written before versioning existed hold `0`, meaning "formulas not identified".

# Clinician view: the read path

Everything above writes measurements. The clinician view is the only code that reads them back,
and it runs the same pipeline in reverse:

```text
Core Data
  → ReportQuery            (fetch only, no logic)
  → snapshot structs       (flat, Sendable, no NSManagedObject)
  → derivations            (pure, nonisolated, one file per chart)
  → ClinicianReportModel   (@MainActor ObservableObject)
  → chart views            (Swift Charts, one finished array each)
  → ReportExport           (ImageRenderer → PDF)
```

The entry point is the Insights pill at the bottom of `HomeView`, a `NavigationLink` to
`ClinicianReportView`. There is no second scene and no clinician-side login: the report is a
patient-facing screen the patient shows or sends.

| Layer | Knows about | Does not know about |
| --- | --- | --- |
| `ReportQuery` | Core Data, predicates, sort descriptors | charts, binning, baselines |
| snapshot structs | nothing, they are plain values | — |
| derivations | snapshot structs, `SummaryStats` | Core Data, SwiftUI |
| `ClinicianReportModel` | query, derivations, loading state | chart geometry |
| chart views | one derived array each, design tokens | where the data came from |
| `ReportExport` | chart views, `ImageRenderer`, `CGContext` | derivations |

## No chart view touches an NSManagedObject

- A derivation that takes `[SessionSnapshot]` and returns `[DoseBin]` is a pure function, so it
  gets the same microsecond tests as the analyzers, with no Core Data stack.
- `ImageRenderer` walks a view tree outside the main actor's normal update cycle. Faulting a
  managed object there is a concurrency hazard; snapshots are `Sendable` and carry no context.
- `BradykinesiaResult` has around 40 attributes and a week holds dozens of rows. One fetch into
  flat structs beats hundreds of lazy faults fired from chart body re-evaluation.

## ReportQuery

`ReportQuery.load(window:in:)` returns one `ReportData` holding the window's sessions, the
window's doses, every questionnaire, and the patient's whole session history. It runs on
`viewContext`, matching the other stores: result rows are small and a window holds tens of them.

Each fetch sets `relationshipKeyPathsForPrefetching` for the relationships the snapshots read —
the three result relationships and `medicationContext` on a session, the schedule on a dose — so
a week does not fire a fault per row.

Two of the four collections deliberately ignore the window:

- **History.** A baseline needs 5 familiarization days plus 14 baseline days with data, and the
  default window is 7 days, so the baseline cannot be computed from the window alone.
- **Questionnaires.** The PDQ-8 chart is a months-scale chart, and a 7-day window usually holds
  no answers at all.

Sessions are fetched by `startedAt`, doses by `dayStart`, because a dose belongs to the day it
was due. Both fetches are start-inclusive and end-exclusive, matching `ReportWindow`.

## The two snapshot rules

`persistence/ReportSnapShotMapping.swift` holds a failable initialiser per row kind. Both rules
that the rest of the read path depends on live there and are applied nowhere else.

**`minutesSinceDose` becomes `Double?`, resolved from `medicationContext != nil`.** The stored
number is a non-optional `Double` defaulting to `0`, so `0` means either "tested at the moment of
a dose" or "no dose that day". Testing the number would silently drop every pre-first-dose
session, which is the OFF-state data the wearing-off question depends on.

**A placeholder zero becomes `nil`, gated on the row's own `isValid`.** All three stores write
`0` into required numeric columns when a metric was unavailable. A chart that plots one draws a
dip that is pure artefact, so `measured(_:isValid:)` returns `nil` for an invalid row and for a
non-finite stored value.

One exception, by design: `numTaps`, `numCorrectTaps`, and `durationSec` are not gated.
`BradykinesiaStore` validates the counts and the duration separately from the statistics and
throws on a count mismatch or a non-positive duration, so tap rate is still a measurement even
when an unrelated drift CV was missing. Gating it would throw away whole sessions.

`SessionSnapshot` sorts its tapping rows by timestamp, because the relationship is a set and hand
order is not stored.

## The derivations

One file per concern in `calculations/ClinicianView/`, all pure value types, each with its own
test suite.

| File | Produces | For |
| --- | --- | --- |
| `ReportWindow` | the day range and its days | every chart |
| `PrimaryMetric` | one value per session per hand | the four charts that plot "the primary metric" |
| `DoseBinning` | ten `DoseBin`s in x-axis order | time since dose |
| `DailyAggregate` | one row per day in the window | daily trend, and the shared median helper |
| `Baseline` | `BaselineState`: familiarization, building, or established | the baseline band and every z-score |
| `AdherencePoint` | one point per scheduled dose | dose timing |
| `TapComponentZScores` | speed, rhythm, and decrement as z, plus accuracy in its own units | tapping components |
| `DataQuality` | window counts, exclusions, versions present | the section above the charts |

Two conventions run through all of them:

- **Days come from `Calendar`, never from `/ 86400`.** A window spanning a daylight-saving
  change has days that are not 86400 seconds long. Sessions are grouped by
  `window.calendar.startOfDay(for: session.dayStart)`.
- **A missing value stays missing.** Derivations return `Double?` and keep empty slots in their
  arrays: every day in the window gets a row, every dose bin keeps its place on the axis. A gap
  the eye fills in would be a different claim than no data.

## The view model

`ClinicianReportModel` holds the window length, the selected metric, the selected hand, the
selected day, and one published array per derivation. Changing the metric or the hand calls
`rebuild()`, which recomputes the derivations from the data already loaded. Changing the window
length calls `load()`, which goes back to Core Data.

`timelinePoints(for:)` and `doseMarkers(for:)` scope the daily timeline to one day, so a week of
sessions is not overplotted on one 24-hour axis.

## Charts and export

Each section of the report is described once, as data. `ReportSections.all(for:)` returns one
`ReportSectionSpec` per section, carrying its title, subtitle, legend, optional caption and a
content closure that takes the theme. `ReportBody` renders that list as one column;
`ReportExport` slices the same list into pages through `ReportSections.pageGroups`. Pagination is
therefore the only thing the export decides for itself, and a heading or caption cannot differ
between screen and paper because neither caller holds one. `ReportSections.headerSubtitle(for:)`
is the date-range line, shared the same way.

A section's closure receives the theme, which is how a screen-only control stays off the page:
the day-selector strip and the baseline progress bar are drawn only when `!theme.isPrint`.

`ChartSection` wraps every chart with its task-named title, a line of context, the legend, an
optional caption, and the method link. `ReportLayout` holds one set of spacing numbers for both
surfaces: `margin` (16 pt) is applied once to the scroll content, `pageMargin` (48 pt) once to
the whole PDF page, and neither is re-applied per section, so the two side margins cannot drift
apart. `ReportTheme` swaps the screen's cream background for white on paper.

`ReportExport.renderPDF(model:)` draws the same chart views into a four-page US Letter PDF
through `ImageRenderer` and a `CGContext` PDF consumer: data quality and the daily timeline,
time since dose and dose timing, the daily trend and PDQ-8, then the tapping components. The page
template fills white behind each page and draws the page number and "Not a diagnostic tool." on
every page, so neither can be forgotten on an individual chart. The file goes to the temporary
directory and is handed to `ShareLink`. There is no network code in the feature.

## What the read path does not have yet

- **The method and readings sheet.** `ChartSection` draws the link and takes an `onMethodTap`
  closure, but no caller passes one, so the plain-language formula and the table of underlying
  rows are not reachable. The control is a **deliberate placeholder**, kept in place so the
  layout and the regulatory requirement stay visible, rather than an oversight. The PDF omits
  the link rather than printing a control that cannot be tapped, which means the same material
  still has to reach paper some other way before the requirement is met.
- **Session detail.** Reading one session's `RawCapture.payload` on a background context, which
  is what shows the within-session interval series behind the decrement scalar.
- **An export confirmation step.** The share sheet opens straight from the export button.

`views/Clinician/ReportSeed.swift` writes 45 days of history behind a `#if DEBUG` button at the
bottom of the report, so the charts can be looked at on a device. It is not in a release build.
