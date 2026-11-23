import SwiftUI

/// 人物頁的「利害關係人分析」（fork，第二版，見 docs/stakeholder-design.md）：
/// 先給結論（資料卡：象限、態度、決策角色、把握），再給行動（下次見面），最後才是描述和出處。
/// 角色、組織、背景可以自己填，送給整理工具當成事實
struct StakeholderSection: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview
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
                    StakeholderDetails(profile: profile)
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
            // 每個案子各自的份量（關係人地圖照這個放）
            if let profile, !profile.projects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("在各個案子").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(profile.projects, id: \.folder) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Button { model.openStakeholderMap(folder: p.folder) } label: {
                                    Label(p.folder, systemImage: "folder").foregroundStyle(Color.celadon)
                                }
                                .buttonStyle(.plain)
                                .help("打開這個案子的關係人地圖")
                                QuadrantBadge(quadrant: StakeholderProfile.Quadrant(power: p.power, interest: p.interest))
                                if !p.attitude.isEmpty { AttitudeBadge(attitude: p.attitude, trend: "") }
                            }
                            if !p.note.isEmpty {
                                Text(p.note).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.callout)
                    }
                }
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

/// 結論、行動在前，描述和出處在後
struct StakeholderDetails: View {
    let profile: StakeholderProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            nextMeeting
            if !profile.needs.isEmpty || !profile.commitments.isEmpty {
                HStack(alignment: .top, spacing: 28) {
                    if !profile.needs.isEmpty {
                        block(String(localized: "他需要我們提供的")) { bullets(profile.needs) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !profile.commitments.isEmpty {
                        block(String(localized: "雙方的承諾")) { commitments }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !profile.readings.isEmpty {
                block(String(localized: "話中的意思")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(profile.readings.enumerated()), id: \.offset) { _, reading in
                            ReadingRow(reading: reading)
                        }
                    }
                }
            }
            if !profile.topics.isEmpty {
                block(String(localized: "關心的議題和立場")) {
                    VStack(alignment: .leading, spacing: 8) {
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
            HStack(alignment: .top, spacing: 28) {
                if !profile.personality.isEmpty {
                    block(String(localized: "個性與溝通風格")) { points(profile.personality) }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !profile.motivations.isEmpty {
                    block(String(localized: "在意的事、動機")) { points(profile.motivations) }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !profile.relationships.isEmpty {
                block(String(localized: "人際關係")) {
                    VStack(alignment: .leading, spacing: 4) {
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
            if !profile.openQuestions.isEmpty {
                block(String(localized: "還看不出來的地方")) { bullets(profile.openQuestions) }
            }
            Text("這是整理工具從他說的話推測的，只供參考；你填的背景會優先。").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 下次見面：目標、要談的、要問的、要避免的（舊版的分析只有 advice，就顯示 advice）
    @ViewBuilder
    private var nextMeeting: some View {
        let n = profile.nextMeeting
        if !n.objective.isEmpty || !n.talkingPoints.isEmpty || !n.questions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("下次見面", systemImage: "target").font(.headline).foregroundStyle(Color.celadon)
                if !n.objective.isEmpty { Text(n.objective).fontWeight(.medium).fixedSize(horizontal: false, vertical: true) }
                HStack(alignment: .top, spacing: 24) {
                    if !n.talkingPoints.isEmpty { column(String(localized: "要談的"), n.talkingPoints) }
                    if !n.questions.isEmpty { column(String(localized: "要問的"), n.questions) }
                    if !n.avoid.isEmpty { column(String(localized: "避免"), n.avoid) }
                }
                if !profile.advice.isEmpty {
                    Divider()
                    column(String(localized: "互動建議"), profile.advice)
                }
            }
            .padding(14)
            .background(Color.celadon.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        } else if !profile.advice.isEmpty {
            block(String(localized: "互動建議")) { bullets(profile.advice) }
        }
    }

    private func column(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            bullets(items)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commitments: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(profile.commitments.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let ours = c.who == "us"
                    Text(ours ? String(localized: "我們") : String(localized: "他"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .foregroundStyle(ours ? Color.celadon : .orange)
                        .background((ours ? Color.celadon : .orange).opacity(0.12), in: Capsule())
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
        case "high": (String(localized: "高"), .red)
        case "medium": (String(localized: "中"), .orange)
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
        case .manageClosely: return .red
        case .keepSatisfied: return .orange
        case .keepInformed: return Color.celadon
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
        case "champion", "supporter": return .green
        case "skeptic": return .orange
        case "blocker": return .red
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
        let folders = Array(Set(model.meetings.map(\.meeting.folder).filter { !$0.isEmpty })).sorted()
        let folder = model.stakeholderMapFolder
        let items = model.stakeholderMap(folder: folder.isEmpty ? nil : folder)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(folder.isEmpty ? String(localized: "關係人地圖") : String(localized: "關係人地圖：\(folder)")).font(.songti(20))
                Spacer()
                Picker("一個資料夾", selection: $model.stakeholderMapFolder) {
                    Text("所有會議").tag("")
                    ForEach(folders, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            if items.isEmpty {
                Text(folder.isEmpty ? String(localized: "還沒有分析過的人。到側欄「人物」打開一個人，按「分析」。")
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
        return (p.power, p.interest, p.attitude, "")
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
