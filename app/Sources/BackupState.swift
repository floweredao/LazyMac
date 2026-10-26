import Darwin
import Foundation
import Network

// What the app shares with bin/due.sh: the schedule-state file, the backup lock and the kind of network.

/// The "key value" file bin/due.sh keeps (see its header). The app writes paused, metered and app.
enum BackupState {
    static var url: URL {
        if let f = ProcessInfo.processInfo.environment["LAZYMAC_STATE"], !f.isEmpty { return URL(fileURLWithPath: f) }
        return BackupConfig.supportDir.appendingPathComponent("schedule-state")
    }

    static func value(_ key: String) -> String? {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "\n").last { $0.hasPrefix(key + " ") }.map { String($0.dropFirst(key.count + 1)) }
    }

    /// Replaces the key's line (nil removes it), writing a new file in one move like due.sh does.
    static func set(_ key: String, _ value: String?) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n").filter { !$0.isEmpty && $0.split(separator: " ").first.map(String.init) != key }
        if let value { lines.append("\(key) \(value)") }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.map { $0 + "\n" }.joined()).write(to: url, atomically: true, encoding: .utf8)
    }

    static var pausedSince: Date? { value("paused").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } }
    static var paused: Bool { value("paused") != nil }
    static var waitsOnMetered: Bool { value("metered") == "wait" }
    /// Why the last automatic start waited: offline, metered or paused.
    static var deferred: String? { value("deferred") }
}

/// The lock daily.sh and `lazymac --run-backup` take so only one backup runs: a POSIX record lock (fcntl, like
/// zsh's `zsystem flock`) on backup.lock in the log folder. The system drops it when the holder exits.
enum BackupLock {
    static var url: URL { DailyLog.dir.appendingPathComponent("backup.lock") }

    private static func open() -> Int32 {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
    }

    private static func region(_ type: Int32) -> flock {
        var l = flock()
        l.l_type = Int16(type)
        l.l_whence = Int16(SEEK_SET)
        return l
    }

    static func holder() -> pid_t? {
        let fd = open()
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var l = region(F_WRLCK)
        guard fcntl(fd, F_GETLK, &l) == 0, l.l_type != Int16(F_UNLCK) else { return nil }
        return l.l_pid
    }

    /// Takes the lock for the rest of this process; nil when another backup holds it. Keep the descriptor open:
    /// closing any descriptor of the file releases a record lock.
    static func acquire() -> Int32? {
        let fd = open()
        guard fd >= 0 else { return nil }
        var l = region(F_WRLCK)
        guard fcntl(fd, F_SETLK, &l) == 0 else { close(fd); return nil }
        try? "\(getpid())\n".write(to: DailyLog.dir.appendingPathComponent("backup.pid"), atomically: true, encoding: .utf8)
        return fd
    }

    /// Stops the copying programs (rclone, rsync) of a running backup, the lock holder's and this app's own. Both
    /// write each file under a temporary name first, so a copy cut short leaves no half file; the backup script then
    /// sees the pause and ends with "=== paused". Steps that write the list are short and left to finish.
    static func stopCopies() {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-Ao", "pid=,ppid=,comm="]
        let out = Pipe()
        ps.standardOutput = out
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var children: [pid_t: [(pid: pid_t, name: String)]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, let pid = pid_t(f[0]), let ppid = pid_t(f[1]) else { continue }
            children[ppid, default: []].append((pid, String(f[2])))
        }
        var queue = [getpid()] + (holder().map { [$0] } ?? [])
        var seen = Set<pid_t>()
        while let p = queue.popLast() {
            guard seen.insert(p).inserted else { continue }
            for c in children[p] ?? [] {
                let name = (c.name as NSString).lastPathComponent
                if name == "rclone" || name == "rsync" { kill(c.pid, SIGTERM) } else { queue.append(c.pid) }
            }
        }
    }
}

/// The kind of connection macOS reports: a hotspot or cellular link is "expensive", Low Data Mode is "constrained".
enum NetworkStatus: String {
    case free, metered, offline

    private final class Box: @unchecked Sendable {
        var value = NetworkStatus.offline
    }

    static func current() -> NetworkStatus {
        let monitor = NWPathMonitor()
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            box.value = path.status != .satisfied ? .offline : (path.isExpensive || path.isConstrained) ? .metered : .free
            done.signal()
        }
        monitor.start(queue: DispatchQueue(label: "lazymac.network"))
        _ = done.wait(timeout: .now() + 2)
        monitor.cancel()
        return box.value
    }

    static func check() async -> NetworkStatus {
        await Task.detached { current() }.value
    }
}
