# Accessibility

What the code does today, and what it does not. The patients this app is for have a movement
disorder, so touch target size and anything that moves under a resting finger matter more here
than in an average app.

## Touch targets

`AkinesiaBoardLayout.minimumTouchTarget` is 44 pt, following Apple's guidance and the WCAG
enhanced target size. The firefly board is laid out from that number rather than from a
screenshot: the jar and the firefly have floor radii of 28 pt and 26 pt whatever the board side
is, the board itself has a floor of 280 pt, and `AkinesiaBoardLayoutTests` asserts the minimums
hold across device sizes and that every ring spawn lands on the board without overlapping the
jar. In the report, the window-length buttons and the day selector are 44 pt high, and the
Measure and hand pickers sit in a 44 pt row.

## Nothing moves under a resting finger

The firefly test has the patient hold a finger on the jar for the whole round, so the board
cannot reflow while they are touching it.

- `FireflyBoard.configure(...)` is called on every SwiftUI redraw and compares the requested
  firefly position against the last one, spawning only when the position changed. Otherwise one
  firefly would report several onsets.
- The feedback line appearing or disappearing must not shift the board. That is on the manual
  checklist in TESTING.md, because no unit test can see a layout shift.
- `configure(_:)` on the tapping test accepts new geometry only from `.ready` and `.rest`, so the
  targets cannot move mid-capture.

## Charts without colour

Every series in the report is distinguished twice, by hue and by shape, so the charts read in
greyscale print and without colour vision.

| Series | Colour | Second encoding |
| --- | --- | --- |
| Right hand | moss | circle |
| Left hand | pond | triangle |
| Dose taken | pine | solid rule |
| Dose skipped | pine | dashed rule |

`ChartTokens.handSymbol` returns a `ChartSymbol`, and the legend draws the same symbol the chart
does, so the key cannot drift from the plot. `designSystem/chartTokens.swift` deliberately does
not import Charts: the token layer defines the symbol, and the chart layer maps it onto a
concrete mark.

No chart uses red against green, and no chart uses colour to carry a judgement. The regulatory
boundary and the colour-vision requirement point the same way here.

## Legibility

- Axis labels thin out instead of overlapping. `ReportFormat.labelStride` keeps a tick on every
  point and caps labels at six across the chart, so a 30-day window does not print 30 of them.
  The dose-bin axis labels only the hour boundaries and says in the caption that the groups are
  30 minutes wide.
- Counts are pluralised through `ReportFormat.count`, so no string reads "1 readings" or
  "7 day(s)".
- Every axis carries its unit, and `PrimaryMetric.axisTitle` holds the unit in brackets the way a
  clinical chart labels an axis.
- The PDF forces a light colour scheme and fills white behind the whole sheet, so a chart with a
  transparent background cannot print as a grey block.

## Copy

`AkinesiaCopyTests` asserts that the firefly screens carry no empty strings, no clinical or
internal vocabulary, and no blame in the failure messages, and that practice and scored progress
never read identically. A missed round is a thing that happened, not something the patient did
wrong.

Task names are the task, not the symptom: "Tapping", "Fireflies", "Constellation tracing". Tests
in `ReportFormatTests` and `DataQualityTests` assert that none of them contains a symptom word.

## What is not done

These are known gaps, not oversights to be discovered later.

- **Dynamic Type does not reach the clinician view.** `designSystem/typographyTokens.swift`
  defines its fonts from text styles, which scale, but the report and the chart layer use fixed
  `.system(size:)` values throughout. Fixed sizes are correct for the PDF, which has fixed page
  geometry, and the screen currently inherits them.
- **VoiceOver coverage is partial.** The firefly board, the PDQ-8 questionnaire, and the
  medication log carry labels and hints. The report's charts do not: a chart is read as an image
  with no audio graph and no per-point label, so the figures behind a chart are not reachable
  without sight. The method and readings sheet that would hold those figures as a table is
  specified in CLINICIAN_VIEW.md §7.0, and its link is a deliberate placeholder that no caller
  wires up yet.
- **No automated accessibility tests.** No contrast ratios are asserted, and no VoiceOver or
  Switch Control pass has been run. Nothing in the suite would catch a regression in any of the
  above.
- **Reduce Motion is not consulted anywhere.** Nothing in the app animates during a capture, so
  there is nothing to disable today, but the setting is not read.
