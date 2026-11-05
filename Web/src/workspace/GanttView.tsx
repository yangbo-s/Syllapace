import { useEffect, useMemo, useRef, useState } from "react";
import { getDaysInMonth, startOfMonth, addMonths } from "date-fns";
import { enUS, zhCN } from "date-fns/locale";
import { Gantt } from "@/components/reui/gantt/gantt";
import { GanttNav, GanttNavToday, GanttNavPrev, GanttNavNext, GanttTitle, GanttScaleSwitcher } from "@/components/reui/gantt/gantt-nav";
import { GanttView as GanttTimeline } from "@/components/reui/gantt/gantt-view";
import type {
  GanttScale,
  GanttEvent,
  GanttResource,
  GanttDateRange,
} from "@/components/reui/gantt/gantt-types";
import { scheduleGroups } from "./schedule";
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
  const container = useRef<HTMLDivElement>(null);
  const [monthUnit, setMonthUnit] = useState(1);
  const [range, setRange] = useState<GanttDateRange | null>(null);
  useEffect(() => {
    const pane = container.current?.querySelector<HTMLElement>("[data-slot=gantt-timeline-pane] [data-slot=scroll-area-viewport]");
    if (!pane) return;
    const update = () => setMonthUnit(pane.clientWidth / getDaysInMonth(date) / parseFloat(getComputedStyle(document.documentElement).fontSize));
    const observer = new ResizeObserver(update); observer.observe(pane); update();
    return () => observer.disconnect();
  }, [date]);
  const { resources, bars } = useMemo(() => {
    const resources: GanttResource[] = [];
    const bars: GanttEvent<AcademicEvent>[] = [];
    const groups = scheduleGroups(events, new Date(snapshot.now));
    for (const series of groups) {
      for (const event of series.occurrences) {
      const bounds = ganttBounds(event);
      if (!bounds) continue;
      const start = (bounds.isRelease ? event.releaseDateOnly : event.dateOnly)
        ? displayDate({ ...event, dateOnly: true }, dateKey(bounds.start, event.timeZone), displayZone)! : bounds.start;
      const end = event.dateOnly ? displayDate(event, dateKey(bounds.end, event.timeZone), displayZone)! : bounds.end;
      if (range && (end < range.start || start >= range.end)) continue;
      let group = resources.find((resource) => resource.id === event.courseID);
      if (!group) {
        group = { id: event.courseID, title: event.courseLabel, children: [] };
        resources.push(group);
      }
      if (!group.children!.some(row => row.id === series.event.id)) group.children!.push({ id: series.event.id, title: series.event.title });
      bars.push({
        id: event.id,
        title: event.title,
        start,
        end,
        allDay: event.dateOnly,
        resourceId: series.event.id,
        readOnly: true,
        draggable: false,
        resizable: false,
        color: courseColor(event, snapshot.courses),
        data: event,
      });
    }
    }
    return { resources, bars };
  }, [events, snapshot.courses, snapshot.now, displayZone, range]);
  return (
    <div ref={container} className="flex min-h-0 flex-1 flex-col"><Gantt
      resources={resources}
      events={bars}
      date={date}
      onDateChange={setDate}
      scale={scale}
      onScaleChange={setScale}
      infiniteScroll={true}
      onRangeChange={({ range: next }) => setRange(next)}
      scrollbars="native"
      metrics={{ unitWidths: { month: monthUnit } }}
      initialCenter={scale === "month" ? new Date((+startOfMonth(date) + +addMonths(startOfMonth(date), 1)) / 2) : "anchor"}
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
    </Gantt></div>
  );
}
