# Syllapace

**English** | [简体中文](README.zh-CN.md)

A local macOS semester planner that turns Canvas courses and your materials into organized classes, deadlines, and exams. Bring your own AI key and work across List, Timeline, and Calendar views.

Connect your own Canvas account and choose the semester and courses you want. AI filters irrelevant prose, organizes supported dates, and adds them automatically; source evidence stays available. A native SwiftUI shell hosts a bundled React/ReUI workspace in WebKit, while Swift handles storage, credentials, integrations, and the desktop card. There is no Syllapace server.

This is an early release. See [acceptance evidence](docs/ACCEPTANCE-0.5.0.md) for automated checks, live integration results, and remaining verification limits.

## Install

Download the **DMG** from [GitHub Releases](https://github.com/yangbo-s/Syllapace/releases), drag Syllapace to Applications, and open it there. Syllapace supports **Apple Silicon and macOS 26+**. A ZIP and SHA-256 checksums are also provided.

The package is ad hoc signed and **not notarized by Apple**. If macOS blocks the first launch, use [Apple's per-app opening instructions](https://support.apple.com/en-us/102445) after checking the source and checksum; see the [release notes](docs/releases/0.5.0.md). An update signature protects subsequent downloads, but does not replace Apple notarization.

## Language and updates

Open **Settings → General** to choose **Follow system**, **English**, or **简体中文**. The app interface changes immediately and remembers the preference. Native system menus and Sparkle update windows adopt the language after reopening. Canvas, OpenAI, API, PDF, DOCX, ICS and other product/protocol names retain their spelling. Course names and original evidence are never translated; changing the interface language does not expand the document parser's language support.

Choose **Syllapace → Check for Updates…** or use the button in General settings. Sparkle checks the GitHub-hosted feed, verifies update archives with the public key embedded in the app, and installs after confirmation. Automatic checks are enabled by default, roughly every 24 hours while the app is running, and can be turned off in General. Publishing a release does not immediately push it to running clients. Update checks send no course content or credentials; system profile submission is disabled.

## Build and run

Requirements:

- macOS 26 or later.
- Xcode 26 or later with a Swift 6.2+ toolchain and Apple asset compilation tools. Command Line Tools alone may select an older Swift version.
- Node.js 22.13+ LTS or 24+, and npm for building the bundled workspace. The build runs `npm ci` when dependencies or the lockfile change, then compiles React, TypeScript, and Tailwind.
- Swift Package Manager downloads the pinned Sparkle 2.10.1 dependency. The installed app needs neither Node.js nor a local web server.

From the repository root:

```sh
./build.sh --open
```

The script creates `build/Syllapace.app`, embeds the static workspace, Sparkle, localizations, and third-party notices, compiles the icon, and signs the bundle ad hoc by default. It does not install over your existing copy. Use `./build.sh --debug --open` for a faster development build. It defaults to the toolchain in `/Applications/Xcode.app`; set `DEVELOPER_DIR` if Xcode is installed elsewhere. Set `SIGN_IDENTITY` to a suitable local signing identity if desired. This build is not notarized. See [release maintenance](docs/RELEASING.md) for archive signing, packaging and publishing. Fork maintainers must use their own feed and update-signing key.

To inspect the interface with fictional courses and deadlines:

```sh
./tools/demo.sh
```

Demo events are generated in memory and are not saved to your real library. Canvas, model extraction, EventKit access and update checks are disabled in demo mode. Quit the demo and open the app normally to configure your own workspace.

## One workspace, three views

The default course workspace admits three categories: **class meetings**, **submission deadlines**, and **exams/quizzes**. Lecture, Recitation, Lab, recurring Demo, Homework, Project, Midterm, and Final retain their specific meaning. Grading rubrics, learning objectives, grade announcements, and general prose remain source material rather than calendar events.

| View | Purpose |
| --- | --- |
| List | Scan, sort and filter events; course codes stay compact while titles get the available width. |
| Timeline | Opens to a full month. Classes and assessments are points; tasks span an explicit release date to their due date. Without a release date, a task remains a point. |
| Calendar | Opens to the month; week, day and agenda are also available. |

The three views are separate native sidebar destinations and share one library. Status follows dates: **Not started**, **In progress**, then **Historical**. History is hidden by default; use the history button to include it. Unknown release dates are never guessed. Submission or saved completion flags do not determine schedule status. School calendars remain a separate sidebar layer.

Settings → Appearance offers System, Light or Dark, a custom accent, and 90%, 100% or 115% interface size. Native content and the embedded workspace share the same colors and scale. Practice assessments remain source material instead of becoming formal exams.

The former mandatory Review queue is now **Needs information**: only missing facts, failed organization, or source changes overlapping your edits need attention. A successful AI result enters the workspace without a per-event approval step.

## Add documents, text, or links

1. Choose **File → Add Material…** (`⌘O`). Add up to ten files, paste text, or enter a public link.
2. Choose the course or academic calendar, year, and time zone. You can create a local course in the same sheet.
3. Enable **Use AI** to organize with your selected provider and optional instructions, such as “Only deadlines for Fall 2026.” Leave it off for conservative local extraction; that material stays excluded from automatic model requests, including after a source refresh.
4. Choose **Organize & add**. Supported, relevant events are added automatically. Partial failures keep the material and results in the sheet so you can retry or keep the successful portion; you do not need to approve every date.
5. Use **Undo import** to undo the last committed import while preserving later edits. Existing Calendar edits remain protected by the usual conflict checks.

Supported files include text-based PDF, DOCX, XLSX, CSV, UTF-8 TXT, Markdown, and HTML. XLSX import reads cell values, shared strings, sheets, date serials, and stored formula results; it never calculates formulas or follows spreadsheet links. Scanned PDFs still require OCR elsewhere. [`fixtures/syllabus.md`](fixtures/syllabus.md) is a synthetic example.

Public pages, PDF links, and public Google Sheets can be read without a browser session. For a private page or spreadsheet, paste the relevant text or import an exported file. Unknown dates remain source-linked issues rather than invented calendar entries.

Use **Sources → Organize** to run the selected model again on a saved course source. Automatic organization also processes changed course materials while enabled. Reorganization preserves manual edits and rejections, reconciles matching observations, and offers **Undo reorganization** for the latest batch in the current session. Evidence-supported source changes can update machine-managed events; changes that overlap your edits need resolution.

## Connect Canvas

1. Open **Settings → Canvas → Find your school…** to search Instructure’s public school directory, or enter your Canvas address directly, such as `https://canvas.example.edu`. The lookup sends only the school-name query, without a Canvas token. Use the origin only, without a course path, query parameters, or credentials in the URL.
2. Paste your own access token and choose **Save connection**, then **Sync now**. Saving checks the input format; the first sync verifies access and discovers course and semester metadata.
3. Choose a semester, check the courses you want, and select **Save & sync**. Course content is fetched only after this selection. Portal and other course spaces without a named semester are optional.
4. Change the selection through the semester menu in the sidebar or **Settings → Canvas → Manage courses…**.

The selected courses determine what appears in the workspace, Needs information, Sources, search, and the desktop card, as well as new EventKit writes and ICS exports. Switching semesters keeps historical data and previously exported Calendar events. Personal and manually imported courses remain available. Upgrading an existing library asks you to choose a Canvas scope before resuming content sync.

Keep the saved address spelling consistent: credentials are scoped to the configured address. Changing the address requires saving a token for that address. Leave the token field blank to retain the saved credential for the current address. Tokens are saved locally by default; Keychain is optional in **General → Credential storage**.

For selected courses, the connector reads Assignments and submission/grade state, course Calendar events, inline syllabus HTML, Announcements, Modules, the front page, and referenced Pages and attachments. Classic Quizzes and quiz-linked Assignments are associated by Canvas IDs to avoid duplicate items; New Quizzes coverage uses the information available through Canvas Assignments. Course events are organized into class meetings, submission deadlines, and exams/quizzes, retaining subtypes such as Lecture, Recitation, Project, and Midterm. Timed events retain an explicit end time and location when supplied. Grades and submission states remain attached to the task; grade-release notices do not become separate schedule entries.

**Sources** preserves text and links from course materials. Referenced attachments and likely syllabus/schedule files can be imported explicitly. A hidden or inaccessible Files directory does not prevent other accessible sources from syncing; individual attachments still require permission.

For an external schedule link, use **Add Material → Link** or the source’s **Import link** action to read a public document or Google Sheets export. These requests use no Canvas token or browser cookies. If a source requires a separate sign-in, its link remains available to open in a browser; you can also import an exported file. Private Google authorization and complete Gradescope/Piazza connectors are not included. Gradescope-linked work is limited to the dates and grades actually available in Canvas; individual extensions may remain solely in Gradescope.

**Refresh every 10 minutes while running** is opt-in. The app must remain running to fetch changes. Partial failures preserve existing data and report the affected resources. Unchanged source content is skipped during background refresh, without moving the current view. Attachments and external documents are imported on request, rather than downloaded again on each refresh.

**Renew token automatically** is enabled by default in Canvas settings. While the app is open, it checks the saved personal token and requests an expiry extension near the end of its lifetime, when the institution permits it. This is an active expiry-extension request, not OAuth refresh or automatic renewal from token usage. The renewal period is no longer than the first observed lifetime and is capped at 30 days; the token value and permissions remain unchanged. The token matcher handles server mask formats and distinguishes an identification failure from a rejected or unconfirmed extension. Successful metadata retrieval alone does not prove renewal is allowed. You can switch renewal off. If the app stays closed until expiry, or Canvas refuses renewal, generate a replacement in Canvas and save it in Settings. Course sync and saved data do not depend on renewal succeeding.

## Choose a model

Open **Settings → Models**:

1. Choose **OpenAI**, **Anthropic · Claude**, **DeepSeek**, or **Custom service**. Official providers supply their API address; a custom service accepts an HTTPS base URL.
2. Enter your API key and choose **Load models**. Syllapace queries that provider’s model API, saves a successfully used key in your selected credential storage, and offers a searchable model list.
3. Select a model and choose **Save model**. Refresh the list when needed. If a compatible service does not list models, enable **Enter a model identifier manually**.

Anthropic uses its native Messages API with a JSON schema; an optional Workspace ID is available for keys that require it. OpenAI, DeepSeek, and custom services use chat completions with JSON response format. Known non-text model families are excluded from the list. A listed model can still have account-specific access or API compatibility restrictions; list retrieval does not run a paid generation. The existing endpoint and credential account identifier are retained when upgrading an older custom configuration; see the credential migration instructions below.

**Automatically organize course materials** is enabled by default in Models settings. Once a model and key are configured, eligible saved materials for the selected courses can be sent directly to that provider after launch, sync, or import. Material imported with **Use AI** off is excluded. Explicitly organizing that source permits that operation without enabling later automatic uploads. Turn the setting off to stop background organization; explicit **Organize** and **Use AI** imports remain available. Provider usage may incur charges under your own account.

The adapter gives models no tools and validates returned fields, dates, and verbatim evidence. It filters irrelevant text and normalizes titles before merging accepted events. A fingerprint of the source, model configuration, date range, and curation version skips unchanged successful work. Missing dates and unresolved conflicts remain in **Needs information**, with the source available. Evidence checks reduce errors but do not guarantee correct semantic interpretation; events remain editable and the latest reorganization is undoable. Canvas tokens are never included in model requests.

For compatible chat endpoints, recognized reasoning models use `max_completion_tokens` without `temperature`; a definite unsupported-parameter error permits one compatibility retry. Authentication, rate-limit, network, and incomplete-generation errors are not automatically retried. Plain HTTP endpoints and providers requiring a different protocol are not supported.

## Academic calendars

Open **Settings → Academic calendars** to add an ICS subscription or a calendar based on imported documents. Give it a name, semester, time zone, and date range, then save it. **Sync dates** fetches a saved ICS subscription on request. You can also choose **Import calendar document…** to parse a PDF, spreadsheet, text, or public link with the same material workflow.

A **CMU Academic Calendar** preset links to the official feed and the 2026–2027 PDF. The feed may contain only upcoming dates; the full-year document can fill gaps. Check the source’s campus and program coverage before relying on it.

Academic milestones and holidays have their own sidebar group. The main course workspace excludes them by default; select an academic calendar explicitly to view that separate layer. A holiday never automatically cancels a class meeting. Supported ICS recurrence rules expand only inside the chosen range; unsupported rules or ambiguous times produce warnings instead of guessed dates. Missing or source-cancelled items preserve saved history for review. ICS subscriptions are read into Syllapace, not installed as an Apple Calendar subscription URL.

## Customize course names

Use **Settings → General → Course display** to choose course code, course name, code plus name, or a custom name. Right-click a course in the sidebar and choose **Customize display…** for a per-course override and preview. This changes display labels without rewriting Canvas identities or source evidence.

## Apple Calendar

Open **Settings → Calendar → Connect & sync calendar**. Syllapace requests full calendar access so it can find and update its previously written events and detect external edits. Its implementation operates only on its dedicated `Syllapace` calendar and owned events.

The current implementation uses a local **On My Mac** calendar only. If the local source is unavailable, first choose **File → New Calendar → On My Mac** in Apple Calendar, then reconnect. It does not silently create an iCloud calendar or host a subscription URL.

- Only approved events within the selected course and academic-calendar scope, with valid dates and time zones, are published. Explicit end times and multi-day all-day ranges are preserved.
- Repeated syncs reuse event mappings. Confirmed date changes update the existing event.
- External edits or deletions are reported as conflicts. **Use Syllapace version** requires an explicit confirmation before replacing an edit or recreating a deleted event. There is no automatic reverse import of Calendar edits into Syllapace.
- Rejecting a previously published event in the current scope can remove its owned Calendar counterpart, provided it has not been changed externally. Missing sources, failed fetches, and switching semesters do not imply deletion.
- **Sync confirmed changes automatically** is opt-in and runs while the application is open. Already saved events remain in Calendar when Syllapace quits.

Portable `.ics` export is also available from the File menu (`⇧⌘E`) or Calendar settings. Export is a snapshot, not live synchronization; repeated manual imports may be duplicated by the receiving client despite stable UIDs.

## Desktop card and shortcuts

Show the desktop card with `⇧⌘D` or the menu bar item. Its compact view separates **Next class** from **Next deadline**; expand it to see the next seven days. Drag its background to move it, use the menu to pin it above windows, lock its position, or snap to screen edges, and click an event to open the workspace. The card follows your chosen semester and courses. This release ships an AppKit desktop panel; a WidgetKit extension in the macOS widget gallery is deferred.

| Action | Shortcut |
| --- | --- |
| New event | `⌘N` |
| Add material | `⌘O` |
| Sync Canvas | `⌘R` |
| Export ICS | `⇧⌘E` |
| Show desktop card | `⇧⌘D` |
| Settings | `⌘,` |

## Data and privacy

The library is an atomically written JSON archive at `~/Library/Application Support/Syllapace/archive.json`. `archive.json.backup` retains the previous readable archive. Version 0.4.0 reads schema-1 through schema-3 libraries and writes schema 4 on the next successful save, keeping a one-time `archive.json.schema-<old-version>.backup` as well as the rolling backup. Existing completion flags are retained, with added task progress, planned starts, and curation records. Older versions cannot read schema 4; preserve the backup before attempting a downgrade. EventKit bindings are stored separately in `calendar-mapping.json` alongside it. Connection addresses and nonsecret preferences use UserDefaults.

**Tokens and API keys default to a local file** at `~/Library/Application Support/Syllapace/Credentials/credentials.json`, separate from the course archive, its backups, exports, and WebKit data. The directory is owner-only (`0700`) and the file is owner read/write (`0600`), with atomic writes. It is plaintext, not an encrypted vault: other programs running as your macOS account may read it. Include this folder only in backups you trust.

Choose **Settings → General → Credential storage → macOS Keychain** for system-protected storage. Existing local keys are copied first, and the local copies are removed only after all writes and the mode change succeed. Denial or failure leaves Local selected and its values intact; copies already written to Keychain can remain. Keychain mode may show macOS authorization prompts, including after an ad hoc-signed update.

**Upgrading from 0.4.0 or earlier:** Local is selected without reading old Keychain entries. Choose **Import from Keychain…** to copy them explicitly, or enter your Canvas token and model API key again. Import may require system permission; it never overwrites existing local keys, restores explicitly deleted local keys, or deletes the originals. A failed or cancelled import commits nothing. Switching from Keychain back to Local also does not read Keychain; import or re-enter your keys afterwards. These settings affect application credentials, not the maintainer’s Sparkle release-signing key.

Imported text and evidence are stored locally without additional application-level encryption. Original local documents remain where you selected them. Downloaded temporary files are cleaned up after ingestion. No Syllapace account, telemetry service, or backend is required. Automatic organization and explicit AI imports send the applicable source text and any extraction instructions directly to the provider you configured. The WebKit workspace receives display data and sends finite native commands; it has no Canvas token or model key, loads only bundled UI resources, and does not run a second database. School search sends a school-name query to Instructure; model discovery sends your key only to the configured provider. Public document and academic-calendar requests use no Canvas or model credentials.

Set `APP_STORE` to an alternate archive path for isolated development runs; local credentials use a sibling `Credentials/` directory. This isolates local files, not the optional system Keychain service. Automated verification uses synthetic credentials and never imports real Keychain entries. If the archive is corrupt or has an unknown schema, the app reports it and refuses to overwrite it. Back up the application-support directory before manually restoring files; a calendar mapping should not be discarded casually, because it preserves event ownership and duplicate prevention.

## Verification

Build before running application-level scripts:

```sh
./tools/test.sh        # Swift Testing: domain, documents, connectors, calendar sync planner
./tools/selftest.sh    # Application curation/commands/undo/persistence in a temporary store
npm --prefix Web test # Workspace views, filters, progress, and planning
python3 tools/snap-review.py build/verification/visual-review # Both languages, light/dark
# Focused workspace matrix (use a fresh output directory):
APP_SNAPSHOT_WORKSPACE=1 python3 tools/snap-review.py build/verification/workspace-review
APP_SNAPSHOT_CREDENTIALS=1 python3 tools/snap-review.py build/verification/credential-review
./tools/grid-lint.sh   # SwiftUI spacing checks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift tools/check-layout.swift build/verification/visual-review/*/*-layout.json
```

The review runner uses an isolated app copy and temporary data, leaving the installed version untouched. Full review expects 51 screenshots per language; workspace-only review expects 18, covering three views, two sizes, both appearances, empty data, a course filter, and the academic-calendar layer. It waits for the matching WebKit snapshot and fails on loading errors rather than capturing a placeholder. Native Settings forms use system layout; grid probes cover custom native surfaces, while WebKit layout is reviewed from real window captures. Use the emitted `*-layout.json` paths with the layout checker. The runner captures only the app's own windows. Screen Recording permission may be required for faithful window captures; a logged `view-render fallback` does not verify native materials or active window chrome.

The tests use synthetic PDFs/DOCX documents, mocked network responses, and calendar snapshots. They do not request real credentials or write to your actual calendars. See [engineering requirements](docs/ENGINEERING.md), [EventKit decision](docs/decisions/0001-apple-calendar-eventkit.md), and [acceptance evidence](docs/ACCEPTANCE-0.5.0.md).

## Current limits

- Import limits: 20 MB per document, 150 PDF pages, and 2 MB extracted text. Scanned/image-only PDFs need OCR elsewhere first. Complex PDF layouts can lose reading order; DOCX parsing preserves basic row/cell associations rather than visual layout.
- Each model extraction accepts up to 64,000 Swift string characters of source text, 2,000 instruction characters, and up to 300 returned structured entries before bounded recurrence expansion. It requires a compatible HTTPS provider. Larger files may be stored locally but must be shortened for model extraction.
- File discovery follows accessible course references and syllabus/schedule-style filenames. Files and public external links are explicitly imported; previously downloaded documents are not automatically re-downloaded on every Canvas refresh. Import a revised source again to process its changes.
- Canvas access depends on course configuration and your account permissions. Private Google Sheets, Piazza posts, complete Gradescope content, and New Quizzes question content are outside the current connector coverage.
- Structured ICS recurrence is bounded to the selected date range. AI can identify weekly class schedules in prose; native code expands only explicitly supported weekdays/times within known course or source dates. A semester name alone is not enough to infer its boundaries. Missing ranges, unsupported rules, or ambiguous daylight-saving times produce issues. Holidays do not automatically cancel classes.
- Rule extraction is conservative, primarily for English academic event wording and explicit dates. It is not a complete multilingual date parser.
- Reconciliation combines matching observations and protects your edits, but cannot prove that differently named items are the same event. AI interpretation is not guaranteed; unresolved dates remain outside the schedule instead of being guessed.
- The app has no unattended background agent, OAuth setup, OCR, Windows build, or other-LMS integration.
- Runtime permission flows, account-specific Canvas permissions, provider compatibility, and real Calendar synchronization still require user-configured live checks.

## Logo

The course-page and date mark is available as transparent [SVG files](Brand/README.md) in two-color, teal, near-black, and white versions. Its [construction diagram](Brand/concepts-v2/alignment.png) records the alignment grid. The native app icon uses the same paths in `Icon/AppIcon.icon`; macOS supplies its material and appearance variants.

## Project layout

`Sources/SyllapaceKit/` contains domain models, persistence, parsing, reconciliation, connectors, ICS export, and the pure calendar synchronization planner. `Sources/Syllapace/` contains the SwiftUI shell, WebKit bridge, application state, desktop panel, and EventKit adapter. `Web/` contains the bundled React/Tailwind workspace and reused ReUI/shadcn components. `Tests/SyllapaceKitTests/` exercises the core boundaries with synthetic fixtures.

The desktop interaction takes inspiration from [Still Today](https://github.com/OyangDer/still-today). The desktop panel is implemented in Swift/AppKit and does not embed the upstream Svelte/Tauri interface. The main workspace reuses MIT-licensed [ReUI](https://reui.io/) components; license notices travel with the app.
