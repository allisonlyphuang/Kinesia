# Clinical basis

## Bradykinesia: tapping

The tapping task is a two-handed 20-second alternating tapping assessment. Each hand is recorded separately and both are recorded into one session. Kinesia records times and positions and derives a raw set of numbers from them, from which other values such as coefficient of variations can be derived. 

### Protocol
For each hand, after 3-second countdown follows a 20-second capture round. The participant is instructed to alternate between two on-screen targets as quickly and accurately as possible, starting on the right target. The right hand is tested first by default, followed by an untimed rest during which the participant switches hands and continues when ready. 

### Raw measurement
Each tap records a monotonic `UITouch.timestamp`, local x/y position, and a UI target classification (`.left`, `.right`, or `.miss`). The UI classification is the stored outcome of a distance-to-center measurement against the displayed circles at the moment of the tap.

### Paper-derived temporal features
For the captured tap order:
```text
TapInter[t] = T[t] - T[t-1]
```

The implementation calculates descriptive statistics for valid interval sequences, population-SD coefficient of variation, and population-moment skewness:
```text
CV = populationSD / mean * 100
skewness = mean((x - mean)^3) / populationSD^3
```

`stdev` is calculated as sample standard deviation (`N - 1`); the CV/skew helpers use population standard deviation (`N`).

### Paper-derived spatial features
Spatial pathway uses coordinates; Within each partition, `DriftLeft` and `DriftRight` are consecutive Euclidean distances while retaining original capture order. `corXY` is Pearson correlation across all x/y pairs.
```text
meanX  = mean(all x coordinates)
Pleft  = x < meanX
Pright = x >= meanX
```

### Target accuracy
`numCorrectTaps` is the only metric derived from UI label classification. A tap is correct when it lands inside the target the protocol expects next, where the expected sequence starts on the right. Misses and hits on the wrong target are not counted and do not advance the expectation, so tapping left and then missing does not mean the next target is left, the next target is still right.
Because the rule fixes the opening side, the on-screen instruction states it explicitly. Without that instruction the metric would partly measure compliance with an unstated rule rather than motor performance.

### Medication context
Each session is associated with the most recent medication dose actually taken on the same local day and at or before the session began. Skipped doses are excluded, since the association exists to express time since an actual dose. When no qualifying dose exists the association is left unset, and `minutesSinceDose` must not be interpreted.
Both hands of a bilateral test share one session and therefore one medication context.

# Dexterity tracing measurement basis

Dexterity V1 is a Kinesia product protocol informed by touchscreen dexterity literature, including slide/swipe pattern work that records movement time, accuracy, and Euclidean distance. The exact Kinesia constellation geometry and repetition plan are not represented as a diagnostic or independently validated clinical test.

The interaction uses the right index finger on a right-hand-only MVP route. A participant completes one unscored practice trace and three completed scored traces of the same visible ordered route without lifting contact. A lift or system cancellation ends the current attempt and permits the same round to be retried; it is retained as raw data but excluded from the primary metric aggregate.

The implementation records continuous local points with monotonic timestamps, maps them to a versioned canonical route coordinate system, and derives assigned-segment RMSE, maximum per-sequence RMSE, actual route-space trace distance, and descriptive swipe-speed statistics. These metrics are transparent movement measurements intended for future longitudinal use; no severity, composite, diagnostic, or clinical threshold is assigned.

## Current boundaries

The result is a raw/derived metric bundle. Kinesia does not calculate a normalized/composite score, severity label, or diagnosis, and will not: as of 2026-10-17 that is a settled product boundary rather than something deferred. See docs/ADR.md.

Left/right asymmetry is deliberately **not** computed. Storing both hands in one session makes asymmetry a direct query over that session whenever a definition is agreed, but choosing that definition is a clinical decision that has not been made. MotionQC collection and interpretation remain deferred.

## Akinesia: fireflies
Parkinson's slowness is usually split into three related ideas:
- Akinesia affects movement initiation. It is usually delayed, or in severe cases does not initiate. It does not measure slowness of movement (bradykinesia).
- Reaction time correlates with dopamine levels, which makes it useful for decisions on Levodopa dosing. However, the relationship between reaction time and PD is not purely dopaminergic.
- The delay increases on harder tasks, which is usually interpreted as the dopamine deficit involving processing the signal before the movement rather than movement preparation alone, but this is still debated.

### Protocol
Per session, a finger rests on a jar at the center of the screen. After a random wait of 1 to 4 seconds, a firefly appears at any point at a fixed distance from the jar. The patient taps the firefly as quick as possible, returning their finger to the jar after doing so. 12 rounds are scored.
- A fixed number of rounds are played instead of a fixed duration of the total test. With a fixed duration, a patient with severe symptoms completes less rounds and will have less data.
- Practice rounds are not included in scoring.

### Akinesia finger
The test uses the index finger with the phone resting on a table, and the hand and finger are recorded. 
- The thumb of the hand holding the phone can only comfortably cover a curved region whose size depends on hand size and grip, so a ring of targets
 would put many fireflies outside a thumb's range. Movement time would then vary with hand size, phone model, and how easy the firefly is to reach from the thumb position.Every lab study this test is modeled on used a supported limb moving from a fixed home position.



# Clinician view: what the report measures

The report answers four questions and nothing else. A chart that does not serve one of them does
not belong in it.

1. Does movement get worse before the next dose?
2. After a dose, how quickly does movement improve, and for how long?
3. Are doses being taken on time?
4. Is the overall pattern improving across weeks?

## Why the report exists

From the literature review behind this project: patient and observer agreement on motor state was
**59.8%**, and patients described themselves as normal during **10.1%** of OFF periods.
Anosognosia is common and worsens with progression. Median medication adherence was **97.7%**
while median *timing* adherence was **24.4%**.

So the weak link is self-report, not measurement. The report puts a time-stamped, dose-linked
record next to the patient's own account. It does not replace the account.

## What each chart measures

| Chart | Quantity | Unit |
| --- | --- | --- |
| Through the day | the selected measure against time of day, with dose markers | the measure's own unit |
| By time since dose | the selected measure grouped by minutes since the last dose | the measure's own unit |
| Dose timing | taken time minus scheduled time, per dose | minutes, signed |
| Per day | daily median of the selected measure, against the baseline band | the measure's own unit |
| Quality of life | PDQ-8 score index | 0 to 100, higher is worse |
| Tapping components | speed, rhythm, and decrement as distance from each one's own baseline | standard deviations, plus accuracy as a percentage |

The three measures the first four charts can plot are tap rate (taps per second), reaction time
(milliseconds), and distance from the route (canonical route units). Each is a direct
measurement with a unit, not an index.

## The baseline

Two findings from the review set the two spans:

- Tapping frequency rises over roughly the first three days and plateaus after five, so the
  **first five days with data are excluded** as familiarization.
- Roche PD Mobile showed good to excellent test-retest reliability between two two-week periods,
  so a baseline needs **14 days**.

The band is the 25th to 75th percentile of the daily medians across those 14 days: half the
patient's baseline days fell inside it, which is a sentence a clinician can check. The
alternative, median plus or minus one MAD, produces a visibly different band and is harder to
state plainly.

Days are counted as days that produced a value. The band stays on the first 14 qualifying days
rather than growing, so the band marks where the patient started and the line moves against it.

Every band and every z-score compares the patient against their own earlier sessions. There is no
population comparison anywhere in the report.

## Time since dose

Sessions are grouped by minutes since the last dose taken that day: a group for sessions with no
dose context yet, eight 30-minute groups covering the first four hours, and one group for four
hours or more. A rise from the no-dose group into the 30 to 90 minute groups is what a dose
response looks like in this chart. The groups are descriptive statistics over whatever sessions
exist, not a fitted response curve.

A group holding one session shows its median with no range, because a range over one value would
imply a spread that was never measured.

## What the report does not do

Consistent with the boundaries above, and permanently rather than pending:

- No severity score, composite score, or normalized index.
- No diagnosis, classification, or OFF/ON state inference.
- No dose recommendation.
- No left/right asymmetry index. Both hands sit in one session, so asymmetry is a query away, but
  the definition is a clinical decision that has not been made.
- No claim that the app is clinically validated.

The report supports a clinical conversation. It does not have one.
