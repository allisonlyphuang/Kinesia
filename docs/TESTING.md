# Testing

## Automated coverage

The `KinesiaTests` XCTest target has **642 tests**, all passing as of 2026-10-23. The count is taken from the source, as described under "Counting the tests" below, and the run reported `** TEST SUCCEEDED **` with no failures.

| Suite | Tests | Covers |
| --- | --- | --- |
| `SummaryStatsTests` | 19 | percentile interpolation, sample SD, population SD, paper CV, population-moment skewness, 90th percentile, median absolute deviation, non-finite input |
| `BradykinesiaAnalyzerTests` | 27 | TapInter extraction, malformed/non-increasing timestamps, insufficient samples, mean-X partitions, Euclidean drift, Pearson correlation, UI-label independence, correct-tap scoring |
| `BradykinesiaStoreTests` | 16 | Core Data mapping, bilateral session shape, validation guards, raw payload round trips, CV and correct-tap persistence, measured duration, medication context, fetch ordering, context refetch |
| `BradykinesiaTestModelTests` | 11 | phase transitions, tap gating/order/miss preservation, bilateral sequencing and rest, duplicate-save protection, persistence failure, geometry locking, reset |
| `AkinesiaTestModelTests` | 31 | the full round cycle; false start, slip, missed, drag-instead-of-lift and interruption paths; practice gating; geometry locking; session cap; save failure; reset; ring-spawn geometry |
| `FireflyBoardTests` | 25 | hit-test geometry including exact boundaries and non-finite input; showing the firefly in one frame under repeated SwiftUI redraws; replacing stale callbacks; a real `CADisplayLink` reporting an onset on the right clock |
| `AkinesiaAnalyzerTests` | 18 | reaction and movement time arithmetic; both threshold boundaries; outcome counts adding up; practice exclusion; the statistics cut-off; movement time kept out of reaction-time stats |
| `AkinesiaStoreTests` | 24 | created-object shape, every statistic and count column, raw payload round trip, each validation rejection leaving the context empty, medication-context rules, validity marking, durability across a context reset, fetch helpers |
| `AkinesiaBoardLayoutTests` | 11 | board sizing across device sizes, the clearance rule that keeps a firefly from overlapping the jar, touch-target minimums, degenerate sizes, and every ring spawn landing on the board |
| `AkinesiaCopyTests` | 7 | no empty strings, no clinical or internal vocabulary, no blame in failure messages, practice and scored progress never identical |
| `TapModelTests` | 1 | `TapTrial` Codable round trip |
| `TapCaptureViewTests` | 1 | UI target classification including the radius boundary |
| Dexterity calculation, capture, route, layout, fit, protocol, store, and session suites | 57 | canonical geometry, continuous capture, ordered progression, protocol lifecycle, Core Data persistence, raw payloads, and retry/save-once behavior |
| `TapInterSlopeTests` | 13 | OLS decrement arithmetic, a known hand-checked fit, speeding up, a symmetric spike leaving the trend flat, per-tap rather than per-second scaling, the three-interval minimum, non-finite input, and the slope reaching the metric bundle |
| `MedicationSchedulePlanTests` | 18 | time-of-day and dosage validation including boundaries, duplicate slots, ordering, occurrence resolution, a late-night dose resolving to the previous day, and a clock time skipped by daylight saving |
| `MedicationStoreTests` | 26 | schedule replacement deactivating rather than deleting, new rows taking fresh ids so re-saving a loaded schedule does not collide with the uniqueness constraint on `id`, an old log keeping its slot, taken/skipped/unscheduled logging, adherence delay sign, scheduled-day filing, duplicate rejection, undo, medication-context rules, fetch ordering, and durability across a context reset |
| `MedicationDayModelTests` | 13 | row construction per scheduled dose, taken/skipped/pending as three distinct states, undo and re-record, duplicate writes surfacing without changing the row, next-dose selection, unscheduled doses, day switching, and non-blaming failure copy |
| `PDQ8Tests` | 18 | instrument shape, one item per dimension, scoring arithmetic at both ends and the midpoint, item order preservation, refusal to score a partial questionnaire, and stored-value range validation |
| `PDQ8StoreTests` | 10 | created-row shape, per-item payload round trip, durability across a context reset, incomplete and non-finite input leaving the context empty, missing payload reporting, and fetch ordering in both directions |
| `PDQ8ModelTests` | 11 | progress and navigation, selecting without auto-advancing, changing an answer, completion gating, saving, discarding a partial questionnaire, and reset |
| `HomeSummaryTests` | 12 | the streak counting back from today and from yesterday, breaking on a missed day, zero with no history, the day number from the first recorded session, all three tests needed before a day counts as checked in, yesterday's tests not counting as today's, and the next dose later today or rolling to tomorrow |
| `ReportWindowTests` | 28 | day count and ordering, start and end boundaries, adjacent windows not overlapping, zero and negative days rejected, days with no sessions still listed, spring-forward and fall-back windows keeping their day count, and each scale's own spans and default |
| `ReportFormatTests` | 18 | axis number formatting including the printf half-to-even case, signed values, h:mm, singular and plural counts, the label stride at every window length with a proof that no window exceeds the label budget, picker titles short enough for the one-line Measure control, and task names carrying no symptom word |
| `ClinicianReportModelTests` | 16 | loading with and without data, every derivation built, the window default and change, metric and hand switching rebuilding, a baseline established from the history a 7 day window could not hold, timeline points scoped to one day, dose markers and their skipped state |
| `ReportExportTests` | 14 | a readable four page PDF, refusal before anything is loaded, an empty window still exporting, US Letter geometry, equal side margins, the disclaimer and page number on every page, no symptom word in the text, the page rendering white inside its margin, and every one of the six charts reaching the export |
| `ReportSnapshotTests` | 19 | placeholder zeros becoming nil on an invalid row for all three tasks, tap rate surviving one, non-finite stored values, minutesSinceDose from the relationship rather than the number, a dose at the exact moment of a session reading 0 not nil, session assembly, hand order recovered from timestamps, an unrecognised hand dropped, and snapshots outliving a context reset |
| `PrimaryMetricTests` | 17 | each metric's extraction and unit label, per-hand selection, the seconds to milliseconds conversion, higherIsBetter per case, zero duration, and nil propagation from an invalid row |
| `ReportQueryTests` | 15 | inclusive start and exclusive end, ordering, sessions with only some of the three tasks, dose context present and absent, dose and questionnaire fetches, the whole history loaded alongside the window, and loaded data driving the derivations after the context is reset |
| `DoseBinningTests` | 35 | the ten-bin layout and its order, every half-hour boundary, 0 and 30 and 239.99 and exactly 240 minutes, no dose context getting its own bin, negative and non-finite values left out, empty bins kept, one session giving a median but no whisker, the p25/p75 whisker, per-hand binning, a wearing-off pattern across the bins, and the short axis labels with only the hour boundaries marked |
| `DailyAggregateTests` | 20 | one row per day including days with no sessions, daily median for one/odd/even session counts, hands kept separate, every primary metric, tap rate surviving an invalid row, zero duration, dose counting, window edges, and the median helper |
| `BaselineTests` | 21 | the 5-day familiarization and 14-day baseline thresholds, every state transition at its boundary, the first five days excluded, the p25/p75 band and the stdev, an established baseline not moving as more data arrives, days counted as days with data, unsorted and non-finite input, and building daily values from sessions |
| `AdherencePointTests` | 18 | delay sign in both directions, a late-night dose reading as late, skipped doses carrying no delay, unscheduled doses left out, slot identity and label format, ordering, window edges, and the off-schedule count at its threshold |
| `TapComponentZScoreTests` | 30 | each component's value accessor, speed surviving an invalid row, the sign convention for all three components, z unavailable without a baseline or with zero spread, one point per day per component, per-component baselines, and accuracy kept off the z-axis |
| `DataQualityTests` | 22 | day and session counts, the fewer-than-5-days boundary, exclusions per result rather than per session, a missing reason stated, task names containing no symptom word, one and two metrics versions in a window, and baseline state pass-through |

Eight suites share `ReportFixtures`, which builds snapshots as plain values: `ReportWindowTests`, `PrimaryMetricTests`, `DoseBinningTests`, `DailyAggregateTests`, `BaselineTests`, `AdherencePointTests`, `TapComponentZScoreTests`, and `DataQualityTests`. None of them opens a Core Data store, because none of the types they test has ever seen one.

The four suites that do open one — `ReportSnapshotTests`, `ReportQueryTests`, `ClinicianReportModelTests`, and `ReportExportTests` — use the same in-memory `TestCoreDataStack` as the store suites. `ReportSnapshotTests` and `ReportQueryTests` each assert that what they read back still reads correctly after `context.reset()`, which is the check that no snapshot is holding a managed object.

Tests use an isolated in-memory Core Data store and drive each test's lifecycle synchronously rather than sleeping, so a "20-second" tapping capture and a full 12-round firefly session both run in microseconds.

### Counting the tests

Do not count with `grep -c "Test case .* passed"` on the build log. `xcodebuild` wraps long lines, so a test with a long name can be split across two lines and missed, giving a number one or two short. Count the declarations in the source instead:

```bash
cat KinesiaTests/*.swift | grep -cE '^\s*func test[A-Za-z0-9_]+\s*\('
```

Then confirm the run reported zero failures and `** TEST SUCCEEDED **`.

### Test doubles

`BradykinesiaTestModel.init` takes `monotonicNow`, `wallClockNow`, and `persistenceAction` so tests can substitute a controlled clock or a failing save.

The fake clocks must **advance** on every read. A constant clock produces a zero-length capture window, which `BradykinesiaStore` correctly rejects with `invalidCaptureDuration`. See `advancingClock(from:step:)` in `BradykinesiaTestModelTests`.

`AkinesiaTestModel.init` additionally takes `foreperiodGenerator`, `spawnGenerator`, and `deviceIdentity`, and `automaticallyScheduleTimers: false` stops every timer from firing on its own. Tests then call `settleElapsed()`, `foreperiodElapsed()`, `slipWindowElapsed()`, `responseCeilingElapsed()`, `movementCeilingElapsed()`, and `sessionCapElapsed()` themselves. The same advancing-clock rule applies: a constant clock makes the session's own start and end identical.

`AkinesiaAnalyzer.analyze(_:thresholds:)` and `score(_:thresholds:)` take the cut-offs as a parameter, so a test can re-score the same round under different rules.

One trap: a timestamp built by adding does not survive being subtracted again. `(10.0 + 0.120) - 10.0` is `0.11999999999999922`, which is below a 0.120 cut-off. Tests that check a threshold boundary anchor the cue at zero so the subtraction is exact. See `exactRound(reactionTime:)` in `AkinesiaAnalyzerTests`.

## Running the suite

Run as a single line. Multi-line commands with trailing `\` break if a blank line or trailing whitespace follows the backslash, and the shell then executes each flag as its own command.

```bash
xcodebuild -quiet -project Kinesia.xcodeproj -scheme Kinesia -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
```

To type-check without running (faster; compile errors are easier to read than test-run output):

```bash
xcodebuild -quiet -project Kinesia.xcodeproj -scheme Kinesia -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build-for-testing
```

List installed simulators with `xcrun simctl list devices available` and substitute `id=<UUID>` for `name=...` if names are ambiguous.

Note that `xcodebuild ... build` compiles the **app target only** and will not surface test compile errors. Omitting `-destination` targets a real device, which fails with a code-signing error unrelated to the code; simulator builds need no development team.

# Dexterity testing

Dexterity coverage adds deterministic tests for canonical transforms, scale invariance, point-to-segment distance, ordered segment ownership, self-intersection protection, RMSE, per-sequence RMSE, path length, swipe distance, speed/CV, malformed data, UIKit-capture state handling, route progression, and route-layout fitting.

Persistence tests use an in-memory Core Data store to verify a valid V1 save creates exactly one `TestSession`, one `DexterityResult`, and one `RawCapture`; raw practice/retry/cancelled attempts round-trip through JSON; `fingerLifts`, scored-only metric mapping, newest-first fetching, and incomplete-save rejection are covered. Session-model tests verify one completed practice trace, failed retry retention, three completed scored traces, and save-once protection.

Manual interaction validation was performed in the Xcode development tracing harness for route/render alignment, continuous UIKit capture, ordered progress, completion, early lift, cancellation visibility, reset, and debug metric readout. Physical iPhone validation remains appropriate for real-device coalesced-touch behavior.

## Manual simulator validation

Automated tests use an in-memory store and cannot prove that data survives the app being killed.

### Bradykinesia

As of 2026-08-15, a live bilateral UI run and a quit/relaunch persistence check are still pending. They must not be reported as done until actually exercised in the simulator.

1. Home navigation into the Bradykinesia test.
2. Countdown gating — taps during the countdown are not recorded.
3. The active hand is clearly labelled during countdown and capture.
4. A full 20-second right-hand capture, then the rest screen naming the left hand.
5. Taps during rest are ignored.
6. A full 20-second left-hand capture, then the finished screen listing both hands.
7. Exactly one `TestSession`, two `BradykinesiaResult` rows, and two `RawCapture` rows per completed test.
8. The latest-saved-test section lists both hands with their tap counts.
9. Navigating away mid-test discards the attempt and writes nothing.
10. App termination and relaunch, with both hands still visible afterwards.
11. With a medication dose logged earlier the same day, the session links it; with none, nothing is linked and no misleading value is shown.

### Akinesia
1. Home navigation into the Fireflies test.
2. The jar is visible in the middle and the firefly is clearly the brightest thing on screen when it appears.
3. The firefly appears suddenly, with no fade or glow ramp.
4. Touches before the test starts are ignored.
5. Lifting a finger before the firefly appears is handled kindly and the round is retried, not counted.
6. Letting a firefly time out without moving records a missed round and moves on.
7. Sliding to the firefly instead of lifting works and is timed the same way.
8. The round counter reaches the configured number of rounds and the session ends.
9. Navigating away mid-session writes nothing.
10. The feedback line appearing or disappearing does not shift the board under the resting finger.


### Opening screen and dashboard

Checked in the simulator on 2026-10-23, on an iPhone 17 running iOS 27.

1. First open: Get started into the medication schedule, then the questionnaire.
2. Returning: greeting and date, with no streak line at all before there is any history.
3. The dashboard reading the saved schedule, with the medicine row showing the next dose time.
4. The garden card opening the first unfinished test.
5. The settings cog opening the schedule, saving, and returning to the dashboard.
6. The tab pill moving between Today, Garden and Insights.
7. Re-saving a schedule that was loaded from the store, which is the path that used to throw.

The third opening state, where all three tests are already done for the day, was not exercised here: reaching it means completing three real captures. `HomeSummaryTests` covers the rule that decides it, so the logic is tested and the screen it produces is not.

### What is not unit tested

The chart views themselves. The derivations in `calculations/ClinicianView` carry the logic and are tested directly, which is the reason the views take finished arrays and only draw them. `ReportExportTests` covers the one thing the view layer can get wrong on its own: the geometry, background and footer of the printed page.
