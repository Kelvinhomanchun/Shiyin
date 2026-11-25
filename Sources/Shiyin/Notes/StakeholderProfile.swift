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

    // MARK: 人物側寫（第三版，2026-11-25）：像顧問準備見一個人時要知道的（不是他在會議裡做了什麼）
    // 參考 Chief of Staff 關係人地圖（owns / measured on / this quarter / how they like to work / trusts）、
    // Umbrex 大客戶管理（strategic priorities、personal wins、risk posture、decision triggers）、
    // Miller Heiman 的 personal win、Social Styles 的決策風格、Maister / Sobel 的「客戶的議程」

    /// 他的人物側寫
    struct Portrait: Codable, Hashable {
        /// 他負責什麼、對什麼結果負責（職責、管的範圍、團隊）
        var mandate: [Point]
        /// 他被怎麼評量：他的成功標準、指標、期限
        var measuredOn: [Point]
        /// 他現在的議程：這段時間最優先要完成的事
        var agenda: [Point]
        /// 壓力來源：上面、外面給他的壓力，他擔心的風險
        var pressures: [Point]
        /// 個人的贏面：做成了對他自己有什麼好處（名聲、升遷、證明自己、保住位置），推測要講明
        var personalWin: String
        /// 決策風格：怎麼下決定、相信什麼證據、怎麼看風險
        var decisionStyle: [Point]
        /// 工作和溝通的方式：直接或委婉、看細節或大方向、節奏
        var workingStyle: [Point]
        /// 底線、會讓他反彈的事
        var redLines: [Point]
        /// 他聽誰的、相信誰的意見
        var trustedVoices: [String]
        static let empty = Portrait(mandate: [], measuredOn: [], agenda: [], pressures: [], personalWin: "", decisionStyle: [],
                                    workingStyle: [], redLines: [], trustedVoices: [])
        var isEmpty: Bool {
            mandate.isEmpty && measuredOn.isEmpty && agenda.isEmpty && pressures.isEmpty && personalWin.isEmpty
                && decisionStyle.isEmpty && workingStyle.isEmpty && redLines.isEmpty
        }
    }
    var portrait: Portrait = .empty
    /// 這次更新改了什麼（第一次分析時空的）：每一點一句，例如「態度從存疑變成支持」
    var changes: [String] = []
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
        case workingWithMe, portrait, changes
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
        portrait = v(.portrait, .empty); changes = v(.changes, [])
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
        let portrait = #"{"type":"object","additionalProperties":false,"required":["mandate","measuredOn","agenda","pressures","personalWin","decisionStyle","workingStyle","redLines","trustedVoices"],"properties":{"mandate":"# + point + #","measuredOn":"# + point + #","agenda":"# + point + #","pressures":"# + point + #","personalWin":{"type":"string"},"decisionStyle":"# + point + #","workingStyle":"# + point + #","redLines":"# + point + #","trustedVoices":"# + strings + "}}"
        let projects = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["folder","power","interest","attitude","note"],"properties":{"folder":{"type":"string"},"power":"# + level + #","interest":"# + level + #","attitude":"# + attitude + #","note":{"type":"string"}}}}"#
        return #"{"type":"object","additionalProperties":false,"required":["summary","portrait","changes","role","organization","power","powerReason","interest","attitude","attitudeTrend","decisionRole","confidence","personality","motivations","needs","topics","readings","commitments","relationships","nextMeeting","projects","workingWithMe","advice","openQuestions"],"properties":{"summary":{"type":"string"},"portrait":"# + portrait + #","changes":"# + strings + #","role":{"type":"string"},"organization":{"type":"string"},"power":"# + level
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
        p.projects = Self.mergedProjects(projects.filter { !$0.folder.isEmpty })
        func cleanPoints(_ list: [Point]) -> [Point] {
            list.compactMap { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Point(text: $0.text, evidence: clean($0.evidence)) }
        }
        p.portrait.mandate = cleanPoints(portrait.mandate)
        p.portrait.measuredOn = cleanPoints(portrait.measuredOn)
        p.portrait.agenda = cleanPoints(portrait.agenda)
        p.portrait.pressures = cleanPoints(portrait.pressures)
        p.portrait.decisionStyle = cleanPoints(portrait.decisionStyle)
        p.portrait.workingStyle = cleanPoints(portrait.workingStyle)
        p.portrait.redLines = cleanPoints(portrait.redLines)
        p.portrait.personalWin = portrait.personalWin.trimmingCharacters(in: .whitespacesAndNewlines)
        p.changes = changes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        p.workingWithMe.interactions = workingWithMe.interactions.compactMap { r in
            var r = r
            r.time = TimeFormat.clean(r.time)
            return meetingIds.contains(r.meetingId) && TimeFormat.seconds(r.time) != nil ? r : nil
        }
        return p
    }

    /// 把文字裡的會議編號（Meeting 22、會議 22）換成日期和標題；只換認得的編號，出處的 meetingId 不動
    func namingMeetings(_ labels: [Int64: String]) -> StakeholderProfile {
        guard !labels.isEmpty, let regex = try? NSRegularExpression(pattern: #"(\b[Ii]n )?\[?\b(?:[Mm]eeting|會議|会议)\s?#?(?:id=)?(\d+)\b\]?"#) else { return self }  // l10n-skip
        let json = jsonString()
        let ns = json as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: json, range: NSRange(location: 0, length: ns.length)) {
            guard let id = Int64(ns.substring(with: match.range(at: 2))), let label = labels[id] else { continue }
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            // 「In Meeting 22」→「on 2026-11-25 “標題”」
            if match.range(at: 1).location != NSNotFound { out += ns.substring(with: match.range(at: 1)).hasPrefix("I") ? "On " : "on " }
            // 放進 JSON 字串：引號、反斜線要跳脫
            out += label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            last = match.range.location + match.range.length
        }
        guard last > 0 else { return self }
        out += ns.substring(from: last)
        return (try? JSONDecoder().decode(StakeholderProfile.self, from: Data(out.utf8))) ?? self
    }

    /// 同一個案子只留一筆（資料夾改名後，舊名字和新名字各一筆）：留第一筆（新的分析先寫），沒寫的說明用另一筆補
    static func mergedProjects(_ list: [Project]) -> [Project] {
        var out: [Project] = []
        for p in list {
            if let i = out.firstIndex(where: { $0.folder.caseInsensitiveCompare(p.folder) == .orderedSame }) {
                if out[i].note.isEmpty { out[i].note = p.note }
            } else {
                out.append(p)
            }
        }
        return out
    }

    /// 資料夾改名：案子的評估跟著改名，跟新名字原本的那筆合併；刪掉資料夾（改成空的）時拿掉
    func renamingProject(_ old: String, to new: String) -> StakeholderProfile {
        guard projects.contains(where: { $0.folder.caseInsensitiveCompare(old) == .orderedSame }) else { return self }
        func same(_ x: String, _ y: String) -> Bool { x.caseInsensitiveCompare(y) == .orderedSame }
        // 改成的名字原本就有一筆：留原本那筆（它是用新名字分析的），舊的只補說明
        let existing = projects.filter { same($0.folder, new) }
        let moved = new.isEmpty ? [] : projects.filter { same($0.folder, old) }.map { project -> Project in
            var project = project
            project.folder = new
            return project
        }
        let rest = projects.filter { !same($0.folder, old) && !same($0.folder, new) }
        var p = self
        p.projects = Self.mergedProjects(existing + moved) + rest
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

    /// 還在的資料夾（資料夾表、會議用到的）：分析裡的案子要是其中一個
    func existingFolders() throws -> Set<String> {
        try pool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM folders UNION SELECT DISTINCT folder FROM meetings WHERE folder <> '' AND deleted_at IS NULL"))
        }
    }

    /// 拿掉分析裡已經不在的資料夾的案子評估（這個修正之前改名的資料夾，留下舊名字的一筆）。回傳改了幾個人
    @discardableResult
    func pruneStakeholderProjects() throws -> Int {
        let folders = try existingFolders()
        guard !folders.isEmpty else { return 0 }
        return try pool.write { db in
            var changed = 0
            for record in try StakeholderRecord.fetchAll(db, sql: "SELECT * FROM stakeholder_profiles WHERE profile <> ''") {
                guard var profile = record.decoded else { continue }
                let kept = profile.projects.filter { folders.contains($0.folder) }
                guard kept.count != profile.projects.count else { continue }
                profile.projects = kept
                try db.execute(sql: "UPDATE stakeholder_profiles SET profile = ? WHERE person_id = ?", arguments: [profile.jsonString(), record.personId])
                changed += 1
            }
            return changed
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
        // 已經有一個在等：重新計時（會議紀錄又改了，等改完再一次分析），不另外排
        let queued = try pool.write { db -> Bool in
            try db.execute(sql: "UPDATE jobs SET created_at = ? WHERE meeting_id = ? AND kind = 'stakeholders' AND status = 'queued' AND payload IS NULL",
                           arguments: [Clock.now(), meetingId])
            return db.changesCount > 0
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
        You are a senior management consultant and executive coach helping the user (a consultant) understand ONE person they work with (the target). \
        From the meetings provided, write the private profile the user would want before meeting this person: who they are, what they own and are measured on, \
        what they are trying to achieve and what pressures them, what drives them, how they decide and like to work, and how to work with them. \
        The other people in the excerpts are only context.

        What a good profile is:
        - It describes the PERSON, not the meetings. Synthesise across all meetings into stable traits, goals and patterns. Do not narrate what happened in meetings ("In the meeting on … he said …") outside the evidence, readings, commitments and changes fields.
        - Every point is specific to this person and useful for the user: no generic statements that would fit anyone in that job ("wants the project to succeed"). Name the concrete deliverable, metric, deadline, risk or person.
        - Separate observation from inference. When something is an inference, say so plainly ("likely", "seems to") and keep it modest; never state a guess as fact.

        Rules:
        1. Base everything only on what the target actually said and how they said it in the excerpts, plus the meeting notes for context. Do not use outside knowledge about real people.
        2. Meetings are labelled [Meeting id=N]. Put N only in meetingId fields. Never write "Meeting N", meeting ids or "the meeting above" in any text value; when text must refer to a meeting, use its date and short title, e.g. "on 2026-11-25 (AXA weekly progress)".
        3. Evidence: meetingId, time exactly as in the excerpt ([mm:ss] or [h:mm:ss], without brackets), and a short quote of the target's own words (at most 25 words, in the original language). Give evidence for every point that can be backed by a quote; a point without evidence must be phrased as an inference.
        4. summary: 3 to 4 sentences, a profile in brief, written so it stays true across meetings: (a) who they are and what they own, (b) what they are driving toward right now and under what pressure, (c) how they operate (style, what they value, how they decide), (d) what this means for the user. No meeting dates, no event narration, no comments about the analysis itself.
        5. portrait (each list 1 to 4 points, one sentence each, most important first; empty when there is no basis):
           - mandate: what they are responsible and accountable for — scope, team, budget, systems, deliverables they own.
           - measuredOn: how their success is judged — the outcomes, metrics, deadlines or approvals they answer for (infer from what they chase and report on; mark inferences).
           - agenda: their priorities right now, the few things they are trying to get done in the coming weeks or months.
           - pressures: pressure on them (from their boss, sponsor, customers, regulators, deadlines, budget) and the risks they worry about.
           - personalWin: one or two sentences on what success would do for them personally (credibility, being proven right, protecting their team, career, reputation). Always phrase as an inference.
           - decisionStyle: how they make decisions — what evidence they trust (data, artefacts, people, precedent), speed, consensus vs. directive, risk appetite, what they need before saying yes.
           - workingStyle: how they communicate and like to work — direct or diplomatic, detail or big picture, written or verbal, pace, humour, how they give feedback, how they run meetings.
           - redLines: what they will not accept or what reliably triggers push-back from them.
           - trustedVoices: names (or roles) of the people whose opinion they rely on or defer to, from the excerpts only.
        6. personality: 2 to 4 enduring character traits and values (e.g. "holds people to commitments", "protective of his team"), distinct from workingStyle. motivations: 2 to 4 deeper drivers — what energises them and why they care, distinct from agenda.
        7. power: the target's influence over decisions and resources (high / medium / low), with powerReason explaining why (title, who defers to them, who decides). interest: how engaged and invested they are overall (high / medium / low).
        8. topics: the subjects the target cares about, each with interest (high / medium / low) and stance (supportive, opposed, neutral, concerned, undecided… in a few words).
        9. readings: 3 to 8 notable things the target said where the underlying meaning differs from or goes beyond the literal words (hedging, polite refusal, hidden concern, pressure, a test, an indirect request). quote is their words; meaning is what it most likely signals, considering their role and context. Be culturally aware: Hong Kong / Cantonese and other Asian business communication is often indirect.
        10. advice: 2 to 5 practical tips for working with this person (how to frame proposals, what to prepare, what to avoid).
        11. openQuestions: 2 to 5 things about the PERSON the user should still find out (their real authority, what they are measured on, their view on an open decision, their relationship with someone). Only questions about the person and their situation. Never ask about the app or the data: folder or project names, duplicate entries, speaker labels or transcription errors.
        12. When a previous profile is given, update it with the new meetings: keep what still holds, revise what the new evidence changes, add new points, and keep the old evidence that still applies. Do not drop earlier meetings' insights just because they are not in the new excerpts. If the new material adds nothing, return the previous profile unchanged.
        13. changes: compared with the previous (or earlier) profile, 0 to 5 short items on what changed about the person — a new priority, a shifted stance or attitude, a new pressure, a commitment made or kept, a revised assessment — each naming the meeting by date as in rule 2, e.g. "Attitude to the BA team moved from critical to supportive (2026-11-25 weekly progress)". Empty when there is no previous profile or nothing changed. Do not list wording or formatting changes.
        14. Be concise and professional. This is a private working note for the user; avoid judgmental or offensive wording, and do not speculate about health, family, religion, politics or other sensitive personal attributes. If you would not say a line to the person's face, rephrase it.
        15. Write every text value (summary, portrait, changes, role, organization, powerReason, personality, motivations, needs, topics, stance, meaning, commitments, relationships, nextMeeting, workingWithMe, advice, openQuestions) in \(name). Keep quotes in the original language of the transcript. The enum fields (power, interest, attitude, attitudeTrend, decisionRole, confidence, trust, who) stay exactly as the allowed English values.
        16. If "Facts from the user" are given, they are ground truth: use them for role, organization, mandate, power and decision role, and interpret everything the target says in that light. Do not contradict them; if the meetings seem to conflict, mention it in openQuestions.
        17. organization: the company or team the target belongs to (client, our firm, vendor, department), if known.
        18. attitude toward the user's work / project / proposal: champion (actively advocates), supporter, neutral, skeptic (doubts, pushes back), blocker (actively resists). attitudeTrend: improving / stable / declining across the meetings in date order, or unknown with only one meeting.
        19. decisionRole: decision maker (signs off, owns budget), influencer (shapes the decision), gatekeeper (controls access or process), expert (technical/subject authority), user (affected by the outcome), other.
        20. confidence: high when the target spoke a lot across several meetings, low when there is little to go on (one short meeting, few lines).
        21. needs: 2 to 5 concrete things the target needs from the user or the user's team (information, deliverables, reassurance, decisions).
        22. commitments: promises in the meetings — who "them" (the target promised) or "us" (the user / the user's side promised the target), the commitment in a few words, meetingId and time. Only explicit commitments.
        23. relationships: how the target relates to other named people in the excerpts (defers to, aligned with, tension with, manages, reports to), with a short note. Only what the excerpts show.
        24. nextMeeting: a practical plan for the user's next conversation with the target — objective (one sentence), talkingPoints (2 to 4), questions to ask to close the openQuestions (2 to 4), avoid (1 to 3 things that would likely backfire).
        25. projects: meetings are grouped into projects (the "project/folder" shown on each meeting). For EACH project the target appears in, assess power, interest and attitude on THAT project specifically — the same person can be a decision maker on one project and a bystander on another — with a one-sentence note on their stake in it. folder must be exactly the project name as given. Keep entries from the previous profile for projects not in the new excerpts. The top-level power / interest / attitude are the overall view across all projects.
        26. workingWithMe: advice written specifically for the user (named in "The user" below; their lines are marked ▲). Base it on how the target and the user actually interact in the excerpts — what the user says and how the target responds, who drives, where they agree or push back. relationship: how the target sees and treats the user (e.g. as an executor, trusted advisor, junior, peer, vendor). trust: high / medium / low. expectations (2 to 4): what the target expects from the user. communication (2 to 4): the format, level of detail, cadence and language that work best with this target. buildTrust (2 to 4): concrete moves that would raise the user's credibility with the target. watchOuts (1 to 3): habits or behaviours of the user in these meetings that may land badly with this target. interactions (1 to 4): telling exchanges, quote = the target's words in reply to the user (meetingId, time), meaning = what it reveals about their working relationship. If the user does not appear with the target, give empty arrays and say so in relationship.
        """
    }

    /// comparison：重新分析（從全部會議重做）時的上一版，只用來寫「這次改了什麼」
    static func prompt(person: String, otherNames: [String], previous: StakeholderProfile?, meetings: [MeetingMaterial],
                       userRole: String = "", userOrg: String = "", userNotes: String = "", me: String? = nil,
                       comparison: StakeholderProfile? = nil) -> String {
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
        } else if let comparison {
            out.append("")
            out.append("Earlier profile (JSON), for the changes field only. Rebuild the profile from the meetings below; do not copy it:")
            out.append(comparison.jsonString())
        }
        for m in meetings {
            out.append("")
            // 子資料夾是「客戶/案子」：projects 用完整的路徑當 folder，分析時看得出是哪個客戶的哪個案子
            out.append("[Meeting id=\(m.id)] \(m.date) · \(m.title)" + (m.folder.isEmpty ? "" :
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
