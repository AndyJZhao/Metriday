import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowsClockwise, BookOpen, Browsers, CalendarBlank, CaretLeft, CaretRight,
  ChartBar, Check, CheckCircle, Clock, Code, DotsSixVertical, DotsThree,
  FileText, Flask, FolderSimple, GearSix, GlobeSimple, Laptop, LinkSimple,
  LockSimple, NotePencil, Pause, Play, Plus, ShieldCheck, Sparkle, TerminalWindow,
  Timer, Trash, TrendUp, Waveform, X,
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
  { id: "activities", label: "Activities", icon: Waveform },
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

const API_BASE_STORAGE_KEY = "metriday.apiBase";
const DEFAULT_API_BASE = "http://127.0.0.1:8765";

function normalizeApiBase(value) {
  const raw = String(value || "").trim();
  if (!raw) return DEFAULT_API_BASE;
  const withScheme = /^[a-z][a-z\d+.-]*:\/\//i.test(raw) ? raw : `http://${raw}`;
  try {
    const url = new URL(withScheme);
    if (!["http:", "https:"].includes(url.protocol) || !url.host) return DEFAULT_API_BASE;
    return url.toString().replace(/\/$/, "");
  } catch {
    return DEFAULT_API_BASE;
  }
}

function apiBaseURL() {
  const configured = typeof window !== "undefined" ? window.__METRIDAY_API_BASE__ : "";
  const persisted = typeof window !== "undefined" ? window.localStorage?.getItem(API_BASE_STORAGE_KEY) : "";
  return normalizeApiBase(configured || persisted || import.meta.env.VITE_METRIDAY_API_BASE || DEFAULT_API_BASE);
}

function localDateKey(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function offsetDateKey(dateKey, offset) {
  const date = new Date(`${dateKey}T12:00:00`);
  if (Number.isNaN(date.getTime())) return dateKey;
  date.setDate(date.getDate() + offset);
  return localDateKey(date);
}

function dateKeysBetween(startDate, endDate) {
  const keys = [];
  for (let offset = 0; offset < 90; offset += 1) {
    const key = offsetDateKey(startDate, offset);
    keys.push(key);
    if (key >= endDate) break;
  }
  return keys.filter((key) => key <= endDate);
}

function planDateLabel(dateKey) {
  const date = new Date(`${dateKey}T12:00:00`);
  if (Number.isNaN(date.getTime())) return dateKey;
  return date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" });
}

async function apiRequest(path, options = {}, base = apiBaseURL()) {
  const response = await fetch(`${normalizeApiBase(base)}${path}`, {
    ...options,
    headers: { ...(options.body ? { "Content-Type": "application/json" } : {}), ...(options.headers || {}) },
  });
  if (!response.ok) {
    const message = await response.text().catch(() => "");
    throw new Error(message || `${response.status} ${response.statusText}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

function useMetridayAPI(dateKey, apiBase) {
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [snapshot, setSnapshot] = useState({
    connected: false,
    loading: true,
    error: "",
    status: null,
    projects: [],
    activities: [],
    entries: [],
    plan: null,
    sync: null,
    rules: [],
    focusActive: false,
    weekly: [],
    insights: [],
  });

  const request = useCallback((path, options = {}) => apiRequest(path, options, apiBase), [apiBase]);

  const refresh = useCallback(async () => {
    const date = dateKey || localDateKey();
    const weekKeys = Array.from({ length: 6 }, (_, index) => offsetDateKey(date, index - 5));
    try {
      const status = await request("/v1/status");
      const results = await Promise.allSettled([
        request(`/v1/activities?date=${date}`),
        request(`/api/v1/time-entries?start_date_min=${date}&start_date_max=${date}`),
        request("/api/v1/projects"),
        request(`/v1/plans?date=${date}`),
        request("/v1/sync/status"),
        request("/v1/rules"),
        Promise.all(weekKeys.map(async (weekDate) => {
          const [activityResult, planResult] = await Promise.allSettled([
            request(`/v1/activities?date=${weekDate}`),
            request(`/v1/plans?date=${weekDate}`),
          ]);
          return {
            date: weekDate,
            activities: activityResult.status === "fulfilled" && Array.isArray(activityResult.value) ? activityResult.value : [],
            plan: planResult.status === "fulfilled" ? planResult.value : null,
          };
        })),
        request(`/v1/insights?date=${date}`),
      ]);
      const value = (index, fallback) => results[index].status === "fulfilled" ? results[index].value : fallback;
      setSnapshot({
        connected: true,
        loading: false,
        error: "",
        status,
        activities: value(0, []),
        entries: value(1, { data: [] })?.data || [],
        projects: value(2, { data: [] })?.data || [],
        plan: value(3, null),
        sync: value(4, null),
        rules: value(5, { data: [] })?.data || [],
        focusActive: Boolean(value(5, { focusActive: false })?.focusActive),
        weekly: value(6, []),
        insights: value(7, { data: [] })?.data || [],
      });
      setRefreshVersion((value) => value + 1);
    } catch (error) {
      setSnapshot((current) => ({ ...current, connected: false, loading: false, error: error.message || "Metriday API unavailable" }));
    }
  }, [dateKey, request]);

  useEffect(() => {
    refresh();
    const interval = window.setInterval(refresh, 10_000);
    return () => window.clearInterval(interval);
  }, [refresh]);

  const mutate = useCallback(async (path, body) => {
    await request(path, {
      method: "POST",
      body: body ? JSON.stringify(body) : undefined,
    });
    await refresh();
  }, [refresh, request]);

  const fetchRange = useCallback(async (startDate, endDate) => {
    const activityDates = dateKeysBetween(startDate, endDate);
    const entryDates = dateKeysBetween(offsetDateKey(startDate, -1), endDate);
    const activityResults = await Promise.all(activityDates.map(async (day) => ({ day, items: await request(`/v1/activities?date=${day}`) })));
    const entryResults = await Promise.all(entryDates.map((day) => request(`/api/v1/time-entries?start_date_min=${day}&start_date_max=${day}`)));
    return {
      activities: activityResults.flatMap(({ day, items }) => Array.isArray(items) ? items.map((item) => ({ ...item, date: day })) : []),
      entries: entryResults.flatMap((payload) => payload?.data || []),
      startDate,
      endDate,
    };
  }, [request]);

  return {
    ...snapshot,
    refreshVersion,
    refresh,
    fetchRange,
    startTimer: (title, projectID) => mutate("/v1/timer/start", { title, projectID }),
    stopTimer: () => mutate("/v1/timer/stop"),
    toggleTracking: () => mutate(snapshot.status?.tracking ? "/v1/tracking/pause" : "/v1/tracking/resume"),
    syncNow: () => mutate("/v1/sync/now"),
    addTimeEntry: async (entry) => {
      await request("/v1/time-entries", { method: "POST", body: JSON.stringify(entry) });
      await refresh();
    },
    updateTimeEntry: async (id, entry) => {
      await request(`/api/v1/time-entries/${resourceID(id)}`, { method: "PATCH", body: JSON.stringify(entry) });
      await refresh();
    },
    deleteTimeEntry: async (id) => {
      await request(`/api/v1/time-entries/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    createProject: async (project) => {
      await request("/api/v1/projects", { method: "POST", body: JSON.stringify(project) });
      await refresh();
    },
    updateProject: async (id, project) => {
      await request(`/api/v1/projects/${resourceID(id)}`, { method: "PATCH", body: JSON.stringify(project) });
      await refresh();
    },
    deleteProject: async (id) => {
      await request(`/api/v1/projects/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    addWebRule: async (domain, allowed = false) => {
      await request("/v1/rules", { method: "POST", body: JSON.stringify({ domain, allowed }) });
      await refresh();
    },
    updateWebRule: async (id, allowed) => {
      await request(`/v1/rules/${id}`, { method: "PATCH", body: JSON.stringify({ allowed }) });
      await refresh();
    },
    deleteWebRule: async (id) => {
      await request(`/v1/rules/${id}`, { method: "DELETE" });
      await refresh();
    },
    setFocusActive: async (active) => {
      await request("/v1/focus", { method: "POST", body: JSON.stringify({ active }) });
      await refresh();
    },
    savePlan: async (markdown, date = dateKey || localDateKey()) => {
      await request(`/v1/plans?date=${date}`, { method: "PUT", body: JSON.stringify({ markdown }) });
      await refresh();
    },
  };
}

function formatTime(minutes) {
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

function formatRange(start, end) {
  return start == null || end == null ? "" : `${formatTime(start)}–${formatTime(end)}`;
}

function currentMinuteAndLabel() {
  const now = new Date();
  return {
    minute: now.getHours() * 60 + now.getMinutes(),
    label: now.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", hour12: false }),
  };
}

function timelineBlockStyle(start, end, minimumHeight = 34) {
  return { top: `${((start - DAY_START) / 60) * HOUR_HEIGHT}px`, height: `${Math.max(((end - start) / 60) * HOUR_HEIGHT, minimumHeight)}px` };
}

function blockStyle(start, end) {
  return timelineBlockStyle(start, end);
}

function actualBlockStyle(block) {
  return timelineBlockStyle(block.start, block.end, block.end - block.start < 30 ? 4 : 34);
}

function preciseClock(totalSeconds) {
  const value = Math.max(0, Math.round(Number(totalSeconds || 0)));
  const hours = Math.floor(value / 3600) % 24;
  const minutes = Math.floor((value % 3600) / 60);
  const seconds = value % 60;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function preciseDuration(totalSeconds) {
  const value = Math.max(0, Math.round(Number(totalSeconds || 0)));
  const hours = Math.floor(value / 3600);
  const minutes = Math.floor((value % 3600) / 60);
  const seconds = value % 60;
  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

function activityLabel(activity) {
  const app = activity.appName || activity.deviceName || "Activity";
  const detail = activity.windowTitle || activity.resource || "";
  return detail && detail.toLowerCase() !== app.toLowerCase() ? `${app} · ${detail}` : app;
}

function activityIcon(activity) {
  const bundle = String(activity.bundleIdentifier || "").toLowerCase();
  const app = String(activity.appName || "").toLowerCase();
  if (bundle.includes("vscode") || app.includes("code")) return VSCodeLogo;
  if (bundle.includes("terminal") || app.includes("terminal")) return TerminalWindow;
  if (bundle.includes("safari") || bundle.includes("chrome") || bundle.includes("firefox") || app.includes("browser")) return GlobeSimple;
  if (app.includes("youtube")) return YouTubeLogo;
  if (app.includes("arxiv")) return ArxivLogo;
  return Browsers;
}

function activityCategory(activity) {
  switch (activity?.relevance) {
    case "related":
      return { key: "focused", label: "Focused" };
    case "distracted":
      return { key: "distracting", label: "Distracting" };
    case "idle":
      return { key: "idle", label: "Idle" };
    default:
      return { key: "other", label: "Other" };
  }
}

function activityContext(activity) {
  const title = String(activity?.windowTitle || "").trim();
  const resource = String(activity?.resource || "").trim();
  const app = String(activity?.appName || "").trim();
  if (title && title.toLowerCase() !== app.toLowerCase()) return title;
  if (resource) {
    try {
      return new URL(resource).host || resource;
    } catch {
      return resource;
    }
  }
  return "";
}

function liveActivityBlocks(activities) {
  const primaryKind = (totals) => [...totals.entries()].sort((left, right) => right[1] - left[1])[0]?.[0] || "other";
  const normalized = activities
    .map((activity) => {
      const rawStartSecond = Math.max(DAY_START * 60, Number(activity.startSecond || 0));
      const rawEndSecond = Math.min(DAY_END * 60, Number(activity.endSecond || 0));
      const start = Math.max(DAY_START, Math.floor(rawStartSecond / 60));
      const end = Math.min(DAY_END, Math.ceil(rawEndSecond / 60));
      if (end <= start) return null;
      const category = activityCategory(activity);
      return {
        id: activity.id || `${start}-${end}-${activity.appName}`,
        start,
        end,
        startSecond: rawStartSecond,
        endSecond: rawEndSecond,
        kind: category.key,
        label: category.key === "idle" ? "Idle" : activityLabel(activity),
        icon: category.key === "idle" ? null : activityIcon(activity),
      };
    })
    .filter(Boolean)
    .sort((left, right) => left.start - right.start || left.end - right.end);

  const blocks = [];
  for (const activity of normalized) {
    const previous = blocks[blocks.length - 1];
    const canMerge = previous
      && activity.start <= previous.end + 1
      && activity.end - previous.start <= 20;

    if (!canMerge) {
      blocks.push({
        id: activity.id,
        start: activity.start,
        end: activity.end,
        startSecond: activity.startSecond,
        endSecond: activity.endSecond,
        kind: activity.kind,
        label: activity.kind === "idle" ? "Idle" : activity.label,
        detail: activity.kind === "idle" ? "No significant activity" : formatRange(activity.start, activity.end),
        kinds: new Set([activity.kind]),
        categorySeconds: new Map([[activity.kind, Math.max(1, activity.endSecond - activity.startSecond)]]),
        rowMap: new Map([[`${activity.kind}|${activity.label}`, {
          icon: activity.icon,
          label: activity.label,
          start: activity.start,
          end: activity.end,
          seconds: Math.max(1, activity.endSecond - activity.startSecond),
          kind: activity.kind,
        }]]),
      });
      continue;
    }

    previous.end = Math.max(previous.end, activity.end);
    previous.startSecond = Math.min(previous.startSecond, activity.startSecond);
    previous.endSecond = Math.max(previous.endSecond, activity.endSecond);
    previous.kinds.add(activity.kind);
    previous.categorySeconds.set(
      activity.kind,
      (previous.categorySeconds.get(activity.kind) || 0) + Math.max(1, activity.endSecond - activity.startSecond)
    );
    previous.kind = primaryKind(previous.categorySeconds);
    const rowKey = `${activity.kind}|${activity.label}`;
    const row = previous.rowMap.get(rowKey);
    if (row) {
      row.end = Math.max(row.end, activity.end);
      row.seconds += Math.max(1, activity.endSecond - activity.startSecond);
    } else {
      previous.rowMap.set(rowKey, {
        icon: activity.icon,
        label: activity.label,
        start: activity.start,
        end: activity.end,
        seconds: Math.max(1, activity.endSecond - activity.startSecond),
        kind: activity.kind,
      });
    }
  }

  return blocks.map((block) => ({
    id: block.id,
    start: block.start,
    end: block.end,
    startSecond: block.startSecond,
    endSecond: block.endSecond,
    kind: block.kind,
    label: block.label,
    detail: block.kind === "idle" ? block.detail : formatRange(block.start, block.end),
    rows: block.kinds.size === 1 && block.kinds.has("idle") ? null : [...block.rowMap.values()]
      .sort((left, right) => right.seconds - left.seconds)
      .slice(0, 5)
      .map((row) => ({
        minutes: formatDurationSeconds(row.seconds),
        icon: row.icon,
        label: row.label,
        time: formatRange(row.start, row.end),
        kind: row.kind,
      })),
  }));
}

function planTaskFromAPI(task, index) {
  return {
    id: task.id || "api-task-" + index,
    title: task.title || "Untitled task",
    tags: Array.isArray(task.tags) ? task.tags : [],
    start: Number.isFinite(task.start_minute) ? task.start_minute : null,
    end: Number.isFinite(task.end_minute) ? task.end_minute : null,
    completed: Boolean(task.completed),
    tone: index === 0 ? "accent" : "soft",
  };
}

function taskMarkdownLine(task, prefix = "- ") {
  const range = task.start != null && task.end != null ? formatTime(task.start) + " - " + formatTime(task.end) + " " : "";
  const tags = Array.isArray(task.tags) && task.tags.length > 0 ? " " + task.tags.map((tag) => "#" + tag).join(" ") : "";
  return prefix + "[" + (task.completed ? "x" : " ") + "] " + range + String(task.title || "Untitled task").trim() + tags;
}

function markdownWithTasks(raw, tasks) {
  const lines = String(raw || "").split("\n");
  let taskIndex = 0;
  let lastTaskLine = -1;
  const updated = lines.map((line, lineIndex) => {
    const match = line.match(/^(\s*(?:[-*+]|[0-9]+[.)])\s+)\[( |x|X)\]\s+(.*)$/);
    if (!match) return line;
    lastTaskLine = lineIndex;
    const task = tasks[taskIndex++];
    if (!task) return line;
    return taskMarkdownLine(task, match[1]);
  });
  const extraTasks = tasks.slice(taskIndex).map((task) => taskMarkdownLine(task));
  if (extraTasks.length > 0) {
    const insertionIndex = Math.min(updated.length, lastTaskLine >= 0 ? lastTaskLine + 1 : updated.length);
    updated.splice(insertionIndex, 0, ...extraTasks);
  }
  return updated.join("\n");
}

function ConnectionSettings({ open, apiBase, connected, onSave, onClose }) {
  const [draft, setDraft] = useState(apiBase);
  const [message, setMessage] = useState("");

  useEffect(() => {
    if (open) {
      setDraft(apiBase);
      setMessage("");
    }
  }, [apiBase, open]);

  if (!open) return null;

  const save = (event) => {
    event.preventDefault();
    const value = String(draft || "").trim();
    if (!value) {
      setMessage("请输入 API 地址。");
      return;
    }
    const candidate = /^[a-z][a-z\d+.-]*:\/\//i.test(value) ? value : `http://${value}`;
    try {
      const url = new URL(candidate);
      if (!["http:", "https:"].includes(url.protocol) || !url.host) throw new Error("unsupported protocol");
      const normalized = url.toString().replace(/\/$/, "");
      window.localStorage.setItem(API_BASE_STORAGE_KEY, normalized);
      onSave(normalized);
      onClose();
    } catch {
      setMessage("请输入有效的 http:// 或 https:// API 地址。");
    }
  };

  const reset = () => {
    window.localStorage.removeItem(API_BASE_STORAGE_KEY);
    onSave(apiBaseURL());
    setDraft(apiBaseURL());
    setMessage("已恢复默认连接地址。");
  };

  return <div className="settings-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="settings-dialog" role="dialog" aria-modal="true" aria-labelledby="settings-title">
    <div className="settings-dialog-heading"><div><span>Connection</span><h2 id="settings-title">Metriday Web App</h2></div><IconButton label="Close settings" onClick={onClose}><X size={18} /></IconButton></div>
    <p className="settings-description">把 Web 伴侣连接到正在运行的 Metriday 原生应用。Mac 默认使用本机地址；手机或另一台设备请填写 Mac 的局域网 IP 或 HTTPS 网关地址。</p>
    <form className="settings-form" onSubmit={save}>
      <label htmlFor="metriday-api-base">Native API base URL</label>
      <div className="settings-input-wrap"><LinkSimple size={18} /><input id="metriday-api-base" value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="http://127.0.0.1:8765" autoFocus /></div>
      <div className="settings-connection-state"><i className={connected ? "connected" : ""} /><span>{connected ? "Connected" : "Not connected"}</span><small>不会上传到 Metriday 云端</small></div>
      {message ? <p className="entry-message" role="status">{message}</p> : null}
      <div className="settings-actions"><button type="button" className="secondary-button" onClick={reset}>Use this Mac</button><button type="submit" className="primary-button">Save & connect</button></div>
    </form>
    <div className="settings-install-note"><Laptop size={18} /><div><strong>Install on phone</strong><span>在 Safari/Chrome 的分享或菜单中选择“添加到主屏幕”。离线时仍可打开界面，数据请求会在恢复连接后重试。</span></div></div>
  </section></div>;
}

function Sidebar({ page, setPage, api, onOpenSettings }) {
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
        <div className="local-state"><Laptop size={22} /><span>{api.connected ? "Live with Metriday" : "Preview data"}</span><i className={api.connected ? "connected" : ""} aria-label={api.connected ? "Native Metriday API connected" : "Local API unavailable"} /></div>
        <button type="button" className="footer-link" onClick={onOpenSettings}><GearSix size={22} /><span>Settings</span></button>
        <div className="sync-state"><CheckCircle size={17} weight="fill" /><span>{api.sync?.enabled ? "Sync connected" : api.connected ? "Native API connected" : "Offline preview"}</span></div>
      </div>
    </aside>
  );
}

function IconButton({ label, children, onClick, className = "" }) {
  return <button type="button" className={`icon-button ${className}`} aria-label={label} title={label} onClick={onClick}>{children}</button>;
}

function ActionMenu({ label, items, children }) {
  const [open, setOpen] = useState(false);
  return <div className="action-menu">
    <button type="button" className="icon-button" aria-label={label} title={label} aria-expanded={open} onClick={() => setOpen((value) => !value)}>{children}</button>
    {open ? <div className="action-menu-popover" role="menu" aria-label={label}>
      {items.map((item) => <button key={item.label} type="button" role="menuitem" className="action-menu-item" onClick={() => { item.onSelect(); setOpen(false); }}>{item.label}</button>)}
    </div> : null}
  </div>;
}

function TodayHeader({ focusRunning, setFocusRunning, setPage, api, dateKey, setDateKey }) {
  const currentTitle = api.status?.currentTask?.title || "GeneZip rebuttal experiment";
  const currentApplication = api.status?.currentApplication && api.status.currentApplication !== "Waiting for activity" ? api.status.currentApplication : "Research Focus";
  return (
    <header className="today-header">
      <div className="date-heading">
        <h1>{planDateLabel(dateKey)}</h1>
        <div className="date-controls"><CalendarBlank size={21} /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div>
      </div>
      <div className="current-session">
        <div className="session-copy"><span>Current block</span><strong>{currentTitle}</strong><p>14:00–16:00 <b>·</b> <em>{focusRunning ? "In progress" : "Paused"}</em></p></div>
        <button type="button" className="primary-button" onClick={async () => { if (api.connected) { if (focusRunning) await api.stopTimer(); else await api.startTimer(currentTitle); } else setFocusRunning((value) => !value); }}>{focusRunning ? <Pause size={18} weight="fill" /> : <Play size={18} weight="fill" />}{focusRunning ? "Pause focus" : "Resume focus"}</button>
        <div className="focus-rule"><ShieldCheck size={38} color="#39a65a" weight="duotone" /><div><strong>Research Focus</strong><span>{api.connected ? currentApplication : "Blocklist active"}</span><button type="button" onClick={() => setPage("rules")}>Adjust allowed sites</button></div></div>
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

function planTimelineBlocks(tasks, connected) {
  if (!connected || !Array.isArray(tasks)) return fixedPlanBlocks;
  return tasks.filter((task) => Number.isFinite(task.start_minute) && Number.isFinite(task.end_minute) && task.end_minute > task.start_minute).map((task, index) => {
    const title = task.title || "Untitled task";
    const lowerTitle = title.toLowerCase();
    const Icon = lowerTitle.includes("review") ? BookOpen : lowerTitle.includes("write") || lowerTitle.includes("draft") ? NotePencil : index === 0 ? Flask : Code;
    return { id: task.id || `plan-${index}`, title, start: task.start_minute, end: task.end_minute, icon: Icon, current: index === 0 };
  });
}

function PlannedTrack({ tasks, connected }) {
  const blocks = planTimelineBlocks(tasks, connected);
  return (
    <section className="today-track planned-track" aria-label="Planned timeline">
      <div className="track-heading"><strong>Plan</strong><span>What I planned</span></div>
      <div className="track-canvas"><GridLines />{blocks.map(({ id, title, start, end, icon: Icon, current }) => (
        <button key={id} type="button" className={`planned-block ${current ? "current" : ""}`} style={blockStyle(start, end)}><Icon size={18} weight="duotone" /><span><strong>{title}</strong><small>{formatRange(start, end)}</small></span></button>
      ))}{connected && blocks.length === 0 ? <div className="planned-empty">No scheduled tasks in this Markdown plan.</div> : null}</div>
    </section>
  );
}

function ActualRows({ block }) {
  if (block.end - block.start < 30) return <div className="actual-compact" aria-hidden="true" />;
  if (!block.rows) return <div className="actual-simple"><strong>{Math.round(block.end - block.start)}m</strong><span><b>{block.label}</b><small>{block.detail}</small></span></div>;
  return <div className="actual-row-list">{block.rows.map((row, index) => { const Icon = row.icon; return (
    <div key={`${block.id}-${index}`} className={`actual-row ${row.kind || block.kind}`}><strong>{row.minutes || (index === 0 ? block.minutes : "")}</strong><span className="activity-icon">{Icon ? <Icon size={20} weight="duotone" /> : null}</span><b>{row.label}</b><small>{row.time}</small></div>
  ); })}</div>;
}

function ActualHoverCard({ block, onRecord }) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const categoryLabel = block.kind === "focused" ? "Focused" : block.kind === "distracting" ? "Distracting" : block.kind === "idle" ? "Idle" : "Other";
  const appLabel = block.rows?.[0]?.label || block.label;
  const startSecond = Number.isFinite(block.startSecond) ? block.startSecond : block.start * 60;
  const endSecond = Number.isFinite(block.endSecond) ? block.endSecond : block.end * 60;
  const record = async () => {
    if (!onRecord || busy) return;
    setBusy(true);
    setMessage("");
    try {
      await onRecord({ ...block, startSecond, endSecond });
      setMessage("Recorded");
    } catch (error) {
      setMessage(error.message || "Could not record");
    } finally {
      setBusy(false);
    }
  };
  return <div className="actual-hover-card" role="tooltip">
    <strong className="actual-hover-time">{preciseClock(startSecond)}</strong>
    <span className="actual-hover-duration">({preciseDuration(endSecond - startSecond)})</span>
    <div className="actual-hover-meta"><span>App:</span><b>{appLabel}</b></div>
    <div className="actual-hover-meta"><span>Category:</span><i className={`hover-category-dot ${block.kind}`} /><b>{categoryLabel}</b></div>
    <div className="actual-hover-meta"><span>Project:</span><i className="hover-project-dot" /><b>None</b><small>From the app usage</small></div>
    {onRecord ? <div className="actual-hover-actions"><button type="button" className="actual-record-button" onClick={record} disabled={busy}>{message || (busy ? "Recording…" : "Record time")}</button></div> : null}
  </div>;
}

function ActualTrack({ activities, connected, onRecord }) {
  const [hoveredBlockId, setHoveredBlockId] = useState(null);
  const blocks = connected && activities.length > 0 ? liveActivityBlocks(activities) : actualBlocks;
  return (
    <section className="today-track actual-track" aria-label="Actual activity timeline">
      <div className="track-heading"><strong>Actual</strong><span>{connected ? "Live from Metriday" : "What actually happened"}</span></div>
      <div className="track-canvas"><GridLines />{blocks.map((block) => <div key={block.id} className={`actual-block ${block.kind} ${hoveredBlockId === block.id ? "hovered" : ""}`} style={actualBlockStyle(block)} title={`${block.label} · ${block.detail}`} onMouseEnter={() => setHoveredBlockId(block.id)} onMouseLeave={() => setHoveredBlockId(null)}><ActualRows block={block} />{hoveredBlockId === block.id ? <ActualHoverCard block={block} onRecord={connected ? onRecord : null} /> : null}</div>)}</div>
    </section>
  );
}

function TodayPage({ setPage, api, dateKey, setDateKey }) {
  const [focusRunning, setFocusRunning] = useState(Boolean(api.status?.timer));
  useEffect(() => setFocusRunning(Boolean(api.status?.timer)), [api.status?.timer?.id]);
  const recordActivity = async (block) => {
    const start = localEntryDateSeconds(dateKey, block.startSecond);
    const end = localEntryDateSeconds(dateKey, block.endSecond);
    if (!start || !end || end <= start) throw new Error("Activity range is not available");
    await api.addTimeEntry({
      title: block.rows?.[0]?.label || block.label || "App activity",
      start,
      end,
      billingStatus: "billable",
    });
  };
  const now = currentMinuteAndLabel();
  const showNow = dateKey === localDateKey();
  const nowStyle = showNow ? { top: `${56 + ((now.minute - DAY_START) / 60) * HOUR_HEIGHT}px` } : { display: "none" };
  return (
    <main className="page today-page">
      <TodayHeader focusRunning={focusRunning} setFocusRunning={setFocusRunning} setPage={setPage} api={api} dateKey={dateKey} setDateKey={setDateKey} />
      <div className="today-comparison"><div className="timeline-label-column"><HourLabels /></div><PlannedTrack tasks={api.plan?.tasks} connected={api.connected} /><ActualTrack activities={api.activities} connected={api.connected} onRecord={recordActivity} /><div className="now-marker" style={nowStyle} aria-label={`Current time ${now.label}`}><span /></div></div>
      <TodayInsightBar api={api} setPage={setPage} />
      {api.connected ? <WebActivityInsights insights={api.insights} dateKey={dateKey} /> : null}
    </main>
  );
}

function TodayInsightBar({ api, setPage }) {
  if (!api.connected) {
    return <div className="insight-bar"><TrendUp size={26} color="#4f63ef" weight="duotone" /><div><p><strong>Started 8 min late</strong><b>·</b><strong className="positive">82% task-related</strong><b>·</b><strong className="warning">Estimate likely +25 min</strong></p><span>Connect Metriday to replace the preview insight with local activity evidence.</span></div><button type="button" className="secondary-button" onClick={() => setPage("rules")}><ShieldCheck size={18} /> Adjust blocklist</button></div>;
  }
  const activities = Array.isArray(api.activities) ? api.activities : [];
  const active = activities.filter((activity) => activity.relevance !== "idle");
  const relatedSeconds = active.filter((activity) => activity.relevance === "related").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const distractedSeconds = active.filter((activity) => activity.relevance === "distracted").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const activeSeconds = active.reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const taskRelated = activeSeconds > 0 ? Math.round((relatedSeconds / activeSeconds) * 100) : 0;
  const distraction = api.insights?.find((insight) => insight.id === "distraction");
  const trackingLabel = api.status?.tracking ? "Tracking active" : "Tracking paused";
  const activityLabel = activeSeconds > 0 ? `${formatDurationSeconds(activeSeconds)} captured locally` : "No active usage captured yet";
  const distractionLabel = distraction?.detail || (distractedSeconds > 0 ? `${formatDurationSeconds(distractedSeconds)} outside task focus` : "No distraction evidence yet");
  return <div className="insight-bar"><TrendUp size={26} color="#4f63ef" weight="duotone" /><div><p><strong>{trackingLabel}</strong><b>·</b><strong className="positive">{taskRelated}% task-related</strong><b>·</b><strong className={distractedSeconds > 0 ? "warning" : "positive"}>{activityLabel}</strong></p><span>{distractionLabel} · Source: local activity monitor and Screen Time when available.</span></div><button type="button" className="secondary-button" onClick={() => setPage("rules")}><ShieldCheck size={18} /> Adjust blocklist</button></div>;
}

function WebActivityInsights({ insights, dateKey }) {
  const sourceLabels = [...new Set((insights || []).map((insight) => insight.source_label || "Local activity monitor"))];
  return <section className="web-insights-panel" aria-label="Smart Activity Summary"><div className="web-insights-heading"><div><h2><Sparkle size={19} weight="fill" /> Smart Activity Summary</h2><p>Explainable highlights generated on this Mac from the same activity evidence used by reports.</p></div><span className="web-insights-date">{dateKey}</span></div>{insights?.length ? <div className="web-insights-list">{insights.map((insight) => <article className="web-insight-row" key={insight.id}><span className="web-insight-icon"><Sparkle size={16} weight="fill" /></span><div><strong>{insight.title}</strong><p>{insight.detail}</p><small>{insight.source_label || "Local activity monitor"}{Number(insight.duration_seconds) > 0 ? ` · ${formatInsightDuration(Number(insight.duration_seconds))} evidenced` : ""}</small></div></article>)}</div> : <div className="web-insights-empty">No activity summary is available for this date yet.</div>}<footer>Sources: {sourceLabels.length ? sourceLabels.join(" · ") : "Local activity monitor"} · Network access off · {insights?.[0]?.generated_by || "metriday.local.activity-insights"}</footer></section>;
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

function MarkdownTaskLine({ task, line, active, onDragStart, onPointerDragStart, onSelectTask, onComplete, onTitleChange, onTitleCommit, onSchedule }) {
  return (
    <div className={`editor-line task-line ${active ? "recently-updated" : ""}`} draggable onDragStart={(event) => onDragStart(event, task.id)} data-task-id={task.id}>
      <span className="line-number">{line}</span><button type="button" className="drag-handle" aria-label={`Drag ${task.title} to calendar`} onPointerDown={(event) => onPointerDragStart(event, task.id)} onClick={() => onSelectTask(task.id)}><DotsSixVertical size={16} /></button><span className="markdown-token">- [</span>
      <button type="button" className="markdown-check" onClick={() => onComplete(task.id)} aria-label={`Mark ${task.title} ${task.completed ? "incomplete" : "complete"}`}>{task.completed ? <Check size={13} weight="bold" /> : null}</button><span className="markdown-token">]</span>
      {task.start != null ? <TimeEditor task={task} onSchedule={onSchedule} /> : null}
      <input className={`task-title-input ${task.completed ? "completed" : ""}`} value={task.title} onChange={(event) => onTitleChange(task.id, event.target.value)} onBlur={() => onTitleCommit(task.id)} aria-label={`Task title: ${task.title}`} />
      <span className="tag-list">{task.tags.map((tag) => <button type="button" key={tag} className="markdown-tag">#{tag}</button>)}</span>
      {active ? <span className="inline-success"><CheckCircle size={15} weight="fill" /> Time added</span> : null}
    </div>
  );
}

function MarkdownEditor({ tasks, setTasks, lastUpdatedId, planDate, onTaskDragStart, onPointerDragStart, onSelectTask, onSchedule, onComplete, onTitleCommit, addTask }) {
  const [newTitle, setNewTitle] = useState("");
  const newTaskInputRef = useRef(null);
  const updateTask = (id, patch) => setTasks((items) => items.map((task) => task.id === id ? { ...task, ...patch } : task));
  const copyTaskList = () => {
    const markdown = tasks.map((task) => `- [${task.completed ? "x" : " "}] ${task.title}${task.start != null ? ` ${formatRange(task.start, task.end)}` : ""}`).join("\n");
    navigator.clipboard?.writeText(markdown).catch(() => {});
  };
  return (
    <section className="markdown-editor" aria-label="Markdown daily plan">
      <div className="editor-toolbar"><div className="file-name"><FileText size={18} /> {planDate}.md <CaretRight size={13} /></div><div className="editor-actions"><span>Markdown</span><ActionMenu label="Document actions" items={[{ label: "Focus new task", onSelect: () => newTaskInputRef.current?.focus() }, { label: "Copy task list", onSelect: copyTaskList }]}><DotsThree size={22} /></ActionMenu></div></div>
      <div className="editor-body">
        <div className="editor-line heading-line"><span className="line-number">1</span><span className="heading-mark">#</span><strong>{planDateLabel(planDate)}</strong></div>
        <div className="editor-line quote-line"><span className="line-number">2</span><span className="heading-mark">&gt;</span><em>Plan deep work. Ship calm results.</em></div>
        <div className="editor-line empty-line"><span className="line-number">3</span></div>
        <div className="editor-line section-line"><span className="line-number">4</span><span className="heading-mark">##</span><strong>Focus</strong></div>
        {tasks.map((task, index) => <MarkdownTaskLine key={task.id} task={task} line={5 + index} active={lastUpdatedId === task.id} onDragStart={onTaskDragStart} onPointerDragStart={onPointerDragStart} onSelectTask={onSelectTask} onComplete={onComplete} onTitleChange={(id, title) => updateTask(id, { title })} onTitleCommit={onTitleCommit} onSchedule={onSchedule} />)}
        <div className="editor-line add-task-line"><span className="line-number">{5 + tasks.length}</span><span className="markdown-token">- [ ]</span><input ref={newTaskInputRef} value={newTitle} onChange={(event) => setNewTitle(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && newTitle.trim()) { addTask(newTitle.trim()); setNewTitle(""); } }} placeholder="Add a Markdown task…" aria-label="Add a Markdown task" /></div>
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

function CalendarPanel({ tasks, selectedTaskId, setSelectedTaskId, onDropTask, onMoveStart, onComplete, onUnschedule, onResizeStart, dateKey, onSelectDate }) {
  const timelineRef = useRef(null);
  const [mode, setMode] = useState("day");
  const drop = (event) => { event.preventDefault(); const id = event.dataTransfer.getData("text/task-id") || selectedTaskId; if (!id || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(id, event.clientY - rect.top); };
  const calendarItems = [
    { label: "Today", onSelect: () => onSelectDate(localDateKey()) },
    { label: "Previous day", onSelect: () => onSelectDate(offsetDateKey(dateKey, -1)) },
    { label: "Next day", onSelect: () => onSelectDate(offsetDateKey(dateKey, 1)) }
  ];
  if (mode === "week") return (
    <section className="calendar-panel week-panel" aria-label="Week calendar"><div className="calendar-toolbar"><div className="segmented-control"><button type="button" onClick={() => setMode("day")}>Day</button><button type="button" className="active">Week</button></div><ActionMenu label="Calendar options" items={calendarItems}><DotsThree size={21} /></ActionMenu></div><h2>{planDateLabel(offsetDateKey(dateKey, -3))}–{planDateLabel(offsetDateKey(dateKey, 3))}</h2><div className="week-grid">{Array.from({ length: 7 }, (_, index) => offsetDateKey(dateKey, index - 3)).map((day) => <button type="button" key={day} className={day === dateKey ? "today" : ""} onClick={() => { onSelectDate(day); setMode("day"); }}><span>{new Date(`${day}T12:00:00`).toLocaleDateString(undefined, { weekday: "short", day: "numeric" })}</span>{day === dateKey ? <strong>{tasks.filter((task) => task.start != null).length} blocks</strong> : <small>Open</small>}</button>)}</div><p className="week-hint">Select a day to open its draggable timeline.</p></section>
  );
  return (
    <section className="calendar-panel" aria-label="Day calendar">
      <div className="calendar-toolbar"><div className="segmented-control"><button type="button" className="active">Day</button><button type="button" onClick={() => setMode("week")}>Week</button></div><ActionMenu label="Calendar options" items={calendarItems}><DotsThree size={21} /></ActionMenu></div>
      <h2>{new Date(`${dateKey}T12:00:00`).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })}</h2><div className="all-day-row"><span>all-day</span></div>
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

function PlanPage({ tasks, setTasks, api, dateKey, setDateKey }) {
  const [lastUpdatedId, setLastUpdatedId] = useState("genezip");
  const [selectedTaskId, setSelectedTaskId] = useState(null);
  const [toast, setToast] = useState("Markdown updated · 14:00–16:00 added");
  const planDate = dateKey;
  useEffect(() => {
    if (!api.connected || !api.plan?.tasks) return;
    setTasks(api.plan.tasks.map(planTaskFromAPI));
    setSelectedTaskId(null);
  }, [api.connected, api.plan?.date, setTasks]);
  const persistTasks = (nextTasks, message) => {
    setTasks(nextTasks);
    setToast(message);
    if (!api.connected || !api.plan?.markdown || api.plan.date !== dateKey) return;
    api.savePlan(markdownWithTasks(api.plan.markdown, nextTasks))
      .then(() => setToast("Markdown synced to Metriday"))
      .catch(() => setToast("Local change kept; sync failed"));
  };
  const scheduleTask = (id, start, end) => { const nextTasks = tasks.map((task) => task.id === id ? { ...task, start, end } : task); persistTasks(nextTasks, "Markdown updated · " + formatRange(start, end) + " added"); setLastUpdatedId(id); setSelectedTaskId(id); };
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
  const completeTask = (id) => { const nextTasks = tasks.map((task) => task.id === id ? { ...task, completed: !task.completed } : task); persistTasks(nextTasks, "Markdown task state updated"); };
  const titleCommit = () => persistTasks(tasks, "Markdown saved");
  const unscheduleTask = (id) => { const nextTasks = tasks.map((task) => task.id === id ? { ...task, start: null, end: null } : task); persistTasks(nextTasks, "Markdown updated · time removed, task preserved"); setLastUpdatedId(id); setSelectedTaskId(null); };
  const resizeStart = (event, id) => {
    event.preventDefault(); event.stopPropagation(); const task = tasks.find((item) => item.id === id); if (!task) return; const startY = event.clientY; const initialEnd = task.end;
    let finalEnd = initialEnd;
    const move = (moveEvent) => { const delta = Math.round(((moveEvent.clientY - startY) / HOUR_HEIGHT) * 4) * 15; finalEnd = Math.max(task.start + 30, Math.min(DAY_END, initialEnd + delta)); setTasks((items) => items.map((item) => item.id === id ? { ...item, end: finalEnd } : item)); };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); const nextTasks = tasks.map((item) => item.id === id ? { ...item, end: finalEnd } : item); persistTasks(nextTasks, "Markdown updated · calendar duration changed"); setLastUpdatedId(id); };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };
  const addTask = (title) => { const nextTasks = [...tasks, { id: "task-" + Date.now(), title, tags: [], start: null, end: null, completed: false, tone: "soft" }]; persistTasks(nextTasks, "Markdown task added"); };
  return (
    <main className="page plan-page"><header className="plan-header"><h1>Plan <span>·</span> {planDateLabel(planDate)}</h1><div className="date-controls"><CalendarBlank size={21} /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div></header>
      <div className="plan-workspace"><MarkdownEditor tasks={tasks} setTasks={setTasks} lastUpdatedId={lastUpdatedId} planDate={planDate} onTaskDragStart={taskDragStart} onPointerDragStart={pointerMoveStart} onSelectTask={setSelectedTaskId} onSchedule={scheduleTask} onComplete={completeTask} onTitleCommit={titleCommit} addTask={addTask} /><CalendarPanel tasks={tasks} selectedTaskId={selectedTaskId} setSelectedTaskId={setSelectedTaskId} onDropTask={dropTask} onMoveStart={pointerMoveStart} onComplete={completeTask} onUnschedule={unscheduleTask} onResizeStart={resizeStart} dateKey={planDate} onSelectDate={setDateKey} /></div>
      {toast ? <div className="toast" role="status"><CheckCircle size={20} weight="fill" /><span>{toast}</span><IconButton label="Dismiss" onClick={() => setToast("")}><X size={15} /></IconButton></div> : null}
    </main>
  );
}

function formatDurationSeconds(seconds) {
  const minutes = Math.max(0, Math.round(Number(seconds || 0) / 60));
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function formatInsightDuration(seconds) {
  const value = Math.max(0, Number(seconds || 0));
  return value > 0 && value < 60 ? "<1m" : formatDurationSeconds(value);
}

function entryID(entry) {
  return String(entry?.id || "").split("/").pop();
}

function resourceID(value) {
  return String(value || "").split("/").pop();
}

function entryClock(value) {
  const date = new Date(value || "");
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", hour12: false });
}

function entryRange(entry) {
  return `${entryClock(entry.start_date || entry.start)}–${entryClock(entry.end_date || entry.end)}`;
}

function localEntryDate(dateKey, time) {
  const date = new Date(`${dateKey}T${time}:00`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function localEntryDateSeconds(dateKey, seconds) {
  const date = new Date(`${dateKey}T00:00:00`);
  if (Number.isNaN(date.getTime())) return null;
  date.setSeconds(Math.round(Number(seconds || 0)));
  return date.toISOString();
}

function billingLabel(value) {
  const labels = { billable: "Billable", not_billable: "Not billable", pending: "Pending", billed: "Billed", paid: "Paid" };
  return labels[value] || value || "Billable";
}

function projectTitleFor(projects, value) {
  const id = resourceID(value);
  return projects.find((project) => resourceID(project.id) === id)?.title || "Unassigned";
}

function ProjectPanel({ api }) {
  const [title, setTitle] = useState("");
  const [rate, setRate] = useState("0");
  const [currency, setCurrency] = useState("USD");
  const [billingStatus, setBillingStatus] = useState("billable");
  const [editing, setEditing] = useState(null);
  const [message, setMessage] = useState("");
  const projects = [...api.projects].sort((left, right) => String(left.title || "").localeCompare(String(right.title || "")));
  const create = async (event) => {
    event.preventDefault();
    if (!title.trim()) return;
    try {
      await api.createProject({ title: title.trim(), billing_rate: Number(rate) || 0, currency: currency.trim().toUpperCase() || "USD", default_billing_status: billingStatus });
      setTitle("");
      setRate("0");
      setMessage("Project saved locally.");
    } catch (error) {
      setMessage(error.message || "Could not save the project.");
    }
  };
  const beginEdit = (project) => setEditing({ id: project.id, title: project.title || "", rate: String(project.billing_rate || 0), currency: project.currency || "USD", billingStatus: project.default_billing_status || "billable" });
  const saveEdit = async (event) => {
    event.preventDefault();
    if (!editing?.title.trim()) return;
    try {
      await api.updateProject(editing.id, { title: editing.title.trim(), billing_rate: Number(editing.rate) || 0, currency: editing.currency.trim().toUpperCase() || "USD", default_billing_status: editing.billingStatus });
      setEditing(null);
      setMessage("Project updated locally.");
    } catch (error) {
      setMessage(error.message || "Could not update the project.");
    }
  };
  const remove = async (project) => {
    if (!window.confirm(`Archive project “${project.title}”?`)) return;
    try {
      await api.deleteProject(project.id);
      setMessage("Project archived.");
    } catch (error) {
      setMessage(error.message || "Could not archive the project.");
    }
  };
  return <section className="projects-panel"><div className="activities-list-heading"><div><h2>Projects & clients</h2><p>Projects carry billing defaults into timers and manual time entries.</p></div><span className="api-badge online">{projects.length} active</span></div><form className="project-create-form" onSubmit={create}><input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Project or client name" aria-label="Project name" /><input type="number" min="0" step="0.01" value={rate} onChange={(event) => setRate(event.target.value)} placeholder="Rate" aria-label="Project billing rate" /><input value={currency} onChange={(event) => setCurrency(event.target.value)} maxLength={3} aria-label="Project currency" /><select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Project default billing status"><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option></select><button type="submit" disabled={!api.connected}><Plus size={17} />Add project</button></form>{message ? <p className="entry-message" role="status">{message}</p> : null}{projects.length > 0 ? <div className="project-table">{projects.map((project) => editing?.id === project.id ? <form className="project-row project-edit-row" key={project.id} onSubmit={saveEdit}><input value={editing.title} onChange={(event) => setEditing((value) => ({ ...value, title: event.target.value }))} aria-label={`Edit ${project.title} name`} /><input type="number" min="0" step="0.01" value={editing.rate} onChange={(event) => setEditing((value) => ({ ...value, rate: event.target.value }))} aria-label={`Edit ${project.title} rate`} /><input value={editing.currency} onChange={(event) => setEditing((value) => ({ ...value, currency: event.target.value }))} maxLength={3} aria-label={`Edit ${project.title} currency`} /><select value={editing.billingStatus} onChange={(event) => setEditing((value) => ({ ...value, billingStatus: event.target.value }))} aria-label={`Edit ${project.title} billing status`}><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option></select><span className="project-actions"><button type="submit" aria-label="Save project"><Check size={16} /></button><IconButton label="Cancel project edit" onClick={() => setEditing(null)}><X size={15} /></IconButton></span></form> : <div className="project-row" key={project.id}><span className="project-dot" /><strong>{project.title}</strong><span>{project.currency || "USD"} {Number(project.billing_rate || 0).toFixed(2)}/h</span><small>{billingLabel(project.default_billing_status)}</small><span className="project-actions"><IconButton label={`Edit ${project.title}`} onClick={() => beginEdit(project)}><NotePencil size={15} /></IconButton><IconButton label={`Archive ${project.title}`} onClick={() => remove(project)}><Trash size={15} /></IconButton></span></div>)}</div> : <div className="entries-empty"><FolderSimple size={24} /><span>{api.connected ? "Create a project to organize time and billing." : "Connect the native app to manage projects."}</span></div>}</section>;
}

function TimeEntryEditRow({ entry, api, dateKey, projects, onCancel }) {
  const [title, setTitle] = useState(entry.title || "");
  const [start, setStart] = useState(entryClock(entry.start_date || entry.start));
  const [end, setEnd] = useState(entryClock(entry.end_date || entry.end));
  const [project, setProject] = useState(entry.project || "");
  const [billingStatus, setBillingStatus] = useState(entry.billing_status || "billable");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const save = async (event) => {
    event.preventDefault();
    const startDate = localEntryDate(dateKey, start);
    const endDate = localEntryDate(dateKey, end);
    if (!title.trim() || !startDate || !endDate || new Date(endDate) <= new Date(startDate)) {
      setMessage("Enter a valid title and time range.");
      return;
    }
    setBusy(true);
    try {
      await api.updateTimeEntry(entry.id, { title: title.trim(), start_date: startDate, end_date: endDate, project: project || "", billing_status: billingStatus });
      onCancel();
    } catch (error) {
      setMessage(error.message || "Could not update the time entry.");
    } finally {
      setBusy(false);
    }
  };
  return <form className="entry-edit-row" onSubmit={save}><input value={title} onChange={(event) => setTitle(event.target.value)} aria-label="Edit time entry title" /><input type="time" value={start} onChange={(event) => setStart(event.target.value)} aria-label="Edit time entry start" /><input type="time" value={end} onChange={(event) => setEnd(event.target.value)} aria-label="Edit time entry end" /><select value={project} onChange={(event) => setProject(event.target.value)} aria-label="Edit time entry project"><option value="">Unassigned</option>{projects.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</select><select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Edit time entry billing status"><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select><span className="project-actions"><button type="submit" disabled={busy} aria-label="Save time entry"><Check size={16} /></button><IconButton label="Cancel time entry edit" onClick={onCancel}><X size={15} /></IconButton></span>{message ? <small className="entry-edit-message">{message}</small> : null}</form>;
}

function TimeEntriesPanel({ api, dateKey }) {
  const [title, setTitle] = useState("");
  const [start, setStart] = useState("09:00");
  const [end, setEnd] = useState("10:00");
  const [project, setProject] = useState("");
  const [billingStatus, setBillingStatus] = useState("billable");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [editingEntryID, setEditingEntryID] = useState(null);
  const entries = [...api.entries].sort((left, right) => new Date(left.start_date || left.start) - new Date(right.start_date || right.start));
  const projects = [...api.projects].sort((left, right) => String(left.title || "").localeCompare(String(right.title || "")));
  const submit = async (event) => {
    event.preventDefault();
    const startDate = localEntryDate(dateKey, start);
    const endDate = localEntryDate(dateKey, end);
    if (!title.trim() || !startDate || !endDate || new Date(endDate) <= new Date(startDate)) {
      setMessage("Enter a title and a valid time range.");
      return;
    }
    setBusy(true);
    setMessage("");
    try {
      await api.addTimeEntry({ title: title.trim(), start: startDate, end: endDate, projectID: project ? resourceID(project) : undefined, billingStatus });
      setTitle("");
      setMessage("Time entry saved locally.");
    } catch (error) {
      setMessage(error.message || "Could not save the time entry.");
    } finally {
      setBusy(false);
    }
  };
  return <section className="time-entries-panel"><div className="activities-list-heading"><div><h2>Time entries</h2><p>Manual entries and focus sessions for {planDateLabel(dateKey)}.</p></div><span className="api-badge online">{entries.length} saved</span></div><form className="manual-entry-form" onSubmit={submit}><input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="What did you work on?" aria-label="Time entry title" /><label>From<input type="time" value={start} onChange={(event) => setStart(event.target.value)} aria-label="Time entry start" /></label><label>To<input type="time" value={end} onChange={(event) => setEnd(event.target.value)} aria-label="Time entry end" /></label><select value={project} onChange={(event) => setProject(event.target.value)} aria-label="Time entry project"><option value="">Unassigned</option>{projects.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</select><select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Time entry billing status"><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select><button type="submit" disabled={busy || !api.connected}><Plus size={17} />{busy ? "Saving…" : "Add entry"}</button></form>{message ? <p className="entry-message" role="status">{message}</p> : null}{entries.length > 0 ? <div className="entry-table">{entries.map((entry) => editingEntryID === entry.id ? <TimeEntryEditRow key={entry.id} entry={entry} api={api} dateKey={dateKey} projects={projects} onCancel={() => setEditingEntryID(null)} /> : <div className="entry-table-row" key={entry.id}><Clock size={17} /><strong>{entry.title || "Untitled"}</strong><span>{projectTitleFor(projects, entry.project)}</span><span>{entryRange(entry)}</span><small>{billingLabel(entry.billing_status)} · {formatDurationSeconds(entry.duration)}</small>{entry.is_running ? <span className="entry-running">Running</span> : <span className="project-actions"><IconButton label={`Edit ${entry.title || "time entry"}`} onClick={() => setEditingEntryID(entry.id)}><NotePencil size={15} /></IconButton><IconButton label={`Delete ${entry.title || "time entry"}`} onClick={() => api.deleteTimeEntry(entryID(entry)).catch((error) => setMessage(error.message || "Could not delete the time entry."))}><Trash size={15} /></IconButton></span>}</div>)}</div> : <div className="entries-empty"><Clock size={24} /><span>{api.connected ? "No manual entries for this date." : "Connect the native app to edit time entries."}</span></div>}</section>;
}

function ReviewPage({ api, dateKey }) {
  const fallbackDays = [{ label: "Mon", planned: 7.2, actual: 6.6 }, { label: "Tue", planned: 6.5, actual: 7.1 }, { label: "Wed", planned: 7.8, actual: 6.9 }, { label: "Thu", planned: 6.2, actual: 5.8 }, { label: "Fri", planned: 7.1, actual: 6.5 }, { label: "Sat", planned: 5.5, actual: 4.8 }];
  const days = api.weekly.length === 6 ? api.weekly.map((day) => {
    const plannedMinutes = (day.plan?.tasks || []).reduce((total, task) => total + (Number.isFinite(task.start_minute) && Number.isFinite(task.end_minute) ? Math.max(0, task.end_minute - task.start_minute) : 0), 0);
    const activeSeconds = (day.activities || []).reduce((total, activity) => total + (activity.relevance === "idle" ? 0 : Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0))), 0);
    return { label: new Date(`${day.date}T12:00:00`).toLocaleDateString(undefined, { weekday: "short" }), planned: plannedMinutes / 60, actual: activeSeconds / 3600 };
  }) : fallbackDays;
  const relatedSeconds = api.activities.filter((activity) => activity.relevance === "related").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const distractedSeconds = api.activities.filter((activity) => activity.relevance === "distracted").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const totalActive = relatedSeconds + distractedSeconds + api.activities.filter((activity) => activity.relevance === "other").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const taskRelated = totalActive > 0 ? Math.round((relatedSeconds / totalActive) * 100) : 0;
  const deepWork = api.connected ? formatDurationSeconds(relatedSeconds) : "22h 14m";
  const distraction = api.connected ? formatDurationSeconds(distractedSeconds) : "91%";
  return <main className="page supporting-page"><header className="supporting-header"><div><span>{api.connected ? `Live · ${planDateLabel(dateKey)}` : "This week"}</span><h1>Review with evidence</h1></div><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : api.connected ? "Refresh" : "Aug 10–16"}</button></header><section className="review-summary"><div><Timer size={26} /><span>Deep work</span><strong>{deepWork}</strong><small>{api.connected ? `${taskRelated}% task-related today` : "+2h 06m from last week"}</small></div><div><TrendUp size={26} /><span>Task relevance</span><strong>{api.connected ? `${taskRelated}%` : "86%"}</strong><small>{api.connected ? `${formatDurationSeconds(totalActive)} active usage` : "Best on research blocks"}</small></div><div><ShieldCheck size={26} /><span>Distraction</span><strong>{distraction}</strong><small>{api.connected ? "Detected locally" : "6 distractions blocked"}</small></div></section><section className="weekly-chart"><div className="chart-heading"><div><h2>Planned vs. actual</h2><p>{api.connected ? "Six-day evidence from the native activity and Markdown plan stores." : "Longer actual bars reveal underestimated work."}</p></div><div className="legend"><span><i className="planned" />Planned</span><span><i className="actual" />Actual</span></div></div><div className="bar-chart">{days.map((day) => <div key={day.label} className="bar-day"><div className="bar-pair"><i className="planned" style={{ height: `${Math.max(4, Math.min(9, day.planned) * 28)}px` }} /><i className="actual" style={{ height: `${Math.max(4, Math.min(9, day.actual) * 28)}px` }} /></div><span>{day.label}</span></div>)}</div></section>{api.connected ? <WebActivityInsights insights={api.insights} dateKey={dateKey} /> : null}<WebReportPanel api={api} dateKey={dateKey} /></main>;
}

function reportRoundSeconds(seconds, mode, intervalMinutes) {
  if (mode === "none") return seconds;
  const interval = Math.max(1, intervalMinutes) * 60;
  if (mode === "up") return Math.ceil(seconds / interval) * interval;
  if (mode === "down") return Math.floor(seconds / interval) * interval;
  return Math.round(seconds / interval) * interval;
}

function reportDateTime(dateKey, second) {
  const date = new Date(`${dateKey}T00:00:00`);
  date.setSeconds(Math.max(0, Number(second || 0)));
  return date;
}

function reportCell(value) {
  return `"${String(value ?? "").replace(/"/g, '""')}"`;
}

function reportHTMLCell(value) {
  return String(value ?? "").replace(/[&<>\"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[character]));
}

function downloadReport(filename, content, type) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

function WebReportPanel({ api, dateKey }) {
  const [rangeStart, setRangeStart] = useState(offsetDateKey(dateKey, -6));
  const [rangeEnd, setRangeEnd] = useState(dateKey);
  const [includeActivities, setIncludeActivities] = useState(true);
  const [billingFilter, setBillingFilter] = useState("all");
  const [rounding, setRounding] = useState("none");
  const [roundingInterval, setRoundingInterval] = useState(15);
  const [dataset, setDataset] = useState({ activities: [], entries: [] });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  useEffect(() => {
    setRangeStart(offsetDateKey(dateKey, -6));
    setRangeEnd(dateKey);
  }, [dateKey]);
  useEffect(() => {
    if (!api.connected || !rangeStart || !rangeEnd || rangeStart > rangeEnd) return;
    let current = true;
    setLoading(true);
    setMessage("");
    api.fetchRange(rangeStart, rangeEnd).then((result) => {
      if (current) setDataset(result);
    }).catch((error) => {
      if (current) setMessage(error.message || "Could not load report data.");
    }).finally(() => {
      if (current) setLoading(false);
    });
    return () => { current = false; };
  }, [api.connected, api.fetchRange, api.refreshVersion, rangeStart, rangeEnd]);
  const report = useMemo(() => {
    const startBound = new Date(`${rangeStart}T00:00:00`);
    const endBound = new Date(`${offsetDateKey(rangeEnd, 1)}T00:00:00`);
    const projectFor = (value) => projectTitleFor(api.projects, value);
    const projectDetails = (value) => {
      const project = api.projects.find((item) => resourceID(item.id) === resourceID(value));
      return { rate: project?.billing_rate || 0, currency: project?.currency || "USD" };
    };
    const rows = [];
    dataset.entries.forEach((entry) => {
      const start = new Date(entry.start_date || entry.start);
      const end = new Date(entry.end_date || entry.end);
      if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end <= start || end <= startBound || start >= endBound) return;
      if (billingFilter !== "all" && entry.billing_status !== billingFilter) return;
      const clippedStart = start < startBound ? startBound : start;
      const clippedEnd = end > endBound ? endBound : end;
      const seconds = reportRoundSeconds(Math.max(0, (clippedEnd - clippedStart) / 1000), rounding, Number(roundingInterval));
      const details = projectDetails(entry.project);
      rows.push({ kind: "Time entry", title: entry.title || "Untitled", project: projectFor(entry.project), billing: billingLabel(entry.billing_status), currency: details.currency, start: clippedStart, end: clippedEnd, seconds, amount: seconds / 3600 * details.rate, notes: entry.notes || "" });
    });
    if (includeActivities && billingFilter === "all") {
      dataset.activities.forEach((activity) => {
        if (activity.relevance === "idle") return;
        const start = reportDateTime(activity.date, activity.startSecond);
        const end = reportDateTime(activity.date, activity.endSecond);
        if (end <= startBound || start >= endBound || end <= start) return;
        const clippedStart = start < startBound ? startBound : start;
        const clippedEnd = end > endBound ? endBound : end;
        const seconds = reportRoundSeconds(Math.max(0, (clippedEnd - clippedStart) / 1000), rounding, Number(roundingInterval));
        const details = projectDetails(activity.projectID);
        rows.push({ kind: "Activity", title: activityLabel(activity), project: projectFor(activity.projectID), billing: activity.relevance || "other", currency: details.currency, start: clippedStart, end: clippedEnd, seconds, amount: seconds / 3600 * details.rate, notes: activity.windowTitle || "" });
      });
    }
    rows.sort((left, right) => left.start - right.start);
    return { rows, totalSeconds: rows.reduce((sum, row) => sum + row.seconds, 0), billableSeconds: rows.filter((row) => row.billing === "Billable").reduce((sum, row) => sum + row.seconds, 0), amount: rows.reduce((sum, row) => sum + row.amount, 0), currencies: [...new Set(rows.map((row) => row.currency).filter(Boolean))] };
  }, [api.projects, billingFilter, dataset, includeActivities, rangeEnd, rangeStart, rounding, roundingInterval]);
  const setPreset = (preset) => {
    if (preset === "today") {
      setRangeStart(dateKey);
      setRangeEnd(dateKey);
    } else if (preset === "month") {
      const date = new Date(`${dateKey}T12:00:00`);
      date.setDate(1);
      setRangeStart(localDateKey(date));
      setRangeEnd(dateKey);
    } else {
      setRangeStart(offsetDateKey(dateKey, -6));
      setRangeEnd(dateKey);
    }
  };
  const exportRows = report.rows.map((row) => ({ kind: row.kind, title: row.title, project: row.project, billing_status: row.billing, currency: row.currency, start: row.start.toISOString(), end: row.end.toISOString(), duration_seconds: row.seconds, amount: Number(row.amount.toFixed(2)), notes: row.notes }));
  const exportCSV = () => {
    const headers = ["Kind", "Title", "Project", "Billing Status", "Currency", "Start", "End", "Duration Seconds", "Amount", "Notes"];
    const csv = [headers, ...exportRows.map((row) => [row.kind, row.title, row.project, row.billing_status, row.currency, row.start, row.end, row.duration_seconds, row.amount, row.notes])].map((line) => line.map(reportCell).join(",")).join("\n");
    downloadReport(`metriday-report-${rangeStart}-${rangeEnd}.csv`, csv, "text/csv;charset=utf-8");
  };
  const exportJSON = () => downloadReport(`metriday-report-${rangeStart}-${rangeEnd}.json`, JSON.stringify({ startDate: rangeStart, endDate: rangeEnd, totalSeconds: report.totalSeconds, billableSeconds: report.billableSeconds, amount: Number(report.amount.toFixed(2)), currencies: report.currencies, rows: exportRows }, null, 2), "application/json");
  const exportHTML = () => {
    const tableRows = exportRows.map((row) => `<tr><td>${reportHTMLCell(row.kind)}</td><td>${reportHTMLCell(row.title)}</td><td>${reportHTMLCell(row.project)}</td><td>${reportHTMLCell(row.billing_status)}</td><td>${reportHTMLCell(row.currency)}</td><td>${reportHTMLCell(row.start)}</td><td>${reportHTMLCell(row.end)}</td><td>${reportHTMLCell(row.duration_seconds)}</td><td>${reportHTMLCell(row.amount)}</td></tr>`).join("");
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>Metriday report ${rangeStart} to ${rangeEnd}</title><style>body{font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#252832;margin:36px}h1{font-size:24px}p{color:#626978}table{border-collapse:collapse;width:100%;margin-top:24px}th,td{border:1px solid #dfe1e6;padding:8px;text-align:left;font-size:12px}th{background:#f4f5f8}</style></head><body><h1>Metriday report</h1><p>${rangeStart} to ${rangeEnd} · Total ${reportHTMLCell(formatDurationSeconds(report.totalSeconds))} · Billable ${reportHTMLCell(formatDurationSeconds(report.billableSeconds))} · Amount ${reportHTMLCell(report.amount.toFixed(2))} ${reportHTMLCell(report.currencies.length === 1 ? report.currencies[0] : report.currencies.length > 1 ? "mixed" : "USD")}</p><table><thead><tr><th>Kind</th><th>Title</th><th>Project</th><th>Billing</th><th>Currency</th><th>Start</th><th>End</th><th>Duration (s)</th><th>Amount</th></tr></thead><tbody>${tableRows}</tbody></table></body></html>`;
    downloadReport(`metriday-report-${rangeStart}-${rangeEnd}.html`, html, "text/html;charset=utf-8");
  };
  return <section className="web-report-panel"><div className="chart-heading"><div><h2>Reports & exports</h2><p>Timing-style reports from local activities, time entries, projects, and billing status.</p></div><div className="report-actions"><button type="button" onClick={exportCSV} disabled={!report.rows.length}>Export CSV</button><button type="button" onClick={exportJSON} disabled={!report.rows.length}>Export JSON</button><button type="button" onClick={exportHTML} disabled={!report.rows.length}>Export HTML</button></div></div><div className="report-presets"><button type="button" onClick={() => setPreset("today")}>Today</button><button type="button" className="active" onClick={() => setPreset("week")}>Last 7 days</button><button type="button" onClick={() => setPreset("month")}>This month</button><label>From<input type="date" value={rangeStart} onChange={(event) => setRangeStart(event.target.value)} /></label><label>To<input type="date" value={rangeEnd} onChange={(event) => setRangeEnd(event.target.value)} /></label></div><div className="report-filters"><label><input type="checkbox" checked={includeActivities} onChange={(event) => setIncludeActivities(event.target.checked)} />Include app activity</label><label>Billing<select value={billingFilter} onChange={(event) => setBillingFilter(event.target.value)}><option value="all">All statuses</option><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select></label><label>Rounding<select value={rounding} onChange={(event) => setRounding(event.target.value)}><option value="none">Exact</option><option value="up">Round up</option><option value="down">Round down</option><option value="nearest">Nearest</option></select></label><label>Interval<select value={roundingInterval} onChange={(event) => setRoundingInterval(Number(event.target.value))}><option value={1}>1 min</option><option value={5}>5 min</option><option value={6}>6 min</option><option value={10}>10 min</option><option value={12}>12 min</option><option value={15}>15 min</option><option value={30}>30 min</option><option value={60}>1 hour</option></select></label></div>{message ? <p className="entry-message" role="status">{message}</p> : null}<div className="report-metrics"><div><span>Total</span><strong>{formatDurationSeconds(report.totalSeconds)}</strong></div><div><span>Billable</span><strong>{formatDurationSeconds(report.billableSeconds)}</strong></div><div><span>Amount</span><strong>{report.amount.toFixed(2)} {report.currencies.length === 1 ? report.currencies[0] : report.currencies.length > 1 ? "mixed" : "USD"}</strong></div><div><span>Rows</span><strong>{loading ? "…" : report.rows.length}</strong></div></div>{report.rows.length > 0 ? <div className="report-table"><div className="report-table-head"><span>Title</span><span>Project</span><span>Timespan</span><span>Duration</span><span>Billing</span></div>{report.rows.slice(0, 40).map((row, index) => <div className="report-table-row" key={`${row.kind}-${row.start.toISOString()}-${index}`}><strong>{row.title}</strong><span>{row.project}</span><span>{row.start.toLocaleDateString(undefined, { month: "short", day: "numeric" })} {entryClock(row.start)}–{entryClock(row.end)}</span><span>{formatDurationSeconds(row.seconds)}</span><small>{row.billing}</small></div>)}</div> : <div className="entries-empty"><ChartBar size={24} /><span>{loading ? "Loading report data…" : api.connected ? "No rows match this report." : "Connect the native app to generate a report."}</span></div>}</section>;
}

function ActivityTable({ activities }) {
  return <div className="activity-table">
    <div className="activity-table-head" aria-hidden="true"><span>App</span><span>Category</span><span>Time</span><span>Device</span></div>
    {activities.map((activity) => {
      const category = activityCategory(activity);
      const Icon = activityIcon(activity);
      const app = activity.appName || activity.deviceName || "Unknown App";
      const context = activityContext(activity);
      const start = Math.floor(Number(activity.startSecond || 0) / 60);
      const end = Math.ceil(Number(activity.endSecond || 0) / 60);
      const duration = Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
      return <div className="activity-table-row" key={activity.id}>
        <div className="activity-app-cell">
          <span className="activity-table-icon"><Icon size={19} weight="duotone" /></span>
          <span className="activity-app-copy"><strong>{app}</strong>{context ? <small>{context}</small> : null}</span>
        </div>
        <span className={`activity-category ${category.key}`}><i />{category.label}</span>
        <span>{formatRange(start, end)}</span>
        <small>{formatDurationSeconds(duration)} · {activity.deviceName || "This Mac"}</small>
      </div>;
    })}
  </div>;
}

function ActivitiesPage({ api, dateKey, setDateKey }) {
  const [query, setQuery] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [deviceFilter, setDeviceFilter] = useState("all");
  const allActivities = [...api.activities].sort((left, right) => Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const devices = [...new Set(allActivities.map((activity) => activity.deviceName || "This Mac"))].sort();
  const normalizedQuery = query.trim().toLowerCase();
  const activities = allActivities.filter((activity) => {
    const category = activityCategory(activity);
    const searchable = `${activityLabel(activity)} ${activityContext(activity)} ${activity.appName || ""} ${activity.deviceName || ""} ${category.label}`.toLowerCase();
    return (!normalizedQuery || searchable.includes(normalizedQuery))
      && (categoryFilter === "all" || category.key === categoryFilter)
      && (deviceFilter === "all" || (activity.deviceName || "This Mac") === deviceFilter);
  });
  const hasFilters = Boolean(normalizedQuery || categoryFilter !== "all" || deviceFilter !== "all");
  const resetFilters = () => {
    setQuery("");
    setCategoryFilter("all");
    setDeviceFilter("all");
  };
  return <main className="page supporting-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? `Native activity stream · ${planDateLabel(dateKey)}` : "Local preview"}</span><h1>Activities</h1></div><div className="activities-page-actions"><div className="date-controls"><CalendarBlank size={20} /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : "Refresh"}</button></div></header><div className="activities-page-toolbar"><label className="activity-search"><Waveform size={18} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search app, website, window title…" aria-label="Search activities" />{query ? <IconButton label="Clear activity search" onClick={() => setQuery("")}><X size={15} /></IconButton> : null}</label><label className="activity-filter-control">Category<select value={categoryFilter} onChange={(event) => setCategoryFilter(event.target.value)} aria-label="Activity category filter"><option value="all">All categories</option><option value="focused">Focused</option><option value="distracting">Distracting</option><option value="other">Other</option><option value="idle">Idle</option></select></label><label className="activity-filter-control">Device<select value={deviceFilter} onChange={(event) => setDeviceFilter(event.target.value)} aria-label="Activity device filter"><option value="all">All devices</option>{devices.map((device) => <option key={device} value={device}>{device}</option>)}</select></label><button type="button" className="quiet-pill activity-reset" onClick={resetFilters} disabled={!hasFilters}>Reset</button></div><ProjectPanel api={api} /><TimeEntriesPanel api={api} dateKey={dateKey} /><section className="activities-list"><div className="activities-list-heading"><div><h2>Today’s activity</h2><p>{api.connected ? hasFilters ? `${activities.length} of ${allActivities.length} locally recorded segments` : `${activities.length} locally recorded segments` : "Start Metriday to see app, browser, and Screen Time activity here."}</p></div><span className={`api-badge ${api.connected ? "online" : "offline"}`}>{api.connected ? "Connected" : "Offline"}</span></div>{activities.length === 0 ? <div className="activities-empty"><Waveform size={34} /><strong>{api.connected ? allActivities.length > 0 ? "No activity matches these filters" : "No activity recorded yet" : "Waiting for the native Metriday app"}</strong><span>{api.error || (hasFilters ? "Clear the filters to see all local activity." : "The hosted view keeps working with preview data until the loopback API is available.")}</span></div> : <ActivityTable activities={activities} />}</section></main>;
}

function RulesPage() {
  const [locked, setLocked] = useState(true); const [blocked, setBlocked] = useState(["youtube.com", "x.com", "reddit.com"]); const [allowed, setAllowed] = useState(["arxiv.org", "github.com", "pytorch.org"]); const [draft, setDraft] = useState("");
  return <main className="page supporting-page rules-page"><header className="supporting-header"><div><span>Focus rules</span><h1>Research Focus</h1></div><button type="button" className={`status-pill ${locked ? "active" : ""}`} onClick={() => setLocked((value) => !value)}><LockSimple size={17} />{locked ? "Locked mode on" : "Flexible mode"}</button></header><div className="rules-layout"><section className="rule-overview"><ShieldCheck size={54} color="#3da65a" weight="duotone" /><h2>Protect deep-work blocks</h2><p>This rule starts with scheduled research tasks and stays local to this Mac.</p><div className="rule-meta"><span><Clock size={18} />Runs with calendar blocks</span><span><Laptop size={18} />Local processing</span><span><Browsers size={18} />All browsers</span></div></section><section className="site-list-section"><div className="site-list-heading"><div><h2>Blocked sites</h2><p>Attempts are recorded as distraction evidence.</p></div><strong>{blocked.length}</strong></div><div className="site-list">{blocked.map((site) => <div key={site}><GlobeSimple size={20} /><span>{site}</span><IconButton label={`Allow ${site}`} onClick={() => { setBlocked((items) => items.filter((item) => item !== site)); setAllowed((items) => [...items, site]); }}><X size={15} /></IconButton></div>)}</div><form onSubmit={(event) => { event.preventDefault(); if (draft.trim() && !blocked.includes(draft.trim())) setBlocked((items) => [...items, draft.trim()]); setDraft(""); }}><GlobeSimple size={19} /><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a distracting domain" aria-label="Add blocked website" /><button type="submit"><Plus size={17} />Add</button></form></section><section className="site-list-section allowed-section"><div className="site-list-heading"><div><h2>Allowed research</h2><p>Always available inside this focus rule.</p></div><strong>{allowed.length}</strong></div><div className="site-list">{allowed.map((site) => <div key={site}><CheckCircle size={20} weight="fill" /><span>{site}</span></div>)}</div></section></div></main>;
}

function RulesPageLive({ api }) {
  const [locked, setLocked] = useState(true);
  const [blocked, setBlocked] = useState(["youtube.com", "x.com", "reddit.com"]);
  const [allowed, setAllowed] = useState(["arxiv.org", "github.com", "pytorch.org"]);
  const [draft, setDraft] = useState("");
  const [message, setMessage] = useState("");
  const remoteRules = api.connected ? api.rules : null;
  const blockedItems = remoteRules ? remoteRules.filter((rule) => !rule.allowed) : blocked.map((domain) => ({ id: domain, domain, allowed: false }));
  const allowedItems = remoteRules ? remoteRules.filter((rule) => rule.allowed) : allowed.map((domain) => ({ id: domain, domain, allowed: true }));
  const focusActive = api.connected ? api.focusActive : locked;
  const toggleFocus = () => {
    if (!api.connected) {
      setLocked((value) => !value);
      return;
    }
    api.setFocusActive(!api.focusActive).catch((error) => setMessage(error.message || "Could not change Focus state."));
  };
  const addDomain = async (event) => {
    event.preventDefault();
    const domain = draft.trim();
    if (!domain) return;
    try {
      if (api.connected) await api.addWebRule(domain, false);
      else if (!blocked.includes(domain)) setBlocked((items) => [...items, domain]);
      setDraft("");
      setMessage("Blocked site added.");
    } catch (error) {
      setMessage(error.message || "Could not add the blocked site.");
    }
  };
  const allowDomain = (item) => {
    if (api.connected) api.updateWebRule(item.id, true).catch((error) => setMessage(error.message || "Could not allow the site."));
    else {
      setBlocked((items) => items.filter((domain) => domain !== item.domain));
      setAllowed((items) => items.includes(item.domain) ? items : [...items, item.domain]);
    }
  };
  const removeDomain = (item) => {
    if (api.connected) api.deleteWebRule(item.id).catch((error) => setMessage(error.message || "Could not remove the site."));
    else setAllowed((items) => items.filter((domain) => domain !== item.domain));
  };
  return <main className="page supporting-page rules-page"><header className="supporting-header"><div><span>{api.connected ? "Native Focus rules" : "Focus rules"}</span><h1>Research Focus</h1></div><button type="button" className={`status-pill ${focusActive ? "active" : ""}`} onClick={toggleFocus}><LockSimple size={17} />{focusActive ? "Locked mode on" : "Flexible mode"}</button></header><div className="rules-layout"><section className="rule-overview"><ShieldCheck size={54} color="#3da65a" weight="duotone" /><h2>Protect deep-work blocks</h2><p>{api.connected ? "Changes are saved to the native Metriday blocklist on this Mac." : "This rule starts with scheduled research tasks and stays local to this Mac."}</p><div className="rule-meta"><span><Clock size={18} />Runs with calendar blocks</span><span><Laptop size={18} />Local processing</span><span><Browsers size={18} />Safari + Chrome</span></div></section><section className="site-list-section"><div className="site-list-heading"><div><h2>Blocked sites</h2><p>Attempts are recorded as distraction evidence.</p></div><strong>{blockedItems.length}</strong></div><div className="site-list">{blockedItems.map((item) => <div key={item.id}><GlobeSimple size={20} /><span>{item.domain}</span><IconButton label={`Allow ${item.domain}`} onClick={() => allowDomain(item)}><X size={15} /></IconButton></div>)}</div><form onSubmit={addDomain}><GlobeSimple size={19} /><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a distracting domain" aria-label="Add blocked website" /><button type="submit"><Plus size={17} />Add</button></form></section><section className="site-list-section allowed-section"><div className="site-list-heading"><div><h2>Allowed research</h2><p>Always available inside this focus rule.</p></div><strong>{allowedItems.length}</strong></div><div className="site-list">{allowedItems.map((item) => <div key={item.id}><CheckCircle size={20} weight="fill" /><span>{item.domain}</span><IconButton label={`Remove ${item.domain}`} onClick={() => removeDomain(item)}><X size={15} /></IconButton></div>)}</div></section></div>{message ? <p className="entry-message rules-message" role="status">{message}</p> : null}</main>;
}

export function App() {
  const [page, setPage] = useState("today");
  const [dateKey, setDateKey] = useState(localDateKey());
  const [tasks, setTasks] = useState(initialTasks);
  const [apiBase, setApiBase] = useState(apiBaseURL);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const api = useMetridayAPI(dateKey, apiBase);
  const content = useMemo(() => page === "plan" ? <PlanPage tasks={tasks} setTasks={setTasks} api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "activities" ? <ActivitiesPage api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "review" ? <ReviewPage api={api} dateKey={dateKey} /> : page === "rules" ? <RulesPageLive api={api} /> : <TodayPage setPage={setPage} api={api} dateKey={dateKey} setDateKey={setDateKey} />, [api, page, tasks, dateKey]);
  return <div className="app-shell"><Sidebar page={page} setPage={setPage} api={api} onOpenSettings={() => setSettingsOpen(true)} />{content}<ConnectionSettings open={settingsOpen} apiBase={apiBase} connected={api.connected} onSave={setApiBase} onClose={() => setSettingsOpen(false)} /></div>;
}
