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
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridColumnHeader } from "@/components/reui/data-grid/data-grid-column-header";
import { DataGridPagination } from "@/components/reui/data-grid/data-grid-pagination";
import {
  CourseLabel,
  EventActions,
  EventDate,
  ScheduleStatus,
  categoryIcons,
  type EventContext,
} from "./EventParts";
import { eventDate } from "./model";
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
  const [pagination, setPagination] = useState({ pageIndex: 0, pageSize: 50 });
  const columns = useMemo<ColumnDef<DataGridFeatures, AcademicEvent>[]>(
    () => [
      {
        accessorKey: "title",
        header: ({ column }) => (
          <DataGridColumnHeader column={column} title={t.title} />
        ),
        size: 280,
        meta: { fillWidth: true },
        cell: ({ row }) => {
          const event = row.original;
          const Icon = categoryIcons[event.category];
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
            </div>
          );
        },
      },
      {
        accessorKey: "courseLabel",
        header: t.course,
        size: 96,
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
        size: 108,
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
    [snapshot, run, busy, t],
  );
  const table = useTable({
    features: dataGridFeatures,
    data: events,
    columns,
    getRowId: (event) => event.id,
    state: {
      sorting,
      pagination,
      columnVisibility: {
        courseLabel: new Set(events.map((event) => event.courseID)).size > 1,
      },
    },
    initialState: {
      columnPinning: { start: [], end: ["actions"] },
    },
    onSortingChange: setSorting,
    onPaginationChange: setPagination,
  });
  return (
    <>
    <div className="workspace-toolbar">{tools}</div>
    <DataGrid
      table={table}
      recordCount={events.length}
      tableLayout={{
        dense: true,
        columnsResizable: true,
        rowBorder: true,
        headerBackground: false,
        columnsPinnable: true,
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
          <DataGridScrollArea className="h-full">
            <DataGridTable />
          </DataGridScrollArea>
        </DataGridContainer>
        {events.length > 50 && <DataGridPagination />}
      </div>
    </DataGrid>
    </>
  );
}
