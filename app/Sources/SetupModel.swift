import AppKit
import Foundation
import Observation

@MainActor @Observable
final class SetupModel {
    enum Stage: Int, CaseIterable, Identifiable {
        case prepare, choose, review, install
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .prepare: tr("Prepare", "준비")
            case .choose: tr("Choose", "고르기")
            case .review: tr("Review", "확인")
            case .install: tr("Install", "설치")
            }
        }

        var subtitle: String {
            switch self {
            case .prepare: tr("Homebrew and data folder", "Homebrew와 데이터 폴더")
            case .choose: tr("Pick what to bring", "가져갈 것 고르기")
            case .review: tr("See the install order", "설치 순서 보기")
            case .install: tr("Progress", "진행 상황")
            }
        }
    }

    enum StepState { case pending, running, done, failed }
    enum Job { case homebrew, install }

    struct GroupRows: Identifiable {
        let id: String
        let section: String
        let title: String
        let symbol: String
        let rows: [CatalogRow]
    }

    var page: Page = .overview
    var stage: Stage = .prepare
    var selected: Set<String> = []
    var extraSteps: Set<Step> = [.dotfiles, .secrets, .check]
    var showLeftBehind = false
    var search = ""

    private(set) var repo: URL?
    private(set) var rows: [CatalogRow] = []
    private(set) var loadError: String?
    private(set) var brewPath: String?
    private(set) var job: Job?
    private(set) var lastJob: Job?
    private(set) var installSteps: [Step] = []
    private(set) var stepStates: [Step: StepState] = [:]
    private(set) var installFinished = false
    private(set) var failedSteps: [Step] = []

    let console = Console()


    /// The configured data folder, never the code checkout.
    nonisolated static func findRepo() -> URL? {
        let data = StorageConfig.load().dataURL
        return isRepo(data) ? data : nil
    }

    init() {
        console.onLine = { [weak self] line in self?.handle(line) }
        if let found = Self.findRepo() { use(repo: found) }
        Task { await refreshChecks() }
        let show = (ProcessInfo.processInfo.environment["LAZYMAC_SHOW"] ?? "").split(separator: ":").map(String.init)
        if let name = show.first {
            if let p = Page.allCases.first(where: { $0.rawValue == name }) { page = p }
            if let s = Stage.allCases.first(where: { "\($0)" == name }) {
                page = .apps
                if ready || s == .prepare { stage = s }
            }
        }
        showSheet = show.count > 1 ? show[1] : nil
    }

    var hasOwnRestore: Bool { rows.contains { $0.how == "restore" } }

    /// Chosen apps LazyMac never installs; the install screen must tell the user to install them by hand.
    var byHandApps: [CatalogRow] { rows.filter { $0.how == "byhand" && $0.section == "app" && selected.contains($0.id) } }

    /// Set by the LAZYMAC_SHOW screenshot hook: "compare" or "save" opens that sheet on the Choose screen.
    var showSheet: String?

    // MARK: Repo and catalog

    nonisolated static func isRepo(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("catalog.tsv").path)
            && fm.fileExists(atPath: url.appendingPathComponent("groups.tsv").path)
    }

    var ready: Bool { repo != nil }

    func reloadCatalog() {
        if let repo { use(repo: repo, keepSelection: true) }
    }

    func use(repo url: URL, keepSelection: Bool = false) {
        guard Self.isRepo(url) else {
            loadError = tr("\(url.path) does not hold a LazyMac backup list.",
                           "\(url.path) 폴더에 LazyMac 백업 목록이 없어요.")
            return
        }
        do {
            let text = try String(contentsOf: url.appendingPathComponent("catalog.tsv"), encoding: .utf8)
            rows = try Catalog.parse(text)
            Catalog.loadGroups((try? String(contentsOf: url.appendingPathComponent("groups.tsv"), encoding: .utf8)) ?? "")
            repo = url
            loadError = nil
            loadProfiles()
            if !keepSelection { useMachineProfiles() }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func chooseRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = tr("Use This Folder", "이 폴더 쓰기")
        panel.message = tr("Choose the LazyMac data folder", "LazyMac 데이터 폴더를 골라 주세요")
        panel.directoryURL = repo ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                var storage = StorageConfig.load()
                storage.data = url.path
                try storage.save()
                use(repo: storage.dataURL)
            } catch { loadError = error.localizedDescription }
        }
    }

    // MARK: Choosing

    var selectableRows: [CatalogRow] { rows.filter { $0.step != nil } }
    var chosenRows: [CatalogRow] { rows.filter { $0.step != nil && selected.contains($0.id) } }

    var stepsToRun: [Step] {
        let chosen = Set(chosenRows.compactMap(\.step))
        return Step.allCases.filter { $0.hasItems ? chosen.contains($0) : extraSteps.contains($0) }
    }

    func resetSelection() {
        selected = Set(selectableRows.filter { $0.decision == .keep }.map(\.id))
        extraSteps = [.dotfiles, .secrets, .check]
        baseProfile = nil
        addOns = []
        profileError = nil
    }

    // MARK: Profiles

    struct CompareItem: Identifiable, Decodable, Hashable {
        let key: String
        let name: String
        let name_ko: String
        let section: String
        let group: String
        var id: String { key }
        var label: String { Lang.korean && !name_ko.isEmpty ? name_ko : name }
    }

    struct CompareResult: Decodable {
        let host: String
        let scanned: String
        let missing: [CompareItem]
        let extra: [CompareItem]
        let same: Int
        let notChecked: Int
        let unlisted: Int
    }

    private(set) var profiles: [Profile] = []
    private(set) var profileFileErrors: [String] = []
    private(set) var baseProfile: String?
    private(set) var addOns: [String] = []
    private(set) var profileError: String?
    private(set) var profileStatus: String?
    private var profileSelection: Set<String> = []
    private var profileSteps: Set<Step> = []
    private(set) var savingProfile = false
    private(set) var comparing = false
    private(set) var comparison: CompareResult?
    private(set) var compareError: String?
    private(set) var scanning = false
    private(set) var scanStatus: String?

    var baseProfiles: [Profile] { profiles.filter(\.isBase) }
    var addOnProfiles: [Profile] { profiles.filter { !$0.isBase } }
    var role: Profiles.Role { repo.map { Profiles.machine(repo: $0).role } ?? .extra }
    var profileEdited: Bool { baseProfile != nil && (selected != profileSelection || extraSteps != profileSteps) }

    var profileTitle: String {
        guard let base = baseProfile else { return tr("Catalog picks", "추천대로") }
        let names = ([base] + addOns).joined(separator: " + ")
        return profileEdited ? tr("\(names) (edited)", "\(names) (바뀜)") : names
    }

    func loadProfiles() {
        guard let repo else { profiles = []; return }
        let found = Profiles.all(repo: repo)
        profiles = found.profiles
        profileFileErrors = found.errors
    }

    /// The profiles machines.tsv gives this Mac; the catalog picks when it names none or they cannot be read.
    func useMachineProfiles() {
        guard let repo else { return resetSelection() }
        let names = Profiles.machine(repo: repo).profiles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let base = names.first, profiles.contains(where: { $0.name == base && $0.isBase }) else { return resetSelection() }
        apply(base: base, addOns: names.dropFirst().filter { n in profiles.contains { $0.name == n && !$0.isBase } })
    }

    func apply(base: String, addOns names: [String]) {
        guard let repo else { return }
        do {
            let r = try Profiles.resolve(names: ([base] + names).joined(separator: ","), rows: rows, repo: repo)
            selected = Set(selectableRows.filter { r.keys.contains(Profiles.key($0)) }.map(\.id))
            extraSteps = Set(Step.allCases.filter { !$0.hasItems && !r.skip.contains($0.rawValue) })
            baseProfile = base
            addOns = names
            profileSelection = selected
            profileSteps = extraSteps
            profileError = nil
        } catch {
            profileError = error.localizedDescription
        }
    }

    func toggle(addOn name: String) {
        guard let base = baseProfile else { return }
        let order = addOnProfiles.map(\.name)
        let next = addOns.contains(name) ? addOns.filter { $0 != name } : order.filter { addOns.contains($0) || $0 == name }
        apply(base: base, addOns: next)
    }

    func profileExists(_ name: String) -> Bool { profiles.contains { $0.name == name } }

    func isValidProfileName(_ name: String) -> Bool {
        name.range(of: Profiles.nameRule, options: .regularExpression) != nil && !addOnProfiles.contains { $0.name == name }
    }

    /// Writes the current choice as profiles/<name>.txt, then copies shared data to storage.
    func saveProfile(name: String, note: String) async {
        guard let repo, role == .main, isValidProfileName(name), !savingProfile else { return }
        savingProfile = true
        defer { savingProfile = false }
        let skip = Step.allCases.filter { !$0.hasItems && !extraSteps.contains($0) }
        let file = Profiles.dir(repo).appendingPathComponent("\(name).txt")
        do {
            try FileManager.default.createDirectory(at: Profiles.dir(repo), withIntermediateDirectories: true)
            try Profiles.text(note: note, selected: selected, skip: skip, rows: rows).write(to: file, atomically: true, encoding: .utf8)
        } catch {
            profileStatus = tr("Could not save the profile: \(error.localizedDescription)", "프로필을 저장하지 못했어요: \(error.localizedDescription)")
            return
        }
        loadProfiles()
        apply(base: name, addOns: [])
        let path = "profiles/\(name).txt"
        guard let script = Tools.script("storage.sh") else {
            profileStatus = tr("Saved locally, but the storage script is missing.", "로컬에 저장했지만 저장소 스크립트가 없어요.")
            return
        }
        let r = await Shell.run(["/bin/zsh", script, "upload"])
        profileStatus = r.code == 0
            ? tr("Saved \(path) and copied it to storage", "\(path)를 저장하고 저장소에 복사했어요")
            : tr("Saved \(path), but the storage copy failed: \(Self.lastLine(r))", "\(path)는 저장했지만 저장소 복사에 실패했어요: \(Self.lastLine(r))")
    }

    nonisolated static func lastLine(_ r: Shell.Result) -> String {
        let text = (r.err.isEmpty ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.components(separatedBy: "\n").last ?? "exit \(r.code)"
    }

    /// Compares the current choice with this Mac's last scan (inventory/<host>/) through bin/catalog.ts compare.
    func compare() async {
        guard let repo, !comparing else { return }
        comparing = true
        defer { comparing = false }
        compareError = nil
        guard let bun = AutoBackup.bunPath() else {
            comparison = nil
            compareError = tr("Comparing needs bun (the bun step installs it).", "비교하려면 bun이 필요해요 (bun 단계에서 설치돼요).")
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("lazymac")
        let file = support.appendingPathComponent("compare-selection.txt")
        let skip = Step.allCases.filter { !$0.hasItems && !extraSteps.contains($0) }
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try Profiles.text(note: "", selected: selected, skip: skip, rows: rows).write(to: file, atomically: true, encoding: .utf8)
        } catch {
            compareError = error.localizedDescription
            return
        }
        guard let script = Tools.script("catalog.ts") else { return }
        let r = await Shell.run([bun, script, "compare", "--file", file.path, "--json"], cwd: repo)
        if r.code == 0, let result = try? JSONDecoder().decode(CompareResult.self, from: Data(r.out.utf8)) {
            comparison = result
        } else {
            comparison = nil
            compareError = r.err.contains("no scan for")
                ? tr("This Mac (\(Profiles.host)) has no scan yet. Press Scan This Mac.", "이 맥(\(Profiles.host))은 아직 훑은 기록이 없어요. '이 맥 훑기'를 눌러 주세요.")
                : tr("Could not compare: \(Self.lastLine(r))", "비교하지 못했어요: \(Self.lastLine(r))")
        }
    }

    /// Scans this Mac into inventory/<host>/ and copies only its own inventory to storage.
    func scanThisMac() async {
        guard let repo, !scanning else { return }
        scanning = true
        defer { scanning = false }
        scanStatus = nil
        guard let script = Tools.script("scan.sh") else { return }
        let r = await Shell.run(["/bin/zsh", script], cwd: repo)
        let last = r.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last ?? ""
        scanStatus = r.code == 0
            ? tr("Scanned this Mac and copied it to storage (\(last))", "이 맥을 훑고 저장소에 복사했어요 (\(last))")
            : tr("Scan failed: \(last.isEmpty ? Self.lastLine(r) : last)", "훑기에 실패했어요: \(last.isEmpty ? Self.lastLine(r) : last)")
    }

    // MARK: Auto backup

    private(set) var backupInstalled: BackupSchedule?
    var backupOn = false
    var backupDraft = BackupSchedule()
    /// Automatic backups wait on a hotspot or in Low Data Mode (bin/due.sh). Off unless the person turns it on.
    var backupWaitMetered = false
    private(set) var backupWaitMeteredSaved = false
    private(set) var backupStatus: String?
    private(set) var backupBusy = false

    var backupDirty: Bool {
        backupOn != (backupInstalled != nil) || (backupOn && (backupDraft != backupInstalled || backupWaitMetered != backupWaitMeteredSaved))
    }

    func reloadBackup() {
        backupInstalled = AutoBackup.current()
        backupOn = backupInstalled != nil
        backupDraft = backupInstalled ?? BackupSchedule()
        backupWaitMeteredSaved = BackupState.waitsOnMetered
        backupWaitMetered = backupWaitMeteredSaved
    }

    func applyBackup() {
        guard !backupBusy else { return }
        backupBusy = true
        defer { backupBusy = false }
        let draft = backupDraft
        do {
            if backupOn {
                try AutoBackup.install(draft, repo: repo)
                BackupState.set("metered", backupWaitMetered ? "wait" : nil)
                backupStatus = tr("Auto backup is on: \(draft.summary)", "자동 백업을 켰어요: \(draft.summary)")
            } else {
                try AutoBackup.remove()
                backupStatus = tr("Auto backup is off. Back up with Back Up Now when you want.",
                                  "자동 백업을 껐어요. 필요할 때 '지금 백업'을 눌러 주세요.")
            }
            reloadBackup()
        } catch {
            backupStatus = error.localizedDescription
        }
    }

    func isOn(_ row: CatalogRow) -> Bool { selected.contains(row.id) }

    func set(_ row: CatalogRow, _ on: Bool) {
        if on { selected.insert(row.id) } else { selected.remove(row.id) }
    }

    func set(_ rows: [CatalogRow], _ on: Bool) {
        for r in rows { set(r, on) }
    }

    func rows(for step: Step) -> [CatalogRow] { chosenRows.filter { $0.step == step } }

    var groups: [GroupRows] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = selectableRows.filter { r in
            (showLeftBehind || r.decision == .keep || selected.contains(r.id))
                && (q.isEmpty || [r.label, r.name, r.what, r.source].contains { $0.lowercased().contains(q) })
        }
        var out: [GroupRows] = []
        for section in Catalog.sectionOrder {
            let inSection = visible.filter { $0.section == section }
            var order: [String] = []
            for r in inSection where !order.contains(r.group) { order.append(r.group) }
            // groups.tsv order first; a group it does not list keeps its catalog position at the end.
            let rank = { (g: String) in Catalog.groupOrder.firstIndex(of: "\(section)/\(g)") ?? Int.max }
            order = order.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
            for g in order {
                let title = "\(Catalog.sectionTitle(section)) · \(Catalog.groupTitle(section, g))"
                out.append(GroupRows(id: "\(section)/\(g)", section: section, title: title,
                                     symbol: Catalog.sectionSymbols[section] ?? "circle",
                                     rows: inSection.filter { $0.group == g }))
            }
        }
        return out
    }

    // MARK: Getting ready

    func refreshChecks() async {
        let fm = FileManager.default
        brewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { fm.isExecutableFile(atPath: $0) }
    }

    nonisolated static func exitCode(_ command: [String]) async -> Int32 {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: command[0])
            p.arguments = Array(command.dropFirst())
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(returning: 127) }
        }
    }

    func installHomebrew() {
        start(.homebrew, tr("Install Homebrew", "Homebrew 설치"), ["/bin/bash", "-c",
            "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""])
    }

    func copyCodeAndContinue() {
        guard let code = console.oneTimeCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        console.send("")
    }

    private func start(_ job: Job, _ title: String, _ command: [String]) {
        guard self.job == nil else { return }
        self.job = job
        lastJob = job
        console.run(title: title, command: command) { [weak self] code in
            guard let self else { return }
            self.job = nil
            Task { await self.refreshChecks() }
        }
    }

    // MARK: Installing

    var installing: Bool { job == .install }
    var currentStep: Step? { installSteps.first { stepStates[$0] == .running } }
    var doneCount: Int { installSteps.filter { stepStates[$0] == .done }.count }

    func startInstall() { install(stepsToRun) }
    func retryFailed() { install(failedSteps) }

    private func install(_ steps: [Step]) {
        guard repo != nil, job == nil, !steps.isEmpty else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lazymac/selection")
        do {
            try Catalog.write(Catalog.setupFiles(chosen: chosenRows, all: rows), to: dir)
        } catch {
            loadError = tr("Could not save the chosen lists: \(error.localizedDescription)",
                           "선택한 목록을 저장하지 못했어요: \(error.localizedDescription)")
            return
        }
        installSteps = steps
        stepStates = Dictionary(uniqueKeysWithValues: steps.map { ($0, .pending) })
        installFinished = false
        failedSteps = []
        job = .install
        lastJob = .install
        stage = .install
        guard let script = Tools.script("setup.sh") else { job = nil; return }
        console.run(title: tr("Install", "설치"), command: ["/bin/zsh", script] + steps.map(\.rawValue),
                    environment: ["LAZYMAC_SETUP_DIR": dir.path]) { [weak self] code in
            self?.finishInstall(code)
        }
    }

    private func handle(_ line: String) {
        guard job == .install else { return }
        if line.hasPrefix("== "), let name = line.dropFirst(3).split(separator: ":").first, let step = Step(rawValue: String(name)) {
            if let running = currentStep { stepStates[running] = .done }
            stepStates[step] = .running
        } else if line.hasPrefix("Finished with problems in:") {
            let names = line.replacingOccurrences(of: "Finished with problems in:", with: "")
                .components(separatedBy: ". Fix").first ?? ""
            failedSteps = names.split(separator: " ").compactMap { Step(rawValue: String($0)) }
        }
    }

    private func finishInstall(_ code: Int32) {
        job = nil
        installFinished = true
        for s in installSteps {
            if failedSteps.contains(s) {
                stepStates[s] = .failed
            } else if stepStates[s] == .running {
                stepStates[s] = code == 0 || !failedSteps.isEmpty ? .done : .failed
            } else if code == 0 {
                stepStates[s] = .done
            }
        }
        if code != 0 {
            failedSteps = installSteps.filter { stepStates[$0] == .failed || stepStates[$0] == .pending }
        }
        NSApp.requestUserAttention(.informationalRequest)
    }

    func canOpen(_ s: Stage) -> Bool {
        switch s {
        case .prepare: true
        case .choose, .review: ready
        case .install: !installSteps.isEmpty
        }
    }

    func isComplete(_ s: Stage) -> Bool {
        switch s {
        case .prepare: ready
        case .choose, .review: !installSteps.isEmpty || stage.rawValue > s.rawValue
        case .install: installFinished && failedSteps.isEmpty
        }
    }
}
