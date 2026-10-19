# Kinesia

An iOS app for Parkinson's self-monitoring. A patient runs three short touchscreen tests, logs
their medication and a quality-of-life questionnaire, and gets a dated report they can show or
send to a clinician.

Everything stays on the phone. There is no account, no server, and no network code anywhere in
the app; the only way data leaves the device is a PDF the patient exports through the share
sheet.

**Not a diagnostic tool.** The app records movement and displays it. It assigns no severity, no
composite score, and no diagnosis, and it never recommends a dose change. That boundary is a
product decision, not a gap waiting to be filled: see [docs/ADR.md](docs/ADR.md) and
[docs/CLINICAL_BASIS.md](docs/CLINICAL_BASIS.md).

## What it measures

| Task | Interaction | Primary measurement |
| --- | --- | --- |
| Tapping | alternate between two targets for 20 seconds, one hand at a time | tap rate, interval variability, decrement |
| Fireflies | rest a finger on a jar, lift and tap each firefly as it appears | reaction time, movement time |
| Constellation tracing | trace a fixed five-point route without lifting the finger | distance from the route, swipe speed |

Alongside them: a medication schedule and dose log, and the eight-item PDQ-8 questionnaire. Both
exist so the report can put movement next to when doses were taken.

## How the code is arranged

Each test is the same four layers, in this order:

```text
capture (UIKit)   records touches and timestamps, decides nothing
analyzer (pure)   value types in, metrics struct out, no Core Data
store (static)    validates everything, then one atomic context.save()
view model        @MainActor, owns the lifecycle
```

The clinician view runs the same pipeline in reverse, and keeps the same property: Core Data rows
become flat `Sendable` snapshots, pure derivations turn those into one array per chart, and no
chart view ever touches an `NSManagedObject`.

| Folder | Holds |
| --- | --- |
| `calculations/` | every pure value type and analyzer, grouped per test, plus `ClinicianView/` for the report derivations |
| `capture/` | the UIKit views that record touches |
| `persistence/` | the stores, and the Core Data to snapshot mapping |
| `models/` | the Core Data model |
| `viewModels/` | one per test, plus the report |
| `views/` | SwiftUI screens, with the report under `views/Clinician/` |
| `designSystem/` | colour, type, spacing, and chart tokens |
| `KinesiaTests/` | 629 XCTest cases |
| `docs/` | the documents listed below |

Two rules hold across every layer:

- **An unavailable value is `nil`, never zero.** Stores write a placeholder zero into required
  numeric columns and set `isValid = false`; the read path turns those back into `nil`. A
  placeholder zero plotted as a measurement draws a dip that never happened.
- **Two clocks, never mixed.** Every interval comes from the monotonic `UITouch.timestamp`. Every
  stored instant is a wall-clock `Date`. Neither is ever used in place of the other.

## Building and testing

Requires Xcode with an iOS 26.5 simulator. Run the suite as a single line:

```bash
xcodebuild -quiet -project Kinesia.xcodeproj -scheme Kinesia -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
```

All 629 tests are synchronous and run against an in-memory Core Data store, so a 20-second
tapping capture and a 12-round firefly session both finish in microseconds. No test sleeps.

**Adding a file needs Xcode, not just the filesystem.** `project.pbxproj` uses classic
`PBXGroup` membership rather than file-system-synchronized groups, so a new `.swift` file has to
be added to the `Kinesia` target, and a new test file to `KinesiaTests`, by hand. A file created
on disk alone will not compile into the target and will not fail loudly.

More on the test suite, including the counting trap and the manual simulator checks that
automated tests cannot cover: [docs/TESTING.md](docs/TESTING.md).

## Documents

| Document | Covers |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | the layers of each test, the stores, and the clinician view read path |
| [docs/DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) | every field, its unit, and what each one means when it is missing |
| [docs/CLINICAL_BASIS.md](docs/CLINICAL_BASIS.md) | what each task measures, what the literature supports, and the boundaries |
| [docs/TESTING.md](docs/TESTING.md) | suites, how to run them, and what is checked by hand |
| [docs/ADR.md](docs/ADR.md) | decisions taken, with their reasons, and what is still open |
| [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md) | what the code does for legibility and touch, and what is untested |
| [CLINICIAN_VIEW.md](CLINICIAN_VIEW.md) | the clinician view specification, with each section's build state |
