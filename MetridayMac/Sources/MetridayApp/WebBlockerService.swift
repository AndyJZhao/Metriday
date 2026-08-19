import AppKit
import Combine
import Foundation

@MainActor
final class WebBlockerService: ObservableObject {
    @Published var isActive = false {
        didSet { isActive ? startMonitoring() : stopMonitoring() }
    }
    @Published private(set) var status = "Blocklist ready"
    @Published private(set) var lastBlockedDomain: String?
    @Published private(set) var rules: [WebRule]

    private var timer: Timer?
    private let defaultsKey = "metriday.web-rules.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([WebRule].self, from: data) {
            rules = saved
        } else {
            rules = [
                WebRule(domain: "youtube.com"),
                WebRule(domain: "reddit.com"),
                WebRule(domain: "x.com"),
                WebRule(domain: "news.ycombinator.com")
            ]
        }
    }

    var blockedRules: [WebRule] { rules.filter { !$0.isAllowed } }
    var allowedRules: [WebRule] { rules.filter(\.isAllowed) }

    func add(domain rawDomain: String, allowed: Bool = false) {
        let domain = DomainRuleMatcher.normalizedDomain(rawDomain)
        guard !domain.isEmpty, !rules.contains(where: { $0.domain == domain && $0.isAllowed == allowed }) else { return }
        rules.append(WebRule(domain: domain, isAllowed: allowed))
        persist()
        status = allowed ? "Allowed site added" : "Blocked site added"
    }

    func remove(_ rule: WebRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
        status = "Rule removed"
    }

    func setAllowed(_ rule: WebRule, allowed: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isAllowed = allowed
        persist()
        status = allowed ? "Site allowed during focus" : "Site returned to blocklist"
    }

    static func shouldBlock(host rawHost: String, rules: [WebRule]) -> Bool {
        DomainRuleMatcher.shouldBlock(host: rawHost, rules: rules)
    }

    static func normalizedDomain(_ rawValue: String) -> String {
        DomainRuleMatcher.normalizedDomain(rawValue)
    }

    func importRules(_ importedRules: [WebRule]) {
        var merged = rules
        for imported in importedRules where !merged.contains(where: {
            $0.domain == imported.domain && $0.isAllowed == imported.isAllowed
        }) {
            merged.append(imported)
        }
        rules = merged
        persist()
        status = "Imported \(importedRules.count) focus rules"
    }

    private func startMonitoring() {
        guard timer == nil else { return }
        status = "Research Focus active · Safari and Chrome monitored"
        inspectFrontBrowser()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.inspectFrontBrowser() }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        status = "Blocklist ready"
    }

    private func inspectFrontBrowser() {
        guard let browser = currentBrowserURL(),
              let url = URL(string: browser.url),
              let host = url.host,
              Self.shouldBlock(host: host, rules: rules) else { return }
        redirect(browser: browser.name, blockedHost: host)
    }

    private func currentBrowserURL() -> (name: String, url: String)? {
        let script = #"""
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
        end tell
        if frontApp is "Safari" then
            tell application "Safari" to return "Safari||" & URL of current tab of front window
        else if frontApp is "Google Chrome" then
            tell application "Google Chrome" to return "Google Chrome||" & URL of active tab of front window
        end if
        return ""
        """#
        var error: NSDictionary?
        guard let value = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              !value.isEmpty else {
            if let error { status = "Browser automation needs permission: \(error[NSAppleScript.errorMessage] ?? "Unknown error")" }
            return nil
        }
        let parts = value.components(separatedBy: "||")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private func redirect(browser: String, blockedHost: String) {
        let page = """
        <html><head><meta name='viewport' content='width=device-width'><style>body{font-family:-apple-system;background:#f7f8fc;color:#20222a;display:grid;place-items:center;height:100vh;margin:0}.card{max-width:560px;padding:48px;border:1px solid #dfe2ea;border-radius:24px;background:white;text-align:center}h1{font-size:32px;margin:16px}.shield{font-size:46px;color:#4f63ef}p{color:#656b78;line-height:1.6}</style></head><body><div class='card'><div class='shield'>Focus</div><h1>Research Focus is active</h1><p>\(blockedHost) is blocked during this time block. Return to GeneZip rebuttal experiment.</p></div></body></html>
        """
        guard let encoded = page.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let blockedURL = "data:text/html;charset=utf-8,\(encoded)"
        let escapedURL = blockedURL.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source: String
        if browser == "Safari" {
            source = "tell application \"Safari\" to set URL of current tab of front window to \"\(escapedURL)\""
        } else {
            source = "tell application \"Google Chrome\" to set URL of active tab of front window to \"\(escapedURL)\""
        }
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            status = "Could not redirect blocked page: \(error[NSAppleScript.errorMessage] ?? "Unknown error")"
        } else {
            lastBlockedDomain = Self.normalizedDomain(blockedHost)
            status = "Blocked \(blockedHost) · Research Focus active"
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
