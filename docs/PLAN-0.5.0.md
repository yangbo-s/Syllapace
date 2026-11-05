# 0.5.0 — Native workspace and trustworthy dates

GOAL-050: Make the semester workspace read as one Mac application, with reliable historical state and dates.

| Requirement / acceptance / tests | Observable result |
| --- | --- |
| REQ/AC/TC-0501 | Native sidebar exposes List, Timeline, Calendar; no board, duplicate semester heading/count, web tabs or All/Open/Soon/Done strip. Search and type filtering remain compact. |
| REQ/AC/TC-0502 | Settings changes system/light/dark appearance, accent and interface size across native and WebKit surfaces. SF typography, neutral surfaces and readable light/dark states at 940×620 and 1120×760. |
| REQ/AC/TC-0503 | List gives spare width to titles, keeps course codes compact, and retains sorting, date-derived status and source actions. |
| REQ/AC/TC-0504 | Calendar and timeline open in month view. Meetings/assessments are timeline points; deadlines span verified release to due; missing release never fabricates a duration. |
| REQ/AC/TC-0505 | All past events are historical; no overdue classification or warning exists. No completion controls or overdue states. Released events are active, future or unknown releases are upcoming; history is hidden by default. Submission/progress never changes schedule phase. Date-only civil dates remain stable across display timezones. |
| REQ/AC/TC-0506 | Practice exams do not become actual assessments. Existing generated practice records are reversibly excluded; source material and user edits remain. Midterm reports are deliverables, not exams. |
| REQ/AC/TC-0508 | Foreground feedback uses a brief native toolbar summary and an on-demand popover with full message/undo/stop. No persistent bottom notice or progress bar; no automatic intrusive popup. |
| REQ/AC/TC-0507 | Swift/web tests, offline real WebKit self-test, visual checks and release verification pass. Publish 0.5.0/build7 packages and signed feed; preserve the installed application and its preferences. |

ADR-050: Retain SwiftUI/AppKit shell and offline React workspace. Native navigation and appearance are authoritative; extend the snapshot with optional theme/date metadata for compatibility. Reuse installed controls, compose workspace views for academic semantics, add no dependency. Avoid replacing the app framework or guessing corrected dates.

MOD-0501: Native navigation/settings and theme projection. MOD-0502: Web layout and event projections. MOD-0503: Canvas/extraction/reconciliation date and classification boundaries.

IF-050: schema1 snapshot adds optional `theme`, `releasedAt`, `releaseDateOnly`. New archive fields are optional, preserving schema4 reads. Past dates display as history without judging whether a deadline was missed. Release is an explicit availability date, never file creation or import time. ISO instants include offsets; civil dates remain YYYY-MM-DD. Existing revision checks, finite bridge commands and local-only CSP remain authoritative. Persisted legacy `kanban` selection falls back to list.

CON-050: No real credential reads, no modification of the installed app or update preferences, no real account calls needed for fixtures. Original source dates remain recoverable. OOS-050: Backend replacement, account integration expansion, marketing imagery.

Order: reproduce date/classification defects → additive data contract + regression tests → impeccable navigation/theme/views → unslop spacing/color/icon/copy/type/layout/details/visual/motion pass → isolated validation and evidence score → signed public release.
