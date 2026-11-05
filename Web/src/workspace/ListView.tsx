import { useMemo, useState } from "react";
import {
  useTable,
  type ColumnDef,
  type SortingState,
} from "@tanstack/react-table";
import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
  type DataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";

import { DataGridColumnHeader } from "@/components/reui/data-grid/data-grid-column-header";
import { Button } from "@/components/ui/button";
import { Popover, PopoverTrigger, PopoverContent } from "@/components/ui/popover";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { inTwoWeeks, scheduleGroups } from "./schedule";
import {
  CourseLabel,
  EventActions,
  EventDate,
  ScheduleStatus,
  categoryIcons,
  type EventContext,
} from "./EventParts";
import { eventDate, formatDate } from "./model";
import { strings } from "./strings";
import type { AcademicEvent } from "./types";

export function ListView({
  events,
  snapshot,
  run,
  busy,
  tools,
}: EventContext & { events: AcademicEvent[] }) {
  const t = strings(snapshot.language);
  const [sorting, setSorting] = useState<SortingState>([]);
  const [pagination, setPagination] = useState({ pageIndex: 0, pageSize: 20 });
  const [range, setRange] = useState("all");
  const zh = snapshot.language === "zh-Hans";
  const groups = useMemo(() => scheduleGroups(events.filter(e => range === "all" || inTwoWeeks(e, new Date(snapshot.now), Intl.DateTimeFormat().resolvedOptions().timeZone)), new Date(snapshot.now)), [events, snapshot.now, range]);
  const rows = groups.map(group => group.event);
  const pageCount = Math.max(1, Math.ceil(rows.length / pagination.pageSize));
  const pageIndex = Math.min(pagination.pageIndex, pageCount - 1);
  const columns = useMemo<ColumnDef<DataGridFeatures, AcademicEvent>[]>(
    () => [
      {
        accessorKey: "title",
        header: ({ column }) => (
          <DataGridColumnHeader column={column} title={t.title} />
        ),
        size: 240,
        meta: { fillWidth: true },
        cell: ({ row }) => {
          const event = row.original;
          const Icon = categoryIcons[event.category];
          const group = groups.find(g => g.event.id === event.id);
          return (
            <div className="flex min-w-0 items-center gap-3">
              <Icon
                className="size-4 shrink-0 text-muted-foreground"
                aria-hidden
              />
              <div className="flex min-w-0 flex-col gap-1">
                <button
                  type="button"
                  className="line-clamp-2 whitespace-normal text-left font-medium hover:underline focus-visible:outline-2 focus-visible:outline-ring"
                  onClick={() =>
                    void run({
                      method: "event.openEditor",
                      payload: { eventID: event.id },
                    })
                  }
                >
                  {event.title}
                </button>
              </div>
              {group && group.occurrences.length > 1 && <Popover><PopoverTrigger render={<Button variant="ghost" size="sm" className="ml-auto shrink-0 text-muted-foreground" />}>
                {zh ? `${group.occurrences.length} 次` : `${group.occurrences.length} dates`}
              </PopoverTrigger><PopoverContent className="w-72 p-1" align="start">
                <div className="max-h-64 overflow-auto" aria-label={zh ? "重复课次" : "Recurring dates"}>
                {group.occurrences.map(occurrence => <Button key={occurrence.id} variant="ghost" className="w-full justify-start" onClick={() => void run({ method: "event.openEditor", payload: { eventID: occurrence.id } })}>
                  {formatDate(occurrence, snapshot.language)}
                </Button>)}</div>
              </PopoverContent></Popover>}

            </div>
          );
        },
      },
      {
        accessorKey: "courseLabel",
        header: t.course,
        size: 120,
        cell: ({ row }) => (
          <CourseLabel event={row.original} snapshot={snapshot} />
        ),
      },
      {
        id: "date",
        accessorFn: (event) => eventDate(event)?.valueOf() ?? Infinity,
        header: ({ column }) => (
          <DataGridColumnHeader column={column} title={t.date} />
        ),
        size: 160,
        cell: ({ row }) => (
          <div className="flex flex-col items-start gap-1.5 whitespace-normal">
            <EventDate event={row.original} snapshot={snapshot} />
          </div>
        ),
      },
      {
        id: "scheduleStatus",
        header: t.status,
        size: 96,
        cell: ({ row }) => (
          <ScheduleStatus
            event={row.original}
            snapshot={snapshot}
          />
        ),
      },
      {
        id: "actions",
        header: "",
        size: 40,
        enableResizing: false,
        meta: { cellClassName: "px-1 text-center" },
        cell: ({ row }) => (
          <EventActions
            event={row.original}
            snapshot={snapshot}
            run={run}
            busy={busy}
          />
        ),
      },
    ],
    [snapshot, run, busy, t, groups, zh],
  );
  const table = useTable({
    features: dataGridFeatures,
    data: rows,
    columns,
    getRowId: (event) => event.id,
    state: {
      sorting,
      pagination: { ...pagination, pageIndex },
      columnVisibility: {
        courseLabel: new Set(events.map((event) => event.courseID)).size > 1,
      },
    },
    onSortingChange: setSorting,
    onPaginationChange: setPagination,
  });
  return (
    <>
    <div className="workspace-toolbar">
      <select aria-label={zh ? "日期范围" : "Date range"} className="workspace-select mr-auto" value={range} onChange={e => { setRange(e.target.value); setPagination(p => ({ ...p, pageIndex: 0 })); }}>
        <option value="all">{zh ? "全部日程" : "All dates"}</option><option value="twoWeeks">{zh ? "本周和下周" : "This week & next"}</option>
      </select>{tools}</div>
    <DataGrid
      table={table}
      recordCount={rows.length}
      tableLayout={{
        dense: true,
        columnsResizable: false,
        rowBorder: true,
        headerBackground: false,
        columnsPinnable: false,
      }}
      i18n={
        snapshot.language === "zh-Hans"
          ? {
              labels: {
                sortAscending: "升序",
                sortDescending: "降序",
                loading: t.loading,
                empty: t.noMatches,
                rowsPerPage: "每页",
                paginationInfo: ({ from, to, count }) =>
                  `${from}–${to} / ${count}`,
                previousPage: "上一页",
                nextPage: "下一页",
                goToPage: (page) => `第 ${page} 页`,
              },
            }
          : undefined
      }
    >
      <div className="flex min-h-0 flex-1 flex-col gap-3">
        <DataGridContainer className="min-h-0 flex-1">
          <div data-slot="list-scroll-viewport" className="h-full overflow-auto">
            <DataGridTable />
          </div>
        </DataGridContainer>
        <div className="flex shrink-0 items-center gap-2 pt-1" data-slot="list-pagination">
          <select aria-label={zh ? "每页显示" : "Rows per page"} className="workspace-select" value={pagination.pageSize} onChange={e => setPagination({ pageIndex: 0, pageSize: Number(e.target.value) })}>
            {[20, 50, 100].map(size => <option key={size} value={size}>{zh ? `每页 ${size} 项` : `${size} per page`}</option>)}
            <option value={2147483647}>{zh ? "显示全部" : "Show all"}</option>
          </select>
          <span className="ml-auto text-muted-foreground" aria-live="polite">{rows.length ? pageIndex * pagination.pageSize + 1 : 0}–{Math.min((pageIndex + 1) * pagination.pageSize, rows.length)} / {rows.length}</span>
          <Button variant="ghost" size="icon-sm" aria-label={zh ? "上一页" : "Previous page"} disabled={pageIndex === 0} onClick={() => setPagination(p => ({ ...p, pageIndex: pageIndex - 1 }))}><ChevronLeft /></Button>
          <span>{pageIndex + 1} / {pageCount}</span>
          <Button variant="ghost" size="icon-sm" aria-label={zh ? "下一页" : "Next page"} disabled={pageIndex >= pageCount - 1} onClick={() => setPagination(p => ({ ...p, pageIndex: pageIndex + 1 }))}><ChevronRight /></Button>
        </div>
      </div>
    </DataGrid>
    </>
  );
}
