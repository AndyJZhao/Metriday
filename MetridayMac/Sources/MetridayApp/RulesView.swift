import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var blocker: WebBlockerService
    @State private var newBlockedDomain = ""
    @State private var newAllowedDomain = ""

    init(blocker: WebBlockerService) {
        _blocker = ObservedObject(wrappedValue: blocker)
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
