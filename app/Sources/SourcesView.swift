import AppKit
import SwiftUI

struct SourcesView: View {
    @Environment(SetupModel.self) private var model
    @Environment(SourcesModel.self) private var sources

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("App Sources", "앱 출처")).font(AppText.title.weight(.bold))
                    Text(tr("Where each app that Homebrew and the App Store do not cover comes from. Check, fix and save it here.",
                            "Homebrew와 App Store에 없는 앱을 어디서 받는지 여기서 확인하고 고쳐요."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await sources.checkAll() } } label: { Label(tr("Check All", "모두 확인"), systemImage: "arrow.clockwise") }
                    .disabled(sources.busy)
            }
            .padding(20)
            Divider()

            if !model.ready {
                ContentUnavailableView(tr("No data folder yet", "데이터 폴더가 아직 없어요"), systemImage: "folder.badge.questionmark",
                                       description: Text(tr("Restore or start with example data in Settings first.", "먼저 설정에서 데이터를 복원하거나 예제로 시작해 주세요.")))
            } else {
                List {
                    ForEach(sources.entries) { SourceRow(id: $0.id) }
                }
                .listStyle(.inset)
            }

            BottomBar {
                if let status = sources.status {
                    Text(status).foregroundStyle(.secondary).lineLimit(2)
                } else if sources.dirty {
                    Text(tr("\(sources.entries.filter(\.dirty).count) edited, not synced yet", "\(sources.entries.filter(\.dirty).count)개 수정함, 아직 동기화 안 됨"))
                        .foregroundStyle(.secondary)
                } else if !sources.uncommitted.isEmpty {
                    Text(tr("Saved changes are not in storage yet", "저장한 변경이 아직 저장소에 없어요")).foregroundStyle(.secondary)
                } else {
                    Text(tr("In sync with storage", "저장소와 같아요")).foregroundStyle(.secondary)
                }
            } trailing: {
                if sources.busy { ProgressView().controlSize(.small) }
                if sources.unpushed && !sources.canSync {
                    Button { Task { await sources.retryPush() } } label: { Label(tr("Retry Sync", "동기화 다시"), systemImage: "arrow.up.circle") }
                        .disabled(sources.busy)
                }
                Button {
                    Task {
                        await sources.sync { model.reloadCatalog() }
                        sources.load(rows: model.rows, repo: model.repo)
                    }
                } label: { Label(tr("Save and Sync", "저장하고 동기화"), systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!sources.canSync)
                    .help(tr("Saves catalog.tsv, updates setup files, then copies data to storage. Only the main Mac can edit shared data.",
                             "catalog.tsv와 설치 목록을 저장한 뒤 저장소에 복사해요. 공유 데이터는 주 맥에서만 고칠 수 있어요."))
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .tint(.indigo)
        .task {
            sources.load(rows: model.rows, repo: model.repo)
            await sources.pull()
            model.reloadCatalog()
            sources.load(rows: model.rows, repo: model.repo)
            await sources.checkAll()
        }
    }
}

struct SourceRow: View {
    @Environment(SourcesModel.self) private var sources
    let id: String
    @State private var showSuggestions = false

    var body: some View {
        if let i = sources.binding(id) {
            let e = sources.entries[i]
            let installed = sources.installedVersion(e.row)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(e.row.label).font(AppText.headline)
                    if let installed {
                        Tag(text: tr("installed \(installed)", "설치됨 \(installed)"), symbol: "checkmark")
                    } else if e.row.section == "app" {
                        Tag(text: tr("not installed", "설치 안 됨"), symbol: "minus")
                    }
                    if e.row.decision == .drop { Tag(text: tr("marked leave", "두고 가기로 함"), symbol: "minus.circle") }
                    if e.dirty { Tag(text: tr("edited", "수정함"), symbol: "pencil") }
                    Spacer()
                    Picker(tr("How", "방식"), selection: Binding(get: { e.how }, set: { sources.setHow(id, $0) })) {
                        Text(tr("GitHub release", "GitHub 릴리즈")).tag("release")
                        Text(tr("Download page", "다운로드 페이지")).tag("download")
                        Text(tr("Build", "직접 빌드")).tag("build")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                }
                HStack(spacing: 8) {
                    TextField(e.how == "release" ? "owner/repo" : "https://…",
                              text: Binding(get: { e.ref }, set: { sources.setRef(id, $0) }))
                        .textFieldStyle(.roundedBorder)
                        .font(AppText.body.monospaced())
                        .onSubmit { Task { await sources.check(id) } }
                    Button { open(e) } label: { Image(systemName: "arrow.up.right.square") }
                        .help(tr("Open in the browser", "브라우저로 열기"))
                    Button {
                        showSuggestions = true
                        Task { await sources.search(id) }
                    } label: { Label(tr("Find on GitHub", "GitHub에서 찾기"), systemImage: "magnifyingglass") }
                        .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                            SuggestionList(id: id) { showSuggestions = false }
                        }
                    Button { Task { await sources.check(id) } } label: { Image(systemName: "arrow.clockwise") }
                        .help(tr("Check again", "다시 확인"))
                    if e.dirty {
                        Button(tr("Revert", "되돌리기")) { sources.revert(id) }
                    }
                }
                StatusLine(id: id, entry: e, installed: installed)
            }
            .padding(.vertical, 8)
        }
    }

    private func open(_ e: SourcesModel.Entry) {
        let link = e.how == "release" ? SourcesModel.githubRepo(e.ref).map { "https://github.com/\($0)/releases" } : e.ref
        if let link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}

struct StatusLine: View {
    @Environment(SourcesModel.self) private var sources
    let id: String
    let entry: SourcesModel.Entry
    let installed: String?

    var body: some View {
        HStack(spacing: 6) {
            switch entry.check {
            case nil:
                if entry.dirty, let problem = SourcesModel.problem(how: entry.how, ref: entry.ref) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problem).foregroundStyle(.orange)
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
                    Text(tr("Not checked yet", "아직 확인 안 함")).foregroundStyle(.secondary)
                }
            case .checking:
                ProgressView().controlSize(.small)
                Text(tr("Checking…", "확인하는 중…")).foregroundStyle(.secondary)
            case .release(let tag, let asset):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(tr("Latest \(tag) · installs \(asset)", "최신 \(tag) · \(asset) 설치")).foregroundStyle(.secondary)
                if let installed, Self.version(tag) != Self.version(installed) {
                    Tag(text: tr("update: \(installed) → \(Self.version(tag))", "업데이트: \(installed) → \(Self.version(tag))"), symbol: "arrow.up.circle")
                }
            case .releaseAvailable(_, let tag, let asset):
                Image(systemName: "sparkles").foregroundStyle(.blue)
                Text(tr("This repo has release \(tag) with \(asset)", "이 저장소에 \(tag) 릴리즈(\(asset))가 있어요")).foregroundStyle(.secondary)
                Button(tr("Install It Automatically", "자동 설치로 바꾸기")) { sources.useRelease(id) }
                    .buttonStyle(.link)
            case .failed(let message):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text(message).foregroundStyle(.red).lineLimit(2)
            case .page:
                Image(systemName: entry.how == "build" ? "hammer" : "safari").foregroundStyle(.secondary)
                Text(entry.how == "build"
                     ? tr("Built by hand from this repo (no release found)", "이 저장소에서 직접 빌드해요 (릴리즈 없음)")
                     : tr("Setup opens this page in the browser", "설치할 때 이 페이지를 브라우저로 열어요"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(AppText.callout)
    }

    static func version(_ s: String) -> String { s.hasPrefix("v") ? String(s.dropFirst()) : s }
}

struct SuggestionList: View {
    @Environment(SourcesModel.self) private var sources
    let id: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Pick the original repo", "원본 저장소를 골라 주세요")).font(AppText.headline).padding(12)
            Divider()
            if let i = sources.binding(id) {
                let e = sources.entries[i]
                if e.searching {
                    HStack { ProgressView().controlSize(.small); Text(tr("Searching GitHub…", "GitHub에서 찾는 중…")) }
                        .foregroundStyle(.secondary).padding(16)
                } else if let list = e.suggestions, !list.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(list) { s in
                                Button {
                                    sources.pick(id, s)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.repo).font(AppText.body.monospaced().weight(.medium))
                                        Text(s.detail).font(AppText.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                } else {
                    Text(tr("No matching repos", "맞는 저장소가 없어요")).foregroundStyle(.secondary).padding(16)
                }
            }
        }
        .frame(width: 440)
        .frame(maxHeight: 420)
    }
}
