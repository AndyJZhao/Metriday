# Metriday v1：Timing.app 复刻实现收尾记录

> 日期：2026-08-21（Asia/Shanghai）  
> 当前原生实现：`MetridayMac/`
> 当前 Web companion：仓库根目录 `src/`
> 当前 HEAD：`fd71e36 [8.168 Development] 💻 📝 Add expandable Reports outline`

## 1. 这份文档的目的

本文件是 v1 收尾和下一轮实现的交接基线，记录当前已经落地的 Timing.app Professional 复刻范围、Metriday 的明确改进、数据边界、验证证据以及仍然未完成的工作。

产品方向不是把 Timing 的界面机械复制成 Web 页面，而是以 Timing 的自动活动记录、项目、计时器、报告和 Focus 作为功能基线，再用 NotePlan 风格的 Markdown 计划与 Calendar 时间线统一“计划了什么”和“实际发生了什么”。生产运行时是原生 macOS 14+ SwiftUI/AppKit；React/Vite 版本是 API-backed companion 和视觉参考，不是 WebView 包装。

## 2. 当前完成度摘要

### 已完成的主链路

1. 原生 macOS 产品壳：Today、Plan、Activities、Stats、Reports、Review、Rules、Teams、Settings，以及持久的左侧导航和顶部日期 / Block / Focus / Blocklist 控制。
2. Markdown-first Plan：每日 Markdown 是单一事实源，连续编辑器和时间线对同一个文件进行读写。
3. Time Block：从任务拖拽创建、移动、上下边缘调整、完成同步、Focus 启停和 planned-vs-actual 反馈。
4. App / Website / Window activity：每秒采样前台应用，记录浏览器域名、窗口标题、文档路径、Idle、设备来源和可解释的分类结果。
5. RescueTime 语义：App 使用浅灰身份块，Category 负责颜色；Focused 为深蓝，Distracting 为红色，Other/Idle 为中性色；App、Website、Item 三类规则独立可编辑。
6. Timing 项目与时间记录：项目树、规则归属、手动 Time Entry、Timer、计费状态、覆盖拆分、Entry-O-Matic undo、报告和导出。
7. Activities：Unified、Chronological、By Category，项目/设备层级，筛选器，水平和垂直时间线，Calendar / Time Entry / App Usage 轨道，拖拽分配和完整的详情 / 菜单交互。
8. Stats、Review、Reports、Teams：统计图表、项目与时间记录层级、报告构建器、导出、Smart Activity Summary、团队与成员本地模型。
9. Focus 与网页阻断 MVP：当前 Markdown Block 可启动 Focus-aware Timer 和前台 Safari/Chrome 域名阻断；焦点生命周期、暂停、继续、超时、睡眠恢复均有明确语义。
10. 本地自动化与 companion：localhost API、Timing 形状的 `/api/v1` aliases、URL scheme、AppleScript、原生设置、Timing Sync 和 Web companion 已接入同一套本地数据模型。
11. Focus/Session 独立浮动 companion：原生 AppKit/SwiftUI `NSPanel` 已接入同一套 AppState / TimeEntryStore / Focus lifecycle，支持 always-on-top、拖动、隐藏、剩余/超时、planned duration、活动分解、blocklist 状态和菜单动作。

### 明确未完成或暂缓

- Focus/Session companion 的 Phase A 已完成；后续只剩多显示器、屏幕边缘、relaunch、sleep、Accessibility test identifiers 和长时间运行等硬化验证。
- 网页阻断目前是 Safari/Chrome 前台 tab 监控 + 本地 Focus page redirect。系统级 Network Extension 需要 Apple entitlement、签名和 app extension 分发，暂未纳入本地 dev build。
- Calendar 默认只读；手动 Record Time Entry 和 Convert to Time Block 已有，默认不会自动复制 Markdown 或自动启动 Timer。
- v1 仍是本地优先 dev repo，不是生产发布版本；账号服务、云端协作、正式签名分发和远程同步服务尚未作为产品前提。

## 3. 产品壳与交互基线

### 3.1 原生运行时

- `MetridayMac/` 是 shipping direction，使用 SwiftUI + AppKit pointer tracking。
- 不使用 WebView 包装原生产品；文件、权限、菜单栏、快捷键和本地数据都走 macOS 原生能力。
- Light native-macOS visual direction：白色和 soft-neutral surface、graphite text、blue-violet accent、细分隔线、低 elevation、SF/Inter-like typography。
- 所有 section 保持同一产品壳，导航和顶部控制不会被 NotePlan 编辑器 chrome 替换。

### 3.2 命中区域和点击语义

本轮已经系统修复了用户指出的“只有文字可点击”的问题。代表一个导航或选择动作的可视行都使用整行 hit target，包括空白区域、尾部 chevron 和 banner；紧凑的 icon 或 trailing action 仍保持独立动作。

已覆盖：

- Today 日期 banner 的整块点击和 Go to Today；
- sidebar Today / Plan / Activities / Stats / Reports / Review / Rules / Teams / Data / Settings；
- Plan 月历日期、相邻日期、Time Block 和 Markdown 任务行；
- Activities 项目、设备、过滤器、活动行、Time Entry 行和 timeline block；
- Stats 项目、标题组和 Time Entry 详情；
- Reports preset、Project / Title / Entry 层级行；
- Web companion 中与原生对应的日期 banner、来源行、项目行、报告 preset 和时间记录操作。

这一规则既服务普通鼠标操作，也服务 Accessibility / AX smoke 验证。

## 4. Plan 与 Time Block

### 4.1 Markdown 单一事实源

每日文件位于：

```text
~/Library/Application Support/Metriday/Calendar/YYYY-MM-DD.md
```

- Plan 是单一连续 plain-text editor，不拆成 `Plan` / `Raw Markdown` 模式。
- 任意 Markdown 可编辑并原样保留；Return 会继续 task、bullet、numbered-list 前缀。
- 非活动行使用 NotePlan 风格 hybrid live preview：heading、bold、italic、strike、inline code、link、quote、bullet、numbered list、task checkbox 渲染为语义视图；当前编辑行显示必要的轻量语法。
- `- [ ] Task` 解析后出现可见的六点拖拽句柄；展示层属性不会写入 Markdown。
- 点击任意缺失日期会创建空白 daily template，不复制其他日期的任务。
- 每日文件通过本地 `TaskIdentities.json` sidecar 保持任务身份，确保 Reload、Focus、Time Entry、Web refresh 后仍解析到同一 Time Block。

### 4.2 时间线排程

- 右侧为 compact month calendar + continuous multi-day Timeline，不增加 Day/Week mode 控件。
- 任务行或六点句柄拖入时间线：普通 drop 弹出 Time Block / Event 选择；`⌘` drop 立即创建 Time Block；`⌥` drop 保留为 Event 入口。
- Time Block body 可整体移动；顶部边缘改 start；底部边缘改 end；时间吸附 15 分钟。
- 移动、resize、删除时间范围都会立即改写对应 Markdown task line；删除只删除时间，不删除任务文本。
- Calendar Event overlap 会在选择面板中解释冲突，但不会悄悄覆盖或创建对象。
- Plan 时间线有 live current-time marker，display-only，不拦截 task selection、resize 或 drag/drop。

### 4.3 计划与实际关联

- Focus Session 和手动记录的 Time Entry 可通过 `metriday_plan_task_id` 关联到 Markdown task。
- 同一 task 的暂停 / 继续会聚合为多个实际执行区间，完成后显示 `Actual …`，运行中显示 `In progress …`。
- Time Block detail surface 展示 planned range、实际区间、App/Website evidence、Focus quality（focused / distracting / other / idle）和 active focused percentage。
- evidence 关系可解释为 task keyword match、Focused/Distracting category 或 planned-time overlap；这些证据只展示，不自动改写 Markdown。

## 5. 本地活动采集与数据语义

### 5.1 App Usage monitor

活动历史位于：

```text
~/Library/Application Support/Metriday/Activity/YYYY-MM-DD.json
```

- 原生 monitor 约每秒采样前台应用。
- 应用、focused window title、Idle state 变化时关闭当前 segment。
- 默认约两分钟无键盘 / pointer 输入视为 Idle；恢复后弹出 Idle interval form。
- Idle form 有 Timing 风格 `prev`、`−5m`、`+5m`、`next`，支持 `⌥` 1 分钟和 `⌘` 15 分钟调整，也可对齐相邻 Time Entry boundary。
- 活动数据保留 `appName`、bundle identifier、device、window title、resource/URL、second-level range、relevance、project ID、activity date。
- 无 Accessibility 权限仍可记录应用级 observation；获得权限后可读取窗口标题和文档 context。
- Safari、Chrome、Firefox、Brave 的域名通过 Automation permission 捕获；Private / Incognito / InPrivate 窗口在隐私检查后丢弃。
- Activity monitor 处理 sleep/wake，关闭 sleep 前 segment，并按偏好恢复 tracking。
- 支持 non-midnight `Wrap days at`，逻辑 workday、timeline axis、Native 和 Web 保持一致。

### 5.2 来源和可选集成

- App foreground tracking：默认本地可用。
- Apple Screen Time `knowledgeC.db`：read-only、可选；Full Disk Access 后导入 iPhone/iPad-style App/Web usage，归档到 `ScreenTime`，权限或 schema 不可用时降级到 archive。
- Calendar EventKit：只读显示、Event change refresh、详情、Record Time Entry、幂等的 Convert to Time Block；一个外部 event identifier 只关联一个 Markdown Time Block。
- Reminders：权限后可提供 completed tasks 和 title suggestions。
- Phone Calls：本地 Call History 只在授权后读取，状态含 `database_available`，可隐藏号码。
- 未归属活动可以作为底层采样或待分类证据，但不增加第三类用户时间对象。

### 5.3 RescueTime 分类颜色

这是当前必须保持的语义基线：

| 来源 | 作用 |
| --- | --- |
| App | 第一列身份；浅灰色 icon tile / graphite icon |
| Category | 第二列语义与颜色，颜色来自自定义分类 |
| Website | 可单独作为分类规则来源 |
| Item | 可单独匹配 window title / document / path |
| Focused | 深蓝色 |
| Distracting | 红色 |
| Other / Idle | 中性颜色 |

App、Website、Item 规则有独立匹配来源和优先级；类别颜色不会被 App icon 或 Project color 覆盖。Project color 只表示项目身份。

## 6. Activities 工作区

### 6.1 工具栏和侧栏

Activities 已有 Timing 风格完整 toolbar：New Project、New Time Entry、Start Timer、Date Range、Devices、Filters、Timeline Orientation、Search。侧栏包含 All Activities、Unassigned、My Projects 项目层级、Archived Projects、Project Drop Zone 和 Saved Filters。

- 父项目默认包含 descendants；Settings 可选择只作用于 parent。
- 父项目选中支持 plain click、`⌘` multi-select、`⇧` contiguous range select。
- Activity 可拖到 Project 重新归属；`⌥` drop 可同时建立 future-activity rule。
- Project Drop Zone 支持 Finder file/folder 或 activity drop；普通多项 drop 合并为一个项目，`⌘` 拆成 child projects，`⌥` 保留创建 rule 意图。
- 规则 Reapply 是显式操作，并保留不匹配的手动 assignment。

### 6.2 视图和分组

- Unified：可展示 Project → Device → Application → Activity 层级。
- Chronological：按时间查看 Websites、Applications、Paths、Keywords 等摘要。
- By Category：Focused、Distracting、Other/Idle 等独立 cards。
- Project 与 Device group header 都是可折叠、整行可点、可访问的 disclosure control。
- Saved Filters 与 Projects 独立；Filter 是 rule-based saved view，不修改 Project assignment，也不包含 manual Time Entry。
- Built-in filters 包括 Web Browsing、Media、Communication、Office & Business、Reading & Writing、File Management、Graphics、Development、Finance、Gaming、Social Media；可和 Project / Saved Filter 组合。

### 6.3 两种时间线

- Horizontal：compact `MACOS` / `PROJECT` strip，另外显示 Calendar 和 Time Entries track；Project 连续相邻片段合并。
- Vertical：Timing-style `MACOS` / `PROJECT` / `TIME ENTRIES` lanes，有小时刻度、Calendar event、Time Entry、App Usage、gap action 和 category legend。
- App Usage 使用深蓝 / 红 / 灰区分 Focused / Distracting / Other/Idle；Time Entry 使用 amber lane；Calendar Event 使用蓝色 dashed/amber 风格；Smart Summary 使用 sparkle-marked dashed block。
- 活动 block hover 显示 second-level range、duration、source 和 Project marker；未归属 App 显示 `None · From the app usage`。
- timeline drag selection 15 分钟吸附，可过滤活动或创建 offline Time Entry。
- Activity block 的 `+`、context menu、double-click、Option-click 均可进入或立即创建精确范围的 Time Entry。
- Time Entry 可以直接编辑、删除、移动、resize；覆盖范围只替换选中部分，前后碎片保留；Entry-O-Matic undo 原子恢复。
- Calendar Event 普通 click 打开详情，`⌥` click 显式记录 Time Entry；不自动启动 Timer。

### 6.4 Display settings

持久化 Timing 风格设置：

- App Usage / Time Entry 是否显示；
- window title 和 resource path 是否可见；
- short app-usage rows 是否合并为 display-only summary；
- selected day 或 last seven days；
- Unified / Chronological / By Category；
- Project / Device grouping；
- Idle visibility；
- device filter；
- horizontal / vertical orientation；
- date range、working-hours zoom 和 wrap boundary。

## 7. Projects、Time Entries、Timer 与计费

### 7.1 Project model

项目位于：

```text
~/Library/Application Support/Metriday/Projects.json
```

已实现：

- top-level / nested child project；
- rename、recolor、archive、restore；
- hierarchy cycle prevention；
- sort order、alphabetical descendant reorder；
- productivity weight；
- notes / metadata；
- project rule：application、bundle、title、title-or-path、file path、URL/path、domain、full URL、keyword、device、time range、day-of-week；
- first-match priority arrows 和 Reapply；
- project team ownership；
- billing default inheritance、hourly rate、currency；
- Standard / Darker top-level color scheme、Inherited / Similar / Rainbow child color scheme。

Project color 是 identity metadata，不会取代 App / Website / Item Category color。

### 7.2 Time Entry 与 Timer

Time Entries 和 Timer 状态位于：

```text
~/Library/Application Support/Metriday/TimeEntries.json
```

- Manual Time Entry 与 non-manual Timer 共享报告、Review、Today、Activities 统计；running Timer 以 live entry materialize，但停止前不落地普通 entry。
- Billing status：Billable、Not billable、Pending、Billed、Paid、Undetermined。
- 新 entry 和 timer 根据项目继承的 billing default 初始化。
- Overlap replacement 仅替换目标范围，保留前后片段；Entry-O-Matic undo 原子还原。
- title suggestions 来自历史 entries、projects 和 Calendar events。
- `$billable`、`$billed`、`$paid`、`$undetermined` 快捷方式可在标题字段中选择 billing status。
- 同 title 的多个 entry 支持 Edit Title for All Occurrences；单条编辑仍可修改时间、notes、project、billing。
- Timer 支持最近一次 timer 快速恢复、估计时长、±1/±5/±15 分钟起点调整、上一条 entry boundary 对齐、estimate check-in、remaining time。
- Start Timer 可从 Today、Activities、Project context、菜单栏、URL scheme、AppleScript、API、Focus Block 进入。
- 全局快捷键 `⌃⌥⌘T` Quick Start Timer；`⌘⇧T` Tracking pause/resume。

## 8. Focus Session 与网页阻断

### 已实现的入口

- Global Header 当前 Block 的 Start/Resume/Pause Focus；
- Plan / Today Time Block 选中或 hover 后的 Start/Pause Focus；
- Activities timer/context action；
- 菜单栏 Focus control；
- Web companion 对应入口；
- API：`/v1/focus/session/start[?task_id=UUID]`、`/v1/focus/session/stop`；
- URL scheme 和 AppleScript timer 入口共用 Focus-aware lifecycle。

### 生命周期

- 启动当前 Markdown Block 会创建带计划时长的 Timer，并激活 blocklist。
- Pause 会停止 Timer、释放 blocklist；Resume 会扣除已关联的实际执行区间，不重置原估计。
- 计划时长结束后切换为 open-ended timer，显示 `In progress`，不把 countdown 重置。
- 计时器 custom fields 保存 plan task ID 和 plan date；relaunch 后恢复 daily Markdown context、选中对应 Block，并恢复 blocklist。
- 如果启用 sleep stop，Mac sleep 会自动释放 Focus state。
- Global Header、菜单栏显示 second-level remaining / `left` / `Over by`，普通 Timer 与 Focus Timer 的优先级明确。

### 当前边界

网页阻断 MVP 只检查前台 Safari/Chrome tab，通过 macOS Automation permission 将 blocklisted domain redirect 到本地 Focus page。尚未实现 system-wide Network Extension。

独立 Timing 风格 floating Focus companion 已作为原生 `NSPanel` 接入；它只展示并控制现有 Focus/Timer 状态，不创建第二套 Timer 或 activity store。关闭按钮和 Hide Companion 只隐藏窗口，Pause/Stop 才结束当前会话。

## 9. Today、Stats、Review、Reports、Teams

### Today

Today 是 execution-observability surface：展示计划与实际 timeline、当前 Block、Focus state、Blocklist、App/Website evidence、Idle、Time Entry、Calendar Event 和 task relevance。Time Block detail 能在同一对象内显示 planned range、actual intervals、focused/distraction quality 和 evidence。

### Stats

Stats 已有 selected-week/time range 数据：

- total active time；
- productivity score / pulse；
- related / distraction / other / idle breakdown；
- weekday chart；
- hourly chart；
- category stacked chart；
- time per project；
- top applications；
- relative/custom range；
- project scope 和 multi-project selection；
- Projects & Time Entries hierarchy。

最近实现的 Stats hierarchy：Project → Title group → clipped Time Entry range。项目和标题默认可控展开，entry row 可跳回 Activities 对应日期。

### Review

Review 使用同一套 local activity、Screen Time、project、time-entry stores，提供 planned-vs-actual、category pulse、project billing、Smart Activity Summary 和 report builder 入口。Smart Activity Summary 是 deterministic/local-only：dominant application、longest related stretch、largest distraction、imported device time 都带 source range 和 duration，不向模型或网络发送活动内容。

### Reports

Report Builder 已支持：

- Easy / Advanced mode；
- custom date range、This week、Last 7 days、This month；
- include App Usage、Time Entries 或 both；
- absorb covered App Usage；
- short-entry filter；
- Project / Application / Document / Hour / Day / Week / Month / Year / Week+Day 等 grouping；
- project hierarchy、billing status filter、rounding、duration format；
- columns 选择；
- CSV、XLSX、JSON、HTML、PDF export；
- project rate / billing amount；
- Screen Time device provenance；
- cross-midnight Time Entry 按报告日 clip，不重复计时。

最近的 Reports parity 功能：主 Reports 页面已从扁平 project total 扩展为 Timing 风格可展开的 `Project → Title → Entry` outline；entry 明细可跳回 Activities。为了避免每秒 activity sample 触发历史报告树重建，outline 在进入 Reports 或切换日期时缓存，实时 tracking 仍更新顶部统计卡片。

### Teams

Teams 使用本地 stable member IDs、team ownership、project counts 和 tracked totals；team archive 参与 Timing Sync，项目 team ID 在 merge 时重映射。个人项目仍是默认，普通 activity 数据不暴露团队成员。

## 10. Calendar、Reminders、Phone Calls、Screen Time

### Calendar

- EventKit 默认只读；无权限时其余本地追踪仍可用。
- Calendar Event 以独立样式进入 Plan / Today / Activities 时间线。
- moved、renamed、cancelled 事件监听刷新。
- 详情显示 calendar、location、notes、range。
- Record Time Entry 是显式动作，不自动启动 Timer、不写 Markdown。
- Convert to Time Block 是单独显式动作，会生成 `#calendar` Markdown task，并保存 event identifier link。
- Web Plan / Today 通过 local API 使用同一 Calendar bridge。

### Reminders / Phone Calls / Screen Time

这些是可选 source，均有权限 gated UI、connection status、Native/Web 对应状态，不会成为本地核心 tracking 的硬依赖。Screen Time 使用 archive 处理 retention window；Phone Calls 支持 database availability 和号码隐藏；Reminders 作为 completed task/title suggestion source。

## 11. Rules、Filters、Exclusions 与 Categories

### Rules

Rules 可以从 activity 创建，也可以手动创建；匹配字段包含 application、bundle、title、title-or-path、file path、URL/path、domain、full URL、keyword、device、start-time、day-of-week。操作包含 contains、exact、prefix、suffix、wildcard、not-equal、time-range 和 regex。keyword 按单词匹配，`art` 不匹配 `article`；`||` 和 `&&` 可组合简单 token；priority arrows 改变 first-match order。

### Saved Filters

Filters 位于 `Filters.json`，和 Projects 独立。支持 any/all 规则，以及 application、bundle、window title、URL/path、domain、full URL、keyword、device、start-time、day-of-week；支持导入、导出、PATCH/PUT API。

### Exclusions

Exclusions 位于 `Exclusions.json`，在 segment 创建前过滤匹配的应用、bundle、title、URL/path、domain、full URL 或 device。旧的 bare bundle-ID JSON 仍可读取。

### Categories

Categories 位于 `ActivityCategories.json`，可在 Activities display settings 管理。App、Website、Item 是独立 rule source，first-match priority 可调整；Native、Web、Stats、Today、Review、Reports 使用同一 effective category 和颜色语义。

## 12. Settings、权限、同步与本地 API

### Settings

已实现偏好包括：

- idle threshold；
- weekend tracking；
- overnight-capable working hours；
- working-hours automatic timeline zoom；
- `Wrap days at`；
- launch tracking；
- sleep 时停止 Timer；
- login item；
- Accessibility / Automation / Full Disk Access / Calendar / Reminders / Phone Calls 状态；
- device name；
- Activity display settings；
- local data export/import；
- Project、Filter、Category、Rules、Exclusion、Time Entry、Screen Time archive 管理；
- Review reminder interval 和 notification authorization。

### Timing Sync

Settings 可配置共享目录（iCloud Drive、Dropbox、NAS 等）。每台设备写入 `devices/<device-id>.json`、`manifest.json` 和 rolling `backups/`，merge：

- Projects / hierarchy / team IDs；
- Filters / Categories / Rules / Exclusions；
- Time Entries；
- local Activity history；
- archived Screen Time；
- Focus website rules；
- Markdown daily plans；
- Task identity sidecars；
- Calendar Event links。

最近 30 个 snapshot 保留，restore 前会先写安全备份；Project IDs 和 linked task IDs 在跨设备导入时重映射。

### Local API

原生 app 提供 loopback-only：

```text
http://127.0.0.1:8765/v1
```

主要资源：`status`、`plans`、`activities`、`phone-calls`、`insights`、`reports`、`time-entries`、`projects`、`filters`、`exclusions`、`preferences`、`calendar-events`、`teams`、`sync`、`tracking`、`timer`、`focus/session`。

报告导出支持 CSV/XLSX/JSON/HTML/PDF；activities 支持删除 tombstone，防止 Screen Time refresh 或 sync import resurrect；Timer 支持 start/stop/adjust/estimate；Plan 支持按日期完整读写 Markdown。

对 Timing public resource vocabulary 提供 `/api/v1` aliases，包括 projects、project hierarchy、teams、activity hierarchy、time entries、batch update、archived projects、mobile-device inclusion 和 line-budgeted plain-text hierarchy。

### URL scheme / AppleScript

URL scheme 例子：

```text
metriday://tracking/pause
metriday://tracking/resume
metriday://timer/start?title=Deep%20work&project=Research
metriday://timer/stop
metriday://entry/add?title=Meeting&minutes=30
metriday://phone-calls/hide?address=555-0100&hidden=false
```

原生 app 同时带 Cocoa AppleScript dictionary，可 start/stop timer、pause/resume tracking、add entry、query summary、list projects、export report。

## 13. Web companion

根目录 Vite app 是 API-backed companion，不是 WebView：

- 默认连接 `http://127.0.0.1:8765`；可由 Settings、`window.__METRIDAY_API_BASE__` 或 `VITE_METRIDAY_API_BASE` 改写。
- 有 offline shell / PWA install guidance。
- 无 API 时保留 visual preview，并明确显示 connection state。
- Today、Activities、Review、Stats、Reports、Plan、Projects、Rules、Settings 与原生数据模型对齐。
- 可执行日期切换、Plan Markdown 写入、Time Entry create/delete、Project / billing 编辑、Timer start/stop、Focus blocklist 操作、Rules 管理、sync 状态和报告导出。
- Web Plan 与 Native Plan 共用 Calendar bridge、Task identity sidecar 和 drop modifier 语义。
- Web 与 Native 都支持多项目 scope、project-context Start Timer、Time Block Start/Pause Focus 和 planned-vs-actual evidence。

## 14. 关键数据文件

| 文件 | 作用 |
| --- | --- |
| `Calendar/YYYY-MM-DD.md` | Markdown 计划和 Time Block 文本源 |
| `TaskIdentities.json` | Markdown task 的稳定内部 identity |
| `Activity/YYYY-MM-DD.json` | 本地 App/Website/Window/Idle 采样 |
| `Projects.json` | Project hierarchy、规则、颜色、billing、team |
| `TimeEntries.json` | Time Entry、Timer、Focus-linked execution |
| `Filters.json` | Saved activity filters |
| `ActivityCategories.json` | App/Website/Item 分类和颜色 |
| `Exclusions.json` | segment 创建前的排除规则 |
| `Preferences.json` | tracker、wrap、display、sleep、device 等偏好 |
| `ScreenTime/` | Screen Time archive |
| Timing Sync folder | device snapshot、manifest、backups、合并数据 |

所有用户层数据默认 local-first；没有登录、网络或远程账号也能完成 Plan、Activities、Stats、Review、Reports、Focus 和本地导出。

## 15. v1 验证记录

最近一轮 Reports 实现的证据：

- `swift build`：通过；
- `MetridayMac/Scripts/run_smoke_tests.sh`：通过；
- `MetridayMac/Scripts/package_app.sh`：通过，Release app 生成于 `MetridayMac/build/Metriday.app`；
- macOS AX runtime：Reports 能在真实历史数据下进入并显示项目层级；
- 项目展开后显示 Title 分组；
- Title 展开后显示 App Usage / Time Entry / Timer 明细；
- 明细点击能切换到对应日期并打开 Activities；
- 初始只渲染项目行，报告树按层级惰性展开并在进入/切换日期时缓存，避免活动每秒采样导致 Reports 主线程持续重算；
- `git diff --check`：通过；
- 最新提交已 push 到 `origin/main`。

历史开发中也持续使用原生 smoke tests、AX identifiers、运行态截图和前后对照 Timing.app 进行验证。需要注意：本文件收尾时没有重新执行根目录 Web Sites handoff 流程；Web 功能已有历史实现，但下一轮若修改 Web / Sites 相关文件，应重新运行 `npm run build` 和 `npm run test:sites`。

## 16. 版本与主要提交线索

仓库共有 426 个开发提交，当前主线从 NotePlan 原型逐步演进为 Timing parity build。可按以下阶段定位历史：

- `ab8ae1f`：NotePlan basic foundation；
- `f748fc5`–`df0828d`：Timing parity foundation、Activities、Stats、Reports、Teams、RescueTime category semantics；
- `9815a4b`–`c0f075f`：Calendar/Reminders、Screen Time、project rules、Report Builder、native settings、sync、XLSX/PDF export；
- `9ec72f8`–`49d41d9`：Native workspace shell、Focus / Entry-O-Matic、Activities project/filter sidebar、timeline and Time Entry actions；
- `49d41d9`–`d1287e8`：Plan Markdown editor、live preview、task identity、Time Block、Calendar overlay、Today/Activities detail actions；
- `7.8` stream：Web/native interaction parity、date semantics、category color invariants、reports、project hierarchy、billing、hit targets；
- `8.139`–`8.168` stream：Quick Start Timer、Project Drop Zone、timeline drag/resize、menu bar preferences、timer controls、full-row hit targets、performance fixes、horizontal project lane、Stats hierarchy、Reports outline。

本次 v1 收尾文档本身不修改产品代码；只应单独 commit `doc/0821_v1_impl_timing_reproduce.md`，保留 `doc/` 中其他已有的未跟踪思路文档。

## 17. 下一轮实现方案（新对话起点）

新对话不需要重新盘点基础设施，直接以本文件和当前 HEAD 为基线。建议顺序：

### Phase A：完成 Timing 1:1 的 Focus companion（已完成）

- 已用 Computer Use 对照本机 Timing.app 的 Timer 入口和运行状态，确认 companion 的独立展示需求。
- 已实现单窗口 native AppKit/SwiftUI `NSPanel` prototype，尺寸约 372×248，可调整大小并保持 floating level。
- 已复用现有 AppState / TimeEntryStore / Focus lifecycle，没有创建第二套 Timer 或 activity store。
- 已接入 Global Header、菜单栏、Plan/Today Time Block 详情和 Focus menu；Focus 启动时自动显示 companion。
- 已实现拖动、always-on-top、隐藏不停止 Focus；Pause 保留可 Resume 的 Markdown Block 上下文，Stop 才结束并清除会话。
- 已实现当前 Timer、planned duration、remaining/overdue、Focused/Distracting/Other、blocklist 状态和菜单动作。
- 已通过 `swift build`、`Scripts/run_smoke_tests.sh`、`Scripts/package_app.sh` 和 Native runtime AX 验证。

### Phase B：把 companion 变成可验证的 Focus surface（已完成）

- companion 已实时显示 Timer/Focus 的 remaining、open-ended、Paused 和 Over by 状态；
- 已显示当前 Markdown Block、project context、planned range、actual accumulated time 和 interval count；
- 已显示 Focused、Distracting、Other、Idle 的短条与百分比；
- 已区分 blocklist ready、active、blocked domain 和 permission required；
- 已提供 Stop、Pause、Resume、Open Metriday、Open Rules、Open current Block；
- Pause 会保留同一 Markdown Block 的暂停上下文，Resume 按已累计实际时间扣减计划时长，Stop 才清除暂停上下文；
- Native 与 Web 共用 pause/resume API，状态通过 focusPaused、paused task ID 和 plan date 传播；
- 已通过 swift build、Scripts/run_smoke_tests.sh、Scripts/package_app.sh 和本地 API start → pause → resume → stop 生命周期验证；已在解锁后的真实 macOS 窗口完成 AX 验收：Plan Time Block 启动、companion 展示、Hide 不停止、Global Header 重开、Pause/Resume、Open Block、菜单动作和 Stop 后清除 Focus 状态。

### Phase C：之后再补硬化与差异化改进

- Network Extension system-wide blocker（需要 entitlements / signed distribution）；
- richer Calendar Event conversion and conflict model；
- report preview 与导出列完全同步；
- larger-data performance profiling and incremental report index；
- Focus quality history、daily/weekly Focus analytics；
- optional cross-device hosted sync，不改变 local-first baseline。

新对话第一步应先读取本文件和 `MetridayMac/README.md`，再打开 Timing 的 Focus/Session companion 对照运行态，避免直接凭记忆实现。

## 18. 常用验证命令

```bash
cd /Users/andyzhao/Projects/Metriday/MetridayMac
swift build
Scripts/run_smoke_tests.sh
Scripts/package_app.sh

cd /Users/andyzhao/Projects/Metriday
npm run build
npm run test:sites
git diff --check
```

原生 app 包：

```text
/Users/andyzhao/Projects/Metriday/MetridayMac/build/Metriday.app
```

收尾时的原则仍然是：Timing.app 是功能基线，Metriday 的 Markdown-first、Calendar read-only、解释性 planned-vs-actual、local-first 和 category-owned color 是有记录的 deliberate extensions；任何新功能都要先保持熟悉的 Timing 行为，再增加可解释的改进。
