# Bradykinesia decisions
- **Untimed rest period between hands:** switching hands takes an unpredictable amount of time, and starting the round while the participant is still repositioning would affect the second trial.
# Dexterity V1 protocol decisions

- **Route:** fixed `constellation-v1`, version 1, with canonical points `(15,80) → (20,20) → (50,45) → (80,20) → (85,80)`.
- **Interaction:** right index finger, right hand, one completed practice trace followed by three completed scored traces. The target radius is 8 canonical route units.
- **Retry behavior:** early lift and cancellation end and preserve an attempt, then retry the same practice/scored round. Only the three completed scored sequences supply primary metrics.
- **Metric meanings:** `rmsError` is aggregate scored-sample RMSE; `rmsErrorMax` is maximum per-sequence RMSE; `swipeDist` is mean actual canonical path length per completed scored sequence.
- **Persistence:** a full raw session is encoded as one `RawCapture` JSON payload. The `DexterityResult.fingerLifts` attribute replaces `thumbLifts` through a Core Data renaming identifier.

These are MVP product/engineering decisions. They do not assert diagnostic accuracy, clinical validation, or severity cutoffs.

# Clinician view decisions
- **No composite scores:** report gives raw measurements with units and descriptive statistics for each chart. Giving raw data prevents "analysis" and diagnosis like behavior that could be flagged.
- **HealthKitLog:** stays in the Core Data model, deliberately rather than as a leftover. Watch data is not in scope for the clinician view and nothing in the report reads the entity.
- **Baseline:** 25th to 75th percentile of the daily medians over the 14 days after a 5-day familiarization period, the span supported by the Roche PD Mobile test-retest reliability work. Derived live from the daily medians rather than stored, so it stays correct when old data is edited or deleted.
- **Safety:** "Not a diagnostic tool." is drawn by the screen and by the PDF page template, so it cannot be left off one page, and every axis carries its unit.
- **Default units:** tap rate, in taps per second. It is the one measure every session has, and the tapping task is the one the patient does most often. The Measure control switches to reaction time or tracing error.
- **Placeholder zeros are resolved at the snapshot boundary:** The store writes `0` into required columns when a metric is unavailable, and invalidity is indicated by `isValid`. Snapshot initializers replace 0 with `nil` so every derivation takes `Double?` and every chart draws a gap.
- **Tap rate is not gated on `isValid`:** `BradykinesiaStore` validates the tap counts and the capture duration separately from the statistics, so tap rate is still a measurement even on a row whose drift CV was missing. Gating it would discard sessions for an unrelated reason.
- **Export is a four-page US Letter PDF:** fixed 612 x 792 pt geometry with equal margins on all four sides, light colour scheme, the same chart views as the screen, and the page number and disclaimer on every page. The file goes to the temporary directory and leaves through the share sheet. There is no network code in the feature.
- **One patient, one clinician:** no accounts, no roster, no clinician-side login. The report stays patient-owned and on device.
- **No conversational chart headings.** A heading names what the chart shows. It is never a
  question or a sentence addressed to the reader, because a clinician is reading a record rather
  than being walked through an app: "Which part of tapping is changing" was replaced for that
  reason. The `Task: Subject` form belongs to **Tapping Task: Component Breakdown** alone, which
  is the one chart that breaks a task into parts rather than plotting a measure over time; the
  other five keep their existing wording.
- **Screen and paper read one section list.** Each section is described once in
  `ReportSections.all(for:)`; the screen renders the list and the PDF slices it into pages. The
  wording used to be written twice, once per surface, and the two drifted: two headings differed,
  the captions existed on one side only, and the printed subtitles skipped `ReportFormat.count`
  so a one-dose window printed "1 scheduled doses". Pagination is the only thing the export
  decides on its own.
- **Session detail is two charts, not one.** The tapping interval series plots the gap between
  consecutive taps against tap number within one capture; the firefly round chart plots reaction
  time against round number, with the symbol carrying how each round ended. Both axes are in
  milliseconds, so the axis titles are what keeps them apart. The source spec merged these into
  one row, which could not have been built: `RoundRecord` holds no inter-tap interval.
- **The method and readings link stays as a placeholder.** `ChartSection` draws it and takes an
  `onMethodTap` closure; no caller passes one yet, so it does nothing. Keeping the control rather
  than hiding it is deliberate: it holds its place in the layout and keeps the open requirement
  visible. The regulatory requirement that a clinician can review the basis of an output is met
  only once the sheet exists and the same material reaches paper, where there is no link to tap.
- **Debug-only sample history:** `ReportSeed` writes 45 days of history behind a `#if DEBUG` button so the charts can be checked on a device. It is not in a release build.
