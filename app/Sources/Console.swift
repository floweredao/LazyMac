import Foundation
import Observation

/// Runs one command inside a pseudo-terminal (through /usr/bin/script) so that sudo, age and
/// gh can ask their questions, and streams what it prints. Answers go back through `send`.
@MainActor @Observable
final class Console {
    enum Prompt: Equatable {
        case secret(String)
        case text(String)
    }

    struct Line: Identifiable {
        let id: Int
        let text: String
    }

    private(set) var lines: [Line] = []
    private(set) var partial = ""
    private(set) var running = false
    private(set) var title = ""
    private(set) var exitCode: Int32?
    private(set) var prompt: Prompt?
    private(set) var oneTimeCode: String?

    @ObservationIgnored var onLine: ((String) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var pending = Data()
    @ObservationIgnored private var pendingCR = false
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var exited: Int32?
    @ObservationIgnored private var outputClosed = false
    @ObservationIgnored private var onExit: ((Int32) -> Void)?

    private static let maxLines = 6000
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[()][0-9A-Za-z]|\u{1B}[=>78]")
    private static let code = try! NSRegularExpression(pattern: "one-time code: ([A-Z0-9]{4}-[A-Z0-9]{4})")

    nonisolated static let path = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    func run(title: String, command: [String], environment extra: [String: String] = [:], onExit: @escaping (Int32) -> Void) {
        guard !running else { return }
        self.title = title
        lines = []
        partial = ""
        exitCode = nil
        prompt = nil
        oneTimeCode = nil
        pending = Data()
        pendingCR = false
        exited = nil
        outputClosed = false
        self.onExit = onExit

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null"] + command
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.path
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        for (k, v) in extra { env[k] = v }
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = inp
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processExited(status) } }
        }
        do {
            try p.run()
        } catch {
            append(tr("Could not start: \(error.localizedDescription)", "시작하지 못했어요: \(error.localizedDescription)"))
            exitCode = 127
            onExit(127)
            return
        }
        process = p
        input = inp.fileHandleForWriting
        running = true
    }

    func send(_ text: String) {
        guard running else { return }
        try? input?.write(contentsOf: Data((text + "\r").utf8))
        prompt = nil
    }

    func stop() {
        guard running else { return }
        try? input?.write(contentsOf: Data([0x03]))
        process?.interrupt()
    }

    private func receive(_ data: Data) {
        if data.isEmpty {
            outputClosed = true
            finishIfDone()
            return
        }
        pending.append(data)
        // A chunk can end in the middle of a multi-byte character; keep those bytes for the next chunk.
        var text: String?
        for cut in 0...min(3, pending.count) {
            if let s = String(data: pending.prefix(pending.count - cut), encoding: .utf8) {
                text = s
                pending = Data(pending.suffix(cut))
                break
            }
        }
        guard let text else {
            ingest(String(decoding: pending, as: UTF8.self))
            pending = Data()
            return
        }
        ingest(text)
    }

    private func ingest(_ raw: String) {
        let ns = raw as NSString
        let clean = Self.ansi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        for ch in clean {
            switch ch {
            case "\n", "\r\n":
                commit()
            case "\r":
                pendingCR = true
            case "\u{08}":
                if !partial.isEmpty { partial.removeLast() }
            default:
                if pendingCR {
                    partial = ""
                    pendingCR = false
                }
                if ch.isASCII, let v = ch.asciiValue, v < 0x20, ch != "\t" { continue }
                partial.append(ch)
            }
        }
        detectPrompt()
    }

    private func commit() {
        pendingCR = false
        let line = partial
        partial = ""
        append(line)
        if let m = Self.code.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            oneTimeCode = (line as NSString).substring(with: m.range(at: 1))
        }
        onLine?(line)
    }

    private func append(_ text: String) {
        lines.append(Line(id: nextID, text: text))
        nextID += 1
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    private func detectPrompt() {
        let t = partial.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { prompt = nil; return }
        let low = t.lowercased()
        if low.contains("password") || low.contains("passphrase") || t.contains("암호") {
            prompt = .secret(t)
        } else if low.contains("press return") || low.contains("press enter") || low.contains("[y/n]")
                    || low.contains("(y/n)") || t.hasSuffix("?") || t.hasSuffix(":") {
            prompt = .text(t)
        } else {
            prompt = nil
        }
    }

    private func processExited(_ status: Int32) {
        exited = status
        // The output pipe normally closes right after the process; do not wait on it forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                self?.outputClosed = true
                self?.finishIfDone()
            }
        }
        finishIfDone()
    }

    private func finishIfDone() {
        guard running, outputClosed, let status = exited else { return }
        if !partial.isEmpty { commit() }
        running = false
        prompt = nil
        exitCode = status
        process = nil
        try? input?.close()
        input = nil
        let done = onExit
        onExit = nil
        done?(status)
    }
}
