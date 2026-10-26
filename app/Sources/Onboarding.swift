import AppKit
import SwiftUI

// MARK: - Welcome window

/// The welcome flow a new user sees in its own window before the main window: what LazyMac does, where backups
/// go, the first backup and the passwords lock. Closing the window at any page skips the rest; Settings > Advanced
/// shows it again. Screenshot hook: LAZYMAC_SHOW=onboarding[:<page number from 0>].
enum Onboarding {
    static let windowID = "onboarding"
    static let doneKey = "onboardingDone"
    /// Set once the launch check ran, so reopening the main window never routes back here.
    @MainActor static var routed = false

    static var forcedPage: Int? {
        let show = (ProcessInfo.processInfo.environment["LAZYMAC_SHOW"] ?? "").split(separator: ":").map(String.init)
        guard show.first == "onboarding" else { return nil }
        return show.count > 1 ? Int(show[1]) ?? 0 : 0
    }

    /// True when this launch should open the welcome window instead of the main window. A Mac that already has a
    /// backup set up is marked done without seeing it, so people who used LazyMac before are not interrupted.
    @MainActor static func shouldShow(initialized: Bool) -> Bool {
        if forcedPage != nil { return true }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: doneKey) { return false }
        if initialized {
            defaults.set(true, forKey: doneKey)
            return false
        }
        return true
    }
}

struct OnboardingView: View {
    enum Page: Int, CaseIterable {
        case welcome, apps, settings, restore, place, backup, passwords, done
    }

    @Environment(SetupModel.self) private var model
    @Environment(BackupModel.self) private var backup
    @Environment(StorageModel.self) private var storage
    @Environment(MacBackup.self) private var mac
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.consoleSheet) private var consoleSheet
    @State private var page: Page = Onboarding.forcedPage.flatMap(Page.init(rawValue:)) ?? .welcome
    @State private var hasBackup = false
    @State private var working = false
    @State private var startedBackup = false

    private var place: StorageConfig.Place? { storage.config.place }
    private var placeReady: Bool {
        guard let place else { return false }
        if place.drive { return backup.rclonePath != nil && backup.remotes.contains(backup.config.remoteName) }
        return place.connected
    }
    private var backedUp: Bool { storage.config.isInitialized && startedBackup && !mac.running && !working }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 40)
            footer
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.xxl)
        }
        .font(AppText.body)
        .frame(width: 620, height: 540)
        .consoleSheet()
        .task(id: storage.config.target) {
            backup.refresh()
            hasBackup = await storage.placeHasBackup()
        }
        .onDisappear(perform: finish)
    }

    // MARK: Pages

    @ViewBuilder private var content: some View {
        switch page {
        case .welcome:
            PageBody(symbol: "laptopcomputer.and.arrow.down",
                     title: tr("Welcome to LazyMac", "LazyMac에 오신 걸 환영해요"),
                     text: tr("LazyMac remembers how your Mac is set up, so a new or erased Mac can be set up the same way again.",
                              "LazyMac은 맥을 어떻게 꾸며 두었는지 기억해 두었다가, 새 맥이나 초기화한 맥을 똑같이 다시 꾸며 줘요."))
        case .apps:
            PageBody(symbol: "square.grid.2x2",
                     title: tr("Your apps and tools", "앱과 도구"),
                     text: tr("LazyMac lists the apps and command-line tools on this Mac. On a new Mac it installs the ones you pick.",
                              "이 맥에 있는 앱과 명령줄 도구 목록을 만들어요. 새 맥에서는 고른 것만 설치해요."))
        case .settings:
            PageBody(symbol: "slider.horizontal.3",
                     title: tr("Your settings and folders", "설정과 폴더"),
                     text: tr("It saves app settings, your shell setup and the folders you choose, every day if you like.",
                              "앱 설정, 셸 설정, 고른 폴더를 저장해요. 원하면 매일 자동으로 해요."))
        case .restore:
            PageBody(symbol: "arrow.triangle.2.circlepath",
                     title: tr("Ready for a new Mac", "새 맥도 금방"),
                     text: tr("When you get a new Mac, open LazyMac there, point it at the same backup place and choose what to bring back.",
                              "새 맥에서 LazyMac을 열고 같은 백업 장소를 고른 뒤, 되살릴 것을 고르면 돼요."))
        case .place: placePage
        case .backup: backupPage
        case .passwords: passwordsPage
        case .done:
            PageBody(symbol: "checkmark.circle",
                     title: tr("You're all set", "준비가 끝났어요"),
                     text: storage.config.isInitialized
                        ? tr("LazyMac will show how each backup went. You can see this welcome again in Settings > Advanced.",
                             "백업이 어떻게 되었는지는 LazyMac 첫 화면에서 볼 수 있어요. 이 안내는 설정 > 고급에서 다시 볼 수 있어요.")
                        : tr("You can choose a backup place and back up any time from Back Up > This Mac.",
                             "백업 장소 고르기와 백업은 언제든 백업 > 이 맥에서 할 수 있어요."))
        }
    }

    private var placePage: some View {
        PageBody(symbol: "externaldrive",
                 title: tr("Choose where backups go", "백업을 둘 곳 고르기"),
                 text: tr("A folder on an external disk is safest: the backup stays safe even if this Mac breaks. Any folder works.",
                          "외장 디스크의 폴더가 가장 안전해요. 이 맥이 고장 나도 백업은 남으니까요. 어느 폴더든 괜찮아요.")) {
            VStack(spacing: Space.l) {
                if let place, placeReady {
                    StatusLabel(kind: .ok, text: place.sentence)
                } else if let place, place.drive {
                    StatusLabel(kind: .problem, text: tr("Google Drive is not connected yet. Finish the steps in Settings.", "Google 드라이브가 아직 연결되지 않았어요. 설정에서 남은 단계를 마쳐 주세요."))
                } else if let place, !place.connected {
                    StatusLabel(kind: .problem, text: tr("The disk “\(place.disk ?? "")” is not connected. Connect it, or choose another folder.", "“\(place.disk ?? "")” 디스크가 연결되어 있지 않아요. 디스크를 연결하거나 다른 폴더를 골라 주세요."))
                }
                Button(placeReady ? tr("Choose Another Folder…", "다른 폴더 고르기…") : tr("Choose Folder…", "폴더 고르기…")) {
                    storage.chooseFolder()
                }
                .controlSize(.large)
                .fixedSize()
                Button(place?.drive == true ? tr("Open Google Drive Settings…", "Google 드라이브 설정 열기…") : tr("Use Google Drive Instead…", "Google 드라이브 쓰기…")) {
                    if place?.drive != true {
                        storage.config.backend = .gdrive
                        storage.save()
                    }
                    SettingsTab.open(.place, openSettings)
                }
                .buttonStyle(.link)
                .fixedSize()
                Text(tr("Google Drive uses rclone, which LazyMac can install for you.", "Google 드라이브는 rclone을 써요. LazyMac이 설치해 줄 수 있어요."))
                    .font(AppText.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var backupPage: some View {
        PageBody(symbol: "arrow.up.doc",
                 title: tr("Back up now", "지금 백업하기"),
                 text: hasBackup
                    ? tr("This place already has a LazyMac backup. LazyMac uses its list on this Mac and adds this Mac to it.",
                         "이 장소에는 이미 LazyMac 백업이 있어요. 그 목록을 이 맥에서 쓰고, 이 맥도 함께 저장해요.")
                    : tr("LazyMac lists your apps and tools, saves your settings and copies them to the backup place. It takes about a minute.",
                         "LazyMac이 앱과 도구 목록을 만들고 설정을 저장한 뒤 백업 장소로 복사해요. 1분쯤 걸려요.")) {
            VStack(spacing: Space.l) {
                if !placeReady {
                    StatusLabel(kind: .info, text: tr("Choose a backup place first.", "먼저 백업 장소를 골라 주세요."))
                } else {
                    MissingHelpersLine()
                }
                if backedUp {
                    StatusLabel(kind: mac.outcome?.ok == false ? .problem : .ok,
                                text: mac.outcome?.ok == false ? tr("The backup did not finish. You can try again later.", "백업을 마치지 못했어요. 나중에 다시 해 보세요.")
                                                               : tr("This Mac is backed up.", "이 맥을 백업했어요."))
                } else {
                    HStack(spacing: Space.l) {
                        Button(tr("Back Up This Mac", "이 맥 백업하기")) { start() }
                            .controlSize(.large)
                            .disabled(!placeReady || working || mac.running || !Helper.missing(main: !hasBackup).isEmpty)
                            .fixedSize()
                        if working || mac.running || storage.busy { ProgressView().controlSize(.small) }
                    }
                }
                if let message = storage.message, !storage.initialized, !working {
                    StatusLabel(kind: .info, text: message)
                }
            }
        }
    }

    private var passwordsPage: some View {
        PageBody(symbol: "lock",
                 title: tr("Lock your passwords", "비밀번호 잠그기"),
                 text: tr("LazyMac can lock your sign-in keys, like SSH keys and GitHub sign-ins, with a passphrase you choose. Write the passphrase down somewhere safe: without it nobody can open them, not even LazyMac.",
                          "SSH 키, GitHub 로그인 같은 로그인 키를 직접 정한 암호로 잠가 둘 수 있어요. 암호는 안전한 곳에 꼭 적어 두세요. 암호가 없으면 LazyMac도 열 수 없어요.")) {
            VStack(spacing: Space.l) {
                if Helper.age.path == nil {
                    Button(tr("Install age", "age 설치")) {
                        backup.install([.age])
                        consoleSheet.wrappedValue = true
                    }
                    .controlSize(.large)
                    .disabled(backup.busy)
                    .fixedSize()
                } else {
                    Button(tr("Lock Passwords…", "비밀번호 잠그기…")) {
                        backup.lockSecrets(startList: true)
                        consoleSheet.wrappedValue = true
                    }
                    .controlSize(.large)
                    .disabled(!storage.config.isInitialized || backup.busy)
                    .fixedSize()
                }
                Text(tr("You can skip this and do it any time from Back Up > This Mac.", "건너뛰고 나중에 백업 > 이 맥에서 언제든 할 수 있어요."))
                    .font(AppText.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(tr("Back", "뒤로")) { move(-1) }
                .opacity(page == .welcome ? 0 : 1)
                .disabled(page == .welcome)
            Spacer()
            Button(nextTitle) { page == .done ? close() : move(1) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(working || mac.running)
        }
        .overlay {
            HStack(spacing: Space.s) {
                ForEach(Page.allCases, id: \.self) { p in
                    Circle()
                        .fill(p == page ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(tr("Page \(page.rawValue + 1) of \(Page.allCases.count)", "\(Page.allCases.count)쪽 중 \(page.rawValue + 1)쪽"))
        }
        .controlSize(.large)
    }

    private var nextTitle: String {
        switch page {
        case .welcome: tr("Get Started", "시작하기")
        case .place: placeReady ? tr("Next", "다음") : tr("Skip", "건너뛰기")
        case .backup: backedUp ? tr("Next", "다음") : tr("Skip", "건너뛰기")
        case .passwords: tr("Next", "다음")
        case .done: tr("Open LazyMac", "LazyMac 열기")
        default: tr("Next", "다음")
        }
    }

    private func move(_ by: Int) {
        if let p = Page(rawValue: page.rawValue + by) { page = p }
    }

    private func start() {
        working = true
        startedBackup = true
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

    private func close() {
        finish()
        dismissWindow(id: Onboarding.windowID)
    }

    /// Finishing, or closing the window early, marks the welcome as seen and opens the main window.
    private func finish() {
        UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
        openWindow(id: "main")
    }
}

/// One centered welcome page: a symbol, a title, one or two sentences and optional controls under them.
private struct PageBody<Extra: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: Space.xxl) {
            Image(systemName: symbol)
                .font(.system(size: 56 * TextScale.current, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(height: 72 * TextScale.current)
                .accessibilityHidden(true)
            VStack(spacing: Space.m) {
                Text(title)
                    .font(AppText.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            extra
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 480)
    }
}

extension PageBody where Extra == EmptyView {
    init(symbol: String, title: String, text: String) {
        self.init(symbol: symbol, title: title, text: text) { EmptyView() }
    }
}
