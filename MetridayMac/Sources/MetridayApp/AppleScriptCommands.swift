import AppKit
import Foundation

/// The native AppleScript surface mirrors the local URL/API automation surface.
/// Commands are delivered by Cocoa's scripting system on the application's main
/// actor, so they can safely use the same stores as the SwiftUI UI.
@MainActor
final class MetridayAppleScriptRuntime {
    static var appState: AppState?
}

final class MetridayStartTimerCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let requestedTitle = arguments["title"] as? String
        let projectName = arguments["project"] as? String
        let notes = arguments["notes"] as? String ?? ""
        let billingRawValue = arguments["billing status"] as? String
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            let title = requestedTitle
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ?? state.currentTask?.title
                ?? "Manual timer"
            let projectID = projectName
                .flatMap { projectName in
                    state.projectStore.projects.first(where: { $0.name == projectName })?.id
                }
            let billingStatus = billingRawValue
                .flatMap(scriptBillingStatus)
                ?? .billable
            state.timeEntryStore.startTimer(
                title: title,
                projectID: projectID,
                notes: notes,
                startedAt: .now,
                billingStatus: billingStatus
            )
            guard let timer = state.timeEntryStore.runningTimer else {
                scriptError("Timer could not be started")
                return nil
            }
            return timer.id.uuidString
        }
    }
}

final class MetridayStopTimerCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            return state.timeEntryStore.stopTimer() != nil
        }
    }
}

final class MetridayPauseTrackingCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            if state.activityMonitor.isTracking { state.activityMonitor.stop() }
            return true
        }
    }
}

final class MetridayResumeTrackingCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            if !state.activityMonitor.isTracking { state.activityMonitor.start() }
            return true
        }
    }
}

final class MetridayAddTimeEntryCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let start = arguments["from"] as? Date
        let end = arguments["to"] as? Date
        let title = arguments["title"] as? String ?? "Manual time entry"
        let projectName = arguments["project"] as? String
        let notes = arguments["notes"] as? String ?? ""
        let billingRawValue = arguments["billing status"] as? String
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            guard let start,
                  let end,
                  end > start else {
                scriptError("add time entry needs a valid from and to date")
                return nil
            }
            let projectID = projectName
                .flatMap { projectName in
                    state.projectStore.projects.first(where: { $0.name == projectName })?.id
                }
            let billingStatus = billingRawValue
                .flatMap(scriptBillingStatus)
                ?? .billable
            guard let id = state.timeEntryStore.addEntry(
                title: title,
                projectID: projectID,
                notes: notes,
                start: start,
                end: end,
                billingStatus: billingStatus
            ) else {
                scriptError("Time entry could not be created")
                return nil
            }
            return id.uuidString
        }
    }
}

final class MetridayGetTimeSummaryCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let requestedDate = arguments["date"] as? Date
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            let date = Calendar.current.startOfDay(for: requestedDate ?? .now)
            let segments = state.activityMonitor.segments(for: date) + state.screenTimeStore.segments(for: date)
            let summary = ActivitySummary(segments: segments)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            let entries = state.timeEntryStore.materializedEntries().filter {
                $0.start < dayEnd && $0.end > date
            }
            let clippedEntrySeconds = entries.reduce(0) { total, entry in
                let clippedStart = max(entry.start, date)
                let clippedEnd = min(entry.end, dayEnd)
                return total + max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
            }
            var result: [String: Any] = [
                "date": date,
                "tracked seconds": segments.reduce(0) { $0 + $1.durationSeconds },
                "active seconds": summary.relatedDurationSeconds + summary.distractedDurationSeconds + summary.otherDurationSeconds,
                "related seconds": summary.relatedDurationSeconds,
                "distracted seconds": summary.distractedDurationSeconds,
                "idle seconds": summary.idleDurationSeconds,
                "task related percentage": summary.taskRelatedPercentage,
                "time entry seconds": clippedEntrySeconds,
                "time entry count": entries.count
            ]
            if let timer = state.timeEntryStore.runningTimer {
                result["running timer"] = [
                    "id": timer.id.uuidString,
                    "title": timer.title,
                    "started at": timer.startedAt,
                    "duration seconds": state.timeEntryStore.runningDurationSeconds
                ]
            }
            return result
        }
    }
}

final class MetridayListProjectsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            return state.projectStore.activeProjects.map { project in
                [
                    "id": project.id.uuidString,
                    "name": project.name,
                    "parent id": project.parentID?.uuidString ?? "",
                    "archived": project.isArchived,
                    "productivity": project.productivity,
                    "billing status": project.defaultBillingStatus.rawValue,
                    "billing rate": project.billingRate,
                    "currency": project.currency
                ]
            }
        }
    }
}

final class MetridayExportReportCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let requestedStart = arguments["from"] as? Date
        let requestedEnd = arguments["until"] as? Date
        let requestedFormat = arguments["format"] as? String
        let requestedPath = arguments["path"] as? String
        return onMain { () -> Any? in
            guard let state = MetridayAppleScriptRuntime.appState else {
                scriptError("Metriday is not ready")
                return nil
            }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: requestedStart ?? .now)
            let end = calendar.startOfDay(for: requestedEnd ?? requestedStart ?? .now)
            let firstDate = min(start, end)
            let lastDate = max(start, end)
            let dates = scriptDates(from: firstDate, through: lastDate)
            let activityDays = dates.map { date in
                (date: date, segments: state.activityMonitor.segments(for: date) + state.screenTimeStore.segments(for: date))
            }
            let reportEnd = calendar.date(byAdding: .day, value: 1, to: lastDate) ?? lastDate
            let entries = state.timeEntryStore.materializedEntries().filter {
                $0.start < reportEnd && $0.end > firstDate
            }
            let format = scriptReportFormat(requestedFormat)
            let destination: URL
            if let requestedPath, !requestedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destination = URL(fileURLWithPath: requestedPath)
            } else {
                destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("metriday-report-\(UUID().uuidString)")
                    .appendingPathExtension(format.fileExtension)
            }
            do {
                try ReportExporter.write(
                    to: destination,
                    format: format,
                    activityDays: activityDays,
                    timeEntries: entries,
                    projectStore: state.projectStore,
                    options: ReportOptions()
                )
                return destination.path
            } catch {
                scriptError("Report could not be exported: (error.localizedDescription)")
                return nil
            }
        }
    }
}

private func onMain<T>(_ body: @MainActor () -> T) -> T {
    let result = ScriptResultBox<T>()
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            result.value = body()
        }
        return result.value!
    }
    DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            result.value = body()
        }
    }
    return result.value!
}

private final class ScriptResultBox<T>: @unchecked Sendable {
    var value: T?
}

private func scriptBillingStatus(_ rawValue: String) -> BillingStatus? {
    switch rawValue.lowercased().replacingOccurrences(of: " ", with: "_") {
    case "billable": return .billable
    case "not_billable", "notbillable": return .notBillable
    case "pending": return .pending
    case "billed": return .billed
    case "paid": return .paid
    default: return nil
    }
}

private func scriptDates(from start: Date, through end: Date) -> [Date] {
    let calendar = Calendar.current
    var dates: [Date] = []
    var cursor = calendar.startOfDay(for: start)
    let last = calendar.startOfDay(for: end)
    while cursor <= last, dates.count < 3_650 {
        dates.append(cursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return dates
}

private func scriptReportFormat(_ rawValue: String?) -> ReportFileFormat {
    switch rawValue?.lowercased() {
    case "excel", "xlsx": return .xlsx
    case "json": return .json
    case "html": return .html
    case "pdf": return .pdf
    default: return .csv
    }
}

@MainActor
private func scriptError(_ message: String) {
    let command = NSScriptCommand.current()
    command?.scriptErrorNumber = -1000
    command?.scriptErrorString = message
}
