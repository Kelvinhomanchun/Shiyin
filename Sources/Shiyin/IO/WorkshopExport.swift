import Foundation

/// 工作坊的交付件（fork）：給客戶的摘要（Word、PDF）和給顧問自己的 Excel 工作簿。
/// 文字跟著會議紀錄的語言（同其他匯出）；摘要不放錄音的時間點，工作簿放（顧問自己追證據用）。
/// 項目沒有確認就標「待確認」，確認了才標「已確認」；被駁回的不放
enum WorkshopExport {
    // MARK: 文字

    private static func t(_ x: ExportText, _ zh: String, _ en: String) -> String { x.language.text(zh: zh, en: en, ja: en) }

    private static func purposeName(_ p: WorkshopPurpose, _ x: ExportText) -> String {
        switch p {
        case .validate: t(x, "驗證草稿流程", "Validate a draft process")
        case .clarify: t(x, "釐清問題", "Clarify questions")
        case .walkthrough: t(x, "客戶走一遍流程", "Client walkthrough")
        case .elicit: t(x, "蒐集需求", "Elicit requirements")
        }
    }
    private static func verdictName(_ v: StepVerdict, _ x: ExportText) -> String {
        switch v {
        case .confirmed: t(x, "確認", "Confirmed as drawn")
        case .changed: t(x, "要修改", "Needs a change")
        case .added: t(x, "新增的一步", "New step")
        case .notDone: t(x, "實際沒做", "Not done in practice")
        case .disputed: t(x, "說法不同", "Views differ")
        case .unclear: t(x, "沒討論到", "Not covered")
        }
    }
    private static func answerName(_ s: AnswerState, _ x: ExportText) -> String {
        switch s {
        case .answered: t(x, "已回答", "Answered")
        case .partial: t(x, "回答一部分", "Partly answered")
        case .notCovered: t(x, "還沒回答", "Not answered")
        }
    }
    private static func kindName(_ k: RequirementKind, _ x: ExportText) -> String {
        switch k {
        case .functional: t(x, "功能", "Functional")
        case .data: t(x, "資料", "Data")
        case .report: t(x, "報表", "Report")
        case .integration: t(x, "系統串接", "Integration")
        case .nonFunctional: t(x, "非功能", "Non-functional")
        case .constraint: t(x, "限制", "Constraint")
        }
    }
    private static func raidName(_ k: RaidKind, _ x: ExportText) -> String {
        switch k {
        case .decision: t(x, "決定", "Decision")
        case .assumption: t(x, "假設", "Assumption")
        case .issue, .conflict: t(x, "議題", "Issue")
        case .risk: t(x, "風險", "Risk")
        }
    }
    private static func statusName(_ m: WorkshopMeta, _ x: ExportText) -> String {
        m.status == .confirmed ? t(x, "已確認", "Confirmed") : t(x, "待確認", "To confirm")
    }
    private static func raisedBy(_ m: WorkshopMeta) -> String { m.evidence.first?.speaker ?? "" }

    // MARK: 圖

    /// 摘要裡的圖：草稿（版本 1）、驗證後的版本 2。回傳標題和 PNG（跟會議紀錄的圖一樣，白底、沒有錄音時間點）
    @MainActor
    static func diagrams(_ b: ExportBundle, _ w: WorkshopRecord) -> [(title: String, png: Data)] {
        let x = b.notesText
        var out: [(String, Data)] = []
        if w.plan.hasDraft, let d = w.plan.draft, let png = DiagramExport.png(DiagramExport.forExport(d, meeting: b.meeting)) {
            out.append((t(x, "草稿流程（版本 1）", "Draft process (version 1)"), png))
        }
        if let d = w.revised, let png = DiagramExport.png(DiagramExport.forExport(d, meeting: b.meeting)) {
            out.append((t(x, "工作坊後的流程（版本 2）", "Process after the workshop (version 2)"), png))
        }
        return out
    }

    // MARK: 摘要（Word、PDF）

    /// pdf：PDF 版面（封面條、數字列）；否則給 Word 的簡單版面。diagramTitles：每張圖的標題，位置標記依序放
    static func html(_ b: ExportBundle, _ w: WorkshopRecord, pdf: Bool, diagramTitles: [String]) -> String {
        let m = b.meeting
        let x = b.notesText
        let a = w.analysis ?? WorkshopAnalysis()
        func e(_ s: String) -> String { HTML.escape(s) }
        func cell(_ s: String) -> String { s.isEmpty ? "—" : e(s) }

        let folder = m.folder.isEmpty ? "" : " · " + FolderPath.display(m.folder)
        let kicker = t(x, "工作坊摘要", "Workshop summary") + folder
        var body = ""
        let confirmed = a.confirmedCount, toConfirm = a.openCount
        let openQuestions = a.questions.filter { $0.meta.status != .rejected && $0.state != .answered }.count
        var meta = ["\(x.date)\(pdf ? "" : x.colon)<b>\(e(NotesExporter.reportDate(m.meetingDate, x)))</b>"]
        if !m.participantList.isEmpty { meta.append("\(x.participants)\(pdf ? "" : x.colon)<b>\(e(m.participantList.joined(separator: x.listSeparator)))</b>") }
        if !w.plan.owner.isEmpty { meta.append("\(t(x, "流程負責人", "Process owner"))\(pdf ? "" : x.colon)<b>\(e(w.plan.owner))</b>") }
        let purposes = w.plan.purposes.map { purposeName($0, x) }.joined(separator: x.listSeparator)
        var scope = ""
        if !w.plan.trigger.isEmpty || !w.plan.endPoint.isEmpty {
            scope = "<b>\(t(x, "流程範圍", "Process scope"))</b>\(x.colon)\(cell(w.plan.trigger)) → \(cell(w.plan.endPoint))"
        }
        if pdf {
            body += "<header class=\"cover\"><div class=\"kicker\">\(e(kicker))</div><h1>\(e(m.displayTitle))</h1><div class=\"meta\">"
            body += meta.map { "<div>\($0)</div>" }.joined() + "</div></header>\n"
            if !purposes.isEmpty || !scope.isEmpty {
                body += "<p class=\"sub\">" + [purposes.isEmpty ? "" : "<b>\(t(x, "目的", "Purpose"))</b>\(x.colon)\(e(purposes))", scope].filter { !$0.isEmpty }.joined(separator: "<br>") + "</p>\n"
            }
            body += "<div class=\"figs\">"
            for (n, label) in [(confirmed, t(x, "已確認", "Confirmed")), (toConfirm, t(x, "待確認", "To confirm")), (openQuestions, t(x, "未回答的問題", "Open questions"))] {
                body += "<div class=\"fig\"><div class=\"n\">\(n)</div><div class=\"l\">\(e(label))</div></div>"
            }
            body += "</div>\n"
        } else {
            body += "<p class=\"kicker\">\(e(kicker))</p>\n<h1>\(e(m.displayTitle))</h1>\n<p class=\"meta\">" + meta.joined(separator: "&nbsp;&nbsp;&nbsp;·&nbsp;&nbsp;&nbsp;") + "</p>\n"
            if !purposes.isEmpty { body += "<p class=\"meta\"><b>\(t(x, "目的", "Purpose"))</b>\(x.colon)\(e(purposes))</p>\n" }
            if !scope.isEmpty { body += "<p class=\"meta\">\(scope)</p>\n" }
            body += "<p class=\"meta\">\(t(x, "已確認", "Confirmed"))\(x.colon)<b>\(confirmed)</b>&nbsp;&nbsp;·&nbsp;&nbsp;\(t(x, "待確認", "To confirm"))\(x.colon)<b>\(toConfirm)</b>&nbsp;&nbsp;·&nbsp;&nbsp;\(t(x, "未回答的問題", "Open questions"))\(x.colon)<b>\(openQuestions)</b></p>\n<hr>\n"
        }

        var section = 0
        func number(_ n: Int) -> String { String(format: "%02d", n) }
        /// 段落：標題、一行說明、內容。PDF 把標題和說明放在一起不拆頁
        func add(_ title: String, _ intro: String, _ content: String, first: String = "") {
            section += 1
            let heading = "<h2><span class=\"no\">\(number(section))</span>\(pdf ? "" : "&nbsp;&nbsp;")\(e(title))</h2>"
            let lead = intro.isEmpty ? "" : "<p class=\"intro\">\(e(intro))</p>"
            // PDF：標題和第一個內容（第一張圖）放在一起不拆頁，標題才不會單獨留在頁尾
            body += pdf ? "<section><div class=\"lead\">\(heading)\(lead)\(first)</div>\(content)</section>\n" : "\(heading)\n\(lead)\n\(first)\(content)\n"
        }
        func table(_ heads: [(String, Int)], _ rows: [[String]]) -> String {
            let head = heads.map { "<th style=\"width:\($0.1)%\">\(e($0.0))</th>" }.joined()
            let trs = rows.map { row in
                "<tr>" + row.enumerated().map { i, c in "<td\(i == 0 ? " class=\"o\"" : "")>\(c)</td>" }.joined() + "</tr>"
            }.joined()
            return "<table><thead><tr>\(head)</tr></thead><tbody>\(trs)</tbody></table>"
        }
        func status(_ meta: WorkshopMeta) -> String {
            let text = statusName(meta, x) + (meta.status == .confirmed && !meta.confirmedBy.isEmpty ? " (\(meta.confirmedBy))" : "")
            return meta.status == .confirmed ? "<span style=\"color:#0F62FE\">\(e(text))</span>" : "<span style=\"color:#8D8D8D\">\(e(text))</span>"
        }
        func live<T>(_ list: [T], _ meta: KeyPath<T, WorkshopMeta>) -> [T] { list.filter { $0[keyPath: meta].status != .rejected } }
        func step(_ ref: String) -> String { ref.isEmpty ? "—" : e(ref) }

        // 1 流程：圖、對照表
        let steps = live(a.steps, \.meta)
        if !diagramTitles.isEmpty || !steps.isEmpty {
            var cards = ""
            for (k, title) in diagramTitles.enumerated() {
                let card = "<h3>\(e(title))</h3>\n<p class=\"diagram\">\(ScreenExport.diagramMarker(k))</p>"
                cards += pdf ? "<div class=\"topic\">\(card)</div>" : card
            }
            var table1 = ""
            if !steps.isEmpty {
                table1 = table([(t(x, "步驟", "Step"), 8), (t(x, "草稿裡的步驟", "Step as drafted"), 30), (t(x, "客戶怎麼說", "What the client said"), 19),
                                (t(x, "說明", "Note"), 27), (t(x, "狀態", "Status"), 16)],
                               steps.map { s in
                                   [step(s.ref), e(s.verdict == .added ? s.newLabel : s.label), e(verdictName(s.verdict, x)),
                                    cell(s.verdict == .added && s.note.isEmpty ? s.newLane : s.note), status(s.meta)]
                               })
            }
            add(t(x, "流程：草稿和客戶的回應", "Process: the draft and the client's response"),
                t(x, "我們畫的草稿，和客戶看過之後的結果。", "What we drew, and what the client said when they saw it."), cards, first: table1)
        }
        // 2 客戶現在怎麼做
        let walk = Workshop.ordered(live(a.walkthrough, \.meta))
        if !walk.isEmpty {
            add(t(x, "客戶現在怎麼做", "How the client works today"),
                t(x, "依客戶的說明整理，例外附在它分出去的那一步。", "As the client described it; exceptions are attached to the step they branch from."),
                table([(t(x, "編號", "ID"), 11), (t(x, "步驟", "Step"), 8), (t(x, "做什麼", "What happens"), 23), (t(x, "誰", "Who"), 13),
                       (t(x, "系統", "Systems"), 15), (t(x, "時間、頻率", "Timing, frequency"), 17), (t(x, "狀態", "Status"), 13)],
                      walk.map { s in
                          let when = [s.timing, s.branchFrom.isEmpty ? "" : "\(t(x, "例外，從步驟", "Exception from step")) \(s.branchFrom)", s.frequency].filter { !$0.isEmpty }.joined(separator: " · ")
                          return [e(s.meta.id), step(s.ref), e(s.label), cell(s.actor), cell(s.systems), cell(when), status(s.meta)]
                      }))
        }
        // 3 痛點
        let pains = live(a.pains, \.meta)
        if !pains.isEmpty {
            add(t(x, "痛點", "Pain points"), t(x, "客戶卡住的地方；有土法煉鋼的做法就是隱藏的需求。", "Where the client struggles; a workaround usually points to a hidden requirement."),
                table([(t(x, "編號", "ID"), 10), (t(x, "痛點", "Pain point"), 34), (t(x, "步驟", "Step"), 8), (t(x, "現在的做法", "Workaround today"), 24), (t(x, "狀態", "Status"), 14)] + [],
                      pains.map { [e($0.meta.id), e($0.text), step($0.stepRef), cell($0.workaround), status($0.meta)] }))
        }
        // 4 需求
        let reqs = live(a.requirements, \.meta)
        if !reqs.isEmpty {
            add(t(x, "需求", "Requirements"), t(x, "優先順序只在客戶自己說過的時候才寫。", "Priority is shown only where the client stated it."),
                table([(t(x, "編號", "ID"), 9), (t(x, "類型", "Type"), 11), (t(x, "需求", "Requirement"), 36), (t(x, "步驟", "Step"), 8), (t(x, "優先", "Priority"), 10),
                       (t(x, "提出的人", "Raised by"), 12), (t(x, "狀態", "Status"), 15)],
                      reqs.map { [e($0.meta.id), e(kindName($0.kind, x)), e($0.text), step($0.stepRef), cell($0.priority), cell(raisedBy($0.meta)), status($0.meta)] }))
        }
        // 5 規則、授權
        let rules = live(a.rules, \.meta)
        if !rules.isEmpty {
            add(t(x, "業務規則和授權", "Business rules and authority"), t(x, "規則（RUL）和誰有權決定（AUTH）。", "Rules (RUL) and who has the authority to decide (AUTH)."),
                table([(t(x, "編號", "ID"), 10), (t(x, "規則、授權", "Rule or authority"), 56), (t(x, "步驟", "Step"), 8), (t(x, "狀態", "Status"), 18)] + [],
                      rules.map { [e($0.meta.id), e($0.text), step($0.stepRef), status($0.meta)] }))
        }
        // 6 決定
        let decisions = live(a.raid, \.meta).filter { $0.kind == .decision }
        if !decisions.isEmpty {
            add(t(x, "決定", "Decisions"), t(x, "只記有人明確說「就這樣」的決定，並寫下是誰決定的。", "Only what a named person clearly decided is recorded here."),
                table([(t(x, "編號", "ID"), 10), (t(x, "決定", "Decision"), 50), (t(x, "決定的人", "Decided by"), 20), (t(x, "狀態", "Status"), 20)],
                      decisions.map { [e($0.meta.id), e($0.text), cell($0.decidedBy), status($0.meta)] }))
        }
        // 7 問題
        let questions = live(a.questions, \.meta)
        if !questions.isEmpty {
            add(t(x, "問題", "Questions"), t(x, "事先準備的問題和會中提出的問題，答案和沒回答的部分分開列。", "Prepared questions and those raised in the room, with what was answered and what is still open."),
                table([(t(x, "編號", "ID"), 9), (t(x, "問題", "Question"), 27), (t(x, "回答", "Answer"), 29), (t(x, "結果", "Result"), 11), (t(x, "負責人", "Owner"), 9), (t(x, "期限", "Due"), 8), (t(x, "狀態", "Status"), 14) ],
                      questions.map { q in
                          [e(q.meta.id), e(q.text + (q.raisedInRoom ? " (\(t(x, "會中提出", "raised in the room")))" : "")), cell(q.answer), e(answerName(q.state, x)),
                           cell(q.owner), cell(q.due), status(q.meta)]
                      }))
        }
        // 8 假設、議題、風險
        let others = live(a.raid, \.meta).filter { $0.kind != .decision }
        if !others.isEmpty {
            add(t(x, "假設、議題和風險", "Assumptions, issues and risks"), t(x, "還沒解決的事，每一項要有負責人和期限。", "Things still open; each needs an owner and a date."),
                table([(t(x, "編號", "ID"), 9), (t(x, "類型", "Type"), 11), (t(x, "內容", "Statement"), 38), (t(x, "負責人", "Owner"), 11), (t(x, "期限", "Due"), 11), (t(x, "狀態", "Status"), 20)],
                      others.map { [e($0.meta.id), e(raidName($0.kind, x)), e($0.text), cell($0.owner), cell($0.due), status($0.meta)] }))
        }
        // 9 暫放、範圍外、名詞
        func notes(_ title: String, _ list: [NoteFinding]) -> String {
            let items = live(list, \.meta)
            guard !items.isEmpty else { return "" }
            let rows = items.map { n in
                "<li>\(e(n.meta.id))&nbsp;&nbsp;\(e(n.text))\(n.detail.isEmpty ? "" : " — " + e(n.detail))</li>"
            }.joined()
            return "<h3>\(e(title))</h3><ul>\(rows)</ul>"
        }
        let side = notes(t(x, "暫放（之後再談）", "Parking lot"), a.parking) + notes(t(x, "範圍外", "Out of scope"), a.outOfScope) + notes(t(x, "名詞", "Glossary"), a.glossary)
        if !side.isEmpty { add(t(x, "暫放、範圍外和名詞", "Parking lot, out of scope and glossary"), "", side) }
        // 10 簽核
        var sign = ""
        if a.readBack.done {
            let result: String
            switch a.readBack.result {
            case .agreed: result = t(x, "客戶同意", "The client agreed")
            case .partly: result = t(x, "客戶部分同意", "The client agreed in part")
            case .no: result = t(x, "客戶不同意", "The client did not agree")
            case .unknown: result = t(x, "結果不明", "Outcome unclear")
            }
            sign += "<p>\(e(t(x, "會議結束前讀回確認：", "Read-back at the end of the workshop: ")))<b>\(e(result))</b></p>"
        }
        let versions = diagramTitles.isEmpty ? "" : "<p>\(e(t(x, "這份摘要裡的版本：", "Versions in this summary: ")))<b>\(e(diagramTitles.joined(separator: " · ")))</b></p>"
        sign += versions
        let blank = Array(repeating: ["&nbsp;", "&nbsp;", "&nbsp;", "&nbsp;"], count: 3)
        sign += table([(t(x, "簽核人（姓名、職稱）", "Approver (name, role)"), 36), (t(x, "日期", "Date"), 18), (t(x, "審閱的版本", "Version reviewed"), 26), (t(x, "簽名", "Signature"), 20)], blank)
        add(t(x, "簽核", "Sign-off"), t(x, "簽核表示客戶同意上面「已確認」的項目；「待確認」的項目還沒有人確認。", "Sign-off covers the items marked Confirmed; items marked To confirm are not yet agreed."), sign)

        if pdf { return body }
        return HTML.document(title: m.displayTitle, body: body + "<hr>\n<p class=\"foot\">\(e(footer(x)))</p>\n", language: x.language)
    }

    static func footer(_ x: ExportText) -> String {
        t(x, "由 KelNote 根據工作坊錄音整理 · AI 產生的內容，標「待確認」的項目還沒有人確認", "Prepared with KelNote from the workshop recording · AI-generated; items marked To confirm have not been confirmed yet")
    }

    /// PDF 的版面（在會議紀錄的 PDF 樣式上補幾個樣式）
    static func pdfPage(_ b: ExportBundle, body: String) -> String {
        let page = HTML.report(title: b.meeting.displayTitle, body: body, footer: footer(b.notesText), language: b.notesText.language)
        let extra = ".sub{margin:12pt 0 0;color:#525252;font-size:9pt}.sub b{color:#161616;font-weight:500}.intro{margin:-2pt 0 8pt;color:#525252;font-size:9pt}"
            + "section h3{font-weight:500;font-size:10.5pt;margin:10pt 0 3pt}th,td{overflow-wrap:break-word}td.o{white-space:nowrap}"
        return page.replacingOccurrences(of: "</style>", with: extra + "</style>")
    }

    // MARK: Excel 工作簿

    /// 編號跟 CBAF 的 Engagement Control Workbook 一樣（RAID & Decisions 的欄位、Evidence 的欄位），可以直接貼進去。
    /// 證據編號從項目編號來：EV-REQ-004-1
    static func workbook(_ b: ExportBundle, _ w: WorkshopRecord) throws -> Data {
        let m = b.meeting
        let a = w.analysis ?? WorkshopAnalysis()
        let source = "\(m.displayTitle) (\(m.meetingDate))"
        let pending = "Unconfirmed (AI)"
        func conf(_ meta: WorkshopMeta) -> String { meta.status == .confirmed ? "Confirmed" : pending }
        func live<T>(_ list: [T], _ meta: KeyPath<T, WorkshopMeta>) -> [T] { list.filter { $0[keyPath: meta].status != .rejected } }
        /// 這一項的證據編號（用在每個工作表的「Evidence ref」）
        func refs(_ meta: WorkshopMeta) -> String { meta.evidence.indices.map { "EV-\(meta.id)-\($0 + 1)" }.joined(separator: ", ") }
        let x = b.notesText
        var evidence: [[String]] = []
        func collect(_ meta: WorkshopMeta, _ statement: String) {
            for (k, ev) in meta.evidence.enumerated() {
                evidence.append(["EV-\(meta.id)-\(k + 1)", "Interview", ev.quote, [source, ev.speaker, ev.time].filter { !$0.isEmpty }.joined(separator: " · "),
                                 meta.id, meta.confirmedBy, m.meetingDate, meta.status == .confirmed ? "Confirmed" : "Unconfirmed"])
            }
        }

        var about: [[String]] = [["Workshop", m.displayTitle], ["Date", m.meetingDate], ["Folder", FolderPath.display(m.folder)],
                                 ["Participants", m.participantList.joined(separator: ", ")], ["Process owner", w.plan.owner],
                                 ["Purpose", w.plan.purposes.map { purposeName($0, x) }.joined(separator: ", ")],
                                 ["Process trigger", w.plan.trigger], ["Process end point", w.plan.endPoint],
                                 ["Items confirmed", "\(a.confirmedCount)"], ["Items unconfirmed (AI)", "\(a.openCount)"],
                                 ["Note", "IDs continue across the project folder. Priority is filled only where the client stated it. Every item stays Unconfirmed (AI) until a person confirms it in KelNote."],
                                 ["Note", "RAID & Decisions and Evidence use the column layout of the CBAF Engagement Control Workbook; rows can be pasted in."]]
        about = about.filter { !$0[1].isEmpty }

        let reqs = live(a.requirements, \.meta)
        reqs.forEach { collect($0.meta, $0.text) }
        let requirements = reqs.map { r in
            [r.meta.id, kindName(r.kind, ExportText(.en)), r.text, r.stepRef, r.priority, r.fromWorkaround, raisedBy(r.meta), conf(r.meta), r.meta.confirmedBy, r.meta.confirmedOn, refs(r.meta)]
        }
        let rl = live(a.rules, \.meta)
        rl.forEach { collect($0.meta, $0.text) }
        let rules = rl.map { [$0.meta.id, $0.isAuthority ? "Authority" : "Rule", $0.text, $0.stepRef, raisedBy($0.meta), conf($0.meta), $0.meta.confirmedBy, $0.meta.confirmedOn, refs($0.meta)] }
        let qs = live(a.questions, \.meta)
        qs.forEach { collect($0.meta, $0.text) }
        let en = ExportText(.en)
        let questions = qs.map { q in
            [q.meta.id, q.text, q.stepRef, answerName(q.state, en), q.answer, q.raisedInRoom ? "Yes" : "No", q.owner, q.due,
             q.state == .answered ? "Closed" : "Open", conf(q.meta), refs(q.meta)]
        }
        let rd = live(a.raid, \.meta)
        rd.forEach { collect($0.meta, $0.text) }
        let raid = rd.map { r in
            // CBAF 的欄位：ID、Type、Statement、Raised by、Source artifact、Owner、Due、Status、Resolution/decision、Options considered、Decider、Date、Decider's words、Evidence ref
            let isDecision = r.kind == .decision
            return [r.meta.id, raidName(r.kind, en), r.text, raisedBy(r.meta), source, r.owner, r.due, isDecision ? "Closed" : "Open",
                    isDecision ? r.text : "", "", isDecision ? r.decidedBy : "", isDecision ? m.meetingDate : "",
                    isDecision ? (r.meta.evidence.first?.quote ?? "") : "", refs(r.meta), conf(r.meta)]
        }
        let ws = live(a.walkthrough, \.meta)
        ws.forEach { collect($0.meta, $0.label) }
        let st = live(a.steps, \.meta)
        st.forEach { collect($0.meta, $0.note) }
        let pn = live(a.pains, \.meta)
        pn.forEach { collect($0.meta, $0.text) }
        let process = Workshop.ordered(ws).map { s in
            [s.meta.id, s.ref, s.label, s.actor, s.systems, s.timing, s.branchFrom, s.frequency, s.handoffNeeds, conf(s.meta), refs(s.meta)]
        } + st.map { s in
            [s.meta.id, s.ref, s.verdict == .added ? s.newLabel : s.label, "", "", "", "", "", "Draft check: \(verdictName(s.verdict, en))" + (s.note.isEmpty ? "" : " — \(s.note)"), conf(s.meta), refs(s.meta)]
        }
        let pains = pn.map { [$0.meta.id, $0.text, $0.stepRef, $0.workaround, $0.impact, conf($0.meta), refs($0.meta)] }

        let sheets: [Sheet] = [
            Sheet(name: "Workshop", heads: [("Field", 24), ("Value", 90)], rows: about),
            Sheet(name: "Requirements", heads: [("ID", 11), ("Type", 14), ("Requirement", 60), ("Step", 8), ("Priority (client-stated)", 14), ("From workaround", 28),
                                                 ("Raised by", 16), ("Confirmation", 16), ("Confirmed by", 16), ("Confirmed on", 13), ("Evidence ref", 22)], rows: requirements),
            Sheet(name: "Rules", heads: [("ID", 11), ("Kind", 11), ("Statement", 70), ("Step", 8), ("Raised by", 16), ("Confirmation", 16), ("Confirmed by", 16), ("Confirmed on", 13), ("Evidence ref", 22)], rows: rules),
            Sheet(name: "Questions", heads: [("ID", 11), ("Question", 55), ("Step", 8), ("Answer state", 15), ("Answer", 55), ("Raised in room", 12), ("Owner", 16), ("Due", 12),
                                              ("Status", 11), ("Confirmation", 16), ("Evidence ref", 22)], rows: questions,
                  lists: [(8, ["Open", "Closed"])]),
            Sheet(name: "RAID & Decisions", heads: [("ID", 11), ("Type", 12), ("Statement", 55), ("Raised by", 16), ("Source artifact", 30), ("Owner", 16), ("Due", 12), ("Status", 12),
                                                     ("Resolution / decision", 40), ("Options considered", 24), ("Decider", 16), ("Date", 12), ("Decider's words", 40), ("Evidence ref", 22),
                                                     ("Confirmation", 16)], rows: raid,
                  lists: [(1, ["Risk", "Assumption", "Issue", "Question", "Decision"]), (7, ["Open", "In progress", "Closed"])]),
            Sheet(name: "Process steps", heads: [("ID", 11), ("Step", 8), ("Step description", 50), ("Actor", 18), ("Systems", 18), ("Timing", 16), ("Branches from", 12), ("Frequency", 14),
                                                  ("Hand-off / draft check", 40), ("Confirmation", 16), ("Evidence ref", 22)], rows: process),
            Sheet(name: "Pain points", heads: [("ID", 11), ("Pain point", 60), ("Step", 8), ("Workaround today", 40), ("Impact", 30), ("Confirmation", 16), ("Evidence ref", 22)], rows: pains),
            Sheet(name: "Evidence", heads: [("EV ID", 22), ("Kind", 13), ("Statement / finding", 70), ("Source", 44), ("Used by", 13), ("Confirmed by", 16), ("Date", 12), ("Status", 14)], rows: evidence,
                  lists: [(1, ["Interview", "Document", "Data", "Observation", "Estimate", "Benchmark"]), (7, ["Unconfirmed", "Confirmed", "Superseded"])]),
        ]
        return try XLSX.data(sheets)
    }

    struct Sheet {
        var name: String
        var heads: [(String, Double)]
        var rows: [[String]]
        /// 下拉選單：欄的位置（從 0 算）和選項
        var lists: [(column: Int, values: [String])] = []
    }
}

/// 最小的 xlsx 寫入（沒有外部套件）：字串寫在儲存格裡（inlineStr）、一個標題列樣式、凍結第一列、篩選、下拉選單。用 /usr/bin/zip 壓縮
enum XLSX {
    struct Failure: LocalizedError {
        var reason: String
        var errorDescription: String? { reason }
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t", "\n", "\r": out.unicodeScalars.append(u)
            default: if u.value >= 0x20 && u.value != 0xFFFE && u.value != 0xFFFF { out.unicodeScalars.append(u) }   // XML 不允許的控制字元丟掉
            }
        }
        return out
    }

    static func column(_ index: Int) -> String {
        var n = index, out = ""
        repeat { out = String(UnicodeScalar(UInt8(65 + n % 26))) + out; n = n / 26 - 1 } while n >= 0
        return out
    }

    private static func cell(_ ref: String, _ text: String, style: Int) -> String {
        "<c r=\"\(ref)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">\(escape(text))</t></is></c>"
    }

    /// 工作表名稱：最多 31 字、不能有 : \ / ? * [ ]
    private static func sheetName(_ name: String) -> String {
        String(name.filter { !":\\/?*[]".contains($0) }.prefix(31))
    }

    private static func sheetXML(_ s: WorkshopExport.Sheet) -> String {
        let last = max(s.rows.count + 1, 2)
        let lastColumn = column(max(s.heads.count - 1, 0))
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols>
        """
        for (i, head) in s.heads.enumerated() {
            xml += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(head.1)\" customWidth=\"1\"/>"
        }
        xml += "</cols><sheetData>"
        xml += "<row r=\"1\" ht=\"22\" customHeight=\"1\">" + s.heads.enumerated().map { cell("\(column($0.offset))1", $0.element.0, style: 1) }.joined() + "</row>"
        for (r, row) in s.rows.enumerated() {
            xml += "<row r=\"\(r + 2)\">" + s.heads.indices.map { cell("\(column($0))\(r + 2)", $0 < row.count ? row[$0] : "", style: 0) }.joined() + "</row>"
        }
        xml += "</sheetData><autoFilter ref=\"A1:\(lastColumn)\(last)\"/>"
        if !s.lists.isEmpty {
            xml += "<dataValidations count=\"\(s.lists.count)\">"
            for list in s.lists {
                let c = column(list.column)
                xml += "<dataValidation type=\"list\" allowBlank=\"1\" showErrorMessage=\"0\" sqref=\"\(c)2:\(c)\(max(last, 200))\"><formula1>\"\(escape(list.values.joined(separator: ",")))\"</formula1></dataValidation>"
            }
            xml += "</dataValidations>"
        }
        return xml + "</worksheet>"
    }

    static func data(_ sheets: [WorkshopExport.Sheet]) throws -> Data {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("KelNoteXLSX-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        try write("[Content_Types].xml", head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
            + sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined() + "</Types>")
        try write("_rels/.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        try write("xl/workbook.xml", head + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><bookViews><workbookView activeTab=\"0\"/></bookViews><sheets>"
            + sheets.enumerated().map { "<sheet name=\"\(escape(sheetName($0.element.name)))\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>" }.joined() + "</sheets></workbook>")
        try write("xl/_rels/workbook.xml.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined()
            + "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>")
        try write("xl/styles.xml", head + """
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="10"/><color rgb="FF161616"/><name val="Calibri"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0F62FE"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFE0E0E0"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """)
        for (i, s) in sheets.enumerated() { try write("xl/worksheets/sheet\(i + 1).xml", sheetXML(s)) }

        let output = root.appendingPathComponent("out.xlsx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-X", "-D", "-q", "-r", output.path, "[Content_Types].xml", "_rels", "xl"]
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(reason: String(localized: "Excel 檔寫出失敗（zip 結束代碼 \(process.terminationStatus)）")) }
        return try Data(contentsOf: output)
    }
}
