import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var blocker: WebBlockerService
    @ObservedObject private var projectStore: ProjectStore
    @State private var newBlockedDomain = ""
    @State private var newAllowedDomain = ""
    @State private var showingRuleEditor = false

    init(blocker: WebBlockerService, projectStore: ProjectStore) {
        _blocker = ObservedObject(wrappedValue: blocker)
        _projectStore = ObservedObject(wrappedValue: projectStore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageDateHeader(title: "Rules", subtitle: "Freedom-style browser intervention, linked to the active time block")

                HStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 32))
                            .foregroundStyle(blocker.isActive ? MetridayTheme.success : MetridayTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Research Focus").font(.system(size: 17, weight: .bold))
                            Text(blocker.status).font(.system(size: 11)).foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        Toggle("Active", isOn: Binding(
                            get: { appState.focusIsActive },
                            set: { appState.focusIsActive = $0 }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .metridayPanel()

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Current scope", systemImage: "clock.badge.checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                        Text(appState.currentTask?.title ?? "No scheduled block")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(appState.currentTask?.timeRange ?? "No time") · Safari + Chrome")
                            .font(.system(size: 11))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .metridayPanel()
                }

                HStack(alignment: .top, spacing: 16) {
                    rulesPanel(
                        title: "Blocked websites",
                        subtitle: "Redirected while Research Focus is active",
                        rules: blocker.blockedRules,
                        input: $newBlockedDomain,
                        placeholder: "youtube.com",
                        add: {
                            blocker.add(domain: newBlockedDomain)
                            newBlockedDomain = ""
                        }
                    )

                    rulesPanel(
                        title: "Allowed websites",
                        subtitle: "Exceptions for research and task context",
                        rules: blocker.allowedRules,
                        input: $newAllowedDomain,
                        placeholder: "docs.example.com",
                        add: {
                            blocker.add(domain: newAllowedDomain, allowed: true)
                            newAllowedDomain = ""
                        }
                    )
                }

                projectRulesPanel

                VStack(alignment: .leading, spacing: 14) {
                    Label("How blocking works in this build", systemImage: "info.circle")
                        .font(.system(size: 14, weight: .bold))
                    Text("When a focus session is active, Metriday checks the frontmost Safari or Chrome tab. A matching domain is replaced with a local focus page. macOS asks for Automation permission the first time. The blocklist stays on this Mac and is never uploaded.")
                        .font(.system(size: 12))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineSpacing(4)
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(MetridayTheme.success)
                        Text("A future hardened mode can use an Apple Network Extension for system-wide enforcement; that target requires Apple-granted entitlements and code signing.")
                            .font(.system(size: 11))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                }
                .padding(20)
                .metridayPanel()
            }
            .padding(28)
        }
        .sheet(isPresented: $showingRuleEditor) {
            ProjectRuleEditorSheet(projects: projectStore.activeProjects) { projectID, field, comparison, pattern, caseSensitive in
                _ = projectStore.addRule(
                    projectID: projectID,
                    field: field,
                    pattern: pattern,
                    isCaseSensitive: caseSensitive,
                    comparison: comparison
                )
                showingRuleEditor = false
            }
        }
    }

    private var projectRulesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project automation rules")
                        .font(.system(size: 16, weight: .bold))
                    Text("Rules assign future app, title, domain, URL, path, keyword, start-time, or day-of-week activity to projects.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button {
                    showingRuleEditor = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("rules.new-project-rule")
            }
            .padding(18)

            Divider()

            if projectStore.rules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No project rules yet")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Assign an activity in Activities, then use the wand button to create a reusable rule.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                .padding(18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(projectStore.rules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(MetridayTheme.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(projectStore.name(for: rule.projectID))
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(rule.field.label) \(rule.comparison.label) · \(rule.pattern)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            Spacer()
                            VStack(spacing: 2) {
                                Button {
                                    projectStore.moveRule(rule, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                Button {
                                    projectStore.moveRule(rule, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == projectStore.rules.count - 1)
                            }
                            Button(role: .destructive) {
                                projectStore.removeRule(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        Divider().padding(.leading, 52)
                    }
                }
            }

            HStack {
                Label(
                    projectStore.statusMessage,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Button("Reapply to Today") {
                    appState.activityMonitor.reapplyRules(for: appState.selectedDate)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("rules.reapply-project-rules")
                Button("Reapply All History") {
                    appState.activityMonitor.reapplyRulesForAllStoredDays()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("rules.reapply-all-project-rules")
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private func rulesPanel(
        title: String,
        subtitle: String,
        rules: [WebRule],
        input: Binding<String>,
        placeholder: String,
        add: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(MetridayTheme.secondary)
            }
            .padding(18)

            Divider()

            if rules.isEmpty {
                Text("No sites yet")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        HStack(spacing: 12) {
                            Image(systemName: rule.isAllowed ? "checkmark.shield" : "nosign")
                                .foregroundStyle(rule.isAllowed ? MetridayTheme.success : MetridayTheme.danger)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.domain).font(.system(size: 13, weight: .medium))
                                Text(rule.isAllowed ? "Allowed during focus" : "Blocked during focus")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            Spacer()
                            Button {
                                blocker.setAllowed(rule, allowed: !rule.isAllowed)
                            } label: {
                                Image(systemName: rule.isAllowed ? "arrow.uturn.backward" : "checkmark")
                            }
                            .buttonStyle(.borderless)
                            Button(role: .destructive) { blocker.remove(rule) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        Divider().padding(.leading, 52)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(placeholder, text: input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .metridayPanel()
    }
}

private struct ProjectRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projects: [TrackingProject]
    let onSave: (UUID, ProjectRuleField, ProjectRuleComparison, String, Bool) -> Void

    @State private var projectID: UUID?
    @State private var field: ProjectRuleField = .application
    @State private var comparison: ProjectRuleComparison = .contains
    @State private var pattern = ""
    @State private var caseSensitive = false

    init(
        projects: [TrackingProject],
        onSave: @escaping (UUID, ProjectRuleField, ProjectRuleComparison, String, Bool) -> Void
    ) {
        self.projects = projects
        self.onSave = onSave
        _projectID = State(initialValue: projects.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Project Rule")
                .font(.system(size: 18, weight: .bold))

            Picker("Project", selection: $projectID) {
                Text("Choose a project").tag(nil as UUID?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }

            Picker("Match", selection: $field) {
                ForEach(ProjectRuleField.allCases) { value in
                    Text(value.label).tag(value)
                }
            }

            Picker("Relation", selection: $comparison) {
                ForEach(ProjectRuleComparison.allCases) { value in
                    Text(value.label).tag(value)
                }
            }

            TextField("Pattern or value", text: $pattern)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Toggle("Case sensitive", isOn: $caseSensitive)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Text("String rules are case-insensitive by default. Domain rules compare the browser host only; regex rules use the full candidate value.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(3)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Rule", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        projectID == nil
                            || pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        guard let projectID,
              !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave(projectID, field, comparison, pattern, caseSensitive)
        dismiss()
    }
}
