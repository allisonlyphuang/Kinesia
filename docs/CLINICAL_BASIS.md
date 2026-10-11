# Clinical basis

## Bradykinesia: tapping

Kinesia implements a two-handed 20-second alternating tapping assessment. Each hand is recorded
separately and both go into one session. The code records times and positions and derives a
transparent set of numbers from them. It does not diagnose Parkinson's, assign a severity, or
claim the app itself has been clinically validated.

### Protocol

Per hand: a 3-second countdown, then a 20-second capture. The participant is instructed to alternate between two on-screen targets as quickly and accurately as possible, **starting on the right target**. The right hand is tested first by default, followed by an untimed rest during which the participant switches hands and continues when ready.

The rest is deliberately not timed. Switching hands takes an unpredictable amount of time, and starting capture while the participant is still repositioning would contaminate the second trial.

### Raw measurement

Each touch-down records its monotonic `UITouch.timestamp`, local x/y position, and a UI target classification (`.left`, `.right`, or `.miss`). The UI classification is the stored outcome of a distance-to-center test against the displayed circles at the moment of the tap.

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

Descriptive `stdev` remains sample standard deviation (`N - 1`); the separate paper CV/skew helpers use population standard deviation (`N`).

### Paper-derived spatial features

The published-style spatial pathway deliberately uses coordinates rather than UI labels:

```text
meanX  = mean(all x coordinates)
Pleft  = x < meanX
Pright = x >= meanX
```

Within each partition, `DriftLeft` and `DriftRight` are consecutive Euclidean distances while retaining original capture order. `corXY` is Pearson correlation across all raw x/y pairs.

Allison confirmed this separation: mean-X grouping is retained for paper comparability, while `.left`/`.right`/`.miss` remains UI target-hit metadata. Changing a target label alone must not alter mean-X grouping, drift metrics, or `corXY`.

### Target accuracy

`numCorrectTaps` is the one metric derived from the UI target classification. A tap is correct when it lands inside the target the protocol expects next, where the expected sequence opens on the right and alternates. Misses and hits on the wrong target are not counted and do not advance the expectation, so tapping left and then missing does not mean the next target is left, the next target is still right.

Because the rule fixes the opening side, the on-screen instruction states it explicitly. Without that instruction the metric would partly measure compliance with an unstated rule rather than motor performance.

### Medication context

Each session is associated with the most recent medication dose actually taken on the same local day and at or before the session began. Skipped doses are excluded, since the association exists to express time since an actual dose. When no qualifying dose exists the association is left unset, and `minutesSinceDose` must not be interpreted.

Both hands of a bilateral test share one session and therefore one medication context.

### Current boundaries

The result is a raw/derived metric bundle. Kinesia currently does not calculate a normalized/composite Bradykinesia score, severity label, or diagnosis.

Left/right asymmetry is deliberately **not** computed. Storing both hands in one session makes asymmetry a direct query over that session whenever a definition is agreed, but choosing that definition is a clinical decision that has not been made. MotionQC collection and interpretation remain deferred.

## Akinesia: fireflies
Parkinson's slowness is usually split into three related ideas:
- **Akinesia** affects movement initiation. It is usually delayed, or in severe cases does not begin. It does not measure slowness of movement (bradykinesia)
- Reacion time moves with dopamine levels, which is the property that makes it useful for figuring out Levodopa dosing (which mimics endogenous dopamine). 
- The relationship between reaction time and PD is not purely dopaminergic, so it is still only one sign out of many.
- The delay is modest on simple tasks and larger on harder tasks, which is usualy interpreted as evidence that the dopamine deficit involves processing the signal before the movement rather than movement preparation alone, but this is still debated.

### The protocol
Per session, a finger rests on a jar at the center of the screen. After a random wait of 1 to 4 seconds, a firefly appears at any point at a fixed distance from the jar. The patient taps the firefly as quick as possible, returning their finger to the jar after doing so. 12 rounds are scored.
- A fixed number of rounds are played instead of a fixed duration of hte total test. With a fixed duration, a patient with severe symptoms completes less rounds and will have less data.
- Practice rounds are not included in scoring.

### Which finger, and why not the thumb

The test uses the** **index finger with the phone resting on a table, and the hand and finger are recorded. 
- The thumb of the hand holding the phone can only comfortably cover a curved region whose size depends on hand size and grip, so a ring of targets
 would put many fireflies outside a thumb's range. Movement time would then vary with hand size, phone model, and how easy the firefly is to reach from the thumb position.Every lab study this test is modeled on used a supported limb moving from a fixed home position.

### Current boundaries
The result is a set of counts and summary numbers. There is no normalised score, no severity label, and no diagnosis. Movement time is stored beside the reaction times and never averaged into them. This is an adaptation of a standard experimental paradigm, not a validated clinical instrument. Any index built from it describes a patient against their own baseline, not against a population. The app supports a clinical conversation; it does not recommend dose changes.
