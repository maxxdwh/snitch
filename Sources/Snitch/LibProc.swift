import Darwin
import Foundation

/// Thin, allocation-light wrappers over libproc. Everything here reads the kernel
/// directly, so Snitch never has to spawn `lsof` / `ps` (which is slow and heavy).
enum LibProc {
    struct Basic {
        var pid: pid_t
        var ppid: pid_t
        var uid: uid_t
        var name: String
        var startTime: UInt64 // seconds since epoch; used to guard against PID reuse
    }

    struct Endpoint: Hashable {
        var port: Int
        var isExposed: Bool   // reachable from other machines (bound to * / 0.0.0.0 / ::)
    }

    private static func string<T>(fromTuple tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
            return String(decoding: bytes[bytes.startIndex..<end], as: UTF8.self)
        }
    }

    static func allPids() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 64)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return [] }
        return pids.prefix(Int(got) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }

    static func basic(_ pid: pid_t) -> Basic? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Basic(
            pid: pid,
            ppid: pid_t(info.pbi_ppid),
            uid: info.pbi_uid,
            name: string(fromTuple: info.pbi_name).isEmpty ? string(fromTuple: info.pbi_comm) : string(fromTuple: info.pbi_name),
            startTime: info.pbi_start_tvsec
        )
    }

    /// TCP sockets in LISTEN state owned by `pid`.
    static func listeningEndpoints(_ pid: pid_t) -> [Endpoint] {
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(listSize) / stride + 8)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard got > 0 else { return [] }

        var result = Set<Endpoint>()
        let sockSize = Int32(MemoryLayout<socket_fdinfo>.size)
        for fd in fds.prefix(Int(got) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, sockSize) == sockSize else { continue }
            guard si.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = si.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }

            let ini = tcp.tcpsi_ini
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport)))
            guard port > 0 else { continue }

            var exposed = false
            let v6 = (ini.insi_vflag & UInt8(INI_IPV6)) != 0
            if v6 {
                let addr = ini.insi_laddr.ina_6
                let bytes = withUnsafeBytes(of: addr) { Array($0) }
                let isAny = bytes.allSatisfy { $0 == 0 }
                exposed = isAny
            } else {
                let s = ini.insi_laddr.ina_46.i46a_addr4.s_addr
                let first = UInt8(truncatingIfNeeded: UInt32(bigEndian: s) >> 24)
                exposed = (s == 0) || (first != 127)
            }
            result.insert(Endpoint(port: port, isExposed: exposed))
        }
        return result.sorted { $0.port < $1.port }
    }

    static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = string(fromTuple: info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// Memory as Activity Monitor reports it ("Memory" column), in bytes.
    static func footprint(_ pid: pid_t) -> UInt64 {
        var ri = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ri) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return ok == 0 ? ri.ri_phys_footprint : 0
    }

    /// Command-line arguments (argv) via sysctl.
    static func arguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }

        var argc: Int32 = 0
        memcpy(&argc, buf, MemoryLayout<Int32>.size)
        var i = MemoryLayout<Int32>.size
        while i < size && buf[i] != 0 { i += 1 }      // exec path
        while i < size && buf[i] == 0 { i += 1 }      // padding

        var args: [String] = []
        while i < size, args.count < Int(argc) {
            var j = i
            while j < size && buf[j] != 0 { j += 1 }
            args.append(String(decoding: buf[i..<j], as: UTF8.self))
            i = j + 1
        }
        return args
    }
}
