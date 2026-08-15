# Bradykinesia testing

## Automated coverage

The `KinesiaTests` XCTest target has 68 passing tests as of 2026-08-15:

| Suite | Tests | Covers |
| --- | --- | --- |
| `SummaryStatsTests` | 12 | percentile interpolation, sample SD, population SD, paper CV, population-moment skewness, non-finite input |
| `BradykinesiaAnalyzerTests` | 27 | TapInter extraction, malformed/non-increasing timestamps, insufficient samples, mean-X partitions, Euclidean drift, Pearson correlation, UI-label independence, correct-tap scoring |
| `BradykinesiaStoreTests` | 16 | Core Data mapping, bilateral session shape, validation guards, raw payload round trips, CV and correct-tap persistence, measured duration, medication context, fetch ordering, context refetch |
| `BradykinesiaTestModelTests` | 11 | phase transitions, tap gating/order/miss preservation, bilateral sequencing and rest, duplicate-save protection, persistence failure, geometry locking, reset |
| `TapModelTests` | 1 | `TapTrial` Codable round trip |
| `TapCaptureViewTests` | 1 | UI target classification including the radius boundary |

Tests use an isolated in-memory Core Data store and drive the capture lifecycle synchronously
via `countdownTick()` and `completeRunningWindow()` rather than sleeping, so a "20-second"
capture runs in microseconds.

### Test doubles

`BradykinesiaTestModel.init` takes `monotonicNow`, `wallClockNow`, and `persistenceAction` so
tests can substitute a controlled clock or a failing save.

The fake clocks must **advance** on every read. A constant clock produces a zero-length capture
window, which `BradykinesiaStore` correctly rejects with `invalidCaptureDuration`. See
`advancingClock(from:step:)` in `BradykinesiaTestModelTests`.

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

## Manual simulator validation

Automated tests use an in-memory store and cannot prove that data survives process termination.

As of 2026-08-15, manual completion of a live bilateral UI run and quit/relaunch persistence
verification are pending. They must not be reported as completed until exercised in the
simulator.

The manual check should confirm:

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
