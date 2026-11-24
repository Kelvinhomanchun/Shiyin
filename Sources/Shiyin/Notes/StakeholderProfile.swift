import Foundation
import GRDB

/// 利害關係人分析（fork）：從一個人在每場會議說的話，整理他的個性、影響力、關心的議題，以及他的話背後的意思。
/// 每場會議整理完會累積更新（前一版的分析 + 新會議的發言），也可以在人物頁從全部會議重新分析。
/// 只根據他自己說的話和會議紀錄；推論都要附出處（哪場會議、哪個時間點），信心低的要說是推測。
struct StakeholderProfile: Codable, Hashable {
    struct Evidence: Codable, Hashable {
        var meetingId: Int64
        var time: String
        var quote: String
    }
    struct Point: Codable, Hashable {
        var text: String
        var evidence: [Evidence]
    }
    struct Topic: Codable, Hashable {
        var topic: String
        /// high / medium / low
        var interest: String
        /// 支持、反對、中立、擔心…（照分析的語言寫）
        var stance: String
        var evidence: [Evidence]
    }
    /// 話中的意思：他實際說的話 → 可能的意思
    struct Reading: Codable, Hashable {
        var meetingId: Int64
        var time: String
        var quote: String
        var meaning: String
    }

    /// 一兩句的總結：他是誰、在這些會議裡扮演什麼角色
    var summary: String
    /// 推測的角色、職位（例如客戶的專案負責人、內部的人資窗口）
    var role: String
    /// 影響力：high / medium / low，加上理由
    var power: String
    var powerReason: String
    /// 整體的參與度、關心程度：high / medium / low
    var interest: String
    /// 溝通風格、個性（例如直接、重細節、避免衝突）
    var personality: [Point]
    /// 他在意的事、動機、壓力來源
    var motivations: [Point]
    /// 他關心的議題和立場
    var topics: [Topic]
    /// 話中的意思：值得注意的發言和背後可能的意思
    var readings: [Reading]
    /// 跟他互動的建議
    var advice: [String]
    /// 還不確定、需要更多會議才看得出來的地方
    var openQuestions: [String]

    // MARK: 顧問用的欄位（第二版）：舊的分析沒有這些，讀的時候給預設值

    /// 他答應的事、我們答應他的事
    struct Commitment: Codable, Hashable {
        /// them（他答應的）／us（我們答應他的）
        var who: String
        var text: String
        var meetingId: Int64
        var time: String
    }
    /// 跟其他人的關係：聽誰的、跟誰站同一邊、跟誰有摩擦
    struct Relationship: Codable, Hashable {
        var person: String
        /// defers to / aligned with / tension with / manages / reports to（照分析的語言寫，短）
        var relation: String
        var note: String
    }
    /// 在一個案子（資料夾）上的影響力、關心程度、態度：同一個人在不同案子的份量不一樣（關係人地圖照這個放）
    struct Project: Codable, Hashable {
        var folder: String
        var power: String
        var interest: String
        var attitude: String
        var note: String
    }
    /// 跟使用者（我）的關係和怎麼跟他合作：專門寫給使用者的，用他們兩個人之間實際的互動當依據
    struct WorkingWithMe: Codable, Hashable {
        /// 一兩句：他怎麼看我、我們之間的關係（例如他把我當執行者、當顧問、當對手）
        var relationship: String
        /// 他對我的信任程度：high / medium / low
        var trust: String
        /// 他對我的期待
        var expectations: [String]
        /// 怎麼跟他溝通最有效（形式、頻率、細節程度、語言）
        var communication: [String]
        /// 在他面前建立信用的做法
        var buildTrust: [String]
        /// 我跟他互動時要小心的地方（我的習慣可能跟他衝突的地方）
        var watchOuts: [String]
        /// 我們之間互動的例子：我說了什麼、他怎麼反應（附出處）
        var interactions: [Reading]
        static let empty = WorkingWithMe(relationship: "", trust: "", expectations: [], communication: [], buildTrust: [], watchOuts: [], interactions: [])
        var isEmpty: Bool { relationship.isEmpty && expectations.isEmpty && communication.isEmpty && buildTrust.isEmpty && watchOuts.isEmpty }
    }
    /// 下一次見面的準備
    struct NextMeeting: Codable, Hashable {
        var objective: String
        var talkingPoints: [String]
        var questions: [String]
        var avoid: [String]
        static let empty = NextMeeting(objective: "", talkingPoints: [], questions: [], avoid: [])
    }

    /// 組織（客戶、內部部門、供應商）
    var organization: String = ""
    /// 態度：champion / supporter / neutral / skeptic / blocker
    var attitude: String = ""
    /// 態度的變化：improving / stable / declining / unknown
    var attitudeTrend: String = ""
    /// 在決策裡的角色：decision maker / influencer / gatekeeper / expert / user / other
    var decisionRole: String = ""
    /// 分析的把握：high / medium / low（他說了多少、出現在幾場會議）
    var confidence: String = ""
    /// 他需要我們提供的東西
    var needs: [String] = []
    var commitments: [Commitment] = []
    var relationships: [Relationship] = []
    var nextMeeting: NextMeeting = .empty
    var projects: [Project] = []
    var workingWithMe: WorkingWithMe = .empty

    /// 這個案子的評估；沒有時用整體的
    func project(_ folder: String?) -> Project? {
        guard let folder, !folder.isEmpty else { return nil }
        return projects.first { $0.folder.caseInsensitiveCompare(folder) == .orderedSame }
    }

    /// 影響力 × 關心程度的四個象限（Mendelow）：高高 = 密切管理、高低 = 讓他滿意、低高 = 隨時告知、低低 = 留意
    var quadrant: Quadrant { Quadrant(power: power, interest: interest) }

    enum Quadrant: String, CaseIterable {
        case manageClosely, keepSatisfied, keepInformed, monitor
        /// 影響力要「高」才算在上面（真的能拍板、能擋的人）；關心程度「中」以上就算在右邊
        init(power: String, interest: String) {
            switch (power == "high", interest != "low") {
            case (true, true): self = .manageClosely
            case (true, false): self = .keepSatisfied
            case (false, true): self = .keepInformed
            case (false, false): self = .monitor
            }
        }
    }

    init(summary: String, role: String, power: String, powerReason: String, interest: String, personality: [Point], motivations: [Point],
         topics: [Topic], readings: [Reading], advice: [String], openQuestions: [String]) {
        self.summary = summary; self.role = role; self.power = power; self.powerReason = powerReason; self.interest = interest
        self.personality = personality; self.motivations = motivations; self.topics = topics; self.readings = readings
        self.advice = advice; self.openQuestions = openQuestions
    }

    enum CodingKeys: String, CodingKey {
        case summary, role, power, powerReason, interest, personality, motivations, topics, readings, advice, openQuestions
        case organization, attitude, attitudeTrend, decisionRole, confidence, needs, commitments, relationships, nextMeeting, projects
        case workingWithMe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        summary = v(.summary, ""); role = v(.role, ""); power = v(.power, ""); powerReason = v(.powerReason, "")
        interest = v(.interest, ""); personality = v(.personality, []); motivations = v(.motivations, [])
        topics = v(.topics, []); readings = v(.readings, []); advice = v(.advice, []); openQuestions = v(.openQuestions, [])
        organization = v(.organization, ""); attitude = v(.attitude, ""); attitudeTrend = v(.attitudeTrend, "")
        decisionRole = v(.decisionRole, ""); confidence = v(.confidence, ""); needs = v(.needs, [])
        commitments = v(.commitments, []); relationships = v(.relationships, []); nextMeeting = v(.nextMeeting, .empty)
        projects = v(.projects, []); workingWithMe = v(.workingWithMe, .empty)
    }

    static let empty = StakeholderProfile(summary: "", role: "", power: "", powerReason: "", interest: "",
                                          personality: [], motivations: [], topics: [], readings: [], advice: [], openQuestions: [])

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static let jsonSchema: String = {
        let evidence = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["meetingId","time","quote"],"properties":{"meetingId":{"type":"integer"},"time":{"type":"string"},"quote":{"type":"string"}}}}"#
        let point = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","evidence"],"properties":{"text":{"type":"string"},"evidence":"# + evidence + "}}}"
        let topics = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["topic","interest","stance","evidence"],"properties":{"topic":{"type":"string"},"interest":{"type":"string","enum":["high","medium","low"]},"stance":{"type":"string"},"evidence":"# + evidence + "}}}"
        let readings = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["meetingId","time","quote","meaning"],"properties":{"meetingId":{"type":"integer"},"time":{"type":"string"},"quote":{"type":"string"},"meaning":{"type":"string"}}}}"#
        let strings = #"{"type":"array","items":{"type":"string"}}"#
        let commitments = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["who","text","meetingId","time"],"properties":{"who":{"type":"string","enum":["them","us"]},"text":{"type":"string"},"meetingId":{"type":"integer"},"time":{"type":"string"}}}}"#
        let relationships = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["person","relation","note"],"properties":{"person":{"type":"string"},"relation":{"type":"string"},"note":{"type":"string"}}}}"#
        let next = #"{"type":"object","additionalProperties":false,"required":["objective","talkingPoints","questions","avoid"],"properties":{"objective":{"type":"string"},"talkingPoints":"# + strings + #","questions":"# + strings + #","avoid":"# + strings + "}}"
        let level = #"{"type":"string","enum":["high","medium","low"]}"#
        let attitude = #"{"type":"string","enum":["champion","supporter","neutral","skeptic","blocker"]}"#
        let working = #"{"type":"object","additionalProperties":false,"required":["relationship","trust","expectations","communication","buildTrust","watchOuts","interactions"],"properties":{"relationship":{"type":"string"},"trust":"# + level + #","expectations":"# + strings + #","communication":"# + strings + #","buildTrust":"# + strings + #","watchOuts":"# + strings + #","interactions":"# + readings + "}}"
        let projects = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["folder","power","interest","attitude","note"],"properties":{"folder":{"type":"string"},"power":"# + level + #","interest":"# + level + #","attitude":"# + attitude + #","note":{"type":"string"}}}}"#
        return #"{"type":"object","additionalProperties":false,"required":["summary","role","organization","power","powerReason","interest","attitude","attitudeTrend","decisionRole","confidence","personality","motivations","needs","topics","readings","commitments","relationships","nextMeeting","projects","workingWithMe","advice","openQuestions"],"properties":{"summary":{"type":"string"},"role":{"type":"string"},"organization":{"type":"string"},"power":"# + level
            + #","powerReason":{"type":"string"},"interest":"# + level
            + #","attitude":{"type":"string","enum":["champion","supporter","neutral","skeptic","blocker"]},"attitudeTrend":{"type":"string","enum":["improving","stable","declining","unknown"]},"decisionRole":{"type":"string","enum":["decision maker","influencer","gatekeeper","expert","user","other"]},"confidence":"# + level
            + #","personality":"# + point + #","motivations":"# + point + #","needs":"# + strings + #","topics":"# + topics + #","readings":"# + readings
            + #","commitments":"# + commitments + #","relationships":"# + relationships + #","nextMeeting":"# + next + #","projects":"# + projects + #","workingWithMe":"# + working + #","advice":"# + strings + #","openQuestions":"# + strings + "}}"
    }()

    static let format = LLMClient.OutputFormat(schema: jsonSchema, toolName: "save_stakeholder_profile",
                                               toolDescription: "Save the stakeholder analysis of this person")

    /// 丟掉不能用的出處：不是提供的會議、時間格式不對
    func validated(meetingIds: Set<Int64>) -> StakeholderProfile {
        func clean(_ list: [Evidence]) -> [Evidence] {
            list.compactMap { e in
                var e = e
                e.time = TimeFormat.clean(e.time)
                e.quote = e.quote.trimmingCharacters(in: .whitespacesAndNewlines)
                guard meetingIds.contains(e.meetingId), TimeFormat.seconds(e.time) != nil else { return nil }
                return e
            }
        }
        var p = self
        p.personality = personality.map { Point(text: $0.text, evidence: clean($0.evidence)) }
        p.motivations = motivations.map { Point(text: $0.text, evidence: clean($0.evidence)) }
        p.topics = topics.map { Topic(topic: $0.topic, interest: $0.interest, stance: $0.stance, evidence: clean($0.evidence)) }
        p.readings = readings.compactMap { r in
            var r = r
            r.time = TimeFormat.clean(r.time)
            return meetingIds.contains(r.meetingId) && TimeFormat.seconds(r.time) != nil ? r : nil
        }
        p.commitments = commitments.compactMap { c in
            var c = c
            c.time = TimeFormat.clean(c.time)
            guard !c.text.isEmpty, meetingIds.contains(c.meetingId) else { return nil }
            if TimeFormat.seconds(c.time) == nil { c.time = "" }
            return c
        }
        p.projects = projects.filter { !$0.folder.isEmpty }
        p.workingWithMe.interactions = workingWithMe.interactions.compactMap { r in
            var r = r
            r.time = TimeFormat.clean(r.time)
            return meetingIds.contains(r.meetingId) && TimeFormat.seconds(r.time) != nil ? r : nil
        }
        return p
    }
}

/// 存在資料庫的一份分析：哪些會議已經分析過（累積更新時只送新的會議）
struct StakeholderRecord: SnakeCaseRecord, Hashable {
    static let databaseTableName = "stakeholder_profiles"
    var personId: Int64
    var profile: String          // StakeholderProfile 的 JSON
    var meetingIds: String       // 分析過的會議 id，JSON 陣列
    var language: String         // 分析用的語言
    var provider: String
    var updatedAt: String = Clock.now()
    /// 使用者自己填的：角色、組織、知道的背景（重新分析時保留，送給整理工具當成事實）
    var userRole: String = ""
    var userOrg: String = ""
    var userNotes: String = ""
    /// 分析用的模型（fork），例如 claude-opus-5-5；舊的分析是空的
    var model: String = ""

    /// 更新的時間，本機時區（例如 2026-11-24 11:32）
    var updatedLocal: String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: updatedAt) else { return String(updatedAt.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    var hasUserContext: Bool { !userRole.isEmpty || !userOrg.isEmpty || !userNotes.isEmpty }

    var decoded: StakeholderProfile? { try? JSONDecoder().decode(StakeholderProfile.self, from: Data(profile.utf8)) }
    var analyzedMeetings: Set<Int64> { Set((try? JSONDecoder().decode([Int64].self, from: Data(meetingIds.utf8))) ?? []) }
}

extension AppDatabase {
    func stakeholderProfile(_ personId: Int64) throws -> StakeholderRecord? {
        try pool.read { db in try StakeholderRecord.fetchOne(db, sql: "SELECT * FROM stakeholder_profiles WHERE person_id = ?", arguments: [personId]) }
    }

    /// 存分析：使用者填的背景照舊（不會被分析蓋掉）
    func saveStakeholderProfile(_ record: StakeholderRecord) throws {
        try pool.write { db in
            var record = record
            if let old = try StakeholderRecord.fetchOne(db, sql: "SELECT * FROM stakeholder_profiles WHERE person_id = ?", arguments: [record.personId]) {
                record.userRole = old.userRole
                record.userOrg = old.userOrg
                record.userNotes = old.userNotes
            }
            try db.execute(sql: "DELETE FROM stakeholder_profiles WHERE person_id = ?", arguments: [record.personId])
            try record.insert(db)
        }
    }

    /// 使用者填的角色、組織、背景；還沒分析過也可以先填（profile 先放空的）
    func saveStakeholderContext(_ personId: Int64, role: String, org: String, notes: String) throws {
        try pool.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT 1 FROM stakeholder_profiles WHERE person_id = ?", arguments: [personId]) ?? false
            if exists {
                try db.execute(sql: "UPDATE stakeholder_profiles SET user_role = ?, user_org = ?, user_notes = ? WHERE person_id = ?",
                               arguments: [role, org, notes, personId])
            } else {
                var record = StakeholderRecord(personId: personId, profile: "", meetingIds: "[]", language: "", provider: "",
                                               userRole: role, userOrg: org, userNotes: notes)
                try record.insert(db)
            }
        }
    }

    /// 所有分析過的人（關係人地圖）
    func allStakeholderProfiles() throws -> [StakeholderRecord] {
        try pool.read { db in try StakeholderRecord.fetchAll(db, sql: "SELECT * FROM stakeholder_profiles WHERE profile <> ''") }
    }

    /// 合併人物前：被併掉的人的背景接到留下的人（留下的人沒填的欄位才接），分析之後重做
    func mergeStakeholderContext(from: Int64, into: Int64) throws {
        try pool.write { db in
            guard let old = try StakeholderRecord.fetchOne(db, sql: "SELECT * FROM stakeholder_profiles WHERE person_id = ?", arguments: [from]),
                  old.hasUserContext else { return }
            if var keep = try StakeholderRecord.fetchOne(db, sql: "SELECT * FROM stakeholder_profiles WHERE person_id = ?", arguments: [into]) {
                if keep.userRole.isEmpty { keep.userRole = old.userRole }
                if keep.userOrg.isEmpty { keep.userOrg = old.userOrg }
                if keep.userNotes.isEmpty { keep.userNotes = old.userNotes } else if !old.userNotes.isEmpty { keep.userNotes += "\n" + old.userNotes }
                try db.execute(sql: "UPDATE stakeholder_profiles SET user_role = ?, user_org = ?, user_notes = ? WHERE person_id = ?",
                               arguments: [keep.userRole, keep.userOrg, keep.userNotes, into])
            } else {
                var record = StakeholderRecord(personId: into, profile: "", meetingIds: "[]", language: "", provider: "",
                                               userRole: old.userRole, userOrg: old.userOrg, userNotes: old.userNotes)
                try record.insert(db)
            }
        }
    }

    func deleteStakeholderProfile(_ personId: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM stakeholder_profiles WHERE person_id = ?", arguments: [personId]) }
    }

    /// 排一個「更新這場會議與會者的分析」：設定關掉、沒有認得名字的人、還沒有正式的會議紀錄時不排；
    /// 已經有一個在排隊就不再排（連續改好幾個名字時只做一次，跑的時候讀最新的名字）。回傳有沒有排
    @discardableResult
    func enqueueStakeholderRefresh(_ meetingId: Int64) throws -> Bool {
        guard AppSettings.stakeholderAnalysis else { return false }
        let ready = try pool.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT 1 FROM meetings WHERE id = ? AND deleted_at IS NULL AND notes IS NOT NULL AND notes <> '' AND notes_draft = 0
                """, arguments: [meetingId]) ?? false
        }
        guard ready, try !peopleInMeeting(meetingId).isEmpty else { return false }
        let queued = try pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT 1 FROM jobs WHERE meeting_id = ? AND kind = 'stakeholders' AND status = 'queued' AND payload IS NULL",
                              arguments: [meetingId]) ?? false
        }
        if queued { return false }
        _ = try enqueue(meetingId, kind: .stakeholders)
        return true
    }

    /// 這場會議裡對到人物的說話者（要更新分析的人）
    func peopleInMeeting(_ meetingId: Int64) throws -> [Int64] {
        try pool.read { db in
            try Int64.fetchAll(db, sql: "SELECT DISTINCT person_id FROM speakers WHERE meeting_id = ? AND person_id IS NOT NULL", arguments: [meetingId])
        }
    }

    /// 不分析自己：錄過「我的聲音」的人（R80）；沒錄過時，出現在最多場會議、而且至少一半的會議都有他的那個人當成自己
    func myPersonIds() throws -> Set<Int64> {
        try pool.read { db in
            let enrolled = Set(try Int64.fetchAll(db, sql: "SELECT DISTINCT person_id FROM voiceprints WHERE audio_source = 'enroll'"))
            guard enrolled.isEmpty else { return enrolled }
            let total = try Int.fetchOne(db, sql: "SELECT count(*) FROM meetings WHERE deleted_at IS NULL") ?? 0
            guard let row = try Row.fetchOne(db, sql: """
                SELECT s.person_id AS id, count(DISTINCT s.meeting_id) AS n FROM speakers s JOIN meetings m ON m.id = s.meeting_id
                WHERE s.person_id IS NOT NULL AND m.deleted_at IS NULL GROUP BY s.person_id ORDER BY n DESC LIMIT 1
                """) else { return [] }
            let n: Int = row["n"]
            return total >= 3 && n * 2 >= total ? [row["id"]] : []
        }
    }
}

/// 送給整理工具的材料和提示詞
enum StakeholderPrompt {
    /// 一場會議的材料：他說的每一句（說話者名字、時間點），加上會議紀錄的摘要和決議（看得懂上下文）
    struct MeetingMaterial {
        var id: Int64
        var title: String
        var date: String
        var context: [String]   // 摘要、決議
        var folder: String = ""  // 這場會議放在哪個資料夾（案子）
        var lines: [String]     // [時間] 說話者：內容（他自己的話，加上前一句別人說的話當上下文）
    }

    /// 送出的字數上限：超過就先刪舊會議的上下文、再截短舊會議的發言
    static let characterLimit = 40_000
    /// 另外選了分析用的模型（通常是長上下文的大模型）：可以多送一些較舊的會議
    static func characterLimit(customModel: Bool) -> Int { customModel ? 150_000 : characterLimit }

    static func system(_ language: MeetingLanguage) -> String {
        let name = language.profile.outputName ?? language.profile.uiName.en
        return """
        You are an experienced stakeholder analyst helping a consultant understand a person they meet with. \
        From the meetings provided, build a stakeholder profile of ONE person (the target). The other people in the excerpts are only context.

        Rules:
        1. Base everything only on what the target actually said and how they said it in the excerpts, plus the meeting notes for context. Do not use outside knowledge about real people.
        2. Separate observation from inference. When something is an inference, say so plainly ("seems to", "likely") and keep it modest; never state a guess as fact.
        3. Every personality point, motivation and topic needs evidence: meetingId (the [Meeting N] number), time exactly as in the excerpt ([mm:ss] or [h:mm:ss], without brackets), and a short quote of the target's own words (at most 25 words, in the original language).
        4. power: the target's influence over decisions and resources in these meetings (high / medium / low), with powerReason explaining why (title, who defers to them, who decides). interest: how engaged and invested they are overall (high / medium / low).
        5. topics: the subjects the target cares about, each with interest (high / medium / low) and stance (supportive, opposed, neutral, concerned, undecided… in a few words).
        6. readings: 3 to 8 notable things the target said where the underlying meaning differs from or goes beyond the literal words (hedging, polite refusal, hidden concern, pressure, a test, an indirect request). quote is their words; meaning is what it most likely signals, considering their role and context. Be culturally aware: Hong Kong / Cantonese and other Asian business communication is often indirect.
        7. advice: 2 to 5 practical tips for working with this person (how to frame proposals, what to prepare, what to avoid).
        8. openQuestions: what cannot be judged yet from these meetings.
        9. When a previous profile is given, update it with the new meetings: keep what still holds, revise what the new evidence changes, add new points, and keep the old evidence that still applies. Do not drop earlier meetings' insights just because they are not in the new excerpts.
        10. Be concise and professional. This is a private working note for the user; avoid judgmental or offensive wording, and do not speculate about health, religion, politics or other sensitive personal attributes.
        11. Write every text value (summary, role, organization, powerReason, personality, motivations, needs, topics, stance, meaning, commitments, relationships, nextMeeting, workingWithMe, advice, openQuestions) in \(name). Keep quotes in the original language of the transcript. The enum fields (power, interest, attitude, attitudeTrend, decisionRole, confidence, trust, who) stay exactly as the allowed English values.
        12. If "Facts from the user" are given, they are ground truth: use them for role, organization, power and decision role, and interpret everything the target says in that light. Do not contradict them; if the meetings seem to conflict, mention it in openQuestions.
        13. organization: the company or team the target belongs to (client, our firm, vendor, department), if known.
        14. attitude toward the user's work / project / proposal: champion (actively advocates), supporter, neutral, skeptic (doubts, pushes back), blocker (actively resists). attitudeTrend: improving / stable / declining across the meetings in date order, or unknown with only one meeting.
        15. decisionRole: decision maker (signs off, owns budget), influencer (shapes the decision), gatekeeper (controls access or process), expert (technical/subject authority), user (affected by the outcome), other.
        16. confidence: high when the target spoke a lot across several meetings, low when there is little to go on (one short meeting, few lines).
        17. needs: 2 to 5 concrete things the target needs from the user or the user's team (information, deliverables, reassurance, decisions).
        18. commitments: promises in the meetings — who "them" (the target promised) or "us" (the user / the user's side promised the target), the commitment in a few words, meetingId and time. Only explicit commitments.
        19. relationships: how the target relates to other named people in the excerpts (defers to, aligned with, tension with, manages, reports to), with a short note. Only what the excerpts show.
        20. nextMeeting: a practical plan for the user's next conversation with the target — objective (one sentence), talkingPoints (2 to 4), questions to ask to close the openQuestions (2 to 4), avoid (1 to 3 things that would likely backfire).
        21. projects: meetings are grouped into projects (the "project/folder" shown on each meeting). For EACH project the target appears in, assess power, interest and attitude on THAT project specifically — the same person can be a decision maker on one project and a bystander on another — with a one-sentence note on their stake in it. folder must be exactly the project name as given. Keep entries from the previous profile for projects not in the new excerpts. The top-level power / interest / attitude are the overall view across all projects.
        22. workingWithMe: advice written specifically for the user (named in "The user" below; their lines are marked ▲). Base it on how the target and the user actually interact in the excerpts — what the user says and how the target responds, who drives, where they agree or push back. relationship: how the target sees and treats the user (e.g. as an executor, trusted advisor, junior, peer, vendor). trust: high / medium / low. expectations (2 to 4): what the target expects from the user. communication (2 to 4): the format, level of detail, cadence and language that work best with this target. buildTrust (2 to 4): concrete moves that would raise the user's credibility with the target. watchOuts (1 to 3): habits or behaviours of the user in these meetings that may land badly with this target. interactions (1 to 4): telling exchanges, quote = the target's words in reply to the user (meetingId, time), meaning = what it reveals about their working relationship. If the user does not appear with the target, give empty arrays and say so in relationship.
        """
    }

    static func prompt(person: String, otherNames: [String], previous: StakeholderProfile?, meetings: [MeetingMaterial],
                       userRole: String = "", userOrg: String = "", userNotes: String = "", me: String? = nil) -> String {
        var out: [String] = []
        out.append("Target person: \(person)")
        out.append("The user (who will read this analysis): " + (me ?? "the person who recorded these meetings (not identified in the transcript)"))
        if !userRole.isEmpty || !userOrg.isEmpty || !userNotes.isEmpty {
            out.append("")
            out.append("Facts from the user (ground truth):")
            if !userRole.isEmpty { out.append("- Role / title: \(userRole)") }
            if !userOrg.isEmpty { out.append("- Organization: \(userOrg)") }
            if !userNotes.isEmpty { out.append("- What the user knows: \(userNotes)") }
        }
        if !otherNames.isEmpty { out.append("Other names this person may be referred to by in the transcript: \(otherNames.joined(separator: ", "))") }
        if let previous {
            out.append("")
            out.append("Previous profile (JSON), to update:")
            out.append(previous.jsonString())
        }
        for m in meetings {
            out.append("")
            // 子資料夾是「客戶/案子」：projects 用完整的路徑當 folder，分析時看得出是哪個客戶的哪個案子
            out.append("[Meeting \(m.id)] \(m.title) (\(m.date))" + (m.folder.isEmpty ? "" :
                FolderPath.isSub(m.folder) ? " — account: \(FolderPath.account(m.folder)), project/folder: \(m.folder)" : " — project/folder: \(m.folder)"))
            if !m.context.isEmpty {
                out.append("Meeting notes (context):")
                out += m.context.map { "- " + $0 }
            }
            out.append("Excerpts (the target's lines are marked ★, the user's lines ▲; unmarked lines are the line just before, for context):")
            out += m.lines
        }
        return out.joined(separator: "\n")
    }
}
