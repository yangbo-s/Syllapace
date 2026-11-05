import type { AcademicEvent, WorkspaceSnapshot } from "./types";

// Imported only under import.meta.env.DEV. No fixture data or preview bridge enters the release.
export function installPreview() {
  const params = new URLSearchParams(location.search);
  const courses = [
    {
      id: "course-algorithms",
      label: "15-451",
      code: "15-451",
      name: "Algorithm Design",
      color: 0,
    },
    {
      id: "course-systems",
      label: "18-613",
      code: "18-613",
      name: "Computer Systems",
      color: 1,
    },
    {
      id: "course-learning",
      label: "10-701",
      code: "10-701",
      name: "Machine Learning",
      color: 3,
    },
  ];
  const seed = [
    [
      "lecture-a",
      0,
      "Lecture · Network flow",
      "meeting",
      "Lecture",
      "2026-11-04T15:30:00-05:00",
      "2026-11-04T16:50:00-05:00",
      "todo",
    ],
    [
      "recitation-a",
      1,
      "Recitation · Memory hierarchy",
      "meeting",
      "Recitation",
      "2026-11-05T11:00:00-05:00",
      "2026-11-05T11:50:00-05:00",
      "todo",
    ],
    [
      "hw4",
      0,
      "Homework 4 · Graph algorithms",
      "deadline",
      "Homework",
      "2026-11-05T23:59:00-05:00",
      null,
      "doing",
    ],
    [
      "lab3",
      1,
      "Lab 3 · Cache simulator",
      "deadline",
      "Lab submission",
      "2026-11-07T23:59:00-05:00",
      null,
      "todo",
    ],
    [
      "project",
      2,
      "Project · Research proposal",
      "deadline",
      "Project",
      "2026-11-10T17:00:00-05:00",
      null,
      "doing",
    ],
    [
      "hw3",
      0,
      "Homework 3 · Dynamic programming",
      "deadline",
      "Homework",
      "2026-11-02T23:59:00-05:00",
      null,
      "done",
    ],
    [
      "quiz2",
      2,
      "Quiz 2 · Regression",
      "assessment",
      "Quiz",
      "2026-11-06T13:30:00-05:00",
      "2026-11-06T14:00:00-05:00",
      "todo",
    ],
    [
      "midterm",
      1,
      "Midterm · Computer systems",
      "assessment",
      "Midterm",
      "2026-11-11T10:00:00-05:00",
      "2026-11-11T11:30:00-05:00",
      "todo",
    ],
  ] as const;
  const snapshot: WorkspaceSnapshot = {
    schemaVersion: 1,
    revision: 1,
    language: params.get("lang") === "zh" ? "zh-Hans" : "en",
    appearance: params.get("theme") === "dark" ? "dark" : "light",
    view: ["list", "kanban", "gantt", "calendar"].includes(
      params.get("view") || "",
    )
      ? (params.get("view") as WorkspaceSnapshot["view"])
      : "list",
    scope: params.get("lang") === "zh" ? "2026 秋季学期" : "Fall 2026",
    loading: false,
    now: "2026-11-04T10:00:00-05:00",
    courses,
    events: params.has("empty")
      ? []
      : seed.map(
          ([id, ci, title, category, subtype, start, end, progress]) =>
            ({
              id,
              courseID: courses[ci].id,
              courseLabel: courses[ci].label,
              title,
              category,
              subtype,
              start,
              end,
              progress,
              dateOnly: false,
              timeZone: "America/New_York",
              plannedStart:
                id === "project" ? "2026-11-03T10:00:00-05:00" : null,
              location: null,
              evidence: "Synthetic preview event.",
              sourceURL: null,
              revision: 1,
            }) satisfies AcademicEvent,
        ),
  };
  window.webkit = {
    messageHandlers: {
      workspace: {
        postMessage: async (command) => {
          if (command.method === "workspace.setView")
            snapshot.view = command.payload.view;
          if (
            command.method === "event.setProgress" ||
            command.method === "event.setPlan"
          ) {
            const event = snapshot.events.find(
              (event) => event.id === command.payload.eventID,
            );
            if (!event || event.revision !== command.payload.expectedRevision)
              return { ok: false, error: "The event changed. Try again." };
            if (command.method === "event.setProgress")
              event.progress = command.payload.progress;
            else event.plannedStart = command.payload.plannedStart;
            event.revision += 1;
          }
          snapshot.revision += 1;
          return { ok: true, snapshot: structuredClone(snapshot) };
        },
      },
    },
  };
}
