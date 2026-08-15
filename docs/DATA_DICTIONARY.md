# Bradykinesia data dictionary

This document describes the current local-first Bradykinesia tapping data pipeline. It
documents implementation semantics, not a clinical diagnosis or a severity score.

## Raw trial data

### `TapSample`

| Field | Type | Meaning |
| --- | --- | --- |
| `t` | `TimeInterval` | Raw `UITouch.timestamp` at touch-down. It is monotonic/touch-relative timing, **not** a Unix or wall-clock timestamp. |
| `x` | `Double` | Tap x-coordinate in the local capture-view coordinate space. |
| `y` | `Double` | Tap y-coordinate in the local capture-view coordinate space. |
| `target` | `TapTarget` | UI hit classification: `.left`, `.right`, or `.miss`, based on the displayed target circles. |

`target` is preserved for target-hit/miss metadata. It does not determine the paper-derived spatial partitions described below.

### `TapTrial`

| Field | Meaning |
| --- | --- |
| `samples` | Every captured `TapSample`, in arrival order, including misses. |
| `leftCenter`, `rightCenter` | Displayed target centers in the same local coordinate space as `x` and `y`. |
| `targetRadius` | Displayed/UI-classification target radius. |
| `startedAt` | Monotonic start time for the raw trial; not wall-clock time. |
| `hand` | Tested-hand metadata; the current playable screen uses the existing `right` default because hand selection is not yet implemented. |
| `screenScale` | Active display scale used while the trial was configured. |

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

## Availability semantics

The calculation layer represents unavailable derived values as `nil`, never as NaN, infinity, or a fabricated zero. Examples include insufficient samples, non-finite input, non-increasing timestamps, zero-variance skewness, and undefined Pearson correlation.

`BradykinesiaResult` currently has required numeric Core Data fields. If an unavailable mapped metric prevents a complete result, persistence sets `isValid = false`, provides `invalidReason`, and stores the required numeric placeholder. A placeholder zero is **not** a measured zero when `isValid == false`.

## Persisted objects

Each completed attempt creates one `TestSession`, one `BradykinesiaResult`, and one `RawCapture`.

| Object | Key fields/semantics |
| --- | --- |
| `TestSession` | Explicit wall-clock `startedAt`, `completedAt`, and `dayStart`. These are supplied as `Date` values and are separate from raw touch timing. |
| `BradykinesiaResult` | Schema-backed count, temporal summaries, drift summaries, correlation, validity, and session relationship. `numCorrectTaps` is not calculated yet. |
| `RawCapture` | `kind = "bradykinesia"`, `schemaVersion = 1`, and JSON-encoded `TapTrial` in `payload`. |

The analyzer calculates `cvTapInter`, `cvDriftLeft`, and `cvDriftRight`, but the current Core Data schema has no explicit CV attributes. CV values are therefore not persisted into unrelated fields.
