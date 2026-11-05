import { describe, expect, it } from "vitest";
import { addDays } from "date-fns";
import {
  clockMinutes,
  dateAtClockMinutes,
  getDayTotalMinutes,
  segmentOccurrence,
  zonedStartOfDay,
} from "@/components/reui/event-calendar/event-calendar-lib";
import type { EventCalendarOccurrence } from "@/components/reui/event-calendar/event-calendar-types";

const zone = "America/New_York";
function occurrence(start: string, end: string): EventCalendarOccurrence {
  const event = {
    id: "lecture",
    title: "Lecture",
    start: new Date(start),
    end: new Date(end),
  };
  return {
    key: "lecture",
    eventId: event.id,
    event,
    start: event.start,
    end: event.end,
    allDay: false,
    isRecurring: false,
  };
}
describe("ReUI civil calendar coordinates", () => {
  it.each([
    ["fall-back day", "2026-11-01T11:00:00-05:00", "2026-11-01T12:20:00-05:00"],
    [
      "spring-forward day",
      "2026-03-08T11:00:00-04:00",
      "2026-03-08T12:20:00-04:00",
    ],
    ["ordinary day", "2026-11-04T11:00:00-05:00", "2026-11-04T12:20:00-05:00"],
  ])(
    "places 11:00 at the same clock row and reverses a slot on %s",
    (_, start, end) => {
      const event = occurrence(start, end);
      const day = zonedStartOfDay(event.start, zone);
      const segments = segmentOccurrence(
        event,
        { start: day, end: addDays(day, 1) },
        zone,
      );
      expect(
        segments.map((segment) => [segment.startMin, segment.endMin]),
      ).toEqual([[660, 740]]);
      expect(dateAtClockMinutes(day, 660, zone).valueOf()).toBe(
        event.start.valueOf(),
      );
      expect(clockMinutes(event.start, day, zone)).toBe(660);
      expect(getDayTotalMinutes()).toBe(1440);
    },
  );
  it("keeps cross-midnight end exclusive and splits the repeated-hour day correctly", () => {
    const event = occurrence(
      "2026-10-31T23:30:00-04:00",
      "2026-11-01T03:30:00-05:00",
    );
    const day = zonedStartOfDay(event.start, zone);
    const segments = segmentOccurrence(
      event,
      { start: day, end: addDays(day, 2) },
      zone,
    );
    expect(
      segments.map((segment) => [segment.startMin, segment.endMin]),
    ).toEqual([
      [1410, 1440],
      [0, 210],
    ]);
    expect(dateAtClockMinutes(day, 1440, zone).valueOf()).toBe(
      new Date("2026-11-01T00:00:00-04:00").valueOf(),
    );
  });
  it("places both fall-back 01:30 instants on the 01:30 clock row without changing their instants", () => {
    const day = new Date("2026-11-01T00:00:00-04:00");
    for (const iso of [
      "2026-11-01T01:30:00-04:00",
      "2026-11-01T01:30:00-05:00",
    ])
      expect(clockMinutes(new Date(iso), day, zone)).toBe(90);
  });
});
