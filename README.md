
<div align="center">
  <img src="KinesiaLogo.jpeg" alt="Kinesia Logo" width="220">

  <h1>Kinesia</h1>
</div>


**An iOS app for tracking movement and medication in Parkinson's disease through short, game-based activities.**

Parkinson's symptoms can change throughout the day, while clinical appointments capture only a small part of that experience. Patients are often asked to remember and describe those changes themselves. Kinesia explores whether brief, repeatable touchscreen activities can make it easier to record movement over time and review it alongside medication timing.

Instead of presenting each activity as a conventional assessment, Kinesia uses a calm, nature-inspired interface: a plant-watering tapping task, a firefly-catching movement-initiation task, and a constellation-tracing dexterity task. The aim is to make regular tracking more approachable without hiding what is actually being measured.

## Features

| Feature | What the user does | What the app records or displays |
| --- | --- | --- |
| **Tapping** | Alternates between two targets for 20 seconds, one hand at a time, in a plant-themed task. | Tap counts, timing, rhythm, and positional variation. |
| **Fireflies** | Starts with a finger on a home position, then lifts and taps a firefly after it appears. | Movement-initiation (reaction) time and movement time. |
| **Constellation tracing** | Traces a fixed five-point path, with separate attempts and continuous contact within each trace. | Path deviation, movement speed, and trace completion/validity. |
| **Medication** | Sets scheduled dose times and records medication events. | Scheduled versus logged medication information. |
| **PDQ-8** | Completes an eight-item Parkinson's quality-of-life questionnaire during onboarding. | Patient-reported responses, separate from motor-test measurements. |
| **Garden** | Completes the three motor activities during the day. | Four illustrated growth states based on **0–3 distinct activities recorded today**, plus an activity streak. |
| **Insights** | Reviews saved measurements and medication information. | Dated charts and a PDF report that can be exported using the iOS share sheet. |

The task names describe the movement characteristics being explored, not a clinical diagnosis. For example, constellation tracing provides measurements of fine-motor control; it does not independently identify dyskinesia.

## How it works

1. **Get started.** Set up medication times and answer the initial PDQ-8 questions.
2. **Record a check-in.** Open the three activities from **Today**. Each test collects touch information and saves its own results.
3. **Log medication.** Record dose events separately from movement tests so the information can be viewed in context.
4. **Visit Garden.** The garden illustration changes as different activities are completed that day. Repeating one test does not advance the garden multiple times.
5. **Review Insights.** Look at measurements across sessions and export a dated PDF for discussion with a clinician.

The current Garden is based on **daily activity completion**, not symptom improvement or medication adherence. A streak represents days with recorded motor-test activity; it is not a clinical score.

## Implementation

Kinesia is written in **Swift**, with **SwiftUI** for its interface, **UIKit** for lower-level touch capture where needed, **Core Data** for local persistence, and **Swift Charts** for the clinician-facing graphs.

```text
Touch coordinates + timestamps
            |
            v
    Test capture / lifecycle
            |
            v
      Calculation + validation
            |
            v
    Core Data: sessions + results
            |
            v
     Report data + chart series
            |
            v
       Insights / PDF export
```

The capture, calculation, and storage layers are kept separate so that measurements can be tested without running an entire game. Two details are especially important:

- **Time intervals and dates are different things.** The app uses monotonic touch timestamps for elapsed movement time, and wall-clock dates for saved sessions and calendar-based views.
- **Missing results are not zero results.** Invalid or unavailable measurements are identified as such instead of being plotted as real values, which could create misleading changes in a chart.

The clinician view works from snapshots of saved records and derives chart data separately from the Core Data objects. For the exact metrics, units, formulas, and validity rules, see the [data dictionary](docs/DATA_DICTIONARY.md) and [architecture](docs/ARCHITECTURE.md).

## Data and privacy

Kinesia is **local-first**. The current app does not require an account or use cloud synchronization; recorded sessions, medication information, and questionnaire responses are stored on the device. Users decide whether to share a PDF report through the iOS share sheet.

The report is intended to make recorded information easier to review with a healthcare professional. Patterns visible in a chart should not be treated as proof of medication response or as instructions for treatment.



## Project structure

| Location | Responsibility |
| --- | --- |
| `capture/` | UIKit touch collection and timestamps |
| `calculations/` | Measurement calculations and report derivations |
| `persistence/` | Data validation, Core Data stores, and report snapshots |
| `models/` | Core Data schema |
| `viewModels/` | Test state and lifecycle |
| `views/` | Onboarding, Today, motor tasks, Garden, medication, and Insights |
| `designSystem/` | Shared visual styles and UI tokens |
| `Assets.xcassets/` | Game and Garden illustrations, branding, and app assets |
| `KinesiaTests/` | Automated tests |

### Documentation

- [Architecture](docs/ARCHITECTURE.md) — capture-to-storage flow and report generation.
- [Data dictionary](docs/DATA_DICTIONARY.md) — stored fields, measurement definitions, and units.
- [Clinical basis](docs/CLINICAL_BASIS.md) — research informing the tasks and what it does **not** establish about Kinesia.
- [Testing](docs/TESTING.md) — automated coverage and manual checks.
- [Accessibility](docs/ACCESSIBILITY.md) — design accommodations and outstanding verification.
- [Architecture decisions](docs/ADR.md) — technical and product scope decisions.
- [Clinician view](CLINICIAN_VIEW.md) — reporting design and implementation notes.

The project draws on published work on Parkinson's self-monitoring, tapping tests, movement initiation, and touchscreen dexterity. Those studies informed the selection of tasks and measurements; they do **not** clinically validate this implementation. The papers and measurement-specific rationale are documented in [Clinical basis](docs/CLINICAL_BASIS.md).

## Team and scope

Developed by **Allison Huang and Vandit Bhatia**.

The current prototype focuses on on-device movement measurements, medication logging, patient-reported quality of life, and longitudinal review. Wearable/Apple Watch integration, passive tremor monitoring, expanded tracking, predictive machine learning, and clinical validation remain future possibilities rather than features of this version.
