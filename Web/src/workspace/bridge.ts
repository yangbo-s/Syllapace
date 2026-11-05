import { useSyncExternalStore } from "react";
import type { Command, WorkspaceSnapshot } from "./types";

let current: WorkspaceSnapshot | null = null;
const listeners = new Set<() => void>();
let sequence = 0;

export async function receive(snapshot: WorkspaceSnapshot): Promise<boolean> {
  if (snapshot.schemaVersion !== 1 || !Array.isArray(snapshot.events))
    return false;
  if (current && snapshot.revision < current.revision) return false;
  current = snapshot;
  document.documentElement.classList.toggle(
    "dark",
    snapshot.appearance === "dark",
  );
  document.documentElement.lang = snapshot.language;
  document.documentElement.style.colorScheme = snapshot.appearance;
  for (const name of ["background", "foreground", "muted", "muted-foreground", "card", "card-foreground", "popover", "popover-foreground", "secondary", "secondary-foreground", "accent", "accent-foreground", "border", "input", "primary", "primary-foreground", "ring", "course-0", "course-1", "course-2", "course-3", "course-4", "course-5"]) {
    const value = snapshot.theme?.[name];
    if (value) document.documentElement.style.setProperty(`--${name}`, value);
    else document.documentElement.style.removeProperty(`--${name}`);
  }
  listeners.forEach((listener) => listener());
  await new Promise<void>((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
  );
  return true;
}
window.syllapace = { receive };

export async function send(command: Command): Promise<void> {
  const handler = window.webkit?.messageHandlers?.workspace;
  if (!handler)
    throw new Error(
      current?.language === "zh-Hans"
        ? "无法连接本机服务。请重新打开工作区。"
        : "Native connection unavailable. Reopen the workspace.",
    );
  const result = await handler.postMessage({
    id: `workspace-${++sequence}`,
    ...command,
  });
  if (!result.ok)
    throw new Error(
      result.error ||
        (current?.language === "zh-Hans"
          ? "操作未完成。"
          : "The action could not be completed."),
    );
  if (result.snapshot) await receive(result.snapshot);
}
function subscribe(callback: () => void) {
  listeners.add(callback);
  return () => {
    listeners.delete(callback);
  };
}
export function useWorkspace() {
  return useSyncExternalStore(subscribe, () => current);
}
