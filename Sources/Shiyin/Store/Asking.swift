import Foundation
import GRDB

/// 一組問答（design §21.8）：meeting_id 是 NULL 時是問所有會議
struct QuestionRecord: SnakeCaseRecord, Identifiable, Hashable {
    static let databaseTableName = "questions"
    var id: Int64?
    var meetingId: Int64?
    var scope: String = ""
    var question: String
    var answer: String          // AskPrompt.Answer 的 JSON
    var provider: String
    var createdAt: String = Clock.now()

    var decoded: AskPrompt.Answer? { try? JSONDecoder().decode(AskPrompt.Answer.self, from: Data(answer.utf8)) }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

enum AskTarget: Equatable {
    case meeting(Int64)
    case all
}

/// 問所有會議的範圍
enum AskScope: String, CaseIterable, Identifiable {
    case all, folder, recent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return String(localized: "所有會議")
        case .folder: return String(localized: "目前的資料夾")
        case .recent: return String(localized: "最近 30 天")
        }
    }

    /// 資料夾的問答存成 scope = folder:<名稱>，資料夾之間的紀錄分開
    static let folderPrefix = "folder:"
    static func folderScope(_ folder: String) -> String { folderPrefix + folder }
}

extension AppDatabase {
    func questions(meetingId: Int64?) throws -> [QuestionRecord] {
        try pool.read { db in
            if let meetingId {
                return try QuestionRecord.filter(Column("meeting_id") == meetingId).order(Column("id")).fetchAll(db)
            }
            return try QuestionRecord.filter(Column("meeting_id") == nil).order(Column("id")).fetchAll(db)
        }
    }

    func saveQuestion(_ record: QuestionRecord) throws {
        try pool.write { db in
            var record = record
            try record.insert(db)
        }
    }

    func deleteQuestion(_ id: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM questions WHERE id = ?", arguments: [id]) }
    }

    func deleteQuestions(meetingId: Int64?) throws {
        try pool.write { db in
            if let meetingId {
                try db.execute(sql: "DELETE FROM questions WHERE meeting_id = ?", arguments: [meetingId])
            } else {
                try db.execute(sql: "DELETE FROM questions WHERE meeting_id IS NULL")
            }
        }
    }
}

/// 對會議提問（design §21.8、R19.6、D32）：不排進工作佇列，使用者在等；同時只問一題
extension AppModel {
    /// 跨會議時最多帶幾場會議、總共多少字
    static let askMeetingLimit = 8
    static let askCharacterLimit = 40_000

    func loadMeetingQuestions(_ meetingId: Int64) {
        meetingQuestions = (try? db.questions(meetingId: meetingId)) ?? []
    }

    /// 問答紀錄：選了資料夾時只看那個資料夾問過的（scope 是 folder:<名稱>），其他範圍看沒有綁資料夾的
    func loadAllQuestions() {
        let all = (try? db.questions(meetingId: nil)) ?? []
        if let folder = askFolder {
            allQuestions = all.filter { $0.scope == AskScope.folderScope(folder) }
        } else {
            allQuestions = all.filter { !$0.scope.hasPrefix(AskScope.folderPrefix) }
        }
    }

    func clearQuestions(meetingId: Int64?) {
        if meetingId == nil {
            // 只清掉目前看到的這一份（這個資料夾的，或沒有綁資料夾的）
            for record in allQuestions { if let id = record.id { try? db.deleteQuestion(id) } }
        } else {
            try? db.deleteQuestions(meetingId: meetingId)
        }
        if let meetingId { loadMeetingQuestions(meetingId) } else { loadAllQuestions() }
    }

    /// 從資料夾的右鍵選單打開「問這個資料夾」
    func askAboutFolder(_ folder: String) {
        askFolder = folder
        loadAllQuestions()
        openWindowById?("ask")
    }

    /// 不能問時的原因（還沒設定整理工具、設定為不整理、正在問別的）
    var askUnavailableReason: String? {
        if AppSettings.provider == .none {
            return AppSettings.needsProviderSetup
                ? String(localized: "還沒設定整理工具，沒辦法提問；請到設定選擇 Claude、Codex 或 API")
                : String(localized: "整理工具設定為「不整理」，沒辦法提問；請到設定改成 Claude、Codex 或 API")
        }
        // 沒登入、沒有 key…（R45.4）
        if let problem = AppSettings.summarizerProblem { return problem.message }
        return nil
    }

    func cancelAsk() {
        askProcess?.terminate()
        askTask?.cancel()
    }

    // MARK: 一場會議

    func askMeeting(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, asking == nil, let id = selection, let meeting = try? db.meeting(id) else { return }
        if let reason = askUnavailableReason { errorMessage = reason; return }
        let provider = AppSettings.provider, model = AppSettings.model
        let language = meeting.meetingLanguage
        let names = Dictionary(uniqueKeysWithValues: ((try? db.speakers(id)) ?? []).map { ($0.idx, $0.name) })
        let lines = ((try? db.segments(id)) ?? []).map { s in
            let speaker = s.speaker.map { (names[$0] ?? language.defaultSpeaker($0)) + language.text(zh: "：", en: ": ", ja: "：") } ?? ""
            return "[\(TimeFormat.string(s.start))] \(speaker)\(s.text)"
        }
        let history = meetingQuestions.suffix(3).compactMap { q in q.decoded.map { (q.question, $0.answer) } }
        let documents = ((try? db.documents(id)) ?? []).map(DocumentText.init)
        let screens = ((try? db.screens(id)) ?? []).map(ScreenText.init)
        let prompt = AskPrompt.meetingPrompt(meeting: meeting, notes: meeting.decodedNotes, lines: lines, history: history, question: question,
                                             documents: documents, screens: screens)
        let system = AskPrompt.meetingSystem(language, documents: !documents.isEmpty, screens: !screens.isEmpty)
        run(.meeting(id)) {
            let raw = try await AskPrompt.generate(AskPrompt.Answer.self, provider: provider, model: model, system: system,
                                                   prompt: prompt, format: AskPrompt.meetingFormat, onStart: { self.askProcess = $0 })
            return QuestionRecord(meetingId: id, question: question,
                                  answer: Self.json(AskPrompt.validate(raw, meetingIds: nil, documentCitations: !documents.isEmpty)),
                                  provider: provider.rawValue)
        }
    }

    // MARK: 所有會議

    func askAll(_ question: String, scope: AskScope) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, asking == nil else { return }
        if let reason = askUnavailableReason { errorMessage = reason; return }
        let provider = AppSettings.provider, model = AppSettings.model
        let language = MeetingLanguage.interface
        let folder = scope == .folder ? askFolder : nil
        if scope == .folder && folder == nil { return }
        let savedScope = folder.map(AskScope.folderScope) ?? scope.rawValue
        run(.all) {
            // 1. 抽關鍵詞
            struct Keywords: Decodable { var keywords: [String] }
            let keywords = try await AskPrompt.generate(Keywords.self, provider: provider, model: model, system: AskPrompt.keywordsSystem(language),
                                                        prompt: AskPrompt.keywordsPrompt(language, question: question),
                                                        format: AskPrompt.keywordsFormat, onStart: { self.askProcess = $0 }).keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 2 }
            try Task.checkCancellation()
            // 2. 全文搜尋，挑會議和片段
            let blocks = self.askBlocks(keywords: keywords, scope: scope, folder: folder)
            guard !blocks.isEmpty else {
                let answer = AskPrompt.Answer(answer: String(localized: "找不到跟這個問題有關的會議。可以換個說法，或用會議裡實際講的詞再問一次。"),
                                              found: false, citations: [], keywords: keywords, meetingIds: [])
                return QuestionRecord(meetingId: nil, scope: savedScope, question: question, answer: Self.json(answer), provider: provider.rawValue)
            }
            // 3. 回答
            let raw = try await AskPrompt.generate(AskPrompt.Answer.self, provider: provider, model: model, system: AskPrompt.allSystem(language),
                                                   prompt: AskPrompt.allPrompt(language, blocks: blocks, question: question),
                                                   format: AskPrompt.allFormat, onStart: { self.askProcess = $0 })
            var answer = AskPrompt.validate(raw, meetingIds: Set(blocks.map(\.id)))
            answer.keywords = keywords
            answer.meetingIds = blocks.map(\.id)
            return QuestionRecord(meetingId: nil, scope: savedScope, question: question, answer: Self.json(answer), provider: provider.rawValue)
        }
    }

    /// 用每個關鍵詞搜尋，依命中數、日期挑最多 8 場會議；每場帶摘要、決議和命中的段落（前後各一段），總長 40,000 字以內
    func askBlocks(keywords: [String], scope: AskScope, folder: String?) -> [AskPrompt.MeetingBlock] {
        var hits: [Int64: [SearchHit]] = [:]
        for keyword in keywords {
            for hit in (try? db.search(keyword, limit: 300)) ?? [] { hits[hit.meetingId, default: []].append(hit) }
        }
        // 資料夾：每場會議都帶（沒有命中關鍵詞的也帶紀錄），才能回答「整個資料夾」的問題
        if scope == .folder, let folder {
            return folderBlocks(folder: folder, hits: hits)
        }
        let cutoff = DateText.string(Date().addingTimeInterval(-30 * 86_400))
        let candidates: [(meeting: Meeting, hits: [SearchHit])] = hits.compactMap { id, list in
            guard let meeting = try? db.meeting(id), meeting.deletedAt == nil else { return nil }
            switch scope {
            case .all: break
            case .folder: guard let folder, meeting.isIn(folder: folder) else { return nil }
            case .recent: guard meeting.meetingDate >= cutoff else { return nil }
            }
            return (meeting, list)
        }
        .sorted { a, b in a.hits.count != b.hits.count ? a.hits.count > b.hits.count : a.meeting.meetingDate > b.meeting.meetingDate }
        var blocks: [AskPrompt.MeetingBlock] = []
        var total = 0
        for (meeting, list) in candidates.prefix(Self.askMeetingLimit) {
            let id = meeting.id!
            let language = meeting.meetingLanguage
            let notes = meeting.decodedNotes
            let summary = ((notes?.summary ?? []) + (notes?.decisions ?? [])).map { $0.time.isEmpty ? $0.text : "[\($0.time)] \($0.text)" }
            let segments = (try? db.segments(id)) ?? []
            let names = Dictionary(uniqueKeysWithValues: ((try? db.speakers(id)) ?? []).map { ($0.idx, $0.name) })
            let index = Dictionary(segments.enumerated().compactMap { i, s in s.id.map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
            var wanted = Set<Int>()
            for hit in list where hit.kind == .segment {
                if let i = index[hit.ref] { wanted.formUnion([i - 1, i, i + 1].filter { segments.indices.contains($0) }) }
            }
            let lines = wanted.sorted().map { i -> String in
                let s = segments[i]
                let speaker = s.speaker.map { (names[$0] ?? language.defaultSpeaker($0)) + language.text(zh: "：", en: ": ", ja: "：") } ?? ""
                return "[\(TimeFormat.string(s.start))] \(speaker)\(s.text)"
            }
            var block = AskPrompt.MeetingBlock(id: id, title: meeting.displayTitle, date: meeting.meetingDate, summary: summary, lines: lines)
            let size = (block.summary + block.lines).reduce(0) { $0 + $1.count }
            if total + size > Self.askCharacterLimit {
                // 放不下整場：只放到上限為止的段落
                let room = Self.askCharacterLimit - total - block.summary.reduce(0) { $0 + $1.count }
                guard room > 200 else { break }
                var used = 0
                block.lines = block.lines.prefix { used += $0.count; return used <= room }.map { $0 }
            }
            total += (block.summary + block.lines).reduce(0) { $0 + $1.count }
            blocks.append(block)
        }
        return blocks
    }

    /// 資料夾裡的會議最多帶幾場（每場至少帶會議紀錄）
    static let askFolderMeetingLimit = 20

    /// 問資料夾：資料夾裡每一場都帶（命中多的、新的先），先放每場的會議紀錄（摘要、決議、待辦、未決問題），
    /// 剩下的字數再依序補議題的重點、命中的逐字稿片段。總長一樣在 askCharacterLimit 以內
    func folderBlocks(folder: String, hits: [Int64: [SearchHit]]) -> [AskPrompt.MeetingBlock] {
        // 上層資料夾（客戶）：連子資料夾（案子）的會議一起帶
        let meetings = meetings.map(\.meeting).filter { $0.isIn(folder: folder) && $0.deletedAt == nil }
            .sorted { a, b in
                let ha = hits[a.id ?? -1]?.count ?? 0, hb = hits[b.id ?? -1]?.count ?? 0
                return ha != hb ? ha > hb : a.meetingDate > b.meetingDate
            }
            .prefix(Self.askFolderMeetingLimit)
        func item(_ text: String, _ time: String) -> String { time.isEmpty ? text : "[\(time)] \(text)" }
        var blocks: [AskPrompt.MeetingBlock] = []
        var extras: [[String]] = []     // 每場之後再補的：議題重點、逐字稿片段
        for meeting in meetings {
            guard let id = meeting.id else { continue }
            let language = meeting.meetingLanguage
            let notes = meeting.decodedNotes
            let l = MeetingLanguage.interface   // 欄位名稱用提問的語言（同 allPrompt）
            var summary = (notes?.summary ?? []).map { item($0.text, $0.time) }
            summary += (notes?.decisions ?? []).map { l.prompt(zh: "決議", en: "Decision", ja: "決定事項") + ": " + item($0.text, $0.time) }
            summary += (notes?.actionItems ?? []).map { a in
                l.prompt(zh: "待辦", en: "Action", ja: "ToDo") + ": " + item(a.task, a.time) + (a.owner.isEmpty ? "" : " — \(a.owner)") + (a.due.isEmpty ? "" : " (\(a.due))")
            }
            summary += (notes?.openQuestions ?? []).map { l.prompt(zh: "未決", en: "Open question", ja: "未決事項") + ": " + item($0.text, $0.time) }
            var extra = (notes?.topics ?? []).flatMap { topic in topic.points.map { "\(topic.title): " + item($0.text, $0.time) } }
            // 命中的逐字稿片段（前後各一段）
            let list = hits[id] ?? []
            if !list.isEmpty {
                let segments = (try? db.segments(id)) ?? []
                let names = Dictionary(uniqueKeysWithValues: ((try? db.speakers(id)) ?? []).map { ($0.idx, $0.name) })
                let index = Dictionary(segments.enumerated().compactMap { i, s in s.id.map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
                var wanted = Set<Int>()
                for hit in list where hit.kind == .segment {
                    if let i = index[hit.ref] { wanted.formUnion([i - 1, i, i + 1].filter { segments.indices.contains($0) }) }
                }
                extra += wanted.sorted().map { i in
                    let s = segments[i]
                    let speaker = s.speaker.map { (names[$0] ?? language.defaultSpeaker($0)) + language.text(zh: "：", en: ": ", ja: "：") } ?? ""
                    return "[\(TimeFormat.string(s.start))] \(speaker)\(s.text)"
                }
            }
            blocks.append(AskPrompt.MeetingBlock(id: id, title: meeting.displayTitle, date: meeting.meetingDate, summary: summary, lines: []))
            extras.append(extra)
        }
        // 先保證每場的紀錄放得下（放不下的從後面截短），再輪流補每場的議題、片段
        var total = 0
        for i in blocks.indices {
            let room = Self.askCharacterLimit - total
            var used = 0
            blocks[i].summary = blocks[i].summary.prefix { used += $0.count; return used <= room }.map { $0 }
            total += blocks[i].summary.reduce(0) { $0 + $1.count }
        }
        var cursor = Array(repeating: 0, count: blocks.count)
        var added = true
        while added {
            added = false
            for i in blocks.indices where cursor[i] < extras[i].count {
                let line = extras[i][cursor[i]]
                guard total + line.count <= Self.askCharacterLimit else { continue }
                blocks[i].lines.append(line)
                total += line.count
                cursor[i] += 1
                added = true
            }
        }
        return blocks.filter { !$0.summary.isEmpty || !$0.lines.isEmpty }
    }

    /// 共用的流程：標記正在問、可以取消、存問答、更新畫面
    private func run(_ target: AskTarget, _ work: @escaping @MainActor () async throws -> QuestionRecord) {
        asking = target
        askTask = Task {
            defer {
                asking = nil
                askTask = nil
                askProcess = nil
            }
            do {
                let record = try await work()
                guard !Task.isCancelled else { return }
                try db.saveQuestion(record)
                UsageStats.shared.asked()
                if case .meeting(let id) = target { loadMeetingQuestions(id) } else { loadAllQuestions() }
            } catch is CancellationError {
            } catch {
                // CLI 被結束（按了取消）時也會丟錯誤
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    private static func json(_ answer: AskPrompt.Answer) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(answer)) ?? Data(), as: UTF8.self)
    }

    /// 點了回答裡的出處：打開那場會議、切到逐字稿、從那個時間點播放
    func openCitation(meetingId: Int64, time: String) {
        openMainWindow?()
        showTrash = false
        selection = meetingId
        tab = .transcript
        guard let seconds = TimeFormat.seconds(time) else { return }
        player.seek(to: seconds, play: false)
        if let id = detail?.segmentId(at: seconds) { flashSegment(id) }
    }
}
