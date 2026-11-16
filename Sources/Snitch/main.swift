import AppKit
import ServiceManagement
import SwiftUI

// `Snitch --dump` prints what the scanner sees and exits (handy for debugging).
if CommandLine.arguments.contains("--dump") {
    for i in Scanner.scan() {
        print("\(i.isProject ? "P" : "-") pid=\(i.pid) \(i.title) ports=\(i.ports) web=\(i.webPorts) exposed=\(i.exposed) mem=\(Format.bytes(i.memory)) up=\(Format.uptime(i.uptime)) cwd=\(i.cwd ?? "-")")
    }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--stop"), i + 1 < CommandLine.arguments.count,
   let pid = pid_t(CommandLine.arguments[i + 1]), let b = LibProc.basic(pid) {
    let sem = DispatchSemaphore(value: 0)
    Task { print("stopped:", await Killer.stop(pid: pid, expectedStart: b.startTime)); sem.signal() }
    sem.wait()
    exit(0)
}

// `Snitch --snapshot out.png [query]` renders the popover offscreen (for docs / visual checks).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let store = Store()
        store.refresh()
        let deadline = Date().addingTimeInterval(3)
        while !store.hasScanned && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                let host = NSHostingView(rootView: PopoverView(store: store).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    var hotkey: Hotkey?
    var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Snitch, local servers")
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: PopoverView(store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        store.onChange = { [weak self] in self?.updateTitle() }
        updateTitle()
        store.refresh()
        schedule(interval: 15)

        hotkey = Hotkey { [weak self] in self?.togglePopover() }
        Updater.checkInBackgroundIfDue()

        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(interval: 15) }
        }
    }

    /// Fast while the popover is open, lazy in the background (saves battery).
    func schedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refresh() }
        }
        timer?.tolerance = interval * 0.2
    }

    func updateTitle() {
        statusItem.button?.title = store.menuBarTitle
    }

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            statusItem.menu = buildMenu()
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        store.refresh()
        schedule(interval: 2)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Show Snitch", action: #selector(show), keyEquivalent: "").target = self
        m.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)

        let mem = NSMenuItem(title: "Show Memory in Menu Bar", action: #selector(toggleMemory), keyEquivalent: "")
        mem.target = self
        mem.state = store.showMemoryInMenuBar ? .on : .off
        m.addItem(mem)

        let notify = NSMenuItem(title: "Notify When a Server Starts", action: #selector(toggleNotify), keyEquivalent: "")
        notify.target = self
        notify.state = store.notifyOnNewServer ? .on : .off
        m.addItem(notify)

        m.addItem(.separator())
        m.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        let about = m.addItem(withTitle: "About Snitch \(Updater.currentVersion)", action: #selector(about), keyEquivalent: "")
        about.target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Snitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc func show() { togglePopover() }
    @objc func toggleMemory() { store.showMemoryInMenuBar.toggle() }
    @objc func toggleNotify() {
        store.notifyOnNewServer.toggle()
        if store.notifyOnNewServer { Notifier.requestAccess() }
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "Move Snitch into your Applications folder and try again."
            alert.runModal()
        }
    }
    @objc func checkUpdates() { Task { await Updater.check(manual: true) } }
    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
