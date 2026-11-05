# Vendored ReUI corrections

The MIT components come from the [official ReUI Base Nova registry](https://reui.io/r/base-nova/event-calendar.json). Their styles, spacing, animation, keyboard behavior, and event surfaces remain unchanged.

## Civil time coordinates — November 4, 2026

The original calendar mixed elapsed minutes since midnight with a shared 24-hour clock grid. In a week beginning on November 1, 2026 in New York, the daylight-saving fallback made the gutter label the 11:00 row as 10 AM. Events on either DST transition day also used inconsistent positions.

`event-calendar-lib.tsx` now provides `clockMinutes` and `dateAtClockMinutes`. Segmentation, time-grid/resource-grid coordinates, current-time indicator, pointer slots, and drag/resize inverse coordinates use this shared civil-clock mapping. The gutter formats its numeric clock slot using a fixed UTC reference date. This does not change event instants, source deadlines, all-day civil dates, or the Syllapace bridge. Syllapace's Calendar remains read-only; event clicks open the native editor.

A repeated local hour shares a clock row, with separate occurrence IDs and instants retained. `TZDate` resolves ambiguous or nonexistent civil times for the inverse mapping; Syllapace does not create or drag source events through Calendar. Timed move durations remain elapsed durations, while their pointer anchors use clock coordinates.

Regression tests cover spring-forward, fallback, a normal day, midnight splitting, repeated-hour instants, inverse slot mapping, and DOM gutter labels in DST weeks. Keep these tests when updating the registry components.
