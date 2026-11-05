# Desktop

Mode: Operate. User task: discover deadlines, understand the selected semester, and verify source evidence.

## Direction and authority

The Quiet Library Study Desk remains the incumbent world, concept `seed:7b4975d51b65fec9`: quiet, exact and compact; SF typography; semantic neutral layers; restrained default teal; course color on data. Native macOS 26+ chrome and installed workspace components remain authoritative. The 0.5.1 changes extend the approved code-led system revision, with no new visual world or separate approved comp. No imagery or decorative motion is required.

## Current workspace

The native sidebar owns separate List, Timeline and Calendar destinations, semester selection and course filtering. Sources and a nonempty review queue remain native destinations. The first viewport contains one title context, compact History / 历史, search and type tools and the selected data view; it has no duplicate heading/count, web view tabs, Board, status strip or seven-day ribbon.

List gives spare width to event titles; title/course/date/status/actions begin at 240/120/160/96/40 logical pixels. Rows retain sorting without column resize handles or pinned columns. The leading date-range select offers All dates / This week & next; the trailing controls remain compact. A native overflow viewport holds the rows above a non-scrolling footer with 20/50/100/all grouped rows per page, counts and page navigation. A repeated class occupies one row with a date-count control opening its individual dates; selecting a date opens the native editor. Grouping only changes the presentation and preserves source records and user edits.

Timeline opens to a full month fitted to the viewport with a course/event tree, point classes and assessments, and explicit-release-to-due deadline spans. Repeated classes share a track with one point per occurrence. Native horizontal scrolling and background panning reach adjacent dates while event movement and resizing remain disabled. Window resizing maintains full-month framing until the user scrolls or pans, then preserves the date at the viewport center. Missing release is unknown, and legacy personal plans cannot create a duration. Calendar opens in month view. All views use date-derived phase and initially hide historical events; no completion or overdue UI is present.

Main initial size is 1120 × 760; minimum content is 940 × 620 before scale. Shared main content sizing is 90%, 100% or 115%, including native and embedded WebKit content; Settings is 640 × 560 before that scale. Follow system / Light / Dark and custom accent changes affect both renderers. Semantic colors and contrast-adjusted custom accent variants are defined by AppAppearance.swift, not by screenshot samples.

Routine feedback occupies toolbar Activity, not schedule height. Notices show a single-line summary for six seconds before becoming an information icon; curation retains progress and its summary. A click opens the native details popover with selectable text, Stop or available undo/dismissal actions. It never auto-opens; blocking errors retain native alerts, and foreground work does not send system notifications.

## Evidence and limits

Implementation and acceptance scope: [PLAN-0.5.0](../../docs/PLAN-0.5.0.md) and [PLAN-0.5.1](../../docs/PLAN-0.5.1.md). The current extension is grounded in `Web/src/workspace/ListView.tsx`, `Web/src/workspace/GanttView.tsx`, `Web/src/workspace/schedule.ts`, `Web/src/App.tsx`, `Web/src/index.css` and the viewport anchoring in `Web/src/components/reui/gantt/gantt-view.tsx`. Source-text caching, persisted curation failures, compatible legacy fingerprints, Canvas syllabus reading and bounded local weekly-schedule generation are product behavior documented in PRODUCT.md; they do not add a new visual language.

Previous workspace originals: `build/verification/0.5.0/review-fix/{en,zh-Hans}`. Previous appearance and scale originals: `build/verification/0.5.0/appearance-verified/{en,zh-Hans}`. The 0.5.1 round-two originals are in `.impeccable/review/0.5.1-round2/{en,zh-Hans}` (48 images). Its 12 timeline originals were replaced with the corrected captures from `.impeccable/review/0.5.1-gantt-fix/{en,zh-Hans}`; the other 36 originals remain from round two. File comparison confirms that the corrected timeline copies match. Independent final visual review resolved FF-051-01 with a ship disposition; the report is `build/verification/0.5.1/finish-review.md`. These locations are review evidence, not an approved design comp or a claim of live provider integration. Final review and recapture status belong in the release acceptance record.

This surface brief documents the main application workspace. The existing compact desktop-card specification in DESIGN.md and its sidecar was not reconciled in this revision; its separate size and behavior drift must be reviewed independently. Portable specimens do not replace actual bilingual light/dark window review.
