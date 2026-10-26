import SwiftUI

// The "Status" card on This Mac: where automatic backups stand, read from the files bin/due.sh and daily.sh keep
// (schedule-state, the daily log, the backup lock) and the LaunchAgent's schedule, so it also follows a backup that
// launchd started while LazyMac was closed.

extension BackupSchedule {
    var period: TimeInterval {
        switch frequency {
        case .hourly: 3600
        case .everyHours: TimeInterval(max(1, everyHours) * 3600)
        case .daily: 86400
        case .weekly: 604_800
        }
    }

    private var components: [DateComponents] {
        intervals.map { i in
            var c = DateComponents()
            c.minute = i["Minute"]
            c.hour = i["Hour"]
            c.weekday = i["Weekday"].map { $0 % 7 + 1 }
            return c
        }
    }

    /// The latest scheduled time at or before `date` (bin/due.sh's "slot").
    func slot(atOrBefore date: Date) -> Date? {
        let probe = date.addingTimeInterval(1)
        return components.compactMap {
            Calendar.current.nextDate(after: probe, matching: $0, matchingPolicy: .nextTime, direction: .backward)
        }.max()
    }

    func next(after date: Date) -> Date? {
        components.compactMap { Calendar.current.nextDate(after: date, matching: $0, matchingPolicy: .nextTime) }.min()
    }
}

struct BackupStatus: Equatable {
    enum Phase: Equatable {
        case running(step: MacBackup.Step?, done: Int, total: Int)
        case paused(since: Date?)
        case retrying(after: Date)
        case waiting(offline: Bool)
        case missed(slot: Date)
        case upToDate
        case off
    }

    var phase: Phase
    var lastSuccess: Date?
    var next: Date?
    var failures = 0
    var problem: (reason: String, date: Date?)?

    var isRunning: Bool { if case .running = phase { true } else { false } }

    static func == (a: BackupStatus, b: BackupStatus) -> Bool {
        a.phase == b.phase && a.lastSuccess == b.lastSuccess && a.next == b.next && a.failures == b.failures
            && a.problem?.reason == b.problem?.reason && a.problem?.date == b.problem?.date
    }

    static var now: Date {
        ProcessInfo.processInfo.environment["LAZYMAC_NOW"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } ?? .now
    }

    /// `app` is a backup this window started (it knows its own steps); otherwise a running backup is read from its log.
    @MainActor static func read(app: MacBackup?, main: Bool, folders: Bool) -> BackupStatus {
        let now = now
        let schedule = AutoBackup.current()
        let last = DailyLog.latest()
        func epoch(_ key: String) -> Date? { BackupState.value(key).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } }
        var lastSuccess = epoch("last-success")
        if let last, last.ok, let d = last.date, d > (lastSuccess ?? .distantPast) { lastSuccess = d }
        let failures = Int(BackupState.value("failures") ?? "") ?? 0
        let problem: (String, Date?)? = last.flatMap { $0.ok ? nil : ($0.detail, $0.date) }

        var s = BackupStatus(phase: .off, lastSuccess: lastSuccess, next: nil, failures: failures, problem: problem)
        if let schedule { s.next = schedule.next(after: now) }

        if let app, app.running {
            s.phase = .running(step: app.currentStep, done: app.doneCount, total: app.steps.count)
            return s
        }
        if BackupLock.holder() != nil {
            let seen = DailyLog.todayRunLines().compactMap { l -> MacBackup.Step? in
                let body = l.count > 20 ? String(l.dropFirst(20)) : l
                return body.hasPrefix("step ") ? MacBackup.Step(rawValue: String(body.dropFirst(5))) : nil
            }
            let total = (main ? 5 : 3) + (folders ? 1 : 0)
            s.phase = .running(step: seen.last, done: max(0, seen.count - 1), total: max(total, seen.count))
            return s
        }
        if BackupState.paused { s.phase = .paused(since: BackupState.pausedSince); return s }
        guard let schedule else { s.phase = .off; return s }
        guard let slot = schedule.slot(atOrBefore: now), (lastSuccess ?? .distantPast) < slot,
              now.timeIntervalSince(lastSuccess ?? .distantPast) >= schedule.period / 2 else {
            s.phase = .upToDate
            return s
        }
        // Behind schedule: the same order of reasons bin/due.sh uses.
        if failures > 0, let attempt = epoch("last-attempt") {
            let wait = min(900 * pow(2, Double(min(failures, 4) - 1)), min(schedule.period, 7200))
            if attempt.addingTimeInterval(wait) > now {
                s.phase = .retrying(after: attempt.addingTimeInterval(wait))
                return s
            }
        }
        switch BackupState.deferred {
        case "offline": s.phase = .waiting(offline: true)
        case "metered" where BackupState.waitsOnMetered: s.phase = .waiting(offline: false)
        default: s.phase = .missed(slot: slot)
        }
        return s
    }
}

extension DailyLog {
    static func todayRunLines() -> [String] {
        let url = dir.appendingPathComponent(fileName(for: .now))
        let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let start = lines.lastIndex(where: { $0.contains(" === start") }) else { return [] }
        return Array(lines[start...])
    }
}

struct StatusSection: View {
    @Environment(StorageModel.self) private var storage
    let status: BackupStatus

    var body: some View {
        Section {
            nowRow
            LabeledContent(tr("Last successful backup", "마지막 성공")) {
                Text(status.lastSuccess.map(whenPhrase) ?? tr("Not yet", "아직 없어요"))
            }
            LabeledContent(tr("Next backup", "다음 백업")) { Text(nextText) }
            if let problem = status.problem {
                LabeledContent(tr("Last problem", "최근 문제")) {
                    VStack(alignment: .trailing, spacing: Space.xxs) {
                        Text(BackupProblem.explain(problem.reason).text)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(problemWhen(problem.date))
                            .font(AppText.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let place = storage.config.place {
                LabeledContent(tr("Backup place", "백업 장소")) {
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        Text(place.folder).lineLimit(1).truncationMode(.middle)
                        if let usage {
                            ProgressView(value: usage.fraction)
                                .frame(width: 160 * TextScale.current)
                                .accessibilityLabel(tr("Space used", "쓴 공간"))
                            Text(usage.text).font(AppText.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(tr("Status", "현황"))
        }
    }

    @ViewBuilder private var nowRow: some View {
        switch status.phase {
        case .running(let step, let done, let total):
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    StatusLabel(kind: .info, text: step.map { tr("Backing up: \($0.title)", "백업하는 중: \($0.title)") } ?? tr("Starting the backup", "백업을 시작하는 중"))
                    Spacer()
                    Text(tr("Step \(min(done + 1, total)) of \(total)", "\(total)단계 중 \(min(done + 1, total))단계"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .accessibilityLabel(tr("Backup progress", "백업 진행"))
            }
        case .paused(let since):
            StatusLabel(kind: .info, text: since.map { tr("Paused since \(whenPhrase($0))", "\(whenPhrase($0))부터 멈춰 있어요") } ?? tr("Paused", "멈춰 있어요"))
        case .retrying(let after):
            StatusLabel(kind: .problem, text: tr("The last try failed. Trying again after \(clock(after)).", "지난 시도가 실패했어요. \(clock(after)) 이후에 다시 해요."))
        case .waiting(let offline):
            StatusLabel(kind: .problem, text: offline
                ? tr("Behind schedule. Waiting for the internet.", "밀렸어요. 인터넷 연결을 기다리고 있어요.")
                : tr("Behind schedule. Waiting for a connection that does not charge for data.", "밀렸어요. 데이터 요금이 들지 않는 연결을 기다리고 있어요."))
        case .missed(let slot):
            StatusLabel(kind: .problem, text: tr("Missed \(whenPhrase(slot)). It backs up as soon as it can.", "\(whenPhrase(slot)) 백업을 놓쳤어요. 할 수 있게 되면 바로 해요."))
        case .upToDate:
            StatusLabel(kind: .ok, text: tr("Up to date", "최신이에요"))
        case .off:
            StatusLabel(kind: .info, text: tr("Automatic backup is off", "자동 백업이 꺼져 있어요"))
        }
    }

    private var nextText: String {
        switch status.phase {
        case .paused: return tr("After you resume", "다시 켠 뒤")
        case .off: return tr("When you click Back Up This Mac", "'이 맥 백업하기'를 누를 때")
        case .missed, .waiting: return tr("As soon as it can", "할 수 있게 되는 대로")
        case .retrying(let after): return whenPhrase(after)
        case .running, .upToDate: return status.next.map(whenPhrase) ?? "–"
        }
    }

    private func problemWhen(_ date: Date?) -> String {
        let when = date.map(whenPhrase) ?? tr("recently", "최근")
        return status.failures > 1 ? tr("\(when), \(status.failures) times in a row", "\(when), \(status.failures)번 연달아") : when
    }

    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private var usage: (fraction: Double, text: String)? {
        guard let c = storage.capacity, let total = c.total, let free = c.available, total > 0 else { return nil }
        let used = max(0, total - free)
        let fmt = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return (Double(used) / Double(total), tr("\(fmt(used)) of \(fmt(total)) used, \(fmt(free)) free", "\(fmt(total)) 중 \(fmt(used)) 사용, \(fmt(free)) 남음"))
    }
}
