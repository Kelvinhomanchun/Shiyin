import Foundation
import GRDB

/// 我的表現（fork，2026-11-25）：從使用者自己在所有會議的表現，算出六項會議技巧的分數和趨勢（不用整理工具），
/// 再請整理工具寫整體的教練建議（強項、弱項、信任、改善計畫）。放在自己的人物頁（別人的人物頁是利害關係人分析）。
/// 需求：docs/coaching-requirements.md；樣子：docs/mockups/my-coaching.html
enum Coaching {
    // MARK: 會議種類

    enum Kind: String, CaseIterable, Codable, Identifiable {
        case client, internalTeam = "internal", interview, oneOnOne = "one-on-one"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .client: return String(localized: "客戶會議")
            case .internalTeam: return String(localized: "內部會議")
            case .interview: return String(localized: "面試")
            case .oneOnOne: return String(localized: "一對一")
            }
        }
    }

    // MARK: 一場會議的數字

    struct MeetingStats: Codable, Hashable, Identifiable {
        var id: Int64            // 會議 id
        var date: String
        var title: String
        var kind: Kind
        var minutes: Double
        /// 我說話的時間 ÷ 所有人說話的時間（0–100）
        var talk: Double
        /// 我最長的一段（秒），和它開始的時間
        var longest: Double
        var longestAt: Double
        /// 每 5 分鐘換幾次人說話
        var switches: Double
        /// 我每 30 分鐘問幾個問題
        var questions: Double
        /// 我每分鐘的口頭禪、重複字
        var fillers: Double
        /// 別人最長的一段（我沒插話），和它開始的時間
        var room: Double
        var roomAt: Double
        /// 我每說 100 個字/詞，有幾次重複開頭（我我我）
        var restarts: Double
    }

    // MARK: 六項技巧

    enum Skill: String, CaseIterable, Codable, Identifiable {
        case listening, concision, dialogue, clarity, room, curiosity
        var id: String { rawValue }
        var label: String {
            switch self {
            case .listening: return String(localized: "傾聽")
            case .concision: return String(localized: "簡潔")
            case .dialogue: return String(localized: "對話")
            case .clarity: return String(localized: "清晰")
            case .room: return String(localized: "給人空間")
            case .curiosity: return String(localized: "好奇心")
            }
        }
        var what: String {
            switch self {
            case .listening: return String(localized: "把多少說話的時間留給別人")
            case .concision: return String(localized: "講重點，不長篇大論")
            case .dialogue: return String(localized: "來回對話，不是獨白")
            case .clarity: return String(localized: "少用口頭禪、少重複開頭")
            case .room: return String(localized: "讓別人把話說完")
            case .curiosity: return String(localized: "問得夠多，但不像審問")
            }
        }
        var metricName: String {
            switch self {
            case .listening: return String(localized: "說話佔比")
            case .concision: return String(localized: "最長的一段")
            case .dialogue: return String(localized: "每 5 分鐘換人次數")
            case .clarity: return String(localized: "每分鐘口頭禪")
            case .room: return String(localized: "別人最長的一段")
            case .curiosity: return String(localized: "每 30 分鐘的問題")
            }
        }
        var symbol: String {
            switch self {
            case .listening: return "ear"
            case .concision: return "scissors"
            case .dialogue: return "arrow.left.arrow.right"
            case .clarity: return "waveform"
            case .room: return "hand.raised"
            case .curiosity: return "questionmark.bubble"
            }
        }

        func value(_ s: MeetingStats) -> Double {
            switch self {
            case .listening: return s.talk
            case .concision: return s.longest
            case .dialogue: return s.switches
            case .clarity: return s.fillers
            case .room: return s.room
            case .curiosity: return s.questions
            }
        }

        /// 目標範圍（需求 §4，可以之後再讓使用者改）；nil：這種會議不評
        func target(_ kind: Kind) -> ClosedRange<Double>? {
            switch (self, kind) {
            case (.listening, .client): return 30...50
            case (.listening, .internalTeam): return 35...60
            case (.listening, .interview): return 30...45
            case (.listening, .oneOnOne): return 40...60
            case (.concision, .client), (.concision, .interview): return 0...120
            case (.concision, .internalTeam): return 0...180
            case (.concision, .oneOnOne): return 0...150
            case (.dialogue, _): return 15...999
            case (.clarity, _): return 0...3
            case (.room, .internalTeam): return 60...99_999
            case (.room, _): return 120...99_999
            case (.curiosity, .internalTeam): return 4...20
            case (.curiosity, .oneOnOne): return 6...15
            case (.curiosity, _): return 8...20
            }
        }

        /// 離目標多遠扣滿 4 分
        var scale: Double {
            switch self {
            case .listening: return 30
            case .concision: return 300
            case .dialogue: return 15
            case .clarity: return 6
            case .room: return 120
            case .curiosity: return 15
            }
        }

        /// 1–5 分：在目標範圍內 5 分，離得越遠越低
        func score(_ s: MeetingStats) -> Double? {
            guard let t = target(s.kind) else { return nil }
            let v = value(s)
            let d = v < t.lowerBound ? t.lowerBound - v : v > t.upperBound ? v - t.upperBound : 0
            return 5 - 4 * min(1, d / scale)
        }

        func format(_ v: Double) -> String {
            switch self {
            case .listening: return "\(Int(v.rounded()))%"
            case .concision, .room: return TimeFormat.string(v)
            case .dialogue, .clarity: return String(format: "%.1f", v)
            case .curiosity: return "\(Int(v.rounded()))"
            }
        }

        func targetText(_ kind: Kind) -> String {
            guard let t = target(kind) else { return String(localized: "不評") }
            if t.lowerBound == 0 { return String(localized: "\(format(t.upperBound)) 以下") }
            if t.upperBound >= 999 { return String(localized: "\(format(t.lowerBound)) 以上") }
            return "\(format(t.lowerBound))–\(format(t.upperBound))"
        }
    }

    // MARK: 趨勢

    enum Trend: String, Codable {
        case improving, same, worse, notEnough
        var label: String {
            switch self {
            case .improving: return String(localized: "進步")
            case .same: return String(localized: "持平")
            case .worse: return String(localized: "退步")
            case .notEnough: return String(localized: "會議還不夠")
            }
        }
        var arrow: String {
            switch self {
            case .improving: return "arrow.up"
            case .same: return "arrow.right"
            case .worse: return "arrow.down"
            case .notEnough: return "ellipsis"
            }
        }
    }

    /// 最近 n 場和之前 n 場比（n 最多 8；兩邊各至少 3 場才算）
    struct SkillSummary: Hashable {
        var skill: Skill
        var now: Double?
        var before: Double?
        var trend: Trend
        var median: Double?
        var recentCount: Int
    }

    static func median(_ a: [Double]) -> Double? {
        guard !a.isEmpty else { return nil }
        let s = a.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func mean(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }

    /// 分數的變化超過 0.3 才算進步或退步（一場特別的會議不會翻轉趨勢）
    static func trend(now: Double?, before: Double?) -> Trend {
        guard let now, let before else { return .notEnough }
        let d = now - before
        return abs(d) < 0.3 ? .same : d > 0 ? .improving : .worse
    }

    /// 依日期排好（舊到新）的會議
    static func windows(_ stats: [MeetingStats], max n: Int = 8) -> (recent: [MeetingStats], earlier: [MeetingStats]) {
        let k = min(n, stats.count / 2)
        guard k >= 3 else { return (stats, []) }
        return (Array(stats.suffix(k)), Array(stats.dropLast(k).suffix(k)))
    }

    static func summaries(_ stats: [MeetingStats]) -> [SkillSummary] {
        let (recent, earlier) = windows(stats)
        return Skill.allCases.map { skill in
            let now = mean(recent.compactMap(skill.score))
            let before = earlier.isEmpty ? nil : mean(earlier.compactMap(skill.score))
            return SkillSummary(skill: skill, now: now, before: before, trend: trend(now: now, before: before),
                                median: median(recent.map(skill.value)), recentCount: recent.count)
        }
    }

    /// 一種會議的趨勢：這種會議最近 5 場和之前 5 場
    static func trend(_ skill: Skill, kind: Kind, stats: [MeetingStats]) -> Trend {
        let list = stats.filter { $0.kind == kind }
        let (recent, earlier) = windows(list, max: 5)
        guard !earlier.isEmpty else { return .notEnough }
        return trend(now: mean(recent.compactMap(skill.score)), before: mean(earlier.compactMap(skill.score)))
    }

    /// 總分：六項的平均
    static func overall(_ list: [SkillSummary]) -> (now: Double?, before: Double?) {
        (mean(list.compactMap(\.now)), mean(list.compactMap(\.before)))
    }

    // MARK: 計算

    /// 一句是不是問句：問號，或粵語、國語的句尾疑問詞
    static func questionCount(_ text: String) -> Int {
        let marks = text.filter { $0 == "?" || $0 == "？" }.count
        if marks > 0 { return marks }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["嗎", "吗", "呢", "咩", "未", "冇"].contains(where: { trimmed.hasSuffix($0) }) ? 1 : 0  // l10n-skip
    }

    static let fillerPattern = try! NSRegularExpression(pattern: #"誒|嗯|呃|(?i)\b(um+|uh+|erm)\b"#)  // l10n-skip
    static let restartPattern = try! NSRegularExpression(pattern: #"(\S{1,2})\1{2,}"#)

    static func count(_ regex: NSRegularExpression, _ text: String) -> Int {
        regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    struct Line { var start: Double; var end: Double; var text: String; var mine: Bool }

    /// 一場會議的數字；我說不到 60 秒、或沒有別人說話時不算
    static func stats(meeting: Meeting, kind: Kind, lines: [Line]) -> MeetingStats? {
        guard let id = meeting.id, !lines.isEmpty else { return nil }
        let mine = lines.filter(\.mine)
        let me = mine.reduce(0) { $0 + max(0, $1.end - $1.start) }
        let total = lines.reduce(0) { $0 + max(0, $1.end - $1.start) }
        guard me >= 60, lines.contains(where: { !$0.mine }), total > 0 else { return nil }
        // 連續同一邊說的話併成一段
        var turns: [(mine: Bool, start: Double, end: Double)] = []
        for l in lines {
            if let last = turns.last, last.mine == l.mine { turns[turns.count - 1].end = max(last.end, l.end) }
            else { turns.append((l.mine, l.start, l.end)) }
        }
        let myTurn = turns.filter(\.mine).max { ($0.end - $0.start) < ($1.end - $1.start) }
        let otherTurn = turns.filter { !$0.mine }.max { ($0.end - $0.start) < ($1.end - $1.start) }
        let minutes = max(1, (lines.last!.end - lines.first!.start) / 60)
        let text = mine.map(\.text).joined(separator: " ")
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count + text.unicodeScalars.filter { $0.value >= 0x3400 && $0.value <= 0x9FFF }.count)
        return MeetingStats(
            id: id, date: meeting.meetingDate, title: meeting.displayTitle, kind: kind, minutes: minutes,
            talk: 100 * me / total,
            longest: myTurn.map { $0.end - $0.start } ?? 0, longestAt: myTurn?.start ?? 0,
            switches: Double(max(0, turns.count - 1)) / minutes * 5,
            questions: Double(mine.reduce(0) { $0 + questionCount($1.text) }) / minutes * 30,
            fillers: Double(count(fillerPattern, text)) / (me / 60),
            room: otherTurn.map { $0.end - $0.start } ?? 0, roomAt: otherTurn?.start ?? 0,
            restarts: Double(count(restartPattern, text)) / Double(words) * 100)
    }
}

// MARK: - 教練建議（整理工具寫的）

struct CoachingProfile: Codable, Hashable {
    typealias Evidence = StakeholderProfile.Evidence

    struct Finding: Codable, Hashable {
        var title: String
        var detail: String
        /// improving / same / worse / new
        var trend: String
        /// client / internal / interview / one-on-one
        var kinds: [String]
        var evidence: [Evidence]

        init(title: String, detail: String, trend: String, kinds: [String], evidence: [Evidence]) {
            self.title = title; self.detail = detail; self.trend = trend; self.kinds = kinds; self.evidence = evidence
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
            trend = (try? c.decode(String.self, forKey: .trend)) ?? "same"
            kinds = (try? c.decode([String].self, forKey: .kinds)) ?? []
            evidence = (try? c.decode([Evidence].self, forKey: .evidence)) ?? []
        }
    }

    struct TrustPart: Codable, Hashable {
        /// 1–5（自我中心：越低越好）
        var score: Double
        var trend: String
        var text: String
        var evidence: [Evidence]

        init(score: Double, trend: String, text: String, evidence: [Evidence]) {
            self.score = score; self.trend = trend; self.text = text; self.evidence = evidence
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            score = (try? c.decode(Double.self, forKey: .score)) ?? 0
            trend = (try? c.decode(String.self, forKey: .trend)) ?? "same"
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            evidence = (try? c.decode([Evidence].self, forKey: .evidence)) ?? []
        }
        static let empty = TrustPart(score: 0, trend: "same", text: "", evidence: [])
    }

    struct Trust: Codable, Hashable {
        var credibility: TrustPart = .empty
        var reliability: TrustPart = .empty
        var intimacy: TrustPart = .empty
        var selfOrientation: TrustPart = .empty

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            credibility = (try? c.decode(TrustPart.self, forKey: .credibility)) ?? .empty
            reliability = (try? c.decode(TrustPart.self, forKey: .reliability)) ?? .empty
            intimacy = (try? c.decode(TrustPart.self, forKey: .intimacy)) ?? .empty
            selfOrientation = (try? c.decode(TrustPart.self, forKey: .selfOrientation)) ?? .empty
        }
    }

    struct Plan: Codable, Hashable {
        var focus: String = ""
        /// 這個重點看哪一項技巧（listening…curiosity），進度用它的數字
        var skill: String = ""
        /// 適用哪種會議
        var kind: String = ""
        var why: String = ""
        var techniques: [String] = []
        var goodExample: Finding?

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            focus = (try? c.decode(String.self, forKey: .focus)) ?? ""
            skill = (try? c.decode(String.self, forKey: .skill)) ?? ""
            kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
            why = (try? c.decode(String.self, forKey: .why)) ?? ""
            techniques = (try? c.decode([String].self, forKey: .techniques)) ?? []
            goodExample = try? c.decode(Finding.self, forKey: .goodExample)
        }
    }

    struct KindNote: Codable, Hashable {
        var kind: String
        var note: String
    }

    var summary: [String] = []
    var strengths: [Finding] = []
    var weaknesses: [Finding] = []
    var trust = Trust()
    var byKind: [KindNote] = []
    var plan = Plan()
    var changes: [String] = []

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        summary = v(.summary, [])
        if summary.isEmpty, let one = try? c.decode(String.self, forKey: .summary), !one.isEmpty { summary = [one] }
        strengths = v(.strengths, []); weaknesses = v(.weaknesses, []); trust = v(.trust, Trust())
        byKind = v(.byKind, []); plan = v(.plan, Plan()); changes = v(.changes, [])
    }

    var isEmpty: Bool { summary.isEmpty && strengths.isEmpty && weaknesses.isEmpty }

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static let jsonSchema: String = {
        let evidence = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["meetingId","time","quote"],"properties":{"meetingId":{"type":"integer"},"time":{"type":"string"},"quote":{"type":"string"}}}}"#
        let trend = #"{"type":"string","enum":["improving","same","worse","new"]}"#
        let kinds = #"{"type":"array","items":{"type":"string","enum":["client","internal","interview","one-on-one"]}}"#
        let finding = #"{"type":"object","additionalProperties":false,"required":["title","detail","trend","kinds","evidence"],"properties":{"title":{"type":"string"},"detail":{"type":"string"},"trend":"# + trend + #","kinds":"# + kinds + #","evidence":"# + evidence + "}}"
        let findings = #"{"type":"array","items":"# + finding + "}"
        let part = #"{"type":"object","additionalProperties":false,"required":["score","trend","text","evidence"],"properties":{"score":{"type":"number"},"trend":"# + trend + #","text":{"type":"string"},"evidence":"# + evidence + "}}"
        let trust = #"{"type":"object","additionalProperties":false,"required":["credibility","reliability","intimacy","selfOrientation"],"properties":{"credibility":"# + part + #","reliability":"# + part + #","intimacy":"# + part + #","selfOrientation":"# + part + "}}"
        let strings = #"{"type":"array","items":{"type":"string"}}"#
        let skill = #"{"type":"string","enum":["listening","concision","dialogue","clarity","room","curiosity","other"]}"#
        let plan = #"{"type":"object","additionalProperties":false,"required":["focus","skill","kind","why","techniques","goodExample"],"properties":{"focus":{"type":"string"},"skill":"# + skill + #","kind":{"type":"string","enum":["client","internal","interview","one-on-one","all"]},"why":{"type":"string"},"techniques":"# + strings + #","goodExample":"# + finding + "}}"
        let byKind = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["kind","note"],"properties":{"kind":{"type":"string","enum":["client","internal","interview","one-on-one"]},"note":{"type":"string"}}}}"#
        return #"{"type":"object","additionalProperties":false,"required":["summary","strengths","weaknesses","trust","byKind","plan","changes"],"properties":{"summary":"# + strings + #","strengths":"# + findings + #","weaknesses":"# + findings + #","trust":"# + trust + #","byKind":"# + byKind + #","plan":"# + plan + #","changes":"# + strings + "}}"
    }()

    static let format = LLMClient.OutputFormat(schema: jsonSchema, toolName: "save_coaching",
                                               toolDescription: "Save the overall meeting coaching for the user")

    /// 丟掉不能用的出處：不是提供的會議、時間格式不對；沒有出處的強項、弱項不留（需求 FR-D3）
    func validated(meetingIds: Set<Int64>) -> CoachingProfile {
        func clean(_ list: [Evidence]) -> [Evidence] {
            list.compactMap { e in
                var e = e
                e.time = TimeFormat.clean(e.time)
                e.quote = e.quote.trimmingCharacters(in: .whitespacesAndNewlines)
                guard meetingIds.contains(e.meetingId), TimeFormat.seconds(e.time) != nil else { return nil }
                return e
            }
        }
        func findings(_ list: [Finding], max n: Int) -> [Finding] {
            Array(list.compactMap { f -> Finding? in
                var f = f
                f.evidence = clean(f.evidence)
                return f.title.isEmpty || f.evidence.isEmpty ? nil : f
            }.prefix(n))
        }
        var p = self
        p.summary = summary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        p.strengths = findings(strengths, max: 3)
        p.weaknesses = findings(weaknesses, max: 3)
        for path in [\Trust.credibility, \Trust.reliability, \Trust.intimacy, \Trust.selfOrientation] {
            p.trust[keyPath: path].evidence = clean(trust[keyPath: path].evidence)
            p.trust[keyPath: path].score = min(5, max(0, trust[keyPath: path].score))
        }
        if var example = plan.goodExample {
            example.evidence = clean(example.evidence)
            p.plan.goodExample = example.evidence.isEmpty ? nil : example
        }
        p.changes = changes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return p
    }
}

/// 存在資料庫的教練建議：一個人（自己）一份
struct CoachingRecord: SnakeCaseRecord, Hashable {
    static let databaseTableName = "coaching"
    var personId: Int64
    var profile: String
    var meetingIds: String
    /// 使用者說「不對」的建議（標題），之後不再寫
    var rejected: String = "[]"
    /// 使用者說「有用」的建議（標題），之後重新整理盡量保留
    var useful: String = "[]"
    var language: String = ""
    var provider: String = ""
    var model: String = ""
    var updatedAt: String = Clock.now()

    var decoded: CoachingProfile? { profile.isEmpty ? nil : try? JSONDecoder().decode(CoachingProfile.self, from: Data(profile.utf8)) }
    var analyzedMeetings: Set<Int64> { Set((try? JSONDecoder().decode([Int64].self, from: Data(meetingIds.utf8))) ?? []) }
    var rejectedTitles: [String] { (try? JSONDecoder().decode([String].self, from: Data(rejected.utf8))) ?? [] }
    var usefulTitles: [String] { (try? JSONDecoder().decode([String].self, from: Data(useful.utf8))) ?? [] }

    var updatedLocal: String {
        guard let date = ISO8601DateFormatter().date(from: updatedAt) else { return String(updatedAt.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}

extension AppDatabase {
    /// 我的每場會議的數字（舊到新）。跳過說話者可能分錯的會議（不算進趨勢），回傳跳過幾場
    func coachingStats(_ personId: Int64) throws -> (stats: [Coaching.MeetingStats], skipped: Int) {
        let myOrg = try stakeholderProfile(personId)?.userOrg.nonEmpty
            ?? (try peopleOverview().first { $0.id == personId }?.group)
        return try pool.read { db in
            let meetings = try Meeting.fetchAll(db, sql: """
                SELECT DISTINCT m.* FROM meetings m JOIN speakers s ON s.meeting_id = m.id
                WHERE s.person_id = ? AND m.deleted_at IS NULL ORDER BY m.meeting_date, m.id
                """, arguments: [personId])
            var out: [Coaching.MeetingStats] = []
            var skipped = 0
            for meeting in meetings {
                guard let id = meeting.id else { continue }
                let speakers = try SpeakerName.fetchAll(db, sql: "SELECT * FROM speakers WHERE meeting_id = ?", arguments: [id])
                let mine = Set(speakers.filter { $0.personId == personId }.map(\.idx))
                let segments = try Segment.fetchAll(db, sql: "SELECT * FROM segments WHERE meeting_id = ? AND kind = 'final' ORDER BY seq", arguments: [id])
                let lines = segments.compactMap { s in s.speaker.map { Coaching.Line(start: s.start, end: s.end, text: s.text, mine: mine.contains($0)) } }
                // 種類：面試、一對一看範本；有別的組織的人是客戶會議（自己的組織：自己填的，或人物群組）
                let otherIds = Set(speakers.filter { !mine.contains($0.idx) }.compactMap(\.personId))
                var orgs = Set<String>()
                for pid in otherIds {
                    let group = try String.fetchOne(db, sql: "SELECT group_name FROM people WHERE id = ?", arguments: [pid])
                    let org = try String.fetchOne(db, sql: "SELECT user_org FROM stakeholder_profiles WHERE person_id = ?", arguments: [pid])
                    if let o = org?.nonEmpty ?? group?.nonEmpty { orgs.insert(o.lowercased()) }
                }
                let kind: Coaching.Kind
                if meeting.templateId == "interview" { kind = .interview }
                else if meeting.templateId == "one-on-one" { kind = .oneOnOne }
                else if let myOrg, orgs.contains(where: { $0 != myOrg.lowercased() }) { kind = .client }
                else { kind = .internalTeam }
                if meeting.mayHaveMergedSpeakers && !meeting.speakerHintDismissed { skipped += 1; continue }
                if let s = Coaching.stats(meeting: meeting, kind: kind, lines: lines) { out.append(s) }
            }
            return (out, skipped)
        }
    }

    func coachingRecord(_ personId: Int64) throws -> CoachingRecord? {
        try pool.read { db in try CoachingRecord.fetchOne(db, sql: "SELECT * FROM coaching WHERE person_id = ?", arguments: [personId]) }
    }

    /// 存建議：使用者說不對的清單照舊
    func saveCoaching(_ record: CoachingRecord) throws {
        try pool.write { db in
            var record = record
            if let old = try CoachingRecord.fetchOne(db, sql: "SELECT * FROM coaching WHERE person_id = ?", arguments: [record.personId]) {
                record.rejected = old.rejected
                record.useful = old.useful
            }
            try db.execute(sql: "DELETE FROM coaching WHERE person_id = ?", arguments: [record.personId])
            try record.insert(db)
        }
    }

    /// 「不對」：從建議拿掉，記下標題，之後不再寫
    func rejectCoachingFinding(_ personId: Int64, title: String) throws {
        try pool.write { db in
            guard var record = try CoachingRecord.fetchOne(db, sql: "SELECT * FROM coaching WHERE person_id = ?", arguments: [personId]),
                  var profile = record.decoded else { return }
            profile.strengths.removeAll { $0.title == title }
            profile.weaknesses.removeAll { $0.title == title }
            var titles = record.rejectedTitles
            if !titles.contains(title) { titles.append(title) }
            record.rejected = (try? JSONEncoder().encode(titles)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            record.profile = profile.jsonString()
            try db.execute(sql: "UPDATE coaching SET profile = ?, rejected = ? WHERE person_id = ?", arguments: [record.profile, record.rejected, personId])
        }
    }

    /// 「有用」：記下標題（再按一次取消），之後重新整理時請整理工具保留這一點
    func toggleUsefulCoachingFinding(_ personId: Int64, title: String) throws {
        try pool.write { db in
            guard let record = try CoachingRecord.fetchOne(db, sql: "SELECT * FROM coaching WHERE person_id = ?", arguments: [personId]) else { return }
            var titles = record.usefulTitles
            if let i = titles.firstIndex(of: title) { titles.remove(at: i) } else { titles.append(title) }
            let json = (try? JSONEncoder().encode(titles)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            try db.execute(sql: "UPDATE coaching SET useful = ? WHERE person_id = ?", arguments: [json, personId])
        }
    }

    func deleteCoaching(_ personId: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM coaching WHERE person_id = ?", arguments: [personId]) }
    }

    /// 會議整理完：我在這場會議，就排一次教練建議的更新（同一個人只排一個，已經在等就重新計時）
    @discardableResult
    func enqueueCoachingRefresh(_ meetingId: Int64) throws -> Bool {
        guard AppSettings.stakeholderAnalysis else { return false }
        let me = try myPersonIds()
        guard !me.isEmpty, try peopleInMeeting(meetingId).contains(where: me.contains) else { return false }
        let queued = try pool.write { db -> Bool in
            try db.execute(sql: "UPDATE jobs SET created_at = ?, meeting_id = ? WHERE kind = 'coaching' AND status = 'queued'",
                           arguments: [Clock.now(), meetingId])
            return db.changesCount > 0
        }
        if queued { return false }
        _ = try enqueue(meetingId, kind: .coaching)
        return true
    }
}

/// 送給整理工具的材料和提示詞
enum CoachingPrompt {
    static func system(_ language: MeetingLanguage) -> String {
        let name = language.profile.outputName ?? language.profile.uiName.en
        return """
        You are an executive coach with decades of experience coaching senior IT consultants. You coach ONE person: the user, whose lines are marked ★. \
        From the user's behaviour across ALL the meetings provided, write an OVERALL coaching assessment of their meeting soft skills: \
        recurring strengths and weaknesses, how they build or lose trust, and one concrete focus to improve. Do not coach individual meetings.

        Principles (from the research on feedback that changes behaviour):
        - Look for PATTERNS that recur across meetings. A one-off moment is only worth mentioning if it is unusually telling.
        - Be specific and behavioural: name what the user does, its effect on the other people, and in which kinds of meeting.
        - Few points: at most 3 strengths and 3 weaknesses, most important first. One focus.
        - Compare earlier meetings with recent ones to judge each trend: improving, same, worse, or new (first seen recently).
        - Never judge the person's character; judge observable behaviour. Be candid but encouraging, as a coach the user trusts.
        - Use the measured numbers given; do not contradict them. They are the user's own baseline, not industry rules.

        Rules:
        1. Meetings are labelled [Meeting id=N] with their date, kind (client, internal, interview, one-on-one) and measured numbers. Put N only in meetingId fields; in text refer to meetings by date and short title.
        2. Every strength, weakness and good example needs 1 to 3 pieces of evidence: meetingId, time exactly as in the excerpt (mm:ss or h:mm:ss) and a short quote (at most 25 words) of what was said there, in the original language. Points without evidence are discarded.
        3. summary: 3 short paragraphs (an array of 3 strings): how the user comes across in meetings overall, how this differs between kinds of meeting, and what has changed recently.
        4. strengths and weaknesses: title (a short behaviour, e.g. "Long briefings at the start of interviews"), detail (1 to 2 sentences: what they do, its effect, why it matters), trend, kinds, evidence.
        5. trust: the Trust Equation (Maister, Green & Galford): credibility (expertise and clarity of what they say), reliability (follow-through on commitments), intimacy (how safe others feel to open up, rapport), selfOrientation (focus on themselves rather than the other person; LOWER is better). For each: score 1 to 5, trend, one sentence of evidence-based reading, 1 piece of evidence. If there is no evidence for a part, say so in text and give a middle score of 3.
        6. byKind: one sentence for each kind of meeting present, describing how the user behaves there.
        7. plan: the ONE focus to work on next, taken from the weaknesses (focus: an action, e.g. "Keep interview briefings under 2 minutes"), skill: the measured skill that shows progress (listening = talk share, concision = longest stretch, dialogue = switches, clarity = fillers, room = others' longest story, curiosity = questions; other if none fits), kind: the kind of meeting it applies to (or all), why: one sentence with the numbers, techniques: exactly 3 concrete techniques the user can try in their next meeting, goodExample: a moment from the user's own meetings where they already did it well (title, detail, trend "same", kinds, evidence).
        8. changes: when a previous assessment is given, 0 to 4 short items on what changed since then (a new weakness, a trend that moved, a resolved issue), naming meetings by date. Empty otherwise.
        9. Points the user marked as wrong are listed; do not write them or close variants again.
        10. Write every text value in \(name). Keep quotes in the original language. Enum values stay in English.
        11. This is a private note for the user. Do not speculate about health, family or other sensitive attributes.
        """
    }

    struct MeetingMaterial {
        var stats: Coaching.MeetingStats
        var lines: [String]
    }

    static func prompt(me: String, role: String, org: String, summaries: [Coaching.SkillSummary], meetings: [MeetingMaterial],
                       previous: CoachingProfile?, rebuild: Bool = false, rejected: [String], useful: [String] = []) -> String {
        var out: [String] = []
        out.append("The user: \(me)" + ([role, org].contains { !$0.isEmpty } ? " (\([role, org].filter { !$0.isEmpty }.joined(separator: ", ")))" : ""))
        out.append("")
        out.append("Measured skills, 1 to 5 (recent meetings vs earlier meetings, against the user's targets):")
        for s in summaries {
            let now = s.now.map { String(format: "%.1f", $0) } ?? "-"
            let before = s.before.map { String(format: "%.1f", $0) } ?? "-"
            out.append("- \(s.skill.rawValue) (\(s.skill.metricName)): recent \(now), earlier \(before), trend \(s.trend.rawValue)")
        }
        if !rejected.isEmpty {
            out.append("")
            out.append("Points the user marked as wrong (do not repeat): " + rejected.joined(separator: "; "))
        }
        if !useful.isEmpty {
            out.append("")
            out.append("Points the user marked as useful (keep them, with the same title, while the evidence still supports them; update their trend): " + useful.joined(separator: "; "))
        }
        if let previous {
            out.append("")
            out.append(rebuild ? "Previous assessment (JSON), for the changes field only. Rebuild the assessment from all the meetings below; do not copy it:"
                       : "Previous assessment (JSON), to update with the new meetings and to write the changes field:")
            out.append(previous.jsonString())
        }
        for m in meetings {
            let s = m.stats
            out.append("")
            out.append("[Meeting id=\(s.id)] \(s.date) · \(s.title) · kind: \(s.kind.rawValue) · talk share \(Int(s.talk))%, longest stretch \(TimeFormat.string(s.longest)) at \(TimeFormat.string(s.longestAt)), switches/5min \(String(format: "%.1f", s.switches)), questions/30min \(Int(s.questions)), fillers/min \(String(format: "%.1f", s.fillers)), others' longest story \(TimeFormat.string(s.room))")
            out.append("Excerpts (the user's lines are marked ★; unmarked lines are what others said just before):")
            out += m.lines
        }
        return out.joined(separator: "\n")
    }

    static let characterLimit = 60_000
}
