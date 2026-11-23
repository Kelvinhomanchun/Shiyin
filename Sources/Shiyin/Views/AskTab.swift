import SwiftUI

/// 對這場會議提問（design §21.8、R19.6）：回答附上錄音時間點，點了跳過去；問答紀錄留在會議裡
struct AskTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.snapshotMode) private var snapshotMode
    @Environment(\.textScale) private var scale
    let detail: MeetingDetail
    @State private var question = ""

    private var asking: Bool { model.asking == .meeting(detail.meeting.id!) }

    var body: some View {
        VStack(spacing: 0) {
            if snapshotMode {
                // 截圖畫不出 ScrollView 的內容（DEBUG 的 snapshot），直接排出來
                list
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView { list }
                        .onChange(of: model.meetingQuestions.count) { _, _ in
                            if let last = model.meetingQuestions.last?.id { withAnimation { proxy.scrollTo(last, anchor: .top) } }
                        }
                }
            }
            Divider()
            AskInputBar(question: $question, placeholder: String(localized: "問這場會議，例如：誰負責寄信的部分？"),
                        busy: model.asking != nil, onClear: model.meetingQuestions.isEmpty ? nil : {
                            model.clearQuestions(meetingId: detail.meeting.id)
                        }) {
                model.askMeeting(question)
                question = ""
            }
        }
        .onAppear { model.loadMeetingQuestions(detail.meeting.id!) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.meetingQuestions.isEmpty && !asking {
                VStack(alignment: .leading, spacing: 6) {
                    Text("問這場會議").font(.songti(18))
                    Text("例如：「誰負責寄信的部分？」「最後決定的上線日期是哪一天？」回答只根據這場會議的會議紀錄和逐字稿，每一點都附上時間，點了就能聽原話。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(model.meetingQuestions) { record in
                QuestionView(record: record) { time in
                    if let seconds = TimeFormat.seconds(time) { model.player.seek(to: seconds) }
                }
                .id(record.id)
            }
            if asking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在用 \(AppSettings.provider.shortLabel) 回答…").foregroundStyle(.secondary)
                    Button("取消") { model.cancelAsk() }.buttonStyle(.link)
                }
                .id("asking")
            }
        }
        .contentFont()   // 文字大小（design §38.5）
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .frame(maxWidth: 760 * scale, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 提問的輸入列（單場和所有會議共用）
struct AskInputBar: View {
    @Environment(AppModel.self) private var model
    @Binding var question: String
    let placeholder: String
    let busy: Bool
    var onClear: (() -> Void)?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = model.askUnavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.signal)
            }
            HStack(spacing: 10) {
                TextField(placeholder, text: $question, axis: .vertical)
                    .textFieldStyle(.sheet)
                    .lineLimit(1...4)
                    .onSubmit(submit)
                Button("提問", action: submit)
                    .buttonStyle(SheetPillButtonStyle(.primary))
                    .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.askUnavailableReason != nil)
                if let onClear {
                    Menu {
                        DestructiveMenuButton(String(localized: "清除問答紀錄"), action: onClear)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("更多")
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
    }

    private func submit() {
        guard !busy, model.askUnavailableReason == nil, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmit()
    }
}

/// 一組問答：問題、回答、出處（時間點，跨會議時加上會議名稱）
struct QuestionView: View {
    @Environment(AppModel.self) private var model
    let record: QuestionRecord
    var meetingTitle: ((Int64) -> String?)? = nil
    let onCitation: (String) -> Void
    var onMeetingCitation: ((Int64, String) -> Void)? = nil
    @State private var showQuotes = false

    /// 一個出處的小標籤：點了跳過去，滑過看原文
    @ViewBuilder
    private func chip(_ citation: AskPrompt.Citation) -> some View {
        let label: String = {
            if let id = citation.meetingId { return "\(meetingTitle?(id) ?? String(localized: "會議")) \(citation.time)" }
            return citation.time.isEmpty ? String(localized: "參考文件") : citation.time
        }()
        Button {
            if let id = citation.meetingId, let onMeetingCitation { onMeetingCitation(id, citation.time) }
            else if !citation.time.isEmpty { onCitation(citation.time) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: citation.time.isEmpty ? "paperclip" : "play.fill").font(.system(size: 8))
                Text(label).lineLimit(1)
            }
            .contentFont(.caption, monospacedDigit: true)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(citation.time.isEmpty ? Color.secondary : Color.celadon)
            .background((citation.time.isEmpty ? Color.secondary : Color.celadon).opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(citation.quote)
    }

    var body: some View {
        let answer = record.decoded
        VStack(alignment: .leading, spacing: 8) {
            Text(record.question).fontWeight(.semibold).textSelection(.enabled)
            if let answer {
                // 回答常用 **粗體**：解析行內的 Markdown，保留換行和「- 」列點
                Text((try? AttributedString(markdown: answer.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                     ?? AttributedString(answer.answer))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(answer.found ? .primary : .secondary)
                // 出處（UX 檢查 C4）：原本每條都是一整行原文，回答被一長串引文淹沒。改成一排小標籤
                //（時間點，跨會議時加會議標題），滑過看原文；要看全部原文按「顯示原文」
                if !answer.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("出處").contentFont(.caption).foregroundStyle(.secondary)
                            Button(showQuotes ? String(localized: "收起原文") : String(localized: "顯示原文")) { showQuotes.toggle() }
                                .buttonStyle(.borderless).contentFont(.caption)
                        }
                        if showQuotes {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, citation in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        chip(citation)
                                        Text(citation.quote).contentFont(.callout).foregroundStyle(.secondary).meetingText()
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, citation in chip(citation) }
                            }
                        }
                    }
                }
                if let ids = answer.meetingIds, record.meetingId == nil {
                    Text(ids.isEmpty ? String(localized: "沒有找到相關的會議") : String(localized: "參考了 \(ids.count) 場會議"))
                        .contentFont(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 問所有會議（design §21.8）：獨立的視窗，可以一邊看會議一邊問；出處點了打開那場會議
struct AskAllView: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var scope: AskScope = .all

    /// 有資料夾的會議才列（空的資料夾問不出東西）
    private var folders: [String] {
        Array(Set(model.meetings.map(\.meeting.folder).filter { !$0.isEmpty })).sorted()
    }

    private var folderScope: Binding<AskScope> {
        Binding(get: { model.askFolder != nil ? .folder : scope }, set: { value in
            if value == .folder {
                if model.askFolder == nil { model.askFolder = model.folderFilter ?? folders.first }
            } else {
                model.askFolder = nil
                scope = value
            }
            model.loadAllQuestions()
        })
    }

    var body: some View {
        let current = folderScope.wrappedValue
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(current == .folder ? String(localized: "問資料夾") : String(localized: "問所有會議")).font(.songti(20))
                Spacer()
                Picker("範圍", selection: folderScope) {
                    ForEach(AskScope.allCases) { scope in
                        if scope != .folder || !folders.isEmpty {
                            Text(scope == .folder ? String(localized: "一個資料夾") : scope.label).tag(scope)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
                if current == .folder {
                    Picker("資料夾", selection: Binding(get: { model.askFolder ?? "" }, set: { name in
                        model.askFolder = name
                        model.loadAllQuestions()
                    })) {
                        ForEach(folders, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.allQuestions.isEmpty && model.asking != .all {
                            Text(current == .folder
                                 ? String(localized: "例如：「這個專案目前的進度和風險？」「有哪些還沒完成的待辦？」拾音會帶上這個資料夾每一場會議的紀錄，再加上跟問題有關的逐字稿片段，請整理工具回答。")
                                 : String(localized: "例如：「上個月跟客戶談過哪些價格？」「寄信的機制最後怎麼決定的？」拾音會先找出相關的會議片段，再請整理工具回答，回答附上是哪一場會議、哪個時間點。"))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(model.allQuestions) { record in
                            QuestionView(record: record, meetingTitle: { id in
                                model.meetings.first { $0.id == id }?.meeting.displayTitle
                            }, onCitation: { _ in }, onMeetingCitation: { id, time in model.openCitation(meetingId: id, time: time) })
                            .id(record.id)
                        }
                        if model.asking == .all {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text("正在找相關的會議，再用 \(AppSettings.provider.shortLabel) 回答…").foregroundStyle(.secondary)
                                Button("取消") { model.cancelAsk() }.buttonStyle(.link)
                            }
                        }
                    }
                    .contentFont()   // 文字大小（design §38.5）
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.allQuestions.count) { _, _ in
                    if let last = model.allQuestions.last?.id { withAnimation { proxy.scrollTo(last, anchor: .top) } }
                }
            }
            Divider()
            AskInputBar(question: $question,
                        placeholder: current == .folder
                            ? String(localized: "問「\(model.askFolder ?? "")」裡的會議，例如：還有哪些待辦沒完成？")
                            : String(localized: "問所有會議，例如：寄信的機制最後怎麼決定的？"),
                        busy: model.asking != nil, onClear: model.allQuestions.isEmpty ? nil : { model.clearQuestions(meetingId: nil) }) {
                model.askAll(question, scope: current)
                question = ""
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .contentTextScale()
        .onAppear { model.loadAllQuestions() }
    }
}
