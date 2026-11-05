export type WorkspaceView = "list" | "kanban" | "gantt" | "calendar";
export type Progress = "todo" | "doing" | "done";
export type Category = "meeting" | "deadline" | "assessment" | "academic";
export type Language = "en" | "zh-Hans";
export interface Course {
  id: string;
  label: string;
  code: string;
  name: string;
  color: number;
}
export interface AcademicEvent {
  id: string;
  courseID: string;
  courseLabel: string;
  title: string;
  category: Category;
  subtype: string;
  start: string | null;
  end: string | null;
  dateOnly: boolean;
  timeZone: string;
  progress: Progress;
  plannedStart: string | null;
  location?: string | null;
  evidence: string;
  sourceURL?: string | null;
  revision: number;
}
export interface WorkspaceSnapshot {
  schemaVersion: 1;
  revision: number;
  language: Language;
  appearance: "light" | "dark";
  view: WorkspaceView;
  scope: string;
  loading: boolean;
  needsSemester?: boolean;
  now: string;
  courses: Course[];
  events: AcademicEvent[];
}
export interface WorkspaceReply {
  ok: boolean;
  snapshot?: WorkspaceSnapshot;
  error?: string;
}
export type Command =
  | {
      method:
        | "workspace.ready"
        | "workspace.addMaterial"
        | "workspace.chooseSemester"
        | "event.create";
      payload: Record<string, never>;
    }
  | { method: "workspace.setView"; payload: { view: WorkspaceView } }
  | {
      method: "event.setProgress";
      payload: {
        eventID: string;
        expectedRevision: number;
        progress: Progress;
      };
    }
  | {
      method: "event.setPlan";
      payload: {
        eventID: string;
        expectedRevision: number;
        plannedStart: string | null;
      };
    }
  | {
      method: "event.openEditor" | "source.open";
      payload: { eventID: string };
    };
declare global {
  interface Window {
    syllapace: { receive: (snapshot: WorkspaceSnapshot) => Promise<boolean> };
    webkit?: {
      messageHandlers?: {
        workspace?: {
          postMessage: (
            message: Command & { id: string },
          ) => Promise<WorkspaceReply>;
        };
      };
    };
  }
}
