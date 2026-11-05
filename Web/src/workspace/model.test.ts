import { describe, expect, it } from "vitest";
import {
  displayDate,
  planFromDisplay,
  eventDate,
  eventsForView,
  formatDate,
  filteredEvents,
  ganttBounds,
  planStartToday,
  scheduleStatus,
} from "./model";
import type { AcademicEvent } from "./types";

function event(patch: Partial<AcademicEvent> = {}): AcademicEvent {
  return {
    id: "deadline-1",
    courseID: "course-1",
    courseLabel: "15-451",
    title: "Homework 4",
    category: "deadline",
    subtype: "Homework",
    start: "2026-11-04T23:59:00-05:00",
    end: null,
    dateOnly: false,
    timeZone: "America/New_York",
    progress: "todo",
    plannedStart: null,
    evidence: "Homework 4 due November 4 at 23:59.",
    revision: 1,
    ...patch,
  };
}
describe("shared event projections", () => {
  it("includes meetings, tasks and exams in the monthly timeline", () => {
    const task = event(),
      meeting = event({ id: "lecture", category: "meeting" }),
      exam = event({ id: "exam", category: "assessment" });
    expect(eventsForView([task, meeting, exam], "gantt", "all")).toEqual([
      task,
      meeting,
      exam,
    ]);
    expect(eventsForView([meeting], "gantt", "meeting")).toEqual([meeting]);
    expect(
      eventsForView([task, meeting, exam], "calendar", "all"),
    ).toHaveLength(3);
  });
  it("formats timed events in the shared display timezone while preserving all-day civil dates", () => {
    const timed = event({ start: "2026-11-04T16:00:00Z" });
    expect(formatDate(timed, "en", "America/New_York")).toContain("11:00");
    expect(formatDate(timed, "en", "America/Los_Angeles")).toContain("08:00");
    expect(
      formatDate(
        event({ start: "2026-11-04", dateOnly: true }),
        "en",
        "Asia/Shanghai",
      ),
    ).toBe("Wed, Nov 4");
  });
  it("keeps all-day civil dates stable across display zones and converts plan commands back", () => {
    const e = event({ dateOnly: true, start: "2026-11-04" });
    const shown = displayDate(e, e.start, "America/Los_Angeles")!;
    expect(shown.valueOf()).toBe(new Date("2026-11-04T08:00:00Z").valueOf());
    expect(planFromDisplay(e, shown, "America/Los_Angeles").valueOf()).toBe(
      eventDate(e)?.valueOf(),
    );
    const timed = event();
    expect(displayDate(timed, timed.start, "Asia/Shanghai")?.valueOf()).toBe(
      eventDate(timed)?.valueOf(),
    );
  });

  it("derives phase from availability and due date regardless of saved completion", () => {
    const now = new Date("2026-11-04T17:00:00Z");
    for (const progress of ["todo", "doing", "done"] as const) {
      expect(scheduleStatus(event({ progress, releasedAt: "2026-11-03T10:00:00Z" }), now)).toBe("active");
      expect(scheduleStatus(event({ progress, releasedAt: "2026-11-04T20:00:00Z" }), now)).toBe("upcoming");
      expect(scheduleStatus(event({ progress }), now)).toBe("upcoming");
    }
    expect(scheduleStatus(event({ start: null }), now)).toBe("undated");
  });
  it("keeps civil due dates through the end of the local day", () => {
    const e = event({ start: "2026-11-04", dateOnly: true, releasedAt: "2026-11-01", releaseDateOnly: true });
    expect(scheduleStatus(e, new Date("2026-11-05T03:00:00Z"))).toBe("active");
    expect(scheduleStatus(e, new Date("2026-11-05T05:01:00Z"))).toBe("historical");
  });
  it("uses meeting end times and exclusive all-day ends", () => {
    const e = event({ category: "meeting", start: "2026-11-04T16:00:00Z", end: "2026-11-04T18:00:00Z" });
    expect(scheduleStatus(e, new Date("2026-11-04T17:00:00Z"))).toBe("active");
    expect(scheduleStatus(e, new Date("2026-11-04T18:00:00Z"))).toBe("historical");
    expect(scheduleStatus(event({ category: "academic", dateOnly: true, start: "2026-11-03", end: "2026-11-05" }), new Date("2026-11-05T05:00:00Z"))).toBe("historical");
  });
  it("preserves date-only local dates across DST", () => {
    expect(
      eventDate(event({ dateOnly: true, start: "2026-11-01" }))?.valueOf(),
    ).toBe(new Date("2026-11-01T04:00:00.000Z").valueOf());
  });
  it("never fabricates gantt work duration for a deadline", () => {
    const bounds = ganttBounds(event())!;
    expect(bounds.start).toEqual(bounds.end);
    expect(bounds.isRelease).toBe(false);
  });
  it("does not use legacy personal plans as source availability, and meetings are points", () => {
    const e = event({ plannedStart: "2026-11-02T15:00:00Z" });
    expect(ganttBounds(e)?.start).toEqual(eventDate(e));
    const bounds = ganttBounds(event({ category: "meeting", end: "2026-11-05T01:00:00-05:00" }))!;
    expect(bounds.end).toEqual(bounds.start);
  });
  it("uses verified availability for a deadline interval and never expands an exam", () => {
    const e = event({ releasedAt: "2026-11-01T15:00:00Z", releaseDateOnly: false });
    expect(ganttBounds(e)?.start).toEqual(new Date(e.releasedAt!));
    expect(ganttBounds(e)?.isRelease).toBe(true);
    expect(ganttBounds(event({ ...e, category: "assessment" }))?.start).toEqual(eventDate(e));
    expect(ganttBounds(event({ releasedAt: "2027-01-01T00:00:00Z" }))?.start).toEqual(eventDate(e));
  });
  it("all past dates are historical regardless of progress or import timing", () => {
    const now = new Date("2027-01-01T00:00:00Z");
    for (const category of ["deadline", "meeting", "assessment", "academic"] as const)
      expect(scheduleStatus(event({ category, progress: "doing" }), now)).toBe("historical");
  });
  it("filters title/course/type without losing undated or previously completed tasks", () => {
    const list = [event(), event({ id: "later", start: null }), event({ id: "done", progress: "done" }), event({ id: "exam", category: "assessment" })];
    expect(filteredEvents(list, "15-451", "deadline").map(e => e.id)).toEqual(["deadline-1", "done", "later"]);
  });
  it("allows a same-day plan for all-day deadlines in the event timezone", () => {
    const e = event({ dateOnly: true, start: "2026-11-04" });
    expect(planStartToday(e, new Date("2026-11-05T03:00:00Z")).valueOf()).toBe(
      eventDate(e)?.valueOf(),
    );
  });
});
