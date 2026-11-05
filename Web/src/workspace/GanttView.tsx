import { useMemo, useState } from "react";
import { enUS, zhCN } from "date-fns/locale";
import { Gantt } from "@/components/reui/gantt/gantt";
import { GanttNav, GanttNavToday, GanttNavPrev, GanttNavNext, GanttTitle, GanttScaleSwitcher } from "@/components/reui/gantt/gantt-nav";
import { GanttView as GanttTimeline } from "@/components/reui/gantt/gantt-view";
import type {
  GanttScale,
  GanttEvent,
  GanttResource,
} from "@/components/reui/gantt/gantt-types";
import { getGanttDateRange } from "@/components/reui/gantt/gantt-lib";
import {
  courseColor,
  dateKey,
  displayDate,
  ganttBounds,
} from "./model";
import { ganttChinese } from "./calendarI18n";
import type { AcademicEvent } from "./types";
import type { EventContext } from "./EventParts";

export function GanttView({
  events,
  snapshot,
  run,
  tools,
}: EventContext & { events: AcademicEvent[] }) {
  const displayZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [date, setDate] = useState(() => new Date(snapshot.now));
  const [scale, setScale] = useState<GanttScale>("month");
  const { resources, bars } = useMemo(() => {
    const resources: GanttResource[] = [];
    const bars: GanttEvent<AcademicEvent>[] = [];
    const { visibleRange } = getGanttDateRange(scale, date, { timeZone: displayZone, weekStartsOn: 1 });
    for (const event of events) {
      const bounds = ganttBounds(event);
      if (!bounds) continue;
      const start = (bounds.isRelease ? event.releaseDateOnly : event.dateOnly)
        ? displayDate({ ...event, dateOnly: true }, dateKey(bounds.start, event.timeZone), displayZone)! : bounds.start;
      const end = event.dateOnly ? displayDate(event, dateKey(bounds.end, event.timeZone), displayZone)! : bounds.end;
      if (end < visibleRange.start || start >= visibleRange.end) continue;
      let group = resources.find((resource) => resource.id === event.courseID);
      if (!group) {
        group = { id: event.courseID, title: event.courseLabel, children: [] };
        resources.push(group);
      }
      group.children!.push({ id: event.id, title: event.title });
      bars.push({
        id: event.id,
        title: event.title,
        start,
        end,
        allDay: event.dateOnly,
        resourceId: event.id,
        readOnly: true,
        draggable: false,
        resizable: false,
        color: courseColor(event, snapshot.courses),
        data: event,
      });
    }
    return { resources, bars };
  }, [events, snapshot.courses, displayZone, date, scale]);
  return (
    <Gantt
      resources={resources}
      events={bars}
      date={date}
      onDateChange={setDate}
      scale={scale}
      onScaleChange={setScale}
      infiniteScroll={false}
      scrollbars="native"
      metrics={{ unitWidths: { month: 0.75 } }}
      initialCenter="anchor"
      offDays={{ className: "bg-muted/25" }}
      zoomControl={false}
      wheelZoom={false}
      offscreenIndicators={false}
      timeZone={displayZone}
      locale={snapshot.language === "zh-Hans" ? zhCN : enUS}
      i18n={
        snapshot.language === "zh-Hans"
          ? ganttChinese
          : { labels: { resources: "Courses & events" } }
      }
      treePanel={{ width: 216, minWidth: 180, maxWidth: 360 }}
      rowCheckboxes={false}
      summaryBars={false}
      barLabel="none"
      interactions={{ drag: false, resize: false, selectSlot: false }}
      onResourceClick={({ resource, isGroup }) => {
        if (!isGroup) void run({ method: "event.openEditor", payload: { eventID: resource.id } });
      }}
      onEventClick={(occurrence) =>
        void run({
          method: "event.openEditor",
          payload: { eventID: occurrence.event.id },
        })
      }
      className="min-h-0 flex-1"
    >
      <GanttNav className="workspace-view-toolbar"><GanttNavPrev /><GanttNavNext /><GanttTitle /><GanttNavToday /><div className="grow" /><GanttScaleSwitcher />{tools}</GanttNav>
      <GanttTimeline />
    </Gantt>
  );
}
