import { useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowsClockwise, BookOpen, Browsers, CalendarBlank, CaretLeft, CaretRight,
  ChartBar, Check, CheckCircle, Clock, Code, DotsSixVertical, DotsThree,
  FileText, Flask, GearSix, GlobeSimple, Laptop, LinkSimple,
  LockSimple, NotePencil, Pause, Play, Plus, ShieldCheck, TerminalWindow,
  Timer, Trash, TrendUp, X,
} from "@phosphor-icons/react";
import { SiArxiv, SiVscodium, SiYoutube } from "@icons-pack/react-simple-icons";

const VSCodeLogo = ({ weight: _weight, ...props }) => <SiVscodium {...props} color="#1683d8" />;
const ArxivLogo = ({ weight: _weight, ...props }) => <SiArxiv {...props} color="#b31b1b" />;
const YouTubeLogo = ({ weight: _weight, ...props }) => <SiYoutube {...props} color="#ff0033" />;

const DAY_START = 8 * 60;
const DAY_END = 20 * 60;
const HOUR_HEIGHT = 66;

const initialTasks = [
  { id: "genezip", title: "GeneZip rebuttal experiment", tags: ["research", "important"], start: 14 * 60, end: 16 * 60, completed: false, tone: "accent" },
  { id: "reviewer", title: "Read reviewer 2", tags: ["review"], start: 16 * 60 + 15, end: 17 * 60, completed: false, tone: "soft" },
  { id: "draft", title: "Draft response", tags: ["writing"], start: null, end: null, completed: false, tone: "soft" },
];

const navItems = [
  { id: "today", label: "Today", icon: CalendarBlank },
  { id: "plan", label: "Plan", icon: NotePencil },
  { id: "review", label: "Review", icon: ChartBar },
  { id: "rules", label: "Rules", icon: ShieldCheck },
];

const fixedPlanBlocks = [
  { id: "literature", title: "Literature review", start: 9 * 60, end: 10 * 60 + 30, icon: FileText },
  { id: "notes", title: "Notes & synthesis", start: 10 * 60 + 30, end: 12 * 60, icon: BookOpen },
  { id: "lunch", title: "Lunch", start: 12 * 60, end: 13 * 60, icon: Clock },
  { id: "prep", title: "Implementation prep", start: 13 * 60, end: 14 * 60, icon: Code },
  { id: "genezip", title: "GeneZip rebuttal experiment", start: 14 * 60, end: 16 * 60, icon: Flask, current: true },
  { id: "results", title: "Results analysis", start: 16 * 60, end: 18 * 60, icon: ChartBar },
  { id: "write", title: "Write up", start: 18 * 60, end: 19 * 60, icon: NotePencil },
];

const actualBlocks = [
  { id: "idle-am", start: 8 * 60, end: 9 * 60, label: "Idle", detail: "No significant activity", kind: "idle" },
  { id: "code-am", start: 9 * 60, end: 10 * 60 + 25, kind: "related", minutes: "85m", rows: [
    { icon: VSCodeLogo, label: "VS Code", time: "09:00–09:45" },
    { icon: TerminalWindow, label: "Terminal", time: "09:45–10:25" },
  ] },
  { id: "research-am", start: 10 * 60 + 30, end: 12 * 60, kind: "related", minutes: "90m", rows: [
    { icon: ArxivLogo, label: "arXiv PDF", time: "10:30–11:15" },
    { icon: BookOpen, label: "Notes", time: "11:15–12:00" },
  ] },
  { id: "lunch-actual", start: 12 * 60, end: 13 * 60, label: "Lunch / Break", detail: "12:00–13:00", kind: "idle" },
  { id: "prep-actual", start: 13 * 60, end: 13 * 60 + 55, kind: "related", minutes: "55m", rows: [{ icon: VSCodeLogo, label: "VS Code", time: "13:00–13:55" }] },
  { id: "current-actual", start: 14 * 60, end: 15 * 60 + 52, kind: "current", rows: [
    { minutes: "8m", label: "Idle", time: "14:00–14:08", kind: "idle" },
    { minutes: "71m", icon: VSCodeLogo, label: "VS Code", time: "14:08–15:19", kind: "related" },
    { minutes: "12m", icon: YouTubeLogo, label: "YouTube", time: "15:19–15:31", kind: "distracted" },
    { minutes: "21m", icon: TerminalWindow, label: "Terminal", time: "15:31–15:52", kind: "related" },
  ] },
  { id: "idle-pm", start: 16 * 60, end: 18 * 60, label: "Idle", detail: "16:00–18:00", kind: "idle" },
  { id: "idle-evening", start: 18 * 60, end: 19 * 60, label: "Idle", detail: "18:00–19:00", kind: "idle" },
];

function formatTime(minutes) {
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

function formatRange(start, end) {
  return start == null || end == null ? "" : `${formatTime(start)}–${formatTime(end)}`;
}

function blockStyle(start, end) {
  return { top: `${((start - DAY_START) / 60) * HOUR_HEIGHT}px`, height: `${Math.max(((end - start) / 60) * HOUR_HEIGHT, 34)}px` };
}

function Sidebar({ page, setPage }) {
  return (
    <aside className="sidebar">
      <div className="brand-lockup"><strong>Metriday 日衡</strong><span>Local-first · On this Mac</span></div>
      <nav className="primary-nav" aria-label="Primary navigation">
        {navItems.map(({ id, label, icon: Icon }) => (
          <button key={id} type="button" className={`nav-item ${page === id ? "active" : ""}`} onClick={() => setPage(id)} aria-label={label} aria-current={page === id ? "page" : undefined}>
            <Icon size={23} weight={page === id ? "duotone" : "regular"} /><span>{label}</span>
          </button>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div className="local-state"><Laptop size={22} /><span>Data on this Mac</span><i aria-label="Local data healthy" /></div>
        <button type="button" className="footer-link"><GearSix size={22} /><span>Settings</span></button>
        <div className="sync-state"><CheckCircle size={17} weight="fill" /><span>Synced 09:02</span></div>
      </div>
    </aside>
  );
}

function IconButton({ label, children, onClick, className = "" }) {
  return <button type="button" className={`icon-button ${className}`} aria-label={label} title={label} onClick={onClick}>{children}</button>;
}

function TodayHeader({ focusRunning, setFocusRunning, setPage }) {
  return (
    <header className="today-header">
      <div className="date-heading">
        <h1>Saturday, August 15, 2026</h1>
        <div className="date-controls"><CalendarBlank size={21} /><button type="button" className="quiet-pill">Today</button><IconButton label="Previous day"><CaretLeft size={18} /></IconButton><IconButton label="Next day"><CaretRight size={18} /></IconButton></div>
      </div>
      <div className="current-session">
        <div className="session-copy"><span>Current block</span><strong>GeneZip rebuttal experiment</strong><p>14:00–16:00 <b>·</b> <em>{focusRunning ? "In progress" : "Paused"}</em></p></div>
        <button type="button" className="primary-button" onClick={() => setFocusRunning((value) => !value)}>{focusRunning ? <Pause size={18} weight="fill" /> : <Play size={18} weight="fill" />}{focusRunning ? "Pause focus" : "Resume focus"}</button>
        <div className="focus-rule"><ShieldCheck size={38} color="#39a65a" weight="duotone" /><div><strong>Research Focus</strong><span>Blocklist active</span><button type="button" onClick={() => setPage("rules")}>Adjust allowed sites</button></div></div>
      </div>
    </header>
  );
}

function HourLabels({ end = 19 }) {
  const hours = Array.from({ length: end - 7 }, (_, index) => index + 8);
  return <div className="hour-labels" aria-hidden="true">{hours.map((hour) => <span key={hour} style={{ top: `${(hour - 8) * HOUR_HEIGHT}px` }}>{String(hour).padStart(2, "0")}:00</span>)}</div>;
}

function GridLines({ end = 19 }) {
  const hours = Array.from({ length: end - 7 }, (_, index) => index + 8);
  return <div className="grid-lines" aria-hidden="true">{hours.map((hour) => <i key={hour} style={{ top: `${(hour - 8) * HOUR_HEIGHT}px` }} />)}</div>;
}

function PlannedTrack() {
  return (
    <section className="today-track planned-track" aria-label="Planned timeline">
      <div className="track-heading"><strong>Plan</strong><span>What I planned</span></div>
      <div className="track-canvas"><GridLines />{fixedPlanBlocks.map(({ id, title, start, end, icon: Icon, current }) => (
        <button key={id} type="button" className={`planned-block ${current ? "current" : ""}`} style={blockStyle(start, end)}><Icon size={18} weight="duotone" /><span><strong>{title}</strong><small>{formatRange(start, end)}</small></span></button>
      ))}</div>
    </section>
  );
}

function ActualRows({ block }) {
  if (!block.rows) return <div className="actual-simple"><strong>{Math.round(block.end - block.start)}m</strong><span><b>{block.label}</b><small>{block.detail}</small></span></div>;
  return <div className="actual-row-list">{block.rows.map((row, index) => { const Icon = row.icon; return (
    <div key={`${block.id}-${index}`} className={`actual-row ${row.kind || block.kind}`}><strong>{row.minutes || (index === 0 ? block.minutes : "")}</strong><span className="activity-icon">{Icon ? <Icon size={20} weight="duotone" /> : null}</span><b>{row.label}</b><small>{row.time}</small></div>
  ); })}</div>;
}

function ActualTrack() {
  return (
    <section className="today-track actual-track" aria-label="Actual activity timeline">
      <div className="track-heading"><strong>Actual</strong><span>What actually happened</span></div>
      <div className="track-canvas"><GridLines />{actualBlocks.map((block) => <div key={block.id} className={`actual-block ${block.kind}`} style={blockStyle(block.start, block.end)}><ActualRows block={block} /></div>)}</div>
    </section>
  );
}

function TodayPage({ setPage }) {
  const [focusRunning, setFocusRunning] = useState(false);
  return (
    <main className="page today-page">
      <TodayHeader focusRunning={focusRunning} setFocusRunning={setFocusRunning} setPage={setPage} />
      <div className="today-comparison"><div className="timeline-label-column"><HourLabels /></div><PlannedTrack /><ActualTrack /><div className="now-marker" aria-label="Current time 15:52"><span /></div></div>
      <div className="insight-bar"><TrendUp size={26} color="#4f63ef" weight="duotone" /><div><p><strong>Started 8 min late</strong><b>·</b><strong className="positive">82% task-related</strong><b>·</b><strong className="warning">Estimate likely +25 min</strong></p><span>YouTube 12m (15:19–15:31) was outside Research Focus. Consider blocking during deep work.</span></div><button type="button" className="secondary-button" onClick={() => setPage("rules")}><ShieldCheck size={18} /> Adjust blocklist</button></div>
    </main>
  );
}

function TimeEditor({ task, onSchedule }) {
  const [value, setValue] = useState(formatRange(task.start, task.end));
  useEffect(() => setValue(formatRange(task.start, task.end)), [task.start, task.end]);
  const commit = () => {
    const match = value.match(/^(\d{1,2}):(\d{2})\s*[–-]\s*(\d{1,2}):(\d{2})$/);
    if (!match) return setValue(formatRange(task.start, task.end));
    const start = Number(match[1]) * 60 + Number(match[2]);
    const end = Number(match[3]) * 60 + Number(match[4]);
    if (start >= DAY_START && end > start && end <= DAY_END) onSchedule(task.id, start, end); else setValue(formatRange(task.start, task.end));
  };
  return <input className="markdown-time-input" aria-label={`Scheduled time for ${task.title}`} value={value} onChange={(event) => setValue(event.target.value)} onBlur={commit} onKeyDown={(event) => { if (event.key === "Enter") event.currentTarget.blur(); }} />;
}

function MarkdownTaskLine({ task, line, active, onDragStart, onPointerDragStart, onSelectTask, onComplete, onTitleChange, onSchedule }) {
  return (
    <div className={`editor-line task-line ${active ? "recently-updated" : ""}`} draggable onDragStart={(event) => onDragStart(event, task.id)} data-task-id={task.id}>
      <span className="line-number">{line}</span><button type="button" className="drag-handle" aria-label={`Drag ${task.title} to calendar`} onPointerDown={(event) => onPointerDragStart(event, task.id)} onClick={() => onSelectTask(task.id)}><DotsSixVertical size={16} /></button><span className="markdown-token">- [</span>
      <button type="button" className="markdown-check" onClick={() => onComplete(task.id)} aria-label={`Mark ${task.title} ${task.completed ? "incomplete" : "complete"}`}>{task.completed ? <Check size={13} weight="bold" /> : null}</button><span className="markdown-token">]</span>
      {task.start != null ? <TimeEditor task={task} onSchedule={onSchedule} /> : null}
      <input className={`task-title-input ${task.completed ? "completed" : ""}`} value={task.title} onChange={(event) => onTitleChange(task.id, event.target.value)} aria-label={`Task title: ${task.title}`} />
      <span className="tag-list">{task.tags.map((tag) => <button type="button" key={tag} className="markdown-tag">#{tag}</button>)}</span>
      {active ? <span className="inline-success"><CheckCircle size={15} weight="fill" /> Time added</span> : null}
    </div>
  );
}

function MarkdownEditor({ tasks, setTasks, lastUpdatedId, onTaskDragStart, onPointerDragStart, onSelectTask, onSchedule, addTask }) {
  const [newTitle, setNewTitle] = useState("");
  const updateTask = (id, patch) => setTasks((items) => items.map((task) => task.id === id ? { ...task, ...patch } : task));
  return (
    <section className="markdown-editor" aria-label="Markdown daily plan">
      <div className="editor-toolbar"><div className="file-name"><FileText size={18} /> 2026-08-15.md <CaretRight size={13} /></div><div className="editor-actions"><span>Markdown</span><IconButton label="Document actions"><DotsThree size={22} /></IconButton></div></div>
      <div className="editor-body">
        <div className="editor-line heading-line"><span className="line-number">1</span><span className="heading-mark">#</span><strong>Saturday, August 15, 2026</strong></div>
        <div className="editor-line quote-line"><span className="line-number">2</span><span className="heading-mark">&gt;</span><em>Plan deep work. Ship calm results.</em></div>
        <div className="editor-line empty-line"><span className="line-number">3</span></div>
        <div className="editor-line section-line"><span className="line-number">4</span><span className="heading-mark">##</span><strong>Focus</strong></div>
        {tasks.map((task, index) => <MarkdownTaskLine key={task.id} task={task} line={5 + index} active={lastUpdatedId === task.id} onDragStart={onTaskDragStart} onPointerDragStart={onPointerDragStart} onSelectTask={onSelectTask} onComplete={(id) => updateTask(id, { completed: !tasks.find((item) => item.id === id)?.completed })} onTitleChange={(id, title) => updateTask(id, { title })} onSchedule={onSchedule} />)}
        <div className="editor-line add-task-line"><span className="line-number">{5 + tasks.length}</span><span className="markdown-token">- [ ]</span><input value={newTitle} onChange={(event) => setNewTitle(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && newTitle.trim()) { addTask(newTitle.trim()); setNewTitle(""); } }} placeholder="Add a Markdown task…" aria-label="Add a Markdown task" /></div>
        <div className="editor-line empty-line"><span className="line-number">{6 + tasks.length}</span></div>
        <div className="editor-line section-line"><span className="line-number">{7 + tasks.length}</span><span className="heading-mark">##</span><strong>Notes</strong></div>
        <div className="editor-line note-line"><span className="line-number">{8 + tasks.length}</span><span>- Reviewer 2 asks about generalization.</span></div>
        <div className="editor-line note-line"><span className="line-number">{9 + tasks.length}</span><span>- Compare GeneZip vs. strong baselines.</span></div>
      </div>
      <footer className="editor-footer"><span>{tasks.length + 7} lines</span><span>UTF-8</span><span>Local file</span><CheckCircle size={18} weight="fill" /></footer>
    </section>
  );
}

function CalendarBlock({ task, selected, onSelect, onMoveStart, onComplete, onUnschedule, onResizeStart }) {
  return (
    <div className={`calendar-task-block ${task.tone} ${selected ? "selected" : ""} ${task.completed ? "completed" : ""}`} style={blockStyle(task.start, task.end)} onClick={(event) => { event.stopPropagation(); onSelect(task.id); }} tabIndex={0} onKeyDown={(event) => { if (event.key === "Delete" || event.key === "Backspace") onUnschedule(task.id); }}>
      <div className="block-content" onPointerDown={(event) => onMoveStart(event, task.id)}><strong>{task.title}</strong><span>{formatRange(task.start, task.end)}</span></div>
      {selected ? <div className="block-actions"><IconButton label={task.completed ? "Mark incomplete" : "Mark complete"} onClick={() => onComplete(task.id)}>{task.completed ? <ArrowsClockwise size={15} /> : <Check size={15} />}</IconButton><IconButton label="Remove time" onClick={() => onUnschedule(task.id)}><Trash size={15} /></IconButton></div> : null}
      <button type="button" className="resize-handle" aria-label={`Resize ${task.title}`} onPointerDown={(event) => onResizeStart(event, task.id)} />
    </div>
  );
}

function CalendarPanel({ tasks, selectedTaskId, setSelectedTaskId, onDropTask, onMoveStart, onComplete, onUnschedule, onResizeStart }) {
  const timelineRef = useRef(null);
  const [mode, setMode] = useState("day");
  const drop = (event) => { event.preventDefault(); const id = event.dataTransfer.getData("text/task-id") || selectedTaskId; if (!id || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(id, event.clientY - rect.top); };
  if (mode === "week") return (
    <section className="calendar-panel week-panel" aria-label="Week calendar"><div className="calendar-toolbar"><div className="segmented-control"><button type="button" onClick={() => setMode("day")}>Day</button><button type="button" className="active">Week</button></div><IconButton label="Calendar options"><DotsThree size={21} /></IconButton></div><h2>August 10–16</h2><div className="week-grid">{["Mon 10", "Tue 11", "Wed 12", "Thu 13", "Fri 14", "Sat 15", "Sun 16"].map((day) => <button type="button" key={day} className={day === "Sat 15" ? "today" : ""} onClick={() => setMode("day")}><span>{day}</span>{day === "Sat 15" ? <strong>3 blocks</strong> : <small>Open</small>}</button>)}</div><p className="week-hint">Select Saturday to return to the draggable day timeline.</p></section>
  );
  return (
    <section className="calendar-panel" aria-label="Day calendar">
      <div className="calendar-toolbar"><div className="segmented-control"><button type="button" className="active">Day</button><button type="button" onClick={() => setMode("week")}>Week</button></div><IconButton label="Calendar options"><DotsThree size={21} /></IconButton></div>
      <h2>Sat, Aug 15</h2><div className="all-day-row"><span>all-day</span></div>
      <div ref={timelineRef} className={`plan-calendar-canvas ${selectedTaskId ? "ready-to-schedule" : ""}`} onDragOver={(event) => event.preventDefault()} onDrop={drop} onClick={(event) => { if (!selectedTaskId || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(selectedTaskId, event.clientY - rect.top); }}>
        <HourLabels end={20} /><GridLines end={20} />
        <div className="static-calendar-block morning" style={blockStyle(8 * 60, 9 * 60)}><strong>Morning routine</strong><span>08:00–09:00</span></div>
        <div className="static-calendar-block team" style={blockStyle(9 * 60 + 30, 10 * 60 + 15)}><strong>Team sync</strong><span>09:30–10:15</span></div>
        <div className="static-calendar-block lunch" style={blockStyle(12 * 60, 13 * 60)}><strong>Lunch</strong><span>12:00–13:00</span></div>
        {tasks.filter((task) => task.start != null).map((task) => <CalendarBlock key={task.id} task={task} selected={selectedTaskId === task.id} onSelect={setSelectedTaskId} onMoveStart={onMoveStart} onComplete={onComplete} onUnschedule={onUnschedule} onResizeStart={onResizeStart} />)}
      </div>
      <div className="calendar-drop-hint"><LinkSimple size={19} /><span>{selectedTaskId ? "Click a time or drag here to schedule" : "Drag a Markdown task here to schedule it"}</span></div>
    </section>
  );
}

function PlanPage({ tasks, setTasks }) {
  const [lastUpdatedId, setLastUpdatedId] = useState("genezip");
  const [selectedTaskId, setSelectedTaskId] = useState(null);
  const [toast, setToast] = useState("Markdown updated · 14:00–16:00 added");
  const scheduleTask = (id, start, end) => { setTasks((items) => items.map((task) => task.id === id ? { ...task, start, end } : task)); setLastUpdatedId(id); setSelectedTaskId(id); setToast(`Markdown updated · ${formatRange(start, end)} added`); };
  const dropTask = (id, offsetY) => { const raw = DAY_START + (offsetY / HOUR_HEIGHT) * 60; const start = Math.max(DAY_START, Math.min(DAY_END - 30, Math.round(raw / 15) * 15)); const task = tasks.find((item) => item.id === id); const duration = task?.start != null ? Math.max(task.end - task.start, 30) : 60; scheduleTask(id, start, Math.min(start + duration, DAY_END)); };
  const taskDragStart = (event, id) => { event.dataTransfer.effectAllowed = "move"; event.dataTransfer.setData("text/task-id", id); setSelectedTaskId(id); };
  const pointerMoveStart = (event, id) => {
    event.preventDefault();
    setSelectedTaskId(id);
    const up = (upEvent) => {
      window.removeEventListener("pointerup", up);
      const calendar = document.querySelector(".plan-calendar-canvas");
      if (!calendar) return;
      const rect = calendar.getBoundingClientRect();
      if (upEvent.clientX >= rect.left && upEvent.clientX <= rect.right && upEvent.clientY >= rect.top && upEvent.clientY <= rect.bottom) dropTask(id, upEvent.clientY - rect.top + calendar.scrollTop);
    };
    window.addEventListener("pointerup", up);
  };
  const completeTask = (id) => setTasks((items) => items.map((task) => task.id === id ? { ...task, completed: !task.completed } : task));
  const unscheduleTask = (id) => { setTasks((items) => items.map((task) => task.id === id ? { ...task, start: null, end: null } : task)); setLastUpdatedId(id); setSelectedTaskId(null); setToast("Markdown updated · time removed, task preserved"); };
  const resizeStart = (event, id) => {
    event.preventDefault(); event.stopPropagation(); const task = tasks.find((item) => item.id === id); if (!task) return; const startY = event.clientY; const initialEnd = task.end;
    const move = (moveEvent) => { const delta = Math.round(((moveEvent.clientY - startY) / HOUR_HEIGHT) * 4) * 15; const nextEnd = Math.max(task.start + 30, Math.min(DAY_END, initialEnd + delta)); setTasks((items) => items.map((item) => item.id === id ? { ...item, end: nextEnd } : item)); };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); setLastUpdatedId(id); setToast("Markdown updated · calendar duration changed"); };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };
  const addTask = (title) => setTasks((items) => [...items, { id: `task-${Date.now()}`, title, tags: [], start: null, end: null, completed: false, tone: "soft" }]);
  return (
    <main className="page plan-page"><header className="plan-header"><h1>Plan <span>·</span> Saturday, August 15</h1><div className="date-controls"><CalendarBlank size={21} /><button type="button" className="quiet-pill">Today</button><IconButton label="Previous day"><CaretLeft size={18} /></IconButton><IconButton label="Next day"><CaretRight size={18} /></IconButton></div></header>
      <div className="plan-workspace"><MarkdownEditor tasks={tasks} setTasks={setTasks} lastUpdatedId={lastUpdatedId} onTaskDragStart={taskDragStart} onPointerDragStart={pointerMoveStart} onSelectTask={setSelectedTaskId} onSchedule={scheduleTask} addTask={addTask} /><CalendarPanel tasks={tasks} selectedTaskId={selectedTaskId} setSelectedTaskId={setSelectedTaskId} onDropTask={dropTask} onMoveStart={pointerMoveStart} onComplete={completeTask} onUnschedule={unscheduleTask} onResizeStart={resizeStart} /></div>
      {toast ? <div className="toast" role="status"><CheckCircle size={20} weight="fill" /><span>{toast}</span><IconButton label="Dismiss" onClick={() => setToast("")}><X size={15} /></IconButton></div> : null}
    </main>
  );
}

function ReviewPage() {
  const days = [{ label: "Mon", planned: 7.2, actual: 6.6 }, { label: "Tue", planned: 6.5, actual: 7.1 }, { label: "Wed", planned: 7.8, actual: 6.9 }, { label: "Thu", planned: 6.2, actual: 5.8 }, { label: "Fri", planned: 7.1, actual: 6.5 }, { label: "Sat", planned: 5.5, actual: 4.8 }];
  return <main className="page supporting-page"><header className="supporting-header"><div><span>This week</span><h1>Review with evidence</h1></div><button className="quiet-pill" type="button">Aug 10–16</button></header><section className="review-summary"><div><Timer size={26} /><span>Deep work</span><strong>22h 14m</strong><small>+2h 06m from last week</small></div><div><TrendUp size={26} /><span>Estimate accuracy</span><strong>86%</strong><small>Best on research blocks</small></div><div><ShieldCheck size={26} /><span>Protected focus</span><strong>91%</strong><small>6 distractions blocked</small></div></section><section className="weekly-chart"><div className="chart-heading"><div><h2>Planned vs. actual</h2><p>Longer actual bars reveal underestimated work.</p></div><div className="legend"><span><i className="planned" />Planned</span><span><i className="actual" />Actual</span></div></div><div className="bar-chart">{days.map((day) => <div key={day.label} className="bar-day"><div className="bar-pair"><i className="planned" style={{ height: `${day.planned * 28}px` }} /><i className="actual" style={{ height: `${day.actual * 28}px` }} /></div><span>{day.label}</span></div>)}</div></section></main>;
}

function RulesPage() {
  const [locked, setLocked] = useState(true); const [blocked, setBlocked] = useState(["youtube.com", "x.com", "reddit.com"]); const [allowed, setAllowed] = useState(["arxiv.org", "github.com", "pytorch.org"]); const [draft, setDraft] = useState("");
  return <main className="page supporting-page rules-page"><header className="supporting-header"><div><span>Focus rules</span><h1>Research Focus</h1></div><button type="button" className={`status-pill ${locked ? "active" : ""}`} onClick={() => setLocked((value) => !value)}><LockSimple size={17} />{locked ? "Locked mode on" : "Flexible mode"}</button></header><div className="rules-layout"><section className="rule-overview"><ShieldCheck size={54} color="#3da65a" weight="duotone" /><h2>Protect deep-work blocks</h2><p>This rule starts with scheduled research tasks and stays local to this Mac.</p><div className="rule-meta"><span><Clock size={18} />Runs with calendar blocks</span><span><Laptop size={18} />Local processing</span><span><Browsers size={18} />All browsers</span></div></section><section className="site-list-section"><div className="site-list-heading"><div><h2>Blocked sites</h2><p>Attempts are recorded as distraction evidence.</p></div><strong>{blocked.length}</strong></div><div className="site-list">{blocked.map((site) => <div key={site}><GlobeSimple size={20} /><span>{site}</span><IconButton label={`Allow ${site}`} onClick={() => { setBlocked((items) => items.filter((item) => item !== site)); setAllowed((items) => [...items, site]); }}><X size={15} /></IconButton></div>)}</div><form onSubmit={(event) => { event.preventDefault(); if (draft.trim() && !blocked.includes(draft.trim())) setBlocked((items) => [...items, draft.trim()]); setDraft(""); }}><GlobeSimple size={19} /><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a distracting domain" aria-label="Add blocked website" /><button type="submit"><Plus size={17} />Add</button></form></section><section className="site-list-section allowed-section"><div className="site-list-heading"><div><h2>Allowed research</h2><p>Always available inside this focus rule.</p></div><strong>{allowed.length}</strong></div><div className="site-list">{allowed.map((site) => <div key={site}><CheckCircle size={20} weight="fill" /><span>{site}</span></div>)}</div></section></div></main>;
}

export function App() {
  const [page, setPage] = useState("today");
  const [tasks, setTasks] = useState(initialTasks);
  const content = useMemo(() => page === "plan" ? <PlanPage tasks={tasks} setTasks={setTasks} /> : page === "review" ? <ReviewPage /> : page === "rules" ? <RulesPage /> : <TodayPage setPage={setPage} />, [page, tasks]);
  return <div className="app-shell"><Sidebar page={page} setPage={setPage} />{content}</div>;
}
