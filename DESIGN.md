---
name: Syllapace
description: A quiet native Mac workspace for a trustworthy academic timeline.
colors:
  accent-light: "rgb(15% 47% 43%)"
  accent-dark: "rgb(46% 79% 73%)"
  action-accent: "rgb(15% 47% 43%)"
  on-accent-light: "white"
  on-accent-dark: "rgb(4% 4% 4%)"
  warning-light: "rgb(59% 30% 3%)"
  course-blue-light: "#4774B8"
  course-blue-dark: "#81A8E1"
  course-ochre-light: "#A96824"
  course-ochre-dark: "#DBAC70"
  course-purple-light: "#825BA6"
  course-purple-dark: "#BA92D6"
  course-rose-light: "#AA5A74"
  course-rose-dark: "#DA91AA"
  course-green-light: "#557E48"
  course-green-dark: "#A1C391"
typography:
  source-heading:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 600
  brand:
    fontFamily: "SF Pro Rounded, system-ui, sans-serif"
    fontSize: "19px"
    fontWeight: 600
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif'
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "20px"
  event-title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif'
    fontSize: "13px"
    fontWeight: 500
    lineHeight: "20px"
  metadata:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif'
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "16px"
rounded:
  compact-control: "8px"
  workspace-control: "10px"
spacing:
  micro: "4px"
  tight: "8px"
  compact: "12px"
  row: "16px"
  section: "20px"
  panel: "24px"
  content: "28px"
components:
  button-primary:
    backgroundColor: "{colors.accent-light}"
    textColor: "{colors.on-accent-light}"
    typography: "{typography.event-title}"
    rounded: "{rounded.workspace-control}"
    height: "32px"
    padding: "0px 10px"
  button-native-primary:
    backgroundColor: "{colors.action-accent}"
    textColor: "{colors.on-accent-light}"
  button-ghost:
    typography: "{typography.event-title}"
    rounded: "{rounded.compact-control}"
    size: "28px"
  search:
    typography: "{typography.body}"
    rounded: "{rounded.workspace-control}"
    height: "28px"
    width: "176px"
    padding: "4px 10px"
  course-label:
    typography: "{typography.metadata}"
  schedule-status:
    typography: "{typography.metadata}"
  event-row:
    typography: "{typography.event-title}"
  workspace:
    padding: "0px 16px 16px"
  workspace-toolbar:
    height: "44px"
  sidebar:
    width: "212px"
  settings:
    width: "640px"
    height: "560px"
    padding: "{spacing.row}"
  desktop:
    width: "360px"
    height: "420px"
    padding: "36px 24px 24px"
---

# Design System: Syllapace

## Overview

**Creative North Star: "The Quiet Library Study Desk"**

Syllapace feels like an orderly academic desk: quiet, exact and compact, with restrained teal, readable system type and familiar Mac controls. Clear alignment lets course names, dates and source evidence carry the information without explanatory decoration.

The native window, sidebar, toolbar and settings establish one application around the offline WebKit workspace. Neutral semantic layers separate controls from data; color belongs to actions and named courses. The approved revision is code-led, with bilingual light and dark window inspection rather than a separate approved visual comp. Imagery and decorative motion are unnecessary to this direction.

**Key Characteristics:**
- Native Mac navigation and SF system typography.
- Compact controls, readable metadata and title-first data layouts.
- Shared semantic surfaces, adaptive accents and six named-course colors.
- Trustworthy date presentation with explicit uncertainty.

Direction provenance: seven references were considered—library catalogue, course timetable, editorial syllabus, botanical index, museum reading room, campus wayfinding and quiet library study desk (`seed:7b4975d51b65fec9`). The last informs palette and rhythm. Acetate/manual, developer-console and catalog-sleeve challengers contributed grouping, seam hierarchy and whitespace, while the native interface remained authoritative. The 0.5.0 system revision and 0.5.1 workspace extension preserve that direction.

This revision is grounded in [AppAppearance.swift](Sources/Syllapace/AppAppearance.swift), [Theme.swift](Sources/Syllapace/Theme.swift), [ContentView.swift](Sources/Syllapace/ContentView.swift), [SettingsView.swift](Sources/Syllapace/SettingsView.swift), [ActivityControl.swift](Sources/Syllapace/ActivityControl.swift), [workspace styles](Web/src/index.css) and [workspace components](Web/src/workspace). The frontmatter records default primitives; custom accents and semantic system colors are resolved at runtime. Portable dimensions represent logical points or CSS pixels before the shared content scale, not physical display pixels. The [sidecar](.impeccable/design.json) contains portable specimens, not proof of native runtime behavior; synthesized tonal ramps are documentation aids, not runtime colors. The existing desktop-panel specification is outside this workspace revision and remains unreconciled with its separate implementation.

## Colors

### Primary

Study-desk teal in light appearance and mineral teal in dark appearance identify selected controls and current-date accents. Settings preserves the user's selected swatch; rendered custom variants blend toward black in light appearance and white in dark appearance, preserving the hue family while targeting 7.5:1 against white in light appearance (headroom for Aqua control tint blending) and 4.6:1 against the raised dark reference surface. That is a rendering target, not a claim that every possible control or background was measured.

Accent-fill foregrounds are computed from relative luminance: white on deeper fills and near-black on lighter fills. Native prominent buttons derive a deep action variant because macOS supplies their white label. The frontmatter accent and foreground pairs describe the default theme; a custom accent replaces the relevant variants in both native and web content.

### Secondary

Six shared course colors cycle through teal, blue, ochre, purple, rose and green. The first follows the chosen accent; the other five use the appearance-specific pairs in the frontmatter. Small markers, timeline data and calendar data use these colors alongside course text. Warnings still use warm review brown in light appearance and AppKit system orange in dark appearance for actual errors or review concerns, never for a past deadline.

### Neutral

AppKit is authoritative: `windowBackgroundColor` supplies the canvas, `labelColor` supplies primary text, and `separatorColor` supplies borders. Raised web surfaces blend the canvas 5.5% toward the label color. Web secondary labels use label-color alpha 0.64 in light appearance and 0.72 in dark appearance. These resolved values override the standalone CSS fallbacks; do not sample a screenshot and freeze system colors into constants.

**The Paired Accent Rule.** Resolve accent and foreground together for the active appearance; native prominent actions retain a deep variant for the system white label.

**The Named Course Rule.** Course color always accompanies a text label; it never carries identity alone.

## Typography

SF system type is the primary voice in native and WebKit content. The workspace uses the exact system stack recorded in the frontmatter, with body and event-title roles at the shared body size and metadata at its own readable size. Event titles use medium weight and up to two lines in the list; course codes, dates and schedule phases use the metadata role. Dates use tabular numerals.

The Sources page retains its native semibold heading, and the sidebar wordmark retains rounded system type. Other native forms and sheets use system text styles rather than a fabricated global display scale. The old center-page heading and date-ribbon type roles are not part of the active workspace. No bundled font is required.

**The Readable Metadata Rule.** Keep essential workspace metadata at the documented metadata size and semantic contrast; use layout and weight to establish hierarchy before shrinking text.

## Layout

The main window uses `NavigationSplitView`: sidebar minimum 192, ideal 212 and maximum 240 logical points. List, Timeline and Calendar are separate native destinations; Sources and a nonempty review queue remain native pages. The native title and semester selector carry context once. The embedded workspace has no duplicated semester heading, event count, view tabs or status-filter strip.

The initial window is 1120 × 760 points; minimum content dimensions are 940 × 620 before scaling. A single content scale applies to the native main content and its embedded WebKit workspace: Compact 90%, Standard 100%, Large 115%. Minimum main dimensions scale with it. Settings uses the same scale and a base 640 × 560 content frame. Native window chrome remains system-owned.

The workspace uses the frontmatter inset, a compact tools row and a growing data region. List places its date range at the leading edge and tools at the trailing edge; Timeline and Calendar combine period navigation at the leading edge with compact view and filtering controls at the trailing edge. Their navigation rows have a 48-point minimum height with 8-point vertical padding. Search expands in place; History / 历史 remains a compact labeled control and event type stays compact.

List gives spare width to the title. The initial supporting columns are course 120, date 160, status 96 and actions 40 logical pixels; title starts at 240 and fills remaining width. The course column hides when only one course is present. Dense rows keep borders and sorting, with column resizing and pinning disabled. The table scrolls in its own native overflow viewport; its non-scrolling pagination footer remains below it. The timeline course/event tree starts at 216 points and resizes between 180 and 360. Its initial month scale fits the timeline viewport while adjacent dates remain reachable by native horizontal scrolling or background panning. Before user navigation, resizing maintains the full-month framing; after scrolling or panning, resizing preserves the date at the viewport center. There is no mobile-layout contract.

Sheets remain task-sized: event editing is 480 points wide, importing is 460, and the source reader is 640 × 560. Native source and editor pages retain their content inset and scrolling. Surface behavior and screenshot provenance belong in the [desktop brief](.impeccable/surfaces/desktop.md).

## Elevation & Depth

The workspace is flat at rest: semantic background layers and separators organize data without decorative cards or custom shadows. Native windows and sheets own native elevation; installed shadcn/ReUI popovers and controls retain their component elevation and focus treatment. Do not flatten those interaction affordances to satisfy an absolute no-shadow rule.

There is no bespoke application motion system. Preserve native behavior and installed component transitions without adding decorative reveals or retiming library components. Loading indicators communicate pending work; they are not visual ornament.

## Shapes

Native buttons, lists, sheets and windows retain their system geometry. The workspace preserves the installed component geometry: regular fields and buttons use the workspace-control radius; compact icon controls use the compact-control radius. Circular course markers supplement course labels. Native SF Symbols and workspace SVG icons provide the action vocabulary; workspace icon strokes are 1.5 units.

## Components

### Buttons

Native confirmation actions use `.borderedProminent` with the deep action accent; secondary native actions retain bordered or borderless styles. Web controls use the installed shadcn/ReUI variants, including filled, outline and ghost, with their existing hover, focus, active and disabled behavior. Search and type controls use compact ghost geometry. History combines its icon with History / 历史 text, switches from ghost to secondary when active, and exposes a pressed state. Icons have accessible labels.

### Search and forms

Workspace search expands to the documented compact field size; Escape clears and collapses it. Event type uses a menu and displays the selected non-default type next to its icon. A clear action appears when search or type filtering is active. List date range and page size use native HTML selects with the workspace text and semantic border colors. Native forms keep text fields, pickers, toggles and date pickers. Keyboard focus remains visible; an existing draft is not selected merely because a sheet opens.

### Navigation and event rows

The native sidebar separates List, Timeline and Calendar from Sources and the conditional review queue. Course filters retain named markers, selection checkmarks and an All courses recovery entry. The list aligns titles, course codes, dates and automatic schedule phases in separate columns. Clicking a title opens the native editor; the actions menu exposes editing and source access when available. No completion control or overdue decoration appears.

Repeated classes occupy one list row. Its date-count control opens a scrollable popover of occurrences, each opening that occurrence's native editor. Pagination counts grouped rows and offers 20, 50, 100 or all rows, with 20 initially selected; range filtering offers All dates or This week & next. The latter covers the current Monday-start week and following week in the display timezone. Page and range changes preserve a visible, non-scrolling footer.

Commands retain native conventions: Import `⌘O`, New `⌘N`, Sync `⌘R`, Export `⇧⌘E`, desktop card `⇧⌘D`, Settings `⌘,`.

### Timeline and Calendar

Both open in month view. Timeline shows classes and assessments as points; repeated class occurrences share one track under their course. A deadline receives a span only from its explicit release date to its due date. Unknown release dates remain unknown and render at the due point; legacy personal plans supply no duration. Course color belongs to the plotted data, with course/event labels in the tree. Event dragging and resizing are disabled; background panning moves the date viewport, and selecting an occurrence opens its native editor. Calendar also offers week, day and agenda views through its own compact switcher.

Not started, In progress and Historical are date-derived labels. An event without a date retains Date to be confirmed. Historical events are hidden initially and can be revealed by the history control. Schedule phase never infers completion or lateness; source review concerns remain separate from schedule phase.

### Desktop panel

The compact native panel shows up to three upcoming events, a pin action and a route back to the timeline. It can remain on the desktop or float above windows. It uses the same spacing, type and course markers as the main window; it is an AppKit panel, not a WidgetKit widget.

### Empty, busy and error states

The workspace uses installed empty-state components with a nearby action: choose a semester, add material, clear filters or reveal historical events. The native review and source pages retain native empty states. Loading has a compact placeholder; workspace command errors offer Retry and dismissal. Native activity stays in the toolbar so it never reduces schedule height. A new notice shows a one-line summary for six seconds, then collapses to an information icon; active curation keeps its progress indicator and summary. Clicking Activity opens a native popover with selectable, scrollable detail, Stop while work is running, or the available undo and dismissal actions afterward. The popover is 392 points wide with detail capped at 240 points high and does not open automatically. Blocking native errors retain alerts; foreground activity does not trigger system notifications. Demo data stays visibly labeled.

### Appearance, language and updates

Settings places Appearance before General. Appearance contains Follow system, Light and Dark, a custom color picker, Compact / Standard / Large sizing and Reset appearance. Changes affect the native and web workspace together; the color picker keeps the original selected swatch while renderers use contrast-adjusted variants.

General retains Follow system, English and 简体中文 language choices. Product and protocol names such as Canvas, OpenAI, API and ICS retain their spelling; evidence and course names are user content. The interface changes without replacing the archive or connection model. Native menus and Sparkle windows adopt the language on reopening.

Updates retains the version, automatic-check preference, Check for Updates and release notes. Sparkle supplies its standard progress, error and install windows; verification and user confirmation precede installation. Demo and automated capture sessions keep updates disabled.

### Brand mark

The mark combines stacked course pages, a selected date and a separated turning corner. Its recognizable page-and-calendar meaning follows the user's revised direction, while the restrained geometry reflects the requested Codex, Slack and Linear style references. The drawing is original and uses no font glyphs, SF Symbols or borrowed brand paths. The native study-desk interface direction is unchanged.

The source geometry uses an 8-unit base and a 32-unit structural gap. Paper corners use radius 32, internal details 16, and tangent tip fillets 8. The rear page shifts by 96 on each axis, exposing equal 64-unit strips and a 32-unit gap; its inner radius 64 is concentric with the front page's radius 32. The content has equal 96-unit padding within the front page's rectangular bounds. Date cells share 128 × 128 bounds and a 64-unit horizontal/vertical gap; the header aligns with the grid's edges and sits 64 units above it. The selected date's radii 64 and 32 retain the same 32-unit negative-space ring. The turning corner and page notch use concentric radii 96 and 128, with tangent radius-8 tips; selected-date clearance to the notch is approximately 34.27 units. Rounded tips intentionally open the gap at its ends.

[Brand/README.md](Brand/README.md) documents the transparent two-color, teal, near-black and white SVG variants. Each retains the same compound paths and circular date marker, with a `128 128 768 768` viewBox. [tools/make_brand.py](tools/make_brand.py) derives the shared geometry and [Brand/geometry.json](Brand/geometry.json) records its measured constraints. The native icon scales the complete centered mark uniformly to 560 units high. Its materials and appearance adaptations are supplied by Icon Composer / macOS; the standalone SVGs contain no background, gradients or shadows.

## Do's and Don'ts

### Do:
- Do keep native window, form, button and keyboard behavior authoritative.
- Do let the title column take spare width and keep supporting columns compact.
- Do resolve native and web appearance from the same semantic colors, accent variants and content scale.
- Do show course names, schedule phases and review concerns in text as well as color.
- Do verify bilingual light and dark Mac windows at the supported sizes and content scales.

### Don't:
- Don't turn the workspace into a dashboard of decorative metric cards or repeat native navigation inside the web content.
- Don't replace semantic system colors with sampled screenshot constants.
- Don't invent a date, release duration, completion state or source confidence to make the layout look populated.
- Don't present portable HTML previews as proof of native runtime behavior.
