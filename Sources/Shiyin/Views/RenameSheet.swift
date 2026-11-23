import SwiftUI

/// 重新命名的彈窗（R102、design §76）：標題、一行說明、帶目前名字的輸入框、取消／儲存。
/// 會議、資料夾、新資料夾、人物、標記都用這一個
struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: RenameTarget
    @State private var name = ""
    @State private var original = ""

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 「+」建空的資料夾時，同名的已經有就不能建（R104）
        let canSave = !trimmed.isEmpty && (isNewFolder || trimmed != original) && !(isEmptyNewFolder && model.renameConflict(for: target, name: trimmed) != nil)
        // 共用的彈窗元件（design §80）
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: title, subtitle: hint(trimmed))
            SheetTextField(placeholder: placeholder, text: $name, focusOnAppear: true) { if canSave { save() } }
            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SheetPillButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(isEmptyNewFolder ? String(localized: "建立") : isNewFolder ? String(localized: "建立並移入") : String(localized: "儲存")) { save() }
                    .buttonStyle(SheetPillButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .sheetChrome()
        .onAppear {
            original = model.currentName(for: target)
            name = original
        }
    }

    private var isNewFolder: Bool {
        switch target { case .newFolder, .newSubfolder, .newPersonGroup: true; default: false }
    }
    private var isEmptyNewFolder: Bool {
        switch target { case .newFolder(let ids): ids.isEmpty; case .newSubfolder: true; case .newPersonGroup(let ids): ids.isEmpty; default: false }
    }

    private func save() {
        model.commitRename(target, to: name)
        dismiss()
    }

    private var title: String {
        switch target {
        case .meeting: String(localized: "重新命名會議")
        case .folder: String(localized: "重新命名資料夾")
        case .newFolder: String(localized: "新資料夾")
        case .newSubfolder(let parent): String(localized: "在「\(parent)」裡新增子資料夾")
        case .person: String(localized: "重新命名這個人")
        case .bookmark: String(localized: "重新命名標記")
        case .newPersonGroup: String(localized: "新人物群組")
        case .personGroup: String(localized: "重新命名群組")
        }
    }

    private var placeholder: String {
        switch target {
        case .folder, .newFolder: String(localized: "資料夾名稱")
        case .newSubfolder: String(localized: "子資料夾名稱（例如案子名稱）")
        case .newPersonGroup, .personGroup: String(localized: "群組名稱")
        case .person: String(localized: "名字")
        default: String(localized: "名稱")
        }
    }

    /// 說明；改成會合併的名字時換成提醒
    private func hint(_ name: String) -> String {
        if let other = model.renameConflict(for: target, name: name) {
            switch target {
            case .newFolder(let ids) where ids.isEmpty: return String(localized: "已經有「\(other)」。")
            case .newSubfolder: return String(localized: "已經有「\(other)」。")
            case .newPersonGroup(let ids) where ids.isEmpty: return String(localized: "已經有「\(other)」。")
            case .newPersonGroup: return String(localized: "已經有「\(other)」，會放進那個群組。")
            case .newFolder: return String(localized: "已經有「\(other)」，會議會移進那個資料夾。")
            default: return String(localized: "已經有「\(other)」，儲存後會合併成一個。")
            }
        }
        switch target {
        case .meeting: return String(localized: "保持簡短、容易辨識。日期和與會者在會議頁的「編輯」改。")
        case .folder: return String(localized: "資料夾裡的會議都會跟著改。")
        case .newFolder(let ids) where ids.isEmpty: return String(localized: "例如客戶名稱；之後可以在裡面建案子的子資料夾。")
        case .newSubfolder(let parent): return String(localized: "例如案子名稱。在「\(parent)」看得到所有子資料夾的會議。")
        case .newFolder(let ids):
            return ids.count > 1 ? String(localized: "例如專案名稱或客戶名稱。這 \(ids.count) 場會議會移進新資料夾。")
                                 : String(localized: "例如專案名稱或客戶名稱。這場會議會移進新資料夾。")
        case .person: return String(localized: "所有會議裡的這個人都會跟著改。")
        case .newPersonGroup(let ids) where ids.isEmpty: return String(localized: "例如「HKJC 客戶」「IBM 團隊」「面試者」。把人拖進群組，或在人的選單選「移到群組」。")
        case .newPersonGroup: return String(localized: "例如「HKJC 客戶」「IBM 團隊」「面試者」。這個人會放進新群組。")
        case .personGroup: return String(localized: "群組裡的人都會跟著移過去。")
        case .bookmark(let id):
            let time = model.detail?.bookmarks.first { $0.id == id }?.time ?? 0
            return String(localized: "\(TimeFormat.string(time)) 的標記")
        }
    }
}
