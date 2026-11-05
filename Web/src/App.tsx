import { useCallback, useEffect, useMemo, useState } from "react";
import { CalendarDays, History, ListFilter, Search, X } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { TooltipProvider } from "@/components/ui/tooltip";
import { send, useWorkspace } from "./workspace/bridge";
import { eventsForView, filteredEvents, scheduleStatus } from "./workspace/model";
import { strings } from "./workspace/strings";
import type { Category, Command } from "./workspace/types";
import { ListView } from "./workspace/ListView";
import { GanttView } from "./workspace/GanttView";
import { CalendarView } from "./workspace/CalendarView";
import { uniqueOccurrences } from "./workspace/schedule";

export function App() {
  const snapshot = useWorkspace();
  const [query, setQuery] = useState("");
  const [showHistory, setShowHistory] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [category, setCategory] = useState<Category | "all">("all");
  const [error, setError] = useState<string | null>(null);
  const [lastCommand, setLastCommand] = useState<Command | null>(null);
  const [busy, setBusy] = useState(false);
  const t = strings(snapshot?.language || "en");
  const run = useCallback(async (command: Command) => {
    setBusy(true); setError(null); setLastCommand(command);
    try { await send(command); }
    catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setBusy(false); }
  }, []);
  useEffect(() => { void run({ method: "workspace.ready", payload: {} }); }, [run]);
  const events = useMemo(() => snapshot ? filteredEvents(uniqueOccurrences(snapshot.events), query, category) : [], [snapshot, query, category]);
  function clearFilters() { setQuery(""); setCategory("all"); }
  const visible = snapshot ? eventsForView(events.filter(event => showHistory || scheduleStatus(event, new Date(snapshot.now)) !== "historical"), snapshot.view, category) : [];
  const tools = <div className="workspace-tools">
    <Button variant={showHistory ? "secondary" : "ghost"} size="sm" aria-label={showHistory ? t.hideHistory : t.showHistory} title={showHistory ? t.hideHistory : t.showHistory} aria-pressed={showHistory} onClick={() => setShowHistory(value => !value)}><History />{snapshot?.language === "zh-Hans" ? "历史" : "History"}</Button>
    {searchOpen ? <Input type="search" autoFocus className="h-7 w-44" placeholder={t.search} aria-label={t.search} value={query}
      onChange={(event) => setQuery(event.target.value)} onKeyDown={(event) => { if (event.key === "Escape") { setQuery(""); setSearchOpen(false); } }} />
      : <Button variant="ghost" size="icon-sm" aria-label={t.search} title={t.search} onClick={() => setSearchOpen(true)}><Search /></Button>}
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="ghost" size={category === "all" ? "icon-sm" : "sm"} aria-label={t.categories} title={t.categories} />}>
        <ListFilter />{category !== "all" && t[category]}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end"><DropdownMenuGroup><DropdownMenuRadioGroup value={category} onValueChange={(value) => setCategory(value as Category | "all")}>
        {(["all", "meeting", "deadline", "assessment", ...(snapshot?.events.some(e => e.category === "academic") ? ["academic"] : [])] as Array<Category | "all">).map(value =>
          <DropdownMenuRadioItem key={value} value={value}>{t[value]}</DropdownMenuRadioItem>)}
      </DropdownMenuRadioGroup></DropdownMenuGroup></DropdownMenuContent>
    </DropdownMenu>
    {(query || category !== "all") && <Button variant="ghost" size="icon-sm" aria-label={t.clear} onClick={clearFilters}><X /></Button>}
  </div>;
  const empty = (title: string, body: string, action: string, onClick: () => void) => <Empty>
    <EmptyHeader><EmptyMedia variant="icon"><CalendarDays /></EmptyMedia><EmptyTitle>{title}</EmptyTitle>{body && <EmptyDescription>{body}</EmptyDescription>}</EmptyHeader>
    <EmptyContent><Button size="sm" onClick={onClick} disabled={busy}>{action}</Button></EmptyContent>
  </Empty>;
  const context = snapshot ? { snapshot, run, busy, tools } : null;
  return <TooltipProvider><main className="workspace" aria-label="Syllapace workspace" data-view={snapshot?.view}>
    {error && <Alert variant="destructive"><AlertTitle>{t.errorTitle}</AlertTitle><AlertDescription>{error}</AlertDescription><AlertAction>
      <Button variant="outline" size="sm" disabled={busy} onClick={() => void run(lastCommand || { method: "workspace.ready", payload: {} })}>{t.retry}</Button>
      <Button variant="ghost" size="icon-sm" aria-label={t.close} onClick={() => setError(null)}><X /></Button>
    </AlertAction></Alert>}
    {!snapshot || (snapshot.loading && !snapshot.events.length) ? <div role="status" className="flex flex-col gap-3 p-4"><span className="sr-only">{t.loadingConnection}</span>{[0,1,2,3,4].map(i => <Skeleton key={i} className="h-10 w-full" />)}</div>
      : !snapshot.events.length ? empty(snapshot.needsSemester ? t.chooseSemester : t.emptyTitle, snapshot.needsSemester ? t.chooseSemesterBody : t.empty,
        snapshot.needsSemester ? t.chooseSemester : t.import, () => void run({ method: snapshot.needsSemester ? "workspace.chooseSemester" : "workspace.addMaterial", payload: {} }))
      : !visible.length && snapshot.view === "list" ? <><div className="workspace-toolbar">{tools}</div>{empty(events.length && !showHistory ? t.noUpcoming : events.length ? t.noDates : t.noMatches,
        "", events.length && !showHistory ? t.showHistory : events.length ? t.list : t.clear,
        () => events.length && !showHistory ? setShowHistory(true) : events.length ? void run({ method: "workspace.setView", payload: { view: "list" } }) : clearFilters())}</>
      : context && (snapshot.view === "list" ? <ListView {...context} events={visible} /> : snapshot.view === "gantt" ? <GanttView {...context} events={visible} /> : <CalendarView {...context} events={visible} />)}
  </main></TooltipProvider>;
}
