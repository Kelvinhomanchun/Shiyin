import Foundation
import GRDB

/// 工作坊（fork）：業務分析師跟客戶開的需求工作坊。開會前先準備（目的、範圍、要驗證的草稿流程、要問的問題），
/// 開完後整理成：草稿流程每一步的驗證結果、問題的回答、客戶走一遍的流程（含例外、交接、系統、痛點）、需求與規則、RAID。
/// 每一項都附證據（誰、什麼時候、原話），而且都是「待確認」——只有使用者可以按確認（CBAF：Only a person may set a status to confirmed）。
/// ID 對齊 CBAF 的 Engagement Control Workbook：QST-、REQ-、RUL-、AUTH-、DEC-、ASM-、ISS-、RSK-、PRC-、EV-

// MARK: - 開會前：目的、範圍、準備

/// 這場工作坊要做什麼（可複選）
enum WorkshopPurpose: String, Codable, CaseIterable, Identifiable {
    case validate, clarify, walkthrough, elicit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .validate: String(localized: "驗證草稿流程")
        case .clarify: String(localized: "釐清問題")
        case .walkthrough: String(localized: "請客戶走一遍流程")
        case .elicit: String(localized: "蒐集需求")
        }
    }
    var detail: String {
        switch self {
        case .validate: String(localized: "拿我畫好的流程給客戶看，確認每一步對不對")
        case .clarify: String(localized: "把準備好的問題一題一題問完")
        case .walkthrough: String(localized: "請客戶說明他們每天怎麼做，從頭走到尾")
        case .elicit: String(localized: "問客戶想要什麼、卡在哪裡")
        }
    }
    var icon: String {
        switch self {
        case .validate: "checkmark.rectangle.stack"
        case .clarify: "questionmark.bubble"
        case .walkthrough: "figure.walk"
        case .elicit: "text.badge.plus"
        }
    }
}

/// 要問的一個問題（QST-）。可以連到草稿流程的某一步
struct WorkshopQuestion: Codable, Hashable, Identifiable {
    var id: String          // QST-001
    var text: String
    /// 連到草稿流程某一步的 ref（1、2a…）；沒有是空字串
    var stepRef: String = ""
    /// 問誰（可以空）
    var ask: String = ""

    init(id: String, text: String, stepRef: String = "", ask: String = "") {
        (self.id, self.text, self.stepRef, self.ask) = (id, text, stepRef, ask)
    }
    enum CodingKeys: String, CodingKey { case id, text, stepRef, ask }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        stepRef = (try? c.decode(String.self, forKey: .stepRef)) ?? ""
        ask = (try? c.decode(String.self, forKey: .ask)) ?? ""
    }
}

/// 開會前的準備：存在 workshop_plans，一場一份
struct WorkshopPlan: Codable, Equatable {
    var purposes: [WorkshopPurpose] = []
    /// 流程範圍：從什麼事件開始、到什麼結果結束
    var trigger: String = ""
    var endPoint: String = ""
    /// 流程負責人（客戶那邊）
    var owner: String = ""
    /// 草稿流程（版本 1）：用 KelNote 的圖格式存；沒有時 nil
    var draft: MeetingDiagrams.Diagram? = nil
    /// 草稿的來源說明（「手動輸入」「從文字整理」「從檔案 X」）
    var draftSource: String = ""
    /// 草稿是從這段文字整理的；使用者提的意見留著，重新畫時一起給整理工具
    var draftText: String = ""
    var draftComments: [String] = []
    var questions: [WorkshopQuestion] = []
    /// 這個專案（資料夾）從哪個編號開始接（QST-、REQ-… 各自）
    var counters: [String: Int] = [:]

    var isEmpty: Bool {
        purposes.isEmpty && trigger.isEmpty && endPoint.isEmpty && owner.isEmpty && draft == nil && questions.isEmpty
    }
    var hasDraft: Bool { draft.map { $0.nodes.count >= 2 } ?? false }

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
    static func decode(_ json: String?) -> WorkshopPlan? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkshopPlan.self, from: data)
    }
}

// MARK: - 開完後：分析結果

/// 一條證據：誰、什麼時候、原話
struct WorkshopEvidence: Codable, Hashable {
    var speaker: String = ""
    var time: String = ""
    var quote: String = ""

    init(speaker: String = "", time: String = "", quote: String = "") { (self.speaker, self.time, self.quote) = (speaker, time, quote) }
    enum CodingKeys: String, CodingKey { case speaker, time, quote }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speaker = (try? c.decode(String.self, forKey: .speaker)) ?? ""
        time = TimeFormat.clean((try? c.decode(String.self, forKey: .time)) ?? "")
        quote = (try? c.decode(String.self, forKey: .quote)) ?? ""
    }
}

/// 使用者對一項的決定：AI 給的都是 unconfirmed，只有使用者能確認
enum WorkshopStatus: String, Codable { case unconfirmed, confirmed, rejected }

/// 草稿流程每一步的驗證結果
enum StepVerdict: String, Codable, CaseIterable {
    case confirmed          // 客戶說就是這樣
    case changed            // 順序、角色或平行不一樣
    case added              // 客戶說還有一步，草稿沒有（ref 空）
    case notDone            // 實際上沒人這樣做
    case disputed           // 客戶之間說法不同
    case unclear            // 沒討論到，或沒說清楚

    var title: String {
        switch self {
        case .confirmed: String(localized: "確認")
        case .changed: String(localized: "要修改")
        case .added: String(localized: "新增的一步")
        case .notDone: String(localized: "實際沒做")
        case .disputed: String(localized: "說法不同")
        case .unclear: String(localized: "沒討論到")
        }
    }
    var icon: String {
        switch self {
        case .confirmed: "checkmark.circle"
        case .changed: "pencil.circle"
        case .added: "plus.circle"
        case .notDone: "minus.circle"
        case .disputed: "exclamationmark.bubble"
        case .unclear: "questionmark.circle"
        }
    }
}

/// 所有分析項目共用的欄位：ID、狀態、證據、使用者改過沒
struct WorkshopMeta: Codable, Hashable {
    var id: String = ""
    var status: WorkshopStatus = .unconfirmed
    var evidence: [WorkshopEvidence] = []
    /// 使用者手動改過文字：重新分析時保留
    var edited = false
    /// 使用者確認的日期、確認的人（使用者自己填，沒填就是空）
    var confirmedOn: String = ""
    var confirmedBy: String = ""
}

struct StepFinding: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    /// 草稿的哪一步（node id）；新增的是空字串
    var nodeId: String = ""
    var ref: String = ""
    var label: String = ""
    var verdict: StepVerdict = .unclear
    /// 客戶怎麼說的、要怎麼改（一句話）
    var note: String = ""
    /// 要改的內容（verdict == changed 或 added 時）：新的標題、泳道、接在哪一步後面
    var newLabel: String = ""
    var newLane: String = ""
    var afterRef: String = ""

    enum CodingKeys: String, CodingKey { case meta, nodeId, ref, label, verdict, note, newLabel, newLane, afterRef }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        nodeId = (try? c.decode(String.self, forKey: .nodeId)) ?? ""
        ref = (try? c.decode(String.self, forKey: .ref)) ?? ""
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        verdict = (try? c.decode(StepVerdict.self, forKey: .verdict)) ?? .unclear
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        newLabel = (try? c.decode(String.self, forKey: .newLabel)) ?? ""
        newLane = (try? c.decode(String.self, forKey: .newLane)) ?? ""
        afterRef = (try? c.decode(String.self, forKey: .afterRef)) ?? ""
    }
}

enum AnswerState: String, Codable {
    case answered, partial, notCovered
    var title: String {
        switch self {
        case .answered: String(localized: "已回答")
        case .partial: String(localized: "回答一部分")
        case .notCovered: String(localized: "沒問到")
        }
    }
    var icon: String {
        switch self {
        case .answered: "checkmark.circle"
        case .partial: "circle.lefthalf.filled"
        case .notCovered: "circle.dashed"
        }
    }
}

struct QuestionFinding: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    var text: String = ""
    var stepRef: String = ""
    var state: AnswerState = .notCovered
    var answer: String = ""
    /// 現場新提出來的問題（不是事前準備的）
    var raisedInRoom = false
    /// 誰要回答、哪天前（還沒回答的）
    var owner: String = ""
    var due: String = ""

    enum CodingKeys: String, CodingKey { case meta, text, stepRef, state, answer, raisedInRoom, owner, due }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        stepRef = (try? c.decode(String.self, forKey: .stepRef)) ?? ""
        state = (try? c.decode(AnswerState.self, forKey: .state)) ?? .notCovered
        answer = (try? c.decode(String.self, forKey: .answer)) ?? ""
        raisedInRoom = (try? c.decode(Bool.self, forKey: .raisedInRoom)) ?? false
        owner = (try? c.decode(String.self, forKey: .owner)) ?? ""
        due = (try? c.decode(String.self, forKey: .due)) ?? ""
    }
}

/// 客戶走一遍的流程裡的一步（PRC-）。主線先、例外接在它分出去的那一步
struct WalkStep: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    /// 步驟編號（1、2、2a…）
    var ref: String = ""
    /// 動詞＋受詞
    var label: String = ""
    /// 誰做
    var actor: String = ""
    /// 用什麼系統、檔案（Excel、郵件…）
    var systems: String = ""
    /// 多久、多少量、多常發生
    var timing: String = ""
    /// 例外：這一步是從哪一步分出去的（ref）；主線是空字串
    var branchFrom: String = ""
    /// 例外發生的頻率（「大約一成」）
    var frequency: String = ""
    /// 交給下一位的時候，接手的人需要什麼
    var handoffNeeds: String = ""
    /// 這一步是草稿裡的哪一步（對得到才有）
    var draftNodeId: String = ""

    enum CodingKeys: String, CodingKey { case meta, ref, label, actor, systems, timing, branchFrom, frequency, handoffNeeds, draftNodeId }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        for (key, set) in [(CodingKeys.ref, \WalkStep.ref), (.label, \.label), (.actor, \.actor), (.systems, \.systems), (.timing, \.timing),
                           (.branchFrom, \.branchFrom), (.frequency, \.frequency), (.handoffNeeds, \.handoffNeeds), (.draftNodeId, \.draftNodeId)] {
            self[keyPath: set] = (try? c.decode(String.self, forKey: key)) ?? ""
        }
    }
}

struct PainPoint: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    var text: String = ""
    var stepRef: String = ""
    /// 客戶自己的做法（這是最有價值的發現）
    var workaround: String = ""
    /// 影響（多久、多少錢、多少錯）：客戶說過才寫
    var impact: String = ""

    enum CodingKeys: String, CodingKey { case meta, text, stepRef, workaround, impact }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        stepRef = (try? c.decode(String.self, forKey: .stepRef)) ?? ""
        workaround = (try? c.decode(String.self, forKey: .workaround)) ?? ""
        impact = (try? c.decode(String.self, forKey: .impact)) ?? ""
    }
}

enum RequirementKind: String, Codable, CaseIterable {
    case functional, data, report, integration, nonFunctional, constraint
    var title: String {
        switch self {
        case .functional: String(localized: "功能")
        case .data: String(localized: "資料")
        case .report: String(localized: "報表")
        case .integration: String(localized: "系統串接")
        case .nonFunctional: String(localized: "非功能（速度、安全、稽核）")
        case .constraint: String(localized: "限制")
        }
    }
    var short: String {
        switch self {
        case .functional: String(localized: "功能")
        case .data: String(localized: "資料")
        case .report: String(localized: "報表")
        case .integration: String(localized: "串接")
        case .nonFunctional: String(localized: "非功能")
        case .constraint: String(localized: "限制")
        }
    }
}

struct RequirementFinding: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    var text: String = ""
    var kind: RequirementKind = .functional
    /// 客戶講過優先順序才寫（高、中、低或原話）；沒講過是空字串，不替客戶決定
    var priority: String = ""
    var stepRef: String = ""
    /// 這是從哪個變通做法看出來的需求（PNP- 的痛點 ID）；沒有是空字串
    var fromWorkaround: String = ""

    enum CodingKeys: String, CodingKey { case meta, text, kind, priority, stepRef, fromWorkaround }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        kind = (try? c.decode(RequirementKind.self, forKey: .kind)) ?? .functional
        priority = (try? c.decode(String.self, forKey: .priority)) ?? ""
        stepRef = (try? c.decode(String.self, forKey: .stepRef)) ?? ""
        fromWorkaround = (try? c.decode(String.self, forKey: .fromWorkaround)) ?? ""
    }
}

/// 業務規則（RUL-）、權限（AUTH-）候選：都帶來源，狀態是 candidate（沒確認前不算規則）
struct RuleFinding: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    var text: String = ""
    /// authority：誰有權批准、批到多少
    var isAuthority = false
    var stepRef: String = ""

    enum CodingKeys: String, CodingKey { case meta, text, isAuthority, stepRef }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        isAuthority = (try? c.decode(Bool.self, forKey: .isAuthority)) ?? false
        stepRef = (try? c.decode(String.self, forKey: .stepRef)) ?? ""
    }
}

enum RaidKind: String, Codable, CaseIterable {
    case decision, assumption, issue, risk, conflict
    var prefix: String {
        switch self {
        case .decision: "DEC"
        case .assumption: "ASM"
        case .issue: "ISS"
        case .risk: "RSK"
        case .conflict: "ISS"   // 說法衝突記成議題，兩邊的話都留著
        }
    }
    var title: String {
        switch self {
        case .decision: String(localized: "決定")
        case .assumption: String(localized: "假設")
        case .issue: String(localized: "議題")
        case .risk: String(localized: "風險")
        case .conflict: String(localized: "說法衝突")
        }
    }
    var icon: String {
        switch self {
        case .decision: "checkmark.seal"
        case .assumption: "lightbulb"
        case .issue: "exclamationmark.triangle"
        case .risk: "bolt.trianglebadge.exclamationmark"
        case .conflict: "arrow.left.arrow.right"
        }
    }
}

struct RaidFinding: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    var kind: RaidKind = .issue
    var text: String = ""
    /// 決定：誰說的（具名的人明確說了才算決定）
    var decidedBy: String = ""
    var owner: String = ""
    var due: String = ""

    enum CodingKeys: String, CodingKey { case meta, kind, text, decidedBy, owner, due }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        kind = (try? c.decode(RaidKind.self, forKey: .kind)) ?? .issue
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        decidedBy = (try? c.decode(String.self, forKey: .decidedBy)) ?? ""
        owner = (try? c.decode(String.self, forKey: .owner)) ?? ""
        due = (try? c.decode(String.self, forKey: .due)) ?? ""
    }
}

/// 停車場、範圍外、詞彙：只有文字和證據
struct NoteFinding: Codable, Hashable, Identifiable {
    var meta = WorkshopMeta()
    var id: String { meta.id }
    var text: String = ""
    /// 詞彙：客戶的說法
    var detail: String = ""

    enum CodingKeys: String, CodingKey { case meta, text, detail }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = (try? c.decode(WorkshopMeta.self, forKey: .meta)) ?? WorkshopMeta()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
    }
}

/// 會議最後有沒有把整理好的流程讀回給客戶、客戶有沒有同意
struct ReadBack: Codable, Hashable {
    enum Result: String, Codable { case agreed, partly, no, unknown }
    var done = false
    var result: Result = .unknown
    var time: String = ""
    var quote: String = ""

    enum CodingKeys: String, CodingKey { case done, result, time, quote }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        result = (try? c.decode(Result.self, forKey: .result)) ?? .unknown
        time = TimeFormat.clean((try? c.decode(String.self, forKey: .time)) ?? "")
        quote = (try? c.decode(String.self, forKey: .quote)) ?? ""
    }
}

struct WorkshopAnalysis: Codable, Equatable {
    var steps: [StepFinding] = []
    var questions: [QuestionFinding] = []
    var walkthrough: [WalkStep] = []
    var pains: [PainPoint] = []
    var requirements: [RequirementFinding] = []
    var rules: [RuleFinding] = []
    var raid: [RaidFinding] = []
    var parking: [NoteFinding] = []
    var outOfScope: [NoteFinding] = []
    var glossary: [NoteFinding] = []
    var readBack = ReadBack()
    /// 分析時根據的會議紀錄、準備內容（過期提示用）
    var basis: String = ""

    enum CodingKeys: String, CodingKey {
        case steps, questions, walkthrough, pains, requirements, rules, raid, parking, outOfScope, glossary, readBack, basis
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = (try? c.decode([StepFinding].self, forKey: .steps)) ?? []
        questions = (try? c.decode([QuestionFinding].self, forKey: .questions)) ?? []
        walkthrough = (try? c.decode([WalkStep].self, forKey: .walkthrough)) ?? []
        pains = (try? c.decode([PainPoint].self, forKey: .pains)) ?? []
        requirements = (try? c.decode([RequirementFinding].self, forKey: .requirements)) ?? []
        rules = (try? c.decode([RuleFinding].self, forKey: .rules)) ?? []
        raid = (try? c.decode([RaidFinding].self, forKey: .raid)) ?? []
        parking = (try? c.decode([NoteFinding].self, forKey: .parking)) ?? []
        outOfScope = (try? c.decode([NoteFinding].self, forKey: .outOfScope)) ?? []
        glossary = (try? c.decode([NoteFinding].self, forKey: .glossary)) ?? []
        readBack = (try? c.decode(ReadBack.self, forKey: .readBack)) ?? ReadBack()
        basis = (try? c.decode(String.self, forKey: .basis)) ?? ""
    }

    /// 所有項目的 meta，依序（確認數、統計用）
    var allMeta: [WorkshopMeta] {
        steps.map(\.meta) + questions.map(\.meta) + walkthrough.map(\.meta) + pains.map(\.meta) + requirements.map(\.meta)
            + rules.map(\.meta) + raid.map(\.meta) + parking.map(\.meta) + outOfScope.map(\.meta) + glossary.map(\.meta)
    }
    var isEmpty: Bool { allMeta.isEmpty }
    var confirmedCount: Int { allMeta.filter { $0.status == .confirmed }.count }
    var openCount: Int { allMeta.filter { $0.status == .unconfirmed }.count }

    /// 依 ID 改一項的 meta（確認、駁回、證據）；找不到不動
    mutating func updateMeta(_ id: String, _ change: (inout WorkshopMeta) -> Void) {
        func go<T>(_ list: inout [T], _ meta: WritableKeyPath<T, WorkshopMeta>) -> Bool {
            guard let k = list.firstIndex(where: { $0[keyPath: meta].id == id }) else { return false }
            change(&list[k][keyPath: meta]); return true
        }
        _ = go(&steps, \.meta) || go(&questions, \.meta) || go(&walkthrough, \.meta) || go(&pains, \.meta) || go(&requirements, \.meta)
            || go(&rules, \.meta) || go(&raid, \.meta) || go(&parking, \.meta) || go(&outOfScope, \.meta) || go(&glossary, \.meta)
    }

    /// 依 ID 改一項的主要文字（使用者手動改：記下改過，重新分析時保留）
    mutating func setText(_ id: String, _ text: String) {
        func go<T>(_ list: inout [T], _ meta: WritableKeyPath<T, WorkshopMeta>, _ text: WritableKeyPath<T, String>) -> Bool {
            guard let k = list.firstIndex(where: { $0[keyPath: meta].id == id }) else { return false }
            list[k][keyPath: text] = text_; list[k][keyPath: meta].edited = true; return true
        }
        let text_ = text
        _ = go(&steps, \.meta, \.note) || go(&questions, \.meta, \.answer) || go(&walkthrough, \.meta, \.label) || go(&pains, \.meta, \.text)
            || go(&requirements, \.meta, \.text) || go(&rules, \.meta, \.text) || go(&raid, \.meta, \.text) || go(&parking, \.meta, \.text)
            || go(&outOfScope, \.meta, \.text) || go(&glossary, \.meta, \.text)
    }

    /// 這一項的主要文字（編輯時帶入）
    func text(_ id: String) -> String? {
        if let s = steps.first(where: { $0.id == id }) { return s.note }
        if let q = questions.first(where: { $0.id == id }) { return q.answer }
        if let w = walkthrough.first(where: { $0.id == id }) { return w.label }
        if let p = pains.first(where: { $0.id == id }) { return p.text }
        if let r = requirements.first(where: { $0.id == id }) { return r.text }
        if let r = rules.first(where: { $0.id == id }) { return r.text }
        if let r = raid.first(where: { $0.id == id }) { return r.text }
        return (parking + outOfScope + glossary).first { $0.id == id }?.text
    }

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
    static func decode(_ json: String?) -> WorkshopAnalysis? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkshopAnalysis.self, from: data)
    }
}

/// workshop_plans 的一列
struct WorkshopRecord: Equatable {
    var plan: WorkshopPlan
    var analysis: WorkshopAnalysis?
    var provider: String = ""
    var model: String = ""
    var updatedAt: String = ""
    /// 版本 2：草稿加上驗證的結果；沒有草稿或還沒套用時 nil
    var revised: MeetingDiagrams.Diagram? = nil
}

/// 分析的工作要做什麼
struct WorkshopJob: Codable, Equatable {
    enum Mode: String, Codable { case analyze, draftFromText }
    var mode: Mode
    /// draftFromText：要整理成流程圖的文字（使用者貼的、讀進來的檔）
    var text: String? = nil
    var source: String? = nil
    /// 重新畫草稿：這次的意見
    var comment: String? = nil

    var json: String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
    static func decode(_ payload: String?) -> WorkshopJob? {
        payload.flatMap { try? JSONDecoder().decode(WorkshopJob.self, from: Data($0.utf8)) }
    }
}

// MARK: - 分析的規則、格式、提示詞

enum Workshop {
    /// 專案的編號：同一個資料夾裡的工作坊編號接下去（QST-001、QST-002…）
    static func id(_ prefix: String, _ n: Int) -> String { "\(prefix)-" + String(format: "%03d", n) }

    // MARK: 給整理工具的格式

    /// 一條證據的格式（放進每一項裡）
    private static let ev = #"{"type":"array","items":{"type":"object","additionalProperties":false,"required":["speaker","time","quote"],"properties":{"speaker":{"type":"string"},"time":{"type":"string"},"quote":{"type":"string"}}}}"#

    private static func obj(_ props: [(String, String)]) -> String {
        let body = props.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",")
        let req = props.map { "\"\($0.0)\"" }.joined(separator: ",")
        return #"{"type":"object","additionalProperties":false,"required":["#+req+#"],"properties":{"#+body+"}}"
    }
    private static let s = #"{"type":"string"}"#
    private static let b = #"{"type":"boolean"}"#
    private static func e(_ values: [String]) -> String { #"{"type":"string","enum":["#+values.map { "\"\($0)\"" }.joined(separator: ",")+"]}" }
    private static func arr(_ item: String) -> String { #"{"type":"array","items":"#+item+"}" }

    static let analysisSchema: String = {
        let step = obj([("nodeId", s), ("ref", s), ("verdict", e(StepVerdict.allCases.map(\.rawValue))), ("note", s), ("newLabel", s),
                        ("newLane", s), ("afterRef", s), ("evidence", ev)])
        let question = obj([("qid", s), ("text", s), ("stepRef", s), ("state", e(["answered", "partial", "notCovered"])), ("answer", s),
                            ("raisedInRoom", b), ("owner", s), ("due", s), ("evidence", ev)])
        let walk = obj([("ref", s), ("label", s), ("actor", s), ("systems", s), ("timing", s), ("branchFrom", s), ("frequency", s),
                        ("handoffNeeds", s), ("draftNodeId", s), ("evidence", ev)])
        let pain = obj([("text", s), ("stepRef", s), ("workaround", s), ("impact", s), ("evidence", ev)])
        let req = obj([("text", s), ("kind", e(RequirementKind.allCases.map(\.rawValue))), ("priority", s), ("stepRef", s),
                       ("fromPainIndex", #"{"type":"integer"}"#), ("evidence", ev)])
        let rule = obj([("text", s), ("isAuthority", b), ("stepRef", s), ("evidence", ev)])
        let raid = obj([("kind", e(RaidKind.allCases.map(\.rawValue))), ("text", s), ("decidedBy", s), ("owner", s), ("due", s), ("evidence", ev)])
        let note = obj([("text", s), ("detail", s), ("evidence", ev)])
        let readBack = obj([("done", b), ("result", e(["agreed", "partly", "no", "unknown"])), ("time", s), ("quote", s)])
        return obj([("steps", arr(step)), ("questions", arr(question)), ("walkthrough", arr(walk)), ("pains", arr(pain)),
                    ("requirements", arr(req)), ("rules", arr(rule)), ("raid", arr(raid)), ("parking", arr(note)),
                    ("outOfScope", arr(note)), ("glossary", arr(note)), ("readBack", readBack)])
    }()

    static let analysisFormat = LLMClient.OutputFormat(schema: analysisSchema, toolName: "save_workshop_analysis",
                                                       toolDescription: "Save the analysis of a requirements workshop")  // l10n-skip

    /// 讀文字整理出草稿流程用的格式：同畫圖
    static let draftFormat = Diagrams.drawFormat

    // MARK: 提示詞

    private static func languageRule(_ language: MeetingLanguage) -> String {
        let name = language.profile.outputName ?? language.profile.uiName.en
        return "Write every text value in \(name). Keep names of systems, files and people as written. Quotes stay exactly as spoken (do not translate or tidy them)."
    }

    static func analysisSystem(_ language: MeetingLanguage, purposes: [WorkshopPurpose]) -> String {
        let focus = purposes.isEmpty ? "all of the sections below" : purposes.map(\.rawValue).joined(separator: ", ")
        return """
        You are a senior business analyst reading the record of a requirements workshop with a client. You work to BABOK v3 and the \
        CBAF conventions: nothing you produce is a decision or a confirmed fact; everything is a candidate that the analyst will \
        confirm with the client. The analyst prepared the workshop for these purposes: \(focus). Fill every section that the \
        workshop actually covers and leave the rest as empty lists; never pad.

        Rules for EVERY item:
        1. evidence: one to three entries. speaker = the person who said it, as named in the transcript; time = mm:ss from the \
           transcript; quote = their words, copied exactly (short, under 25 words). An item with no evidence is not allowed: leave \
           it out.
        2. Use only what was said. Do not infer, complete or improve. If the client contradicted themselves or two people \
           disagreed, record both statements, do not choose.
        3. Step labels are VERB + OBJECT, 2 to 6 words ("Download claim owner files"). Refs follow the draft where one exists.

        Sections:
        - steps (only when a draft process was supplied): ONE entry for every step of the draft, in the same order, then any extra \
          steps the client added. nodeId = the draft node id (empty for added steps). verdict: "confirmed" the client said it is \
          done like this; "changed" order, role or parallelism differs (give newLabel / newLane / afterRef when known); "added" the \
          client described a step the draft does not have (nodeId empty, newLabel, newLane, afterRef = the ref it follows); \
          "notDone" nobody does this in practice; "disputed" clients disagree; "unclear" not discussed or not clear. Never mark a \
          step "confirmed" unless somebody actually spoke about it. note: one sentence on what the client said.
        - questions: ONE entry for every prepared question (qid = its id, text = as prepared), state answered / partial / \
          notCovered, answer = the answer in one or two sentences from the client's words (empty when notCovered). Questions that \
          were raised in the room and not prepared: qid "", raisedInRoom true. For partial or not covered, owner and due only when \
          somebody was named or a date was given, else empty.
        - walkthrough: when the client walked through how they work: the happy path first, in order, one entry per business task \
          (not click-by-click); then each exception as its own entry with branchFrom = the ref of the step it splits from and \
          frequency as the client said it ("about 1 in 10"). actor = who does it. systems = tools and side spreadsheets named. \
          timing = duration, volume, how often, as said. handoffNeeds = what the next person needs from this step, only when said. \
          draftNodeId = the draft step it corresponds to, when one does.
        - pains: each pain point tied to a step (stepRef). workaround = what the client does today to cope (workarounds are the \
          richest finding: always capture them). impact = time, cost or error figures only when stated.
        - requirements: things the client needs. kind per the enum. priority ONLY when the client themselves said how important it \
          is (use their words); otherwise empty. When a requirement comes from a workaround, set fromPainIndex to the 0-based \
          index of that pain in the pains list, else -1.
        - rules: business-rule candidates (isAuthority false) and authority limits / who may approve what (isAuthority true), \
          each with the evidence of who stated it.
        - raid: decision only when a NAMED person explicitly decided something in the room (decidedBy = that person); assumption, \
          issue, risk as raised; conflict when people disagreed (text states both positions with their names). owner and due only \
          when given.
        - parking: topics set aside for later. outOfScope: topics the client or analyst excluded. glossary: client terms and \
          abbreviations with their meaning (text = term, detail = meaning).
        - readBack: done true only if the analyst read the process back to the client near the end; result agreed / partly / no \
          according to the client's reaction; quote the reaction.

        \(languageRule(language))
        """
    }

    /// 草稿流程給整理工具看的文字（步驟、判斷、連線）
    static func draftText(_ d: MeetingDiagrams.Diagram) -> String {
        var lines = ["Draft process: \(d.title)"]
        for n in d.nodes {
            lines.append("- node \(n.id) | ref \(n.ref.isEmpty ? "-" : n.ref) | \(n.shape.rawValue) | \(n.label)"
                         + (n.lane.isEmpty ? "" : " | lane: \(n.lane)") + (n.detail.isEmpty ? "" : " | \(n.detail)"))
        }
        for e in d.edges { lines.append("- \(e.from) -> \(e.to)" + (e.label.isEmpty ? "" : " [\(e.label)]")) }
        return lines.joined(separator: "\n")
    }

    static func analysisPrompt(meeting: Meeting, plan: WorkshopPlan, notes: MeetingNotes?, segments: [Segment], speakers: [Int: String],
                               limit: Int = 60_000) -> String {
        var lines = ["Workshop: \(meeting.displayTitle)", "Date: \(meeting.meetingDate)", ""]
        if !plan.trigger.isEmpty || !plan.endPoint.isEmpty || !plan.owner.isEmpty {
            lines.append("Process scope: starts when \(plan.trigger.isEmpty ? "(not stated)" : plan.trigger); ends with \(plan.endPoint.isEmpty ? "(not stated)" : plan.endPoint)."
                         + (plan.owner.isEmpty ? "" : " Process owner: \(plan.owner)."))
            lines.append("")
        }
        if let draft = plan.draft, plan.hasDraft { lines += [draftText(draft), ""] }
        if !plan.questions.isEmpty {
            lines.append("Prepared questions:")
            lines += plan.questions.map { "- \($0.id): \($0.text)" + ($0.stepRef.isEmpty ? "" : " (about step \($0.stepRef))") + ($0.ask.isEmpty ? "" : " [ask: \($0.ask)]") }
            lines.append("")
        }
        if let notes, !notes.isEmpty { lines += ["Meeting notes (JSON):", notes.jsonString(), ""] }
        lines.append("Transcript ([time] speaker: text):")
        var size = lines.reduce(0) { $0 + $1.count }
        let language = meeting.meetingLanguage
        for s in segments {
            let speaker = s.speaker.map { (speakers[$0] ?? language.defaultSpeaker($0)) + ": " } ?? ""
            let line = "[\(TimeFormat.string(s.start))] \(speaker)\(s.text)"
            size += line.count
            if size > limit { lines.append("[…]"); break }
            lines.append(line)
        }
        lines += ["", "Return the workshop analysis."]
        return lines.joined(separator: "\n")
    }

    static func draftSystem(_ language: MeetingLanguage) -> String {
        """
        You are a senior business analyst. The user pasted or imported a description of a process (notes, an email, a document). \
        Turn it into a draft process diagram that they will validate with the client. Give the structure only (kind, title, \
        caption, nodes, edges); KelNote lays it out.

        Rules: use a swimlane when two or more roles are named, else a flowchart. Step labels are VERB + OBJECT, 2 to 6 words. \
        Decisions are questions with labelled exits. Every step and decision has a ref in reading order (1, 2, 3…; parallel work 2a, \
        2b). At most 9 nodes and 12 edges: merge steps that always happen together. Use only what the text says; do not invent steps. \
        time is always "". focal is false. direction "across" when the process has parallel branches or more than 6 steps, else "down".
        \(languageRule(language))
        """
    }

    /// 草稿加上驗證結果＝版本 2：確認的不動、要改的改、新增的插進去、沒做的拿掉；有變化的框標成重點（藍色），最多 2 個以外的不標
    /// 變化記在 changes（給畫面和 Word 的「與草稿的差異」用）
    struct Revision {
        var diagram: MeetingDiagrams.Diagram
        var changes: [Change]
        struct Change: Hashable {
            var ref: String
            var verdict: StepVerdict
            var label: String
            var detail: String
        }
    }

    static func revise(_ draft: MeetingDiagrams.Diagram, with steps: [StepFinding]) -> Revision? {
        var d = draft
        var changes: [Revision.Change] = []
        let live = steps.filter { $0.meta.status != .rejected }
        var removed = Set<String>()
        for f in live {
            guard let k = d.nodes.firstIndex(where: { $0.id == f.nodeId }), f.verdict != .added else { continue }
            let old = d.nodes[k]
            switch f.verdict {
            case .changed:
                if !f.newLabel.isEmpty { d.nodes[k].label = f.newLabel }
                if d.kind == .swimlane, !f.newLane.isEmpty { d.nodes[k].lane = f.newLane }
                changes.append(.init(ref: old.ref, verdict: .changed, label: old.label, detail: f.note))
            case .notDone:
                removed.insert(old.id)
                changes.append(.init(ref: old.ref, verdict: .notDone, label: old.label, detail: f.note))
            case .disputed:
                changes.append(.init(ref: old.ref, verdict: .disputed, label: old.label, detail: f.note))
            default: break
            }
        }
        // 拿掉的步驟：前後接起來（進來的線接到出去的線）
        for id in removed {
            let incoming = d.edges.filter { $0.to == id && !removed.contains($0.from) }
            let outgoing = d.edges.filter { $0.from == id && !removed.contains($0.to) }
            d.edges.removeAll { $0.from == id || $0.to == id }
            for i in incoming { for o in outgoing where !d.edges.contains(where: { $0.from == i.from && $0.to == o.to }) {
                d.edges.append(.init(from: i.from, to: o.to, label: i.label, dashed: false))
            } }
            d.nodes.removeAll { $0.id == id }
        }
        // 新增的步驟：接在 afterRef 後面（插在那一步和它原本的下一步中間）
        var counter = 0
        for f in live where f.verdict == .added && !f.newLabel.isEmpty {
            counter += 1
            let nid = "w\(counter)"
            let after = d.nodes.first { !$0.ref.isEmpty && $0.ref == f.afterRef }
            var node = MeetingDiagrams.Node(id: nid, label: f.newLabel, detail: "", shape: .step,
                                            lane: d.kind == .swimlane ? (f.newLane.isEmpty ? (after?.lane ?? d.nodes.first?.lane ?? "") : f.newLane) : "",
                                            focal: false, time: "")
            node.ref = f.ref.isEmpty ? (after.map { Workshop.nextRef(after: $0.ref, existing: d.nodes.map(\.ref)) } ?? "") : f.ref
            if let after, let ai = d.nodes.firstIndex(where: { $0.id == after.id }) {
                d.nodes.insert(node, at: ai + 1)
                let outs = d.edges.filter { $0.from == after.id }
                if let first = outs.first {
                    d.edges.removeAll { $0.from == after.id && $0.to == first.to }
                    d.edges.append(.init(from: after.id, to: nid, label: first.label, dashed: false))
                    d.edges.append(.init(from: nid, to: first.to, label: "", dashed: false))
                } else {
                    d.edges.append(.init(from: after.id, to: nid, label: "", dashed: false))
                }
            } else {
                // 不知道接在哪：放在結束之前
                let endIndex = d.nodes.lastIndex { $0.shape == .end } ?? d.nodes.count
                d.nodes.insert(node, at: endIndex)
                if let prev = d.nodes[..<endIndex].last(where: { $0.id != nid }) {
                    d.edges.append(.init(from: prev.id, to: nid, label: "", dashed: false))
                }
            }
            changes.append(.init(ref: node.ref, verdict: .added, label: f.newLabel, detail: f.note))
        }
        guard !changes.isEmpty else { return nil }
        // 有變化的框標成重點（版本 2 看得出改了哪裡）：最多 Diagrams.maxFocal 個，其他靠文字清單
        let changedLabels = Set(changes.filter { $0.verdict == .changed || $0.verdict == .added }.map(\.label))
        var marked = 0
        for i in d.nodes.indices {
            let hit = changedLabels.contains(d.nodes[i].label) || d.nodes[i].id.hasPrefix("w")
            d.nodes[i].focal = hit && marked < Diagrams.maxFocal * 3
            if d.nodes[i].focal { marked += 1 }
        }
        d.caption = String(localized: "版本 2：依工作坊的驗證結果修改；藍色的是改過或新增的步驟")
        d.id = draft.id
        d.nodes = Array(d.nodes.prefix(Diagrams.maxNodes + 3))
        return Revision(diagram: d, changes: changes)
    }

    /// 2 後面插一步 → 2.1（已經有就 2.2…），避免跟後面的編號撞
    static func nextRef(after ref: String, existing: [String]) -> String {
        guard !ref.isEmpty else { return "" }
        var k = 1
        while existing.contains("\(ref).\(k)") { k += 1 }
        return "\(ref).\(k)"
    }
}

// MARK: - 分析結果收進來：編號、補證據、過濾

extension Workshop {
    /// 整理工具的答案（還沒有 ID、狀態）
    struct Raw: Decodable {
        struct Ev: Decodable { var speaker: String?; var time: String?; var quote: String? }
        struct Step: Decodable { var nodeId: String?; var ref: String?; var verdict: String?; var note: String?; var newLabel: String?
            var newLane: String?; var afterRef: String?; var evidence: [Ev]? }
        struct Question: Decodable { var qid: String?; var text: String?; var stepRef: String?; var state: String?; var answer: String?
            var raisedInRoom: Bool?; var owner: String?; var due: String?; var evidence: [Ev]? }
        struct Walk: Decodable { var ref: String?; var label: String?; var actor: String?; var systems: String?; var timing: String?
            var branchFrom: String?; var frequency: String?; var handoffNeeds: String?; var draftNodeId: String?; var evidence: [Ev]? }
        struct Pain: Decodable { var text: String?; var stepRef: String?; var workaround: String?; var impact: String?; var evidence: [Ev]? }
        struct Req: Decodable { var text: String?; var kind: String?; var priority: String?; var stepRef: String?; var fromPainIndex: Int?; var evidence: [Ev]? }
        struct Rule: Decodable { var text: String?; var isAuthority: Bool?; var stepRef: String?; var evidence: [Ev]? }
        struct Raid: Decodable { var kind: String?; var text: String?; var decidedBy: String?; var owner: String?; var due: String?; var evidence: [Ev]? }
        struct Note: Decodable { var text: String?; var detail: String?; var evidence: [Ev]? }
        struct Back: Decodable { var done: Bool?; var result: String?; var time: String?; var quote: String? }
        var steps: [Step]?; var questions: [Question]?; var walkthrough: [Walk]?; var pains: [Pain]?; var requirements: [Req]?
        var rules: [Rule]?; var raid: [Raid]?; var parking: [Note]?; var outOfScope: [Note]?; var glossary: [Note]?; var readBack: Back?
    }

    private static func clean(_ s: String?) -> String { Diagrams.clean(s ?? "") }

    private static func evidence(_ list: [Raw.Ev]?) -> [WorkshopEvidence] {
        (list ?? []).prefix(3).compactMap { e in
            let quote = clean(e.quote)
            guard !quote.isEmpty else { return nil }
            return WorkshopEvidence(speaker: clean(e.speaker), time: e.time ?? "", quote: String(quote.prefix(300)))
        }
    }

    /// 整理工具的答案變成有 ID、有證據的項目。
    /// - 沒有證據的項目拿掉（CBAF：每個痛點都要有證據），但草稿的每一步、準備的每一題一定留著（沒討論到就標沒討論到）
    /// - ID 從專案目前的編號接下去（counters 會更新）
    /// - 使用者之前確認過、改過的項目：文字相同的沿用它的 ID、狀態和編輯（重新分析不會洗掉使用者的確認）
    static func build(_ raw: Raw, plan: WorkshopPlan, previous: WorkshopAnalysis?, counters: inout [String: Int]) -> WorkshopAnalysis {
        var out = WorkshopAnalysis()
        func next(_ prefix: String) -> String {
            counters[prefix, default: 0] += 1
            return id(prefix, counters[prefix]!)
        }
        func meta(_ prefix: String, _ evidence: [Raw.Ev]?, reuse: WorkshopMeta?) -> WorkshopMeta? {
            if var old = reuse { old.evidence = Self.evidence(evidence).isEmpty ? old.evidence : Self.evidence(evidence); return old }
            let list = Self.evidence(evidence)
            guard !list.isEmpty else { return nil }
            return WorkshopMeta(id: next(prefix), status: .unconfirmed, evidence: list)
        }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

        // 草稿的每一步一定有一條
        if let draft = plan.draft, plan.hasDraft {
            let byNode = Dictionary((raw.steps ?? []).compactMap { s in s.nodeId.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
            for n in draft.nodes where n.shape == .step || n.shape == .decision {
                let r = byNode[n.id]
                let old = previous?.steps.first { $0.nodeId == n.id }
                var f = StepFinding()
                f.nodeId = n.id; f.ref = n.ref; f.label = n.label
                if let old, old.meta.edited || old.meta.status != .unconfirmed { f = old; out.steps.append(f); continue }
                f.verdict = r.flatMap { StepVerdict(rawValue: $0.verdict ?? "") } ?? .unclear
                if f.verdict == .added { f.verdict = .unclear }
                f.note = clean(r?.note)
                f.newLabel = clean(r?.newLabel); f.newLane = clean(r?.newLane)
                let ev = evidence(r?.evidence)
                // 沒有證據就不能說確認、要改、沒做：退回「沒討論到」
                if ev.isEmpty && f.verdict != .unclear { f.verdict = .unclear; f.note = ""; f.newLabel = ""; f.newLane = "" }
                f.meta = WorkshopMeta(id: old?.meta.id ?? next("STP"), status: .unconfirmed, evidence: ev)
                out.steps.append(f)
            }
            // 客戶加的新步驟
            for r in raw.steps ?? [] where StepVerdict(rawValue: r.verdict ?? "") == .added && !clean(r.newLabel).isEmpty {
                let ev = evidence(r.evidence)
                guard !ev.isEmpty else { continue }
                var f = StepFinding()
                f.verdict = .added; f.label = clean(r.newLabel); f.newLabel = clean(r.newLabel); f.newLane = clean(r.newLane)
                f.afterRef = clean(r.afterRef); f.note = clean(r.note)
                let old = previous?.steps.first { $0.verdict == .added && norm($0.newLabel) == norm(f.newLabel) }
                if let old, old.meta.edited || old.meta.status != .unconfirmed { out.steps.append(old); continue }
                f.meta = WorkshopMeta(id: old?.meta.id ?? next("STP"), status: .unconfirmed, evidence: ev)
                out.steps.append(f)
            }
        }
        // 準備的每一題一定有一條
        let rawQ = raw.questions ?? []
        for q in plan.questions {
            let r = rawQ.first { clean($0.qid) == q.id }
            let old = previous?.questions.first { $0.meta.id == q.id }
            if let old, old.meta.edited || old.meta.status != .unconfirmed { out.questions.append(old); continue }
            var f = QuestionFinding()
            f.text = q.text; f.stepRef = q.stepRef
            f.state = r.flatMap { AnswerState(rawValue: $0.state ?? "") } ?? .notCovered
            f.answer = clean(r?.answer)
            f.owner = clean(r?.owner); f.due = clean(r?.due)
            let ev = evidence(r?.evidence)
            if ev.isEmpty && f.state != .notCovered { f.state = .notCovered; f.answer = "" }
            f.meta = WorkshopMeta(id: q.id, status: .unconfirmed, evidence: ev)
            out.questions.append(f)
        }
        // 現場提出來的問題：接在專案的 QST- 編號後面
        for r in rawQ where clean(r.qid).isEmpty || !plan.questions.contains(where: { $0.id == clean(r.qid) }) {
            let text = clean(r.text)
            guard !text.isEmpty else { continue }
            let reuse = previous?.questions.first { $0.raisedInRoom && norm($0.text) == norm(text) }
            var f = QuestionFinding()
            f.text = text; f.stepRef = clean(r.stepRef); f.raisedInRoom = true
            f.state = AnswerState(rawValue: r.state ?? "") ?? .notCovered
            f.answer = clean(r.answer); f.owner = clean(r.owner); f.due = clean(r.due)
            if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { out.questions.append(reuse); continue }
            guard let m = meta("QST", r.evidence, reuse: reuse?.meta) else { continue }
            f.meta = m
            out.questions.append(f)
        }
        // 流程的步驟：主線先、例外跟在分出去的那一步後面
        var seenRefs = Set<String>()
        for r in raw.walkthrough ?? [] {
            var f = WalkStep()
            f.label = clean(r.label); f.ref = clean(r.ref); f.actor = clean(r.actor); f.systems = clean(r.systems)
            f.timing = clean(r.timing); f.branchFrom = clean(r.branchFrom); f.frequency = clean(r.frequency)
            f.handoffNeeds = clean(r.handoffNeeds); f.draftNodeId = clean(r.draftNodeId)
            guard !f.label.isEmpty else { continue }
            if !f.ref.isEmpty, !seenRefs.insert(f.ref).inserted { f.ref = "" }
            let reuse = previous?.walkthrough.first { norm($0.label) == norm(f.label) }
            if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { out.walkthrough.append(reuse); continue }
            guard let m = meta("PRC", r.evidence, reuse: reuse?.meta) else { continue }
            f.meta = m
            out.walkthrough.append(f)
        }
        out.walkthrough = ordered(out.walkthrough)
        // 痛點
        var painIds: [Int: String] = [:]
        for (k, r) in (raw.pains ?? []).enumerated() {
            var f = PainPoint()
            f.text = clean(r.text); f.stepRef = clean(r.stepRef); f.workaround = clean(r.workaround); f.impact = clean(r.impact)
            guard !f.text.isEmpty else { continue }
            let reuse = previous?.pains.first { norm($0.text) == norm(f.text) }
            if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { out.pains.append(reuse); painIds[k] = reuse.meta.id; continue }
            guard let m = meta("PNP", r.evidence, reuse: reuse?.meta) else { continue }
            f.meta = m
            painIds[k] = m.id
            out.pains.append(f)
        }
        for r in raw.requirements ?? [] {
            var f = RequirementFinding()
            f.text = clean(r.text); f.kind = RequirementKind(rawValue: r.kind ?? "") ?? .functional
            f.priority = clean(r.priority); f.stepRef = clean(r.stepRef)
            f.fromWorkaround = r.fromPainIndex.flatMap { painIds[$0] } ?? ""
            guard !f.text.isEmpty else { continue }
            let reuse = previous?.requirements.first { norm($0.text) == norm(f.text) }
            if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { out.requirements.append(reuse); continue }
            guard let m = meta("REQ", r.evidence, reuse: reuse?.meta) else { continue }
            f.meta = m
            out.requirements.append(f)
        }
        for r in raw.rules ?? [] {
            var f = RuleFinding()
            f.text = clean(r.text); f.isAuthority = r.isAuthority ?? false; f.stepRef = clean(r.stepRef)
            guard !f.text.isEmpty else { continue }
            let reuse = previous?.rules.first { norm($0.text) == norm(f.text) }
            if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { out.rules.append(reuse); continue }
            guard let m = meta(f.isAuthority ? "AUTH" : "RUL", r.evidence, reuse: reuse?.meta) else { continue }
            f.meta = m
            out.rules.append(f)
        }
        for r in raw.raid ?? [] {
            var f = RaidFinding()
            f.kind = RaidKind(rawValue: r.kind ?? "") ?? .issue
            f.text = clean(r.text); f.decidedBy = clean(r.decidedBy); f.owner = clean(r.owner); f.due = clean(r.due)
            guard !f.text.isEmpty else { continue }
            // 決定要有具名的人明確說了：沒有人名就降成議題
            if f.kind == .decision && f.decidedBy.isEmpty { f.kind = .issue }
            let reuse = previous?.raid.first { norm($0.text) == norm(f.text) }
            if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { out.raid.append(reuse); continue }
            guard let m = meta(f.kind.prefix, r.evidence, reuse: reuse?.meta) else { continue }
            f.meta = m
            out.raid.append(f)
        }
        func notes(_ list: [Raw.Note]?, prefix: String, old: [NoteFinding]?) -> [NoteFinding] {
            (list ?? []).compactMap { r in
                var f = NoteFinding()
                f.text = clean(r.text); f.detail = clean(r.detail)
                guard !f.text.isEmpty else { return nil }
                let reuse = old?.first { norm($0.text) == norm(f.text) }
                if let reuse, reuse.meta.edited || reuse.meta.status != .unconfirmed { return reuse }
                guard let m = meta(prefix, r.evidence, reuse: reuse?.meta) else { return nil }
                f.meta = m
                return f
            }
        }
        out.parking = notes(raw.parking, prefix: "PRK", old: previous?.parking)
        out.outOfScope = notes(raw.outOfScope, prefix: "OOS", old: previous?.outOfScope)
        out.glossary = notes(raw.glossary, prefix: "GLO", old: previous?.glossary)
        if let b = raw.readBack {
            out.readBack = ReadBack()
            out.readBack.done = b.done ?? false
            out.readBack.result = ReadBack.Result(rawValue: b.result ?? "") ?? .unknown
            out.readBack.time = TimeFormat.clean(b.time ?? "")
            out.readBack.quote = clean(b.quote)
            if !out.readBack.done { out.readBack.result = .unknown }
        }
        return out
    }

    /// 流程步驟的順序：主線照原本順序，例外放在分出去的那一步後面
    static func ordered(_ steps: [WalkStep]) -> [WalkStep] {
        let main = steps.filter { $0.branchFrom.isEmpty }
        var out: [WalkStep] = []
        for s in main {
            out.append(s)
            if !s.ref.isEmpty { out += steps.filter { $0.branchFrom == s.ref && $0.meta.id != s.meta.id } }
        }
        // 找不到起點的例外放最後
        for s in steps where !out.contains(where: { $0.meta.id == s.meta.id }) { out.append(s) }
        return out
    }

    /// 重新分析之前的分析根據的內容：草稿、問題、會議紀錄（過期提示用）
    static func basisKey(plan: WorkshopPlan, notes: MeetingNotes?) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let text = plan.jsonString() + (notes.map(Diagrams.notesKey) ?? "")
        for byte in text.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// 專案的編號範圍：同一個資料夾（含底下的子資料夾）的工作坊接著編；沒有資料夾的各自編
    static func scopeFolder(_ meeting: Meeting) -> String { FolderPath.account(meeting.folder) }

    /// 準備的問題一次加進來：一行一題，「1.」「-」「•」「Q1:」這類開頭去掉；空行、重複的略過
    static func parseQuestions(_ text: String) -> [String] {
        let pattern = try! Regex(#"^\s*(?:[-*•·▪◦]|\(?[0-9]{1,3}[.)、:]|Q[0-9]{1,3}[.:)、]?)\s*"#)  // l10n-skip
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap { line in
            var t = line.trimmingCharacters(in: .whitespaces)
            while let m = try? pattern.prefixMatch(in: t), !m.0.isEmpty { t = String(t[m.range.upperBound...]).trimmingCharacters(in: .whitespaces) }
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { return nil }
            return t
        }
    }
}

// MARK: - 資料庫

extension AppDatabase {
    func workshop(_ meetingId: Int64) throws -> WorkshopRecord? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM workshop_plans WHERE meeting_id = ?", arguments: [meetingId]) else { return nil }
            return WorkshopRecord(plan: WorkshopPlan.decode(row["plan"]) ?? WorkshopPlan(),
                                  analysis: WorkshopAnalysis.decode(row["analysis"]),
                                  provider: row["provider"], model: row["model"], updatedAt: row["updated_at"],
                                  revised: MeetingDiagrams.decode(row["revised"])?.diagrams.first)
        }
    }

    func saveWorkshop(_ meetingId: Int64, _ record: WorkshopRecord) throws {
        let revised = record.revised.map { MeetingDiagrams(diagrams: [$0]).jsonString() }
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO workshop_plans (meeting_id, plan, analysis, provider, model, updated_at, revised)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(meeting_id) DO UPDATE SET plan = excluded.plan, analysis = excluded.analysis, provider = excluded.provider,
                  model = excluded.model, updated_at = excluded.updated_at, revised = excluded.revised
                """, arguments: [meetingId, record.plan.jsonString(), record.analysis?.jsonString(), record.provider, record.model,
                                 Clock.now(), revised])
        }
    }

    /// 讀出來改了再存回去（使用者的操作）
    func updateWorkshop(_ meetingId: Int64, _ change: (inout WorkshopRecord) -> Void) throws {
        var record = try workshop(meetingId) ?? WorkshopRecord(plan: WorkshopPlan(), analysis: nil)
        change(&record)
        try saveWorkshop(meetingId, record)
    }

    /// 專案裡下一個編號：同一個資料夾（帳戶）的所有工作坊，各種前綴各自數
    func workshopCounters(scope: String, excluding meetingId: Int64) throws -> [String: Int] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.analysis, w.plan, m.folder FROM workshop_plans w JOIN meetings m ON m.id = w.meeting_id
                WHERE w.meeting_id != ? AND m.deleted_at IS NULL
                """, arguments: [meetingId])
            var counters: [String: Int] = [:]
            func see(_ id: String) {
                let parts = id.split(separator: "-")
                guard parts.count == 2, let n = Int(parts[1]) else { return }
                counters[String(parts[0]), default: 0] = max(counters[String(parts[0])] ?? 0, n)
            }
            for row in rows {
                guard FolderPath.account(row["folder"] as String? ?? "") == scope else { continue }
                if let a = WorkshopAnalysis.decode(row["analysis"]) { a.allMeta.forEach { see($0.id) } }
                WorkshopPlan.decode(row["plan"])?.questions.forEach { see($0.id) }
            }
            return counters
        }
    }

    func deleteWorkshop(_ meetingId: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM workshop_plans WHERE meeting_id = ?", arguments: [meetingId]) }
    }

    func activeWorkshopJobs(_ meetingId: Int64) throws -> [WorkshopJob] {
        try pool.read { db in
            try String.fetchAll(db, sql: "SELECT payload FROM jobs WHERE kind = 'workshop' AND status IN ('queued', 'running') AND meeting_id = ? ORDER BY id",
                                arguments: [meetingId])
        }.compactMap { WorkshopJob.decode($0) }
    }
}
