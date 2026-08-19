import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowsClockwise, BookOpen, Browsers, CalendarBlank, CaretDown, CaretLeft, CaretRight,
  ChartBar, Check, CheckCircle, Clock, Code, DotsSixVertical, DotsThree,
  FileText, Flask, FolderSimple, GearSix, GlobeSimple, Laptop, LinkSimple,
  LockSimple, NotePencil, Pause, Play, Plus, ShieldCheck, Sparkle, TerminalWindow,
  Timer, Trash, TrendUp, UsersThree, Waveform, X, SlidersHorizontal,
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
  { id: "stats", label: "Stats", icon: ChartBar },
  { id: "reports", label: "Reports", icon: FileText },
  { id: "teams", label: "Teams", icon: UsersThree },
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
    phoneCalls: { data: [], database_available: false, status: "Phone Calls integration not connected" },
    filters: [],
    categories: [],
    calendarEvents: { data: [], authorized: false, status: "Calendar access not connected" },
    reminders: { data: [], authorized: false, status: "Reminders access not connected" },
    screenTime: { data: [], database_available: false, status: "Screen Time integration not connected" },
    projectRules: [],
    preferences: null,
    integrations: [],
    exclusions: [],
    activityPreferences: null,
    teams: [],
    weekly: [],
    insights: [],
  });

  const request = useCallback((path, options = {}) => apiRequest(path, options, apiBase), [apiBase]);

  const refresh = useCallback(async () => {
    const date = dateKey || localDateKey();
    const weekKeys = Array.from({ length: 7 }, (_, index) => offsetDateKey(date, index - 6));
    try {
      const status = await request("/v1/status");
      const results = await Promise.allSettled([
        request(`/v1/activities?date=${date}`),
        request(`/api/v1/time-entries?start_date_min=${date}&start_date_max=${date}`),
        request("/api/v1/projects"),
        request(`/v1/plans?date=${date}`),
        request("/v1/sync/status"),
        request("/v1/rules"),
        request(`/v1/phone-calls?date=${date}`),
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
        request("/v1/filters"),
        request("/v1/categories"),
        request(`/v1/calendar-events?date=${date}`),
        request(`/v1/reminders?date=${date}`),
        request(`/v1/screen-time?date=${date}`),
        request("/v1/project-rules"),
        request("/v1/preferences"),
        request("/v1/integrations"),
        request("/v1/exclusions"),
        request("/v1/activity-preferences"),
        request("/v1/teams"),
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
        phoneCalls: value(6, { data: [], database_available: false, status: "Phone Calls integration not connected" }),
        weekly: value(7, []),
        insights: value(8, { data: [] })?.data || [],
        filters: value(9, { data: [] })?.data || [],
        categories: value(10, { data: [] })?.data || [],
        calendarEvents: value(11, { data: [], authorized: false, status: "Calendar access not connected" }),
        reminders: value(12, { data: [], authorized: false, status: "Reminders access not connected" }),
        screenTime: value(13, { data: [], database_available: false, status: "Screen Time integration not connected" }),
        projectRules: value(14, { data: [] })?.data || [],
        preferences: value(15, null),
        integrations: value(16, { data: [] })?.data || [],
        exclusions: value(17, { data: [] })?.data || [],
        activityPreferences: value(18, null),
        teams: value(19, { data: [] })?.data || [],
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

  const fetchPlan = useCallback((date = localDateKey()) => request(`/v1/plans?date=${date}`), [request]);

  return {
    ...snapshot,
    refreshVersion,
    refresh,
    fetchRange,
    fetchPlan,
    downloadReportFile: async ({ startDate, endDate, format, include, groupBy, billingFilter, rounding, roundingMinutes }) => {
      const params = new URLSearchParams({ start_date: startDate, end_date: endDate, format, include, group_by: groupBy, billing_status: billingFilter, rounding, rounding_minutes: String(roundingMinutes) });
      const response = await fetch(`${normalizeApiBase(apiBase)}/v1/reports?${params.toString()}`);
      if (!response.ok) throw new Error((await response.text().catch(() => "")) || "Could not generate the native report.");
      const blob = await response.blob();
      const href = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = href;
      link.download = `metriday-report-${startDate}-${endDate}.${format}`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(href);
    },
    startTimer: (title, projectID, options = {}) => mutate("/v1/timer/start", { title, projectID, ...options }),
    stopTimer: () => mutate("/v1/timer/stop"),
    setTimerEstimate: (minutes) => mutate("/v1/timer/estimate", { estimatedMinutes: Number(minutes) }),
    adjustTimer: (minutes) => mutate("/v1/timer/adjust", { minutes: Number(minutes) }),
    toggleTracking: () => mutate(snapshot.status?.tracking ? "/v1/tracking/pause" : "/v1/tracking/resume"),
    updatePreferences: async (preferences) => {
      await request("/v1/preferences", { method: "PATCH", body: JSON.stringify(preferences) });
      await refresh();
    },
    updateActivityPreferences: async (preferences) => {
      await request("/v1/activity-preferences", { method: "PATCH", body: JSON.stringify(preferences) });
      await refresh();
    },
    syncNow: () => mutate("/v1/sync/now"),
    restoreSync: () => mutate("/v1/sync/restore"),
    syncIntegration: async (provider) => {
      await request(`/v1/integrations/${encodeURIComponent(provider)}/sync`, { method: "POST" });
      await refresh();
    },
    exportProjects: () => request("/v1/projects/export"),
    importProjects: async (archive) => {
      const result = await request("/v1/projects/import", { method: "POST", body: archive });
      await refresh();
      return result;
    },
    exportTimeEntries: () => request("/v1/time-entries/export"),
    importTimeEntries: async (archive) => {
      const result = await request("/v1/time-entries/import", { method: "POST", body: archive });
      await refresh();
      return result;
    },
    addTimeEntry: async (entry) => {
      await request("/v1/time-entries", { method: "POST", body: JSON.stringify(entry) });
      await refresh();
    },
    createTimeEntries: async (entries) => {
      for (const entry of entries) {
        await request("/v1/time-entries", { method: "POST", body: JSON.stringify(entry) });
      }
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
    deleteTimeEntries: async (ids) => {
      for (const id of ids) {
        await request(`/api/v1/time-entries/${resourceID(id)}`, { method: "DELETE" });
      }
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
    hidePhoneCallAddress: async (address, hidden = true) => {
      await request("/v1/phone-calls/hide", { method: "POST", body: JSON.stringify({ address, hidden }) });
      await refresh();
    },
    createActivityFilter: async (filter) => {
      await request("/v1/filters", { method: "POST", body: JSON.stringify(filter) });
      await refresh();
    },
    deleteActivityFilter: async (id) => {
      await request(`/v1/filters/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    updateActivityFilter: async (id, filter) => {
      await request(`/v1/filters/${resourceID(id)}`, { method: "PATCH", body: JSON.stringify(filter) });
      await refresh();
    },
    createActivityExclusion: async (rule) => {
      await request("/v1/exclusions", { method: "POST", body: JSON.stringify(rule) });
      await refresh();
    },
    deleteActivityExclusion: async (id) => {
      await request(`/v1/exclusions/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    createActivityCategory: async (category) => {
      await request("/v1/categories", { method: "POST", body: JSON.stringify(category) });
      await refresh();
    },
    deleteActivityCategory: async (id) => {
      await request(`/v1/categories/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    updateActivityCategory: async (id, category) => {
      await request(`/v1/categories/${resourceID(id)}`, { method: "PATCH", body: JSON.stringify(category) });
      await refresh();
    },
    createProjectRule: async (rule) => {
      await request("/v1/project-rules", { method: "POST", body: JSON.stringify(rule) });
      await refresh();
    },
    deleteProjectRule: async (id) => {
      await request(`/v1/project-rules/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    moveProjectRule: async (id, offset) => {
      await request(`/v1/project-rules/${resourceID(id)}`, { method: "PATCH", body: JSON.stringify({ offset }) });
      await refresh();
    },
    savePlan: async (markdown, date = dateKey || localDateKey()) => {
      await request(`/v1/plans?date=${date}`, { method: "PUT", body: JSON.stringify({ markdown }) });
      await refresh();
    },
    assignActivity: async (id, projectID, date = dateKey || localDateKey()) => {
      await request(`/v1/activities/${resourceID(id)}?date=${date}`, { method: "PATCH", body: JSON.stringify({ projectID: projectID || null }) });
      await refresh();
    },
    createTeam: async (team) => {
      await request("/v1/teams", { method: "POST", body: JSON.stringify(team) });
      await refresh();
    },
    archiveTeam: async (id) => {
      await request(`/v1/teams/${resourceID(id)}`, { method: "DELETE" });
      await refresh();
    },
    addTeamMember: async (id, member) => {
      await request(`/v1/teams/${resourceID(id)}/members`, { method: "POST", body: JSON.stringify(member) });
      await refresh();
    },
    fetchTeamMembers: async (id) => {
      const result = await request(`/v1/teams/${resourceID(id)}/members`);
      return result?.data || [];
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
  const categoryRole = String(activity?.categoryRole || "").toLowerCase();
  if (["focused", "distracting", "other", "idle"].includes(categoryRole)) {
    return { key: categoryRole, label: activity.categoryName || categoryRole[0].toUpperCase() + categoryRole.slice(1), color: activity.categoryColor || categoryRoleColor(categoryRole) };
  }
  switch (activity?.relevance) {
    case "related":
      return { key: "focused", label: "Focused", color: "blue" };
    case "distracted":
      return { key: "distracting", label: "Distracting", color: "red" };
    case "idle":
      return { key: "idle", label: "Idle", color: "graphite" };
    default:
      return { key: "other", label: "Other", color: "graphite" };
  }
}

function categoryRoleColor(role) {
  return ["focused", "related", "current"].includes(role) ? "blue" : ["distracting", "distracted"].includes(role) ? "red" : "graphite";
}

function activityCategoryStyle(category) {
  const palette = {
    blue: { color: "#384ae0", background: "#eef0ff" },
    red: { color: "#d24b4b", background: "#fff0f0" },
    green: { color: "#399a55", background: "#f2faf4" },
    orange: { color: "#d77b22", background: "#fff6ea" },
    purple: { color: "#7b57b5", background: "#f5f0ff" },
    graphite: { color: "#6f7480", background: "#f0f1f4" },
  };
  return palette[category?.color] || palette.graphite;
}

function activityFilterValues(activity, field) {
  switch (field) {
    case "application": return [activity.appName || ""];
    case "bundleIdentifier": return [activity.bundleIdentifier || ""];
    case "windowTitle": return [activity.windowTitle || ""];
    case "resource": return [activity.resource || ""];
    case "domain": return [activity.resource || ""];
    case "fullURL": return [activity.resource || ""];
    case "keyword": return [activity.appName, activity.windowTitle, activity.resource].filter(Boolean);
    case "device": return [activity.deviceName || "This Mac"];
    default: return [];
  }
}

function activityFilterRuleMatches(activity, rule) {
  const pattern = String(rule.pattern || "");
  const flags = rule.case_sensitive ? "" : "i";
  const values = activityFilterValues(activity, rule.field);
  if (!values.length || !pattern) return false;
  if (rule.comparison === "matchesRegex") {
    try { return values.some((value) => new RegExp(pattern, flags).test(String(value))); } catch { return false; }
  }
  return values.some((value) => {
    const source = String(value);
    const left = rule.case_sensitive ? source : source.toLowerCase();
    const right = rule.case_sensitive ? pattern : pattern.toLowerCase();
    switch (rule.comparison) {
      case "equals": return left === right;
      case "beginsWith": return left.startsWith(right);
      case "endsWith": return left.endsWith(right);
      case "isNot": return left !== right;
      case "like": return left.includes(right.replaceAll("%", ""));
      default: return left.includes(right);
    }
  });
}

function activityMatchesFilter(activity, filter) {
  const rules = Array.isArray(filter?.rules) ? filter.rules : [];
  if (!rules.length) return false;
  return filter.match_mode === "all"
    ? rules.every((rule) => activityFilterRuleMatches(activity, rule))
    : rules.some((rule) => activityFilterRuleMatches(activity, rule));
}

function activityBlockStyle(color) {
  const palette = {
    blue: { borderColor: "#cfd8ff", background: "#f1f4ff" },
    red: { borderColor: "#f0caca", background: "#fff5f5" },
    green: { borderColor: "#cbe7d2", background: "#f2faf4" },
    orange: { borderColor: "#f2d8b4", background: "#fff8ee" },
    purple: { borderColor: "#dfd1f3", background: "#f8f3ff" },
    graphite: { borderColor: "#e2e3e7", background: "#f7f7f8" },
  };
  return palette[color] || palette.graphite;
}

function activityContext(activity, options = {}) {
  const showWindowTitles = options.showWindowTitles !== false;
  const showResourcePaths = options.showResourcePaths !== false;
  const title = String(activity?.windowTitle || "").trim();
  const resource = String(activity?.resource || "").trim();
  const app = String(activity?.appName || "").trim();
  if (showWindowTitles && title && title.toLowerCase() !== app.toLowerCase()) return title;
  if (showResourcePaths && resource) {
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
        categoryColor: category.color,
        categoryLabel: category.label,
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
        categoryColor: activity.categoryColor,
        categoryLabel: activity.categoryLabel,
        label: activity.kind === "idle" ? "Idle" : activity.label,
        detail: activity.kind === "idle" ? "No significant activity" : formatRange(activity.start, activity.end),
        kinds: new Set([activity.kind]),
        categorySeconds: new Map([[activity.kind, Math.max(1, activity.endSecond - activity.startSecond)]]),
        categoryColors: new Map([[activity.kind, activity.categoryColor]]),
        categoryLabels: new Map([[activity.kind, activity.categoryLabel]]),
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
    previous.categoryColors.set(activity.kind, activity.categoryColor);
    previous.categoryLabels.set(activity.kind, activity.categoryLabel);
    previous.kind = primaryKind(previous.categorySeconds);
    previous.categoryColor = previous.categoryColors.get(previous.kind) || previous.categoryColor;
    previous.categoryLabel = previous.categoryLabels.get(previous.kind) || previous.categoryLabel;
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
    categoryColor: block.categoryColor,
    categoryLabel: block.categoryLabel,
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

function tasksFromMarkdown(raw, previousTasks = []) {
  const pattern = /^\s*(?:[-*+]|[0-9]+[.)])\s+\[([ xX])\]\s+(?:(\d{1,2}:\d{2}\s*[–—-]\s*\d{1,2}:\d{2})\s+)?(.+)$/;
  const lines = String(raw || "").split("\n");
  let taskIndex = 0;
  return lines.flatMap((line) => {
    const match = line.match(pattern);
    if (!match) return [];
    const range = match[2]?.match(/^(\d{1,2}):(\d{2})\s*[–—-]\s*(\d{1,2}):(\d{2})$/);
    const start = range ? Number(range[1]) * 60 + Number(range[2]) : null;
    const end = range ? Number(range[3]) * 60 + Number(range[4]) : null;
    const body = match[3].trim();
    const tags = body.split(/\s+/).filter((item) => item.startsWith("#")).map((item) => item.slice(1)).filter(Boolean);
    const title = body.split(/\s+/).filter((item) => !item.startsWith("#")).join(" ") || "Untitled task";
    const previous = previousTasks[taskIndex];
    taskIndex += 1;
    return [{
      id: previous?.id || "markdown-task-" + Date.now() + "-" + taskIndex,
      title,
      tags,
      start: Number.isFinite(start) && Number.isFinite(end) && end > start ? start : null,
      end: Number.isFinite(start) && Number.isFinite(end) && end > start ? end : null,
      completed: match[1].toLowerCase() === "x",
      tone: title.toLowerCase().includes("genezip") ? "accent" : "soft",
    }];
  });
}

function ConnectionSettings({ open, apiBase, connected, api, onSave, onClose }) {
  const [draft, setDraft] = useState(apiBase);
  const [preferences, setPreferences] = useState({
    idle_threshold_seconds: 120,
    track_weekends: true,
    track_only_during_working_hours: false,
    working_hours_start_minute: 540,
    working_hours_end_minute: 1080,
    start_tracking_when_app_opens: true,
    auto_stop_timer_on_sleep: true,
    allow_local_network_api: false,
  });
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);
  const [transferBusy, setTransferBusy] = useState(false);
  const projectsFileRef = useRef(null);
  const entriesFileRef = useRef(null);

  useEffect(() => {
    if (open) {
      setDraft(apiBase);
      setPreferences((current) => ({ ...current, ...(api?.preferences || {}) }));
      setMessage("");
    }
  }, [apiBase, open]);

  if (!open) return null;

  const preferenceTime = (minutes) => `${String(Math.floor(Number(minutes || 0) / 60)).padStart(2, "0")}:${String(Number(minutes || 0) % 60).padStart(2, "0")}`;
  const updatePreference = (key, value) => setPreferences((current) => ({ ...current, [key]: value }));
  const exportArchive = async (kind) => {
    try {
      setTransferBusy(true);
      const archive = kind === "projects" ? await api.exportProjects() : await api.exportTimeEntries();
      downloadReport(`metriday-${kind}-${localDateKey()}.json`, JSON.stringify(archive, null, 2), "application/json;charset=utf-8");
      setMessage(`${kind === "projects" ? "Projects" : "Time entries"} exported.`);
    } catch (error) {
      setMessage(error.message || "Could not export local data.");
    } finally {
      setTransferBusy(false);
    }
  };
  const importArchive = async (event, kind) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    try {
      setTransferBusy(true);
      const archive = await file.text();
      const result = kind === "projects" ? await api.importProjects(archive) : await api.importTimeEntries(archive);
      const count = kind === "projects" ? `${result?.projectsImported || 0} projects` : `${result?.entriesImported || 0} time entries`;
      setMessage(`Imported ${count}.`);
    } catch (error) {
      setMessage(error.message || "Could not import local data.");
    } finally {
      setTransferBusy(false);
    }
  };
  const save = async (event) => {
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
      setSaving(true);
      if (connected && api?.updatePreferences) await api.updatePreferences(preferences);
      onSave(normalized);
      onClose();
    } catch {
      setMessage("无法保存设置，请确认原生应用仍在运行。");
    } finally {
      setSaving(false);
    }
  };

  const reset = () => {
    window.localStorage.removeItem(API_BASE_STORAGE_KEY);
    onSave(apiBaseURL());
    setDraft(apiBaseURL());
    setMessage("已恢复默认连接地址。");
  };

  return <div className="settings-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="settings-dialog" role="dialog" aria-modal="true" aria-labelledby="settings-title">
    <div className="settings-dialog-heading"><div><span>Preferences</span><h2 id="settings-title">Metriday Settings</h2></div><IconButton label="Close settings" onClick={onClose}><X size={18} /></IconButton></div>
    <p className="settings-description">Tracking, working hours, privacy, and the local Web companion connection are kept on this Mac.</p>
    <form className="settings-form" onSubmit={save}>
      <div className="settings-section"><div className="settings-section-heading"><strong>Tracking</strong><span className={`settings-state-dot ${connected ? "connected" : ""}`} />{connected ? api.status?.tracking ? "Running" : "Paused" : "Offline"}</div>
        <div className="settings-toggle-row"><label><input type="checkbox" checked={Boolean(api.status?.tracking)} onChange={() => api.toggleTracking()} disabled={!connected || saving} />Automatic activity tracking</label><small>{connected ? "Window, app, browser, and idle evidence" : "Connect the native app to change tracking"}</small></div>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.start_tracking_when_app_opens)} onChange={(event) => updatePreference("start_tracking_when_app_opens", event.target.checked)} disabled={!connected || saving} />Start tracking when Metriday opens</span></label>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.auto_stop_timer_on_sleep)} onChange={(event) => updatePreference("auto_stop_timer_on_sleep", event.target.checked)} disabled={!connected || saving} />Stop timers when the Mac sleeps</span></label>
        <label className="settings-field-row"><span>Idle detection</span><select value={preferences.idle_threshold_seconds} onChange={(event) => updatePreference("idle_threshold_seconds", Number(event.target.value))} disabled={!connected || saving}><option value={60}>1 min</option><option value={120}>2 min</option><option value={180}>3 min</option><option value={300}>5 min</option><option value={600}>10 min</option></select></label>
      </div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Working hours</strong></div>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.track_weekends)} onChange={(event) => updatePreference("track_weekends", event.target.checked)} disabled={!connected || saving} />Track on weekends</span></label>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.track_only_during_working_hours)} onChange={(event) => updatePreference("track_only_during_working_hours", event.target.checked)} disabled={!connected || saving} />Track only during working hours</span></label>
        <div className="settings-time-row"><label>From<input type="time" value={preferenceTime(preferences.working_hours_start_minute)} onChange={(event) => updatePreference("working_hours_start_minute", Math.max(0, Math.min(1439, Number(event.target.value.split(":")[0]) * 60 + Number(event.target.value.split(":")[1] || 0))))} disabled={!connected || saving} /></label><span>to</span><label>To<input type="time" value={preferenceTime(preferences.working_hours_end_minute)} onChange={(event) => updatePreference("working_hours_end_minute", Math.max(0, Math.min(1439, Number(event.target.value.split(":")[0]) * 60 + Number(event.target.value.split(":")[1] || 0))))} disabled={!connected || saving} /></label></div>
      </div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Privacy & connection</strong></div>
        <div className="settings-toggle-row"><label><input type="checkbox" checked={Boolean(preferences.allow_local_network_api)} onChange={(event) => updatePreference("allow_local_network_api", event.target.checked)} disabled={!connected || saving} />Allow local network access</label><small>Required for another device to use this Web companion</small></div>
        <label htmlFor="metriday-api-base">Native API base URL</label><div className="settings-input-wrap"><LinkSimple size={18} /><input id="metriday-api-base" value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="http://127.0.0.1:8765" /></div>
        <div className="settings-connection-state"><i className={connected ? "connected" : ""} /><span>{connected ? "Native API connected" : "Native API not connected"}</span><small>Local-first · no cloud upload</small></div>
      </div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Local data</strong></div><span className="settings-help-text">Projects and time entries remain in the native Application Support store. Archives merge locally; time-entry IDs are deduplicated on import.</span><div className="settings-data-actions"><button type="button" onClick={() => exportArchive("projects")} disabled={!connected || saving || transferBusy}>Export projects</button><button type="button" onClick={() => projectsFileRef.current?.click()} disabled={!connected || saving || transferBusy}>Import projects</button><button type="button" onClick={() => exportArchive("time entries")} disabled={!connected || saving || transferBusy}>Export time entries</button><button type="button" onClick={() => entriesFileRef.current?.click()} disabled={!connected || saving || transferBusy}>Import time entries</button><input ref={projectsFileRef} type="file" accept="application/json,.json" hidden onChange={(event) => importArchive(event, "projects")} /><input ref={entriesFileRef} type="file" accept="application/json,.json" hidden onChange={(event) => importArchive(event, "entries")} /></div></div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Sync & integrations</strong></div>
        <div className="settings-toggle-row"><span>{api.sync?.enabled ? "Local sync enabled" : "Local sync not configured"}</span><small>{api.sync?.status || "No sync status"}</small></div>
        <div className="settings-sync-actions"><button type="button" className="secondary-button" onClick={() => api.syncNow().then(() => setMessage("Sync completed.")).catch((error) => setMessage(error.message || "Sync failed."))} disabled={!connected || saving}>Sync now</button><button type="button" className="secondary-button" onClick={() => api.restoreSync().then(() => setMessage("Latest backup restored.")).catch((error) => setMessage(error.message || "Restore failed."))} disabled={!connected || saving || !api.sync?.backupCount}>Restore latest backup</button></div>
        <div className="settings-integration-list">{api.integrations?.map((integration) => <div className="settings-integration-row" key={integration.provider}><div><strong>{integration.title || integration.provider}</strong><small>{integration.connected ? integration.workspace || "Connected" : integration.status || "Not connected"}</small></div><button type="button" className="quiet-pill" onClick={() => api.syncIntegration(integration.provider).then(() => setMessage(`${integration.title || integration.provider} sync started.`)).catch((error) => setMessage(error.message || "Integration sync failed."))} disabled={!connected || saving || api.sync?.isWorking}>{integration.connected ? "Sync" : "Connect"}</button></div>)}</div>
      </div>
      <div className="settings-section settings-source-status"><div className="settings-section-heading"><strong>Data sources</strong></div><span><i className={api.calendarEvents?.authorized ? "connected" : ""} />Calendar · {api.calendarEvents?.status || "Not connected"}</span><span><i className={api.reminders?.authorized ? "connected" : ""} />Reminders · {api.reminders?.status || "Not connected"}</span><span><i className={api.screenTime?.database_available ? "connected" : ""} />Screen Time · {api.screenTime?.status || "Not connected"}</span></div>
      {message ? <p className="entry-message" role="status">{message}</p> : null}
      <div className="settings-actions"><button type="button" className="secondary-button" onClick={reset}>Use this Mac</button><button type="submit" className="primary-button" disabled={saving}>{saving ? "Saving…" : "Save settings"}</button></div>
    </form>
    <div className="settings-install-note"><Laptop size={18} /><div><strong>Install on phone</strong><span>在 Safari/Chrome 的分享或菜单中选择“添加到主屏幕”。切换到局域网访问后，其他设备可通过 Mac 地址连接。</span></div></div>
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

function WebGlobalHeader({ api, setPage, dateKey, setDateKey }) {
  const currentTask = api.status?.currentTask;
  const focusActive = Boolean(api.focusActive);
  const currentTitle = currentTask?.title || "No scheduled block";
  const currentRange = Number.isFinite(currentTask?.start_minute) && Number.isFinite(currentTask?.end_minute)
    ? formatRange(currentTask.start_minute, currentTask.end_minute)
    : "No scheduled time";
  const toggleFocus = async () => {
    if (!api.connected || !currentTask) return;
    try {
      await api.setFocusActive(!focusActive);
    } catch {
      // The page-level controls continue to reflect the native API on the next refresh.
    }
  };
  return <header className="web-global-header"><div className="web-global-date"><strong>{planDateLabel(dateKey)}</strong><div className="date-controls"><DatePickerControl dateKey={dateKey} onChange={setDateKey} label="Choose selected date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div></div><div className="web-global-context"><div className="web-global-current"><span>Current block</span><strong>{currentTitle}</strong><small>{currentRange} · {focusActive ? "In progress" : currentTask ? "Ready" : "Waiting"}</small></div><button type="button" className={`primary-button web-global-focus ${focusActive ? "active" : ""}`} onClick={toggleFocus} disabled={!api.connected || !currentTask}>{focusActive ? <Pause size={16} weight="fill" /> : <Play size={16} weight="fill" />}{focusActive ? "Pause focus" : "Resume focus"}</button><div className="web-global-rule"><ShieldCheck size={30} color="#399a55" weight="duotone" /><div><strong>Research Focus</strong><span>{focusActive ? "Blocklist active" : "Blocklist ready"}</span><button type="button" onClick={() => setPage("rules")}>Adjust allowed sites</button></div></div></div></header>;
}

function IconButton({ label, children, onClick, className = "", disabled = false }) {
  return <button type="button" className={`icon-button ${className}`} aria-label={label} title={label} onClick={onClick} disabled={disabled}>{children}</button>;
}

function DatePickerControl({ dateKey, onChange, label = "Choose date" }) {
  return <label className="date-picker-control" title={label}><CalendarBlank size={20} /><input type="date" value={dateKey} onChange={(event) => { if (event.target.value) onChange(event.target.value); }} aria-label={label} /></label>;
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

function TimerControls({ api }) {
  const [message, setMessage] = useState("");
  const timer = api.status?.timer;
  if (!timer) return null;
  const remaining = Number(timer.remainingSeconds);
  const setEstimate = async (event) => {
    const minutes = Number(event.target.value);
    if (!minutes) return;
    try {
      await api.setTimerEstimate(minutes);
      setMessage(`${minutes} min estimate saved`);
    } catch (error) {
      setMessage(error.message || "Could not set timer estimate.");
    }
  };
  const adjust = async (minutes) => {
    try {
      await api.adjustTimer(minutes);
      setMessage(`${minutes > 0 ? "+" : ""}${minutes} min adjustment saved`);
    } catch (error) {
      setMessage(error.message || "Could not adjust timer.");
    }
  };
  return <div className="timer-controls" aria-label="Running timer controls"><span>{Number.isFinite(remaining) ? `${formatDurationSeconds(remaining)} remaining` : "Timer running"}</span><select aria-label="Timer estimate" value={timer.estimatedDurationSeconds ? Math.round(Number(timer.estimatedDurationSeconds) / 60) : ""} onChange={setEstimate}><option value="">Set estimate</option><option value={15}>15 min</option><option value={25}>25 min</option><option value={30}>30 min</option><option value={45}>45 min</option><option value={60}>1 hour</option><option value={90}>90 min</option><option value={120}>2 hours</option></select><button type="button" onClick={() => adjust(-15)} aria-label="Move timer start 15 minutes earlier">−15m</button><button type="button" onClick={() => adjust(15)} aria-label="Move timer start 15 minutes later">+15m</button>{message ? <small role="status">{message}</small> : null}</div>;
}

function TodayHeader({ focusRunning, setFocusRunning, setPage, api, dateKey, setDateKey }) {
  const currentTask = api.status?.currentTask;
  const currentTitle = currentTask?.title || (api.connected ? "No scheduled block" : "GeneZip rebuttal experiment");
  const currentRange = Number.isFinite(currentTask?.start_minute) && Number.isFinite(currentTask?.end_minute)
    ? formatRange(currentTask.start_minute, currentTask.end_minute)
    : api.connected ? "No scheduled time" : "14:00–16:00";
  const currentApplication = api.status?.currentApplication && api.status.currentApplication !== "Waiting for activity" ? api.status.currentApplication : "Research Focus";
  const focusActionLabel = focusRunning ? "Pause focus" : api.connected && !currentTask ? "Start timer" : "Resume focus";
  return (
    <header className="today-header">
      <div className="date-heading">
        <h1>{planDateLabel(dateKey)}</h1>
        <div className="date-controls"><DatePickerControl dateKey={dateKey} onChange={setDateKey} label="Choose Today date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div>
      </div>
      <div className="current-session">
        <div className="session-copy"><span>Current block</span><strong>{currentTitle}</strong><p>{currentRange} <b>·</b> <em>{focusRunning ? "In progress" : currentTask || !api.connected ? "Paused" : "Waiting"}</em></p></div>
        <div className="session-actions"><button type="button" className="primary-button" onClick={async () => { if (api.connected) { if (focusRunning) await api.stopTimer(); else await api.startTimer(currentTask?.title || "Focused work"); } else setFocusRunning((value) => !value); }}>{focusRunning ? <Pause size={18} weight="fill" /> : <Play size={18} weight="fill" />}{focusActionLabel}</button><TimerControls api={api} /></div>
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

function PlannedTrack({ tasks, connected, onSelect }) {
 const blocks = planTimelineBlocks(tasks, connected);
 return (
   <section className="today-track planned-track" aria-label="Planned timeline">
     <div className="track-heading"><strong>Plan</strong><span>What I planned</span></div>
     <div className="track-canvas"><GridLines />{blocks.map(({ id, title, start, end, icon: Icon, current }) => (
        <button key={id} type="button" className={`planned-block ${current ? "current" : ""}`} style={blockStyle(start, end)} onClick={() => onSelect?.(id)} aria-label={`Open planned task ${title}`}><Icon size={18} weight="duotone" /><span><strong>{title}</strong><small>{formatRange(start, end)}</small></span></button>
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
  const categoryLabel = block.categoryLabel || (block.kind === "focused" ? "Focused" : block.kind === "distracting" ? "Distracting" : block.kind === "idle" ? "Idle" : "Other");
  const categoryStyle = activityCategoryStyle({ color: block.categoryColor || categoryRoleColor(block.kind) });
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
    <div className="actual-hover-meta"><span>Category:</span><i className={`hover-category-dot ${block.kind}`} style={{ background: categoryStyle.color }} /><b>{categoryLabel}</b></div>
    <div className="actual-hover-meta"><span>Project:</span><i className="hover-project-dot" /><b>None</b><small>From the app usage</small></div>
    {onRecord ? <div className="actual-hover-actions"><button type="button" className="actual-record-button" onClick={record} disabled={busy}>{message || (busy ? "Recording…" : "Record time")}</button></div> : null}
  </div>;
}

function ActualTrack({ activities, connected, onRecord, onSelect }) {
 const [hoveredBlockId, setHoveredBlockId] = useState(null);
 const blocks = connected && activities.length > 0 ? liveActivityBlocks(activities) : actualBlocks;
  const selectActivity = (block) => activities.find((activity) => String(activity.id) === String(block.id)) || null;
 return (
   <section className="today-track actual-track" aria-label="Actual activity timeline">
     <div className="track-heading"><strong>Actual</strong><span>{connected ? "Live from Metriday" : "What actually happened"}</span></div>
      <div className="track-canvas"><GridLines />{blocks.map((block) => { const activity = selectActivity(block); return <div key={block.id} className={`actual-block ${block.kind} ${hoveredBlockId === block.id ? "hovered" : ""}`} style={{ ...actualBlockStyle(block), ...activityBlockStyle(block.categoryColor || categoryRoleColor(block.kind)) }} title={`${block.label} · ${block.detail}`} role={activity ? "button" : undefined} tabIndex={activity ? 0 : undefined} onMouseEnter={() => setHoveredBlockId(block.id)} onMouseLeave={() => setHoveredBlockId(null)} onClick={(event) => { if (event.target.closest("button")) return; if (activity) onSelect?.(activity); }} onKeyDown={(event) => { if (activity && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); onSelect?.(activity); } }}><ActualRows block={block} />{hoveredBlockId === block.id ? <ActualHoverCard block={block} onRecord={connected ? onRecord : null} /> : null}</div>; })}</div>
   </section>
 );
}

function TodayPage({ setPage, api, dateKey, setDateKey }) {
  const [selectedActivity, setSelectedActivity] = useState(null);
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
      <div className="today-comparison"><div className="timeline-label-column"><HourLabels /></div><PlannedTrack tasks={api.plan?.tasks} connected={api.connected} onSelect={() => setPage("plan")} /><ActualTrack activities={api.activities} connected={api.connected} onRecord={recordActivity} onSelect={setSelectedActivity} /><div className="now-marker" style={nowStyle} aria-label={`Current time ${now.label}`}><span /></div></div>
      <TodayInsightBar api={api} setPage={setPage} />
      {api.connected ? <WebActivityInsights insights={api.insights} dateKey={dateKey} /> : null}{selectedActivity ? <ActivityDetailDialog activity={selectedActivity} api={api} dateKey={dateKey} displayPreferences={api.activityPreferences} onClose={() => setSelectedActivity(null)} /> : null}
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

function MarkdownEditor({ tasks, markdown, planDate, onMarkdownChange, onMarkdownCommit, onTaskDragStart, onPointerDragStart, onSelectTask, onComplete }) {
  const [scrollTop, setScrollTop] = useState(0);
  const lines = String(markdown || "").split("\n");
  const taskLineIndices = lines.map((line, index) => ({ line, index })).filter(({ line }) => /^\s*(?:[-*+]|[0-9]+[.)])\s+\[[ xX]\]\s+/.test(line));
  const copyMarkdown = () => navigator.clipboard?.writeText(String(markdown || "")).catch(() => {});
  return (
    <section className="markdown-editor" aria-label="Markdown daily plan">
      <div className="editor-toolbar"><div className="file-name"><FileText size={18} /> {planDate}.md <span>{markdown ? "Markdown document" : "Blank Markdown document"}</span></div><div className="editor-actions"><span>Markdown</span><ActionMenu label="Document actions" items={[{ label: "Copy Markdown", onSelect: copyMarkdown }]}><DotsThree size={22} /></ActionMenu></div></div>
      <div className="editor-body markdown-source-wrap">
        <textarea className="markdown-source-editor" aria-label="Markdown editor" value={markdown || ""} spellCheck={false} onChange={(event) => onMarkdownChange(event.target.value)} onBlur={(event) => onMarkdownCommit(event.currentTarget.value)} onScroll={(event) => setScrollTop(event.currentTarget.scrollTop)} />
        <div className="markdown-source-overlays" style={{ transform: "translateY(" + (-scrollTop) + "px)" }} aria-hidden="false">
          {lines.map((_, index) => <span className="markdown-source-line-number" key={index}>{index + 1}</span>)}
          {taskLineIndices.map(({ index }, taskIndex) => { const task = tasks[taskIndex]; if (!task) return null; return <div className="markdown-source-task-actions" style={{ top: (index * 46) + 18 }} key={task.id}><button type="button" className="drag-handle" draggable onDragStart={(event) => onTaskDragStart(event, task.id)} onPointerDown={(event) => onPointerDragStart(event, task.id)} onClick={() => onSelectTask(task.id)} aria-label={`Drag ${task.title} to calendar`}><DotsSixVertical size={16} /></button><button type="button" className="markdown-check" onClick={() => onComplete(task.id)} aria-label={`Mark ${task.title} ${task.completed ? "incomplete" : "complete"}`}>{task.completed ? <Check size={13} weight="bold" /> : null}</button></div>; })}
        </div>
      </div>
      <footer className="editor-footer"><span>{lines.length} lines</span><span>UTF-8</span><span>Local file</span><CheckCircle size={18} weight="fill" /></footer>
    </section>
  );
}

function CalendarBlock({ task, selected, onSelect, onMoveStart, onComplete, onUnschedule, onResizeStart }) {
  return (
    <div className={`calendar-task-block ${task.tone} ${selected ? "selected" : ""} ${task.completed ? "completed" : ""}`} style={blockStyle(task.start, task.end)} role="button" aria-label={`${task.title}, ${formatRange(task.start, task.end)}`} aria-pressed={selected} onClick={(event) => { event.stopPropagation(); onSelect(task.id); }} tabIndex={0} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onSelect(task.id); } else if (event.key === "Delete" || event.key === "Backspace") onUnschedule(task.id); }}>
      <div className="block-content" onPointerDown={(event) => onMoveStart(event, task.id)}><strong>{task.title}</strong><span>{formatRange(task.start, task.end)}</span></div>
      {selected ? <div className="block-actions"><IconButton label={task.completed ? "Mark incomplete" : "Mark complete"} onClick={() => onComplete(task.id)}>{task.completed ? <ArrowsClockwise size={15} /> : <Check size={15} />}</IconButton><IconButton label="Remove time" onClick={() => onUnschedule(task.id)}><Trash size={15} /></IconButton></div> : null}
      <button type="button" className="resize-start-handle" aria-label={`Resize start of ${task.title}`} onPointerDown={(event) => onResizeStart(event, task.id, "start")} /><button type="button" className="resize-handle" aria-label={`Resize end of ${task.title}`} onPointerDown={(event) => onResizeStart(event, task.id, "end")} />
    </div>
  );
}

function CalendarPanel({ tasks, neighborPlans, selectedTaskId, setSelectedTaskId, onDropTask, onMoveStart, onComplete, onUnschedule, onResizeStart, dateKey, onSelectDate, connected = false }) {
  const timelineRef = useRef(null);
  const [visibleMonth, setVisibleMonth] = useState(() => new Date(`${dateKey}T12:00:00`));
  useEffect(() => {
    const selectedMonth = new Date(`${dateKey}T12:00:00`);
    if (!Number.isNaN(selectedMonth.getTime()) && (selectedMonth.getMonth() !== visibleMonth.getMonth() || selectedMonth.getFullYear() !== visibleMonth.getFullYear())) {
      setVisibleMonth(selectedMonth);
    }
  }, [dateKey]);
  const drop = (event) => { event.preventDefault(); const id = event.dataTransfer.getData("text/task-id") || selectedTaskId; if (!id || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(id, event.clientY - rect.top, { metaKey: event.metaKey, altKey: event.altKey }); };
  const calendarItems = [
    { label: "Today", onSelect: () => onSelectDate(localDateKey()) },
    { label: "Previous day", onSelect: () => onSelectDate(offsetDateKey(dateKey, -1)) },
    { label: "Next day", onSelect: () => onSelectDate(offsetDateKey(dateKey, 1)) }
  ];
  const firstOfMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1, 12);
  const leadingDays = (firstOfMonth.getDay() + 6) % 7;
  const daysInMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + 1, 0, 12).getDate();
  const cellCount = Math.ceil((leadingDays + daysInMonth) / 7) * 7;
  const monthDays = Array.from({ length: cellCount }, (_, index) => localDateKey(new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), index - leadingDays + 1, 12)));
  const monthTitle = visibleMonth.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  const selectedDateLabel = new Date(`${dateKey}T12:00:00`).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
  const timelineDays = [-1, 0, 1].map((offset) => offsetDateKey(dateKey, offset));
  return (
    <section className="calendar-panel" aria-label="Calendar and continuous timeline">
      <div className="calendar-toolbar"><div className="month-navigation"><IconButton label="Previous month" onClick={() => setVisibleMonth((value) => new Date(value.getFullYear(), value.getMonth() - 1, 1, 12))}><CaretLeft size={16} /></IconButton><strong>{monthTitle}</strong><IconButton label="Next month" onClick={() => setVisibleMonth((value) => new Date(value.getFullYear(), value.getMonth() + 1, 1, 12))}><CaretRight size={16} /></IconButton></div><ActionMenu label="Calendar options" items={calendarItems}><DotsThree size={21} /></ActionMenu></div>
      <div className="month-calendar" aria-label={`${monthTitle} calendar`}><div className="month-weekdays" aria-hidden="true">{["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => <span key={day}>{day}</span>)}</div><div className="month-grid">{monthDays.map((day) => { const date = new Date(`${day}T12:00:00`); const isCurrentMonth = date.getMonth() === visibleMonth.getMonth(); const isSelected = day === dateKey; const isToday = day === localDateKey(); const taskCount = isSelected ? tasks.filter((task) => task.start != null).length : 0; return <button type="button" key={day} className={`month-day ${isCurrentMonth ? "" : "outside"} ${isSelected ? "selected" : ""} ${isToday ? "today" : ""}`} onClick={() => onSelectDate(day)} aria-label={`${date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" })}${taskCount ? `, ${taskCount} scheduled blocks` : ""}`}><span>{date.getDate()}</span>{taskCount ? <small>{taskCount}</small> : null}</button>; })}</div></div>
      <h2>{selectedDateLabel}</h2><div className="all-day-row"><span>all-day</span></div>
      <div className="continuous-timeline" aria-label="Three-day continuous timeline"><div className="continuous-timeline-head"><div /><div className="continuous-day-labels">{timelineDays.map((day) => { const date = new Date(`${day}T12:00:00`); return <button type="button" key={day} className={day === dateKey ? "selected" : ""} onClick={() => onSelectDate(day)}><span>{date.toLocaleDateString(undefined, { weekday: "short" })}</span><strong>{date.getDate()}</strong></button>; })}</div></div><div className="continuous-timeline-body"><div className="continuous-hour-axis"><HourLabels end={20} /></div>{timelineDays.map((day) => { const isSelected = day === dateKey; const dayTasks = isSelected ? tasks : (neighborPlans?.[day] || []); if (isSelected) return <div ref={timelineRef} key={day} className={`plan-calendar-canvas continuous-day-canvas ${selectedTaskId ? "ready-to-schedule" : ""}`} onDragOver={(event) => event.preventDefault()} onDrop={drop} onClick={(event) => { if (!selectedTaskId || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(selectedTaskId, event.clientY - rect.top, { metaKey: event.metaKey, altKey: event.altKey }); }}><GridLines end={20} />{!connected ? <><div className="static-calendar-block morning" style={blockStyle(8 * 60, 9 * 60)}><strong>Morning routine</strong><span>08:00–09:00</span></div><div className="static-calendar-block team" style={blockStyle(9 * 60 + 30, 10 * 60 + 15)}><strong>Team sync</strong><span>09:30–10:15</span></div><div className="static-calendar-block lunch" style={blockStyle(12 * 60, 13 * 60)}><strong>Lunch</strong><span>12:00–13:00</span></div></> : null}{dayTasks.filter((task) => task.start != null).map((task) => <CalendarBlock key={task.id} task={task} selected={selectedTaskId === task.id} onSelect={setSelectedTaskId} onMoveStart={onMoveStart} onComplete={onComplete} onUnschedule={onUnschedule} onResizeStart={onResizeStart} />)}</div>; return <div key={day} className="continuous-day-canvas adjacent" onClick={() => onSelectDate(day)}><GridLines end={20} />{dayTasks.filter((task) => task.start != null).map((task) => <div key={task.id} className={`continuous-neighbor-block ${task.tone}`} style={blockStyle(task.start, task.end)}><strong>{task.title}</strong><span>{formatRange(task.start, task.end)}</span></div>)}</div>; })}</div></div>
      <div className="calendar-drop-hint"><LinkSimple size={19} /><span>{selectedTaskId ? "Click a time or drag here to schedule" : "Drag a Markdown task here to schedule it"}</span></div>
    </section>
  );
}

function PlanPage({ tasks, setTasks, api, dateKey, setDateKey }) {
  const [selectedTaskId, setSelectedTaskId] = useState(null);
  const [lastUpdatedId, setLastUpdatedId] = useState(null);
  const [toast, setToast] = useState("");
  const [markdown, setMarkdown] = useState(() => markdownWithTasks("", tasks));
  const markdownRef = useRef(markdown);
  const [neighborPlans, setNeighborPlans] = useState({});
  const [pendingSchedule, setPendingSchedule] = useState(null);
  const planDate = dateKey;
  useEffect(() => {
    if (!api.connected || !api.plan?.tasks) return;
    const loadedMarkdown = String(api.plan.markdown || "");
    markdownRef.current = loadedMarkdown;
    setMarkdown(loadedMarkdown);
    setTasks(api.plan.tasks.map(planTaskFromAPI));
    setSelectedTaskId(null);
  }, [api.connected, api.plan?.date, api.plan?.markdown, setTasks]);
  useEffect(() => {
    if (!api.connected || typeof api.fetchPlan !== "function") {
      setNeighborPlans({});
      return undefined;
    }
    let cancelled = false;
    const dates = [offsetDateKey(dateKey, -1), offsetDateKey(dateKey, 1)];
    Promise.all(dates.map(async (day) => {
      try {
        const plan = await api.fetchPlan(day);
        return [day, Array.isArray(plan?.tasks) ? plan.tasks.map(planTaskFromAPI) : []];
      } catch {
        return [day, []];
      }
    })).then((items) => {
      if (!cancelled) setNeighborPlans(Object.fromEntries(items));
    });
    return () => { cancelled = true; };
  }, [api.connected, api.fetchPlan, dateKey]);
  const persistTasks = (nextTasks, message) => {
    const nextMarkdown = markdownWithTasks(markdownRef.current || api.plan?.markdown || "", nextTasks);
    markdownRef.current = nextMarkdown;
    setMarkdown(nextMarkdown);
    setTasks(nextTasks);
    setToast(message);
    if (!api.connected || !api.plan?.markdown || api.plan.date !== dateKey) return;
    api.savePlan(nextMarkdown)
      .then(() => setToast("Markdown synced to Metriday"))
      .catch(() => setToast("Local change kept; sync failed"));
  };
  const updateMarkdown = (nextMarkdown) => {
    markdownRef.current = nextMarkdown;
    setMarkdown(nextMarkdown);
    setTasks(tasksFromMarkdown(nextMarkdown, tasks));
  };
  const commitMarkdown = (nextMarkdown) => {
    const source = markdownRef.current === nextMarkdown ? nextMarkdown : markdownRef.current;
    markdownRef.current = source;
    const parsedTasks = tasksFromMarkdown(source, tasks);
    setMarkdown(source);
    setTasks(parsedTasks);
    setToast("Markdown saved");
    if (!api.connected || api.plan?.date !== dateKey) return;
    api.savePlan(source)
      .then(() => setToast("Markdown synced to Metriday"))
      .catch(() => setToast("Local change kept; sync failed"));
  };
  const scheduleTask = (id, start, end) => { const nextTasks = tasks.map((task) => task.id === id ? { ...task, start, end } : task); persistTasks(nextTasks, "Markdown updated · " + formatRange(start, end) + " added"); setLastUpdatedId(id); setSelectedTaskId(id); };
  const dropTask = (id, offsetY, modifiers = {}) => { const raw = DAY_START + (offsetY / HOUR_HEIGHT) * 60; const start = Math.max(DAY_START, Math.min(DAY_END - 30, Math.round(raw / 15) * 15)); const task = tasks.find((item) => item.id === id); if (!task) return; const end = Math.min(start + (task.start != null ? Math.max(task.end - task.start, 30) : 60), DAY_END); if (modifiers.altKey) { setToast("Event drop reserved for a later calendar integration"); return; } if (modifiers.metaKey) { scheduleTask(id, start, end); return; } setPendingSchedule({ id, start, end, title: task.title }); };
  const confirmSchedule = (kind) => { if (!pendingSchedule) return; if (kind === "time-block") scheduleTask(pendingSchedule.id, pendingSchedule.start, pendingSchedule.end); else setToast("Event scheduling is reserved for a later calendar integration"); setPendingSchedule(null); };
  const taskDragStart = (event, id) => { event.dataTransfer.effectAllowed = "move"; event.dataTransfer.setData("text/task-id", id); setSelectedTaskId(id); };
  const pointerMoveStart = (event, id) => {
    event.preventDefault();
    setSelectedTaskId(id);
    const startX = event.clientX;
    const startY = event.clientY;
    let didMove = false;
    const move = (moveEvent) => {
      if (Math.hypot(moveEvent.clientX - startX, moveEvent.clientY - startY) > 5) didMove = true;
    };
    const up = (upEvent) => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      if (!didMove) return;
      const calendar = document.querySelector(".plan-calendar-canvas");
      if (!calendar) return;
      const rect = calendar.getBoundingClientRect();
      if (upEvent.clientX >= rect.left && upEvent.clientX <= rect.right && upEvent.clientY >= rect.top && upEvent.clientY <= rect.bottom) dropTask(id, upEvent.clientY - rect.top + calendar.scrollTop, { metaKey: upEvent.metaKey, altKey: upEvent.altKey });
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  const completeTask = (id) => { const nextTasks = tasks.map((task) => task.id === id ? { ...task, completed: !task.completed } : task); persistTasks(nextTasks, "Markdown task state updated"); };
  const titleCommit = () => persistTasks(tasks, "Markdown saved");
  const unscheduleTask = (id) => { const nextTasks = tasks.map((task) => task.id === id ? { ...task, start: null, end: null } : task); persistTasks(nextTasks, "Markdown updated · time removed, task preserved"); setLastUpdatedId(id); setSelectedTaskId(null); };
  const resizeStart = (event, id, edge = "end") => {
    event.preventDefault(); event.stopPropagation(); const task = tasks.find((item) => item.id === id); if (!task || task.start == null || task.end == null) return; const startY = event.clientY; const initialValue = edge === "start" ? task.start : task.end;
    let finalValue = initialValue;
    const move = (moveEvent) => { const delta = Math.round(((moveEvent.clientY - startY) / HOUR_HEIGHT) * 4) * 15; finalValue = edge === "start" ? Math.max(DAY_START, Math.min(task.end - 30, task.start + delta)) : Math.max(task.start + 30, Math.min(DAY_END, task.end + delta)); setTasks((items) => items.map((item) => item.id === id ? { ...item, ...(edge === "start" ? { start: finalValue } : { end: finalValue }) } : item)); };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); const nextTasks = tasks.map((item) => item.id === id ? { ...item, ...(edge === "start" ? { start: finalValue } : { end: finalValue }) } : item); persistTasks(nextTasks, `Markdown updated · calendar ${edge === "start" ? "start" : "duration"} changed`); setLastUpdatedId(id); };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };
  const addTask = (title) => { const nextTasks = [...tasks, { id: "task-" + Date.now(), title, tags: [], start: null, end: null, completed: false, tone: "soft" }]; persistTasks(nextTasks, "Markdown task added"); };
  return (
    <main className="page plan-page"><header className="plan-header"><h1>Plan <span>·</span> {planDateLabel(planDate)}</h1><div className="date-controls"><DatePickerControl dateKey={planDate} onChange={setDateKey} label="Choose Plan date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div></header>
      <div className="plan-workspace"><MarkdownEditor tasks={tasks} markdown={markdown} planDate={planDate} onMarkdownChange={updateMarkdown} onMarkdownCommit={commitMarkdown} onTaskDragStart={taskDragStart} onPointerDragStart={pointerMoveStart} onSelectTask={setSelectedTaskId} onComplete={completeTask} /><CalendarPanel tasks={tasks} neighborPlans={neighborPlans} selectedTaskId={selectedTaskId} setSelectedTaskId={setSelectedTaskId} onDropTask={dropTask} onMoveStart={pointerMoveStart} onComplete={completeTask} onUnschedule={unscheduleTask} onResizeStart={resizeStart} dateKey={planDate} onSelectDate={setDateKey} connected={api.connected} /></div>
      {pendingSchedule ? <div className="schedule-choice-backdrop" role="presentation" onClick={() => setPendingSchedule(null)}><section className="schedule-choice-dialog" role="dialog" aria-modal="true" aria-labelledby="schedule-choice-title" onClick={(event) => event.stopPropagation()}><div><span>Schedule task</span><h2 id="schedule-choice-title">{pendingSchedule.title}</h2><p>{formatRange(pendingSchedule.start, pendingSchedule.end)} · Choose how this drop should be recorded.</p></div><div className="schedule-choice-actions"><button type="button" className="secondary-button" onClick={() => confirmSchedule("event")} disabled>Event <small>Later</small></button><button type="button" className="primary-button" onClick={() => confirmSchedule("time-block")}>Time Block</button></div><button type="button" className="schedule-choice-cancel" onClick={() => setPendingSchedule(null)}>Cancel</button></section></div> : null}
      {toast ? <div className="toast" role="status"><CheckCircle size={20} weight="fill" /><span>{toast}</span><IconButton label="Dismiss" onClick={() => setToast("")}><X size={15} /></IconButton></div> : null}
    </main>
  );
}

function formatDurationSeconds(seconds) {
  const minutes = Math.max(0, Math.round(Number(seconds || 0) / 60));
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function entrySecondsForDate(entry, dateKey) {
  const dayStart = new Date(`${dateKey}T00:00:00`);
  const startValue = entry?.start_date || entry?.start;
  const endValue = entry?.end_date || entry?.end;
  const startDate = new Date(startValue || "");
  const endDate = new Date(endValue || "");
  if (Number.isNaN(dayStart.getTime()) || Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) return null;
  const startSecond = Math.max(0, Math.min(24 * 60 * 60, Math.floor((startDate.getTime() - dayStart.getTime()) / 1000)));
  const endSecond = Math.max(0, Math.min(24 * 60 * 60, Math.ceil((endDate.getTime() - dayStart.getTime()) / 1000)));
  return endSecond > startSecond ? { startSecond, endSecond } : null;
}

function entryOMaticIntervals(activities, entries, dateKey, options = {}) {
  const minimumDurationSeconds = Math.max(1, Number(options.minimumDurationMinutes || 5) * 60);
  const maximumGapSeconds = Math.max(0, Number(options.maximumGapSeconds || 0));
  const sorted = activities
    .filter((activity) => activityCategory(activity).key !== "idle" && Number(activity.endSecond || 0) > Number(activity.startSecond || 0))
    .map((activity) => ({
      startSecond: Math.max(0, Math.min(24 * 60 * 60, Number(activity.startSecond || 0))),
      endSecond: Math.max(0, Math.min(24 * 60 * 60, Number(activity.endSecond || 0))),
    }))
    .filter((interval) => interval.endSecond > interval.startSecond)
    .sort((left, right) => left.startSecond - right.startSecond || left.endSecond - right.endSecond);
  const merged = [];
  sorted.forEach((interval) => {
    const last = merged[merged.length - 1];
    if (!last || interval.startSecond > last.endSecond + maximumGapSeconds) merged.push({ ...interval });
    else last.endSecond = Math.max(last.endSecond, interval.endSecond);
  });
  const longEnough = merged.filter((interval) => interval.endSecond - interval.startSecond >= minimumDurationSeconds);
  if (options.overwriteExisting || longEnough.length === 0) return longEnough;
  const covered = entries.map((entry) => entrySecondsForDate(entry, dateKey)).filter(Boolean);
  if (covered.length === 0) return longEnough;
  const remaining = [];
  longEnough.forEach((interval) => {
    let pieces = [interval];
    covered.forEach((blocker) => {
      const next = [];
      pieces.forEach((candidate) => {
        if (blocker.endSecond <= candidate.startSecond || blocker.startSecond >= candidate.endSecond) {
          next.push(candidate);
          return;
        }
        if (candidate.startSecond < blocker.startSecond) next.push({ startSecond: candidate.startSecond, endSecond: Math.min(candidate.endSecond, blocker.startSecond) });
        if (blocker.endSecond < candidate.endSecond) next.push({ startSecond: Math.max(candidate.startSecond, blocker.endSecond), endSecond: candidate.endSecond });
      });
      pieces = next.filter((piece) => piece.endSecond > piece.startSecond);
    });
    remaining.push(...pieces);
  });
  return remaining.filter((interval) => interval.endSecond - interval.startSecond >= minimumDurationSeconds).sort((left, right) => left.startSecond - right.startSecond);
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

function ProjectPanel({ api, onAssignActivity }) {
  const [title, setTitle] = useState("");
  const [rate, setRate] = useState("0");
  const [currency, setCurrency] = useState("USD");
  const [billingStatus, setBillingStatus] = useState("billable");
  const [editing, setEditing] = useState(null);
  const [message, setMessage] = useState("");
  const [dropTarget, setDropTarget] = useState(null);
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
  const dropOnProject = async (event, project) => {
    event.preventDefault();
    setDropTarget(null);
    const activityID = event.dataTransfer.getData("application/x-metriday-activity");
    const activityDate = event.dataTransfer.getData("application/x-metriday-activity-date");
    if (!activityID || !onAssignActivity) return;
    try {
      await onAssignActivity(activityID, project.id, activityDate || undefined);
      setMessage(`Activity assigned to ${project.title}.`);
    } catch (error) {
      setMessage(error.message || "Could not assign the activity.");
    }
  };
  return <section className="projects-panel"><div className="activities-list-heading"><div><h2>Projects & clients</h2><p>Drag an App / Category row here to assign its activity to a project.</p></div><span className="api-badge online">{projects.length} active</span></div><form className="project-create-form" onSubmit={create}><input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Project or client name" aria-label="Project name" /><input type="number" min="0" step="0.01" value={rate} onChange={(event) => setRate(event.target.value)} placeholder="Rate" aria-label="Project billing rate" /><input value={currency} onChange={(event) => setCurrency(event.target.value)} maxLength={3} aria-label="Project currency" /><select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Project default billing status"><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option></select><button type="submit" disabled={!api.connected}><Plus size={17} />Add project</button></form>{message ? <p className="entry-message" role="status">{message}</p> : null}{projects.length > 0 ? <div className="project-table">{projects.map((project) => editing?.id === project.id ? <form className="project-row project-edit-row" key={project.id} onSubmit={saveEdit}><input value={editing.title} onChange={(event) => setEditing((value) => ({ ...value, title: event.target.value }))} aria-label={`Edit ${project.title} name`} /><input type="number" min="0" step="0.01" value={editing.rate} onChange={(event) => setEditing((value) => ({ ...value, rate: event.target.value }))} aria-label={`Edit ${project.title} rate`} /><input value={editing.currency} onChange={(event) => setEditing((value) => ({ ...value, currency: event.target.value }))} maxLength={3} aria-label={`Edit ${project.title} currency`} /><select value={editing.billingStatus} onChange={(event) => setEditing((value) => ({ ...value, billingStatus: event.target.value }))} aria-label={`Edit ${project.title} billing status`}><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option></select><span className="project-actions"><button type="submit" aria-label="Save project"><Check size={16} /></button><IconButton label="Cancel project edit" onClick={() => setEditing(null)}><X size={15} /></IconButton></span></form> : <div className={`project-row ${dropTarget === project.id ? "drop-target" : ""}`} key={project.id} onDragOver={(event) => { event.preventDefault(); setDropTarget(project.id); }} onDragLeave={() => setDropTarget(null)} onDrop={(event) => dropOnProject(event, project)}><span className="project-dot" /><strong>{project.title}</strong><span>{project.currency || "USD"} {Number(project.billing_rate || 0).toFixed(2)}/h</span><small>{billingLabel(project.default_billing_status)}</small><span className="project-actions"><IconButton label={`Edit ${project.title}`} onClick={() => beginEdit(project)}><NotePencil size={15} /></IconButton><IconButton label={`Archive ${project.title}`} onClick={() => remove(project)}><Trash size={15} /></IconButton></span></div>)}</div> : <div className="entries-empty"><FolderSimple size={24} /><span>{api.connected ? "Create a project to organize time and billing." : "Connect the native app to manage projects."}</span></div>}</section>;
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

function ReviewPage({ api, dateKey, setDateKey }) {
  const fallbackDays = [{ label: "Mon", planned: 7.2, actual: 6.6 }, { label: "Tue", planned: 6.5, actual: 7.1 }, { label: "Wed", planned: 7.8, actual: 6.9 }, { label: "Thu", planned: 6.2, actual: 5.8 }, { label: "Fri", planned: 7.1, actual: 6.5 }, { label: "Sat", planned: 5.5, actual: 4.8 }];
  const days = api.weekly.length >= 6 ? api.weekly.slice(-6).map((day) => {
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
  const categoryRows = api.connected ? [...api.activities.reduce((groups, activity) => {
    const category = activityCategory(activity);
    const seconds = Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
    if (seconds <= 0 || category.key === "idle") return groups;
    const key = `${category.key}:${category.label}`;
    const current = groups.get(key) || { ...category, seconds: 0 };
    current.seconds += seconds;
    groups.set(key, current);
    return groups;
  }, new Map()).values()] : [
    { key: "focused", label: "Focused", color: "blue", seconds: 22 * 3600 },
    { key: "distracting", label: "Distracting", color: "red", seconds: 3 * 3600 },
    { key: "other", label: "Other", color: "graphite", seconds: 1 * 3600 },
  ];
  const categoryTotal = categoryRows.reduce((total, category) => total + category.seconds, 0);
  return <main className="page supporting-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? `Live · ${planDateLabel(dateKey)}` : "This week"}</span><h1>Review with evidence</h1></div><div className="activities-page-actions"><div className="date-controls"><DatePickerControl dateKey={dateKey} onChange={setDateKey} label="Choose Review date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : api.connected ? "Refresh" : "Preview"}</button></div></header><section className="review-summary"><div><Timer size={26} /><span>Deep work</span><strong>{deepWork}</strong><small>{api.connected ? `${taskRelated}% task-related today` : "+2h 06m from last week"}</small></div><div><TrendUp size={26} /><span>Task relevance</span><strong>{api.connected ? `${taskRelated}%` : "86%"}</strong><small>{api.connected ? `${formatDurationSeconds(totalActive)} active usage` : "Best on research blocks"}</small></div><div><ShieldCheck size={26} /><span>Distraction</span><strong>{distraction}</strong><small>{api.connected ? "Detected locally" : "6 distractions blocked"}</small></div></section><section className="review-evidence-grid"><section className="weekly-chart"><div className="chart-heading"><div><h2>Planned vs. actual</h2><p>{api.connected ? "Six-day evidence from the native activity and Markdown plan stores." : "Longer actual bars reveal underestimated work."}</p></div><div className="legend"><span><i className="planned" />Planned</span><span><i className="actual" />Actual</span></div></div><div className="bar-chart">{days.map((day) => <div key={day.label} className="bar-day"><div className="bar-pair"><i className="planned" style={{ height: `${Math.max(4, Math.min(9, day.planned) * 20)}px` }} /><i className="actual" style={{ height: `${Math.max(4, Math.min(9, day.actual) * 20)}px` }} /></div><span>{day.label}</span></div>)}</div></section><section className="review-category-panel"><div className="chart-heading"><div><h2>Category pulse</h2><p>App and website time grouped by the same Focused / Distracting rules used in Activities.</p></div><span className="api-badge online">{formatDurationSeconds(categoryTotal)} active</span></div><div className="review-category-list">{categoryRows.map((category) => { const share = categoryTotal > 0 ? Math.round((category.seconds / categoryTotal) * 100) : 0; const color = activityCategoryStyle(category).color; return <div className="review-category-row" key={`${category.key}:${category.label}`}><div className="review-category-heading"><span className={`activity-category ${category.key}`} style={activityCategoryStyle(category)}><i />{category.label}</span><strong>{share}%</strong><small>{formatDurationSeconds(category.seconds)}</small></div><div className="review-category-track"><i style={{ width: `${Math.max(2, share)}%`, background: color }} /></div></div>; })}</div></section></section>{api.connected ? <WebActivityInsights insights={api.insights} dateKey={dateKey} /> : null}</main>;
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
  const [reportPreset, setReportPreset] = useState("timesheet");
  const [includeMode, setIncludeMode] = useState("both");
  const [groupBy, setGroupBy] = useState("exact");
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
  const reportPresets = [
    { key: "timesheet", label: "Timesheet", include: "both", group: "exact" },
    { key: "timesheet-week-day", label: "Timesheet (Week + Day)", include: "both", group: "day" },
    { key: "weekly-snippet", label: "Weekly Snippet", include: "both", group: "week" },
    { key: "time-project", label: "Time Per Project", include: "time", group: "project" },
    { key: "time-application", label: "Time Per Application", include: "app", group: "application" },
    { key: "time-document", label: "Time Per Document", include: "time", group: "document" },
    { key: "ultra-detailed", label: "Ultra-Detailed", include: "both", group: "exact" },
    { key: "raw-time-entries", label: "Raw Time Entries", include: "time", group: "exact" },
    { key: "raw-app-usage", label: "Raw App Usage", include: "app", group: "exact" },
  ];
  const report = useMemo(() => {
    const startBound = new Date(`${rangeStart}T00:00:00`);
    const endBound = new Date(`${offsetDateKey(rangeEnd, 1)}T00:00:00`);
    const projectFor = (value) => projectTitleFor(api.projects, value);
    const projectDetails = (value) => {
      const project = api.projects.find((item) => resourceID(item.id) === resourceID(value));
      return { rate: project?.billing_rate || 0, currency: project?.currency || "USD" };
    };
    const rows = [];
    if (includeMode !== "app") dataset.entries.forEach((entry) => {
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
    if (includeMode !== "time" && billingFilter === "all") {
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
    rows.forEach((row) => { row.billableSeconds = row.billing === "Billable" ? row.seconds : 0; });
    const groupedRows = groupBy === "exact" ? rows : [...rows.reduce((groups, row) => {
      const application = row.kind === "Activity" ? row.title.split(" · ")[0] : "Time entries";
      const document = row.notes || row.title;
      const key = groupBy === "project" ? row.project : groupBy === "application" ? application : groupBy === "document" ? document : groupBy === "day" ? row.start.toLocaleDateString() : groupBy === "week" ? `Week of ${row.start.toLocaleDateString()}` : row.start.toLocaleDateString();
      const current = groups.get(key) || { ...row, kind: "Summary", title: key, seconds: 0, billableSeconds: 0, amount: 0, notes: "" };
      current.seconds += row.seconds;
      current.billableSeconds += row.billableSeconds;
      current.amount += row.amount;
      current.start = current.start < row.start ? current.start : row.start;
      current.end = current.end > row.end ? current.end : row.end;
      current.billing = current.billing === row.billing ? row.billing : "Mixed";
      groups.set(key, current);
      return groups;
    }, new Map()).values()].sort((left, right) => left.start - right.start);
    return { rows: groupedRows, totalSeconds: groupedRows.reduce((sum, row) => sum + row.seconds, 0), billableSeconds: groupedRows.reduce((sum, row) => sum + row.billableSeconds, 0), amount: groupedRows.reduce((sum, row) => sum + row.amount, 0), currencies: [...new Set(groupedRows.map((row) => row.currency).filter(Boolean))] };
  }, [api.projects, billingFilter, dataset, groupBy, includeMode, rangeEnd, rangeStart, rounding, roundingInterval]);
  const setDatePreset = (preset) => {
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
  const applyReportPreset = (preset) => {
    const selected = reportPresets.find((item) => item.key === preset);
    if (!selected) return;
    setReportPreset(selected.key);
    setIncludeMode(selected.include);
    setGroupBy(selected.group);
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
  const exportNativeReport = async (format) => {
    try {
      setMessage(`Generating ${format.toUpperCase()}…`);
      await api.downloadReportFile({ startDate: rangeStart, endDate: rangeEnd, format, include: includeMode, groupBy, billingFilter, rounding, roundingMinutes: roundingInterval });
      setMessage(`${format.toUpperCase()} report exported.`);
    } catch (error) {
      setMessage(error.message || `Could not export ${format.toUpperCase()} report.`);
    }
  };
  return <section className="web-report-panel">
    <div className="chart-heading">
      <div><h2>Reports & exports</h2><p>Timing-style reports from local activities, time entries, projects, and billing status.</p></div>
      <div className="report-actions"><button type="button" onClick={exportCSV} disabled={!report.rows.length}>Export CSV</button><button type="button" onClick={exportJSON} disabled={!report.rows.length}>Export JSON</button><button type="button" onClick={exportHTML} disabled={!report.rows.length}>Export HTML</button><button type="button" onClick={() => exportNativeReport("xlsx")} disabled={!report.rows.length || !api.connected}>Export XLSX</button><button type="button" onClick={() => exportNativeReport("pdf")} disabled={!report.rows.length || !api.connected}>Export PDF</button></div>
    </div>
    <div className="report-presets">
      <label>Report<select value={reportPreset} onChange={(event) => applyReportPreset(event.target.value)}>{reportPresets.map((preset) => <option value={preset.key} key={preset.key}>{preset.label}</option>)}</select></label>
      <button type="button" onClick={() => setDatePreset("today")}>Today</button><button type="button" onClick={() => setDatePreset("week")}>Last 7 days</button><button type="button" onClick={() => setDatePreset("month")}>This month</button>
      <label>From<input type="date" value={rangeStart} onChange={(event) => setRangeStart(event.target.value)} /></label><label>To<input type="date" value={rangeEnd} onChange={(event) => setRangeEnd(event.target.value)} /></label>
    </div>
    <div className="report-filters">
      <label>Include<select value={includeMode} onChange={(event) => setIncludeMode(event.target.value)}><option value="both">Time entries + app activity</option><option value="time">Time entries only</option><option value="app">App activity only</option></select></label>
      <label>Group by<select value={groupBy} onChange={(event) => setGroupBy(event.target.value)}><option value="exact">Exact rows</option><option value="day">Day</option><option value="week">Week</option><option value="project">Project</option><option value="application">Application</option><option value="document">Document</option></select></label>
      <label>Billing<select value={billingFilter} onChange={(event) => setBillingFilter(event.target.value)}><option value="all">All statuses</option><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select></label>
      <label>Rounding<select value={rounding} onChange={(event) => setRounding(event.target.value)}><option value="none">Exact</option><option value="up">Round up</option><option value="down">Round down</option><option value="nearest">Nearest</option></select></label>
      <label>Interval<select value={roundingInterval} onChange={(event) => setRoundingInterval(Number(event.target.value))}><option value={1}>1 min</option><option value={5}>5 min</option><option value={6}>6 min</option><option value={10}>10 min</option><option value={12}>12 min</option><option value={15}>15 min</option><option value={30}>30 min</option><option value={60}>1 hour</option></select></label>
    </div>
    {message ? <p className="entry-message" role="status">{message}</p> : null}
    <div className="report-metrics"><div><span>Total</span><strong>{formatDurationSeconds(report.totalSeconds)}</strong></div><div><span>Billable</span><strong>{formatDurationSeconds(report.billableSeconds)}</strong></div><div><span>Amount</span><strong>{report.amount.toFixed(2)} {report.currencies.length === 1 ? report.currencies[0] : report.currencies.length > 1 ? "mixed" : "USD"}</strong></div><div><span>Rows</span><strong>{loading ? "…" : report.rows.length}</strong></div></div>
    {report.rows.length > 0 ? <div className="report-table"><div className="report-table-head"><span>Title</span><span>Project</span><span>Timespan</span><span>Duration</span><span>Billing</span></div>{report.rows.slice(0, 40).map((row, index) => <div className="report-table-row" key={`${row.kind}-${row.start.toISOString()}-${index}`}><strong>{row.title}</strong><span>{row.project}</span><span>{row.start.toLocaleDateString(undefined, { month: "short", day: "numeric" })} {entryClock(row.start)}–{entryClock(row.end)}</span><span>{formatDurationSeconds(row.seconds)}</span><small>{row.billing}</small></div>)}</div> : <div className="entries-empty"><ChartBar size={24} /><span>{loading ? "Loading report data…" : api.connected ? "No rows match this report." : "Connect the native app to generate a report."}</span></div>}
  </section>;
}

function WebActivityTimeline({ activities, dateKey, api, onSelect, orientation: requestedOrientation = "horizontal", onToggleOrientation }) {
 const trackRef = useRef(null);
 const [selection, setSelection] = useState(null);
 const [message, setMessage] = useState("");
  const controlledOrientation = typeof onToggleOrientation === "function";
  const [localOrientation, setLocalOrientation] = useState(() => api.activityPreferences?.timeline_orientation === "vertical" ? "vertical" : "horizontal");
  const orientation = controlledOrientation ? requestedOrientation : localOrientation;
  useEffect(() => {
    if (!controlledOrientation) setLocalOrientation(api.activityPreferences?.timeline_orientation === "vertical" ? "vertical" : "horizontal");
  }, [api.activityPreferences, controlledOrientation]);
  const toggleOrientation = onToggleOrientation || (() => {
    const next = orientation === "horizontal" ? "vertical" : "horizontal";
    setLocalOrientation(next);
    void api.updateActivityPreferences?.({ timeline_orientation: next });
  });
 const totalSeconds = 24 * 60 * 60;
  const minuteAt = (clientPosition, rect) => {
    const offset = orientation === "vertical" ? clientPosition - rect.top : clientPosition - rect.left;
    const length = orientation === "vertical" ? rect.height : rect.width;
    return Math.max(0, Math.min(24 * 60, Math.round((offset / length) * 24 * 60 / 15) * 15));
  };
  const startSelection = (event) => {
    if (event.button !== 0 || !trackRef.current) return;
    const rect = trackRef.current.getBoundingClientRect();
    const position = orientation === "vertical" ? event.clientY : event.clientX;
    const start = minuteAt(position, rect);
    let latest = { start, end: Math.min(start + 15, 24 * 60) };
    setSelection(latest);
    const move = (moveEvent) => {
      const movePosition = orientation === "vertical" ? moveEvent.clientY : moveEvent.clientX;
      const end = minuteAt(movePosition, rect);
      latest = { start: Math.min(start, end), end: Math.max(start, end) || Math.min(start + 15, 24 * 60) };
      if (latest.end === latest.start) latest.end = Math.min(latest.start + 15, 24 * 60);
      setSelection(latest);
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      if (latest.end <= latest.start) setSelection(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  const recordSelection = async () => {
    if (!selection || !api.connected) return;
    const start = localEntryDateSeconds(dateKey, selection.start * 60);
    const end = localEntryDateSeconds(dateKey, selection.end * 60);
    if (!start || !end) return;
    setMessage("Recording…");
    try {
      await api.addTimeEntry({ title: "Activity time", start, end, billingStatus: "billable" });
      setSelection(null);
      setMessage("Recorded " + formatRange(selection.start, selection.end));
    } catch (error) {
      setMessage(error.message || "Could not record the selected range.");
    }
  };
  const vertical = orientation === "vertical";
  const timelineHours = [0, 6, 12, 18, 24];
  const timeEntries = api.activityPreferences?.include_time_entries !== false ? (api.entries || []).map((entry) => ({ entry, range: entrySecondsForDate(entry, dateKey) })).filter((item) => item.range) : [];
  const calendarEvents = Array.isArray(api.calendarEvents?.data) ? api.calendarEvents.data.map((event) => {
    const startDate = new Date(event.start || "");
    const endDate = new Date(event.end || "");
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) return null;
    const dayStart = new Date(`${dateKey}T00:00:00`);
    const startSecond = Math.max(0, Math.min(totalSeconds, Math.floor((startDate.getTime() - dayStart.getTime()) / 1000)));
    const endSecond = Math.max(0, Math.min(totalSeconds, Math.ceil((endDate.getTime() - dayStart.getTime()) / 1000)));
    return endSecond > startSecond ? { event, startSecond, endSecond } : null;
  }).filter(Boolean) : [];
  const recordCalendarEvent = async (calendarEvent) => {
    if (!api.connected) return;
    try {
      await api.addTimeEntry({ title: calendarEvent.title || "Calendar event", start: calendarEvent.start, end: calendarEvent.end, billingStatus: "billable" });
      setMessage("Recorded calendar event.");
    } catch (error) {
      setMessage(error.message || "Could not record the calendar event.");
    }
  };
  const rangeStyle = (startSecond, endSecond, color) => vertical ? { top: `${(startSecond / totalSeconds) * 100}%`, height: `${Math.max((endSecond - startSecond) / totalSeconds * 100, 0.4)}%`, borderColor: color } : { left: `${(startSecond / totalSeconds) * 100}%`, width: `${Math.max((endSecond - startSecond) / totalSeconds * 100, 0.4)}%`, borderColor: color };
  return <section className="web-activity-timeline" aria-label="Activities timeline"><div className="web-activity-timeline-heading"><div><h2>Timeline</h2><p>Hover for exact activity; drag across a gap to select time for a manual entry.</p><div className="web-activity-timeline-legend" aria-label="Timeline color legend"><span><i className="focused" />Focused</span><span><i className="distracting" />Distracting</span><span><i className="other" />Other</span><span><i className="idle" />Idle</span></div></div><div className="web-activity-timeline-actions"><button type="button" className="timeline-orientation-toggle" onClick={toggleOrientation} aria-label={"Switch to " + (vertical ? "horizontal" : "vertical") + " timeline"} title={"Switch to " + (vertical ? "horizontal" : "vertical") + " timeline"}><ArrowsClockwise size={14} />{vertical ? "Vertical" : "Horizontal"}</button>{selection ? <><span>{formatRange(selection.start, selection.end)}</span><button type="button" onClick={recordSelection} disabled={!api.connected}>Record time</button><button type="button" className="timeline-clear" onClick={() => setSelection(null)}>Clear</button></> : <span>00:00–24:00</span>}{message ? <small role="status">{message}</small> : null}</div></div><div className={"web-activity-timeline-track " + (vertical ? "vertical" : "horizontal")} ref={trackRef} onPointerDown={startSelection}>{timelineHours.map((hour) => <span className="web-activity-timeline-label" key={hour} style={vertical ? { top: `${(hour / 24) * 100}%` } : { left: `${(hour / 24) * 100}%` }}>{String(hour).padStart(2, "0")}:00</span>)}<div className="web-activity-timeline-grid" aria-hidden="true">{timelineHours.map((hour) => <i key={hour} style={vertical ? { top: `${(hour / 24) * 100}%` } : { left: `${(hour / 24) * 100}%` }} />)}</div>{activities.map((activity) => { const startSecond = Math.max(0, Number(activity.startSecond || 0)); const endSecond = Math.min(totalSeconds, Number(activity.endSecond || 0)); if (endSecond <= startSecond) return null; const category = activityCategory(activity); const categoryStyle = activityCategoryStyle(category); const startPercent = (startSecond / totalSeconds) * 100; const durationPercent = Math.max((endSecond - startSecond) / totalSeconds * 100, 0.18); const blockStyle = vertical ? { top: `${startPercent}%`, height: `${durationPercent}%`, borderColor: categoryStyle.color } : { left: `${startPercent}%`, width: `${durationPercent}%`, borderColor: categoryStyle.color }; return <button type="button" key={activity.id} className={"web-activity-timeline-block " + category.key} style={blockStyle} title={activityLabel(activity) + " · " + category.label + " · " + preciseClock(startSecond) + "–" + preciseClock(endSecond)} onPointerDown={(event) => event.stopPropagation()} onClick={() => onSelect(activity)}><span style={{ color: categoryStyle.color }} /></button>; })}{timeEntries.map(({ entry, range }) => <button type="button" key={"entry-" + entryID(entry)} className="web-activity-timeline-overlay time-entry" style={rangeStyle(range.startSecond, range.endSecond, "#d77b22")} title={"Time entry · " + (entry.title || "Untitled") + " · " + entryRange(entry)} onPointerDown={(event) => event.stopPropagation()} onClick={() => setMessage("Time entry · " + (entry.title || "Untitled"))}><span /></button>)}{calendarEvents.map(({ event, startSecond, endSecond }) => <button type="button" key={"calendar-" + (event.id || event.title)} className="web-activity-timeline-overlay calendar-event" style={rangeStyle(startSecond, endSecond, "#4e5ff2")} title={"Calendar · " + (event.title || "Untitled event")} onPointerDown={(pointerEvent) => pointerEvent.stopPropagation()} onClick={() => recordCalendarEvent(event)}><span /></button>)}{selection ? <div className="web-activity-timeline-selection" style={vertical ? { top: `${(selection.start / (24 * 60)) * 100}%`, height: `${((selection.end - selection.start) / (24 * 60)) * 100}%` } : { left: `${(selection.start / (24 * 60)) * 100}%`, width: `${((selection.end - selection.start) / (24 * 60)) * 100}%` }} aria-label={"Selected " + formatRange(selection.start, selection.end)} /> : null}</div></section>;
}

function ActivityTable({ activities, onSelect, viewMode = "unified", groupMode = "none", projects = [], displayPreferences = null, dateKey = "" }) {
  const [collapsedGroups, setCollapsedGroups] = useState(() => new Set());
  const rows = [...activities].sort((left, right) => String(left.date || dateKey).localeCompare(String(right.date || dateKey)) || Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const activityRow = (activity) => {
    const category = activityCategory(activity);
    const Icon = activityIcon(activity);
    const app = activity.appName || activity.deviceName || "Unknown App";
    const context = activityContext(activity, {
      showWindowTitles: displayPreferences?.show_window_titles,
      showResourcePaths: displayPreferences?.show_resource_paths,
    });
    const start = Math.floor(Number(activity.startSecond || 0) / 60);
    const end = Math.ceil(Number(activity.endSecond || 0) / 60);
    const duration = Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
    return <button className="activity-table-row" key={activity.id} type="button" draggable onDragStart={(event) => { event.dataTransfer.effectAllowed = "copy"; event.dataTransfer.setData("application/x-metriday-activity", activity.id); event.dataTransfer.setData("application/x-metriday-activity-date", activity.date || dateKey); }} onClick={() => onSelect(activity)} aria-label={`Open details for ${app} ${formatRange(start, end)}`} title="Drag this activity to a project to assign it">
      <div className="activity-app-cell">
        <span className="activity-table-icon"><Icon size={19} weight="duotone" /></span>
        <span className="activity-app-copy"><strong>{app}</strong>{context ? <small>{context}</small> : null}</span>
      </div>
      <span className={`activity-category ${category.key}`} style={activityCategoryStyle(category)}><i />{category.label}</span>
      <span>{activity.date && activity.date !== dateKey ? `${activity.date} · ` : ""}{formatRange(start, end)}</span>
      <small>{formatDurationSeconds(duration)} · {activity.deviceName || "This Mac"}</small>
    </button>;
  };
  const grouping = viewMode === "category" ? "category" : groupMode !== "none" ? groupMode : viewMode === "unified" ? "application" : "none";
  if (grouping === "none") {
    return <div className="activity-table">
      <div className="activity-table-head" aria-hidden="true"><span>App</span><span>Category</span><span>Time</span><span>Device</span></div>
      {rows.map(activityRow)}
    </div>;
  }
  const grouped = [...rows.reduce((groups, activity) => {
    const category = activityCategory(activity);
    const key = grouping === "category" ? `${category.key}:${category.label}` : grouping === "project" ? resourceID(activity.projectID) || "unassigned" : grouping === "device" ? activity.deviceName || "This Mac" : activity.appName || activity.deviceName || "Unknown App";
    const label = grouping === "category" ? category.label : grouping === "project" ? projectTitleFor(projects, activity.projectID) : grouping === "device" ? activity.deviceName || "This Mac" : activity.appName || activity.deviceName || "Unknown App";
    const existing = groups.get(key) || { key, label, category, activities: [], seconds: 0 };
    existing.activities.push(activity);
    existing.seconds += Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
    groups.set(key, existing);
    return groups;
  }, new Map()).values()].sort((left, right) => right.seconds - left.seconds || left.label.localeCompare(right.label));
  return <div className="activity-table">
    {grouped.map((group) => {
      const collapsed = collapsedGroups.has(group.key);
      return <section className="activity-group" key={group.key}>
        <button type="button" className="activity-group-heading" onClick={() => setCollapsedGroups((current) => { const next = new Set(current); if (next.has(group.key)) next.delete(group.key); else next.add(group.key); return next; })} aria-expanded={!collapsed}>
          <span className="activity-group-title">{grouping === "category" ? <span className={`activity-category ${group.category.key}`} style={activityCategoryStyle(group.category)}><i />{group.label}</span> : <strong>{group.label}</strong>}</span>
          <span className="activity-group-meta">{formatDurationSeconds(group.seconds)} · {group.activities.length} segment{group.activities.length === 1 ? "" : "s"}<CaretDown size={15} className={collapsed ? "collapsed" : ""} /></span>
        </button>
        {!collapsed ? <div className="activity-group-rows">{group.activities.map(activityRow)}</div> : null}
      </section>;
    })}
  </div>;
}

function ActivityDetailDialog({ activity, api, dateKey, displayPreferences = null, onClose }) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const projectLabel = projectTitleFor(api.projects, activity.projectID);
  const category = activityCategory(activity);
  const Icon = activityIcon(activity);
  const app = activity.appName || activity.deviceName || "Unknown App";
  const context = activityContext(activity, {
    showWindowTitles: displayPreferences?.show_window_titles,
    showResourcePaths: displayPreferences?.show_resource_paths,
  });
  const startSecond = Math.max(0, Number(activity.startSecond || 0));
  const endSecond = Math.max(startSecond, Number(activity.endSecond || 0));
  const record = async () => {
    if (busy || !api.connected || endSecond <= startSecond) return;
    setBusy(true);
    setMessage("");
    try {
      const activityDateKey = activity.date || dateKey;
      const start = localEntryDateSeconds(activityDateKey, startSecond);
      const end = localEntryDateSeconds(activityDateKey, endSecond);
      await api.addTimeEntry({ title: activityLabel(activity), start, end, billingStatus: "billable" });
      setMessage("Recorded as a time entry.");
    } catch (error) {
      setMessage(error.message || "Could not record this activity.");
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    const handleKeyDown = (event) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);
  return <div className="activity-detail-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section className="activity-detail-dialog" role="dialog" aria-modal="true" aria-labelledby="activity-detail-title">
      <header className="activity-detail-heading"><div><span>Activity details</span><h2 id="activity-detail-title">{app}</h2></div><IconButton label="Close activity details" onClick={onClose}><X size={18} /></IconButton></header>
      <div className="activity-detail-app"><span className="activity-detail-icon"><Icon size={22} weight="duotone" /></span><div><strong>{context || app}</strong><small>{activity.deviceName || "This Mac"}</small></div><span className={`activity-category ${category.key}`} style={activityCategoryStyle(category)}><i />{category.label}</span></div>
      <dl className="activity-detail-facts"><div><dt>Date</dt><dd>{activity.date || dateKey}</dd></div><div><dt>Time</dt><dd>{preciseClock(startSecond)}–{preciseClock(endSecond)}</dd></div><div><dt>Duration</dt><dd>{preciseDuration(endSecond - startSecond)}</dd></div><div><dt>Project</dt><dd><i className="hover-project-dot" />{projectLabel} {!activity.projectID ? <small>From the app usage</small> : null}</dd></div>{displayPreferences?.show_window_titles !== false && activity.windowTitle ? <div><dt>Window</dt><dd>{activity.windowTitle}</dd></div> : null}{displayPreferences?.show_resource_paths !== false && activity.resource ? <div><dt>Resource</dt><dd>{activity.resource}</dd></div> : null}</dl>
      {message ? <p className="entry-message" role="status">{message}</p> : null}
      <footer className="activity-detail-actions"><button type="button" className="secondary-button" onClick={onClose}>Close</button><button type="button" className="primary-button" onClick={record} disabled={busy || !api.connected || endSecond <= startSecond}>{busy ? "Recording…" : "Record time"}</button></footer>
    </section>
  </div>;
}

function WebPhoneCallsPanel({ api }) {
  const payload = api.phoneCalls || {};
  const calls = Array.isArray(payload.data) ? payload.data : [];
  const formatCallTime = (value) => {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  };
  return <section className="web-source-panel" aria-label="Phone Calls"><div className="web-source-heading"><div><h2>Phone Calls</h2><p>Read-only call history that can be recorded as local time evidence.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.database_available ? "online" : ""}`}>{payload.database_available ? `${calls.length} calls` : "Not connected"}</span><button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{calls.length > 0 ? <div className="web-source-list">{calls.map((call) => <div className="web-source-row" key={call.id}><span className="web-source-icon"><Clock size={18} /></span><div><strong>{call.address || "Phone call"}</strong><small>{call.service_provider || "Call history"} · {formatCallTime(call.start)}–{formatCallTime(call.end)}</small></div><span>{formatDurationSeconds(Number(call.duration_seconds || 0))}</span><IconButton label={`Hide calls from ${call.address || "this address"}`} onClick={() => api.hidePhoneCallAddress(call.address, true)}><X size={15} /></IconButton></div>)}</div> : <div className="web-source-empty"><Clock size={22} /><span>{payload.status || "No phone calls for this date."}</span></div>}</section>;
}

function WebCalendarEventsPanel({ api }) {
  const payload = api.calendarEvents || {};
  const events = Array.isArray(payload.data) ? payload.data : [];
  const [message, setMessage] = useState("");
  const record = async (event) => {
    try {
      await api.addTimeEntry({ title: event.title || "Calendar event", start: event.start, end: event.end, billingStatus: "billable" });
      setMessage(`Recorded “${event.title || "Calendar event"}”.`);
    } catch (error) {
      setMessage(error.message || "Could not record the calendar event.");
    }
  };
  const time = (value) => {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  };
  return <section className="web-source-panel" aria-label="Calendar Events"><div className="web-source-heading"><div><h2>Calendar Events</h2><p>Read-only calendar events can seed a local time entry after access is granted.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.authorized ? "online" : ""}`}>{payload.authorized ? `${events.length} events` : "Not connected"}</span><button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{events.length > 0 ? <div className="web-source-list">{events.map((event) => <div className="web-source-row" key={event.id}><span className="web-source-icon"><CalendarBlank size={18} /></span><div><strong>{event.title}</strong><small>{event.calendar || "Calendar"} · {time(event.start)}–{time(event.end)}{event.location ? ` · ${event.location}` : ""}</small></div><button type="button" className="quiet-pill" onClick={() => record(event)}>Record</button></div>)}</div> : <div className="web-source-empty"><CalendarBlank size={22} /><span>{payload.status || "No calendar events for this date."}</span></div>}{message ? <p className="entry-message" role="status">{message}</p> : null}</section>;
}

function WebRemindersPanel({ api }) {
  const payload = api.reminders || {};
  const reminders = Array.isArray(payload.data) ? payload.data : [];
  const [message, setMessage] = useState("");
  const record = async (reminder) => {
    const start = new Date(reminder.completed_at || "");
    if (Number.isNaN(start.getTime())) return;
    const end = new Date(start.getTime() + 15 * 60 * 1000).toISOString();
    try {
      await api.addTimeEntry({ title: reminder.title || "Completed reminder", start: reminder.completed_at, end, billingStatus: "billable" });
      setMessage(`Recorded “${reminder.title || "Completed reminder"}”.`);
    } catch (error) {
      setMessage(error.message || "Could not record the reminder.");
    }
  };
  const time = (value) => {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  };
  return <section className="web-source-panel" aria-label="Completed Reminders"><div className="web-source-heading"><div><h2>Completed Reminders</h2><p>Completed local reminders remain read-only and can suggest a 15-minute time entry.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.authorized ? "online" : ""}`}>{payload.authorized ? `${reminders.length} completed` : "Not connected"}</span><button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{reminders.length > 0 ? <div className="web-source-list">{reminders.map((reminder) => <div className="web-source-row" key={reminder.id}><span className="web-source-icon"><CheckCircle size={18} /></span><div><strong>{reminder.title}</strong><small>{reminder.list || "Reminders"} · Completed {time(reminder.completed_at)}{reminder.is_recurring ? " · Recurring" : ""}</small></div><button type="button" className="quiet-pill" onClick={() => record(reminder)}>Record</button></div>)}</div> : <div className="web-source-empty"><CheckCircle size={22} /><span>{payload.status || "No completed reminders for this date."}</span></div>}{message ? <p className="entry-message" role="status">{message}</p> : null}</section>;
}

function WebScreenTimePanel({ api }) {
  const payload = api.screenTime || {};
  const segments = Array.isArray(payload.data) ? payload.data : [];
  const grouped = [...segments.reduce((groups, segment) => {
    const key = segment.appName || segment.resource || "Screen Time activity";
    const current = groups.get(key) || { key, label: key, seconds: 0, category: activityCategory(segment) };
    current.seconds += Math.max(0, Number(segment.endSecond || 0) - Number(segment.startSecond || 0));
    groups.set(key, current);
    return groups;
  }, new Map()).values()].sort((left, right) => right.seconds - left.seconds).slice(0, 8);
  return <section className="web-source-panel" aria-label="Screen Time"><div className="web-source-heading"><div><h2>Screen Time</h2><p>Read-only Apple Screen Time imports are included in the Activities evidence above.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.database_available ? "online" : ""}`}>{payload.database_available ? `${segments.length} records` : "Not connected"}</span><button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{grouped.length > 0 ? <div className="web-source-list">{grouped.map((item) => <div className="web-source-row" key={item.key}><span className="web-source-icon" style={{ color: activityCategoryStyle(item.category).color }}><Laptop size={18} /></span><div><strong>{item.label}</strong><small>{item.category.label} · Imported Screen Time</small></div><span>{formatDurationSeconds(item.seconds)}</span></div>)}</div> : <div className="web-source-empty"><Laptop size={22} /><span>{payload.status || "No Screen Time activities for this date."}</span></div>}</section>;
}

function WebActivityFiltersPanel({ api }) {
  const [name, setName] = useState("");
  const [field, setField] = useState("application");
  const [comparison, setComparison] = useState("contains");
  const [pattern, setPattern] = useState("");
  const [editingID, setEditingID] = useState(null);
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", windowTitle: "Window title", resource: "URL or path", domain: "Domain", keyword: "Keyword", device: "Device" };
  const submit = async (event) => {
    event.preventDefault();
    if (!name.trim() || !pattern.trim() || !api.connected) return;
    try {
      const payload = { name: name.trim(), color: "purple", match_mode: "any", rules: [{ field, comparison, pattern: pattern.trim(), case_sensitive: false }] };
      if (editingID) await api.updateActivityFilter(editingID, payload);
      else await api.createActivityFilter(payload);
      setName("");
      setPattern("");
      setEditingID(null);
    } catch (error) {
      // The shared Activities refresh surface already exposes connection errors.
    }
  };
  const beginEdit = (filter) => {
    const rule = filter.rules?.[0] || {};
    setEditingID(resourceID(filter.id));
    setName(filter.name || "");
    setField(rule.field || "application");
    setComparison(rule.comparison || "contains");
    setPattern(rule.pattern || "");
  };
  return <section className="web-source-panel web-filters-panel" aria-label="Activity Filters"><div className="web-source-heading"><div><h2>Filters</h2><p>Save reusable App, website, and device rules for this activity stream.</p></div><span className="api-badge">{api.filters.length} saved</span></div><form className="web-filter-form" onSubmit={submit}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Filter name" aria-label="Activity filter name" /><select value={field} onChange={(event) => setField(event.target.value)} aria-label="Activity filter field">{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={comparison} onChange={(event) => setComparison(event.target.value)} aria-label="Activity filter comparison"><option value="contains">contains</option><option value="equals">is</option><option value="beginsWith">begins with</option><option value="endsWith">ends with</option><option value="matchesRegex">matches regex</option></select><input value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="Value" aria-label="Activity filter value" /><button type="submit" disabled={!api.connected || !name.trim() || !pattern.trim()}>{editingID ? <Check size={16} /> : <Plus size={16} />}{editingID ? "Save changes" : "Save filter"}</button>{editingID ? <button type="button" className="quiet-pill" onClick={() => { setEditingID(null); setName(""); setPattern(""); }}>Cancel</button> : null}</form>{api.filters.length > 0 ? <div className="web-source-list">{api.filters.map((filter) => <div className="web-source-row web-filter-row" key={filter.id}><span className="web-source-icon" style={{ color: activityCategoryStyle({ color: filter.color }).color }}><Waveform size={17} /></span><div><strong>{filter.name}</strong><small>{(filter.rules || []).map((rule) => `${fields[rule.field] || rule.field} ${rule.comparison} “${rule.pattern}”`).join(` ${filter.match_mode === "all" ? "and" : "or"} `)}</small></div><span>{filter.match_mode === "all" ? "All rules" : "Any rule"}</span><span className="web-category-actions"><IconButton label={`Edit ${filter.name}`} onClick={() => beginEdit(filter)}><NotePencil size={15} /></IconButton><IconButton label={`Delete ${filter.name}`} onClick={() => api.deleteActivityFilter(filter.id)}><Trash size={15} /></IconButton></span></div>)}</div> : <div className="web-source-empty"><Waveform size={22} /><span>No saved filters yet. Add one to reuse the same activity rule on this Mac.</span></div>}</section>;
}

function WebActivityExclusionsPanel({ api }) {
  const [field, setField] = useState("application");
  const [comparison, setComparison] = useState("contains");
  const [pattern, setPattern] = useState("");
  const [caseSensitive, setCaseSensitive] = useState(false);
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", windowTitle: "Window title", resource: "URL or path", domain: "Domain", fullURL: "Full website URL", device: "Device" };
  const submit = async (event) => {
    event.preventDefault();
    if (!pattern.trim() || !api.connected) return;
    try {
      await api.createActivityExclusion({ field, comparison, pattern: pattern.trim(), case_sensitive: caseSensitive });
      setPattern("");
    } catch {
      // Keep the editor available while the native connection recovers.
    }
  };
  return <section className="web-source-panel web-exclusions-panel" aria-label="Activity Exclusions"><div className="web-source-heading"><div><h2>Exclusions</h2><p>Ignore matching App, website, item, or device activity before it enters the local evidence stream.</p></div><span className="api-badge">{api.exclusions.length} saved</span></div><form className="web-filter-form" onSubmit={submit}><select value={field} onChange={(event) => setField(event.target.value)} aria-label="Activity exclusion field">{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={comparison} onChange={(event) => setComparison(event.target.value)} aria-label="Activity exclusion comparison"><option value="contains">contains</option><option value="equals">is</option><option value="beginsWith">begins with</option><option value="endsWith">ends with</option><option value="matchesRegex">matches regex</option></select><input value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="Value to ignore" aria-label="Activity exclusion value" /><label className="exclusion-case-toggle"><input type="checkbox" checked={caseSensitive} onChange={(event) => setCaseSensitive(event.target.checked)} />Case-sensitive</label><button type="submit" disabled={!api.connected || !pattern.trim()}><Plus size={16} />Save exclusion</button></form>{api.exclusions.length > 0 ? <div className="web-source-list">{api.exclusions.map((rule) => <div className="web-source-row web-filter-row" key={rule.id}><span className="web-source-icon"><ShieldCheck size={17} /></span><div><strong>{fields[rule.field] || rule.field}</strong><small>{rule.comparison} “{rule.pattern}”{rule.case_sensitive ? " · Case-sensitive" : ""}</small></div><IconButton label={`Delete exclusion ${rule.pattern}`} onClick={() => api.deleteActivityExclusion(rule.id)}><Trash size={15} /></IconButton></div>)}</div> : <div className="web-source-empty"><ShieldCheck size={22} /><span>No exclusions yet. Add one to keep private or noisy activity out of future captures.</span></div>}</section>;
}

function WebActivityCategoriesPanel({ api }) {
  const [name, setName] = useState("");
  const [role, setRole] = useState("focused");
  const [color, setColor] = useState("blue");
  const [field, setField] = useState("application");
  const [comparison, setComparison] = useState("contains");
  const [pattern, setPattern] = useState("");
  const [editingID, setEditingID] = useState(null);
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", windowTitle: "Window title", resource: "URL or path", domain: "Domain", keyword: "Keyword", device: "Device" };
  const submit = async (event) => {
    event.preventDefault();
    if (!name.trim() || !pattern.trim() || !api.connected) return;
    try {
      const payload = { name: name.trim(), role, color, match_mode: "any", rules: [{ field, comparison, pattern: pattern.trim(), case_sensitive: false }] };
      if (editingID) await api.updateActivityCategory(editingID, payload);
      else await api.createActivityCategory(payload);
      setName("");
      setPattern("");
      setEditingID(null);
    } catch (error) {
      // Keep the panel usable while the shared API connection state recovers.
    }
  };
  const beginEdit = (category) => {
    const rule = category.rules?.[0] || {};
    setEditingID(resourceID(category.id));
    setName(category.name || "");
    setRole(category.role || "other");
    setColor(category.color || "graphite");
    setField(rule.field || "application");
    setComparison(rule.comparison || "contains");
    setPattern(rule.pattern || "");
  };
  return <section className="web-source-panel web-categories-panel" aria-label="Activity Categories"><div className="web-source-heading"><div><h2>Categories</h2><p>App, website, and item colors come from these matching categories.</p></div><span className="api-badge">{api.categories.length} active</span></div><form className="web-category-form" onSubmit={submit}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Category name" aria-label="Activity category name" /><select value={role} onChange={(event) => setRole(event.target.value)} aria-label="Activity category role"><option value="focused">Focused</option><option value="distracting">Distracting</option><option value="other">Other</option><option value="idle">Idle</option></select><select value={color} onChange={(event) => setColor(event.target.value)} aria-label="Activity category color"><option value="blue">Deep blue</option><option value="red">Red</option><option value="green">Green</option><option value="orange">Orange</option><option value="purple">Purple</option><option value="graphite">Graphite</option></select><select value={field} onChange={(event) => setField(event.target.value)} aria-label="Activity category field">{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={comparison} onChange={(event) => setComparison(event.target.value)} aria-label="Activity category comparison"><option value="contains">contains</option><option value="equals">is</option><option value="beginsWith">begins with</option><option value="endsWith">ends with</option><option value="matchesRegex">matches regex</option></select><input value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="Matching value" aria-label="Activity category value" /><button type="submit" disabled={!api.connected || !name.trim() || !pattern.trim()}>{editingID ? <Check size={16} /> : <Plus size={16} />}{editingID ? "Save changes" : "Save category"}</button>{editingID ? <button type="button" className="quiet-pill" onClick={() => { setEditingID(null); setName(""); setPattern(""); }}>Cancel</button> : null}</form><div className="web-category-list">{api.categories.map((category) => <div className="web-category-row" key={category.id}><span className="web-category-swatch" style={{ background: activityCategoryStyle({ color: category.color }).color }} /><div><strong>{category.name}</strong><small>{category.is_system ? `Built-in fallback · ${category.role}` : `${(category.rules || []).length} rule${(category.rules || []).length === 1 ? "" : "s"} · ${category.role}`}</small></div>{category.is_system ? <span className="web-category-system">Built-in</span> : <span className="web-category-actions"><IconButton label={`Edit ${category.name}`} onClick={() => beginEdit(category)}><NotePencil size={15} /></IconButton><IconButton label={`Delete ${category.name}`} onClick={() => api.deleteActivityCategory(category.id)}><Trash size={15} /></IconButton></span>}</div>)}</div></section>;
}

function WebActivityDisplayMenu({ open, onToggle, preferences, devices, onChange }) {
  const values = preferences || {
    include_time_entries: true,
    show_window_titles: true,
    show_resource_paths: true,
    activity_time_range: "selectedDay",
    selected_device: "All Devices",
  };
  return <div className="activity-display-menu"><button type="button" className={`quiet-pill activity-display-button ${open ? "active" : ""}`} onClick={onToggle} aria-expanded={open} aria-haspopup="dialog"><SlidersHorizontal size={15} />Display</button>{open ? <div className="activity-display-popover" role="dialog" aria-label="Activity display settings"><strong>Display settings</strong><label><input type="checkbox" checked={Boolean(values.include_time_entries)} onChange={(event) => onChange({ include_time_entries: event.target.checked })} />Include time entries</label><label><input type="checkbox" checked={Boolean(values.show_window_titles)} onChange={(event) => onChange({ show_window_titles: event.target.checked })} />Show window titles</label><label><input type="checkbox" checked={Boolean(values.show_resource_paths)} onChange={(event) => onChange({ show_resource_paths: event.target.checked })} />Show website paths</label><label className="activity-display-select">Activity range<select value={values.activity_time_range || "selectedDay"} onChange={(event) => onChange({ activity_time_range: event.target.value })}><option value="selectedDay">Selected day</option><option value="lastSevenDays">Last 7 days</option></select></label></div> : null}</div>;
}

function WebActivityDevicesMenu({ open, devices, selectedDevice, hideDevicesWithoutTime, onToggle, onSelect, onToggleHide }) {
  const availableDevices = hideDevicesWithoutTime ? devices.filter((device) => device === "This Mac" || device === selectedDevice) : devices;
  const title = selectedDevice === "all" ? "Devices" : selectedDevice;
  const option = (value, label, icon) => <button type="button" className={`activity-popover-option ${selectedDevice === value ? "active" : ""}`} onClick={() => onSelect(value)}><span>{icon}</span><strong>{label}</strong>{selectedDevice === value ? <Check size={14} weight="bold" /> : null}</button>;
  return <div className="activity-toolbar-popover"><button type="button" className={`quiet-pill activity-toolbar-popover-button ${open ? "active" : ""}`} onClick={onToggle} aria-expanded={open} aria-haspopup="dialog"><Laptop size={15} />{title}</button>{open ? <div className="activity-toolbar-popover-panel" role="dialog" aria-label="Devices"><strong>Devices</strong>{option("all", "All Mac devices", <Laptop size={15} />)}<div className="activity-popover-divider" />{availableDevices.filter((device) => device !== "This Mac").map((device) => option(device, device, <Laptop size={15} key={device} />))}{availableDevices.includes("This Mac") ? option("This Mac", "This Mac", <Laptop size={15} />) : null}{devices.length <= 1 ? <p className="activity-popover-empty">No other devices have recorded time yet.</p> : null}<div className="activity-popover-divider" /><label className="activity-popover-checkbox"><input type="checkbox" checked={hideDevicesWithoutTime} onChange={(event) => onToggleHide(event.target.checked)} />Hide devices without time</label></div> : null}</div>;
}

function WebActivityFiltersMenu({ open, filters, projectFilterID, savedFilterID, categoryFilter, onToggle, onProjectFilter, onSavedFilter, onCategoryFilter }) {
  const savedFilter = filters.find((filter) => resourceID(filter.id) === savedFilterID);
  const title = savedFilter?.name || (projectFilterID === "unassigned" ? "Unassigned" : categoryFilter !== "all" ? `${categoryFilter[0].toUpperCase()}${categoryFilter.slice(1)}` : "Filters");
  const selectAll = () => { onProjectFilter("all"); onSavedFilter("all"); onCategoryFilter("all"); };
  const selectProject = () => { onProjectFilter("unassigned"); onSavedFilter("all"); onCategoryFilter("all"); };
  const selectCategory = (value) => { onProjectFilter("all"); onSavedFilter("all"); onCategoryFilter(value); };
  return <div className="activity-toolbar-popover"><button type="button" className={`quiet-pill activity-toolbar-popover-button ${open ? "active" : ""}`} onClick={onToggle} aria-expanded={open} aria-haspopup="dialog"><SlidersHorizontal size={15} />{title}</button>{open ? <div className="activity-toolbar-popover-panel" role="dialog" aria-label="Activity filters"><strong>Filters</strong><button type="button" className={`activity-popover-option ${savedFilterID === "all" && projectFilterID === "all" && categoryFilter === "all" ? "active" : ""}`} onClick={selectAll}><span><Waveform size={15} /></span><strong>All activity</strong>{savedFilterID === "all" && projectFilterID === "all" && categoryFilter === "all" ? <Check size={14} weight="bold" /> : null}</button><button type="button" className={`activity-popover-option ${projectFilterID === "unassigned" ? "active" : ""}`} onClick={selectProject}><span><TrayIcon /></span><strong>Unassigned</strong>{projectFilterID === "unassigned" ? <Check size={14} weight="bold" /> : null}</button><div className="activity-popover-divider" />{["focused", "distracting", "other", "idle"].map((value) => <button type="button" className={`activity-popover-option ${categoryFilter === value ? "active" : ""}`} key={value} onClick={() => selectCategory(value)}><span className={`activity-popover-category-dot ${value}`} /><strong>{value[0].toUpperCase() + value.slice(1)}</strong>{categoryFilter === value ? <Check size={14} weight="bold" /> : null}</button>)}{filters.length > 0 ? <><div className="activity-popover-divider" /><span className="activity-popover-label">Saved Filters</span>{filters.map((filter) => <button type="button" className={`activity-popover-option ${savedFilterID === resourceID(filter.id) ? "active" : ""}`} key={filter.id} onClick={() => { onProjectFilter("all"); onCategoryFilter("all"); onSavedFilter(resourceID(filter.id)); }}><span><Waveform size={15} /></span><strong>{filter.name}</strong>{savedFilterID === resourceID(filter.id) ? <Check size={14} weight="bold" /> : null}</button>)}</> : null}</div> : null}</div>;
}

function WebActivityProjectSidebar({ projects, filters, activities, projectFilterID, savedFilterID, onProjectFilter, onSavedFilter }) {
  const activeActivities = activities.filter((activity) => activityCategory(activity).key !== "idle");
  const secondsFor = (items) => items.reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const projectRows = projects.map((project) => ({ project, activities: activeActivities.filter((activity) => resourceID(activity.projectID) === resourceID(project.id)) }));
  const sidebarButton = (active, onClick, icon, title, detail) => <button type="button" className={`activity-project-filter ${active ? "active" : ""}`} onClick={onClick}><span className="activity-project-filter-icon">{icon}</span><span><strong>{title}</strong><small>{detail}</small></span></button>;
  return <aside className="activity-project-sidebar" aria-label="Activity projects and filters"><div className="activity-project-sidebar-heading"><h2>Projects</h2><span>{formatDurationSeconds(secondsFor(activeActivities))}</span></div><div className="activity-project-filter-list">{sidebarButton(projectFilterID === "all" && savedFilterID === "all", () => onProjectFilter("all"), <Waveform size={16} />, "All Activities", `${activeActivities.length} segments`)}{sidebarButton(projectFilterID === "unassigned", () => onProjectFilter("unassigned"), <TrayIcon />, "Unassigned", `${activeActivities.filter((activity) => !activity.projectID).length} segments`)}{projectRows.length > 0 ? <div className="activity-project-sidebar-label">My Projects</div> : null}{projectRows.map(({ project, activities: projectActivities }) => sidebarButton(projectFilterID === resourceID(project.id), () => onProjectFilter(resourceID(project.id)), <FolderSimple size={16} />, project.title, `${projectActivities.length} · ${formatDurationSeconds(secondsFor(projectActivities))}`))}</div><div className="activity-project-sidebar-divider" /><div className="activity-project-sidebar-heading"><h2>Filters</h2><span>{filters.length}</span></div><div className="activity-project-filter-list">{sidebarButton(savedFilterID === "all" && projectFilterID === "all", () => onSavedFilter("all"), <SlidersHorizontal size={16} />, "All activity", "No saved filter")}{filters.map((filter) => sidebarButton(savedFilterID === resourceID(filter.id), () => onSavedFilter(resourceID(filter.id)), <Waveform size={16} />, filter.name, `${(filter.rules || []).length} rule${(filter.rules || []).length === 1 ? "" : "s"}`))}</div><p className="activity-project-sidebar-hint">Drag an App / Category row to a project below to assign it.</p></aside>;
}

function TrayIcon() {
  return <span className="tray-icon" aria-hidden="true" />;
}

function WebEntryOMaticDialog({ open, activities, entries, projects, dateKey, onClose, onCreate }) {
  const [projectID, setProjectID] = useState("");
  const [minimumDurationMinutes, setMinimumDurationMinutes] = useState(5);
  const [maximumGapSeconds, setMaximumGapSeconds] = useState(60);
  const [overwriteExisting, setOverwriteExisting] = useState(false);
  const [title, setTitle] = useState("Work session");
  const [notes, setNotes] = useState("");
  const [billingStatus, setBillingStatus] = useState("billable");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const scopedActivities = projectID ? activities.filter((activity) => resourceID(activity.projectID) === projectID) : activities;
  const previewIntervals = useMemo(() => entryOMaticIntervals(scopedActivities, entries, dateKey, { minimumDurationMinutes, maximumGapSeconds, overwriteExisting }), [dateKey, entries, maximumGapSeconds, minimumDurationMinutes, overwriteExisting, scopedActivities]);
  const previewDuration = previewIntervals.reduce((total, interval) => total + interval.endSecond - interval.startSecond, 0);
  useEffect(() => {
    if (!open) return;
    setProjectID("");
    setMinimumDurationMinutes(5);
    setMaximumGapSeconds(60);
    setOverwriteExisting(false);
    setTitle("Work session");
    setNotes("");
    setBillingStatus("billable");
    setBusy(false);
    setMessage("");
  }, [dateKey, open]);
  const updateProject = (value) => {
    setProjectID(value);
    const project = projects.find((item) => resourceID(item.id) === value);
    if (project) {
      setTitle(project.title || "Work session");
      setBillingStatus(project.default_billing_status || "billable");
    }
  };
  const submit = async () => {
    if (busy || previewIntervals.length === 0 || !title.trim()) return;
    setBusy(true);
    setMessage("");
    try {
      await onCreate(previewIntervals, { title: title.trim(), notes, projectID: projectID || null, billingStatus, overwriteExisting });
      onClose();
    } catch (error) {
      setMessage(error.message || "Could not create time entries.");
    } finally {
      setBusy(false);
    }
  };
  if (!open) return null;
  return <div className="entry-omatic-backdrop" role="presentation" onClick={onClose}><section className="entry-omatic-dialog" role="dialog" aria-modal="true" aria-labelledby="entry-omatic-title" onClick={(event) => event.stopPropagation()}><header><div><span>Activity conversion</span><h2 id="entry-omatic-title">Create Time Entries</h2><p>Turn visible App / Category usage into reviewable time entries for {dateKey}.</p></div><IconButton label="Close Entry-O-Matic" onClick={onClose}><X size={17} /></IconButton></header><div className="entry-omatic-form"><label>Project<select value={projectID} onChange={(event) => updateProject(event.target.value)}><option value="">All visible activity</option>{projects.map((project) => <option value={resourceID(project.id)} key={project.id}>{project.title}</option>)}</select></label><div className="entry-omatic-options"><label>Minimum duration<select value={minimumDurationMinutes} onChange={(event) => setMinimumDurationMinutes(Number(event.target.value))}>{[1, 5, 10, 15].map((minutes) => <option value={minutes} key={minutes}>At least {minutes}m</option>)}</select></label><label>Maximum gap<select value={maximumGapSeconds} onChange={(event) => setMaximumGapSeconds(Number(event.target.value))}>{[0, 5, 30, 60, 300].map((seconds) => <option value={seconds} key={seconds}>{seconds === 0 ? "No gap" : `Gap ≤ ${seconds}s`}</option>)}</select></label></div><label className="entry-omatic-check"><input type="checkbox" checked={overwriteExisting} onChange={(event) => setOverwriteExisting(event.target.checked)} />Replace overlapping time entries</label><small className="entry-omatic-help">Without replacement, existing time is subtracted from the generated intervals.</small><label>Time entry title<input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Work session" /></label><label>Billing status<select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)}><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select></label><label>Notes (optional)<textarea value={notes} onChange={(event) => setNotes(event.target.value)} rows={2} /></label></div><div className="entry-omatic-preview"><div><strong><Sparkle size={16} /> Preview</strong><span>{previewIntervals.length ? `${previewIntervals.length} entries · ${formatDurationSeconds(previewDuration)}` : "No intervals meet the current minimum duration and coverage settings."}</span></div>{previewIntervals.length ? <p>{previewIntervals.map((interval) => formatRange(Math.floor(interval.startSecond / 60), Math.ceil(interval.endSecond / 60))).join(" · ")}</p> : null}</div>{message ? <p className="entry-message" role="status">{message}</p> : null}<footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="button" className="primary-button" onClick={submit} disabled={busy || previewIntervals.length === 0 || !title.trim()}>{busy ? "Creating…" : `Create ${previewIntervals.length} Time Entries`}</button></footer></section></div>;
}

function WebTimeEntryDialog({ mode, open, api, projects, recentEntries, dateKey, onClose }) {
  const timerMode = mode === "timer";
  const [title, setTitle] = useState("");
  const [start, setStart] = useState("09:00");
  const [end, setEnd] = useState("10:00");
  const [projectID, setProjectID] = useState("");
  const [notes, setNotes] = useState("");
  const [billingStatus, setBillingStatus] = useState("billable");
  const [estimatedMinutes, setEstimatedMinutes] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  useEffect(() => {
    if (!open) return;
    setTitle(timerMode ? "Focused work" : "");
    setStart("09:00");
    setEnd("10:00");
    setProjectID("");
    setNotes("");
    setBillingStatus("billable");
    setEstimatedMinutes("");
    setBusy(false);
    setMessage("");
  }, [dateKey, open, timerMode]);
  const selectRecent = (entry) => {
    setTitle(entry.title || "");
    setProjectID(resourceID(entry.project) || "");
    setNotes(entry.notes || "");
    setBillingStatus(entry.billing_status || "billable");
  };
  const updateProject = (value) => {
    setProjectID(value);
    const project = projects.find((item) => resourceID(item.id) === value);
    if (project) setBillingStatus(project.default_billing_status || "billable");
  };
  const submit = async () => {
    if (busy || !title.trim() || !api.connected) return;
    const startDate = localEntryDate(dateKey, start);
    const endDate = localEntryDate(dateKey, end);
    if (!timerMode && (!startDate || !endDate || new Date(endDate) <= new Date(startDate))) {
      setMessage("Enter a valid time range.");
      return;
    }
    setBusy(true);
    setMessage("");
    try {
      if (timerMode) {
        await api.startTimer(title.trim(), projectID ? resourceID(projectID) : undefined, { notes, billingStatus, estimatedMinutes: estimatedMinutes ? Number(estimatedMinutes) : undefined });
      } else {
        await api.addTimeEntry({ title: title.trim(), projectID: projectID ? resourceID(projectID) : undefined, notes, billingStatus, start: startDate, end: endDate });
      }
      onClose();
    } catch (error) {
      setMessage(error.message || `Could not ${timerMode ? "start the timer" : "save the time entry"}.`);
    } finally {
      setBusy(false);
    }
  };
  if (!open) return null;
  const recent = recentEntries.filter((entry) => !entry.is_running).slice(-5).reverse();
  return <div className="entry-omatic-backdrop" role="presentation" onClick={onClose}><section className="entry-omatic-dialog time-entry-dialog" role="dialog" aria-modal="true" aria-labelledby="time-entry-dialog-title" onClick={(event) => event.stopPropagation()}><header><div><span>{timerMode ? "Focus session" : "Manual time"}</span><h2 id="time-entry-dialog-title">{timerMode ? "Start Timer" : "New Time Entry"}</h2><p>{timerMode ? "The timer will capture activity until you stop it." : `Record a time entry for ${dateKey}.`}</p></div><IconButton label="Close time entry dialog" onClick={onClose}><X size={17} /></IconButton></header><div className="entry-omatic-form">{timerMode && recent.length > 0 ? <div className="time-entry-recent"><strong>Recent timers</strong>{recent.map((entry) => <button type="button" key={entry.id} onClick={() => selectRecent(entry)}><Clock size={14} /><span><b>{entry.title || "Untitled"}</b><small>{projectTitleFor(projects, entry.project)}</small></span></button>)}</div> : null}<label>{timerMode ? "What are you working on?" : "Time entry title"}<input value={title} onChange={(event) => setTitle(event.target.value)} placeholder={timerMode ? "Focused work" : "What did you work on?"} /></label>{!timerMode ? <div className="entry-omatic-options"><label>From<input type="time" value={start} onChange={(event) => setStart(event.target.value)} /></label><label>To<input type="time" value={end} onChange={(event) => setEnd(event.target.value)} /></label></div> : null}<label>Project<select value={projectID} onChange={(event) => updateProject(event.target.value)}><option value="">Unassigned</option>{projects.map((project) => <option value={resourceID(project.id)} key={project.id}>{project.title}</option>)}</select></label><label>Billing status<select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)}><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select></label>{timerMode ? <label>Estimated duration<select value={estimatedMinutes} onChange={(event) => setEstimatedMinutes(event.target.value)}><option value="">No estimate</option>{[15, 30, 45, 60, 90, 120, 180, 240].map((minutes) => <option value={minutes} key={minutes}>{minutes >= 60 ? `${Math.floor(minutes / 60)}h${minutes % 60 ? ` ${minutes % 60}m` : ""}` : `${minutes}m`}</option>)}</select></label> : null}<label>Notes (optional)<textarea value={notes} onChange={(event) => setNotes(event.target.value)} rows={2} /></label></div>{message ? <p className="entry-message" role="status">{message}</p> : null}<footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="button" className="primary-button" onClick={submit} disabled={busy || !api.connected || !title.trim()}>{busy ? "Saving…" : timerMode ? "Start Timer" : "Save Time Entry"}</button></footer></section></div>;
}

function ActivitiesPage({ api, dateKey, setDateKey }) {
  const [query, setQuery] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [deviceFilter, setDeviceFilter] = useState("all");
  const [projectFilterID, setProjectFilterID] = useState("all");
  const [savedFilterID, setSavedFilterID] = useState("all");
  const [activityView, setActivityView] = useState("unified");
  const [includeIdle, setIncludeIdle] = useState(false);
  const [groupByProject, setGroupByProject] = useState(false);
  const [groupByDevice, setGroupByDevice] = useState(false);
  const [displayMenuOpen, setDisplayMenuOpen] = useState(false);
  const [devicesMenuOpen, setDevicesMenuOpen] = useState(false);
  const [filtersMenuOpen, setFiltersMenuOpen] = useState(false);
  const [hideDevicesWithoutTime, setHideDevicesWithoutTime] = useState(false);
  const [selectedActivity, setSelectedActivity] = useState(null);
  const [timerBusy, setTimerBusy] = useState(false);
  const [timerMessage, setTimerMessage] = useState("");
  const [displayMessage, setDisplayMessage] = useState("");
  const [entryOMaticOpen, setEntryOMaticOpen] = useState(false);
  const [timeEntryDialogMode, setTimeEntryDialogMode] = useState(null);
  const timerRunning = Boolean(api.status?.timer);
  useEffect(() => {
    const preferences = api.activityPreferences;
    if (!preferences) return;
    setIncludeIdle(Boolean(preferences.include_idle));
    setGroupByProject(Boolean(preferences.group_by_project));
    setGroupByDevice(Boolean(preferences.group_by_device));
    setDeviceFilter(preferences.selected_device && preferences.selected_device !== "All Devices" ? preferences.selected_device : "all");
    if (preferences.activity_display_mode === "byCategory") setActivityView("category");
    else if (preferences.activity_display_mode === "chronological") setActivityView("chronological");
    else setActivityView("unified");
  }, [api.activityPreferences]);
  const currentActivities = [...api.activities].sort((left, right) => Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const useSevenDayRange = api.activityPreferences?.activity_time_range === "lastSevenDays";
  const rangeActivities = useSevenDayRange && api.weekly.length > 0
    ? api.weekly.flatMap((day) => (day.activities || []).map((activity) => ({ ...activity, date: day.date })))
    : currentActivities;
  const allActivities = [...rangeActivities].sort((left, right) => String(left.date || dateKey).localeCompare(String(right.date || dateKey)) || Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const devices = [...new Set([...currentActivities, ...rangeActivities].map((activity) => activity.deviceName || "This Mac"))].sort();
  const normalizedQuery = query.trim().toLowerCase();
  const savedFilter = api.filters.find((filter) => resourceID(filter.id) === savedFilterID);
  const filterActivity = (activity) => {
    const category = activityCategory(activity);
    const searchable = `${activityLabel(activity)} ${activityContext(activity)} ${activity.appName || ""} ${activity.deviceName || ""} ${category.label}`.toLowerCase();
    return (!normalizedQuery || searchable.includes(normalizedQuery))
      && (categoryFilter === "all" || category.key === categoryFilter)
      && (deviceFilter === "all" || (activity.deviceName || "This Mac") === deviceFilter)
      && (projectFilterID === "all" || (projectFilterID === "unassigned" ? !activity.projectID : resourceID(activity.projectID) === projectFilterID))
      && (!savedFilter || activityMatchesFilter(activity, savedFilter));
  };
  const recordedActivities = allActivities.filter((activity) => includeIdle || activityCategory(activity).key !== "idle");
  const activities = recordedActivities.filter(filterActivity);
  const timelineActivities = currentActivities.filter((activity) => (includeIdle || activityCategory(activity).key !== "idle") && filterActivity(activity));
  const hasFilters = Boolean(normalizedQuery || categoryFilter !== "all" || deviceFilter !== "all" || projectFilterID !== "all" || savedFilterID !== "all");
  const resetFilters = () => {
    setQuery("");
    setCategoryFilter("all");
    setDeviceFilter("all");
    setProjectFilterID("all");
    setSavedFilterID("all");
  };
  const selectProjectFilter = (value) => {
    setProjectFilterID(value);
    setSavedFilterID("all");
    setCategoryFilter("all");
  };
  const selectSavedFilter = (value) => {
    setSavedFilterID(value);
    setProjectFilterID("all");
    setCategoryFilter("all");
  };
  const saveDisplayPreferences = async (patch) => {
    if (!api.connected || !api.updateActivityPreferences) return;
    setDisplayMessage("");
    try {
      await api.updateActivityPreferences(patch);
    } catch (error) {
      setDisplayMessage(error.message || "Could not save activity display preferences.");
    }
  };
  const setViewMode = (mode) => {
    setActivityView(mode);
    void saveDisplayPreferences({ activity_display_mode: mode === "category" ? "byCategory" : mode });
  };
  const setIdleVisibility = (value) => {
    setIncludeIdle(value);
    void saveDisplayPreferences({ include_idle: value });
  };
  const setDeviceSelection = (value) => {
    setDeviceFilter(value === "All Devices" ? "all" : value);
    void saveDisplayPreferences({ selected_device: value });
    setDevicesMenuOpen(false);
  };
  const updateDisplayPreference = (patch) => {
    void saveDisplayPreferences(patch);
  };
  const setGrouping = (mode, value) => {
    if (mode === "project") {
      setGroupByProject(value);
      if (value) setGroupByDevice(false);
      void saveDisplayPreferences({ group_by_project: value, group_by_device: value ? false : groupByDevice });
      return;
    }
    setGroupByDevice(value);
    if (value) setGroupByProject(false);
    void saveDisplayPreferences({ group_by_device: value, group_by_project: value ? false : groupByProject });
  };
  const toggleTimer = async () => {
    if (timerBusy || !api.connected) return;
    setTimerBusy(true);
    setTimerMessage("");
    try {
      if (timerRunning) await api.stopTimer();
      else setTimeEntryDialogMode("timer");
    } catch (error) {
      setTimerMessage(error.message || "Could not update the timer.");
    } finally {
      setTimerBusy(false);
    }
  };
  const createGeneratedEntries = async (intervals, configuration) => {
    const generatedRanges = intervals.map((interval) => ({
      start: localEntryDateSeconds(dateKey, interval.startSecond),
      end: localEntryDateSeconds(dateKey, interval.endSecond),
    }));
    if (configuration.overwriteExisting) {
      const overlappingIDs = api.entries.filter((entry) => {
        const existing = entrySecondsForDate(entry, dateKey);
        return existing && intervals.some((interval) => existing.startSecond < interval.endSecond && existing.endSecond > interval.startSecond);
      }).map((entry) => entryID(entry));
      if (overlappingIDs.length > 0) await api.deleteTimeEntries(overlappingIDs);
    }
    await api.createTimeEntries(generatedRanges.map((range) => ({
      title: configuration.title,
      notes: configuration.notes,
      projectID: configuration.projectID ? resourceID(configuration.projectID) : undefined,
      billingStatus: configuration.billingStatus,
      start: range.start,
      end: range.end,
    })));
  };
  useEffect(() => setSelectedActivity(null), [dateKey]);
  return <main className="page supporting-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? `Native activity stream · ${planDateLabel(dateKey)}` : "Local preview"}</span><h1>Activities</h1></div><div className="activities-page-actions"><div className="date-controls"><DatePickerControl dateKey={dateKey} onChange={setDateKey} label="Choose Activities date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div><button type="button" className="quiet-pill" onClick={() => setTimeEntryDialogMode("new")} disabled={!api.connected}><Plus size={16} />New time entry</button><button type="button" className={`status-pill activities-timer ${timerRunning ? "active" : ""}`} onClick={toggleTimer} disabled={timerBusy || !api.connected}><Timer size={16} weight={timerRunning ? "fill" : "regular"} />{timerBusy ? "Updating…" : timerRunning ? "Stop timer" : "Start timer"}</button><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : "Refresh"}</button></div></header><div className="activities-page-toolbar"><div className="activity-view-switcher" role="group" aria-label="Activity view"><button type="button" className={activityView === "unified" ? "active" : ""} onClick={() => setViewMode("unified")}>Unified</button><button type="button" className={activityView === "category" ? "active" : ""} onClick={() => setViewMode("category")}>By Category</button><button type="button" className={activityView === "chronological" ? "active" : ""} onClick={() => setViewMode("chronological")}>Chronological</button></div><label className="activity-display-toggle"><input type="checkbox" checked={includeIdle} onChange={(event) => setIdleVisibility(event.target.checked)} />Show Idle</label><label className="activity-display-toggle"><input type="checkbox" checked={groupByProject} disabled={activityView !== "chronological"} onChange={(event) => setGrouping("project", event.target.checked)} />Group by project</label><label className="activity-display-toggle"><input type="checkbox" checked={groupByDevice} disabled={activityView !== "chronological"} onChange={(event) => setGrouping("device", event.target.checked)} />Group by device</label><WebActivityDisplayMenu open={displayMenuOpen} onToggle={() => setDisplayMenuOpen((value) => !value)} preferences={api.activityPreferences} devices={devices} onChange={updateDisplayPreference} /><label className="activity-search"><Waveform size={18} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search app, website, window title…" aria-label="Search activities" />{query ? <IconButton label="Clear activity search" onClick={() => setQuery("")}><X size={15} /></IconButton> : null}</label><WebActivityFiltersMenu open={filtersMenuOpen} filters={api.filters} projectFilterID={projectFilterID} savedFilterID={savedFilterID} categoryFilter={categoryFilter} onToggle={() => { setFiltersMenuOpen((value) => !value); setDevicesMenuOpen(false); }} onProjectFilter={(value) => { selectProjectFilter(value); setFiltersMenuOpen(false); }} onSavedFilter={(value) => { selectSavedFilter(value); setFiltersMenuOpen(false); }} onCategoryFilter={(value) => { setCategoryFilter(value); setFiltersMenuOpen(false); }} /><WebActivityDevicesMenu open={devicesMenuOpen} devices={devices} selectedDevice={deviceFilter} hideDevicesWithoutTime={hideDevicesWithoutTime} onToggle={() => { setDevicesMenuOpen((value) => !value); setFiltersMenuOpen(false); }} onSelect={setDeviceSelection} onToggleHide={setHideDevicesWithoutTime} /><button type="button" className="quiet-pill activity-reset" onClick={resetFilters} disabled={!hasFilters}>Reset</button></div>{timerMessage ? <p className="entry-message activities-timer-message" role="status">{timerMessage}</p> : null}{displayMessage ? <p className="entry-message activities-display-message" role="status">{displayMessage}</p> : null}<div className="activities-workspace"><WebActivityProjectSidebar projects={api.projects} filters={api.filters} activities={currentActivities} projectFilterID={projectFilterID} savedFilterID={savedFilterID} onProjectFilter={selectProjectFilter} onSavedFilter={selectSavedFilter} /><div className="activities-workspace-main"><WebActivityTimeline activities={timelineActivities} dateKey={dateKey} api={api} onSelect={setSelectedActivity} /><WebCalendarEventsPanel api={api} /><WebRemindersPanel api={api} /><WebPhoneCallsPanel api={api} /><WebScreenTimePanel api={api} /><WebActivityFiltersPanel api={api} /><WebActivityExclusionsPanel api={api} /><WebActivityCategoriesPanel api={api} /><section className="activities-list"><div className="activities-list-heading"><div><h2>Today’s activity</h2><p>{api.connected ? hasFilters ? `${activities.length} of ${allActivities.length} locally recorded segments` : `${activities.length} locally recorded segments` : "Start Metriday to see app, browser, and Screen Time activity here."}</p></div><div className="activities-list-heading-actions"><button type="button" className="quiet-pill" onClick={() => setEntryOMaticOpen(true)} disabled={!api.connected || timelineActivities.length === 0}><Sparkle size={16} />Create time entries</button><span className={`api-badge ${api.connected ? "online" : "offline"}`}>{api.connected ? "Connected" : "Offline"}</span></div></div>{activities.length === 0 ? <div className="activities-empty"><Waveform size={34} /><strong>{api.connected ? allActivities.length > 0 ? "No activity matches these filters" : "No activity recorded yet" : "Waiting for the native Metriday app"}</strong><span>{api.error || (hasFilters ? "Clear the filters to see all local activity." : "The hosted view keeps working with preview data until the loopback API is available.")}</span></div> : <ActivityTable activities={activities} viewMode={activityView} groupMode={activityView === "chronological" ? (groupByProject ? "project" : groupByDevice ? "device" : "none") : "none"} projects={api.projects} displayPreferences={api.activityPreferences} dateKey={dateKey} onSelect={setSelectedActivity} />}</section><ProjectPanel api={api} onAssignActivity={(id, projectID, activityDate) => api.assignActivity(id, projectID, activityDate || dateKey)} />{api.activityPreferences?.include_time_entries !== false ? <TimeEntriesPanel api={api} dateKey={dateKey} /> : null}</div></div>{selectedActivity ? <ActivityDetailDialog activity={selectedActivity} api={api} dateKey={dateKey} displayPreferences={api.activityPreferences} onClose={() => setSelectedActivity(null)} /> : null}<WebEntryOMaticDialog open={entryOMaticOpen} activities={timelineActivities} entries={api.entries} projects={api.projects} dateKey={dateKey} onClose={() => setEntryOMaticOpen(false)} onCreate={createGeneratedEntries} /><WebTimeEntryDialog mode={timeEntryDialogMode} open={Boolean(timeEntryDialogMode)} api={api} projects={api.projects} recentEntries={api.entries} dateKey={dateKey} onClose={() => setTimeEntryDialogMode(null)} /></main>;
}

function StatsPage({ api, dateKey, setDateKey }) {
  const days = api.weekly.slice(-7);
  const dayRows = days.map((day) => {
    const active = (day.activities || []).filter((activity) => activityCategory(activity).key !== "idle").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
    const focused = (day.activities || []).filter((activity) => activityCategory(activity).key === "focused").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
    return { date: day.date, label: new Date(`${day.date}T12:00:00`).toLocaleDateString(undefined, { weekday: "short" }), active, focused };
  });
  const totalActive = dayRows.reduce((total, day) => total + day.active, 0);
  const totalFocused = dayRows.reduce((total, day) => total + day.focused, 0);
  const segments = days.flatMap((day) => day.activities || []);
  const appRows = [...segments.reduce((groups, activity) => {
    if (activityCategory(activity).key === "idle") return groups;
    const key = activity.appName || activity.deviceName || "Unknown App";
    groups.set(key, (groups.get(key) || 0) + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)));
    return groups;
  }, new Map()).entries()].sort((left, right) => right[1] - left[1]).slice(0, 8);
  const projectRows = [...segments.reduce((groups, activity) => {
    if (activityCategory(activity).key === "idle") return groups;
    const key = projectTitleFor(api.projects, activity.projectID);
    groups.set(key, (groups.get(key) || 0) + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)));
    return groups;
  }, new Map()).entries()].sort((left, right) => right[1] - left[1]).slice(0, 8);
  const maxDay = Math.max(1, ...dayRows.map((day) => day.active));
  const maxApp = Math.max(1, ...appRows.map((row) => row[1]));
  const formatStat = (seconds) => formatDurationSeconds(seconds);
  return <main className="page supporting-page stats-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? "Native statistics · Last 7 days" : "Local preview"}</span><h1>Stats</h1></div><div className="activities-page-actions"><div className="date-controls"><DatePickerControl dateKey={dateKey} onChange={setDateKey} label="Choose Stats date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div><button className="quiet-pill" type="button" onClick={() => api.refresh()}>{api.loading ? "Connecting…" : "Refresh"}</button></div></header><section className="stats-summary"><div><Clock size={22} /><span>Total time</span><strong>{formatStat(totalActive)}</strong><small>Active app usage</small></div><div><ShieldCheck size={22} /><span>Productivity score</span><strong>{totalActive ? `${Math.round((totalFocused / totalActive) * 100)}%` : "—"}</strong><small>Weighted by category relevance</small></div><div><Timer size={22} /><span>Focused time</span><strong>{formatStat(totalFocused)}</strong><small>Focused category</small></div><div><TrendUp size={22} /><span>Segments</span><strong>{segments.length}</strong><small>Across the selected week</small></div></section><section className="stats-grid"><section className="stats-panel"><div className="chart-heading"><div><h2>Most active weekdays</h2><p>Active minutes from native activity evidence.</p></div></div><div className="stats-bars">{dayRows.map((day) => <div className="stats-bar-column" key={day.date}><div className="stats-bar-track"><i style={{ height: `${Math.max(3, (day.active / maxDay) * 100)}%` }} /></div><strong>{day.active ? formatStat(day.active) : "—"}</strong><span>{day.label}</span></div>)}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Time per Project</h2><p>Tracked activity grouped by assigned project.</p></div></div><div className="stats-ranking">{projectRows.length ? projectRows.map(([name, seconds]) => <div className="stats-ranking-row" key={name}><span>{name}</span><i><b style={{ width: `${Math.max(4, (seconds / Math.max(1, projectRows[0][1])) * 100)}%` }} /></i><strong>{formatStat(seconds)}</strong></div>) : <div className="entries-empty"><FolderSimple size={22} /><span>No project activity yet.</span></div>}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Most active applications</h2><p>Top App / website sources by captured time.</p></div></div><div className="stats-ranking">{appRows.length ? appRows.map(([name, seconds]) => <div className="stats-ranking-row" key={name}><span>{name}</span><i><b style={{ width: `${Math.max(4, (seconds / maxApp) * 100)}%` }} /></i><strong>{formatStat(seconds)}</strong></div>) : <div className="entries-empty"><Browsers size={22} /><span>No application activity yet.</span></div>}</div></section></section></main>;
}

function ReportsPage({ api, dateKey, setDateKey }) {
  return <main className="page supporting-page reports-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? "Native report builder" : "Local preview"}</span><h1>Reports</h1></div><div className="activities-page-actions"><div className="date-controls"><DatePickerControl dateKey={dateKey} onChange={setDateKey} label="Choose Reports date" /><button type="button" className="quiet-pill" onClick={() => setDateKey(localDateKey())}>Today</button><IconButton label="Previous day" onClick={() => setDateKey((value) => offsetDateKey(value, -1))}><CaretLeft size={18} /></IconButton><IconButton label="Next day" onClick={() => setDateKey((value) => offsetDateKey(value, 1))}><CaretRight size={18} /></IconButton></div></div><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : "Refresh"}</button></header><WebReportPanel api={api} dateKey={dateKey} /></main>;
}

function TeamsPage({ api }) {
  const [selectedTeamID, setSelectedTeamID] = useState("");
  const [newTeamName, setNewTeamName] = useState("");
  const [newMemberName, setNewMemberName] = useState("");
  const [newMemberEmail, setNewMemberEmail] = useState("");
  const [members, setMembers] = useState([]);
  const [message, setMessage] = useState("");
  const selectedTeam = api.teams.find((team) => resourceID(team.id) === selectedTeamID) || null;
  useEffect(() => {
    if (!selectedTeamID && api.teams[0]) setSelectedTeamID(resourceID(api.teams[0].id));
    if (selectedTeamID && !api.teams.some((team) => resourceID(team.id) === selectedTeamID)) setSelectedTeamID(api.teams[0] ? resourceID(api.teams[0].id) : "");
  }, [api.teams, selectedTeamID]);
  useEffect(() => {
    let current = true;
    if (!selectedTeamID || !api.connected) { setMembers([]); return () => { current = false; }; }
    api.fetchTeamMembers(selectedTeamID).then((result) => { if (current) setMembers(result); }).catch((error) => { if (current) setMessage(error.message || "Could not load team members."); });
    return () => { current = false; };
  }, [api.connected, api.refreshVersion, selectedTeamID]);
  const createTeam = async (event) => {
    event.preventDefault();
    if (!newTeamName.trim() || !api.connected) return;
    try { await api.createTeam({ name: newTeamName.trim() }); setNewTeamName(""); setMessage("Team created locally."); } catch (error) { setMessage(error.message || "Could not create the team."); }
  };
  const addMember = async (event) => {
    event.preventDefault();
    if (!selectedTeamID || !newMemberName.trim() || !api.connected) return;
    try { await api.addTeamMember(selectedTeamID, { name: newMemberName.trim(), email: newMemberEmail.trim() }); setNewMemberName(""); setNewMemberEmail(""); setMessage("Member added locally."); } catch (error) { setMessage(error.message || "Could not add the member."); }
  };
  const archiveTeam = async () => {
    if (!selectedTeam || !window.confirm(`Archive team “${selectedTeam.name}”?`)) return;
    try { await api.archiveTeam(selectedTeam.id); setMessage("Team archived."); } catch (error) { setMessage(error.message || "Could not archive the team."); }
  };
  return <main className="page supporting-page teams-page"><header className="supporting-header"><div><span>{api.connected ? "Native team workspace" : "Local preview"}</span><h1>Teams</h1></div></header><section className="teams-intro"><UsersThree size={28} /><div><h2>Team workspace</h2><p>Team data stays local or follows the selected Sync folder. Personal activity remains on each device.</p></div></section><form className="team-create-form" onSubmit={createTeam}><input value={newTeamName} onChange={(event) => setNewTeamName(event.target.value)} placeholder="New team name" aria-label="New team name" /><button type="submit" disabled={!api.connected || !newTeamName.trim()}><Plus size={16} />Create Team</button></form>{api.teams.length === 0 ? <section className="teams-empty"><UsersThree size={30} /><strong>No team yet</strong><span>Create a local team to associate projects and invite members.</span></section> : <section className="teams-layout"><div className="teams-list"><h2>Your Teams</h2>{api.teams.map((team) => <button type="button" key={team.id} className={resourceID(team.id) === selectedTeamID ? "active" : ""} onClick={() => setSelectedTeamID(resourceID(team.id))}><UsersThree size={18} /><span><strong>{team.name}</strong><small>{team.members_count || 0} members</small></span>{resourceID(team.id) === selectedTeamID ? <Check size={15} /> : null}</button>)}</div><section className="team-detail">{selectedTeam ? <><header><div><h2>{selectedTeam.name}</h2><p>{selectedTeam.members_count || members.length} members · {api.projects.filter((project) => resourceID(project.team_id) === resourceID(selectedTeam.id)).length} projects</p></div><button type="button" className="quiet-pill danger-pill" onClick={archiveTeam}>Archive</button></header><form className="team-member-form" onSubmit={addMember}><input value={newMemberName} onChange={(event) => setNewMemberName(event.target.value)} placeholder="Name" aria-label="New team member name" /><input value={newMemberEmail} onChange={(event) => setNewMemberEmail(event.target.value)} placeholder="Email (optional)" aria-label="New team member email" /><button type="submit" disabled={!api.connected || !newMemberName.trim()}>Add</button></form><div className="team-members">{members.map((member) => <div key={member.id}><UsersThree size={17} /><strong>{member.name}</strong>{member.email ? <span>{member.email}</span> : null}<small>{member.role}</small></div>)}</div><div className="team-tracked">Aggregate tracked · {formatDurationSeconds(Number(selectedTeam.tracked_seconds || 0))}</div></> : <div className="entries-empty"><UsersThree size={24} /><span>Select a team.</span></div>}</section></section>}{message ? <p className="entry-message" role="status">{message}</p> : null}</main>;
}

function RulesPage() {
  const [locked, setLocked] = useState(true); const [blocked, setBlocked] = useState(["youtube.com", "x.com", "reddit.com"]); const [allowed, setAllowed] = useState(["arxiv.org", "github.com", "pytorch.org"]); const [draft, setDraft] = useState("");
  return <main className="page supporting-page rules-page"><header className="supporting-header"><div><span>Focus rules</span><h1>Research Focus</h1></div><button type="button" className={`status-pill ${locked ? "active" : ""}`} onClick={() => setLocked((value) => !value)}><LockSimple size={17} />{locked ? "Locked mode on" : "Flexible mode"}</button></header><div className="rules-layout"><section className="rule-overview"><ShieldCheck size={54} color="#3da65a" weight="duotone" /><h2>Protect deep-work blocks</h2><p>This rule starts with scheduled research tasks and stays local to this Mac.</p><div className="rule-meta"><span><Clock size={18} />Runs with calendar blocks</span><span><Laptop size={18} />Local processing</span><span><Browsers size={18} />All browsers</span></div></section><section className="site-list-section"><div className="site-list-heading"><div><h2>Blocked sites</h2><p>Attempts are recorded as distraction evidence.</p></div><strong>{blocked.length}</strong></div><div className="site-list">{blocked.map((site) => <div key={site}><GlobeSimple size={20} /><span>{site}</span><IconButton label={`Allow ${site}`} onClick={() => { setBlocked((items) => items.filter((item) => item !== site)); setAllowed((items) => [...items, site]); }}><X size={15} /></IconButton></div>)}</div><form onSubmit={(event) => { event.preventDefault(); if (draft.trim() && !blocked.includes(draft.trim())) setBlocked((items) => [...items, draft.trim()]); setDraft(""); }}><GlobeSimple size={19} /><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a distracting domain" aria-label="Add blocked website" /><button type="submit"><Plus size={17} />Add</button></form></section><section className="site-list-section allowed-section"><div className="site-list-heading"><div><h2>Allowed research</h2><p>Always available inside this focus rule.</p></div><strong>{allowed.length}</strong></div><div className="site-list">{allowed.map((site) => <div key={site}><CheckCircle size={20} weight="fill" /><span>{site}</span></div>)}</div></section></div></main>;
}

function WebProjectRulesPanel({ api }) {
  const [projectID, setProjectID] = useState("");
  const [field, setField] = useState("application");
  const [comparison, setComparison] = useState("contains");
  const [pattern, setPattern] = useState("");
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", titleContains: "Title contains", resourceContains: "URL or path contains", domain: "Domain", fullURL: "Full website URL", keyword: "Keyword", startTime: "Start time", dayOfWeek: "Day of week" };
  const projects = api.projects || [];
  const submit = async (event) => {
    event.preventDefault();
    if (!projectID || !pattern.trim() || !api.connected) return;
    try {
      await api.createProjectRule({ project_id: projectID, field, comparison, pattern: pattern.trim(), case_sensitive: false });
      setPattern("");
    } catch (error) {
      // Keep the form available while the shared API connection state recovers.
    }
  };
  return <section className="project-rules-panel"><div className="project-rules-heading"><div><h2>Project automation rules</h2><p>Assign future App, title, domain, URL, or keyword activity to a project.</p></div><span className="api-badge">{api.projectRules.length} saved</span></div><form className="project-rules-form" onSubmit={submit}><select value={projectID} onChange={(event) => setProjectID(event.target.value)} aria-label="Project rule project"><option value="">Choose project</option>{projects.map((project) => <option key={project.id} value={resourceID(project.id)}>{project.title || project.name}</option>)}</select><select value={field} onChange={(event) => setField(event.target.value)} aria-label="Project rule field">{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={comparison} onChange={(event) => setComparison(event.target.value)} aria-label="Project rule comparison"><option value="contains">contains</option><option value="equals">is</option><option value="beginsWith">begins with</option><option value="endsWith">ends with</option><option value="like">is like</option><option value="matchesRegex">matches regex</option></select><input value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="Matching value" aria-label="Project rule value" /><button type="submit" disabled={!api.connected || !projectID || !pattern.trim()}><Plus size={16} />Add Rule</button></form>{api.projectRules.length > 0 ? <div className="project-rules-list">{api.projectRules.map((rule, index) => <div className="project-rule-row" key={rule.id}><span className="web-source-icon"><Sparkle size={17} /></span><div><strong>{rule.project_name || projectTitleFor(projects, rule.project_id)}</strong><small>{fields[rule.field] || rule.field} {rule.comparison} “{rule.pattern}”</small></div><span className="project-rule-order"><IconButton label="Move rule up" onClick={() => api.moveProjectRule(rule.id, -1)} disabled={index === 0}><CaretLeft size={15} className="rotate-up" /></IconButton><IconButton label="Move rule down" onClick={() => api.moveProjectRule(rule.id, 1)} disabled={index === api.projectRules.length - 1}><CaretRight size={15} className="rotate-down" /></IconButton></span><IconButton label={`Delete rule for ${rule.project_name || "project"}`} onClick={() => api.deleteProjectRule(rule.id)}><Trash size={15} /></IconButton></div>)}</div> : <div className="project-rules-empty"><Sparkle size={22} /><span>No project automation rules yet. Assign an activity in Activities, then save its matching pattern here.</span></div>}</section>;
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
  return <main className="page supporting-page rules-page"><header className="supporting-header"><div><span>{api.connected ? "Native Focus rules" : "Focus rules"}</span><h1>Research Focus</h1></div><button type="button" className={`status-pill ${focusActive ? "active" : ""}`} onClick={toggleFocus}><LockSimple size={17} />{focusActive ? "Locked mode on" : "Flexible mode"}</button></header><div className="rules-layout"><section className="rule-overview"><ShieldCheck size={54} color="#3da65a" weight="duotone" /><h2>Protect deep-work blocks</h2><p>{api.connected ? "Changes are saved to the native Metriday blocklist on this Mac." : "This rule starts with scheduled research tasks and stays local to this Mac."}</p><div className="rule-meta"><span><Clock size={18} />Runs with calendar blocks</span><span><Laptop size={18} />Local processing</span><span><Browsers size={18} />Safari + Chrome</span></div></section><section className="site-list-section"><div className="site-list-heading"><div><h2>Blocked sites</h2><p>Attempts are recorded as distraction evidence.</p></div><strong>{blockedItems.length}</strong></div><div className="site-list">{blockedItems.map((item) => <div key={item.id}><GlobeSimple size={20} /><span>{item.domain}</span><IconButton label={`Allow ${item.domain}`} onClick={() => allowDomain(item)}><X size={15} /></IconButton></div>)}</div><form onSubmit={addDomain}><GlobeSimple size={19} /><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a distracting domain" aria-label="Add blocked website" /><button type="submit"><Plus size={17} />Add</button></form></section><section className="site-list-section allowed-section"><div className="site-list-heading"><div><h2>Allowed research</h2><p>Always available inside this focus rule.</p></div><strong>{allowedItems.length}</strong></div><div className="site-list">{allowedItems.map((item) => <div key={item.id}><CheckCircle size={20} weight="fill" /><span>{item.domain}</span><IconButton label={`Remove ${item.domain}`} onClick={() => removeDomain(item)}><X size={15} /></IconButton></div>)}</div></section></div><WebProjectRulesPanel api={api} />{message ? <p className="entry-message rules-message" role="status">{message}</p> : null}</main>;
}

export function App() {
  const [page, setPage] = useState("today");
  const [dateKey, setDateKey] = useState(localDateKey());
  const [tasks, setTasks] = useState(initialTasks);
  const [apiBase, setApiBase] = useState(apiBaseURL);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const api = useMetridayAPI(dateKey, apiBase);
  const content = useMemo(() => page === "plan" ? <PlanPage tasks={tasks} setTasks={setTasks} api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "activities" ? <ActivitiesPage api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "stats" ? <StatsPage api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "reports" ? <ReportsPage api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "teams" ? <TeamsPage api={api} /> : page === "review" ? <ReviewPage api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "rules" ? <RulesPageLive api={api} /> : <TodayPage setPage={setPage} api={api} dateKey={dateKey} setDateKey={setDateKey} />, [api, page, tasks, dateKey]);
  return <div className="app-shell"><Sidebar page={page} setPage={setPage} api={api} onOpenSettings={() => setSettingsOpen(true)} /><div className="app-main"><WebGlobalHeader api={api} setPage={setPage} dateKey={dateKey} setDateKey={setDateKey} />{content}</div><ConnectionSettings open={settingsOpen} api={api} apiBase={apiBase} connected={api.connected} onSave={setApiBase} onClose={() => setSettingsOpen(false)} /></div>;
}
