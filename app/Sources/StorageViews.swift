import SwiftUI

struct StorageSettingsSection: View {
    @Environment(StorageModel.self) private var storage
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup

    var body: some View {
        @Bindable var storage = storage
        Section(tr("Storage", "저장소")) {
            Picker(tr("Backend", "저장 방식"), selection: $storage.config.backend) {
                Text(tr("Google Drive", "Google 드라이브")).tag(StorageConfig.Backend.gdrive)
                Text(tr("Local folder", "로컬 폴더")).tag(StorageConfig.Backend.local)
            }
            .onChange(of: storage.config.backend) { save() }
            if storage.config.backend == .gdrive {
                TextField(tr("Remote name and folder", "원격 이름과 폴더"), text: $storage.config.remote)
                    .onSubmit { save() }
            } else {
                LabeledContent(tr("Local folder", "로컬 폴더")) {
                    Text(storage.config.local.isEmpty ? tr("Not set", "정하지 않음") : BackupConfig.tilde(storage.config.local))
                        .lineLimit(1).truncationMode(.middle).help(storage.config.local)
                    Button(tr("Choose…", "고르기…")) { storage.chooseFolder(); reload() }
                }
            }
            Toggle(tr("Back up files and folders automatically", "파일과 폴더 자동 백업"), isOn: $storage.config.files)
                .onChange(of: storage.config.files) { save() }
            TextField(tr("Data folder", "데이터 폴더"), text: $storage.config.data)
                .onSubmit { save() }
            Button(tr("Choose Data Folder…", "데이터 폴더 고르기…")) { storage.chooseFolder(data: true); reload() }
            Text(tr("Data and folder copies never delete destination files. Press Return to save text fields.",
                    "데이터와 폴더를 복사해도 저장소의 파일은 지우지 않아요. 입력 칸은 Return을 누르면 저장돼요."))
                .font(AppText.callout).foregroundStyle(.secondary)
            if let message = storage.message {
                Text(message).font(AppText.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        Section(tr("Data folder", "데이터 폴더")) {
            if !storage.config.isInitialized {
                Text(tr("Restore your data from storage, or start with a small fictional example. Starting here makes this Mac the main Mac.",
                        "저장소에서 데이터를 복원하거나 작은 가상 예제로 시작해요. 예제로 시작하면 이 맥이 주 맥이 돼요."))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(tr("Restore from Storage", "저장소에서 복원")) {
                        Task { await storage.initialize(restore: true); reload() }
                    }
                    Button(tr("Start from Example", "예제로 시작")) {
                        Task { await storage.initialize(restore: false); reload() }
                    }
                    if storage.busy { ProgressView().controlSize(.small) }
                }
            } else {
                LabeledContent(tr("Data is in", "데이터 위치"), value: BackupConfig.tilde(storage.config.dataURL.path))
                Text(tr("Only the main Mac can change the shared catalog and profiles. Each Mac writes its own inventory.",
                        "공유 목록과 프로필은 주 맥에서만 바꿔요. 각 맥은 자기 맥의 훑은 기록만 써요."))
                    .font(AppText.callout).foregroundStyle(.secondary)
            }
        }
        .disabled(storage.busy || backup.busy)
    }

    private func save() { storage.save(); reload() }
    private func reload() {
        backup.refresh()
        if storage.config.isInitialized { model.use(repo: storage.config.dataURL) }
    }
}

struct StorageStatusSection: View {
    @Environment(StorageModel.self) private var storage
    @Environment(BackupModel.self) private var backup

    var body: some View {
        Section(tr("Storage status", "저장소 상태")) {
            LabeledContent(tr("Destination", "저장 위치"), value: StorageConfig.load().target)
            RunRow(title: tr("Last backup", "마지막 백업"), run: backup.lastBackup)
            LabeledContent(tr("Available capacity", "남은 용량")) {
                VStack(alignment: .trailing, spacing: 2) {
                    if let c = storage.capacity, let bytes = c.available {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                             + (c.total.map { tr(" of ", " / ") + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""))
                            .foregroundStyle(c.stale ? Color.secondary : Color.primary)
                    } else {
                        Text(tr("Unavailable", "확인할 수 없음")).foregroundStyle(.secondary)
                    }
                    if storage.capacity?.stale == true {
                        Text(tr("Could not refresh. Showing the last known value.", "새로 확인하지 못했어요. 마지막 값을 표시해요."))
                            .font(AppText.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await storage.refreshCapacity() }
        .onChange(of: backup.lastBackup?.id) { Task { await storage.refreshCapacity() } }
    }
}
