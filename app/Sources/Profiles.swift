import Foundation

// profiles/<name>.txt and machines.tsv, read the same way bin/catalog.ts reads them, so a profile picked
// in the app gives the same lists as `bun bin/catalog.ts profile <names> <dir>` (tests/app-setup-files.sh).
//   base profile:  `from keep | empty | <base>` then lines
//   add-on:        no from line, only lines
//   lines:         `+ group <section>/<group>` (its keep and ask rows), `- group ...`, `+ <section>/<id>`,
//                  `- <section>/<id>`, `skip <step>...`

struct Profile: Identifiable, Hashable {
    struct Op: Hashable {
        let add: Bool
        let group: String?
        let key: String?
    }

    let name: String
    let from: String?
    let ops: [Op]
    let skip: [String]
    let note: String

    var id: String { name }
    var isBase: Bool { from != nil }
}

enum Profiles {
    static let nameRule = #"^[a-z0-9][a-z0-9-]*$"#

    static func key(_ r: CatalogRow) -> String { "\(r.section)/\(r.ids.joined(separator: ","))" }

    static func parse(_ name: String, _ text: String) throws -> Profile {
        var from: String?
        var ops: [Profile.Op] = []
        var skip: [String] = []
        var note = ""
        func fail(_ i: Int, _ en: String, _ ko: String) -> CatalogError {
            CatalogError(message: tr("\(name) line \(i + 1): \(en)", "\(name) \(i + 1)번째 줄: \(ko)"))
        }
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                if note.isEmpty { note = trimmed.dropFirst().trimmingCharacters(in: .whitespaces) }
                continue
            }
            let line = (trimmed.range(of: #"\s+#.*$"#, options: .regularExpression).map { String(trimmed[..<$0.lowerBound]) } ?? trimmed)
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if words[0] == "from", words.count == 2 {
                guard from == nil else { throw fail(i, "a second from line", "from 줄이 두 번 있어요") }
                from = words[1]
            } else if words[0] == "+" || words[0] == "-", words.count >= 2 {
                if words[1] == "group", words.count == 3, words[2].contains("/") {
                    ops.append(.init(add: words[0] == "+", group: words[2], key: nil))
                } else {
                    let rest = line.dropFirst(1).trimmingCharacters(in: .whitespaces)
                    guard rest.contains("/") else { throw fail(i, "cannot read \"\(line)\"", "\"\(line)\"을 읽을 수 없어요") }
                    ops.append(.init(add: words[0] == "+", group: nil, key: rest))
                }
            } else if words[0] == "skip", words.count >= 2 {
                for s in words.dropFirst() {
                    guard Step(rawValue: s) != nil else { throw fail(i, "unknown step \(s)", "모르는 단계 \(s)") }
                    skip.append(s)
                }
            } else {
                throw fail(i, "cannot read \"\(line)\"", "\"\(line)\"을 읽을 수 없어요")
            }
        }
        return Profile(name: name, from: from, ops: ops, skip: skip, note: note)
    }

    static func dir(_ repo: URL) -> URL { repo.appendingPathComponent("profiles") }

    static func load(_ name: String, repo: URL) throws -> Profile {
        guard name.range(of: nameRule, options: .regularExpression) != nil else {
            throw CatalogError(message: tr("Bad profile name: \(name) (use a-z, 0-9 and -)", "프로필 이름이 맞지 않아요: \(name) (a-z, 0-9, - 만 써요)"))
        }
        let file = dir(repo).appendingPathComponent("\(name).txt")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw CatalogError(message: tr("No profile \(name) (profiles/\(name).txt)", "\(name) 프로필이 없어요 (profiles/\(name).txt)"))
        }
        return try parse(name, text)
    }

    /// Every profile in the repo, bases first, by name. A file that cannot be read is reported, not skipped silently.
    static func all(repo: URL) -> (profiles: [Profile], errors: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir(repo).path)) ?? []
        var out: [Profile] = []
        var errors: [String] = []
        for f in files.sorted() where f.hasSuffix(".txt") {
            do { out.append(try load(String(f.dropLast(4)), repo: repo)) } catch { errors.append(error.localizedDescription) }
        }
        return (out.sorted { ($0.isBase ? 0 : 1, $0.name) < ($1.isBase ? 0 : 1, $1.name) }, errors)
    }

    /// "section/group" keys from groups.tsv text.
    static func groupKeys(_ text: String) -> Set<String> {
        Set(text.components(separatedBy: "\n").filter { !$0.hasPrefix("#") }.dropFirst().compactMap { line in
            let c = line.components(separatedBy: "\t")
            return c.count == 4 ? "\(c[0])/\(c[1])" : nil
        })
    }

    private static func apply(_ p: Profile, to set: inout Set<String>, rows: [CatalogRow], groups: Set<String>) throws {
        for op in p.ops {
            let hit: [CatalogRow]
            if let g = op.group {
                let parts = g.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2, groups.contains(g) else {
                    throw CatalogError(message: tr("\(p.name): no group \(g) in groups.tsv", "\(p.name): groups.tsv에 \(g) 묶음이 없어요"))
                }
                hit = rows.filter { $0.section == parts[0] && $0.group == parts[1] && (!op.add || $0.decision != .drop) }
            } else {
                hit = rows.filter { key($0) == op.key }
                guard !hit.isEmpty else {
                    throw CatalogError(message: tr("\(p.name): no item \(op.key ?? "") in catalog.tsv", "\(p.name): catalog.tsv에 \(op.key ?? "") 항목이 없어요"))
                }
            }
            for r in hit {
                if op.add { set.insert(key(r)) } else { set.remove(key(r)) }
            }
        }
    }

    private static func baseSet(_ p: Profile, rows: [CatalogRow], groups: Set<String>, seen: [String], load: (String) throws -> Profile) throws -> Set<String> {
        guard let from = p.from else {
            throw CatalogError(message: tr("\(p.name) is an add-on profile (no from line); start with a base profile",
                                           "\(p.name)은 덧붙이는 프로필이에요(from 줄 없음). 기본 프로필부터 골라 주세요"))
        }
        guard !seen.contains(p.name) else {
            throw CatalogError(message: tr("Profile loop: \((seen + [p.name]).joined(separator: " -> "))", "프로필이 돌고 돌아요: \((seen + [p.name]).joined(separator: " -> "))"))
        }
        var set: Set<String>
        switch from {
        case "keep": set = Set(rows.filter { $0.decision == .keep }.map(key))
        case "empty": set = []
        default: set = try baseSet(load(from), rows: rows, groups: groups, seen: seen + [p.name], load: load)
        }
        try apply(p, to: &set, rows: rows, groups: groups)
        return set
    }

    /// A base profile, then add-ons on top in order. Returns catalog keys and the steps to leave out.
    static func resolve(base: Profile, addOns: [Profile], rows: [CatalogRow], groups: Set<String>,
                        load: (String) throws -> Profile) throws -> (keys: Set<String>, skip: [String]) {
        var keys = try baseSet(base, rows: rows, groups: groups, seen: [], load: load)
        var skip = base.skip
        for a in addOns {
            guard a.from == nil else {
                throw CatalogError(message: tr("\(a.name) is a base profile; only add-ons go after the first one",
                                               "\(a.name)은 기본 프로필이에요. 덧붙이는 프로필만 뒤에 올 수 있어요"))
            }
            try apply(a, to: &keys, rows: rows, groups: groups)
            for s in a.skip where !skip.contains(s) { skip.append(s) }
        }
        return (keys, skip)
    }

    /// `base,add-on,...` -> keys and skipped steps.
    static func resolve(names: String, rows: [CatalogRow], repo: URL) throws -> (keys: Set<String>, skip: [String]) {
        let parts = names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = parts.first else { throw CatalogError(message: tr("No profile name", "프로필 이름이 없어요")) }
        let groups = groupKeys((try? String(contentsOf: repo.appendingPathComponent("groups.tsv"), encoding: .utf8)) ?? "")
        return try resolve(base: load(first, repo: repo), addOns: parts.dropFirst().map { try load($0, repo: repo) }, rows: rows, groups: groups) {
            try load($0, repo: repo)
        }
    }

    /// A base profile that picks exactly `selected` (catalog row ids), written as changes from `from keep`.
    static func text(note: String, selected: Set<String>, skip: [Step], rows: [CatalogRow]) -> String {
        var lines = ["# " + (note.isEmpty ? "Saved from the LazyMac app" : note), "from keep"]
        for r in rows where r.step != nil {
            let on = selected.contains(r.id)
            if r.decision == .keep, !on { lines.append("- \(key(r))") }
            if r.decision != .keep, on { lines.append("+ \(key(r))") }
        }
        if !skip.isEmpty { lines.append("skip " + skip.map(\.rawValue).joined(separator: " ")) }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: This Mac

    static let host: String = {
        if let h = ProcessInfo.processInfo.environment["LAZYMAC_HOST"], !h.isEmpty { return h }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--get", "LocalHostName"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if p.terminationStatus == 0, !name.isEmpty { return name }
        }
        return ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? "mac"
    }()

    enum Role: String { case main, extra }

    /// machines.tsv: this Mac's role and profiles. A Mac not listed is extra with the pro profile.
    static func machine(repo: URL, host: String = Profiles.host) -> (role: Role, profiles: String) {
        let text = (try? String(contentsOf: repo.appendingPathComponent("machines.tsv"), encoding: .utf8)) ?? ""
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }.dropFirst()
        for line in lines {
            let c = line.components(separatedBy: "\t")
            guard c.count >= 2, c[0] == host else { continue }
            let profiles = c.count > 2 ? c[2].trimmingCharacters(in: .whitespaces) : ""
            return (c[1] == "main" ? .main : .extra, profiles.isEmpty ? "pro" : profiles)
        }
        return (.extra, "pro")
    }
}
