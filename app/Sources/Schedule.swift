import Foundation

// Auto backup: the LaunchAgent local.lazymac-daily runs on a schedule. With a LazyMac repo and bun it runs
// bin/daily.sh (the main Mac in machines.tsv does the full job; any other Mac scans itself, pushes inventory/<host>/
// and copies its folders); without them it runs `lazymac --run-backup`, which copies the folders in backup.conf.
// Turning it on writes ~/Library/LaunchAgents/local.lazymac-daily.plist and loads it; turning it off unloads
// and removes it. Changing the schedule keeps every other key of an existing plist.

struct BackupSchedule: Equatable {
    enum Frequency: String, CaseIterable, Identifiable {
        case hourly, everyHours, daily, weekly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hourly: tr("Every hour", "매시간")
            case .everyHours: tr("Every few hours", "몇 시간마다")
            case .daily: tr("Every day", "매일")
            case .weekly: tr("Every week", "매주")
            }
        }
    }

    var frequency: Frequency = .daily
    var everyHours = 6
    var hour = 4
    var minute = 0
    /// launchd numbering: 0 = Sunday ... 6 = Saturday.
    var weekday = 1

    static let label = "local.lazymac-daily"
    static let hourSteps = [2, 3, 4, 6, 8, 12]

    var intervals: [[String: Int]] {
        switch frequency {
        case .hourly: return [["Minute": minute]]
        case .everyHours:
            let n = max(1, everyHours)
            return (0..<24).filter { (($0 - hour) % n + n) % n == 0 }.map { ["Hour": $0, "Minute": minute] }
        case .daily: return [["Hour": hour, "Minute": minute]]
        case .weekly: return [["Weekday": weekday, "Hour": hour, "Minute": minute]]
        }
    }

    init(frequency: Frequency = .daily, everyHours: Int = 6, hour: Int = 4, minute: Int = 0, weekday: Int = 1) {
        self.frequency = frequency
        self.everyHours = everyHours
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
    }

    /// Reads a StartCalendarInterval value (one dictionary or an array of them).
    init?(calendar value: Any?) {
        let list: [[String: Int]]
        if let d = value as? [String: Int] { list = [d] } else if let a = value as? [[String: Int]], !a.isEmpty { list = a } else { return nil }
        let first = list[0]
        minute = first["Minute"] ?? 0
        if list.count == 1 {
            if let w = first["Weekday"], let h = first["Hour"] {
                frequency = .weekly; weekday = w % 7; hour = h
            } else if let h = first["Hour"] {
                frequency = .daily; hour = h
            } else {
                frequency = .hourly
            }
            return
        }
        let hours = list.compactMap { $0["Hour"] }.sorted()
        guard hours.count == list.count, hours.count >= 2, 24 % hours.count == 0 else { return nil }
        let n = 24 / hours.count
        guard hours.enumerated().allSatisfy({ $0.element == hours[0] + $0.offset * n }) else { return nil }
        frequency = .everyHours; everyHours = n; hour = hours[0]
    }

    /// Command-line form, for the test hook: hourly[:MM] | every:<N>[:HH:MM] | daily:HH:MM | weekly:<0-6>:HH:MM
    init?(spec: String) {
        let p = spec.split(separator: ":").map(String.init)
        func num(_ i: Int, _ range: ClosedRange<Int>) -> Int? { i < p.count ? Int(p[i]).flatMap { range.contains($0) ? $0 : nil } : nil }
        switch p.first {
        case "hourly":
            frequency = .hourly; minute = p.count > 1 ? (num(1, 0...59) ?? -1) : 0
        case "every":
            guard let n = num(1, 2...12), 24 % n == 0 else { return nil }
            frequency = .everyHours; everyHours = n
            hour = p.count > 2 ? (num(2, 0...23) ?? -1) : 0; minute = p.count > 3 ? (num(3, 0...59) ?? -1) : 0
        case "daily":
            frequency = .daily; hour = num(1, 0...23) ?? -1; minute = num(2, 0...59) ?? -1
        case "weekly":
            frequency = .weekly; weekday = num(1, 0...6) ?? -1; hour = num(2, 0...23) ?? -1; minute = num(3, 0...59) ?? -1
        default: return nil
        }
        if hour < 0 || minute < 0 || weekday < 0 { return nil }
    }

    static func weekdayName(_ w: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: Lang.korean ? "ko_KR" : "en_US")
        return cal.weekdaySymbols[w % 7]
    }

    var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch frequency {
        case .hourly: return tr("Every hour at :\(String(format: "%02d", minute))", "매시간 \(minute)분")
        case .everyHours:
            let hours = intervals.compactMap { $0["Hour"] }.map { String(format: "%02d", $0) }.joined(separator: ", ")
            return tr("Every \(everyHours) hours (\(hours) at :\(String(format: "%02d", minute)))", "\(everyHours)시간마다 (\(hours)시 \(minute)분)")
        case .daily: return tr("Every day at \(time)", "매일 \(time)")
        case .weekly: return tr("Every \(Self.weekdayName(weekday)) at \(time)", "매주 \(Self.weekdayName(weekday)) \(time)")
        }
    }
}

enum AutoBackup {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var plistURL: URL {
        if let d = ProcessInfo.processInfo.environment["LAZYMAC_LAUNCHAGENTS_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: d).appendingPathComponent("\(BackupSchedule.label).plist")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(BackupSchedule.label).plist")
    }

    static var domain: String { "gui/\(getuid())" }

    static func current() -> BackupSchedule? {
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return BackupSchedule(calendar: dict["StartCalendarInterval"])
    }

    static func bunPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.bun/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// A new plist for this Mac. With a repo, bun starts bin/daily.sh because a /bin/zsh started by launchd cannot
    /// read ~/Documents; without one, this app's own binary runs the folder backup (it needs Full Disk Access).
    static func freshPlist(repo: URL?) throws -> [String: Any] {
        let program: [String]
        if repo != nil, let code = Tools.codeRoot, let bun = bunPath() {
            let script = code.appendingPathComponent("bin/daily.sh").path.replacingOccurrences(of: "'", with: "'\\''")
            program = [bun, "exec", "/bin/zsh '\(script)'"]
        } else if let exe = Bundle.main.executablePath {
            program = [exe, "--run-backup"]
        } else {
            throw Failure(message: tr("Cannot find this app's program to run the backup.", "백업을 돌릴 이 앱의 프로그램을 찾지 못했어요."))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let log = home + "/Library/Logs/lazymac-daily/launchd.log"
        return [
            "Label": BackupSchedule.label,
            "ProgramArguments": program,
            "WorkingDirectory": repo?.path ?? home,
            "EnvironmentVariables": ["HOME": home, "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:\(home)/.bun/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
                .merging(ProcessInfo.processInfo.environment.filter { ["LAZYMAC_DATA", "LAZYMAC_STORAGE_CONF"].contains($0.key) }) { _, new in new },
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
    }

    static func launchctl(_ args: [String]) -> (code: Int32, out: String) {
        if let fake = ProcessInfo.processInfo.environment["LAZYMAC_LAUNCHCTL"], !fake.isEmpty {
            return run([fake] + args)
        }
        return run(["/bin/launchctl"] + args)
    }

    private static func run(_ command: [String]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command[0])
        p.arguments = Array(command.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (127, error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static var isRunning: Bool {
        let r = launchctl(["print", "\(domain)/\(BackupSchedule.label)"])
        return r.code == 0 && r.out.contains("state = running")
    }

    /// The program the installed job starts, when it is no longer there (the app was moved or deleted).
    static var missingProgram: String? {
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let first = (dict["ProgramArguments"] as? [String])?.first else { return nil }
        return FileManager.default.isExecutableFile(atPath: first) ? nil : first
    }

    static func install(_ schedule: BackupSchedule, repo: URL?) throws {
        guard !isRunning else {
            throw Failure(message: tr("A backup is running right now. Change the schedule after it finishes.",
                                      "지금 백업이 도는 중이에요. 끝난 뒤에 바꿔 주세요."))
        }
        let fm = FileManager.default
        var dict: [String: Any]
        if let data = try? Data(contentsOf: plistURL),
           let existing = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            dict = existing
        } else {
            dict = try freshPlist(repo: repo)
        }
        let intervals = schedule.intervals
        dict["StartCalendarInterval"] = intervals.count == 1 ? intervals[0] as Any : intervals as Any
        dict.removeValue(forKey: "StartInterval")
        if let log = dict["StandardOutPath"] as? String {
            try? fm.createDirectory(atPath: (log as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        _ = launchctl(["bootout", "\(domain)/\(BackupSchedule.label)"])
        let r = launchctl(["bootstrap", domain, plistURL.path])
        guard r.code == 0 else {
            throw Failure(message: tr("Saved the schedule, but launchctl could not load it: \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))",
                                      "일정은 저장했지만 launchctl이 불러오지 못했어요: \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))"))
        }
    }

    static func remove() throws {
        guard !isRunning else {
            throw Failure(message: tr("A backup is running right now. Turn it off after it finishes.",
                                      "지금 백업이 도는 중이에요. 끝난 뒤에 꺼 주세요."))
        }
        _ = launchctl(["bootout", "\(domain)/\(BackupSchedule.label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) { try FileManager.default.removeItem(at: plistURL) }
    }
}
