import Foundation

// catalog.tsv is the one list of everything; this mirrors what bin/catalog.ts reads and
// writes, so the app can turn any choice of rows into the same setup/ files.

enum Lang {
    static let korean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
    /// Dates follow the language the UI is shown in, not the region (a Korean UI says "9시간 전").
    static let locale = Locale(identifier: korean ? "ko_KR" : "en_US")
}

func tr(_ en: String, _ ko: String) -> String { Lang.korean ? ko : en }

func itemCount(_ n: Int) -> String { tr(n == 1 ? "1 item" : "\(n) items", "\(n)개") }

func itemsAndSteps(_ items: Int, _ steps: Int) -> String {
    tr("\(items == 1 ? "1 item" : "\(items) items") · \(steps == 1 ? "1 step" : "\(steps) steps")", "\(items)개 항목 · \(steps)단계")
}

enum Decision: String { case keep, drop, ask }

enum Step: String, CaseIterable, Identifiable {
    case brew, node, bun, python, scripts, releases, dotfiles, secrets, repos, jobs, downloads, check

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brew: tr("Homebrew and App Store", "Homebrew·App Store")
        case .node: "Node.js"
        case .bun: "bun"
        case .python: "Python"
        case .scripts: tr("Install-script tools", "설치 스크립트 도구")
        case .releases: tr("GitHub release apps", "GitHub 릴리즈 앱")
        case .dotfiles: tr("Settings files", "설정 파일")
        case .secrets: tr("Passwords and sign-in files", "비밀번호·로그인 파일")
        case .repos: tr("Other projects", "다른 프로젝트")
        case .jobs: tr("Background jobs", "백그라운드 작업")
        case .downloads: tr("Download-only apps", "직접 받는 앱")
        case .check: tr("Check what is left", "남은 것 확인")
        }
    }

    var detail: String {
        switch self {
        case .brew: tr("Installs apps, command-line tools and fonts with Homebrew and the App Store",
                       "앱, 명령줄 도구, 글꼴을 Homebrew와 App Store로 설치해요")
        case .node: tr("Installs Node.js with nvm, then the npm tools", "nvm으로 Node.js를 깔고 npm 도구를 설치해요")
        case .bun: tr("Installs bun and its global tools", "bun과 bun 전역 도구를 설치해요")
        case .python: tr("Installs Python with uv", "uv로 Python을 설치해요")
        case .scripts: tr("Tools that ship their own install script", "자체 설치 스크립트가 있는 도구")
        case .releases: tr("Installs apps from their latest GitHub release",
                           "최신 GitHub 릴리즈에서 앱을 받아 설치해요")
        case .dotfiles: tr("Copies shell, Git, tmux, npm and SSH settings (old files are backed up) and applies the Dock settings",
                           "셸·Git·tmux·npm·SSH 설정을 복사하고 (기존 파일은 백업) Dock 설정을 적용해요")
        case .secrets: tr("Restores sign-ins and API keys from the encrypted bundle (one passphrase)",
                          "암호화 묶음에서 로그인 정보와 API 키를 되살려요 (암호 한 번)")
        case .repos: tr("Gets and sets up the other projects your list names", "목록에 적힌 다른 프로젝트를 받아 준비해요")
        case .jobs: tr("Registers the background jobs you picked", "고른 백그라운드 작업을 등록해요")
        case .downloads: tr("Opens the download page of apps that have no Homebrew package",
                            "Homebrew에 없는 앱의 다운로드 페이지를 열어요")
        case .check: tr("Shows anything still missing after the install", "설치가 끝난 뒤 빠진 게 있는지 보여 줘요")
        }
    }

    var symbol: String {
        switch self {
        case .brew: "shippingbox"
        case .node: "hexagon"
        case .bun: "cube"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .scripts: "scroll"
        case .releases: "arrow.down.app"
        case .dotfiles: "slider.horizontal.3"
        case .secrets: "key"
        case .repos: "externaldrive.connected.to.line.below"
        case .jobs: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        case .check: "checklist"
        }
    }

    var hasItems: Bool {
        switch self {
        case .dotfiles, .secrets, .repos, .check: false
        default: true
        }
    }

    static func forHow(_ how: String) -> Step? {
        switch how {
        case "tap", "brew", "cask", "mas", "uv": .brew
        case "nvm", "npm": .node
        case "bun-install", "bun": .bun
        case "uv-python": .python
        case "script": .scripts
        case "release": .releases
        case "register": .jobs
        case "download", "build": .downloads
        default: nil
        }
    }
}

struct CatalogRow: Identifiable, Hashable {
    let section: String
    let group: String
    let ids: [String]
    let name: String
    let nameKo: String
    let decision: Decision
    let how: String
    let ref: String
    let whatEn: String
    let whatKo: String
    let whyEn: String
    let whyKo: String
    let line: Int

    var id: String { "\(section)|\(group)|\(ids.joined(separator: ","))" }
    var label: String { Lang.korean && !nameKo.isEmpty ? nameKo : name }
    var what: String { Lang.korean ? whatKo : whatEn }
    var why: String { Lang.korean ? whyKo : whyEn }
    var step: Step? { Step.forHow(how) }

    var source: String {
        switch how {
        case "brew", "cask", "tap": "Homebrew"
        case "mas": "App Store"
        case "npm": "npm"
        case "bun", "bun-install": "bun"
        case "uv", "uv-python": "uv"
        case "nvm": "nvm"
        case "script": tr("install script", "설치 스크립트")
        case "release": tr("GitHub release", "GitHub 릴리즈")
        case "register": tr("background", "백그라운드")
        case "download", "build": tr("download", "직접 받기")
        default: how
        }
    }
}

struct CatalogError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Catalog {
    static func parse(_ text: String) throws -> [CatalogRow] {
        let lines = text.components(separatedBy: "\n").enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty && !$0.element.hasPrefix("#") }
        var rows: [CatalogRow] = []
        for (i, (lineIndex, line)) in lines.dropFirst().enumerated() {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count == 12 else {
                throw CatalogError(message: tr("Your app list item \(i + 1): expected 12 columns, got \(c.count)",
                                               "앱 목록 \(i + 1)번째 항목: 열이 12개여야 하는데 \(c.count)개예요"))
            }
            guard let decision = Decision(rawValue: c[5]) else {
                throw CatalogError(message: tr("catalog.tsv item \(i + 1): unknown decision \(c[5])",
                                               "catalog.tsv \(i + 1)번째 항목: 알 수 없는 decision \(c[5])"))
            }
            rows.append(CatalogRow(section: c[0], group: c[1], ids: c[2].components(separatedBy: ","), name: c[3],
                                   nameKo: c[4], decision: decision, how: c[6], ref: c[7],
                                   whatEn: c[8], whatKo: c[9], whyEn: c[10], whyKo: c[11], line: lineIndex))
        }
        return rows
    }

    static let sectionOrder = ["app", "cli", "setting", "job", "secret", "elsewhere", "leftover"]

    static func sectionTitle(_ section: String) -> String {
        switch section {
        case "app": tr("Apps", "앱")
        case "cli": tr("Command-line tools", "명령줄 도구")
        case "job": tr("Running in the background", "뒤에서 도는 것")
        case "setting": tr("Settings and fonts", "설정·글꼴")
        case "secret": tr("Secrets and sign-ins", "비밀값·로그인")
        case "elsewhere": tr("Kept in other repos", "다른 저장소에 있는 것")
        case "leftover": tr("Leftovers on this Mac", "이 맥의 찌꺼기")
        default: section
        }
    }

    static let sectionSymbols: [String: String] = [
        "app": "square.grid.2x2", "cli": "terminal", "job": "clock.arrow.circlepath", "setting": "textformat",
        "secret": "key", "elsewhere": "shippingbox", "leftover": "trash",
    ]

    /// Subcategory titles from the repo's groups.tsv (section, group, title_en, title_ko), in display order,
    /// so new subcategories need no app release.
    @MainActor private(set) static var groupTitles: [String: (en: String, ko: String)] = [:]
    @MainActor private(set) static var groupOrder: [String] = []

    @MainActor static func loadGroups(_ text: String) {
        var titles: [String: (en: String, ko: String)] = [:]
        var order: [String] = []
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        for line in lines.dropFirst() {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count == 4 else { continue }
            titles["\(c[0])/\(c[1])"] = (c[2], c[3])
            order.append("\(c[0])/\(c[1])")
        }
        groupTitles = titles
        groupOrder = order
    }

    /// The part before ": " (the rest says how it comes back, which the README explains).
    @MainActor static func groupTitle(_ section: String, _ group: String) -> String {
        guard let t = groupTitles["\(section)/\(group)"] else { return group }
        return String(tr(t.en, t.ko).split(separator: ":", maxSplits: 1)[0])
    }

    /// `chosen` must be in catalog order; `all` supplies the Node and Python versions.
    static func setupFiles(chosen: [CatalogRow], all: [CatalogRow],
                           head: String = "# Generated by the lazymac app from the items you chose. Do not edit.\n") -> [String: String] {
        func of(_ how: String) -> [CatalogRow] { chosen.filter { $0.how == how } }
        func trusted(_ ref: String) -> String { ref.split(separator: "/").count == 3 ? ", trusted: true" : "" }
        func list(_ how: String, _ f: (CatalogRow) -> String) -> String { head + of(how).map(f).joined(separator: "\n") + "\n" }

        // A package from a third-party tap needs that tap even when the tap row itself was not ticked.
        var taps = of("tap").map(\.ref)
        for r in of("brew") + of("cask") {
            let parts = r.ref.split(separator: "/")
            guard parts.count == 3 else { continue }
            let tap = parts.prefix(2).joined(separator: "/")
            if !taps.contains(tap) { taps.append(tap) }
        }
        let brewfile = taps.map { "tap \"\($0)\"" }
            + of("brew").map { "brew \"\($0.ref)\"\(trusted($0.ref))" }
            + of("cask").map { "cask \"\($0.ref)\"\(trusted($0.ref))" }
            + of("mas").map { "mas \"\($0.name)\", id: \($0.ref)" }
            + of("uv").map { "uv \"\($0.ref)\"" }

        func version(_ how: String) -> String {
            (all.first { $0.how == how && $0.decision == .keep } ?? all.first { $0.how == how })?.ref ?? ""
        }
        let downloads = chosen.filter { $0.how == "download" || $0.how == "build" }
            .map { "\($0.name)\t\($0.ref)\t\(installedPath($0))" }

        return [
            "Brewfile": head + brewfile.joined(separator: "\n") + "\n",
            "npm.txt": list("npm") { $0.ref },
            "bun.txt": list("bun") { $0.ref },
            "scripts.tsv": list("script") { "\($0.ids[0])\t\($0.ref)" },
            "downloads.tsv": head + downloads.joined(separator: "\n") + "\n",
            "jobs.txt": list("register") { $0.ids[0] },
            "byhand.tsv": head + chosen.filter { $0.how == "byhand" && $0.section == "app" }
                .map { "\($0.name)\t\($0.ref.isEmpty ? "-" : $0.ref)" }.joined(separator: "\n") + "\n",
            "releases.tsv": list("release") { r in
                let parts = r.ref.split(separator: "#", maxSplits: 1).map(String.init)
                let pattern = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "-"
                return "\(r.name)\t\(parts[0])\t\(pattern)\t\(installedPath(r))"
            },
            "versions.env": "\(head)NODE_VERSION=\(version("nvm"))\nPYTHON_VERSION=\(version("uv-python"))\n",
        ]
    }

    static func installedPath(_ r: CatalogRow) -> String {
        if r.section == "app" { return "/Applications/\(r.ids[0]).app" }
        if r.group == "fonts" { return "~/Library/Fonts/\(r.ids[0])*" }
        return "~/.local/bin/\(r.ids[0])"
    }

    static func write(_ files: [String: String], to dir: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}
