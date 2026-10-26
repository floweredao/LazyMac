import AppKit
import SwiftUI

// MARK: - Back Up > This Mac

/// The home screen. Until a backup place is chosen and the list exists it is the first-run flow; then it shows
/// how the last backup went, the one Back Up This Mac button, and what a backup holds.
struct OverviewView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(MacBackup.self) private var mac
    @State private var parts = BackupParts()
    @State private var last = DailyLog.latest()

    var body: some View {
        Group {
            if storage.config.hasPlace && storage.config.isInitialized {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusHeader(last: last)
                        Form {
                            if mac.running || mac.outcome?.ok == false { RunStepsSection() }
                            PartsSection(parts: parts)
                            DetailsSection(last: last)
                        }
                        .formStyle(.grouped)
                        .scrollDisabled(true)
                        .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                FirstRunView()
            }
        }
        .consoleSheet()
        .onAppear(perform: reload)
        .onChange(of: mac.running) { if !mac.running { reload() } }
        .onChange(of: backup.job) { if backup.job == nil { reload() } }
        .onChange(of: storage.config) { reload() }
    }

    private func reload() {
        backup.refresh()
        model.reloadBackup()
        last = DailyLog.latest()
        parts = BackupParts.read(data: storage.config.dataURL, host: Profiles.host)
        if storage.config.isInitialized, model.repo == nil { model.use(repo: storage.config.dataURL) }
    }
}

struct StatusHeader: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(MacBackup.self) private var mac
    let last: DailyLog?

    private struct Status {
        let kind: StatusLabel.Kind
        let text: String
        let problem: BackupProblem?
    }

    private var status: Status {
        if let place = storage.config.place, !place.connected, let disk = place.disk {
            return Status(kind: .problem, text: tr("Your backup disk “\(disk)” is not connected.", "백업 디스크 “\(disk)”가 연결되어 있지 않아요."),
                          problem: BackupProblem(text: tr("Connect it to back up, or choose another place.", "디스크를 연결하거나 다른 곳을 골라 주세요."), fix: .choosePlace))
        }
        if let problem = mac.startProblem { return Status(kind: .problem, text: problem, problem: nil) }
        let outcome = mac.outcome.map { (ok: $0.ok, date: Optional($0.date), reason: $0.reason ?? "") }
            ?? last.map { (ok: $0.ok, date: $0.date, reason: $0.detail) }
        guard let outcome else {
            return Status(kind: .info, text: tr("This Mac has not been backed up yet.", "이 맥은 아직 백업하지 않았어요."), problem: nil)
        }
        let when = outcome.date.map(whenPhrase) ?? tr("recently", "최근")
        if outcome.ok {
            return Status(kind: .ok, text: tr("Last backup: \(when). Everything is OK.", "마지막 백업: \(when), 모두 잘 됐어요."), problem: nil)
        }
        return Status(kind: .problem, text: tr("The last backup did not finish (\(when)).", "마지막 백업이 끝나지 못했어요 (\(when))."),
                      problem: BackupProblem.explain(outcome.reason))
    }

    private var canBackUp: Bool {
        !mac.running && !backup.busy && storage.config.place?.connected != false && Helper.missing(main: model.role == .main).isEmpty
    }

    var body: some View {
        let status = status
        VStack(alignment: .leading, spacing: Space.l) {
            Text(tr("Back Up", "백업"))
                .font(AppText.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.s) {
                if mac.running {
                    HStack(spacing: Space.m) {
                        ProgressView().controlSize(.small)
                        Text(mac.currentStep.map { tr("Backing up: \($0.title)…", "백업하는 중: \($0.title)…") } ?? tr("Starting the backup…", "백업을 시작하는 중…"))
                            .font(AppText.title3.weight(.semibold))
                    }
                } else {
                    StatusLabel(kind: status.kind, text: status.text)
                        .font(AppText.title3.weight(.semibold))
                    if let problem = status.problem { ProblemLine(problem: problem) }
                }
                PlaceLine()
            }
            MissingHelpersLine()
            AdaptiveRow {
                Button {
                    mac.start(main: model.role == .main, folders: storage.config.files)
                } label: {
                    Text(tr("Back Up This Mac", "이 맥 백업하기")).frame(minWidth: 150 * TextScale.current)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canBackUp)
                .fixedSize()
            } trailing: {
                ScheduleLine()
            }
        }
        .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
        .padding(.horizontal, Space.page)
        .padding(.top, 26)
        .padding(.bottom, Space.xs)
    }
}

struct ProblemLine: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(\.openSettings) private var openSettings
    @Environment(\.consoleSheet) private var consoleSheet
    let problem: BackupProblem

    var body: some View {
        AdaptiveRow {
            Text(problem.text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } trailing: {
            switch problem.fix {
            case .install(let tools):
                Button(tr("Install \(tools.map(\.rawValue).joined(separator: " and "))", "\(tools.map(\.rawValue).joined(separator: ", ")) 설치")) {
                    backup.install(tools)
                    consoleSheet.wrappedValue = true
                }
                .disabled(backup.busy).fixedSize()
            case .choosePlace:
                Button(tr("Choose Place…", "장소 고르기…")) { SettingsTab.open(.place, openSettings) }.fixedSize()
            case .chooseFolders:
                Button(tr("Choose Folders…", "폴더 고르기…")) { model.page = .folders }.fixedSize()
            case .fullDiskAccess:
                Button(tr("Open Privacy Settings…", "개인정보 설정 열기…")) { BackupModel.openFullDiskAccess() }.fixedSize()
            case .details, nil:
                EmptyView()
            }
        }
    }
}

struct PlaceLine: View {
    @Environment(StorageModel.self) private var storage
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let place = storage.config.place {
            AdaptiveRow {
                Text(place.sentence + free)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(storage.config.target)
            } trailing: {
                Button(tr("Change…", "바꾸기…")) { SettingsTab.open(.place, openSettings) }
                    .buttonStyle(.link)
                    .fixedSize()
            }
        }
    }

    private var free: String {
        guard let c = storage.capacity, let bytes = c.available, !c.stale else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return tr(" \(size) free.", " \(size) 남았어요.")
    }
}

struct ScheduleLine: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        HStack(spacing: Space.s) {
            Text(model.backupInstalled.map { tr("Backs up by itself: \($0.summary.lowercasedFirst)", "자동 백업: \($0.summary)") }
                 ?? tr("Automatic backup is off.", "자동 백업은 꺼져 있어요."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.backupInstalled == nil ? tr("Turn On…", "켜기…") : tr("Change…", "바꾸기…")) { model.page = .schedule }
                .buttonStyle(.link)
                .fixedSize()
        }
    }
}

struct MissingHelpersLine: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(\.consoleSheet) private var consoleSheet

    var body: some View {
        let missing = Helper.missing(main: model.role == .main || model.repo == nil)
        if !missing.isEmpty {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: Space.xs) {
                    StatusLabel(kind: .problem, text: tr("First install the free tools LazyMac uses:", "먼저 LazyMac이 쓰는 무료 도구를 설치해 주세요:"))
                    ForEach(missing) { tool in
                        Text(verbatim: "• \(tool.rawValue): \(tool.purpose)")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } trailing: {
                Button(tr("Install Tools", "도구 설치")) {
                    backup.install(missing)
                    consoleSheet.wrappedValue = true
                }
                .disabled(backup.busy)
                .fixedSize()
            }
        }
    }
}

struct RunStepsSection: View {
    @Environment(MacBackup.self) private var mac

    var body: some View {
        Section {
            if mac.running {
                ProgressView(value: Double(mac.doneCount), total: Double(max(mac.steps.count, 1)))
                    .accessibilityLabel(tr("Backup progress", "백업 진행"))
            }
            ForEach(mac.steps) { step in
                let state = mac.states[step] ?? .waiting
                HStack(spacing: Space.l) {
                    Group {
                        switch state {
                        case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
                        case .running: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                    .frame(width: 18 * TextScale.current)
                    Text(step.title)
                        .font(AppText.body.weight(state == .running ? .semibold : .regular))
                        .foregroundStyle(state == .waiting ? .secondary : .primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(state == .done ? tr("done", "완료") : state == .failed ? tr("problem", "문제") : state == .running ? tr("running", "진행 중") : tr("waiting", "대기"))
            }
        } header: {
            Text(mac.running ? tr("Backing up", "백업하는 중") : tr("Where it stopped", "멈춘 곳"))
        }
    }
}

struct PartsSection: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(\.consoleSheet) private var consoleSheet
    @State private var askLock = false
    let parts: BackupParts

    private var main: Bool { model.role == .main }

    var body: some View {
        Section {
            PartRow(symbol: "square.grid.2x2", title: tr("Apps and tools", "앱과 도구"), lines: appsLines, saved: parts.scannedAt != nil)
            PartRow(symbol: "slider.horizontal.3", title: tr("Settings", "설정"), lines: [settingsLine], saved: main && parts.settingsAt != nil)
            passwords
            folders
        } header: {
            Text(tr("What a backup holds", "백업하는 것"))
        }
        .alert(tr("Lock your passwords and sign-ins?", "비밀번호와 로그인 정보를 잠글까요?"), isPresented: $askLock) {
            Button(tr("Cancel", "취소"), role: .cancel) {}
            Button(tr("Lock Them", "잠그기")) {
                backup.lockSecrets(startList: true)
                consoleSheet.wrappedValue = true
            }
        } message: {
            Text(tr("LazyMac locks the usual sign-in files, like SSH keys and GitHub and cloud tool sign-ins, with a passphrase you choose. Keep the passphrase somewhere safe: without it nobody can open them, not even LazyMac.",
                    "SSH 키, GitHub와 클라우드 도구 로그인 같은 흔한 로그인 파일을 직접 정한 암호로 잠가요. 암호는 안전한 곳에 꼭 적어 두세요. 암호가 없으면 LazyMac도 열 수 없어요."))
        }
    }

    private var appsLines: [String] {
        guard let apps = parts.foundApps, let scanned = parts.scannedAt else {
            return [tr("Not checked yet. The next backup lists them.", "아직 살펴보지 않았어요. 다음 백업 때 목록을 만들어요.")]
        }
        let tools = parts.foundTools ?? 0
        let found = tr("\(apps) apps and \(tools) tools on this Mac · checked \(dayPhrase(scanned))",
                       "이 맥의 앱 \(apps)개, 도구 \(tools)개 · \(dayPhrase(scanned)) 확인")
        let list = parts.listItems > 0
            ? tr("\(parts.listItems) are on your list to bring to a new Mac.", "새 맥에 가져갈 목록에 \(parts.listItems)개가 있어요.")
            : tr("Your list for a new Mac is still empty.", "새 맥에 가져갈 목록은 아직 비어 있어요.")
        return [found, list]
    }

    private var settingsLine: String {
        guard main else { return tr("Your main Mac saves these.", "주 맥에서 저장해요.") }
        guard let saved = parts.settingsAt else { return tr("Saved with the next backup.", "다음 백업 때 저장해요.") }
        return tr("\(parts.settingsFiles) settings files and \(parts.macSettings) Mac settings · saved \(dayPhrase(saved))",
                  "설정 파일 \(parts.settingsFiles)개, 맥 설정 \(parts.macSettings)개 · \(dayPhrase(saved)) 저장")
    }

    @ViewBuilder private var passwords: some View {
        let title = tr("Passwords and sign-ins", "비밀번호와 로그인")
        if !main {
            PartRow(symbol: "key", title: title, lines: [tr("Your main Mac keeps these.", "주 맥에서 보관해요.")], saved: parts.bundleAt != nil)
        } else if Helper.age.path == nil {
            PartRow(symbol: "key", title: title, lines: [tr("Needs age, a free tool that \(Helper.age.purpose).", "age가 필요해요. 무료 도구이고, \(Helper.age.purpose).")], saved: false) {
                Button(tr("Install age", "age 설치")) {
                    backup.install([.age])
                    consoleSheet.wrappedValue = true
                }
                .disabled(backup.busy)
            }
        } else if !parts.hasManifest {
            PartRow(symbol: "key", title: title, lines: [tr("Not set up yet. Lock your sign-in keys with a passphrase you choose.", "아직 준비 전이에요. 직접 정한 암호로 로그인 키를 잠가 둘 수 있어요.")], saved: false) {
                Button(tr("Set Up…", "준비하기…")) { askLock = true }.disabled(backup.busy)
            }
        } else if let locked = parts.bundleAt {
            PartRow(symbol: "key", title: title, lines: [tr("Locked with your passphrase · saved \(dayPhrase(locked))", "내 암호로 잠금 · \(dayPhrase(locked)) 저장")], saved: true) {
                Button(tr("Update…", "다시 잠그기…")) {
                    backup.lockSecrets(startList: false)
                    consoleSheet.wrappedValue = true
                }
                .disabled(backup.busy)
            }
        } else {
            PartRow(symbol: "key", title: title, lines: [tr("Not locked yet.", "아직 잠그지 않았어요.")], saved: false) {
                Button(tr("Lock and Save…", "잠가서 저장…")) {
                    backup.lockSecrets(startList: false)
                    consoleSheet.wrappedValue = true
                }
                .disabled(backup.busy)
            }
        }
    }

    @ViewBuilder private var folders: some View {
        let on = Binding(get: { storage.config.files }, set: { storage.setFiles($0); if $0 && backup.config.folders.isEmpty { model.page = .folders } })
        let count = backup.config.folders.count
        let line: String = !storage.config.files
            ? tr("Optional. Also copy folders that are not on iCloud or GitHub.", "선택 사항이에요. iCloud나 GitHub에 없는 폴더도 함께 복사해요.")
            : count == 0 ? tr("On, but no folders are chosen yet.", "켜져 있지만 아직 고른 폴더가 없어요.")
            : tr(count == 1 ? "1 folder is copied with every backup." : "\(count) folders are copied with every backup.", "백업할 때마다 폴더 \(count)개를 복사해요.")
        PartRow(symbol: "folder", title: tr("Files and folders", "파일과 폴더"), lines: [line], saved: false, problem: storage.config.files && count == 0) {
            if storage.config.files {
                Button(tr("Choose Folders…", "폴더 고르기…")) { model.page = .folders }
            }
            Toggle(tr("Copy folders too", "폴더도 복사"), isOn: on)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(tr("Copy folders too", "폴더도 복사"))
        }
    }
}

struct PartRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let lines: [String]
    let saved: Bool
    var problem = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        AdaptiveRow {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Image(systemName: symbol)
                    .font(AppText.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28 * TextScale.current)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(AppText.headline)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(AppText.callout)
                            .foregroundStyle(problem ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } trailing: {
            trailing.fixedSize()
            if saved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel(tr("Saved", "저장됨"))
            } else if problem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(tr("Needs attention", "확인 필요"))
            }
        }
        .padding(.vertical, Space.xs)
    }
}

extension PartRow where Trailing == EmptyView {
    init(symbol: String, title: String, lines: [String], saved: Bool) {
        self.init(symbol: symbol, title: title, lines: lines, saved: saved, problem: false) { EmptyView() }
    }
}

struct DetailsSection: View {
    @Environment(MacBackup.self) private var mac
    let last: DailyLog?
    @State private var open = false

    var body: some View {
        let lines = mac.running || mac.outcome != nil ? mac.lines : (last?.lastRunLines ?? [])
        if !lines.isEmpty {
            Section {
                DisclosureGroup(tr("Details of the last backup", "마지막 백업 자세히 보기"), isExpanded: $open) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ScrollView {
                            Text(lines.suffix(300).joined(separator: "\n"))
                                .font(AppText.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 180)
                        if let url = last?.url {
                            Button(tr("Open the Log File", "로그 파일 열기")) { NSWorkspace.shared.open(url) }.fixedSize()
                        }
                    }
                    .padding(.top, Space.s)
                }
            }
        }
    }
}

// MARK: - First run

/// Two steps for a Mac that has no backup yet: choose where backups go, then back up.
struct FirstRunView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(MacBackup.self) private var mac
    @Environment(\.openSettings) private var openSettings
    @State private var hasBackup = false
    @State private var working = false

    private var place: StorageConfig.Place? { storage.config.place }
    private var placeReady: Bool {
        guard let place else { return false }
        if place.drive { return backup.rclonePath != nil && backup.remotes.contains(backup.config.remoteName) }
        return place.connected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.page) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(tr("Back up this Mac", "이 맥 백업하기"))
                        .font(AppText.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(tr("LazyMac saves the list of your apps, your settings and your sign-ins, so a new Mac can be set up the same way.",
                            "LazyMac은 앱 목록, 설정, 로그인 정보를 저장해 두었다가 새 맥을 똑같이 꾸며 줘요."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FirstRunStep(number: 1, done: placeReady, active: !placeReady, title: tr("Choose where backups go", "백업을 둘 곳 고르기")) {
                    if let place, placeReady {
                        StatusLabel(kind: .ok, text: place.sentence)
                    } else if let place, place.drive {
                        StatusLabel(kind: .problem, text: tr("Google Drive is not connected yet. Finish the steps in Settings.", "Google 드라이브가 아직 연결되지 않았어요. 설정에서 남은 단계를 마쳐 주세요."))
                    } else if let place, !place.connected {
                        StatusLabel(kind: .problem, text: tr("The disk “\(place.disk ?? "")” is not connected. Connect it, or choose another folder.", "“\(place.disk ?? "")” 디스크가 연결되어 있지 않아요. 디스크를 연결하거나 다른 폴더를 골라 주세요."))
                    } else {
                        Text(tr("A folder on an external disk is safest: the backup stays safe even if this Mac breaks. Any folder works.",
                                "외장 디스크의 폴더가 가장 안전해요. 이 맥이 고장 나도 백업은 남으니까요. 어느 폴더든 괜찮아요."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Space.l) {
                        if placeReady {
                            Button(tr("Choose Another Folder…", "다른 폴더 고르기…")) { storage.chooseFolder() }.fixedSize()
                        } else {
                            Button(tr("Choose Folder…", "폴더 고르기…")) { storage.chooseFolder() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .keyboardShortcut(.defaultAction)
                                .fixedSize()
                        }
                        Button(place?.drive == true ? tr("Open Google Drive Settings…", "Google 드라이브 설정 열기…") : tr("Use Google Drive Instead…", "Google 드라이브 쓰기…")) {
                            if place?.drive != true {
                                storage.config.backend = .gdrive
                                storage.save()
                            }
                            SettingsTab.open(.place, openSettings)
                        }
                        .buttonStyle(.link)
                        .fixedSize()
                    }
                }
                FirstRunStep(number: 2, done: false, active: placeReady, title: tr("Back up now", "지금 백업하기")) {
                    Text(hasBackup
                         ? tr("This place already has a LazyMac backup. LazyMac uses its list on this Mac and adds this Mac to it.",
                              "이 장소에는 이미 LazyMac 백업이 있어요. 그 목록을 이 맥에서 쓰고, 이 맥도 함께 저장해요.")
                         : tr("LazyMac lists your apps and tools, saves your settings and copies them to the backup place. It takes about a minute.",
                              "LazyMac이 앱과 도구 목록을 만들고 설정을 저장한 뒤 백업 장소로 복사해요. 1분쯤 걸려요."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if placeReady { MissingHelpersLine() }
                    HStack(spacing: Space.l) {
                        Button(tr("Back Up This Mac", "이 맥 백업하기")) { start() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(placeReady ? .defaultAction : nil)
                            .disabled(!placeReady || working || mac.running || !Helper.missing(main: !hasBackup).isEmpty)
                            .fixedSize()
                        if working || storage.busy { ProgressView().controlSize(.small) }
                    }
                    if let message = storage.message, !storage.initialized, !working {
                        StatusLabel(kind: .info, text: message)
                    }
                }
            }
            .frame(maxWidth: Metrics.firstRunWidth, alignment: .leading)
            .padding(.horizontal, Space.page)
            .padding(.top, 26)
            .padding(.bottom, Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: storage.config.target) {
            backup.refresh()
            hasBackup = await storage.placeHasBackup()
        }
    }

    private func start() {
        working = true
        Task {
            defer { working = false }
            if !storage.config.isInitialized {
                await storage.initialize(hasBackup ? .restore : .new)
                guard storage.initialized else { return }
                model.use(repo: storage.config.dataURL)
                backup.refresh()
            }
            mac.start(main: model.role == .main, folders: storage.config.files)
        }
    }
}

struct FirstRunStep<Content: View>: View {
    let number: Int
    let done: Bool
    let active: Bool
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            StageBadge(number: number, complete: done, active: active)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 * TextScale.current }
            VStack(alignment: .leading, spacing: Space.m) {
                Text(title)
                    .font(AppText.title2.weight(.semibold))
                    .foregroundStyle(active || done ? .primary : .secondary)
                content
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Output of tool installs and the passwords bundle

private struct ConsoleSheetKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var consoleSheet: Binding<Bool> {
        get { self[ConsoleSheetKey.self] }
        set { self[ConsoleSheetKey.self] = newValue }
    }
}

extension View {
    func consoleSheet() -> some View { modifier(ConsoleSheetHost()) }
}

private struct ConsoleSheetHost: ViewModifier {
    @Environment(BackupModel.self) private var backup
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .environment(\.consoleSheet, $shown)
            .sheet(isPresented: $shown) {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text(backup.console.title.isEmpty ? tr("Output", "출력") : backup.console.title)
                        .font(AppText.title2.bold())
                    Text(tr("When it asks for a password or passphrase, type it in the field at the bottom and press Return.",
                            "암호를 물어보면 아래 칸에 입력하고 Return을 눌러 주세요."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ConsolePanel(console: backup.console)
                        .frame(minHeight: 280)
                    if let message = backup.message, !backup.console.running {
                        Text(message).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button(tr("Stop", "중지")) { backup.console.stop() }
                            .disabled(!backup.console.running)
                            .fixedSize()
                        Button(tr("Done", "완료")) { shown = false }
                            .keyboardShortcut(.defaultAction)
                            .disabled(backup.console.running)
                            .fixedSize()
                    }
                }
                .padding(Space.xxl + Space.xs)
                .frame(width: 600)
            }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

func folderCount(_ n: Int) -> String { tr(n == 1 ? "1 folder" : "\(n) folders", "\(n)개") }

struct RunRow: View {
    let title: String
    let run: BackupRun?

    var body: some View {
        LabeledContent(title) {
            if let run {
                StatusLabel(kind: run.ok ? .ok : .problem,
                            text: (run.ok ? tr("Done", "끝남") : tr("Problems", "문제 있음")) + " · " + run.date.formatted(.relative(presentation: .named).locale(Lang.locale)))
                    .help(run.date.formatted(Date.FormatStyle(date: .complete, time: .standard).locale(Lang.locale)))
            } else {
                Text(tr("Never", "아직 없음")).foregroundStyle(.secondary)
            }
        }
    }
}

struct BackupConsole: View {
    @Environment(BackupModel.self) private var backup

    var body: some View {
        if let job = backup.lastJob, [.backup, .check, .listCloud, .restore].contains(job),
           backup.console.running || !backup.console.lines.isEmpty {
            ConsolePanel(console: backup.console)
                .frame(height: 240)
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: Metrics.contentWidth)
        }
    }
}

/// The newest ~/Library/Logs/lazymac-daily/<date>.log: when the last run (scheduled or from the app) ended and how.
struct DailyLog {
    let url: URL
    let date: Date?
    let ok: Bool
    let detail: String

    static func latest() -> DailyLog? {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}\.log$"#, options: .regularExpression) != nil }.sorted()
        for name in files.reversed() {
            let url = dir.appendingPathComponent(name)
            let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            guard let end = lines.last(where: { $0.contains("=== ok") || $0.contains(" FAIL: ") }) else { continue }
            let ok = end.contains("=== ok")
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let detail = ok ? "" : end.components(separatedBy: " FAIL: ").last ?? ""
            return DailyLog(url: url, date: f.date(from: String(end.prefix(19))), ok: ok, detail: detail)
        }
        return nil
    }
}

// MARK: - Back Up > Folders

struct FoldersView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @State private var excludes = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: tr("Folders", "폴더"),
                               subtitle: tr("Optional. Copy folders that are not on iCloud or GitHub, like projects, photos or notes. Nothing is ever deleted, here or in the backup.",
                                            "선택 사항이에요. 프로젝트, 사진, 메모처럼 iCloud나 GitHub에 없는 폴더를 복사해요. 여기서도 백업에서도 아무것도 지우지 않아요."))
                    Form {
                        Section {
                            Toggle(tr("Copy these folders with every backup", "백업할 때마다 이 폴더도 복사하기"),
                                   isOn: Binding(get: { storage.config.files }, set: { storage.setFiles($0) }))
                            PlaceLine()
                        }
                        Section {
                            if backup.config.folders.isEmpty {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(tr("No folders yet", "아직 폴더가 없어요")).font(AppText.headline)
                                    Text(tr("Add folders that are not on GitHub or iCloud, like project files, photos or notes.",
                                            "GitHub나 iCloud에 없는 폴더를 넣어요. 프로젝트 파일, 사진, 메모 같은 것이요."))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, Space.xs)
                            }
                            ForEach(backup.config.folders, id: \.self) { FolderRow(path: $0) }
                        } header: {
                            Text(tr("Folders to copy", "복사할 폴더"))
                        } footer: {
                            AdaptiveRow {
                                FooterText(tr("Always skipped: dependencies and build output (node_modules, build, .venv…), caches, .env and key files, and folders that are their own GitHub project.",
                                              "늘 빼는 것: 의존성·빌드 결과(node_modules, build, .venv…), 캐시, .env와 키 파일, 자체 GitHub 프로젝트인 폴더.")
                                           + (backup.gitleaksPath == nil ? "" : tr(" Files that look like they hold a password are skipped too.", " 비밀번호가 든 것처럼 보이는 파일도 빼요.")))
                            } trailing: {
                                Button(tr("Add Folder…", "폴더 추가…")) { backup.addFolders() }.fixedSize()
                            }
                        }
                        Section {
                            TextField(tr("Also skip", "더 뺄 것"), text: $excludes, prompt: Text(verbatim: "*.mov, Exports"))
                                .onSubmit { backup.setExcludes(excludes) }
                        } footer: {
                            FooterText(tr("Names or patterns, separated by commas. Press Return to save.", "이름이나 패턴을 쉼표로 나눠 적어요. Return을 누르면 저장돼요."))
                        }
                        if !backup.unreadable.filter(backup.exists).isEmpty {
                            Section {
                                AdaptiveRow {
                                    StatusLabel(kind: .problem, text: tr("LazyMac cannot read some folders. Allow Full Disk Access for LazyMac, then come back.",
                                                                         "LazyMac이 일부 폴더를 읽지 못해요. LazyMac에 '전체 디스크 접근'을 허용하고 돌아와 주세요."))
                                } trailing: {
                                    Button(tr("Open Privacy Settings…", "개인정보 설정 열기…")) { BackupModel.openFullDiskAccess() }.fixedSize()
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
                    BackupConsole()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            BottomBar {
                if let message = backup.message {
                    Text(message).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    RunRowCompact(run: backup.lastBackup)
                }
            } trailing: {
                Button(tr("Check", "비교")) { backup.check() }.fixedSize()
                    .disabled(!backup.ready || backup.busy)
                    .help(tr("Compares every folder with its copy, without copying", "복사하지 않고 폴더와 사본을 비교해요"))
                Button(tr("Copy Folders Now", "지금 폴더 복사")) { backup.backUpNow() }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!backup.ready || backup.busy)
            }
        }
        .onAppear {
            backup.refresh()
            excludes = backup.config.excludes.joined(separator: ", ")
        }
    }
}

struct RunRowCompact: View {
    let run: BackupRun?

    var body: some View {
        if let run {
            StatusLabel(kind: run.ok ? .ok : .problem,
                        text: (run.ok ? tr("Last copy: ", "마지막 복사: ") : tr("Last copy had problems: ", "마지막 복사에 문제: ")) + run.date.formatted(.relative(presentation: .named).locale(Lang.locale)))
                .lineLimit(2)
        } else {
            Text(tr("Not copied yet", "아직 복사하지 않았어요")).foregroundStyle(.secondary)
        }
    }
}

struct FolderRow: View {
    @Environment(BackupModel.self) private var backup
    let path: String

    var body: some View {
        HStack(spacing: Space.l) {
            Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(URL(fileURLWithPath: path).lastPathComponent).font(AppText.body.weight(.medium))
                Text(BackupConfig.tilde(path))
                    .font(AppText.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                if !backup.exists(path) {
                    StatusLabel(kind: .problem, text: tr("Not found on this Mac", "이 맥에 없어요")).font(AppText.callout)
                } else if backup.unreadable.contains(path) {
                    StatusLabel(kind: .problem, text: tr("Cannot read: needs Full Disk Access", "읽을 수 없어요: 전체 디스크 접근 필요")).font(AppText.callout)
                }
            }
            Spacer(minLength: Space.m)
            Button {
                backup.remove(path)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("Stop copying this folder (the copy in the backup stays)", "이 폴더 복사를 그만해요 (백업에 있는 사본은 남아요)"))
            .accessibilityLabel(tr("Remove \(URL(fileURLWithPath: path).lastPathComponent)", "\(URL(fileURLWithPath: path).lastPathComponent) 빼기"))
        }
        .padding(.vertical, Space.xxs)
    }
}

// MARK: - Google Drive connection (rclone config create)

struct ConnectSheet: View {
    @Environment(BackupModel.self) private var backup
    @Environment(\.dismiss) private var dismiss
    @State private var name = "gdrive"
    @State private var path = BackupModel.suggestedPath
    @State private var ownClient = false
    @State private var clientID = ""
    @State private var clientSecret = ""

    var nameProblem: String? {
        if name.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil { return tr("Use letters, numbers, - and _", "영문, 숫자, -, _ 만 써요") }
        if backup.remotes.contains(name) { return tr("\(name) is already set up. Pick it in the Cloud list instead.", "\(name)은(는) 이미 있어요. 클라우드 목록에서 골라 주세요.") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Connect Google Drive", "Google 드라이브 연결")).font(AppText.title2.bold())
            Text(tr("Your browser opens to sign in to Google and allow rclone. rclone can see only the files it makes, nothing else in your Drive.",
                    "브라우저가 열리면 Google에 로그인하고 rclone을 허용해요. rclone은 자기가 만든 파일만 볼 수 있고, 드라이브의 다른 것은 못 봐요."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(tr("Name", "이름"), text: $name)
                TextField(tr("Folder in Drive", "드라이브 안 폴더"), text: $path)
                Toggle(tr("Use my own Google client ID", "내 Google 클라이언트 ID 쓰기"), isOn: $ownClient)
                if ownClient {
                    TextField(tr("Client ID", "클라이언트 ID"), text: $clientID)
                    SecureField(tr("Client secret", "클라이언트 보안 비밀"), text: $clientSecret)
                }
            }
            .formStyle(.grouped)
            Text(tr("Optional. rclone's shared ID can be slow when many people use it at once; your own (from Google Cloud Console) avoids that.",
                    "선택이에요. rclone 공용 ID는 사람이 몰리면 느려질 수 있어요. Google Cloud Console에서 만든 내 ID를 쓰면 괜찮아요."))
                .font(AppText.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let nameProblem { StatusLabel(kind: .problem, text: nameProblem) }
            HStack {
                Spacer()
                Button(tr("Cancel", "취소"), role: .cancel) { dismiss() }.fixedSize()
                    .keyboardShortcut(.cancelAction)
                Button(tr("Connect", "연결")) {
                    backup.connectGoogleDrive(name: name, path: path, clientID: ownClient ? clientID : "", clientSecret: ownClient ? clientSecret : "")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(nameProblem != nil || path.isEmpty || (ownClient && (clientID.isEmpty || clientSecret.isEmpty)))
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            var n = "gdrive", i = 2
            while backup.remotes.contains(n) { n = "gdrive\(i)"; i += 1 }
            name = n
        }
    }
}

// MARK: - Back Up > Schedule (also LazyMac > Settings… > Schedule)

struct ScheduleView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    let inSettings: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if !inSettings {
                PageHeader(title: tr("Schedule", "일정"),
                           subtitle: tr("When this Mac backs up by itself. It runs in the background, even when LazyMac is closed.",
                                        "이 맥이 스스로 백업하는 때예요. LazyMac을 닫아도 뒤에서 돌아요."))
            }
            Form {
                Section {
                    Toggle(tr("Back up automatically", "자동으로 백업하기"), isOn: $model.backupOn)
                    if model.backupOn {
                        Picker(tr("How often", "얼마나 자주"), selection: $model.backupDraft.frequency) {
                            ForEach(BackupSchedule.Frequency.allCases) { Text($0.title).tag($0) }
                        }
                        switch model.backupDraft.frequency {
                        case .hourly:
                            Picker(tr("At minute", "몇 분에"), selection: $model.backupDraft.minute) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: ":%02d", $0)).tag($0) }
                            }
                        case .everyHours:
                            Picker(tr("Every", "간격"), selection: $model.backupDraft.everyHours) {
                                ForEach(BackupSchedule.hourSteps, id: \.self) { Text(tr("\($0) hours", "\($0)시간")).tag($0) }
                            }
                            TimeRow(hour: $model.backupDraft.hour, minute: $model.backupDraft.minute, title: tr("Starting at", "시작 시각"))
                        case .daily:
                            TimeRow(hour: $model.backupDraft.hour, minute: $model.backupDraft.minute, title: tr("At", "시각"))
                        case .weekly:
                            Picker(tr("On", "요일"), selection: $model.backupDraft.weekday) {
                                ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { Text(BackupSchedule.weekdayName($0)).tag($0) }
                            }
                            TimeRow(hour: $model.backupDraft.hour, minute: $model.backupDraft.minute, title: tr("At", "시각"))
                        }
                        LabeledContent(tr("Runs", "도는 때"), value: model.backupDraft.summary)
                    }
                } header: {
                    Text(tr("Automatic backup", "자동 백업"))
                } footer: {
                    FooterText(whatRuns)
                }

                Section(tr("Now", "지금")) {
                    LabeledContent(tr("Schedule", "일정"), value: model.backupInstalled?.summary ?? tr("Off", "꺼짐"))
                    if let missing = AutoBackup.missingProgram {
                        StatusLabel(kind: .problem, text: tr("The scheduled job points to \(missing), which is gone. Press Apply to point it at this app.",
                                                             "예약 작업이 가리키는 \(missing)이(가) 없어요. '적용'을 누르면 이 앱으로 다시 맞춰요."))
                    }
                    if model.repo == nil {
                        Text(tr("Automatic backups need Full Disk Access for LazyMac, so it can read your folders while you are away.",
                                "자동 백업이 폴더를 읽으려면 LazyMac에 '전체 디스크 접근'이 필요해요."))
                            .foregroundStyle(.secondary)
                        Button(tr("Open Privacy Settings…", "개인정보 설정 열기…")) { BackupModel.openFullDiskAccess() }.fixedSize()
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: inSettings ? nil : Metrics.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            BottomBar {
                if let status = model.backupStatus {
                    Text(status).font(AppText.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            } trailing: {
                Button(tr("Revert", "되돌리기")) { model.reloadBackup() }.fixedSize()
                    .disabled(!model.backupDirty || model.backupBusy)
                Button(tr("Apply", "적용")) { model.applyBackup() }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(model.backupDirty || AutoBackup.missingProgram != nil) || model.backupBusy)
            }
        }
        .onAppear { model.reloadBackup() }
    }

    var whatRuns: String {
        storage.config.files
            ? tr("Each automatic backup lists this Mac's apps, saves your settings, copies your folders and copies everything to your backup place.",
                 "자동 백업은 이 맥의 앱 목록을 만들고, 설정을 저장하고, 폴더를 복사한 뒤 모두 백업 장소로 복사해요.")
            : tr("Each automatic backup lists this Mac's apps, saves your settings and copies them to your backup place. Folders are copied only when you turn them on.",
                 "자동 백업은 이 맥의 앱 목록을 만들고, 설정을 저장한 뒤 백업 장소로 복사해요. 폴더는 켰을 때만 복사해요.")
    }
}

struct TimeRow: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let title: String

    var body: some View {
        let date = Binding<Date>(
            get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                hour = c.hour ?? 0
                minute = c.minute ?? 0
            })
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
    }
}

// MARK: - Restore > Folders

struct RestoreFoldersView: View {
    @Environment(BackupModel.self) private var backup

    var body: some View {
        @Bindable var backup = backup
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: tr("Restore Folders", "폴더 복원"),
                               subtitle: tr("Bring backed-up folders back. Files already on this Mac are kept as they are.",
                                            "백업한 폴더를 되살려요. 이 맥에 이미 있는 파일은 그대로 둬요."))
                    Form {
                        Section { PlaceLine() }
                        Section {
                            if !backup.cloudListed {
                                AdaptiveRow {
                                    Text(tr("See which folders the backup holds.", "백업에 어떤 폴더가 있는지 봐요.")).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                } trailing: {
                                    Button(tr("Find Backed-Up Folders", "백업된 폴더 찾기")) { backup.listCloud() }.fixedSize()
                                        .disabled(!backup.hasRemote || (StorageConfig.load().backend == .gdrive && backup.rclonePath == nil) || backup.busy)
                                }
                            } else if backup.cloudFolders.isEmpty {
                                AdaptiveRow {
                                    StatusLabel(kind: .info, text: tr("This backup has no folders.", "이 백업에는 폴더가 없어요."))
                                } trailing: {
                                    Button(tr("Look Again", "다시 찾기")) { backup.listCloud() }.disabled(backup.busy).fixedSize()
                                }
                            } else {
                                ForEach(backup.cloudFolders, id: \.self) { rel in
                                    let on = Binding(get: { backup.restoreSelection.contains(rel) },
                                                     set: { if $0 { backup.restoreSelection.insert(rel) } else { backup.restoreSelection.remove(rel) } })
                                    Toggle(isOn: on) {
                                        VStack(alignment: .leading, spacing: Space.xxs) {
                                            Text(URL(fileURLWithPath: rel).lastPathComponent).font(AppText.body.weight(.medium))
                                            Text(tr("To ", "→ ") + BackupConfig.tilde(BackupConfig.localPath(rel, under: backup.restoreTo?.path)))
                                                .font(AppText.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        } header: {
                            HStack {
                                Text(tr("Folders in the backup", "백업에 있는 폴더"))
                                Spacer()
                                if !backup.cloudFolders.isEmpty {
                                    let all = backup.restoreSelection.count == backup.cloudFolders.count
                                    Button(all ? tr("Select None", "모두 해제") : tr("Select All", "모두 선택")) {
                                        backup.restoreSelection = all ? [] : Set(backup.cloudFolders)
                                    }
                                    .buttonStyle(.link)
                                    .font(AppText.caption)
                                }
                            }
                        }
                        Section(tr("How", "방법")) {
                            Picker(tr("Put them", "둘 곳"), selection: Binding(get: { backup.restoreTo == nil ? 0 : 1 },
                                                                              set: { if $0 == 0 { backup.restoreTo = nil } else { backup.chooseRestoreFolder() } })) {
                                Text(tr("Where they were", "원래 있던 곳")).tag(0)
                                Text(backup.restoreTo.map { tr("In \(BackupConfig.tilde($0.path))", "\(BackupConfig.tilde($0.path)) 안에") } ?? tr("In another folder…", "다른 폴더에…")).tag(1)
                            }
                            .pickerStyle(.radioGroup)
                            Toggle(tr("Replace files here that are older than the backup", "백업보다 오래된 파일은 바꾸기"), isOn: $backup.restoreReplace)
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
                    BackupConsole()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            BottomBar {
                Text(backup.message ?? (backup.restoreReplace
                     ? tr("A file here is replaced only when the backup has a newer one.", "백업에 더 새 파일이 있을 때만 바꿔요.")
                     : tr("Files already here are never touched.", "이미 있는 파일은 건드리지 않아요.")))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } trailing: {
                let n = backup.cloudFolders.filter { backup.restoreSelection.contains($0) }.count
                Button(n == 0 ? tr("Restore", "복원") : tr(n == 1 ? "Restore 1 Folder" : "Restore \(n) Folders", "폴더 \(n)개 복원")) { backup.restore() }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(n == 0 || backup.busy)
            }
        }
        .onAppear { backup.refresh() }
    }
}
