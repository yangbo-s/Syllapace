import { useMemo } from "react";
import { addDays } from "date-fns";
import { enUS, zhCN } from "date-fns/locale";
import { EventCalendar } from "@/components/reui/event-calendar/event-calendar";
import { EventCalendarContent } from "@/components/reui/event-calendar/event-calendar-content";
import { EventCalendarNav, EventCalendarNavToday, EventCalendarNavPrev, EventCalendarNavNext, EventCalendarTitle, EventCalendarViewSwitcher } from "@/components/reui/event-calendar/event-calendar-nav";
import type { CalendarEvent } from "@/components/reui/event-calendar/event-calendar-types";
import { courseColor, displayDate } from "./model";
import { calendarChinese } from "./calendarI18n";
import type { AcademicEvent } from "./types";
import type { EventContext } from "./EventParts";

export function CalendarView({
  events,
  snapshot,
  run,
  tools,
}: EventContext & { events: AcademicEvent[] }) {
  const displayZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const calendarEvents = useMemo<CalendarEvent<AcademicEvent>[]>(
    () =>
      events.flatMap((event) => {
        const start = displayDate(event, event.start, displayZone);
        if (!start) return [];
        // An instantaneous deadline gets a one-millisecond render interval, never a stored duration.
        const end =
          displayDate(event, event.end, displayZone) ??
          (event.dateOnly ? addDays(start, 1) : new Date(start.valueOf() + 1));
        return [
          {
            id: event.id,
            title: event.title,
            start,
            end,
            allDay: event.dateOnly,
            color: courseColor(event, snapshot.courses),
            readOnly: true,
            data: event,
          },
        ];
      }),
    [events, snapshot.courses, displayZone],
  );
  return (
    <EventCalendar
      events={calendarEvents}
      defaultDate={new Date(snapshot.now)}
      defaultView="month"
      scrollToHour={9}
      views={["month", "week", "day", "agenda"]}
      timeZone={displayZone}
      locale={snapshot.language === "zh-Hans" ? zhCN : enUS}
      i18n={snapshot.language === "zh-Hans" ? calendarChinese : undefined}
      interactions={{ drag: false, resize: false, selectSlot: false }}
      onEventClick={(occurrence) =>
        void run({
          method: "event.openEditor",
          payload: { eventID: occurrence.event.id },
        })
      }
      className="min-h-0 flex-1"
    >
      <EventCalendarNav className="workspace-view-toolbar"><EventCalendarNavPrev /><EventCalendarNavNext /><EventCalendarTitle /><EventCalendarNavToday /><div className="grow" /><EventCalendarViewSwitcher />{tools}</EventCalendarNav>
      <EventCalendarContent />
    </EventCalendar>
  );
}
