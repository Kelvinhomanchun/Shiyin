import SwiftUI

/// 人物頁的「利害關係人分析」（fork，第二版，見 docs/stakeholder-design.md）：
/// 先給結論（資料卡：象限、態度、決策角色、把握），再給行動（下次見面），最後才是描述和出處。
/// 角色、組織、背景可以自己填，送給整理工具當成事實
struct StakeholderSection: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview
    /// 「記錄」分頁：人物頁原本的待辦、會議
    var record: AnyView? = nil
    @State private var editing = false

    var body: some View {
        let record = model.stakeholderPersonId == person.id ? model.stakeholder : nil
        let profile = record?.decoded
        let analyzing = model.isAnalyzingStakeholder(person.id)
        let isMe = person.isMe || model.stakeholderMe.contains(person.id)
        VStack(alignment: .leading, spacing: 22) {
            if isMe {
                NotesSection(title: String(localized: "利害關係人分析")) {
                    Text("這是你自己，不做分析。").foregroundStyle(.secondary)
                }
            } else {
                StakeholderCard(person: person, record: record, profile: profile, analyzing: analyzing, editing: $editing)
                if editing {
                    StakeholderContextEditor(person: person, record: record) { editing = false }
                }
                if let profile {
                    StakeholderDetails(profile: profile, record: self.record)
                } else if analyzing {
                    Text("正在分析他在會議裡說的話…").foregroundStyle(.secondary)
                } else {
                    Text("還沒有分析。按「分析」，拾音會把他在每場會議說的話交給整理工具，整理出他的個性、影響力、關心的議題，以及話背後可能的意思；之後每場有他的會議整理完都會自動更新。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: person.id) { model.loadStakeholder(person.id) }
    }
}

// MARK: - 資料卡

/// 一眼看完：角色、組織（你填的優先）、象限、影響力、關心程度、態度和變化、決策角色、把握、一句話總結
struct StakeholderCard: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview
    let record: StakeholderRecord?
    let profile: StakeholderProfile?
    let analyzing: Bool
    @Binding var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("利害關係人分析").contentTitleFont(18)
                Spacer()
                if analyzing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("分析中…").foregroundStyle(.secondary)
                    }
                }
                Button(editing ? String(localized: "完成") : String(localized: "補充背景"), systemImage: "person.text.rectangle") {
                    editing.toggle()
                }
                .help("填他的實際角色、組織和你知道的背景；分析會以這些為準")
                if !analyzing {
                    Button(profile == nil ? String(localized: "分析") : String(localized: "重新分析"), systemImage: "sparkles") {
                        model.analyzeStakeholder(person.id)
                    }
                    .disabled(model.askUnavailableReason != nil)
                    .help("用 \(AppSettings.provider.shortLabel) 從他出現過的每一場會議重新分析。每場會議整理完也會自動更新")
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)

            // 一欄由上往下排：身分 → 標記 → 影響力、關心程度 → 總結。不用 Grid、不跟小圖並排：
            // 長的理由在窄欄裡會換很多行，算高度時壓到下面的總結（2026-11-23 使用者截圖）
            identity
            if let profile {
                HStack(spacing: 8) {
                    QuadrantBadge(quadrant: profile.quadrant)
                    if !profile.attitude.isEmpty { AttitudeBadge(attitude: profile.attitude, trend: profile.attitudeTrend) }
                    if !profile.decisionRole.isEmpty { Tag(text: Self.decisionRoleLabel(profile.decisionRole)) }
                    Spacer(minLength: 0)
                    Button(String(localized: "看關係人地圖"), systemImage: "square.grid.2x2") {
                        model.openStakeholderMap(folder: profile.projects.count == 1 ? profile.projects[0].folder : model.folderFilter)
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .help("在影響力 × 關心程度的四象限上看他和其他人")
                }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    HStack(spacing: 6) { Text("影響力").foregroundStyle(.secondary); LevelBadge(level: profile.power) }
                    HStack(spacing: 6) { Text("關心程度").foregroundStyle(.secondary); LevelBadge(level: profile.interest) }
                }
                .font(.callout)
                if !profile.powerReason.isEmpty {
                    Text(profile.powerReason)
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let profile, !profile.summary.isEmpty {
                Text(profile.summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
            if let record, let profile { footnote(record, profile) }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 角色、組織：你填的有「你填的」標記，否則是推測的
    @ViewBuilder
    private var identity: some View {
        let role = record?.userRole.nonEmpty ?? profile?.role.nonEmpty
        let org = record?.userOrg.nonEmpty ?? profile?.organization.nonEmpty
        let mine = !(record?.userRole.isEmpty ?? true) || !(record?.userOrg.isEmpty ?? true)
        if role != nil || org != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text([role, org].compactMap { $0 }.joined(separator: " · ")).fontWeight(.medium).textSelection(.enabled)
                Text(mine ? String(localized: "你填的") : String(localized: "推測")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func footnote(_ record: StakeholderRecord, _ profile: StakeholderProfile) -> some View {
        let count = record.analyzedMeetings.count
        let date = String(record.updatedAt.prefix(10))
        let confidence = Self.confidenceLabel(profile.confidence)
        return VStack(alignment: .leading, spacing: 2) {
            Text(profile.confidence.isEmpty ? String(localized: "根據 \(count) 場會議・\(date) 更新")
                                            : String(localized: "把握：\(confidence)・根據 \(count) 場會議・\(date) 更新"))
                .font(.caption).foregroundStyle(.secondary)
            if profile.confidence == "low" && !record.hasUserContext {
                Text("他說的話還不多。按「補充背景」填他的角色和你知道的事，分析會準一些。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    static func confidenceLabel(_ value: String) -> String {
        switch value {
        case "high": return String(localized: "高")
        case "medium": return String(localized: "中")
        case "low": return String(localized: "低")
        default: return "—"
        }
    }

    static func decisionRoleLabel(_ value: String) -> String {
        switch value {
        case "decision maker": return String(localized: "決策者")
        case "influencer": return String(localized: "影響者")
        case "gatekeeper": return String(localized: "把關者")
        case "expert": return String(localized: "專家")
        case "user": return String(localized: "使用者")
        default: return String(localized: "其他角色")
        }
    }
}

// MARK: - 補充背景

struct StakeholderContextEditor: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview
    let record: StakeholderRecord?
    let done: () -> Void
    @State private var role = ""
    @State private var org = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("你知道的事會當成事實交給整理工具，分析會以這些為準。").font(.callout).foregroundStyle(.secondary)
            TextField("角色、職位（例如：客戶的 QE 主管，管預算）", text: $role)
            TextField("組織（例如：HKJC、IBM 內部、供應商）", text: $org)
            VStack(alignment: .leading, spacing: 4) {
                Text("你知道的背景").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                Text("例如：向誰報告、在意什麼指標、跟我們合作的歷史、私下聊過的事").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { done() }
                Button("儲存並重新分析") {
                    model.saveStakeholderContext(person.id, role: role, org: org, notes: notes)
                    done()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        .onAppear {
            role = record?.userRole ?? ""
            org = record?.userOrg ?? ""
            notes = record?.userNotes ?? ""
        }
    }
}

// MARK: - 內容

/// 分析的內容分成五個分頁（UX：一頁太長、沒有分組）。照顧問準備見面的順序：
/// 先「怎麼做」（下次見面、怎麼跟你合作）→「讀懂他」→「他在意什麼」→「他的人脈」→「記錄」（待辦、會議）
enum StakeholderTab: String, CaseIterable, Identifiable {
    case plan, read, interests, network, record
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plan: return String(localized: "怎麼做")
        case .read: return String(localized: "讀懂他")
        case .interests: return String(localized: "在意什麼")
        case .network: return String(localized: "人脈與承諾")
        case .record: return String(localized: "記錄")
        }
    }
}

struct StakeholderTabBar: View {
    @Binding var selection: StakeholderTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar
            ScrollView(.horizontal, showsIndicators: false) { bar }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("分頁"))
    }

    private var bar: some View {
        HStack(spacing: 4) {
            ForEach(StakeholderTab.allCases) { tab in
                let on = selection == tab
                Button { selection = tab } label: {
                    Text(tab.label)
                        .font(.callout.weight(on ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(on ? Color.celadon : .secondary)
                        .background(on ? Color.celadon.opacity(0.13) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.07), in: Capsule())
    }
}

struct StakeholderDetails: View {
    @Environment(AppModel.self) private var model
    let profile: StakeholderProfile
    /// 「記錄」分頁的內容（待辦、會議），由人物頁傳進來
    var record: AnyView? = nil

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            // 不用 segmented Picker：它的寬度跟著內容的文字大小長，字放大時會超出閱讀欄、蓋到側欄（使用者截圖）。
            // 自己畫的分頁列放得下就一行，放不下就可以左右捲，不會撐出欄外
            StakeholderTabBar(selection: $model.stakeholderTab)
            switch model.stakeholderTab {
            case .plan: plan
            case .read: read
            case .interests: interests
            case .network: network
            case .record: record ?? AnyView(EmptyView())
            }
            if model.stakeholderTab != .record {
                Text("這是整理工具從他說的話推測的，只供參考；你填的背景會優先。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 怎麼做

    @ViewBuilder
    private var plan: some View {
        VStack(alignment: .leading, spacing: 22) {
            nextMeeting
            workingWithMe
            if profile.nextMeeting.objective.isEmpty && profile.workingWithMe.isEmpty && profile.advice.isEmpty {
                empty
            }
        }
    }

    /// 下次見面：目標、要談的、要問的、要避免的
    @ViewBuilder
    private var nextMeeting: some View {
        let n = profile.nextMeeting
        if !n.objective.isEmpty || !n.talkingPoints.isEmpty || !n.questions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("下次見面", systemImage: "target").font(.headline).foregroundStyle(Color.celadon)
                if !n.objective.isEmpty { Text(n.objective).fontWeight(.medium).fixedSize(horizontal: false, vertical: true) }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { nextColumns(n) }
                    VStack(alignment: .leading, spacing: 12) { nextColumns(n) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.celadon.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func nextColumns(_ n: StakeholderProfile.NextMeeting) -> some View {
        if !n.talkingPoints.isEmpty { column(String(localized: "要談的"), n.talkingPoints) }
        if !n.questions.isEmpty { column(String(localized: "要問的"), n.questions) }
        if !n.avoid.isEmpty { column(String(localized: "避免"), n.avoid) }
    }

    /// 跟你合作：他怎麼看你、信任程度、他對你的期待、溝通方式、建立信用、要小心的地方、你們之間的互動
    @ViewBuilder
    private var workingWithMe: some View {
        let w = profile.workingWithMe
        if !w.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("怎麼跟他合作", systemImage: "person.2.wave.2").font(.headline)
                    if !w.trust.isEmpty {
                        HStack(spacing: 4) {
                            Text("他對你的信任").font(.callout).foregroundStyle(.secondary)
                            LevelBadge(level: w.trust)
                        }
                    }
                }
                if !w.relationship.isEmpty {
                    Text(w.relationship).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                twoColumns(
                    (String(localized: "他對你的期待"), w.expectations),
                    (String(localized: "怎麼溝通最有效"), w.communication))
                twoColumns(
                    (String(localized: "建立信用"), w.buildTrust),
                    (String(localized: "要小心的地方"), w.watchOuts))
                if !w.interactions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("你們之間的互動").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(w.interactions.enumerated()), id: \.offset) { _, r in ReadingRow(reading: r) }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        } else if !profile.advice.isEmpty {
            // 舊的分析沒有「跟你合作」：先顯示一般的互動建議
            block(String(localized: "互動建議")) { bullets(profile.advice) }
        }
        if !w.isEmpty && !profile.advice.isEmpty {
            block(String(localized: "互動建議")) { bullets(profile.advice) }
        }
    }

    // MARK: 讀懂他

    @ViewBuilder
    private var read: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !profile.readings.isEmpty {
                block(String(localized: "話中的意思")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(profile.readings.enumerated()), id: \.offset) { _, reading in ReadingRow(reading: reading) }
                    }
                }
            }
            if !profile.personality.isEmpty { block(String(localized: "個性與溝通風格")) { points(profile.personality) } }
            if !profile.motivations.isEmpty { block(String(localized: "在意的事、動機")) { points(profile.motivations) } }
            if !profile.openQuestions.isEmpty { block(String(localized: "還看不出來的地方")) { bullets(profile.openQuestions) } }
            if profile.readings.isEmpty && profile.personality.isEmpty && profile.motivations.isEmpty { empty }
        }
    }

    // MARK: 在意什麼

    @ViewBuilder
    private var interests: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !profile.needs.isEmpty { block(String(localized: "他需要我們提供的")) { bullets(profile.needs) } }
            if !profile.topics.isEmpty {
                block(String(localized: "關心的議題和立場")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(profile.topics.enumerated()), id: \.offset) { _, topic in
                            // 議題一行、立場在下一行：並排時長的議題名稱把立場擠成很窄的一欄（UX 檢查）
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    LevelBadge(level: topic.interest)
                                    Text(topic.topic).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                                }
                                if !topic.stance.isEmpty {
                                    Text(topic.stance).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                EvidenceList(evidence: topic.evidence)
                            }
                        }
                    }
                }
            }
            if !profile.projects.isEmpty {
                block(String(localized: "在各個案子")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(profile.projects, id: \.folder) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Button { model.openStakeholderMap(folder: p.folder) } label: {
                                        Label(FolderPath.display(p.folder), systemImage: "folder").foregroundStyle(Color.celadon)
                                    }
                                    .buttonStyle(.plain)
                                    .help("打開這個案子的關係人地圖")
                                    QuadrantBadge(quadrant: StakeholderProfile.Quadrant(power: p.power, interest: p.interest))
                                    if !p.attitude.isEmpty { AttitudeBadge(attitude: p.attitude, trend: "") }
                                }
                                if !p.note.isEmpty {
                                    Text(p.note).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            if profile.needs.isEmpty && profile.topics.isEmpty && profile.projects.isEmpty { empty }
        }
    }

    // MARK: 人脈與承諾

    @ViewBuilder
    private var network: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !profile.relationships.isEmpty {
                block(String(localized: "人際關係")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(profile.relationships.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(r.person).fontWeight(.medium)
                                    Text(r.relation).foregroundStyle(Color.celadon)
                                }
                                if !r.note.isEmpty {
                                    Text(r.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            if !profile.commitments.isEmpty { block(String(localized: "雙方的承諾")) { commitments } }
            if profile.relationships.isEmpty && profile.commitments.isEmpty { empty }
        }
    }

    private var empty: some View {
        Text("這一頁還沒有內容。按「重新分析」用最新的分析方式整理。").foregroundStyle(.secondary)
    }

    // MARK: 共用

    @ViewBuilder
    private func twoColumns(_ a: (String, [String]), _ b: (String, [String])) -> some View {
        if !a.1.isEmpty || !b.1.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    if !a.1.isEmpty { column(a.0, a.1) }
                    if !b.1.isEmpty { column(b.0, b.1) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if !a.1.isEmpty { column(a.0, a.1) }
                    if !b.1.isEmpty { column(b.0, b.1) }
                }
            }
        }
    }

    private func column(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            bullets(items)
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
    }

    private var commitments: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(profile.commitments.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let ours = c.who == "us"
                    Text(ours ? String(localized: "我們") : String(localized: "他"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .foregroundStyle(ours ? Color.celadon : Color.accent2)
                        .background((ours ? Color.celadon : Color.accent2).opacity(0.12), in: Capsule())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.text).fixedSize(horizontal: false, vertical: true)
                        if !c.time.isEmpty { CitationLink(meetingId: c.meetingId, time: c.time) }
                    }
                }
            }
        }
    }

    private func block(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).contentTitleFont(16)
            content()
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("• " + item).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func points(_ points: [StakeholderProfile.Point]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• " + point.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    EvidenceList(evidence: point.evidence)
                }
            }
        }
    }
}

/// 話中的意思：原話在上（引用的樣子），意思在下
struct ReadingRow: View {
    let reading: StakeholderProfile.Reading

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Color.celadon.opacity(0.5)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.quote).italic().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(reading.meaning).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                CitationLink(meetingId: reading.meetingId, time: reading.time)
            }
        }
    }
}

/// 出處預設收起來：「3 個出處 ▸」，點了展開
struct EvidenceList: View {
    let evidence: [StakeholderProfile.Evidence]
    @State private var open = false

    var body: some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { open.toggle() }
                } label: {
                    Label(String(localized: "\(evidence.count) 個出處"), systemImage: open ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(Array(evidence.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            CitationLink(meetingId: e.meetingId, time: e.time)
                            Text("「\(e.quote)」").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.leading, 12)
        }
    }
}

/// 出處：會議日期＋時間點，點了打開那場會議、從那裡播放；標題放在滑過的說明（定期會議常常同名）
struct CitationLink: View {
    @Environment(AppModel.self) private var model
    let meetingId: Int64
    let time: String

    var body: some View {
        let meeting = model.meetings.first { $0.id == meetingId }?.meeting
        Button {
            model.openFromPersonPage(meetingId, seconds: TimeFormat.seconds(time))
        } label: {
            Text("\(meeting?.meetingDate ?? String(localized: "會議")) \(time)")
                .font(.callout).monospacedDigit().foregroundStyle(Color.celadon).lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
        .help((meeting?.displayTitle ?? "") + "\n" + String(localized: "打開這場會議，從 \(time) 開始"))
    }
}

// MARK: - 標記

struct LevelBadge: View {
    let level: String

    var body: some View {
        let (label, color): (String, Color) = switch level {
        // 高中低是程度，不是好壞：用主色的深淺（Blue 70／Blue 60 淡／灰），不用紅橘，免得看起來像警告
        case "high": (String(localized: "高"), Color.celadon)
        case "medium": (String(localized: "中"), Color.accent2)
        default: (String(localized: "低"), .secondary)
        }
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct QuadrantBadge: View {
    let quadrant: StakeholderProfile.Quadrant

    var body: some View {
        Tag(text: Self.label(quadrant), color: Self.color(quadrant))
            .help(Self.help(quadrant))
    }

    static func label(_ q: StakeholderProfile.Quadrant) -> String {
        switch q {
        case .manageClosely: return String(localized: "密切管理")
        case .keepSatisfied: return String(localized: "讓他滿意")
        case .keepInformed: return String(localized: "隨時告知")
        case .monitor: return String(localized: "留意就好")
        }
    }

    static func help(_ q: StakeholderProfile.Quadrant) -> String {
        switch q {
        case .manageClosely: return String(localized: "影響力高、關心程度高：重要決定前先跟他談，讓他參與")
        case .keepSatisfied: return String(localized: "影響力高、關心程度低：顧到他在意的事，不用事事打擾")
        case .keepInformed: return String(localized: "影響力低、關心程度高：定期告知進度，他可能是很好的盟友")
        case .monitor: return String(localized: "影響力低、關心程度低：留意他的態度變化就好")
        }
    }

    static func color(_ q: StakeholderProfile.Quadrant) -> Color {
        switch q {
        // 四個象限：Blue 60（最重要）、Purple 60、Teal 60、灰（IBM 的 4 色組：藍、紫、青綠跟灰可以放在一起）
        case .manageClosely: return Color.celadon
        case .keepSatisfied: return Color.accent2
        case .keepInformed: return Color(nsColor: .dynamic(light: 0x007D79, dark: 0x08BDBA))
        case .monitor: return .secondary
        }
    }
}

struct AttitudeBadge: View {
    let attitude: String
    let trend: String

    var body: some View {
        let arrow = switch trend {
        case "improving": " ↗"
        case "declining": " ↘"
        case "stable": " →"
        default: ""
        }
        Tag(text: Self.label(attitude) + arrow, color: Self.color(attitude))
            .help(Self.trendHelp(trend))
    }

    static func label(_ value: String) -> String {
        switch value {
        case "champion": return String(localized: "大力支持")
        case "supporter": return String(localized: "支持")
        case "neutral": return String(localized: "中立")
        case "skeptic": return String(localized: "存疑")
        case "blocker": return String(localized: "反對")
        default: return value
        }
    }

    static func color(_ value: String) -> Color {
        switch value {
        // 態度是好壞：綠、灰、橘、紅（IBM 的 Green／Orange／Red 60、深色 40）。不只靠顏色：標記上都寫著字
        case "champion", "supporter": return Color.positive
        case "skeptic": return Color.caution
        case "blocker": return Color.negative
        default: return .secondary
        }
    }

    static func trendHelp(_ value: String) -> String {
        switch value {
        case "improving": return String(localized: "態度越來越正面")
        case "declining": return String(localized: "態度越來越負面，要注意")
        case "stable": return String(localized: "態度一直差不多")
        default: return String(localized: "只有一場會議，還看不出變化")
        }
    }
}

// MARK: - 影響力 × 關心程度

/// 四象限的小圖：橫軸關心程度、縱軸影響力；點的顏色是態度
struct PowerInterestGrid: View {
    struct Dot: Identifiable {
        var id: Int64
        var initials: String
        var quadrantX: String   // interest
        var quadrantY: String   // power
        var attitude: String
        var name: String = ""
    }
    let points: [Dot]
    var size: CGFloat = 120
    var labels = false
    var onTap: ((Int64) -> Void)? = nil

    var body: some View {
        let positions = layout()
        let d: CGFloat = labels ? 30 : 22
        ZStack(alignment: .topLeading) {
            VStack(spacing: 2) {
                HStack(spacing: 2) { cell(.keepSatisfied); cell(.manageClosely) }
                HStack(spacing: 2) { cell(.monitor); cell(.keepInformed) }
            }
            ForEach(points) { dot in
                let p = positions[dot.id] ?? .zero
                Button { onTap?(dot.id) } label: {
                    ZStack {
                        Circle().fill(AttitudeBadge.color(dot.attitude).opacity(dot.attitude.isEmpty ? 0.5 : 0.9))
                        Text(dot.initials).font(.system(size: labels ? 11 : 9, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: d, height: d)
                }
                .buttonStyle(.plain)
                .help(dot.name.isEmpty ? "" : "\(dot.name)・\(AttitudeBadge.label(dot.attitude))")
                .position(x: p.x, y: p.y)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            if labels { Text("關心程度 →").font(.caption).foregroundStyle(.secondary).offset(y: 18) }
        }
        .overlay(alignment: .leading) {
            if labels { Text("影響力 →").font(.caption).foregroundStyle(.secondary).rotationEffect(.degrees(-90)).fixedSize().offset(x: -34) }
        }
    }

    private func cell(_ q: StakeholderProfile.Quadrant) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(QuadrantBadge.color(q).opacity(0.08))
            if labels {
                Text(QuadrantBadge.label(q)).font(.caption.weight(.semibold)).foregroundStyle(QuadrantBadge.color(q)).padding(6)
            }
        }
    }

    /// 先照象限放進格子（跟資料卡的象限一致：影響力要高才在上面、關心程度中以上就在右邊），
    /// 同一格裡依高中低稍微偏移，再把同一格的人排成格子狀，不重疊
    private func layout() -> [Int64: CGPoint] {
        var groups: [StakeholderProfile.Quadrant: [Dot]] = [:]
        for dot in points { groups[StakeholderProfile.Quadrant(power: dot.quadrantY, interest: dot.quadrantX), default: []].append(dot) }
        var result: [Int64: CGPoint] = [:]
        let half = size / 2
        for (q, dots) in groups {
            let origin = CGPoint(x: (q == .manageClosely || q == .keepInformed) ? half : 0,
                                 y: (q == .manageClosely || q == .keepSatisfied) ? 0 : half)
            // 中的人放在靠中線那一側，高、低的人放在外側
            let sorted = dots.sorted { level($0.quadrantX) + level($0.quadrantY) > level($1.quadrantX) + level($1.quadrantY) }
            let columns = max(1, Int(ceil(sqrt(Double(sorted.count)))))
            let rows = Int(ceil(Double(sorted.count) / Double(columns)))
            let top: CGFloat = labels ? 30 : 14
            let cellW = (half - 16) / CGFloat(columns)
            let cellH = (half - top - 10) / CGFloat(max(rows, 1))
            for (i, dot) in sorted.enumerated() {
                let c = i % columns, r = i / columns
                result[dot.id] = CGPoint(x: origin.x + 8 + cellW * (CGFloat(c) + 0.5), y: origin.y + top + cellH * (CGFloat(r) + 0.5))
            }
        }
        return result
    }

    private func level(_ value: String) -> Int { value == "high" ? 2 : value == "medium" ? 1 : 0 }
}

// MARK: - 關係人地圖

/// 所有分析過的人放在同一張影響力 × 關心程度的圖上，可以只看一個資料夾；點一個人打開他的人物頁
struct StakeholderMapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let folders = model.folders.map(\.name).filter { name in model.meetings.contains { $0.meeting.isIn(folder: name) } }
        let folder = model.stakeholderMapFolder
        let group = model.stakeholderMapGroup
        let items = model.stakeholderMap(folder: folder.isEmpty ? nil : folder, group: group.isEmpty ? nil : group)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(folder.isEmpty ? String(localized: "關係人地圖") : String(localized: "關係人地圖：\(FolderPath.display(folder))")).font(.songti(20))
                Spacer()
                Picker("一個資料夾", selection: $model.stakeholderMapFolder) {
                    Text("所有會議").tag("")
                    ForEach(folders, id: \.self) { Text(FolderPath.display($0)).tag($0) }
                }
                .fixedSize()
                if !model.personGroups.isEmpty {
                    Picker("一個群組", selection: $model.stakeholderMapGroup) {
                        Text("所有人").tag("")
                        ForEach(model.personGroups, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                }
                Button {
                    model.confirmReanalyzeAll = true
                    model.openMainWindow?()   // 確認彈窗在主視窗
                } label: {
                    Label(model.analyzingStakeholders.isEmpty ? String(localized: "重新分析所有人") : String(localized: "分析中…"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!model.analyzingStakeholders.isEmpty || model.askUnavailableReason != nil)
                .help("每個人都從他出現過的所有會議重新分析")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            if items.isEmpty {
                Text(!group.isEmpty ? String(localized: "這個群組裡還沒有分析過的人（或不在這個資料夾的會議裡）。")
                     : folder.isEmpty ? String(localized: "還沒有分析過的人。到側欄「人物」打開一個人，按「分析」。")
                                    : String(localized: "這個資料夾的會議裡還沒有分析過的人。"))
                    .foregroundStyle(.secondary).padding(24)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 28) {
                    PowerInterestGrid(points: items.map { item in
                        let r = Self.rating(item.profile, folder)
                        return .init(id: item.person.id, initials: StakeholderCard.initials(item.person.name), quadrantX: r.interest,
                                     quadrantY: r.power, attitude: r.attitude, name: item.person.name)
                    }, size: 380, labels: true) { model.openPerson($0) }
                    .padding(.leading, 40)
                    .padding(.bottom, 26)
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(StakeholderProfile.Quadrant.allCases, id: \.self) { q in
                                let group = items.filter { let r = Self.rating($0.profile, folder); return StakeholderProfile.Quadrant(power: r.power, interest: r.interest) == q }
                                if !group.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        QuadrantBadge(quadrant: q)
                                        ForEach(group, id: \.person.id) { item in
                                            Button { model.openPerson(item.person.id) } label: {
                                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                    Text(item.person.name).fontWeight(.medium)
                                                    let r = Self.rating(item.profile, folder)
                                                    if !r.attitude.isEmpty {
                                                        AttitudeBadge(attitude: r.attitude, trend: item.profile.attitudeTrend)
                                                    }
                                                    Text(r.note.nonEmpty ?? item.record.userRole.nonEmpty ?? item.profile.role)
                                                        .foregroundStyle(.secondary).lineLimit(1)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
                Text(folder.isEmpty
                     ? String(localized: "顏色是態度：綠色支持、灰色中立、橘色存疑、紅色反對。只放分析過的人；點一個人打開他的人物頁。")
                     : String(localized: "放的是他在這個案子的影響力、關心程度和態度；同一個人在別的案子可能不一樣。點一個人打開他的人物頁。"))
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            model.reloadPeopleOverview()
            model.reloadPersonGroups()
            // 第一次打開：有資料夾時先看第一個（地圖是看一個案子的人，跨案子的影響力意義不大）
            if !model.stakeholderMapChosen, model.stakeholderMapFolder.isEmpty, let first = folders.first {
                model.stakeholderMapFolder = model.folderFilter ?? first
            }
            model.stakeholderMapChosen = true
        }
    }
}

extension StakeholderMapView {
    /// 這個案子的評估；沒有（舊的分析、沒有對到資料夾）就用整體的
    static func rating(_ p: StakeholderProfile, _ folder: String) -> (power: String, interest: String, attitude: String, note: String) {
        if let x = p.project(folder) { return (x.power, x.interest, x.attitude, x.note) }
        // 上層資料夾（客戶）：用他在這個客戶底下各案子裡最高的影響力、關心程度（同一個客戶的人通常跨案子）
        if !folder.isEmpty, !FolderPath.isSub(folder) {
            let inside = p.projects.filter { FolderPath.contains(folder, $0.folder) }
            if !inside.isEmpty {
                func rank(_ v: String) -> Int { v == "high" ? 2 : v == "medium" ? 1 : 0 }
                let top = inside.max { rank($0.power) * 3 + rank($0.interest) < rank($1.power) * 3 + rank($1.interest) }!
                return (top.power, top.interest, top.attitude, inside.map { "\(FolderPath.project($0.folder) ?? $0.folder)：\($0.note)" }.joined(separator: "；"))
            }
        }
        return (p.power, p.interest, p.attitude, "")
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 名字：點了打開人物頁，滑過看小卡（UX 檢查 A1–A4）

/// 會議裡出現的名字（待辦負責人、與會者、每個人的重點、逐字稿的說話者）：對到認識的人時可以點，
/// 滑過出現小卡（角色、象限、態度、對你的信任、最近一次見面、還沒完成的待辦），不用離開會議就看得到這個人
struct PersonLink<Label: View>: View {
    @Environment(AppModel.self) private var model
    let personId: Int64?
    @ViewBuilder var label: () -> Label
    @State private var hovering = false
    @State private var showCard = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        if let personId {
            Button { model.openPerson(personId) } label: { label() }
                .buttonStyle(.plain)
                .onHover { inside in
                    hovering = inside
                    task?.cancel()
                    // 停一下才出小卡，滑過去不會一直跳出來
                    task = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(inside ? 550 : 250))
                        guard !Task.isCancelled else { return }
                        showCard = hovering
                    }
                }
                .popover(isPresented: $showCard, arrowEdge: .bottom) {
                    PersonHoverCard(personId: personId) { showCard = false }
                }
                .help(String(localized: "打開人物頁"))
        } else {
            label()
        }
    }
}

struct PersonHoverCard: View {
    @Environment(AppModel.self) private var model
    let personId: Int64
    let close: () -> Void

    var body: some View {
        let person = model.peopleOverview.first { $0.id == personId }
        let profile = model.stakeholderSummary(personId)
        let isMe = (person?.isMe ?? false) || model.stakeholderMe.contains(personId)
        let done = (try? model.db.doneActionItems()) ?? []
        let open = (try? model.db.personActionItems(person?.name ?? ""))?
            .filter { !done.contains(ActionDone.key($0.meeting.id ?? 0, $0.item.task)) }.count ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PersonAvatar(name: person?.name ?? "", color: Color.person(person?.name ?? ""), size: 32, isMe: isMe, scales: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person?.name ?? "").font(.headline)
                    if let role = profile?.role.nonEmpty { Text(role).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            if let profile, !isMe {
                HStack(spacing: 6) {
                    QuadrantBadge(quadrant: profile.quadrant)
                    if !profile.attitude.isEmpty { AttitudeBadge(attitude: profile.attitude, trend: profile.attitudeTrend) }
                }
                if !profile.workingWithMe.trust.isEmpty {
                    HStack(spacing: 4) {
                        Text("他對你的信任").font(.callout).foregroundStyle(.secondary)
                        LevelBadge(level: profile.workingWithMe.trust)
                    }
                }
                if !profile.nextMeeting.objective.isEmpty {
                    Text(profile.nextMeeting.objective).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            } else if !isMe {
                Text("還沒有分析").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let date = person?.lastMeetingDate { Text("最近：\(date)").font(.caption).foregroundStyle(.secondary) }
                if open > 0 { Text("\(open) 項待辦還沒完成").font(.caption).foregroundStyle(.secondary) }
            }
            Button("打開人物頁", systemImage: "person.crop.circle") {
                close()
                model.openPerson(personId)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.celadon)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: - 這場會議的與會者（UX 檢查 C2）

/// 會議紀錄上方一行：這場會議認得的與會者（你自己除外），每人一個小標記：象限的顏色、態度。
/// 用這場會議所在案子（資料夾）的評估；點了打開人物頁、滑過看小卡。沒有分析過的人不列
struct AttendeeLens: View {
    @Environment(AppModel.self) private var model
    let detail: MeetingDetail

    var body: some View {
        let me = model.stakeholderMe
        let folder = detail.meeting.folder
        let people: [(Int64, String, StakeholderProfile)] = detail.speakerPersons.sorted { $0.key < $1.key }.compactMap { idx, personId in
            guard !me.contains(personId), idx != detail.selfIdx, let profile = model.stakeholderSummary(personId) else { return nil }
            return (personId, detail.speakers[idx] ?? "", profile)
        }
        if !people.isEmpty {
            ViewThatFits(in: .horizontal) {
                row(people, folder)
                ScrollView(.horizontal, showsIndicators: false) { row(people, folder) }
            }
        }
    }

    private func row(_ people: [(Int64, String, StakeholderProfile)], _ folder: String) -> some View {
        HStack(spacing: 14) {
            Text("與會者").font(.callout).foregroundStyle(.secondary)
            ForEach(people, id: \.0) { personId, name, profile in
                let r = StakeholderMapView.rating(profile, folder)
                let q = StakeholderProfile.Quadrant(power: r.power, interest: r.interest)
                // 一個顏色只代表一件事（同關係人地圖）：點和字都是態度；象限寫成文字
                PersonLink(personId: personId) {
                    HStack(spacing: 5) {
                        Circle().fill(AttitudeBadge.color(r.attitude)).frame(width: 8, height: 8)
                        Text(name).font(.callout.weight(.medium)).foregroundStyle(Color.primary)
                        Text(QuadrantBadge.label(q)).font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                .help(r.attitude.isEmpty ? QuadrantBadge.label(q) : "\(AttitudeBadge.label(r.attitude))・\(QuadrantBadge.label(q))")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.06), in: Capsule())
    }
}

/// 能打開人物頁的名字：一般文字色，滑過加底線（跟其他連結一樣的提示，但不跟青瓷綠的時間點搶）
struct LinkName: View {
    let name: String
    @State private var hovering = false

    var body: some View {
        Text(name)
            .foregroundStyle(Color.primary)
            .underline(hovering, color: Color.celadon)
            .onHover { hovering = $0 }
    }
}
