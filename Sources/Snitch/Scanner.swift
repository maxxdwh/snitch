import Foundation

/// Finds every TCP listener owned by the current user. Runs off the main thread.
enum Scanner {
    static func scan() -> [ServerItem] {
        let me = getuid()
        var basics: [pid_t: LibProc.Basic] = [:]
        var children: [pid_t: [pid_t]] = [:]
        for pid in LibProc.allPids() {
            guard let b = LibProc.basic(pid), b.uid == me else { continue }
            basics[pid] = b
            children[b.ppid, default: []].append(pid)
        }

        var items: [ServerItem] = []
        for (pid, b) in basics where pid != getpid() {
            let endpoints = LibProc.listeningEndpoints(pid)
            guard !endpoints.isEmpty else { continue }

            let ports = endpoints.map(\.port)
            let args = LibProc.arguments(pid)
            let cwd = LibProc.cwd(pid)
            let info = Naming.describe(name: b.name, args: args, cwd: cwd, ports: ports)

            var memory = LibProc.footprint(pid)
            for d in descendants(of: pid, in: children) { memory += LibProc.footprint(d) }

            items.append(ServerItem(
                pid: pid, startTime: b.startTime, title: info.title, framework: info.framework,
                folder: info.folder, cwd: cwd, ports: ports,
                webPorts: (info.kind == .web && info.isProject) ? ports : [],
                exposed: endpoints.contains(where: \.isExposed),
                kind: info.kind, isProject: info.isProject, memory: memory,
                startedAt: Date(timeIntervalSince1970: TimeInterval(b.startTime)),
                isSystem: isSystemProcess(args.first),
                hint: b.name == "ControlCenter" ? "To free ports 5000/7000: System Settings → General → AirDrop & Handoff → AirPlay Receiver" : nil
            ))
        }
        return items.sorted {
            if $0.isProject != $1.isProject { return $0.isProject }
            if $0.memory != $1.memory { return $0.memory > $1.memory }
            return $0.pid < $1.pid
        }
    }

    private static func isSystemProcess(_ exec: String?) -> Bool {
        guard let exec else { return false }
        return ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"].contains { exec.hasPrefix($0) }
    }

    static func descendants(of pid: pid_t, in children: [pid_t: [pid_t]]) -> [pid_t] {
        var out: [pid_t] = []
        var stack = children[pid] ?? []
        while let next = stack.popLast() {
            out.append(next)
            stack.append(contentsOf: children[next] ?? [])
        }
        return out
    }

    // MARK: Memory pressure

    enum Pressure: String {
        case normal = "Normal", warning = "Getting tight", critical = "Very high"
    }

    static func memoryPressure() -> Pressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
