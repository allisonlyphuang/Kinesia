# Data dictionary

What each stored or computed value means, and how to read it without misinterpreting it.

- **Bradykinesia (tapping)** is saved to Core Data.
- **Akinesia (fireflies)** is computed but not yet saved.

## Bradykinesia: tapping

This describes the local-first tapping pipeline. It documents what the code does, not a
diagnosis or a severity score.

### Three unrelated meanings of "left" and "right"

These appear side by side throughout the codebase and are **independent**. Changing one must
not change the others.

| Name | Domain | Meaning | Set by |
| --- | --- | --- | --- |
| `leftCenter`, `rightCenter` | screen position | where the two target circles are drawn | `BradykinesiaTestScreen.targetGeometry(in:)` |
| `CurrentHand.left`, `.right` | body laterality | which hand is being tested | `BradykinesiaTestConfiguration.handOrder` |
| `leftDrift`, `rightDrift` | statistics | the mean-X partition of tap coordinates | `BradykinesiaAnalyzer.paperSpatialPartition` |

A left-hand trial still has a right-side circle on screen, and its taps still split into
left/right *statistical* partitions by mean x. The three axes never interact.

### Raw trial data

#### `TapSample`

| Field | Type | Meaning |
| --- | --- | --- |
| `t` | `TimeInterval` | Raw `UITouch.timestamp` at touch-down. It is monotonic/touch-relative timing, **not** a Unix or wall-clock timestamp. |
| `x` | `Double` | Tap x-coordinate in the local capture-view coordinate space. |
| `y` | `Double` | Tap y-coordinate in the local capture-view coordinate space. |
| `target` | `TapTarget` | UI hit classification: `.left`, `.right`, or `.miss`. |

`target` is the **stored result of a geometry test already performed** at capture time by
`RawTouchView.classify`: `.left` means the tap's distance from the left circle's center was
within `targetRadius`, `.right` likewise, `.miss` means outside both. It therefore already
encodes "landed within the target radius"; no separate radius check exists downstream.

`target` is used by `numCorrectTaps` and by nothing else. It does not determine the
paper-derived spatial partitions described below.

#### `TapTrial`

One trial per hand. A bilateral test produces two.

| Field | Meaning |
| --- | --- |
| `samples` | Every captured `TapSample`, in arrival order, including misses. |
| `leftCenter`, `rightCenter` | Displayed target centers in the same local coordinate space as `x` and `y`. |
| `targetRadius` | Displayed/UI-classification target radius. |
| `startedAt` | Monotonic start time for this hand's capture; not wall-clock time. |
| `hand` | `CurrentHand` — which hand this trial recorded. |
| `screenScale` | Active display scale used while the trial was configured. |

`CurrentHand` is a `String`-raw-value enum, so it encodes to JSON as `"left"` / `"right"`.

#### `HandAttempt`

The model's in-memory record of one completed hand, handed to the store. Carries the `hand`,
its `TapTrial`, its `BradykinesiaMetrics`, wall-clock `startedAt` / `completedAt`, and
`monotonicCompletedAt` (used with `trial.startedAt` to derive the measured capture duration).

### Temporal metrics

For supplied sample order, the analyzer derives:

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
| `BradykinesiaResult.accelMeanG`, `accelMaxG`, `deviceMoved` | Reserved for MotionQC. Never written; schema defaults only. |

Both hands of one test share a single `TestSession`, so a bilateral test has exactly one
medication context, one `dayStart`, and one pair of session bounds.

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

Nothing is saved to Core Data yet, so this section describes the values the code produces in
memory. These are the names a future `AkinesiaStore` will map onto database columns.

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

Two fields were added in this change, used by both tests:

| Field | Meaning |
| --- | --- |
| `p90` | the 90th percentile — the slow tail, where trouble starting a movement shows up before the middle of the distribution moves |
| `mad` | median absolute deviation — how spread out the values are, measured so that one extreme value cannot distort it |

Reaction times are lopsided: there are a few very slow ones and none very fast. Median and MAD
describe that shape better than mean and standard deviation.
