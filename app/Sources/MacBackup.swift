import AppKit
import Foundation
import Observation

// "Back Up This Mac": the app runs bin/daily.sh, the same pipeline as the scheduled job, and follows its log
// (~/Library/Logs/lazymac-daily/<date>.log) to show each step. The data folder says what a backup holds.

/// What the data folder holds for this Mac: the scan, the list, the settings and the locked bundle.
struct BackupParts: Equatable {
    var listItems = 0
    var foundApps: Int?
    var foundTools: Int?
    var scannedAt: Date?
    var settingsFiles = 0
    var macSettings = 0
    var settingsAt: Date?
    var bundleAt: Date?
    var hasManifest = false

    static func read(data: URL, host: String) -> BackupParts {
        let fm = FileManager.default
        func lines(_ url: URL) -> [String]? {
            (try? String(contentsOf: url, encoding: .utf8)).map {
                $0.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
            }
        }
        func modified(_ url: URL) -> Date? { (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date }

        var p = BackupParts()
        if let text = try? String(contentsOf: data.appendingPathComponent("catalog.tsv"), encoding: .utf8),
           let rows = try? Catalog.parse(text) {
            p.listItems = rows.filter { $0.step != nil && $0.decision == .keep }.count
        }
        let scan = data.appendingPathComponent("inventory/\(host)")
        if let apps = lines(scan.appendingPathComponent("apps.tsv")) {
            p.foundApps = apps.filter { $0.components(separatedBy: "\t").dropFirst().first != "apple" }.count
            p.scannedAt = modified(scan.appendingPathComponent("apps.tsv"))
        }
        let leaves = lines(scan.appendingPathComponent("brew-leaves.tsv"))?.count
        let globals = lines(scan.appendingPathComponent("cli-global.txt"))?.count
        if leaves != nil || globals != nil { p.foundTools = (leaves ?? 0) + (globals ?? 0) }

        let dot = data.appendingPathComponent("dotfiles")
        let files = (fm.enumerator(at: dot, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && $0.pathExtension != "partial" }
        p.settingsFiles = files.filter { $0.lastPathComponent != "macos-defaults.tsv" }.count
        p.macSettings = lines(dot.appendingPathComponent("macos-defaults.tsv"))?.count ?? 0
        p.settingsAt = files.compactMap(modified).max()
        p.bundleAt = modified(data.appendingPathComponent("secrets/secrets.tar.age"))
        p.hasManifest = fm.fileExists(atPath: data.appendingPathComponent("secrets/manifest.txt").path)
        return p
    }
}

/// Free tools the backup uses, found where the scripts look for them.
enum Helper: String, CaseIterable, Identifiable {
    case gitleaks, bun, age, rclone
    var id: String { rawValue }
    var path: String? { Tools.find(rawValue) }

    var purpose: String {
        switch self {
        case .gitleaks: tr("checks your list for passwords before it is saved", "목록을 저장하기 전에 비밀번호가 섞였는지 확인해요")
        case .bun: tr("keeps your app list up to date", "앱 목록을 최신으로 정리해요")
        case .age: tr("locks your passwords with a passphrase", "비밀번호를 암호로 잠가요")
        case .rclone: tr("copies your backup to Google Drive", "백업을 Google 드라이브로 복사해요")
        }
    }

    /// The tools a backup cannot run without on this Mac (bun only for the main Mac, which updates the list).
    static func missing(main: Bool) -> [Helper] {
        ([.gitleaks] + (main ? [.bun] : [])).filter { $0.path == nil }
    }
}

struct BackupProblem: Equatable {
    enum Fix: Equatable { case install([Helper]), choosePlace, details, fullDiskAccess, chooseFolders }
    let text: String
    let fix: Fix?

    /// `raw` is the reason daily.sh logs after "FAIL: ".
    static func explain(_ raw: String) -> BackupProblem {
        if raw.hasPrefix("The backup disk "), let disk = raw.dropFirst(16).components(separatedBy: " is not connected").first {
            return .init(text: tr("Your backup disk “\(disk)” is not connected. Connect it, then back up again.",
                                  "백업 디스크 “\(disk)”가 연결되어 있지 않아요. 디스크를 연결한 뒤 다시 백업해 주세요."), fix: nil)
        }
        if raw.hasPrefix("Choose a storage destination") || raw.hasPrefix("The local destination") {
            return .init(text: tr("Choose where backups go first.", "먼저 백업을 둘 곳을 골라 주세요."), fix: .choosePlace)
        }
        if raw.hasPrefix("gitleaks is not installed") {
            return .init(text: tr("LazyMac needs gitleaks, a free tool that \(Helper.gitleaks.purpose).", "LazyMac에 gitleaks가 필요해요. 무료 도구이고, \(Helper.gitleaks.purpose)."),
                         fix: .install([.gitleaks]))
        }
        if raw.hasPrefix("bun is not installed") {
            return .init(text: tr("LazyMac needs bun, a free tool that \(Helper.bun.purpose).", "LazyMac에 bun이 필요해요. 무료 도구이고, \(Helper.bun.purpose)."),
                         fix: .install([.bun]))
        }
        if raw.hasPrefix("Another backup is still running") {
            return .init(text: tr("Another backup was still running. Wait a few minutes, then try again.", "다른 백업이 아직 돌고 있었어요. 몇 분 뒤에 다시 해 주세요."), fix: nil)
        }
        if raw.hasPrefix("Catalog prune refused") {
            return .init(text: tr("LazyMac stopped because many apps seem to be gone at once. See the details for which ones.",
                                  "한꺼번에 많은 앱이 사라진 것처럼 보여서 멈췄어요. 자세히 보기에서 어떤 앱인지 확인해 주세요."), fix: .details)
        }
        if raw.hasPrefix("Could not copy data") || raw.hasPrefix("Could not restore shared data") || raw.hasPrefix("Could not refresh") {
            return .init(text: tr("LazyMac could not reach your backup place. Check that it is connected and has free space.",
                                  "백업 장소에 닿지 못했어요. 연결되어 있는지, 남은 공간이 있는지 확인해 주세요."), fix: .details)
        }
        if raw.hasPrefix("Set up folders") {
            return .init(text: tr("Folder backup is on, but no folders are chosen yet.", "폴더 백업을 켰는데 아직 고른 폴더가 없어요."), fix: .chooseFolders)
        }
        if raw.hasPrefix("Folder copy failed") || raw.hasPrefix("Folder comparison failed") {
            return .init(text: tr("Some folders were not copied. Check that they still exist and that LazyMac has Full Disk Access.",
                                  "일부 폴더를 복사하지 못했어요. 폴더가 아직 있는지, LazyMac에 전체 디스크 접근 권한이 있는지 확인해 주세요."), fix: .fullDiskAccess)
        }
        if raw.hasPrefix("Inventory scan failed") || raw.hasPrefix("Could not save the settings") || raw.hasPrefix("Catalog render") || raw.hasPrefix("Snapshot") {
            return .init(text: tr("The backup stopped while saving your list. See the details for why.", "목록을 저장하다가 멈췄어요. 자세히 보기에서 이유를 확인해 주세요."), fix: .details)
        }
        return .init(text: tr("The backup stopped: \(raw)", "백업이 멈췄어요: \(raw)"), fix: .details)
    }
}

/// "today at 04:00", "yesterday at 04:00", "Oct 21 at 04:00" in the UI language.
func whenPhrase(_ date: Date) -> String {
    let clock = DateFormatter()
    clock.locale = Lang.locale
    clock.dateFormat = "HH:mm"
    let time = clock.string(from: date)
    let cal = Calendar.current
    if cal.isDateInToday(date) { return tr("today at \(time)", "오늘 \(time)") }
    if cal.isDateInYesterday(date) { return tr("yesterday at \(time)", "어제 \(time)") }
    let day = date.formatted(.dateTime.month(.abbreviated).day().locale(Lang.locale))
    return tr("\(day) at \(time)", "\(day) \(time)")
}

func dayPhrase(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return tr("today", "오늘") }
    if cal.isDateInYesterday(date) { return tr("yesterday", "어제") }
    return date.formatted(.dateTime.month(.abbreviated).day().locale(Lang.locale))
}

@MainActor @Observable
final class MacBackup {
    enum Step: String, Identifiable {
        case refresh, scan, list, settings, copy, folders
        var id: String { rawValue }
        var title: String {
            switch self {
            case .refresh: tr("Getting the latest from your backup place", "백업 장소에서 최신 내용 받기")
            case .scan: tr("Listing the apps and tools on this Mac", "이 맥의 앱과 도구 살펴보기")
            case .list: tr("Updating your app list", "앱 목록 정리하기")
            case .settings: tr("Saving your settings", "설정 저장하기")
            case .copy: tr("Copying to your backup place", "백업 장소로 복사하기")
            case .folders: tr("Copying your folders", "폴더 복사하기")
            }
        }
    }

    enum StepState { case waiting, running, done, failed }

    struct Outcome: Equatable {
        let ok: Bool
        let reason: String?
        let date: Date
    }

    private(set) var running = false
    private(set) var steps: [Step] = []
    private(set) var states: [Step: StepState] = [:]
    private(set) var lines: [String] = []
    private(set) var outcome: Outcome?
    private(set) var startProblem: String?
    /// Backups wait until resumed: the automatic ones, and this button. Kept in the schedule-state file.
    private(set) var paused = BackupState.paused
    /// The last automatic start waited because the connection may charge for data (only when waiting is turned on).
    private(set) var waitingForFreeNetwork = false

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var logURL: URL?
    @ObservationIgnored private var offset: UInt64 = 0
    @ObservationIgnored private var reason: String?
    @ObservationIgnored private var notifyFile: URL?
    @ObservationIgnored private var stoppedByPause = false

    var currentStep: Step? { steps.first { states[$0] == .running } }
    var doneCount: Int { steps.filter { states[$0] == .done }.count }

    func reloadState() {
        paused = BackupState.paused
        waitingForFreeNetwork = !paused && BackupState.waitsOnMetered && BackupState.deferred == "metered"
    }

    /// Stops a running backup at a safe point and keeps every backup from starting until `resume()`.
    func pause() {
        BackupState.set("paused", String(Int(Date().timeIntervalSince1970)))
        BackupLock.stopCopies()
        reloadState()
    }

    func resume() {
        BackupState.set("paused", nil)
        reloadState()
        AutoBackup.checkNow()
    }

    func start(main: Bool, folders: Bool) {
        guard !running else { return }
        startProblem = nil
        reloadState()
        guard !paused else { return }
        guard let script = Tools.script("daily.sh") else {
            startProblem = tr("This copy of LazyMac is missing its backup script.", "이 LazyMac에 백업 스크립트가 없어요.")
            return
        }
        if BackupLock.holder() != nil {
            startProblem = tr("A backup is running right now. Try again when it is done.", "지금 백업이 도는 중이에요. 끝난 뒤에 다시 눌러 주세요.")
            return
        }
        steps = main ? [.refresh, .scan, .list, .settings, .copy] : [.refresh, .scan, .copy]
        if folders { steps.append(.folders) }
        states = Dictionary(uniqueKeysWithValues: steps.map { ($0, .waiting) })
        lines = []
        outcome = nil
        reason = nil
        stoppedByPause = false
        let log = DailyLog.dir.appendingPathComponent(DailyLog.fileName(for: .now))
        logURL = log
        offset = ((try? FileManager.default.attributesOfItem(atPath: log.path))?[.size] as? NSNumber)?.uint64Value ?? 0

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Console.path
        // A run started here reports in this window, not as a notification or through the on-failure hook.
        if env["LAZYMAC_DAILY_NOTIFY_FILE"] == nil {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("lazymac-backup-\(UUID().uuidString).txt")
            env["LAZYMAC_DAILY_NOTIFY_FILE"] = file.path
            notifyFile = file
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script]
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(status) } }
        }
        do { try p.run() } catch {
            startProblem = tr("Could not start the backup: \(error.localizedDescription)", "백업을 시작하지 못했어요: \(error.localizedDescription)")
            return
        }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readLog() }
        }
    }

    /// Takes the complete new lines of the log; a line still being written waits for the next read.
    private func readLog() {
        guard let logURL, let h = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: offset)) != nil, let data = try? h.readToEnd(), let cut = data.lastIndex(of: 0x0A) else { return }
        let chunk = data[data.startIndex...cut]
        offset += UInt64(chunk.count)
        for line in String(decoding: chunk, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            take(String(line))
        }
    }

    /// Log lines look like "2026-10-26 04:00:01 step scan" or "... FAIL: <reason>".
    private func take(_ line: String) {
        lines.append(line)
        let body = line.count > 20 ? String(line.dropFirst(20)) : line
        if body.hasPrefix("step "), let step = Step(rawValue: String(body.dropFirst(5))) {
            if !steps.contains(step) { steps.append(step) }
            let i = steps.firstIndex(of: step) ?? 0
            for s in steps[..<i] where states[s] != .failed { states[s] = .done }
            states[step] = .running
        } else if body.hasPrefix("FAIL: ") {
            reason = String(body.dropFirst(6))
        } else if body == "=== paused" {
            stoppedByPause = true
        }
    }

    private func finish(_ status: Int32) {
        readLog()
        timer?.invalidate()
        timer = nil
        if status != 0, reason == nil, let notifyFile, let text = try? String(contentsOf: notifyFile, encoding: .utf8) {
            reason = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let notifyFile { try? FileManager.default.removeItem(at: notifyFile) }
        notifyFile = nil
        running = false
        reloadState()
        if stoppedByPause {
            for s in steps where states[s] != .done { states[s] = .waiting }
            outcome = nil
            onFinish?()
            return
        }
        if status == 0 {
            for s in steps { states[s] = .done }
        } else {
            for s in steps where states[s] == .running { states[s] = .failed }
        }
        outcome = Outcome(ok: status == 0, reason: status == 0 ? nil : (reason ?? "exit \(status)"), date: .now)
        onFinish?()
    }
}

extension DailyLog {
    static var dir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAZYMAC_DAILY_LOGDIR"] ?? NSHomeDirectory() + "/Library/Logs/lazymac-daily")
    }

    /// daily.sh names each day's log by the local date.
    static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date) + ".log"
    }

    var lastRunLines: [String] {
        let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let start = lines.lastIndex(where: { $0.contains(" === start") }) else { return lines }
        return Array(lines[start...])
    }
}
