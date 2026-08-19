# Timing fidelity audit · 2026-08-19

Captured from the running Web companion at `http://127.0.0.1:4173/` after the native API loaded.

## Steps

1. `01-today.png` — Today shell, planned/actual timeline, current-block state, and Smart Activity Summary.
2. `02-activities.png` — Activities before hierarchy correction; project and time-entry panels pushed the primary activity list below the fold.
3. `03-review.png` — Review metrics, planned-vs-actual chart, and date controls.
4. `04-activities-primary.png` — Activities after moving the recorded activity list ahead of project and time-entry management.
5. `05-activities-row-style.png` — Activity rows after removing browser button borders so separators remain light and native-looking.
6. `06-today-current-state.png` — Today after reconciling the current-block banner with the native API; no scheduled block is no longer replaced by preview content.
7. `07-review-category-pulse.png` — Review after adding a RescueTime-style category breakdown sourced from the same activity evidence.
8. `08-review-evidence-grid.png` — Review after placing Planned vs. Actual beside Category pulse so category colors remain visible in the first viewport.
9. `09-plan-month-calendar.png` — Plan after replacing the Day / Week branch with a compact, actionable month calendar above the selected-day timeline.
10. `10-plan-continuous-timeline.png` — Plan after extending the right rail into a three-day continuous timeline with the selected day as the writable drop target.
11. `11-date-controls.png` — Activities after making the header calendar icon an actionable date picker; App uses a light-gray icon tile while Category remains the semantic color column.
12. `12-category-colors-live.png` — Activities after restarting the packaged native build; the live API now carries category name, role, and color metadata, with Distracting rows rendered red.
13. Plan scheduling now follows the drop modifier contract: plain task drops open a Time Block / Event choice, ⌘ drops create a Time Block immediately, and ⌥ drops remain reserved for the later Event implementation.
14. `14-today-category-timeline.png` — Today after the packaged native restart; live activity segments populate the Actual timeline using the same category-aware block styles.
15. `15-activities-timeline.png` — Activities after adding the missing full-day timeline above the App / Category list, with 00:00–24:00 labels and clickable activity blocks.

## Findings applied

- Activities now presents the captured App / Category / Time / Device evidence first, matching the primary purpose of Timing's Activities surface.
- Activity rows remain full-width keyboard-accessible buttons without default browser bevels or dark borders.
- Today only shows a scheduled current block when the native API provides one; otherwise it presents an explicit empty state and a generic Start timer action.
- Review keeps planned/actual evidence and Focused/Distracting/Other category colors in the same first-viewport evidence grid.
- Plan exposes 42 actionable month cells and keeps the selected date's draggable timeline directly below the calendar.
- Plan's right rail now keeps adjacent days visible in one continuous timeline; only the selected day accepts Markdown scheduling writes.
- Today, Plan, Activities, and Review expose the same native date-picker affordance in their headers, while preserving Today and previous/next shortcuts.
- Activities keeps App identity in the light-gray icon tile and lets the item/app/website Category own its color: Focused uses deep blue and Distracting uses red.
- The packaged native API now exposes `categoryName`, `categoryRole`, and `categoryColor` on every activity segment, so the web companion receives the same category decisions as the macOS surface.
- Plan task drops now preserve the Time Block / Event distinction instead of silently turning every drop into a Time Block.
- Activities now exposes the same high-level timeline workflow as the native surface: full-day activity overview, category-colored blocks, click-through details, and a selection path for recording manual time.
