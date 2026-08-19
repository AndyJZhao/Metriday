# Metriday for macOS

Native SwiftUI implementation of Metriday's Markdown-first daily planning workflow.

## Build

```bash
swift build
Scripts/run_smoke_tests.sh
Scripts/package_app.sh
```

The packaged app is written to `build/Metriday.app` and is ad-hoc signed for local use.

## Local data

Daily notes are plain Markdown files under:

```text
~/Library/Application Support/Metriday/Calendar/YYYY-MM-DD.md
```

The Markdown file is the source of truth. Scheduling, moving, resizing, completing, or removing a calendar time block rewrites the corresponding task line.

## Automatic activity monitoring

Metriday records a local activity history under:

```text
~/Library/Application Support/Metriday/Activity/YYYY-MM-DD.json
```

While tracking is enabled, the native macOS monitor samples the frontmost application every five seconds and closes an activity segment when the application, focused window title, or idle state changes. It also detects two minutes without keyboard or pointer input as `Idle`; when activity resumes, Metriday offers an Idle interval form so the user can account for time away from the Mac or skip it. The Today `Actual` timeline and Review metrics read these segments directly instead of using placeholder activity rows.

Application names are available without additional permission. To include focused window titles and document context, allow Metriday under System Settings → Privacy & Security → Accessibility. Safari, Chrome, Firefox, and Brave domain capture uses macOS Automation permission when available. For native document-based apps, Metriday also reads the focused document path through Accessibility when the app exposes it; captured activity data remains local-first and is written only to the Metriday Application Support directory.

Safari and Chrome windows explicitly labeled Private Browsing, Private Window, Incognito, or InPrivate are discarded from activity history. This conservative privacy check requires a readable window title; when Accessibility access is unavailable, Metriday captures only the application-level observation.

The left product navigation and top date/focus controls remain visible in every section. The top previous/next/Today controls and every day in Plan's mini month calendar switch the active daily note. Selecting a missing date creates a blank `YYYY-MM-DD.md` with `Focus` and `Notes` sections; existing days reopen without being rewritten.

## Projects, activities, and time entries

The Activities screen now exposes the Timing-style categorization workflow: activities can be assigned to local Projects, projects can store application/title/URL/path rules, and a rule can be created from an assigned activity. Chrome and Safari URLs are captured locally when their Automation permission is available; the UI displays the domain while the raw value remains in the local activity JSON.

Projects are stored at ~/Library/Application Support/Metriday/Projects.json. Projects can be nested, renamed, recolored, given a productivity weight, annotated, assigned a default billing status and hourly billing rate/currency, or archived from the project context menu. Manual Time Entries and Timer sessions are stored at ~/Library/Application Support/Metriday/TimeEntries.json; entries support Billable, Not billable, Pending, Billed, and Paid status. New entries and timers inherit the selected project's default billing status. Reports calculate billable amounts from the assigned project rate. Activities defaults to hiding true Idle segments, while Today continues to show Idle as execution evidence. Unknown foreground applications are tracked as ordinary other activity instead of being mislabeled as Idle.

Activities also supports saved Filters, stored at ~/Library/Application Support/Metriday/Filters.json. Filters are independent from Projects: they are rule-based saved views over app activities, may overlap, and never change project assignments or include manual time entries. Create or edit a filter from the Activities sidebar, choose whether any or all rules must match, and use application, bundle identifier, window title, URL/path, domain, full URL, keyword, device, start-time, or day-of-week fields with Timing-style string comparisons. Filters are included in the local Timing Sync archive.

Grouped Activities project and device headers are full-width, keyboard/accessibility-visible disclosure controls, so large activity histories can be collapsed without losing their totals. The activity view also includes a Timing-style Unified mode that expands project → application → activity groups, alongside Chronological and By Category modes. Calendar timeline events are clickable: a normal click opens the Time Entry editor and an `⌥`-click records the event immediately.

The Activities display-settings control persists Timing-style choices for including recorded Time Entries on the timeline, showing window titles and resource paths, and viewing the selected day or the last seven days. The selected activity view (Unified, Chronological, or By Category), grouping, Idle visibility, and device filter also persist across launches. The timeline remains anchored to the selected day while a wider range expands the activity list.

Activity tracking can be paused or resumed from Today, Settings, the menu bar, or the `⌘⇧T` Tracking command. A running timer remains independent of activity tracking and is materialized in live Review/report totals until it is stopped. Quick Start Timer reuses the most recent timer context, is available from the menu bar, and is bound to `⌃⌥⌘T`; invoking it while a timer is running stops that timer. Project editors reject parent-child cycles so hierarchical reports remain stable.

The Activities view includes a full-day local timeline. Dragging across it selects a 15-minute-snapped range, filters the activity list, and can seed a new offline Time Entry; hovering an activity block exposes a `+` shortcut and its context menu creates an entry for that exact range. Activities can be dragged onto a project to assign them; holding `⌥` while dropping also creates a future-activity rule. The sidebar Project Drop Zone also creates projects from Finder files/folders or dragged activities and adds path rules automatically; a normal multi-item drop groups into one project, while `⌘` splits items into separate child projects and `⌥` preserves the rule-creation intent. Reapplying rules is explicit and preserves manually assigned activities that do not match a rule. Chronological and By Category modes expose Websites, Applications, Paths, and Keywords summaries; the device menu filters multi-device activity, and the list can group by project or device while the local host name is retained in each segment. Review includes a report builder with custom date ranges plus This week, Last 7 days, and This month presets, app-usage/time-entry inclusion, optional absorption of app usage already covered by time entries, a short-entry filter, project/application/document/hour/day/week/month/year/week+day grouping, Timing-style Timesheet, Time Per Document, and Ultra-Detailed presets, billing-status filters, rounding, duration formats, and CSV/XLSX/JSON/HTML/PDF export. Screen Time device provenance is retained in exported rows, and time-entry reports clip entries that cross midnight to each included report day, so durations are not double-counted.

Activity rows expose a Timing-style double-click/context-menu path to create a Time Entry for the exact captured range.

Recorded manual and timer entries now appear as a distinct amber lane in Today’s Actual timeline and in the Activities 24-hour timeline. Cross-midnight entries are clipped to the selected day, while a running timer is rendered as a live entry without being persisted until it stops.
Recorded entries in the Activities timeline are clickable and open the full Time Entry editor; the context menu exposes the same action.

Timeline colors are explained inline: filled green/red/gray blocks are related, distracted, and other/idle app usage; the amber outlined lane is a manual or timer Time Entry; the blue dashed lane is a Calendar event. Hovering any block opens a Timing-style detail banner with the exact second-level range, duration, source, and Project marker; an unassigned App block shows `None · From the app usage`.

The running timer controls support Timing-style ±1/±5/±15-minute start corrections, alignment to the previous entry boundary, estimate check-ins, and visible remaining time.

Activities also includes an Entry-O-Matic flow. It previews generated entries from visible app usage, merges segments across a configurable maximum gap, discards sessions shorter than the selected minimum, subtracts existing entries by default, and offers an explicit overwrite mode before writing anything.

Review's Productivity score uses each assigned project's productivity weight; unassigned related, distracted, and other activity receive sensible local defaults.

Calendar Events are an optional EventKit integration. After Calendar access is granted, timed events from the selected calendars appear on the timeline and in the Activities screen; all-day events are hidden to keep the timeline focused. Record pre-fills a manual entry with the event title, calendar, notes, and exact times. Writable calendars expose edit and delete actions with an explicit delete confirmation; read-only calendars remain visible but cannot be modified. A Markdown task dropped with `⌥` can now create an external calendar event after the explicit Add Event action; Time Blocks remain local Markdown only. Calendar selection is stored locally, and Metriday remains fully usable without Calendar permission.

Completed Reminders are an optional read-only EventKit integration. After Reminders access is granted, completed reminders appear in Activities for the selected day and their titles can be used as Time Entry suggestions or opened through Record for editing. Settings can limit the integration to selected reminder lists and hide recurring reminders; those filters are stored locally. Metriday never creates or changes reminders and does not automatically create a Time Entry.

When the monitor sees a supported call app (FaceTime, Zoom, Teams, Slack, or WhatsApp) or a clearly labeled browser meeting window (Google Meet, Zoom Meeting, Teams, or Slack Huddle), it offers a local “Record call time?” prompt after a call lasting at least one minute. The prompt is editable and can be saved or skipped; no entry is created automatically.

Phone Calls is a separate read-only integration for the macOS CallHistory database used by iPhone/FaceTime continuity. After Full Disk Access is granted, calls appear as a selected-day Activities panel with a Record action; contact names are intentionally not read, and point-in-time calls use a one-minute editable range when recorded. The row context menu can hide calls from a specific number; this preference is local, excludes the number from the timeline and local API, and never changes Apple's source database.

Screen Time is an optional, read-only integration for Apple's local `knowledgeC.db`. After Full Disk Access is granted, Metriday imports iPhone/iPad-style app and web usage into the selected-day Activities timeline, Today actuals, Review summaries, project rules, Entry-O-Matic, and exports. Imported rows are archived under `~/Library/Application Support/Metriday/ScreenTime`, so project assignments survive the system's retention window. Apple changes this private database format frequently; Metriday introspects the available schema and degrades to archived data when the database or permission is unavailable.

Rules can be created from an activity or manually from Rules. Manual rules support application, bundle identifier, title, path, domain, full URL, keyword, start-time, and day-of-week matching; operators include contains, exact, prefix, suffix, wildcard, not-equal, and regular expression. A pattern can combine simple terms with `||` and `&&`; the priority arrows change first-match order, and Reapply to Today applies the current order to stored activity segments.

Settings persist tracker behavior in ~/Library/Application Support/Metriday/Preferences.json, including idle threshold, weekend tracking, overnight-capable working-hour limits, whether tracking starts when Metriday opens, and whether running timers stop when the Mac sleeps. The activity monitor closes its active segment before system sleep and resumes after wake when tracking was active. The Settings sheet can also register Metriday as a macOS login item through ServiceManagement.

The Settings sheet also maintains activity exclusion rules at ~/Library/Application Support/Metriday/Exclusions.json. Rules can match an application, bundle identifier, window title, URL/path, domain, full URL, or device with the same string comparisons used by project automation. Matching activity is filtered before an activity segment is created; the legacy bare bundle-ID JSON format remains readable.

## Time Blocks

- Drag a Markdown task into the Timeline to choose between a local Time Block and an external Calendar Event.
- Hold `⌘` while dropping to create a Time Block immediately.
- `⌥` + drop creates an Event immediately when Calendar access is already available; otherwise it opens the explicit Connect Calendar → Add Event path.
- Drag the block body to move it; drag the top edge to change its start; drag the bottom edge to change its end.
- Time Blocks only rewrite Markdown (for example, `- [ ] 13:00 - 14:30 Email`) and do not request Calendar access or create external events.

The left pane is a native continuous Markdown editor with NotePlan-style live preview. Inactive lines render as headings, bold/italic text, quotes, lists, links, inline code, and clickable task checkboxes instead of exposing source delimiters; the active line reveals only the Markdown syntax needed for editing. Return continues task, bullet, and numbered-list prefixes. The file is still saved exactly as plain Markdown, task lines expose a six-dot gutter handle as soon as they match `- [ ] Task`, and calendar actions only rewrite the corresponding task line.

## Website blocking MVP

While a focus session is active, Metriday can inspect the frontmost Safari or Chrome tab through macOS Automation and redirect blocklisted domains to a local focus page. The app asks for Automation permission when this feature is first used.

A system-wide Network Extension content filter is intentionally not bundled in this local build because Apple requires a restricted entitlement and signed app-extension distribution.

## Reports and menu bar

Review is backed by the local activity history, project assignments, Screen Time imports, and manual time entries. Report Builder supports selectable dates, project hierarchy, billing status, short-entry filtering, rounding, duration formats, and CSV/XLSX/JSON/HTML/PDF exports. Settings can export/import project hierarchies and rules as JSON, and export/import completed time entries as JSON while skipping duplicate IDs. Timer start suggests the most recent non-manual timer for quick restoration of its title, project, notes, and billing status. Metriday also exposes a native menu bar item with Start Timer, Stop Timer, and Open Metriday actions.

Review also includes a deterministic Smart Activity Summary. It groups the same local segments used by the report engine, identifies the dominant application, longest related stretch, largest distraction, and imported device time, and explains each highlight with a duration and source range. This local summary is intentionally network-free; it provides an auditable baseline for a future model-backed summary without sending activity or document data off the Mac.

The running timer controls support Timing-style ±1/±5/±15-minute start corrections, alignment to the previous entry boundary, estimate check-ins, and visible remaining time. The same estimate operations are available through the local API.

Local automation commands use the `metriday://` URL scheme: `metriday://tracking/pause`, `metriday://tracking/resume`, `metriday://timer/start?title=Deep%20work&project=Research`, `metriday://timer/stop`, `metriday://entry/add?title=Meeting&minutes=30`, and `metriday://phone-calls/hide?address=555-0100&hidden=false`. Entry commands also accept ISO-8601 `start`/`end`, `notes`, `projectID`, and `billingStatus` query parameters.

The packaged native app also exposes a Cocoa AppleScript dictionary at `Contents/Resources/Metriday.sdef`. Scripts can use `tell application "Metriday"` to `start timer`, `stop current timer`, `pause tracking`, `resume tracking`, `add time entry`, `get time summary`, `list projects`, or `export report`; timer and entry commands accept title, project, notes, billing status, and date parameters, while report export accepts a date range, CSV/XLSX/JSON/HTML/PDF format, and destination path. The scripting commands execute on the same main-actor stores as the UI and do not create a second tracking database.

The native app also exposes a localhost-only HTTP API at `http://127.0.0.1:8765/v1`. `GET /v1/status`, `/v1/plans?date=YYYY-MM-DD`, `/v1/activities`, `/v1/phone-calls?date=YYYY-MM-DD`, `/v1/insights?date=YYYY-MM-DD`, `/v1/reports?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&format=json`, `/v1/time-entries`, `/v1/projects`, `/v1/filters`, and `/v1/exclusions` provide local data; filters and exclusions support `POST`, `GET`, and `DELETE`, while filters also support `PATCH` and `PUT` for rule-based saved activity views. Report exports accept CSV, XLSX, JSON, HTML, or PDF plus include/grouping/billing/rounding query options. `/v1/phone-calls/hide` manages the local number filter, and `/v1/insights` returns deterministic, network-free highlights with explicit source and duration fields so the Web companion and reports can audit the same activity evidence. `PUT /v1/plans?date=YYYY-MM-DD` writes a complete Markdown document, while `POST /v1/tracking/pause`, `/v1/tracking/resume`, `/v1/timer/start`, `/v1/timer/stop`, `/v1/timer/adjust`, and `/v1/time-entries` provide local automation; timer start accepts an optional estimated duration and adjust shifts the current start by seconds or minutes. Export and import endpoints use the same JSON archives as Settings. The server binds only to loopback and is controlled from Settings.

`POST /v1/timer/estimate` sets the active timer estimate in seconds or minutes; `/v1/status` includes the current estimate and remaining seconds.

For integrations that expect Timing's public resource vocabulary, the same server accepts `/api/v1` aliases for projects, project hierarchy, teams, activity hierarchy, and time entries. Responses expose `data`, `title`, `start_date`, `end_date`, `billing_status`, `project`, `latest`, `running`, and `custom_fields` fields; `PATCH /api/v1/time-entries/batch-update` updates a group of entries. The plain-text `GET /api/v1/activity-hierarchy` supports date ranges, total/day/hour/15-minute/5-minute buckets, project filters, depth, line budgets, and mobile-device inclusion. Authentication remains unnecessary because the server is loopback-only.

Timing Sync is available from Settings as a shared-folder sync layer. Select an iCloud Drive, Dropbox, NAS, or other folder shared by the user's Macs; every device writes `devices/<device-id>.json`, rolling snapshots under `backups/`, and a `manifest.json`, then merges projects, filters, rules, time entries, local activity history, archived Screen Time activity, Focus website rules, activity exclusion rules, and Markdown daily plans. The latest 30 snapshots are retained across devices, so a cloud-folder overwrite has a recoverable local archive; Settings and `POST /v1/sync/restore` can restore the latest snapshot after writing a safety backup first. Project IDs are translated during import, activity device names are preserved, and separate device files avoid overwriting offline edits. Older archives without Screen Time, Focus rules, or rule-based exclusions remain readable. `GET /v1/sync/status` and `POST /v1/sync/now` expose the same local sync state. This is deliberately provider-neutral and local-first; a hosted account service and web dashboard can be layered over the same archive contract later.

Settings also contains a local-first Project integrations panel for the Timing-compatible ClickUp, Linear, and Clio workflows. ClickUp imports tasks from a configured List ID, Linear imports issues through its GraphQL API, and Clio imports Matters through API v4. Credentials are stored in the macOS Keychain, requests are made only after Test connection or Import projects is pressed, and imported records become nested Metriday projects with `integration_provider`, `integration_id`, `integration_url`, and `integration_status` custom fields so they remain traceable and deduplicated. GrandTotal can consume the existing CSV/XLSX report exports. `GET /v1/integrations` exposes sanitized connection state without returning tokens.

The Team workspace panel provides local teams, members, and explicit team ownership on projects. Team archives keep stable member IDs and are included in Timing Sync; project team IDs are remapped when a shared archive is merged on another Mac. The public-shaped API exposes `GET/POST /api/v1/teams`, `GET/POST /api/v1/teams/{team_id}/members`, and returns `team_id` on project resources. Personal projects remain the default, and team members are not exposed in ordinary activity data.

The Vite Web App at the repository root is now an API-backed companion view. It uses `http://127.0.0.1:8765` by default, or a persisted address from Settings, `window.__METRIDAY_API_BASE__`, or `VITE_METRIDAY_API_BASE` when hosted beside another gateway. It is packaged as an installable PWA with an offline shell; the Web App Settings panel explains how to install it on a phone and configure a Mac LAN/HTTPS API endpoint. The native API remains loopback-only by default; the native Settings sheet has an explicit opt-in to bind on the local network. With the native app running it shows live Today activity, Activities, Review evidence, projects, time entries, plan metadata, sync state, timer start/stop controls, and the native Focus blocklist. The date controls load the corresponding daily Markdown plan and activity history. Review's six-day planned-vs-actual chart is calculated from native activity and plan data, and its Reports & exports panel supports custom ranges, app-activity inclusion, billing-status filtering, duration rounding, project-rate amounts, and CSV/JSON/HTML exports. Activities can create or delete local manual time entries, Projects & clients can edit rates and billing defaults, and Rules can add, allow, remove, or toggle Focus domains through the same native store. Newly added Web Plan tasks are inserted into the source Markdown rather than remaining only in browser state. Without the loopback or configured remote API it falls back to the visual preview data and clearly labels the connection state. This keeps the local Web App useful today while leaving a provider-authenticated hosted Timing Web App as a later deployment boundary.
