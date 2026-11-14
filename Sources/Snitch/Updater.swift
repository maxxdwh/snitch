import AppKit

/// Lightweight update check against GitHub Releases. Unsigned apps can't self-install
/// updates, so we just tell people and send them to the download.
enum Updater {
    static let repo = "maxxdwh/snitch"
    private static let lastCheckKey = "lastUpdateCheck"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func checkInBackgroundIfDue() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check(manual: false) }
    }

    @MainActor static func check(manual: Bool) async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
            req.timeoutInterval = 10
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw URLError(.badServerResponse) }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            if isNewer(latest, than: currentVersion) {
                let alert = NSAlert()
                alert.messageText = "Snitch \(latest) is available"
                alert.informativeText = "You're on \(currentVersion). Download the new version and drag it into Applications to replace this one."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    let page = (json["html_url"] as? String).flatMap(URL.init(string:))
                    NSWorkspace.shared.open(page ?? URL(string: "https://github.com/\(repo)/releases/latest")!)
                }
            } else if manual {
                let alert = NSAlert()
                alert.messageText = "Snitch is up to date"
                alert.informativeText = "You have version \(currentVersion), the latest."
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } catch {
            guard manual else { return }
            let alert = NSAlert()
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "Check your internet connection and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
