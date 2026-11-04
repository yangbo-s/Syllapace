---
name: Syllapace
description: A quiet native Mac workspace for a trustworthy academic timeline.
colors:
  accent-light: "rgb(15% 47% 43%)"
  accent-dark: "rgb(46% 79% 73%)"
  action-accent: "rgb(15% 47% 43%)"
  on-accent-light: "white"
  on-accent-dark: "rgb(5% 17% 15%)"
  warning-light: "rgb(59% 30% 3%)"
typography:
  heading:
    fontFamily: "SF Pro Rounded, system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 500
    letterSpacing: "-0.5px"
  event-title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
  detail-title:
    fontFamily: "SF Pro Rounded, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 500
  evidence:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  group-label:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
  date:
    fontFamily: "SF Pro Rounded, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 400
  date-current:
    fontFamily: "SF Pro Rounded, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 600
  weekday:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
rounded:
  field: "8px"
  surface: "12px"
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
    backgroundColor: "{colors.action-accent}"
    textColor: "{colors.on-accent-light}"
  search:
    rounded: "{rounded.field}"
    padding: "{spacing.compact}"
  evidence:
    typography: "{typography.evidence}"
    rounded: "{rounded.surface}"
    padding: "{spacing.row}"
  event-row:
    typography: "{typography.event-title}"
    padding: "16px 28px"
  date-current-light:
    backgroundColor: "{colors.accent-light}"
    textColor: "{colors.on-accent-light}"
    typography: "{typography.date-current}"
    rounded: "{rounded.surface}"
    padding: "12px 0px"
  date-current-dark:
    backgroundColor: "{colors.accent-dark}"
    textColor: "{colors.on-accent-dark}"
    typography: "{typography.date-current}"
    rounded: "{rounded.surface}"
    padding: "12px 0px"
  sidebar:
    width: "212px"
  inspector:
    width: "292px"
    padding: "{spacing.panel}"
  desktop:
    width: "360px"
    height: "420px"
    padding: "36px 24px 24px"
---

# Design System: Syllapace

## Overview

**Creative North Star: "The Quiet Library Study Desk"**

Syllapace feels like an orderly place to understand the semester: generous row rhythm, restrained teal, familiar Mac controls, and clear separation between a date and the evidence supporting it. Rounded system headings soften the workspace without weakening its information hierarchy.

The native window, sidebar, sheets and compact desktop panel carry the interaction. Content stays plain and readable; color identifies an action, a course or an unresolved decision. The user approved implementation directly in SwiftUI and inspection of the real light and dark interfaces.

**Key Characteristics:**
- Native Mac controls and system typography.
- Spacious rows with compact, purposeful metadata.
- Adaptive teal with explicit foreground contrast.
- Evidence and uncertainty visible at the point of review.

Direction provenance: seven references were considered—library catalogue, course timetable, editorial syllabus, botanical index, museum reading room, campus wayfinding and quiet library study desk (`seed:7b4975d51b65fec9`). The last informs palette and rhythm. Acetate/manual, developer-console and catalog-sleeve challengers contributed grouping, seam hierarchy and whitespace, while the native interface remained authoritative.

This file records the implemented system. [Theme.swift](Sources/Syllapace/Theme.swift), [ContentView.swift](Sources/Syllapace/ContentView.swift), [Editors.swift](Sources/Syllapace/Editors.swift) and [DesktopPanel.swift](Sources/Syllapace/DesktopPanel.swift) are the implementation sources. Portable token dimensions use `px` to represent SwiftUI logical points, not physical display pixels. System-controlled colors, type styles, button geometry and focus rings intentionally have no fabricated fixed token. The [sidecar](.impeccable/design.json) contains illustrative portable component previews, not substitutes for native screenshots. Its synthesized tonal ramps are documentation aids, not additional runtime colors.

## Colors

### Primary

Deep study-desk teal in light appearance and pale mineral teal in dark appearance identify current-day emphasis and active interface accents. Each appearance has its own `on-accent` foreground. Native prominent buttons use the separate deep `action-accent` in both appearances because the system supplies a white label.

### Secondary

Course markers use the accent and SwiftUI's adaptive blue, orange and purple. Course names remain readable semantic text; a small colored marker supplements the name. Light-appearance warnings use the warm brown token, while dark appearance uses `NSColor.systemOrange`.

### Neutral

The content surface uses `NSColor.textBackgroundColor`. Text uses SwiftUI primary, secondary and tertiary semantic foregrounds. Search, evidence and the inspector use translucent quaternary layers; the sidebar and window chrome are system-rendered. Do not freeze their current screenshot colors into custom constants.

**The Paired Accent Rule.** Custom accent-filled surfaces use the appearance-matched `on-accent` foreground. Native prominent buttons keep the deep `action-accent` and system white label in both appearances.

**The Named Course Rule.** Course color always accompanies a text label; it never carries identity alone.

## Typography

System SF Pro provides body text and native control labels. Rounded system type is reserved for the main heading, brand name, date numerals, inspector title and desktop heading. No bundled font or custom font loading is needed.

The heading, event title, evidence and date roles are extracted in the frontmatter. Group labels organize the timeline without introducing heavy headings. Other captions and form labels use native `.caption`, `.headline`, `.title2` and default text styles so the system remains responsible for their metrics.

Event titles allow two lines in rows and expand in the inspector. Evidence is selectable and uses five points of extra line spacing. Supporting text is secondary by role, not by reducing important content to an unreadable size.

## Layout

The main window is a `NavigationSplitView` with a sidebar that ranges from 192 to 240 points, ideally the frontmatter width. The center timeline grows; selecting an event opens the fixed-width inspector. The supported minimum content area is 940 × 620 points. The initial main window is 1120 × 760 points. This is a desktop layout, with no mobile breakpoint or hidden mobile navigation contract.

Headings and event rows share the content inset. Rows use the row vertical inset and inter-item gap; the inspector and desktop panel use the panel inset. The compact panel has an additional compact top inset to clear its title bar. Gaps follow the observed four-point rhythm listed in the frontmatter.

Sheets remain task-sized: event editing is 480 points wide, importing is 460, the source reader is 640 × 560 and Settings is 580 × 400. Use native scrolling when content exceeds its allotted area.

The Today surface's seven-day ribbon and the list below share alignment. Its composition is a surface-level signature, recorded in the [desktop brief](.impeccable/surfaces/desktop.md), not a requirement to add date ribbons to every future screen.

## Elevation & Depth

The application adds no custom shadows. Native window, panel and sheet elevation communicates containment; inside the window, dividers and subdued tonal backgrounds establish hierarchy. Plain timeline rows keep adjacent events easy to scan. A selected row uses an eight-percent accent fill.

There is no custom animation duration or easing token in the current implementation. Native control and sheet behavior supplies motion; do not document a bespoke transition as implemented until it exists and has been checked with Reduce Motion.

## Shapes

Search uses the field radius; source evidence and the selected day use the surface radius. Native buttons, lists, sheets and windows retain their system geometry. Small circular course markers and date dots serve information, not decoration. SF Symbols provide the action and event-kind vocabulary.

## Components

### Buttons

Primary confirmation actions use native `.borderedProminent` tinted with `action-accent` in both appearances. The deep fill preserves contrast with the system-provided white label. Secondary actions use native bordered or borderless styles. Toolbar icons have labels and help text; destructive actions retain semantic roles and explicit confirmation when cancelling an event. Hover, pressed, focus and disabled rendering remain system-owned.

### Search and forms

Search is a plain text field inside a softly rounded quaternary surface, with a magnifying-glass symbol and a clear control when populated. Forms use native text fields, pickers, toggles, steppers and date pickers. Keyboard focus remains visible while editing. An empty new-event title may receive initial focus; existing content should not appear selected merely because its sheet opened.

### Navigation and event rows

The native sidebar separates workspace pages from course filters. An active filter has a checkmark, with an “All courses” recovery entry. Rows put the event title first, source/course metadata below and date context at the trailing edge. Selection reveals evidence; context menus expose editing and state actions.

Commands follow native conventions: Import `⌘O`, New `⌘N`, Sync `⌘R`, Export `⇧⌘E`, desktop card `⇧⌘D`, Settings `⌘,`.

### Date ribbon and evidence

The seven-day ribbon gives today the paired accent fill and leaves neighboring dates open. A small dot indicates an event. The inspector separates status, date and selectable source evidence; evidence lives in the padded tonal container. “Needs review” and “Schedule changed” remain explicit text states.

### Desktop panel

The compact native panel shows up to three upcoming events, a pin action and a route back to the timeline. It can remain on the desktop or float above windows. It uses the same spacing, type and course markers as the main window; it is an AppKit panel, not a WidgetKit widget.

### Empty, busy and error states

Empty content uses `ContentUnavailableView` with a nearby next action. Filtered emptiness says “No matching events” and offers “Clear filters”; a finished review queue says “All caught up.” Work in progress has a small native progress indicator. Notices are inline and dismissible; errors use a native alert. Demo data is always visibly labeled.

### Brand mark

The mark combines stacked course pages, a selected date and a separated turning corner. Its recognizable page-and-calendar meaning follows the user's revised direction, while the restrained geometry reflects the requested Codex, Slack and Linear style references. The drawing is original and uses no font glyphs, SF Symbols or borrowed brand paths. The native study-desk interface direction is unchanged.

The source geometry uses an 8-unit base and a 32-unit structural gap. Paper corners use radius 32, internal details 16, and tangent tip fillets 8. The rear page shifts by 96 on each axis, exposing equal 64-unit strips and a 32-unit gap; its inner radius 64 is concentric with the front page's radius 32. The content has equal 96-unit padding within the front page's rectangular bounds. Date cells share 128 × 128 bounds and a 64-unit horizontal/vertical gap; the header aligns with the grid's edges and sits 64 units above it. The selected date's radii 64 and 32 retain the same 32-unit negative-space ring. The turning corner and page notch use concentric radii 96 and 128, with tangent radius-8 tips; selected-date clearance to the notch is approximately 34.27 units. Rounded tips intentionally open the gap at its ends.

[Brand/README.md](Brand/README.md) documents the transparent two-color, teal, near-black and white SVG variants. Each retains the same compound paths and circular date marker, with a `128 128 768 768` viewBox. [tools/make_brand.py](tools/make_brand.py) derives the shared geometry and [Brand/geometry.json](Brand/geometry.json) records its measured constraints. The native icon scales the complete centered mark uniformly to 560 units high. Its materials and appearance adaptations are supplied by Icon Composer / macOS; the standalone SVGs contain no background, gradients or shadows.

## Do's and Don'ts

### Do:
- Do keep native window, form, button and keyboard behavior authoritative.
- Do align headings and rows to the shared content inset.
- Do pair custom accent fills with their appearance-specific foreground and use the deep action accent for native prominent buttons.
- Do show course names and review states in text as well as color.
- Do verify the actual light and dark Mac windows at the supported minimum size.

### Don't:
- Don't turn the timeline into a dashboard of decorative metric cards.
- Don't replace semantic system colors with sampled screenshot constants.
- Don't invent a date, completion state or source confidence to make the layout look populated.
- Don't present portable HTML previews as proof of native runtime behavior.
