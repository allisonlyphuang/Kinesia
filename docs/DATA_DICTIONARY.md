# Data dictionary

## Bradykinesia: tapping
### "left" and "right"
| Name | Meaning | Set in |
| --- | --- | --- |
| `leftCenter`, `rightCenter` | where the two target circles are drawn | `BradykinesiaTestScreen.targetGeometry(in:)` |
| `CurrentHand.left`, `.right` | which hand is being tested | `BradykinesiaTestConfiguration.handOrder` |
| `leftDrift`, `rightDrift` | the mean-X partition of tap coordinates | `BradykinesiaAnalyzer.paperSpatialPartition` |
Regardless of which hand is being used, taps are still split into left/right statistical partitions by mean x. 

### Raw trial data

#### `TapSample`
| Field | Type | Meaning |
| --- | --- | --- |
| `t` | `TimeInterval` |  `UITouch.timestamp` at touch. It is monotonic/touch-relative timing. |
| `x` | `Double` | Tap x-coordinate in the coordinate space. |
| `y` | `Double` | Tap y-coordinate in the coordinate space. |
| `target` | `TapTarget` | UI hit classification: `.left`, `.right`, or `.miss`. |
`target` values are produced by `RawTouchView.classify`. `.left` means the distance of the tap from the center of the left circle was within `targetRadius`, `.right` is classified the same way, `.miss` means it is outside both circles.
`target` is only used by `numCorrectTaps` .

#### `TapTrial`
The complete recording for one 20 second tapping trial.

| Field | Meaning |
| --- | --- |
| `samples` | Each `TapSample` in order, including misses. |
| `leftCenter`, `rightCenter` | Displayed target centers in the same local coordinate space as `x` and `y`. |
| `targetRadius` | Displayed/UI-classification target radius. |
| `startedAt` | Monotonic start time for the round/trial. |
| `hand` | `CurrentHand` ; current hand being tested. |
| `screenScale` | Active display scale used while the trial was configured. |
`CurrentHand` is a `String` enum; it encodes to JSON as `"left"` / `"right"`.

#### `HandAttempt`
Stored record of one completed hand. 

| Field | Meaning |
| --- | --- |
|  `hand`|  Current hand for this hand attempt. |
| `trial` |  The `TapTrial` containing this attempt's data.  |
| `BradykinesiaMetrics` | Collected metrics for this attempt. |
| `startedAt` | Monotonic time that the round began. |

### Temporal metrics
For sample order, the analyzer derives:

```text
TapInter[t] = T[t] - T[t-1]
```

Samples are never sorted or silently removed. Timestamps must be finite and strictly increasing. Invalid timestamps make temporal-derived values unavailable while preserving `numTaps` and raw samples.

`tapInterStats` contains min, max, mean, median, p25, p75, range, IQR, and `stdev`. Percentiles use linear interpolation at `fraction * (N - 1)`. `SummaryStats.stdev` is **sample** standard deviation, with denominator `N - 1`.

The paper-derived helpers intentionally use population standard deviation:

```text
populationSD = sqrt(sum((x - mean)^2) / N)
CV = populationSD / mean * 100
skewness = mean((x - mean)^3) / populationSD^3
```

`cvTapInter` and `skewTapInter` use those paper-derived formulas, not `SummaryStats.stdev`.

### Paper-derived spatial metrics

For finite raw coordinates:

```text
meanX  = mean(all tap x coordinates)
Pleft  = taps where x < meanX
Pright = taps where x >= meanX
```

The filtered partitions preserve original tap order. Their UI target classifications, including `.miss`, have no effect on this calculation.

`DriftLeft` and `DriftRight` are Euclidean distances between consecutive positions within their own filtered partitions:

```text
distance = sqrt((x2 - x1)^2 + (y2 - y1)^2)
```

For each drift sequence, the analyzer provides the same descriptive statistics plus paper-derived CV and skewness. `corXY` is Pearson correlation across all raw x/y coordinate pairs; it is not partitioned by UI target or mean-X side.

### Correct taps

`numCorrectTaps` counts taps that land inside the target the protocol expects next.

```text
expected = right
for each tap in capture order:
    if tap.target == expected:
        count += 1
        expected = the other side
    else:
        no count, expected unchanged
```

- The sequence **opens on the right**. The on-screen instruction states this. A participant
  who opens on the left loses that tap and stays offset for the rest of the trial.
- A **miss** is not counted and **does not advance** the expected target — the target that was
  owed is still owed. `right, miss, left` scores 2.
- A **wrong-target hit** is treated the same way. `right, right, left` scores 2.
- Always computable, so `BradykinesiaMetrics.numCorrectTaps` is a non-optional `Int`.
  `numCorrectTaps <= numTaps` always holds.

This is the only metric that reads `TapTarget`.

### Availability semantics

The calculation layer represents unavailable derived values as `nil`, never as NaN, infinity, or a fabricated zero. Examples include insufficient samples, non-finite input, non-increasing timestamps, zero-variance skewness, and undefined Pearson correlation.

`BradykinesiaResult` has required numeric Core Data fields. If an unavailable mapped metric prevents a complete result, persistence sets `isValid = false`, provides `invalidReason`, and stores the required numeric placeholder. **A placeholder zero is not a measured zero when `isValid == false`.**

This matters most for the CV columns: `cvTapInter = 0` is a plausible reading meaning *perfectly
regular tapping*, the healthiest possible result. Always consult `isValid` before interpreting a
CV value.

### Persisted objects

Each completed test creates **one** `TestSession`, and **one** `BradykinesiaResult` plus **one**
`RawCapture` per hand. A bilateral test therefore writes five rows in a single transaction.

| Object | Key fields/semantics |
| --- | --- |
| `TestSession` | Explicit wall-clock `startedAt` (earliest hand's start), `completedAt` (latest hand's completion), and `dayStart`. Supplied as `Date` values, separate from raw touch timing. |
| `BradykinesiaResult` | Per hand. Schema-backed counts, temporal summaries, drift summaries, CVs, correlation, measured duration, validity, and session relationship. |
| `RawCapture` | `kind = "bradykinesia"`, `schemaVersion = 1`, and JSON-encoded `TapTrial` in `payload`. One per hand; the hand is inside the payload. |

`payload` holds the actual captured data; `kind`, `schemaVersion`, `timestamp`, and `session`
are labels that let you find and interpret it without decoding it.

#### Field notes

| Field | Semantics |
| --- | --- |
| `TestSession.dayStart` | Local midnight of the day the test **began**, not the day it ended. A session crossing midnight is filed under its start day. |
| `TestSession.medicationContext` | The most recent `MedicationLog` with `wasSkipped == false`, taken on or after `dayStart` and at or before the session's `startedAt`. `nil` when no such dose exists. |
| `TestSession.minutesSinceDose` | Minutes from that dose to the session start. **Only meaningful when `medicationContext` is non-nil.** When no dose qualifies, the stored `0` is a schema placeholder, not a measurement. |
| `TestSession.status` | Reserved and unwritten. Every persisted session is complete by construction, so the stored `0` carries no meaning. Do not read it until a status vocabulary is defined. |
| `BradykinesiaResult.hand` | `CurrentHand.rawValue` — `"left"` or `"right"`. |
| `BradykinesiaResult.durationSec` | The **measured** monotonic capture window (`monotonicCompletedAt - trial.startedAt`), not the nominal 20 seconds. Validated as finite and positive before writing. Expect small run-to-run variation above `captureDuration`; see the drift note in ARCHITECTURE.md. |
| `BradykinesiaResult.numCorrectTaps` | See "Correct taps" above. |
| `BradykinesiaResult.cvTapInter`, `cvDriftLeft`, `cvDriftRight` | Paper-derived population CVs, as percentages. Participate in `isValid` / `invalidReason`. |
| `BradykinesiaResult.tapInterSlope` | Decrement. See "Decrement" below. Participates in `isValid` / `invalidReason`. |
| `BradykinesiaResult.metricsVersion` | Which set of formulas produced this row. See "Metrics versioning" below. |
| `BradykinesiaResult.accelMeanG`, `accelMaxG`, `deviceMoved` | Reserved for MotionQC. Never written; schema defaults only. |

Both hands of one test share a single `TestSession`, so a bilateral test has exactly one
medication context, one `dayStart`, and one pair of session bounds.

### Decrement

`tapInterSlope` is the ordinary-least-squares slope of tap interval against **tap index**:

```text
x[i] = i                      (the interval's ordinal position, 0-based)
y[i] = TapInter[i]            (seconds)
slope = sum((x - mean(x)) * (y - mean(y))) / sum((x - mean(x))^2)
```

Units are **seconds per tap**. Positive means intervals lengthened across the capture, so the
participant slowed down while tapping. Negative means they sped up. Zero is a flat sequence.

The regressor is the ordinal position, not the timestamp, so the value does not change when a
capture window is longer or shorter. A capture of the same behaviour over 10 seconds and over 20
seconds reports the same decrement.

`nil` for fewer than three intervals, where a line through the points says nothing about a
trend. Three intervals needs four taps, which a 20-second capture clears many times over, so in
practice this only fires on an abandoned or malformed trial.

This is a **trend** measure, not a hesitation detector. A single large interval in the middle of
an otherwise even sequence leaves the slope at zero. Hesitations are visible in the
within-session interval series drawn from `RawCapture`, not in this scalar.

### Metrics versioning

`metricsVersion` records which set of formulas produced a row, so a chart spanning weeks can tell
when a definition changed inside its own window rather than silently mixing two of them.

| Value | Meaning |
| --- | --- |
| `0` | Written before versioning existed. The formulas are not identified. |
| `1` | The first stamped set. For tapping this is the set that includes `tapInterSlope`. |

`AkinesiaResult`, `BradykinesiaResult`, and `DexterityResult` each carry their own version; the
three are independent and a change to one does not bump the others.

## Medication

### `MedicationSchedule`

One row per scheduled dose in the patient's day. `hour` and `minute` are a local clock time, not
an instant: the row says "8:00 every day", and the actual occurrence is resolved per day.

Replacing the schedule **deactivates** the old rows rather than deleting them. `MedicationLog`
points at them, and a patient who moves their 8:00 dose to 9:00 has not retroactively changed
when last month's doses were due. Always read through `MedicationStore.activeSchedule`, which
filters on `isActive`; a historical log will correctly reference an inactive row.

| Field | Meaning |
| --- | --- |
| `hour`, `minute` | Local clock time of day, 0–23 and 0–59. |
| `dosageMg` | Milligrams. **Zero is allowed and is not missing data** — plenty of patients do not know the number, and the dose still has a time, which is what every dose-linked chart needs. |
| `label` | Optional. What the patient calls the dose. |
| `sortIndex` | Position in time-of-day order, assigned on save. |
| `isActive` | False once a later schedule replaced this row. |

### `MedicationLog`

One row per dose the patient recorded, taken or skipped.

| Field | Meaning |
| --- | --- |
| `timestamp` | When the dose was actually taken. For a **skipped** dose there is no take time, so this holds the scheduled occurrence instead; a zero here would file the row in 1970. |
| `scheduledTime` | When the dose was due. **`0` is the sentinel for "not on the schedule"**, never a real scheduled time. |
| `dayStart` | Local midnight of the **scheduled** day when the dose has a schedule, otherwise of the day it was taken. |
| `wasSkipped` | The patient recorded that they did not take this dose. |
| `source` | `"manual"` today. Reserved for an imported or notification-confirmed dose later. |
| `schedule` | The slot this dose belongs to, possibly now inactive. `nil` for an unscheduled dose. |

Three rules that are easy to get wrong:

**Read `scheduledTime` through `MedicationLog.scheduledDate`, never directly.** The attribute is
a non-optional `Double` defaulting to `0`, so an unscheduled dose read raw looks like it was due
on 1 January 1970 and therefore 55 years late. `scheduledDate` returns `nil` for the sentinel,
and `delayMinutes` returns `nil` with it.

**A dose is filed under the day it was due, not the day it was taken.** A dose scheduled for
23:00 and taken at 00:30 is 90 minutes late, and it belongs in the adherence column for the day
it was due. `MedicationStore` resolves `scheduledTime` to the occurrence **nearest** the taken
time, searching yesterday, today, and tomorrow, so the same lateness never reads as 22.5 hours
early.

**Not recorded, taken, and skipped are three different facts.** The absence of a row means the
patient has not answered yet. It never means the dose was skipped.

Adherence is then:

```text
delayMinutes = (timestamp - scheduledTime) / 60
```

Zero is on schedule, positive is late, negative is early, and `nil` is an unscheduled dose that
has nothing to be late against.

### Dose context on a session

`TestSession.medicationContext` is the most recent **non-skipped** `MedicationLog` on the
session's own local day, at or before the session started.

**The only correct test for "did this session have a dose before it" is
`session.medicationContext != nil`.** Not `minutesSinceDose > 0`: `minutesSinceDose` is a
non-optional `Double` defaulting to `0`, so zero means either "tested at the exact moment of a
dose" or "no qualifying dose that day". Testing the number instead of the relationship silently
drops every pre-first-dose session, which is precisely the OFF-state data the wearing-off
question depends on.

Skipped doses are excluded because the association exists to express time since an *actual*
dose. An unscheduled dose is included: it is still a dose the patient took.

## PDQ-8

The eight-item short form of the PDQ-39 quality-of-life questionnaire — one item per PDQ-39
dimension. This is the only self-report measure in the app, and the only one that is not a touch
timestamp.

Eight items, each answered on a five-point scale scored 0 to 4:

```text
rawSum     = sum of the eight item scores            (0 to 32)
scoreIndex = rawSum / 32 * 100                       (0 to 100)
```

| Field | Meaning |
| --- | --- |
| `itemScores` | JSON-encoded `[Int16]`, eight values in `PDQ8Item` order. Stored so a clinician can see *which* dimension moved, not just the total. |
| `rawSum` | 0 to 32. |
| `scoreIndex` | 0 to 100. |
| `timestamp`, `dayStart` | Wall clock, and local midnight of the day it was completed. |

Two things to hold onto:

**Higher means worse.** A rising PDQ-8 line means quality of life declined. That is the opposite
direction to every motor metric in the app and is the easiest misread in the whole clinician
view, so the chart annotates the direction on its axis.

**A partial questionnaire is never scored.** A missing item is not a zero; scoring seven of eight
would understate the index and show an improvement that did not happen. `PDQ8Score.compute`
throws rather than scoring an incomplete set, so nothing partial reaches the store.

The PDQ family is licensed by Oxford University Innovation. Confirm the licence position before
shipping. Nothing in the scoring depends on the exact item wording, so licensed phrasing can be
substituted into `PDQ8Item.prompt` without touching any arithmetic.

# Dexterity data dictionary

Dexterity V1 is a fixed right-hand, right-index-finger constellation tracing interaction for longitudinal movement measurement. It is not represented here as a diagnostic or independently clinically validated test.

## Raw capture

| Type / field | Meaning |
| --- | --- |
| `DexterityTracePoint.t` | Monotonic `UITouch.timestamp`; never a wall-clock epoch. |
| `x`, `y` | Raw local capture-view coordinates. |
| `segmentIndex` | The active ordered canonical route segment at that exact sample. |
| `DexteritySequence` | One continuous-contact attempt, including `completed`, `endedByLift`, and `endedByCancellation`. |
| `DexteritySessionCapture` | Full V1 session history: route/transform, practice attempts, all scored attempts, and the indexes of the three completed scored attempts. |

The V1 route is `constellation-v1`, version 1: `(15,80) → (20,20) → (50,45) → (80,20) → (85,80)`, with target radius 8 canonical units. It uses one successfully completed practice attempt and three successfully completed scored attempts. Lifts/cancellations are retained but do not count as completed scored sequences.

## Dexterity metrics

Raw local samples are transformed into canonical route coordinates using the saved uniform transform. Only the three completed scored attempts contribute to the following primary fields:

| Field | Meaning |
| --- | --- |
| `rmsError` | Aggregate root-mean-square point-to-assigned-segment error across all three scored traces, in canonical route units. |
| `rmsErrorMax` | Maximum *per-sequence* RMSE across the three scored traces. It is not the maximum individual point error. |
| `swipeDist` | Mean actual canonical path length per completed scored sequence; each path length is the sum of consecutive in-sequence point distances. |
| `swipeSpeed*` | Descriptive statistics of canonical-distance / monotonic-time speed samples, aggregated within—not across—the three scored sequences. |
| `fingerLifts` | Count of incomplete normal-lift attempts during the scored portion only. Practice lifts and cancellations are excluded. |

`maxPointError` and speed CV are computed-only values and are not written into unrelated Core Data fields. The former must not be substituted for `rmsErrorMax`.

`DexterityResult` belongs to one `TestSession`; the session has a `RawCapture` whose `kind` is `dexterity`, schema version is 1, and JSON payload is `DexteritySessionCapture`. `fingerLifts` replaces the prior model attribute name `thumbLifts` with Core Data's renaming identifier retained for lightweight migration.
## Akinesia: fireflies

The in-memory value types come first, then the columns `AkinesiaStore` maps them onto.

### One round — `RoundRecord`

| Field | Meaning |
| --- | --- |
| `index` | round number within the session, starting at 0 |
| `isPractice` | practice rounds are counted but never scored |
| `homeSettledAt` | when the finger had rested on the jar long enough for the wait to begin |
| `plannedForeperiod` | the random wait this round drew, between 1 and 4 seconds |
| `cueOnsetAt` | the frame the firefly actually appeared on |
| `liftOffAt` | the finger leaving the jar |
| `catchAt` | the finger landing on the firefly |
| `returnedHomeAt` | the finger back on the jar. Not scored, but it is when the next wait starts, so it is still recorded. |
| `spawn` | where the firefly appeared |
| `captureOutcome` | what the board saw: `completed`, `falseStart`, `slip`, or `missed` |
| `scoredOutcome` | a placeholder. The analyzer always recomputes this and ignores whatever is stored. |

Every timestamp here is monotonic — seconds since the phone booted, never a date or a time of
day. See "Two clocks, never mixed" in ARCHITECTURE.md.

A round can be missing timestamps and still be valid. A false start has no `cueOnsetAt` because
the firefly never appeared. A round where the patient lifted but never reached the firefly has no
`catchAt`, and its reaction time still counts.

### One session — `AkinesiaTrial`

Holds every round plus the context needed to read them later: where the jar was and how big it
was, how big the firefly was, the ring the firefly spawns on, which hand and finger were used,
the screen scale, the screen's refresh rate, and the cue type (`"visual"` for now).

Hand, finger, and device all matter because switching any of them breaks comparisons against a
patient's own earlier sessions.

### Derived numbers — `AkinesiaMetrics`

| Field | Meaning |
| --- | --- |
| `numRounds` | scored rounds attempted; practice not included |
| `numPracticeRounds` | practice rounds seen |
| `numValidRounds` | rounds that produced a usable reaction time |
| `numAnticipations` | responses too fast to be a real reaction |
| `numLapses` | responses slow enough to look like a lapse in attention |
| `numFalseStarts` | lifted before the firefly appeared |
| `numSlips` | finger came off the jar without the patient meaning to |
| `numMissed` | never lifted at all |
| `numMalformed` | the round claimed to be completed but its timestamps could not produce a reaction time |
| `reactionTimes` | the usable reaction times, in the order they happened |
| `reactionTimeStats` | a summary of those. `nil` when there were fewer than 8. |
| `movementTimes` | lift-off to catch, for valid rounds that also have a catch time |
| `movementTimeStats` | a summary of those, `nil` under the same rule |

Three things to know when reading these:

- **The seven outcome counts add up exactly to `numRounds`.** A test asserts it, so if they ever
  disagree something is wrong rather than merely surprising.
- **`numMalformed` is deliberately kept apart from `numMissed`.** One is a data fault, the other
  is a patient failing to start a movement. Someone reading `numMissed` should not find data
  faults mixed into it.
- **`nil` statistics mean "too little data to summarise", not zero.** The counts and the raw
  times are still there. This follows the same rule as the tapping test; see "Availability
  semantics" above.

`movementTimes` can be shorter than `reactionTimes`, because a round can produce a reaction time
without producing a movement time. Movement time is never averaged into the reaction-time
statistics: it measures what the tapping test already measures.

### Statistics — `SummaryStats`

| Field | Meaning |
| --- | --- |
| `p90` | the 90th percentile — the slow tail, where trouble starting a movement shows up before the middle of the distribution moves |
| `mad` | median absolute deviation — how spread out the values are, measured so that one extreme value cannot distort it |

### Persisted objects

One completed session writes **one** `TestSession`, **one** `AkinesiaResult`, and **one**
`RawCapture` (`kind = "akinesia"`, `schemaVersion = 1`, the whole `AkinesiaTrial` as JSON) in a
single transaction.

| Field | Semantics |
| --- | --- |
| `AkinesiaResult.timestamp` | Wall clock, the session's completion. Result fetching is newest-first on this column. |
| `AkinesiaResult.dayStart` | Local midnight of the day the session began. |
| `AkinesiaResult.hand` | `CurrentHand.rawValue`. The finger is in the payload, not a column. |
| `reactionTime*` | min, max, mean, median, p25, p75, **p90**, stdev, MAD of the usable reaction times, in seconds. |
| `movementTime*` | the same statistics except p90, in seconds. There is no `movementTimeP90` column. |
| the nine counts | `numRounds`, `numPracticeRounds`, `numValidRounds`, `numAnticipations`, `numLapses`, `numFalseStarts`, `numSlips`, `numMissed`, `numMalformed`. Validated to fit `Int32`, and the seven outcome counts are validated to sum to `numRounds` before anything is inserted. |
| `metricsVersion` | `AkinesiaMetrics.metricsVersion`. See "Metrics versioning" above. |
| `isValid`, `invalidReason` | Per statistics bundle. See below. |

**The two statistics bundles are independent.** Reaction time and movement time are written from
separate `SummaryStats`, and either can be unavailable on its own: a round where the patient
lifted but never reached the firefly has a reaction time and no movement time. A bundle holding
any non-finite value is treated as unavailable, its columns take the placeholder zero, and
`invalidReason` says which bundle was missing (`"reaction time statistics unavailable"`,
`"movement time statistics unavailable"`, or both, joined by `;`).

The same rule as tapping applies: **a placeholder zero is not a measured zero when
`isValid == false`.** A reaction time of 0 s is not a possible reading, so the placeholder is
less dangerous here than a tapping CV of 0, but it is still a placeholder.

The counts are always written and never gated on `isValid`, because they are counted directly
from the rounds rather than derived from the statistics.

`AkinesiaResult` stores no capture duration, unlike `BradykinesiaResult.durationSec`. The
session's wall-clock bounds live on `TestSession`, and the monotonic session duration is
validated at save time rather than stored.


# Clinician view: snapshots and derived values

The read path turns Core Data rows into flat value types before anything draws them. These are
the names the derivations and the charts use. The rules that decide what becomes `nil` are in
`persistence/ReportSnapShotMapping.swift` and are described in ARCHITECTURE.md under "The two
snapshot rules".

## `ReportData`

What one `ReportQuery.load(window:in:)` returns.

| Field | Meaning |
| --- | --- |
| `window` | The `ReportWindow` the fetch used. |
| `sessions` | Sessions that started inside the window, oldest first. |
| `doses` | `MedicationLog` rows whose `dayStart` falls inside the window: the day the dose was due, or the day it was taken when it was unscheduled. |
| `questionnaires` | Every PDQ-8 answer ever recorded, oldest first. Not limited to the window. |
| `history` | Every session ever recorded. Not limited to the window; a baseline needs 19 days with data. |

## Snapshot types

Every one is a `nonisolated struct ... Sendable` with no reference to a managed object or a
context, so it survives the context being reset and can cross an actor boundary.

### `SessionSnapshot`

| Field | Meaning |
| --- | --- |
| `id`, `startedAt`, `dayStart` | From `TestSession`. `dayStart` is local midnight of the day the session began. |
| `minutesSinceDose` | `Double?`. Minutes from the last qualifying dose to the session start, `nil` when the session had no dose context. Zero is a real reading, meaning a session that started at the moment of a dose. |
| `tapping` | `[TappingSnapshot]`, one per hand, **sorted by timestamp** because the Core Data relationship is a set and hand order is not stored. |
| `firefly` | `FireflySnapshot?` |
| `tracing` | `TracingSnapshot?` |

A session holds whichever tasks the patient completed. One, two, or all three may be present, and
a session with no usable task is still a session for the day and session counts.

### `TappingSnapshot`

| Field | Unit | Gated on `isValid` |
| --- | --- | --- |
| `numTaps`, `numCorrectTaps` | count | no |
| `durationSec` | seconds | no |
| `tapInterMedian` | seconds | yes |
| `cvTapInter` | percent | yes |
| `tapInterSlope` | seconds per tap | yes |

The three ungated fields are what tap rate is computed from, and `BradykinesiaStore` validates
them separately from the statistics. Tap rate therefore survives a row whose `isValid` is false.

### `FireflySnapshot`

| Field | Unit | Gated on `isValid` |
| --- | --- | --- |
| `reactionTimeMedian`, `reactionTimeP90`, `movementTimeMedian` | seconds | yes |
| `numRounds`, `numValidRounds`, `numLapses`, `numMissed` | count | no |

Reaction time is stored in **seconds** and plotted in **milliseconds**;
`PrimaryMetric.reactionTime` does the conversion, and nothing else should.

### `TracingSnapshot`

| Field | Unit | Gated on `isValid` |
| --- | --- | --- |
| `rmsError` | canonical route units | yes |
| `swipeSpeedMedian` | canonical route units per second | yes |
| `fingerLifts`, `numSequences`, `doneSequences` | count | no |

### `DoseSnapshot`

| Field | Meaning |
| --- | --- |
| `dayStart` | Local midnight of the day the dose was **due**. |
| `takenAt` | When it was taken. For a skipped dose, the scheduled instant. |
| `scheduledAt` | `Date?`. `nil` for an unscheduled dose, read through `MedicationLog.scheduledDate` so the `0` sentinel never reaches a chart. |
| `wasSkipped` | The patient recorded that they did not take it. |
| `slotLabel`, `slotMinutesIntoDay` | The schedule slot, as a name and as minutes into the day. The minutes identify the slot for colouring, so a patient renaming a dose does not split its series. |
| `delayMinutes` | Computed. `nil` for an unscheduled dose and for a skipped one, because neither has something to be late by. |

### `PDQ8Snapshot`

`id`, `completedAt`, `rawSum` (0 to 32), `scoreIndex` (0 to 100, higher is worse). A row with a
non-finite `scoreIndex` is dropped rather than plotted.

## Derived values

| Type | One per | Carries |
| --- | --- | --- |
| `DoseBin` | bin, always ten, in x-axis order | its points, `SummaryStats?`, `median`, `hasWhisker` |
| `DailyAggregate` | day in the window | daily median per hand, session count, taken-dose count |
| `Baseline` | request | `center` (median of daily medians), `lower` (p25), `upper` (p75), `spread` (sample SD), `dayCount`, `establishedOn` |
| `AdherencePoint` | scheduled dose | `delayMinutes?`, `wasSkipped`, slot identity |
| `TapComponentPoint` | day per component | `rawValue?` in the component's own unit, `z?` |
| `TapAccuracyPoint` | day | `accuracy?`, 0 to 1 |
| `DataQuality` | window | day and session counts, `excludedSessions`, `metricsVersionsInWindow` |
| `ExcludedSession` | invalid **result**, not per session | date, task name, hand, reason |

Three conventions that run through all of them:

**A bin, a day, or a slot keeps its place when it has no data.** `DoseBinning.bins` returns all
ten bins every time and `DailyAggregation.aggregate` returns one row per day in the window, with
`nil` values. "No data" has to be visible as itself.

**`SummaryStats.compute` returns `nil` below two values, so a one-session bin has a median and no
whisker.** `DoseBin.median` comes from `DailyAggregation.median`, which is defined for one value;
`DoseBin.stats` is the percentile bundle and is absent for a single point. `hasWhisker` is the
flag the chart reads.

**Positive z always means further from baseline in the worsening direction.** `TapComponent`
carries `higherIsWorse` — false for speed, true for rhythm and decrement — and
`TapComponents.zScore` applies the sign. Without it, speed and rhythm would point opposite ways
on one axis. Accuracy is deliberately not a z-score: it is a compliance measure in its own units.

### Dose bins

| Bin | Contains |
| --- | --- |
| `beforeFirstDose` | sessions with no dose context, where `minutesSinceDose` is `nil` |
| `sinceDose(startMinutes:)` | eight 30-minute bins covering 0:00 to 4:00 since the last dose |
| `fourHoursOrMore` | 240 minutes or more |

A negative or non-finite `minutesSinceDose` is placed in no bin at all. The store only records a
dose at or before the session start, so a negative value means the row is wrong, and forcing it
into the first bin would pass that error on to the chart.

### Baseline states

| State | Meaning |
| --- | --- |
| `familiarization(dayNumber:of:)` | fewer than 5 days with data. Tapping frequency rises over the first days and plateaus, so these days are excluded. |
| `building(dayNumber:of:)` | past familiarization, fewer than 14 baseline days. |
| `established(Baseline)` | the 5 familiarization days are dropped and the next 14 days with data form the band. |

Days are counted as **days that produced a value**, not calendar days, so a patient who skips
days takes longer to reach a baseline. The baseline does not grow once established: it stays the
first 14 qualifying days, so the band stays where the patient started while the line moves.

A baseline is computed per variable, not per metric. `Baseline` carries the hand but no metric,
because the tapping components need baselines on `cvTapInter` and `tapInterSlope` and neither is
a `PrimaryMetric` case. The caller asked for one variable's daily values and knows which.

### `PrimaryMetric`

| Case | Value | Unit | Higher is better |
| --- | --- | --- | --- |
| `tapRate` | `numTaps / durationSec` for that hand | taps/sec | yes |
| `reactionTime` | `reactionTimeMedian × 1000` | ms | no |
| `tracingError` | `rmsError` | canonical route units | no |

`higherIsBetter` exists so the baseline band and the trend chart can orient "improvement" without
any chart hardcoding a direction. It is a presentation property and never produces a judgement
label.

Each case reads one task and one hand. A session with no tapping row for the requested hand
returns `nil` for `tapRate` rather than falling back to the other hand, and `reactionTime` and
`tracingError` return `nil` unless that task's row was recorded for the requested hand.
