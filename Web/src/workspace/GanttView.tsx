import { useMemo } from "react";
import { enUS, zhCN } from "date-fns/locale";
import { Gantt } from "@/components/reui/gantt/gantt";
import { GanttNav } from "@/components/reui/gantt/gantt-nav";
import { GanttView as GanttTimeline } from "@/components/reui/gantt/gantt-view";
import type {
  GanttEvent,
  GanttResource,
} from "@/components/reui/gantt/gantt-types";
import {
  courseColor,
  dateKey,
  displayDate,
  eventDate,
  ganttBounds,
  planFromDisplay,
} from "./model";
import { ganttChinese } from "./calendarI18n";
import type { AcademicEvent } from "./types";
import type { EventContext } from "./EventParts";

export function GanttView({
  events,
  snapshot,
  run,
  busy,
}: EventContext & { events: AcademicEvent[] }) {
  const displayZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const { resources, bars } = useMemo(() => {
    const resources: GanttResource[] = [];
    const bars: GanttEvent<AcademicEvent>[] = [];
    for (const event of events) {
      const bounds = ganttBounds(event);
      if (!bounds) continue;
      let group = resources.find((resource) => resource.id === event.courseID);
      if (!group) {
        group = { id: event.courseID, title: event.courseLabel, children: [] };
        resources.push(group);
      }
      group.children!.push({ id: event.id, title: event.title });
      bars.push({
        id: event.id,
        title: event.title,
        start: event.dateOnly
          ? displayDate(
              event,
              dateKey(bounds.start, event.timeZone),
              displayZone,
            )!
          : bounds.start,
        end: event.dateOnly
          ? displayDate(
              event,
              dateKey(bounds.end, event.timeZone),
              displayZone,
            )!
          : bounds.end,
        allDay: event.dateOnly,
        resourceId: event.id,
        progress: event.progress === "done" ? 100 : undefined,
        readOnly: !bounds.isPlan || busy,
        draggable: false,
        resizable: bounds.isPlan,
        color: courseColor(event, snapshot.courses),
        data: event,
      });
    }
    return { resources, bars };
  }, [events, snapshot.courses, busy, displayZone]);
  return (
    <Gantt
      resources={resources}
      events={bars}
      defaultDate={new Date(snapshot.now)}
      defaultScale="month"
      timeZone={displayZone}
      locale={snapshot.language === "zh-Hans" ? zhCN : enUS}
      i18n={
        snapshot.language === "zh-Hans"
          ? ganttChinese
          : { labels: { resources: "Courses & events" } }
      }
      rowCheckboxes={false}
      summaryBars={false}
      barLabel="auto"
      interactions={{ drag: false, resize: true, selectSlot: false }}
      enforceCanDrop
      canDropEvent={(update) =>
        update.source === "resize-start" &&
        planFromDisplay(update.event.data!, update.start, displayZone) <=
          (eventDate(update.event.data!) ?? update.start)
      }
      onEventUpdate={(update) => {
        if (update.source !== "resize-start" || !update.event.data)
          return false;
        const event = update.event.data;
        void run({
          method: "event.setPlan",
          payload: {
            eventID: event.id,
            expectedRevision: event.revision,
            plannedStart: planFromDisplay(
              event,
              update.start,
              displayZone,
            ).toISOString(),
          },
        });
        // Swift persists first and sends the authoritative snapshot; source deadlines never move.
        return false;
      }}
      onEventClick={(occurrence) =>
        void run({
          method: "event.openEditor",
          payload: { eventID: occurrence.event.id },
        })
      }
      className="min-h-0 flex-1"
    >
      <GanttNav />
      <GanttTimeline />
    </Gantt>
  );
}
