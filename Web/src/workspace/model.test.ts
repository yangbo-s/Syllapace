import { describe, expect, it } from "vitest";
import {
  boardColumns,
  displayDate,
  planFromDisplay,
  eventDate,
  eventsForView,
  formatDate,
  filteredEvents,
  ganttBounds,
  planStartToday,
  urgency,
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
  it("defaults Gantt to tasks and exams while allowing an explicit Classes filter", () => {
    const task = event(),
      meeting = event({ id: "lecture", category: "meeting" }),
      exam = event({ id: "exam", category: "assessment" });
    expect(eventsForView([task, meeting, exam], "gantt", "all")).toEqual([
      task,
      exam,
    ]);
    expect(eventsForView([meeting], "gantt", "meeting")).toEqual([meeting]);
    expect(
      eventsForView([task, meeting, exam], "calendar", "all"),
    ).toHaveLength(3);
  });
  it("formats timed events in the shared display timezone while preserving all-day civil dates", () => {
    const timed = event({ start: "2026-11-04T16:00:00Z" });
    expect(formatDate(timed, "en", "America/New_York")).toContain("11:00 AM");
    expect(formatDate(timed, "en", "America/Los_Angeles")).toContain("8:00 AM");
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

  it("keeps progress independent from urgency", () => {
    const e = event({ progress: "doing" });
    expect(urgency(e, new Date("2026-11-04T12:00:00-05:00"))).toBe("today");
    expect(boardColumns([e]).doing).toEqual([e]);
  });
  it("does not mark an all-day deadline overdue before the day ends in its timezone", () => {
    const e = event({ start: "2026-11-04", dateOnly: true });
    expect(urgency(e, new Date("2026-11-05T03:00:00Z"))).toBe("today");
    expect(urgency(e, new Date("2026-11-05T05:01:00Z"))).toBe("overdue");
  });
  it("preserves date-only local dates across DST", () => {
    expect(
      eventDate(event({ dateOnly: true, start: "2026-11-01" }))?.valueOf(),
    ).toBe(new Date("2026-11-01T04:00:00.000Z").valueOf());
  });
  it("never fabricates gantt work duration for a deadline", () => {
    const bounds = ganttBounds(event())!;
    expect(bounds.start).toEqual(bounds.end);
    expect(bounds.isPlan).toBe(false);
  });
  it("only shows a duration when a real plan exists and keeps the source deadline", () => {
    const e = event({ plannedStart: "2026-11-02T15:00:00Z" });
    const bounds = ganttBounds(e)!;
    expect(bounds.start.valueOf()).toBe(new Date(e.plannedStart!).valueOf());
    expect(bounds.end).toEqual(eventDate(e));
    expect(bounds.isPlan).toBe(true);
  });
  it("rejects reversed plans and keeps confirmed meetings as actual intervals", () => {
    expect(
      ganttBounds(event({ plannedStart: "2027-01-01T00:00:00Z" }))?.isPlan,
    ).toBe(false);
    const bounds = ganttBounds(
      event({ category: "meeting", end: "2026-11-05T01:00:00-05:00" }),
    )!;
    expect(bounds.end > bounds.start).toBe(true);
  });
  it("applies the same course/title/type/urgency filters without losing undated tasks", () => {
    const now = new Date("2026-11-04T12:00:00-05:00");
    const list = [
      event(),
      event({ id: "later", start: null }),
      event({ id: "done", progress: "done" }),
      event({ id: "exam", category: "assessment" }),
    ];
    expect(
      filteredEvents(list, "15-451", "deadline", "open", now).map((e) => e.id),
    ).toEqual(["deadline-1", "later"]);
    expect(
      filteredEvents(list, "", "all", "soon", now).map((e) => e.id),
    ).toEqual(["deadline-1", "exam"]);
  });
  it("allows a same-day plan for all-day deadlines in the event timezone", () => {
    const e = event({ dateOnly: true, start: "2026-11-04" });
    expect(planStartToday(e, new Date("2026-11-05T03:00:00Z")).valueOf()).toBe(
      eventDate(e)?.valueOf(),
    );
  });
  it("a completed task is never overdue", () => {
    expect(
      urgency(event({ progress: "done" }), new Date("2027-01-01T00:00:00Z")),
    ).toBe("done");
  });
});
