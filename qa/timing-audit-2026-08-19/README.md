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
16. `16-activities-project-drop.png` — Activities after adding the Project assignment drop target below the App / Category list; activity rows advertise the drag affordance and projects accept the drop.
17. `17-activities-view-modes.png` — Activities after adding Unified, By Category, and Chronological views with full-width collapsible group headers.
18. `18-activities-phone-calls.png` — Activities after bringing the native read-only Phone Calls source into the Web timeline context, including its local connection state.
19. `19-activities-filters.png` — Activities after adding reusable local Activity Filters with field, comparison, and value controls plus the saved-filter empty state.
20. `20-activities-categories.png` — Activities after exposing the native Category store in Web, with built-in Focused / Distracting / Other / Idle colors and custom rule creation.
21. `21-activities-calendar-reminders.png` — Activities after adding Calendar Events and Completed Reminders source panels, with per-date loading and explicit local permission empty states.
22. `22-activities-screen-time.png` — Activities after adding the read-only Screen Time source panel, including the current Full Disk Access status and its inclusion in the activity evidence.
23. `23-rules-project-automation.png` — Rules after exposing persisted project automation rules with project, field, comparison, priority, and delete controls.
24. Review report builder — verified in the running Web companion with nine report presets, Include source selection, Group by aggregation, billing/rounding controls, and CSV/JSON/HTML exports.
25. Settings — verified in the running Web companion with native-backed tracking, idle, working-hours, privacy, connection, and source-permission controls.
26. Settings local data — verified with project/time-entry archive export controls and native sync/integration actions; project export completed from the running app.
27. Review report formats — verified native `/v1/reports` XLSX and PDF responses and exposed both downloads beside the existing CSV/JSON/HTML actions.
28. Today timer controls — added the running Focus timer's remaining-time display, estimate picker, and ±15 minute start adjustment against the native timer API.
29. Activities exclusions — verified create/delete of a temporary App exclusion through the Web companion and native persisted exclusion store.
30. Activities category editing — verified create, edit, color/rule update, and delete of a temporary custom category from the Web companion.
31. Activities filter editing — verified create, rule/name update, and delete of a temporary saved filter from the Web companion.
32. Activity detail project fidelity — corrected the detail dialog to show the assigned project instead of always displaying `None`.
33. Activities display preferences — verified native-backed Show Idle, Chronological grouping by Project/Device, mutually exclusive grouping, preference persistence, and wrapped toolbar layout in the running Web companion.
34. Activities Display menu — verified persisted Selected day / Last 7 days range, Show window titles, Show website paths, Include time entries, device selection, date labels for historical rows, and historical detail recording dates.
35. Historical project assignment — carried the source date through the activity drag payload so assigning a seven-day-range row updates the correct native date.
36. Native workspace parity — added Web Stats, Reports, and Teams first-level navigation; Reports now owns the report builder, Stats summarizes seven-day evidence, and Teams supports native-backed creation, member addition, and archive.
37. Persistent Web shell — verified one shared date / current-block / Focus / Research Focus header across Today, Plan, Activities, Stats, Reports, Teams, Review, and Rules; Today no longer duplicates its page-local header.
38. Activities Entry-O-Matic — verified the native-shaped conversion dialog, project scope, minimum-duration and maximum-gap controls, overlap replacement toggle, preview recalculation, billing/notes fields, and create action against the selected App / Category evidence.
39. Activities project workspace — verified the native-shaped Projects / Unassigned / Filters sidebar, project and saved-filter selection, filtered timeline/list counts, and no horizontal overflow at the desktop viewport.
40. Activities entry workflow — verified native-shaped New Time Entry and Start Timer sheets, project/billing/notes fields, timer estimate choices, recent-entry surface, validation, and cancel paths without creating QA data.
41. Activities toolbar popovers — verified native-shaped Devices and Filters popovers, device visibility state, Focused / Distracting / Other / Idle selection, saved-filter entries, automatic close after selection, and continued filtering of the same activity evidence.
42. Activities timeline orientation — verified native-backed horizontal / vertical switching, Y-axis time selection in vertical mode, persisted `timeline_orientation`, reload restoration, category-colored blocks, and no horizontal overflow.
43. Activities timeline legend — verified the Web timeline exposes the same category semantics as the native surface: Focused deep blue, Distracting red, Other graphite, and Idle outlined graphite, with an accessible legend and no horizontal overflow.
44. Activities timeline sources — verified App usage blocks remain category-colored, Time Entry overlays use orange solid outlines, Calendar overlays use blue dashed outlines, Calendar click-to-record remains API-backed, and vertical mode still renders 625 live activity blocks without overflow.
45. Today timeline hit targets — verified Plan blocks are full buttons that enter Plan, live Actual blocks are full keyboard-accessible buttons that open Activity details, and the existing hover-card Record time action remains separate from parent selection.
46. Plan daily Markdown files — verified native `swift build` and smoke tests after adding a no-context-switch ensure-file path for `/v1/plans?date=...`; missing selected dates now materialize their blank `Calendar/YYYY-MM-DD.md` template without replacing the currently loaded editor document.
47. Plan month navigation — verified all 42 month cells remain actionable, Next / Previous month no longer snap back to the selected date, December 31 selection switches the editor to `2026-12-31.md`, and a missing day renders a blank editable task list.
48. Plan connected empty state — verified a connected missing-day plan has no preview Morning routine / Team sync / Lunch blocks, no stale “14:00–16:00 added” toast, zero Markdown task rows, and no horizontal overflow.
49. Plan Time Block resizing — verified separate top/start and bottom/end resize hit targets, 15-minute snapping, a 30-minute minimum duration, and independent Markdown persistence.
50. Plan Markdown editor — verified the connected Plan surface uses one continuous editable Markdown document, preserves arbitrary lines and normal Return editing, and overlays task drag/check controls without replacing the source with per-line title fields.
51. Plan Time Block selection — verified a plain click selects a narrow calendar block without opening the schedule dialog or removing its time; only pointer movement beyond the drag threshold starts a reschedule, and selected actions no longer cover the block body.
52. Plan Time Block accessibility — verified scheduled blocks expose button semantics, readable range labels, selected state, and Enter / Space keyboard selection without opening the schedule dialog.
53. Stats Category breakdown — verified the seven-day Stats view aggregates active time by Category, shows percentages and durations, uses the custom category color, Focused deep blue, Distracting red, excludes Idle from active totals, and has no horizontal overflow.
54. Native Stats Category parity — verified `swift build`, packaged-app launch, and native smoke tests after adding the same active Category breakdown to the macOS Stats workspace.
55. Native Today timeline hit targets — verified `swift build`, packaged-app launch, and native smoke tests after making Plan, Actual, and recorded time blocks full visual/accessibility hit targets that route to their owning workspaces.
56. Activities/Plan modal keyboard dismissal — verified the New Time Entry and timeline edit dialogs open from their full button hit targets and close with Escape; Plan's schedule-choice and Entry-O-Matic paths now also register Escape dismissal in code.

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
- Activities now supports assigning a captured activity to a project by dragging its App / Category row onto a Project row; the local API persists the assignment for the selected date, including historical dates.
- Activities now supports the native three-way view switch: Unified app groups, category groups, and Chronological rows; group headers are full-width buttons and preserve the App / Category row semantics.
- Activities now surfaces the native read-only Phone Calls source beside the full-day timeline, with per-date loading, local connection status, and address hiding when call history is available.
- Activities now supports reusable Activity Filters backed by the native local API; selecting one narrows the same App / Category rows, while creating or deleting a filter persists on this Mac.
- Activities now exposes the native Activity Categories store; custom categories can classify an App, website, or item and immediately drive the App / Category colors, while Focused remains deep blue and Distracting remains red.
- Activities now mirrors the native Calendar Events and Completed Reminders panels; both are read-only by default, use the selected date, and show a truthful not-connected state until macOS access is granted.
- Activities now surfaces the native Screen Time import state separately while keeping its records in the shared App / Category evidence list; the Web panel reports the exact local permission requirement when access is unavailable.
- Rules now exposes native project automation rules; a saved App / title / domain / URL / keyword match can be created, reordered, and removed from the Web companion while preserving the existing website blocklist.
- Review reports now has the native report-builder shape: Timesheet, Weekly Snippet, per-project/application/document, detailed, and raw presets; Include and Group by controls change the actual rows and totals instead of being decorative.
- Settings now reads and writes the native Preferences store through `/v1/preferences`; tracking state, idle threshold, working hours, weekend behavior, sleep handling, LAN exposure, and Calendar/Reminders/Screen Time status are visible in one full settings surface.
- Settings now exposes local project and time-entry archive transfer, native Sync now / Restore latest backup, and per-provider ClickUp / Linear / Clio sync actions; exports stay local to the browser download and imports are delegated to the native merge/deduplication stores.
- Review exports now cover CSV, JSON, HTML, XLSX, and PDF; XLSX/PDF are generated by the native report writer with the current date, Include, Group by, billing, and rounding selections.
- Today now exposes Timing-style timer refinement while a timer is running: set an estimate and move the captured start earlier or later in 15-minute increments without leaving the current block.
- Activities now separates reusable Filters from Exclusions: Filters narrow the visible evidence, while Exclusions remove matching App / website / item / device captures before they enter the local stream.
- Custom Categories now support editing as well as creation/deletion; changing a category's role, color, or matching rule updates the native classification store used by the App / Category columns and timeline colors.
- Saved Activity Filters now support editing as well as creation/deletion; changing a filter name or rule updates the native reusable filter store used by the toolbar and reports context.
- Activity detail now reflects project assignment persisted by the drag target; unassigned segments still explicitly identify their source as app usage.
- Activities display preferences now persist through `/v1/activity-preferences`; Show Idle filters the shared timeline/list, Chronological can group by Project or Device, and the toolbar wraps instead of clipping on the desktop viewport.
- Activities now exposes a native-shaped Display menu; Last 7 days uses the already fetched weekly evidence while the selected-day timeline remains focused on the active date, and historical rows carry their source date through detail recording.
- Historical activity drag-and-drop now carries its source date into project assignment, matching the detail dialog's date-aware recording behavior.
- Web navigation now matches the native AppSection set: Stats, Reports, and Teams are first-level workspaces, while Review remains focused on planned-vs-actual and category evidence.
- Teams uses the native `/v1/teams` and `/v1/teams/:id/members` stores; creating, adding a member, and archiving a temporary QA team were verified against the running packaged app.
- The Web companion now preserves the native global workspace shell across every first-level page, so date navigation, the current block, Focus state, and blocklist entry remain available without replacing page-specific content.
- The global Focus control now matches native semantics: it toggles the Research Focus blocklist, shows Resume/Pause focus, is disabled without a scheduled current block, and never starts a timer implicitly.
- Activities now exposes Entry-O-Matic conversion: visible non-idle App / Category segments are merged by configurable gap, existing time can be subtracted or replaced, and the preview maps directly to native time-entry creation payloads.
- Activities now keeps project and saved-filter navigation beside the timeline, with full-width rows that filter the same App / Category evidence and preserve the project assignment drop workflow.
- Activities now exposes native-shaped New Time Entry and Start Timer sheets from the primary toolbar; direct timer starts are replaced by explicit title, project, billing, notes, and estimate configuration.
- Activities now groups device and filter selection into native-style popovers; Display remains focused on presentation settings while Devices and Filters own their respective scope choices.
- Activities now mirrors the native timeline orientation control; horizontal mode remains the default, vertical mode uses the same 24-hour evidence and selection workflow, and the preference is shared with the macOS app.
- Activities now exposes the category meaning directly beside the timeline; App identity remains separate from the color-bearing Category, with Focused deep blue and Distracting red.
- Activities now overlays local Time Entries and read-only Calendar Events on the same full-day timeline; source styling stays distinct from the Category color used by App / website activity.
- Today now makes its full Plan / Actual timeline blocks actionable: Plan navigates to the Markdown planner and Actual opens the shared Activity details surface, with visible focus affordances.
- Plan date reads now preserve Markdown-first behavior for missing days: the API creates the blank daily file while neighboring-day reads do not mutate the active editor document.
- Plan month navigation now keeps the visible month independent from the selected date until a day is chosen, so every calendar cell can be reached and selected.
- Connected Plan renders only the selected date’s Markdown tasks; static sample blocks and preview update messages are limited to offline preview mode.
- Plan calendar Time Blocks now expose separate full-width start and end resize handles; moving the top edge rewrites the start time, moving the bottom edge rewrites the end time, and both keep the task selectable and Markdown-first.
- Plan now keeps a single continuous Markdown textarea as the source of truth; task handles and circular checkboxes are overlays keyed to parsed task lines, while free-form Markdown remains directly editable and saveable.
- Plan Time Blocks now distinguish click from drag and place completion/remove actions below the selected block, preserving the full block hit target even in narrow three-day timeline columns.
- Plan Time Blocks now expose explicit button semantics and keyboard selection, keeping the visual click target and accessibility hit target aligned.
- Stats now provides a RescueTime-style active-time Category ranking beside weekday, project, and application views; Category remains the color owner, with Focused deep blue and Distracting red.
- Native Stats now presents the same Category ranking and colors beside Applications, while Project and Time Entry totals remain separate from active App / website / item classification.
- Native Today Plan blocks now open Plan and select the task; Actual and recorded time blocks open Activities. Their visible block surfaces, not only text glyphs, carry the interaction and accessibility labels.
- Activities timeline Time Entry overlays now open an editable dialog instead of only showing a passive status message; the edit form preserves the selected date, project, billing status, and full keyboard dismissal path.
