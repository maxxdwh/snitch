import Foundation

enum ServerKind {
    case web, database, other

    var symbol: String {
        switch self {
        case .web: return "globe"
        case .database: return "cylinder.split.1x2"
        case .other: return "gearshape"
        }
    }
}

struct ServerItem: Identifiable, Equatable {
    var id: pid_t { pid }
    let pid: pid_t
    let startTime: UInt64
    let title: String
    let framework: String?
    let folder: String?
    let cwd: String?
    let ports: [Int]
    let webPorts: [Int]
    let exposed: Bool
    let kind: ServerKind
    let isProject: Bool
    let memory: UInt64        // listener + its children, bytes
    let startedAt: Date
    let isSystem: Bool        // macOS-owned; never offer to stop these
    let hint: String?

    var uptime: TimeInterval { Date().timeIntervalSince(startedAt) }
    var isForgotten: Bool { isProject && uptime > 8 * 3600 }

    static func == (a: ServerItem, b: ServerItem) -> Bool {
        a.pid == b.pid && a.startTime == b.startTime && a.ports == b.ports && a.memory == b.memory
            && a.exposed == b.exposed && a.title == b.title
    }
}

enum Format {
    static func bytes(_ n: UInt64) -> String {
        let mb = Double(n) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }

    static func uptime(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    static func ports(_ ports: [Int]) -> String {
        switch ports.count {
        case 0: return ""
        case 1: return "localhost:\(ports[0])"
        case 2, 3: return "ports " + ports.map(String.init).joined(separator: ", ")
        default: return "ports \(ports[0]), \(ports[1]) +\(ports.count - 2)"
        }
    }
}
