import SwiftUI

// MARK: - 工作坊（fork）：筆記頁上的一段
// 開會前：目的、範圍、草稿流程、要問的問題，「開始錄音」錄進這一場。
// 開會後：整理工具列出的每一項都是「待確認」，只有使用者按了才算確認；每一項附證據（誰、什麼時候、原話）。

struct WorkshopSection: View {
    @Environment(AppModel.self) private var model
    let detail: MeetingDetail

    private var record: WorkshopRecord? { detail.workshop }
    private var plan: WorkshopPlan { record?.plan ?? WorkshopPlan() }
    private var analysis: WorkshopAnalysis? { record?.analysis }
    private var locked: Bool { detail.meeting.deletedAt != nil || model.viewingNotes != nil }
    private var planned: Bool { model.isPlannedWorkshop(detail.meeting) }
    private var hasContent: Bool { !detail.segments.isEmpty || detail.notes != nil }
    private var stale: Bool {
        guard let a = analysis else { return false }
        return a.basis != Workshop.basisKey(plan: plan, notes: detail.notes)
    }

    var body: some View {
        NotesSection(title: String(localized: "工作坊")) {
            if hasContent {
                Button(detail.analysingWorkshop ? String(localized: "整理中…")
                        : analysis == nil ? String(localized: "整理工作坊") : String(localized: "重新整理"),
                       systemImage: "sparkles") { model.analyseWorkshop() }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .foregroundStyle(locked ? Color.secondary : Color.celadon)
                    .disabled(detail.analysingWorkshop || locked)
                    .help("把逐字稿整理成：草稿流程每一步的驗證結果、問題的回答、客戶說的流程、需求與規則、RAID。每一項都附證據，都是「待確認」")
            }
        } content: {
            VStack(alignment: .leading, spacing: 22) {
                prepCard
                if detail.analysingWorkshop {
                    Label("正在整理這場工作坊…", systemImage: "hourglass").foregroundStyle(.secondary)
                }
                if let a = analysis, !a.isEmpty || a.readBack.done {
                    results(a)
                } else if hasContent && !detail.analysingWorkshop {
                    Text("錄音轉錄好之後，按「整理工作坊」。整理出來的每一項都附證據、都是「待確認」，由你確認。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 準備

    @ViewBuilder private var prepCard: some View {
        let collapsible = analysis != nil
        if collapsible {
            DisclosureGroup(isExpanded: Binding(get: { model.workshopPrepOpen }, set: { model.workshopPrepOpen = $0 })) {
                WorkshopPrep(detail: detail, planned: planned, locked: locked).padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Text("事前準備").contentFont(.body, weight: .semibold)
                    Text(prepSummary).foregroundStyle(.secondary).contentFont(.callout)
                }
            }
        } else {
            WorkshopPrep(detail: detail, planned: planned, locked: locked)
        }
    }

    private var prepSummary: String {
        var parts: [String] = []
        if !plan.purposes.isEmpty { parts.append(plan.purposes.map(\.title).joined(separator: ", ")) }
        if plan.hasDraft { parts.append(String(localized: "草稿 \(plan.draft?.nodes.count ?? 0) 步")) }
        if !plan.questions.isEmpty { parts.append(String(localized: "\(plan.questions.count) 個問題")) }
        return parts.joined(separator: " · ")
    }

    // MARK: 結果

    private func results(_ a: WorkshopAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            summaryStrip(a)
            if !a.steps.isEmpty { validation(a) }
            if !a.questions.isEmpty { questions(a) }
            if !a.walkthrough.isEmpty { walkthrough(a) }
            if !a.pains.isEmpty { pains(a) }
            if !a.requirements.isEmpty { requirements(a) }
            if !a.rules.isEmpty { rules(a) }
            if !a.raid.isEmpty { raid(a) }
            if !a.parking.isEmpty || !a.outOfScope.isEmpty || !a.glossary.isEmpty { others(a) }
            readBack(a)
        }
    }

    private func summaryStrip(_ a: WorkshopAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label("\(a.openCount) 項待確認", systemImage: "circle.dashed").foregroundStyle(a.openCount > 0 ? Color.signal : .secondary)
                Label("\(a.confirmedCount) 項已確認", systemImage: "checkmark.circle.fill").foregroundStyle(Color.positive)
                Spacer()
                Button("全部確認", systemImage: "checkmark.circle") { model.confirmAllWorkshop(a.allMeta.filter { $0.status == .unconfirmed }.map(\.id)) }
                    .buttonStyle(.borderless).foregroundStyle(Color.celadon)
                    .disabled(a.openCount == 0 || locked)
                    .help("看過、都對的時候一次確認；不對的先改或駁回")
            }
            .contentFont(.callout, weight: .medium)
            Text("整理工具列出的都是「待確認」：沒有你確認，不算客戶說定的。每一項附上誰在什麼時候說的、原話。")
                .contentFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if stale {
                Label("事前準備或會議紀錄改過，這份整理是依之前的內容做的", systemImage: "clock.arrow.circlepath")
                    .contentFont(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.celadon.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // 草稿驗證
    private func validation(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "草稿流程驗證"), meta: a.steps.map(\.meta), locked: locked) {
            if let draft = plan.draft, plan.hasDraft {
                WorkshopBeforeAfter(detail: detail, draft: draft, revised: record?.revised)
            }
            ForEach(a.steps) { f in
                WorkshopItem(meta: f.meta, editText: f.note, locked: locked) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !f.ref.isEmpty { RefBadge(f.ref) }
                        Text(f.label.isEmpty ? f.newLabel : f.label).contentFont(.body, weight: .semibold)
                        Spacer(minLength: 8)
                        VerdictMenu(finding: f, locked: locked)
                    }
                    if !f.note.isEmpty { Text(f.note).fixedSize(horizontal: false, vertical: true) }
                    if f.verdict == .changed || f.verdict == .added, !f.newLabel.isEmpty, f.newLabel != f.label {
                        Label(f.newLabel + (f.newLane.isEmpty ? "" : " (\(f.newLane))"), systemImage: "arrow.turn.down.right")
                            .contentFont(.callout).foregroundStyle(Color.celadon)
                    }
                }
            }
        }
    }

    // 問題
    private func questions(_ a: WorkshopAnalysis) -> some View {
        let answered = a.questions.filter { $0.state == .answered }.count
        return WorkshopGroup(title: String(localized: "問題記錄"), meta: a.questions.map(\.meta), locked: locked,
                             subtitle: String(localized: "\(answered) / \(a.questions.count) 已回答")) {
            ForEach(a.questions) { q in
                WorkshopItem(meta: q.meta, editText: q.answer, locked: locked) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(q.state.title, systemImage: q.state.icon)
                            .labelStyle(.titleAndIcon)
                            .contentFont(.caption, weight: .semibold)
                            .foregroundStyle(q.state == .answered ? Color.positive : q.state == .partial ? Color.signal : .secondary)
                        if q.raisedInRoom { Chip(String(localized: "現場提出")) }
                        if !q.stepRef.isEmpty { RefBadge(q.stepRef) }
                    }
                    Text(q.text).contentFont(.body, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    if !q.answer.isEmpty { Text(q.answer).fixedSize(horizontal: false, vertical: true) }
                    if q.state != .answered, !(q.owner.isEmpty && q.due.isEmpty) {
                        Label([q.owner, q.due].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "person.badge.clock")
                            .contentFont(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // 客戶走一遍
    private func walkthrough(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "客戶說的流程"), meta: a.walkthrough.map(\.meta), locked: locked,
                      subtitle: String(localized: "主線先，例外接在分出去的那一步")) {
            ForEach(a.walkthrough) { s in
                let exception = !s.branchFrom.isEmpty
                WorkshopItem(meta: s.meta, editText: s.label, locked: locked) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if exception { Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary) }
                        if !s.ref.isEmpty { RefBadge(s.ref) }
                        Text(s.label).contentFont(.body, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    }
                    if exception {
                        Text(String(localized: "例外：從第 \(s.branchFrom) 步分出去") + (s.frequency.isEmpty ? "" : " · " + s.frequency))
                            .contentFont(.callout).foregroundStyle(Color.signal)
                    }
                    FlowLayout(spacing: 6) {
                        if !s.actor.isEmpty { Chip(s.actor, icon: "person") }
                        if !s.systems.isEmpty { Chip(s.systems, icon: "desktopcomputer") }
                        if !s.timing.isEmpty { Chip(s.timing, icon: "clock") }
                        if !s.handoffNeeds.isEmpty { Chip(String(localized: "交接需要：\(s.handoffNeeds)"), icon: "arrow.right.arrow.left") }
                    }
                }
                .padding(.leading, exception ? 22 : 0)
            }
            Button("畫成泳道圖", systemImage: "rectangle.split.3x1") { model.drawWalkthrough() }
                .buttonStyle(.borderless).foregroundStyle(Color.celadon).contentFont(.callout)
                .disabled(locked || detail.notes == nil)
                .help("依這些步驟畫一張泳道圖（誰做哪一步、怎麼交接），畫好放在上面的「圖」")
        }
    }

    // 痛點
    private func pains(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "痛點與變通做法"), meta: a.pains.map(\.meta), locked: locked,
                      subtitle: String(localized: "客戶自己想的辦法，常常就是沒說出口的需求")) {
            ForEach(a.pains) { p in
                WorkshopItem(meta: p.meta, editText: p.text, locked: locked) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !p.stepRef.isEmpty { RefBadge(p.stepRef) }
                        Text(p.text).contentFont(.body, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    }
                    if !p.workaround.isEmpty {
                        Label(p.workaround, systemImage: "wrench.and.screwdriver").foregroundStyle(Color.signal)
                            .contentFont(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    if !p.impact.isEmpty { Label(p.impact, systemImage: "gauge.with.dots.needle.67percent").contentFont(.callout).foregroundStyle(.secondary) }
                }
            }
        }
    }

    // 需求
    private func requirements(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "需求"), meta: a.requirements.map(\.meta), locked: locked,
                      subtitle: String(localized: "優先順序只在客戶說過的時候才寫")) {
            ForEach(a.requirements) { r in
                WorkshopItem(meta: r.meta, editText: r.text, locked: locked) {
                    HStack(spacing: 6) {
                        Chip(r.kind.short)
                        if !r.priority.isEmpty { Chip(String(localized: "客戶說：\(r.priority)"), icon: "flag", tint: .signal) }
                        if !r.stepRef.isEmpty { RefBadge(r.stepRef) }
                        if !r.fromWorkaround.isEmpty { Chip(String(localized: "來自 \(r.fromWorkaround) 的變通做法"), icon: "wrench.and.screwdriver", tint: .signal) }
                    }
                    Text(r.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // 規則
    private func rules(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "業務規則與權限"), meta: a.rules.map(\.meta), locked: locked,
                      subtitle: String(localized: "候選：確認前不算規則")) {
            ForEach(a.rules) { r in
                WorkshopItem(meta: r.meta, editText: r.text, locked: locked) {
                    HStack(spacing: 6) {
                        Chip(r.isAuthority ? String(localized: "權限") : String(localized: "規則"), icon: r.isAuthority ? "person.badge.key" : "list.bullet.rectangle")
                        if !r.stepRef.isEmpty { RefBadge(r.stepRef) }
                    }
                    Text(r.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // RAID
    private func raid(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "RAID：決定、假設、議題、風險"), meta: a.raid.map(\.meta), locked: locked,
                      subtitle: String(localized: "決定只記有具名的人明確說了的；說法不同的兩邊都留著")) {
            ForEach(a.raid) { r in
                WorkshopItem(meta: r.meta, editText: r.text, locked: locked) {
                    HStack(spacing: 6) {
                        Chip(r.kind.title, icon: r.kind.icon, tint: r.kind == .risk || r.kind == .conflict ? .signal : .celadon)
                        if !r.decidedBy.isEmpty { Chip(String(localized: "決定的人：\(r.decidedBy)"), icon: "person") }
                    }
                    Text(r.text).fixedSize(horizontal: false, vertical: true)
                    if !(r.owner.isEmpty && r.due.isEmpty) {
                        Label([r.owner, r.due].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "person.badge.clock")
                            .contentFont(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // 停車場、範圍外、詞彙
    private func others(_ a: WorkshopAnalysis) -> some View {
        WorkshopGroup(title: String(localized: "停車場、範圍外、詞彙"), meta: (a.parking + a.outOfScope + a.glossary).map(\.meta), locked: locked) {
            ForEach(a.parking) { n in note(n, String(localized: "停車場"), "parkingsign") }
            ForEach(a.outOfScope) { n in note(n, String(localized: "範圍外"), "nosign") }
            ForEach(a.glossary) { n in note(n, String(localized: "詞彙"), "character.book.closed") }
        }
    }

    private func note(_ n: NoteFinding, _ kind: String, _ icon: String) -> some View {
        WorkshopItem(meta: n.meta, editText: n.text, locked: locked) {
            HStack(spacing: 6) { Chip(kind, icon: icon); Text(n.text).contentFont(.body, weight: .semibold) }
            if !n.detail.isEmpty { Text(n.detail).fixedSize(horizontal: false, vertical: true) }
        }
    }

    // 讀回確認
    private func readBack(_ a: WorkshopAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("結束前有沒有讀回給客戶").contentTitleFont(15)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                let r = a.readBack
                Label(r.done ? (r.result == .agreed ? String(localized: "有，客戶同意") : r.result == .partly ? String(localized: "有，客戶部分同意") : r.result == .no ? String(localized: "有，客戶不同意") : String(localized: "有讀回"))
                            : String(localized: "逐字稿裡沒有看到"),
                      systemImage: r.result == .agreed ? "checkmark.seal.fill" : r.done ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(r.result == .agreed ? Color.positive : r.done ? Color.celadon : Color.signal)
                    .contentFont(.body, weight: .semibold)
                if !r.time.isEmpty { TimeButton(time: r.time, quiet: true) }
                Spacer()
                Menu("改成…") {
                    Button("客戶同意") { model.setReadBack(.agreed) }
                    Button("客戶部分同意") { model.setReadBack(.partly) }
                    Button("客戶不同意") { model.setReadBack(.no) }
                    Button("沒有讀回") { model.setReadBack(.unknown) }
                }
                .menuStyle(.borderlessButton).fixedSize().disabled(locked)
            }
            if !a.readBack.quote.isEmpty { Text("「\(a.readBack.quote)」").foregroundStyle(.secondary).italic() }
            if !a.readBack.done {
                Text("好的做法：結束前把整理好的流程讀一遍，請客戶說「對」。沒讀回的內容，客戶之後可能不同意。")
                    .contentFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 事前準備

struct WorkshopPrep: View {
    @Environment(AppModel.self) private var model
    let detail: MeetingDetail
    let planned: Bool
    let locked: Bool

    private var plan: WorkshopPlan { detail.workshop?.plan ?? WorkshopPlan() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            purposes
            scope
            draft
            questions
            if planned {
                HStack(spacing: 12) {
                    Button { model.startWorkshopRecording(detail.meeting.id!) } label: {
                        Label("開始錄音", systemImage: "record.circle")
                    }
                    .buttonStyle(SheetPillButtonStyle(.primary))
                    .disabled(locked || model.recorder.isRecording)
                    .help(model.recorder.isRecording ? String(localized: "已經在錄另一場") : String(localized: "錄進這一場，準備好的草稿和問題會留著"))
                    Text("錄音時，右邊會列出要問的問題。").foregroundStyle(.secondary).contentFont(.callout)
                }
            }
        }
    }

    private var purposes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("這場工作坊要做什麼").contentFont(.callout, weight: .semibold).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                ForEach(WorkshopPurpose.allCases) { p in
                    let on = plan.purposes.contains(p)
                    Button { model.togglePurpose(p) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: p.icon).foregroundStyle(on ? Color.celadon : .secondary).frame(width: 22).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).contentFont(.body, weight: .semibold)
                                Text(p.detail).contentFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.celadon : .secondary.opacity(0.5))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? Color.celadon.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.celadon.opacity(0.6) : .clear, lineWidth: 1.5))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("流程範圍").contentFont(.callout, weight: .semibold).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                PlanField(label: String(localized: "從什麼事件開始"), placeholder: String(localized: "例如：月底結帳日"), value: plan.trigger, locked: locked) { v in model.updateWorkshopPlan { $0.trigger = v } }
                PlanField(label: String(localized: "到什麼結果結束"), placeholder: String(localized: "例如：報表發給管理層"), value: plan.endPoint, locked: locked) { v in model.updateWorkshopPlan { $0.endPoint = v } }
                PlanField(label: String(localized: "流程負責人"), placeholder: String(localized: "客戶那邊的人"), value: plan.owner, locked: locked) { v in model.updateWorkshopPlan { $0.owner = v } }
            }
        }
    }

    // 草稿
    @ViewBuilder private var draft: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("草稿流程（版本 1）").contentFont(.callout, weight: .semibold).foregroundStyle(.secondary)
            if detail.draftingWorkshop {
                Label("正在把文字整理成流程…", systemImage: "hourglass").foregroundStyle(.secondary)
            }
            if let d = plan.draft, plan.hasDraft {
                Text(d.title).contentTitleFont(16)
                if !plan.draftSource.isEmpty { Text(plan.draftSource).contentFont(.callout).foregroundStyle(.secondary) }
                WorkshopDiagramFrame(diagram: d)
                    .opacity(detail.draftingWorkshop ? 0.4 : 1)
                HStack(spacing: 14) {
                    if !plan.draftText.isEmpty {
                        Button("提意見重新畫…", systemImage: "text.bubble") { model.workshopSheet = .draftComment }
                            .foregroundStyle(Color.celadon)
                    }
                    Button("換成別的文字…", systemImage: "doc.text") { model.workshopSheet = .draftText }.foregroundStyle(Color.celadon)
                    DiagramDownloadMenu(diagram: d, key: "workshopdraft")
                    Spacer(minLength: 0)
                    Button("移除草稿", systemImage: "trash") { model.removeDraft() }.foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless).contentFont(.callout).disabled(locked)
            } else if !detail.draftingWorkshop {
                Text("你先畫好的流程，拿去給客戶驗證每一步對不對。貼上描述、讀進文件，整理工具會整理成一張流程圖；之後工作坊的結果會對照這一張。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("貼上或讀入流程描述…", systemImage: "doc.on.clipboard") { model.workshopSheet = .draftText }
                        .foregroundStyle(Color.celadon)
                    if let diagrams = detail.diagrams?.diagrams.diagrams, !diagrams.isEmpty {
                        Menu("用這場會議的圖") {
                            ForEach(diagrams, id: \.id) { d in Button(d.title) { model.useDiagramAsDraft(d) } }
                        }
                        .menuStyle(.borderlessButton).fixedSize().foregroundStyle(Color.celadon)
                    }
                }
                .buttonStyle(.borderless).contentFont(.callout).disabled(locked)
            }
        }
    }

    // 問題
    private var questions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("要問的問題").contentFont(.callout, weight: .semibold).foregroundStyle(.secondary)
                Spacer()
                Button("加問題…", systemImage: "plus") { model.workshopSheet = .questions() }
                    .buttonStyle(.borderless).contentFont(.callout).foregroundStyle(Color.celadon).disabled(locked)
            }
            if plan.questions.isEmpty {
                Text("寫下要釐清的問題，或貼上整份清單、讀進文件。每一題有編號（QST-），工作坊後會一題一題對照：回答了、回答一部分、還是沒問到。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(plan.questions) { q in
                QuestionRow(question: q, steps: plan.draft?.nodes.map(\.ref).filter { !$0.isEmpty } ?? [], locked: locked)
            }
        }
    }
}

private struct QuestionRow: View {
    @Environment(AppModel.self) private var model
    let question: WorkshopQuestion
    let steps: [String]
    let locked: Bool
    @State private var text = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(question.id).contentFont(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            if editing {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.sheetCompact)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, now in if !now { commit() } }
            } else {
                Text(question.text).fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { if !locked { text = question.text; editing = true; focused = true } }
            }
            Spacer(minLength: 6)
            if !steps.isEmpty {
                Menu {
                    Button("不連到流程") { model.editQuestion(question.id, stepRef: "") }
                    Divider()
                    ForEach(steps, id: \.self) { s in Button(String(localized: "第 \(s) 步")) { model.editQuestion(question.id, stepRef: s) } }
                } label: {
                    Text(question.stepRef.isEmpty ? String(localized: "連到步驟") : String(localized: "第 \(question.stepRef) 步"))
                        .contentFont(.caption)
                }
                .menuStyle(.borderlessButton).fixedSize().disabled(locked)
            }
            Button { model.removeQuestion(question.id) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(locked)
                .help("拿掉這一題")
                .accessibilityLabel(Text("拿掉這一題"))
        }
        .padding(.vertical, 2)
    }

    private func commit() {
        guard editing else { return }
        editing = false
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != question.text { model.editQuestion(question.id, text: t) }
    }
}

private struct PlanField: View {
    let label: String
    let placeholder: String
    let value: String
    let locked: Bool
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SheetFieldLabel(label)
            TextField(placeholder, text: $text)
                .textFieldStyle(.sheetCompact)
                .focused($focused)
                .onSubmit { save(text.trimmingCharacters(in: .whitespaces)) }
                .onChange(of: focused) { _, now in if !now, text != value { save(text.trimmingCharacters(in: .whitespaces)) } }
                .disabled(locked)
        }
        .onAppear { text = value }
        .onChange(of: value) { _, new in if !focused { text = new } }
    }
}

// MARK: - 共用的小元件

/// 步驟編號的小標籤（1、2a）
struct RefBadge: View {
    let ref: String
    init(_ ref: String) { self.ref = ref }
    var body: some View {
        Text(ref).contentFont(.caption, weight: .semibold).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(Text("第 \(ref) 步"))
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .secondary
    init(_ text: String, icon: String? = nil, tint: Color = .secondary) { self.text = text; self.icon = icon; self.tint = tint }
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text).lineLimit(2)
        }
        .contentFont(.caption, weight: .medium)
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// 一組項目：標題、數量、「這組全部確認」
struct WorkshopGroup<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let meta: [WorkshopMeta]
    let locked: Bool
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let open = meta.filter { $0.status == .unconfirmed }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).contentTitleFont(16)
                Text(open.isEmpty ? String(localized: "\(meta.count) 項，都確認了") : String(localized: "\(open.count) / \(meta.count) 待確認"))
                    .contentFont(.callout).foregroundStyle(open.isEmpty ? Color.positive : .secondary)
                Spacer()
                if !open.isEmpty {
                    Button("這組全部確認") { model.confirmAllWorkshop(open.map(\.id)) }
                        .buttonStyle(.borderless).contentFont(.callout).foregroundStyle(Color.celadon).disabled(locked)
                }
            }
            if let subtitle { Text(subtitle).contentFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            content
        }
    }
}

/// 一項：左邊是狀態（點一下確認、再點取消）；下面證據；確認、改、駁回
struct WorkshopItem<Content: View>: View {
    @Environment(AppModel.self) private var model
    let meta: WorkshopMeta
    let editText: String
    let locked: Bool
    @ViewBuilder var content: Content
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private var rejected: Bool { meta.status == .rejected }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                model.setWorkshopStatus(meta.id, meta.status == .confirmed ? .unconfirmed : .confirmed)
            } label: {
                Image(systemName: meta.status == .confirmed ? "checkmark.circle.fill" : rejected ? "xmark.circle" : "circle.dashed")
                    .font(.system(size: 18))
                    .foregroundStyle(meta.status == .confirmed ? Color.positive : rejected ? Color.negative : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(locked || rejected)
            .help(meta.status == .confirmed ? String(localized: "已確認，再按一次取消") : String(localized: "按一下確認"))
            .accessibilityLabel(Text(meta.status == .confirmed ? "已確認" : rejected ? "已駁回" : "待確認"))
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(meta.id).contentFont(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if meta.edited { Text("你改過").contentFont(.caption).foregroundStyle(.secondary) }
                    if meta.status == .confirmed, !meta.confirmedOn.isEmpty {
                        Text(String(localized: "\(meta.confirmedOn) 確認")).contentFont(.caption).foregroundStyle(Color.positive)
                    }
                }
                VStack(alignment: .leading, spacing: 4) { content }
                    .strikethrough(rejected)
                    .opacity(rejected ? 0.5 : 1)
                if editing {
                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.sheetCompact)
                        .focused($focused)
                        .onSubmit(commit)
                    HStack {
                        Button("存") { commit() }.buttonStyle(SheetPillButtonStyle(.primary, compact: true))
                        Button("取消") { editing = false }.buttonStyle(SheetPillButtonStyle(.secondary, compact: true))
                    }
                }
                ForEach(Array(meta.evidence.enumerated()), id: \.offset) { _, e in EvidenceLine(evidence: e) }
                if !locked && !editing {
                    HStack(spacing: 14) {
                        if meta.status == .unconfirmed {
                            Button("確認") { model.setWorkshopStatus(meta.id, .confirmed) }.foregroundStyle(Color.celadon)
                        }
                        Button("改") { text = editText; editing = true; focused = true }.foregroundStyle(.secondary)
                        if rejected {
                            Button("還原") { model.setWorkshopStatus(meta.id, .unconfirmed) }.foregroundStyle(Color.celadon)
                        } else {
                            Button("不對，駁回") { model.setWorkshopStatus(meta.id, .rejected) }.foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless).contentFont(.callout)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(meta.status == .confirmed ? Color.positive.opacity(0.06) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func commit() {
        editing = false
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != editText { model.editWorkshopItem(meta.id, text: t) }
    }
}

struct EvidenceLine: View {
    let evidence: WorkshopEvidence
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("「\(evidence.quote)」").italic().contentFont(.callout).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if !evidence.speaker.isEmpty { Text(evidence.speaker).contentFont(.caption).foregroundStyle(.secondary) }
                if !evidence.time.isEmpty { TimeButton(time: evidence.time, quiet: true) }
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Capsule().fill(Color.celadon.opacity(0.45)).frame(width: 2) }
    }
}

/// 草稿每一步的結論：點了改（AI 判斷錯的時候）
private struct VerdictMenu: View {
    @Environment(AppModel.self) private var model
    let finding: StepFinding
    let locked: Bool

    static func color(_ v: StepVerdict) -> Color {
        switch v {
        case .confirmed: .positive
        case .changed, .added: .celadon
        case .notDone: .negative
        case .disputed: .signal
        case .unclear: .secondary
        }
    }

    var body: some View {
        Menu {
            ForEach(StepVerdict.allCases.filter { $0 != .added || finding.verdict == .added }, id: \.self) { v in
                Button { model.setStepVerdict(finding.id, v) } label: { Label(v.title, systemImage: v.icon) }
            }
        } label: {
            Label(finding.verdict.title, systemImage: finding.verdict.icon).contentFont(.caption, weight: .semibold)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundStyle(Self.color(finding.verdict))
        .disabled(locked)
        .help("整理工具的判斷不對的話，點這裡改")
    }
}

// MARK: - 圖

struct WorkshopDiagramFrame: View {
    @Environment(\.textScale) private var textScale
    @Environment(AppModel.self) private var model
    let diagram: MeetingDiagrams.Diagram
    var body: some View {
        DiagramFrame(view: DiagramView(diagram: diagram, onSeek: nil), textScale: textScale)
    }
}

struct DiagramDownloadMenu: View {
    @Environment(AppModel.self) private var model
    let diagram: MeetingDiagrams.Diagram
    let key: String
    var body: some View {
        FloatingMenuLabelButton(title: String(localized: "下載"), systemImage: "arrow.down.circle",
                                help: String(localized: "存成圖片、PDF 或可以改的 draw.io 檔"), debugKey: key) {
            DiagramExport.Format.allCases.map { f in
                MenuEntry.action(DiagramExport.title(f), icon: DiagramExport.icon(f)) { model.downloadDiagram(diagram, format: f) }
            } + [.divider, .action(String(localized: "拷貝圖片"), icon: "doc.on.doc") { model.copyDiagram(diagram) }]
        }
    }
}

/// 版本 1（草稿）和版本 2（依工作坊結果改過的）：切換看，兩張都可以下載給客戶
struct WorkshopBeforeAfter: View {
    @Environment(AppModel.self) private var model
    let detail: MeetingDetail
    let draft: MeetingDiagrams.Diagram
    let revised: MeetingDiagrams.Diagram?
    @State private var showV2 = true

    private var changes: [Workshop.Revision.Change] {
        detail.workshop?.analysis.flatMap { Workshop.revise(draft, with: $0.steps)?.changes } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let revised {
                Picker("版本", selection: $showV2) {
                    Text("版本 1：草稿").tag(false)
                    Text("版本 2：驗證後").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                let shown = showV2 ? revised : draft
                WorkshopDiagramFrame(diagram: shown)
                HStack(spacing: 14) {
                    DiagramDownloadMenu(diagram: titled(shown, showV2 ? 2 : 1), key: "workshopdiagram")
                    Text(showV2 ? String(localized: "藍色是改過或新增的步驟") : String(localized: "你事前畫的草稿"))
                        .contentFont(.callout).foregroundStyle(.secondary)
                }
                if showV2, !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("和草稿的差異").contentFont(.callout, weight: .semibold).foregroundStyle(.secondary)
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, c in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: c.verdict.icon).foregroundStyle(VerdictColor.color(c.verdict))
                                if !c.ref.isEmpty { RefBadge(c.ref) }
                                Text(c.label).contentFont(.callout, weight: .medium)
                                if !c.detail.isEmpty { Text("— " + c.detail).contentFont(.callout).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            } else {
                Text("草稿裡沒有需要修改的步驟，所以沒有版本 2。確認、駁回、改結論之後，版本 2 會跟著更新。")
                    .contentFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 6)
    }

    private func titled(_ d: MeetingDiagrams.Diagram, _ version: Int) -> MeetingDiagrams.Diagram {
        var out = d
        out.title = d.title + String(localized: "（版本 \(version)）")
        return out
    }
}

private enum VerdictColor {
    static func color(_ v: StepVerdict) -> Color {
        switch v {
        case .confirmed: .positive
        case .changed, .added: .celadon
        case .notDone: .negative
        case .disputed: .signal
        case .unclear: .secondary
        }
    }
}

/// 錄音時旁邊的問題清單：問到了點一下劃掉（只在這次錄音的畫面裡，提醒用；整理時還是依逐字稿判斷有沒有回答）
struct WorkshopQuestionChecklist: View {
    let questions: [WorkshopQuestion]
    @State private var asked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("要問的問題").font(.songti(16))
            Text("\(asked.count) / \(questions.count) 已問").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(questions) { q in
                        Button {
                            if asked.contains(q.id) { asked.remove(q.id) } else { asked.insert(q.id) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: asked.contains(q.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(asked.contains(q.id) ? Color.positive : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(q.id).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                    Text(q.text).font(.callout).strikethrough(asked.contains(q.id))
                                        .foregroundStyle(asked.contains(q.id) ? .secondary : .primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(q.id) \(q.text)"))
                        .accessibilityAddTraits(asked.contains(q.id) ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: 220)
            Divider().padding(.vertical, 4)
        }
    }
}
