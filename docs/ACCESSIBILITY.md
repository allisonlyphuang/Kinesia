# Accessibility

Designed to prioritize accessibility for Parkinson's patients, primarily through touch target sizes that allow patients with tremor to navigate the UI comfortably.

## Touch targets
- `AkinesiaBoardLayout.minimumTouchTarget` uses 44 pt, following Apple's guidance and the WCAG enhanced target size
- The firefly jar and the firefly have floor radii of 28 pt and 26 pt. 
- In the clinician view, the window-length buttons and the day selector are 44 pt high, and the measure and hand pickers are in a row that is 44pt.
- On the dashboard each row is at least 60 pt tall, and the back and settings controls are 44 pt. 
- Each tab on the switch tab bar is about 130 pt wide.

## Charts without colour
Every series in the report is denoted by both color and shape, so the charts read in greyscale print and with potential colorblindness.

| Series | Colour | Second encoding |
| --- | --- | --- |
| Right hand | moss | circle |
| Left hand | pond | triangle |
| Dose taken | pine | solid rule |
| Dose skipped | pine | dashed rule |

## Contrast on patient screens

Patient screens: opening screen, dashboard, medication log, dose times screen, and PDQ-8.

| Pair | Usage | Ratio of on screen color : background |
| --- | --- | --- |
| moss `#576155` on cream | secondary text, section labels | 6.4:1 |
| pine `#3A423A` on cream | row titles, headings | 10.2:1 |
| pine on the  sage button `#DDE2D2` | button text | 7.9:1 |
| `textQuiet #6E7569` on cream | row values, tab labels | 4.7:1 |
| cream on the opening scrim at its lightest color | the wordmark and subtitle | above 4.5:1 |



## Copy

`AkinesiaCopyTests` asserts that the firefly screens do not display clinical or internal vocabulary, and that failure messages are not punitive. 
Task names are displayed as the task and not the symptom  ("Tapping", "Fireflies", "Constellation tracing"). 
