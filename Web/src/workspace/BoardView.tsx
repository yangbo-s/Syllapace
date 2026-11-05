import { useEffect, useState } from "react";
import { GripVertical } from "lucide-react";
import {
  Kanban,
  KanbanBoard,
  KanbanColumn,
  KanbanColumnContent,
  KanbanItem,
  KanbanItemHandle,
  KanbanOverlay,
} from "@/components/reui/kanban";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { boardColumns } from "./model";
import {
  CourseLabel,
  EventActions,
  EventDate,
  UrgencyBadge,
  type EventContext,
} from "./EventParts";
import { strings } from "./strings";
import type { AcademicEvent, Progress } from "./types";

export function BoardView({
  events,
  snapshot,
  run,
  busy,
}: EventContext & { events: AcademicEvent[] }) {
  const [columns, setColumns] = useState(() => boardColumns(events));
  const t = strings(snapshot.language);
  useEffect(() => {
    setColumns(boardColumns(events));
  }, [events]);
  return (
    <div className="min-h-0 flex-1 overflow-auto">
      <Kanban
        value={columns}
        onValueChange={setColumns}
        getItemValue={(item) => item.id}
        restoreOnCancel
        onValueCommit={(next, meta) => {
          if (meta.kind !== "item") return;
          const event = next[meta.overContainer]?.[meta.overIndex];
          if (!event || event.progress === meta.overContainer) return;
          setColumns(boardColumns(events));
          void run({
            method: "event.setProgress",
            payload: {
              eventID: event.id,
              expectedRevision: event.revision,
              progress: meta.overContainer as Progress,
            },
          });
        }}
      >
        <KanbanBoard className="grid min-w-[660px] grid-cols-3 items-start gap-4">
          {Object.entries(columns).map(([progress, tasks]) => (
            <KanbanColumn key={progress} value={progress}>
              <div className="flex items-center gap-2 pb-3">
                <h2 className="text-sm font-semibold">
                  {t[progress as Progress]}
                </h2>
                <Badge variant="outline">{tasks.length}</Badge>
              </div>
              <KanbanColumnContent
                value={progress}
                className="flex min-h-40 flex-col gap-3"
              >
                {tasks.map((event) => (
                  <KanbanItem key={event.id} value={event.id} disabled={busy}>
                    <Card size="sm">
                      <CardHeader>
                        <div className="flex items-start justify-between gap-1">
                          <CourseLabel event={event} snapshot={snapshot} />
                          <div className="flex shrink-0 items-center gap-1">
                            <KanbanItemHandle
                              render={
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="icon-xs"
                                  aria-label={
                                    snapshot.language === "en"
                                      ? `Move ${event.title}`
                                      : `移动 ${event.title}`
                                  }
                                />
                              }
                            >
                              <GripVertical />
                            </KanbanItemHandle>
                            <EventActions
                              event={event}
                              snapshot={snapshot}
                              run={run}
                              busy={busy}
                            />
                          </div>
                        </div>
                        <CardTitle>
                          <button
                            type="button"
                            className="text-left hover:underline focus-visible:outline-2 focus-visible:outline-ring"
                            onClick={() =>
                              void run({
                                method: "event.openEditor",
                                payload: { eventID: event.id },
                              })
                            }
                          >
                            {event.title}
                          </button>
                        </CardTitle>
                      </CardHeader>
                      <CardContent>
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <EventDate event={event} snapshot={snapshot} />
                          <UrgencyBadge event={event} snapshot={snapshot} />
                        </div>
                      </CardContent>
                    </Card>
                  </KanbanItem>
                ))}
              </KanbanColumnContent>
            </KanbanColumn>
          ))}
        </KanbanBoard>
        <KanbanOverlay>
          <Card size="sm">
            <CardContent>
              <span className="text-sm">{t.title}</span>
            </CardContent>
          </Card>
        </KanbanOverlay>
      </Kanban>
    </div>
  );
}
