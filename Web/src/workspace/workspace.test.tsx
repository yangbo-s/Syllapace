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
  it("opens the individual occurrence from a recurring class date list", async () => {
    const snapshot = fixture(); const commands: Command[] = [];
    snapshot.events = ["2026-11-04T22:00:00Z", "2026-11-11T22:00:00Z"].map((start, index) => ({ ...snapshot.events[0], id: `class-${index}`, title: "Recitation", category: "meeting", subtype: "recitation", start }));
    bridge(snapshot, command => commands.push(command)); render(<App />);
    await waitFor(() => expect(screen.getByRole("button", { name: "2 dates" })).toBeTruthy());
    await waitFor(() => expect(screen.getByRole("button", { name: "Open event: Recitation" }).hasAttribute("disabled")).toBe(false));
    fireEvent.click(screen.getByRole("button", { name: "2 dates" }));
    fireEvent.click(await screen.findByRole("button", { name: /Nov 11/ }));
    await waitFor(() => expect(commands).toContainEqual(expect.objectContaining({ method: "event.openEditor", payload: { eventID: "class-1" } })));
    expect(snapshot.events).toHaveLength(2);
  });
  it("paginates the list, offers show-all and resets the page for the two-week range", async () => {
    const snapshot = fixture();
    snapshot.events = Array.from({ length: 45 }, (_, index) => ({ ...snapshot.events[0], id: `task-${index}`, title: `Task ${String(index).padStart(2, "0")}`, start: index < 8 ? "2026-11-06T12:00:00Z" : "2026-11-25T12:00:00Z" }));
    bridge(snapshot); const { container } = render(<App />);
    await waitFor(() => expect(screen.getByText("Task 00")).toBeTruthy());
    expect(screen.queryByText("Task 20")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Next page" }));
    expect(screen.getByText("Task 20")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Date range"), { target: { value: "twoWeeks" } });
    expect(screen.getByText("Task 00")).toBeTruthy(); expect(screen.queryByText("Task 20")).toBeNull();
    fireEvent.change(screen.getByLabelText("Date range"), { target: { value: "all" } });
    fireEvent.change(screen.getByLabelText("Rows per page"), { target: { value: "2147483647" } });
    expect(screen.getByText("Task 44")).toBeTruthy();
    expect(container.querySelector('[data-slot="list-pagination"]')).toBeTruthy();
    expect(container.querySelector('[data-slot="list-scroll-viewport"]')).toBeTruthy();
    expect(screen.getByRole("button", { name: "Show history" }).textContent).toContain("History");
  });
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
  it("follows native navigation without a duplicate heading, tabs or status filters", async () => {
    const snapshot = fixture();
    bridge(snapshot);
    render(<App />);
    await screen.findByRole("button", { name: "Homework 4" });
    for (const view of ["gantt", "calendar", "list"] as const) {
      snapshot.view = view; snapshot.revision = ++revision;
      await act(() => receive(structuredClone(snapshot)));
      await waitFor(() => expect(screen.getByRole("main").getAttribute("data-view")).toBe(view));
      if (view === "calendar") expect(document.querySelector('[data-slot="event-calendar-month-view"]')).not.toBeNull();
    }
    expect(screen.queryByRole("tab")).toBeNull();
    expect(screen.queryByRole("heading", { name: "Fall 2026" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Not done" })).toBeNull();
  });
  it("hides history by default, computes active phase, and preserves editor actions", async () => {
    const snapshot = fixture();
    snapshot.events[0].releasedAt = "2026-11-01T10:00:00Z";
    snapshot.events[0].progress = "done";
    snapshot.events.push({ ...snapshot.events[0], id: "past", title: "Past exam", category: "assessment", start: "2026-10-01T10:00:00Z" });
    const commands: Command[] = [];
    bridge(snapshot, command => commands.push(command));
    await act(() => receive(snapshot));
    render(<App />);
    await screen.findByRole("button", { name: "Homework 4" });
    expect(screen.getByText("In progress")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Past exam" })).toBeNull();
    expect(screen.queryByText("Done")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Show history" }));
    await screen.findByRole("button", { name: "Past exam" });
    expect(screen.getByText("Historical")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Hide history" }));
    expect(screen.queryByRole("button", { name: "Past exam" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Homework 4" }));
    await waitFor(() => expect(commands).toContainEqual(expect.objectContaining({ method: "event.openEditor", payload: { eventID: "hw4" } })));
    await waitFor(() => expect(screen.getByRole("button", { name: "Open event: Homework 4" }).hasAttribute("disabled")).toBe(false));
    fireEvent.click(screen.getByRole("button", { name: "Open event: Homework 4" }));
    await screen.findByRole("menuitem", { name: "Open event" });
    expect(screen.queryByRole("menuitem", { name: "View source" })).toBeNull();
  });
  it("adopts native theme colors and removes stale overrides", async () => {
    const snapshot = fixture();
    snapshot.theme = { background: "rgb(30, 30, 30)", primary: "rgb(90, 140, 200)" };
    snapshot.appearance = "dark";
    await act(() => receive(snapshot));
    expect(document.documentElement.style.getPropertyValue("--background")).toBe("rgb(30, 30, 30)");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
    await act(() => receive({ ...snapshot, revision: ++revision, appearance: "light", theme: undefined }));
    expect(document.documentElement.style.getPropertyValue("--background")).toBe("");
  });
  it("does not overwrite a newer snapshot with a stale reply", async () => {
    const snapshot = fixture();
    bridge(snapshot);
    await act(() => receive(snapshot));
    render(<App />);
    await screen.findByRole("button", { name: "Homework 4" });
    await act(() =>
      receive({ ...snapshot, revision: 1, events: [] }),
    );
    expect(screen.getByRole("button", { name: "Homework 4" })).toBeTruthy();
  });
});
