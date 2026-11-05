// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { App } from "../App";
import { receive } from "./bridge";
import type { Command, WorkspaceSnapshot } from "./types";
import { EventCalendar } from "@/components/reui/event-calendar/event-calendar";
import { EventCalendarContent } from "@/components/reui/event-calendar/event-calendar-content";

beforeAll(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  );
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) =>
    setTimeout(() => callback(0), 0),
  );
  vi.stubGlobal("cancelAnimationFrame", clearTimeout);
  window.matchMedia = () => ({
    matches: false,
    media: "",
    onchange: null,
    addListener() {},
    removeListener() {},
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent: () => true,
  });
  Element.prototype.scrollIntoView = () => {};
  Element.prototype.scrollTo = () => {};
  Element.prototype.getAnimations = () => [];
});
afterEach(cleanup);
let revision = 100;
function fixture(): WorkspaceSnapshot {
  return {
    schemaVersion: 1,
    revision: ++revision,
    language: "en",
    appearance: "light",
    view: "list",
    scope: "Fall 2026",
    loading: false,
    now: "2026-11-04T15:00:00Z",
    courses: [
      {
        id: "course1",
        label: "15-451",
        code: "15-451",
        name: "Algorithms",
        color: 0,
      },
    ],
    events: [
      {
        id: "hw4",
        courseID: "course1",
        courseLabel: "15-451",
        title: "Homework 4",
        category: "deadline",
        subtype: "Homework",
        start: "2026-11-06T04:59:00Z",
        end: null,
        dateOnly: false,
        timeZone: "America/New_York",
        progress: "todo",
        plannedStart: null,
        evidence: "Homework 4 is due November 5 at 23:59.",
        revision: 2,
      },
    ],
  };
}
function bridge(
  snapshot: WorkspaceSnapshot,
  onCommand: (command: Command) => void = () => {},
) {
  window.webkit = {
    messageHandlers: {
      workspace: {
        postMessage: async (command) => {
          onCommand(command);
          if (command.method === "workspace.setView")
            snapshot.view = command.payload.view;
          if (command.method === "event.setProgress")
            snapshot.events[0].progress = command.payload.progress;
          snapshot.revision = ++revision;
          return { ok: true, snapshot: structuredClone(snapshot) };
        },
      },
    },
  };
}
describe("workspace boundary", () => {
  it.each(["2026-11-04T12:00:00-05:00", "2026-03-11T12:00:00-04:00"])(
    "keeps the calendar gutter on civil clock labels in the DST week of %s",
    (now) => {
      const { container } = render(
        <EventCalendar
          events={[]}
          defaultDate={new Date(now)}
          defaultView="week"
          timeZone="America/New_York"
          weekStartsOn={0}
        >
          <EventCalendarContent />
        </EventCalendar>,
      );
      const labels = [
        ...container.querySelectorAll(
          "[data-slot=event-calendar-time-gutter] > div",
        ),
      ].map((row) => row.textContent);
      expect(labels).toHaveLength(24);
      expect(labels[1]).toBe("1 AM");
      expect(labels[2]).toBe("2 AM");
      expect(labels[11]).toBe("11 AM");
      expect(labels[23]).toBe("11 PM");
    },
  );
  it("renders every view from the same native event snapshot and sends view selection", async () => {
    const snapshot = fixture();
    const commands: Command[] = [];
    bridge(snapshot, (command) => commands.push(command));
    render(<App />);
    await screen.findByRole("button", { name: "Homework 4" });
    for (const [label, id] of [
      ["Board", "kanban"],
      ["Gantt", "gantt"],
      ["Calendar", "calendar"],
      ["List", "list"],
    ]) {
      fireEvent.click(screen.getByRole("tab", { name: label }));
      await waitFor(() =>
        expect(screen.getByRole("tabpanel").getAttribute("data-view")).toBe(id),
      );
    }
    expect(
      commands.filter((command) => command.method === "workspace.setView"),
    ).toHaveLength(4);
  });
  it("sends expected event revision and adopts native progress, without exposing source actions when absent", async () => {
    const snapshot = fixture();
    const commands: Command[] = [];
    bridge(snapshot, (command) => commands.push(command));
    await act(() => receive(snapshot));
    render(<App />);
    await screen.findByRole("button", { name: "Homework 4: Progress" });
    await waitFor(() =>
      expect(
        screen
          .getByRole("button", { name: "Homework 4: Progress" })
          .hasAttribute("disabled"),
      ).toBe(false),
    );
    fireEvent.click(
      screen.getByRole("button", { name: "Homework 4: Progress" }),
    );
    fireEvent.click(
      await screen.findByRole("menuitem", { name: "In progress" }),
    );
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Homework 4: Progress" })
          .textContent,
      ).toContain("In progress"),
    );
    expect(commands).toContainEqual(
      expect.objectContaining({
        method: "event.setProgress",
        payload: { eventID: "hw4", expectedRevision: 2, progress: "doing" },
      }),
    );
    await waitFor(() =>
      expect(
        screen
          .getByRole("button", { name: "Open event: Homework 4" })
          .hasAttribute("disabled"),
      ).toBe(false),
    );
    fireEvent.click(
      screen.getByRole("button", { name: "Open event: Homework 4" }),
    );
    await screen.findByRole("menuitem", { name: "Open event" });
    expect(screen.queryByRole("menuitem", { name: "View source" })).toBeNull();
  });
  it("does not overwrite a newer snapshot with a stale reply", async () => {
    const snapshot = fixture();
    bridge(snapshot);
    await act(() => receive(snapshot));
    render(<App />);
    await screen.findByRole("heading", { name: "Fall 2026" });
    await act(() =>
      receive({ ...snapshot, revision: 1, scope: "Stale semester" }),
    );
    expect(
      screen.queryByRole("heading", { name: "Stale semester" }),
    ).toBeNull();
  });
});
