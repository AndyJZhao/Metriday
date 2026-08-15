import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 236)
                .fixedSize(horizontal: true, vertical: false)
                .zIndex(2)

            Divider()

            VStack(spacing: 0) {
                GlobalTopHeader(store: appState.markdownStore)
                    .zIndex(2)
                Divider()

                Group {
                    switch appState.section {
                    case .today:
                        TodayView(store: appState.markdownStore)
                    case .plan:
                        PlanView()
                    case .review:
                        ReviewView()
                    case .rules:
                        RulesView(blocker: appState.blocker)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MetridayTheme.canvas)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(MetridayTheme.canvas)
        .tint(MetridayTheme.accent)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Metriday 日衡")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                Text("Local-first · On this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 48)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { appState.section = section }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 19, weight: .medium))
                                .frame(width: 24)
                            Text(section.rawValue)
                                .font(.system(size: 16, weight: appState.section == section ? .semibold : .regular))
                            Spacer()
                            if appState.section == section {
                                Capsule().fill(MetridayTheme.accent).frame(width: 3, height: 22)
                            }
                        }
                        .foregroundStyle(appState.section == section ? MetridayTheme.accent : MetridayTheme.graphite)
                        .padding(.horizontal, 15)
                        .frame(height: 52)
                        .background(appState.section == section ? MetridayTheme.accentSoft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.\(section.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider().padding(.horizontal, 16)

            VStack(spacing: 18) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([appState.markdownStore.fileURL])
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "laptopcomputer")
                        Text("Data on this Mac")
                        Spacer()
                        Circle().fill(MetridayTheme.success).frame(width: 8, height: 8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.data")

                Button {
                    appState.section = .rules
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.settings")
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MetridayTheme.success)
                    Text("Markdown synced")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(MetridayTheme.secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(MetridayTheme.secondary)
            .padding(20)
        }
        .background(MetridayTheme.sidebar)
    }
}

struct GlobalTopHeader: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(dateTitle)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 12) {
                    Button {
                        appState.section = .plan
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .buttonStyle(.plain)
                    .help("Open Plan")

                    Button("Today") { appState.goToToday() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("header.today")

                    Button { appState.moveSelectedDate(byDays: -1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("header.previous-day")

                    Button { appState.moveSelectedDate(byDays: 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("header.next-day")
                }
                .foregroundStyle(MetridayTheme.secondary)
            }
            .frame(width: 250, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current block")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                    Text(appState.currentTask?.title ?? "No scheduled block")
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(blockSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appState.focusIsActive ? MetridayTheme.accent : MetridayTheme.secondary)
                }
                .frame(width: 210, alignment: .leading)

                Button {
                    appState.focusIsActive.toggle()
                } label: {
                    Label(
                        appState.focusIsActive ? "Pause focus" : "Resume focus",
                        systemImage: appState.focusIsActive ? "pause.fill" : "play.fill"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.currentTask == nil)
                .accessibilityIdentifier("header.focus")

                Divider().frame(height: 50)

                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 30))
                        .foregroundStyle(MetridayTheme.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Research Focus").font(.system(size: 13, weight: .semibold))
                        Text(appState.focusIsActive ? "Blocklist active" : "Blocklist ready")
                            .font(.system(size: 11))
                            .foregroundStyle(MetridayTheme.secondary)
                        Button("Adjust allowed sites") { appState.section = .rules }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(MetridayTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 90)
            .metridayPanel(radius: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(.white)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: appState.selectedDate)
    }

    private var blockSubtitle: String {
        guard let task = appState.currentTask, let range = task.timeRange else {
            return store.fileURL.lastPathComponent
        }
        return "\(range)  ·  \(appState.focusIsActive ? "In progress" : "Ready")"
    }
}

struct PageDateHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MetridayTheme.secondary)
                }
            }
            Spacer()
        }
    }
}
