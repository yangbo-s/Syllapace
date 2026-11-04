# Syllapace
<!-- impeccable:product-schema 1 -->
## Platform
Native macOS, SwiftUI and AppKit. No Windows target.
## Stack
User-confirmed Swift native application; EventKit for Apple Calendar. Swift Package build, macOS 26+.
## Users
Canvas-using students running their own local open-source client.
## Product Purpose
Turn assignments and syllabus documents into a trustworthy academic timeline with evidence, review and change tracking.
## Operating Context
Users configure their Canvas token and BYOK model directly. Local storage and Keychain; no Syllapace backend. Main window for review, compact desktop card for daily use.
## Capabilities and Constraints
Canvas courses/assignments/syllabus/file discovery; PDF/DOCX/text import; optional BYOK structured extraction; manual review/edit; stable event identity; source changes preserve user decisions; EventKit dedicated local calendar and ICS export.
## Brand Commitments
Refined, spacious, beautiful native Mac interface. Borrow Still Today's desktop card interaction. Direct code-first design and real light/dark screenshots approved by user. The user references Codex, Slack and Linear for precision and simplicity, while asking for a recognizable course-and-schedule meaning. The current course-stack direction combines layered syllabus pages, an aligned date grid and a turning corner; geometry uses explicit shared dimensions and spacing. The application interface retains its study-desk direction.
## Evidence on Hand
Proposal ZIP and conversation; docs/decisions/0001-apple-calendar-eventkit.md. No real credentials or course documents supplied. Demo data must be synthetic and clearly labeled.
## Product Principles
Traceable evidence, explicit uncertainty, user control, offline resilience.
