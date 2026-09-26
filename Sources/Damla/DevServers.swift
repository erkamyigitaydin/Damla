import Darwin
import Foundation

/// A command-line process of this user listening on a TCP port: a dev server, a database, a tool's local API.
struct DevServer: Identifiable, Equatable {
    var id: String { "\(pid):\(port)" }
    let pid: pid_t
    let port: Int
    let name: String        // executable name: node, bun, python3, postgres…
    let project: String     // the git repository (or folder) it runs in
    var isDatabase: Bool { DevServer.databases.contains(name) }

    static let databases: Set<String> = ["postgres", "mongod", "mysqld", "mariadbd", "redis-server", "memcached", "clickhouse", "etcd"]

    /// Apps, their helpers and system services also listen on ports; only processes started from a shell count.
    static func isDevProcess(path: String, cwd: String) -> Bool {
        guard !path.isEmpty, !path.contains(".app/Contents/"), cwd != "/" else { return false }
        return !["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// The nearest folder with a .git inside, so a database under `project/.data/postgres` is named `project`.
    static func projectName(cwd: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        var url = URL(fileURLWithPath: cwd)
        for _ in 0..<6 where url.path != "/" && url.path != NSHomeDirectory() {
            if fileExists(url.appendingPathComponent(".git").path) { return url.lastPathComponent }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// Lists this user's listening dev servers straight from the kernel (libproc; a full scan takes a few ms), every
/// few seconds and only while someone is looking at the list.
final class DevServerMonitor: ObservableObject {
    @Published private(set) var servers: [DevServer] = []
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "app.local.damla.devservers", qos: .utility)

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 3, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            let found = Self.scan()
            DispatchQueue.main.async { if self?.servers != found { self?.servers = found } }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }

    /// Asks the server to quit (SIGTERM), as Ctrl-C in its terminal would; only this user's processes are listed.
    func terminate(_ server: DevServer) {
        kill(server.pid, SIGTERM)
        servers.removeAll { $0.pid == server.pid }
    }

    static func scan() -> [DevServer] {
        let uid = getuid()
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var found: [DevServer] = []
        var seen = Set<String>()
        for pid in pids.prefix(Int(max(0, count))) where pid > 0 && pid != getpid() {
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0, bsd.pbi_uid == uid else { continue }
            let ports = listeningPorts(pid)
            guard !ports.isEmpty else { continue }
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path = String(cString: pathBuffer)
            var vnode = proc_vnodepathinfo()
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, Int32(MemoryLayout<proc_vnodepathinfo>.size))
            let cwd = withUnsafePointer(to: vnode.pvi_cdir.vip_path) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            guard DevServer.isDevProcess(path: path, cwd: cwd) else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent
            let project = DevServer.projectName(cwd: cwd)
            for port in ports where seen.insert("\(pid):\(port)").inserted {
                found.append(DevServer(pid: pid, port: port, name: name, project: project))
            }
        }
        return found.sorted { $0.isDatabase == $1.isDatabase ? $0.port < $1.port : !$0.isDatabase }
    }

    private static func listeningPorts(_ pid: pid_t) -> [Int] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard got > 0 else { return [] }
        var ports: [Int] = []
        for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size)) > 0,
                  info.psi.soi_kind == SOCKINFO_TCP, info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)))
            if port > 0, !ports.contains(port) { ports.append(port) }
        }
        return ports
    }
}
