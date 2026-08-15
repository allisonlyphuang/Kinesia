# Bradykinesia testing

## Automated coverage

The `KinesiaTests` XCTest target currently has 46 passing tests covering:

- `SummaryStats`, percentile interpolation, sample SD, and non-finite input
- population SD, paper CV, and population-moment skewness
- TapInter extraction, malformed/non-increasing timestamps, and insufficient samples
- mean-X partitions, Euclidean drift, Pearson correlation, and UI-label independence
- Codable `TapTrial` round trips
- Core Data mapping, raw payload round trips, fetch ordering, and context refetch
- UI target classification
- ViewModel phase transitions, tap gating/order/miss preservation, duplicate-save protection, and persistence failure behavior
- geometry configuration locking and reset from a completed attempt

Run the suite with an installed simulator ID:

```bash
xcodebuild -quiet \
  -project Kinesia.xcodeproj \
  -scheme Kinesia \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<DEVICE_ID>' \
  test
```

Build the app with the same command ending in `build`.

## Manual simulator validation

Automated tests use an isolated in-memory Core Data store and do not prove process-relaunch persistence. The real simulator app installs and launches, and its persistent SQLite store is present. As of 2026-08-14, manual completion of a live 20-second UI run and quit/relaunch persistence verification are pending; they must not be reported as completed until exercised in the simulator.

The manual check should confirm: Home navigation, countdown tap gating, 20-second capture, finished/latest-result refresh, one session/result/raw capture per run, app termination/relaunch, and latest-result visibility after relaunch.
