import AppKit
import Foundation
import Observation

// Folder backup: the folders and the cloud place in backup.conf, copied by bin/nogit-backup.sh with rclone.
// The app only edits backup.conf and runs the script, so the scheduled job and the buttons do the same thing.

struct BackupConfig: Equatable {
    var remote = ""
    var folders: [String] = []
    var excludes: [String] = []

    static var url: URL {
        if let f = ProcessInfo.processInfo.environment["LAZYMAC_BACKUP_CONF"], !f.isEmpty { return URL(fileURLWithPath: f) }
        return supportDir.appendingPathComponent("backup.conf")
    }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("lazymac")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() -> BackupConfig {
        parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    static func parse(_ text: String) -> BackupConfig {
        var c = BackupConfig()
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0] {
            case "remote": c.remote = value
            case "folder": c.folders.append(expand(value))
            case "exclude": c.excludes.append(value)
            default: break
            }
        }
        return c
    }

    var text: String {
        var lines = ["# LazyMac folder backup. The app writes this file (Back Up > Folders); bin/nogit-backup.sh reads it."]
        if !remote.isEmpty { lines.append("remote \(remote)") }
        lines += folders.map { "folder \(Self.tilde($0))" }
        lines += excludes.map { "exclude \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: Self.url, atomically: true, encoding: .utf8)
    }

    static func expand(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Where a folder goes in the cloud, relative to the remote (the script's rel_of).
    static func cloudPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? String(path.dropFirst(home.count + 1)) : "_root" + path
    }

    /// Where a cloud folder comes back to (the script's place_of).
    static func localPath(_ rel: String, under base: String? = nil) -> String {
        if let base { return base + "/" + rel }
        if rel.hasPrefix("_root/") { return String(rel.dropFirst(5)) }
        return NSHomeDirectory() + "/" + rel
    }

    var remoteName: String { remote.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "" }
    var remotePath: String { remote.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? "" }
}

struct BackupRun: Identifiable, Equatable {
    enum Kind: String { case backup, check, restore }
    let date: Date
    let kind: Kind
    let ok: Bool
    let remote: String
    var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)" }

    static func all() -> [BackupRun] {
        let file = BackupConfig.url.deletingLastPathComponent().appendingPathComponent("runs.tsv")
        let storage = StorageConfig.url.deletingLastPathComponent().appendingPathComponent("storage-runs.tsv")
        let text = [file, storage].map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }.joined(separator: "\n")
        let iso = ISO8601DateFormatter()
        return text.components(separatedBy: "\n").compactMap { line in
            let c = line.components(separatedBy: "\t")
            guard c.count >= 3, let d = iso.date(from: c[0]), let k = Kind(rawValue: c[1]) else { return nil }
            return BackupRun(date: d, kind: k, ok: c[2] == "ok", remote: c.count > 3 ? c[3] : "")
        }.sorted { $0.date < $1.date }
    }
}

enum Tools {
    static var appBin: URL { BackupConfig.supportDir.appendingPathComponent("bin") }

    /// Where the scripts look for tools. LAZYMAC_TOOLS_PATH (a PATH-style list) replaces it, so tests and
    /// screenshots can show a Mac without a tool.
    static var searchDirs: [String] {
        if let p = ProcessInfo.processInfo.environment["LAZYMAC_TOOLS_PATH"] {
            return p.split(separator: ":").map(String.init)
        }
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", appBin.path, home + "/.bun/bin", home + "/.local/bin"]
    }

    static func find(_ name: String) -> String? {
        let fm = FileManager.default
        return searchDirs.map { $0 + "/" + name }.first { fm.isExecutableFile(atPath: $0) }
    }

    /// The folder backup script: LAZYMAC_BACKUP_SCRIPT, then the repo's copy (what the scheduled job runs), then
    /// the copy inside the app, so the folder backup works without a repo.
    static func backupScript(repo: URL?) -> String? {
        let fm = FileManager.default
        if let s = ProcessInfo.processInfo.environment["LAZYMAC_BACKUP_SCRIPT"], !s.isEmpty { return s }
        if let script = Tools.script("nogit-backup.sh") { return script }
        if let repo, fm.fileExists(atPath: repo.appendingPathComponent("bin/nogit-backup.sh").path) {
            return repo.appendingPathComponent("bin/nogit-backup.sh").path
        }
        if let bundled = Bundle.main.url(forResource: "nogit-backup", withExtension: "sh"), fm.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return nil
    }

    /// bin/due.sh, the catch-up rules: the repo's copy, then the one inside the app.
    static var dueScript: String? {
        if let script = Tools.script("due.sh") { return script }
        if let bundled = Bundle.main.url(forResource: "due", withExtension: "sh"), FileManager.default.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return nil
    }
}

@MainActor @Observable
final class BackupModel {
    enum Job: Equatable { case installRclone, installTools, connect, backup, check, listCloud, restore, secrets }

    private(set) var config = BackupConfig.load()
    private(set) var configured = BackupConfig.exists
    private(set) var rclonePath: String?
    private(set) var gitleaksPath: String?
    private(set) var remotes: [String] = []
    private(set) var runs: [BackupRun] = []
    private(set) var job: Job?
    private(set) var lastJob: Job?
    private(set) var message: String?
    private(set) var unreadable: Set<String> = []

    private(set) var cloudFolders: [String] = []
    private(set) var cloudListed = false
    /// The backup place holds folders (its lazymac-folders.txt), or this Mac backs up folders now.
    private(set) var backupHasFolders = false
    var restoreSelection: Set<String> = []
    var restoreTo: URL?
    var restoreReplace = false

    let console = Console()
    @ObservationIgnored var repo: () -> URL? = { nil }
    @ObservationIgnored private var listBuffer: [String] = []

    init() {
        console.onLine = { [weak self] line in self?.handle(line) }
        refresh()
    }

    var busy: Bool { job != nil }
    var hasRemote: Bool { !config.remote.isEmpty }
    var ready: Bool { (StorageConfig.load().backend == .local || rclonePath != nil) && hasRemote && !config.folders.isEmpty }
    var lastBackup: BackupRun? { runs.last { $0.kind == .backup && $0.remote == config.remote } }
    var lastCheck: BackupRun? { runs.last { $0.kind == .check } }
    var lastRestore: BackupRun? { runs.last { $0.kind == .restore } }
    var scriptPath: String? { Tools.backupScript(repo: repo()) }

    func refresh() {
        config = BackupConfig.load()
        let storage = StorageConfig.load()
        if FileManager.default.fileExists(atPath: StorageConfig.url.path) { config.remote = storage.target }
        configured = BackupConfig.exists
        rclonePath = Tools.find("rclone")
        gitleaksPath = Tools.find("gitleaks")
        runs = BackupRun.all()
        checkAccess()
        Task {
            await loadRemotes()
            await probeFolders()
        }
    }

    /// rclone is asked only when Google Drive is the backup place.
    func loadRemotes() async {
        guard StorageConfig.load().backend == .gdrive, let rclone = rclonePath else { remotes = []; return }
        let r = await Shell.run([rclone, "listremotes"])
        remotes = r.out.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.map { $0.hasSuffix(":") ? String($0.dropLast()) : $0 }
    }

    func probeFolders() async {
        let storage = StorageConfig.load()
        if storage.files && !config.folders.isEmpty { backupHasFolders = true; return }
        let local = StorageConfig.exists ? storage.backend == .local : false
        guard hasRemote else { backupHasFolders = false; return }
        if local {
            backupHasFolders = FileManager.default.fileExists(atPath: config.remote + "/lazymac-folders.txt")
        } else if let rclone = rclonePath {
            let r = await Shell.run([rclone, "lsf", config.remote + "/lazymac-folders.txt"])
            backupHasFolders = r.code == 0 && !r.out.isEmpty
        } else {
            backupHasFolders = false
        }
    }

    /// Folders the app cannot read (missing, or blocked until LazyMac gets Full Disk Access).
    func checkAccess() {
        let fm = FileManager.default
        unreadable = Set(config.folders.filter { (try? fm.contentsOfDirectory(atPath: $0)) == nil })
    }

    func exists(_ folder: String) -> Bool { FileManager.default.fileExists(atPath: folder) }

    private func save(_ change: (inout BackupConfig) -> Void) {
        var next = config
        change(&next)
        do {
            try next.save()
            config = next
            configured = true
            message = nil
        } catch {
            message = tr("Could not save the backup settings: \(error.localizedDescription)",
                         "백업 설정을 저장하지 못했어요: \(error.localizedDescription)")
        }
        checkAccess()
    }

    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = tr("Add", "추가")
        panel.message = tr("Choose folders to back up. Folders that are already on GitHub or iCloud do not need it.",
                           "백업할 폴더를 골라요. GitHub나 iCloud에 이미 있는 폴더는 안 넣어도 돼요.")
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        guard panel.runModal() == .OK else { return }
        add(panel.urls.map(\.path))
    }

    func add(_ paths: [String]) {
        save { c in
            for p in paths.map(BackupConfig.expand) where !c.folders.contains(p) { c.folders.append(p) }
        }
    }

    func remove(_ folder: String) { save { $0.folders.removeAll { $0 == folder } } }

    func setRemote(name: String, path: String) {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        do {
            var storage = StorageConfig.load()
            storage.remote = "\(name):\(clean)"
            try storage.save()
        } catch { message = error.localizedDescription; return }
        save { $0.remote = "\(name):\(clean)" }
    }

    func setExcludes(_ text: String) {
        let list = text.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard list != config.excludes else { return }
        save { $0.excludes = list }
    }

    static var suggestedPath: String { "LazyMac/\(Profiles.host)" }

    // MARK: Jobs

    private func start(_ job: Job, _ title: String, _ command: [String], done: ((Int32) -> Void)? = nil) {
        guard self.job == nil else { return }
        self.job = job
        lastJob = job
        message = nil
        console.run(title: title, command: command) { [weak self] code in
            guard let self else { return }
            self.job = nil
            self.runs = BackupRun.all()
            done?(code)
        }
    }

    func installRclone() {
        if let brew = Tools.find("brew") {
            start(.installRclone, tr("Install rclone", "rclone 설치"), [brew, "install", "rclone"]) { [weak self] _ in self?.refresh() }
            return
        }
        let arch: String = {
            var info = utsname()
            uname(&info)
            let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return machine == "arm64" ? "arm64" : "amd64"
        }()
        let script = """
        set -e
        dir="$1"; tmp=$(mktemp -d)
        echo "Downloading rclone from downloads.rclone.org"
        curl -fL --progress-bar "https://downloads.rclone.org/rclone-current-osx-\(arch).zip" -o "$tmp/rclone.zip"
        ditto -x -k "$tmp/rclone.zip" "$tmp/x"
        mkdir -p "$dir" && cp "$tmp"/x/rclone-*/rclone "$dir/rclone" && chmod +x "$dir/rclone"
        rm -rf "$tmp"
        "$dir/rclone" version | head -1
        """
        start(.installRclone, tr("Install rclone", "rclone 설치"), ["/bin/zsh", "-c", script, "zsh", Tools.appBin.path]) { [weak self] _ in self?.refresh() }
    }

    /// Makes a Google Drive remote. The browser asks to allow rclone; rclone then prints the new settings with the
    /// sign-in token, so stdout goes nowhere and only the sign-in steps (stderr) are shown.
    func connectGoogleDrive(name: String, path: String, clientID: String, clientSecret: String) {
        guard let rclone = rclonePath else { return }
        var params = ["scope=drive.file"]
        if !clientID.isEmpty { params += ["client_id=\(clientID)", "client_secret=\(clientSecret)"] }
        let command = ["/bin/sh", "-c", "exec \"$0\" config create \"$@\" >/dev/null", rclone, name, "drive"] + params
        start(.connect, tr("Connect Google Drive", "Google 드라이브 연결"), command) { [weak self] code in
            guard let self else { return }
            Task {
                await self.loadRemotes()
                if code == 0, self.remotes.contains(name) {
                    self.setRemote(name: name, path: path)
                    self.message = tr("Connected to Google Drive as \(name).", "Google 드라이브를 \(name)(으)로 연결했어요.")
                } else {
                    self.message = tr("Google Drive is not connected. Try again, or set it up in Terminal with rclone config.",
                                      "Google 드라이브가 연결되지 않았어요. 다시 해 보거나 터미널에서 rclone config로 설정해 주세요.")
                }
            }
        }
    }

    func openRcloneConfig() {
        guard let rclone = rclonePath else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lazymac-rclone-config.command")
        try? "#!/bin/zsh\n'\(rclone)' config\n".write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }

    /// Installs missing helper tools in the output panel: gitleaks and age with Homebrew (installed first when
    /// it is missing; it asks for the Mac password there), bun with its own installer.
    func install(_ helpers: [Helper]) {
        let brewTools = helpers.filter { $0 != .bun }.map(\.rawValue)
        var script = "set -e\n"
        if !brewTools.isEmpty {
            script += """
            if ! command -v brew >/dev/null 2>&1; then
              echo "Installing Homebrew first. It asks for your Mac password."
              /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
              eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
            fi
            brew install \(brewTools.joined(separator: " "))

            """
        }
        if helpers.contains(.bun) { script += "curl -fsSL https://bun.sh/install | bash\n" }
        start(.installTools, tr("Install tools", "도구 설치"), ["/bin/zsh", "-c", script]) { [weak self] _ in self?.refresh() }
    }

    static let starterManifest = """
    # What bin/secrets-pack.sh locks into secrets.tar.age with your passphrase. Paths are inside your home
    # folder; a line that matches nothing on this Mac is skipped. Add keychain:<service> lines for Keychain items.
    .ssh/id_*
    .config/gh/hosts.yml
    .aws/credentials
    .docker/config.json
    .netrc
    .npmrc
    .kube/config

    """

    /// Locks the passwords and sign-in files into the encrypted bundle. age asks for the passphrase in the
    /// output panel. With `startList`, first writes a starter list of the usual sign-in files.
    func lockSecrets(startList: Bool) {
        guard let script = Tools.script("secrets-pack.sh") else { return }
        let manifest = StorageConfig.load().dataURL.appendingPathComponent("secrets/manifest.txt")
        if startList, !FileManager.default.fileExists(atPath: manifest.path) {
            do {
                try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Self.starterManifest.write(to: manifest, atomically: true, encoding: .utf8)
            } catch {
                message = error.localizedDescription
                return
            }
        }
        start(.secrets, tr("Lock passwords and sign-ins", "비밀번호와 로그인 정보 잠그기"), ["/bin/zsh", script]) { [weak self] code in
            self?.message = code == 0 ? tr("Locked and saved your passwords and sign-ins.", "비밀번호와 로그인 정보를 잠가서 저장했어요.")
                : tr("Your passwords and sign-ins were not locked. The output says why.", "비밀번호와 로그인 정보를 잠그지 못했어요. 아래 출력에서 이유를 볼 수 있어요.")
        }
    }

    private func script(_ args: [String], _ job: Job, _ title: String, done: ((Int32) -> Void)? = nil) {
        guard let path = scriptPath else {
            message = tr("The folder backup script is missing from this copy of LazyMac.", "이 LazyMac에 폴더 백업 스크립트가 없어요.")
            return
        }
        start(job, title, ["/bin/zsh", path] + args, done: done)
    }

    var scheduledRunning: Bool { AutoBackup.isRunning }

    func backUpNow() {
        guard !BackupState.paused else {
            message = tr("Backups are paused. Resume them on This Mac first.", "백업이 멈춰 있어요. 먼저 '이 맥'에서 다시 켜 주세요.")
            return
        }
        guard !scheduledRunning, BackupLock.holder() == nil else {
            message = tr("The scheduled backup is running now. Try again when it is done.", "예약된 백업이 지금 도는 중이에요. 끝나면 다시 눌러 주세요.")
            return
        }
        script(["rclone"], .backup, tr("Copy folders", "폴더 복사")) { [weak self] code in
            self?.message = code == 0 ? tr("Copied every folder.", "모든 폴더를 복사했어요.")
                : tr("Some folders were not copied. The output says which.", "일부 폴더를 복사하지 못했어요. 아래 출력에서 어떤 폴더인지 볼 수 있어요.")
        }
    }

    func check() {
        script(["rclone", "--check"], .check, tr("Compare with the backup", "백업과 비교")) { [weak self] code in
            self?.message = code == 0 ? tr("The backup matches every folder.", "백업 사본이 모든 폴더와 같아요.")
                : tr("Some files differ or are missing in the backup. Back up again to copy them.", "백업에 없거나 다른 파일이 있어요. 다시 백업하면 복사돼요.")
        }
    }

    func listCloud() {
        listBuffer = []
        script(["folders"], .listCloud, tr("Find backed-up folders", "백업된 폴더 찾기")) { [weak self] code in
            guard let self else { return }
            self.cloudListed = true
            self.cloudFolders = code == 0 ? self.listBuffer : []
            self.restoreSelection = Set(self.cloudFolders)
            if code != 0 {
                self.message = tr("No LazyMac backup was found in \(self.config.remote).", "\(self.config.remote)에서 LazyMac 백업을 찾지 못했어요.")
            }
        }
    }

    func chooseRestoreFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Restore Here", "여기에 복원")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        restoreTo = url
    }

    func restore() {
        let chosen = cloudFolders.filter { restoreSelection.contains($0) }
        guard !chosen.isEmpty else { return }
        var args = ["restore"]
        if let restoreTo { args += ["--to", restoreTo.path] }
        if restoreReplace { args.append("--replace") }
        script(args + chosen, .restore, tr("Restore folders", "폴더 복원")) { [weak self] code in
            self?.message = code == 0 ? tr("Restored \(chosen.count == 1 ? "1 folder" : "\(chosen.count) folders").", "폴더 \(chosen.count)개를 복원했어요.")
                : tr("Some folders were not restored. The output says which.", "일부 폴더를 복원하지 못했어요. 아래 출력에서 어떤 폴더인지 볼 수 있어요.")
        }
    }

    private func handle(_ line: String) {
        guard job == .listCloud else { return }
        let t = line.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, !t.contains(" NOTICE:"), !t.hasPrefix("No folder list") { listBuffer.append(t) }
    }

    static func openFullDiskAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

// MARK: - Scheduled run without a repo

/// `lazymac --run-backup [--if-due]`: what the LaunchAgent runs on a Mac with no LazyMac repo (or no bun). Copies the
/// folders, compares, logs to ~/Library/Logs/lazymac-daily/<date>.log and shows a notification when something failed.
/// It follows the same catch-up rules, pause and lock as daily.sh, through bin/due.sh.
enum ScheduledBackup {
    static func run(ifDue: Bool) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        // With initialized data, the same daily pipeline handles both app and LaunchAgent runs.
        if StorageConfig.load().isInitialized, let script = Tools.script("daily.sh") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [script] + (ifDue ? ["--if-due"] : [])
            do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
            catch { return notify(error.localizedDescription) }
        }
        let due = Tools.dueScript
        func rules(_ args: [String], net: String? = nil) -> [String] {
            guard let due else { return ["run"] }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [due] + args
            if let net { p.environment = env.merging(["LAZYMAC_NET": net]) { _, new in new } }
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return ["run"] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self).components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        if ifDue, rules(["decide"]).first != "run" { return 0 }

        let logDir = DailyLog.dir
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        let logURL = logDir.appendingPathComponent("\(day.string(from: .now)).log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        guard let log = try? FileHandle(forWritingTo: logURL) else { return 1 }
        log.seekToEndOfFile()
        func write(_ s: String) {
            let stamp = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime])
            log.write(Data("\(stamp) \(s)\n".utf8))
        }
        guard StorageConfig.load().files else {
            write("=== ok (file backup off)")
            return 0
        }
        if BackupState.paused {
            if !ifDue { write("skip: paused") }
            return 0
        }
        guard let lock = BackupLock.acquire() else {
            let pid = BackupLock.holder().map { " (pid \($0))" } ?? ""
            if ifDue { write("skip: running\(pid)"); return 0 }
            write("FAIL: another backup is still running\(pid)")
            return notify(tr("Another backup is still running.", "다른 백업이 아직 돌고 있어요."))
        }
        defer { close(lock) }
        if ifDue {
            let net = env["LAZYMAC_NET"].flatMap(NetworkStatus.init(rawValue:)) ?? NetworkStatus.current()
            let answer = rules(["net"], net: net.rawValue)
            if let first = answer.first, first != "run" {
                if first == "skip offline" || first == "skip metered" { write(first.replacingOccurrences(of: "skip ", with: "skip: ")) }
                if answer.count > 1 { _ = notify(answer[1], prefixed: false) }
                return 0
            }
            _ = rules(["start"])
        }
        guard let script = Tools.backupScript(repo: SetupModel.findRepo()) else {
            write("FAIL: no folder backup script")
            return notify(tr("The folder backup script is missing.", "폴더 백업 스크립트가 없어요."))
        }
        write("=== start (folder backup)")
        for (args, what) in [(["rclone"], "backup"), (["rclone", "--check"], "check")] {
            if BackupState.paused { write("=== paused"); return 0 }
            write(what)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [script] + args
            p.standardOutput = log
            p.standardError = log
            do { try p.run() } catch {
                write("FAIL: \(error.localizedDescription)")
                return notify(error.localizedDescription)
            }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                // Pausing stops the copy; that is not a failure.
                if BackupState.paused { write("=== paused"); return 0 }
                write("FAIL: \(what) exited \(p.terminationStatus)")
                let reason = what == "backup" ? tr("Some folders were not copied to the cloud.", "일부 폴더를 클라우드에 복사하지 못했어요.")
                                              : tr("The cloud copy differs from the folders.", "클라우드 사본이 폴더와 달라요.")
                guard ifDue else { return notify(reason) }
                if let alert = rules(["fail", reason]).first { _ = notify(alert, prefixed: false) }
                return 1
            }
        }
        _ = rules(["ok"])
        write("=== ok")
        return 0
    }

    private static func notify(_ message: String, prefixed: Bool = true) -> Int32 {
        if let file = ProcessInfo.processInfo.environment["LAZYMAC_DAILY_NOTIFY_FILE"], !file.isEmpty {
            let line = Data("\(message)\n".utf8)
            if let h = FileHandle(forWritingAtPath: file) { h.seekToEndOfFile(); h.write(line); try? h.close() }
            else { FileManager.default.createFile(atPath: file, contents: line) }
            return 1
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv", "-e", "display notification (item 1 of argv) with title \"LazyMac\"", "-e", "end run",
                       tr("Backup failed: ", "백업 실패: ") + message]
        try? p.run()
        p.waitUntilExit()
        return 1
    }
}
