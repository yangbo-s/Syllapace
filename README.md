# Syllapace

A native Mac workspace for assignments, syllabus deadlines, and the changes that happen during a semester.

Syllapace runs on your Mac. Connect your own Canvas account, optionally configure your own model API key, review extracted dates with their source text, and keep confirmed events in Apple Calendar. A compact desktop card puts upcoming work within reach.

This is an early implementation. Automated tests and local application checks are available; a real Canvas account, model provider, and authorized Apple Calendar connection have not yet been exercised in this development run. See [acceptance evidence](docs/ACCEPTANCE.md) for the exact verification status.

## Build and run

Requirements:

- macOS 26 or later.
- Xcode 26 or later with a Swift 6.2+ toolchain and Apple asset compilation tools. Command Line Tools alone may select an older Swift version.
- No third-party package dependencies or hosted Syllapace service.

From the repository root:

```sh
./build.sh --open
```

The script creates `build/Syllapace.app`, compiles the icon, and signs the bundle ad hoc by default. Use `./build.sh --debug --open` for a faster development build. It defaults to the toolchain in `/Applications/Xcode.app`; set `DEVELOPER_DIR` if Xcode is installed elsewhere. Set `SIGN_IDENTITY` to a suitable local signing identity if desired. This build is not a notarized distribution release.

To inspect the interface with fictional courses and deadlines:

```sh
./tools/demo.sh
```

Demo events are generated in memory and are not saved to your real library. Canvas, model extraction, and EventKit access are disabled in demo mode. Quit the demo and open the app normally to configure your own workspace.

## Start with a syllabus

1. Choose **File → Import Syllabus…** (`⌘O`). Choose the course and academic year before importing.
2. Import a text-based PDF, DOCX, UTF-8 TXT, Markdown, or HTML file. [`fixtures/syllabus.md`](fixtures/syllabus.md) is a synthetic example.
3. Open **Review**. Inspect the evidence, edit unresolved dates, then approve or reject each candidate.
4. Confirmed events appear in **Today** and **Timeline**. Search by event or course, filter by course, and mark work complete.
5. Use **Sources** to inspect imported text or explicitly request model extraction.

Rules preserve date-only events and leave ambiguous dates unresolved. A sentence containing multiple dates is not assumed to identify the deadline correctly. The academic year is supplied by the import setting. Source changes produce reviewable conflicts instead of silently replacing an approved date or user edit.

## Connect Canvas

Open **Settings → Canvas**:

- Enter your institution's Canvas address, such as `https://canvas.example.edu`. Use the origin only, without a course path, query parameters, or credentials in the URL.
- Paste your own access token and choose **Save connection**, then **Sync now**. Saving checks the input format; syncing verifies access against Canvas.
- Keep the saved address spelling consistent. Credentials are stored in macOS Keychain under the configured address. Changing the address requires saving a token for that address; a token is not automatically transferred to another endpoint.
- Leave the token field blank to retain the saved credential for the current address.

The connector reads active courses, assignments and submission state, course calendar events, syllabus HTML, and accessible file metadata. Likely syllabus/schedule documents appear in **Sources** and are downloaded when selected. It does not crawl every course attachment or modify Canvas.

**Refresh every 10 minutes while running** is opt-in. The app must remain running to fetch changes. Partial failures preserve existing data; the sync message identifies failed course resources. An expired token can be replaced in Settings. Unchanged syllabus hashes are skipped during background refresh, without moving the current view.

## Use your own model

Open **Settings → Extraction** and supply:

- An HTTPS API base URL, for example `https://provider.example/v1`.
- The provider's exact model identifier.
- Your API key.

The adapter uses an OpenAI-compatible **chat completions** endpoint. It appends `/chat/completions` to a supplied base path unless already present. The provider must accept JSON response format, `temperature`, and `max_tokens`; compatibility with every provider or model is not guaranteed. HTTP endpoints, including ordinary local HTTP model servers, are not supported by this adapter.

Choose **Extract** for an individual source to send that document's text directly to the configured provider. Extraction is never automatic. The key is stored in Keychain and scoped to the configured endpoint. The document request contains no Canvas token and gives the model no tools. Responses are schema-checked, matched to actual evidence excerpts, and always enter Review. Matching an excerpt does not establish that a model interpreted the date correctly: inspect candidates before confirming them. Provider usage may incur charges under your own account.

## Apple Calendar

Open **Settings → Calendar → Connect & sync calendar**. Syllapace requests full calendar access so it can find and update its previously written events and detect external edits. Its implementation operates only on its dedicated `Syllapace` calendar and owned events.

The current implementation uses a local **On My Mac** calendar only. If the local source is unavailable, first choose **File → New Calendar → On My Mac** in Apple Calendar, then reconnect. It does not silently create an iCloud calendar or host a subscription URL.

- Only approved events with valid dates and time zones are published.
- Repeated syncs reuse event mappings. Confirmed date changes update the existing event.
- External edits or deletions are reported as conflicts. **Use Syllapace version** requires an explicit confirmation before replacing an edit or recreating a deleted event. There is no automatic reverse import of Calendar edits into Syllapace.
- Rejecting a previously published event can remove its owned Calendar counterpart, provided it has not been changed externally. Missing sources or failed fetches do not imply deletion.
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

The library is an atomically written JSON archive at `~/Library/Application Support/Syllapace/archive.json`. `archive.json.backup` retains the previous readable archive. EventKit bindings are stored separately in `calendar-mapping.json` alongside it. Credentials are in Keychain; connection addresses and nonsecret preferences use UserDefaults.

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
- File discovery is based on syllabus/schedule-style names. Files are explicitly imported; previously downloaded PDFs/DOCX files are not automatically re-downloaded on every Canvas refresh. Import a revised file again to review its changes.
- Rule extraction is conservative, primarily for English academic event wording and explicit dates. It is not a complete multilingual date parser.
- Similar cross-source titles are flagged for review; the app does not prove two differently named milestones are the same event.
- The app has no unattended background agent, OAuth setup, OCR, Windows build, or other-LMS integration.
- Runtime permission flows, account-specific Canvas permissions, provider compatibility, and real Calendar synchronization still require user-configured live checks.

## Logo

The course-page and date mark is available as transparent [SVG files](Brand/README.md) in two-color, teal, near-black, and white versions. Its [construction diagram](Brand/concepts-v2/alignment.png) records the alignment grid. The native app icon uses the same paths in `Icon/AppIcon.icon`; macOS supplies its material and appearance variants.

## Project layout

`Sources/SyllapaceKit/` contains domain models, persistence, parsing, reconciliation, connectors, ICS export, and the pure calendar synchronization planner. `Sources/Syllapace/` contains SwiftUI views, application state, the desktop panel, and the EventKit adapter. `Tests/SyllapaceKitTests/` exercises the core boundaries with synthetic fixtures.

The desktop interaction takes inspiration from [Still Today](https://github.com/OyangDer/still-today). This is a new native Swift implementation; it does not embed the upstream Svelte/Tauri interface.
