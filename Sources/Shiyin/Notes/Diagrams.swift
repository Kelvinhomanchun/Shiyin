import Foundation
import GRDB

/// 會議紀錄的圖（fork）：會議裡講了流程、步驟、交接時，整理完另外請整理工具判斷要不要畫圖、畫什麼圖，
/// 給的是結構（類型、節點、連線），排版和畫法由 KelNote 自己來（IBM 的配色、直角的連線），不用整理工具給的座標。
/// 選圖的規則參考 diagram-design（MIT，github.com/cathrynlavery/diagram-design）：會比一段文字、表格更清楚才畫；
/// 一張最多 9 個節點、12 條連線，重點（藍色）最多 2 個；超過就拆成兩張
struct MeetingDiagrams: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        /// 有判斷、分支的流程
        case flowchart
        /// 照順序的步驟（3～7 步）
        case steps
        /// 跨部門、跨角色的流程，每一條道是一個角色
        case swimlane
        /// 系統、資料之間的流向
        case dataFlow
        /// 時間上的事件、階段
        case timeline
    }

    enum Shape: String, Codable { case step, decision, start, end, data, system }

    struct Node: Codable, Hashable {
        var id: String
        var label: String
        /// 補充一行（檔案名、系統、多久）；可以空白
        var detail: String
        var shape: Shape
        /// swimlane 的道名；其他類型空白
        var lane: String
        /// 重點（最多 2 個）：例如瓶頸、要改的那一步
        var focal: Bool
        /// 逐字稿的時間點 mm:ss，點了播放
        var time: String
        /// 步驟的編號（1、2、3a、3b…），印在框的上面；開始、結束、資料、系統不編號（使用者要的：每一步有 ID）
        var ref: String = ""

        enum CodingKeys: String, CodingKey { case id, label, detail, shape, lane, focal, time, ref }

        init(id: String, label: String, detail: String, shape: Shape, lane: String, focal: Bool, time: String, ref: String = "") {
            self.id = id; self.label = label; self.detail = detail; self.shape = shape; self.lane = lane; self.focal = focal
            self.time = time; self.ref = ref
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            label = try c.decode(String.self, forKey: .label)
            detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
            shape = (try? c.decode(Shape.self, forKey: .shape)) ?? .step
            lane = (try? c.decode(String.self, forKey: .lane)) ?? ""
            focal = (try? c.decode(Bool.self, forKey: .focal)) ?? false
            time = (try? c.decode(String.self, forKey: .time)) ?? ""
            ref = (try? c.decode(String.self, forKey: .ref)) ?? ""
        }
    }

    struct Edge: Codable, Hashable {
        var from: String
        var to: String
        /// 連線上的字（判斷的「是」「否」、交出去的東西）；可以空白，最多 14 個字元
        var label: String
        /// 虛線：選擇性、之後才做、回傳
        var dashed: Bool

        enum CodingKeys: String, CodingKey { case from, to, label, dashed }

        init(from: String, to: String, label: String, dashed: Bool) { self.from = from; self.to = to; self.label = label; self.dashed = dashed }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            from = try c.decode(String.self, forKey: .from)
            to = try c.decode(String.self, forKey: .to)
            label = (try? c.decode(String.self, forKey: .label)) ?? ""
            dashed = (try? c.decode(Bool.self, forKey: .dashed)) ?? false
        }
    }

    struct Diagram: Codable, Hashable {
        var kind: Kind
        var title: String
        /// 一句話說這張圖在講什麼
        var caption: String
        var nodes: [Node]
        var edges: [Edge]
        /// 流程的方向：down 由上往下（預設）、across 由左往右（使用者要橫的時候）
        var direction: String = "down"
        var across: Bool { direction == "across" }
        // 以下 KelNote 自己記的，不是整理工具給的
        /// 這張圖的代號（重新畫、復原、移除用）
        var id: String = ""
        /// 使用者對這張圖說過的話，照順序；每次重新畫都一起給整理工具
        var comments: [String] = []
        /// 當初要畫什麼（建議的內容或使用者自己描述的）；移除時放回建議
        var request: Suggestion? = nil
        /// 畫的時候根據的那一版會議紀錄（Diagrams.notesKey）
        var notesKey: String = ""

        init(kind: Kind, title: String, caption: String, nodes: [Node], edges: [Edge]) {
            (self.kind, self.title, self.caption, self.nodes, self.edges) = (kind, title, caption, nodes, edges)
        }

        enum CodingKeys: String, CodingKey { case kind, title, caption, nodes, edges, direction, id, comments, request, notesKey }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(Kind.self, forKey: .kind)
            title = try c.decode(String.self, forKey: .title)
            caption = (try? c.decode(String.self, forKey: .caption)) ?? ""
            nodes = try c.decode([Node].self, forKey: .nodes)
            edges = (try? c.decode([Edge].self, forKey: .edges)) ?? []
            direction = (try? c.decode(String.self, forKey: .direction)) == "across" ? "across" : "down"
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            comments = (try? c.decode([String].self, forKey: .comments)) ?? []
            request = try? c.decode(Suggestion.self, forKey: .request)
            notesKey = (try? c.decode(String.self, forKey: .notesKey)) ?? ""
        }
    }

    /// 整理工具建議可以畫的一張圖：使用者決定要不要畫
    struct Suggestion: Codable, Hashable, Identifiable {
        var id: String = ""
        var kind: Kind
        var title: String
        /// 為什麼畫成圖比文字清楚、圖會讓人看懂什麼
        var why: String
        /// 會議紀錄裡的哪一段（引用或段落名稱）
        var focus: String
        /// 逐字稿裡講到的時間點
        var time: String
        /// 使用者自己描述的（「自己描述一張圖」）；整理工具建議的是空的
        var userRequest: String = ""

        enum CodingKeys: String, CodingKey { case id, kind, title, why, focus, time, userRequest }

        init(id: String = "", kind: Kind, title: String, why: String, focus: String, time: String, userRequest: String = "") {
            (self.id, self.kind, self.title, self.why, self.focus, self.time, self.userRequest) = (id, kind, title, why, focus, time, userRequest)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .flowchart
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            why = (try? c.decode(String.self, forKey: .why)) ?? ""
            focus = (try? c.decode(String.self, forKey: .focus)) ?? ""
            time = (try? c.decode(String.self, forKey: .time)) ?? ""
            userRequest = (try? c.decode(String.self, forKey: .userRequest)) ?? ""
        }
    }

    /// 整理工具建議的格式
    struct Suggestions: Codable { var suggestions: [Suggestion] }

    var diagrams: [Diagram]

    var isEmpty: Bool { diagrams.isEmpty }

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String?) -> MeetingDiagrams? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeetingDiagrams.self, from: data)
    }

    /// 整理工具給的結果整理一下：去掉空的節點、找不到兩端的連線、重複的連線；節點、連線、重點、道的數量限在規則以內。
    /// 剩不到 2 個節點的圖不要（一個框不算圖）
    func validated() -> MeetingDiagrams {
        var out: [Diagram] = []
        for var d in diagrams.prefix(Diagrams.maxDiagrams) {
            d.title = Diagrams.clean(d.title)
            d.caption = Diagrams.clean(d.caption)
            var seen = Set<String>()
            d.nodes = d.nodes.compactMap { n -> Node? in
                var n = n
                n.id = Diagrams.clean(n.id)
                n.label = Diagrams.clean(n.label)
                n.detail = Diagrams.clean(n.detail)
                n.lane = d.kind == .swimlane ? Diagrams.clean(n.lane) : ""
                n.time = TimeFormat.clean(n.time)
                n.ref = String(Diagrams.clean(n.ref).trimmingCharacters(in: CharacterSet(charactersIn: ".:)、 ")).prefix(6))  // l10n-skip
                if n.shape == .start || n.shape == .end { n.ref = "" }
                (n.ref, n.label) = Diagrams.splitRef(n.ref, n.label)
                guard !n.id.isEmpty, !n.label.isEmpty, seen.insert(n.id).inserted else { return nil }
                return n
            }
            d.nodes = Array(d.nodes.prefix(Diagrams.maxNodes))
            // 重點最多 2 個
            var focal = 0
            for i in d.nodes.indices where d.nodes[i].focal {
                focal += 1
                if focal > Diagrams.maxFocal { d.nodes[i].focal = false }
            }
            if d.kind == .swimlane {
                // 道最多 5 條，多的併到最後一條；沒寫道的放第一條
                var lanes: [String] = []
                for n in d.nodes where !n.lane.isEmpty && !lanes.contains(n.lane) { lanes.append(n.lane) }
                if lanes.isEmpty { d.kind = .flowchart }
                else {
                    let keep = Array(lanes.prefix(Diagrams.maxLanes))
                    for i in d.nodes.indices {
                        if d.nodes[i].lane.isEmpty { d.nodes[i].lane = keep[0] }
                        else if !keep.contains(d.nodes[i].lane) { d.nodes[i].lane = keep[keep.count - 1] }
                    }
                }
            }
            let ids = Set(d.nodes.map(\.id))
            var pairs = Set<String>()
            d.edges = d.edges.compactMap { e -> Edge? in
                var e = e
                e.from = Diagrams.clean(e.from)
                e.to = Diagrams.clean(e.to)
                e.label = String(Diagrams.clean(e.label).prefix(24))
                guard ids.contains(e.from), ids.contains(e.to), e.from != e.to, pairs.insert(e.from + "\u{1}" + e.to).inserted else { return nil }
                return e
            }
            d.edges = Array(d.edges.prefix(Diagrams.maxEdges))
            // 步驟、時間軸只照順序畫，連線不用
            if d.kind == .steps || d.kind == .timeline { d.edges = [] }
            guard d.nodes.count >= 2, !d.title.isEmpty else { continue }
            out.append(d)
        }
        return MeetingDiagrams(diagrams: out)
    }

    /// 每一個文字欄位都套用 transform（簡體）
    func mappingText(_ r: (String) -> String) -> MeetingDiagrams {
        MeetingDiagrams(diagrams: diagrams.map { d in
            var d = d
            d.title = r(d.title)
            d.caption = r(d.caption)
            d.nodes = d.nodes.map { var n = $0; n.label = r(n.label); n.detail = r(n.detail); n.lane = r(n.lane); n.ref = r(n.ref); return n }
            d.edges = d.edges.map { var e = $0; e.label = r(e.label); return e }
            d.comments = d.comments.map(r)
            return d
        })
    }
}

/// meeting_diagrams 的一列：畫好的圖、還沒決定的建議、每張圖之前的版本（復原用）
struct DiagramRecord: Equatable {
    var diagrams: MeetingDiagrams
    /// 舊版（一次畫好整組）時根據的會議紀錄；新的圖各自記在 Diagram.notesKey
    var notesKey: String
    var provider: String
    var model: String
    var updatedAt: String
    /// 整理工具建議、使用者還沒決定的圖
    var suggestions: [MeetingDiagrams.Suggestion] = []
    /// 請整理工具建議過（沒有建議時顯示「沒有適合畫成圖的」）
    var suggested = false
    /// 每張圖重新畫之前的版本（圖的 id → 由舊到新）
    var history: [String: [MeetingDiagrams.Diagram]] = [:]

    var isEmpty: Bool { diagrams.isEmpty && suggestions.isEmpty && !suggested }

    func diagram(_ id: String) -> MeetingDiagrams.Diagram? { diagrams.diagrams.first { $0.id == id } }

    /// 這張圖是不是依目前的會議紀錄畫的
    func isStale(_ d: MeetingDiagrams.Diagram, notes: MeetingNotes?) -> Bool {
        guard let notes else { return false }
        let key = d.notesKey.isEmpty ? notesKey : d.notesKey
        return !key.isEmpty && key != Diagrams.notesKey(notes)
    }
}

/// 畫圖的工作要做什麼（工作的 payload）
struct DiagramJob: Codable, Equatable {
    enum Mode: String, Codable { case suggest, draw, redraw }
    var mode: Mode
    /// draw：照這個建議（或使用者描述的）畫
    var suggestion: MeetingDiagrams.Suggestion? = nil
    /// redraw：哪一張、這次說了什麼
    var diagramId: String? = nil
    var comment: String? = nil

    var json: String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
    static func decode(_ payload: String?) -> DiagramJob? {
        payload.flatMap { try? JSONDecoder().decode(DiagramJob.self, from: Data($0.utf8)) }
    }
}

enum Diagrams {
    static let maxDiagrams = 2, maxNodes = 9, maxEdges = 12, maxFocal = 2, maxLanes = 5

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 「1a. Generate extracts」這種把編號寫在名稱裡的：編號拿出來當 ref、名稱只留動作（ref 已經有時只拿掉名稱裡重複的）
    static func splitRef(_ ref: String, _ label: String) -> (String, String) {
        let pattern = try! Regex(#"^\s*(?:Step\s*|步驟\s*)?([0-9]{1,2}[A-Za-z]?(?:\.[0-9]{1,2}[A-Za-z]?)?)\s*[.:)、]\s+(.+)$"#)  // l10n-skip
        guard let m = try? pattern.firstMatch(in: label), let r1 = m[1].substring, let r2 = m[2].substring else { return (ref, label) }
        let found = String(r1), rest = String(r2)
        if ref.isEmpty || ref.caseInsensitiveCompare(found) == .orderedSame { return (found, rest) }
        return (ref, label)
    }

    /// 會議紀錄內容的雜湊（FNV-1a）：圖是不是根據目前這一版紀錄畫的
    static func notesKey(_ notes: MeetingNotes) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in notes.jsonString().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: 給整理工具的格式和提示詞（給模型看的，不是介面文字）

    static let kindsEnum = MeetingDiagrams.Kind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")

    /// 一張圖（畫、重新畫）
    static let diagramSchema: String = {
        let node = #"{"type":"object","additionalProperties":false,"required":["id","ref","label","detail","shape","lane","focal","time"],"properties":{"id":{"type":"string"},"ref":{"type":"string"},"label":{"type":"string"},"detail":{"type":"string"},"shape":{"type":"string","enum":["step","decision","start","end","data","system"]},"lane":{"type":"string"},"focal":{"type":"boolean"},"time":{"type":"string"}}}"#
        let edge = #"{"type":"object","additionalProperties":false,"required":["from","to","label","dashed"],"properties":{"from":{"type":"string"},"to":{"type":"string"},"label":{"type":"string"},"dashed":{"type":"boolean"}}}"#
        return #"{"type":"object","additionalProperties":false,"required":["diagram"],"properties":{"diagram":{"type":"object","additionalProperties":false,"required":["kind","title","caption","direction","nodes","edges"],"properties":{"direction":{"type":"string","enum":["down","across"]},"kind":{"type":"string","enum":["#
            + kindsEnum + #"]},"title":{"type":"string"},"caption":{"type":"string"},"nodes":{"type":"array","items":"# + node
            + #"},"edges":{"type":"array","items":"# + edge + "}}}}}"
    }()

    /// 建議可以畫的圖（不畫）
    static let suggestSchema: String = {
        #"{"type":"object","additionalProperties":false,"required":["suggestions"],"properties":{"suggestions":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["kind","title","why","focus","time"],"properties":{"kind":{"type":"string","enum":["#
            + kindsEnum + #"]},"title":{"type":"string"},"why":{"type":"string"},"focus":{"type":"string"},"time":{"type":"string"}}}}}}"#
    }()

    static let drawFormat = LLMClient.OutputFormat(schema: diagramSchema, toolName: "save_diagram",
                                                   toolDescription: "Save one diagram that supplements the meeting notes")  // l10n-skip
    static let suggestFormat = LLMClient.OutputFormat(schema: suggestSchema, toolName: "save_diagram_suggestions",
                                                      toolDescription: "Save suggestions for diagrams that would supplement the meeting notes")  // l10n-skip

    private static let kindGuide = """
    - flowchart: a process with at least one real decision or branch. Begin with one start node (the trigger) and finish with \
      end node(s) (the outcome). A decision is a yes/no question (shape "decision", label ending in "?") and every exit is labelled \
      (Yes / No, or the condition). Parallel work that later joins is two branches, not a decision.
    - steps: a short ordered method with 3 to 7 stages and no branches; one node per stage, in order; no edges needed.
    - swimlane: a process that moves between 2 to 5 roles, teams or systems; set lane to the actor who does each step. A lane is \
      a real hand-off (someone who actually receives work), not a department named for completeness. The edges that cross lanes \
      are the hand-offs; label them with what is handed over.
    - dataFlow: where data comes from, what transforms it, and where it ends up (shape "data" for files or tables, "system" for \
      systems and tools, "step" for a transformation someone or something does).
    - timeline: events or phases in time order, e.g. a migration plan or a parallel run; one node per event, in order; no edges needed.
    """

    private static func languageRule(_ language: MeetingLanguage) -> String {
        let name = language.profile.outputName ?? language.profile.uiName.en
        return "Write every text value in \(name). Keep names of systems, files and people as written in the notes and transcript."
    }

    static func suggestSystem(_ language: MeetingLanguage) -> String {
        """
        You are an information designer. The user wants to supplement their meeting notes with diagrams, and decides which ones to \
        draw. Your job here is only to SUGGEST: point at the parts of the meeting that a diagram would explain better than the \
        written notes. Do not draw anything.

        Good candidates: a process or workflow someone walked through, operational steps, a hand-off between teams or systems, a \
        decision with branches, how data moves between systems, phases on a timeline. Status updates, opinions and lists of facts \
        are not good candidates. Suggest only what a reader would genuinely understand faster as a picture; an empty list is a fine \
        answer.

        Kinds:
        \(kindGuide)

        Rules:
        1. At most 4 suggestions, most useful first. Each covers a different part of the meeting; do not suggest two diagrams of \
           the same content.
        2. title: what the diagram would show, 3 to 8 words. why: one sentence, addressed to the user, on what the picture would \
           make clear that the text does not. focus: which part of the notes it covers (a section and a short quote or paraphrase). \
           time: where it is discussed in the transcript, mm:ss, or an empty string.
        3. Use only what the meeting says.
        4. \(languageRule(language))
        """
    }

    static func drawSystem(_ language: MeetingLanguage) -> String {
        """
        You are a senior business analyst and information designer who draws one process diagram to supplement meeting notes, \
        following BPMN-style process-modelling practice. KelNote lays it out and draws it; you give only the structure: kind, title, \
        caption, nodes and edges.

        Kinds:
        \(kindGuide)

        Rules:
        1. Draw exactly what the request asks for. If the user gave comments on an earlier version, follow every comment; the \
           latest comment wins when two disagree. Keep what the comments do not ask to change.
        2. Model how the work really happens as described in the meeting (the as-is), including manual workarounds. Do not mix in \
           a future or planned process unless the request asks for it; if it does, keep it clearly separate (its own branch or \
           lane, or say so in the caption).
        3. One level of detail across the whole diagram: business tasks done by one actor at one time (no click-by-click UI steps, \
           no whole departments as a single box). At most 9 nodes and 12 edges; merge steps that always happen together and leave \
           out steps that add nothing.
        4. Step labels are VERB + OBJECT in the imperative, 2 to 6 words: "Download claim owner files", "Append both extracts", \
           "Refresh Power BI model". Never a noun phrase ("Data download"), a system name alone, or a status. Decisions are \
           questions: "Cut-off gap found?". Start and end nodes name the trigger and the outcome ("Month-end reached", "Reports \
           sent"). Data and system nodes are nouns ("Claim owner file", "Power BI").
        5. ref: a step ID for every step and decision, in reading order: 1, 2, 3… Parallel branches that run side by side share \
           the number with a letter (2a, 2b) and rejoin at the next number. Start, end, data and system nodes have ref "". Do not \
           repeat the ID inside the label.
        6. detail: one short line of specifics from the meeting (file names, systems, who, how long, how often), or "". Never \
           invent detail; anything unclear stays out.
        7. Mark focal true on at most 2 nodes: the bottleneck, the riskiest manual step, or what the meeting decided to change.
        8. Edge labels are optional, at most 14 characters (Yes, No, Monthly, Excel file). Every exit of a decision is labelled. \
           dashed true for optional, later, return or asynchronous paths.
        9. time: when this step is discussed in the transcript, mm:ss (or h:mm:ss over an hour), else "". Times are shown on \
           screen only, never in exported files.
        10. ids are short and unique (n1, n2…); edges refer to ids, not refs.
        11. Use only what the meeting says, except facts the user states in a comment, which you follow as given.
        12. direction: "down" (top to bottom, the default) or "across" (left to right). Use "across" when the user asks for a \
            horizontal layout, or for a short process with parallel branches that reads better side by side. Steps and \
            timelines ignore it.
        13. title: a short name for the process, ideally verb + object or "<object> process"; caption: one sentence saying what it \
            shows, from which trigger to which outcome.
        14. \(languageRule(language))
        """
    }

    static func material(meeting: Meeting, notes: MeetingNotes, segments: [Segment], speakers: [Int: String], limit: Int = 60_000) -> [String] {
        var lines = ["Meeting: \(meeting.displayTitle)", "Date: \(meeting.meetingDate)", "", "Meeting notes (JSON):", notes.jsonString(), "",
                     "Transcript ([time] speaker: text):"]
        var size = lines.reduce(0) { $0 + $1.count }
        let language = meeting.meetingLanguage
        for s in segments {
            let speaker = s.speaker.map { (speakers[$0] ?? language.defaultSpeaker($0)) + ": " } ?? ""
            let line = "[\(TimeFormat.string(s.start))] \(speaker)\(s.text)"
            size += line.count
            if size > limit { lines.append("[…]"); break }
            lines.append(line)
        }
        return lines
    }

    static func suggestPrompt(_ material: [String], existing: [MeetingDiagrams.Diagram]) -> String {
        var lines = material
        if !existing.isEmpty {
            lines += ["", "Diagrams already drawn (do not suggest these again):"] + existing.map { "- \($0.kind.rawValue): \($0.title)" }
        }
        lines += ["", "Suggest which parts of this meeting would be clearer as a diagram (or return an empty list)."]
        return lines.joined(separator: "\n")
    }

    static func drawPrompt(_ material: [String], request: MeetingDiagrams.Suggestion?, current: MeetingDiagrams.Diagram?, comments: [String]) -> String {
        var lines = material + [""]
        if let request {
            if !request.userRequest.isEmpty {
                lines += ["The user asked for this diagram, in their words:", request.userRequest]
            } else {
                lines += ["Draw this diagram:", "Kind: \(request.kind.rawValue)", "Title: \(request.title)", "Why: \(request.why)",
                          "Covers: \(request.focus)" + (request.time.isEmpty ? "" : " (\(request.time))")]
            }
        }
        if let current {
            var shown = current
            shown.comments = []; shown.request = nil; shown.id = ""; shown.notesKey = ""
            lines += ["", "The current version of the diagram (JSON):", MeetingDiagrams(diagrams: [shown]).jsonString()]
        }
        if !comments.isEmpty {
            lines += ["", "The user's comments on the diagram, oldest first; apply all of them:"]
            lines += comments.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }
        lines += ["", current == nil ? "Return the diagram." : "Return the revised diagram."]
        return lines.joined(separator: "\n")
    }

    static func newId() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    /// 一張圖整理一下（同 validated，只看這一張）；不成圖（少於 2 個節點、沒標題）時 nil
    static func cleanDiagram(_ d: MeetingDiagrams.Diagram) -> MeetingDiagrams.Diagram? {
        MeetingDiagrams(diagrams: [d]).validated().diagrams.first
    }

    static func cleanSuggestions(_ list: [MeetingDiagrams.Suggestion]) -> [MeetingDiagrams.Suggestion] {
        var seen = Set<String>()
        return list.compactMap { s -> MeetingDiagrams.Suggestion? in
            var s = s
            s.title = clean(s.title); s.why = clean(s.why); s.focus = clean(s.focus); s.time = TimeFormat.clean(s.time)
            guard !s.title.isEmpty, seen.insert(s.title.lowercased()).inserted else { return nil }
            s.id = newId()
            return s
        }.prefix(4).map { $0 }
    }
}

extension AppDatabase {
    func diagramRecord(_ meetingId: Int64) throws -> DiagramRecord? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM meeting_diagrams WHERE meeting_id = ?", arguments: [meetingId]),
                  var diagrams = MeetingDiagrams.decode(row["diagrams"]) else { return nil }
            // 第一版自動畫的圖沒有 id：依順序給一個固定的（每次讀都一樣）
            for k in diagrams.diagrams.indices where diagrams.diagrams[k].id.isEmpty { diagrams.diagrams[k].id = "auto\(k)" }
            let suggestions = (row["suggestions"] as String?).flatMap { try? JSONDecoder().decode([MeetingDiagrams.Suggestion].self, from: Data($0.utf8)) } ?? []
            let history = (row["history"] as String?).flatMap { try? JSONDecoder().decode([String: [MeetingDiagrams.Diagram]].self, from: Data($0.utf8)) } ?? [:]
            return DiagramRecord(diagrams: diagrams, notesKey: row["notes_key"], provider: row["provider"], model: row["model"],
                                 updatedAt: row["updated_at"], suggestions: suggestions, suggested: (row["suggested"] as Int?) == 1, history: history)
        }
    }

    func saveDiagrams(_ meetingId: Int64, _ record: DiagramRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let suggestions = String(decoding: try encoder.encode(record.suggestions), as: UTF8.self)
        let history = String(decoding: try encoder.encode(record.history), as: UTF8.self)
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO meeting_diagrams (meeting_id, diagrams, notes_key, provider, model, updated_at, suggestions, suggested, history)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(meeting_id) DO UPDATE SET diagrams = excluded.diagrams, notes_key = excluded.notes_key,
                  provider = excluded.provider, model = excluded.model, updated_at = excluded.updated_at,
                  suggestions = excluded.suggestions, suggested = excluded.suggested, history = excluded.history
                """, arguments: [meetingId, record.diagrams.jsonString(), record.notesKey, record.provider, record.model, record.updatedAt,
                                 suggestions, record.suggested ? 1 : 0, history])
        }
    }

    /// 讀出來改了再存回去（使用者的操作：移除、復原、放回建議）
    func updateDiagrams(_ meetingId: Int64, _ change: (inout DiagramRecord) -> Void) throws {
        var record = try diagramRecord(meetingId)
            ?? DiagramRecord(diagrams: MeetingDiagrams(diagrams: []), notesKey: "", provider: "", model: "", updatedAt: Clock.now())
        change(&record)
        record.updatedAt = Clock.now()
        try saveDiagrams(meetingId, record)
    }

    func deleteDiagrams(_ meetingId: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM meeting_diagrams WHERE meeting_id = ?", arguments: [meetingId]) }
    }

    /// 排一個畫圖的工作（建議、畫、重新畫）
    func enqueueDiagrams(_ meetingId: Int64, _ job: DiagramJob) throws {
        _ = try enqueue(meetingId, kind: .diagrams, payload: job.json)
    }

    /// 排隊或正在做的畫圖工作
    func activeDiagramJobs(_ meetingId: Int64) throws -> [DiagramJob] {
        try pool.read { db in
            try String.fetchAll(db, sql: "SELECT payload FROM jobs WHERE kind = 'diagrams' AND status IN ('queued', 'running') AND meeting_id = ? ORDER BY id",
                                arguments: [meetingId])
        }.compactMap { DiagramJob.decode($0) }
    }
}
