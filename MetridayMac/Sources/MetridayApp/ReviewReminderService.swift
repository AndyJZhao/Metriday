import Combine
import Foundation
import UserNotifications

/// Sends the periodic activity-review notification offered by Timing.
///
/// The reminder is intentionally local and opt-in. It uses the same live
/// activity monitor that powers Today, Activities, and Review, so the
/// notification never invents a second total or uploads activity data.
@MainActor
final class ReviewReminderService: ObservableObject {
    @Published private(set) var notificationsAuthorized = false
    @Published private(set) var notificationStatus = "Notifications not requested"

    private let monitor: AppActivityMonitor
    private let preferences: PreferencesStore
    private let categoryStore: ActivityCategoryStore
    private let filterStore: ActivityFilterStore
    private let notificationCenter = UNUserNotificationCenter.current()
    private var timer: Timer?
    private var nextReminderAt: Date?
    private var lastNotifiedCallID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(
        monitor: AppActivityMonitor,
        preferences: PreferencesStore,
        categoryStore: ActivityCategoryStore,
        filterStore: ActivityFilterStore
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.categoryStore = categoryStore
        self.filterStore = filterStore

        preferences.$reviewReminderIntervalMinutes
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetSchedule()
            }
            .store(in: &cancellables)

        monitor.$isTracking
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetSchedule()
            }
            .store(in: &cancellables)

        monitor.$pendingCallInterval
            .sink { [weak self] interval in
                self?.handleCallInterval(interval)
            }
            .store(in: &cancellables)
    }

    func start() {
        guard timer == nil else { return }
        refreshAuthorizationStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        resetSchedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        nextReminderAt = nil
    }

    func requestAuthorization() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
                refreshAuthorizationStatus()
            } catch {
                notificationStatus = "Could not request notification access"
            }
        }
    }

    private func resetSchedule() {
        let intervalMinutes = max(0, min(24 * 60, preferences.reviewReminderIntervalMinutes))
        guard intervalMinutes > 0, monitor.isTracking else {
            nextReminderAt = nil
            return
        }

        nextReminderAt = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
        if !notificationsAuthorized {
            requestAuthorization()
        }
    }

    private func tick() {
        guard let nextReminderAt,
              preferences.reviewReminderIntervalMinutes > 0,
              monitor.isTracking else {
            return
        }
        guard Date() >= nextReminderAt else { return }

        postReminder()
        let intervalMinutes = max(1, min(24 * 60, preferences.reviewReminderIntervalMinutes))
        self.nextReminderAt = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
    }

    private func postReminder() {
        let date = Date()
        let segments = categoryStore.applyingCategories(
            to: monitor.segments(for: date),
            filterStore: filterStore,
            date: date
        )
        let summary = ActivitySummary(segments: segments)
        guard summary.totalMinutes > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Review your activities"
        content.body = "\(durationLabel(summary.activeMinutes * 60)) active today · \(summary.relatedMinutes)m focused · \(summary.distractedMinutes)m distracting."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "co.metriday.review-reminder",
            content: content,
            trigger: trigger
        )
        notificationCenter.add(request)
    }

    private func handleCallInterval(_ interval: CallInterval?) {
        guard let interval,
              preferences.callNotificationsEnabled,
              interval.durationSeconds >= 60,
              lastNotifiedCallID != interval.id,
              notificationsAuthorized else { return }
        lastNotifiedCallID = interval.id

        let content = UNMutableNotificationContent()
        content.title = "Record call time?"
        let title = interval.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = "\(title.isEmpty ? interval.appName : title) · \(durationLabel(interval.durationSeconds))"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "co.metriday.call-\(interval.id.uuidString)",
            content: content,
            trigger: trigger
        )
        notificationCenter.add(request)
    }

    private func refreshAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            let authorizationStatus = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.notificationsAuthorized = true
                    self.notificationStatus = "Notifications enabled"
                case .denied:
                    self.notificationsAuthorized = false
                    self.notificationStatus = "Notifications blocked in System Settings"
                case .notDetermined:
                    self.notificationsAuthorized = false
                    self.notificationStatus = "Notifications not requested"
                @unknown default:
                    self.notificationsAuthorized = false
                    self.notificationStatus = "Notification status unavailable"
                }
            }
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}
