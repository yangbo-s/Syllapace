import {
  CalendarDays,
  Check,
  Circle,
  Clock3,
  ExternalLink,
  GraduationCap,
  MoreHorizontal,
  Play,
  SquarePen,
  Target,
} from "lucide-react";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  courseColor,
  eventDate,
  formatDate,
  planStartToday,
  progressValues,
  urgency,
} from "./model";
import { strings } from "./strings";
import type { AcademicEvent, Command, WorkspaceSnapshot } from "./types";

export type RunCommand = (command: Command) => Promise<void>;
export interface EventContext {
  snapshot: WorkspaceSnapshot;
  run: RunCommand;
  busy: boolean;
}
export const categoryIcons = {
  meeting: GraduationCap,
  deadline: Target,
  assessment: SquarePen,
  academic: CalendarDays,
};

export function CourseLabel({
  event,
  snapshot,
}: {
  event: AcademicEvent;
  snapshot: WorkspaceSnapshot;
}) {
  return (
    <span className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground">
      <span
        className="size-1.5 shrink-0 rounded-full"
        style={{ backgroundColor: courseColor(event, snapshot.courses) }}
        aria-hidden
      />
      <span className="truncate">{event.courseLabel}</span>
    </span>
  );
}
export function EventDate({
  event,
  snapshot,
}: {
  event: AcademicEvent;
  snapshot: WorkspaceSnapshot;
}) {
  return (
    <time
      dateTime={event.start || undefined}
      className="text-xs tabular-nums text-muted-foreground"
    >
      {formatDate(event, snapshot.language)}
    </time>
  );
}
export function UrgencyBadge({
  event,
  snapshot,
}: {
  event: AcademicEvent;
  snapshot: WorkspaceSnapshot;
}) {
  const value = urgency(event, new Date(snapshot.now));
  const t = strings(snapshot.language);
  if (
    event.category !== "deadline" ||
    !["overdue", "today", "soon"].includes(value)
  )
    return null;
  return (
    <Badge
      variant={value === "overdue" ? "destructive-light" : "warning-light"}
    >
      {t[value]}
    </Badge>
  );
}
export function ProgressControl({
  event,
  snapshot,
  run,
  busy,
}: EventContext & { event: AcademicEvent }) {
  const t = strings(snapshot.language);
  if (event.category !== "deadline")
    return (
      <span className="text-xs text-muted-foreground">
        {eventDate(event) && eventDate(event)! < new Date(snapshot.now)
          ? t.past
          : t.scheduled}
      </span>
    );
  const Icon =
    event.progress === "done"
      ? Check
      : event.progress === "doing"
        ? Play
        : Circle;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            type="button"
            variant="ghost"
            size="sm"
            disabled={busy}
            aria-label={`${event.title}: ${t.status}`}
          />
        }
      >
        <Icon data-icon="inline-start" />
        {t[event.progress]}
      </DropdownMenuTrigger>
      <DropdownMenuContent>
        <DropdownMenuGroup>
          <DropdownMenuLabel>{t.status}</DropdownMenuLabel>
          {progressValues.map((progress) => (
            <DropdownMenuItem
              key={progress}
              onClick={() =>
                void run({
                  method: "event.setProgress",
                  payload: {
                    eventID: event.id,
                    expectedRevision: event.revision,
                    progress,
                  },
                })
              }
            >
              {t[progress]}
              {progress === event.progress && <Check />}
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
export function EventActions({
  event,
  snapshot,
  run,
  busy,
}: EventContext & { event: AcademicEvent }) {
  const t = strings(snapshot.language);
  const due = eventDate(event);
  const now = new Date(snapshot.now);
  const plannedStart = planStartToday(event, now);
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            type="button"
            variant="ghost"
            size="icon-sm"
            aria-label={`${t.edit}: ${event.title}`}
            disabled={busy}
          />
        }
      >
        <MoreHorizontal />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuGroup>
          <DropdownMenuItem
            onClick={() =>
              void run({
                method: "event.openEditor",
                payload: { eventID: event.id },
              })
            }
          >
            <SquarePen />
            {t.edit}
          </DropdownMenuItem>
          {event.sourceURL && (
            <DropdownMenuItem
              onClick={() =>
                void run({
                  method: "source.open",
                  payload: { eventID: event.id },
                })
              }
            >
              <ExternalLink />
              {t.source}
            </DropdownMenuItem>
          )}
        </DropdownMenuGroup>
        {event.category === "deadline" && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              {progressValues.map((progress) => (
                <DropdownMenuItem
                  key={progress}
                  onClick={() =>
                    void run({
                      method: "event.setProgress",
                      payload: {
                        eventID: event.id,
                        expectedRevision: event.revision,
                        progress,
                      },
                    })
                  }
                >
                  {t[progress]}
                </DropdownMenuItem>
              ))}
            </DropdownMenuGroup>
            {due && due >= plannedStart && (
              <>
                <DropdownMenuSeparator />
                <DropdownMenuGroup>
                  <DropdownMenuItem
                    onClick={() =>
                      void run({
                        method: "event.setPlan",
                        payload: {
                          eventID: event.id,
                          expectedRevision: event.revision,
                          plannedStart: plannedStart.toISOString(),
                        },
                      })
                    }
                  >
                    <Clock3 />
                    {t.plan} · {t.today}
                  </DropdownMenuItem>
                  {event.plannedStart && (
                    <DropdownMenuItem
                      onClick={() =>
                        void run({
                          method: "event.setPlan",
                          payload: {
                            eventID: event.id,
                            expectedRevision: event.revision,
                            plannedStart: null,
                          },
                        })
                      }
                    >
                      {t.resetPlan}
                    </DropdownMenuItem>
                  )}
                </DropdownMenuGroup>
              </>
            )}
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
