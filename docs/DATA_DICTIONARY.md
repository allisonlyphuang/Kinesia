# Bradykinesia data dictionary

This document describes the current local-first Bradykinesia tapping data pipeline. It
documents implementation semantics, not a clinical diagnosis or a severity score.

## Three unrelated meanings of "left" and "right"

These appear side by side throughout the codebase and are **independent**. Changing one must
not change the others.

| Name | Domain | Meaning | Set by |
| --- | --- | --- | --- |
| `leftCenter`, `rightCenter` | screen position | where the two target circles are drawn | `BradykinesiaTestScreen.targetGeometry(in:)` |
| `CurrentHand.left`, `.right` | body laterality | which hand is being tested | `BradykinesiaTestConfiguration.handOrder` |
| `leftDrift`, `rightDrift` | statistics | the mean-X partition of tap coordinates | `BradykinesiaAnalyzer.paperSpatialPartition` |

A left-hand trial still has a right-side circle on screen, and its taps still split into
left/right *statistical* partitions by mean x. The three axes never interact.

## Raw trial data

### `TapSample`

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

### `TapTrial`

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

### `HandAttempt`

The model's in-memory record of one completed hand, handed to the store. Carries the `hand`,
its `TapTrial`, its `BradykinesiaMetrics`, wall-clock `startedAt` / `completedAt`, and
`monotonicCompletedAt` (used with `trial.startedAt` to derive the measured capture duration).

## Temporal metrics

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

## Paper-derived spatial metrics

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

## Correct taps

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

## Availability semantics

The calculation layer represents unavailable derived values as `nil`, never as NaN, infinity, or a fabricated zero. Examples include insufficient samples, non-finite input, non-increasing timestamps, zero-variance skewness, and undefined Pearson correlation.

`BradykinesiaResult` has required numeric Core Data fields. If an unavailable mapped metric prevents a complete result, persistence sets `isValid = false`, provides `invalidReason`, and stores the required numeric placeholder. **A placeholder zero is not a measured zero when `isValid == false`.**

This matters most for the CV columns: `cvTapInter = 0` is a plausible reading meaning *perfectly
regular tapping*, the healthiest possible result. Always consult `isValid` before interpreting a
CV value.

## Persisted objects

Each completed test creates **one** `TestSession`, and **one** `BradykinesiaResult` plus **one**
`RawCapture` per hand. A bilateral test therefore writes five rows in a single transaction.

| Object | Key fields/semantics |
| --- | --- |
| `TestSession` | Explicit wall-clock `startedAt` (earliest hand's start), `completedAt` (latest hand's completion), and `dayStart`. Supplied as `Date` values, separate from raw touch timing. |
| `BradykinesiaResult` | Per hand. Schema-backed counts, temporal summaries, drift summaries, CVs, correlation, measured duration, validity, and session relationship. |
| `RawCapture` | `kind = "bradykinesia"`, `schemaVersion = 1`, and JSON-encoded `TapTrial` in `payload`. One per hand; the hand is inside the payload. |

`payload` holds the actual captured data; `kind`, `schemaVersion`, `timestamp`, and `session`
are labels that let you find and interpret it without decoding it.

### Field notes

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
