import AppKit
import Foundation
import Observation

struct StorageConfig: Equatable {
    enum Backend: String, CaseIterable { case gdrive, local }
    var backend: Backend = .gdrive
    var remote = "gdrive:LazyMac"
    var local = ""
    var files = false
    var data = NSHomeDirectory() + "/LazyMac-data"

    static var url: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAZYMAC_STORAGE_CONF"]
            ?? BackupConfig.supportDir.appendingPathComponent("storage.conf").path)
    }

    static func load() -> StorageConfig {
        var c = StorageConfig()
        for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "backend": c.backend = Backend(rawValue: parts[1]) ?? .gdrive
            case "remote": c.remote = parts[1]
            case "local": c.local = BackupConfig.expand(parts[1])
            case "files": c.files = parts[1] == "on"
            case "data": c.data = BackupConfig.expand(parts[1])
            default: break
            }
        }
        return c
    }

    var dataURL: URL {
        URL(fileURLWithPath: BackupConfig.expand(ProcessInfo.processInfo.environment["LAZYMAC_DATA"] ?? data))
    }
    var target: String { backend == .local ? local : remote }
    var isInitialized: Bool { FileManager.default.fileExists(atPath: dataURL.appendingPathComponent("catalog.tsv").path) }

    func save() throws {
        guard ![remote, local, data].contains(where: { $0.contains("\n") || $0.contains("\r") }) else {
            throw CatalogError(message: tr("Folder paths and remote names must be one line.", "폴더 경로와 원격 이름은 한 줄로 입력해 주세요."))
        }
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "backend \(backend.rawValue)\nremote \(remote)\nlocal \(local)\nfiles \(files ? "on" : "off")\ndata \(data)\n"
        try text.write(to: Self.url, atomically: true, encoding: .utf8)
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
    var config = StorageConfig.load()
    private(set) var capacity: StorageCapacity?
    private(set) var busy = false
    private(set) var initialized = false
    private(set) var message: String?
    @ObservationIgnored private var refreshing = false

    init() {
        capacity = StorageCapacity.load(target: config.target)
    }

    func save() {
        do {
            try config.save()
            message = tr("Storage settings saved.", "저장소 설정을 저장했어요.")
            capacity = StorageCapacity.load(target: config.target)
            Task { await refreshCapacity() }
        } catch { message = error.localizedDescription }
    }

    func chooseFolder(data: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Use This Folder", "이 폴더 쓰기")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if data { config.data = url.path } else { config.local = url.path }
        save()
    }

    func initialize(restore: Bool) async {
        guard !busy else { return }
        initialized = false
        guard let script = Tools.script("storage.sh") else {
            message = tr("The storage script is missing from this app.", "이 앱에 저장소 스크립트가 없어요.")
            return
        }
        busy = true
        defer { busy = false }
        do { try config.save() } catch { message = error.localizedDescription; return }
        let r = await Shell.run(["/bin/zsh", script, restore ? "download" : "init"])
        guard r.code == 0 else { message = SetupModel.lastLine(r); return }
        guard config.isInitialized else {
            message = tr("No catalog was found in this storage destination.", "이 저장소에서 목록을 찾지 못했어요.")
            return
        }
        message = restore ? tr("Restored the data folder.", "데이터 폴더를 복원했어요.") : tr("Started with example data. This Mac is the main Mac.", "예제 데이터로 시작했어요. 이 맥이 주 맥이에요.")
        if !restore {
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
