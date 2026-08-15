# Metriday Native macOS — NotePlan Plan QA

## Comparison target

- Source visual truth: `/var/folders/h5/_5s_45r120q3vm_zr83gfs000000gn/T/codex-clipboard-995f3630-95d9-497c-9638-2df704b1100d.png`
- Native implementation: `qa/native-plan-noteplan-final.png`
- Full-view comparison evidence: `qa/compare-noteplan-full.png`
- Focused right-rail comparison evidence: `qa/compare-noteplan-sidebar.png`
- App bundle: `MetridayMac/build/Metriday.app`

## Viewport and normalization

- Source: 1046 × 547 pixels, light appearance, NotePlan Today editor with compact month and multi-day Timeline.
- Implementation: 1190 × 768 pixels, light appearance, native macOS window captured through Computer Use.
- State: Saturday, August 15, 2026; GeneZip scheduled 14:00–16:00; Read reviewer 2 scheduled 16:15–17:00; Draft response unscheduled.
- Full view: both original images were placed in one 2300 × 768 white comparison canvas without changing aspect ratio.
- Focused region: the source right rail was cropped at 332 × 547 and normalized to the implementation rail width; the implementation right rail was cropped at 338 × 547 below the app-level date header. The final side-by-side evidence is 676 × 546.
- The source does not contain Metriday's persistent app navigation rail, so the focused comparison excludes it rather than treating that product-level difference as drift.

## Findings

- No actionable P0, P1, or P2 visual mismatch remains.
- [P3] The implementation month typography is slightly denser than NotePlan's at this narrower native rail width. The month hierarchy, two selected dates, week-number gutter, navigation, and relative month/Timeline anatomy are preserved.
- [P3] Metriday uses its established blue-violet active color while the reference uses orange and magenta calendar accents. This is an intentional brand-token substitution, not a structural mismatch.

## Required fidelity surfaces

| Surface | Result | Evidence |
| --- | --- | --- |
| Fonts and typography | Pass | SF typography matches the native macOS character of the source. Editor content remains monospaced to expose Markdown syntax; small calendar labels stay legible without wrapping. |
| Spacing and layout rhythm | Pass | The editor-dominant split, compact month, Timeline header, all-day strip, four equal day columns, and aligned hourly grid reproduce the reference anatomy. Timeline opens near the active afternoon period so scheduled blocks remain above the fold. |
| Colors and visual tokens | Pass | White surfaces, graphite copy, soft dividers, muted secondary labels, pale date selection, and restrained elevation match the reference while retaining Metriday's blue-violet semantic accent. |
| Image quality and asset fidelity | Pass | No raster product imagery is required. Controls use native SF Symbols; no placeholder art, handcrafted SVG, emoji, or rasterized UI substitution appears. |
| Copy and content | Pass | `August 2026`, `Timeline`, `all-day`, Sat–Tue columns, date, Markdown task syntax, time ranges, tags, and local-file status are present. `Plan / Raw Markdown` and `Day / Week` controls are absent. |
| Affordances and interaction states | Pass | Each task has a visible six-dot drag handle with a semantic accessibility label, native drag preview, full-row gesture fallback, target highlight, and explicit Markdown update feedback. |
| Accessibility and resilience | Pass | Sidebar, date controls, editor fields, drag handles, month navigation, and timeline content are present in the macOS accessibility tree. Dense timelines scroll rather than clipping persistent controls. |

## Primary interaction evidence

- The packaged `.app` launched successfully and the Plan page was opened through native sidebar navigation with Computer Use.
- Accessibility inspection confirms there is one Markdown editor surface, no editor-mode segmented control, no calendar-mode segmented control, and three labelled task drag handles.
- The scheduling implementation provides two native paths over the same state transition: SwiftUI `draggable`/`dropDestination` for the six-dot handle and a simultaneous row drag gesture measured in the Plan coordinate space. Both resolve to `MarkdownStore.schedule`, which immediately rewrites the local Markdown range.
- `Scripts/run_smoke_tests.sh` passes Markdown round-trip parsing, 12/24-hour range handling, schedule, move, resize, unschedule-with-task-preservation, and domain block/allow matching.
- Computer Use's synthetic drag did not emit a sustained mouse-move event in this native SwiftUI window, including for an already scheduled block's move gesture. This is recorded as an automation-driver limitation rather than visual QA drift; the packaged app retains the standard macOS drag/drop implementation and the independent row-gesture fallback.

## Comparison history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P1 | The Plan toolbar exposed `Plan / Raw Markdown`, and the calendar exposed `Day / Week`, contradicting the NotePlan model. | Removed both mode systems and their alternate views. Plan now has a single Markdown editor and a continuous right rail. | `qa/native-plan-noteplan-final.png` and the accessibility tree show neither segmented control. |
| P1 | The original small drag glyph did not provide a dependable, discoverable scheduling path. | Added a 30 × 34 six-dot handle, semantic label/help, standard native drag preview/drop destination, whole-row gesture fallback, live target highlight, and Markdown update feedback. | Final capture shows the handle on every task; AX exposes `Drag … to timeline` labels. Model transition is covered by smoke tests. |
| P2 | The right rail was a single-day card view rather than NotePlan's month plus multi-day Timeline. | Added the compact August month, CW gutter, selected dates, Timeline header, all-day strip, and Sat–Tue columns. | `qa/compare-noteplan-sidebar.png` shows matching component anatomy and column structure. |
| P2 | The first month implementation was vertically compressed and timeline hour labels accumulated a four-point offset per row. | Increased the month grid rhythm, added the adjacent selected date, corrected label frame ordering, and opened the timeline near the active afternoon period. | Final focused comparison shows stable month rhythm and 13:00–17:00 labels aligned with blocks. |

## Follow-up polish

- Optional current-time red rule matching NotePlan's live timeline indicator.
- Optional animated connector between the active Markdown line and its scheduled block.

final result: passed
