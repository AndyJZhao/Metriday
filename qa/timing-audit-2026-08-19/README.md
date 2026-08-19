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

## Findings applied

- Activities now presents the captured App / Category / Time / Device evidence first, matching the primary purpose of Timing's Activities surface.
- Activity rows remain full-width keyboard-accessible buttons without default browser bevels or dark borders.
- Today only shows a scheduled current block when the native API provides one; otherwise it presents an explicit empty state and a generic Start timer action.
- Review keeps planned/actual evidence and Focused/Distracting/Other category colors in the same first-viewport evidence grid.
