import SwiftUI
import UniformTypeIdentifiers

/// 工作坊（fork）的彈窗：加問題、貼流程文字、對草稿提意見
enum WorkshopSheetRequest: Identifiable, Equatable {
    case questions(stepRef: String = "")
    case draftText
    case draftComment
    var id: String {
        switch self {
        case .questions(let ref): "questions-\(ref)"
        case .draftText: "draftText"
        case .draftComment: "draftComment"
        }
    }
}

/// 選一個檔案（Word、PDF、文字…讀得出文字的都可以）
@MainActor
func pickWorkshopFile(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = prompt
    return panel.runModal() == .OK ? panel.url : nil
}

struct WorkshopSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: WorkshopSheetRequest
    @State private var text = ""
    @FocusState private var focused: Bool

    private var title: String {
        switch request {
        case .questions: String(localized: "加問題")
        case .draftText: String(localized: "從文字整理成流程")
        case .draftComment: String(localized: "對草稿提意見")
        }
    }
    private var subtitle: String {
        switch request {
        case .questions: String(localized: "一行一題，貼上整份清單也可以。編號（QST-）會自動接下去，之後整理時每一題都會有回答或「沒問到」。")
        case .draftText: String(localized: "貼上流程的描述（郵件、會議筆記、文件的一段）。整理工具會整理成一張草稿流程圖，你再拿去給客戶驗證。")
        case .draftComment: String(localized: "說哪裡要改。之前的意見也會一起考慮。")
        }
    }
    private var placeholder: String {
        switch request {
        case .questions: String(localized: "例如：\n誰負責核對月底的保費數字？\n如果檔案晚到，現在怎麼處理？")
        case .draftText: String(localized: "例如：每月五號 AMS 會寄出理賠檔案，Shing 下載後改檔名、放進 SharePoint，再更新 Power BI 報表…")
        case .draftComment: String(localized: "例如：核對和批准是兩步，不要合在一起；少畫例外")
        }
    }
    private var count: Int { Workshop.parseQuestions(text).count }
    private var sendTitle: String {
        switch request {
        case .questions: count > 0 ? String(localized: "加 \(count) 個問題") : String(localized: "加問題")
        case .draftText: String(localized: "整理成流程")
        case .draftComment: String(localized: "重新畫")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: title, subtitle: subtitle)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.vertical, 9).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .focused($focused)
                    .accessibilityLabel(Text(title))
            }
            .frame(minHeight: 140, maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.25)))
            HStack(spacing: 10) {
                if request != .draftComment {
                    Button(String(localized: "從檔案讀入…"), systemImage: "doc.badge.plus") {
                        guard let url = pickWorkshopFile(prompt: String(localized: "選一個 Word、PDF 或文字檔")) else { return }
                        if case .questions = request { model.importQuestionsFile(url) } else { model.importDraftFile(url) }
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.celadon)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SheetPillButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(sendTitle) { send() }
                    .buttonStyle(SheetPillButtonStyle(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheetChrome(width: 520)
        .onAppear { focused = true }
    }

    private func send() {
        switch request {
        case .questions(let ref):
            model.addQuestions(Workshop.parseQuestions(text), stepRef: ref)
            dismiss()
        case .draftText:
            if model.draftFromText(text) { dismiss() }
        case .draftComment:
            let plan = model.detail?.workshop?.plan
            if model.draftFromText(plan?.draftText ?? "", source: nil, comment: text) { dismiss() }
        }
    }
}
