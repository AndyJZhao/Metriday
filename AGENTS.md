# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Durable Metriday product decisions

- Preserve the selected light, native-macOS visual direction: white and soft-neutral surfaces, graphite text, disciplined blue-violet accents, thin dividers, minimal elevation, and SF/Inter-like typography.
- `Today` is the execution-observability surface: planned and actual timelines are aligned side by side, with explainable task-relevance evidence and the active focus rule.
- Keep the Metriday product shell persistent across every section: the left `Today` / `Plan` / `Review` / `Rules` navigation and the top selected-date, current-block, focus-session, and blocklist controls must never be replaced by NotePlan-inspired editor chrome.
- `Plan` is Markdown-first. Markdown is the single source of truth; the calendar is a synchronized visual editor over the same task lines.
- Follow NotePlan's single-editor model in `Plan`: never split the surface into `Plan` and `Raw Markdown` modes.
- The right rail uses a compact month calendar above a continuous multi-day `Timeline`; do not add `Day` / `Week` mode controls.
- Every date in the compact month calendar is actionable. Selecting a date switches the editor and timeline to `Calendar/YYYY-MM-DD.md`; if that file does not exist, create a blank editable daily Markdown template. Never copy another day's tasks into the new file.
- Every Markdown task row exposes a visible six-dot drag handle. Dragging either that handle or the row into Saturday's timeline is the primary scheduling path, with a highlighted drop target and immediate Markdown feedback.
- Match NotePlan's drop modifiers: a plain drop opens the Time Block/Event choice, `⌘`+drop creates a Time Block immediately, and `⌥`+drop is reserved for the later Event implementation.
- A Time Block remains Markdown-first and is not an external calendar event. Its timeline block can be moved vertically, resized from the top to change its start, and resized from the bottom to change its end; every change rewrites the Markdown range.
- The Markdown pane is one native continuous plain-text editor, not a stack of per-line controls or a special add-task row. Every line is freely editable, Return inserts a normal newline, and arbitrary Markdown is preserved exactly. A task line receives a six-dot gutter drag identity as soon as it parses as `- [ ] Task`.
- Present Markdown with NotePlan-style hybrid live preview: inactive lines hide source delimiters and render semantic typography/controls, while the active line may reveal lightweight syntax needed for editing. Support headings, bold, italic, strike, inline code, links, quotes, bullets, numbered lists, and task checkboxes without changing the plain `.md` source.
- Render task markers as clickable circular checkboxes and continue task, bullet, and numbered-list prefixes on Return. Presentation attributes are never serialized into the Markdown file.
- Timeline block movement and edge resizing use native AppKit pointer tracking so scrolling, selection, menus, and SwiftUI gesture arbitration cannot swallow the drag. The body moves; the top edge changes the start; the bottom edge changes the end; values snap to 15 minutes.
- Dragging a Markdown task into the calendar writes a human-readable `HH:MM–HH:MM` range into that task line. Moving or resizing a block rewrites the range; removing a block removes only its time; completing from either side stays synchronized.
- The primary prototype scope is desktop/macOS and must keep `Today` and `Plan` interactions functional. Website-block rules remain task/calendar-aware and local-first.
- The production direction is a native macOS 14+ SwiftUI app in `MetridayMac/`; the React/Vite build remains a visual prototype and comparison reference, not the shipping runtime.
- Do not wrap the web prototype in a WebView. Use SwiftUI/AppKit, SF Symbols, local files in Application Support, and standard macOS drag/drop APIs.
- The first runnable webpage-blocking layer monitors the frontmost Safari or Chrome tab during focus and redirects matching domains to a local focus page. Treat a Network Extension content-filter target as a later hardened mode because it requires Apple-granted entitlements and signed distribution.
- Timing.app Professional is the primary functional benchmark. Aim for close behavioral parity with its core workflows first, then add Metriday improvements as deliberate, documented extensions without weakening the familiar baseline.
- Calendar integration is optional and read-only by default: EventKit events may appear on the Activities timeline and seed manual Time Entries only after the user grants Calendar access; all other local tracking remains usable without that permission.
- Any visual row that represents one navigation or selection action must expose the entire visible row as its hit target, including whitespace and trailing indicators; keep compact icon and trailing-action controls scoped to their own actions.
