import type { ReactNode } from "react";
import { CalendarDays, ExternalLink, GraduationCap, MoreHorizontal, SquarePen, Target } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { courseColor, formatDate, scheduleStatus } from "./model";
import { strings } from "./strings";
import type { AcademicEvent, Command, WorkspaceSnapshot } from "./types";

export type RunCommand = (command: Command) => Promise<void>;
export interface EventContext { snapshot: WorkspaceSnapshot; run: RunCommand; busy: boolean; tools?: ReactNode; }
export const categoryIcons = { meeting: GraduationCap, deadline: Target, assessment: SquarePen, academic: CalendarDays };

export function CourseLabel({ event, snapshot }: { event: AcademicEvent; snapshot: WorkspaceSnapshot }) {
  return <span className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground" title={event.courseLabel}>
    <span className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: courseColor(event, snapshot.courses) }} aria-hidden />
    <span className="truncate">{event.courseLabel}</span>
  </span>;
}
export function EventDate({ event, snapshot }: { event: AcademicEvent; snapshot: WorkspaceSnapshot }) {
  return <time dateTime={event.start || undefined} className="text-xs tabular-nums text-muted-foreground">{formatDate(event, snapshot.language)}</time>;
}
export function ScheduleStatus({ event, snapshot }: { event: AcademicEvent; snapshot: WorkspaceSnapshot }) {
  const status = scheduleStatus(event, new Date(snapshot.now));
  return <span className={status === "active" ? "text-xs text-foreground" : "text-xs text-muted-foreground"}>{strings(snapshot.language)[status]}</span>;
}
export function EventActions({ event, snapshot, run, busy }: EventContext & { event: AcademicEvent }) {
  const t = strings(snapshot.language);
  return <DropdownMenu>
    <DropdownMenuTrigger render={<Button type="button" variant="ghost" size="icon-sm" aria-label={`${t.edit}: ${event.title}`} disabled={busy} />}><MoreHorizontal /></DropdownMenuTrigger>
    <DropdownMenuContent align="end"><DropdownMenuGroup>
      <DropdownMenuItem onClick={() => void run({ method: "event.openEditor", payload: { eventID: event.id } })}><SquarePen />{t.edit}</DropdownMenuItem>
      {event.sourceURL && <DropdownMenuItem onClick={() => void run({ method: "source.open", payload: { eventID: event.id } })}><ExternalLink />{t.source}</DropdownMenuItem>}
    </DropdownMenuGroup></DropdownMenuContent>
  </DropdownMenu>;
}
