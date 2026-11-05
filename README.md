# Syllapace

**English** | [简体中文](README.zh-CN.md)

A native macOS semester planner for Canvas courses, class schedules, assignments, and projects, with local storage, a desktop card, and Apple Calendar sync.

Syllapace runs on your Mac. Connect your own Canvas account, choose the semester and courses you want to see, and review dates alongside their source text. Bring your own model API key for optional extraction, and keep confirmed events in Apple Calendar. A compact desktop card puts upcoming work within reach.

This is an early release. See [acceptance evidence](docs/ACCEPTANCE.md) for automated checks, live integration results, and remaining verification limits.

## Install

Download the **DMG** from [GitHub Releases](https://github.com/yangbo-s/Syllapace/releases), drag Syllapace to Applications, and open it there. Syllapace supports **Apple Silicon and macOS 26+**. A ZIP and SHA-256 checksums are also provided.

The package is ad hoc signed and **not notarized by Apple**. If macOS blocks the first launch, use [Apple's per-app opening instructions](https://support.apple.com/en-us/102445) after checking the source and checksum; see the [release notes](docs/releases/0.2.0.md). An update signature protects subsequent downloads, but does not replace Apple notarization.

## Language and updates

Open **Settings → General** to choose **Follow system**, **English**, or **简体中文**. The app interface changes immediately and remembers the preference. Native system menus and Sparkle update windows adopt the language after reopening. Canvas, OpenAI, API, PDF, DOCX, ICS and other product/protocol names retain their spelling. Course names and original evidence are never translated; changing the interface language does not expand the document parser's language support.

Choose **Syllapace → Check for Updates…** or use the button in General settings. Sparkle checks the GitHub-hosted feed, verifies update archives with the public key embedded in the app, and installs after confirmation. Automatic checks are enabled by default, roughly every 24 hours while the app is running, and can be turned off in General. Publishing a release does not immediately push it to running clients. Update checks send no course content or credentials; system profile submission is disabled.

## Build and run

Requirements:

- macOS 26 or later.
- Xcode 26 or later with a Swift 6.2+ toolchain and Apple asset compilation tools. Command Line Tools alone may select an older Swift version.
- Swift Package Manager downloads the pinned Sparkle 2.10.1 dependency. No hosted Syllapace service is required.

From the repository root:

```sh
./build.sh --open
```

The script creates `build/Syllapace.app`, embeds Sparkle and localization resources, compiles the icon, and signs the bundle ad hoc by default. Use `./build.sh --debug --open` for a faster development build. It defaults to the toolchain in `/Applications/Xcode.app`; set `DEVELOPER_DIR` if Xcode is installed elsewhere. Set `SIGN_IDENTITY` to a suitable local signing identity if desired. This build is not notarized. See [release maintenance](docs/RELEASING.md) for archive signing, packaging and publishing. Fork maintainers must use their own feed and update-signing key.

To inspect the interface with fictional courses and deadlines:

```sh
./tools/demo.sh
```

Demo events are generated in memory and are not saved to your real library. Canvas, model extraction, EventKit access and update checks are disabled in demo mode. Quit the demo and open the app normally to configure your own workspace.

## Start with a syllabus

1. Choose **File → Import Syllabus…** (`⌘O`). Choose the course and academic year before importing.
2. Import a text-based PDF, DOCX, UTF-8 TXT, Markdown, or HTML file. [`fixtures/syllabus.md`](fixtures/syllabus.md) is a synthetic example.
3. Open **Review**. Inspect the evidence, edit unresolved dates, then approve or reject each candidate.
4. Confirmed events appear in **Today** and **Timeline**. Search by event or course, filter by course or event type, and mark work complete.
5. Use **Sources** to inspect imported text or explicitly request model extraction.

Rules preserve date-only events and leave ambiguous dates unresolved. A sentence containing multiple dates is not assumed to identify the deadline correctly. The academic year is supplied by the import setting. Source changes produce reviewable conflicts instead of silently replacing an approved date or user edit.

## Connect Canvas

1. Open **Settings → Canvas** and enter your institution's Canvas address, such as `https://canvas.example.edu`. Use the origin only, without a course path, query parameters, or credentials in the URL.
2. Paste your own access token and choose **Save connection**, then **Sync now**. Saving checks the input format; the first sync verifies access and discovers course and semester metadata.
3. Choose a semester, check the courses you want, and select **Save & sync**. Course content is fetched only after this selection. Portal and other course spaces without a named semester are optional.
4. Change the selection through the semester menu in the sidebar or **Settings → Canvas → Manage courses…**.

The selected courses determine what appears in Today, Timeline, Review, Sources, search, and the desktop card, as well as new EventKit writes and ICS exports. Switching semesters keeps historical data and previously exported Calendar events. Personal and manually imported courses remain available. Upgrading an existing library asks you to choose a Canvas scope before resuming content sync.

Keep the saved address spelling consistent: credentials are stored in macOS Keychain under the configured address. Changing the address requires saving a token for that address. Leave the token field blank to retain the saved credential for the current address. Keychain authorization runs asynchronously so the app can remain responsive while macOS asks for access.

For selected courses, the connector reads Assignments and submission/grade state, course Calendar events, inline syllabus HTML, Announcements, Modules, the front page, and referenced Pages and attachments. Classic Quizzes and quiz-linked Assignments are associated by Canvas IDs to avoid duplicate items; New Quizzes coverage uses the information available through Canvas Assignments. Class sessions, assignments, projects, quizzes, exams, and presentations have separate event types. Timed events retain an explicit end time and location when supplied. Grades and submission states remain attached to the task.

**Sources** preserves text and links from course materials. Referenced attachments and likely syllabus/schedule files can be imported explicitly. A hidden or inaccessible Files directory does not prevent other accessible sources from syncing; individual attachments still require permission.

For an external schedule link, use **Import link** to read a public document or Google Sheets export. These requests use no Canvas token or browser cookies. If a source requires a separate sign-in, its link remains available to open in a browser; you can also import an exported file. Private Google authorization and complete Gradescope/Piazza connectors are not included. Gradescope-linked work is limited to the dates and grades actually available in Canvas; individual extensions may remain solely in Gradescope.

**Refresh every 10 minutes while running** is opt-in. The app must remain running to fetch changes. Partial failures preserve existing data and report the affected resources. Unchanged source content is skipped during background refresh, without moving the current view. Attachments and external documents are imported on request, rather than downloaded again on each refresh.

**Renew token automatically** is enabled by default in Canvas settings. While the app is open, it checks the saved personal token and requests an expiry extension near the end of its lifetime, when the institution permits it. This is an active expiry-extension request, not OAuth refresh or automatic renewal from token usage. The renewal period is no longer than the first observed lifetime and is capped at 30 days; the token value and permissions remain unchanged. Version 0.2.0 accepts more server token-mask formats and distinguishes an identification failure from a rejected or unconfirmed extension. Successful metadata retrieval alone does not prove renewal is allowed. You can switch renewal off. If the app stays closed until expiry, or Canvas refuses renewal, generate a replacement in Canvas and save it in Settings. Course sync and saved data do not depend on renewal succeeding.

## Use your own model

Open **Settings → Extraction** and supply:

- An HTTPS API base URL, for example `https://provider.example/v1`.
- The provider's exact model identifier.
- Your API key.

The adapter uses an OpenAI-compatible **chat completions** endpoint. It appends `/chat/completions` to a supplied base path unless already present. The provider must support JSON response format. Recognized reasoning models use `max_completion_tokens` without `temperature`; older and other models retain the legacy token-limit parameters. A definite unsupported-parameter response may trigger one compatibility retry. Failed generations, authentication errors, rate limits, and network errors are not automatically retried. Compatibility with every provider or model is not guaranteed. HTTP endpoints, including ordinary local HTTP model servers, are not supported by this adapter.

Choose **Extract** for an individual source to send that document's text directly to the configured provider. Extraction is never automatic. The key is stored in Keychain and scoped to the configured endpoint. The document request contains no Canvas token and gives the model no tools. Responses are schema-checked, matched to actual evidence excerpts, and always enter Review. Matching an excerpt does not establish that a model interpreted the date correctly: inspect candidates before confirming them. Provider usage may incur charges under your own account.

## Apple Calendar

Open **Settings → Calendar → Connect & sync calendar**. Syllapace requests full calendar access so it can find and update its previously written events and detect external edits. Its implementation operates only on its dedicated `Syllapace` calendar and owned events.

The current implementation uses a local **On My Mac** calendar only. If the local source is unavailable, first choose **File → New Calendar → On My Mac** in Apple Calendar, then reconnect. It does not silently create an iCloud calendar or host a subscription URL.

- Only approved events within the selected course scope, with valid dates and time zones, are published. Explicit end times are preserved.
- Repeated syncs reuse event mappings. Confirmed date changes update the existing event.
- External edits or deletions are reported as conflicts. **Use Syllapace version** requires an explicit confirmation before replacing an edit or recreating a deleted event. There is no automatic reverse import of Calendar edits into Syllapace.
- Rejecting a previously published event in the current scope can remove its owned Calendar counterpart, provided it has not been changed externally. Missing sources, failed fetches, and switching semesters do not imply deletion.
- **Sync confirmed changes automatically** is opt-in and runs while the application is open. Already saved events remain in Calendar when Syllapace quits.

Portable `.ics` export is also available from the File menu (`⇧⌘E`) or Calendar settings. Export is a snapshot, not live synchronization; repeated manual imports may be duplicated by the receiving client despite stable UIDs.

## Desktop card and shortcuts

Show the desktop card with `⇧⌘D` or the menu bar item. Drag the card by its background, toggle the pin to keep it above other windows, and click an event to open the timeline. This is an AppKit panel, not a WidgetKit extension.

| Action | Shortcut |
| --- | --- |
| New event | `⌘N` |
| Import syllabus | `⌘O` |
| Sync Canvas | `⌘R` |
| Export ICS | `⇧⌘E` |
| Show desktop card | `⇧⌘D` |
| Settings | `⌘,` |

## Data and privacy

The library is an atomically written JSON archive at `~/Library/Application Support/Syllapace/archive.json`. `archive.json.backup` retains the previous readable archive. Version 0.2.0 reads existing schema-1 libraries and writes schema 2 on the next successful save, backing up the previous file first. Older app versions cannot read schema 2. EventKit bindings are stored separately in `calendar-mapping.json` alongside it. Credentials are in Keychain; connection addresses and nonsecret preferences use UserDefaults.

Imported text and evidence are stored locally without additional application-level encryption. Original local documents remain where you selected them. Downloaded temporary files are cleaned up after ingestion. No Syllapace account, telemetry service, or backend is required. A model request sends the selected source text to the provider you configured.

Set `APP_STORE` to an alternate archive path for isolated development runs. If the archive is corrupt or has an unknown schema, the app reports it and refuses to overwrite it. Back up the application-support directory before manually restoring files; a calendar mapping should not be discarded casually, because it preserves event ownership and duplicate prevention.

## Verification

Build before running application-level scripts:

```sh
./tools/test.sh        # Swift Testing: domain, documents, connectors, calendar sync planner
./tools/selftest.sh    # Application import/review/change/persistence flow in a temporary store
./tools/snap.sh        # Light/dark application captures with synthetic data
./tools/grid-lint.sh   # SwiftUI spacing checks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift tools/check-layout.swift .impeccable/review/*-layout.json
```

Snapshots and actual-window layout measurements are written to `.impeccable/review/`. Set `APP_LAYOUT_ONLY=1` when running `tools/snap.sh` to refresh measurements without replacing screenshots. Native Settings forms use system layout and are not probed; the checker measures the custom content, inspector, import/editor sheets and desktop card. The snapshot runner captures the app's own windows. Screen Recording permission may be required for faithful window captures; a logged `view-render fallback` does not verify native materials or active window chrome.

The tests use synthetic PDFs/DOCX documents, mocked network responses, and calendar snapshots. They do not request real credentials or write to your actual calendars. See [engineering requirements](docs/ENGINEERING.md), [EventKit decision](docs/decisions/0001-apple-calendar-eventkit.md), and [acceptance evidence](docs/ACCEPTANCE.md).

## Current limits

- Import limits: 20 MB per document, 150 PDF pages, and 2 MB extracted text. Scanned/image-only PDFs need OCR elsewhere first. Complex PDF layouts can lose reading order; DOCX parsing preserves basic row/cell associations rather than visual layout.
- Model extraction accepts up to 64,000 Swift string characters of source text and up to 300 returned candidates. It is optional and requires a compatible HTTPS provider.
- File discovery follows accessible course references and syllabus/schedule-style filenames. Files and public external links are explicitly imported; previously downloaded documents are not automatically re-downloaded on every Canvas refresh. Import a revised source again to review its changes.
- Canvas access depends on course configuration and your account permissions. Private Google Sheets, Piazza posts, complete Gradescope content, and New Quizzes question content are outside the current connector coverage.
- Recurring timetable expansion and academic holiday exceptions are not supported; add or review individual class meetings explicitly.
- Rule extraction is conservative, primarily for English academic event wording and explicit dates. It is not a complete multilingual date parser.
- Similar cross-source titles are flagged for review; the app does not prove two differently named milestones are the same event.
- The app has no unattended background agent, OAuth setup, OCR, Windows build, or other-LMS integration.
- Runtime permission flows, account-specific Canvas permissions, provider compatibility, and real Calendar synchronization still require user-configured live checks.

## Logo

The course-page and date mark is available as transparent [SVG files](Brand/README.md) in two-color, teal, near-black, and white versions. Its [construction diagram](Brand/concepts-v2/alignment.png) records the alignment grid. The native app icon uses the same paths in `Icon/AppIcon.icon`; macOS supplies its material and appearance variants.

## Project layout

`Sources/SyllapaceKit/` contains domain models, persistence, parsing, reconciliation, connectors, ICS export, and the pure calendar synchronization planner. `Sources/Syllapace/` contains SwiftUI views, application state, the desktop panel, and the EventKit adapter. `Tests/SyllapaceKitTests/` exercises the core boundaries with synthetic fixtures.

The desktop interaction takes inspiration from [Still Today](https://github.com/OyangDer/still-today). This is a new native Swift implementation; it does not embed the upstream Svelte/Tauri interface.
