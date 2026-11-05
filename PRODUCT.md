# Syllapace
<!-- impeccable:product-schema 1 -->
## Platform
Local macOS application with native SwiftUI/AppKit chrome and a bundled WebKit workspace. No Windows target.
## Stack
User-confirmed SwiftUI shell + WKWebView hosting React, Tailwind, shadcn, and MIT ReUI components. Swift services own persistence, files, Keychain, Canvas, model calls, EventKit, and Sparkle. Swift Package plus Vite build, Apple Silicon, macOS 26+. Node is a build dependency, not an application runtime.
## Users
Canvas-using students running their own local open-source client.
## Product Purpose
Turn selected-semester materials into an orderly set of class meetings, submission deadlines, and assessments. AI does the filtering and organization; routine valid results do not require manual approval.
## Operating Context
Users configure their Canvas token and BYOK model directly. Local storage and Keychain; no Syllapace backend. The main window offers List, Board, Gantt, and Calendar over one library; a native desktop card shows upcoming classes and deadlines. Automatic course-material organization is enabled by default once a model and key are configured, can incur provider charges, and can be disabled in Models settings. Importing with Use AI off persists a local-only choice that survives source refreshes; explicitly organizing that material does not opt it into future automatic uploads.
## Capabilities and Constraints
Canvas course/term selection and native source discovery; file/text/public-link import including PDF, DOCX, XLSX, and CSV; evidence-validated BYOK curation; bounded weekly class expansion; source-linked unresolved information; reversible reorganization; separate progress and urgency; personal work plans that do not move source deadlines. Academic calendars are an explicitly selected layer, not default course clutter. Manual edits/rejections, local EventKit ownership, and ICS export remain protected. Private Google authorization, OCR, complete Gradescope/Piazza ingestion, and WidgetKit rollout remain outside this release.
## Brand Commitments
Refined, clear, spacious Mac experience. Keep native window, sidebar, toolbar, menus, settings, and desktop interactions. Reuse ReUI components and their design system in the workspace; adapt real data and semantic tokens instead of redrawing the components. Borrow Still Today's desktop card interaction. Direct implementation and real bilingual light/dark window review are user-approved. The Codex, Slack, and Linear references guide the precise course-page/date logo; its explicit alignment and spacing geometry remains unchanged.
## Evidence on Hand
Proposal ZIP and conversation; docs/decisions/0001-apple-calendar-eventkit.md; docs/PLAN-0.4.0.md and docs/DESIGN-0.4.0.md. Demo data is synthetic and clearly labeled. Actual test results and live-integration limits belong in docs/ACCEPTANCE-0.4.0.md; a mock test or screenshot does not establish account-specific provider or Calendar behavior.
## Product Principles
Relevant events before volume; AI handles routine organization; explicit uncertainty without fabricated dates; one library across views; traceable evidence, reversible changes, user control, and offline resilience.
