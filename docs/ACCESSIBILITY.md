
# Accessibility

Kinesia is designed with the motor and usability challenges associated with Parkinson's disease in mind. Tremors, reduced fine-motor control, slower movements, and difficulty accurately reaching small targets can make conventional mobile interfaces frustrating to use.

The app uses larger touch targets, readable typography, a calm visual design, and game-based movement assessments to make daily tracking more approachable. Accessibility is considered throughout the patient interface, although further testing with people living with Parkinson's is needed.

## Touch targets and motor accessibility

Touch interactions are especially important in Kinesia because the app is used both for navigation and for collecting movement measurements.

The interface uses larger controls where possible to reduce accidental taps and make common actions easier to reach.

| Component | Implementation |
| --- | --- |
| Firefly test | `AkinesiaBoardLayout.minimumTouchTarget` uses a 44 pt minimum target. |
| Firefly targets | The jar and firefly have minimum visual radii of 28 pt and 26 pt, respectively. |
| Today dashboard | Activity rows are at least 60 pt tall. |
| Navigation | Back and settings controls use 44 pt targets. |
| Tab bar | The custom navigation tabs have wide interaction areas, approximately 130 pt each. |
| Clinician Insights | Date-range controls and day selection use 44 pt heights, with measure and hand pickers placed in a 44 pt row. |

Apple recommends sufficiently large touch targets for reliable interaction. These sizes provide a useful starting point, but target dimensions alone do not establish accessibility for users with significant tremor or reduced dexterity.

The motor tests intentionally use more controlled interactions because touch positions, timing, and movement patterns are part of the measurements being collected. Enlarging or changing these test targets could also change the measurement protocol, so any such adjustments should be evaluated separately from ordinary navigation controls.

## Visual design and readability

Kinesia uses a muted, nature-inspired palette intended to reduce visual clutter while maintaining readable text and identifiable controls.

The patient interface uses cream backgrounds, dark green text, rounded cards, and consistent spacing. The typography system provides a hierarchy between headings, instructions, and supporting information.

### Color contrast

The following contrast ratios were documented for the patient-facing design.

| Color combination | Usage | Reported contrast |
| --- | --- | --- |
| Moss `#576155` on cream | Secondary text and section labels | 6.4:1 |
| Pine `#3A423A` on cream | Headings and primary text | 10.2:1 |
| Pine on sage button `#DDE2D2` | Button labels | 7.9:1 |
| Quiet text `#6E7569` on cream | Supporting values and tab labels | 4.7:1 |
| Cream text over the opening-screen scrim | Opening title and subtitle | Above 4.5:1 |

These are documented design values, not a substitute for checking the final rendered interface. Background artwork, overlays, transparency, and different UI states may affect the contrast users actually experience.

### Typography

The design system uses a consistent text hierarchy and supports Dynamic Type in parts of the patient interface.

Important text should remain readable without requiring users to distinguish between several similarly sized labels.

Further verification is needed for:
- Larger accessibility text sizes.
- Text wrapping within cards and buttons.
- Clinician charts and dense data labels.
- Landscape or reduced available screen space.

Fixed-size text in parts of the clinician interface remains an area for future accessibility improvement.

## Charts and information beyond color

The clinician report uses secondary visual encodings so information does not depend entirely on color.

| Data series | Color | Additional encoding |
| --- | --- | --- |
| Right hand | Moss | Circle |
| Left hand | Pond | Triangle |
| Dose taken | Pine | Solid rule |
| Dose skipped | Pine | Dashed rule |

These distinctions help when charts are printed in grayscale or viewed by someone with color-vision differences.

Chart labels, legends, units, and validity states remain important because differences in shape or line style may not be sufficient for every user.

Unavailable measurements are also kept distinct from real zero values. An invalid or missing result should not appear as a sudden decline in performance on a chart.

## Instructions and feedback

Kinesia presents its motor assessments as simple activities rather than requiring patients to understand clinical terminology before using the app.

Patient-facing task names include:

- **Tapping**
- **Fireflies**
- **Constellation tracing**

Instructions focus on what the patient should physically do during each test.

For example, the Dexterity test explains that the user should maintain contact while tracing each path and lift their finger between separate attempts. The interface also highlights the correct starting point before tracing begins.

The firefly test uses straightforward instructions and non-punitive language for unsuccessful attempts. `AkinesiaCopyTests` checks that the firefly screens avoid internal or clinical vocabulary and discouraging failure messages.

This approach is intended to reduce confusion and frustration, particularly when a user needs to repeat an attempt.

## Garden accessibility

The Garden uses illustrated plant growth to represent daily motor-test activity.

Its progression is based on the number of distinct motor activities recorded that day, from zero to three.

The illustrations are accompanied by text-based progress information, so understanding the current state does not require identifying differences between the plants.

The Garden also displays:
- The number of activities completed today.
- Individual completion states for Tapping, Fireflies, and Constellation tracing.
- The existing activity streak.

Activity status is communicated through text and accessibility labels rather than color alone. Decorative botanical artwork is treated separately from the information it represents.

Garden growth reflects participation, not symptom improvement or clinical performance. The interface avoids attaching a negative medical meaning to an incomplete day.


## Related documentation

- [Architecture](ARCHITECTURE.md) — application structure and data flow.
- [Testing](TESTING.md) — automated coverage and manual verification.
- [Clinical basis](CLINICAL_BASIS.md) — research informing the movement tasks and their limitations.
- [Data dictionary](DATA_DICTIONARY.md) — measurement definitions, units, and validity states.
