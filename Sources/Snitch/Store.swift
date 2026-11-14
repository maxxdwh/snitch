import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [ServerItem] = []
    @Published private(set) var pressure: Scanner.Pressure = .normal
    @Published var message: String?
    @Published private(set) var stopping: Set<pid_t> = []
    @Published private(set) var hasScanned = false

    @AppStorage("showMemoryInMenuBar") var showMemoryInMenuBar = false { didSet { onChange?() } }
    @AppStorage("notifyOnNewServer") var notifyOnNewServer = false

    var onChange: (() -> Void)?

    private var knownPids: Set<pid_t> = []
    private var notifiedHogs: Set<pid_t> = []
    private var scanning = false

    var projects: [ServerItem] { items.filter(\.isProject) }
    var others: [ServerItem] { items.filter { !$0.isProject } }
    var projectMemory: UInt64 { projects.reduce(0) { $0 + $1.memory } }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        Task.detached(priority: .utility) {
            let result = Scanner.scan()
            let pressure = Scanner.memoryPressure()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanning = false
                self.apply(result, pressure: pressure)
            }
        }
    }

    private func apply(_ result: [ServerItem], pressure: Scanner.Pressure) {
        let isFirst = !hasScanned
        if result != items { items = result }
        if pressure != self.pressure { self.pressure = pressure }
        hasScanned = true
        stopping = stopping.filter { pid in result.contains { $0.pid == pid } }

        if notifyOnNewServer && !isFirst {
            for item in result where item.isProject && !knownPids.contains(item.pid) {
                Notifier.post(title: "\(item.title) started", body: Format.ports(item.webPorts.isEmpty ? item.ports : item.webPorts))
            }
            for item in result where item.isProject && item.memory > 2 * 1_073_741_824 && !notifiedHogs.contains(item.pid) {
                notifiedHogs.insert(item.pid)
                Notifier.post(title: "\(item.title) is using \(Format.bytes(item.memory))", body: "Open Snitch to stop it if you're not using it.")
            }
        }
        knownPids = Set(result.map(\.pid))
        onChange?()
    }

    // MARK: Actions

    func stop(_ item: ServerItem) {
        guard !item.isSystem else { return }
        stopping.insert(item.pid)
        Task {
            let ok = await Killer.stop(pid: item.pid, expectedStart: item.startTime)
            if !ok { flash("Couldn't stop \(item.title). Try again."); stopping.remove(item.pid) }
            refresh()
        }
    }

    func stopAllProjects() {
        for item in projects { stop(item) }
    }

    func open(_ item: ServerItem, port: Int? = nil) {
        guard let port = port ?? item.webPorts.first, let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ port: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port)", forType: .string)
        flash("Copied http://localhost:\(port)")
    }

    func reveal(_ item: ServerItem) {
        guard let cwd = item.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    static let editors: [(name: String, bundleID: String)] = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("VS Code", "com.microsoft.VSCode"),
        ("Zed", "dev.zed.Zed"),
        ("Windsurf", "com.exafunction.windsurf")
    ]

    var installedEditors: [(name: String, url: URL)] {
        Self.editors.compactMap { e in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleID).map { (e.name, $0) }
        }
    }

    func openInEditor(_ item: ServerItem, app: URL) {
        guard let cwd = item.cwd else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func flash(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if message == text { message = nil }
        }
    }

    var menuBarTitle: String {
        if showMemoryInMenuBar && !projects.isEmpty { return "🐀 \(Format.bytes(projectMemory))" }
        return "🐀"
    }
}

enum Notifier {
    private static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAccess() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
