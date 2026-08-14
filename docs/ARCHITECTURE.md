# Bradykinesia architecture

## Implemented vertical slice

```text
HomeView
  → BradykinesiaTestView
  → BradykinesiaTestModel (ready → countdown → running → finished/failed)
  → TapCaptureView / RawTouchView
  → TapSample / TapTrial
  → BradykinesiaAnalyzer
  → BradykinesiaMetrics
  → BradykinesiaStore
  → TestSession + BradykinesiaResult + RawCapture
```

`RawTouchView` enables multitouch and emits every `touchesBegan` touch as a `TapSample`. It assigns UI `.left`, `.right`, or `.miss` classification from the displayed target geometry only. `BradykinesiaTestModel` accepts samples only while running, preserves order and misses, prevents overlapping starts and duplicate completion, and invokes the analyzer and store exactly once.

The production lifecycle uses a configurable 3-second countdown and a 20-second capture duration. Raw touch time and `TapTrial.startedAt` are monotonic. Wall-clock `Date` values are captured separately for session/result persistence; touch timestamps are never interpreted as Unix time.

## Persistence

`BradykinesiaStore.save(trial:metrics:startedAt:completedAt:in:)` receives an already-analyzed trial. It does not recompute metrics. It JSON-encodes the complete `TapTrial` into `RawCapture.payload` and creates one `TestSession` and `BradykinesiaResult` with their schema relationships. Result fetching is newest-first by explicit wall-clock timestamp.

The store preserves raw misses and sample order. It does not associate a medication log, calculate `numCorrectTaps`, fabricate MotionQC data, or write calculated CV values into unrelated schema fields.

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

## Deferred decisions

- `numCorrectTaps`: target hit, correct alternation, or another definition is not finalized.
- Medication context: the Core Data relationship exists; lookup/association behavior is deferred.
- MotionQC: schema fields exist; collection and interpretation are deferred.
- Scoring: there is no normalization, composite score, or severity score.
- CV persistence: CV is calculated in memory but lacks explicit Core Data attributes.
