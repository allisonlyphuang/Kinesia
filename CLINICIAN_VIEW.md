# Clinician view — implementation outline

The read side of Kinesia. Everything built so far writes measurements; nothing reads them back.
This document specifies what the clinician view does, how the code is arranged, and what has to
exist before any of it can be built.

Source: `CAC 26-27: Kinesia` literature review and chart spec.

---

## 1. What it is for

**The supported decision:** whether to change the timing or amount of a patient's medication.

The view supports that decision by showing whether symptoms worsen before doses and improve
after them. It does not make the decision, score severity, or diagnose.

**Users**

| User | Role |
| --- | --- |
| Neurologist / clinician | Primary. Reads the view at a visit or on a telehealth call. |
| Patient | Secondary. Owns the data and decides whether and how it leaves the phone. |

**The four questions every chart must serve**

1. Does movement get worse before the next dose (wearing off)?
2. After a dose, how quickly does movement improve, and for how long?
3. Are doses being taken on time?
4. Is the overall pattern improving across weeks?

A chart that does not answer one of these four does not belong in the view.

### Why this view exists at all

The literature review establishes that self-report is the weak link, not measurement:

- Patient/observer agreement on motor state was **59.8%**; patients called themselves normal
  during 10.1% of OFF periods.
- Anosognosia is common and worsens with progression.
- Median medication adherence was **97.7%**, but median *timing* adherence was **24.4%**.

So the view's job is to put an objective, dose-linked, time-stamped record next to the patient's
own account — not to replace the account.

---

## 2. Regulatory constraints, and what they force in code

The FDA clinical decision support guidance draws the line this app has to stay behind. These are
not soft guidelines; each one maps to a concrete implementation rule.

| Constraint | Implementation rule |
| --- | --- |
| Do not analyze signals from a signal acquisition system | Only touch events and timestamps. No accelerometer-derived symptom inference. `MotionQC` stays a quality flag, never a symptom signal. |
| Display, analyze, print medical information | Charts and tables only. No alerts that imply a clinical state. |
| Support a decision, do not make it | No "increase dose" text, no severity labels, no red/green judgement colour. |
| The clinician can independently review the basis of any output | Every chart ships with a method disclosure and a path to the underlying raw rows. This drives the `ChartCard` / `MethodDisclosure` architecture in §7. |
| Label every page "not a diagnostic tool" | A footer on every screen and every exported PDF page. |
| Label tests by their task, not the intended symptom | UI strings say "tapping task", "firefly task", "constellation tracing" — never "bradykinesia score". Enforced by a copy test (§10). |
| Show raw measurements with their units | Every axis carries units. Every chart has a raw-values table behind it. |

The codebase already has a precedent for enforcing copy rules in tests: `AkinesiaCopyTests`
checks for clinical and internal vocabulary. The clinician view extends that pattern rather than
inventing a new one.

---

## 3. Where it sits in the app

`HomeView` already draws a Garden / Insights segmented pill at the bottom, unwired. That pill is
the entry point.

```text
KinesiaApp
  └─ RootTabView                      (new — replaces HomeView as the root scene)
       ├─ HomeView                    (Garden: existing check-in flow)
       └─ ClinicianReportView         (Insights: this document)
            ├─ ReportHeader           date range, patient-facing metadata
            ├─ DataQualitySection     §8
            ├─ ChartCard × 6          §7
            ├─ SessionList → SessionDetailView
            └─ ExportBar              §9
```

`ClinicianReportView` is a patient-facing screen that a patient shows or sends to a clinician. It
is not a separate login, a separate build, or a server. Everything stays on device; the only way
data leaves is the patient-initiated export in §9.

**Built 2026-10-17, with a smaller change than the tree above.** `RootTabView` was not needed:
the Insights half of the existing pill is now a `NavigationLink` to `ClinicianReportView`, so
`HomeView` stays the root scene and the Garden flow is untouched. The report itself is one
`ScrollView`:

```text
HomeView
  └─ Insights pill → ClinicianReportView
       ├─ header                  date range and check-in count
       ├─ controls                window length, Measure, hand
       ├─ ReportBody
       │    ├─ DataQualitySection §8
       │    └─ ChartSection × 6   §7
       ├─ export button → ShareLink
       └─ "Not a diagnostic tool."
```

`ReportBody` holds the quality section and the six charts together because the PDF pages reuse
the same sections, which is what keeps paper and screen from drifting apart. The day selector
under the daily timeline is screen-only. `SessionList` and `SessionDetailView` are not built;
§7.7 is still open.

---

## 4. Architecture

### 4.1 The shape, and why

The existing test pipelines all follow the same shape:

```text
capture (UIKit)  →  model (@MainActor ObservableObject)  →  value types
                 →  analyzer (pure, nonisolated)         →  metrics struct
                 →  store (static, validates then saves) →  Core Data
```

The analyzers are pure functions over value types, which is why 629 tests run in microseconds
with no simulator timing. The clinician view runs the same pipeline in reverse, keeping the same
property:

```text
Core Data  →  ReportQuery (fetch only, no logic)
           →  snapshot structs (flat, Sendable, no NSManagedObject)
           →  derivations (pure, nonisolated, one file per chart)
           →  ClinicianReportModel (@MainActor ObservableObject)
           →  chart views (Swift Charts, dumb)
           →  ReportExport (ImageRenderer → PDF)
```

**The single most important rule: no chart view ever touches an `NSManagedObject`.**

Three reasons, all practical:

1. **Testability.** A derivation that takes `[SessionSnapshot]` and returns `[DoseBin]` is a pure
   function. It gets the same microsecond unit tests as `BradykinesiaAnalyzer`, with no Core Data
   stack and no fixtures beyond a struct literal.
2. **Export safety.** `ImageRenderer` walks a view tree off the main actor's normal update cycle.
   Faulting a managed object there is a concurrency hazard. Snapshots are `Sendable` value types
   and have no context.
3. **Fault storms.** `BradykinesiaResult` has ~40 attributes and a week holds dozens of rows. One
   fetch into flat structs beats hundreds of lazy faults fired from chart body re-evaluation.

### 4.2 Layer responsibilities

| Layer | Knows about | Does not know about |
| --- | --- | --- |
| `ReportQuery` | Core Data, predicates, sort descriptors | charts, binning, baselines |
| snapshot structs | nothing (plain values) | — |
| derivations | snapshot structs, `SummaryStats` | Core Data, SwiftUI |
| `ClinicianReportModel` | query + derivations, loading state | chart geometry |
| chart views | one derived array each, design tokens | where data came from |
| `ReportExport` | chart views, `ImageRenderer`, PDFKit | derivations |

### 4.3 Concurrency

- Result rows are small and few (a 7-day window is tens of rows). Fetch them on
  `viewContext` — it matches the existing stores and keeps the model simple.
- **Exception:** `RawCapture.payload` decoding for session detail (§7.7). Those are JSON blobs
  of every touch sample. Decode on a background context via
  `container.performBackgroundTask`, hand back decoded value types, never managed objects.
- Derivations are `nonisolated` pure functions, so they can run on either side of the boundary.

---

## 5. Blockers — what has to exist first

**None of the charts can be built until this section is done.** These are not nice-to-haves;
each one is a data source the spec requires and the codebase does not have.

> **Status: 5.1 to 5.6 are implemented** as of 2026-10-16. Each subsection below keeps its
> original statement of the problem, and ends with a note on what was built. The remaining
> blocker is 5.7, which is manual Xcode work that has to be redone for every new file.

### 5.1 Medication logging has no writer

`MedicationLog` and `MedicationSchedule` exist in the Core Data model.
`BradykinesiaStore.mostRecentDose` reads `MedicationLog` and stamps every session's
`medicationContext` and `minutesSinceDose`. But **nothing in the app ever creates a
`MedicationLog`** — `MedicationLogView` is a static DetailsPro mockup with hardcoded 8:00 AM /
1:00 PM / 6:00 PM rows, and `OnboardingMeds` never writes a `MedicationSchedule`.

So right now every saved session has `medicationContext == nil` and `minutesSinceDose == 0`.
Three of the six charts are dose-linked and would be empty.

**Needed: `persistence/MedicationStore.swift`**

```swift
struct MedicationStore {
    static func saveSchedule(_ slots: [ScheduleSlot], in: NSManagedObjectContext) throws
    static func activeSchedule(in: NSManagedObjectContext) throws -> [MedicationSchedule]
    static func logDose(schedule: MedicationSchedule?, takenAt: Date,
                        in: NSManagedObjectContext) throws -> MedicationLog
    static func logSkipped(schedule: MedicationSchedule, on day: Date,
                           in: NSManagedObjectContext) throws -> MedicationLog
    static func logs(from: Date, to: Date, in: NSManagedObjectContext) throws -> [MedicationLog]
}
```

Following the existing store contract: validate everything before inserting anything, single
atomic `context.save()`, `context.rollback()` on failure.

`logDose` must set `scheduledTime` from the matching schedule slot resolved against the log's own
local day. **The adherence chart is `timestamp − scheduledTime`, so a log written without
`scheduledTime` is silently unusable** — validate it as non-zero whenever a schedule is attached.

`MedicationLogView` then has to be rewired from mockup to a real view backed by
`activeSchedule`, with a skip affordance (the spec distinguishes solid rules for taken doses from
dashed rules for skipped ones).

**Done.** `persistence/MedicationStore.swift` writes and reads the schedule and the dose log;
`calculations/MedicationSchedulePlan.swift` holds the validation and the occurrence arithmetic;
`viewModels/MedicationScheduleModel.swift` and `viewModels/MedicationDayModel.swift` drive the
two forms; `OnboardingMeds` and `MedicationLogView` are real screens rather than mockups.
Covered by 56 tests across three suites. Two rules landed that this outline did not anticipate
and that are now in the data dictionary: a dose is filed under the day it was **due** rather than
the day it was taken, and not-recorded / taken / skipped are three distinct states.

### 5.2 PDQ-8 has no writer

`PDQ8Log` exists with `itemScores` (Binary), `rawSum`, `scoreIndex`. `OnboardingPDQ8` is a static
mockup with no state and no save.

**Needed: `persistence/PDQ8Store.swift`** plus a real questionnaire view.

Scoring, to be written into `docs/DATA_DICTIONARY.md` at the same time:

```text
8 items, each scored 0–4
rawSum    = sum of item scores              (0–32)
scoreIndex = rawSum / 32 * 100              (0–100, higher = worse QOL)
```

`itemScores` should be a JSON-encoded `[Int16]` so a clinician can review the per-item basis, and
so a future PDQ-39 migration has somewhere to go. Encode it with `JSONEncoder` to match how
`RawCapture.payload` is handled.

The PDQ-8 trend chart is a months-scale chart. One response per onboarding plus a periodic
re-prompt (monthly) is the minimum that makes the chart meaningful — the re-prompt scheduling is
a product decision that needs to be made before the chart ships, not after.

**Done.** `calculations/PDQ8.swift` holds the eight items, the five-point scale, and the
scoring; `persistence/PDQ8Store.swift` saves and reads; `viewModels/PDQ8Model.swift` runs the
questionnaire; `OnboardingPDQ8` is a real eight-item form. Per-item scores are stored as
JSON-encoded `[Int16]`, and a partial questionnaire is refused rather than scored with gaps as
zeros. Covered by 39 tests across three suites. The re-prompt cadence is still an open product
decision (§12.4), and the Oxford University Innovation licence position still needs confirming.

### 5.3 "Before the first dose" is currently indistinguishable from "no dose"

`TestSession.minutesSinceDose` is a non-optional `Double` defaulting to `0.0`. The store only
writes it when a qualifying dose exists. So `minutesSinceDose == 0` means either *"tested at the
exact moment of a dose"* or *"no dose that day"*.

**No schema change needed.** `medicationContext` is an optional relationship, so the correct test
is `session.medicationContext != nil`. This must be the only way the derivation layer decides
whether a session has dose context. Write it down in the data dictionary, because the obvious
wrong version (`minutesSinceDose > 0`) silently drops every pre-first-dose session, which is
exactly the OFF-state data the wearing-off question depends on.

**Done**, as documentation — no schema change was needed, as predicted. The rule is written
into `docs/DATA_DICTIONARY.md` under "Dose context on a session": the only correct test is
`session.medicationContext != nil`.

### 5.4 Decrement is not computed or stored

The tapping-component chart needs three variables: speed, rhythm, **decrement**.

- Speed → `numTaps / durationSec`, or `1 / tapInterMedian`. Available.
- Rhythm → `cvTapInter`. Available.
- Decrement → the tendency of intervals to lengthen across the 20-second capture. **Not
  computed anywhere.**

`BradykinesiaMetrics.tapIntervals` holds the ordered sequence in memory, but
`BradykinesiaStore` persists only summary statistics. The full `TapTrial` survives in
`RawCapture.payload`, so decrement is recoverable — but recovering it means decoding a JSON blob
per session per chart redraw, which is not acceptable for a 7-day chart.

**Recommended: compute once at save time and persist one scalar.**

Add to `BradykinesiaAnalyzer`:

```swift
/// Ordinary-least-squares slope of tap interval against tap index, in seconds per tap.
/// Positive = intervals lengthening across the capture. `nil` when fewer than three
/// finite intervals exist.
static func tapInterSlope(_ intervals: [Double]) -> Double?
```

Add `tapInterSlope` as an **optional** `Double` attribute on `BradykinesiaResult`. Optional
attributes are inferable, so this stays a lightweight migration under the automatic migration
already configured in `Persistence.swift`. Map it in `BradykinesiaStore.MetricMapping` alongside
the existing optional-preserving pattern, and add its unavailability to `invalidReason`.

Sessions saved before this change will have no slope. The chart must render that as a gap, not a
zero — see §6.1.

**Done.** `BradykinesiaAnalyzer.tapInterSlope` computes the OLS slope of tap interval against
tap index; `BradykinesiaMetrics.tapInterSlope` carries it; `BradykinesiaResult.tapInterSlope` is
a new optional attribute mapped by the store's existing optional-preserving `MetricMapping`, and
contributes to `invalidReason` when unavailable. 13 tests in `TapInterSlopeTests`.

### 5.5 Metrics versioning is inconsistent

`AkinesiaResult.metricsVersion` exists and is written. `BradykinesiaResult` and
`DexterityResult` have no equivalent.

A longitudinal chart spans weeks. If an analyzer formula changes mid-window, the line silently
mixes two definitions. Add `metricsVersion` (`Integer 16`, optional) to both, write it from the
stores, and have the query layer surface a "definition changed on *date*" note when a window
spans more than one version. Cheap now; impossible to reconstruct later.

**Done.** `metricsVersion` added to `BradykinesiaResult` and `DexterityResult` as optional
`Integer 16`, written from both stores, with `static let metricsVersion = 1` on
`BradykinesiaMetrics` and `DexterityMetrics`. Rows written before this change hold `0`, meaning
"formulas not identified".

### 5.6 Design tokens exist but are unused

`designSystem/` defines `Color.primaryColor`, `Font.heading`, `Spacing.md`, `Radius.primary`.
Every existing view ignores them and hardcodes `Color(.sRGB, red: 86/255, ...)`.

The clinician view is the largest view surface in the app and the only one that gets rendered to
PDF, where colour consistency actually shows. Build it on the tokens from the first commit, and
add `designSystem/chartTokens.swift` for the things charts need and the current tokens do not
cover:

- A categorical pair for left/right hand that is distinguishable without colour (the spec colours
  the timeline by hand, and a monochrome print must still work — pair hue with symbol shape).
- A neutral band fill for the baseline ribbon.
- Dose-marker stroke styles: solid for taken, dashed for skipped.
- Grid, axis, and annotation colours that hold up on white PDF paper, not just on `cream`.

**Done.** `designSystem/chartTokens.swift` adds the series, baseline, dose-marker, structure,
and geometry tokens, with hand encoded by hue **and** `ChartSymbol` shape so a greyscale print
still reads. It deliberately does not import `Charts`; the chart layer maps `ChartSymbol` onto
concrete marks. The three screens rewired in 5.1 and 5.2 are built on the existing
`Color` / `Font` / `Spacing` / `Radius` tokens rather than hardcoded sRGB literals. The older
screens (`HomeView`, `OnboardingStart`, the test views) still hardcode their colours.

### 5.7 Xcode project membership is manual

`project.pbxproj` is `objectVersion = 77` but uses classic `PBXGroup` entries with 66 explicit
`PBXBuildFile` records — **not** file-system-synchronized groups. Every new `.swift` file must be
added to the `Kinesia` target, and every new test file to `KinesiaTests`, by hand in Xcode. A
file created on disk alone will not compile and will not fail loudly. This outline adds roughly
30 files; budget for it, and merge the project file carefully across the feature branches.

---

## 6. The derivation layer

One file per concern, all pure, all in `calculations/` beside the existing analyzers.

### 6.1 Snapshots — `calculations/ReportSnapshot.swift`

The boundary type. One flat struct per row kind, built by `ReportQuery`, consumed by everything
downstream.

```swift
nonisolated struct SessionSnapshot: Sendable {
    let id: UUID
    let startedAt: Date
    let dayStart: Date
    let minutesSinceDose: Double?   // nil when medicationContext was nil
    let tapping: [TappingSnapshot]  // one per hand
    let firefly: FireflySnapshot?
    let tracing: TracingSnapshot?
}

nonisolated struct TappingSnapshot: Sendable {
    let hand: CurrentHand
    let timestamp: Date
    let numTaps: Int
    let durationSec: Double
    let tapInterMedian: Double?
    let cvTapInter: Double?
    let tapInterSlope: Double?
    let numCorrectTaps: Int
    let isValid: Bool
    let invalidReason: String?
}
```

**Two rules the snapshot layer enforces, and nothing downstream repeats:**

1. **`minutesSinceDose` becomes `Double?`**, resolved from `medicationContext != nil` (§5.3).
   The ambiguous zero cannot escape this layer.
2. **Placeholder zeros become `nil`.** All three stores write `0` into required numeric columns
   when a metric was unavailable and set `isValid = false`. `DexterityStore` documents this
   explicitly: *"Consumers must not treat a placeholder zero as a measured value when `isValid` is
   false."* A chart that plots a placeholder zero draws a dramatic dip that is pure artefact. The
   snapshot initializer is the one place that applies the rule:

   ```swift
   self.cvTapInter = row.isValid ? row.cvTapInter : nil
   ```

   Every derivation then takes `Double?` and every chart renders `nil` as a gap. This is the
   single highest-risk correctness issue in the whole feature and it is solved once, here.

### 6.2 Primary metric — `calculations/PrimaryMetric.swift`

Four charts plot "the primary metric". It needs one definition, selectable but defaulted.

```swift
nonisolated enum PrimaryMetric: String, CaseIterable {
    case tapRate          // taps/sec   — default, numTaps / durationSec
    case reactionTime     // ms         — reactionTimeMedian
    case tracingError     // route units — rmsError

    var unitLabel: String
    var higherIsBetter: Bool
    func value(_ s: SessionSnapshot, hand: CurrentHand) -> Double?
}
```

`higherIsBetter` exists so the baseline band and the longitudinal chart can orient
"improvement" without any chart hardcoding a direction — tap rate up is better, reaction time up
is worse. It is a presentation property only; it never produces a judgement label.

### 6.3 Report window — `calculations/ReportWindow.swift`

**Each chart holds its own window.** The 7 / 14 / 30 selector at the top of the report governs
only the day-scale charts. The two charts that answer questions about weeks and months carry
their own span selector, because a 7-day span makes neither readable.

`ReportWindowScale` names the three groups and the spans each one offers:

| Scale | Charts | Spans | Default |
| --- | --- | --- | --- |
| `.day` | daily timeline, time since dose, dose timing | 7, 14, 30 days | 7 days |
| `.trend` | tapping day by day | 30, 90 days, 6 months | 30 days |
| `.survey` | PDQ-8 | 6, 12, 24 months | 6 months |

7 days stays the report default, per the spec: one week of diary data predicted four-week
results well.

`ReportWindow` itself does not change. It is a value, so the view model holds one per scale and
`ReportWindow.trailing(scale:)` builds the window a chart starts on. Every window ends on the
same day, so the three spans are nested rather than offset.

Two consequences to keep straight:

- **Baselines never come from a window.** `BaselineRule.dailyValues` already reads the whole
  history, so changing the trend chart's span moves the line and leaves the band where it is.
- **`DataQuality` is computed against the `.day` window.** "5 of 7 days" has to mean the span
  the reader selected at the top, not whichever span a chart below happens to be on.

Days come from `dayStart`, which is stored as the epoch seconds of **local midnight on the day
the session began** — the day the patient experienced it as, even across midnight. Window maths
must go through `Calendar.current`, never `/ 86400`. A window spanning a DST boundary or a
timezone change has days that are not 86400 seconds long, and `dayStart` values written in a
different timezone will not align to the current one. Document the limitation; do not silently
mis-bin.

### 6.4 Dose binning — `calculations/DoseBinning.swift`

For the time-since-dose chart.

```text
bin 0        : before the first dose of the day   (medicationContext == nil)
bins 1 … 8   : 30-minute bins from 0:00 to 4:00 since last dose
bin 9        : 4 hours or more
```

Takes `[SessionSnapshot]`, returns `[DoseBin]` where each bin carries its individual points plus
`SummaryStats` over them — **reuse `SummaryStats`, do not write new percentile code.** The chart
needs median plus a 25th–75th whisker, which are `median`, `p25`, `p75`. Note that
`SummaryStats.compute` returns `nil` for fewer than two values, so a bin with one session gets
its point drawn with no whisker, which is what one value supports.

**Done.** `calculations/ClinicianView/DoseBinning.swift`. `DoseBinning.bins` returns all ten bins
every time, in x-axis order, so a bin with no sessions keeps its slot on the axis.

`DoseBin` carries `median` as well as `stats`, because `SummaryStats.compute` returns nil below
two values and a one-session bin still has a point to draw. `hasWhisker` is false for that bin.

Two cases beyond the sketch:

- **A negative `minutesSinceDose` cannot be placed.** The store only records a dose at or before
  the session start, so a negative value means the row is wrong. Those sessions are left out of
  every bin rather than forced into the first one.
- **Binning is per hand**, like §6.8, so the chart calls it once per hand.

### 6.5 Daily aggregates — `calculations/DailyAggregate.swift`

One row per calendar day in the window: the daily median of the primary metric per hand, the
session count, and the dose count. Days with no sessions produce a row with `nil` values — the
spec requires "no data" to be visible, which means the day has to exist in the array.

**Done.** `calculations/ClinicianView/DailyAggregate.swift`. `DailyAggregation.aggregate` returns
one `DailyAggregate` per day in the window, with the daily median per hand, the session count and
the taken-dose count. `DailyAggregation.medians` is the shared per-day median helper that
`TapComponentZScores` calls three times. `DailyAggregation.median` is separate from
`SummaryStats.compute` because that returns nil below two values and a day with one session has a
median.

### 6.6 Baseline — `calculations/Baseline.swift`

The evidence, straight from the review:

- Tapping frequency rises over the first ~3 days and plateaus after 5 → **exclude the first 5
  days as familiarization**.
- Roche PD Mobile showed good-to-excellent test–retest reliability between two 2-week periods →
  **baseline needs at least 14 days**.

```swift
nonisolated enum BaselineState {
    case familiarization(dayNumber: Int, of: Int)   // "day 3 of 5"
    case building(dayNumber: Int, of: Int)          // "day 9 of 14"
    case established(Baseline)
}

nonisolated struct Baseline {
    let metric: PrimaryMetric
    let hand: CurrentHand
    let center: Double          // median of daily medians
    let lower: Double           // p25
    let upper: Double           // p75
    let dayCount: Int
    let establishedOn: Date
}
```

Derived as a pure function of the ordered daily aggregates, not stored. That makes it
reproducible, testable without Core Data, and automatically correct when old data is edited or
deleted. The tradeoff is that the band moves if history changes; if a clinician needs a frozen
baseline for a trial, that becomes a `BaselineSnapshot` entity later.

**Open decision:** the band is p25–p75 of daily medians in this proposal. The alternative is
median ± 1 MAD (`SummaryStats.mad` already exists). p25–p75 is easier to explain to a clinician —
"half your baseline days fell in here" — which is why it is the default. Pick one and record it
in the ADR before building the chart, because the two produce visibly different bands.

**Done.** `calculations/ClinicianView/Baseline.swift`.

Three things differ from the sketch above:

- **`Baseline` carries no `metric`.** §6.8 needs baselines on `cvTapInter` and `tapInterSlope`,
  and neither is a `PrimaryMetric` case. The caller asked for one variable's daily values and
  knows which.
- **`Baseline` gained `spread`**, the sample standard deviation of the baseline days. §6.8 divides
  by it. The band stays p25 to p75.
- **Days are counted as days that produced a value, not calendar days.** A patient who skips days
  takes longer to reach a baseline.

The baseline is the 14 days after familiarization and does not grow as more data arrives, so the
band stays where the patient started. `BaselineRule.dailyValues` reads the whole history rather
than the window, because a baseline needs 19 days and the default window is 7.

**Open decision resolved:** the band is p25 to p75 of the daily medians. Record it in the ADR.

### 6.7 Adherence — `calculations/AdherencePoint.swift`

```text
delayMinutes = (log.timestamp − log.scheduledTime) / 60
```

One point per dose: date (x), delay in minutes (y), dose slot (colour), skipped (shape). Zero is
on schedule, positive is late, negative is early. Depends entirely on §5.1 writing
`scheduledTime`.

**Done.** `calculations/ClinicianView/AdherencePoint.swift`. One point per scheduled dose in the
window, sorted by day then slot. `slotMinutesIntoDay` identifies the slot for colouring, so it
survives the patient relabelling a dose.

Two cases the sketch did not cover:

- **`delayMinutes` is optional.** A skipped dose was never taken, so it has no delay. Drawing it
  at zero would read as on schedule, so the chart places those separately.
- **Unscheduled doses are left out.** There is no scheduled time to be late against. They still
  appear on the daily timeline and still count as a session's medication context.

### 6.8 Tapping components — `calculations/TapComponentZScores.swift`

Three z-scores, each against that variable's own baseline:

```text
z = (dailyMedian − baselineCenter) / baselineStdev
```

- speed → `numTaps / durationSec`
- rhythm → `cvTapInter`
- decrement → `tapInterSlope` (§5.4)

Returns `nil` per variable until that variable's baseline is established. Accuracy
(`numCorrectTaps / numTaps`) rides on a secondary axis in its own units, not as a z-score — it is
a compliance measure, not a motor one, and mixing it into the z-score family would imply
otherwise.

**Sign convention:** normalize every variable so that **positive z means "further from
baseline in the worsening direction"**, using `PrimaryMetric.higherIsBetter`-style per-variable
orientation. Without that, speed and rhythm point opposite ways on the same axis and the chart is
unreadable. State the convention in the method disclosure.

**Done.** `calculations/ClinicianView/TapComponentZScores.swift`. `TapComponent` has the three
cases with their own value accessors, labels and units. `TapComponents.baselineStates` builds one
baseline per component from the history; `TapComponents.points` returns one point per day per
component; `TapComponents.accuracy` is separate and in its own units.

`higherIsWorse` sets the sign, so positive z always means further from baseline in the worsening
direction: false for speed, true for rhythm and decrement.

One correction to §6.1: **speed is not gated on `isValid`.** `BradykinesiaStore` validates
`numTaps` and `durationSec` separately from the statistics and throws on a count mismatch or a
non-positive duration, so tap rate is still a measurement even when `isValid` is false. Gating it
would discard sessions because an unrelated drift CV was missing. Only `cvTapInter` and
`tapInterSlope` are gated.

### 6.9 Data quality — `calculations/DataQuality.swift`

Computed for the window, rendered by §8.

```swift
nonisolated struct DataQuality {
    let daysInWindow: Int
    let daysWithSessions: Int
    let daysWithAtLeastOneDoseLogged: Int
    let baselineState: BaselineState
    let excludedSessions: [ExcludedSession]   // id, date, reason from invalidReason
    let metricsVersionsInWindow: [Int]
    var isSparse: Bool { daysWithSessions < 5 }
}
```

`excludedSessions` is populated from the `isValid` / `invalidReason` columns the stores already
write. This is what makes the "clinician can independently review the basis" requirement real:
every session the charts dropped is named, dated, and given a reason.

**Done.** `calculations/ClinicianView/DataQuality.swift`. `DataQualityReport.compute` returns the
counts, the baseline state, the exclusions and the versions present.

Two additions:

- **Exclusions are per result, not per session.** A session can have a usable tapping result and
  an unusable tracing one. `ExcludedSession` carries the task name, the hand and the reason.
- **`definitionChanged`** is true when the window holds more than one `metricsVersion`. A row
  written before versioning existed reads as `0`.

Task names are `"Tapping"`, `"Fireflies"` and `"Constellation tracing"`. A test asserts none of
them contains a symptom word.

### 6.10 `DoseSnapshot` — added to `ReportSnapshot.swift`

§6.7 and §6.9 both need dose data and the snapshot layer had no type for it.
`DoseSnapshot` holds the scheduled day, the taken and scheduled instants, the skipped flag and
the slot, with `delayMinutes` computed. It returns nil for an unscheduled dose and for a skipped
one. Mapped from `MedicationLog` in `persistence/ReportSnapShotMapping.swift`.

### 6.11 `ReportQuery` — `persistence/ReportQuery.swift`

**Done 2026-10-17.** The fetch layer from §4: date-range fetches only, no logic.
`ReportQuery.load` returns a `ReportData` holding the window's sessions, its doses, the
questionnaires and the patient's whole session history. Relationship prefetching covers the
three result relationships and the dose schedule, so a week does not fire a fault per result.

Two things the outline did not spell out:

- **`load` returns the whole history as well as the window.** A baseline needs 19 days with
  data and the default window is 7, so §6.6 cannot work from the window alone.
- **Questionnaires are not limited to the window.** The PDQ-8 chart asks about months, and a
  7 day window would hold no answers.

`ReportSnapShotMapping.swift` now covers all five snapshot types. The §6.1 rules live in the
`SessionSnapshot` initialiser and nowhere else, and `ReportSnapshotTests` covers both.

---

## 7. The charts

All six use **Swift Charts**. Deployment target is iOS 26.5, so the full modern API is available.
Each chart is a standalone `View` taking exactly one derived array and rendering it — no fetching,
no computation, no optionals resolved in the body.

> **Built 2026-10-17 as `views/Clinician/`.** The boxed `ChartCard` below was replaced during
> design review by `ChartSection`: no card, no border, and no "question" line. Charts run the
> full width inside one page margin. Section 7.0's requirements survive in `ChartSection` —
> task name, units on the axes, a method link and a caption — but the eyebrow labels and the
> box are gone. The chart files are `DailyTimelineChart`, `TimeSinceDoseChart`,
> `AdherenceChart`, `LongitudinalTrendChart`, `PDQ8TrendChart` and `TapComponentChart`, with
> `DataQualitySection` above them and `ClinicianReportView` assembling the screen.
>
> Three things the sketch did not settle:
>
> - **Dual axes.** Swift Charts has one y scale per chart, so §7.6 maps accuracy into the
>   z-score scale and labels the trailing axis in percent. One plot area, one set of gridlines.
> - **Skipped doses.** §7.3 is two charts sharing an x scale: delays above, a skipped strip
>   below. A skipped dose has no delay and cannot sit at zero without reading as on schedule.
> - **Broken lines.** §7.4 gives each unbroken run of days its own series, so a gap stays a gap.
>
> `ReportLayout.margin` is applied once, to the scroll content and to the PDF page, so the two
> side margins cannot drift apart. `ReportTheme` swaps cream for white on paper.

### 7.0 The chart container — `views/Clinician/ChartCard.swift`

Every chart is wrapped in the same container, which is what makes the regulatory requirements
structural rather than something to remember on each screen:

```swift
ChartCard(
    title: "Tapping task through the day",   // task name, not symptom
    question: "When in the day is movement slowest, relative to doses?",
    units: "taps per second",
    method: .dailyTimeline,                  // → MethodDisclosure
    rawRows: snapshot.rows                   // → inspectable table
) { DailyTimelineChart(points: points) }
```

`MethodDisclosure` is a disclosure group holding the plain-language formula ("tap rate = taps
counted ÷ seconds of capture"), the inclusion rules, and the count of excluded sessions.
`rawRows` opens a table of the underlying values with units. Both are required on every card.

### 7.1 Daily timeline with dose markers

| | |
| --- | --- |
| Question | When in the day are symptoms worst, relative to doses? |
| Marks | `PointMark` for sessions, `RuleMark` (vertical) for doses |
| x | Time of day, midnight → midnight |
| y | Primary metric (default tap rate, taps/sec) |
| Encoding | Colour **and symbol** = hand; solid rule = dose taken, dashed rule = skipped |
| Reading | Points that drop before a dose and rise after it suggest wearing off |

Multi-day windows need either faceting by day or a day selector; a week of sessions overplotted
on one 24-hour axis is unreadable. Recommend a day selector with the week's days as a strip, so
the clinician steps through days without losing the single-day resolution that makes the
dose relationship visible.

### 7.2 Time since dose

| | |
| --- | --- |
| Question | How do symptoms change after a dose, and before the next? |
| Marks | `PointMark` per session (jittered strip), plus median `PointMark` and `RuleMark` whisker per bin |
| x | Bins from §6.4 — "before 1st dose", 30-min bins 0–4h, "4h+" |
| y | Primary metric, same units as 7.1 |
| Reading | A rise from "before 1st dose" into the 30–90 min bins suggests a dose response |

This is the chart that most directly answers question 2. Whiskers are the 25th–75th percentile
per bin. Bins with one session show the point without a whisker; bins with none show an empty
slot, not a collapsed axis.

### 7.3 Adherence

| | |
| --- | --- |
| Question | Are doses taken, and taken on schedule? |
| Marks | `PointMark`, one per dose |
| x | Date, one column per day (`MedicationLog.dayStart`) |
| y | `(timestamp − scheduledTime) / 60`, minutes |
| Encoding | Colour = dose slot; distinct shape for skipped |
| Reading | Dots near 0 are on schedule; dots above 0 are late |

A `RuleMark` at y = 0 is the reference. Given the 24.4% timing-adherence figure from the review,
this chart will often be the most informative one on the screen — it deserves a generous y-range
rather than clipping outliers.

### 7.4 Longitudinal trend

| | |
| --- | --- |
| Question | How are symptoms changing over weeks? |
| Marks | `LineMark` + `AreaMark` for the baseline band |
| x | Date, one point per day (`TestSession.dayStart`) |
| y | Daily median of the primary metric |
| Reading | Consecutive days outside the band suggest change |

Before a baseline exists the band is absent and the card shows the `BaselineState` progress
("building baseline, day 9 of 14") instead of an empty band. Days with no sessions break the line
rather than interpolating across the gap.

### 7.5 PDQ-8 trend

| | |
| --- | --- |
| Question | Is quality of life changing over months? |
| Marks | `LineMark` with visible points |
| x | `PDQ8Log.timestamp` |
| y | `scoreIndex`, 0–100 |
| Reading | An increasing line means worse quality of life |

Explicitly annotate the direction on the axis. A rising line meaning "worse" is the opposite of
every other chart here and is the easiest misread in the view.

### 7.6 Tapping components

| | |
| --- | --- |
| Question | Which part of tapping is changing — speed, rhythm, or decrement? |
| Marks | One `LineMark` per variable |
| x | Date |
| y | z-score from baseline, per variable |
| Secondary | Accuracy (`numCorrectTaps / numTaps`) on its own axis, in percent |
| Reading | Shows which component of the task is moving, when the primary metric only says that something is |

Requires §5.4 and an established baseline. The sign convention from §6.8 goes in the method
disclosure, not just in a code comment.

### 7.7 Session detail

Reached from the session list. Three task-specific panels, each reading `RawCapture.payload` on a
background context (§4.3).

- **Tapping** — `LineMark` of inter-tap interval (ms) against tap index. Intervals that lengthen
  across the capture are within-session slowing; tall isolated spikes are hesitations. This is the
  visual basis for the decrement scalar in 7.6, which is exactly the "independently review the
  basis" requirement.
- **Firefly** — `PointMark` per round: x = round number, y = reaction time (ms), **symbol =
  outcome** (completed, no catch, missed, false start, slip). Movement time renders as a separate
  series, never averaged into reaction time — `AkinesiaMetrics` already keeps them apart and the
  chart must not undo that.
- **Constellation** — the canonical `constellation-v1` route drawn as a path with the recorded
  trace overlaid, coloured by distance from the route. Both in canonical route units, so the
  overlay is scale-independent by construction; `DexteritySessionCapture` already stores the route
  transform needed to invert the local samples.

**Note on the source spec:** the chart table in the PDF merged two rows here — the "fireflies"
row carried "time between taps in ms" and `TapSample.t`, which are tapping quantities, not
firefly ones. `RoundRecord` has no inter-tap interval, so that chart could not have been built
as written. Confirmed 2026-10-17 that the split above is what was meant.

Both axes are in milliseconds and both sit on one screen, so the axis titles are what keeps them
apart: `Gap between taps (ms)` against `Reaction time (ms)`. One measures how fast repeated
movement is sustained, the other how long it takes to start. Keep those titles when building this
section.

### 7.8 What the device pass changed

Built and driven in the simulator at 7, 14 and 30 days on 2026-10-17. Five things the sketch
did not anticipate:

- **Axis label density.** Striding by day printed 30 labels on a 30 day window.
  `ReportFormat.labelStride` keeps a tick on every point and thins labels to at most six.
  The same applies to the component chart and, over two years, the PDQ-8 chart.
- **Out-of-domain marks are held in by the domain, not by clipping.** A fixed ±2 SD domain on
  §7.6 let an outlying day draw its line over the legend and the link below the chart. Each
  chart's y domain now follows its own data, with a floor of ±2 on the component chart.
  Clipping the plot area was tried and reverted: `.clipped()` also removes `RuleMark`
  annotations, which sit just outside the plot, so it dropped the dose times from the daily
  timeline. `ReportExportTests.testEveryChartReachesTheExport` fails on that, by asserting each
  chart's axis label reaches the printed page.
- **Repeated exclusions.** Three readings failing on one day printed three identical lines.
  Identical ones are now counted into one.
- **Stacked axis labels need both rows.** A count under an unlabelled bin rode up into the
  line of labels beside it, because its `VStack` had nothing above it.
- **Pluralisation.** "1 readings" and "day(s)" were visible on device. `ReportFormat.count`
  covers every count string in the report.

`views/Clinician/ReportSeed.swift` writes 45 days of history behind a `#if DEBUG` link at the
bottom of the report, so the charts can be looked at on a device. It is not in a release build.

**Still open from the sketch:** accuracy shares §7.6's y scale with a relabelled trailing axis.
It is arithmetically right, but "above the line" means worse for the three components and means
nothing for accuracy. Moving accuracy to its own strip under the chart, the way skipped doses
sit under §7.3, would remove the ambiguity.

---

## 8. Data quality section

Renders `DataQuality` (§6.9) at the top of the report, above the charts. It is first because a
clinician reading a sparse week needs to know that before they read a trend into it.

- Check-ins completed vs. days in window
- Baseline status: "familiarization day 3 of 5" / "building baseline, day 9 of 14" / "baseline set
  on 12 Oct 2026"
- Sessions left out, each with its date and `invalidReason`
- Days with at least one dose logged
- **A warning when fewer than 5 days have sessions**
- Days with no sessions rendered as "no data", never as a gap the eye fills in

Plain, factual, no colour judgement. "3 of 7 days have sessions" — not "poor adherence".

---

## 9. Export and sharing

The spec calls for delivery by phone view or PDF, with the patient deciding how data goes out.

**`views/Clinician/ReportExport.swift`**

```swift
@MainActor
struct ReportExport {
    static func renderPDF(_ report: ReportBundle) throws -> URL
}
```

Mechanics:

- `ImageRenderer` draws the same SwiftUI chart views into PDF pages via
  `render { size, context in ... }` writing into a `CGContext` PDF consumer. Reusing the chart
  views is the point: there is no second rendering path to keep in sync, and what the clinician
  sees on paper is what the patient saw on screen.
- Fixed page geometry (US Letter, 612 × 792 pt) and explicit frame sizes on each chart. Charts
  sized by the device viewport will reflow unpredictably into a page.
- Light-mode colour scheme forced for print, using the §5.6 chart tokens.
- Page composition: data quality + date range + metadata, then one chart per page or two where
  they pair naturally, then the excluded-session list.
- **Every page footer: "Not a diagnostic tool."** Rendered by the page template, so it cannot be
  omitted by forgetting it on a chart.

Sharing:

- Patient chooses the date range and which charts are included before export. The default is the
  full set; the choice is theirs.
- Output goes to a temporary file handed to `ShareLink` / `UIActivityViewController`. **No network
  code anywhere in this feature.** The app stays local-first and the patient's share sheet is the
  only egress.
- A confirmation step naming the date range and chart count before the sheet opens, so an export
  is never one stray tap away.

**Built 2026-10-17.** The signature is `ReportExport.renderPDF(model:) throws -> URL`, taking the
view model rather than a `ReportBundle`: the model already holds the window and every derived
array, and a second bundle type would have been one more thing to keep in step.

What the sketch got right: `ImageRenderer` into a `CGContext` PDF consumer, fixed 612 x 792 pt
geometry, a forced light colour scheme, the chart views reused rather than redrawn, and a page
template that draws the disclaimer and the page number so no individual chart can omit them. The
page fill is white behind the whole sheet, which guards the margin if a chart renders a
transparent background.

Four pages, two charts each, with the data quality table sharing the first:

| Page | Holds |
| --- | --- |
| 1 | data quality, then the daily timeline |
| 2 | time since dose, then dose timing |
| 3 | the daily trend, then PDQ-8 |
| 4 | the tapping components |

`ReportExportTests` asserts the page count against `ReportExport.pageCount`, the media box of
every page, equal side margins, the disclaimer and page number on each page, no symptom word in
the extracted text, and a white page inside the margin.

**Refactored 2026-10-18.** The export used to compose its own six `ChartSection`s, which meant
every title, subtitle, legend and caption existed twice, once per surface. They drifted: two
headings differed, the captions survived on screen only, and the printed subtitles skipped
`ReportFormat.count`, so a one-dose window printed "1 scheduled doses". Sections are now
described once in `ReportSections.all(for:)` and the export slices that list into pages through
`ReportSections.pageGroups`, so pagination is the only thing it decides. A section's content
closure takes the theme, which keeps the day selector and the baseline progress bar off paper.

**Still open:** the two sharing controls. There is no chart selection and no confirmation step
naming the range before the share sheet opens; the export button renders and hands the file
straight to `ShareLink`. The method link that would print the basis of each chart is also still
unwired, so the PDF omits it rather than printing a control nobody can tap.

---

## 10. Testing

Match the existing conventions: pure value types, synchronous drives, in-memory Core Data via
`TestCoreDataStack`, no sleeping.

| Suite | Covers |
| --- | --- |
| `MedicationStoreTests` | schedule seeding, dose logging, `scheduledTime` resolution across local days, skip logging, validation rejections leaving the context empty, fetch ordering |
| `PDQ8StoreTests` | item-score round trip, `rawSum` / `scoreIndex` arithmetic, range validation |
| `ReportSnapshotTests` | **placeholder zeros becoming `nil` when `isValid` is false**; `minutesSinceDose` resolving to `nil` when `medicationContext` is nil; no `NSManagedObject` escaping |
| `ReportWindowTests` | day boundaries through `Calendar`, DST transition, window containing days with no sessions |
| `DoseBinningTests` | every bin edge exactly (0, 30, 240 minutes), the "before first dose" bin, the 4h+ bin, empty bins preserved, single-session bins producing no whisker |
| `BaselineTests` | the 5-day familiarization exclusion, the 14-day minimum, each `BaselineState` transition, band arithmetic, insufficient data |
| `AdherencePointTests` | delay sign, missing `scheduledTime`, skipped doses, dose-slot grouping |
| `TapComponentZScoreTests` | z-score arithmetic, per-variable sign orientation, `nil` before baseline, accuracy kept off the z-axis |
| `DataQualityTests` | the fewer-than-5-days warning boundary, excluded-session collection, mixed `metricsVersion` detection |
| `TapInterSlopeTests` | OLS slope arithmetic, fewer than three intervals, non-finite input, a flat sequence giving zero |
| `ClinicianCopyTests` | no symptom-named test labels, no severity or judgement words, no recommendation phrasing, every chart has units, the "not a diagnostic tool" string present on every page template |

Boundary arithmetic trap already documented in `docs/TESTING.md` applies here too: a timestamp
built by addition does not survive subtraction (`(10.0 + 0.120) - 10.0 == 0.11999999999999922`).
Bin-edge tests must anchor at zero so the subtraction is exact.

Chart views themselves are not unit tested — the derivations carry the logic, which is the whole
point of keeping the views dumb. A small set of snapshot previews with fixture data covers
rendering.

**Built 2026-10-17**, and every suite above exists except `ClinicianCopyTests`. The target
declares 629 tests; per-suite counts and coverage are in `docs/TESTING.md`. What matters here is
where the plan changed:

- **Copy rules live in `ReportFormatTests` and `ReportExportTests`,** not in a separate
  `ClinicianCopyTests`. Task names are asserted to carry no symptom word where they are defined,
  and the disclaimer is asserted on every exported page. A dedicated copy suite covering
  severity and recommendation vocabulary across the view strings is still worth adding, the way
  `AkinesiaCopyTests` does for the firefly screens.
- **Three suites the plan did not list** turned out to be necessary: `ReportFormatTests` for the
  axis and count formatting that produced "1 readings" and a 30-label axis on device,
  `ClinicianReportModelTests` for the load-and-rebuild behaviour, and `ReportExportTests` for
  the page geometry.
- **Eight derivation suites share `ReportFixtures`** and never open a Core Data store.
  `ReportSnapshotTests` and `ReportQueryTests` do open one, and each asserts that what it read
  back still reads correctly after `context.reset()`, which is the check that no snapshot is
  holding a managed object.

---

## 11. Build order

Sequenced so each phase ships something runnable.

| Phase | Work | Unblocks |
| --- | --- | --- |
| ~~**0**~~ | ~~§5.1 `MedicationStore` + real `MedicationLogView`; §5.2 `PDQ8Store` + real questionnaire~~ **Done 2026-10-16.** | Every dose-linked chart. Nothing else can start. |
| ~~**1**~~ | ~~§5.4 `tapInterSlope`, §5.5 `metricsVersion`, lightweight migration~~ **Done 2026-10-16**, together with §5.6 chart tokens. | 7.6 |
| ~~**2**~~ | ~~`ReportQuery`, snapshots, `PrimaryMetric`, `ReportWindow` + their tests~~ **Done 2026-10-17.** | Everything downstream |
| ~~**3**~~ | ~~`DoseBinning`, `DailyAggregate`, `Baseline`, `AdherencePoint`, `TapComponentZScores`, `DataQuality` + tests~~ **Done 2026-10-17.** | The charts |
| ~~**4**~~ | ~~`chartTokens`, `ChartCard`, charts 7.1–7.3~~ **Done 2026-10-17** as `ChartSection`. | First usable screen |
| ~~**5**~~ | ~~`Baseline` UI, charts 7.4–7.6, data quality section~~ **Done 2026-10-17.** | Full report |
| **6** | Session detail 7.7 with background `RawCapture` decoding | Independent review of the basis |
| ~~**7**~~ | ~~`ReportExport`~~ **Done 2026-10-17**: 4 page US Letter PDF, white, equal margins, disclaimer and page number on every page, shared with `ShareLink`. Sharing gate and a dedicated copy suite still open. | Delivery |

Phases 0 to 5 and 7 are done. What is left is phase 6, the session detail screen, and three
smaller pieces that each belong to a phase already marked done: the method and readings sheet
behind `ChartSection`'s link (§7.0), the export confirmation step (§9), and a copy suite over
the view strings (§10). None of them blocks another.

---

## 12. Decisions that need making before the code is written

1. ~~**Baseline band definition**~~ **Resolved:** p25 to p75 of the daily medians. §6.6.
2. ~~**Baseline recomputation**~~ **Resolved:** derived live, over a fixed 14-day span that does not grow. §6.6.
3. ~~**Default primary metric**~~ **Resolved:** tap rate. `ClinicianReportModel.metric`
   defaults to `.tapRate`, and the Measure control switches to reaction time or tracing error.
   §6.2.
4. **PDQ-8 re-prompt cadence** — the months-scale chart needs more than one data point. §5.2.
   Still open. (A decision given on 2026-10-17 as "4" was about composite scores; that is
   recorded in §13, which is where it belongs.)
5. ~~**Daily timeline across multiple days**~~ **Resolved:** a day selector. The last seven days
   of the window are a strip of 44 pt buttons under the chart, and
   `ClinicianReportModel.timelinePoints(for:)` scopes the chart to one day, so the dose
   relationship stays readable at single-day resolution. The strip is screen-only; the PDF
   prints the selected day, which defaults to the most recent day in the window. §7.1.
5b. ~~**Does the window selector govern the long-span charts?**~~ **Resolved 2026-10-17:** no. Each longitudinal chart has its own span selector. §6.3.
6. ~~**The merged chart row in the source spec**~~ **Resolved 2026-10-17:** the split is
   correct. They are two charts from two tasks. The tapping interval series plots the gap
   between consecutive taps against tap number, from `TapSample.t`, within one capture. The
   firefly round plot plots reaction time against round number, from `RoundRecord`, with the
   symbol carrying how each round ended. §7.7.
7. ~~**HealthKit**~~ **Resolved 2026-10-17:** `HealthKitLog` stays in the schema, but watch
   data is not in scope for this view and ingesting it is not a priority. The entity is kept
   deliberately, not left over. Nothing in the report reads it.
8. ~~**Multi-patient or clinician-side accounts**~~ **Resolved 2026-10-17:** one patient, one
   clinician. No accounts, no roster, no clinician-side login. The report stays patient-owned and
   on-device, and the share sheet in §9 is the only way it leaves the phone.

---

## 13. What this view explicitly does not do

Consistent with the boundaries already recorded in `docs/CLINICAL_BASIS.md`:

- **No severity score, composite score, or normalized index — ever.** Decided 2026-10-17.
  The report shows raw measurements with their units and nothing derived from them beyond the
  descriptive statistics each chart names. This is a permanent product boundary, not a deferral:
  no later version adds a single number summarising how the patient is doing.
- No left/right asymmetry index — both hands live in one session, so asymmetry is a query away,
  but the definition is a clinical decision that has not been made.
- No diagnosis, no classification, no OFF/ON state inference.
- No dose recommendation of any kind.
- No comparison against a population. Every band and every z-score is the patient against their
  own baseline.
- No claim of clinical validation of the app.

The view supports a clinical conversation. It does not have one.

---

*Not a diagnostic tool.*
