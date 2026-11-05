import { useCallback, useEffect, useMemo, useState } from "react";
import {
  CalendarDays,
  CalendarRange,
  ChevronDown,
  Columns3,
  List,
  ListFilter,
  X,
} from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { TooltipProvider } from "@/components/ui/tooltip";
import { send, useWorkspace } from "./workspace/bridge";
import { eventsForView, filteredEvents, type Filter } from "./workspace/model";
import { strings } from "./workspace/strings";
import type { Category, Command, WorkspaceView } from "./workspace/types";
import { ListView } from "./workspace/ListView";
import { BoardView } from "./workspace/BoardView";
import { GanttView } from "./workspace/GanttView";
import { CalendarView } from "./workspace/CalendarView";

const views = [
  { id: "list", icon: List },
  { id: "kanban", icon: Columns3 },
  { id: "gantt", icon: CalendarRange },
  { id: "calendar", icon: CalendarDays },
] as const;

export function App() {
  const snapshot = useWorkspace();
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<Category | "all">("all");
  const [filter, setFilter] = useState<Filter>("all");
  const [error, setError] = useState<string | null>(null);
  const [lastCommand, setLastCommand] = useState<Command | null>(null);
  const [busy, setBusy] = useState(false);
  const t = strings(snapshot?.language || "en");
  const run = useCallback(async (command: Command) => {
    setBusy(true);
    setError(null);
    setLastCommand(command);
    try {
      await send(command);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }, []);
  useEffect(() => {
    void run({ method: "workspace.ready", payload: {} });
  }, [run]);
  const events = useMemo(
    () =>
      snapshot
        ? filteredEvents(
            snapshot.events,
            query,
            category,
            filter,
            new Date(snapshot.now),
          )
        : [],
    [snapshot, query, category, filter],
  );
  function clearFilters() {
    setQuery("");
    setCategory("all");
    setFilter("all");
  }
  const visibleEvents = snapshot
    ? eventsForView(events, snapshot.view, category)
    : [];
  const visibleCount = visibleEvents.length;
  const activeFilters = Boolean(
    query || category !== "all" || filter !== "all",
  );
  const context = snapshot ? { snapshot, run, busy } : null;

  const empty = (
    title: string,
    body: string,
    action: string,
    onClick: () => void,
  ) => (
    <Empty>
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <CalendarDays />
        </EmptyMedia>
        <EmptyTitle>{title}</EmptyTitle>
        <EmptyDescription>{body}</EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button type="button" size="sm" onClick={onClick} disabled={busy}>
          {action}
        </Button>
      </EmptyContent>
    </Empty>
  );
  return (
    <TooltipProvider>
      <main
        className="flex h-full min-h-0 min-w-0 flex-col gap-4 p-6"
        aria-label="Syllapace workspace"
      >
        {error && (
          <Alert variant="destructive">
            <AlertTitle>{t.errorTitle}</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
            <AlertAction>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={busy}
                onClick={() =>
                  void run(
                    lastCommand || { method: "workspace.ready", payload: {} },
                  )
                }
              >
                {t.retry}
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                aria-label={t.close}
                onClick={() => setError(null)}
              >
                <X />
              </Button>
            </AlertAction>
          </Alert>
        )}
        {!snapshot ? (
          <div role="status" className="flex min-h-0 flex-1 flex-col gap-4">
            <span className="sr-only">{t.loadingConnection}</span>
            <Skeleton className="h-8 w-80" />
            <Skeleton className="h-8 w-full" />
            {[0, 1, 2, 3, 4].map((i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        ) : (
          <>
            <header className="flex min-w-0 items-center justify-between gap-3">
              <h1 className="truncate text-xl font-semibold tracking-tight">
                {snapshot.scope}
              </h1>
              <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                {visibleCount}{" "}
                {visibleCount === 1 && snapshot.language === "en"
                  ? "event"
                  : t.events}
              </span>
            </header>
            <Tabs
              value={snapshot.view}
              onValueChange={(value) => {
                if (views.some((view) => view.id === value))
                  void run({
                    method: "workspace.setView",
                    payload: { view: value as WorkspaceView },
                  });
              }}
              className="min-h-0 flex-1 gap-4"
            >
              <div className="flex min-w-0 flex-wrap items-center justify-between gap-3 border-b pb-3">
                <TabsList
                  variant="line"
                  aria-label={
                    snapshot.language === "en" ? "Workspace view" : "工作区视图"
                  }
                >
                  {views.map(({ id, icon: Icon }) => (
                    <TabsTrigger key={id} value={id}>
                      <Icon data-icon="inline-start" />
                      {t[id]}
                    </TabsTrigger>
                  ))}
                </TabsList>
                <div className="w-60 min-w-0 max-w-full">
                  <Input
                    type="search"
                    placeholder={t.search}
                    aria-label={t.search}
                    value={query}
                    onChange={(event) => setQuery(event.target.value)}
                  />
                </div>
              </div>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <ToggleGroup
                  value={[filter]}
                  onValueChange={(values) => {
                    if (values[0]) setFilter(values[0] as Filter);
                  }}
                  size="sm"
                  aria-label={t.status}
                >
                  {(["all", "open", "soon", "done"] as const).map((value) => (
                    <ToggleGroupItem key={value} value={value}>
                      {t[value]}
                    </ToggleGroupItem>
                  ))}
                </ToggleGroup>
                <div className="flex items-center gap-2">
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      render={
                        <Button type="button" variant="outline" size="sm" />
                      }
                    >
                      <ListFilter data-icon="inline-start" />
                      {category === "all"
                        ? snapshot.view === "gantt"
                          ? t.plans
                          : t.categories
                        : t[category]}
                      <ChevronDown data-icon="inline-end" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuGroup>
                        <DropdownMenuRadioGroup
                          value={category}
                          onValueChange={(value) =>
                            setCategory(value as Category | "all")
                          }
                        >
                          {(
                            [
                              "all",
                              "meeting",
                              "deadline",
                              "assessment",
                              ...(snapshot.events.some(
                                (e) => e.category === "academic",
                              )
                                ? ["academic"]
                                : []),
                            ] as Array<Category | "all">
                          ).map((value) => (
                            <DropdownMenuRadioItem key={value} value={value}>
                              {value === "all" && snapshot.view === "gantt"
                                ? t.plans
                                : t[value]}
                            </DropdownMenuRadioItem>
                          ))}
                        </DropdownMenuRadioGroup>
                      </DropdownMenuGroup>
                    </DropdownMenuContent>
                  </DropdownMenu>
                  {activeFilters && (
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon-sm"
                      aria-label={t.clear}
                      onClick={clearFilters}
                    >
                      <X />
                    </Button>
                  )}
                </div>
              </div>
              {views.map(({ id }) => (
                <TabsContent
                  key={id}
                  value={id}
                  className="flex min-h-0 flex-1 flex-col"
                  data-view={id}
                >
                  {snapshot.loading && !snapshot.events.length ? (
                    <div role="status" className="flex flex-col gap-3">
                      <span className="sr-only">{t.loading}</span>
                      {[0, 1, 2, 3, 4].map((i) => (
                        <Skeleton key={i} className="h-12 w-full" />
                      ))}
                    </div>
                  ) : !snapshot.events.length ? (
                    empty(
                      snapshot.needsSemester ? t.chooseSemester : t.emptyTitle,
                      snapshot.needsSemester ? t.chooseSemesterBody : t.empty,
                      snapshot.needsSemester ? t.chooseSemester : t.import,
                      () =>
                        void run({
                          method: snapshot.needsSemester
                            ? "workspace.chooseSemester"
                            : "workspace.addMaterial",
                          payload: {},
                        }),
                    )
                  ) : !events.length ? (
                    empty(t.noMatches, "", t.clear, clearFilters)
                  ) : (
                    context &&
                    (id === "list" ? (
                      <ListView {...context} events={events} />
                    ) : id === "kanban" ? (
                      events.some((event) => event.category === "deadline") ? (
                        <BoardView
                          {...context}
                          events={events.filter(
                            (event) => event.category === "deadline",
                          )}
                        />
                      ) : (
                        empty(
                          t.noTasks,
                          t.noTasksBody,
                          t.list,
                          () =>
                            void run({
                              method: "workspace.setView",
                              payload: { view: "list" },
                            }),
                        )
                      )
                    ) : id === "gantt" &&
                      !visibleEvents.length &&
                      events.some((event) => event.start) ? (
                      empty(
                        t.noPlans,
                        t.noPlansBody,
                        t.list,
                        () =>
                          void run({
                            method: "workspace.setView",
                            payload: { view: "list" },
                          }),
                      )
                    ) : !events.some((event) => event.start) ? (
                      empty(
                        t.noDates,
                        t.noDatesBody,
                        t.list,
                        () =>
                          void run({
                            method: "workspace.setView",
                            payload: { view: "list" },
                          }),
                      )
                    ) : id === "gantt" ? (
                      <GanttView {...context} events={visibleEvents} />
                    ) : (
                      <CalendarView {...context} events={events} />
                    ))
                  )}
                </TabsContent>
              ))}
            </Tabs>
          </>
        )}
      </main>
    </TooltipProvider>
  );
}
