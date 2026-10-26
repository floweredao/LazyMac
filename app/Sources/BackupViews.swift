import AppKit
import SwiftUI

// MARK: - Back Up > Overview

struct OverviewView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: tr("Back Up", "백업"),
                               subtitle: tr("Your apps and settings list lives in your data folder and is copied to the selected storage. Folder backup is optional.",
                                            "앱과 설정 목록은 데이터 폴더에 두고 선택한 저장소로 복사해요. 폴더 백업은 원할 때 켤 수 있어요."))
                    Form {
                        StorageStatusSection()
                        if !backup.configured && model.repo == nil {
                            Section(tr("Get started", "시작하기")) {
                                StartRow(symbol: "folder", title: tr("Back up this Mac", "이 맥 백업하기"),
                                         detail: tr("Choose storage in Settings, then pick the folders to copy.", "설정에서 저장소를 고른 뒤 복사할 폴더를 골라요."),
                                         button: tr("Set Up…", "설정…")) { model.page = .folders }
                                StartRow(symbol: "arrow.down.doc", title: tr("Restore to this Mac", "이 맥으로 복원하기"),
                                         detail: tr("Bring folders back from a backup made on another Mac.", "다른 맥에서 만든 백업에서 폴더를 되살려요."),
                                         button: tr("Restore…", "복원…")) { model.page = .restoreFolders }
                            }
                        }
                        Section {
                            LabeledContent(tr("Copies go to", "복사하는 곳")) {
                                Text(backup.hasRemote ? backup.config.remote : tr("Not set", "정하지 않음"))
                                    .textSelection(.enabled)
                            }
                            LabeledContent(tr("Folders", "폴더")) {
                                Text(backup.config.folders.isEmpty ? tr("None yet", "아직 없음") : folderCount(backup.config.folders.count))
                            }
                            RunRow(title: tr("Last check", "마지막 비교"), run: backup.lastCheck)
                        } header: {
                            Text(tr("Folders", "폴더"))
                        } footer: {
                            AdaptiveRow {
                                Button(tr("Edit Folders…", "폴더 편집…")) { model.page = .folders }.fixedSize()
                            } trailing: {
                                Button(tr("Check", "비교")) { backup.check() }.fixedSize()
                                    .disabled(!backup.ready || backup.busy)
                                    .help(tr("Compares every folder with its backup, without copying", "복사하지 않고 폴더와 백업 사본을 비교해요"))
                                Button(tr("Back Up Now", "지금 백업")) { backup.backUpNow() }.fixedSize()
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!backup.ready || backup.busy)
                            }
                        }

                        Section(tr("Schedule", "일정")) {
                            LabeledContent(tr("Runs", "도는 때"), value: model.backupInstalled?.summary ?? tr("Off", "꺼짐"))
                            if let last = DailyLog.latest() {
                                LabeledContent(tr("Last scheduled run", "마지막 예약 실행")) {
                                    HStack(spacing: 8) {
                                        StatusLabel(kind: last.ok ? .ok : .problem,
                                                    text: (last.ok ? tr("Done", "끝남") : tr("Failed", "실패")) + (last.date.map { " · " + $0.formatted(.relative(presentation: .named).locale(Lang.locale)) } ?? ""))
                                        Button(tr("Show Log", "로그 보기")) { NSWorkspace.shared.open(last.url) }.fixedSize()
                                            .buttonStyle(.link)
                                    }
                                }
                                if !last.ok, !last.detail.isEmpty {
                                    Text(last.detail).font(AppText.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }

                        if model.repo != nil {
                            Section {
                                LabeledContent(tr("This Mac", "이 맥"), value: Profiles.host)
                                LabeledContent(tr("Role", "역할"), value: model.role == .main ? tr("Main Mac", "주 맥") : tr("Other Mac", "보조 맥"))
                                if let status = model.scanStatus {
                                    Text(status).font(AppText.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            } header: {
                                Text(tr("Apps and settings list", "앱과 설정 목록"))
                            } footer: {
                                AdaptiveRow {
                                    FooterText(tr("Scanning reads this Mac (about a minute) and saves its inventory to your data folder and storage.",
                                                  "훑기는 이 맥을 읽고(1분쯤) 기록을 데이터 폴더와 저장소에 저장해요."))
                                } trailing: {
                                    if model.scanning { ProgressView().controlSize(.small) }
                                    Button(tr("Scan This Mac", "이 맥 훑기")) { Task { await model.scanThisMac() } }.fixedSize()
                                        .disabled(model.scanning)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(maxWidth: 760, alignment: .leading)
                    BackupConsole()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            backup.refresh()
            model.reloadBackup()
        }
    }
}

func folderCount(_ n: Int) -> String { tr(n == 1 ? "1 folder" : "\(n) folders", "\(n)개") }

struct StartRow: View {
    let symbol: String
    let title: String
    let detail: String
    let button: String
    let action: () -> Void

    var body: some View {
        AdaptiveRow {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol).font(AppText.title3).foregroundStyle(.secondary).frame(width: 28 * TextScale.current).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppText.headline)
                    Text(detail).font(AppText.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } trailing: {
            Button(button, action: action).fixedSize()
        }
        .padding(.vertical, 4)
    }
}

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
        if backup.lastJob != nil && (backup.console.running || !backup.console.lines.isEmpty) {
            ConsolePanel(console: backup.console)
                .frame(height: 240)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: 760)
        }
    }
}

/// The newest ~/Library/Logs/lazymac-daily/<date>.log: when the last scheduled run ended and how.
struct DailyLog {
    let url: URL
    let date: Date?
    let ok: Bool
    let detail: String

    static func latest() -> DailyLog? {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAZYMAC_DAILY_LOGDIR"] ?? NSHomeDirectory() + "/Library/Logs/lazymac-daily")
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
    @Environment(BackupModel.self) private var backup
    @State private var excludes = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: tr("Folders", "폴더"),
                               subtitle: tr("These folders are copied to the selected storage. Nothing is ever deleted, here or at the destination.",
                                            "이 폴더들을 선택한 저장소에 복사해요. 여기서도 저장소에서도 아무것도 지우지 않아요."))
                    Form {
                        if StorageConfig.load().backend == .gdrive { DestinationSection(restoring: false) }
                        Section {
                            if backup.config.folders.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tr("No folders yet", "아직 폴더가 없어요")).font(AppText.headline)
                                    Text(tr("Add folders that are not on GitHub or iCloud, like project files, photos or notes.",
                                            "GitHub나 iCloud에 없는 폴더를 넣어요. 프로젝트 파일, 사진, 메모 같은 것이요."))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            ForEach(backup.config.folders, id: \.self) { FolderRow(path: $0) }
                        } header: {
                            Text(tr("Folders to back up", "백업할 폴더"))
                        } footer: {
                            AdaptiveRow {
                                FooterText(tr("Always skipped: dependencies and build output (node_modules, build, .venv…), caches, .env and key files, and folders that are their own GitHub repo.",
                                              "늘 빼는 것: 의존성·빌드 결과(node_modules, build, .venv…), 캐시, .env와 키 파일, 자체 GitHub 저장소인 폴더.")
                                           + (backup.gitleaksPath == nil ? "" : tr(" Files gitleaks flags as secrets are skipped too.", " gitleaks가 비밀값으로 찾은 파일도 빼요.")))
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
                    .frame(maxWidth: 760, alignment: .leading)
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
                Button(tr("Back Up Now", "지금 백업")) { backup.backUpNow() }.fixedSize()
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
                        text: (run.ok ? tr("Last backup: ", "마지막 백업: ") : tr("Last backup had problems: ", "마지막 백업에 문제: ")) + run.date.formatted(.relative(presentation: .named).locale(Lang.locale)))
                .lineLimit(2)
        } else {
            Text(tr("Not backed up yet", "아직 백업하지 않았어요")).foregroundStyle(.secondary)
        }
    }
}

struct FolderRow: View {
    @Environment(BackupModel.self) private var backup
    let path: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
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
            Spacer(minLength: 8)
            Button {
                backup.remove(path)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("Stop backing up this folder (the stored copy stays)", "이 폴더 백업을 그만해요 (저장소의 사본은 남아요)"))
            .accessibilityLabel(tr("Remove \(URL(fileURLWithPath: path).lastPathComponent)", "\(URL(fileURLWithPath: path).lastPathComponent) 빼기"))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Where the copies go

struct DestinationSection: View {
    @Environment(BackupModel.self) private var backup
    let restoring: Bool
    @State private var editing = false
    @State private var picked = ""
    @State private var path = ""
    @State private var connecting = false

    var body: some View {
        Section {
            if backup.rclonePath == nil {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("rclone is needed", "rclone이 필요해요")).font(AppText.headline)
                        Text(tr("A free, open-source tool that copies files to Google Drive, Dropbox, OneDrive and 70 other clouds.",
                                "Google 드라이브, Dropbox, OneDrive 등 70여 클라우드에 파일을 복사하는 무료 오픈 소스 도구예요."))
                            .font(AppText.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } trailing: {
                    Button(tr("Install rclone", "rclone 설치")) { backup.installRclone() }.fixedSize()
                        .buttonStyle(.borderedProminent)
                        .disabled(backup.busy)
                }
            } else if backup.hasRemote && !editing {
                LabeledContent(restoring ? tr("Backup is in", "백업이 있는 곳") : tr("Copies go to", "복사하는 곳")) {
                    HStack(spacing: 8) {
                        Text(backup.config.remote).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Button(tr("Change…", "바꾸기…")) { start() }.disabled(backup.busy).fixedSize()
                    }
                }
            } else {
                if !backup.remotes.isEmpty {
                    Picker(tr("Cloud", "클라우드"), selection: $picked) {
                        ForEach(backup.remotes, id: \.self) { Text($0).tag($0) }
                    }
                    TextField(tr("Folder in the cloud", "클라우드 안 폴더"), text: $path, prompt: Text(BackupModel.suggestedPath))
                    HStack {
                        if editing { Button(tr("Cancel", "취소")) { editing = false } }
                        Spacer()
                        Button(tr("Use This Cloud", "이 클라우드 쓰기")) {
                            backup.setRemote(name: picked, path: path.isEmpty ? BackupModel.suggestedPath : path)
                            editing = false
                        }
                        .disabled(picked.isEmpty)
                    }
                }
                AdaptiveRow {
                    Text(backup.remotes.isEmpty ? tr("Connect a cloud drive to copy to.", "복사할 클라우드 드라이브를 연결해요.")
                                                : tr("Or connect another one.", "또는 다른 클라우드를 연결해요."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } trailing: {
                    Button(tr("Other Cloud…", "다른 클라우드…")) { backup.openRcloneConfig() }.fixedSize()
                        .help(tr("Opens Terminal with rclone config, for Dropbox, OneDrive, S3 and others. Come back when it is done.",
                                 "Dropbox, OneDrive, S3 등은 터미널의 rclone config로 설정해요. 끝나면 돌아와 주세요."))
                    Button(tr("Connect Google Drive…", "Google 드라이브 연결…")) { connecting = true }.fixedSize()
                        .buttonStyle(.borderedProminent)
                }
                .disabled(backup.busy)
            }
        } header: {
            Text(restoring ? tr("Cloud", "클라우드") : tr("Cloud", "클라우드"))
        }
        .sheet(isPresented: $connecting) { ConnectSheet().environment(backup) }
        .onAppear { if picked.isEmpty { picked = backup.config.remoteName.isEmpty ? (backup.remotes.first ?? "") : backup.config.remoteName } }
        .onChange(of: backup.remotes) { if picked.isEmpty || !backup.remotes.contains(picked) { picked = backup.remotes.first ?? "" } }
    }

    private func start() {
        picked = backup.config.remoteName
        path = backup.config.remotePath
        editing = true
    }
}

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

// MARK: - Back Up > Schedule (also LazyMac > Settings…)

struct ScheduleView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
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
                if inSettings {
                    StorageSettingsSection()
                    StorageStatusSection()
                }
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
                    Text(tr("Auto backup", "자동 백업"))
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
                        Text(tr("Scheduled runs need Full Disk Access for LazyMac, so it can read your folders while you are away.",
                                "예약 실행이 폴더를 읽으려면 LazyMac에 '전체 디스크 접근'이 필요해요."))
                            .foregroundStyle(.secondary)
                        Button(tr("Open Privacy Settings…", "개인정보 설정 열기…")) { BackupModel.openFullDiskAccess() }.fixedSize()
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: inSettings ? nil : 760, alignment: .leading)
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
        tr("Each run saves this Mac's inventory to storage. Only the main Mac updates the shared catalog and snapshots. Folder copying and comparison run only when file backup is on.",
           "돌 때마다 이 맥의 훑은 기록을 저장소에 복사해요. 공유 목록과 스냅샷은 주 맥에서만 바꿔요. 폴더 복사와 비교는 파일 백업을 켰을 때만 돌아요.")
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
                               subtitle: tr("Bring backed-up folders back from storage. Files already on this Mac are kept as they are.",
                                            "백업한 폴더를 저장소에서 되살려요. 이 맥에 이미 있는 파일은 그대로 둬요."))
                    Form {
                        if StorageConfig.load().backend == .gdrive { DestinationSection(restoring: true) }
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
                                    StatusLabel(kind: .info, text: tr("No LazyMac backup in \(backup.config.remote).", "\(backup.config.remote)에 LazyMac 백업이 없어요."))
                                } trailing: {
                                    Button(tr("Look Again", "다시 찾기")) { backup.listCloud() }.disabled(backup.busy).fixedSize()
                                }
                            } else {
                                ForEach(backup.cloudFolders, id: \.self) { rel in
                                    let on = Binding(get: { backup.restoreSelection.contains(rel) },
                                                     set: { if $0 { backup.restoreSelection.insert(rel) } else { backup.restoreSelection.remove(rel) } })
                                    Toggle(isOn: on) {
                                        VStack(alignment: .leading, spacing: 2) {
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
                    .frame(maxWidth: 760, alignment: .leading)
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
