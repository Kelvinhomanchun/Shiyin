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
    }

    struct Edge: Codable, Hashable {
        var from: String
        var to: String
        /// 連線上的字（判斷的「是」「否」、交出去的東西）；可以空白，最多 14 個字元
        var label: String
        /// 虛線：選擇性、之後才做、回傳
        var dashed: Bool
    }

    struct Diagram: Codable, Hashable {
        var kind: Kind
        var title: String
        /// 一句話說這張圖在講什麼
        var caption: String
        var nodes: [Node]
        var edges: [Edge]
    }

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
            d.nodes = d.nodes.map { var n = $0; n.label = r(n.label); n.detail = r(n.detail); n.lane = r(n.lane); return n }
            d.edges = d.edges.map { var e = $0; e.label = r(e.label); return e }
            return d
        })
    }
}

/// 存在 meetings.diagrams 的一列：產生時根據的那一版會議紀錄（內容的雜湊），紀錄換了圖還是留著，但畫面註明是之前那一版的
struct DiagramRecord: Equatable {
    var diagrams: MeetingDiagrams
    /// 產生時的會議紀錄內容（MeetingNotes.jsonString 的雜湊）
    var notesKey: String
    var provider: String
    var model: String
    var updatedAt: String
}

enum Diagrams {
    static let maxDiagrams = 2, maxNodes = 9, maxEdges = 12, maxFocal = 2, maxLanes = 5

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    static let jsonSchema: String = {
        let kinds = MeetingDiagrams.Kind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let node = #"{"type":"object","additionalProperties":false,"required":["id","label","detail","shape","lane","focal","time"],"properties":{"id":{"type":"string"},"label":{"type":"string"},"detail":{"type":"string"},"shape":{"type":"string","enum":["step","decision","start","end","data","system"]},"lane":{"type":"string"},"focal":{"type":"boolean"},"time":{"type":"string"}}}"#
        let edge = #"{"type":"object","additionalProperties":false,"required":["from","to","label","dashed"],"properties":{"from":{"type":"string"},"to":{"type":"string"},"label":{"type":"string"},"dashed":{"type":"boolean"}}}"#
        return #"{"type":"object","additionalProperties":false,"required":["diagrams"],"properties":{"diagrams":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["kind","title","caption","nodes","edges"],"properties":{"kind":{"type":"string","enum":["#
            + kinds + #"]},"title":{"type":"string"},"caption":{"type":"string"},"nodes":{"type":"array","items":"# + node
            + #"},"edges":{"type":"array","items":"# + edge + "}}}}}}"
    }()

    static let format = LLMClient.OutputFormat(schema: jsonSchema, toolName: "save_meeting_diagrams",
                                               toolDescription: "Save the diagrams that supplement the meeting notes")  // l10n-skip

    static func system(_ language: MeetingLanguage) -> String {
        let name = language.profile.outputName ?? language.profile.uiName.en
        return """
        You are an information designer who supplements meeting notes with diagrams. You decide whether a diagram would help a reader \
        understand the meeting better than the written notes, and if so, which kind, and you write its content. KelNote lays it out and \
        draws it; you only give the structure.

        Draw only when the meeting explains something with structure that prose handles badly: a process or workflow someone walked \
        through, operational steps, a hand-off between teams or systems, a decision with branches, how data moves between systems, or \
        phases on a timeline. Most meetings (status updates, discussions, interviews) need NO diagram: return an empty diagrams array. \
        Ask yourself: would the reader learn more from this than from a well-written paragraph or a three-column table? If not, don't draw.

        Pick the kind by the dominant shape of the content:
        - flowchart: a process with at least one decision or branch (shape "decision" for the question; label each exit, e.g. Yes / No).
        - steps: a short ordered method with 3 to 7 stages and no branches; one node per stage, in order; no edges needed.
        - swimlane: a process that moves between 2 to 5 roles, teams or systems; set lane to the actor who does each step, and the \
          hand-offs between lanes are the edges that matter.
        - dataFlow: where data comes from, what transforms it, and where it ends up (shape "data" for files or tables, "system" for \
          systems and tools).
        - timeline: events or phases in time order, e.g. a migration plan or a parallel run; one node per event, in order; no edges needed.

        Rules:
        1. Return at most 2 diagrams; usually 0 or 1. Only add a second one if it shows something different (for example the current \
           process and the planned future process).
        2. At most 9 nodes and 12 edges per diagram. Every node is a distinct idea: merge nodes that always travel together, and leave \
           out steps that add nothing. Above 9 it is two diagrams or too detailed.
        3. Mark focal true on at most 2 nodes: the most consequential step, the bottleneck, or what the meeting decided to change. \
           Everything else is false.
        4. label: a short name for the step, 2 to 6 words, starting with a verb for actions ("Download source files"). detail: one short \
           line of specifics from the meeting (file names, systems, who, how long), or an empty string. Never invent detail.
        5. Edge labels are optional, at most 14 characters (Yes, No, Monthly, Excel file). dashed true for optional, later, return or \
           asynchronous paths.
        6. time: when this step is discussed in the transcript, mm:ss (or h:mm:ss over an hour), else an empty string.
        7. ids are short and unique within a diagram (n1, n2…); edges refer to them.
        8. Use only what the meeting says. Do not add steps or systems that were not mentioned.
        9. title: a short name for the diagram; caption: one sentence saying what it shows.
        10. Write every text value (title, caption, label, detail, lane, edge label) in \(name). Keep names of systems, files and people \
            as written in the notes and transcript.
        """
    }

    static func prompt(meeting: Meeting, notes: MeetingNotes, segments: [Segment], speakers: [Int: String], limit: Int = 60_000) -> String {
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
        lines += ["", "Decide whether a diagram would supplement these notes, and return the diagrams (or an empty array)."]
        return lines.joined(separator: "\n")
    }
}

extension AppDatabase {
    func diagramRecord(_ meetingId: Int64) throws -> DiagramRecord? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM meeting_diagrams WHERE meeting_id = ?", arguments: [meetingId]),
                  let diagrams = MeetingDiagrams.decode(row["diagrams"]) else { return nil }
            return DiagramRecord(diagrams: diagrams, notesKey: row["notes_key"], provider: row["provider"], model: row["model"],
                                 updatedAt: row["updated_at"])
        }
    }

    func saveDiagrams(_ meetingId: Int64, _ record: DiagramRecord) throws {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO meeting_diagrams (meeting_id, diagrams, notes_key, provider, model, updated_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(meeting_id) DO UPDATE SET diagrams = excluded.diagrams, notes_key = excluded.notes_key,
                  provider = excluded.provider, model = excluded.model, updated_at = excluded.updated_at
                """, arguments: [meetingId, record.diagrams.jsonString(), record.notesKey, record.provider, record.model, record.updatedAt])
        }
    }

    func deleteDiagrams(_ meetingId: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM meeting_diagrams WHERE meeting_id = ?", arguments: [meetingId]) }
    }

    /// 正式的會議紀錄好了：排一個畫圖的工作。同一場還在排隊的就不重排
    func enqueueDiagrams(_ meetingId: Int64, payload: String? = nil) throws -> Bool {
        let queued = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE kind = 'diagrams' AND status = 'queued' AND meeting_id = ?",
                             arguments: [meetingId]) ?? 0
        }
        if queued > 0 { return false }
        _ = try enqueue(meetingId, kind: .diagrams, payload: payload)
        return true
    }
}
