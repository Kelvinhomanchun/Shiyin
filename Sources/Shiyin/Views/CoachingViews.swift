import SwiftUI

/// 我的表現（fork，見 docs/coaching-requirements.md、docs/mockups/my-coaching.html）：
/// 自己的人物頁，用所有會議整理出整體的強弱項、趨勢和要練的一點
enum CoachingTab: String, CaseIterable, Identifiable {
    case overview, findings, trends, trust, record
    var id: String { rawValue }
    var label: String {
        switch self {
        case .overview: return String(localized: "概覽")
        case .findings: return String(localized: "強項與弱項")
        case .trends: return String(localized: "趨勢")
        case .trust: return String(localized: "信任")
        case .record: return String(localized: "記錄")
        }
    }
}

extension Coaching.Kind {
    var color: Color {
        switch self {
        case .client: return Color.celadon
        case .internalTeam: return Color(nsColor: .dynamic(light: 0x007D79, dark: 0x08BDBA))
        case .interview: return Color.accent2
        case .oneOnOne: return Color.signal
        }
    }
}

extension Coaching.Trend {
    init(text: String) {
        switch text {
        case "improving": self = .improving
        case "worse": self = .worse
        case "same": self = .same
        default: self = .notEnough
        }
    }
    var color: Color {
        switch self {
        case .improving: return Color.positive
        case .worse: return Color.signal
        case .same: return .secondary
        case .notEnough: return .secondary
        }
    }
}

/// 趨勢標記：↑ 進步、→ 持平、↓ 退步
struct TrendChip: View {
    let trend: Coaching.Trend
    var text: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.arrow).font(.caption2.weight(.bold))
            Text(text ?? trend.label).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(trend.color)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(trend.color.opacity(0.12), in: Capsule())
        .fixedSize()
    }

    /// 模型寫的趨勢（improving / same / worse / new）
    static func model(_ text: String) -> some View {
        Group {
            if text == "new" {
                Text("新").font(.caption.weight(.semibold)).foregroundStyle(Color.accent2)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.accent2.opacity(0.12), in: Capsule()).fixedSize()
            } else {
                TrendChip(trend: Coaching.Trend(text: text))
            }
        }
    }
}

struct CoachingTabBar: View {
    @Binding var selection: CoachingTab

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
            ForEach(CoachingTab.allCases) { tab in
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

/// 一張卡的外框
private struct CoachCard<Content: View>: View {
    var tint: Color = .secondary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint == .secondary ? Color.secondary.opacity(0.04) : tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint == .secondary ? Color.secondary.opacity(0.15) : tint.opacity(0.15)))
    }
}

private struct SectionTitle: View {
    let title: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.top, 6)
    }
}

/// 自己的人物頁：我的表現
struct CoachingSection: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview
    var record: AnyView? = nil

    var body: some View {
        @Bindable var model = model
        let stats = model.coachingStats
        VStack(alignment: .leading, spacing: 18) {
            header(stats)
            if stats.count < 2 {
                Text("你的聲音出現在至少兩場會議（每場至少說話 60 秒）後，這裡會顯示你在會議裡的表現和趨勢。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let record { record }
            } else {
                CoachingTabBar(selection: $model.coachingTab)
                switch model.coachingTab {
                case .overview: CoachingOverview(person: person, stats: stats)
                case .findings: CoachingFindings(person: person)
                case .trends: CoachingTrends(stats: stats)
                case .trust: CoachingTrust()
                case .record: if let record { record }
                }
            }
        }
        .task(id: person.id) { model.loadCoaching(person.id) }
    }

    private func header(_ stats: [Coaching.MeetingStats]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("我的表現").font(.title2.weight(.semibold))
                HStack(spacing: 10) {
                    if let first = stats.first?.date, let last = stats.last?.date {
                        Text("根據 \(stats.count) 場會議，\(first) 至 \(last)")
                    }
                    if model.coachingSkipped > 0 {
                        Text("\(model.coachingSkipped) 場沒算進去")
                            .help("這些會議的講者可能混在一起：在會議頁確認講者後就會算進去")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                status
            }
            Spacer()
            Button("重新整理", systemImage: "arrow.clockwise") { model.refreshCoaching(person.id) }
                .disabled(model.coachingRunning || stats.count < 2)
                .help("從你所有的會議重新寫一次建議")
        }
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 6) {
            if model.coachingRunning {
                ProgressView().controlSize(.mini)
                Text(model.coaching == nil ? "正在整理…" : "正在更新…先顯示上一次的建議")
            } else if let record = model.coaching {
                Circle().fill(Color.positive).frame(width: 6, height: 6)
                Text("建議更新於 \(record.updatedLocal)，之後每場會議整理完會自動更新")
            } else {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                Text("數字是現算的；按「重新整理」讓整理工具寫建議")
            }
        }
        .font(.callout).foregroundStyle(.secondary)
    }
}

// MARK: - 概覽

private struct CoachingOverview: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview
    let stats: [Coaching.MeetingStats]

    var body: some View {
        let sums = Coaching.summaries(stats)
        let total = Coaching.overall(sums)
        let profile = model.coaching?.decoded
        let (recent, earlier) = Coaching.windows(stats)
        VStack(alignment: .leading, spacing: 18) {
            TwoUpLayout(minColumn: 300, spacing: 14) {
                scoreCard(total, recent: recent.count)
                summaryCard(profile)
            }
            SectionTitle(title: String(localized: "你的能力值"), note: String(localized: "每項 0–5，和你自己之前的會議比"))
            StatSheet(sums: sums)
            legend(recent: recent, earlier: earlier)
            if let plan = profile?.plan, !plan.focus.isEmpty {
                SectionTitle(title: String(localized: "要練的一點"))
                FocusCard(plan: plan, stats: stats)
            }
            SectionTitle(title: String(localized: "不同會議"), note: String(localized: "每種會議的中位數"))
            byKind(profile)
            SectionTitle(title: String(localized: "成就"), note: String(localized: "從你的會議裡拿到的"))
            Achievements(stats: stats)
            if let changes = profile?.changes, !changes.isEmpty {
                SectionTitle(title: String(localized: "上次之後的變化"))
                CoachCard {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
                            Text(line).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func scoreCard(_ total: (now: Double?, before: Double?), recent: Int) -> some View {
        CoachCard {
            HStack(alignment: .center, spacing: 16) {
                ScoreRing(value: total.now ?? 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("會議分數").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    let trend = Coaching.trend(now: total.now, before: total.before)
                    if let now = total.now, let before = total.before {
                        let d = now - before
                        TrendChip(trend: trend, text: String(format: "%@ %.1f · %.1f → %.1f", trend.label, abs(d), before, now))
                    } else {
                        TrendChip(trend: .notEnough)
                    }
                    Text("六項能力的平均：最近 \(recent) 場會議，和之前的比。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryCard(_ profile: CoachingProfile?) -> some View {
        CoachCard(tint: Color.celadon) {
            Label("你給人的感覺", systemImage: "sparkles").font(.callout.weight(.semibold)).foregroundStyle(Color.celadon)
            if let summary = profile?.summary, !summary.isEmpty {
                ForEach(Array(summary.enumerated()), id: \.offset) { _, line in
                    Text(line).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            } else {
                Text(model.coachingRunning ? "正在整理你在會議裡說的話…" : "還沒有建議。按「重新整理」，拾音會把你在每場會議說的話交給整理工具，寫出你的強項、弱項和要練的一點。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legend(recent: [Coaching.MeetingStats], earlier: [Coaching.MeetingStats]) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.celadon.opacity(0.25)).overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.celadon, lineWidth: 2)).frame(width: 14, height: 10)
                Text("最近 \(recent.count) 場")
            }
            if !earlier.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 10)
                    Text("之前 \(earlier.count) 場")
                }
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).stroke(Color.positive, lineWidth: 1.5).frame(width: 14, height: 10)
                Text("目標（4）")
            }
        }
        .font(.callout).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func byKind(_ profile: CoachingProfile?) -> some View {
        let kinds = Coaching.Kind.allCases.filter { k in stats.contains { $0.kind == k } }
        CoachGrid(minColumn: 280, spacing: 12) {
            ForEach(kinds) { kind in
                let list = stats.filter { $0.kind == kind }
                CoachCard {
                    HStack {
                        Tag(text: kind.label, color: kind.color)
                        Spacer()
                        Text("\(list.count) 場").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach([Coaching.Skill.listening, .concision, .curiosity, .clarity]) { skill in
                        let v = Coaching.median(list.map(skill.value)) ?? 0
                        let off = skill.target(kind).map { !$0.contains(v) } ?? false
                        HStack(alignment: .firstTextBaseline) {
                            Text(skill.metricName).foregroundStyle(.secondary)
                            Spacer()
                            Text(skill.format(v)).fontWeight(.semibold).monospacedDigit().foregroundStyle(off ? Color.signal : .primary)
                            Text(skill.targetText(kind)).font(.caption).foregroundStyle(.secondary).frame(minWidth: 64, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                    if let note = profile?.byKind.first(where: { $0.kind == kind.rawValue })?.note, !note.isEmpty {
                        Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                    }
                }
            }
        }
    }
}

/// 分數圈
private struct ScoreRing: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 10)
            Circle().trim(from: 0, to: min(1, max(0, value / 5)))
                .stroke(Color.celadon, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(String(format: "%.1f", value)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                Text("滿分 5").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("會議分數 \(String(format: "%.1f", value))，滿分 5"))
    }
}

// MARK: - 能力值（雷達＋六張卡）

private struct StatSheet: View {
    let sums: [Coaching.SkillSummary]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wide
            narrow
        }
    }

    private func sum(_ skill: Coaching.Skill) -> Coaching.SkillSummary? { sums.first { $0.skill == skill } }

    /// 闊：中間雷達，六張卡圍著（上一、左右各二、下一）
    private var wide: some View {
        VStack(spacing: 12) {
            card(.listening).frame(width: 230)
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 12) { card(.curiosity); card(.room) }.frame(width: 230)
                Radar(sums: sums).frame(width: 320, height: 300)
                VStack(spacing: 12) { card(.concision); card(.dialogue) }.frame(width: 230)
            }
            card(.clarity).frame(width: 230)
        }
        .frame(minWidth: 800, maxWidth: .infinity)
    }

    /// 窄：雷達在上，卡兩欄
    private var narrow: some View {
        VStack(spacing: 14) {
            Radar(sums: sums).frame(width: 340, height: 300).frame(maxWidth: .infinity)
            CoachGrid(minColumn: 220, spacing: 12) {
                ForEach(Coaching.Skill.allCases) { card($0) }
            }
        }
    }

    @ViewBuilder
    private func card(_ skill: Coaching.Skill) -> some View {
        if let s = sum(skill) { SkillCard(summary: s) }
    }
}

private struct SkillCard: View {
    let summary: Coaching.SkillSummary
    var body: some View {
        let skill = summary.skill
        CoachCard {
            HStack(spacing: 6) {
                Image(systemName: skill.symbol).foregroundStyle(Color.celadon).frame(width: 16)
                Text(skill.label).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                TrendChip(trend: summary.trend)
            }
            Text(skill.what).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.now.map { String(format: "%.1f", $0) } ?? "–").font(.title2.weight(.bold)).monospacedDigit()
                if let before = summary.before {
                    Text("之前 \(String(format: "%.1f", before))").font(.caption).foregroundStyle(.secondary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.celadon).frame(width: g.size.width * min(1, (summary.now ?? 0) / 5))
                }
            }
            .frame(height: 5)
            if let median = summary.median {
                Text("\(skill.metricName)：\(skill.format(median))（中位數）")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 六角雷達：藍色是最近，灰色虛線是之前，綠線是目標 4
private struct Radar: View {
    let sums: [Coaching.SkillSummary]
    private let order: [Coaching.Skill] = [.listening, .concision, .dialogue, .clarity, .room, .curiosity]

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            // 標籤畫在圈外：左右要留出最長的標籤（「Room given」）的寬度，上下留一行
            let r = min(size.width / 2 - 62, size.height / 2 - 26)
            func pt(_ i: Int, _ v: Double) -> CGPoint {
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / 6
                return CGPoint(x: c.x + cos(a) * r * v / 5, y: c.y + sin(a) * r * v / 5)
            }
            func poly(_ values: [Double]) -> Path {
                var p = Path()
                for (i, v) in values.enumerated() { i == 0 ? p.move(to: pt(i, v)) : p.addLine(to: pt(i, v)) }
                p.closeSubpath()
                return p
            }
            let grid = GraphicsContext.Shading.color(.secondary.opacity(0.25))
            for k in 1...5 {
                context.stroke(poly(Array(repeating: Double(k), count: 6)), with: grid,
                               style: StrokeStyle(lineWidth: 1, dash: k < 5 ? [3, 4] : []))
            }
            for i in 0..<6 {
                var line = Path(); line.move(to: c); line.addLine(to: pt(i, 5))
                context.stroke(line, with: grid, lineWidth: 1)
            }
            context.stroke(poly(Array(repeating: 4, count: 6)), with: .color(Color.positive.opacity(0.8)), lineWidth: 1.5)
            let before = order.map { s in sums.first { $0.skill == s }?.before }
            if before.allSatisfy({ $0 != nil }) {
                context.stroke(poly(before.map { $0 ?? 0 }), with: .color(.secondary), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            let now = order.map { s in sums.first { $0.skill == s }?.now ?? 0 }
            let shape = poly(now)
            context.fill(shape, with: .color(Color.celadon.opacity(0.18)))
            context.stroke(shape, with: .color(Color.celadon), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            for (i, v) in now.enumerated() {
                let p = pt(i, v)
                let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(Color(nsColor: .textBackgroundColor)))
                context.stroke(dot, with: .color(Color.celadon), lineWidth: 2)
                // 左邊的標籤靠右對齊、右邊的靠左，貼著圈外，不會被切掉
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / 6
                let edge = pt(i, 5)
                let lp = CGPoint(x: edge.x + cos(a) * 10, y: edge.y + sin(a) * 14)
                let anchor: UnitPoint = abs(cos(a)) < 0.1 ? (sin(a) < 0 ? .bottom : .top) : (cos(a) > 0 ? .leading : .trailing)
                context.draw(Text(order[i].label).font(.callout.weight(.semibold)), at: lp, anchor: anchor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(order.compactMap { s in sums.first { $0.skill == s }?.now.map { "\(s.label) \(String(format: "%.1f", $0))" } }.joined(separator: "，")))
    }
}

// MARK: - 要練的一點

private struct FocusCard: View {
    @Environment(AppModel.self) private var model
    let plan: CoachingProfile.Plan
    let stats: [Coaching.MeetingStats]

    var body: some View {
        let skill = Coaching.Skill(rawValue: plan.skill)
        let kind = Coaching.Kind(rawValue: plan.kind)
        CoachCard(tint: Color.accent2) {
            TwoUpLayout(minColumn: 260, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("建議 · 從你的弱項選出").font(.caption.weight(.semibold)).foregroundStyle(Color.accent2)
                    Text(plan.focus).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if !plan.why.isEmpty {
                        Text(plan.why).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(plan.techniques.enumerated()), id: \.offset) { i, t in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Color.accent2, in: Circle())
                            Text(t).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                    if let good = plan.goodExample, !good.evidence.isEmpty || !good.detail.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.positive)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(good.detail.nonEmpty ?? good.title).fixedSize(horizontal: false, vertical: true)
                                EvidenceList(evidence: good.evidence, indent: 0)
                            }
                        }
                        .padding(10)
                        .background(Color.positive.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let skill { progress(skill, kind) }
            }
        }
    }

    /// 進度：之後的會議達標的有幾場（5 場裡 4 場就算習慣了）
    private func progress(_ skill: Coaching.Skill, _ kind: Coaching.Kind?) -> some View {
        let list = stats.filter { kind == nil || $0.kind == kind }
        let since = model.coaching?.updatedAt.prefix(10) ?? ""
        let after = list.filter { $0.date > since }.prefix(5)
        let hits = after.map { s in skill.target(s.kind).map { $0.contains(skill.value(s)) } ?? false }
        let median = Coaching.median(list.suffix(5).map(skill.value))
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(skill.metricName)\(kind.map { " · \($0.label)" } ?? "")").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(median.map(skill.format) ?? "–").font(.title.weight(.bold)).monospacedDigit()
                Text("最近的中位數 · 目標 \(skill.targetText(kind ?? list.last?.kind ?? .client))").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    let color: Color = i < hits.count ? (hits[i] ? Color.positive : Color.signal) : Color.secondary.opacity(0.2)
                    Circle().fill(color).frame(width: 16, height: 16)
                        .overlay { if i == hits.count { Circle().stroke(Color.accent2, lineWidth: 2) } }
                }
            }
            Text("之後的 5 場\(kind.map { $0.label } ?? String(localized: "會議"))裡有 4 場達標，就算養成習慣了。已達標 \(hits.filter { $0 }.count) 場。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 成就

private struct Achievements: View {
    @Environment(AppModel.self) private var model
    let stats: [Coaching.MeetingStats]

    private struct Badge: Identifiable {
        var id: String { name }
        var symbol: String
        var name: String
        var rule: String
        var proof: Coaching.MeetingStats?
        var at: Double = 0
        var progress: (Int, Int)
    }

    private func streak(_ list: [Coaching.MeetingStats], _ ok: (Coaching.MeetingStats) -> Bool) -> Int {
        var best = 0, run = 0
        for s in list { run = ok(s) ? run + 1 : 0; best = max(best, run) }
        return best
    }

    private var badges: [Badge] {
        let clients = stats.filter { $0.kind == .client }
        let interviews = stats.filter { $0.kind == .interview }
        let roomMaker = clients.filter { $0.room >= 300 }.max { $0.room < $1.room }
        let crisp = clients.last { $0.longest <= 90 }
        let short = streak(interviews) { $0.longest <= 120 }
        let steady = streak(stats) { s in Coaching.Skill.listening.target(s.kind)?.contains(s.talk) ?? false }
        return [
            Badge(symbol: "ear.fill", name: String(localized: "讓人暢所欲言"), rule: String(localized: "客戶連續說了超過 5 分鐘，你沒有打斷。"),
                  proof: roomMaker, at: roomMaker?.roomAt ?? 0, progress: (roomMaker == nil ? 0 : 1, 1)),
            Badge(symbol: "scope", name: String(localized: "精簡匯報"), rule: String(localized: "一場客戶會議裡，你每段都不超過 1:30。"),
                  proof: crisp, progress: (crisp == nil ? 0 : 1, 1)),
            Badge(symbol: "timer", name: String(localized: "短而有力"), rule: String(localized: "連續 3 場面試，每段都不超過 2:00。"),
                  proof: short >= 3 ? interviews.last : nil, progress: (min(short, 3), 3)),
            Badge(symbol: "scalemass.fill", name: String(localized: "穩定"), rule: String(localized: "連續 5 場會議，說話佔比都在目標內。"),
                  proof: steady >= 5 ? stats.last : nil, progress: (min(steady, 5), 5)),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(badges) { badge in
                let earned = badge.progress.0 >= badge.progress.1
                VStack(spacing: 6) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(earned ? Color.celadon : .secondary)
                        .frame(width: 48, height: 48)
                        .background(earned ? Color.celadon.opacity(0.14) : Color.secondary.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(earned ? Color.celadon : Color.secondary.opacity(0.3), lineWidth: earned ? 2 : 1))
                    Text(badge.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(badge.rule).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if earned, let proof = badge.proof {
                        Button {
                            model.openFromPersonPage(proof.id, seconds: badge.at)
                        } label: {
                            Text(badge.at > 0 ? "\(proof.date) \(TimeFormat.string(badge.at))" : proof.date).font(.caption).monospacedDigit().foregroundStyle(Color.celadon).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help(proof.title)
                    } else {
                        ProgressView(value: Double(badge.progress.0), total: Double(badge.progress.1)).frame(width: 70)
                        Text("\(badge.progress.0) / \(badge.progress.1)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(earned ? 0.2 : 0.12), style: StrokeStyle(lineWidth: 1, dash: earned ? [] : [4, 3])))
                .opacity(earned ? 1 : 0.8)
            }
        }
    }
}

// MARK: - 強項與弱項

private struct CoachingFindings: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview

    var body: some View {
        if let profile = model.coaching?.decoded, !profile.isEmpty {
            TwoUpLayout(minColumn: 300, spacing: 16) {
                column(String(localized: "強項"), String(localized: "這次沒有找到有出處的強項。"), Color.positive, profile.strengths)
                column(String(localized: "弱項"), String(localized: "這次沒有找到有出處的弱項。"), Color.signal, profile.weaknesses)
            }
        } else {
            Text(model.coachingRunning ? "正在整理…" : "還沒有建議。按上面的「重新整理」。").foregroundStyle(.secondary)
        }
    }

    private func column(_ title: String, _ none: String, _ tint: Color, _ list: [CoachingProfile.Finding]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "circle.fill").labelStyle(.titleAndIcon)
                .font(.callout.weight(.semibold)).foregroundStyle(tint)
                .imageScale(.small)
            if list.isEmpty {
                Text(none).foregroundStyle(.secondary)
            }
            ForEach(Array(list.enumerated()), id: \.offset) { _, finding in
                FindingCard(finding: finding) { model.rejectCoachingFinding(person.id, title: finding.title) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct FindingCard: View {
    let finding: CoachingProfile.Finding
    let reject: () -> Void
    @State private var useful = false

    var body: some View {
        CoachCard {
            Text(finding.title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                TrendChip.model(finding.trend)
                ForEach(finding.kinds.compactMap(Coaching.Kind.init(rawValue:))) { Tag(text: $0.label, color: $0.color) }
            }
            Text(finding.detail).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            ForEach(Array(finding.evidence.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.quote).italic().fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        CitationLink(meetingId: e.meetingId, time: e.time)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(useful ? "謝謝" : "有用", systemImage: useful ? "hand.thumbsup.fill" : "hand.thumbsup") { useful = true }
                    .disabled(useful)
                Button("不對", systemImage: "xmark", action: reject)
                    .help("拿掉這一點，之後重新整理也不會再寫")
            }
            .buttonStyle(.borderless).font(.callout).padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 趨勢

private struct CoachingTrends: View {
    @Environment(AppModel.self) private var model
    let stats: [Coaching.MeetingStats]

    var body: some View {
        @Bindable var model = model
        let kind = model.coachingKind
        let list = kind.map { k in stats.filter { $0.kind == k } } ?? stats
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("會議", selection: $model.coachingKind) {
                    Text("全部").tag(Coaching.Kind?.none)
                    ForEach(Coaching.Kind.allCases.filter { k in stats.contains { $0.kind == k } }) { k in
                        Text(k.label).tag(Coaching.Kind?.some(k))
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                ForEach(Coaching.Kind.allCases.filter { k in stats.contains { $0.kind == k } }) { k in
                    HStack(spacing: 4) { Circle().fill(k.color).frame(width: 8, height: 8); Text(k.label) }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(kind == nil ? "最近 8 場和之前 8 場比。選一種會議，會顯示目標範圍。點一點打開那場會議。" : "這種會議最近 5 場和之前 5 場比，綠色是目標範圍。點一點打開那場會議。")
                .font(.callout).foregroundStyle(.secondary)
            if list.isEmpty {
                Text("沒有這種會議。").foregroundStyle(.secondary)
            } else {
                CoachGrid(minColumn: 300, spacing: 12) {
                    ForEach(Coaching.Skill.allCases) { skill in
                        TrendChart(skill: skill, list: list, all: stats, kind: kind)
                    }
                }
            }
        }
    }
}

private struct TrendChart: View {
    @Environment(AppModel.self) private var model
    let skill: Coaching.Skill
    let list: [Coaching.MeetingStats]
    let all: [Coaching.MeetingStats]
    let kind: Coaching.Kind?
    @State private var hover: Int64?

    private var trend: Coaching.Trend {
        if let kind { return Coaching.trend(skill, kind: kind, stats: all) }
        return Coaching.summaries(all).first { $0.skill == skill }?.trend ?? .notEnough
    }

    var body: some View {
        let values = list.map(skill.value)
        let maxV = max(1, (values.max() ?? 1) * 1.1)
        CoachCard {
            HStack(spacing: 6) {
                Image(systemName: skill.symbol).foregroundStyle(Color.celadon)
                Text(skill.label).font(.callout.weight(.semibold))
                Text(skill.metricName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                TrendChip(trend: trend)
            }
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let left: CGFloat = 38
                let x = { (i: Int) -> CGFloat in list.count == 1 ? left + (w - left) / 2 : left + CGFloat(i) * (w - left - 8) / CGFloat(list.count - 1) }
                let y = { (v: Double) -> CGFloat in 6 + (h - 22) * (1 - CGFloat(v / maxV)) }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { k in
                        let v = maxV * Double(k) / 3
                        Path { p in p.move(to: CGPoint(x: left, y: y(v))); p.addLine(to: CGPoint(x: w, y: y(v))) }
                            .stroke(Color.secondary.opacity(0.12))
                        Text(skill.format(v)).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: left - 4, alignment: .trailing).position(x: (left - 4) / 2, y: y(v))
                    }
                    if let kind, let t = skill.target(kind) {
                        let top = y(min(t.upperBound, maxV)), bottom = y(max(0, t.lowerBound))
                        Rectangle().fill(Color.positive.opacity(0.12))
                            .frame(width: w - left, height: max(0, bottom - top)).offset(x: left, y: top)
                    }
                    Path { p in
                        for (i, v) in values.enumerated() { i == 0 ? p.move(to: CGPoint(x: x(i), y: y(v))) : p.addLine(to: CGPoint(x: x(i), y: y(v))) }
                    }
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1.5)
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                        Circle().fill(s.kind.color)
                            .overlay(Circle().stroke(Color(nsColor: .textBackgroundColor), lineWidth: 1.5))
                            .frame(width: hover == s.id ? 13 : 10, height: hover == s.id ? 13 : 10)
                            .position(x: x(i), y: y(values[i]))
                            .onHover { hover = $0 ? s.id : (hover == s.id ? nil : hover) }
                            .onTapGesture { model.openFromPersonPage(s.id, seconds: skill == .concision ? s.longestAt : skill == .room ? s.roomAt : nil) }
                            .help("\(s.title)\n\(s.date) · \(s.kind.label)\n\(skill.metricName)：\(skill.format(values[i]))")
                    }
                    if let first = list.first?.date, let last = list.last?.date {
                        Text(String(first.suffix(5))).font(.system(size: 9)).foregroundStyle(.secondary).position(x: left + 12, y: h - 6)
                        Text(String(last.suffix(5))).font(.system(size: 9)).foregroundStyle(.secondary).position(x: w - 16, y: h - 6)
                    }
                }
            }
            .frame(height: 130)
            Text("中位數 \(skill.format(Coaching.median(values) ?? 0))").font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 信任

private struct CoachingTrust: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CoachCard {
                HStack(spacing: 10) {
                    Text("信任").font(.title3.weight(.bold))
                    Text("=")
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text("可信度").foregroundStyle(Color.celadon)
                            Text("+")
                            Text("可靠度").foregroundStyle(Coaching.Kind.internalTeam.color)
                            Text("+")
                            Text("親近感").foregroundStyle(Color.accent2)
                        }
                        Rectangle().fill(.primary).frame(height: 1)
                        Text("自我中心").foregroundStyle(Color.signal)
                    }
                    .fixedSize()
                }
                .font(.callout.weight(.semibold))
                Text("出自 Maister、Green、Galford《The Trusted Advisor》。自我中心（只顧自己）影響最大，越低越好。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let trust = model.coaching?.decoded?.trust {
                CoachGrid(minColumn: 280, spacing: 12) {
                    part(String(localized: "可信度"), Color.celadon, trust.credibility, lower: false)
                    part(String(localized: "可靠度"), Coaching.Kind.internalTeam.color, trust.reliability, lower: false)
                    part(String(localized: "親近感"), Color.accent2, trust.intimacy, lower: false)
                    part(String(localized: "自我中心"), Color.signal, trust.selfOrientation, lower: true)
                }
            } else {
                Text(model.coachingRunning ? "正在整理…" : "還沒有建議。按上面的「重新整理」。").foregroundStyle(.secondary)
            }
        }
    }

    private func part(_ title: String, _ tint: Color, _ part: CoachingProfile.TrustPart, lower: Bool) -> some View {
        CoachCard {
            HStack {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(tint)
                Spacer()
                TrendChip.model(part.trend)
            }
            if part.text.isEmpty {
                Text("還沒有足夠的出處。").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", part.score)).font(.title.weight(.bold)).foregroundStyle(tint).monospacedDigit()
                    Text(lower ? "滿分 5 · 越低越好" : "滿分 5").font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(tint).frame(width: g.size.width * min(1, max(0, part.score / 5)))
                    }
                }
                .frame(height: 6)
                Text(part.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                ForEach(Array(part.evidence.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.quote).italic().fixedSize(horizontal: false, vertical: true)
                            CitationLink(meetingId: e.meetingId, time: e.time)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 兩欄的格子（放不下就一欄），每一列等高；TwoUpLayout 只放得下兩個
struct CoachGrid: Layout {
    var minColumn: CGFloat
    var spacing: CGFloat

    private func count(_ width: CGFloat) -> Int { width >= minColumn * 2 + spacing ? 2 : 1 }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> (column: CGFloat, heights: [CGFloat], n: Int) {
        let n = count(width)
        let column = (width - spacing * CGFloat(n - 1)) / CGFloat(n)
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: n) {
            let row = subviews[start..<min(start + n, subviews.count)]
            heights.append(row.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0)
        }
        return (column, heights, n)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minColumn * 2 + spacing
        let r = rows(width, subviews)
        return CGSize(width: width, height: r.heights.reduce(0, +) + spacing * CGFloat(max(r.heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(bounds.width, subviews)
        var y = bounds.minY
        for (rowIndex, h) in r.heights.enumerated() {
            for c in 0..<r.n {
                let i = rowIndex * r.n + c
                guard i < subviews.count else { break }
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(c) * (r.column + spacing), y: y),
                                  proposal: ProposedViewSize(width: r.column, height: h))
            }
            y += h + spacing
        }
    }
}
