# Testing

## Automated coverage

The `KinesiaTests` XCTest target has **248 passing tests** as of 2026-10-11:

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

Tests use an isolated in-memory Core Data store and drive each test's lifecycle synchronously
rather than sleeping, so a "20-second" tapping capture and a full 12-round firefly session both
run in microseconds.

### Counting the tests

Do not count with `grep -c "Test case .* passed"` on the build log. `xcodebuild` wraps long lines,
so a test with a long name can be split across two lines and missed, giving a number one or two
short. Count the declarations in the source instead:

```bash
cat KinesiaTests/*.swift | grep -cE '^\s*func test[A-Za-z0-9_]+\s*\('
```

Then confirm the run reported zero failures and `** TEST SUCCEEDED **`.

### Test doubles

`BradykinesiaTestModel.init` takes `monotonicNow`, `wallClockNow`, and `persistenceAction` so
tests can substitute a controlled clock or a failing save.

The fake clocks must **advance** on every read. A constant clock produces a zero-length capture
window, which `BradykinesiaStore` correctly rejects with `invalidCaptureDuration`. See
`advancingClock(from:step:)` in `BradykinesiaTestModelTests`.

`AkinesiaTestModel.init` additionally takes `foreperiodGenerator`, `spawnGenerator`, and
`deviceIdentity`, and `automaticallyScheduleTimers: false` stops every timer from firing on its
own. Tests then call `settleElapsed()`, `foreperiodElapsed()`, `slipWindowElapsed()`,
`responseCeilingElapsed()`, `movementCeilingElapsed()`, and `sessionCapElapsed()` themselves. The
same advancing-clock rule applies: a constant clock makes the session's own start and end
identical.

`AkinesiaAnalyzer.analyze(_:thresholds:)` and `score(_:thresholds:)` take the cut-offs as a
parameter, so a test can re-score the same round under different rules.

One trap worth knowing: a timestamp built by adding does not survive being subtracted again.
`(10.0 + 0.120) - 10.0` is `0.11999999999999922`, which is genuinely below a 0.120 cut-off. Tests
that check a threshold boundary anchor the cue at zero so the subtraction is exact. See
`exactRound(reactionTime:)` in `AkinesiaAnalyzerTests`.

## Running the suite

Run as a single line. Multi-line commands with trailing `\` break if a blank line or trailing
whitespace follows the backslash, and the shell then executes each flag as its own command.

```bash
xcodebuild -quiet -project Kinesia.xcodeproj -scheme Kinesia -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
```

To type-check without running (faster; compile errors are easier to read than test-run output):

```bash
xcodebuild -quiet -project Kinesia.xcodeproj -scheme Kinesia -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build-for-testing
```

List installed simulators with `xcrun simctl list devices available` and substitute
`id=<UUID>` for `name=...` if names are ambiguous.

Note that `xcodebuild ... build` compiles the **app target only** and will not surface test
compile errors. Omitting `-destination` targets a real device, which fails with a code-signing
error unrelated to the code; simulator builds need no development team.

# Dexterity testing

Dexterity coverage adds deterministic tests for canonical transforms, scale invariance, point-to-segment distance, ordered segment ownership, self-intersection protection, RMSE, per-sequence RMSE, path length, swipe distance, speed/CV, malformed data, UIKit-capture state handling, route progression, and route-layout fitting.

Persistence tests use an in-memory Core Data store to verify a valid V1 save creates exactly one `TestSession`, one `DexterityResult`, and one `RawCapture`; raw practice/retry/cancelled attempts round-trip through JSON; `fingerLifts`, scored-only metric mapping, newest-first fetching, and incomplete-save rejection are covered. Session-model tests verify one completed practice trace, failed retry retention, three completed scored traces, and save-once protection.

Manual interaction validation was performed in the Xcode development tracing harness for route/render alignment, continuous UIKit capture, ordered progress, completion, early lift, cancellation visibility, reset, and debug metric readout. Physical iPhone validation remains appropriate for real-device coalesced-touch behavior.

## Manual simulator validation

Automated tests use an in-memory store and cannot prove that data survives the app being killed.

### Bradykinesia

As of 2026-08-15, a live bilateral UI run and a quit/relaunch persistence check are still
pending. They must not be reported as done until actually exercised in the simulator.

The check should confirm:

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

Once the board draws something and the screen exists, the check should confirm:

1. Home navigation into the Fireflies test.
2. The jar is visible in the middle and the firefly is clearly the brightest thing on screen when
   it appears.
3. The firefly appears suddenly, with no fade or glow ramp.
4. Touches before the test starts are ignored.
5. Lifting a finger before the firefly appears is handled kindly and the round is retried, not
   counted.
6. Letting a firefly time out without moving records a missed round and moves on.
7. Sliding to the firefly instead of lifting works and is timed the same way.
8. The round counter reaches the configured number of rounds and the session ends.
9. Navigating away mid-session writes nothing.
10. The feedback line appearing or disappearing does not shift the board under the resting finger.

Until `AkinesiaStore` exists, a finished session ends on the save-failed screen. That is correct,
not a bug, and items about saving and relaunching cannot be checked yet.
