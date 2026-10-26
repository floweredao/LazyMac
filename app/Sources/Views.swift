import AppKit
import SwiftUI

// The look: the README title. SF Pro (the system font) in bold for titles, black on white (white on black in dark
// mode), system grouped forms, no gradients or painted cards. Color is kept for meaning only: done, problem, asking.

/// macOS has no Dynamic Type, so LazyMac scales its own text (View > Bigger Text). Every font in the app comes
/// from here; the sizes are the macOS text style defaults.
enum TextScale {
    static let key = "textScale"
    static let steps: [Double] = [1, 1.15, 1.3, 1.5, 1.75, 2]

    static var current: Double {
        if let e = ProcessInfo.processInfo.environment["LAZYMAC_TEXT_SCALE"], let v = Double(e) { return v }
        let v = UserDefaults.standard.double(forKey: key)
        return v == 0 ? 1 : v
    }
}

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let page: CGFloat = 28
}

enum Metrics {
    static let contentWidth: CGFloat = 760
    static let firstRunWidth: CGFloat = 640
}

enum AppText {
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        default: 10
        }
    }

    static func font(_ style: Font.TextStyle) -> Font {
        .system(size: size(style) * TextScale.current, weight: style == .headline ? .bold : .regular)
    }

    static var largeTitle: Font { font(.largeTitle) }
    static var title: Font { font(.title) }
    static var title2: Font { font(.title2) }
    static var title3: Font { font(.title3) }
    static var headline: Font { font(.headline) }
    static var subheadline: Font { font(.subheadline) }
    static var body: Font { font(.body) }
    static var callout: Font { font(.callout) }
    static var footnote: Font { font(.footnote) }
    static var caption: Font { font(.caption) }
    static var caption2: Font { font(.caption2) }
}

struct TextSizeCommands: Commands {
    @AppStorage(TextScale.key) private var scale = 1.0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(tr("Bigger Text", "글자 크게")) { step(1) }.fixedSize()
                .keyboardShortcut("+", modifiers: .command)
                .disabled(scale >= TextScale.steps.last!)
            Button(tr("Smaller Text", "글자 작게")) { step(-1) }.fixedSize()
                .keyboardShortcut("-", modifiers: .command)
                .disabled(scale <= TextScale.steps.first!)
            Button(tr("Actual Size", "기본 크기")) { scale = 1 }.fixedSize()
                .keyboardShortcut("0", modifiers: .command)
                .disabled(scale == 1)
            Divider()
        }
    }

    private func step(_ d: Int) {
        let i = TextScale.steps.firstIndex { $0 >= scale } ?? 0
        scale = TextScale.steps[max(0, min(TextScale.steps.count - 1, i + d))]
    }
}

enum Page: String, CaseIterable, Identifiable {
    case overview, folders, schedule, apps, restoreFolders
    var id: String { rawValue }

    var isBackup: Bool { self == .overview || self == .folders || self == .schedule }

    var title: String {
        switch self {
        case .overview: tr("This Mac", "이 맥")
        case .folders: tr("Folders", "폴더")
        case .schedule: tr("Schedule", "일정")
        case .apps: tr("Apps and Settings", "앱과 설정")
        case .restoreFolders: tr("Folders", "폴더")
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .overview: tr("Back up this Mac", "이 맥 백업")
        case .folders: tr("Back up folders", "폴더 백업")
        case .restoreFolders: tr("Restore folders", "폴더 복원")
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "laptopcomputer"
        case .folders: "folder"
        case .schedule: "calendar.badge.clock"
        case .apps: "macbook.and.iphone"
        case .restoreFolders: "arrow.down.doc"
        }
    }

    var shortcut: KeyEquivalent { KeyEquivalent(Character("\((Page.allCases.firstIndex(of: self) ?? 0) + 1)")) }
}

struct ContentView: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(MacBackup.self) private var mac
    @Environment(\.openSettings) private var openSettings
    @AppStorage(TextScale.key) private var scale = 1.0

    var body: some View {
        page
            .font(AppText.body)
            .controlSize(TextScale.current >= 1.3 ? .large : .regular)
            .id(scale)
            .onAppear {
                let env = ProcessInfo.processInfo.environment
                if env["LAZYMAC_SHOW"] == "settings" { openSettings() }
                switch env["LAZYMAC_DO"] {
                case "backup": backup.backUpNow()
                case "mac-backup": mac.start(main: model.role == .main, folders: storage.config.files)
                case "check": backup.check()
                case "find": backup.listCloud()
                default: break
                }
            }
    }

    private var page: some View {
        HStack(spacing: 0) {
            NavList()
                .frame(width: 200 * min(TextScale.current, 1.4))
            Divider()
            Group {
                switch model.page {
                case .overview: OverviewView()
                case .folders: FoldersView()
                case .schedule: ScheduleView(inSettings: false)
                case .apps: AppsView()
                case .restoreFolders: RestoreFoldersView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Left list

struct NavList: View {
    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(\.openWindow) private var openWindow

    private var restorePages: [Page] {
        backup.backupHasFolders || model.page == .restoreFolders ? [.apps, .restoreFolders] : [.apps]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "LazyMac")
                .font(AppText.title.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
                .accessibilityAddTraits(.isHeader)

            NavHeader(title: tr("Back Up", "백업"))
            ForEach(Page.allCases.filter(\.isBackup)) { NavRow(page: $0) }
            NavHeader(title: tr("Restore", "복원")).padding(.top, 14)
            ForEach(restorePages) { NavRow(page: $0) }

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 6) {
                Button(tr("Manage App Sources…", "앱 출처 관리…")) { openWindow(id: "sources") }
                    .buttonStyle(.link)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(AppText.caption)
                    .disabled(!model.ready)
            }
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct NavHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppText.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

struct NavRow: View {
    @Environment(SetupModel.self) private var model
    let page: Page

    var body: some View {
        let active = model.page == page
        Button { model.page = page } label: {
            Label {
                Text(page.title)
            } icon: {
                Image(systemName: page.symbol).frame(width: 20 * TextScale.current)
            }
                .font(AppText.body.weight(active ? .semibold : .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(page.shortcut, modifiers: .command)
        .accessibilityLabel(page.accessibilityTitle)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Shared pieces

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppText.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(AppText.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 6)
    }
}

/// Form footers on macOS sit on the trailing side; this keeps their text on the leading edge like the rows.
struct FooterText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Text with its buttons beside it; at large text sizes (150% and up) the buttons go under the text so neither is cut.
struct AdaptiveRow<Content: View, Trailing: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if TextScale.current >= 1.5 {
            VStack(alignment: .leading, spacing: 8) {
                content
                HStack(spacing: 8) { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                content
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

struct BottomBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}

/// A status line: a symbol and words, so the state never rests on color alone.
struct StatusLabel: View {
    enum Kind { case ok, problem, info }
    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(kind == .info ? .secondary : .primary)
        } icon: {
            switch kind {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .problem: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Restore > Apps and Settings

struct AppsView: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            StageBar()
            Divider()
            Group {
                switch model.stage {
                case .prepare: PrepareView()
                case .choose: ChooseView()
                case .review: ReviewView()
                case .install: InstallView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StageBar: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        let compact = TextScale.current >= 1.5
        HStack(spacing: 6) {
            ForEach(SetupModel.Stage.allCases) { stage in
                if stage != .prepare {
                    Image(systemName: "chevron.right").font(AppText.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                let active = model.stage == stage
                Button { model.stage = stage } label: {
                    HStack(spacing: 6) {
                        StageBadge(number: stage.rawValue + 1, complete: model.isComplete(stage), active: active)
                        if active || !compact {
                            Text(stage.title).font(AppText.callout.weight(active ? .semibold : .regular)).lineLimit(1).fixedSize()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!model.canOpen(stage))
                .help(stage.title)
                .accessibilityLabel(tr("Step \(stage.rawValue + 1): \(stage.title)", "\(stage.rawValue + 1)단계: \(stage.title)"))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct StageBadge: View {
    let number: Int
    let complete: Bool
    let active: Bool

    var body: some View {
        ZStack {
            if complete {
                Image(systemName: "checkmark.circle.fill").font(AppText.title3).foregroundStyle(.green)
            } else if active {
                Circle().fill(.primary)
                Text("\(number)").font(AppText.caption.weight(.bold).monospacedDigit()).foregroundStyle(Color(nsColor: .windowBackgroundColor))
            } else {
                Circle().strokeBorder(.secondary, lineWidth: 1)
                Text("\(number)").font(AppText.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 20 * TextScale.current, height: 20 * TextScale.current)
        .accessibilityHidden(true)
    }
}

// MARK: - Prepare

struct PrepareView: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: tr("Restore apps and settings", "앱과 설정 복원"),
                               subtitle: tr("Installs only what you pick from your backup list: apps, tools, settings and sign-ins.",
                                            "백업 목록에서 고른 앱, 도구, 설정, 로그인만 설치해요."))
                    Form {
                        Section {
                            CheckRow(symbol: "shippingbox", title: "Homebrew",
                                     detail: tr("A free installer for macOS that LazyMac uses to install your apps and tools.",
                                                "LazyMac이 앱과 도구를 설치할 때 쓰는 맥용 무료 설치 프로그램이에요."),
                                     done: model.brewPath != nil, enabled: true,
                                     action: (tr("Install", "설치"), model.installHomebrew))
                            RepoRow()
                        } footer: {
                            FooterText(tr("App Store apps install only after you sign in in the App Store app yourself.",
                                          "App Store 앱은 App Store 앱에서 직접 로그인한 뒤에 설치돼요."))
                        }
                        if let error = model.loadError {
                            Section { StatusLabel(kind: .problem, text: error) }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(maxWidth: 760, alignment: .leading)
                    if model.lastJob != nil && model.lastJob != .install && (model.console.running || !model.console.lines.isEmpty) {
                        ConsolePanel(console: model.console, copyCode: model.copyCodeAndContinue)
                            .frame(height: 260)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 20)
                            .frame(maxWidth: 760)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            BottomBar {
                Text(model.ready ? tr("Ready to choose what to install.", "설치할 항목을 고를 준비가 됐어요.") : tr("Set up your backup place first.", "먼저 백업 장소를 준비해 주세요."))
                    .foregroundStyle(.secondary)
            } trailing: {
                Button(tr("Choose Items", "항목 고르기")) { model.stage = .choose }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.ready)
            }
        }
    }
}

struct RepoRow: View {
    @Environment(SetupModel.self) private var model
    @Environment(StorageModel.self) private var storage
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.ready {
            CheckRow(symbol: "list.bullet.rectangle", title: tr("Your backup list", "백업 목록"),
                     detail: tr("\(itemCount(model.selectableRows.count)) ready to choose from.",
                                "고를 수 있는 항목이 \(model.selectableRows.count)개 있어요."),
                     done: true, enabled: true, action: ("", {}))
        } else if storage.config.hasPlace {
            CheckRow(symbol: "list.bullet.rectangle", title: tr("Your backup list", "백업 목록"),
                     detail: tr("Get the list from your backup place, or back up this Mac first.",
                                "백업 장소에서 목록을 가져오거나, 먼저 이 맥을 백업해 주세요."),
                     done: false, enabled: !storage.busy,
                     action: (tr("Get List from Backup", "백업에서 목록 가져오기"), {
                         Task {
                             await storage.initialize(.restore)
                             if storage.config.isInitialized { model.use(repo: storage.config.dataURL) }
                         }
                     }),
                     secondary: (tr("Back Up First", "먼저 백업하기"), { model.page = .overview }))
        } else {
            CheckRow(symbol: "list.bullet.rectangle", title: tr("Your backup list", "백업 목록"),
                     detail: tr("Choose where your backup is stored so LazyMac can load your list.",
                                "LazyMac이 목록을 불러올 수 있게 백업이 있는 장소를 골라 주세요."),
                     done: false, enabled: true,
                     action: (tr("Choose Backup Place…", "백업 장소 고르기…"), { SettingsTab.open(.place, openSettings) }),
                     secondary: (tr("Choose Folder…", "폴더 고르기…"), model.chooseRepo))
        }
    }
}

struct CheckRow: View {
    @Environment(SetupModel.self) private var model
    let symbol: String
    let title: String
    let detail: String
    let done: Bool
    let enabled: Bool
    let action: (String, () -> Void)
    var secondary: (String, () -> Void)?
    var checking = false

    var body: some View {
        AdaptiveRow {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .font(AppText.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28 * TextScale.current)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppText.headline)
                    Text(detail).font(AppText.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } trailing: {
            if checking && !done {
                ProgressView().controlSize(.small)
                Text(tr("Checking…", "확인하는 중…")).font(AppText.callout).foregroundStyle(.secondary)
            } else if done {
                if let secondary { Button(secondary.0, action: secondary.1).disabled(model.job != nil).fixedSize() }
                StatusLabel(kind: .ok, text: tr("Done", "완료")).font(AppText.callout).fixedSize()
            } else {
                if let secondary { Button(secondary.0, action: secondary.1).disabled(model.job != nil).fixedSize() }
                Button(action.0, action: action.1).disabled(!enabled || model.job != nil).fixedSize()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Choose

struct ChooseView: View {
    @Environment(SetupModel.self) private var model
    @State private var saving = false
    @State private var comparing = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(Step.allCases.filter { !$0.hasItems }) { step in
                        StepToggleRow(step: step)
                    }
                } header: {
                    GroupHeader(title: tr("Settings and wrap-up", "설정과 마무리"), rows: [])
                }
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.rows) { ItemRow(row: $0) }
                    } header: {
                        GroupHeader(title: group.title, rows: group.rows)
                    }
                }
                if model.groups.isEmpty {
                    Text(model.search.isEmpty
                         ? tr("Your list has no items yet. Back up this Mac first, or add items in Manage App Sources.",
                              "아직 목록에 항목이 없어요. 먼저 이 맥을 백업하거나 ‘앱 출처 관리’에서 항목을 추가해 주세요.")
                         : tr("Nothing matches “\(model.search)”", "“\(model.search)”에 맞는 항목이 없어요"))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            .searchable(text: $model.search, placement: .toolbar, prompt: tr("Search names and descriptions", "이름이나 설명으로 찾기"))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ProfileMenu(saving: $saving, comparing: $comparing)
                }
                ToolbarItemGroup {
                    Toggle(isOn: $model.showLeftBehind) { Label(tr("Show Left-Behind Items", "두고 가기로 한 것도 보기"), systemImage: "eye") }
                        .toggleStyle(.button)
                        .help(tr("Also shows the items your list marks leave behind", "목록에서 두고 가기로 한 항목도 보여 줘요"))
                    Button { model.resetSelection() } label: { Label(tr("Reset to List", "목록대로"), systemImage: "arrow.counterclockwise") }
                        .help(tr("Picks only the items your list marks bring", "목록에서 가져가기로 한 항목만 고른 상태로 되돌려요"))
                }
            }
            BottomBar {
                Text(itemsAndSteps(model.chosenRows.count, model.stepsToRun.count))
                    .font(AppText.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let message = model.profileError ?? model.profileStatus ?? model.profileFileErrors.first {
                    Text(message)
                        .font(AppText.callout)
                        .foregroundStyle(model.profileError != nil || model.profileStatus == nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(message)
                }
            } trailing: {
                Button(tr("Back", "이전")) { model.stage = .prepare }.fixedSize()
                Button(tr("Next: Review", "다음: 확인")) { model.stage = .review }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.stepsToRun.isEmpty)
            }
        }
        .navigationTitle(tr("Choose What to Bring", "가져갈 것 고르기"))
        .onAppear {
            if model.showSheet == "compare" { comparing = true } else if model.showSheet == "save" { saving = true }
            model.showSheet = nil
        }
        .sheet(isPresented: $saving) { SaveProfileSheet().environment(model) }
        .sheet(isPresented: $comparing) { CompareSheet().environment(model) }
    }
}

struct GroupHeader: View {
    @Environment(SetupModel.self) private var model
    let title: String
    let rows: [CatalogRow]

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(AppText.headline).foregroundStyle(.primary)
            if !rows.isEmpty {
                Text("\(rows.filter { model.isOn($0) }.count)/\(rows.count)")
                    .font(AppText.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                let allOn = rows.allSatisfy { model.isOn($0) }
                Button(allOn ? tr("Remove All", "모두 빼기") : tr("Add All", "모두 넣기")) { model.set(rows, !allOn) }.fixedSize()
                    .buttonStyle(.link)
                    .font(AppText.caption)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

struct ItemRow: View {
    @Environment(SetupModel.self) private var model
    let row: CatalogRow

    var body: some View {
        let on = Binding(get: { model.isOn(row) }, set: { model.set(row, $0) })
        HStack(spacing: 12) {
            Toggle(row.label, isOn: on).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.label).font(AppText.body.weight(.medium))
                    if row.decision == .drop { Tag(text: tr("marked leave", "두고 가기로 함"), symbol: "minus.circle") }
                    if row.decision == .ask { Tag(text: tr("undecided", "확인 필요"), symbol: "questionmark.circle") }
                }
                Text(row.what).font(AppText.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(row.source).font(AppText.caption).foregroundStyle(.secondary).fixedSize()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.set(row, !model.isOn(row)) }
        .help(row.why)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(model.isOn(row) ? tr("selected", "선택됨") : tr("not selected", "선택 안 됨"))
    }
}

struct StepToggleRow: View {
    @Environment(SetupModel.self) private var model
    let step: Step

    var body: some View {
        let on = Binding(get: { model.extraSteps.contains(step) },
                         set: { if $0 { model.extraSteps.insert(step) } else { model.extraSteps.remove(step) } })
        HStack(spacing: 12) {
            Toggle(step.title, isOn: on).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(AppText.body.weight(.medium))
                Text(step.detail).font(AppText.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { on.wrappedValue.toggle() }
    }
}

struct Tag: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(AppText.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Review

struct ReviewView: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: tr("Here is the plan", "이렇게 설치해요"),
                               subtitle: tr("Steps run from top to bottom. Anything already there is skipped and nothing is deleted, so running it again is safe.",
                                            "위에서부터 차례로 진행해요. 이미 있는 건 건너뛰고, 아무것도 지우지 않아요. 다시 실행해도 안전해요."))
                    Form {
                        Section {
                            ForEach(Step.allCases) { step in
                                ReviewStepRow(step: step, order: model.stepsToRun.firstIndex(of: step).map { $0 + 1 })
                            }
                        }
                        Section(tr("What it will ask you", "중간에 물어보는 것")) {
                            Label(tr("Your Mac password: Homebrew and some apps ask while installing.", "맥 로그인 암호: Homebrew와 일부 앱이 설치할 때 물어봐요."), systemImage: "lock")
                            Label(tr("The bundle passphrase: asked once in the secrets step.", "비밀값 묶음 암호: 비밀값 단계에서 한 번 물어봐요."), systemImage: "key")
                            Label(tr("When asked, the field under the output turns orange.", "물어볼 때는 출력 아래 입력칸이 주황색으로 바뀌어요."), systemImage: "character.cursor.ibeam")
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(maxWidth: 760, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            BottomBar {
                Text(itemsAndSteps(model.chosenRows.count, model.stepsToRun.count))
                    .font(AppText.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } trailing: {
                Button(tr("Back", "이전")) { model.stage = .choose }.fixedSize()
                Button(tr("Start Install", "설치 시작")) { model.startInstall() }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.stepsToRun.isEmpty || model.job != nil)
            }
        }
    }
}

struct ReviewStepRow: View {
    @Environment(SetupModel.self) private var model
    let step: Step
    let order: Int?

    var preview: String {
        let names = model.rows(for: step).map(\.label)
        guard !names.isEmpty else { return step.detail }
        let head = names.prefix(4).joined(separator: ", ")
        return names.count > 4 ? tr("\(head) and \(names.count - 4) more", "\(head) 외 \(names.count - 4)개") : head
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(order.map { "\($0)" } ?? "–")
                .font(AppText.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.title).font(AppText.body.weight(.medium))
                    if step.hasItems, order != nil {
                        Text(itemCount(model.rows(for: step).count)).font(AppText.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Text(order == nil ? tr("Skipped", "건너뜀") : preview).font(AppText.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .foregroundStyle(order == nil ? .secondary : .primary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Install

struct InstallView: View {
    @Environment(SetupModel.self) private var model

    var title: String {
        if let step = model.currentStep { return tr("Installing: \(step.title)", "\(step.title) 설치 중") }
        if model.installing { return tr("Starting", "시작하는 중") }
        if model.installFinished {
            return model.failedSteps.isEmpty ? tr("All done", "다 끝났어요") : tr("Some steps had problems", "일부 단계에 문제가 있어요")
        }
        return tr("Install", "설치")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(AppText.largeTitle.weight(.bold))
                    Spacer()
                    Text(tr("\(model.doneCount)/\(model.installSteps.count) steps", "\(model.doneCount)/\(model.installSteps.count) 단계"))
                        .font(AppText.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if model.installing {
                        Button(tr("Stop", "중지")) { model.console.stop() }.fixedSize()
                    }
                }
                ProgressView(value: Double(model.doneCount), total: Double(max(model.installSteps.count, 1)))
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.installSteps) { step in
                            InstallStepRow(step: step, state: model.stepStates[step] ?? .pending)
                        }
                    }
                }
                .frame(width: 200)
                ConsolePanel(console: model.console, copyCode: model.copyCodeAndContinue)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            if model.installFinished {
                ResultBar()
            }
        }
    }
}

struct InstallStepRow: View {
    let step: Step
    let state: SetupModel.StepState

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch state {
                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
                case .running: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .frame(width: 18, height: 18)
            Text(step.title)
                .font(AppText.callout.weight(state == .running ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(state == .running ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? tr("done", "완료") : state == .failed ? tr("problem", "문제") : state == .running ? tr("running", "진행 중") : tr("waiting", "대기"))
    }
}

struct ResultBar: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        BottomBar {
            if !model.byHandApps.isEmpty {
                StatusLabel(kind: .info, text: tr("Install these apps yourself: ", "이 앱은 직접 설치해 주세요: ")
                            + model.byHandApps.map(\.name).joined(separator: ", "))
                    .lineLimit(2)
            }
            if model.failedSteps.isEmpty {
                Text(model.hasOwnRestore
                     ? tr("Left for you: allow app permissions, sign in to apps, run the restore guides of tools that have their own", "남은 일: 앱이 요청하는 권한 허용, 앱 로그인, 자체 복원 안내가 있는 도구 복원")
                     : tr("Left for you: allow app permissions and sign in to apps", "남은 일: 앱이 요청하는 권한 허용, 앱 로그인"))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                StatusLabel(kind: .problem, text: tr("Steps with problems: ", "문제가 생긴 단계: ") + model.failedSteps.map(\.title).joined(separator: ", "))
                    .lineLimit(2)
            }
        } trailing: {
            if model.failedSteps.isEmpty {
                Button(tr("Back to Choose", "처음으로")) { model.stage = .choose }.fixedSize()
            } else {
                Button(tr("Choose Again", "항목 다시 고르기")) { model.stage = .choose }.fixedSize()
                Button(tr("Retry Failed Steps", "문제 단계만 다시")) { model.retryFailed() }.fixedSize()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Console

struct ConsolePanel: View {
    let console: Console
    var copyCode: (() -> Void)?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if console.running { ProgressView().controlSize(.small) }
                Text(console.title.isEmpty ? tr("Output", "출력") : console.title).font(AppText.caption.weight(.semibold))
                Spacer()
                if let code = console.exitCode {
                    Text(code == 0 ? tr("Finished", "끝남") : tr("Stopped with code \(code)", "종료 코드 \(code)")).font(AppText.caption.monospacedDigit())
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            if let code = console.oneTimeCode, console.running, let copyCode {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("GitHub one-time code", "GitHub 확인 코드")).font(AppText.caption).foregroundStyle(.secondary)
                        Text(code).font(AppText.title2.monospaced().weight(.bold)).textSelection(.enabled)
                    }
                    Spacer()
                    Button(tr("Copy and Open Browser", "복사하고 브라우저 열기"), action: copyCode).fixedSize()
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(console.lines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(console.partial.isEmpty ? " " : console.partial)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("end")
                    }
                    .font(AppText.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                }
                .onChange(of: console.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: console.partial) { proxy.scrollTo("end", anchor: .bottom) }
            }

            if console.running {
                Divider()
                inputBar
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .onChange(of: console.prompt) {
            guard console.prompt != nil else { return }
            DispatchQueue.main.async { focused = true }
        }
    }

    private var inputBar: some View {
        let asking = console.prompt != nil
        return HStack(spacing: 10) {
            switch console.prompt {
            case .secret(let p):
                Image(systemName: "lock.fill").foregroundStyle(.orange)
                SecureField(p, text: $text).focused($focused).onSubmit(send)
            case .text(let p):
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                TextField(p, text: $text).focused($focused).onSubmit(send)
            case nil:
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                TextField(tr("Answer here when asked, then press Return", "물어보면 여기에 답하고 Return"), text: $text).focused($focused).onSubmit(send)
            }
            Button(tr("Send", "보내기"), action: send).fixedSize()
        }
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(asking ? AnyShapeStyle(Color.orange.opacity(0.14)) : AnyShapeStyle(.clear))
    }

    private func send() {
        console.send(text)
        text = ""
    }
}
