# 0.4.0 — Curated academic workspace

User approved SwiftUI shell + bundled React/ReUI on 2026-11-04. Scope is the central workspace and academic event pipeline. Native settings, import, desktop panel, Keychain, Canvas, EventKit and Sparkle remain native.

## Goal and contract

GOAL-040: Students see actionable, consistently organized events for their selected semester without manually approving routine AI results.

| Requirement | Observable acceptance | Verification |
| --- | --- | --- |
| REQ-0401 / AC-0401 | Rubrics, learning objectives and generic announcements produce zero schedule entries; only meetings, submission deadlines and assessments enter the main workspace | TC-0401 extraction/curation regression fixtures |
| REQ-0402 / AC-0402 | Validated AI results enter automatically; explicit recurring meetings expand only inside known course/term bounds; unknown/contradictory facts do not become fabricated events | TC-0402 structured evidence, dates, recurrence and cancellation tests |
| REQ-0403 / AC-0403 | Source changes are curated automatically with cached results; existing generated clutter is reorganized reversibly without losing user edits/rejections/completion | TC-0403 reconciliation/migration/undo tests + app self-test |
| REQ-0404 / AC-0404 | List, Kanban, Gantt and Calendar share event IDs, course filters, progress and dates; progress changes survive reload | TC-0404 frontend contracts + native bridge self-test |
| REQ-0405 / AC-0405 | Due-soon/overdue are derived independently of todo/doing/done; Gantt milestones do not fabricate duration or alter source deadlines | TC-0405 frontend/date/planning tests |
| REQ-0406 / AC-0406 | English/Chinese and light/dark render in a real active macOS window; sidebar, menus, settings and desktop card remain native | TC-0406 screenshots and keyboard/window checks |
| REQ-0407 / AC-0407 | Static web assets ship in the signed app, run offline, and cannot read credentials or navigate remote pages into the native bridge | TC-0407 bridge/parser/build/package verification |
| REQ-0408 / AC-0408 | Version/build, Git tag, public DMG/ZIP and signed latest feed match; installed user app remains untouched | TC-0408 public re-download/signature/installed fingerprint verification |

## Architecture decision ADR-040

Pure SwiftUI would require rebuilding ReUI's interactions and cannot consume its React components. A full web rewrite would duplicate working native services. Adopt only a bundled WKWebView workspace: SwiftUI chrome -> typed snapshot/command bridge -> React/ReUI rendering. Swift remains the only persistent authority. MIT ReUI primitives/examples are used; paid template source is excluded from the public repository.

MOD-0401: SyllapaceKit curation and event model. Input bounded source text + selected course and explicit term bounds; output validated three-category events, exclusion/issue metadata and stable identities. Model data is untrusted. No model confidence score substitutes for source evidence.

MOD-0402: Native curation scheduler. Only changed source/policy/model/term context is processed. Stale responses cannot commit after account, model or scope changes. Failures retain source documents and are retryable, without restoring keyword-generated junk.

MOD-0403: Web workspace. Controlled ReUI components, localized semantic tokens, one central content surface. All-day dates preserve YYYY-MM-DD; timed events retain offset and IANA zone. Academic calendar dates are a separate opt-in layer.

IF-0401: schemaVersion=1 workspace snapshots and typed request/reply commands. Mutations include event ID and expected revision, validated natively; errors roll back visible edits. Web receives no Canvas token, model key, filesystem path or arbitrary native execution interface. External links open through validated native actions.

MOD-0404: Packaging and release. Vite output copied into app Resources before codesigning; no local server/Node runtime dependency. Existing update identity preserved.

## Boundaries and implementation order

1. Model/curation contracts and regression tests.
2. Native automatic curation, reversible reorganization and persistence.
3. Bundled web workspace + limited command bridge.
4. Integration, meaningful tests, actual light/dark bilingual window verification.
5. Versioned release and public verification.

No Windows, WidgetKit signing rollout, remote backend, arbitrary AI tools, or rewriting settings/desktop cards. Original user installation and update preferences must not be changed.

## Evidence score

Release evidence is recorded in [ACCEPTANCE-0.4.0.md](ACCEPTANCE-0.4.0.md): 197 Swift tests, 22 Web tests, 63 isolated app checks, a live synthetic model call, and real bilingual light/dark window review. Public asset re-download, signatures, the latest feed, and unchanged installed-app fingerprints passed. The final evidence score is 94/100; the record distinguishes these checks from the user's still-unperformed local upgrade.
