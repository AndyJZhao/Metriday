import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowsClockwise, BookOpen, Browsers, CalendarBlank, CaretDown, CaretLeft, CaretRight,
  ChartBar, Check, CheckCircle, Clock, Code, DotsSixVertical, DotsThree,
  FileText, Flask, FolderSimple, GearSix, GlobeSimple, Laptop, LinkSimple,
  LockSimple, NotePencil, Pause, Play, Plus, ShieldCheck, Sparkle, TerminalWindow,
  Timer, Trash, TrendUp, UsersThree, Waveform, X, SlidersHorizontal, ShareNetwork,
} from "@phosphor-icons/react";
import {
  SiArc, SiArxiv, SiBilibili, SiBrave, SiChatbot, SiChromewebstore, SiDiscord,
  SiFigma, SiFirefox, SiGmail, SiGooglechrome, SiIterm2, SiLinear, SiNotion,
  SiSafari, SiSteam, SiVscodium, SiWechat, SiXcode, SiYoutube,
} from "@icons-pack/react-simple-icons";

const VSCodeLogo = ({ weight: _weight, ...props }) => <SiVscodium {...props} color="#1683d8" />;
const ArxivLogo = ({ weight: _weight, ...props }) => <SiArxiv {...props} color="#b31b1b" />;
const YouTubeLogo = ({ weight: _weight, ...props }) => <SiYoutube {...props} color="#ff0033" />;
const ChatGPTLogo = ({ weight: _weight, ...props }) => <SiChatbot {...props} color="#10a37f" />;
const ChromeLogo = ({ weight: _weight, ...props }) => <SiGooglechrome {...props} color="#4285f4" />;
const SafariLogo = ({ weight: _weight, ...props }) => <SiSafari {...props} color="#0a84ff" />;
const BraveLogo = ({ weight: _weight, ...props }) => <SiBrave {...props} color="#fb542b" />;
const FirefoxLogo = ({ weight: _weight, ...props }) => <SiFirefox {...props} color="#ff7139" />;
const ArcLogo = ({ weight: _weight, ...props }) => <SiArc {...props} color="#6d5dfc" />;
const LinearLogo = ({ weight: _weight, ...props }) => <SiLinear {...props} color="#5e6ad2" />;
const WeChatLogo = ({ weight: _weight, ...props }) => <SiWechat {...props} color="#07c160" />;
const BilibiliLogo = ({ weight: _weight, ...props }) => <SiBilibili {...props} color="#00aeec" />;
const SteamLogo = ({ weight: _weight, ...props }) => <SiSteam {...props} color="#1b2838" />;
const NotionLogo = ({ weight: _weight, ...props }) => <SiNotion {...props} color="#111111" />;
const FigmaLogo = ({ weight: _weight, ...props }) => <SiFigma {...props} color="#f24e1e" />;
const XcodeLogo = ({ weight: _weight, ...props }) => <SiXcode {...props} color="#147efb" />;
const ItermLogo = ({ weight: _weight, ...props }) => <SiIterm2 {...props} color="#2d2d2d" />;
const GmailLogo = ({ weight: _weight, ...props }) => <SiGmail {...props} color="#ea4335" />;
const DiscordLogo = ({ weight: _weight, ...props }) => <SiDiscord {...props} color="#5865f2" />;
const ChromeWebStoreLogo = ({ weight: _weight, ...props }) => <SiChromewebstore {...props} color="#4285f4" />;

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

const activityBuiltinFilters = [
  { key: "webBrowsing", label: "Web Browsing", terms: ["safari", "chrome", "firefox", "brave", "arc", "edge", "opera", "vivaldi", "browser"] },
  { key: "media", label: "Media", terms: ["music", "spotify", "podcast", "tv", "youtube", "netflix", "vlc", "video", "plex", "twitch"] },
  { key: "communication", label: "Communication", terms: ["slack", "messages", "mail", "outlook", "teams", "zoom", "discord", "wechat", "telegram", "signal", "skype", "whatsapp"] },
  { key: "officeBusiness", label: "Office & Business", terms: ["word", "excel", "powerpoint", "keynote", "numbers", "notion", "linear", "clickup", "asana", "office", "spreadsheet", "invoice", "salesforce"] },
  { key: "readingWriting", label: "Reading & Writing", terms: ["books", "kindle", "reader", "preview", "notes", "textedit", "ulysses", "ia writer", "obsidian", "scrivener", "writer", "medium", "wikipedia"] },
  { key: "fileManagement", label: "File Management", terms: ["finder", "file manager", "path finder", "transmit", "dropbox", "google drive", "onedrive", "files", "folder"] },
  { key: "graphics", label: "Graphics", terms: ["figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator", "blender", "design", "paint", "canva"] },
  { key: "development", label: "Development", terms: ["xcode", "terminal", "iterm", "visual studio", "code", "cursor", "sublime", "intellij", "pycharm", "android studio", "git", "github", "developer", "console"] },
  { key: "finance", label: "Finance", terms: ["bank", "finance", "budget", "money", "mint", "quickbooks", "coinbase", "paypal", "stripe", "invoice", "accounting", "trading"] },
  { key: "gaming", label: "Gaming", terms: ["steam", "game", "gaming", "epic games", "battle.net", "minecraft", "playstation", "xbox", "roblox"] },
  { key: "socialMedia", label: "Social Media", terms: ["facebook", "instagram", "twitter", "x.com", "reddit", "linkedin", "tiktok", "mastodon", "social", "threads", "snapchat", "pinterest"] },
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

function weekStartDateKey(dateKey) {
  const date = new Date(`${dateKey}T12:00:00`);
  if (Number.isNaN(date.getTime())) return dateKey;
  const day = date.getDay();
  date.setDate(date.getDate() - (day === 0 ? 6 : day - 1));
  return localDateKey(date);
}

function statsPeriodLabel(period) {
  switch (period) {
  case "day": return "Today";
  case "yesterday": return "Yesterday";
  case "week": return "This Week";
  case "lastWeek": return "Last Week";
  case "month": return "This Month";
  case "lastMonth": return "Last Month";
  case "year": return "This Year";
  case "lastYear": return "Last Year";
  case "custom": return "Custom Range";
  default: return "This Week";
  }
}

function statsRangeBounds(dateKey, period, customStartDate = dateKey, customEndDate = dateKey) {
  const date = new Date(`${dateKey}T12:00:00`);
  if (Number.isNaN(date.getTime())) return { start: dateKey, end: dateKey };
  if (period === "custom") {
    const start = new Date(`${customStartDate}T12:00:00`);
    const end = new Date(`${customEndDate}T12:00:00`);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return { start: dateKey, end: dateKey };
    return start <= end
      ? { start: localDateKey(start), end: localDateKey(end) }
      : { start: localDateKey(end), end: localDateKey(start) };
  }
  const year = date.getFullYear();
  const month = date.getMonth();
  if (period === "day") {
    return { start: dateKey, end: dateKey };
  }
  if (period === "yesterday") {
    const yesterday = offsetDateKey(dateKey, -1);
    return { start: yesterday, end: yesterday };
  }
  if (period === "year") {
    return { start: `${year}-01-01`, end: `${year}-12-31` };
  }
  if (period === "lastYear") {
    const previousYear = year - 1;
    return { start: `${previousYear}-01-01`, end: `${previousYear}-12-31` };
  }
  if (period === "month") {
    const start = new Date(year, month, 1, 12, 0, 0);
    const end = new Date(year, month + 1, 0, 12, 0, 0);
    return { start: localDateKey(start), end: localDateKey(end) };
  }
  if (period === "lastMonth") {
    const start = new Date(year, month - 1, 1, 12, 0, 0);
    const end = new Date(year, month, 0, 12, 0, 0);
    return { start: localDateKey(start), end: localDateKey(end) };
  }
  const start = weekStartDateKey(dateKey);
  if (period === "lastWeek") {
    const previousStart = offsetDateKey(start, -7);
    return { start: previousStart, end: offsetDateKey(previousStart, 6) };
  }
  return { start, end: offsetDateKey(start, 6) };
}

function activityRangeBounds(dateKey, range) {
  if (range === "lastThirtyDays") {
    return { start: offsetDateKey(dateKey, -29), end: dateKey };
  }
  if (range === "lastNinetyDays") {
    return { start: offsetDateKey(dateKey, -89), end: dateKey };
  }
  return { start: dateKey, end: dateKey };
}

function activityTimeRangeLabel(range) {
  switch (range) {
  case "lastSevenDays": return "Last 7 days";
  case "lastThirtyDays": return "Last 30 days";
  case "lastNinetyDays": return "Last 90 days";
  default: return "Selected day";
  }
}

function dateKeysBetween(startDate, endDate) {
  const keys = [];
  for (let offset = 0; offset < 420; offset += 1) {
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
    sourcePreferences: null,
    weekly: [],
    calendarWeekly: [],
    insights: [],
  });

  const request = useCallback((path, options = {}) => apiRequest(path, options, apiBase), [apiBase]);

  const refresh = useCallback(async () => {
    const date = dateKey || localDateKey();
    const weekKeys = Array.from({ length: 7 }, (_, index) => offsetDateKey(date, index - 6));
    const calendarWeekKeys = Array.from({ length: 7 }, (_, index) => offsetDateKey(weekStartDateKey(date), index));
    const loadWeek = (keys, options = {}) => Promise.all(keys.map(async (weekDate) => {
      const overlapEntries = Boolean(options.overlapEntries);
      const [activityResult, planResult, entryResult] = await Promise.allSettled([
        request(`/v1/activities?date=${weekDate}`),
        request(`/v1/plans?date=${weekDate}`),
        request(`/api/v1/time-entries?start_date_min=${overlapEntries ? offsetDateKey(weekDate, -1) : weekDate}&start_date_max=${weekDate}`),
      ]);
      const rawEntries = entryResult.status === "fulfilled" ? entryResult.value?.data || [] : [];
      const entries = overlapEntries
        ? rawEntries.map((entry) => {
          const range = entrySecondsForDate(entry, weekDate);
          if (!range) return null;
          return {
            ...entry,
            start_date: localEntryDateSeconds(weekDate, range.startSecond),
            end_date: localEntryDateSeconds(weekDate, range.endSecond),
            duration: range.endSecond - range.startSecond,
          };
        }).filter(Boolean)
        : rawEntries;
      return {
        date: weekDate,
        activities: activityResult.status === "fulfilled" && Array.isArray(activityResult.value) ? activityResult.value : [],
        plan: planResult.status === "fulfilled" ? planResult.value : null,
        entries,
      };
    }));
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
        loadWeek(weekKeys, { overlapEntries: true }),
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
        request("/v1/source-preferences"),
        loadWeek(calendarWeekKeys, { overlapEntries: true }),
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
        sourcePreferences: value(20, null),
        calendarWeekly: value(21, []),
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
    const [activityResults, entryResult] = await Promise.all([
      Promise.all(activityDates.map(async (day) => ({ day, items: await request(`/v1/activities?date=${day}`) }))),
      request(`/api/v1/time-entries?start_date_min=${offsetDateKey(startDate, -1)}&start_date_max=${endDate}`),
    ]);
    return {
      activities: activityResults.flatMap(({ day, items }) => Array.isArray(items) ? items.map((item) => ({ ...item, date: day })) : []),
      entries: entryResult?.data || [],
      startDate,
      endDate,
    };
  }, [request]);

  const fetchPlan = useCallback((date = localDateKey()) => request(`/v1/plans?date=${date}`), [request]);
  const fetchProjects = useCallback((includeArchived = false) => request(`/api/v1/projects${includeArchived ? "?include_archived=true" : ""}`), [request]);

  return {
    ...snapshot,
    refreshVersion,
    refresh,
    fetchRange,
    fetchPlan,
    fetchProjects,
    downloadReportFile: async ({ startDate, endDate, format, include, groupBy, billingFilter, rounding, roundingMinutes, projectIDs = [], durationFormat = "decimalMinutes", includeShortEntries = true, includeCoveredAppUsage = false, roundIndividualEntries = true, columns = [] }) => {
      const params = new URLSearchParams({ start_date: startDate, end_date: endDate, format, include, group_by: groupBy, billing_status: billingFilter, rounding, rounding_minutes: String(roundingMinutes), duration_format: durationFormat, include_short_entries: String(includeShortEntries), include_covered_app_usage: String(includeCoveredAppUsage), round_individual_entries: String(roundIndividualEntries), device: snapshot.activityPreferences?.selected_device || "All Devices" });
      if (projectIDs.length > 0) params.set("project_ids", projectIDs.join(","));
      if (columns.length > 0) params.set("columns", columns.join(","));
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
    alignTimer: () => mutate("/v1/timer/adjust", { align_previous_entry: true }),
    adjustTimerEstimate: (minutes) => mutate("/v1/timer/estimate", { deltaSeconds: Number(minutes) * 60 }),
    toggleTracking: () => mutate(snapshot.status?.tracking ? "/v1/tracking/pause" : "/v1/tracking/resume"),
    updatePreferences: async (preferences) => {
      await request("/v1/preferences", { method: "PATCH", body: JSON.stringify(preferences) });
      await refresh();
    },
    updateActivityPreferences: async (preferences) => {
      await request("/v1/activity-preferences", { method: "PATCH", body: JSON.stringify(preferences) });
      await refresh();
    },
    updateSourcePreferences: async (preferences) => {
      await request("/v1/source-preferences", { method: "PATCH", body: JSON.stringify(preferences) });
      await refresh();
    },
    requestSourceAccess: async (source) => {
      await request("/v1/source-preferences/access", { method: "POST", body: JSON.stringify({ source }) });
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
      const created = [];
      const splitFragments = [];
      for (const entry of entries) {
        const result = await request("/v1/time-entries", { method: "POST", body: JSON.stringify(entry) });
        if (result?.data) created.push(result.data);
        if (Array.isArray(result?.split_fragments)) splitFragments.push(...result.split_fragments);
      }
      await refresh();
      return { createdEntries: created, splitFragments };
    },
    restoreTimeEntries: async (entries) => {
      for (const entry of entries) {
        await request("/v1/time-entries", {
          method: "POST",
          body: JSON.stringify({
            title: entry.title || "Untitled",
            notes: entry.notes || "",
            projectID: resourceID(entry.project) || resourceID(entry.projectID) || undefined,
            billingStatus: entry.billing_status || entry.billingStatus || "billable",
            start: entry.start_date || entry.start,
            end: entry.end_date || entry.end,
            custom_fields: entry.custom_fields || {},
          }),
        });
      }
      await refresh();
    },
    updateTimeEntry: async (id, entry) => {
      const result = await request(`/api/v1/time-entries/${resourceID(id)}`, { method: "PATCH", body: JSON.stringify(entry) });
      await refresh();
      return result;
    },
    batchUpdateTimeEntries: async (ids, billingStatus) => {
      await request("/api/v1/time-entries/batch-update", {
        method: "PATCH",
        body: JSON.stringify({
          time_entries: ids.map((id) => resourceID(id)),
          data: { billing_status: billingStatus },
        }),
      });
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
      const result = await request("/api/v1/projects", { method: "POST", body: JSON.stringify(project) });
      await refresh();
      return result?.data || result;
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
    showAllPhoneCallAddresses: async () => {
      await request("/v1/phone-calls/hide-all", { method: "POST" });
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
    reapplyProjectRules: async (date = dateKey || localDateKey()) => {
      const result = await request("/v1/project-rules/reapply", { method: "POST", body: JSON.stringify({ date }) });
      await refresh();
      return result;
    },
    reapplyAllProjectRules: async () => {
      const result = await request("/v1/project-rules/reapply-all", { method: "POST" });
      await refresh();
      return result;
    },
    savePlan: async (markdown, date = dateKey || localDateKey()) => {
      await request(`/v1/plans?date=${date}`, { method: "PUT", body: JSON.stringify({ markdown }) });
      await refresh();
    },
    createCalendarEvent: async (event) => {
      const result = await request("/v1/calendar-events", { method: "POST", body: JSON.stringify(event) });
      await refresh();
      return result;
    },
    updateCalendarEvent: async (id, event) => {
      const result = await request(`/v1/calendar-events/${encodeURIComponent(resourceID(id))}`, { method: "PATCH", body: JSON.stringify(event) });
      await refresh();
      return result;
    },
    deleteCalendarEvent: async (id, date = dateKey || localDateKey()) => {
      const result = await request(`/v1/calendar-events/${encodeURIComponent(resourceID(id))}?date=${date}`, { method: "DELETE" });
      await refresh();
      return result;
    },
    assignActivity: async (id, projectID, date = dateKey || localDateKey()) => {
      await request(`/v1/activities/${resourceID(id)}?date=${date}`, { method: "PATCH", body: JSON.stringify({ projectID: projectID || null }) });
      await refresh();
    },
    deleteActivity: async (id, date = dateKey || localDateKey()) => {
      const result = await request(`/v1/activities/${resourceID(id)}?date=${date}`, { method: "DELETE" });
      await refresh();
      return result;
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

function taskMinuteRange(task) {
  const start = Number(task?.startMinute ?? task?.start_minute);
  const end = Number(task?.endMinute ?? task?.end_minute);
  return Number.isFinite(start) && Number.isFinite(end) ? { start, end } : null;
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

function activityDisplayTitle(activity) {
  const app = activity.appName || activity.deviceName || "Activity";
  const title = String(activity.windowTitle || "").trim();
  if (title && title.toLowerCase() !== app.toLowerCase()) return `${app} · ${title}`;
  try {
    const host = new URL(activity.resource || "").host;
    if (host) return `${app} · ${host}`;
  } catch {
    // Keep the application name when the captured resource is not a URL.
  }
  return app;
}

function activityIcon(activity) {
  const bundle = String(activity.bundleIdentifier || "").toLowerCase();
  const app = String(activity.appName || "").toLowerCase();
  const resource = String(activity.resource || "").toLowerCase();
  const haystack = `${app} ${bundle} ${resource}`;
  if (bundle.includes("vscode") || app.includes("visual studio code") || app === "code" || app.includes("vscodium")) return VSCodeLogo;
  if (bundle.includes("xcode") || app === "xcode") return XcodeLogo;
  if (bundle.includes("iterm") || app.includes("iterm")) return ItermLogo;
  if (bundle.includes("terminal") || app === "terminal") return TerminalWindow;
  if (bundle.includes("safari") || app.includes("safari")) return SafariLogo;
  if (bundle.includes("chrome") || app.includes("google chrome") || app === "chrome") return ChromeLogo;
  if (bundle.includes("brave") || app.includes("brave")) return BraveLogo;
  if (bundle.includes("firefox") || app.includes("firefox")) return FirefoxLogo;
  if (bundle.includes("arc") || app === "arc") return ArcLogo;
  if (haystack.includes("linear.app") || app === "linear") return LinearLogo;
  if (app.includes("wechat") || app.includes("weixin")) return WeChatLogo;
  if (app.includes("bilibili") || resource.includes("bilibili.com")) return BilibiliLogo;
  if (app.includes("steam")) return SteamLogo;
  if (app.includes("notion")) return NotionLogo;
  if (app.includes("figma")) return FigmaLogo;
  if (app.includes("chatgpt") || app.includes("openai")) return ChatGPTLogo;
  if (app.includes("gmail") || resource.includes("mail.google.com")) return GmailLogo;
  if (app.includes("discord")) return DiscordLogo;
  if (app.includes("chrome web store")) return ChromeWebStoreLogo;
  if (app.includes("youtube")) return YouTubeLogo;
  if (app.includes("arxiv")) return ArxivLogo;
  if (resource.startsWith("http://") || resource.startsWith("https://") || app.includes("browser")) return Browsers;
  return Browsers;
}

function activityFilePath(resource) {
  const value = String(resource || "").trim();
  if (!value) return "";
  try {
    const parsed = new URL(value);
    if (parsed.protocol === "file:") return decodeURIComponent(parsed.pathname);
    if (parsed.host) return "";
  } catch {
    // Raw local paths are valid activity resources too.
  }
  return value.replace(/^file:\/\//, "");
}

function pathGroupingNames(resource, displayPreferences = null) {
  const filePath = activityFilePath(resource);
  if (!filePath) return [];
  const grouping = displayPreferences?.group_paths_by || "allDirectories";
  const normalized = filePath.replace(/\\+/g, "/").replace(/\/\.\//g, "/").replace(/\/+/g, "/");
  if (grouping === "filePathOnly") return [normalized];
  const lastSlash = normalized.lastIndexOf("/");
  const immediateParent = lastSlash > 0 ? normalized.slice(0, lastSlash) : "/";
  if (grouping === "immediateParentDirectory") return [immediateParent];
  const names = [];
  let current = immediateParent;
  while (current && current !== "/") {
    names.push(current);
    const parentSlash = current.lastIndexOf("/");
    const parent = parentSlash > 0 ? current.slice(0, parentSlash) : "/";
    if (parent === current) break;
    current = parent;
  }
  return names;
}

function activityApplicationGroupNames(activity, displayPreferences = null) {
  const resource = String(activity?.resource || "").trim();
  if (displayPreferences?.group_websites_independently && resource) {
    try {
      const host = new URL(resource).host;
      if (host) return [host];
    } catch {
      // Continue with the normal application grouping.
    }
  }
  if (displayPreferences?.group_paths_independently && resource) {
    const names = pathGroupingNames(resource, displayPreferences);
    if (names.length) return names;
  }
  return [activity?.appName || activity?.deviceName || "Unknown App"];
}

function activityCategory(activity) {
  const categoryRole = String(activity?.categoryRole || "").toLowerCase();
  if (["focused", "distracting", "other", "idle"].includes(categoryRole)) {
    const color = categoryRole === "focused"
      ? "blue"
      : categoryRole === "distracting"
      ? "red"
      : activity.categoryColor || categoryRoleColor(categoryRole);
    return { key: categoryRole, label: activity.categoryName || categoryRole[0].toUpperCase() + categoryRole.slice(1), color };
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

function activityMatchesSelectedDevice(activity, selectedDevice) {
  const selected = String(selectedDevice || "All Devices");
  return selected === "All Devices" || selected === "all" || String(activity?.deviceName || "This Mac") === selected;
}

function categoryRoleColor(role) {
  return ["focused", "related", "current"].includes(role) ? "blue" : ["distracting", "distracted"].includes(role) ? "red" : "graphite";
}

function activityMatchesBuiltinFilter(activity, key) {
  const filter = activityBuiltinFilters.find((item) => item.key === key);
  if (!filter) return true;
  const app = String(activity?.appName || "").toLowerCase();
  const bundle = String(activity?.bundleIdentifier || "").toLowerCase();
  const title = String(activity?.windowTitle || "").toLowerCase();
  const resource = String(activity?.resource || "").toLowerCase();
  const haystack = `${app} ${bundle} ${title} ${resource}`;
  if (key === "webBrowsing") {
    try {
      if (new URL(activity?.resource || "").host) return true;
    } catch {
      // Fall back to browser application names below.
    }
  }
  return filter.terms.some((term) => haystack.includes(term));
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

function activityProductivityValue(activity, projects = []) {
  const projectID = resourceID(activity?.projectID);
  const project = projectID ? projects.find((item) => resourceID(item.id) === projectID) : null;
  if (project) {
    const raw = Number(project.productivity ?? (Number(project.productivity_score || 0) * 100));
    if (Number.isFinite(raw)) return Math.max(-100, Math.min(100, raw));
  }
  const category = activityCategory(activity).key;
  return category === "focused" ? 100 : category === "distracting" ? 0 : 50;
}

function activityFilterValues(activity, field) {
  const startSecond = Math.max(0, Number(activity?.startSecond || 0));
  const startMinute = Math.floor(startSecond / 60);
  const startDate = new Date(`${activity?.date || localDateKey()}T00:00:00`);
  if (!Number.isNaN(startDate.getTime())) startDate.setSeconds(Math.round(startSecond));
  switch (field) {
    case "application": return [activity.appName || ""];
    case "bundleIdentifier": return [activity.bundleIdentifier || ""];
    case "windowTitle": return [activity.windowTitle || ""];
    case "resource": return [activity.resource || ""];
    case "domain":
      try { return [new URL(activity.resource || "").host]; } catch { return [""]; }
    case "fullURL": return [activity.resource || ""];
    case "keyword": return [activity.windowTitle, activity.resource].filter(Boolean);
    case "device": return [activity.deviceName || "This Mac"];
    case "startTime": return [String(Math.floor(startMinute / 60)).padStart(2, "0") + ":" + String(startMinute % 60).padStart(2, "0")];
    case "dayOfWeek": return Number.isNaN(startDate.getTime()) ? [] : [startDate.toLocaleDateString("en-US", { weekday: "long" })];
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
  const includeTitlesInAdditionToPaths = options.includeTitlesInAdditionToPaths !== false;
  const title = String(activity?.windowTitle || "").trim();
  const resource = String(activity?.resource || "").trim();
  const app = String(activity?.appName || "").trim();
  if (showResourcePaths && resource) {
    let path = resource;
    try {
      path = new URL(resource).host || resource;
    } catch {
      // Keep the raw path when it is not a URL.
    }
    if (showWindowTitles && includeTitlesInAdditionToPaths && title && title.toLowerCase() !== app.toLowerCase()) return `${path} · ${title}`;
    return path;
  }
  if (showWindowTitles && title && title.toLowerCase() !== app.toLowerCase()) return title;
  return "";
}

function activityProjectRule(activity) {
  try {
    const host = new URL(activity?.resource || "").host;
    if (host) return { field: "domain", comparison: "contains", pattern: host, case_sensitive: false };
  } catch {
    // Fall through to application metadata.
  }
  if (activity?.bundleIdentifier) return { field: "bundleIdentifier", comparison: "contains", pattern: activity.bundleIdentifier, case_sensitive: false };
  if (activity?.windowTitle) return { field: "titleContains", comparison: "contains", pattern: activity.windowTitle, case_sensitive: false };
  return null;
}

async function assignActivitiesFromDrop({ event, activities, project, api, onAssignActivity }) {
  const rawIDs = event.dataTransfer.getData("application/x-metriday-activity") || event.dataTransfer.getData("text/plain");
  const activityIDs = [...new Set(rawIDs.split(/\r?\n/).map((value) => resourceID(value.trim())).filter(Boolean))];
  const sourceActivities = activityIDs
    .map((id) => activities.find((activity) => resourceID(activity.id) === id))
    .filter(Boolean);
  const createRules = Boolean(event.altKey);
  if (!sourceActivities.length) return { message: "Drop an App / Category activity row here." };
  if (createRules) {
    let createdRules = 0;
    for (const activity of sourceActivities) {
      const rule = activityProjectRule(activity);
      if (!rule || !api?.createProjectRule) continue;
      await api.createProjectRule({ ...rule, project_id: resourceID(project.id) });
      createdRules += 1;
    }
    return {
      message: createdRules > 0
        ? `Created ${createdRules} future ${createdRules === 1 ? "rule" : "rules"} for ${project.title}.`
        : "This activity has no ruleable app, website, or document metadata."
    };
  }
  if (!onAssignActivity) return { message: "Activity assignment is unavailable." };
  for (const activity of sourceActivities) {
    await onAssignActivity(activity.id, project.id, activity.date || undefined);
  }
  return { message: `Assigned ${sourceActivities.length} ${sourceActivities.length === 1 ? "activity" : "activities"} to ${project.title}.` };
}

function activityDateRangeLabel(activity, wrapAtMinute = 0) {
  const wrapSeconds = Math.max(0, Math.min(1439, Number(wrapAtMinute || 0))) * 60;
  const wallClock = (axisSeconds) => {
    const value = Number(axisSeconds || 0) >= 24 * 60 * 60
      ? wrapSeconds
      : (wrapSeconds + Math.max(0, Number(axisSeconds || 0))) % (24 * 60 * 60);
    return preciseClock(value);
  };
  return `${wallClock(activity?.startSecond)}–${wallClock(activity?.endSecond)}`;
}

function liveActivityBlocks(activities, projects = []) {
  const primaryKind = (totals) => [...totals.entries()].sort((left, right) => right[1] - left[1])[0]?.[0] || "other";
  const normalized = activities
    .map((activity) => {
      const rawStartSecond = Math.max(DAY_START * 60, Number(activity.startSecond || 0));
      const rawEndSecond = Math.min(DAY_END * 60, Number(activity.endSecond || 0));
      const start = Math.max(DAY_START, Math.floor(rawStartSecond / 60));
      const end = Math.min(DAY_END, Math.ceil(rawEndSecond / 60));
      if (end <= start) return null;
      const category = activityCategory(activity);
      const projectID = activity.projectID ? resourceID(activity.projectID) : "";
      return {
        id: activity.id || `${start}-${end}-${activity.appName}`,
        start,
        end,
        startSecond: rawStartSecond,
        endSecond: rawEndSecond,
        kind: category.key,
        categoryColor: category.color,
        categoryLabel: category.label,
        projectID: projectID || null,
        projectLabel: projectID ? projectTitleFor(projects, projectID) : "None",
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
      && activity.end - previous.start <= 20
      && activity.kind === previous.kind
      && activity.categoryColor === previous.categoryColor
      && activity.categoryLabel === previous.categoryLabel;

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
        projectLabels: new Map([[activity.projectID || "", activity.projectLabel]]),
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
    previous.projectLabels.set(activity.projectID || "", activity.projectLabel);
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
    projectID: (() => {
      const entries = [...block.projectLabels.entries()];
      return entries.length === 1 && entries[0][0] ? entries[0][0] : null;
    })(),
    projectLabel: (() => {
      const entries = [...block.projectLabels.values()];
      if (entries.length === 1) return entries[0] || "None";
      return entries.length > 1 ? "Multiple projects" : "None";
    })(),
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
    automatically_zoom_timeline_to_working_hours: false,
    wrap_days_at_minute: 0,
    start_tracking_when_app_opens: true,
    auto_stop_timer_on_sleep: true,
    review_reminder_interval_minutes: 0,
    review_reminder_notifications_authorized: false,
    review_reminder_notification_status: "Notifications not requested",
    include_subprojects_when_selecting_project: true,
    allow_local_network_api: false,
    launch_at_login: false,
    launch_at_login_status: "Login item not configured",
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

  const sourcePreferences = api?.sourcePreferences || {};
  const calendarSource = sourcePreferences.calendar || {};
  const reminderSource = sourcePreferences.reminders || {};
  const phoneSource = sourcePreferences.phone_calls || {};
  const screenTimeSource = sourcePreferences.screen_time || {};
  const permissions = sourcePreferences.permissions || {};
  const updateSource = (payload) => {
    if (!connected || !api?.updateSourcePreferences) return;
    api.updateSourcePreferences(payload).catch((error) => setMessage(error.message || "Could not save source filters."));
  };
  const toggleSourceTitle = (available, included, key, title, checked) => {
    const allTitles = new Set(available || []);
    const selected = new Set(included || []);
    if (selected.size === 0) allTitles.forEach((item) => selected.add(item));
    if (checked) selected.add(title);
    else selected.delete(title);
    updateSource({ [key]: selected.size === allTitles.size ? [] : [...selected] });
  };
  const requestSourceAccess = (source) => {
    if (!connected || !api?.requestSourceAccess) return;
    api.requestSourceAccess(source).catch((error) => setMessage(error.message || "Could not request source access."));
  };
  const showAllPhoneAddresses = () => {
    if (!connected || !api?.showAllPhoneCallAddresses) return;
    api.showAllPhoneCallAddresses().catch((error) => setMessage(error.message || "Could not show phone calls."));
  };

  return <div className="settings-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="settings-dialog" role="dialog" aria-modal="true" aria-labelledby="settings-title">
    <div className="settings-dialog-heading"><div><span>Preferences</span><h2 id="settings-title">Metriday Settings</h2></div><IconButton label="Close settings" onClick={onClose}><X size={18} /></IconButton></div>
    <p className="settings-description">Tracking, working hours, privacy, and the local Web companion connection are kept on this Mac.</p>
    <form className="settings-form" onSubmit={save}>
      <div className="settings-section"><div className="settings-section-heading"><strong>Tracking</strong><span className={`settings-state-dot ${connected ? "connected" : ""}`} />{connected ? api.status?.tracking ? "Running" : "Paused" : "Offline"}</div>
        <div className="settings-toggle-row"><label><input type="checkbox" checked={Boolean(api.status?.tracking)} onChange={() => api.toggleTracking()} disabled={!connected || saving} />Automatic activity tracking</label><small>{connected ? "Window, app, browser, and idle evidence" : "Connect the native app to change tracking"}</small></div>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.start_tracking_when_app_opens)} onChange={(event) => updatePreference("start_tracking_when_app_opens", event.target.checked)} disabled={!connected || saving} />Start tracking when Metriday opens</span></label>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.auto_stop_timer_on_sleep)} onChange={(event) => updatePreference("auto_stop_timer_on_sleep", event.target.checked)} disabled={!connected || saving} />Stop timers when the Mac sleeps</span></label>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.launch_at_login)} onChange={(event) => updatePreference("launch_at_login", event.target.checked)} disabled={!connected || saving} />Launch Metriday at login</span><small>{preferences.launch_at_login_status || "Login item status unavailable"}</small></label>
        <label className="settings-field-row"><span>Idle detection</span><select value={preferences.idle_threshold_seconds} onChange={(event) => updatePreference("idle_threshold_seconds", Number(event.target.value))} disabled={!connected || saving}><option value={60}>1 min</option><option value={120}>2 min</option><option value={180}>3 min</option><option value={300}>5 min</option><option value={600}>10 min</option></select></label>
      </div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Working hours</strong></div>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.track_weekends)} onChange={(event) => updatePreference("track_weekends", event.target.checked)} disabled={!connected || saving} />Track on weekends</span></label>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.track_only_during_working_hours)} onChange={(event) => updatePreference("track_only_during_working_hours", event.target.checked)} disabled={!connected || saving} />Track only during working hours</span></label>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(preferences.automatically_zoom_timeline_to_working_hours)} onChange={(event) => updatePreference("automatically_zoom_timeline_to_working_hours", event.target.checked)} disabled={!connected || saving} />Automatically zoom timeline to working hours</span><small>Keep the Activities timeline focused on the configured work window</small></label>
        <div className="settings-time-row"><label>From<input type="time" value={preferenceTime(preferences.working_hours_start_minute)} onChange={(event) => updatePreference("working_hours_start_minute", Math.max(0, Math.min(1439, Number(event.target.value.split(":")[0]) * 60 + Number(event.target.value.split(":")[1] || 0))))} disabled={!connected || saving} /></label><span>to</span><label>To<input type="time" value={preferenceTime(preferences.working_hours_end_minute)} onChange={(event) => updatePreference("working_hours_end_minute", Math.max(0, Math.min(1439, Number(event.target.value.split(":")[0]) * 60 + Number(event.target.value.split(":")[1] || 0))))} disabled={!connected || saving} /></label></div>
        <label className="settings-field-row"><span>Wrap days at</span><input type="time" value={preferenceTime(preferences.wrap_days_at_minute)} onChange={(event) => updatePreference("wrap_days_at_minute", Math.max(0, Math.min(1439, Number(event.target.value.split(":")[0]) * 60 + Number(event.target.value.split(":")[1] || 0))))} disabled={!connected || saving} /></label>
        <small className="settings-help-text">Activity after midnight stays with the previous workday until this time. Set 00:00 for ordinary calendar days.</small>
      </div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Activity review reminders</strong><span className={`settings-state-dot ${preferences.review_reminder_notifications_authorized ? "connected" : ""}`} /></div>
        <label className="settings-field-row"><span>Remind to review activities</span><select value={Number(preferences.review_reminder_interval_minutes || 0)} onChange={(event) => updatePreference("review_reminder_interval_minutes", Number(event.target.value))} disabled={!connected || saving}><option value={0}>Never</option><option value={15}>Every 15 minutes</option><option value={30}>Every 30 minutes</option><option value={60}>Every hour</option><option value={120}>Every 2 hours</option></select></label>
        <small className="settings-help-text">The native app sends a local notification summarizing today's tracked time. {preferences.review_reminder_notification_status || "Notifications not requested"}</small>
      </div>
      <div className="settings-section"><div className="settings-section-heading"><strong>Project selection</strong></div>
        <label className="settings-toggle-row"><span><input type="checkbox" checked={preferences.include_subprojects_when_selecting_project !== false} onChange={(event) => updatePreference("include_subprojects_when_selecting_project", event.target.checked)} disabled={!connected || saving} />Include sub-projects when selecting a project</span></label>
        <small className="settings-help-text">Selecting a parent in Activities or Stats includes descendant activity when enabled. Collapsed project totals always include their children.</small>
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
      <div className="settings-section settings-source-status"><div className="settings-section-heading"><strong>Data sources</strong></div><span><i className={permissions.accessibility_trusted ? "connected" : ""} />Accessibility · {permissions.status || "Not connected"}</span><span><i className={api.calendarEvents?.authorized ? "connected" : ""} />Calendar · {api.calendarEvents?.status || "Not connected"}</span><span><i className={api.reminders?.authorized ? "connected" : ""} />Reminders · {api.reminders?.status || "Not connected"}</span><span><i className={api.screenTime?.database_available ? "connected" : ""} />Screen Time · {api.screenTime?.status || "Not connected"}</span></div>
      <div className="settings-section settings-source-filters"><div className="settings-section-heading"><strong>Permissions</strong><span className={`settings-state-dot ${permissions.accessibility_trusted ? "connected" : ""}`} /></div><div className="settings-source-connect"><span>{permissions.status || "Accessibility access not connected"}</span><button type="button" className="secondary-button" onClick={() => requestSourceAccess("accessibility")} disabled={!connected}>{permissions.accessibility_trusted ? "Open Settings" : "Request access"}</button></div><small className="settings-help-text">Accessibility access is used for active window titles and local App / website activity evidence.</small></div>
      <div className="settings-section settings-source-filters"><div className="settings-section-heading"><strong>Calendar filters</strong><span className={`settings-state-dot ${calendarSource.authorized ? "connected" : ""}`} /></div>{calendarSource.authorized ? <><label className="settings-toggle-row"><span><input type="checkbox" checked={!calendarSource.included_titles?.length} onChange={(event) => updateSource({ calendar_included_titles: event.target.checked ? [] : (calendarSource.available_titles || []) })} />All calendars</span><small>{calendarSource.available_titles?.length || 0} available</small></label>{calendarSource.available_titles?.map((title) => <label className="settings-source-filter-row" key={title}><span><input type="checkbox" checked={!calendarSource.included_titles?.length || calendarSource.included_titles.includes(title)} onChange={(event) => toggleSourceTitle(calendarSource.available_titles, calendarSource.included_titles, "calendar_included_titles", title, event.target.checked)} />{title}</span></label>)}<small className="settings-help-text">Only selected calendars appear on the Activities timeline; all-day events stay hidden.</small></> : <div className="settings-source-connect"><span>{calendarSource.status || "Calendar access not connected"}</span><button type="button" className="secondary-button" onClick={() => requestSourceAccess("calendar")} disabled={!connected}>Request access</button></div>}</div>
      <div className="settings-section settings-source-filters"><div className="settings-section-heading"><strong>Reminders filters</strong><span className={`settings-state-dot ${reminderSource.authorized ? "connected" : ""}`} /></div>{reminderSource.authorized ? <><label className="settings-toggle-row"><span><input type="checkbox" checked={!reminderSource.included_list_titles?.length} onChange={(event) => updateSource({ reminder_included_list_titles: event.target.checked ? [] : (reminderSource.available_list_titles || []) })} />All reminder lists</span><small>{reminderSource.available_list_titles?.length || 0} available</small></label><label className="settings-toggle-row"><span><input type="checkbox" checked={Boolean(reminderSource.hide_recurring)} onChange={(event) => updateSource({ reminder_hide_recurring: event.target.checked })} />Hide recurring reminders</span></label>{reminderSource.available_list_titles?.map((title) => <label className="settings-source-filter-row" key={title}><span><input type="checkbox" checked={!reminderSource.included_list_titles?.length || reminderSource.included_list_titles.includes(title)} onChange={(event) => toggleSourceTitle(reminderSource.available_list_titles, reminderSource.included_list_titles, "reminder_included_list_titles", title, event.target.checked)} />{title}</span></label>)}<small className="settings-help-text">Completed reminders follow these list and recurring-item filters.</small></> : <div className="settings-source-connect"><span>{reminderSource.status || "Reminders access not connected"}</span><button type="button" className="secondary-button" onClick={() => requestSourceAccess("reminders")} disabled={!connected}>Request access</button></div>}</div>
      <div className="settings-section settings-source-filters"><div className="settings-section-heading"><strong>Phone Calls filters</strong><span className={`settings-state-dot ${phoneSource.database_available ? "connected" : ""}`} /></div>{phoneSource.database_available ? phoneSource.hidden_addresses?.length ? <><div className="settings-source-filter-heading"><span>Hidden numbers</span><button type="button" className="secondary-button" onClick={showAllPhoneAddresses}>Show all</button></div><div className="settings-source-list">{phoneSource.hidden_addresses.map((address) => <div key={address}><span>{address}</span><button type="button" className="quiet-pill" onClick={() => api.hidePhoneCallAddress(address, false).catch((error) => setMessage(error.message || "Could not show phone calls."))}>Show</button></div>)}</div><small className="settings-help-text">Hidden calls stay in macOS CallHistory but are excluded from the Metriday timeline.</small></> : <small className="settings-help-text">Calls are shown by default. Hide a number from the Phone Calls panel in Activities.</small> : <div className="settings-source-connect"><span>{phoneSource.status || "Phone Calls access not connected"}</span><button type="button" className="secondary-button" onClick={() => requestSourceAccess("phone-calls")} disabled={!connected}>Open Settings</button></div>}</div>
      <div className="settings-section settings-source-filters"><div className="settings-section-heading"><strong>Screen Time</strong><span className={`settings-state-dot ${screenTimeSource.database_available ? "connected" : ""}`} /></div><div className="settings-source-connect"><span>{screenTimeSource.status || "Screen Time not connected"}</span>{!screenTimeSource.database_available ? <button type="button" className="secondary-button" onClick={() => requestSourceAccess("screen-time")} disabled={!connected}>Open Settings</button> : null}</div></div>
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
  const currentTaskRange = taskMinuteRange(currentTask);
  const currentRange = currentTaskRange
    ? formatRange(currentTaskRange.start, currentTaskRange.end)
    : "No scheduled time";
  const toggleFocus = async () => {
    if (!api.connected || !currentTask) return;
    try {
      await api.setFocusActive(!focusActive);
    } catch {
      // The page-level controls continue to reflect the native API on the next refresh.
    }
  };
  const openRules = () => setPage("rules");
  const handleRulesKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    openRules();
  };
  return <header className="web-global-header"><div className="web-global-date"><strong>{planDateLabel(dateKey)}</strong><DateControls dateKey={dateKey} onChange={setDateKey} label="Choose selected date" /></div><div className="web-global-context"><div className="web-global-current"><span>Current block</span><strong>{currentTitle}</strong><small>{currentRange} · {focusActive ? "In progress" : currentTask ? "Ready" : "Waiting"}</small></div><button type="button" className={`primary-button web-global-focus ${focusActive ? "active" : ""}`} onClick={toggleFocus} disabled={!api.connected || !currentTask} title={api.connected && !currentTask ? "Schedule a current block to start Focus" : undefined}>{focusActive ? <Pause size={16} weight="fill" /> : <Play size={16} weight="fill" />}{focusActive ? "Pause focus" : "Resume focus"}</button><TimerControls api={api} /><div className="web-global-rule" role="button" tabIndex={0} aria-label="Open Research Focus rules" onClick={openRules} onKeyDown={handleRulesKeyDown}><ShieldCheck size={30} color="#399a55" weight="duotone" /><div><strong>Research Focus</strong><span>{focusActive ? "Blocklist active" : "Blocklist ready"}</span><button type="button" onClick={(event) => { event.stopPropagation(); openRules(); }}>Adjust allowed sites</button></div></div></div></header>;
}

function IconButton({ label, children, onClick, className = "", disabled = false }) {
  return <button type="button" className={`icon-button ${className}`} aria-label={label} title={label} onClick={onClick} disabled={disabled}>{children}</button>;
}

function DatePickerControl({ dateKey, onChange, label = "Choose date" }) {
  return <label className="date-picker-control" title={label}><CalendarBlank size={20} /><input type="date" value={dateKey} onChange={(event) => { if (event.target.value) onChange(event.target.value); }} aria-label={label} /></label>;
}

function DateControls({ dateKey, onChange, label = "Choose date" }) {
  const handleBlankClick = (event) => {
    if (event.target.closest("button, input, label")) return;
    onChange(localDateKey());
  };
  return <div className="date-controls" onClick={handleBlankClick} title="Click empty space to go to Today" aria-label="Date navigation" role="group">
    <DatePickerControl dateKey={dateKey} onChange={onChange} label={label} />
    <button type="button" className="quiet-pill" onClick={() => onChange(localDateKey())}>Today</button>
    <IconButton label="Previous day" onClick={() => onChange(offsetDateKey(dateKey, -1))}><CaretLeft size={18} /></IconButton>
    <IconButton label="Next day" onClick={() => onChange(offsetDateKey(dateKey, 1))}><CaretRight size={18} /></IconButton>
  </div>;
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
  const [dismissedTimerID, setDismissedTimerID] = useState(null);
  const timer = api.status?.timer;
  const timerID = resourceID(timer?.id);
  useEffect(() => {
    if (!timerID || dismissedTimerID === timerID) return;
    if (dismissedTimerID) setDismissedTimerID(null);
  }, [dismissedTimerID, timerID]);
  if (!timer) return null;
  const remaining = Number(timer.remainingSeconds);
  const expired = Number.isFinite(remaining) && remaining < 0;
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
  const align = async () => {
    try {
      await api.alignTimer();
      setMessage("Timer aligned to previous entry");
    } catch (error) {
      setMessage(error.message || "Could not align timer.");
    }
  };
  const adjustEstimate = async (minutes) => {
    try {
      await api.adjustTimerEstimate(minutes);
      setMessage(`${minutes > 0 ? "+" : ""}${minutes} min estimate adjustment saved`);
    } catch (error) {
      setMessage(error.message || "Could not adjust timer estimate.");
    }
  };
  const keepWorking = async () => {
    const elapsedMinutes = Math.max(1, Math.ceil(Number(timer.durationSeconds || 0) / 60));
    try {
      await api.setTimerEstimate(elapsedMinutes + 15);
      setDismissedTimerID(timerID);
      setMessage("Timer extended by 15 min");
    } catch (error) {
      setMessage(error.message || "Could not extend the timer.");
    }
  };
  const stopTimer = async () => {
    try {
      await api.stopTimer();
      setDismissedTimerID(null);
    } catch (error) {
      setMessage(error.message || "Could not stop the timer.");
    }
  };
  const remainingLabel = Number.isFinite(remaining)
    ? remaining >= 0 ? `${formatDurationSeconds(remaining)} remaining` : `Over by ${formatDurationSeconds(-remaining)}`
    : "Timer running";
  return <div className="timer-controls" aria-label="Running timer controls"><span>{remainingLabel}</span><select aria-label="Timer estimate" value={timer.estimatedDurationSeconds ? Math.round(Number(timer.estimatedDurationSeconds) / 60) : ""} onChange={setEstimate}><option value="">Set estimate</option><option value={15}>15 min</option><option value={25}>25 min</option><option value={30}>30 min</option><option value={45}>45 min</option><option value={60}>1 hour</option><option value={90}>90 min</option><option value={120}>2 hours</option></select><details className="timer-adjust-menu" onClick={(event) => { if (event.target.closest("button")) event.currentTarget.open = false; }}><summary>Adjust</summary><div className="timer-adjust-popover"><strong>Adjust start</strong><div className="timer-adjust-grid">{[-15, -5, -1, 1, 5, 15].map((minutes) => <button type="button" key={minutes} onClick={() => adjust(minutes)}>{minutes > 0 ? `+${minutes}` : minutes}m</button>)}</div><button type="button" onClick={align}>Align to previous entry</button><strong>Estimate</strong><div className="timer-adjust-estimate-list">{[15, 30, 60].map((minutes) => <button type="button" key={minutes} onClick={() => adjustEstimate(minutes)}>Add {minutes === 60 ? "1 hour" : `${minutes} min`}</button>)}</div></div></details>{expired && dismissedTimerID !== timerID ? <div className="timer-check-in" role="alert"><strong>Timer estimate reached</strong><span>Still working on “{timer.title}”?</span><button type="button" onClick={keepWorking}>Keep working · +15m</button><button type="button" className="danger" onClick={stopTimer}>Stop timer</button><button type="button" className="quiet" onClick={() => setDismissedTimerID(timerID)}>Dismiss</button></div> : null}{message ? <small role="status">{message}</small> : null}</div>;
}

function TodayHeader({ focusRunning, setFocusRunning, setPage, api, dateKey, setDateKey }) {
  const currentTask = api.status?.currentTask;
  const currentTitle = currentTask?.title || (api.connected ? "No scheduled block" : "GeneZip rebuttal experiment");
  const currentTaskRange = taskMinuteRange(currentTask);
  const currentRange = currentTaskRange
    ? formatRange(currentTaskRange.start, currentTaskRange.end)
    : api.connected ? "No scheduled time" : "14:00–16:00";
  const currentApplication = api.status?.currentApplication && api.status.currentApplication !== "Waiting for activity" ? api.status.currentApplication : "Research Focus";
  const focusActionLabel = focusRunning ? "Pause focus" : api.connected && !currentTask ? "Start timer" : "Resume focus";
  return (
    <header className="today-header">
      <div className="date-heading">
        <h1>{planDateLabel(dateKey)}</h1>
        <DateControls dateKey={dateKey} onChange={setDateKey} label="Choose Today date" />
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
     <div className="track-heading"><div><strong>Plan</strong><span>What I planned</span></div></div>
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
      const result = await onRecord({ ...block, startSecond, endSecond });
      setMessage(result?.opened ? "Editor opened" : "Recorded");
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
    <div className="actual-hover-meta"><span>Project:</span><i className="hover-project-dot" /><b>{block.projectLabel || "None"}</b>{block.projectLabel === "None" ? <small>From the app usage</small> : null}</div>
    {onRecord ? <div className="actual-hover-actions"><button type="button" className="actual-record-button" onClick={record} disabled={busy}>{message || (busy ? "Recording…" : "Record time")}</button></div> : null}
  </div>;
}

function ActualTrack({ activities, connected, onRecord, onSelect, projects = [], api }) {
  const [hoveredBlockId, setHoveredBlockId] = useState(null);
  const blocks = connected && activities.length > 0 ? liveActivityBlocks(activities, projects) : actualBlocks;
  const selectActivity = (block) => activities.find((activity) => String(activity.id) === String(block.id)) || null;
 const tracking = Boolean(api?.status?.tracking);
 const accessibilityTrusted = Boolean(api?.sourcePreferences?.permissions?.accessibility_trusted);
 return (
   <section className="today-track actual-track" aria-label="Actual activity timeline">
     <div className="track-heading"><div><strong>Actual</strong><span>{connected ? tracking ? "Live from Metriday" : "Tracking paused" : "What actually happened"}</span></div>{connected ? <div className="track-actions">{!accessibilityTrusted ? <button type="button" className="track-action" onClick={() => api?.requestSourceAccess?.("accessibility")} aria-label="Request Accessibility access" title="Allow Accessibility access to read window titles"><LockSimple size={12} /></button> : null}<button type="button" className="track-action" onClick={() => api?.toggleTracking?.().catch(() => {})} aria-label={tracking ? "Pause activity tracking" : "Resume activity tracking"}>{tracking ? <Pause size={13} weight="fill" /> : <Play size={13} weight="fill" />}{tracking ? "Pause" : "Track"}</button></div> : null}</div>
      <div className="track-canvas"><GridLines />{blocks.map((block) => { const activity = selectActivity(block); return <div key={block.id} className={`actual-block ${block.kind} ${hoveredBlockId === block.id ? "hovered" : ""}`} style={{ ...actualBlockStyle(block), ...activityBlockStyle(block.categoryColor || categoryRoleColor(block.kind)) }} title={`${block.label} · ${block.detail}`} role={activity ? "button" : undefined} aria-label={activity ? `Open activity ${block.label} ${block.detail}` : undefined} tabIndex={activity ? 0 : undefined} onMouseEnter={() => setHoveredBlockId(block.id)} onMouseLeave={() => setHoveredBlockId(null)} onClick={(event) => { if (event.target.closest("button")) return; if (activity) onSelect?.(activity); }} onKeyDown={(event) => { if (activity && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); onSelect?.(activity); } }}><ActualRows block={block} />{hoveredBlockId === block.id ? <ActualHoverCard block={block} onRecord={connected ? onRecord : null} /> : null}</div>; })}</div>
   </section>
 );
}

function TodayPage({ setPage, api, dateKey, setDateKey }) {
  const [selectedActivity, setSelectedActivity] = useState(null);
  const [timeEntryPrefill, setTimeEntryPrefill] = useState(null);
  const recordActivity = async (block) => {
    const start = localEntryDateSeconds(dateKey, block.startSecond);
    const end = localEntryDateSeconds(dateKey, block.endSecond);
    if (!start || !end || end <= start) throw new Error("Activity range is not available");
    setTimeEntryPrefill({
      title: block.rows?.[0]?.label || block.label || "App activity",
      start,
      end,
      projectID: block.projectID || undefined,
      billingStatus: "billable",
    });
    return { opened: true };
  };
  const now = currentMinuteAndLabel();
  const showNow = dateKey === localDateKey();
  const nowStyle = showNow ? { top: `${56 + ((now.minute - DAY_START) / 60) * HOUR_HEIGHT}px` } : { display: "none" };
  return (
    <main className="page today-page">
      <div className="today-comparison"><div className="timeline-label-column"><HourLabels /></div><PlannedTrack tasks={api.plan?.tasks} connected={api.connected} onSelect={() => setPage("plan")} /><ActualTrack activities={api.activities} connected={api.connected} onRecord={recordActivity} onSelect={setSelectedActivity} projects={api.projects} api={api} /><div className="now-marker" style={nowStyle} aria-label={`Current time ${now.label}`}><span /></div></div>
      <TodayInsightBar api={api} setPage={setPage} />
      {api.connected ? <WebActivityInsights insights={api.insights} dateKey={dateKey} /> : null}{selectedActivity ? <ActivityDetailDialog activity={selectedActivity} api={api} dateKey={dateKey} displayPreferences={api.activityPreferences} onClose={() => setSelectedActivity(null)} /> : null}<WebTimeEntryDialog mode="new" open={Boolean(timeEntryPrefill)} api={api} projects={api.projects} recentEntries={api.entries} dateKey={dateKey} initialEntry={timeEntryPrefill} onClose={() => setTimeEntryPrefill(null)} />
    </main>
  );
}

function TodayInsightBar({ api, setPage }) {
  const openRules = () => setPage("rules");
  const handleRulesKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    openRules();
  };
  const bannerProps = {
    className: "insight-bar",
    role: "button",
    tabIndex: 0,
    "aria-label": "Open Research Focus rules",
    onClick: openRules,
    onKeyDown: handleRulesKeyDown,
  };
  if (!api.connected) {
    return <div {...bannerProps}><TrendUp size={26} color="#4f63ef" weight="duotone" /><div><p><strong>Started 8 min late</strong><b>·</b><strong className="positive">82% task-related</strong><b>·</b><strong className="warning">Estimate likely +25 min</strong></p><span>Connect Metriday to replace the preview insight with local activity evidence.</span></div><button type="button" className="secondary-button" onClick={(event) => { event.stopPropagation(); openRules(); }}><ShieldCheck size={18} /> Adjust blocklist</button></div>;
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
  return <div {...bannerProps}><TrendUp size={26} color="#4f63ef" weight="duotone" /><div><p><strong>{trackingLabel}</strong><b>·</b><strong className="positive">{taskRelated}% task-related</strong><b>·</b><strong className={distractedSeconds > 0 ? "warning" : "positive"}>{activityLabel}</strong></p><span>{distractionLabel} · Source: local activity monitor and Screen Time when available.</span></div><button type="button" className="secondary-button" onClick={(event) => { event.stopPropagation(); openRules(); }}><ShieldCheck size={18} /> Adjust blocklist</button></div>;
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

function markdownInlineNodes(value, keyPrefix = "inline") {
  const source = String(value || "");
  const pattern = /(\*\*[^*]+\*\*|~~[^~]+~~|`[^`]+`|\[[^\]]+\]\([^\)]+\)|(?<!\*)\*[^*]+\*(?!\*))/g;
  const nodes = [];
  let cursor = 0;
  let match;
  let index = 0;
  while ((match = pattern.exec(source))) {
    if (match.index > cursor) nodes.push(source.slice(cursor, match.index));
    const token = match[0];
    if (token.startsWith("**")) nodes.push(<strong key={`${keyPrefix}-bold-${index}`}>{token.slice(2, -2)}</strong>);
    else if (token.startsWith("~~")) nodes.push(<del key={`${keyPrefix}-strike-${index}`}>{token.slice(2, -2)}</del>);
    else if (token.startsWith("`")) nodes.push(<code key={`${keyPrefix}-code-${index}`}>{token.slice(1, -1)}</code>);
    else if (token.startsWith("[")) nodes.push(<span className="markdown-preview-link" key={`${keyPrefix}-link-${index}`}>{token.slice(1, token.indexOf("]("))}</span>);
    else nodes.push(<em key={`${keyPrefix}-italic-${index}`}>{token.slice(1, -1)}</em>);
    cursor = match.index + token.length;
    index += 1;
  }
  if (cursor < source.length) nodes.push(source.slice(cursor));
  return nodes.length ? nodes : [source || "\u00a0"];
}

function MarkdownPreviewLine({ line, index, active }) {
  if (active) return <div className="markdown-live-line markdown-live-line-active" key={index}>{line || "\u00a0"}</div>;
  const source = String(line || "");
  const heading = source.match(/^\s*(#{1,6})\s+(.+)$/);
  if (heading) return <div className={`markdown-live-line markdown-live-heading level-${heading[1].length}`} key={index}>{markdownInlineNodes(heading[2], `heading-${index}`)}</div>;
  const task = source.match(/^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s+(?:(\d{1,2}:\d{2}\s*[–—-]\s*\d{1,2}:\d{2})\s+)?(.+)$/);
  if (task) return <div className="markdown-live-line markdown-live-task" key={index}>{markdownInlineNodes(task[3], `task-${index}`)}</div>;
  const quote = source.match(/^\s*&gt;\s?(.+)$/) || source.match(/^\s*>\s?(.+)$/);
  if (quote) return <div className="markdown-live-line markdown-live-quote" key={index}>{markdownInlineNodes(quote[1], `quote-${index}`)}</div>;
  const unordered = source.match(/^\s*[-*+]\s+(.+)$/);
  if (unordered) return <div className="markdown-live-line markdown-live-list" key={index}><span className="markdown-live-bullet">•</span>{markdownInlineNodes(unordered[1], `bullet-${index}`)}</div>;
  const ordered = source.match(/^\s*\d+[.)]\s+(.+)$/);
  if (ordered) return <div className="markdown-live-line markdown-live-list" key={index}><span className="markdown-live-number">{source.match(/^\s*(\d+)/)?.[1]}.</span>{markdownInlineNodes(ordered[1], `number-${index}`)}</div>;
  return <div className="markdown-live-line" key={index}>{markdownInlineNodes(source, `text-${index}`)}</div>;
}

function markdownListContinuation(line) {
  const source = String(line || "");
  const task = source.match(/^([\t ]*)[-*+]\s+\[[ xX]\]\s*(.*)$/);
  if (task) return task[2].trim() ? `${task[1]}- [ ] ` : "";
  const bullet = source.match(/^([\t ]*)[-*+]\s+(.*)$/);
  if (bullet) return bullet[2].trim() ? `${bullet[1]}- ` : "";
  const ordered = source.match(/^([\t ]*)(\d+)[.)]\s+(.*)$/);
  if (ordered) return ordered[3].trim() ? `${ordered[1]}${Number(ordered[2]) + 1}. ` : "";
  return null;
}

function MarkdownEditor({ tasks, markdown, planDate, onMarkdownChange, onMarkdownCommit, onTaskDragStart, onPointerDragStart, onSelectTask, onComplete, onReload }) {
  const [scrollTop, setScrollTop] = useState(0);
  const [scrollLeft, setScrollLeft] = useState(0);
  const [activeLine, setActiveLine] = useState(null);
  const editorRef = useRef(null);
  const lines = String(markdown || "").split("\n");
  const taskLineIndices = lines.map((line, index) => ({ line, index })).filter(({ line }) => /^\s*(?:[-*+]|[0-9]+[.)])\s+\[[ xX]\]\s+/.test(line));
  const copyMarkdown = () => navigator.clipboard?.writeText(String(markdown || "")).catch(() => {});
  const updateActiveLine = (event) => {
    const value = event.currentTarget.value;
    const caret = event.currentTarget.selectionStart || 0;
    setActiveLine(value.slice(0, caret).split("\n").length - 1);
  };
  const handleEditorKeyDown = (event) => {
    if (event.key !== "Enter" || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;
    const editor = event.currentTarget;
    const source = editor.value || "";
    const start = editor.selectionStart || 0;
    const end = editor.selectionEnd || start;
    const lineStart = source.lastIndexOf("\n", Math.max(0, start - 1)) + 1;
    const nextNewline = source.indexOf("\n", start);
    const lineEnd = nextNewline === -1 ? source.length : nextNewline;
    const line = source.slice(lineStart, lineEnd);
    const continuation = markdownListContinuation(line);
    if (continuation === null) return;
    event.preventDefault();
    const isEmptyListItem = continuation === "";
    const insertion = isEmptyListItem ? "\n" : `\n${continuation}`;
    const next = isEmptyListItem
      ? source.slice(0, lineStart) + source.slice(lineEnd)
      : source.slice(0, start) + insertion + source.slice(end);
    const caret = isEmptyListItem ? lineStart : start + insertion.length;
    onMarkdownChange(next);
    setActiveLine(next.slice(0, caret).split("\n").length - 1);
    window.requestAnimationFrame(() => {
      if (editorRef.current) {
        editorRef.current.focus();
        editorRef.current.setSelectionRange(caret, caret);
      }
    });
  };
  return (
    <section className="markdown-editor" aria-label="Markdown daily plan">
      <div className="editor-toolbar"><div className="file-name"><FileText size={18} /> {planDate}.md <span>{markdown ? "Markdown document" : "Blank Markdown document"}</span></div><div className="editor-actions"><span>Markdown</span><ActionMenu label="Document actions" items={[{ label: "Copy Markdown", onSelect: copyMarkdown }, ...(onReload ? [{ label: "Reload from disk", onSelect: onReload }] : [])]}><DotsThree size={22} /></ActionMenu></div></div>
      <div className="editor-body markdown-source-wrap">
        <textarea ref={editorRef} className="markdown-source-editor" aria-label="Markdown editor" value={markdown || ""} spellCheck={false} onChange={(event) => { onMarkdownChange(event.target.value); updateActiveLine(event); }} onKeyDown={handleEditorKeyDown} onFocus={updateActiveLine} onClick={updateActiveLine} onKeyUp={updateActiveLine} onSelect={updateActiveLine} onBlur={(event) => { onMarkdownCommit(event.currentTarget.value); setActiveLine(null); }} onScroll={(event) => { setScrollTop(event.currentTarget.scrollTop); setScrollLeft(event.currentTarget.scrollLeft); }} />
        <div className="markdown-live-preview" style={{ transform: `translate(${-scrollLeft}px, ${-scrollTop}px)` }} aria-hidden="true">
          {lines.map((line, index) => <MarkdownPreviewLine line={line} index={index} active={activeLine === index} key={index} />)}
        </div>
        <div className="markdown-source-overlays" style={{ transform: "translate(" + (-scrollLeft) + "px, " + (-scrollTop) + "px)" }} aria-hidden="false">
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
  const timelineBodyRef = useRef(null);
  const [visibleMonth, setVisibleMonth] = useState(() => new Date(`${dateKey}T12:00:00`));
  useEffect(() => {
    const selectedMonth = new Date(`${dateKey}T12:00:00`);
    if (!Number.isNaN(selectedMonth.getTime()) && (selectedMonth.getMonth() !== visibleMonth.getMonth() || selectedMonth.getFullYear() !== visibleMonth.getFullYear())) {
      setVisibleMonth(selectedMonth);
    }
  }, [dateKey]);
  const drop = (event) => { event.preventDefault(); const id = event.dataTransfer.getData("text/task-id") || selectedTaskId; if (!id || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(id, event.clientY - rect.top + (timelineBodyRef.current?.scrollTop || 0), { metaKey: event.metaKey, altKey: event.altKey }); };
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
  const timelineDays = Array.from({ length: 4 }, (_, offset) => offsetDateKey(dateKey, offset));
  return (
    <section className="calendar-panel" aria-label="Calendar and continuous timeline">
      <div className="calendar-toolbar"><div className="month-navigation"><IconButton label="Previous month" onClick={() => setVisibleMonth((value) => new Date(value.getFullYear(), value.getMonth() - 1, 1, 12))}><CaretLeft size={16} /></IconButton><strong>{monthTitle}</strong><IconButton label="Next month" onClick={() => setVisibleMonth((value) => new Date(value.getFullYear(), value.getMonth() + 1, 1, 12))}><CaretRight size={16} /></IconButton></div><ActionMenu label="Calendar options" items={calendarItems}><DotsThree size={21} /></ActionMenu></div>
      <div className="month-calendar" aria-label={`${monthTitle} calendar`}><div className="month-weekdays" aria-hidden="true">{["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => <span key={day}>{day}</span>)}</div><div className="month-grid">{monthDays.map((day) => { const date = new Date(`${day}T12:00:00`); const isCurrentMonth = date.getMonth() === visibleMonth.getMonth(); const isSelected = day === dateKey; const isToday = day === localDateKey(); const taskCount = isSelected ? tasks.filter((task) => task.start != null).length : 0; return <button type="button" key={day} className={`month-day ${isCurrentMonth ? "" : "outside"} ${isSelected ? "selected" : ""} ${isToday ? "today" : ""}`} onClick={() => onSelectDate(day)} aria-label={`${date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" })}${taskCount ? `, ${taskCount} scheduled blocks` : ""}`}><span>{date.getDate()}</span>{taskCount ? <small>{taskCount}</small> : null}</button>; })}</div></div>
      <h2>{selectedDateLabel}</h2><div className="all-day-row"><span>all-day</span></div>
      <div className="continuous-timeline" aria-label="Three-day continuous timeline"><div className="continuous-timeline-head"><div /><div className="continuous-day-labels">{timelineDays.map((day) => { const date = new Date(`${day}T12:00:00`); return <button type="button" key={day} className={day === dateKey ? "selected" : ""} onClick={() => onSelectDate(day)}><span>{date.toLocaleDateString(undefined, { weekday: "short" })}</span><strong>{date.getDate()}</strong></button>; })}</div></div><div className="continuous-timeline-body" ref={timelineBodyRef}><div className="continuous-hour-axis"><HourLabels end={20} /></div>{timelineDays.map((day) => { const isSelected = day === dateKey; const dayTasks = isSelected ? tasks : (neighborPlans?.[day] || []); if (isSelected) return <div ref={timelineRef} key={day} className={`plan-calendar-canvas continuous-day-canvas ${selectedTaskId ? "ready-to-schedule" : ""}`} onDragOver={(event) => event.preventDefault()} onDrop={drop} onClick={(event) => { if (!selectedTaskId || !timelineRef.current) return; const rect = timelineRef.current.getBoundingClientRect(); onDropTask(selectedTaskId, event.clientY - rect.top + (timelineBodyRef.current?.scrollTop || 0), { metaKey: event.metaKey, altKey: event.altKey }); }}><GridLines end={20} />{!connected ? <><div className="static-calendar-block morning" style={blockStyle(8 * 60, 9 * 60)}><strong>Morning routine</strong><span>08:00–09:00</span></div><div className="static-calendar-block team" style={blockStyle(9 * 60 + 30, 10 * 60 + 15)}><strong>Team sync</strong><span>09:30–10:15</span></div><div className="static-calendar-block lunch" style={blockStyle(12 * 60, 13 * 60)}><strong>Lunch</strong><span>12:00–13:00</span></div></> : null}{dayTasks.filter((task) => task.start != null).map((task) => <CalendarBlock key={task.id} task={task} selected={selectedTaskId === task.id} onSelect={setSelectedTaskId} onMoveStart={onMoveStart} onComplete={onComplete} onUnschedule={onUnschedule} onResizeStart={onResizeStart} />)}</div>; return <div key={day} className="continuous-day-canvas adjacent" role="button" tabIndex={0} aria-label={`Open Plan for ${day}`} onClick={() => onSelectDate(day)} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onSelectDate(day); } }}><GridLines end={20} />{dayTasks.filter((task) => task.start != null).map((task) => <div key={task.id} className={`continuous-neighbor-block ${task.tone}`} style={blockStyle(task.start, task.end)}><strong>{task.title}</strong><span>{formatRange(task.start, task.end)}</span></div>)}</div>; })}</div></div>
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
    const dates = [1, 2, 3].map((offset) => offsetDateKey(dateKey, offset));
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
  useEffect(() => {
    if (!pendingSchedule) return undefined;
    const handleKeyDown = (event) => { if (event.key === "Escape") setPendingSchedule(null); };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [pendingSchedule]);
  const reloadPlan = async () => {
    if (!api.connected || typeof api.fetchPlan !== "function") return;
    try {
      const loaded = await api.fetchPlan(dateKey);
      const loadedMarkdown = String(loaded?.markdown || "");
      markdownRef.current = loadedMarkdown;
      setMarkdown(loadedMarkdown);
      setTasks(Array.isArray(loaded?.tasks) ? loaded.tasks.map(planTaskFromAPI) : []);
      setSelectedTaskId(null);
      setToast("Markdown reloaded from disk");
    } catch (error) {
      setToast(error.message || "Could not reload Markdown");
    }
  };
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
  const createCalendarEvent = async (id, start, end) => {
    const task = tasks.find((item) => item.id === id);
    if (!task || !api.connected || typeof api.createCalendarEvent !== "function") return;
    if (!api.calendarEvents?.authorized) {
      try {
        await api.requestSourceAccess?.("calendar");
        setToast("Calendar access requested");
      } catch (error) {
        setToast(error.message || "Could not request Calendar access");
      }
      return;
    }
    try {
      await api.createCalendarEvent({ date: planDate, title: task.title, start: localEntryDateSeconds(planDate, start * 60), end: localEntryDateSeconds(planDate, end * 60) });
      setToast("Calendar Event created · " + formatRange(start, end));
      setSelectedTaskId(id);
    } catch (error) {
      setToast(error.message || "Could not create Calendar Event");
    }
  };
  const dropTask = (id, offsetY, modifiers = {}) => { const raw = DAY_START + (offsetY / HOUR_HEIGHT) * 60; const start = Math.max(DAY_START, Math.min(DAY_END - 30, Math.round(raw / 15) * 15)); const task = tasks.find((item) => item.id === id); if (!task) return; const end = Math.min(start + (task.start != null ? Math.max(task.end - task.start, 30) : 60), DAY_END); if (modifiers.altKey) { void createCalendarEvent(id, start, end); return; } if (modifiers.metaKey) { scheduleTask(id, start, end); return; } setPendingSchedule({ id, start, end, title: task.title }); };
  const confirmSchedule = (kind) => { if (!pendingSchedule) return; if (kind === "time-block") { scheduleTask(pendingSchedule.id, pendingSchedule.start, pendingSchedule.end); setPendingSchedule(null); return; } void createCalendarEvent(pendingSchedule.id, pendingSchedule.start, pendingSchedule.end); setPendingSchedule(null); };
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
      const timelineBody = document.querySelector(".continuous-timeline-body");
      if (!calendar || !timelineBody) return;
      const rect = calendar.getBoundingClientRect();
      if (upEvent.clientX >= rect.left && upEvent.clientX <= rect.right && upEvent.clientY >= rect.top && upEvent.clientY <= rect.bottom) dropTask(id, upEvent.clientY - rect.top + timelineBody.scrollTop, { metaKey: upEvent.metaKey, altKey: upEvent.altKey });
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
    <main className="page plan-page"><header className="plan-header"><h1>Plan <span>·</span> {planDateLabel(planDate)}</h1><DateControls dateKey={planDate} onChange={setDateKey} label="Choose Plan date" /></header>
      <div className="plan-workspace"><MarkdownEditor tasks={tasks} markdown={markdown} planDate={planDate} onMarkdownChange={updateMarkdown} onMarkdownCommit={commitMarkdown} onTaskDragStart={taskDragStart} onPointerDragStart={pointerMoveStart} onSelectTask={setSelectedTaskId} onComplete={completeTask} onReload={reloadPlan} /><CalendarPanel tasks={tasks} neighborPlans={neighborPlans} selectedTaskId={selectedTaskId} setSelectedTaskId={setSelectedTaskId} onDropTask={dropTask} onMoveStart={pointerMoveStart} onComplete={completeTask} onUnschedule={unscheduleTask} onResizeStart={resizeStart} dateKey={planDate} onSelectDate={setDateKey} connected={api.connected} /></div>
      {pendingSchedule ? <div className="schedule-choice-backdrop" role="presentation" onClick={() => setPendingSchedule(null)}><section className="schedule-choice-dialog" role="dialog" aria-modal="true" aria-labelledby="schedule-choice-title" onClick={(event) => event.stopPropagation()}><div><span>Schedule task</span><h2 id="schedule-choice-title">{pendingSchedule.title}</h2><p>{formatRange(pendingSchedule.start, pendingSchedule.end)} · Choose how this drop should be recorded.</p></div><div className="schedule-choice-actions"><button type="button" className="secondary-button" onClick={() => confirmSchedule("event")}>{api.calendarEvents?.authorized ? "Add Event" : "Connect Calendar"} <small>{api.calendarEvents?.authorized ? "Event" : "Permission"}</small></button><button type="button" className="primary-button" onClick={() => confirmSchedule("time-block")}>Time Block</button></div><button type="button" className="schedule-choice-cancel" onClick={() => setPendingSchedule(null)}>Cancel</button></section></div> : null}
      {toast ? <div className="toast" role="status"><CheckCircle size={20} weight="fill" /><span>{toast}</span><IconButton label="Dismiss" onClick={() => setToast("")}><X size={15} /></IconButton></div> : null}
    </main>
  );
}

function formatDurationSeconds(seconds) {
  const minutes = Math.max(0, Math.round(Number(seconds || 0) / 60));
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function trackingDayStart(dateKey, wrapAtMinute = 0) {
  const dayStart = new Date(`${dateKey}T00:00:00`);
  if (!Number.isNaN(dayStart.getTime())) dayStart.setMinutes(Math.max(0, Math.min(1439, Number(wrapAtMinute || 0))));
  return dayStart;
}

function entrySecondsForDate(entry, dateKey, wrapAtMinute = 0) {
  const dayStart = trackingDayStart(dateKey, wrapAtMinute);
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
  const covered = entries.map((entry) => entrySecondsForDate(entry, dateKey, options.wrapAtMinute)).filter(Boolean);
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

function localEntryDateSeconds(dateKey, seconds, wrapAtMinute = 0) {
  const date = trackingDayStart(dateKey, wrapAtMinute);
  if (Number.isNaN(date.getTime())) return null;
  date.setSeconds(Math.round(Number(seconds || 0)));
  return date.toISOString();
}

function billingLabel(value) {
  const labels = { automatic: "Automatic", billable: "Billable", not_billable: "Not billable", notBillable: "Not billable", pending: "Pending", billed: "Billed", paid: "Paid", undetermined: "Undetermined" };
  return labels[value] || value || "Billable";
}

function projectTitleFor(projects, value) {
  const id = resourceID(value);
  return projects.find((project) => resourceID(project.id) === id)?.title || "Unassigned";
}

function projectParentID(project) {
  return resourceID(project?.parent || project?.parent_id || project?.parentID);
}

function normalizedBillingStatus(value) {
  if (value === "notBillable" || value === "not-billable") return "not_billable";
  return value || "billable";
}

function resolvedProjectBillingStatus(projects, projectID) {
  const visited = new Set();
  let currentID = resourceID(projectID);
  while (currentID && !visited.has(currentID)) {
    visited.add(currentID);
    const project = projects.find((candidate) => resourceID(candidate.id) === currentID);
    if (!project) break;
    const status = normalizedBillingStatus(project.default_billing_status);
    if (status !== "automatic") return status;
    currentID = projectParentID(project);
  }
  return "billable";
}

function descendantProjectIDs(projects, projectID) {
  const rootID = resourceID(projectID);
  const ids = new Set(rootID ? [rootID] : []);
  const pending = rootID ? [rootID] : [];
  while (pending.length) {
    const parentID = pending.pop();
    projects.forEach((project) => {
      const id = resourceID(project.id);
      if (projectParentID(project) === parentID && !ids.has(id)) {
        ids.add(id);
        pending.push(id);
      }
    });
  }
  return ids;
}

const projectColorOptions = [
  ["blue", "Blue"],
  ["green", "Green"],
  ["orange", "Orange"],
  ["purple", "Purple"],
  ["red", "Red"],
  ["graphite", "Graphite"]
];

function projectColorKey(project) {
  const raw = String(project?.color || "blue").trim().toLowerCase();
  if (projectColorOptions.some(([value]) => value === raw)) return raw;
  return {
    "#4e5ff2": "blue",
    "#399a55": "green",
    "#d77b22": "orange",
    "#8656d8": "purple",
    "#d24b4b": "red",
    "#555b66": "graphite"
  }[raw] || "blue";
}

function projectOptionRows(projects, excludedID = "") {
  const excluded = new Set();
  const markDescendants = (parentID) => {
    projects.filter((project) => projectParentID(project) === parentID).forEach((project) => {
      const id = resourceID(project.id);
      if (excluded.has(id)) return;
      excluded.add(id);
      markDescendants(id);
    });
  };
  if (excludedID) {
    excluded.add(excludedID);
    markDescendants(excludedID);
  }
  const rows = [];
  const visit = (parentID, depth) => {
    projects
      .filter((project) => !excluded.has(resourceID(project.id)) && projectParentID(project) === parentID)
      .sort((left, right) => String(left.title || "").localeCompare(String(right.title || "")))
      .forEach((project) => {
        const id = resourceID(project.id);
        rows.push({ project, depth });
        visit(id, depth + 1);
      });
  };
  visit("", 0);
  return rows;
}

function ProjectPanel({ api, activities = [], onAssignActivity, onDropActivity, editProjectID, onProjectEditHandled }) {
  const [title, setTitle] = useState("");
  const [rate, setRate] = useState("0");
  const [currency, setCurrency] = useState("USD");
  const [billingStatus, setBillingStatus] = useState("automatic");
  const [parentID, setParentID] = useState("");
  const [teamID, setTeamID] = useState("");
  const [addDefaultNameRules, setAddDefaultNameRules] = useState(true);
  const [editing, setEditing] = useState(null);
  const [message, setMessage] = useState("");
  const [dropTarget, setDropTarget] = useState(null);
  const [showArchivedProjects, setShowArchivedProjects] = useState(false);
  const [archivedProjects, setArchivedProjects] = useState([]);
  const projects = [...api.projects].sort((left, right) => String(left.title || "").localeCompare(String(right.title || "")));
  const teams = [...(api.teams || [])].sort((left, right) => String(left.name || "").localeCompare(String(right.name || "")));
  const parentOptions = projectOptionRows(api.projects);
  const displayedProjects = [...(showArchivedProjects ? [...projects, ...archivedProjects.filter((archived) => !projects.some((project) => resourceID(project.id) === resourceID(archived.id)))] : projects)].sort((left, right) => String(left.title || "").localeCompare(String(right.title || "")));
  const reloadProjectInventory = async () => {
    if (!showArchivedProjects) return;
    try {
      const result = await api.fetchProjects(true);
      setArchivedProjects(result?.data || []);
    } catch (error) {
      setMessage(error.message || "Could not load archived projects.");
    }
  };
  const toggleArchivedProjects = async () => {
    if (showArchivedProjects) {
      setShowArchivedProjects(false);
      return;
    }
    try {
      const result = await api.fetchProjects(true);
      setArchivedProjects(result?.data || []);
      setShowArchivedProjects(true);
    } catch (error) {
      setMessage(error.message || "Could not load archived projects.");
    }
  };
  const create = async (event) => {
    event.preventDefault();
    if (!title.trim()) return;
    try {
      await api.createProject({ title: title.trim(), parent: parentID || null, team_id: teamID || null, billing_rate: Number(rate) || 0, currency: currency.trim().toUpperCase() || "USD", default_billing_status: billingStatus, add_default_name_rules: addDefaultNameRules });
      setTitle("");
      setRate("0");
      setParentID("");
      setTeamID("");
      setAddDefaultNameRules(true);
      setMessage("Project saved locally.");
      await reloadProjectInventory();
    } catch (error) {
      setMessage(error.message || "Could not save the project.");
    }
  };
  const beginEdit = (project) => setEditing({ id: project.id, title: project.title || "", parentID: projectParentID(project), teamID: resourceID(project.team_id) || "", color: projectColorKey(project), productivity: String(Math.round(Number(project.productivity ?? (Number(project.productivity_score || 0) * 100)) || 0)), notes: project.notes || "", rate: String(project.billing_rate || 0), currency: project.currency || "USD", billingStatus: normalizedBillingStatus(project.default_billing_status || "automatic") });
  useEffect(() => {
    if (!editProjectID) return;
    const project = api.projects.find((item) => resourceID(item.id) === resourceID(editProjectID));
    if (project) {
      beginEdit(project);
      document.getElementById("web-projects-panel")?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
    onProjectEditHandled?.();
  }, [editProjectID, api.projects]);
  const saveEdit = async (event) => {
    event.preventDefault();
    if (!editing?.title.trim()) return;
    try {
      await api.updateProject(editing.id, { title: editing.title.trim(), parent: editing.parentID || null, team_id: editing.teamID || null, color: editing.color, productivity: Math.max(-100, Math.min(100, Number(editing.productivity) || 0)), notes: editing.notes, billing_rate: Number(editing.rate) || 0, currency: editing.currency.trim().toUpperCase() || "USD", default_billing_status: editing.billingStatus });
      setEditing(null);
      setMessage("Project updated locally.");
      await reloadProjectInventory();
    } catch (error) {
      setMessage(error.message || "Could not update the project.");
    }
  };
  const remove = async (project) => {
    if (!window.confirm(`Archive project “${project.title}”?`)) return;
    try {
      await api.deleteProject(project.id);
      setMessage("Project archived.");
      await reloadProjectInventory();
    } catch (error) {
      setMessage(error.message || "Could not archive the project.");
    }
  };
  const restore = async (project) => {
    try {
      await api.updateProject(project.id, { is_archived: false });
      setMessage("Project restored.");
      await reloadProjectInventory();
    } catch (error) {
      setMessage(error.message || "Could not restore the project.");
    }
  };
  const dropOnProject = async (event, project) => {
    event.preventDefault();
    setDropTarget(null);
    try {
      const result = onDropActivity
        ? await onDropActivity(event, project)
        : await assignActivitiesFromDrop({ event, activities, project, api, onAssignActivity });
      setMessage(result.message);
    } catch (error) {
      setMessage(error.message || "Could not assign the activity.");
    }
  };
  return <section id="web-projects-panel" className="projects-panel">
    <div className="activities-list-heading"><div><h2>Projects & clients</h2><p>Drag an App / Category row here to assign it; hold ⌥ while dropping to create a future rule.</p></div><div className="activities-list-heading-actions"><button type="button" className="quiet-pill" onClick={toggleArchivedProjects} disabled={!api.connected}>{showArchivedProjects ? "Hide archived" : "Show archived"}</button><span className="api-badge online">{showArchivedProjects ? `${displayedProjects.length} total` : `${projects.length} active`}</span></div></div>
    <form className="project-create-form" onSubmit={create}>
      <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Project or client name" aria-label="Project name" />
      <select value={parentID} onChange={(event) => setParentID(event.target.value)} aria-label="Project parent"><option value="">Top level</option>{parentOptions.map(({ project, depth }) => <option value={resourceID(project.id)} key={project.id}>{"— ".repeat(depth)}{project.title}</option>)}</select>
      <select value={teamID} onChange={(event) => setTeamID(event.target.value)} aria-label="Project team"><option value="">Personal project</option>{teams.map((team) => <option value={resourceID(team.id)} key={team.id}>{team.name}</option>)}</select>
      <input type="number" min="0" step="0.01" value={rate} onChange={(event) => setRate(event.target.value)} placeholder="Rate" aria-label="Project billing rate" />
      <input value={currency} onChange={(event) => setCurrency(event.target.value)} maxLength={3} aria-label="Project currency" />
      <select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Project default billing status"><option value="automatic">Automatic</option><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select>
      <button type="submit" disabled={!api.connected}><Plus size={17} />Add project</button>
    </form>
    <label className="project-auto-rules-toggle"><input type="checkbox" checked={addDefaultNameRules} onChange={(event) => setAddDefaultNameRules(event.target.checked)} /><span>Automatically match this project&apos;s title and path</span><small>Adds title and URL/path rules for future activity.</small></label>
    {message ? <p className="entry-message" role="status">{message}</p> : null}
    {displayedProjects.length > 0 ? <div className="project-table">{displayedProjects.map((project) => editing?.id === project.id ? <form className="project-edit-card" key={project.id} onSubmit={saveEdit}>
      <div className="project-edit-fields">
        <label>Project name<input value={editing.title} onChange={(event) => setEditing((value) => ({ ...value, title: event.target.value }))} aria-label={`Edit ${project.title} name`} /></label>
        <label>Parent project<select value={editing.parentID} onChange={(event) => setEditing((value) => ({ ...value, parentID: event.target.value }))} aria-label={`Edit ${project.title} parent`}><option value="">Top level</option>{projectOptionRows(api.projects, resourceID(project.id)).map(({ project: option, depth }) => <option value={resourceID(option.id)} key={option.id}>{"— ".repeat(depth)}{option.title}</option>)}</select></label>
        <label>Team<select value={editing.teamID} onChange={(event) => setEditing((value) => ({ ...value, teamID: event.target.value }))} aria-label={`Edit ${project.title} team`}><option value="">Personal project</option>{teams.map((team) => <option value={resourceID(team.id)} key={team.id}>{team.name}</option>)}</select></label>
        <label>Color<select value={editing.color} onChange={(event) => setEditing((value) => ({ ...value, color: event.target.value }))} aria-label={`Edit ${project.title} color`}>{projectColorOptions.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
        <label>Productivity<input type="number" min="-100" max="100" step="1" value={editing.productivity} onChange={(event) => setEditing((value) => ({ ...value, productivity: event.target.value }))} aria-label={`Edit ${project.title} productivity`} /></label>
        <label>Billing status<select value={editing.billingStatus} onChange={(event) => setEditing((value) => ({ ...value, billingStatus: event.target.value }))} aria-label={`Edit ${project.title} billing status`}><option value="automatic">Automatic</option><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option></select></label>
        <label>Hourly rate<input type="number" min="0" step="0.01" value={editing.rate} onChange={(event) => setEditing((value) => ({ ...value, rate: event.target.value }))} aria-label={`Edit ${project.title} rate`} /></label>
        <label>Currency<input value={editing.currency} onChange={(event) => setEditing((value) => ({ ...value, currency: event.target.value }))} maxLength={3} aria-label={`Edit ${project.title} currency`} /></label>
        <label className="project-edit-notes">Notes<textarea value={editing.notes} onChange={(event) => setEditing((value) => ({ ...value, notes: event.target.value }))} rows={2} aria-label={`Edit ${project.title} notes`} /></label>
      </div>
      <div className="project-edit-card-actions"><button type="submit" aria-label="Save project"><Check size={16} />Save</button><button type="button" className="secondary-button" onClick={() => setEditing(null)}>Cancel</button></div>
    </form> : <div className={`project-row ${project.is_archived ? "archived" : ""} ${dropTarget === project.id ? "drop-target" : ""}`} key={project.id} onDragOver={(event) => { if (project.is_archived) return; event.preventDefault(); setDropTarget(project.id); }} onDragLeave={() => setDropTarget(null)} onDrop={(event) => { if (!project.is_archived) dropOnProject(event, project); }}><span className="project-dot" style={{ background: project.color || "var(--accent)" }} /><strong>{project.title}</strong><span>{projectParentID(project) ? `↳ ${projectTitleFor(displayedProjects, projectParentID(project))}` : "Top level"}</span><span>{project.currency || "USD"} {Number(project.billing_rate || 0).toFixed(2)}/h</span><small>{project.is_archived ? "Archived" : billingLabel(project.default_billing_status)}</small><span className="project-actions"><IconButton label={`Edit ${project.title}`} onClick={() => beginEdit(project)}><NotePencil size={15} /></IconButton>{project.is_archived ? <IconButton label={`Restore ${project.title}`} onClick={() => restore(project)}><ArrowsClockwise size={15} /></IconButton> : <IconButton label={`Archive ${project.title}`} onClick={() => remove(project)}><Trash size={15} /></IconButton>}</span></div>)}</div> : <div className="entries-empty"><FolderSimple size={24} /><span>{api.connected ? "Create a project to organize time and billing." : "Connect the native app to manage projects."}</span></div>}
  </section>;
}

function TimeEntryEditRow({ entry, api, dateKey, projects, onCancel, dialog = false }) {
  const [title, setTitle] = useState(entry.title || "");
  const [start, setStart] = useState(entryClock(entry.start_date || entry.start));
  const [end, setEnd] = useState(entryClock(entry.end_date || entry.end));
  const [project, setProject] = useState(resourceID(entry.project) || "");
  const [billingStatus, setBillingStatus] = useState(normalizedBillingStatus(entry.billing_status));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [overlapEntries, setOverlapEntries] = useState([]);
  const save = async (event, overlapDecision = null) => {
    event?.preventDefault();
    const startDate = localEntryDate(dateKey, start);
    const endDate = localEntryDate(dateKey, end);
    if (!title.trim() || !startDate || !endDate || new Date(endDate) <= new Date(startDate)) {
      setMessage("Enter a valid title and time range.");
      return;
    }
    const startTime = new Date(startDate).getTime();
    const endTime = new Date(endDate).getTime();
    const overlaps = api.entries.filter((candidate) => {
      if (entryID(candidate) === entryID(entry)) return false;
      const candidateStart = new Date(candidate.start_date || candidate.start).getTime();
      const candidateEnd = new Date(candidate.end_date || candidate.end).getTime();
      return Number.isFinite(candidateStart) && Number.isFinite(candidateEnd) && startTime < candidateEnd && endTime > candidateStart;
    });
    if (overlapDecision === null && overlaps.length > 0) {
      setOverlapEntries(overlaps);
      setMessage(`This range overlaps ${overlaps.length} existing time ${overlaps.length === 1 ? "entry" : "entries"}.`);
      return;
    }
    setBusy(true);
    try {
      await api.updateTimeEntry(entry.id, { title: title.trim(), start_date: startDate, end_date: endDate, project: project || "", billing_status: billingStatus, replace_overlapping: overlapDecision === "replace" });
      setOverlapEntries([]);
      onCancel();
    } catch (error) {
      setMessage(error.message || "Could not update the time entry.");
    } finally {
      setBusy(false);
    }
  };
  const fields = <>
    {dialog ? <label>Title<input value={title} onChange={(event) => setTitle(event.target.value)} aria-label="Edit time entry title" /></label> : <input value={title} onChange={(event) => setTitle(event.target.value)} aria-label="Edit time entry title" />}
    {dialog ? <div className="entry-omatic-options"><label>From<input type="time" value={start} onChange={(event) => setStart(event.target.value)} aria-label="Edit time entry start" /></label><label>To<input type="time" value={end} onChange={(event) => setEnd(event.target.value)} aria-label="Edit time entry end" /></label></div> : <><input type="time" value={start} onChange={(event) => setStart(event.target.value)} aria-label="Edit time entry start" /><input type="time" value={end} onChange={(event) => setEnd(event.target.value)} aria-label="Edit time entry end" /></>}
    {dialog ? <label>Project<select value={project} onChange={(event) => setProject(event.target.value)} aria-label="Edit time entry project"><option value="">Unassigned</option>{projects.map((item) => <option key={item.id} value={resourceID(item.id)}>{item.title}</option>)}</select></label> : <select value={project} onChange={(event) => setProject(event.target.value)} aria-label="Edit time entry project"><option value="">Unassigned</option>{projects.map((item) => <option key={item.id} value={resourceID(item.id)}>{item.title}</option>)}</select>}
    {dialog ? <label>Billing status<select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Edit time entry billing status"><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option><option value="undetermined">Undetermined</option></select></label> : <select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)} aria-label="Edit time entry billing status"><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option><option value="undetermined">Undetermined</option></select>}
  </>;
  return <form className={dialog ? "time-entry-edit-form" : "entry-edit-row"} onSubmit={save} onKeyDown={(event) => { if (event.key === "Escape") { event.preventDefault(); onCancel(); } }}>{fields}{overlapEntries.length > 0 ? <div className="time-entry-overlap-callout" role="alert"><strong>Overlapping Time Entry</strong><p>This range overlaps {overlapEntries.length} existing time {overlapEntries.length === 1 ? "entry" : "entries"}. Replace them or keep parallel entries?</p><div><button type="button" className="secondary-button" onClick={() => { setOverlapEntries([]); setMessage(""); }}>Cancel</button><button type="button" className="secondary-button" onClick={() => save(null, "keep")} disabled={busy}>Keep Both</button><button type="button" className="secondary-button danger-pill" onClick={() => save(null, "replace")} disabled={busy}>Replace Existing</button></div></div> : null}<span className={dialog ? "time-entry-edit-actions" : "project-actions"}><button type="submit" disabled={busy} aria-label="Save time entry">{dialog ? "Save changes" : <Check size={16} />}</button><IconButton label="Cancel time entry edit" onClick={onCancel}>{dialog ? "Cancel" : <X size={15} />}</IconButton></span>{message ? <small className="entry-edit-message">{message}</small> : null}</form>;
}

function TimeEntriesPanel({ api, dateKey, onNewEntry = () => window.dispatchEvent(new CustomEvent("metriday:open-new-time-entry")) }) {
  const [message, setMessage] = useState("");
  const [editingEntryID, setEditingEntryID] = useState(null);
  const [selectedEntryIDs, setSelectedEntryIDs] = useState(() => new Set());
  const entries = [...api.entries].sort((left, right) => new Date(left.start_date || left.start) - new Date(right.start_date || right.start));
  const projects = [...api.projects].sort((left, right) => String(left.title || "").localeCompare(String(right.title || "")));
  const selectableEntries = entries.filter((entry) => !entry.is_running);
  const selectedEntries = selectableEntries.filter((entry) => selectedEntryIDs.has(entryID(entry)));
  const allSelectableEntriesSelected = selectableEntries.length > 0 && selectedEntries.length === selectableEntries.length;
  useEffect(() => {
    setSelectedEntryIDs(new Set());
  }, [dateKey]);
  const toggleSelected = (entry) => {
    const id = entryID(entry);
    setSelectedEntryIDs((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };
  const toggleAll = () => {
    setSelectedEntryIDs(allSelectableEntriesSelected ? new Set() : new Set(selectableEntries.map(entryID)));
  };
  const applyBillingStatus = async (billingStatus) => {
    if (selectedEntries.length === 0) return;
    try {
      await api.batchUpdateTimeEntries(selectedEntries.map(entryID), billingStatus);
      setMessage(`Updated billing status for ${selectedEntries.length} time ${selectedEntries.length === 1 ? "entry" : "entries"}.`);
      setSelectedEntryIDs(new Set());
    } catch (error) {
      setMessage(error.message || "Could not update billing status.");
    }
  };
  return <section className="time-entries-panel"><div className="activities-list-heading"><div><h2>Time entries</h2><p>{selectedEntries.length > 0 ? `${selectedEntries.length} selected · choose a billing status to update them together.` : `Manual entries and focus sessions for ${planDateLabel(dateKey)}.`}</p></div><div className="activities-list-heading-actions">{selectableEntries.length > 0 ? <><button type="button" className="quiet-pill" onClick={toggleAll}>{allSelectableEntriesSelected ? "Clear selection" : "Select all"}</button>{selectedEntries.length > 0 ? <select className="entry-bulk-status" value="" onChange={(event) => { if (event.target.value) applyBillingStatus(event.target.value); }} aria-label="Set billing status for selected time entries"><option value="">Set billing status…</option><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option><option value="undetermined">Undetermined</option></select> : null}</> : null}<button type="button" className="quiet-pill" onClick={onNewEntry} disabled={!api.connected}><Plus size={16} />New time entry</button><span className="api-badge online">{entries.length} saved</span></div></div>{message ? <p className="entry-message" role="status">{message}</p> : null}{entries.length > 0 ? <div className="entry-table">{entries.map((entry) => editingEntryID === entry.id ? <TimeEntryEditRow key={entry.id} entry={entry} api={api} dateKey={dateKey} projects={projects} onCancel={() => setEditingEntryID(null)} /> : <WebTimeEntryRow key={entry.id} entry={entry} projects={projects} selected={selectedEntryIDs.has(entryID(entry))} onToggleSelect={() => toggleSelected(entry)} onEdit={() => setEditingEntryID(entry.id)} onDelete={() => api.deleteTimeEntry(entryID(entry)).catch((error) => setMessage(error.message || "Could not delete the time entry."))} />)}</div> : <div className="entries-empty"><Clock size={24} /><span>{api.connected ? "No manual entries for this date." : "Connect the native app to edit time entries."}</span></div>}</section>;
}

function WebTimeEntryRow({ entry, projects, selected = false, onToggleSelect = () => {}, onEdit, onDelete }) {
  const title = entry.title || "Untitled";
  const interactive = !entry.is_running;
  const open = () => { if (interactive) onEdit(); };
  const handleKeyDown = (event) => {
    if (!interactive || (event.key !== "Enter" && event.key !== " ")) return;
    event.preventDefault();
    open();
  };
  return <div className={`entry-table-row ${interactive ? "interactive" : ""} ${selected ? "selected" : ""}`} role={interactive ? "button" : undefined} tabIndex={interactive ? 0 : undefined} aria-label={interactive ? `Edit time entry ${title}` : undefined} onClick={open} onKeyDown={handleKeyDown}>{interactive ? <button type="button" className="entry-select" aria-label={selected ? `Deselect ${title}` : `Select ${title}`} aria-pressed={selected} onClick={(event) => { event.stopPropagation(); onToggleSelect(); }}><CheckCircle weight={selected ? "fill" : "regular"} /></button> : <span className="entry-select-placeholder" aria-hidden="true" />}<Clock size={17} /><strong>{title}</strong><span>{projectTitleFor(projects, entry.project)}</span><span>{entryRange(entry)}</span><small>{billingLabel(entry.billing_status)} · {formatDurationSeconds(entry.duration)}</small>{entry.is_running ? <span className="entry-running">Running</span> : <span className="project-actions"><IconButton label={`Edit ${title}`} onClick={(event) => { event.stopPropagation(); onEdit(); }}><NotePencil size={15} /></IconButton><IconButton label={`Delete ${title}`} onClick={(event) => { event.stopPropagation(); onDelete(); }}><Trash size={15} /></IconButton></span>}</div>;
}

function ReviewPage({ api, dateKey, setDateKey, setPage }) {
  const fallbackDays = [{ label: "Mon", planned: 7.2, actual: 6.6 }, { label: "Tue", planned: 6.5, actual: 7.1 }, { label: "Wed", planned: 7.8, actual: 6.9 }, { label: "Thu", planned: 6.2, actual: 5.8 }, { label: "Fri", planned: 7.1, actual: 6.5 }, { label: "Sat", planned: 5.5, actual: 4.8 }, { label: "Sun", planned: 4.8, actual: 4.2 }];
  const reviewWeekly = api.calendarWeekly.length >= 7 ? api.calendarWeekly : api.weekly;
  const selectedDevice = api.activityPreferences?.selected_device || "All Devices";
  const days = reviewWeekly.length >= 7 ? reviewWeekly.slice(-7).map((day) => {
    const plannedMinutes = (day.plan?.tasks || []).reduce((total, task) => total + (Number.isFinite(task.start_minute) && Number.isFinite(task.end_minute) ? Math.max(0, task.end_minute - task.start_minute) : 0), 0);
    const activities = (day.activities || []).filter((activity) => activityMatchesSelectedDevice(activity, selectedDevice));
    const activeSeconds = activities.reduce((total, activity) => total + (activity.relevance === "idle" ? 0 : Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0))), 0);
    return { date: day.date, label: new Date(`${day.date}T12:00:00`).toLocaleDateString(undefined, { weekday: "short" }), planned: plannedMinutes / 60, actual: activeSeconds / 3600, activities, entries: day.entries || [] };
  }) : fallbackDays;
  const selectedActivities = api.activities.filter((activity) => activityMatchesSelectedDevice(activity, selectedDevice));
  const relatedSeconds = selectedActivities.filter((activity) => activity.relevance === "related").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const distractedSeconds = selectedActivities.filter((activity) => activity.relevance === "distracted").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const totalActive = relatedSeconds + distractedSeconds + selectedActivities.filter((activity) => activity.relevance === "other").reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const taskRelated = totalActive > 0 ? Math.round((relatedSeconds / totalActive) * 100) : 0;
  const productivityScore = totalActive > 0 ? Math.round(selectedActivities.filter((activity) => activity.relevance !== "idle").reduce((total, activity) => total + activityProductivityValue(activity, api.projects) * Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0) / totalActive) : 0;
  const deepWork = api.connected ? formatDurationSeconds(relatedSeconds) : "22h 14m";
  const distraction = api.connected ? formatDurationSeconds(distractedSeconds) : "91%";
  const categoryActivities = api.connected
    ? (api.calendarWeekly.length >= 7 ? api.calendarWeekly.flatMap((day) => (day.activities || []).filter((activity) => activityMatchesSelectedDevice(activity, selectedDevice))) : selectedActivities)
    : [];
  const categoryRows = api.connected ? [...categoryActivities.reduce((groups, activity) => {
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
  return <main className="page supporting-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? `Live · ${planDateLabel(dateKey)}` : "This week"}</span><h1>Review with evidence</h1></div><div className="activities-page-actions"><DateControls dateKey={dateKey} onChange={setDateKey} label="Choose Review date" /><button type="button" className="quiet-pill" onClick={() => setPage?.("reports")}>Report Builder</button><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : api.connected ? "Refresh" : "Preview"}</button></div></header><section className="review-summary"><div><TrendUp size={26} /><span>Productivity score</span><strong>{api.connected ? `${productivityScore}%` : "86%"}</strong><small>{api.connected ? `${taskRelated}% task-related today` : "Weighted task relevance"}</small></div><div><Timer size={26} /><span>Deep work</span><strong>{deepWork}</strong><small>{api.connected ? "Related app time" : "+2h 06m from last week"}</small></div><div><ShieldCheck size={26} /><span>Distraction</span><strong>{distraction}</strong><small>{api.connected ? "Detected locally" : "6 distractions blocked"}</small></div><div><Clock size={26} /><span>Time entries</span><strong>{formatDurationSeconds(api.entries.reduce((total, entry) => total + Number(entry.duration || 0), 0))}</strong><small>Manual + timer</small></div></section><section className="review-evidence-grid"><section className="weekly-chart"><div className="chart-heading"><div><h2>Planned vs. actual</h2><p>{api.connected ? "Seven-day evidence from the native activity and Markdown plan stores." : "Longer actual bars reveal underestimated work."}</p></div><div className="legend"><span><i className="planned" />Planned</span><span><i className="actual" />Actual</span></div></div><div className="bar-chart">{days.map((day) => <div key={day.label} className="bar-day"><div className="bar-pair"><i className="planned" style={{ height: `${Math.max(4, Math.min(9, day.planned) * 20)}px` }} /><i className="actual" style={{ height: `${Math.max(4, Math.min(9, day.actual) * 20)}px` }} /></div><span>{day.label}</span></div>)}</div></section><section className="review-category-panel"><div className="chart-heading"><div><h2>Category pulse</h2><p>App and website time grouped by the same Focused / Distracting rules used in Activities.</p></div><span className="api-badge online">{formatDurationSeconds(categoryTotal)} active</span></div><div className="review-category-list">{categoryRows.map((category) => { const share = categoryTotal > 0 ? Math.round((category.seconds / categoryTotal) * 100) : 0; const color = activityCategoryStyle(category).color; return <div className="review-category-row" key={`${category.key}:${category.label}`}><div className="review-category-heading"><span className={`activity-category ${category.key}`} style={activityCategoryStyle(category)}><i />{category.label}</span><strong>{share}%</strong><small>{formatDurationSeconds(category.seconds)}</small></div><div className="review-category-track"><i style={{ width: `${Math.max(2, share)}%`, background: color }} /></div></div>; })}</div></section></section>{api.connected ? <WebActivityInsights insights={api.insights} dateKey={dateKey} /> : null}<WebReviewDetails api={api} days={days} /></main>;
}

function WebReviewDetails({ api, days }) {
  const activities = days.flatMap((day) => (day.activities || []).map((activity) => ({ ...activity, date: day.date })));
  const entries = days.flatMap((day) => day.entries || []);
  const secondsForActivity = (activity) => Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
  const dayRows = days.map((day, index) => {
    const dayActivities = (day.activities || []).map((activity) => ({ ...activity, date: day.date }));
    const active = dayActivities.filter((activity) => activityCategory(activity).key !== "idle");
    const related = active.filter((activity) => activityCategory(activity).key === "focused").reduce((total, activity) => total + secondsForActivity(activity), 0);
    const distracted = active.filter((activity) => activityCategory(activity).key === "distracting").reduce((total, activity) => total + secondsForActivity(activity), 0);
    return { date: day.date || `fallback-${index}`, label: day.label || new Date(`${day.date}T12:00:00`).toLocaleDateString(undefined, { weekday: "short" }), related, distracted };
  });
  const maxDay = Math.max(1, ...dayRows.map((row) => Math.max(row.related, row.distracted)));
  const applicationRows = [...activities.filter((activity) => activityCategory(activity).key !== "idle").reduce((groups, activity) => {
    const category = activityCategory(activity);
    const name = activityDisplayTitle(activity) || "Unknown App";
    const key = `${name}:${category.key}:${category.label}`;
    const current = groups.get(key) || { name, category, icon: activityIcon(activity), seconds: 0 };
    current.seconds += secondsForActivity(activity);
    groups.set(key, current);
    return groups;
  }, new Map()).values()].sort((left, right) => right.seconds - left.seconds).slice(0, 8);
  const hourRows = Array.from({ length: 24 }, (_, hour) => {
    const hourActivities = activities.filter((activity) => activityCategory(activity).key !== "idle" && Math.min(23, Math.max(0, Math.floor(Number(activity.startSecond || 0) / 3600))) === hour);
    const active = hourActivities.reduce((total, activity) => total + secondsForActivity(activity), 0);
    const related = hourActivities.filter((activity) => activityCategory(activity).key === "focused").reduce((total, activity) => total + secondsForActivity(activity), 0);
    const distracted = hourActivities.filter((activity) => activityCategory(activity).key === "distracting").reduce((total, activity) => total + secondsForActivity(activity), 0);
    return { hour, active, related, distracted };
  });
  const maxHour = Math.max(1, ...hourRows.map((row) => row.active));
  const projectAmounts = new Map();
  const projectCurrencies = new Map();
  const addProjectAmount = (projectValue, key, seconds) => {
    const project = api.projects.find((item) => resourceID(item.id) === resourceID(projectValue));
    const rate = Number(project?.billing_rate || 0);
    if (!project || !rate || seconds <= 0) return;
    projectAmounts.set(key, (projectAmounts.get(key) || 0) + seconds / 3600 * rate);
    projectCurrencies.set(key, project.currency || "USD");
  };
  const projectTotals = activities.filter((activity) => activityCategory(activity).key !== "idle").reduce((groups, activity) => {
    const key = projectTitleFor(api.projects, activity.projectID);
    const seconds = secondsForActivity(activity);
    groups.set(key, (groups.get(key) || 0) + seconds);
    addProjectAmount(activity.projectID, key, seconds);
    return groups;
  }, new Map());
  entries.forEach((entry) => {
    const key = projectTitleFor(api.projects, entry.project);
    const seconds = Math.max(0, Number(entry.duration || 0));
    projectTotals.set(key, (projectTotals.get(key) || 0) + seconds);
    addProjectAmount(entry.project, key, seconds);
  });
  const projectRows = [...projectTotals.entries()].sort((left, right) => right[1] - left[1]).slice(0, 10);
  const projectAmountLabel = (name) => {
    const amount = projectAmounts.get(name) || 0;
    if (amount <= 0) return "";
    return new Intl.NumberFormat(undefined, { style: "currency", currency: projectCurrencies.get(name) || "USD" }).format(amount);
  };
  const exportCSV = () => {
    const header = ["Kind", "Date", "Title", "Project", "Category", "Start", "End", "Duration Seconds"];
    const activityRows = activities.filter((activity) => activityCategory(activity).key !== "idle").map((activity) => ["Activity", activity.date, activityLabel(activity), projectTitleFor(api.projects, activity.projectID), activityCategory(activity).label, activity.startSecond, activity.endSecond, secondsForActivity(activity)]);
    const entryRows = entries.map((entry) => ["Time entry", (entry.start_date || entry.start || "").slice(0, 10), entry.title || "Untitled", projectTitleFor(api.projects, entry.project), "Time entry", entry.start_date || entry.start, entry.end_date || entry.end, Number(entry.duration || 0)]);
    const csv = [header, ...activityRows, ...entryRows].map((row) => row.map(reportCell).join(",")).join("\n");
    downloadReport("metriday-review.csv", csv, "text/csv;charset=utf-8");
  };
  return <>
    <section className="review-detail-panel review-weekly-quality"><div className="chart-heading"><div><h2>Weekly focus quality</h2><p>Focused and Distracting minutes from the same App / Category evidence.</p></div><div className="review-detail-actions"><button type="button" onClick={exportCSV}>Export CSV</button></div></div><div className="review-quality-chart">{dayRows.map((row) => <div className="review-quality-day" key={row.date}><div className="review-quality-pair"><i className="focused" style={{ height: Math.max(4, (row.related / maxDay) * 100) + "%" }} /><i className="distracting" style={{ height: Math.max(4, (row.distracted / maxDay) * 100) + "%" }} /></div><span>{row.label}</span></div>)}</div><div className="legend"><span><i className="focused" />Focused</span><span><i className="distracting" />Distracting</span></div></section>
    <section className="review-detail-grid"><section className="review-detail-panel"><div className="chart-heading"><div><h2>Applications &amp; Websites</h2><p>Top App / Category sources this week.</p></div><span className="api-badge">Top 8</span></div><div className="review-ranking">{applicationRows.length ? applicationRows.map((row) => { const Icon = row.icon; return <div className="review-ranking-row" key={`${row.name}:${row.category.label}`}><div><span className="activity-table-icon review-ranking-icon"><Icon size={16} weight="duotone" /></span><strong>{row.name}</strong><small className={`activity-category ${row.category.key}`} style={activityCategoryStyle(row.category)}><i />{row.category.label}</small></div><span><b style={{ width: Math.max(4, (row.seconds / Math.max(1, applicationRows[0].seconds)) * 100) + "%", background: activityCategoryStyle(row.category).color }} /></span><em>{formatDurationSeconds(row.seconds)}</em></div>; }) : <div className="entries-empty"><Browsers size={22} /><span>No active application time this week.</span></div>}</div></section><section className="review-detail-panel"><div className="chart-heading"><div><h2>Hourly focus</h2><p>Focused, Distracting, and other active time by hour.</p></div></div><div className="review-hour-chart">{hourRows.map((row) => <div className="review-hour-column" key={row.hour} title={`${String(row.hour).padStart(2, "0")}:00 · ${formatDurationSeconds(row.active)}`}><div className="review-hour-track"><i className="focused" style={{ height: Math.max(2, (row.related / maxHour) * 100) + "%" }} /><i className="distracting" style={{ height: Math.max(2, (row.distracted / maxHour) * 100) + "%" }} /></div><span>{row.hour % 6 === 0 || row.hour === 23 ? String(row.hour).padStart(2, "0") : ""}</span></div>)}</div></section></section>
    <section className="review-detail-grid"><section className="review-detail-panel"><div className="chart-heading"><div><h2>Projects &amp; Time Entries</h2><p>Tracked activity and manual/timer entries.</p></div><span className="api-badge">{formatDurationSeconds(projectRows.reduce((total, row) => total + row[1], 0))}</span></div><div className="review-ranking">{projectRows.length ? projectRows.map(([name, seconds]) => <div className="review-detail-project-row" key={name}><span><i />{name}</span><span className="review-project-total"><strong>{formatDurationSeconds(seconds)}</strong>{projectAmountLabel(name) ? <small>{projectAmountLabel(name)}</small> : null}</span></div>) : <div className="entries-empty"><FolderSimple size={22} /><span>No project-assigned activity yet.</span></div>}</div></section><section className="review-detail-panel review-notes"><div className="chart-heading"><div><h2>Next actions</h2><p>Keep the evidence loop actionable.</p></div><Sparkle size={20} color="#4e5ff2" /></div><ul><li>Assign recurring App / Category activity to a project.</li><li>Use New Time Entry for meetings or time away from the Mac.</li><li>Reports use the same local activity and time-entry source.</li></ul></section></section>
  </>;
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

const reportColumnOptions = [
  ["date", "Date"],
  ["type", "Type"],
  ["project", "Project"],
  ["group", "Group"],
  ["application", "Application"],
  ["title", "Title"],
  ["device", "Device"],
  ["resource", "URL or Path"],
  ["start", "Start"],
  ["end", "End"],
  ["duration", "Duration"],
  ["billingStatus", "Billing Status"],
  ["billingAmount", "Amount"],
  ["notes", "Notes"],
];

function WebReportPanel({ api, dateKey }) {
  const [rangeStart, setRangeStart] = useState(offsetDateKey(dateKey, -6));
  const [rangeEnd, setRangeEnd] = useState(dateKey);
  const [projectIDs, setProjectIDs] = useState([]);
  const [reportPreset, setReportPreset] = useState("timesheet");
  const [reportMode, setReportMode] = useState("advanced");
  const [includeMode, setIncludeMode] = useState("both");
  const [groupBy, setGroupBy] = useState("exact");
  const [billingFilter, setBillingFilter] = useState("all");
  const [rounding, setRounding] = useState("none");
  const [roundingInterval, setRoundingInterval] = useState(15);
  const [durationFormat, setDurationFormat] = useState("decimalMinutes");
  const [includeShortEntries, setIncludeShortEntries] = useState(true);
  const [includeCoveredAppUsage, setIncludeCoveredAppUsage] = useState(false);
  const [roundIndividualEntries, setRoundIndividualEntries] = useState(true);
  const [reportColumns, setReportColumns] = useState(() => reportColumnOptions.map(([key]) => key));
  const [dataset, setDataset] = useState({ activities: [], entries: [] });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const controlsRef = useRef(null);
  const selectedDevice = api.activityPreferences?.selected_device || "All Devices";
  useEffect(() => {
    const weekStart = weekStartDateKey(dateKey);
    setRangeStart(weekStart);
    setRangeEnd(offsetDateKey(weekStart, 6));
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
    { key: "timesheet", label: "Timesheet", include: "both", group: "project", icon: CalendarBlank },
    { key: "timesheet-week-day", label: "Timesheet (Week + Day)", include: "both", group: "weekAndDay", icon: CalendarBlank },
    { key: "weekly-snippet", label: "Weekly Snippet", include: "both", group: "week", icon: CalendarBlank },
    { key: "time-project", label: "Time Per Project", include: "both", group: "project", icon: FolderSimple },
    { key: "time-application", label: "Time Per Application", include: "app", group: "application", icon: Browsers },
    { key: "time-document", label: "Time Per Document", include: "app", group: "document", icon: FileText },
    { key: "ultra-detailed", label: "Ultra-Detailed", include: "both", group: "exact", icon: ChartBar },
    { key: "raw-time-entries", label: "Raw Time Entries", include: "time", group: "exact", icon: Clock },
    { key: "raw-app-usage", label: "Raw App Usage", include: "app", group: "exact", icon: Waveform },
  ];
  const report = useMemo(() => {
    const startBound = new Date(`${rangeStart}T00:00:00`);
    const endBound = new Date(`${offsetDateKey(rangeEnd, 1)}T00:00:00`);
    const projectFor = (value) => projectTitleFor(api.projects, value);
    const projectPathFor = (value) => {
      const path = [];
      const seen = new Set();
      let current = api.projects.find((project) => resourceID(project.id) === resourceID(value) || (project.title || project.name || "") === String(value || ""));
      while (current && !seen.has(resourceID(current.id))) {
        seen.add(resourceID(current.id));
        path.unshift(current.title || current.name || "Untitled project");
        const parentID = resourceID(current.parent || current.parent_id || current.parentID);
        current = parentID ? api.projects.find((project) => resourceID(project.id) === parentID) : null;
      }
      return path.length ? path.join(" > ") : "Unassigned";
    };
    const projectDetails = (value) => {
      const project = api.projects.find((item) => resourceID(item.id) === resourceID(value));
      return { rate: project?.billing_rate || 0, currency: project?.currency || "USD" };
    };
    const selectedProjectIDs = new Set(projectIDs.flatMap((projectID) => [...descendantProjectIDs(api.projects, projectID)]));
    const includesProject = (value) => projectIDs.length === 0 || selectedProjectIDs.has(resourceID(value));
    const coveredRanges = dataset.entries
      .map((entry) => ({ start: new Date(entry.start_date || entry.start), end: new Date(entry.end_date || entry.end) }))
      .filter((range) => !Number.isNaN(range.start.getTime()) && !Number.isNaN(range.end.getTime()) && range.end > range.start);
    const uncoveredRanges = (start, end) => {
      if (includeCoveredAppUsage || includeMode !== "both") return [{ start, end }];
      let pieces = [{ start, end }];
      coveredRanges.forEach((covered) => {
        const next = [];
        pieces.forEach((piece) => {
          if (covered.end <= piece.start || covered.start >= piece.end) {
            next.push(piece);
            return;
          }
          if (piece.start < covered.start) next.push({ start: piece.start, end: covered.start });
          if (covered.end < piece.end) next.push({ start: covered.end, end: piece.end });
        });
        pieces = next.filter((piece) => piece.end > piece.start);
      });
      return pieces;
    };
    const rows = [];
    if (includeMode !== "app") dataset.entries.forEach((entry) => {
      const start = new Date(entry.start_date || entry.start);
      const end = new Date(entry.end_date || entry.end);
      if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end <= start || end <= startBound || start >= endBound) return;
      if (!includesProject(entry.project)) return;
      if (billingFilter !== "all" && entry.billing_status !== billingFilter) return;
      const clippedStart = start < startBound ? startBound : start;
      const clippedEnd = end > endBound ? endBound : end;
      const rawSeconds = Math.max(0, (clippedEnd - clippedStart) / 1000);
      const seconds = roundIndividualEntries ? reportRoundSeconds(rawSeconds, rounding, Number(roundingInterval)) : rawSeconds;
      const details = projectDetails(entry.project);
      rows.push({ kind: "Time entry", type: entry.is_manual ? "Time Entry" : "Timer", title: entry.title || "Untitled", project: projectFor(entry.project), group: "", application: "", device: "This Mac", resource: entry.notes || "", billing: billingLabel(entry.billing_status), currency: details.currency, start: clippedStart, end: clippedEnd, seconds, amount: seconds / 3600 * details.rate, notes: entry.notes || "" });
    });
    if (includeMode !== "time" && billingFilter === "all") {
      dataset.activities.forEach((activity) => {
        if (activity.relevance === "idle") return;
        if (!activityMatchesSelectedDevice(activity, selectedDevice)) return;
        if (!includesProject(activity.projectID)) return;
        const start = reportDateTime(activity.date, activity.startSecond);
        const end = reportDateTime(activity.date, activity.endSecond);
        if (end <= startBound || start >= endBound || end <= start) return;
        const clippedStart = start < startBound ? startBound : start;
        const clippedEnd = end > endBound ? endBound : end;
        uncoveredRanges(clippedStart, clippedEnd).forEach((piece) => {
          const rawSeconds = Math.max(0, (piece.end - piece.start) / 1000);
          if (!includeShortEntries && rawSeconds < 60) return;
          const seconds = roundIndividualEntries ? reportRoundSeconds(rawSeconds, rounding, Number(roundingInterval)) : rawSeconds;
          const details = projectDetails(activity.projectID);
          rows.push({ kind: "Activity", type: "App Usage", title: activity.windowTitle || activity.appName || activity.deviceName || "Activity", project: projectFor(activity.projectID), group: "", application: activity.appName || activity.deviceName || "", device: activity.deviceName || "This Mac", resource: activity.resource || "", billing: "", currency: details.currency, start: piece.start, end: piece.end, seconds, amount: seconds / 3600 * details.rate, notes: "" });
        });
      });
    }
    rows.sort((left, right) => left.start - right.start);
    rows.forEach((row) => { row.billableSeconds = row.billing === "Billable" ? row.seconds : 0; });
    const groupedRows = groupBy === "exact" ? rows : [...rows.reduce((groups, row) => {
      const application = row.kind === "Activity" ? row.application : "Time entries";
      const document = row.notes || row.title;
      const rowDate = localDateKey(row.start);
      const projectPath = projectPathFor(row.project);
      const projectComponents = projectPath.split(" > ");
      const hour = String(row.start.getHours()).padStart(2, "0");
      const key = groupBy === "project" ? row.project : groupBy === "topLevelProject" ? projectComponents[0] : groupBy === "secondLevelProject" ? (projectComponents[1] || projectComponents[0]) : groupBy === "projectHierarchy" ? projectPath : groupBy === "application" ? application : groupBy === "document" ? document : groupBy === "day" ? row.start.toLocaleDateString() : groupBy === "weekAndDay" ? `Week of ${weekStartDateKey(rowDate)} / ${row.start.toLocaleDateString()}` : groupBy === "week" ? `Week of ${weekStartDateKey(rowDate)}` : groupBy === "month" ? rowDate.slice(0, 7) : groupBy === "year" ? rowDate.slice(0, 4) : groupBy === "hour" ? `${rowDate} ${hour}:00` : row.start.toLocaleDateString();
      const current = groups.get(key) || { ...row, kind: "Summary", type: "Grouped", title: "", displayTitle: key, group: key, seconds: 0, billableSeconds: 0, amount: 0, notes: "" };
      current.seconds += row.seconds;
      current.billableSeconds += row.billableSeconds;
      current.amount += row.amount;
      current.start = current.start < row.start ? current.start : row.start;
      current.end = current.end > row.end ? current.end : row.end;
      current.billing = current.billing === row.billing ? row.billing : "Mixed";
      groups.set(key, current);
      return groups;
    }, new Map()).values()].sort((left, right) => left.start - right.start);
    const finalRows = groupBy === "exact" || roundIndividualEntries || rounding === "none"
      ? groupedRows
      : groupedRows.map((row) => ({ ...row, seconds: reportRoundSeconds(row.seconds, rounding, Number(roundingInterval)) }));
    return { rows: finalRows, totalSeconds: finalRows.reduce((sum, row) => sum + row.seconds, 0), billableSeconds: finalRows.reduce((sum, row) => sum + row.billableSeconds, 0), amount: finalRows.reduce((sum, row) => sum + row.amount, 0), currencies: [...new Set(finalRows.map((row) => row.currency).filter(Boolean))] };
  }, [api.projects, billingFilter, dataset, groupBy, includeCoveredAppUsage, includeMode, includeShortEntries, projectIDs, rangeEnd, rangeStart, roundIndividualEntries, rounding, roundingInterval, selectedDevice]);
  const setDatePreset = (preset) => {
    if (preset === "today") {
      setRangeStart(dateKey);
      setRangeEnd(dateKey);
    } else if (preset === "month") {
      const date = new Date(`${dateKey}T12:00:00`);
      date.setDate(1);
      setRangeStart(localDateKey(date));
      setRangeEnd(dateKey);
    } else if (preset === "week") {
      const weekStart = weekStartDateKey(dateKey);
      setRangeStart(weekStart);
      setRangeEnd(offsetDateKey(weekStart, 6));
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
  const formatReportDuration = (seconds) => {
    const value = Math.max(0, Number(seconds || 0));
    if (durationFormat === "hms") return preciseClock(value);
    if (durationFormat === "seconds") return value.toFixed(2) + "s";
    if (durationFormat === "decimalHours") return (value / 3600).toFixed(2) + "h";
    if (durationFormat === "decimalMinutes") return (value / 60).toFixed(2) + "m";
    return formatDurationSeconds(value);
  };
  const formatReportExportDuration = (seconds) => {
    const value = Math.max(0, Math.round(Number(seconds || 0)));
    if (durationFormat === "hms") return preciseClock(value);
    if (durationFormat === "seconds") return String(value);
    if (durationFormat === "decimalHours") return (value / 3600).toFixed(3);
    if (durationFormat === "decimalMinutes") return (value / 60).toFixed(2);
    const hours = Math.floor(value / 3600);
    const minutes = Math.floor(value / 60) % 60;
    const remainder = value % 60;
    if (hours > 0) return `${hours}h ${minutes}m ${remainder}s`;
    if (minutes > 0) return `${minutes}m ${remainder}s`;
    return `${remainder}s`;
  };
  const formatReportExportTime = (value) => value.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false });
  const exportRows = report.rows.map((row) => ({
    date: localDateKey(row.start),
    type: row.type || row.kind,
    project: row.project,
    group: row.group || "",
    application: row.application || "",
    title: row.title,
    device: row.device || "This Mac",
    resource: row.resource || "",
    start: formatReportExportTime(row.start),
    end: formatReportExportTime(row.end),
    duration: formatReportExportDuration(row.seconds),
    billingStatus: row.billing || "",
    billingAmount: `${row.currency || "USD"} ${row.amount.toFixed(2)}`,
    notes: row.notes || "",
  }));
  const selectedReportColumns = reportColumnOptions.filter(([key]) => reportColumns.includes(key));
  const exportCSV = () => {
    const headers = selectedReportColumns.map(([, label]) => label);
    const csv = [headers, ...exportRows.map((row) => selectedReportColumns.map(([key]) => row[key]))].map((line) => line.map(reportCell).join(",")).join("\n");
    downloadReport(`metriday-report-${rangeStart}-${rangeEnd}.csv`, csv, "text/csv;charset=utf-8");
  };
  const exportJSON = () => downloadReport(`metriday-report-${rangeStart}-${rangeEnd}.json`, JSON.stringify({ startDate: rangeStart, endDate: rangeEnd, durationFormat, columns: selectedReportColumns.map(([key]) => key), totalSeconds: report.totalSeconds, billableSeconds: report.billableSeconds, amount: Number(report.amount.toFixed(2)), currencies: report.currencies, rows: exportRows.map((row) => Object.fromEntries(selectedReportColumns.map(([key]) => [key, row[key]]))) }, null, 2), "application/json");
  const exportHTML = () => {
    const headers = selectedReportColumns.map(([, label]) => `<th>${reportHTMLCell(label)}</th>`).join("");
    const tableRows = exportRows.map((row) => `<tr>${selectedReportColumns.map(([key]) => `<td>${reportHTMLCell(row[key])}</td>`).join("")}</tr>`).join("");
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>Metriday report ${rangeStart} to ${rangeEnd}</title><style>body{font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#252832;margin:36px}h1{font-size:24px}p{color:#626978}table{border-collapse:collapse;width:100%;margin-top:24px}th,td{border:1px solid #dfe1e6;padding:8px;text-align:left;font-size:12px}th{background:#f4f5f8}</style></head><body><h1>Metriday report</h1><p>${rangeStart} to ${rangeEnd} · Total ${reportHTMLCell(formatReportDuration(report.totalSeconds))} · Billable ${reportHTMLCell(formatReportDuration(report.billableSeconds))} · Amount ${reportHTMLCell(report.amount.toFixed(2))} ${reportHTMLCell(report.currencies.length === 1 ? report.currencies[0] : report.currencies.length > 1 ? "mixed" : "USD")}</p><table><thead><tr>${headers}</tr></thead><tbody>${tableRows}</tbody></table></body></html>`;
    downloadReport(`metriday-report-${rangeStart}-${rangeEnd}.html`, html, "text/html;charset=utf-8");
  };
  const exportNativeReport = async (format) => {
    try {
      setMessage(`Generating ${format.toUpperCase()}…`);
      await api.downloadReportFile({ startDate: rangeStart, endDate: rangeEnd, format, include: includeMode, groupBy, billingFilter, rounding, roundingMinutes: roundingInterval, projectIDs, durationFormat, includeShortEntries, includeCoveredAppUsage, roundIndividualEntries, columns: reportColumns });
      setMessage(`${format.toUpperCase()} report exported.`);
    } catch (error) {
      setMessage(error.message || `Could not export ${format.toUpperCase()} report.`);
    }
  };
  const entrySeconds = dataset.entries.reduce((total, entry) => {
    const start = new Date(entry.start_date || entry.start).getTime();
    const end = new Date(entry.end_date || entry.end).getTime();
    return Number.isFinite(start) && Number.isFinite(end) ? total + Math.max(0, Math.round((end - start) / 1000)) : total;
  }, 0);
  const reportRangeLabel = rangeStart === rangeEnd ? rangeStart : `${rangeStart}–${rangeEnd}`;
  return <section className="web-report-panel">
    <section className="report-summary">
      <div><Clock size={22} /><span>Tracked time</span><strong>{formatReportDuration(report.totalSeconds)}</strong><small>{reportRangeLabel}</small></div>
      <div><Timer size={22} /><span>Time entries</span><strong>{formatReportDuration(entrySeconds)}</strong><small>Manual + timer</small></div>
      <div><TrendUp size={22} /><span>Export formats</span><strong>5</strong><small>CSV · XLSX · JSON · HTML · PDF</small></div>
    </section>
    <section className="report-builder-panel">
      <div className="chart-heading"><div><h2>Report Builder</h2><p>Timing-style presets with custom date, project, grouping, billing, and duration options.</p></div><div className="report-builder-heading-actions"><div className="report-builder-mode" role="group" aria-label="Report builder mode"><button type="button" className={reportMode === "easy" ? "active" : ""} onClick={() => setReportMode("easy")}>Easy</button><button type="button" className={reportMode === "advanced" ? "active" : ""} onClick={() => setReportMode("advanced")}>Advanced</button></div><button type="button" className="report-builder-open" onClick={() => controlsRef.current?.scrollIntoView({ behavior: "smooth", block: "start" })}>Open Builder</button></div></div>
      <div className="report-preset-cards">{reportPresets.map((preset) => { const Icon = preset.icon; return <button type="button" className={`report-preset-card${reportPreset === preset.key ? " active" : ""}`} key={preset.key} onClick={() => applyReportPreset(preset.key)}><span className="report-preset-icon"><Icon size={18} /></span><strong>{preset.label}</strong><CaretRight size={14} /></button>; })}</div>
    </section>
    <div className="chart-heading">
      <div><h2>Reports & exports</h2><p>Timing-style reports from local activities, time entries, projects, and billing status.</p></div>
      <div className="report-actions"><button type="button" onClick={exportCSV} disabled={!report.rows.length}>Export CSV</button><button type="button" onClick={exportJSON} disabled={!report.rows.length}>Export JSON</button><button type="button" onClick={exportHTML} disabled={!report.rows.length}>Export HTML</button><button type="button" onClick={() => exportNativeReport("xlsx")} disabled={!report.rows.length || !api.connected}>Export XLSX</button><button type="button" onClick={() => exportNativeReport("pdf")} disabled={!report.rows.length || !api.connected}>Export PDF</button></div>
    </div>
    <div className="report-presets" ref={controlsRef}>
      <label>Report<select value={reportPreset} onChange={(event) => applyReportPreset(event.target.value)}>{reportPresets.map((preset) => <option value={preset.key} key={preset.key}>{preset.label}</option>)}</select></label>
      <button type="button" onClick={() => setDatePreset("today")}>Today</button><button type="button" onClick={() => setDatePreset("week")}>This week</button><button type="button" onClick={() => setDatePreset("last-seven")}>Last 7 days</button><button type="button" onClick={() => setDatePreset("month")}>This month</button>
      <label>From<input type="date" value={rangeStart} onChange={(event) => setRangeStart(event.target.value)} /></label><label>To<input type="date" value={rangeEnd} onChange={(event) => setRangeEnd(event.target.value)} /></label>
    </div>
    {reportMode === "advanced" ? <>
    <div className="report-filters">
      <label>Include<select value={includeMode} onChange={(event) => setIncludeMode(event.target.value)}><option value="both">Time entries + app activity</option><option value="time">Time entries only</option><option value="app">App activity only</option></select></label>
      <label>Group by<select value={groupBy} onChange={(event) => setGroupBy(event.target.value)}><option value="exact">Exact rows</option><option value="day">Day</option><option value="weekAndDay">Week + Day</option><option value="week">Week</option><option value="month">Month</option><option value="year">Year</option><option value="hour">Hour</option><option value="project">Project</option><option value="topLevelProject">Top-level Project</option><option value="secondLevelProject">Second-level Project</option><option value="projectHierarchy">Project (Hierarchical)</option><option value="application">Application</option><option value="document">Document</option></select></label>
      <label>Billing<select value={billingFilter} onChange={(event) => setBillingFilter(event.target.value)}><option value="all">All statuses</option><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option><option value="undetermined">Undetermined</option></select></label>
      <label>Rounding<select value={rounding} onChange={(event) => setRounding(event.target.value)}><option value="none">Exact</option><option value="up">Round up</option><option value="down">Round down</option><option value="nearest">Nearest</option></select></label>
      <label>Interval<select value={roundingInterval} onChange={(event) => setRoundingInterval(Number(event.target.value))}><option value={1}>1 min</option><option value={5}>5 min</option><option value={6}>6 min</option><option value={10}>10 min</option><option value={12}>12 min</option><option value={15}>15 min</option><option value={30}>30 min</option><option value={60}>1 hour</option></select></label>
    </div>
    <div className="report-project-filter"><strong>Projects</strong><label><input type="checkbox" checked={projectIDs.length === 0} onChange={() => setProjectIDs([])} />All projects</label>{api.projects.map((project) => <label key={project.id}><input type="checkbox" checked={projectIDs.length === 0 || projectIDs.includes(resourceID(project.id))} onChange={(event) => setProjectIDs((current) => { const id = resourceID(project.id); if (event.target.checked) return current.length === 0 ? [id] : [...new Set([...current, id])]; return current.filter((value) => value !== id); })} />{project.title || project.name}</label>)}</div>
    <div className="report-advanced"><label>Duration<select value={durationFormat} onChange={(event) => setDurationFormat(event.target.value)}><option value="decimalMinutes">Fractional minutes</option><option value="hms">HH:MM:SS</option><option value="human">Xh Ym Zs</option><option value="seconds">Fractional seconds</option><option value="decimalHours">Fractional hours</option></select></label><label><input type="checkbox" checked={includeShortEntries} onChange={(event) => setIncludeShortEntries(event.target.checked)} />Include App usage shorter than 1 minute</label><label><input type="checkbox" checked={includeCoveredAppUsage} onChange={(event) => setIncludeCoveredAppUsage(event.target.checked)} />Include App usage covered by Time Entries</label><label><input type="checkbox" checked={roundIndividualEntries} onChange={(event) => setRoundIndividualEntries(event.target.checked)} disabled={rounding === "none"} />Round individual entries</label></div>
    <div className="report-columns"><strong>Columns</strong>{reportColumnOptions.map(([key, label]) => <label key={key}><input type="checkbox" checked={reportColumns.includes(key)} disabled={reportColumns.length === 1 && reportColumns.includes(key)} onChange={(event) => setReportColumns((current) => event.target.checked ? [...new Set([...current, key])] : current.filter((value) => value !== key))} />{label}</label>)}</div>
    </> : null}
    {message ? <p className="entry-message" role="status">{message}</p> : null}
    <div className="report-metrics"><div><span>Total</span><strong>{formatReportDuration(report.totalSeconds)}</strong></div><div><span>Billable</span><strong>{formatReportDuration(report.billableSeconds)}</strong></div><div><span>Amount</span><strong>{report.amount.toFixed(2)} {report.currencies.length === 1 ? report.currencies[0] : report.currencies.length > 1 ? "mixed" : "USD"}</strong></div><div><span>Rows</span><strong>{loading ? "…" : report.rows.length}</strong></div></div>
    {report.rows.length > 0 ? <div className="report-table"><div className="report-table-head"><span>Title</span><span>Project</span><span>Timespan</span><span>Duration</span><span>Billing</span></div>{report.rows.slice(0, 40).map((row, index) => <div className="report-table-row" key={`${row.kind}-${row.start.toISOString()}-${index}`}><strong>{row.displayTitle || row.title}</strong><span>{row.project}</span><span>{row.start.toLocaleDateString(undefined, { month: "short", day: "numeric" })} {entryClock(row.start)}–{entryClock(row.end)}</span><span>{formatReportDuration(row.seconds)}</span><small>{row.billing}</small></div>)}</div> : <div className="entries-empty"><ChartBar size={24} /><span>{loading ? "Loading report data…" : api.connected ? "No rows match this report." : "Connect the native app to generate a report."}</span></div>}
  </section>;
}

function ActivityContextMenu({ activity, x, y, onClose, onSelect, onCreateTimeEntry }) {
  useEffect(() => {
    const closeOnOutsidePointer = (event) => {
      if (!event.target.closest?.(".activity-context-menu")) onClose();
    };
    const closeOnEscape = (event) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("pointerdown", closeOnOutsidePointer);
    window.addEventListener("keydown", closeOnEscape);
    window.addEventListener("scroll", onClose, true);
    return () => {
      window.removeEventListener("pointerdown", closeOnOutsidePointer);
      window.removeEventListener("keydown", closeOnEscape);
      window.removeEventListener("scroll", onClose, true);
    };
  }, [onClose]);
  const app = activity.appName || activity.deviceName || "Unknown App";
  const category = activityCategory(activity);
  const menuWidth = 226;
  const menuHeight = activity.__deleteActivity ? 180 : 142;
  const left = Math.max(8, Math.min(x, (window.innerWidth || x + menuWidth) - menuWidth - 8));
  const top = Math.max(8, Math.min(y, (window.innerHeight || y + menuHeight) - menuHeight - 8));
  const select = () => {
    onClose();
    onSelect?.(activity);
  };
  const createTimeEntry = () => {
    onClose();
    onCreateTimeEntry?.(activity);
  };
  const deleteActivity = async () => {
    onClose();
    if (!activity.__deleteActivity || !window.confirm(`Delete captured app usage for ${app}?`)) return;
    try {
      await activity.__deleteActivity();
    } catch (error) {
      window.alert(error.message || "Could not delete app usage.");
    }
  };
  return <div className="activity-context-menu" role="menu" aria-label={`Actions for ${app}`} style={{ left, top }} onPointerDown={(event) => event.stopPropagation()} onContextMenu={(event) => event.preventDefault()}>
    <div className="activity-context-heading"><span className="activity-context-icon"><Browsers size={16} /></span><div><strong>{app}</strong><small><span className={`activity-context-category ${category.key}`} style={{ color: activityCategoryStyle(category).color }}>{category.label}</span>{activity.deviceName ? ` · ${activity.deviceName}` : ""}</small></div></div>
    <div className="activity-context-divider" />
    <button type="button" role="menuitem" onClick={select}><NotePencil size={15} />Open details</button>
    <button type="button" role="menuitem" onClick={createTimeEntry}><Clock size={15} />Create time entry</button>
    {activity.__deleteActivity ? <button type="button" role="menuitem" className="timeline-context-danger" onClick={deleteActivity}><Trash size={15} />Delete app usage</button> : null}
  </div>;
}

function TimelineContextMenu({ title, subtitle, actionLabel, actionIcon: ActionIcon = Clock, x, y, onClose, onAction, onDelete }) {
  useEffect(() => {
    const closeOnOutsidePointer = (event) => {
      if (!event.target.closest?.(".activity-context-menu")) onClose();
    };
    const closeOnEscape = (event) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("pointerdown", closeOnOutsidePointer);
    window.addEventListener("keydown", closeOnEscape);
    window.addEventListener("scroll", onClose, true);
    return () => {
      window.removeEventListener("pointerdown", closeOnOutsidePointer);
      window.removeEventListener("keydown", closeOnEscape);
      window.removeEventListener("scroll", onClose, true);
    };
  }, [onClose]);
  const menuWidth = 226;
  const menuHeight = onDelete ? 150 : 118;
  const left = Math.max(8, Math.min(x, (window.innerWidth || x + menuWidth) - menuWidth - 8));
  const top = Math.max(8, Math.min(y, (window.innerHeight || y + menuHeight) - menuHeight - 8));
  const action = () => {
    onClose();
    onAction?.();
  };
  const remove = () => {
    onClose();
    onDelete?.();
  };
  return <div className="activity-context-menu" role="menu" aria-label={`Actions for ${title}`} style={{ left, top }} onPointerDown={(event) => event.stopPropagation()} onContextMenu={(event) => event.preventDefault()}>
    <div className="activity-context-heading"><span className="activity-context-icon"><ActionIcon size={16} /></span><div><strong>{title}</strong><small>{subtitle}</small></div></div>
    <div className="activity-context-divider" />
    <button type="button" role="menuitem" onClick={action}><ActionIcon size={15} />{actionLabel}</button>
    {onDelete ? <button type="button" role="menuitem" className="timeline-context-danger" onClick={remove}><Trash size={15} />Delete time entry</button> : null}
  </div>;
}

function WebActivityTimeline({ activities, dateKey, api, onSelect, onEditTimeEntry, onRecordCalendarEvent, onCreateTimeEntry, onCreateSelection, selection: controlledSelection, onSelectionChange, orientation: requestedOrientation = "vertical", onToggleOrientation }) {
 const trackRef = useRef(null);
 const [localSelection, setLocalSelection] = useState(null);
 const selection = controlledSelection === undefined ? localSelection : controlledSelection;
 const updateSelection = (next) => {
   if (controlledSelection === undefined) setLocalSelection(next);
   onSelectionChange?.(next);
 };
 const [contextMenu, setContextMenu] = useState(null);
 const [overlayContextMenu, setOverlayContextMenu] = useState(null);
 const [hoveredActivityID, setHoveredActivityID] = useState(null);
 const [message, setMessage] = useState("");
 const timelineMessageInteracted = useRef(false);
 const wrapAtMinute = Math.max(0, Math.min(1439, Number(api.preferences?.wrap_days_at_minute ?? 0)));
 const automaticEntryIntervals = useMemo(() => entryOMaticIntervals(activities, api.entries || [], dateKey, { minimumDurationMinutes: 5, maximumGapSeconds: 60, wrapAtMinute }), [activities, api.entries, dateKey, wrapAtMinute]);
 const automaticEntryDuration = automaticEntryIntervals.reduce((total, interval) => total + interval.endSecond - interval.startSecond, 0);
 const activityClickTimer = useRef(null);
 useEffect(() => () => { if (activityClickTimer.current) window.clearTimeout(activityClickTimer.current); }, []);
 useEffect(() => {
   timelineMessageInteracted.current = false;
 }, [dateKey]);
 useEffect(() => {
   if (timelineMessageInteracted.current) return;
   if (!automaticEntryIntervals.length) {
     setMessage("");
     return;
   }
   setMessage(<span className="timeline-entry-suggestion"><span>Metriday can automatically create {automaticEntryIntervals.length} time entries with a total duration of {formatDurationSeconds(automaticEntryDuration)} to cover this app usage.</span><button type="button" onClick={() => { timelineMessageInteracted.current = true; window.dispatchEvent(new CustomEvent("metriday:open-entry-omatic")); }}>Create Time Entries</button></span>);
 }, [automaticEntryDuration, automaticEntryIntervals]);
 const setTimelineMessage = (value) => {
   timelineMessageInteracted.current = true;
   setMessage(value);
 };
 const openActivityDetails = (activity) => {
   if (activityClickTimer.current) window.clearTimeout(activityClickTimer.current);
   activityClickTimer.current = window.setTimeout(() => {
     onSelect?.(activity);
     activityClickTimer.current = null;
   }, 220);
 };
 const createActivityTimeEntry = (event, activity) => {
   event.preventDefault();
   event.stopPropagation();
   if (activityClickTimer.current) window.clearTimeout(activityClickTimer.current);
   activityClickTimer.current = null;
   onCreateTimeEntry?.(activity);
 };
 const hoveredActivity = activities.find((activity) => resourceID(activity.id) === resourceID(hoveredActivityID)) || null;
  const controlledOrientation = typeof onToggleOrientation === "function";
  const [localOrientation, setLocalOrientation] = useState(() => api.activityPreferences?.timeline_orientation === "horizontal" ? "horizontal" : "vertical");
  const orientation = controlledOrientation ? requestedOrientation : localOrientation;
  useEffect(() => {
    if (!controlledOrientation) setLocalOrientation(api.activityPreferences?.timeline_orientation === "horizontal" ? "horizontal" : "vertical");
  }, [api.activityPreferences, controlledOrientation]);
  const toggleOrientation = onToggleOrientation || (() => {
    const next = orientation === "horizontal" ? "vertical" : "horizontal";
    setLocalOrientation(next);
    void api.updateActivityPreferences?.({ timeline_orientation: next });
  });
 const totalSeconds = 24 * 60 * 60;
 const zoomToWorkingHours = Boolean(api.preferences?.automatically_zoom_timeline_to_working_hours);
 const axisMinuteForWallMinute = (minute) => {
   const bounded = Math.max(0, Math.min(1439, Number(minute || 0)));
   const shifted = bounded - wrapAtMinute;
   return shifted < 0 ? shifted + 1440 : shifted;
 };
 const wallMinuteForAxisMinute = (minute) => (Math.max(0, Number(minute || 0)) + wrapAtMinute) % 1440;
 const clockForAxisSecond = (second) => {
   const value = Math.max(0, Math.round((wrapAtMinute * 60 + Math.max(0, Number(second || 0))) % totalSeconds));
   const hours = Math.floor(value / 3600) % 24;
   const minutes = Math.floor((value % 3600) / 60);
   const seconds = value % 60;
   return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
 };
 const formatAxisRange = (start, end) => `${clockForAxisSecond(Number(start || 0) * 60)}–${clockForAxisSecond(Number(end || 0) * 60)}`;
 const formatRange = (start, end) => formatAxisRange(start, end);
 const preciseClock = clockForAxisSecond;
 const workingHoursStart = zoomToWorkingHours ? axisMinuteForWallMinute(Number(api.preferences?.working_hours_start_minute ?? 9 * 60)) : 0;
 let workingHoursEnd = zoomToWorkingHours ? axisMinuteForWallMinute(Number(api.preferences?.working_hours_end_minute ?? 18 * 60)) : 24 * 60;
 if (zoomToWorkingHours && workingHoursEnd <= workingHoursStart) workingHoursEnd += 24 * 60;
 const timelineStartMinute = workingHoursStart;
 const timelineEndMinute = zoomToWorkingHours ? Math.max(workingHoursStart + 15, workingHoursEnd) : 24 * 60;
 const timelineSpanMinutes = Math.max(15, timelineEndMinute - timelineStartMinute);
 const absoluteMinuteForSecond = (second, roundUp = false) => {
   const bounded = Math.max(0, Math.min(totalSeconds, Number(second || 0)));
   if (bounded >= totalSeconds) return 24 * 60;
   const raw = roundUp ? Math.ceil(bounded / 60) : Math.floor(bounded / 60);
   return timelineEndMinute > 24 * 60 && raw < timelineStartMinute ? raw + 24 * 60 : raw;
 };
 const clippedMinuteRange = (startSecond, endSecond) => {
   const start = Math.max(timelineStartMinute, absoluteMinuteForSecond(startSecond));
   const end = Math.min(timelineEndMinute, absoluteMinuteForSecond(endSecond, true));
   return end > start ? { start, end } : null;
 };
 const minutePercent = (minute) => ((minute - timelineStartMinute) / timelineSpanMinutes) * 100;
 const dayMinuteToTimelineMinute = (minute) => {
   const bounded = Math.max(0, Math.min(24 * 60, Number(minute || 0)));
   return timelineEndMinute > 24 * 60 && bounded < timelineStartMinute ? bounded + 24 * 60 : bounded;
 };
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const interval = window.setInterval(() => setNow(new Date()), 30_000);
    return () => window.clearInterval(interval);
  }, []);
  const todayLogicalDateKey = (() => {
    const civil = localDateKey();
    const wallMinute = now.getHours() * 60 + now.getMinutes();
    return wallMinute < wrapAtMinute && wrapAtMinute > 0 ? offsetDateKey(civil, -1) : civil;
  })();
  const currentTimeSecond = dateKey === todayLogicalDateKey
    ? Math.max(0, Math.min(totalSeconds, Math.floor(axisMinuteForWallMinute(now.getHours() * 60 + now.getMinutes()) * 60 + now.getSeconds())))
    : null;
  const minuteAt = (clientPosition, rect) => {
    const offset = orientation === "vertical" ? clientPosition - rect.top : clientPosition - rect.left;
    const length = orientation === "vertical" ? rect.height : rect.width;
    const absolute = timelineStartMinute + Math.round((offset / length) * timelineSpanMinutes / 15) * 15;
    return Math.max(0, Math.min(24 * 60, absolute));
  };
  const startSelection = (event) => {
    if (event.button !== 0 || !trackRef.current) return;
    const rect = trackRef.current.getBoundingClientRect();
    const position = orientation === "vertical" ? event.clientY : event.clientX;
    const start = minuteAt(position, rect);
    let latest = { start, end: Math.min(start + 15, 24 * 60) };
    updateSelection(latest);
    const move = (moveEvent) => {
      const movePosition = orientation === "vertical" ? moveEvent.clientY : moveEvent.clientX;
      const end = minuteAt(movePosition, rect);
      latest = { start: Math.min(start, end), end: Math.max(start, end) || Math.min(start + 15, 24 * 60) };
      if (latest.end === latest.start) latest.end = Math.min(latest.start + 15, 24 * 60);
      updateSelection(latest);
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      if (latest.end <= latest.start) updateSelection(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  const recordSelection = async () => {
    if (!selection || !api.connected) return;
    if (onCreateSelection) {
      onCreateSelection(selection);
      updateSelection(null);
      return;
    }
    const start = localEntryDateSeconds(dateKey, selection.start * 60, wrapAtMinute);
    const end = localEntryDateSeconds(dateKey, selection.end * 60, wrapAtMinute);
    if (!start || !end) return;
    setTimelineMessage("Recording…");
    try {
      await api.addTimeEntry({ title: "Activity time", start, end, billingStatus: "billable" });
      updateSelection(null);
      setTimelineMessage("Recorded " + formatAxisRange(selection.start, selection.end));
    } catch (error) {
      setTimelineMessage(error.message || "Could not record the selected range.");
    }
  };
  const vertical = orientation === "vertical";
  const timelineHours = [];
  const timelineStep = timelineSpanMinutes <= 12 * 60 ? 60 : 120;
  for (let minute = timelineStartMinute; minute <= timelineEndMinute; minute += timelineStep) timelineHours.push(minute);
  if (timelineHours[timelineHours.length - 1] !== timelineEndMinute) timelineHours.push(timelineEndMinute);
  useEffect(() => {
    const labels = trackRef.current?.querySelectorAll(".web-activity-timeline-label");
    labels?.forEach((label, index) => {
      const minute = timelineHours[index];
      if (minute != null) label.textContent = formatTime(wallMinuteForAxisMinute(minute));
    });
  }, [orientation, timelineEndMinute, timelineSpanMinutes, timelineStartMinute, wrapAtMinute]);
  const timeEntries = api.activityPreferences?.include_time_entries === false ? (api.entries || []).map((entry) => ({ entry, range: entrySecondsForDate(entry, dateKey, wrapAtMinute) })).filter((item) => item.range) : [];
  const calendarEvents = Array.isArray(api.calendarEvents?.data) ? api.calendarEvents.data.map((event) => {
    const startDate = new Date(event.start || "");
    const endDate = new Date(event.end || "");
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) return null;
    const dayStart = trackingDayStart(dateKey, wrapAtMinute);
    const startSecond = Math.max(0, Math.min(totalSeconds, Math.floor((startDate.getTime() - dayStart.getTime()) / 1000)));
    const endSecond = Math.max(0, Math.min(totalSeconds, Math.ceil((endDate.getTime() - dayStart.getTime()) / 1000)));
    return endSecond > startSecond ? { event, startSecond, endSecond } : null;
  }).filter(Boolean) : [];
  const recordCalendarEvent = async (calendarEvent) => {
    if (onRecordCalendarEvent) {
      onRecordCalendarEvent(calendarEvent);
      return;
    }
    if (!api.connected) return;
    try {
      await api.addTimeEntry({ title: calendarEvent.title || "Calendar event", start: calendarEvent.start, end: calendarEvent.end, billingStatus: "billable" });
      setTimelineMessage("Recorded calendar event.");
    } catch (error) {
      setTimelineMessage(error.message || "Could not record the calendar event.");
    }
  };
  const deleteTimeEntry = async (entry) => {
    if (!api.connected) return;
    try {
      await api.deleteTimeEntry(entryID(entry));
      setTimelineMessage(`Deleted “${entry.title || "Untitled time entry"}”.`);
    } catch (error) {
      setTimelineMessage(error.message || "Could not delete the time entry.");
    }
  };
  const rangeStyle = (startSecond, endSecond, color) => {
    const range = clippedMinuteRange(startSecond, endSecond);
    if (!range) return null;
    const startPercent = minutePercent(range.start);
    const durationPercent = Math.max(minutePercent(range.end) - startPercent, 0.4);
    const hitDurationPercent = Math.max(durationPercent, 1.6);
    const hitStartPercent = Math.max(0, Math.min(100 - hitDurationPercent, startPercent - ((hitDurationPercent - durationPercent) / 2)));
    const outer = vertical
      ? { top: `${hitStartPercent}%`, height: `${hitDurationPercent}%` }
      : { left: `${hitStartPercent}%`, width: `${hitDurationPercent}%` };
    const visual = vertical
      ? { left: "0%", width: "100%", top: `${((startPercent - hitStartPercent) / hitDurationPercent) * 100}%`, height: `${(durationPercent / hitDurationPercent) * 100}%`, borderColor: color }
      : { top: "0%", height: "100%", left: `${((startPercent - hitStartPercent) / hitDurationPercent) * 100}%`, width: `${(durationPercent / hitDurationPercent) * 100}%`, borderColor: color };
    return { outer, visual };
  };
  const selectionStyle = selection ? (() => {
    const start = minutePercent(dayMinuteToTimelineMinute(selection.start));
    const end = minutePercent(dayMinuteToTimelineMinute(selection.end));
    const size = Math.max(0, end - start);
    return vertical ? { top: `${start}%`, height: `${size}%` } : { left: `${start}%`, width: `${size}%` };
  })() : undefined;
  const timelineGaps = (() => {
    const ranges = activities
      .map((activity) => clippedMinuteRange(Math.max(0, Number(activity.startSecond || 0)), Math.min(totalSeconds, Number(activity.endSecond || 0))))
      .filter(Boolean)
      .sort((left, right) => left.start - right.start);
    const merged = [];
    ranges.forEach((range) => {
      const previous = merged[merged.length - 1];
      if (previous && range.start <= previous.end) previous.end = Math.max(previous.end, range.end);
      else merged.push({ ...range });
    });
    const gaps = [];
    let cursor = timelineStartMinute;
    merged.forEach((range) => {
      if (range.start - cursor >= 15) gaps.push({ start: cursor, end: range.start });
      cursor = Math.max(cursor, range.end);
    });
    if (timelineEndMinute - cursor >= 15) gaps.push({ start: cursor, end: timelineEndMinute });
    return gaps;
  })();
  const createGapTimeEntry = (event, gap) => {
    event.preventDefault();
    event.stopPropagation();
    if (onCreateSelection) {
      onCreateSelection(gap);
      updateSelection(null);
    } else {
      updateSelection(gap);
    }
  };
  return <section className="web-activity-timeline" aria-label="Activities timeline"><div className="web-activity-timeline-heading"><div><h2>Timeline</h2><p>Click for details · double-click to create a time entry · right-click for actions · drag across a gap to select time.</p><div className="web-activity-timeline-legend" aria-label="Timeline color legend"><span><i className="focused" />Focused</span><span><i className="distracting" />Distracting</span><span><i className="other" />Other</span><span><i className="idle" />Idle</span></div></div><div className="web-activity-timeline-actions"><button type="button" className="timeline-orientation-toggle" onClick={toggleOrientation} aria-label={"Switch to " + (vertical ? "horizontal" : "vertical") + " timeline"} title={"Switch to " + (vertical ? "horizontal" : "vertical") + " timeline"}><ArrowsClockwise size={14} />{vertical ? "Vertical" : "Horizontal"}</button>{selection ? <><span>{formatRange(selection.start, selection.end)}</span><button type="button" onClick={recordSelection} disabled={!api.connected}>{onCreateSelection ? "Create Time Entry" : "Record time"}</button><button type="button" className="timeline-clear" onClick={() => updateSelection(null)}>Clear</button></> : <span>{timelineHours.length ? `${String(Math.floor((timelineHours[0] % 1440) / 60)).padStart(2, "0")}:00–${String(Math.floor((timelineHours[timelineHours.length - 1] % 1440) / 60)).padStart(2, "0")}:00` : "00:00–24:00"}</span>}{message ? <small role="status">{message}</small> : null}</div></div><div className={"web-activity-timeline-track " + (vertical ? "vertical" : "horizontal")} ref={trackRef} onPointerDown={startSelection} onMouseLeave={() => setHoveredActivityID(null)}>{timelineHours.map((minute) => { const hour = Math.floor((minute % 1440) / 60); const label = `${String(hour).padStart(2, "0")}:00`; const position = minutePercent(minute); return <span className="web-activity-timeline-label" key={minute} style={vertical ? { top: `${position}%` } : { left: `${position}%` }}>{label}</span>; })}<div className="web-activity-timeline-grid" aria-hidden="true">{timelineHours.map((minute) => <i key={minute} style={vertical ? { top: `${minutePercent(minute)}%` } : { left: `${minutePercent(minute)}%` }} />)}</div>{currentTimeSecond !== null && clippedMinuteRange(currentTimeSecond, currentTimeSecond + 60) ? <div className={"web-activity-timeline-current-time " + (vertical ? "vertical" : "horizontal")} style={vertical ? { top: `${minutePercent(absoluteMinuteForSecond(currentTimeSecond))}%` } : { left: `${minutePercent(absoluteMinuteForSecond(currentTimeSecond))}%` }} aria-hidden="true"><span /></div> : null}{hoveredActivity ? <div className="web-activity-timeline-hover-card" role="status" aria-label="Timeline details"><strong>{preciseClock(Number(hoveredActivity.startSecond || 0))}–{preciseClock(Number(hoveredActivity.endSecond || 0))}</strong><span><b>App</b><span>{activityLabel(hoveredActivity)}</span><em>{formatDurationSeconds(activityDurationSeconds(hoveredActivity))}</em></span><span><b>Category</b><i style={{ background: activityCategoryStyle(activityCategory(hoveredActivity)).color }} />{activityCategory(hoveredActivity).label}</span><span><b>Project</b>{projectTitleFor(api.projects, hoveredActivity.projectID)}</span></div> : null}{timelineGaps.map((gap) => { const position = minutePercent((gap.start + gap.end) / 2); const label = formatRange(gap.start, gap.end); return <button type="button" key={"gap-" + gap.start + "-" + gap.end} className="web-activity-timeline-gap" style={vertical ? { top: `${position}%` } : { left: `${position}%` }} aria-label={"Create time entry for " + label} title={"Create time entry · " + label} onPointerDown={(event) => event.stopPropagation()} onClick={(event) => createGapTimeEntry(event, gap)}><Plus size={13} weight="bold" /></button>; })}{activities.map((activity) => { const startSecond = Math.max(0, Number(activity.startSecond || 0)); const endSecond = Math.min(totalSeconds, Number(activity.endSecond || 0)); const range = clippedMinuteRange(startSecond, endSecond); if (!range) return null; const category = activityCategory(activity); const categoryStyle = activityCategoryStyle(category); const startPercent = minutePercent(range.start); const durationPercent = Math.max(minutePercent(range.end) - startPercent, 0.18); const hitDurationPercent = Math.max(durationPercent, 1.6); const hitStartPercent = Math.max(0, Math.min(100 - hitDurationPercent, startPercent - ((hitDurationPercent - durationPercent) / 2))); const blockStyle = vertical ? { top: `${hitStartPercent}%`, height: `${hitDurationPercent}%`, color: categoryStyle.color } : { left: `${hitStartPercent}%`, width: `${hitDurationPercent}%`, color: categoryStyle.color }; const visualStyle = vertical ? { left: "0%", width: "100%", top: `${((startPercent - hitStartPercent) / hitDurationPercent) * 100}%`, height: `${(durationPercent / hitDurationPercent) * 100}%` } : { top: "0%", height: "100%", left: `${((startPercent - hitStartPercent) / hitDurationPercent) * 100}%`, width: `${(durationPercent / hitDurationPercent) * 100}%` }; return <div role="button" tabIndex={0} key={activity.id} className={"web-activity-timeline-block " + category.key} style={blockStyle} aria-label={activityLabel(activity) + " · " + category.label + " · " + preciseClock(startSecond) + "–" + preciseClock(endSecond)} title={activityLabel(activity) + " · " + category.label + " · " + preciseClock(startSecond) + "–" + preciseClock(endSecond)} onPointerDown={(event) => event.stopPropagation()} onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); if (activityClickTimer.current) window.clearTimeout(activityClickTimer.current); activityClickTimer.current = null; setContextMenu({ activity, x: event.clientX, y: event.clientY }); }} onMouseEnter={() => setHoveredActivityID(activity.id)} onClick={() => openActivityDetails(activity)} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); openActivityDetails(activity); } }}><span className="web-activity-timeline-visual" style={visualStyle} /><span className="web-activity-timeline-plus" role="button" tabIndex={0} aria-label={"Create time entry for " + activityLabel(activity)} title="Create time entry" onPointerDown={(event) => event.stopPropagation()} onClick={(event) => createActivityTimeEntry(event, activity)} onKeyDown={(event) => { event.stopPropagation(); if (event.key === "Enter" || event.key === " ") { event.preventDefault(); createActivityTimeEntry(event, activity); } }}><Plus size={11} weight="bold" /></span></div>; })}{timeEntries.map(({ entry, range }) => { const timelineRange = rangeStyle(range.startSecond, range.endSecond, "#d77b22"); if (!timelineRange) return null; return <button type="button" key={"entry-" + entryID(entry)} className="web-activity-timeline-overlay time-entry" style={timelineRange.outer} aria-label={"Edit time entry " + (entry.title || "Untitled") + " " + entryRange(entry)} title={"Edit time entry · " + (entry.title || "Untitled") + " · " + entryRange(entry)} onPointerDown={(event) => event.stopPropagation()} onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); setOverlayContextMenu({ kind: "time-entry", entry, x: event.clientX, y: event.clientY }); }} onClick={() => onEditTimeEntry ? onEditTimeEntry(entry) : setMessage("Time entry · " + (entry.title || "Untitled"))}><span style={timelineRange.visual} /></button>; })}{calendarEvents.map(({ event, startSecond, endSecond }) => { const timelineRange = rangeStyle(startSecond, endSecond, "#4e5ff2"); if (!timelineRange) return null; return <button type="button" key={"calendar-" + (event.id || event.title)} className="web-activity-timeline-overlay calendar-event" style={timelineRange.outer} aria-label={"Record calendar event " + (event.title || "Untitled event")} title={"Calendar · " + (event.title || "Untitled event")} onPointerDown={(pointerEvent) => pointerEvent.stopPropagation()} onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); setOverlayContextMenu({ kind: "calendar-event", event, x: event.clientX, y: event.clientY }); }} onClick={() => recordCalendarEvent(event)}><span style={timelineRange.visual} /></button>; })}{selection ? <div className="web-activity-timeline-selection" style={selectionStyle} aria-label={"Selected " + formatRange(selection.start, selection.end)} /> : null}</div>{contextMenu ? <ActivityContextMenu activity={contextMenu.activity} x={contextMenu.x} y={contextMenu.y} onClose={() => setContextMenu(null)} onSelect={onSelect} onCreateTimeEntry={onCreateTimeEntry} /> : null}{overlayContextMenu?.kind === "time-entry" ? <TimelineContextMenu title={overlayContextMenu.entry.title || "Untitled time entry"} subtitle={entryRange(overlayContextMenu.entry)} actionLabel="Edit time entry" actionIcon={Clock} x={overlayContextMenu.x} y={overlayContextMenu.y} onClose={() => setOverlayContextMenu(null)} onAction={() => onEditTimeEntry?.(overlayContextMenu.entry)} onDelete={() => deleteTimeEntry(overlayContextMenu.entry)} /> : null}{overlayContextMenu?.kind === "calendar-event" ? <TimelineContextMenu title={overlayContextMenu.event.title || "Untitled event"} subtitle={overlayContextMenu.event.calendar || "Calendar event"} actionLabel="Record time entry" actionIcon={CalendarBlank} x={overlayContextMenu.x} y={overlayContextMenu.y} onClose={() => setOverlayContextMenu(null)} onAction={() => recordCalendarEvent(overlayContextMenu.event)} /> : null}</section>;
}

function activityDurationSeconds(activity) {
  const collapsed = Number(activity?.collapsed_duration_seconds);
  if (Number.isFinite(collapsed) && collapsed > 0) return collapsed;
  return Math.max(0, Number(activity?.endSecond || 0) - Number(activity?.startSecond || 0));
}

function collapseShortActivities(activities, thresholdSeconds) {
  const threshold = Math.max(0, Number(thresholdSeconds || 0));
  if (!threshold) return activities;
  const shortActivities = activities.filter((activity) => activityDurationSeconds(activity) < threshold);
  if (shortActivities.length <= 1) return activities;
  const longActivities = activities.filter((activity) => activityDurationSeconds(activity) >= threshold);
  const groups = new Map();
  shortActivities.forEach((activity) => {
    const key = `${resourceID(activity.projectID) || "unassigned"}:${activity.date || ""}:${activity.deviceName || "This Mac"}`;
    const current = groups.get(key) || [];
    current.push(activity);
    groups.set(key, current);
  });
  const label = threshold >= 60 ? `${Math.floor(threshold / 60)}m` : `${threshold}s`;
  const summaries = [...groups.values()].flatMap((group) => {
    if (group.length <= 1) return group;
    const ordered = [...group].sort((left, right) => Number(left.startSecond || 0) - Number(right.startSecond || 0));
    const first = ordered[0];
    return [{
      ...first,
      appName: `(Entries shorter than ${label} each)`,
      bundleIdentifier: "",
      windowTitle: `${ordered.length} activities`,
      resource: "",
      startSecond: Number(first.startSecond || 0),
      endSecond: Number(first.endSecond || first.startSecond || 0),
      relevance: "other",
      categoryRole: "other",
      categoryName: "Other",
      categoryColor: "graphite",
      collapsed_activity_ids: ordered.map((activity) => activity.id),
      collapsed_duration_seconds: ordered.reduce((total, activity) => total + activityDurationSeconds(activity), 0),
      is_collapsed_summary: true,
    }];
  });
  return [...longActivities, ...summaries].sort((left, right) => String(left.date || "").localeCompare(String(right.date || "")) || Number(left.startSecond || 0) - Number(right.startSecond || 0));
}

function ActivityTable({ activities, onSelect, viewMode = "unified", groupMode = "none", unifiedGroupMode = "project", projects = [], displayPreferences = null, dateKey = "", api = null, onCreateTimeEntry }) {
  const [collapsedGroups, setCollapsedGroups] = useState(() => new Set());
  const [contextMenu, setContextMenu] = useState(null);
  const rowClickTimer = useRef(null);
  useEffect(() => () => { if (rowClickTimer.current) window.clearTimeout(rowClickTimer.current); }, []);
  const displayActivities = viewMode === "category"
    ? activities
    : collapseShortActivities(activities, displayPreferences?.collapse_activities_shorter_than_seconds);
  const rows = [...displayActivities].sort((left, right) => String(left.date || dateKey).localeCompare(String(right.date || dateKey)) || Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const projectGroupingEnabled = displayPreferences
    ? displayPreferences.group_by_project !== false
    : unifiedGroupMode === "project";
  const deviceGroupingEnabled = Boolean(displayPreferences?.group_by_device);
  const resolvedUnifiedGroupMode = projectGroupingEnabled && deviceGroupingEnabled
    ? "projectDevice"
    : deviceGroupingEnabled
    ? "device"
    : projectGroupingEnabled
    ? "project"
    : "none";
  const activityRow = (activity) => {
    if (activity.is_collapsed_summary) {
      const count = Array.isArray(activity.collapsed_activity_ids) ? activity.collapsed_activity_ids.length : 0;
      const duration = activityDurationSeconds(activity);
      const project = projectTitleFor(projects, activity.projectID);
      return <div className="activity-table-row activity-table-row-collapsed" key={activity.id} role="status" aria-label={`Collapsed short activities, ${count} activities, ${formatDurationSeconds(duration)}`} title="Collapsed short activities; change the threshold in Display settings">
        <div className="activity-app-cell">
          <span className="activity-table-icon"><Waveform size={18} /></span>
          <span className="activity-app-copy"><strong>{activity.appName}</strong><small>{count} activities · Display-only summary</small></span>
        </div>
        <span className="activity-category other"><i />Collapsed</span>
        <span>—</span>
        <small>{formatDurationSeconds(duration)} · {activity.deviceName || "This Mac"}</small>
        <span className="activity-row-project activity-row-project-static"><FolderSimple size={14} />{project}</span>
      </div>;
    }
    const category = activityCategory(activity);
    const Icon = activityIcon(activity);
    const app = activity.appName || activity.deviceName || "Unknown App";
    const context = activityContext(activity, {
      showWindowTitles: displayPreferences?.show_window_titles,
      showResourcePaths: displayPreferences?.show_resource_paths,
      includeTitlesInAdditionToPaths: displayPreferences?.include_titles_in_addition_to_paths,
    });
    const start = Math.floor(Number(activity.startSecond || 0) / 60);
    const end = Math.ceil(Number(activity.endSecond || 0) / 60);
    const duration = activityDurationSeconds(activity);
    const activityAPI = () => api;
    const assignProject = async (event) => {
      event.stopPropagation();
      const api = activityAPI();
      if (!api?.assignActivity) return;
      await api.assignActivity(activity.id, event.target.value || null, activity.date || dateKey);
    };
    const createRule = async (event) => {
      event.stopPropagation();
      const api = activityAPI();
      const projectID = resourceID(activity.projectID);
      if (!api?.createProjectRule || !projectID) return;
      const rule = activityProjectRule(activity);
      if (rule) await api.createProjectRule({ ...rule, project_id: projectID });
    };
    const openDetails = (event) => {
      if (event.target.closest(".activity-row-action")) return;
      if (rowClickTimer.current) window.clearTimeout(rowClickTimer.current);
      rowClickTimer.current = window.setTimeout(() => {
        onSelect(activity);
        rowClickTimer.current = null;
      }, 220);
    };
    const openTimeEntry = (event) => {
      if (event.target.closest(".activity-row-action")) return;
      event.preventDefault();
      if (rowClickTimer.current) window.clearTimeout(rowClickTimer.current);
      rowClickTimer.current = null;
      onCreateTimeEntry?.(activity);
    };
    const handleKeyDown = (event) => {
      if (event.target.closest(".activity-row-action")) return;
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        if (rowClickTimer.current) window.clearTimeout(rowClickTimer.current);
        rowClickTimer.current = null;
        onSelect(activity);
      }
    };
    const openContextMenu = (event) => {
      if (event.target.closest(".activity-row-action")) return;
      event.preventDefault();
      event.stopPropagation();
      if (rowClickTimer.current) window.clearTimeout(rowClickTimer.current);
      rowClickTimer.current = null;
      setContextMenu({ activity: { ...activity, __deleteActivity: api?.connected && api?.deleteActivity ? () => api.deleteActivity(activity.id, activity.date || dateKey) : null }, x: event.clientX, y: event.clientY });
    };
    return <div className="activity-table-row" key={activity.id} role="button" tabIndex={0} draggable onDragStart={(event) => { event.dataTransfer.effectAllowed = "copy"; event.dataTransfer.setData("application/x-metriday-activity", activity.id); event.dataTransfer.setData("text/plain", activity.id); event.dataTransfer.setData("application/x-metriday-activity-date", activity.date || dateKey); }} onClick={openDetails} onDoubleClick={openTimeEntry} onContextMenu={openContextMenu} onKeyDown={handleKeyDown} aria-label={`Open details for ${app} ${formatRange(start, end)}`} title="Drag this activity to a project to assign it">
      <div className="activity-app-cell">
        <span className="activity-table-icon"><Icon size={19} weight="duotone" /></span>
        <span className="activity-app-copy"><strong>{app}</strong>{context ? <small>{context}</small> : null}{displayPreferences?.show_activity_date_ranges ? <small className="activity-date-range">{activityDateRangeLabel(activity, api?.preferences?.wrap_days_at_minute)}</small> : null}</span>
      </div>
      <span className={`activity-category ${category.key}`} style={activityCategoryStyle(category)}><i />{category.label}</span>
      <span>{activity.date && activity.date !== dateKey ? `${activity.date} · ` : ""}{formatRange(start, end)}</span>
      <small>{formatDurationSeconds(duration)} · {activity.deviceName || "This Mac"}</small>
      <span className="activity-row-project activity-row-action" onClick={(event) => event.stopPropagation()}><select value={resourceID(activity.projectID)} onChange={assignProject} aria-label={`Project for ${app}`}><option value="">Unassigned</option>{projects.map((project) => <option key={project.id} value={resourceID(project.id)}>{project.title || project.name}</option>)}</select>{activity.projectID ? <button type="button" className="activity-row-rule activity-row-action" onClick={createRule} aria-label={`Create project rule from ${app}`} title="Create a rule from this activity"><Sparkle size={14} /></button> : null}</span>
    </div>;
  };
  if (viewMode === "category") {
    return <WebActivityCategoryCards activities={rows} dateKey={dateKey} displayPreferences={displayPreferences} onSelect={onSelect} onCreateTimeEntry={onCreateTimeEntry} />;
  }
  const resolvedListGrouping = viewMode === "unified"
    ? "none"
    : resolvedUnifiedGroupMode === "projectDevice"
    ? "projectDevice"
    : groupMode;
  const grouping = viewMode === "category" ? "category" : resolvedListGrouping !== "none" ? resolvedListGrouping : viewMode === "unified" ? "application" : "none";
  if (grouping === "none") {
    return <div className="activity-table">
      <div className="activity-table-head" aria-hidden="true"><span>App</span><span>Category</span><span>Time</span><span>Device</span><span>Project</span></div>
      {rows.map(activityRow)}
      {contextMenu ? <ActivityContextMenu activity={contextMenu.activity} x={contextMenu.x} y={contextMenu.y} onClose={() => setContextMenu(null)} onSelect={onSelect} onCreateTimeEntry={onCreateTimeEntry} /> : null}
    </div>;
  }
  const groupedFor = (items, groupingMode, keyPrefix = "") => [...items.reduce((groups, activity) => {
    const category = activityCategory(activity);
    const names = groupingMode === "category"
      ? [{ key: `${category.key}:${category.label}`, label: category.label }]
      : groupingMode === "project"
      ? [{ key: resourceID(activity.projectID) || "unassigned", label: projectTitleFor(projects, activity.projectID) }]
      : groupingMode === "device"
      ? [{ key: activity.deviceName || "This Mac", label: activity.deviceName || "This Mac" }]
      : activityApplicationGroupNames(activity, displayPreferences).map((name) => ({ key: name, label: name }));
    names.forEach(({ key: rawKey, label }) => {
      const groupKey = `${keyPrefix}${rawKey}`;
      const existing = groups.get(groupKey) || { key: groupKey, label, category, categories: new Map(), activities: [], seconds: 0 };
      existing.categories.set(`${category.key}:${category.label}:${category.color}`, category);
      existing.activities.push(activity);
      existing.seconds += activityDurationSeconds(activity);
      groups.set(groupKey, existing);
    });
    return groups;
  }, new Map()).values()].sort((left, right) => right.seconds - left.seconds || left.label.localeCompare(right.label));
  const categorySummary = (categories) => categories.length ? <span className="activity-group-category-summary">{categories.map((item) => <span key={`${item.key}:${item.label}:${item.color}`} className={`activity-category-dot ${item.key}`} style={{ background: activityCategoryStyle(item).color }} title={item.label} aria-label={item.label} />)}<small>{categories.length === 1 ? categories[0].label : "Multiple categories"}</small></span> : null;
  const toggleGroup = (key) => setCollapsedGroups((current) => {
    const next = new Set(current);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    return next;
  });
  const renderGroupMeta = (group, collapsed) => <span className="activity-group-meta">{formatDurationSeconds(group.seconds)} · {group.activities.length} segment{group.activities.length === 1 ? "" : "s"}<CaretDown size={15} className={collapsed ? "collapsed" : ""} /></span>;
  const renderFlatGroup = (group) => {
    const collapsed = collapsedGroups.has(group.key);
    const categories = [...(group.categories?.values?.() || [])];
    return <section className="activity-group" key={group.key}>
      <button type="button" className="activity-group-heading" onClick={() => toggleGroup(group.key)} aria-expanded={!collapsed}>
        <span className="activity-group-title">{grouping === "category" ? <span className={`activity-category ${group.category.key}`} style={activityCategoryStyle(group.category)}><i />{group.label}</span> : <><strong>{group.label}</strong>{grouping === "application" ? categorySummary(categories) : null}</>}</span>
        {renderGroupMeta(group, collapsed)}
      </button>
      {!collapsed ? <div className="activity-group-rows">{group.activities.map(activityRow)}</div> : null}
    </section>;
  };
  if (grouping === "application") {
    const unifiedGroups = resolvedUnifiedGroupMode === "project" || resolvedUnifiedGroupMode === "projectDevice"
      ? groupedFor(rows, "project", "project:")
      : resolvedUnifiedGroupMode === "device"
      ? groupedFor(rows, "device", "device:")
      : [{
        key: "all:activities",
        label: "All Activities",
        category: activityCategory(rows[0] || {}),
        categories: new Map(),
        activities: rows,
        seconds: rows.reduce((total, activity) => total + activityDurationSeconds(activity), 0),
      }];
    const showUnifiedHeader = resolvedUnifiedGroupMode !== "none";
    return <div className="activity-table activity-table-unified">
      {unifiedGroups.map((projectGroup) => {
        const projectCollapsed = collapsedGroups.has(projectGroup.key);
        const appGroups = groupedFor(projectGroup.activities, "application", `${projectGroup.key}::application:`);
        return <section className="activity-group activity-group-project" key={projectGroup.key}>
          {showUnifiedHeader ? <button type="button" className="activity-group-heading activity-group-project-heading" onClick={() => toggleGroup(projectGroup.key)} aria-expanded={!projectCollapsed}>
            <span className="activity-group-title">{resolvedUnifiedGroupMode === "device" ? <Laptop size={16} /> : <FolderSimple size={16} />}<strong>{projectGroup.label}</strong></span>
            {renderGroupMeta(projectGroup, projectCollapsed)}
          </button> : null}
          {!projectCollapsed ? <div className="activity-group-nested">
            {(resolvedUnifiedGroupMode === "projectDevice" ? groupedFor(projectGroup.activities, "device", `${projectGroup.key}::device:`) : [null]).map((deviceGroup) => {
              if (!deviceGroup) return null;
              const deviceCollapsed = collapsedGroups.has(deviceGroup.key);
              const deviceAppGroups = groupedFor(deviceGroup.activities, "application", `${deviceGroup.key}::application:`);
              return <section className="activity-group activity-group-device" key={deviceGroup.key}>
                <button type="button" className="activity-group-heading activity-group-device-heading" onClick={() => toggleGroup(deviceGroup.key)} aria-expanded={!deviceCollapsed}>
                  <span className="activity-group-title"><Laptop size={15} /><strong>{deviceGroup.label}</strong></span>
                  {renderGroupMeta(deviceGroup, deviceCollapsed)}
                </button>
                {!deviceCollapsed ? <div className="activity-group-nested activity-group-device-nested">
                  {deviceAppGroups.map((appGroup) => {
                    const appCollapsed = collapsedGroups.has(appGroup.key);
                    const AppIcon = activityIcon(appGroup.activities[0]);
                    const categories = [...(appGroup.categories?.values?.() || [])];
                    return <section className="activity-group activity-group-application" key={appGroup.key}>
                      <button type="button" className="activity-group-heading activity-group-application-heading" onClick={() => toggleGroup(appGroup.key)} aria-expanded={!appCollapsed}>
                        <span className="activity-group-title"><span className="activity-table-icon activity-group-app-icon"><AppIcon size={17} weight="duotone" /></span><strong>{appGroup.label}</strong>{categorySummary(categories)}</span>
                        {renderGroupMeta(appGroup, appCollapsed)}
                      </button>
                      {!appCollapsed ? <div className="activity-group-rows">{appGroup.activities.map(activityRow)}</div> : null}
                    </section>;
                  })}
                </div> : null}
              </section>;
            })}
            {(resolvedUnifiedGroupMode === "projectDevice" ? [] : appGroups).map((appGroup) => {
              const appCollapsed = collapsedGroups.has(appGroup.key);
              const AppIcon = activityIcon(appGroup.activities[0]);
              const categories = [...(appGroup.categories?.values?.() || [])];
              return <section className="activity-group activity-group-application" key={appGroup.key}>
                <button type="button" className="activity-group-heading activity-group-application-heading" onClick={() => toggleGroup(appGroup.key)} aria-expanded={!appCollapsed}>
                  <span className="activity-group-title"><span className="activity-table-icon activity-group-app-icon"><AppIcon size={17} weight="duotone" /></span><strong>{appGroup.label}</strong>{categorySummary(categories)}</span>
                  {renderGroupMeta(appGroup, appCollapsed)}
                </button>
                {!appCollapsed ? <div className="activity-group-rows">{appGroup.activities.map(activityRow)}</div> : null}
              </section>;
            })}
          </div> : null}
        </section>;
      })}
      {contextMenu ? <ActivityContextMenu activity={contextMenu.activity} x={contextMenu.x} y={contextMenu.y} onClose={() => setContextMenu(null)} onSelect={onSelect} onCreateTimeEntry={onCreateTimeEntry} /> : null}
    </div>;
  }
  if (grouping === "projectDevice") {
    const projectGroups = groupedFor(rows, "project", "project:");
    return <div className="activity-table activity-table-project-device">
      {projectGroups.map((projectGroup) => {
        const projectCollapsed = collapsedGroups.has(projectGroup.key);
        const deviceGroups = groupedFor(projectGroup.activities, "device", `${projectGroup.key}::device:`);
        return <section className="activity-group activity-group-project" key={projectGroup.key}>
          <button type="button" className="activity-group-heading activity-group-project-heading" onClick={() => toggleGroup(projectGroup.key)} aria-expanded={!projectCollapsed}>
            <span className="activity-group-title"><FolderSimple size={16} /><strong>{projectGroup.label}</strong></span>
            {renderGroupMeta(projectGroup, projectCollapsed)}
          </button>
          {!projectCollapsed ? <div className="activity-group-nested">
            {deviceGroups.map((deviceGroup) => {
              const deviceCollapsed = collapsedGroups.has(deviceGroup.key);
              return <section className="activity-group activity-group-device" key={deviceGroup.key}>
                <button type="button" className="activity-group-heading activity-group-device-heading" onClick={() => toggleGroup(deviceGroup.key)} aria-expanded={!deviceCollapsed}>
                  <span className="activity-group-title"><Laptop size={15} /><strong>{deviceGroup.label}</strong></span>
                  {renderGroupMeta(deviceGroup, deviceCollapsed)}
                </button>
                {!deviceCollapsed ? <div className="activity-group-rows">{deviceGroup.activities.map(activityRow)}</div> : null}
              </section>;
            })}
          </div> : null}
        </section>;
      })}
      {contextMenu ? <ActivityContextMenu activity={contextMenu.activity} x={contextMenu.x} y={contextMenu.y} onClose={() => setContextMenu(null)} onSelect={onSelect} onCreateTimeEntry={onCreateTimeEntry} /> : null}
    </div>;
  }
  const grouped = groupedFor(rows, grouping);
  return <div className="activity-table">
    {grouped.map(renderFlatGroup)}
    {contextMenu ? <ActivityContextMenu activity={contextMenu.activity} x={contextMenu.x} y={contextMenu.y} onClose={() => setContextMenu(null)} onSelect={onSelect} onCreateTimeEntry={onCreateTimeEntry} /> : null}
  </div>;
}

function WebActivityCategoryCards({ activities, dateKey, displayPreferences, onSelect, onCreateTimeEntry }) {
  const durationFor = (activity) => activityDurationSeconds(activity);
  const websiteName = (activity) => {
    try {
      return new URL(activity.resource || "").host || "";
    } catch {
      return "";
    }
  };
  const pathName = (activity) => {
    if (!activity.resource || websiteName(activity)) return [];
    return pathGroupingNames(activity.resource, displayPreferences);
  };
  const keywordNames = (activity) => {
    const stopWords = new Set(["the", "and", "for", "with", "from", "http", "https", "www", "com"]);
    return [...new Set(`${activity.windowTitle || ""} ${activity.resource || ""}`
      .split(/[^\p{L}\p{N}_-]+/u)
      .map((value) => value.toLowerCase())
      .filter((value) => value.length >= 3 && !stopWords.has(value)))];
  };
  const groupedRows = (segments, namesFor) => {
    const groups = new Map();
    segments.forEach((activity) => {
    namesFor(activity).flatMap((name) => Array.isArray(name) ? name : [name]).filter(Boolean).forEach((name) => {
        const category = activityCategory(activity);
        const row = groups.get(name) || { name, activities: [], seconds: 0, categories: new Map() };
        row.activities.push(activity);
        row.seconds += durationFor(activity);
        const categoryKey = `${category.key}:${category.label}:${category.color}`;
        const categoryBucket = row.categories.get(categoryKey) || { category, seconds: 0 };
        categoryBucket.seconds += durationFor(activity);
        row.categories.set(categoryKey, categoryBucket);
        groups.set(name, row);
      });
    });
    return [...groups.values()].map((row) => {
      const category = [...row.categories.values()].sort((left, right) => right.seconds - left.seconds)[0]?.category || { key: "other", label: "Other", color: "graphite" };
      return { ...row, category };
    }).sort((left, right) => right.seconds - left.seconds || left.name.localeCompare(right.name));
  };
  const cards = [
    { key: "websites", title: "Websites", Icon: GlobeSimple, segments: activities.filter((activity) => Boolean(websiteName(activity))), rows: groupedRows(activities, (activity) => [websiteName(activity)]) },
    { key: "applications", title: "Applications", Icon: Laptop, segments: activities.filter((activity) => Boolean(activity.appName || activity.deviceName)), rows: groupedRows(activities, (activity) => [activity.appName || activity.deviceName || "Unknown App"]) },
    { key: "paths", title: "Paths", Icon: FolderSimple, segments: activities.filter((activity) => pathName(activity).length > 0), rows: groupedRows(activities, pathName) },
    { key: "keywords", title: "Keywords", Icon: FileText, segments: activities.filter((activity) => keywordNames(activity).length > 0), rows: groupedRows(activities, keywordNames) },
  ];
  const openDetails = (event, activity) => {
    if (event.target.closest("button")) return;
    onSelect?.(activity);
  };
  const createTimeEntry = (event, activity) => {
    event.preventDefault();
    event.stopPropagation();
    onCreateTimeEntry?.(activity);
  };
  const handleKeyDown = (event, activity) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect?.(activity);
    }
  };
  const dragStart = (event, row) => {
    event.dataTransfer.effectAllowed = "copy";
    event.dataTransfer.setData("application/x-metriday-activity", row.activities.map((activity) => resourceID(activity.id)).join("\n"));
    event.dataTransfer.setData("text/plain", row.activities.map((activity) => resourceID(activity.id)).join("\n"));
    event.dataTransfer.setData("application/x-metriday-activity-date", row.activities[0]?.date || dateKey);
  };
  return <div className="activity-category-card-grid">
    {cards.map(({ key, title, Icon, segments, rows }) => <section className="activity-category-card" key={key} aria-label={title}>
      <header className="activity-category-card-heading"><span><Icon size={17} /><strong>{title}</strong></span><small>{formatDurationSeconds(segments.reduce((total, activity) => total + durationFor(activity), 0))}</small></header>
      {rows.length ? <div className="activity-category-card-rows">{rows.slice(0, 6).map((row) => <div className="activity-category-card-row" key={row.name} role="button" tabIndex={0} draggable onDragStart={(event) => dragStart(event, row)} onClick={(event) => openDetails(event, row.activities[0])} onDoubleClick={(event) => createTimeEntry(event, row.activities[0])} onKeyDown={(event) => handleKeyDown(event, row.activities[0])} aria-label={`Open ${row.name} in ${title}`} title="Click for details · double-click to create a time entry · drag to a project">
        <span className={`activity-category-card-dot ${row.category.key}`} style={{ background: activityCategoryStyle(row.category).color }} title={row.category.label} aria-label={row.category.label} />
        <strong>{row.name}</strong><span>{formatDurationSeconds(row.seconds)}</span>
      </div>)}</div> : <p className="activity-category-card-empty">No matching activity</p>}
    </section>)}
  </div>;
}

function ActivityDetailDialog({ activity, api, dateKey, displayPreferences = null, onClose }) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [overlapEntries, setOverlapEntries] = useState([]);
  const projectLabel = projectTitleFor(api.projects, activity.projectID);
  const wrapAtMinute = Math.max(0, Math.min(1439, Number(api.preferences?.wrap_days_at_minute ?? 0)));
  const category = activityCategory(activity);
  const Icon = activityIcon(activity);
  const app = activity.appName || activity.deviceName || "Unknown App";
  const context = activityContext(activity, {
    showWindowTitles: displayPreferences?.show_window_titles,
    showResourcePaths: displayPreferences?.show_resource_paths,
    includeTitlesInAdditionToPaths: displayPreferences?.include_titles_in_addition_to_paths,
  });
  const startSecond = Math.max(0, Number(activity.startSecond || 0));
  const endSecond = Math.max(startSecond, Number(activity.endSecond || 0));
  const record = async (overlapDecision = null) => {
    if (busy || !api.connected || endSecond <= startSecond) return;
    const activityDateKey = activity.date || dateKey;
    if (overlapDecision === null && overlapEntries.length === 0) {
      const overlaps = api.entries.filter((entry) => {
        const range = entrySecondsForDate(entry, activityDateKey, wrapAtMinute);
        return range && range.startSecond < endSecond && range.endSecond > startSecond;
      });
      if (overlaps.length > 0) {
        setOverlapEntries(overlaps);
        setMessage(`This activity overlaps ${overlaps.length} existing time ${overlaps.length === 1 ? "entry" : "entries"}.`);
        return;
      }
    }
    setBusy(true);
    setMessage("");
    try {
      const start = localEntryDateSeconds(activityDateKey, startSecond, wrapAtMinute);
      const end = localEntryDateSeconds(activityDateKey, endSecond, wrapAtMinute);
      await api.addTimeEntry({
        title: activity.appName || activity.deviceName || "App activity",
        notes: activity.displayTitle || activityLabel(activity),
        start,
        end,
        projectID: activity.projectID || undefined,
        billingStatus: "billable",
        replace_overlapping: overlapDecision === "replace",
      });
      setOverlapEntries([]);
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
      {overlapEntries.length > 0 ? <div className="time-entry-overlap-callout" role="alert"><strong>Overlapping Time Entry</strong><p>This activity overlaps {overlapEntries.length} existing time {overlapEntries.length === 1 ? "entry" : "entries"}. Replace them or keep parallel entries?</p><div><button type="button" className="secondary-button" onClick={() => { setOverlapEntries([]); setMessage(""); }}>Cancel</button><button type="button" className="secondary-button" onClick={() => record("keep")} disabled={busy}>Keep Both</button><button type="button" className="secondary-button danger-pill" onClick={() => record("replace")} disabled={busy}>Replace Existing</button></div></div> : null}
      {message ? <p className="entry-message" role="status">{message}</p> : null}
      <footer className="activity-detail-actions"><button type="button" className="secondary-button" onClick={onClose}>Close</button><button type="button" className="primary-button" onClick={() => record()} disabled={busy || !api.connected || endSecond <= startSecond || overlapEntries.length > 0}>{busy ? "Recording…" : "Record time"}</button></footer>
    </section>
  </div>;
}

function WebPhoneCallsPanel({ api, onRecord }) {
  const payload = api.phoneCalls || {};
  const calls = Array.isArray(payload.data) ? payload.data : [];
  const formatCallTime = (value) => {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  };
  return <section className="web-source-panel" aria-label="Phone Calls"><div className="web-source-heading"><div><h2>Phone Calls</h2><p>Read-only call history that can be recorded as local time evidence.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.database_available ? "online" : ""}`}>{payload.database_available ? `${calls.length} calls` : "Not connected"}</span>{!payload.database_available && api.requestSourceAccess ? <button type="button" className="quiet-pill" onClick={() => api.requestSourceAccess("phone-calls")}>Connect</button> : null}<button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{calls.length > 0 ? <div className="web-source-list">{calls.map((call) => <div className="web-source-row" key={call.id} role={onRecord ? "button" : undefined} tabIndex={onRecord ? 0 : undefined} aria-label={onRecord ? "Record phone call " + (call.address || "this call") : undefined} onClick={(event) => { if (event.target.closest("button")) return; onRecord?.(call); }} onKeyDown={(event) => { if (event.target.closest("button")) return; if (onRecord && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); onRecord(call); } }}><span className="web-source-icon"><Clock size={18} /></span><div><strong>{call.address || "Phone call"}</strong><small>{call.service_provider || "Call history"} · {formatCallTime(call.start)}–{formatCallTime(call.end)}</small></div><span>{formatDurationSeconds(Number(call.duration_seconds || 0))}</span>{onRecord ? <button type="button" className="quiet-pill" onClick={() => onRecord(call)}>Record</button> : null}<IconButton label={`Hide calls from ${call.address || "this address"}`} onClick={() => api.hidePhoneCallAddress(call.address, true)}><X size={15} /></IconButton></div>)}</div> : <div className="web-source-empty"><Clock size={22} /><span>{payload.status || "No phone calls for this date."}</span></div>}</section>;
}

function localDateTimeInput(value) {
  const date = new Date(value || "");
  if (Number.isNaN(date.getTime())) return "";
  const pad = (number) => String(number).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function WebCalendarEventDialog({ event, api, dateKey, onClose }) {
  const [title, setTitle] = useState(event?.title || "");
  const [start, setStart] = useState(() => localDateTimeInput(event?.start));
  const [end, setEnd] = useState(() => localDateTimeInput(event?.end));
  const [notes, setNotes] = useState(event?.notes || "");
  const [message, setMessage] = useState("");
  const save = async (submitEvent) => {
    submitEvent.preventDefault();
    const startDate = new Date(start);
    const endDate = new Date(end);
    if (!title.trim() || Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime()) || endDate <= startDate) {
      setMessage("Enter a title and a valid time range.");
      return;
    }
    try {
      await api.updateCalendarEvent(event.id, { date: dateKey, title: title.trim(), start: startDate.toISOString(), end: endDate.toISOString(), notes });
      onClose();
    } catch (error) {
      setMessage(error.message || "Could not update the Calendar Event.");
    }
  };
  const remove = async () => {
    if (!window.confirm(`Delete “${event.title || "Calendar Event"}”?`)) return;
    try {
      await api.deleteCalendarEvent(event.id, dateKey);
      onClose();
    } catch (error) {
      setMessage(error.message || "Could not delete the Calendar Event.");
    }
  };
  return <div className="dialog-backdrop" role="presentation" onClick={onClose}><form className="entry-dialog calendar-event-dialog" role="dialog" aria-modal="true" aria-labelledby="calendar-event-dialog-title" onClick={(clickEvent) => clickEvent.stopPropagation()} onSubmit={save}><div className="dialog-heading"><div><span>Calendar Event</span><h2 id="calendar-event-dialog-title">Edit Event</h2></div><IconButton label="Close Calendar Event editor" onClick={onClose}><X size={18} /></IconButton></div><label>Title<input value={title} onChange={(changeEvent) => setTitle(changeEvent.target.value)} autoFocus /></label><div className="entry-dialog-grid"><label>Start<input type="datetime-local" value={start} onChange={(changeEvent) => setStart(changeEvent.target.value)} /></label><label>End<input type="datetime-local" value={end} onChange={(changeEvent) => setEnd(changeEvent.target.value)} /></label></div><label>Notes<textarea value={notes} onChange={(changeEvent) => setNotes(changeEvent.target.value)} rows={3} /></label>{message ? <p className="entry-message" role="status">{message}</p> : null}<div className="dialog-actions"><button type="button" className="quiet-pill danger-pill" onClick={remove}>Delete</button><span /><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="submit" className="primary-button">Save</button></div></form></div>;
}

function WebCalendarEventsPanel({ api, onRecord, dateKey }) {
  const payload = api.calendarEvents || {};
  const events = Array.isArray(payload.data) ? payload.data : [];
  const eventDateKey = dateKey || payload.date || localDateKey();
  const [message, setMessage] = useState("");
  const [selectedEvent, setSelectedEvent] = useState(null);
  const record = async (event) => {
    if (onRecord) {
      onRecord(event);
      return;
    }
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
  return <><section className="web-source-panel" aria-label="Calendar Events"><div className="web-source-heading"><div><h2>Calendar Events</h2><p>Calendar events can be recorded as local time or edited when their calendar is writable.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.authorized ? "online" : ""}`}>{payload.authorized ? `${events.length} events` : "Not connected"}</span>{!payload.authorized && api.requestSourceAccess ? <button type="button" className="quiet-pill" onClick={() => api.requestSourceAccess("calendar")}>Connect</button> : null}<button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{events.length > 0 ? <div className="web-source-list">{events.map((event) => <div className="web-source-row" key={event.id} role="button" tabIndex={0} aria-label={"Record calendar event " + event.title} onClick={(clickEvent) => { if (clickEvent.target.closest("button")) return; record(event); }} onKeyDown={(keyboardEvent) => { if (keyboardEvent.target.closest("button")) return; if (keyboardEvent.key === "Enter" || keyboardEvent.key === " ") { keyboardEvent.preventDefault(); record(event); } }}><span className="web-source-icon"><CalendarBlank size={18} /></span><div><strong>{event.title}</strong><small>{event.calendar || "Calendar"} · {time(event.start)}–{time(event.end)}{event.location ? ` · ${event.location}` : ""}</small></div><button type="button" className="quiet-pill" onClick={() => record(event)}>Record</button>{event.is_editable ? <button type="button" className="quiet-pill" onClick={() => setSelectedEvent(event)}>Edit</button> : null}</div>)}</div> : <div className="web-source-empty"><CalendarBlank size={22} /><span>{payload.status || "No calendar events for this date."}</span></div>}{message ? <p className="entry-message" role="status">{message}</p> : null}</section>{selectedEvent ? <WebCalendarEventDialog event={selectedEvent} api={api} dateKey={eventDateKey} onClose={() => setSelectedEvent(null)} /> : null}</>;
}

function WebRemindersPanel({ api, onRecord }) {
  const payload = api.reminders || {};
  const reminders = Array.isArray(payload.data) ? payload.data : [];
  const [message, setMessage] = useState("");
  const record = async (reminder) => {
    const start = new Date(reminder.completed_at || "");
    if (Number.isNaN(start.getTime())) return;
    const end = new Date(start.getTime() + 15 * 60 * 1000).toISOString();
    if (onRecord) {
      onRecord({ ...reminder, start: reminder.completed_at, end });
      return;
    }
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
  return <section className="web-source-panel" aria-label="Completed Reminders"><div className="web-source-heading"><div><h2>Completed Reminders</h2><p>Completed local reminders remain read-only and can suggest a 15-minute time entry.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.authorized ? "online" : ""}`}>{payload.authorized ? `${reminders.length} completed` : "Not connected"}</span>{!payload.authorized && api.requestSourceAccess ? <button type="button" className="quiet-pill" onClick={() => api.requestSourceAccess("reminders")}>Connect</button> : null}<button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{reminders.length > 0 ? <div className="web-source-list">{reminders.map((reminder) => <div className="web-source-row" key={reminder.id} role="button" tabIndex={0} aria-label={"Record reminder " + reminder.title} onClick={(clickEvent) => { if (clickEvent.target.closest("button")) return; record(reminder); }} onKeyDown={(keyboardEvent) => { if (keyboardEvent.target.closest("button")) return; if (keyboardEvent.key === "Enter" || keyboardEvent.key === " ") { keyboardEvent.preventDefault(); record(reminder); } }}><span className="web-source-icon"><CheckCircle size={18} /></span><div><strong>{reminder.title}</strong><small>{reminder.list || "Reminders"} · Completed {time(reminder.completed_at)}{reminder.is_recurring ? " · Recurring" : ""}</small></div><button type="button" className="quiet-pill" onClick={() => record(reminder)}>Record</button></div>)}</div> : <div className="web-source-empty"><CheckCircle size={22} /><span>{payload.status || "No completed reminders for this date."}</span></div>}{message ? <p className="entry-message" role="status">{message}</p> : null}</section>;
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
  return <section className="web-source-panel" aria-label="Screen Time"><div className="web-source-heading"><div><h2>Screen Time</h2><p>Read-only Apple Screen Time imports are included in the Activities evidence above.</p></div><div className="web-source-actions"><span className={`api-badge ${payload.database_available ? "online" : ""}`}>{payload.database_available ? `${segments.length} records` : "Not connected"}</span>{!payload.database_available && api.requestSourceAccess ? <button type="button" className="quiet-pill" onClick={() => api.requestSourceAccess("screen-time")}>Connect</button> : null}<button type="button" className="quiet-pill" onClick={api.refresh}>Refresh</button></div></div>{grouped.length > 0 ? <div className="web-source-list">{grouped.map((item) => <div className="web-source-row" key={item.key}><span className="web-source-icon" style={{ color: activityCategoryStyle(item.category).color }}><Laptop size={18} /></span><div><strong>{item.label}</strong><small>{item.category.label} · Imported Screen Time</small></div><span>{formatDurationSeconds(item.seconds)}</span></div>)}</div> : <div className="web-source-empty"><Laptop size={22} /><span>{payload.status || "No Screen Time activities for this date."}</span></div>}</section>;
}

function WebActivityFiltersPanel({ api }) {
  const [name, setName] = useState("");
  const [color, setColor] = useState("purple");
  const [matchMode, setMatchMode] = useState("any");
  const [rules, setRules] = useState(() => [{ field: "application", comparison: "contains", pattern: "", case_sensitive: false }]);
  const [editingID, setEditingID] = useState(null);
  const [message, setMessage] = useState("");
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", windowTitle: "Window title", resource: "URL or path", domain: "Domain", fullURL: "Full website URL", keyword: "Keyword", device: "Device", startTime: "Start time", dayOfWeek: "Day of week" };
  const comparisons = { contains: "contains", equals: "is", beginsWith: "begins with", endsWith: "ends with", like: "is like", isNot: "is not", matchesRegex: "matches regex" };
  const emptyRule = () => ({ field: "application", comparison: "contains", pattern: "", case_sensitive: false });
  const resetEditor = () => {
    setName("");
    setColor("purple");
    setMatchMode("any");
    setRules([emptyRule()]);
    setEditingID(null);
    setMessage("");
  };
  const submit = async (event) => {
    event.preventDefault();
    const normalizedRules = rules
      .map((rule) => ({ ...rule, pattern: String(rule.pattern || "").trim(), case_sensitive: Boolean(rule.case_sensitive) }))
      .filter((rule) => rule.pattern);
    if (!name.trim() || !normalizedRules.length || !api.connected) return;
    try {
      const payload = { name: name.trim(), color, match_mode: matchMode, rules: normalizedRules };
      if (editingID) await api.updateActivityFilter(editingID, payload);
      else await api.createActivityFilter(payload);
      resetEditor();
      setMessage("Filter saved locally.");
    } catch (error) {
      setMessage(error.message || "Could not save filter.");
    }
  };
  const beginEdit = (filter) => {
    setEditingID(resourceID(filter.id));
    setName(filter.name || "");
    setColor(filter.color || "purple");
    setMatchMode(filter.match_mode || "any");
    setRules((filter.rules || []).map((rule) => ({ field: rule.field || "application", comparison: rule.comparison || "contains", pattern: rule.pattern || "", case_sensitive: Boolean(rule.case_sensitive) })));
    setMessage("");
  };
  const updateRule = (index, patch) => setRules((current) => current.map((rule, ruleIndex) => ruleIndex === index ? { ...rule, ...patch } : rule));
  const removeRule = (index) => setRules((current) => current.filter((_, ruleIndex) => ruleIndex !== index));
  return <section id="web-activity-filters-panel" className="web-source-panel web-filters-panel" aria-label="Activity Filters"><div className="web-source-heading"><div><h2>Filters</h2><p>Save reusable App, website, and device rules for this activity stream.</p></div><span className="api-badge">{api.filters.length} saved</span></div><form className="web-category-form web-filter-editor" onSubmit={submit}><div className="web-category-primary-fields"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Filter name" aria-label="Activity filter name" /><select value={color} onChange={(event) => setColor(event.target.value)} aria-label="Activity filter color"><option value="blue">Blue</option><option value="red">Red</option><option value="green">Green</option><option value="orange">Orange</option><option value="purple">Purple</option><option value="graphite">Graphite</option></select></div><div className="web-category-rules"><div className="web-category-rules-heading"><div><strong>Matching rules</strong><small>Filters never change project assignments.</small></div><label>Match<select value={matchMode} onChange={(event) => setMatchMode(event.target.value)} aria-label="Activity filter match mode"><option value="any">Any rule</option><option value="all">All rules</option></select></label></div><div className="web-category-rule-list">{rules.map((rule, index) => <div className="web-category-rule-row" key={`${index}-${rule.field}`}><select value={rule.field} onChange={(event) => updateRule(index, { field: event.target.value })} aria-label={`Activity filter rule ${index + 1} field`}>{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={rule.comparison} onChange={(event) => updateRule(index, { comparison: event.target.value })} aria-label={`Activity filter rule ${index + 1} comparison`}>{Object.entries(comparisons).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><input value={rule.pattern} onChange={(event) => updateRule(index, { pattern: event.target.value })} placeholder="Matching value" aria-label={`Activity filter rule ${index + 1} value`} /><label className="exclusion-case-toggle"><input type="checkbox" checked={Boolean(rule.case_sensitive)} onChange={(event) => updateRule(index, { case_sensitive: event.target.checked })} />Case-sensitive</label><button type="button" className="web-category-remove-rule" onClick={() => removeRule(index)} aria-label={`Remove activity filter rule ${index + 1}`}><Trash size={14} /></button></div>)}</div><button type="button" className="web-category-add-rule" onClick={() => setRules((current) => [...current, emptyRule()])}><Plus size={15} />Add rule</button></div><div className="web-category-form-actions">{message ? <small role="status">{message}</small> : null}<span>{editingID ? <button type="button" className="quiet-pill" onClick={resetEditor}>Cancel</button> : null}<button type="submit" disabled={!api.connected || !name.trim() || !rules.some((rule) => String(rule.pattern || "").trim())}>{editingID ? <Check size={16} /> : <Plus size={16} />}{editingID ? "Save changes" : "Save filter"}</button></span></div></form>{api.filters.length > 0 ? <div className="web-source-list">{api.filters.map((filter) => <div className="web-source-row web-filter-row" key={filter.id}><span className="web-source-icon" style={{ color: activityCategoryStyle({ color: filter.color }).color }}><Waveform size={17} /></span><div><strong>{filter.name}</strong><small>{(filter.rules || []).map((rule) => `${fields[rule.field] || rule.field} ${comparisons[rule.comparison] || rule.comparison} “${rule.pattern}”${rule.case_sensitive ? " · Case-sensitive" : ""}`).join(` ${filter.match_mode === "all" ? "and" : "or"} `)}</small></div><span>{filter.match_mode === "all" ? "All rules" : "Any rule"}</span><span className="web-category-actions"><IconButton label={`Edit ${filter.name}`} onClick={() => beginEdit(filter)}><NotePencil size={15} /></IconButton><IconButton label={`Delete ${filter.name}`} onClick={() => api.deleteActivityFilter(filter.id)}><Trash size={15} /></IconButton></span></div>)}</div> : <div className="web-source-empty"><Waveform size={22} /><span>No saved filters yet. Add one to reuse the same activity rule on this Mac.</span></div>}</section>;
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
  const [matchMode, setMatchMode] = useState("any");
  const [rules, setRules] = useState(() => [{ field: "application", comparison: "contains", pattern: "", case_sensitive: false }]);
  const [editingID, setEditingID] = useState(null);
  const [message, setMessage] = useState("");
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", windowTitle: "Window title", resource: "URL or path", domain: "Domain", fullURL: "Full website URL", keyword: "Keyword", device: "Device", startTime: "Start time", dayOfWeek: "Day of week" };
  const comparisons = { contains: "contains", equals: "is", beginsWith: "begins with", endsWith: "ends with", like: "is like", isNot: "is not", matchesRegex: "matches regex" };
  const comparisonRawValue = (value) => Object.entries(comparisons).find(([raw, label]) => raw === value || label === value)?.[0] || "contains";
  const comparisonLabel = (value) => comparisons[value] || value || comparisons.contains;
  const emptyRule = () => ({ field: "application", comparison: "contains", pattern: "", case_sensitive: false });
  const resetEditor = () => {
    setName("");
    setRole("focused");
    setColor("blue");
    setMatchMode("any");
    setRules([emptyRule()]);
    setEditingID(null);
    setMessage("");
  };
  const submit = async (event) => {
    event.preventDefault();
    const normalizedRules = rules
      .map((rule) => ({ ...rule, comparison: comparisonRawValue(rule.comparison), pattern: String(rule.pattern || "").trim(), case_sensitive: Boolean(rule.case_sensitive) }))
      .filter((rule) => rule.pattern);
    if (!name.trim() || !normalizedRules.length || !api.connected) return;
    try {
      const normalizedColor = role === "focused" ? "blue" : role === "distracting" ? "red" : color;
      const payload = { name: name.trim(), role, color: normalizedColor, match_mode: matchMode, rules: normalizedRules };
      if (editingID) await api.updateActivityCategory(editingID, payload);
      else await api.createActivityCategory(payload);
      resetEditor();
      setMessage("Category saved locally.");
    } catch (error) {
      setMessage(error.message || "Could not save category.");
    }
  };
  const beginEdit = (category) => {
    setEditingID(resourceID(category.id));
    setName(category.name || "");
    setRole(category.role || "other");
    setColor(category.color || "graphite");
    setMatchMode(category.match_mode || "any");
    setRules((category.rules || []).map((rule) => ({ field: rule.field || "application", comparison: comparisonLabel(rule.comparison), pattern: rule.pattern || "", case_sensitive: Boolean(rule.case_sensitive) })));
    setMessage("");
  };
  const updateRule = (index, patch) => setRules((current) => current.map((rule, ruleIndex) => ruleIndex === index ? { ...rule, ...patch } : rule));
  const removeRule = (index) => setRules((current) => current.filter((_, ruleIndex) => ruleIndex !== index));
  return <section className="web-source-panel web-categories-panel" aria-label="Activity Categories"><div className="web-source-heading"><div><h2>Categories</h2><p>App, website, and item colors come from these matching categories.</p></div><span className="api-badge">{api.categories.length} active</span></div><form className="web-category-form" onSubmit={submit}><div className="web-category-primary-fields"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Category name" aria-label="Activity category name" /><select value={role} onChange={(event) => { const nextRole = event.target.value; setRole(nextRole); if (nextRole === "focused") setColor("blue"); else if (nextRole === "distracting") setColor("red"); }} aria-label="Activity category role"><option value="focused">Focused</option><option value="distracting">Distracting</option><option value="other">Other</option><option value="idle">Idle</option></select><select value={color} onChange={(event) => setColor(event.target.value)} aria-label="Activity category color" disabled={role === "focused" || role === "distracting"}><option value="blue">Deep blue</option><option value="red">Red</option><option value="green">Green</option><option value="orange">Orange</option><option value="purple">Purple</option><option value="graphite">Graphite</option></select></div><div className="web-category-rules"><div className="web-category-rules-heading"><div><strong>Matching rules</strong><small>Rules are evaluated before the built-in category fallbacks.</small></div><label>Match<select value={matchMode} onChange={(event) => setMatchMode(event.target.value)} aria-label="Activity category match mode"><option value="any">Any rule</option><option value="all">All rules</option></select></label></div><div className="web-category-rule-list">{rules.map((rule, index) => <div className="web-category-rule-row" key={`${index}-${rule.field}`}><select value={rule.field} onChange={(event) => updateRule(index, { field: event.target.value })} aria-label={`Category rule ${index + 1} field`}>{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={rule.comparison} onChange={(event) => updateRule(index, { comparison: event.target.value })} aria-label={`Category rule ${index + 1} comparison`}>{Object.entries(comparisons).map(([value, label]) => <option key={value} value={label}>{label}</option>)}</select><input value={rule.pattern} onChange={(event) => updateRule(index, { pattern: event.target.value })} placeholder="Matching value" aria-label={`Category rule ${index + 1} value`} /><button type="button" className="web-category-remove-rule" onClick={() => removeRule(index)} aria-label={`Remove category rule ${index + 1}`}><Trash size={14} /></button></div>)}</div><button type="button" className="web-category-add-rule" onClick={() => setRules((current) => [...current, emptyRule()])}><Plus size={15} />Add rule</button></div><div className="web-category-form-actions">{message ? <small role="status">{message}</small> : null}<span>{editingID ? <button type="button" className="quiet-pill" onClick={resetEditor}>Cancel</button> : null}<button type="submit" disabled={!api.connected || !name.trim() || !rules.some((rule) => String(rule.pattern || "").trim())}>{editingID ? <Check size={16} /> : <Plus size={16} />}{editingID ? "Save changes" : "Save category"}</button></span></div></form><div className="web-category-list">{api.categories.map((category) => <div className="web-category-row" key={category.id}><span className="web-category-swatch" style={{ background: activityCategoryStyle({ color: category.color }).color }} /><div><strong>{category.name}</strong><small>{category.is_system ? `Built-in fallback · ${category.role}` : `${(category.rules || []).length} rule${(category.rules || []).length === 1 ? "" : "s"} · ${category.match_mode === "all" ? "all" : "any"} · ${category.role}`}</small></div>{category.is_system ? <span className="web-category-system">Built-in</span> : <span className="web-category-actions"><IconButton label={`Edit ${category.name}`} onClick={() => beginEdit(category)}><NotePencil size={15} /></IconButton><IconButton label={`Delete ${category.name}`} onClick={() => api.deleteActivityCategory(category.id)}><Trash size={15} /></IconButton></span>}</div>)}</div></section>;
}

function WebActivityDisplayMenu({ open, onToggle, preferences, devices, onChange }) {
  const values = preferences || {
    include_time_entries: false,
    show_window_titles: true,
    show_resource_paths: true,
    show_activity_date_ranges: false,
    include_titles_in_addition_to_paths: true,
    group_websites_independently: false,
    group_paths_independently: false,
    group_paths_by: "allDirectories",
    activity_time_range: "selectedDay",
    selected_device: "All Devices",
    collapse_activities_shorter_than_seconds: 0,
  };
  return <div className="activity-display-menu"><button type="button" className={`quiet-pill activity-display-button ${open ? "active" : ""}`} onClick={onToggle} aria-expanded={open} aria-haspopup="dialog"><SlidersHorizontal size={15} />Display</button>{open ? <div className="activity-display-popover" role="dialog" aria-label="Activity display settings"><strong>Display settings</strong><label><input type="checkbox" checked={Boolean(values.include_time_entries)} onChange={(event) => onChange({ include_time_entries: event.target.checked })} />Include time entries</label><label><input type="checkbox" checked={Boolean(values.show_window_titles)} onChange={(event) => onChange({ show_window_titles: event.target.checked })} />Show window titles</label><label><input type="checkbox" checked={Boolean(values.show_resource_paths)} onChange={(event) => onChange({ show_resource_paths: event.target.checked })} />Show website paths</label><label><input type="checkbox" checked={Boolean(values.show_activity_date_ranges)} onChange={(event) => onChange({ show_activity_date_ranges: event.target.checked })} />Show app-usage date ranges</label><label><input type="checkbox" checked={Boolean(values.include_titles_in_addition_to_paths)} onChange={(event) => onChange({ include_titles_in_addition_to_paths: event.target.checked })} />Create entries for titles in addition to paths</label><label className="activity-display-select">Collapse activities shorter than<select value={Number(values.collapse_activities_shorter_than_seconds || 0)} onChange={(event) => onChange({ collapse_activities_shorter_than_seconds: Number(event.target.value) })}><option value="0">Never</option><option value="5">5 seconds</option><option value="15">15 seconds</option><option value="30">30 seconds</option><option value="60">1 minute</option></select></label><label><input type="checkbox" checked={Boolean(values.group_websites_independently)} onChange={(event) => onChange({ group_websites_independently: event.target.checked })} />Group websites independently of browser</label><label><input type="checkbox" checked={Boolean(values.group_paths_independently)} onChange={(event) => onChange({ group_paths_independently: event.target.checked })} />Group paths independently of app</label><label className="activity-display-select">Group file paths by<select value={values.group_paths_by || "allDirectories"} onChange={(event) => onChange({ group_paths_by: event.target.value })}><option value="immediateParentDirectory">Immediate parent directory</option><option value="allDirectories">All directories</option><option value="filePathOnly">File path only</option></select></label><label className="activity-display-select">Activity range<select value={values.activity_time_range || "selectedDay"} onChange={(event) => onChange({ activity_time_range: event.target.value })}><option value="selectedDay">Selected day</option><option value="lastSevenDays">Last 7 days</option><option value="lastThirtyDays">Last 30 days</option><option value="lastNinetyDays">Last 90 days</option></select></label></div> : null}</div>;
}

function WebActivityDevicesMenu({ open, devices, selectedDevice, hideDevicesWithoutTime, onToggle, onSelect, onToggleHide }) {
  const availableDevices = hideDevicesWithoutTime ? devices.filter((device) => device === "This Mac" || device === selectedDevice) : devices;
  const title = selectedDevice === "all" ? "Devices" : selectedDevice;
  const option = (value, label, icon) => <button type="button" className={`activity-popover-option ${selectedDevice === value ? "active" : ""}`} onClick={() => onSelect(value)}><span>{icon}</span><strong>{label}</strong>{selectedDevice === value ? <Check size={14} weight="bold" /> : null}</button>;
  return <div className="activity-toolbar-popover"><button type="button" className={`quiet-pill activity-toolbar-popover-button ${open ? "active" : ""}`} onClick={onToggle} aria-expanded={open} aria-haspopup="dialog"><Laptop size={15} />{title}</button>{open ? <div className="activity-toolbar-popover-panel" role="dialog" aria-label="Devices"><strong>Devices</strong>{option("all", "All Mac devices", <Laptop size={15} />)}<div className="activity-popover-divider" />{availableDevices.filter((device) => device !== "This Mac").map((device) => option(device, device, <Laptop size={15} key={device} />))}{availableDevices.includes("This Mac") ? option("This Mac", "This Mac", <Laptop size={15} />) : null}{devices.length <= 1 ? <p className="activity-popover-empty">No other devices have recorded time yet.</p> : null}<div className="activity-popover-divider" /><label className="activity-popover-checkbox"><input type="checkbox" checked={hideDevicesWithoutTime} onChange={(event) => onToggleHide(event.target.checked)} />Hide devices without time</label></div> : null}</div>;
}

function WebActivityFiltersMenu({ open, filters, projectFilterID, savedFilterID, categoryFilter, onToggle, onProjectFilter, onSavedFilter, onCategoryFilter }) {
  const savedFilter = filters.find((filter) => resourceID(filter.id) === savedFilterID);
  const builtinKey = categoryFilter.startsWith("builtin:") ? categoryFilter.slice("builtin:".length) : "all";
  const builtin = activityBuiltinFilters.find((filter) => filter.key === builtinKey);
  const categoryLabel = categoryFilter === "all" ? "Filters" : categoryFilter[0].toUpperCase() + categoryFilter.slice(1);
  const title = savedFilter?.name || (projectFilterID === "unassigned" ? "Unassigned" : builtin?.label || categoryLabel);
  const selectAll = () => { onProjectFilter("all"); onSavedFilter("all"); onCategoryFilter("all"); };
  const selectProject = () => { onProjectFilter("unassigned"); onSavedFilter("all"); onCategoryFilter("all"); };
  const selectBuiltin = (value) => { onProjectFilter("all"); onSavedFilter("all"); onCategoryFilter("builtin:" + value); };
  const selectCategory = (value) => { onProjectFilter("all"); onSavedFilter("all"); onCategoryFilter(value); };
  const allSelected = savedFilterID === "all" && projectFilterID === "all" && categoryFilter === "all";
  return <div className="activity-toolbar-popover"><button type="button" className={`quiet-pill activity-toolbar-popover-button ${open ? "active" : ""}`} onClick={onToggle} aria-expanded={open} aria-haspopup="dialog"><SlidersHorizontal size={15} />{title}</button>{open ? <div className="activity-toolbar-popover-panel" role="dialog" aria-label="Activity filters"><strong>Filters</strong><button type="button" className={`activity-popover-option ${allSelected ? "active" : ""}`} onClick={selectAll}><span><Waveform size={15} /></span><strong>All activity</strong>{allSelected ? <Check size={14} weight="bold" /> : null}</button><button type="button" className={`activity-popover-option ${projectFilterID === "unassigned" ? "active" : ""}`} onClick={selectProject}><span><TrayIcon /></span><strong>Unassigned</strong>{projectFilterID === "unassigned" ? <Check size={14} weight="bold" /> : null}</button><div className="activity-popover-divider" /><span className="activity-popover-label">Built-in Filters</span>{activityBuiltinFilters.map((filter) => <button type="button" className={`activity-popover-option ${builtinKey === filter.key ? "active" : ""}`} key={filter.key} onClick={() => selectBuiltin(filter.key)}><span className="activity-popover-category-dot other" /><strong>{filter.label}</strong>{builtinKey === filter.key ? <Check size={14} weight="bold" /> : null}</button>)}<div className="activity-popover-divider" />{["focused", "distracting", "other", "idle"].map((value) => <button type="button" className={`activity-popover-option ${categoryFilter === value ? "active" : ""}`} key={value} onClick={() => selectCategory(value)}><span className={`activity-popover-category-dot ${value}`} /><strong>{value[0].toUpperCase() + value.slice(1)}</strong>{categoryFilter === value ? <Check size={14} weight="bold" /> : null}</button>)}{filters.length > 0 ? <><div className="activity-popover-divider" /><span className="activity-popover-label">Saved Filters</span>{filters.map((filter) => <button type="button" className={`activity-popover-option ${savedFilterID === resourceID(filter.id) ? "active" : ""}`} key={filter.id} onClick={() => { onProjectFilter("all"); onCategoryFilter("all"); onSavedFilter(resourceID(filter.id)); }}><span><Waveform size={15} /></span><strong>{filter.name}</strong>{savedFilterID === resourceID(filter.id) ? <Check size={14} weight="bold" /> : null}</button>)}</> : null}</div> : null}</div>;
}

function WebActivityProjectSidebar({ projects, filters, activities, projectFilterID, savedFilterID, onProjectFilter, onSavedFilter, onEditProject, onCreateProjectFromActivities, onDropActivity }) {
  const [collapsedProjectIDs, setCollapsedProjectIDs] = useState(() => new Set());
  const [dropTarget, setDropTarget] = useState(false);
  const [dropProjectID, setDropProjectID] = useState(null);
  const [dropMessage, setDropMessage] = useState("");
  const projectClickTimer = useRef(null);
  useEffect(() => () => { if (projectClickTimer.current) window.clearTimeout(projectClickTimer.current); }, []);
  const activeActivities = activities.filter((activity) => activityCategory(activity).key !== "idle");
  const secondsFor = (items) => items.reduce((total, activity) => total + Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0)), 0);
  const projectActivitiesFor = (project) => {
    const projectIDs = descendantProjectIDs(projects, project.id);
    return activeActivities.filter((activity) => projectIDs.has(resourceID(activity.projectID)));
  };
  const sidebarButton = (active, onClick, icon, title, detail, style = {}, onDoubleClick) => <button type="button" className={`activity-project-filter ${active ? "active" : ""}`} style={style} onClick={onClick} onDoubleClick={onDoubleClick}><span className="activity-project-filter-icon">{icon}</span><span><strong>{title}</strong><small>{detail}</small></span></button>;
  const selectProject = (project) => {
    if (projectClickTimer.current) window.clearTimeout(projectClickTimer.current);
    projectClickTimer.current = window.setTimeout(() => {
      onProjectFilter(resourceID(project.id));
      projectClickTimer.current = null;
    }, 220);
  };
  const editProject = (project) => {
    if (projectClickTimer.current) window.clearTimeout(projectClickTimer.current);
    projectClickTimer.current = null;
    onEditProject?.(resourceID(project.id));
  };
  const editSavedFilter = (filter) => {
    const panel = document.getElementById("web-activity-filters-panel");
    panel?.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => {
      const row = [...(panel?.querySelectorAll(".web-filter-row") || [])][filters.indexOf(filter)];
      row?.querySelector("button")?.click();
    }, 250);
  };
  const openProjectComposer = () => {
    const panel = document.getElementById("web-projects-panel");
    panel?.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => panel?.querySelector('input[aria-label="Project name"]')?.focus(), 250);
  };
  const handleProjectDropZoneKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    openProjectComposer();
  };
  const handleCreateProjectDrop = async (event) => {
    event.preventDefault();
    setDropTarget(false);
    const raw = event.dataTransfer.getData("application/x-metriday-activity") || event.dataTransfer.getData("text/plain");
    const activityIDs = [...new Set(raw.split(/\r?\n/).map((value) => resourceID(value.trim())).filter(Boolean))];
    const createProject = onCreateProjectFromActivities;
    if (!activityIDs.length || !createProject) {
      setDropMessage("Drop an App / Category activity row here.");
      return;
    }
    const parentProjectID = projects.some((project) => resourceID(project.id) === projectFilterID) ? projectFilterID : null;
    try {
      await createProject(activityIDs, { parentProjectID, separateItems: event.metaKey, createActivityRules: event.altKey });
      setDropMessage(`${event.metaKey ? activityIDs.length : 1} project${event.metaKey && activityIDs.length !== 1 ? "s" : ""} created.`);
    } catch (error) {
      setDropMessage(error.message || "Could not create a project from this activity.");
    }
  };
  const handleProjectDrop = async (event, project) => {
    event.preventDefault();
    setDropProjectID(null);
    if (!onDropActivity) return;
    try {
      const result = await onDropActivity(event, project);
      setDropMessage(result?.message || "Activity updated.");
    } catch (error) {
      setDropMessage(error.message || "Could not update the project activity.");
    }
  };
  const projectTree = (parentID = "", depth = 0) => projects.filter((project) => projectParentID(project) === parentID).sort((left, right) => String(left.title || "").localeCompare(String(right.title || ""))).map((project) => {
    const id = resourceID(project.id);
    const children = projects.some((candidate) => projectParentID(candidate) === id);
    const collapsed = collapsedProjectIDs.has(id);
    const projectActivities = projectActivitiesFor(project);
    return <div className="activity-project-tree-node" key={id}><div className={`activity-project-tree-row ${dropProjectID === id ? "drop-target" : ""}`} onDragOver={(event) => { event.preventDefault(); setDropProjectID(id); }} onDragLeave={() => setDropProjectID(null)} onDrop={(event) => handleProjectDrop(event, project)}>{children ? <button type="button" className="activity-project-disclosure" aria-label={`${collapsed ? "Expand" : "Collapse"} ${project.title}`} onClick={() => setCollapsedProjectIDs((current) => { const next = new Set(current); if (next.has(id)) next.delete(id); else next.add(id); return next; })}><CaretDown size={13} className={collapsed ? "collapsed" : ""} /></button> : <span className="activity-project-disclosure-placeholder" />}{sidebarButton(projectFilterID === id, () => selectProject(project), <FolderSimple size={16} />, project.title, `${projectActivities.length} · ${formatDurationSeconds(secondsFor(projectActivities))}`, { paddingLeft: `${7 + depth * 12}px` }, () => editProject(project))}</div>{children && !collapsed ? projectTree(id, depth + 1) : null}</div>;
  });
  return <aside className="activity-project-sidebar" aria-label="Activity projects and filters"><div className="activity-project-sidebar-heading"><h2>Projects</h2><span>{formatDurationSeconds(secondsFor(activeActivities))}</span><button type="button" className="activity-project-new" aria-label="New project" title="New project" onClick={openProjectComposer}><Plus size={15} /></button></div><div className="activity-project-filter-list">{sidebarButton(projectFilterID === "all" && savedFilterID === "all", () => onProjectFilter("all"), <Waveform size={16} />, "All Activities", `${activeActivities.length} segments`)}{sidebarButton(projectFilterID === "unassigned", () => onProjectFilter("unassigned"), <TrayIcon />, "Unassigned", `${activeActivities.filter((activity) => !activity.projectID).length} segments`)}{projects.length > 0 ? <div className="activity-project-sidebar-label">My Projects</div> : null}{projectTree()}<div className={`activity-project-drop-zone ${dropTarget ? "active" : ""}`} onClick={openProjectComposer} onKeyDown={handleProjectDropZoneKeyDown} onDragOver={(event) => { event.preventDefault(); setDropTarget(true); }} onDragLeave={() => setDropTarget(false)} onDrop={handleCreateProjectDrop} role="button" tabIndex={0} aria-label="Create project from activity"><FolderSimple size={17} /><span><strong>{dropTarget ? "Release to create project" : "Create from activity"}</strong><small>{dropMessage || "Click to create a project · drop an App / Category row · ⌘ splits · ⌥ adds rules"}</small></span></div></div><div className="activity-project-sidebar-divider" /><div className="activity-project-sidebar-heading"><h2>Filters</h2><span>{filters.length}</span><button type="button" className="activity-project-new" aria-label="New filter" title="New filter" onClick={() => { const panel = document.getElementById("web-activity-filters-panel"); panel?.scrollIntoView({ behavior: "smooth", block: "center" }); window.setTimeout(() => panel?.querySelector('input[aria-label="Activity filter name"]')?.focus(), 250); }}><Plus size={15} /></button></div><div className="activity-project-filter-list">{sidebarButton(savedFilterID === "all" && projectFilterID === "all", () => onSavedFilter("all"), <SlidersHorizontal size={16} />, "All activity", "No saved filter")}{filters.map((filter) => sidebarButton(savedFilterID === resourceID(filter.id), () => onSavedFilter(resourceID(filter.id)), <Waveform size={16} />, filter.name, `${(filter.rules || []).length} rule${(filter.rules || []).length === 1 ? "" : "s"}`, {}, () => editSavedFilter(filter)))}</div><p className="activity-project-sidebar-hint">Drag an App / Category row onto a project; hold ⌥ to create a future rule.</p></aside>;
}

function TrayIcon() {
  return <span className="tray-icon" aria-hidden="true" />;
}

function WebEntryOMaticDialog({ open, activities, entries, projects, dateKey, wrapAtMinute = 0, onClose, onCreate }) {
  const [projectID, setProjectID] = useState("");
  const [minimumDurationMinutes, setMinimumDurationMinutes] = useState(5);
  const [maximumGapSeconds, setMaximumGapSeconds] = useState(60);
  const [overwriteExisting, setOverwriteExisting] = useState(false);
  const [title, setTitle] = useState("Work session");
  const [notes, setNotes] = useState("");
  const [billingStatus, setBillingStatus] = useState("billable");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const effectiveWrapAtMinute = Math.max(0, Math.min(1439, Number(wrapAtMinute || activities?.[0]?._wrapAtMinute || 0)));
  const scopedActivities = projectID ? activities.filter((activity) => resourceID(activity.projectID) === projectID) : activities;
  const previewIntervals = useMemo(() => entryOMaticIntervals(scopedActivities, entries, dateKey, { minimumDurationMinutes, maximumGapSeconds, overwriteExisting, wrapAtMinute: effectiveWrapAtMinute }), [dateKey, effectiveWrapAtMinute, entries, maximumGapSeconds, minimumDurationMinutes, overwriteExisting, scopedActivities]);
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
  useEffect(() => {
    if (!open) return undefined;
    const handleKeyDown = (event) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose, open]);
  const updateProject = (value) => {
    setProjectID(value);
    const project = projects.find((item) => resourceID(item.id) === value);
    if (project) {
      setTitle(project.title || "Work session");
      setBillingStatus(resolvedProjectBillingStatus(projects, project.id));
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
  return <div className="entry-omatic-backdrop" role="presentation" onClick={onClose}><section className="entry-omatic-dialog" role="dialog" aria-modal="true" aria-labelledby="entry-omatic-title" onClick={(event) => event.stopPropagation()}><header><div><span>Activity conversion</span><h2 id="entry-omatic-title">Create Time Entries</h2><p>Turn visible App / Category usage into reviewable time entries for {dateKey}.</p></div><IconButton label="Close Entry-O-Matic" onClick={onClose}><X size={17} /></IconButton></header><div className="entry-omatic-form"><label>Project<select value={projectID} onChange={(event) => updateProject(event.target.value)}><option value="">All visible activity</option>{projects.map((project) => <option value={resourceID(project.id)} key={project.id}>{project.title}</option>)}</select></label><div className="entry-omatic-options"><label>Minimum duration<select value={minimumDurationMinutes} onChange={(event) => setMinimumDurationMinutes(Number(event.target.value))}>{[1, 5, 10, 15].map((minutes) => <option value={minutes} key={minutes}>At least {minutes}m</option>)}</select></label><label>Maximum gap<select value={maximumGapSeconds} onChange={(event) => setMaximumGapSeconds(Number(event.target.value))}>{[0, 5, 30, 60, 300].map((seconds) => <option value={seconds} key={seconds}>{seconds === 0 ? "No gap" : `Gap ≤ ${seconds}s`}</option>)}</select></label></div><label className="entry-omatic-check"><input type="checkbox" checked={overwriteExisting} onChange={(event) => setOverwriteExisting(event.target.checked)} />Replace overlapping time entries</label><small className="entry-omatic-help">Without replacement, existing time is subtracted from the generated intervals.</small><label>Time entry title<input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Work session" /></label><label>Billing status<select value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)}><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option><option value="undetermined">Undetermined</option></select></label><label>Notes (optional)<textarea value={notes} onChange={(event) => setNotes(event.target.value)} rows={2} /></label></div><div className="entry-omatic-preview"><div><strong><Sparkle size={16} /> Preview</strong><span>{previewIntervals.length ? `${previewIntervals.length} entries · ${formatDurationSeconds(previewDuration)}` : "No intervals meet the current minimum duration and coverage settings."}</span></div>{previewIntervals.length ? <p>{previewIntervals.map((interval) => formatRange(Math.floor(interval.startSecond / 60), Math.ceil(interval.endSecond / 60))).join(" · ")}</p> : null}</div>{message ? <p className="entry-message" role="status">{message}</p> : null}<footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="button" className="primary-button" onClick={submit} disabled={busy || previewIntervals.length === 0 || !title.trim()}>{busy ? "Creating…" : `Create ${previewIntervals.length} Time Entries`}</button></footer></section></div>;
}

function WebTimeEntryDialog({ mode, open, api, projects, recentEntries, dateKey, initialEntry = null, onClose }) {
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
  const [overlapEntries, setOverlapEntries] = useState([]);
  useEffect(() => {
    if (!open) return;
    setTitle(timerMode ? "Focused work" : initialEntry?.title || "");
    setStart(timerMode ? "09:00" : initialEntry?.start ? entryClock(initialEntry.start) : "09:00");
    setEnd(timerMode ? "10:00" : initialEntry?.end ? entryClock(initialEntry.end) : "10:00");
    setProjectID(timerMode ? "" : resourceID(initialEntry?.projectID || initialEntry?.project) || "");
    setNotes(timerMode ? "" : initialEntry?.notes || "");
    setBillingStatus(timerMode ? "billable" : initialEntry?.billingStatus || "billable");
    setEstimatedMinutes("");
    setBusy(false);
    setMessage("");
    setOverlapEntries([]);
  }, [dateKey, initialEntry, open, timerMode]);
  useEffect(() => {
    if (!open) return undefined;
    const handleKeyDown = (event) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose, open]);
  const selectRecent = (entry) => {
    setTitle(entry.title || "");
    setProjectID(resourceID(entry.project) || "");
    setNotes(entry.notes || "");
    setBillingStatus(normalizedBillingStatus(entry.billing_status));
  };
  const updateProject = (value) => {
    setProjectID(value);
    const project = projects.find((item) => resourceID(item.id) === value);
    if (project) setBillingStatus(resolvedProjectBillingStatus(projects, project.id));
  };
  const submit = async (overlapDecision = null) => {
    if (busy || !title.trim() || !api.connected) return;
    const startDate = localEntryDate(dateKey, start);
    const endDate = localEntryDate(dateKey, end);
    if (!timerMode && (!startDate || !endDate || new Date(endDate) <= new Date(startDate))) {
      setMessage("Enter a valid time range.");
      return;
    }
    if (!timerMode && overlapDecision === null && overlapEntries.length === 0) {
      const startSecond = Number(start.slice(0, 2)) * 3_600 + Number(start.slice(3, 5)) * 60;
      const endSecond = Number(end.slice(0, 2)) * 3_600 + Number(end.slice(3, 5)) * 60;
      const overlaps = api.entries.filter((entry) => {
        const range = entrySecondsForDate(entry, dateKey);
        return range && range.startSecond < endSecond && range.endSecond > startSecond;
      });
      if (overlaps.length > 0) {
        setOverlapEntries(overlaps);
        setMessage(`This range overlaps ${overlaps.length} existing time ${overlaps.length === 1 ? "entry" : "entries"}.`);
        return;
      }
    }
    setBusy(true);
    setMessage("");
    try {
      if (timerMode) {
        await api.startTimer(title.trim(), projectID ? resourceID(projectID) : undefined, { notes, billingStatus, estimatedMinutes: estimatedMinutes ? Number(estimatedMinutes) : undefined });
      } else {
        await api.addTimeEntry({ title: title.trim(), projectID: projectID ? resourceID(projectID) : undefined, notes, billingStatus, start: startDate, end: endDate, replace_overlapping: overlapDecision === "replace" });
      }
      setOverlapEntries([]);
      onClose();
    } catch (error) {
      setMessage(error.message || `Could not ${timerMode ? "start the timer" : "save the time entry"}.`);
    } finally {
      setBusy(false);
    }
  };
  if (!open) return null;
  const recent = recentEntries.filter((entry) => !entry.is_running).slice(-5).reverse();
  return <div className="entry-omatic-backdrop" role="presentation" onClick={onClose}><section className="entry-omatic-dialog time-entry-dialog" role="dialog" aria-modal="true" aria-labelledby="time-entry-dialog-title" onClick={(event) => event.stopPropagation()}><header><div><span>{timerMode ? "Focus session" : "Manual time"}</span><h2 id="time-entry-dialog-title">{timerMode ? "Start Timer" : "New Time Entry"}</h2><p>{timerMode ? "The timer will capture activity until you stop it." : `Record a time entry for ${dateKey}.`}</p></div><IconButton label="Close time entry dialog" onClick={onClose}><X size={17} /></IconButton></header><div className="entry-omatic-form">{timerMode && recent.length > 0 ? <div className="time-entry-recent"><strong>Recent timers</strong>{recent.map((entry) => <button type="button" key={entry.id} onClick={() => selectRecent(entry)}><Clock size={14} /><span><b>{entry.title || "Untitled"}</b><small>{projectTitleFor(projects, entry.project)}</small></span></button>)}</div> : null}<label>{timerMode ? "What are you working on?" : "Time entry title"}<input aria-label={timerMode ? "Time entry title" : "Time entry title"} value={title} onChange={(event) => setTitle(event.target.value)} placeholder={timerMode ? "Focused work" : "What did you work on?"} /></label>{!timerMode ? <div className="entry-omatic-options"><label>From<input aria-label="From" type="time" value={start} onChange={(event) => { setStart(event.target.value); setOverlapEntries([]); }} /></label><label>To<input aria-label="To" type="time" value={end} onChange={(event) => { setEnd(event.target.value); setOverlapEntries([]); }} /></label></div> : null}<label>Project<select aria-label="Project" value={projectID} onChange={(event) => updateProject(event.target.value)}><option value="">Unassigned</option>{projects.map((project) => <option value={resourceID(project.id)} key={project.id}>{project.title}</option>)}</select></label><label>Billing status<select aria-label="Billing status" value={billingStatus} onChange={(event) => setBillingStatus(event.target.value)}><option value="billable">Billable</option><option value="not_billable">Not billable</option><option value="pending">Pending</option><option value="billed">Billed</option><option value="paid">Paid</option><option value="undetermined">Undetermined</option></select></label>{timerMode ? <label>Estimated duration<select aria-label="Estimated duration" value={estimatedMinutes} onChange={(event) => setEstimatedMinutes(event.target.value)}><option value="">No estimate</option>{[15, 30, 45, 60, 90, 120, 180, 240].map((minutes) => <option value={minutes} key={minutes}>{minutes >= 60 ? `${Math.floor(minutes / 60)}h${minutes % 60 ? ` ${minutes % 60}m` : ""}` : `${minutes}m`}</option>)}</select></label> : null}<label>Notes (optional)<textarea aria-label="Notes (optional)" value={notes} onChange={(event) => setNotes(event.target.value)} rows={2} /></label></div>{overlapEntries.length > 0 ? <div className="time-entry-overlap-callout" role="alert"><strong>Overlapping Time Entry</strong><p>This range overlaps {overlapEntries.length} existing time {overlapEntries.length === 1 ? "entry" : "entries"}. Replace them or keep parallel entries?</p><div><button type="button" className="secondary-button" onClick={() => { setOverlapEntries([]); setMessage(""); }}>Cancel</button><button type="button" className="secondary-button" onClick={() => submit("keep")} disabled={busy}>Keep Both</button><button type="button" className="secondary-button danger-pill" onClick={() => submit("replace")} disabled={busy}>Replace Existing</button></div></div> : null}{message ? <p className="entry-message" role="status">{message}</p> : null}<footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="button" className="primary-button" onClick={submit} disabled={busy || !api.connected || !title.trim() || overlapEntries.length > 0}>{busy ? "Saving…" : timerMode ? "Start Timer" : "Save Time Entry"}</button></footer></section></div>;
}

function WebTimeEntryEditDialog({ entry, api, projects, dateKey, onClose }) {
  useEffect(() => {
    const handleKeyDown = (event) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);
  if (!entry) return null;
  return <div className="entry-omatic-backdrop" role="presentation" onClick={onClose}><section className="entry-omatic-dialog time-entry-dialog" role="dialog" aria-modal="true" aria-labelledby="edit-time-entry-dialog-title" onClick={(event) => event.stopPropagation()}><header><div><span>Manual time</span><h2 id="edit-time-entry-dialog-title">Edit Time Entry</h2><p>Update the title, range, project, or billing category for this entry.</p></div><IconButton label="Close edit time entry dialog" onClick={onClose}><X size={17} /></IconButton></header><TimeEntryEditRow entry={entry} api={api} dateKey={dateKey} projects={projects} onCancel={onClose} dialog /></section></div>;
}

function ActivitiesPage({ api, dateKey, setDateKey, projectScopeID, setProjectScopeID }) {
  const [query, setQuery] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [deviceFilter, setDeviceFilter] = useState("all");
  const projectFilterID = projectScopeID;
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
  const [entryOMaticUndo, setEntryOMaticUndo] = useState(null);
  const [timeEntryDialogMode, setTimeEntryDialogMode] = useState(null);
  const [timeEntryPrefill, setTimeEntryPrefill] = useState(null);
  const [selectedTimeEntry, setSelectedTimeEntry] = useState(null);
  const [timelineSelection, setTimelineSelection] = useState(null);
  const [editProjectID, setEditProjectID] = useState(null);
  const timerRunning = Boolean(api.status?.timer);
  const wrapAtMinute = Math.max(0, Math.min(1439, Number(api.preferences?.wrap_days_at_minute ?? 0)));
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
  const activityTimeRange = api.activityPreferences?.activity_time_range || "selectedDay";
  const activityBounds = activityRangeBounds(dateKey, activityTimeRange);
  const [activityRangeData, setActivityRangeData] = useState(null);
  const [activityRangeLoading, setActivityRangeLoading] = useState(false);
  useEffect(() => {
    let current = true;
    if (!api.connected || activityTimeRange === "selectedDay" || activityTimeRange === "lastSevenDays") {
      setActivityRangeData(null);
      setActivityRangeLoading(false);
      return () => { current = false; };
    }
    setActivityRangeData(null);
    setActivityRangeLoading(true);
    api.fetchRange(activityBounds.start, activityBounds.end)
      .then((result) => { if (current) setActivityRangeData(result); })
      .catch(() => {
        if (current) setActivityRangeData({ activities: [], entries: [], startDate: activityBounds.start, endDate: activityBounds.end });
      })
      .finally(() => { if (current) setActivityRangeLoading(false); });
    return () => { current = false; };
  }, [activityBounds.end, activityBounds.start, activityTimeRange, api.connected, api.fetchRange, api.refreshVersion]);
  const currentActivities = [...api.activities].sort((left, right) => Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const useSevenDayRange = activityTimeRange === "lastSevenDays";
  const rangeActivities = activityRangeData
    ? activityRangeData.activities
    : useSevenDayRange && api.weekly.length > 0
    ? api.weekly.flatMap((day) => (day.activities || []).map((activity) => ({ ...activity, date: day.date })))
    : currentActivities;
  const allActivities = [...rangeActivities].sort((left, right) => String(left.date || dateKey).localeCompare(String(right.date || dateKey)) || Number(left.startSecond || 0) - Number(right.startSecond || 0));
  const devices = [...new Set([...currentActivities, ...rangeActivities].map((activity) => activity.deviceName || "This Mac"))].sort();
  const normalizedQuery = query.trim().toLowerCase();
  const builtinFilterKey = categoryFilter.startsWith("builtin:") ? categoryFilter.slice("builtin:".length) : "all";
  const savedFilter = api.filters.find((filter) => resourceID(filter.id) === savedFilterID);
  const includeSubprojects = api.preferences?.include_subprojects_when_selecting_project !== false;
  const scopedProjectIDs = projectFilterID !== "all" && projectFilterID !== "unassigned"
    ? includeSubprojects ? descendantProjectIDs(api.projects, projectFilterID) : new Set([resourceID(projectFilterID)])
    : null;
  const filterActivity = (activity) => {
    const category = activityCategory(activity);
    const searchable = `${activityLabel(activity)} ${activityContext(activity)} ${activity.appName || ""} ${activity.deviceName || ""} ${category.label}`.toLowerCase();
    return (!normalizedQuery || searchable.includes(normalizedQuery))
      && (builtinFilterKey !== "all" ? activityMatchesBuiltinFilter(activity, builtinFilterKey) : categoryFilter === "all" || category.key === categoryFilter)
      && (deviceFilter === "all" || (activity.deviceName || "This Mac") === deviceFilter)
      && (projectFilterID === "all" || (projectFilterID === "unassigned" ? !activity.projectID : scopedProjectIDs.has(resourceID(activity.projectID))))
      && (!savedFilter || activityMatchesFilter(activity, savedFilter));
  };
  const activityMatchesTimelineSelection = (activity) => {
    if (!timelineSelection) return true;
    if (String(activity.date || dateKey) !== dateKey) return false;
    const startSecond = Math.max(0, Number(activity.startSecond || 0));
    const endSecond = Math.max(startSecond, Number(activity.endSecond || 0));
    return startSecond < timelineSelection.end * 60 && endSecond > timelineSelection.start * 60;
  };
  const recordedActivities = allActivities.filter((activity) => includeIdle || activityCategory(activity).key !== "idle");
  const activities = recordedActivities.filter(filterActivity).filter(activityMatchesTimelineSelection);
  const timelineActivities = currentActivities
    .filter((activity) => (includeIdle || activityCategory(activity).key !== "idle") && filterActivity(activity))
    .map((activity) => ({ ...activity, _wrapAtMinute: wrapAtMinute }));
  const hasFilters = Boolean(normalizedQuery || categoryFilter !== "all" || deviceFilter !== "all" || projectFilterID !== "all" || savedFilterID !== "all" || timelineSelection);
  const resetFilters = () => {
    setQuery("");
    setCategoryFilter("all");
    setDeviceFilter("all");
    setProjectScopeID("all");
    setSavedFilterID("all");
    setTimelineSelection(null);
  };
  const handleActivityProjectDrop = (event, project) => assignActivitiesFromDrop({
    event,
    activities: allActivities,
    project,
    api,
    onAssignActivity: (id, projectID, activityDate) => api.assignActivity(id, projectID, activityDate || dateKey),
  });
  const selectProjectFilter = (value) => {
    setProjectScopeID(value);
    setSavedFilterID("all");
    setCategoryFilter("all");
  };
  const selectSavedFilter = (value) => {
    setSavedFilterID(value);
    setProjectScopeID("all");
    setCategoryFilter("all");
  };
  const createProjectFromActivities = async (activityIDs, options = {}) => {
    if (!api.connected) throw new Error("Connect Metriday before creating a project.");
    const sourceActivities = activityIDs
      .map((id) => allActivities.find((activity) => resourceID(activity.id) === resourceID(id)))
      .filter(Boolean);
    if (!sourceActivities.length) throw new Error("Drop a visible App / Category activity row here.");
    const parentID = api.projects.some((project) => resourceID(project.id) === resourceID(options.parentProjectID))
      ? resourceID(options.parentProjectID)
      : null;
    const nameFor = (activity) => {
      try {
        const host = new URL(activity.resource || "").host;
        if (host) return host;
      } catch {
        // Fall through to the captured application name.
      }
      return activity.appName || activity.deviceName || "New Project";
    };
    const createOne = async (items) => {
      const project = await api.createProject({ title: nameFor(items[0]), parent: parentID });
      const projectID = resourceID(project?.id || project?.project_id);
      if (!projectID) throw new Error("The native app did not return the new project ID.");
      for (const activity of items) {
        await api.assignActivity(activity.id, projectID, activity.date || dateKey);
        if (options.createActivityRules) {
          const rule = activityProjectRule(activity);
          if (rule) await api.createProjectRule({ ...rule, project_id: projectID });
        }
      }
    };
    if (options.separateItems) {
      for (const activity of sourceActivities) await createOne([activity]);
    } else {
      await createOne(sourceActivities);
    }
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
      void saveDisplayPreferences({ group_by_project: value });
      return;
    }
    setGroupByDevice(value);
    void saveDisplayPreferences({ group_by_device: value });
  };
  const toggleTimer = async () => {
    if (timerBusy || !api.connected) return;
    setTimerBusy(true);
    setTimerMessage("");
    try {
      if (timerRunning) await api.stopTimer();
      else { setTimeEntryPrefill(null); setTimeEntryDialogMode("timer"); }
    } catch (error) {
      setTimerMessage(error.message || "Could not update the timer.");
    } finally {
      setTimerBusy(false);
    }
  };
  const openNewTimeEntry = (prefill = null) => {
    setTimeEntryPrefill(prefill);
    setTimeEntryDialogMode("new");
  };
  useEffect(() => {
    const handleOpenNewTimeEntry = () => openNewTimeEntry();
    const handleOpenEntryOMatic = () => setEntryOMaticOpen(true);
    window.addEventListener("metriday:open-new-time-entry", handleOpenNewTimeEntry);
    window.addEventListener("metriday:open-entry-omatic", handleOpenEntryOMatic);
    return () => {
      window.removeEventListener("metriday:open-new-time-entry", handleOpenNewTimeEntry);
      window.removeEventListener("metriday:open-entry-omatic", handleOpenEntryOMatic);
    };
  }, []);
  const openSourceTimeEntry = (source) => {
    if (source?.completed_at) {
      const completed = new Date(source.completed_at);
      if (Number.isNaN(completed.getTime())) return;
      const start = new Date(completed.getTime() - 30 * 60 * 1000).toISOString();
      openNewTimeEntry({
        title: source.title || "Completed reminder",
        notes: [source.list, source.notes].filter(Boolean).join(" · "),
        start,
        end: completed.toISOString(),
        billingStatus: "billable",
      });
      return;
    }
    if (!source?.start || !source?.end) return;
    const isPhoneCall = Boolean(source.address || source.service_provider);
    const title = isPhoneCall
      ? source.address ? "Call · " + source.address : "Phone call"
      : source.title || "Calendar event";
    openNewTimeEntry({
      title,
      notes: isPhoneCall
        ? [source.service_provider, source.address].filter(Boolean).join(" · ")
        : [source.calendar, source.location, source.notes].filter(Boolean).join(" · "),
      start: source.start,
      end: source.end,
      billingStatus: "billable",
    });
  };
  const openActivityTimeEntry = (activity) => {
    const activityDateKey = activity?.date || dateKey;
    const start = localEntryDateSeconds(activityDateKey, activity?.startSecond, wrapAtMinute);
    const end = localEntryDateSeconds(activityDateKey, activity?.endSecond, wrapAtMinute);
    if (!start || !end || new Date(end) <= new Date(start)) return;
    openNewTimeEntry({
      title: activityLabel(activity),
      start,
      end,
      projectID: activity.projectID || "",
      billingStatus: "billable",
    });
  };
  const openSelectedRangeTimeEntry = (selection) => {
    if (!selection || selection.end <= selection.start) return;
    const start = localEntryDateSeconds(dateKey, selection.start * 60, wrapAtMinute);
    const end = localEntryDateSeconds(dateKey, selection.end * 60, wrapAtMinute);
    if (!start || !end || new Date(end) <= new Date(start)) return;
    const selectedProject = projectFilterID !== "all" && projectFilterID !== "unassigned"
      && api.projects.some((project) => resourceID(project.id) === resourceID(projectFilterID))
      ? resourceID(projectFilterID)
      : "";
    openNewTimeEntry({ start, end, projectID: selectedProject, billingStatus: "billable" });
  };
  const createGeneratedEntries = async (intervals, configuration) => {
    const replacedEntries = configuration.overwriteExisting
      ? api.entries.filter((entry) => {
        const existing = entrySecondsForDate(entry, dateKey, wrapAtMinute);
        return existing && intervals.some((interval) => existing.startSecond < interval.endSecond && existing.endSecond > interval.startSecond);
      })
      : [];
    const generatedRanges = intervals.map((interval) => ({
      start: localEntryDateSeconds(dateKey, interval.startSecond, wrapAtMinute),
      end: localEntryDateSeconds(dateKey, interval.endSecond, wrapAtMinute),
    }));
    const { createdEntries, splitFragments } = await api.createTimeEntries(generatedRanges.map((range) => ({
      title: configuration.title,
      notes: configuration.notes,
      projectID: configuration.projectID ? resourceID(configuration.projectID) : undefined,
      billingStatus: configuration.billingStatus,
      start: range.start,
      end: range.end,
      replace_overlapping: configuration.overwriteExisting,
    })));
    if (createdEntries.length > 0) {
      setEntryOMaticUndo({ createdEntries, replacedEntries, splitFragments });
      setDisplayMessage(`Created ${createdEntries.length} Entry-O-Matic time ${createdEntries.length === 1 ? "entry" : "entries"} · Undo available (⌘Z)`);
    }
  };
  const undoEntryOMatic = async () => {
    if (!entryOMaticUndo) return;
    try {
      const createdIDs = entryOMaticUndo.createdEntries.map(entryID).filter(Boolean);
      if (createdIDs.length > 0) await api.deleteTimeEntries(createdIDs);
      const splitFragmentIDs = [...new Set((entryOMaticUndo.splitFragments || []).map(entryID).filter(Boolean))];
      if (splitFragmentIDs.length > 0) await api.deleteTimeEntries(splitFragmentIDs);
      if (entryOMaticUndo.replacedEntries.length > 0) await api.restoreTimeEntries(entryOMaticUndo.replacedEntries);
      setEntryOMaticUndo(null);
      setDisplayMessage("Entry-O-Matic changes undone.");
    } catch (error) {
      setDisplayMessage(error.message || "Could not undo Entry-O-Matic changes.");
    }
  };
  useEffect(() => {
    const handleUndo = (event) => {
      if (!entryOMaticUndo || !event.metaKey || event.altKey || event.shiftKey || event.key.toLowerCase() !== "z") return;
      const target = event.target;
      if (target instanceof HTMLElement && ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return;
      event.preventDefault();
      void undoEntryOMatic();
    };
    window.addEventListener("keydown", handleUndo);
    return () => window.removeEventListener("keydown", handleUndo);
  }, [entryOMaticUndo]);
  useEffect(() => { setSelectedActivity(null); setSelectedTimeEntry(null); setTimelineSelection(null); }, [dateKey]);
  const activityHeading = dateKey === localDateKey() ? "Today’s activity" : `${planDateLabel(dateKey)} activity`;
  const activityRangeDescription = activityRangeLoading
    ? `Loading ${activityTimeRangeLabel(activityTimeRange).toLowerCase()}…`
    : `${activityTimeRangeLabel(activityTimeRange)} history`;
  return <main className="page supporting-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? `Native activity stream · ${planDateLabel(dateKey)}` : "Local preview"}</span><h1>Activities</h1></div><div className="activities-page-actions"><DateControls dateKey={dateKey} onChange={setDateKey} label="Choose Activities date" /><button type="button" className="quiet-pill" onClick={() => openNewTimeEntry()} disabled={!api.connected}><Plus size={16} />New time entry</button><button type="button" className={`status-pill activities-timer ${timerRunning ? "active" : ""}`} onClick={toggleTimer} disabled={timerBusy || !api.connected}><Timer size={16} weight={timerRunning ? "fill" : "regular"} />{timerBusy ? "Updating…" : timerRunning ? "Stop timer" : "Start timer"}</button><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : "Refresh"}</button></div></header><div className="activities-page-toolbar"><div className="activity-view-switcher" role="group" aria-label="Activity view"><button type="button" className={activityView === "unified" ? "active" : ""} onClick={() => setViewMode("unified")}>Unified</button><button type="button" className={activityView === "category" ? "active" : ""} onClick={() => setViewMode("category")}>By Category</button><button type="button" className={activityView === "chronological" ? "active" : ""} onClick={() => setViewMode("chronological")}>Chronological</button></div><label className="activity-display-toggle"><input type="checkbox" checked={includeIdle} onChange={(event) => setIdleVisibility(event.target.checked)} />Show Idle</label><label className="activity-display-toggle"><input type="checkbox" checked={groupByProject} disabled={activityView === "category"} onChange={(event) => setGrouping("project", event.target.checked)} />Group by project</label><label className="activity-display-toggle"><input type="checkbox" checked={groupByDevice} disabled={activityView === "category"} onChange={(event) => setGrouping("device", event.target.checked)} />Group by device</label><WebActivityDisplayMenu open={displayMenuOpen} onToggle={() => setDisplayMenuOpen((value) => !value)} preferences={api.activityPreferences} devices={devices} onChange={updateDisplayPreference} /><label className="activity-search"><Waveform size={18} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search app, website, window title…" aria-label="Search activities" />{query ? <IconButton label="Clear activity search" onClick={() => setQuery("")}><X size={15} /></IconButton> : null}</label><WebActivityFiltersMenu open={filtersMenuOpen} filters={api.filters} projectFilterID={projectFilterID} savedFilterID={savedFilterID} categoryFilter={categoryFilter} onToggle={() => { setFiltersMenuOpen((value) => !value); setDevicesMenuOpen(false); }} onProjectFilter={(value) => { selectProjectFilter(value); setFiltersMenuOpen(false); }} onSavedFilter={(value) => { selectSavedFilter(value); setFiltersMenuOpen(false); }} onCategoryFilter={(value) => { setCategoryFilter(value); setFiltersMenuOpen(false); }} /><WebActivityDevicesMenu open={devicesMenuOpen} devices={devices} selectedDevice={deviceFilter} hideDevicesWithoutTime={hideDevicesWithoutTime} onToggle={() => { setDevicesMenuOpen((value) => !value); setFiltersMenuOpen(false); }} onSelect={setDeviceSelection} onToggleHide={setHideDevicesWithoutTime} /><button type="button" className="quiet-pill activity-reset" onClick={resetFilters} disabled={!hasFilters}>Reset</button></div>{timerMessage ? <p className="entry-message activities-timer-message" role="status">{timerMessage}</p> : null}{displayMessage ? <p className="entry-message activities-display-message" role="status">{displayMessage}</p> : null}<div className="activities-workspace"><WebActivityProjectSidebar projects={api.projects} filters={api.filters} activities={allActivities} projectFilterID={projectFilterID} savedFilterID={savedFilterID} onProjectFilter={selectProjectFilter} onSavedFilter={selectSavedFilter} onEditProject={setEditProjectID} onCreateProjectFromActivities={createProjectFromActivities} onDropActivity={handleActivityProjectDrop} /><div className="activities-workspace-main"><WebActivityTimeline activities={timelineActivities} dateKey={dateKey} api={api} onSelect={setSelectedActivity} onCreateTimeEntry={openActivityTimeEntry} onCreateSelection={openSelectedRangeTimeEntry} selection={timelineSelection} onSelectionChange={setTimelineSelection} onEditTimeEntry={setSelectedTimeEntry} onRecordCalendarEvent={openSourceTimeEntry} /><WebCalendarEventsPanel api={api} onRecord={openSourceTimeEntry} /><WebRemindersPanel api={api} onRecord={openSourceTimeEntry} /><WebPhoneCallsPanel api={api} onRecord={openSourceTimeEntry} /><WebScreenTimePanel api={api} /><WebActivityFiltersPanel api={api} /><WebActivityExclusionsPanel api={api} /><WebActivityCategoriesPanel api={api} /><section className="activities-list"><div className="activities-list-heading"><div><h2>{activityHeading}</h2><p>{api.connected ? hasFilters ? `${activities.length} of ${allActivities.length} locally recorded segments · ${activityRangeDescription}` : `${activities.length} locally recorded segments · ${activityRangeDescription}` : "Start Metriday to see app, browser, and Screen Time activity here."}</p></div><div className="activities-list-heading-actions"><button type="button" className="quiet-pill" onClick={() => setEntryOMaticOpen(true)} disabled={!api.connected || timelineActivities.length === 0}><Sparkle size={16} />Create time entries</button><span className={`api-badge ${api.connected ? "online" : "offline"}`}>{api.connected ? "Connected" : "Offline"}</span></div></div>{activities.length === 0 ? <div className="activities-empty"><Waveform size={34} /><strong>{api.connected ? allActivities.length > 0 ? "No activity matches these filters" : "No activity recorded yet" : "Waiting for the native Metriday app"}</strong><span>{api.error || (hasFilters ? "Clear the filters to see all local activity." : "The hosted view keeps working with preview data until the loopback API is available.")}</span></div> : <ActivityTable activities={activities} viewMode={activityView} groupMode={activityView === "chronological" ? (groupByProject ? "project" : groupByDevice ? "device" : "none") : "none"} projects={api.projects} displayPreferences={api.activityPreferences} dateKey={dateKey} onSelect={setSelectedActivity} api={api} onCreateTimeEntry={openActivityTimeEntry} />}</section><ProjectPanel api={api} activities={allActivities} onDropActivity={handleActivityProjectDrop} editProjectID={editProjectID} onProjectEditHandled={() => setEditProjectID(null)} onAssignActivity={(id, projectID, activityDate) => api.assignActivity(id, projectID, activityDate || dateKey)} />{api.activityPreferences?.include_time_entries === false ? <TimeEntriesPanel api={api} dateKey={dateKey} /> : null}</div></div>{selectedActivity ? <ActivityDetailDialog activity={selectedActivity} api={api} dateKey={dateKey} displayPreferences={api.activityPreferences} onClose={() => setSelectedActivity(null)} /> : null}<WebEntryOMaticDialog open={entryOMaticOpen} activities={timelineActivities} entries={api.entries} projects={api.projects} dateKey={dateKey} onClose={() => setEntryOMaticOpen(false)} onCreate={createGeneratedEntries} /><WebTimeEntryDialog mode={timeEntryDialogMode} open={Boolean(timeEntryDialogMode)} api={api} projects={api.projects} recentEntries={api.entries} dateKey={dateKey} initialEntry={timeEntryPrefill} onClose={() => { setTimeEntryDialogMode(null); setTimeEntryPrefill(null); }} /><WebTimeEntryEditDialog entry={selectedTimeEntry} api={api} projects={api.projects} dateKey={dateKey} onClose={() => setSelectedTimeEntry(null)} /></main>;
}

function StatsDonut({ rows, total, label, centerLabel = null, centerCaption = null }) {
  const visibleRows = rows.filter((row) => Number(row.seconds || 0) > 0);
  const totalSeconds = Math.max(1, Number(total || visibleRows.reduce((sum, row) => sum + Number(row.seconds || 0), 0)));
  let offset = 0;
  const stops = visibleRows.map((row) => {
    const start = (offset / totalSeconds) * 100;
    offset += Number(row.seconds || 0);
    const end = (offset / totalSeconds) * 100;
    return `${row.color} ${start}% ${Math.max(start + 0.35, end)}%`;
  });
  return <div className="stats-donut" role="img" aria-label={label} style={{ background: stops.length ? `conic-gradient(${stops.join(",")})` : "#eff0f3" }}><span>{centerLabel !== null ? <><strong>{centerLabel}</strong>{centerCaption ? <small>{centerCaption}</small> : null}</> : formatDurationSeconds(total)}</span></div>;
}

function StatsProjectScope({ projects, segments, entries, selectedID, onChange }) {
  const secondsForActivity = (activity) => Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
  const activeSegments = segments.filter((activity) => activityCategory(activity).key !== "idle");
  const projectSeconds = new Map();
  activeSegments.forEach((activity) => {
    const key = resourceID(activity.projectID) || "unassigned";
    projectSeconds.set(key, (projectSeconds.get(key) || 0) + secondsForActivity(activity));
  });
  entries.forEach((entry) => {
    const key = resourceID(entry.project) || "unassigned";
    projectSeconds.set(key, (projectSeconds.get(key) || 0) + Math.max(0, Number(entry.duration || 0)));
  });
  const totalSeconds = [...projectSeconds.values()].reduce((sum, value) => sum + value, 0);
  const projectRows = projects.filter((project) => !project.archived && !project.is_archived).map((project) => {
    const ids = descendantProjectIDs(projects, project.id);
    const activitySeconds = activeSegments
      .filter((activity) => ids.has(resourceID(activity.projectID)))
      .reduce((total, activity) => total + secondsForActivity(activity), 0);
    const entrySeconds = entries
      .filter((entry) => ids.has(resourceID(entry.project)))
      .reduce((total, entry) => total + Math.max(0, Number(entry.duration || 0)), 0);
    return {
      id: resourceID(project.id),
      name: project.title || project.name || "Untitled project",
      seconds: activitySeconds + entrySeconds,
    };
  }).sort((left, right) => right.seconds - left.seconds || left.name.localeCompare(right.name));
  const scopeButton = (id, label, detail, Icon) => <button type="button" className={`stats-project-scope-option${selectedID === id ? " active" : ""}`} aria-pressed={selectedID === id} onClick={() => onChange(id)}><Icon size={16} /><span><strong>{label}</strong><small>{detail}</small></span></button>;
  return <aside className="stats-project-scope" aria-label="Stats projects"><div className="stats-project-scope-heading"><h2>Projects</h2><span>{formatDurationSeconds(totalSeconds)}</span></div><div className="stats-project-scope-list">{scopeButton("all", "All Activities", `${activeSegments.length} segments`, Waveform)}{scopeButton("unassigned", "Unassigned", formatDurationSeconds(projectSeconds.get("unassigned") || 0), TrayIcon)}{projectRows.length ? <div className="stats-project-scope-label">My Projects</div> : null}{projectRows.map((project) => scopeButton(project.id, project.name, formatDurationSeconds(project.seconds), FolderSimple))}</div><p className="stats-project-scope-hint">Select a project to scope every chart and total to the same activity evidence.</p></aside>;
}

function StatsPage({ api, dateKey, setDateKey, setPage, projectScopeID, setProjectScopeID }) {
  const [projectUnit, setProjectUnit] = useState("hour");
  const [statsPeriod, setStatsPeriod] = useState("week");
  const [customStartDate, setCustomStartDate] = useState(dateKey);
  const [customEndDate, setCustomEndDate] = useState(dateKey);
  const [statsRangeData, setStatsRangeData] = useState(null);
  const [statsRangeLoading, setStatsRangeLoading] = useState(false);
  const [statsShareMessage, setStatsShareMessage] = useState("");
  const statsBounds = statsRangeBounds(dateKey, statsPeriod, customStartDate, customEndDate);
  useEffect(() => {
    let current = true;
    if (statsPeriod === "week" || !api.connected) {
      setStatsRangeData(null);
      setStatsRangeLoading(false);
      return () => { current = false; };
    }
    setStatsRangeData(null);
    setStatsRangeLoading(true);
    api.fetchRange(statsBounds.start, statsBounds.end)
      .then((result) => { if (current) setStatsRangeData(result); })
      .catch(() => { if (current) setStatsRangeData({ activities: [], entries: [], startDate: statsBounds.start, endDate: statsBounds.end }); })
      .finally(() => { if (current) setStatsRangeLoading(false); });
    return () => { current = false; };
  }, [api.connected, api.fetchRange, statsBounds.end, statsBounds.start, statsPeriod]);
  const selectedDevice = api.activityPreferences?.selected_device || "All Devices";
  const baseDays = (api.calendarWeekly.length >= 7 ? api.calendarWeekly : api.weekly).slice(-7);
  const days = statsRangeData
    ? dateKeysBetween(statsBounds.start, statsBounds.end).map((date) => ({
      date,
      activities: statsRangeData.activities.filter((activity) => activity.date === date && activityMatchesSelectedDevice(activity, selectedDevice)),
      entries: [],
    }))
    : baseDays.map((day) => ({ ...day, activities: (day.activities || []).filter((activity) => activityMatchesSelectedDevice(activity, selectedDevice)) }));
  const secondsForActivity = (activity) => Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
  const productivityValue = (activity) => activityProductivityValue(activity, api.projects);
  const includeSubprojects = api.preferences?.include_subprojects_when_selecting_project !== false;
  const scopedProjectIDs = projectScopeID !== "all" && projectScopeID !== "unassigned"
    ? includeSubprojects ? descendantProjectIDs(api.projects, projectScopeID) : new Set([resourceID(projectScopeID)])
    : null;
  const inProjectScope = (activity) => projectScopeID === "all" || (projectScopeID === "unassigned" ? !activity.projectID : scopedProjectIDs.has(resourceID(activity.projectID)));
  const allSegments = days.flatMap((day) => day.activities || []);
  const segments = allSegments.filter(inProjectScope);
  const dayRows = days.map((day) => {
    const activities = (day.activities || []).filter((activity) => inProjectScope(activity) && activityCategory(activity).key !== "idle");
    const active = activities.reduce((total, activity) => total + secondsForActivity(activity), 0);
    const focused = activities.filter((activity) => activityCategory(activity).key === "focused").reduce((total, activity) => total + secondsForActivity(activity), 0);
    const weighted = activities.reduce((total, activity) => total + productivityValue(activity) * secondsForActivity(activity), 0);
    const categories = [...activities.reduce((groups, activity) => {
      const category = activityCategory(activity);
      const seconds = secondsForActivity(activity);
      const key = `${category.key}:${category.label}:${category.color}`;
      const current = groups.get(key) || { ...category, seconds: 0 };
      current.seconds += seconds;
      groups.set(key, current);
      return groups;
    }, new Map()).values()].sort((left, right) => right.seconds - left.seconds);
    return { date: day.date, label: new Date(`${day.date}T12:00:00`).toLocaleDateString(undefined, { weekday: "short" }), active, focused, categories, productivityScore: active ? Math.round(weighted / active) : 0 };
  });
  const showDailyPeriodRows = ["day", "yesterday", "week", "lastWeek"].includes(statsPeriod)
    || (statsPeriod === "custom" && dayRows.length <= 7);
  const periodRows = showDailyPeriodRows ? dayRows : Array.from({ length: Math.ceil(dayRows.length / 7) }, (_, index) => {
    const chunk = dayRows.slice(index * 7, index * 7 + 7);
    const categories = [...chunk.reduce((groups, day) => {
      day.categories.forEach((category) => {
        const key = `${category.key}:${category.label}:${category.color}`;
        const current = groups.get(key) || { ...category, seconds: 0 };
        current.seconds += category.seconds;
        groups.set(key, current);
      });
      return groups;
    }, new Map()).values()].sort((left, right) => right.seconds - left.seconds);
    const active = chunk.reduce((total, day) => total + day.active, 0);
    const weighted = chunk.reduce((total, day) => total + day.productivityScore * day.active, 0);
    const firstDate = chunk[0]?.date || statsBounds.start;
    return { date: firstDate, label: new Date(`${firstDate}T12:00:00`).toLocaleDateString(undefined, { month: "numeric", day: "numeric" }), active, focused: chunk.reduce((total, day) => total + day.focused, 0), categories, productivityScore: active ? Math.round(weighted / active) : 0 };
  });
  const weekdayRows = Array.from({ length: 7 }, (_, index) => {
    const matches = dayRows.filter((day) => {
      const weekday = new Date(`${day.date}T12:00:00`).getDay();
      return (weekday + 6) % 7 === index;
    });
    const active = matches.reduce((total, day) => total + day.active, 0);
    const categories = [...matches.reduce((groups, day) => {
      day.categories.forEach((category) => {
        const key = `${category.key}:${category.label}:${category.color}`;
        const current = groups.get(key) || { ...category, seconds: 0 };
        current.seconds += category.seconds;
        groups.set(key, current);
      });
      return groups;
    }, new Map()).values()].sort((left, right) => right.seconds - left.seconds);
    const weighted = matches.reduce((total, day) => total + day.productivityScore * day.active, 0);
    const label = new Date(2024, 0, index + 1, 12, 0, 0).toLocaleDateString(undefined, { weekday: "short" });
    return { date: `weekday-${index}`, label, active, focused: matches.reduce((total, day) => total + day.focused, 0), categories, productivityScore: active ? Math.round(weighted / active) : 0 };
  });
  const totalActive = dayRows.reduce((total, day) => total + day.active, 0);
  const totalFocused = dayRows.reduce((total, day) => total + day.focused, 0);
  const totalDistracted = segments.filter((activity) => activityCategory(activity).key === "distracting").reduce((total, activity) => total + secondsForActivity(activity), 0);
  const productivityScore = totalActive > 0 ? Math.round(segments.filter((activity) => activityCategory(activity).key !== "idle").reduce((total, activity) => total + productivityValue(activity) * secondsForActivity(activity), 0) / totalActive) : 0;
  const rangeStartTime = new Date(`${statsBounds.start}T00:00:00`).getTime();
  const rangeEndTime = new Date(`${offsetDateKey(statsBounds.end, 1)}T00:00:00`).getTime();
  const allWeeklyEntries = statsRangeData
    ? statsRangeData.entries.filter((entry) => {
      const start = new Date(entry.start_date || entry.start || "").getTime();
      const end = new Date(entry.end_date || entry.end || "").getTime();
      return Number.isFinite(start) && Number.isFinite(end) && start < rangeEndTime && end > rangeStartTime;
    })
    : days.flatMap((day) => day.entries || []);
  const weeklyEntries = allWeeklyEntries.filter((entry) => projectScopeID === "all" || (projectScopeID === "unassigned" ? !entry.project : scopedProjectIDs.has(resourceID(entry.project))));
  const hourRows = Array.from({ length: 24 }, (_, hour) => {
    const activities = segments.filter((activity) => activityCategory(activity).key !== "idle" && Math.min(23, Math.max(0, Math.floor(Number(activity.startSecond || 0) / 3600))) === hour);
    const active = activities.reduce((total, activity) => total + secondsForActivity(activity), 0);
    const weighted = activities.reduce((total, activity) => total + productivityValue(activity) * secondsForActivity(activity), 0);
    return { hour, active, productivityScore: active ? Math.round(weighted / active) : 0 };
  });
  const appRows = [...segments.reduce((groups, activity) => {
    const category = activityCategory(activity);
    if (category.key === "idle") return groups;
    const name = activity.appName || activity.deviceName || "Unknown App";
    const key = `${name}::${category.key}:${category.label}`;
    const current = groups.get(key) || { name, category, icon: activityIcon(activity), seconds: 0 };
    current.seconds += Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
    groups.set(key, current);
    return groups;
  }, new Map()).values()].sort((left, right) => right.seconds - left.seconds).slice(0, 8);
  const projectTotals = segments.reduce((groups, activity) => {
    if (activityCategory(activity).key === "idle") return groups;
    const key = projectTitleFor(api.projects, activity.projectID);
    groups.set(key, (groups.get(key) || 0) + secondsForActivity(activity));
    return groups;
  }, new Map());
  weeklyEntries.forEach((entry) => {
    const key = projectTitleFor(api.projects, entry.project);
    projectTotals.set(key, (projectTotals.get(key) || 0) + Math.max(0, Number(entry.duration || 0)));
  });
  const projectRows = [...projectTotals.entries()].sort((left, right) => right[1] - left[1]).slice(0, 8);
  const categoryRows = [...segments.filter((activity) => activityCategory(activity).key !== "idle").reduce((groups, activity) => {
    const category = activityCategory(activity);
    const key = category.key + "::" + category.label;
    const current = groups.get(key) || { key: category.key, label: category.label, color: category.color, seconds: 0 };
    current.seconds += Math.max(0, Number(activity.endSecond || 0) - Number(activity.startSecond || 0));
    groups.set(key, current);
    return groups;
  }, new Map()).values()].sort((left, right) => right.seconds - left.seconds);
  const categoryTotal = categoryRows.reduce((total, row) => total + row.seconds, 0);
  const categoryDonutRows = categoryRows.map((row) => ({ ...row, color: activityCategoryStyle({ color: row.color }).color }));
  const applicationDonutRows = appRows.map((row) => ({ ...row, key: `${row.name}:${row.category.label}`, label: row.name, color: activityCategoryStyle(row.category).color }));
  const projectDonutRows = projectRows.map(([name, seconds], index) => {
    const project = api.projects.find((item) => projectTitleFor(api.projects, item.id) === name);
    const fallbackColors = ["blue", "purple", "green", "orange", "red", "graphite"];
    return { key: name, label: name, seconds, color: activityCategoryStyle({ color: project ? projectColorKey(project) : fallbackColors[index % fallbackColors.length] }).color };
  });
  const maxCategory = Math.max(1, ...categoryRows.map((row) => row.seconds));
  const maxDay = Math.max(1, ...periodRows.map((day) => day.active));
  const maxHour = Math.max(1, ...hourRows.map((row) => row.active));
  const maxApp = Math.max(1, ...appRows.map((row) => row.seconds));
  const formatStat = (seconds) => formatDurationSeconds(seconds);
  const formatProjectValue = (seconds) => projectUnit === "day" ? `${(seconds / 86400).toFixed(1)}d` : formatStat(seconds);
  const statsRangeLabel = statsPeriodLabel(statsPeriod);
  const statsShareText = [
    "Metriday Stats",
    `${statsRangeLabel} · ${statsBounds.start}–${statsBounds.end}`,
    `Total time: ${formatStat(totalActive)}`,
    `Productivity score: ${totalActive ? `${productivityScore}%` : "—"}`,
    `Related time: ${formatStat(totalFocused)}`,
    `Distraction: ${formatStat(totalDistracted)}`,
    "",
    "Top categories",
    ...categoryRows.slice(0, 5).map((row) => `${row.label}: ${formatStat(row.seconds)}`),
  ].join("\n");
  const shareStats = async () => {
    const markShareResult = (message) => {
      setStatsShareMessage(message);
      window.setTimeout(() => setStatsShareMessage(""), 1800);
    };
    try {
      if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
        try {
          await navigator.share({ title: "Metriday Stats", text: statsShareText });
          markShareResult("Shared");
          return;
        } catch (error) {
          if (error?.name === "AbortError") return;
        }
      }
      if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(statsShareText);
        markShareResult("Copied");
        return;
      }
      const textarea = document.createElement("textarea");
      textarea.value = statsShareText;
      textarea.setAttribute("readonly", "true");
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      const copied = document.execCommand("copy");
      textarea.remove();
      if (!copied) throw new Error("Clipboard unavailable");
      markShareResult("Copied");
    } catch (error) {
      setStatsShareMessage(error?.name === "AbortError" ? "" : "Share unavailable");
    }
  };
  return <main className="page supporting-page stats-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? `Native statistics · ${statsPeriodLabel(statsPeriod)}` : "Local preview"}</span><h1>Stats</h1></div><div className="activities-page-actions"><DateControls dateKey={dateKey} onChange={setDateKey} label="Choose Stats date" /><label className="stats-period-picker"><span>Period</span><select value={statsPeriod} onChange={(event) => setStatsPeriod(event.target.value)} aria-label="Stats period"><option value="day">Today</option><option value="yesterday">Yesterday</option><option value="week">This Week</option><option value="lastWeek">Last Week</option><option value="month">This Month</option><option value="lastMonth">Last Month</option><option value="year">This Year</option><option value="lastYear">Last Year</option><option value="custom">Custom Range</option></select></label>{statsPeriod === "custom" ? <div className="stats-custom-range" aria-label="Custom Stats date range"><label>From<input type="date" value={customStartDate} onInput={(event) => { const value = event.target.value; setCustomStartDate(value); if (value > customEndDate) setCustomEndDate(value); }} /></label><span aria-hidden="true">–</span><label>To<input type="date" value={customEndDate} onInput={(event) => { const value = event.target.value; setCustomEndDate(value); if (value < customStartDate) setCustomStartDate(value); }} /></label></div> : null}<button className="quiet-pill stats-share-button" type="button" onClick={shareStats} aria-label="Share Stats"><ShareNetwork size={16} />{statsShareMessage || "Share"}</button>{statsShareMessage ? <span className="stats-share-status" role="status">{statsShareMessage}</span> : null}<button className="quiet-pill" type="button" onClick={() => setPage?.("activities")}>Open Activities</button><button className="quiet-pill" type="button" onClick={() => api.refresh()}>{api.loading || statsRangeLoading ? "Loading…" : "Refresh"}</button></div></header><div className="stats-workspace"><StatsProjectScope projects={api.projects} segments={allSegments} entries={allWeeklyEntries} selectedID={projectScopeID} onChange={setProjectScopeID} /><div className="stats-main"><section className="stats-summary"><div><Clock size={22} /><span>Total time</span><strong>{formatStat(totalActive)}</strong><small>Active app usage</small></div><div><ShieldCheck size={22} /><span>Productivity score</span><strong>{totalActive ? `${productivityScore}%` : "—"}</strong><small>Weighted by project relevance</small></div><div><Timer size={22} /><span>Related time</span><strong>{formatStat(totalFocused)}</strong><small>Task-related activity</small></div><div><TrendUp size={22} /><span>Distraction</span><strong>{formatStat(totalDistracted)}</strong><small>Detected locally</small></div></section><section className="stats-grid"><section className="stats-panel"><div className="chart-heading"><div><h2>{showDailyPeriodRows ? "Time by Day" : "Time by Week"}</h2><p>Active minutes by Category.</p></div><div className="legend stats-category-legend">{categoryRows.slice(0, 5).map((category) => <span key={category.key + category.label}><i style={{ background: activityCategoryStyle(category).color }} />{category.label}</span>)}</div></div><div className={`stats-bars stats-category-bars stats-period-bars-${statsPeriod} ${statsPeriod === "custom" && !showDailyPeriodRows ? "stats-period-bars-custom-long" : ""}`}><span className="stats-visually-hidden">Active minutes by Category and period</span>{periodRows.map((day) => <div className="stats-bar-column" key={day.date}><div className="stats-bar-track stats-category-bar-track">{day.categories.map((category) => <i key={category.key + category.label} className={category.key} style={{ height: Math.max(0.8, (category.seconds / Math.max(1, maxDay)) * 100) + "%", background: activityCategoryStyle(category).color }} />)}</div><strong>{day.active ? formatStat(day.active) : "—"}</strong><span>{day.label}</span></div>)}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Most productive weekdays</h2><p>Productivity score</p></div></div><div className="stats-bars stats-score-bars"><span className="stats-visually-hidden">Productivity score by weekday</span>{weekdayRows.map((day) => <div className="stats-bar-column" key={day.date}><div className="stats-bar-track"><i style={{ height: Math.max(3, day.productivityScore) + "%", background: "var(--success)" }} /></div><strong>{day.productivityScore}%</strong><span>{day.label}</span></div>)}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Most active hours</h2><p>Active minutes</p></div></div><div className="stats-hour-bars"><span className="stats-visually-hidden">Active minutes by hour</span>{hourRows.map((row) => <div className="stats-hour-column" key={row.hour}><div className="stats-hour-track"><i style={{ height: Math.max(3, (row.active / maxHour) * 100) + "%" }} /></div><span>{row.hour % 6 === 0 || row.hour === 23 ? String(row.hour).padStart(2, "0") : ""}</span></div>)}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Most productive hours</h2><p>Productivity score</p></div></div><div className="stats-hour-bars stats-score-bars"><span className="stats-visually-hidden">Productivity score by hour</span>{hourRows.map((row) => <div className="stats-hour-column" key={row.hour}><div className="stats-hour-track"><i style={{ height: Math.max(3, row.productivityScore) + "%", background: "var(--success)" }} /></div><span>{row.hour % 6 === 0 || row.hour === 23 ? String(row.hour).padStart(2, "0") : ""}</span></div>)}</div></section><section className="stats-panel stats-category-panel"><div className="chart-heading"><div><h2>Productivity pulse</h2><p>Category-weighted activity quality.</p></div></div><div className="stats-donut-layout stats-category-donut-layout">{categoryRows.length ? <><StatsDonut rows={categoryDonutRows} total={categoryTotal} centerLabel={totalActive ? `${productivityScore}` : "—"} centerCaption="score" label="Productivity pulse" /><div className="stats-category-list" aria-label="Activity categories">{categoryRows.map((row) => { const categoryStyle = activityCategoryStyle({ color: row.color }); const percentage = categoryTotal ? Math.round((row.seconds / categoryTotal) * 100) : 0; const relativeWidth = Math.max(2, (row.seconds / Math.max(1, maxCategory)) * 100); return <div className="stats-category-row" key={row.key + row.label}><div className="stats-category-heading"><span className="stats-category-name"><i style={{ background: categoryStyle.color }} /><span>{row.label}</span></span><strong>{percentage}%</strong><small>{formatStat(row.seconds)}</small></div><div className="stats-category-track" aria-hidden="true"><b style={{ width: `${relativeWidth}%`, background: categoryStyle.color }} /></div></div>; })}</div></> : <div className="entries-empty"><ChartBar size={22} /><span>No categorized activity yet.</span></div>}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Time per Project</h2><p>Tracked activity and time entries.</p></div><label className="stats-unit-picker">Unit<select value={projectUnit} onChange={(event) => setProjectUnit(event.target.value)} aria-label="Project time unit"><option value="hour">Hour</option><option value="day">Day</option></select></label></div><div className="stats-ranking">{projectRows.length ? projectRows.map(([name, seconds]) => <div className="stats-ranking-row" key={name}><span>{name}</span><i><b style={{ width: `${Math.max(4, (seconds / Math.max(1, projectRows[0][1])) * 100)}%` }} /></i><strong>{formatProjectValue(seconds)}</strong></div>) : <div className="entries-empty"><FolderSimple size={22} /><span>No project activity yet.</span></div>}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Projects &amp; Time Entries</h2><p>Tracked activity and time entries</p></div><span className="api-badge">{formatStat(projectRows.reduce((total, row) => total + row[1], 0))}</span></div><div className="stats-donut-layout">{projectRows.length ? <><StatsDonut rows={projectDonutRows} total={projectRows.reduce((total, row) => total + row[1], 0)} label="Projects and Time Entries" /><div className="stats-donut-legend">{projectDonutRows.map((row) => <div className="stats-donut-legend-row" key={"entries-" + row.key}><i style={{ background: row.color }} /><span>{row.label}</span><strong>{formatStat(row.seconds)}</strong></div>)}</div></> : <div className="entries-empty"><Clock size={22} /><span>No project-assigned activity or time entry yet.</span></div>}</div></section><section className="stats-panel"><div className="chart-heading"><div><h2>Most active applications</h2><p>Top App / website sources by captured time.</p></div></div><div className="stats-donut-layout">{appRows.length ? <><StatsDonut rows={applicationDonutRows} total={appRows.reduce((total, row) => total + row.seconds, 0)} label="Most active applications" /><div className="stats-donut-legend">{appRows.map((row) => <div className="stats-donut-legend-row stats-app-legend-row" key={row.name + ":" + row.category.label}><span className="stats-app-identity"><row.icon size={15} weight="duotone" /></span><span>{row.name}<small className={`activity-category ${row.category.key}`} style={activityCategoryStyle(row.category)}><i />{row.category.label}</small></span><strong>{formatStat(row.seconds)}</strong></div>)}</div></> : <div className="entries-empty"><Browsers size={22} /><span>No application activity yet.</span></div>}</div></section></section></div></div></main>;
}

function ReportsPage({ api, dateKey, setDateKey }) {
  return <main className="page supporting-page reports-page"><header className="supporting-header activities-page-header"><div><span>{api.connected ? "Native report builder" : "Local preview"}</span><h1>Reports</h1></div><div className="activities-page-actions"><DateControls dateKey={dateKey} onChange={setDateKey} label="Choose Reports date" /></div><button className="quiet-pill" type="button" onClick={api.refresh}>{api.loading ? "Connecting…" : "Refresh"}</button></header><WebReportPanel api={api} dateKey={dateKey} /></main>;
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

function WebProjectRulesPanel({ api, dateKey }) {
  const [projectID, setProjectID] = useState("");
  const [field, setField] = useState("application");
  const [comparison, setComparison] = useState("contains");
  const [pattern, setPattern] = useState("");
  const [reapplyBusy, setReapplyBusy] = useState("");
  const [message, setMessage] = useState("");
  const fields = { application: "Application", bundleIdentifier: "Bundle identifier", titleContains: "Title contains", resourceContains: "URL or path contains", domain: "Domain", fullURL: "Full website URL", keyword: "Keyword", startTime: "Start time", dayOfWeek: "Day of week" };
  const projects = api.projects || [];
  const submit = async (event) => {
    event.preventDefault();
    if (!projectID || !pattern.trim() || !api.connected) return;
    try {
      await api.createProjectRule({ project_id: projectID, field, comparison, pattern: pattern.trim(), case_sensitive: false });
      setPattern("");
      setMessage("Project rule saved.");
    } catch (error) {
      setMessage(error.message || "Could not save the project rule.");
    }
  };
  const reapply = async (scope) => {
    if (!api.connected || reapplyBusy) return;
    setReapplyBusy(scope);
    setMessage("");
    try {
      if (scope === "today") await api.reapplyProjectRules(dateKey);
      else await api.reapplyAllProjectRules();
      setMessage(scope === "today" ? `Project rules reapplied to ${dateKey}.` : "Project rules reapplied to all stored history.");
    } catch (error) {
      setMessage(error.message || "Could not reapply project rules.");
    } finally {
      setReapplyBusy("");
    }
  };
  return <section className="project-rules-panel"><div className="project-rules-heading"><div><h2>Project automation rules</h2><p>Assign future App, title, domain, URL, or keyword activity to a project.</p></div><span className="api-badge">{api.projectRules.length} saved</span></div><form className="project-rules-form" onSubmit={submit}><select value={projectID} onChange={(event) => setProjectID(event.target.value)} aria-label="Project rule project"><option value="">Choose project</option>{projects.map((project) => <option key={project.id} value={resourceID(project.id)}>{project.title || project.name}</option>)}</select><select value={field} onChange={(event) => setField(event.target.value)} aria-label="Project rule field">{Object.entries(fields).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><select value={comparison} onChange={(event) => setComparison(event.target.value)} aria-label="Project rule comparison"><option value="contains">contains</option><option value="equals">is</option><option value="beginsWith">begins with</option><option value="endsWith">ends with</option><option value="like">is like</option><option value="matchesRegex">matches regex</option></select><input value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="Matching value" aria-label="Project rule value" /><button type="submit" disabled={!api.connected || !projectID || !pattern.trim()}><Plus size={16} />Add Rule</button></form>{api.projectRules.length > 0 ? <div className="project-rules-list">{api.projectRules.map((rule, index) => <div className="project-rule-row" key={rule.id}><span className="web-source-icon"><Sparkle size={17} /></span><div><strong>{rule.project_name || projectTitleFor(projects, rule.project_id)}</strong><small>{fields[rule.field] || rule.field} {rule.comparison} “{rule.pattern}”</small></div><span className="project-rule-order"><IconButton label="Move rule up" onClick={() => api.moveProjectRule(rule.id, -1)} disabled={index === 0}><CaretLeft size={15} className="rotate-up" /></IconButton><IconButton label="Move rule down" onClick={() => api.moveProjectRule(rule.id, 1)} disabled={index === api.projectRules.length - 1}><CaretRight size={15} className="rotate-down" /></IconButton></span><IconButton label={`Delete rule for ${rule.project_name || "project"}`} onClick={() => api.deleteProjectRule(rule.id)}><Trash size={15} /></IconButton></div>)}</div> : <div className="project-rules-empty"><Sparkle size={22} /><span>No project automation rules yet. Assign an activity in Activities, then save its matching pattern here.</span></div>}<div className="project-rules-footer"><span><ArrowsClockwise size={15} />{message || "Rules only change existing activity when you explicitly reapply them."}</span><div><button type="button" onClick={() => reapply("today")} disabled={!api.connected || Boolean(reapplyBusy)}>{reapplyBusy === "today" ? "Reapplying…" : "Reapply to Today"}</button><button type="button" onClick={() => reapply("all")} disabled={!api.connected || Boolean(reapplyBusy)}>{reapplyBusy === "all" ? "Reapplying…" : "Reapply All History"}</button></div></div></section>;
}

function RulesPageLive({ api }) {
  const [locked, setLocked] = useState(true);
  const [blocked, setBlocked] = useState(["youtube.com", "x.com", "reddit.com"]);
  const [allowed, setAllowed] = useState(["arxiv.org", "github.com", "pytorch.org"]);
  const [draft, setDraft] = useState("");
  const [allowedDraft, setAllowedDraft] = useState("");
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
  const addAllowedDomain = async (event) => {
    event.preventDefault();
    const domain = allowedDraft.trim();
    if (!domain) return;
    try {
      if (api.connected) await api.addWebRule(domain, true);
      else if (!allowed.includes(domain)) setAllowed((items) => [...items, domain]);
      setAllowedDraft("");
      setMessage("Allowed site added.");
    } catch (error) {
      setMessage(error.message || "Could not add the allowed site.");
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
  const currentTask = api.status?.currentTask;
  const currentTaskRange = taskMinuteRange(currentTask);
  const currentScope = currentTask?.title || "No scheduled block";
  const currentScopeTime = currentTaskRange ? formatRange(currentTaskRange.start, currentTaskRange.end) : "No time";
  return <main className="page supporting-page rules-page"><header className="supporting-header"><div><span>{api.connected ? "Native Focus rules" : "Focus rules"}</span><h1>Research Focus</h1></div><button type="button" className={`status-pill ${focusActive ? "active" : ""}`} onClick={toggleFocus} disabled={api.connected && !currentTask} title={api.connected && !currentTask ? "Schedule a current block to start Focus" : undefined}><LockSimple size={17} />{focusActive ? "Locked mode on" : "Flexible mode"}</button></header><div className="rules-layout"><section className="rule-overview"><ShieldCheck size={54} color="#3da65a" weight="duotone" /><h2>Protect deep-work blocks</h2><p>{api.connected ? "Changes are saved to the native Metriday blocklist on this Mac." : "This rule starts with scheduled research tasks and stays local to this Mac."}</p><div className="rule-meta"><span><Clock size={18} />Runs with calendar blocks</span><span><Laptop size={18} />Local processing</span><span><Browsers size={18} />Safari + Chrome</span></div><div className="rules-current-scope"><span>Current scope</span><strong>{currentScope}</strong><small>{currentScopeTime} · Safari + Chrome</small></div></section><section className="site-list-section"><div className="site-list-heading"><div><h2>Blocked sites</h2><p>Attempts are recorded as distraction evidence.</p></div><strong>{blockedItems.length}</strong></div><div className="site-list">{blockedItems.map((item) => <div key={item.id}><GlobeSimple size={20} /><span>{item.domain}</span><IconButton label={`Allow ${item.domain}`} onClick={() => allowDomain(item)}><X size={15} /></IconButton></div>)}</div><form onSubmit={addDomain}><GlobeSimple size={19} /><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Add a distracting domain" aria-label="Add blocked website" /><button type="submit"><Plus size={17} />Add</button></form></section><section className="site-list-section allowed-section"><div className="site-list-heading"><div><h2>Allowed research</h2><p>Always available inside this focus rule.</p></div><strong>{allowedItems.length}</strong></div><div className="site-list">{allowedItems.map((item) => <div key={item.id}><CheckCircle size={20} weight="fill" /><span>{item.domain}</span><IconButton label={`Remove ${item.domain}`} onClick={() => removeDomain(item)}><X size={15} /></IconButton></div>)}</div><form onSubmit={addAllowedDomain}><CheckCircle size={19} weight="fill" /><input value={allowedDraft} onChange={(event) => setAllowedDraft(event.target.value)} placeholder="Add a research domain" aria-label="Add allowed website" /><button type="submit"><Plus size={17} />Add</button></form></section></div><section className="rules-explanation"><div><ShieldCheck size={20} /><div><strong>How blocking works in this build</strong><p>When a focus session is active, Metriday checks the frontmost Safari or Chrome tab. A matching domain is replaced with a local focus page. macOS asks for Automation permission the first time. The blocklist stays on this Mac and is never uploaded.</p></div></div><span><LockSimple size={17} />A future hardened mode can use an Apple Network Extension for system-wide enforcement; that target requires Apple-granted entitlements and code signing.</span></section><WebProjectRulesPanel api={api} dateKey={api.status?.selectedDate || localDateKey()} />{message ? <p className="entry-message rules-message" role="status">{message}</p> : null}</main>;
}

export function App() {
  const [page, setPage] = useState("today");
  const [dateKey, setDateKey] = useState(localDateKey());
  const [activityScopeID, setActivityScopeID] = useState("all");
  const [tasks, setTasks] = useState(initialTasks);
  const [apiBase, setApiBase] = useState(apiBaseURL);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const api = useMetridayAPI(dateKey, apiBase);
  const content = useMemo(() => page === "plan" ? <PlanPage tasks={tasks} setTasks={setTasks} api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "activities" ? <ActivitiesPage api={api} dateKey={dateKey} setDateKey={setDateKey} projectScopeID={activityScopeID} setProjectScopeID={setActivityScopeID} /> : page === "stats" ? <StatsPage api={api} dateKey={dateKey} setDateKey={setDateKey} setPage={setPage} projectScopeID={activityScopeID} setProjectScopeID={setActivityScopeID} /> : page === "reports" ? <ReportsPage api={api} dateKey={dateKey} setDateKey={setDateKey} /> : page === "teams" ? <TeamsPage api={api} /> : page === "review" ? <ReviewPage api={api} dateKey={dateKey} setDateKey={setDateKey} setPage={setPage} /> : page === "rules" ? <RulesPageLive api={api} /> : <TodayPage setPage={setPage} api={api} dateKey={dateKey} setDateKey={setDateKey} />, [api, page, tasks, dateKey, setPage, activityScopeID]);
  return <div className="app-shell"><Sidebar page={page} setPage={setPage} api={api} onOpenSettings={() => setSettingsOpen(true)} /><div className="app-main"><WebGlobalHeader api={api} setPage={setPage} dateKey={dateKey} setDateKey={setDateKey} />{content}</div><ConnectionSettings open={settingsOpen} api={api} apiBase={apiBase} connected={api.connected} onSave={setApiBase} onClose={() => setSettingsOpen(false)} /></div>;
}
