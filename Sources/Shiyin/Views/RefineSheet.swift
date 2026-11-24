import SwiftUI

/// 用 AI 修正會議紀錄（fork）：打字告訴整理工具哪裡要補細節、哪裡不正確。
/// 整理工具會看逐字稿、參考文件和目前的紀錄，只改被要求的部分；完成後留一版，「復原上一版」可以換回來
struct RefineSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: RefineRequest
    @State private var text = ""
    @FocusState private var focused: Bool

    /// 常用的說法：點一下放進輸入框，再自己補完
    private var suggestions: [String] {
        if request.text != nil {
            return [String(localized: "這一條要更詳細，補上逐字稿裡講到的細節"),
                    String(localized: "這一條不正確，正確的是："),
                    String(localized: "把這一條拆成幾條"),
                    String(localized: "刪掉這一條")]
        }
        return [String(localized: "摘要寫得更詳細"),
                String(localized: "補上漏掉的決議和待辦"),
                String(localized: "這個主題的討論寫得更完整："),
                String(localized: "名字的正確寫法是：")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: request.text == nil ? String(localized: "用 AI 修正會議紀錄") : String(localized: "用 AI 修正這一條"),
                        subtitle: String(localized: "告訴整理工具哪裡要補細節、哪裡不正確。它會對照逐字稿和參考文件，只改你提到的地方。"))
            if let item = request.text {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Color.celadon).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item).font(.callout).fixedSize(horizontal: false, vertical: true).lineLimit(6)
                        if let time = request.time, !time.isEmpty { Text(time).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                SheetFieldLabel(String(localized: "要怎麼改"))
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(request.text == nil
                             ? String(localized: "例如：預算的討論寫得太簡略，補上數字和誰負責；Sandy 的職稱是 Head of Claims，不是 Claims Lead")
                             : String(localized: "例如：補上為什麼這樣決定；日期是 12 月 3 日不是 11 月 3 日"))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(5)
                        .focused($focused)
                        .accessibilityLabel(Text("要怎麼改"))
                }
                .frame(minHeight: 96, maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.25)))
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) {
                            text = text.isEmpty ? s : text + (text.hasSuffix("\n") ? "" : "\n") + s
                            focused = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .help("放進輸入框，再自己補完")
                    }
                }
            }
            Label("其他段落維持原樣。改完會留一版，按「復原上一版」可以換回來。", systemImage: "arrow.uturn.backward.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("⌘↩ 送出").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("取消") {
                    model.refineDraft[request.id] = text.isEmpty ? nil : text
                    dismiss()
                }
                .buttonStyle(SheetPillButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
                Button("修正") {
                    if model.submitRefine(request, instruction: text) { dismiss() }
                }
                .buttonStyle(SheetPillButtonStyle(.primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheetChrome(width: 520)
        .onAppear {
            // 上次沒送出或修正失敗時打的字填回去（同一份或同一條才填）
            if let draft = model.refineDraft[request.id] { text = draft }
            focused = true
        }
    }
}
