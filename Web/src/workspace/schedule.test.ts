import { describe, expect, it } from "vitest";
import { inTwoWeeks, scheduleGroups, uniqueOccurrences } from "./schedule";
import type { AcademicEvent } from "./types";

const event = (patch: Partial<AcademicEvent> = {}): AcademicEvent => ({ id: "one", courseID: "course", courseLabel: "18-749", title: "18-749 Recitation", category: "meeting", subtype: "recitation", start: "2026-11-04T17:00:00-05:00", end: null, dateOnly: false, timeZone: "America/New_York", progress: "todo", plannedStart: null, evidence: "", revision: 1, ...patch });
const now = new Date("2026-11-05T12:00:00Z");
describe("recurring schedule projection", () => {
  it("merges old and new source titles for the same class occurrence and groups future weeks", () => {
    const values = [event(), event({ id: "duplicate", title: "Recitation", end: "2026-11-04T18:00:00-05:00" }), event({ id: "next", title: "Recitation", start: "2026-11-11T17:00:00-05:00" })];
    expect(uniqueOccurrences(values)).toHaveLength(2);
    const groups = scheduleGroups(values, now);
    expect(groups).toHaveLength(1); expect(groups[0].occurrences).toHaveLength(2); expect(groups[0].event.id).toBe("next");
  });
  it("keeps other courses, explicit independent series, personal edits and distinct topics", () => {
    expect(uniqueOccurrences([event({ userEdited: true }), event({ id: "two" })])).toHaveLength(2);
    expect(uniqueOccurrences([event({ seriesID: "ics:a" }), event({ id: "two", seriesID: "ics:b" })])).toHaveLength(2);
    expect(uniqueOccurrences([event(), event({ id: "two", courseID: "another" })])).toHaveLength(2);
    expect(uniqueOccurrences([event({ title: "Recitation · Trees" }), event({ id: "two", title: "Recitation · Graphs" })])).toHaveLength(2);
    expect(scheduleGroups([event(), event({ id: "one-off", start: "2026-11-16T17:00:00-05:00" })], now)).toHaveLength(2);
  });
  it("keeps release bounds when combining a date-only task with its Canvas due timestamp", () => {
    const values = uniqueOccurrences([event({ category: "deadline", title: "Homework 4 · Parallel solver", dateOnly: true, start: "2026-11-19", releasedAt: "2026-11-01", releaseDateOnly: true }), event({ id: "canvas", category: "deadline", title: "Parallel solver", start: "2026-11-19T23:59:00-05:00" })]);
    expect(values).toHaveLength(1); expect(values[0].id).toBe("canvas"); expect(values[0].releasedAt).toBe("2026-11-01"); expect(values[0].releaseDateOnly).toBe(true);
  });
  it("includes current work overlapping this week and next, with Monday and DST boundaries", () => {
    expect(inTwoWeeks(event({ start: "2026-11-16T00:00:00-05:00" }), now, "America/New_York")).toBe(false);
    expect(inTwoWeeks(event({ start: "2026-11-15T23:59:00-05:00" }), now, "America/New_York")).toBe(true);
    expect(inTwoWeeks(event({ category: "deadline", start: "2026-11-20T23:59:00-05:00", releasedAt: "2026-10-30T09:00:00-04:00" }), now, "America/New_York")).toBe(true);
    expect(inTwoWeeks(event({ start: null }), now, "America/New_York")).toBe(false);
  });
});
