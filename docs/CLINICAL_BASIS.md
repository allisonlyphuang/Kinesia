# Bradykinesia tapping calculation basis

Kinesia currently implements a 20-second alternating two-target tapping assessment for structured motor tracking. The implementation records timestamps and positions, then derives a transparent metric bundle. It does not diagnose Parkinson's disease, assign disease severity, or claim that the app itself has been clinically validated.

## Raw measurement

Each touch-down records its monotonic `UITouch.timestamp`, local x/y position, and a UI target classification (`.left`, `.right`, or `.miss`). The UI classification answers whether a point falls within the displayed target circles; it is retained as separate target-hit/miss metadata.

## Paper-derived temporal features

For the captured tap order:

```text
TapInter[t] = T[t] - T[t-1]
```

The implementation calculates descriptive statistics for valid interval sequences, population-SD coefficient of variation, and population-moment skewness:

```text
CV = populationSD / mean * 100
skewness = mean((x - mean)^3) / populationSD^3
```

Descriptive `stdev` remains sample standard deviation (`N - 1`); the separate paper CV/skew helpers use population standard deviation (`N`).

## Paper-derived spatial features

The published-style spatial pathway deliberately uses coordinates rather than UI labels:

```text
meanX  = mean(all x coordinates)
Pleft  = x < meanX
Pright = x >= meanX
```

Within each partition, `DriftLeft` and `DriftRight` are consecutive Euclidean distances while retaining original capture order. `corXY` is Pearson correlation across all raw x/y pairs.

Allison confirmed this separation: mean-X grouping is retained for paper comparability, while `.left`/`.right`/`.miss` remains UI target-hit metadata. Changing a target label alone must not alter mean-X grouping, drift metrics, or `corXY`.

## Current boundaries

The result is a raw/derived metric bundle. Kinesia currently does not calculate a normalized/composite Bradykinesia score, severity label, or diagnosis. `numCorrectTaps`, medication-context association, and MotionQC are deferred pending product/clinical decisions.
