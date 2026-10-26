import AppKit
import Foundation
import Observation

struct StorageConfig: Equatable {
    /// gdrive (the default): Google Drive through rclone. local: a folder the user picks (an external disk, say).
    enum Backend: String, CaseIterable { case local, gdrive }
    var backend: Backend = .gdrive
    var remote = "gdrive:LazyMac"
    var local = ""
    var files = false
    var data = NSHomeDirectory() + "/LazyMac-data"

    static var url: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAZYMAC_STORAGE_CONF"]
            ?? BackupConfig.supportDir.appendingPathComponent("storage.conf").path)
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Reads storage.conf the way bin/storage.sh does, including its rule for a file with no backend line.
    static func load() -> StorageConfig {
        var c = StorageConfig()
        var sawBackend = false
        for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "backend": c.backend = Backend(rawValue: parts[1]) ?? .local; sawBackend = true
            case "remote": c.remote = parts[1]
            case "local": c.local = BackupConfig.expand(parts[1])
            case "files": c.files = parts[1] == "on"
            case "data": c.data = BackupConfig.expand(parts[1])
            default: break
            }
        }
        if !sawBackend { c.backend = c.local.isEmpty ? .gdrive : .local }
        return c
    }

    /// Writes the defaults (Google Drive, folder backup off) for a new user, so the app and the scripts read the
    /// same place before anything is chosen.
    static func saveDefaultsIfMissing() {
        if !exists { try? StorageConfig().save() }
    }

    var dataURL: URL {
        URL(fileURLWithPath: BackupConfig.expand(ProcessInfo.processInfo.environment["LAZYMAC_DATA"] ?? data))
    }
    var target: String { backend == .local ? local : remote }
    /// A backup place is chosen (a local folder or a Google Drive remote).
    var hasPlace: Bool { !target.isEmpty }
    var isInitialized: Bool { FileManager.default.fileExists(atPath: dataURL.appendingPathComponent("catalog.tsv").path) }

    func save() throws {
        guard ![remote, local, data].contains(where: { $0.contains("\n") || $0.contains("\r") }) else {
            throw CatalogError(message: tr("Folder paths and remote names must be one line.", "폴더 경로와 원격 이름은 한 줄로 입력해 주세요."))
        }
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "backend \(backend.rawValue)\nremote \(remote)\nlocal \(local)\nfiles \(files ? "on" : "off")\ndata \(data)\n"
        try text.write(to: Self.url, atomically: true, encoding: .utf8)
    }

    /// Where backups go, in words: the folder and the disk it is on, or the folder in Google Drive.
    struct Place {
        let folder: String
        let disk: String?
        let external: Bool
        let connected: Bool
        let drive: Bool

        var sentence: String {
            if drive { return tr("Backups go to the folder “\(folder)” in Google Drive.", "백업은 Google 드라이브의 “\(folder)” 폴더에 저장돼요.") }
            guard let disk else { return tr("Backups go to the folder “\(folder)”.", "백업은 “\(folder)” 폴더에 저장돼요.") }
            return external ? tr("Backups go to the folder “\(folder)” on the disk “\(disk)”.", "백업은 “\(disk)” 디스크의 “\(folder)” 폴더에 저장돼요.")
                            : tr("Backups go to the folder “\(folder)” on \(disk).", "백업은 \(disk)의 “\(folder)” 폴더에 저장돼요.")
        }
    }

    var place: Place? {
        guard hasPlace else { return nil }
        if backend == .gdrive {
            let path = remote.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
            return Place(folder: path.isEmpty ? remote : (path as NSString).lastPathComponent, disk: nil, external: false, connected: true, drive: true)
        }
        let url = URL(fileURLWithPath: local)
        let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeIsInternalKey])
        if let values, let name = values.volumeLocalizedName {
            return Place(folder: url.lastPathComponent, disk: name, external: values.volumeIsInternal == false, connected: true, drive: false)
        }
        // Nothing there: a folder on a disk that is not plugged in, or a folder that is gone.
        let parts = url.pathComponents
        if parts.count > 2, parts[1] == "Volumes" {
            return Place(folder: url.lastPathComponent, disk: parts[2], external: true, connected: false, drive: false)
        }
        return Place(folder: url.lastPathComponent, disk: nil, external: false, connected: true, drive: false)
    }
}

struct StorageCapacity: Codable {
    var target: String
    var attemptedAt: Double
    var available: Int64?
    var total: Int64?
    var stale: Bool
    static var url: URL { StorageConfig.url.deletingLastPathComponent().appendingPathComponent("storage-status.json") }

    static func load(target: String) -> StorageCapacity? {
        guard let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Self.self, from: data), c.target == target else { return nil }
        return c
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}

extension Tools {
    /// Code and data have separate roots, including when scripts are bundled in the app.
    static var codeRoot: URL? {
        let fm = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["LAZYMAC_CODE"].map { URL(fileURLWithPath: $0) },
            Bundle.main.resourceURL,
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
        ].compactMap { $0 }
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("bin/storage.sh").path) }
    }

    static func script(_ name: String) -> String? {
        codeRoot?.appendingPathComponent("bin/\(name)").path
    }
}

@MainActor @Observable
final class StorageModel {
    /// example: the small fictional list, to try LazyMac. restore: the list already in the backup place.
    /// new: an empty list for this Mac, for a real first backup.
    enum Start: String { case example, restore, new }

    var config = StorageConfig.load()
    private(set) var capacity: StorageCapacity?
    private(set) var busy = false
    private(set) var initialized = false
    private(set) var message: String?
    @ObservationIgnored private var refreshing = false

    init() {
        capacity = StorageCapacity.load(target: config.target)
    }

    func reload() {
        config = StorageConfig.load()
        capacity = StorageCapacity.load(target: config.target)
    }

    func save() {
        do {
            try config.save()
            message = tr("Saved.", "저장했어요.")
            capacity = StorageCapacity.load(target: config.target)
            Task { await refreshCapacity() }
        } catch { message = error.localizedDescription }
    }

    /// Asks for the backup folder (or, with `data`, the working data folder) and saves it.
    @discardableResult
    func chooseFolder(data: Bool = false) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Use This Folder", "이 폴더 쓰기")
        panel.message = data ? tr("Choose where LazyMac keeps its working copy of your list.", "LazyMac이 목록 작업본을 둘 폴더를 골라 주세요.")
                             : tr("Choose a folder for your backups. A folder on an external disk is safest.", "백업을 둘 폴더를 골라 주세요. 외장 디스크에 있는 폴더가 가장 안전해요.")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        config = StorageConfig.load()
        if data {
            config.data = url.path
        } else {
            config.local = url.path
            config.backend = .local
        }
        save()
        return true
    }

    func setBackend(_ backend: StorageConfig.Backend) {
        config = StorageConfig.load()
        config.backend = backend
        save()
    }

    func setRemote(_ remote: String) {
        config = StorageConfig.load()
        config.remote = remote
        save()
    }

    func setFiles(_ on: Bool) {
        config = StorageConfig.load()
        config.files = on
        save()
    }

    /// Whether the chosen place already holds a LazyMac backup (its list).
    func placeHasBackup() async -> Bool {
        let c = StorageConfig.load()
        switch c.backend {
        case .local:
            return !c.local.isEmpty && FileManager.default.fileExists(atPath: c.local + "/catalog.tsv")
        case .gdrive:
            guard let rclone = Tools.find("rclone") else { return false }
            let r = await Shell.run([rclone, "lsf", c.remote + "/catalog.tsv"])
            return r.code == 0 && r.out.contains("catalog.tsv")
        }
    }

    func initialize(_ start: Start) async {
        guard !busy else { return }
        initialized = false
        guard let script = Tools.script("storage.sh") else {
            message = tr("The storage script is missing from this app.", "이 앱에 저장소 스크립트가 없어요.")
            return
        }
        busy = true
        defer { busy = false }
        do { try config.save() } catch { message = error.localizedDescription; return }
        let command: [String] = switch start {
        case .restore: ["/bin/zsh", script, "download"]
        case .example: ["/bin/zsh", script, "init"]
        case .new: ["/bin/zsh", script, "init", "empty"]
        }
        let r = await Shell.run(command)
        guard r.code == 0 else { message = SetupModel.lastLine(r); return }
        guard config.isInitialized else {
            message = tr("No LazyMac list was found in this backup place.", "이 백업 장소에서 LazyMac 목록을 찾지 못했어요.")
            return
        }
        message = switch start {
        case .restore: tr("Using the list from your backup place.", "백업 장소의 목록을 쓰고 있어요.")
        case .example: tr("Started with example data. This Mac is the main Mac.", "예제 데이터로 시작했어요. 이 맥이 주 맥이에요.")
        case .new: tr("Started a new list for this Mac.", "이 맥의 새 목록을 만들었어요.")
        }
        if start != .restore {
            do {
                let rows = try Catalog.parse(String(contentsOf: config.dataURL.appendingPathComponent("catalog.tsv"), encoding: .utf8))
                let files = Catalog.setupFiles(chosen: rows.filter { $0.decision == .keep }, all: rows,
                    head: "# Generated by `bun bin/catalog.ts render` from catalog.tsv (keep items only). Do not edit.\n")
                try Catalog.write(files, to: config.dataURL.appendingPathComponent("setup"))
            } catch { message = error.localizedDescription; return }
            let upload = await Shell.run(["/bin/zsh", script, "upload"])
            guard upload.code == 0 else { message = SetupModel.lastLine(upload); return }
        }
        initialized = true
        await refreshCapacity()
    }

    func refreshCapacity() async {
        guard !refreshing else { return }
        let current = StorageConfig.load()
        let target = current.target
        guard !target.isEmpty else { capacity = nil; return }
        refreshing = true
        defer { refreshing = false }
        capacity = StorageCapacity.load(target: target)
        if current.backend == .local {
            var next = capacity ?? StorageCapacity(target: target, attemptedAt: 0, stale: true)
            next.attemptedAt = Date.now.timeIntervalSince1970
            do {
                let attrs = try FileManager.default.attributesOfFileSystem(forPath: target)
                next.available = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
                next.total = (attrs[.systemSize] as? NSNumber)?.int64Value
                next.stale = next.available == nil
            } catch { next.stale = true }
            capacity = next
            try? next.save()
            return
        }
        // Record attempts, not just successes, to avoid retrying a broken remote all day.
        if let capacity, Date.now.timeIntervalSince1970 - capacity.attemptedAt < 86400 { return }
        guard let script = Tools.script("storage.sh") else { return }
        var pending = capacity ?? StorageCapacity(target: target, attemptedAt: 0, stale: true)
        pending.attemptedAt = Date.now.timeIntervalSince1970
        pending.stale = true
        try? pending.save()
        _ = await Shell.run(["/bin/zsh", script, "capacity"])
        // Ignore a response for a destination the user changed while the request was running.
        if StorageConfig.load().target == target { capacity = StorageCapacity.load(target: target) }
    }
}
