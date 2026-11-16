import Foundation

/// Stops a server politely (SIGTERM), then forcefully (SIGKILL) if it ignores us.
/// Also stops the things that would just restart it: child processes, and
/// `npm run dev` style wrapper parents.
enum Killer {
    private static let wrapperHints = ["npm", "pnpm", "yarn", "npx", "bunx", "nodemon", "turbo", "concurrently"]

    static func stop(pid: pid_t, expectedStart: UInt64) async -> Bool {
        // Guard 1: the PID must still be the same process we showed the user.
        guard let b = LibProc.basic(pid), b.startTime == expectedStart, b.uid == getuid() else { return true }

        var children: [pid_t: [pid_t]] = [:]
        var basics: [pid_t: LibProc.Basic] = [:]
        for p in LibProc.allPids() {
            if let info = LibProc.basic(p), info.uid == getuid() { basics[p] = info; children[info.ppid, default: []].append(p) }
        }

        var targets: [pid_t] = [pid] + Scanner.descendants(of: pid, in: children)

        // Walk up through parents. Only keep the chain up to the highest *real* wrapper
        // (npm, pnpm, yarn, ...), plus the `sh -c` shims between. A shell with no wrapper
        // above it is someone's terminal or IDE session and must never be touched.
        var chain: [pid_t] = []
        var lastWrapperIndex = -1
        var cursor = b.ppid
        while cursor > 1, let parent = basics[cursor], chain.count < 8 {
            if isShell(parent) {
                guard LibProc.arguments(parent.pid).contains("-c") else { break }
            } else if isWrapper(parent) {
                lastWrapperIndex = chain.count
            } else { break }
            chain.append(cursor)
            cursor = parent.ppid
        }
        if lastWrapperIndex >= 0 { targets += chain.prefix(lastWrapperIndex + 1) }

        let snapshot = targets.compactMap { t in basics[t].map { ($0.pid, $0.startTime) } }
        for (p, _) in snapshot { kill(p, SIGTERM) }

        for _ in 0..<20 {                     // up to ~2s of grace
            try? await Task.sleep(nanoseconds: 100_000_000)
            if snapshot.allSatisfy({ !alive($0.0, $0.1) }) { return true }
        }
        for (p, s) in snapshot where alive(p, s) { kill(p, SIGKILL) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return snapshot.allSatisfy { !alive($0.0, $0.1) }
    }

    private static func alive(_ pid: pid_t, _ start: UInt64) -> Bool {
        guard let b = LibProc.basic(pid) else { return false }
        return b.startTime == start
    }

    private static func isShell(_ p: LibProc.Basic) -> Bool {
        ["sh", "zsh", "bash", "fish", "dash"].contains(p.name)
    }

    private static func isWrapper(_ p: LibProc.Basic) -> Bool {
        let names = LibProc.arguments(p.pid).prefix(4).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() }
        return names.contains { wrapperHints.contains($0) || $0 == "npm-cli" }
    }
}
