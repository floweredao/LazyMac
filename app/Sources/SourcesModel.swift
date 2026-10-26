import AppKit
import Foundation
import Observation

@MainActor @Observable
final class SourcesModel {
    enum Check: Equatable {
        case checking
        case release(tag: String, asset: String)
        case releaseAvailable(repo: String, tag: String, asset: String)
        case failed(String)
        case page
    }

    struct Suggestion: Identifiable, Hashable {
        let repo: String
        let detail: String
        var id: String { repo }
    }

    struct Entry: Identifiable {
        let row: CatalogRow
        var how: String
        var ref: String
        var check: Check?
        var suggestions: [Suggestion]?
        var searching = false
        var id: String { row.id }
        var dirty: Bool { how != row.how || ref != row.ref }
    }

    static let hows = ["release", "download", "build"]

    private(set) var entries: [Entry] = []
    private(set) var repo: URL?
    private(set) var status: String?
    private(set) var busy = false
    private(set) var uncommitted: [String] = []

    var dirty: Bool { entries.contains(where: \.dirty) }
    var invalid: [Entry] { entries.filter { $0.dirty && Self.problem(how: $0.how, ref: $0.ref) != nil } }

    func load(rows: [CatalogRow], repo: URL?) {
        guard !busy else { return }
        self.repo = repo
        let old = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entries = rows.filter { Self.hows.contains($0.how) }.map { row in
            var e = Entry(row: row, how: row.how, ref: row.ref)
            if let prev = old[row.id], prev.how == row.how, prev.ref == row.ref { e.check = prev.check }
            return e
        }
        Task { await refreshUncommitted() }
    }

    func binding(_ id: String) -> Int? { entries.firstIndex { $0.id == id } }

    func setHow(_ id: String, _ how: String) {
        guard let i = binding(id), entries[i].how != how else { return }
        let repo = Self.githubRepo(entries[i].ref)
        entries[i].how = how
        if let repo {
            entries[i].ref = how == "release" ? repo : "https://github.com/\(repo)" + (how == "download" ? "/releases" : "")
        }
        entries[i].check = nil
    }

    func setRef(_ id: String, _ ref: String) {
        guard let i = binding(id) else { return }
        entries[i].ref = ref
        entries[i].check = nil
    }

    func revert(_ id: String) {
        guard let i = binding(id) else { return }
        entries[i].how = entries[i].row.how
        entries[i].ref = entries[i].row.ref
        entries[i].check = nil
    }

    // MARK: Checking

    static func githubRepo(_ ref: String) -> String? {
        let head = String(ref.split(separator: "#", maxSplits: 1).first ?? "")
        if head.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil { return head }
        guard let r = head.range(of: #"github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)"#, options: .regularExpression) else { return nil }
        let parts = head[r].split(separator: "/")
        return "\(parts[1])/\(parts[2])"
    }

    static func problem(how: String, ref: String) -> String? {
        if how == "release" {
            let head = String(ref.split(separator: "#", maxSplits: 1).first ?? "")
            return head.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) == nil
                ? tr("Use owner/repo, optionally #file-pattern", "owner/repo 형식으로 써 주세요 (#파일패턴은 선택)") : nil
        }
        return ref.hasPrefix("https://") || ref.hasPrefix("http://") ? nil : tr("Use a full https:// link", "https://로 시작하는 전체 주소를 써 주세요")
    }

    func installedVersion(_ row: CatalogRow) -> String? {
        let path = Catalog.installedPath(row)
        guard path.hasSuffix(".app") else { return nil }
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String)
    }

    func checkAll() async {
        await withTaskGroup(of: Void.self) { group in
            for e in entries { group.addTask { await self.check(e.id) } }
        }
    }

    func check(_ id: String) async {
        guard repo != nil, let i = binding(id) else { return }
        let e = entries[i]
        if let problem = Self.problem(how: e.how, ref: e.ref) {
            entries[i].check = .failed(problem)
            return
        }
        guard let gh = Self.githubRepo(e.ref) else {
            entries[i].check = .page
            return
        }
        entries[i].check = .checking
        let parts = e.ref.split(separator: "#", maxSplits: 1).map(String.init)
        let pattern = e.how == "release" && parts.count > 1 ? parts[1] : "-"
        guard let script = Tools.script("setup.sh") else { return }
        let result = await Shell.run(["/bin/zsh", script, "--release-asset", gh, pattern])
        guard let j = binding(id), entries[j].how == e.how, entries[j].ref == e.ref else { return }
        let fields = result.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        if result.code == 0, fields.count == 2 {
            entries[j].check = e.how == "release" ? .release(tag: fields[0], asset: fields[1])
                : .releaseAvailable(repo: gh, tag: fields[0], asset: fields[1])
        } else if e.how == "release" {
            let reason = result.err.split(separator: "\n").last.map(String.init) ?? ""
            entries[j].check = .failed(reason.isEmpty ? tr("No release found in \(gh)", "\(gh)에서 릴리즈를 찾지 못했어요") : reason)
        } else {
            entries[j].check = .page
        }
    }

    func useRelease(_ id: String) {
        guard let i = binding(id), case .releaseAvailable(let repo, _, _) = entries[i].check else { return }
        entries[i].how = "release"
        entries[i].ref = repo
        Task { await check(id) }
    }

    // MARK: Finding the repo

    func search(_ id: String) async {
        guard let i = binding(id) else { return }
        entries[i].searching = true
        let row = entries[i].row
        var found: [Suggestion] = []
        func add(_ repo: String, _ detail: String) {
            guard !found.contains(where: { $0.repo.caseInsensitiveCompare(repo) == .orderedSame }) else { return }
            found.append(Suggestion(repo: repo, detail: detail))
        }
        if let feed = updateFeedRepo(row) { add(feed, tr("From the installed app's update feed", "설치된 앱의 업데이트 주소에서 찾음")) }
        if let current = Self.githubRepo(entries[i].ref) { add(current, tr("Written in the catalog now", "지금 카탈로그에 적힌 저장소")) }

        let login = (await Shell.run(["/usr/bin/env", "gh", "api", "user", "--jq", ".login"])).out.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = row.name.replacingOccurrences(of: " ", with: "")
        var queries: [(args: [String], label: String)] = []
        if !login.isEmpty {
            queries.append(([row.name, "--owner", login], tr("In your account", "내 계정")))
            if compact != row.name { queries.append(([compact, "--owner", login], tr("In your account", "내 계정"))) }
        }
        queries.append(((row.name.split(separator: " ").map(String.init)) + ["macos"], "GitHub"))
        queries.append((row.name.split(separator: " ").map(String.init), "GitHub"))
        let results = await withTaskGroup(of: (Int, String).self) { group in
            for (n, q) in queries.enumerated() {
                group.addTask {
                    let r = await Shell.run(["/usr/bin/env", "gh", "search", "repos"] + q.args + ["--limit", "5",
                                            "--json", "fullName,description,stargazersCount",
                                            "--jq", #".[] | [.fullName, (.stargazersCount|tostring), (.description // "")] | @tsv"#])
                    return (n, r.out)
                }
            }
            var all: [(Int, String)] = []
            for await r in group { all.append(r) }
            return all.sorted { $0.0 < $1.0 }
        }
        for (n, out) in results {
            for line in out.split(separator: "\n") {
                let f = line.components(separatedBy: "\t")
                guard f.count == 3 else { continue }
                add(f[0], "\(queries[n].label) · ★ \(f[1])  \(f[2])")
            }
        }
        guard let j = binding(id) else { return }
        entries[j].searching = false
        entries[j].suggestions = Array(found.prefix(10))
    }

    func pick(_ id: String, _ suggestion: Suggestion) {
        guard let i = binding(id) else { return }
        let how = entries[i].how
        entries[i].ref = how == "release" ? suggestion.repo
            : "https://github.com/\(suggestion.repo)" + (how == "download" ? "/releases" : "")
        entries[i].suggestions = nil
        Task { await check(id) }
    }

    private func updateFeedRepo(_ row: CatalogRow) -> String? {
        let path = Catalog.installedPath(row)
        guard path.hasSuffix(".app"),
              let info = NSDictionary(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")),
              let feed = info["SUFeedURL"] as? String else { return nil }
        return Self.githubRepo(feed.replacingOccurrences(of: "raw.githubusercontent.com", with: "github.com"))
    }

    // MARK: Syncing with storage

    func pull() async {
        guard let repo, !dirty, Profiles.machine(repo: repo).role != .main, let script = Tools.script("storage.sh") else { return }
        busy = true
        defer { busy = false }
        let r = await Shell.run(["/bin/zsh", script, "download"])
        status = r.code == 0 ? nil : tr("Could not restore from storage: \(Self.lastLine(r))", "저장소에서 복원하지 못했어요: \(Self.lastLine(r))")
        await refreshUncommitted()
    }

    func refreshUncommitted() async {
        uncommitted = unpushed ? ["catalog.tsv", "setup"] : []
    }

    var canSync: Bool { (dirty || unpushed) && invalid.isEmpty && !busy && repo.map { Profiles.machine(repo: $0).role == .main } == true }

    func sync(onSaved: () -> Void) async {
        guard let repo, canSync else { return }
        busy = true
        defer { busy = false }
        if dirty {
            do { try write(to: repo.appendingPathComponent("catalog.tsv")) } catch {
                status = error.localizedDescription
                return
            }
        }
        unpushed = true
        onSaved()
        guard let bun = AutoBackup.bunPath(), let script = Tools.script("catalog.ts") else {
            status = tr("Saved locally. Install bun to generate setup files and sync.", "로컬에 저장했어요. 설치 목록 생성과 동기화에는 bun이 필요해요.")
            await refreshUncommitted()
            return
        }
        let r = await Shell.run([bun, script, "render"], cwd: repo)
        unpushed = r.code != 0
        status = r.code == 0
            ? tr("Saved and copied to storage.", "저장하고 저장소에 복사했어요.")
            : tr("Saved locally, but sync failed: \(Self.lastLine(r))", "로컬에 저장했지만 동기화에 실패했어요: \(Self.lastLine(r))")
        await refreshUncommitted()
    }

    private(set) var unpushed = false

    func retryPush() async {
        await sync(onSaved: {})
    }

    private func write(to file: URL) throws {
        let changed = tr("catalog.tsv changed on disk. Reopen this window.", "catalog.tsv가 바뀌었어요. 이 창을 다시 열어 주세요.")
        var lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        for e in entries where e.dirty {
            guard e.row.line < lines.count else { throw CatalogError(message: changed) }
            var c = lines[e.row.line].components(separatedBy: "\t")
            guard c.count == 12, c[0] == e.row.section, c[2] == e.row.ids.joined(separator: ",") else { throw CatalogError(message: changed) }
            c[6] = e.how
            c[7] = e.ref
            lines[e.row.line] = c.joined(separator: "\t")
        }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func lastLine(_ r: Shell.Result) -> String {
        (r.err.isEmpty ? r.out : r.err).split(separator: "\n").last.map(String.init) ?? "exit \(r.code)"
    }
}

enum Shell {
    struct Result {
        let code: Int32
        let out: String
        let err: String
    }

    static func run(_ command: [String], cwd: URL? = nil) async -> Result {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: command[0])
            p.arguments = Array(command.dropFirst())
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = Console.path
            p.environment = env
            if let cwd { p.currentDirectoryURL = cwd }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch { return Result(code: 127, out: "", err: error.localizedDescription) }
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Result(code: p.terminationStatus, out: String(decoding: o, as: UTF8.self), err: String(decoding: e, as: UTF8.self))
        }.value
    }
}
