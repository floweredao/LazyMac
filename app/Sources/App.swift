import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        if args.contains("--storage-status") {
            let model = StorageModel()
            await model.refreshCapacity()
            if let capacity = model.capacity, let data = try? JSONEncoder().encode(capacity) {
                print(String(decoding: data, as: UTF8.self))
            } else { print("{}") }
            return
        }
        if let raw = value(args, "--storage-init"), let mode = StorageModel.Start(rawValue: raw) {
            let model = StorageModel()
            await model.initialize(mode)
            if let message = model.message { print(message) }
            exit(model.initialized ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--write-setup") {
            exit(writeSetup(args, at: i))
        }
        if let i = args.firstIndex(of: "--schedule") {
            exit(schedule(args, at: i))
        }
        if args.contains("--run-backup") {
            exit(ScheduledBackup.run())
        }
        LazymacApp.main()
    }

    static func value(_ args: [String], _ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    static func fail(_ message: String, _ code: Int32) -> Int32 {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        return code
    }

    // Test hook: `lazymac --write-setup <dir> [--repo <path>] [--profile <base[,add-on...]>]` writes the setup files
    // for the default (keep) choice, or for a profile, without opening a window; tests/app-setup-files.sh compares
    // them with setup/ and with `bun bin/catalog.ts profile`.
    static func writeSetup(_ args: [String], at i: Int) -> Int32 {
        guard i + 1 < args.count else { return fail("usage: lazymac --write-setup <dir> [--repo <path>] [--profile <names>]", 2) }
        guard let repo = value(args, "--repo").map({ URL(fileURLWithPath: $0) }) ?? SetupModel.findRepo() else {
            return fail("no LazyMac repo found; pass --repo <path>", 2)
        }
        do {
            let rows = try Catalog.parse(String(contentsOf: repo.appendingPathComponent("catalog.tsv"), encoding: .utf8))
            var chosen = rows.filter { $0.step != nil && $0.decision == .keep }
            if let names = value(args, "--profile") {
                let keys: Set<String>
                do { keys = try Profiles.resolve(names: names, rows: rows, repo: repo).keys } catch { return fail("profile: \(error.localizedDescription)", 2) }
                chosen = rows.filter { $0.step != nil && keys.contains(Profiles.key($0)) }
            }
            try Catalog.write(Catalog.setupFiles(chosen: chosen, all: rows), to: URL(fileURLWithPath: args[i + 1]))
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    // Test hook: `lazymac --schedule <spec>|off|show [--repo <path>]` changes the auto backup LaunchAgent the
    // same way the settings window does. spec: hourly[:MM] | every:<N>[:HH:MM] | daily:HH:MM | weekly:<0-6>:HH:MM
    static func schedule(_ args: [String], at i: Int) -> Int32 {
        guard i + 1 < args.count else { return fail("usage: lazymac --schedule <spec>|off|show [--repo <path>]", 2) }
        let repo = value(args, "--repo").map { URL(fileURLWithPath: $0) } ?? SetupModel.findRepo()
        let spec = args[i + 1]
        do {
            switch spec {
            case "show": break
            case "off": try AutoBackup.remove()
            default:
                guard let s = BackupSchedule(spec: spec) else { return fail("bad schedule: \(spec)", 2) }
                try AutoBackup.install(s, repo: repo)
            }
        } catch {
            return fail(error.localizedDescription, 1)
        }
        print(AutoBackup.current().map { "on\t\($0.summary)" } ?? "off")
        return 0
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Screenshot hooks: LAZYMAC_APPEARANCE=dark|light shows the app in that mode whatever the system uses;
    // LAZYMAC_SHOW=<page> opens that page (overview, folders, schedule, restoreFolders, apps), a wizard stage
    // (prepare, choose[:compare|:save], review, install) or settings; LAZYMAC_WINDOW=<width>x<height> sizes the window;
    // LAZYMAC_DO=backup|check|find presses Back Up Now, Check or Find Backed-Up Folders when the window opens.
    // LAZYMAC_TEXT_SCALE=<1-2> draws the text that much larger (View > Bigger Text does the same).
    func applicationWillFinishLaunching(_ notification: Notification) {
        switch ProcessInfo.processInfo.environment["LAZYMAC_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    // LAZYMAC_SNAPSHOT_DELAY=<seconds> waits that long instead of 4 (GitHub's sign-in check can take ~8 s).
    // LAZYMAC_SNAPSHOT=<dir> draws every visible window (and its sheet) into <dir>/<n>.png after a few seconds and
    // quits, so README screenshots can be made without the window being on screen.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        if let size = env["LAZYMAC_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for w in NSApp.windows where w.title == "LazyMac" || w.identifier?.rawValue.hasPrefix("main") == true {
                    w.setContentSize(NSSize(width: size[0], height: size[1]))
                }
            }
        }
        guard let dir = env["LAZYMAC_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["LAZYMAC_SNAPSHOT_DELAY"] ?? "") ?? 4)) {
            var n = 0
            for window in NSApp.windows where window.isVisible {
                for w in [window] + (window.attachedSheet.map { [$0] } ?? []) {
                    guard let view = w.contentView?.superview ?? w.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let name = w.title.isEmpty ? (w.isSheet ? "sheet" : "window") : w.title
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(n)-\(name).png"))
                    n += 1
                }
            }
            exit(0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LazymacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SetupModel()
    @State private var backup = BackupModel()
    @State private var sources = SourcesModel()
    @State private var storage = StorageModel()
    @State private var mac = MacBackup()

    var body: some Scene {
        Window("LazyMac", id: "main") {
            ContentView()
                .environment(model)
                .environment(backup)
                .environment(storage)
                .environment(mac)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear { backup.repo = { [model] in model.repo } }
        }
        .defaultSize(width: 1040, height: 720)
        .windowToolbarStyle(.unified)
        .commands { TextSizeCommands() }

        Window(tr("Welcome to LazyMac", "LazyMac 시작하기"), id: Onboarding.windowID) {
            OnboardingView()
                .environment(model)
                .environment(backup)
                .environment(storage)
                .environment(mac)
                .onAppear { backup.repo = { [model] in model.repo } }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window(tr("App Sources", "앱 출처"), id: "sources") {
            SourcesView()
                .environment(model)
                .environment(sources)
        }
        .defaultSize(width: 1000, height: 720)

        Settings {
            SettingsView()
                .environment(model)
                .environment(backup)
                .environment(storage)
                .environment(mac)
        }
    }
}
