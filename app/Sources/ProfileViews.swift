import SwiftUI

// MARK: - Profile menu (Choose toolbar)

struct ProfileMenu: View {
    @Environment(SetupModel.self) private var model
    @Binding var saving: Bool
    @Binding var comparing: Bool

    var body: some View {
        Menu {
            Section(tr("Mac profile", "맥 프로필")) {
                Button { model.resetSelection() } label: {
                    check(model.baseProfile == nil, tr("Catalog picks (every ✅ item)", "추천대로 (✅ 전부)"))
                }
                ForEach(model.baseProfiles) { p in
                    Button { model.apply(base: p.name, addOns: model.addOns) } label: { check(model.baseProfile == p.name, p.name, p.note) }
                }
            }
            Section(tr("Add on top", "덧붙이기")) {
                ForEach(model.addOnProfiles) { p in
                    Button { model.toggle(addOn: p.name) } label: { check(model.addOns.contains(p.name), p.name, p.note) }
                        .disabled(model.baseProfile == nil)
                }
            }
            Divider()
            Button(tr("Save as Profile…", "프로필로 저장…")) { saving = true }
                .disabled(model.role != .main)
            Button(tr("Compare with This Mac…", "이 맥과 비교…")) { comparing = true }
        } label: {
            Label(tr("Profile: \(model.profileTitle)", "프로필: \(model.profileTitle)"), systemImage: "person.crop.rectangle.stack")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help(tr("Start from a saved profile, add more on top, save your choice, or compare it with this Mac",
                 "저장한 프로필에서 시작하고, 덧붙이고, 고른 것을 저장하거나 이 맥과 비교해요"))
    }

    @ViewBuilder
    private func check(_ on: Bool, _ title: String, _ note: String = "") -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
        if !note.isEmpty { Text(note) }
    }
}

// MARK: - Save as profile

struct SaveProfileSheet: View {
    @Environment(SetupModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""

    var problem: String? {
        if name.isEmpty { return nil }
        if name.range(of: Profiles.nameRule, options: .regularExpression) == nil {
            return tr("Use lowercase letters, numbers and -", "영문 소문자, 숫자, - 만 써요")
        }
        if !model.isValidProfileName(name) { return tr("\(name) is an add-on profile; pick another name", "\(name)은 덧붙이는 프로필이에요. 다른 이름을 골라 주세요") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Save as Profile", "프로필로 저장")).font(AppText.title2.bold())
            Text(tr("Saves the \(itemCount(model.chosenRows.count)) you picked as profiles/<name>.txt, then copies it to storage for your other Macs.",
                    "고른 \(model.chosenRows.count)개를 profiles/<이름>.txt로 저장하고 다른 맥에서도 쓰도록 저장소에 복사해요."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(tr("Name", "이름"), text: $name, prompt: Text(verbatim: "air"))
                TextField(tr("Description", "설명"), text: $note, prompt: Text(tr("What this profile is for", "어디에 쓰는 프로필인지")))
            }
            .formStyle(.grouped)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if model.profileExists(name) {
                Label(tr("This replaces the profile \(name).", "\(name) 프로필을 덮어써요."), systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(tr("Cancel", "취소"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.profileExists(name) ? tr("Replace", "덮어쓰기") : tr("Save", "저장")) {
                    Task {
                        await model.saveProfile(name: name, note: note)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || problem != nil || model.savingProfile)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { name = model.addOns.isEmpty && !model.profileEdited ? (model.baseProfile ?? "") : "" }
    }
}

// MARK: - Compare with this Mac

struct CompareSheet: View {
    @Environment(SetupModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Compare with This Mac", "이 맥과 비교")).font(AppText.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                if model.comparing || model.scanning { ProgressView().controlSize(.small) }
            }
            if let error = model.compareError {
                StatusLabel(kind: .problem, text: error)
            }
            if let c = model.comparison {
                HStack(spacing: 10) {
                    Stat(value: c.missing.count, title: tr("Missing", "빠진 것"), tint: .orange)
                    Stat(value: c.extra.count, title: tr("Extra", "더 있는 것"), tint: .blue)
                    Stat(value: c.same, title: tr("Same", "같음"), tint: .green)
                }
                List {
                    Section {
                        if c.missing.isEmpty { Text(tr("Nothing", "없어요")).foregroundStyle(.secondary) }
                        ForEach(c.missing) { CompareRow(item: $0) }
                    } header: {
                        Text(tr("Missing: the install adds these", "빠진 것: 설치하면 들어와요"))
                    }
                    Section {
                        if c.extra.isEmpty { Text(tr("Nothing", "없어요")).foregroundStyle(.secondary) }
                        ForEach(c.extra) { CompareRow(item: $0) }
                    } header: {
                        Text(tr("Extra: on this Mac but not picked (shown only, never deleted)", "더 있는 것: 이 맥에 있지만 안 고른 것 (보여 주기만, 지우지 않아요)"))
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
                Text(tr("\(c.notChecked) picked items cannot be seen by a scan (settings, secrets, repos). \(c.unlisted) things on this Mac are not in the catalog yet.",
                        "고른 것 중 \(c.notChecked)개는 훑기로 볼 수 없어요 (설정·비밀값·저장소). 이 맥에 있지만 목록에 아직 없는 것이 \(c.unlisted)개 있어요."))
                    .font(AppText.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status = model.scanStatus {
                Text(status).font(AppText.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Button {
                    Task {
                        await model.scanThisMac()
                        await model.compare()
                    }
                } label: { Label(tr("Scan This Mac", "이 맥 훑기"), systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(model.scanning || model.comparing)
                    .help(tr("Scans this Mac (about a minute, read only) and copies its inventory to storage", "이 맥을 훑어서 (1분쯤, 읽기만 해요) 기록을 저장소에 복사해요"))
                Spacer()
                Button(tr("Done", "닫기")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 620)
        .task { await model.compare() }
    }

    var subtitle: String {
        let what = model.profileTitle
        guard let c = model.comparison else { return tr("\(what) · \(Profiles.host)", "\(what) · \(Profiles.host)") }
        let date = ISO8601DateFormatter().date(from: c.scanned.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
        let when = date.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Lang.locale)) } ?? c.scanned
        return tr("\(what) · \(c.host), scanned \(when)", "\(what) · \(c.host), \(when)에 훑음")
    }
}

struct Stat: View {
    let value: Int
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(AppText.title2.weight(.semibold).monospacedDigit())
            Text(title).font(AppText.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CompareRow: View {
    let item: SetupModel.CompareItem

    var body: some View {
        HStack {
            Text(item.label)
            Spacer()
            Text("\(Catalog.sectionTitle(item.section)) · \(Catalog.groupTitle(item.section, item.group))").font(AppText.caption).foregroundStyle(.secondary)
        }
    }
}
