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
        return #"{"type":"object","additionalProperties":false,"required":["summary","role","power","powerReason","interest","personality","motivations","topics","readings","advice","openQuestions"],"properties":{"summary":{"type":"string"},"role":{"type":"string"},"power":{"type":"string","enum":["high","medium","low"]},"powerReason":{"type":"string"},"interest":{"type":"string","enum":["high","medium","low"]},"personality":"# + point
            + #","motivations":"# + point + #","topics":"# + topics + #","readings":"# + readings + #","advice":"# + strings + #","openQuestions":"# + strings + "}}"
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

    var decoded: StakeholderProfile? { try? JSONDecoder().decode(StakeholderProfile.self, from: Data(profile.utf8)) }
    var analyzedMeetings: Set<Int64> { Set((try? JSONDecoder().decode([Int64].self, from: Data(meetingIds.utf8))) ?? []) }
}

extension AppDatabase {
    func stakeholderProfile(_ personId: Int64) throws -> StakeholderRecord? {
        try pool.read { db in try StakeholderRecord.fetchOne(db, sql: "SELECT * FROM stakeholder_profiles WHERE person_id = ?", arguments: [personId]) }
    }

    func saveStakeholderProfile(_ record: StakeholderRecord) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM stakeholder_profiles WHERE person_id = ?", arguments: [record.personId])
            var record = record
            try record.insert(db)
        }
    }

    func deleteStakeholderProfile(_ personId: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM stakeholder_profiles WHERE person_id = ?", arguments: [personId]) }
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
        var lines: [String]     // [時間] 說話者：內容（他自己的話，加上前一句別人說的話當上下文）
    }

    /// 送出的字數上限：超過就先刪舊會議的上下文、再截短舊會議的發言
    static let characterLimit = 40_000

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
        11. Write every text value (summary, role, powerReason, personality, motivations, topics, stance, meaning, advice, openQuestions) in \(name). Keep quotes in the original language of the transcript. power and interest stay as high / medium / low.
        """
    }

    static func prompt(person: String, otherNames: [String], previous: StakeholderProfile?, meetings: [MeetingMaterial]) -> String {
        var out: [String] = []
        out.append("Target person: \(person)")
        if !otherNames.isEmpty { out.append("Other names this person may be referred to by in the transcript: \(otherNames.joined(separator: ", "))") }
        if let previous {
            out.append("")
            out.append("Previous profile (JSON), to update:")
            out.append(previous.jsonString())
        }
        for m in meetings {
            out.append("")
            out.append("[Meeting \(m.id)] \(m.title) (\(m.date))")
            if !m.context.isEmpty {
                out.append("Meeting notes (context):")
                out += m.context.map { "- " + $0 }
            }
            out.append("Excerpts (the target's lines are marked with ★; unmarked lines are the line just before, for context):")
            out += m.lines
        }
        return out.joined(separator: "\n")
    }
}
