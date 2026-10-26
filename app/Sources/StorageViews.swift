import AppKit
import SwiftUI

enum SettingsTab: String {
    case place, schedule, advanced
    static let key = "settingsTab"

    static func open(_ tab: Self, _ action: OpenSettingsAction) {
        UserDefaults.standard.set(tab.rawValue, forKey: key)
        action()
    }
}

struct SettingsView: View {
    @AppStorage(SettingsTab.key) private var tab = SettingsTab.place

    var body: some View {
        TabView(selection: $tab) {
            BackupPlaceView()
                .tabItem { Label(tr("Backup Place", "백업 장소"), systemImage: "externaldrive") }
                .tag(SettingsTab.place)
            ScheduleView(inSettings: true)
                .tabItem { Label(tr("Schedule", "일정"), systemImage: "calendar.badge.clock") }
                .tag(SettingsTab.schedule)
            AdvancedView()
                .tabItem { Label(tr("Advanced", "고급"), systemImage: "gearshape.2") }
                .tag(SettingsTab.advanced)
        }
        .consoleSheet()
        .frame(width: 640, height: 640)
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["LAZYMAC_SETTINGS_TAB"],
               let envTab = SettingsTab(rawValue: raw) {
                tab = envTab
            }
        }
    }
}

struct BackupPlaceView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @State private var connecting = false

    private var backend: Binding<StorageConfig.Backend> {
        Binding(
            get: { storage.config.backend },
            set: { storage.setBackend($0); backup.refresh() }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(tr("Keep backups in", "백업을 둘 곳"), selection: backend) {
                    Text(tr("A folder on this Mac or an external disk (recommended)", "이 맥이나 외장 디스크의 폴더 (권장)"))
                        .tag(StorageConfig.Backend.local)
                    Text(tr("Google Drive", "Google 드라이브"))
                        .tag(StorageConfig.Backend.gdrive)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                FooterText(tr("A folder on an external disk works right away with no extra tools or sign-in. Google Drive keeps an off-site copy in the cloud.",
                              "외장 디스크 폴더는 추가 도구나 로그인 없이 바로 쓸 수 있어요. Google 드라이브는 클라우드에 따로 보관해요."))
            }

            if storage.config.backend == .local {
                LocalPlaceSection()
            } else {
                GoogleDriveSection(connecting: $connecting)
            }

            CapacitySection()
        }
        .formStyle(.grouped)
        .sheet(isPresented: $connecting) { ConnectSheet().environment(backup) }
        .onAppear {
            storage.reload()
            backup.refresh()
        }
        .onChange(of: backup.job) {
            if backup.job == nil {
                storage.reload()
                if storage.config.isInitialized { model.use(repo: storage.config.dataURL) }
            }
        }
    }
}

struct LocalPlaceSection: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage

    var body: some View {
        Section(tr("Backup folder", "백업 폴더")) {
            if let place = storage.config.place, !place.drive {
                StatusLabel(
                    kind: place.connected ? .ok : .problem,
                    text: place.connected
                        ? place.sentence
                        : tr("The disk “\(place.disk ?? "")” is not connected. Connect it, or choose another folder.",
                             "“\(place.disk ?? "")” 디스크가 연결되어 있지 않아요. 디스크를 연결하거나 다른 폴더를 골라 주세요.")
                )
                LabeledContent(tr("Path", "경로")) {
                    Text(BackupConfig.tilde(storage.config.local))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(storage.config.local)
                }
            } else {
                Text(tr("No folder chosen yet. Choose a folder on an external disk or on this Mac.",
                        "아직 고른 폴더가 없어요. 외장 디스크나 이 맥의 폴더를 골라 주세요."))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(storage.config.local.isEmpty ? tr("Choose Folder…", "폴더 고르기…") : tr("Choose Another Folder…", "다른 폴더 고르기…")) {
                    if storage.chooseFolder() {
                        backup.refresh()
                        if storage.config.isInitialized { model.use(repo: storage.config.dataURL) }
                    }
                }
                .fixedSize()
                if !storage.config.local.isEmpty, storage.config.place?.connected != false {
                    Button(tr("Show in Finder", "Finder에서 보기")) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storage.config.local)
                    }
                    .fixedSize()
                }
            }
        }
    }
}

struct GoogleDriveSection: View {
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(\.consoleSheet) private var consoleSheet
    @Binding var connecting: Bool
    @State private var folderPath = ""

    private var remoteName: String {
        let name = storage.config.remote.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return name.isEmpty ? "gdrive" : name
    }

    private var hasRclone: Bool { backup.rclonePath != nil }
    private var hasRemote: Bool { hasRclone && backup.remotes.contains(remoteName) }

    var body: some View {
        Section {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    StatusLabel(
                        kind: hasRclone ? .ok : .info,
                        text: hasRclone
                            ? tr("Step 1: rclone is installed.", "1단계: rclone이 설치되어 있어요.")
                            : tr("Step 1: Install rclone, a free tool that copies files to Google Drive.",
                                 "1단계: Google 드라이브로 파일을 복사하는 무료 도구 rclone을 설치해요.")
                    )
                    if !hasRclone {
                        Text(verbatim: "brew install rclone")
                            .font(AppText.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } trailing: {
                if !hasRclone {
                    Button(tr("Install rclone", "rclone 설치")) {
                        backup.installRclone()
                        consoleSheet.wrappedValue = true
                    }
                    .disabled(backup.busy)
                    .fixedSize()
                }
            }

            AdaptiveRow {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    StatusLabel(
                        kind: hasRemote ? .ok : .info,
                        text: hasRemote
                            ? tr("Step 2: Google Drive (\(remoteName)) is connected.", "2단계: Google 드라이브(\(remoteName))가 연결되어 있어요.")
                            : tr("Step 2: Connect your Google Drive account.", "2단계: Google 드라이브 계정을 연결해요.")
                    )
                    Text(tr("Clicking Connect runs “rclone config” to create a connection named “gdrive”. Your browser opens so you can sign in to Google and allow access. rclone can see only the files LazyMac creates, nothing else in your Drive.",
                            "‘연결’을 누르면 “rclone config”를 실행해 “gdrive” 연결을 만들어요. 브라우저가 열리면 Google에 로그인해 권한을 허용하면 돼요. rclone은 LazyMac이 만든 파일만 볼 수 있고 드라이브의 다른 파일은 보지 못해요."))
                        .font(AppText.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } trailing: {
                Button(hasRemote ? tr("Connect Another…", "다른 계정 연결…") : tr("Connect Google Drive…", "Google 드라이브 연결…")) {
                    connecting = true
                }
                .disabled(!hasRclone || backup.busy)
                .fixedSize()
            }

            if hasRemote {
                if backup.remotes.count > 1 {
                    Picker(tr("Connection", "연결"), selection: Binding(
                        get: { remoteName },
                        set: { saveRemote(name: $0, path: folderPath) }
                    )) {
                        ForEach(backup.remotes, id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField(tr("Folder in Drive", "드라이브 안 폴더"), text: $folderPath, prompt: Text(verbatim: "LazyMac"))
                    .onSubmit { saveRemote(name: remoteName, path: folderPath) }
            }
        } header: {
            Text(tr("Google Drive setup", "Google 드라이브 준비"))
        } footer: {
            FooterText(tr("If you prefer Terminal: run “brew install rclone”, then “rclone config” to create a Google Drive remote.",
                          "터미널에서 직접 하려면 “brew install rclone”을 실행한 뒤 “rclone config”로 Google 드라이브 연결을 만들면 돼요."))
        }
        .onAppear(perform: syncFields)
        .onChange(of: storage.config.remote) { syncFields() }
    }

    private func syncFields() {
        let parts = storage.config.remote.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        folderPath = parts.count > 1 ? parts[1] : "LazyMac"
    }

    private func saveRemote(name: String, path: String) {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let remote = "\(name):\(clean.isEmpty ? "LazyMac" : clean)"
        storage.setRemote(remote)
        backup.setRemote(name: name, path: clean.isEmpty ? "LazyMac" : clean)
    }
}

struct CapacitySection: View {
    @Environment(StorageModel.self) private var storage
    @Environment(BackupModel.self) private var backup

    var body: some View {
        Section(tr("Status", "상태")) {
            if let place = storage.config.place {
                LabeledContent(tr("Where backups go", "저장 위치"), value: place.sentence)
            } else {
                LabeledContent(tr("Where backups go", "저장 위치"), value: tr("Not chosen yet", "아직 고르지 않음"))
            }
            LabeledContent(tr("Free space", "남은 공간")) {
                VStack(alignment: .trailing, spacing: 2) {
                    if let c = storage.capacity, let bytes = c.available {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                             + (c.total.map { tr(" of ", " / ") + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""))
                            .foregroundStyle(c.stale ? Color.secondary : Color.primary)
                    } else {
                        Text(tr("Not checked yet", "아직 확인 전")).foregroundStyle(.secondary)
                    }
                    if storage.capacity?.stale == true {
                        Text(tr("Showing the last known space.", "마지막으로 확인한 용량이에요."))
                            .font(AppText.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text(tr("Backups never delete files from your backup place.", "백업은 백업 장소에 있는 파일을 절대 지우지 않아요."))
                .font(AppText.callout)
                .foregroundStyle(.secondary)
        }
        .task(id: storage.config.target) { await storage.refreshCapacity() }
        .onChange(of: backup.lastBackup?.id) { Task { await storage.refreshCapacity() } }
    }
}

struct AdvancedView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Folder", "폴더")) {
                    Text(BackupConfig.tilde(storage.config.dataURL.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(storage.config.dataURL.path)
                    Button(tr("Change…", "바꾸기…")) {
                        if storage.chooseFolder(data: true) {
                            backup.refresh()
                            if storage.config.isInitialized { model.use(repo: storage.config.dataURL) }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text(tr("Working copy on this Mac", "이 맥의 작업 폴더"))
            } footer: {
                FooterText(tr("LazyMac keeps a copy of your app list and settings here before copying it to your backup place.",
                              "LazyMac이 백업 장소로 복사하기 전에 앱 목록과 설정 사본을 이 폴더에 두어요."))
            }

            Section {
                LabeledContent(tr("Mac name", "맥 이름"), value: Profiles.host)
                LabeledContent(
                    tr("Role", "역할"),
                    value: model.role == .main
                        ? tr("Main Mac (updates the shared list and settings)", "주 맥 (공유 목록과 설정을 업데이트함)")
                        : tr("Extra Mac (saves its own scan only)", "보조 맥 (이 맥의 검색 결과만 저장함)")
                )
            } header: {
                Text(tr("This Mac", "이 맥"))
            }

            if !storage.config.isInitialized {
                Section {
                    Text(tr("Get the existing list from your backup place, or start with a small fictional example list to explore the app.",
                            "백업 장소에서 기존 목록을 가져오거나, 앱을 둘러볼 수 있게 작은 가상 예제 목록으로 시작해요."))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(tr("Get List from Backup Place", "백업 장소에서 목록 가져오기")) {
                            Task { await initData(.restore) }
                        }
                        .disabled(!storage.config.hasPlace)
                        Button(tr("Try with Example Data", "예제 데이터로 체험하기")) {
                            Task { await initData(.example) }
                        }
                        if storage.busy { ProgressView().controlSize(.small) }
                    }
                    if let message = storage.message {
                        Text(message).font(AppText.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(tr("Start or restore list", "목록 시작 또는 가져오기"))
                }
                .disabled(storage.busy || backup.busy)
            }
        }
        .formStyle(.grouped)
    }

    private func initData(_ start: StorageModel.Start) async {
        await storage.initialize(start)
        backup.refresh()
        if storage.config.isInitialized { model.use(repo: storage.config.dataURL) }
    }
}
