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

The left product navigation and top date/focus controls remain visible in every section. The top previous/next/Today controls and every day in Plan's mini month calendar switch the active daily note. Selecting a missing date creates a blank `YYYY-MM-DD.md` with `Focus` and `Notes` sections; existing days reopen without being rewritten.

## Time Blocks

- Drag a Markdown task into the Timeline to choose between a Time Block and the future Event behavior.
- Hold `⌘` while dropping to create a Time Block immediately.
- `⌥` + drop is reserved for Calendar Events and is intentionally not implemented yet.
- Drag the block body to move it; drag the top edge to change its start; drag the bottom edge to change its end.
- Time Blocks only rewrite Markdown (for example, `- [ ] 13:00 - 14:30 Email`) and do not request Calendar access or create external events.

The left pane is a native continuous Markdown editor with NotePlan-style live preview. Inactive lines render as headings, bold/italic text, quotes, lists, links, inline code, and clickable task checkboxes instead of exposing source delimiters; the active line reveals only the Markdown syntax needed for editing. Return continues task, bullet, and numbered-list prefixes. The file is still saved exactly as plain Markdown, task lines expose a six-dot gutter handle as soon as they match `- [ ] Task`, and calendar actions only rewrite the corresponding task line.

## Website blocking MVP

While a focus session is active, Metriday can inspect the frontmost Safari or Chrome tab through macOS Automation and redirect blocklisted domains to a local focus page. The app asks for Automation permission when this feature is first used.

A system-wide Network Extension content filter is intentionally not bundled in this local build because Apple requires a restricted entitlement and signed app-extension distribution.
