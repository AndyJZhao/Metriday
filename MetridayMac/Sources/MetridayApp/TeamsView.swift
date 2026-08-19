import SwiftUI

struct TeamsView: View {
    @ObservedObject var teamStore: TeamStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore

    @State private var newTeamName = ""
    @State private var selectedTeamID: UUID?
    @State private var newMemberName = ""
    @State private var newMemberEmail = ""

    init(
        teamStore: TeamStore,
        projectStore: ProjectStore,
        timeEntryStore: TimeEntryStore
    ) {
        self.teamStore = teamStore
        self.projectStore = projectStore
        self.timeEntryStore = timeEntryStore
        _selectedTeamID = State(initialValue: teamStore.activeTeams.first?.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageDateHeader(
                    title: "Teams",
                    subtitle: "Share projects and keep team ownership explicit"
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 25))
                            .foregroundStyle(MetridayTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Team workspace")
                                .font(.system(size: 17, weight: .bold))
                            Text("Team data stays local or follows the selected Sync folder. Personal activity remains on each device.")
                                .font(.system(size: 11))
                                .foregroundStyle(MetridayTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("New team name", text: $newTeamName)
                            .textFieldStyle(.roundedBorder)
                        Button("Create Team") {
                            if let teamID = teamStore.createTeam(name: newTeamName) {
                                selectedTeamID = teamID
                                newTeamName = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("teams.create")
                    }
                }
                .padding(18)
                .metridayPanel()

                if teamStore.activeTeams.isEmpty {
                    emptyState
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        teamList
                        teamDetail
                    }
                }

                Text(teamStore.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MetridayTheme.accent)
            }
            .padding(28)
        }
        .onChange(of: teamStore.activeTeams.map(\.id)) { _, ids in
            if let selectedTeamID, ids.contains(selectedTeamID) { return }
            selectedTeamID = ids.first
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.3")
                .font(.system(size: 30))
                .foregroundStyle(MetridayTheme.secondary)
            Text("No team yet")
                .font(.system(size: 15, weight: .bold))
            Text("Create a local team to associate projects and invite members. Metriday remains fully usable without a team.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("teams.empty")
    }

    private var teamList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Teams")
                .font(.system(size: 15, weight: .bold))
                .padding(16)

            Divider()

            ForEach(teamStore.activeTeams) { team in
                Button {
                    selectedTeamID = team.id
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "person.3")
                            .foregroundStyle(selectedTeamID == team.id ? MetridayTheme.accent : MetridayTheme.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name)
                                .font(.system(size: 12, weight: selectedTeamID == team.id ? .semibold : .regular))
                            Text("\(team.members.filter(\.isActive).count) members")
                                .font(.system(size: 10))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        if selectedTeamID == team.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(selectedTeamID == team.id ? MetridayTheme.accentSoft : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("teams.list")
    }

    private var teamDetail: some View {
        Group {
            if let selectedTeamID, let team = teamStore.team(selectedTeamID) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(team.name)
                                .font(.system(size: 17, weight: .bold))
                            Text("\(team.members.filter(\.isActive).count) members · \(teamProjectCount(team)) projects")
                                .font(.system(size: 11))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        Button("Archive") {
                            teamStore.archive(team)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(MetridayTheme.danger)
                    }

                    Divider()

                    Text("Add member")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("Name", text: $newMemberName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Email (optional)", text: $newMemberEmail)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            if teamStore.addMember(
                                to: team.id,
                                name: newMemberName,
                                email: newMemberEmail
                            ) != nil {
                                newMemberName = ""
                                newMemberEmail = ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(newMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    ForEach(team.members.filter(\.isActive)) { member in
                        HStack(spacing: 8) {
                            Image(systemName: member.id == teamStore.currentMemberID ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundStyle(MetridayTheme.secondary)
                            Text(member.name)
                                .font(.system(size: 11, weight: .medium))
                            if !member.email.isEmpty {
                                Text(member.email)
                                    .font(.system(size: 10))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            Text(member.role)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MetridayTheme.secondary)
                            Spacer()
                            if member.id != teamStore.currentMemberID {
                                Button {
                                    teamStore.removeMember(member.id, from: team.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove member")
                            }
                        }
                    }

                    Divider()

                    Text("Aggregate tracked: \(formatSeconds(teamTrackedSeconds(team)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MetridayTheme.accent)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .metridayPanel()
                .accessibilityIdentifier("teams.detail")
            } else {
                Text("Select a team")
                    .foregroundStyle(MetridayTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .metridayPanel()
            }
        }
    }

    private func teamProjectCount(_ team: MetridayTeam) -> Int {
        projectStore.activeProjects.filter { $0.teamID == team.id }.count
    }

    private func teamTrackedSeconds(_ team: MetridayTeam) -> Int {
        let projectIDs = Set(projectStore.activeProjects.filter { $0.teamID == team.id }.map(\.id))
        return timeEntryStore.materializedEntries()
            .filter { entry in
                guard let projectID = entry.projectID else { return false }
                return projectIDs.contains(projectID)
            }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = max(0, Int((Double(seconds) / 60.0).rounded()))
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
