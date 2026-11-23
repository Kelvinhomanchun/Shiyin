import Foundation

/// 資料夾可以有一層子資料夾（fork）：上層當客戶、子資料夾當案子。
/// 子資料夾存成「上層/子資料夾」，會議的 folder、資料夾表、條件、MCP 都照舊用這個字串，舊的資料不用改。
/// 「在這個資料夾裡」＝ 就是這個資料夾或它的子資料夾（上層資料夾看得到全部的案子）
enum FolderPath {
    static let separator: Character = "/"

    /// 上層資料夾（客戶）；沒有子資料夾時就是自己
    static func account(_ folder: String) -> String {
        folder.split(separator: separator, maxSplits: 1).first.map(String.init) ?? folder
    }

    /// 子資料夾的名字（案子）；上層資料夾是 nil
    static func project(_ folder: String) -> String? {
        let parts = folder.split(separator: separator, maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : nil
    }

    static func isSub(_ folder: String) -> Bool { project(folder) != nil }

    static func join(_ account: String, _ project: String) -> String { "\(account)\(separator)\(project)" }

    /// folder 是 scope 本身或在它底下
    static func contains(_ scope: String, _ folder: String) -> Bool {
        !scope.isEmpty && (folder == scope || (!isSub(scope) && folder.hasPrefix(scope + String(separator))))
    }

    /// 顯示用：「客戶 › 案子」
    static func display(_ folder: String) -> String {
        guard let project = project(folder) else { return folder }
        return "\(account(folder)) › \(project)"
    }

    /// 名字裡不能有分隔字元（會被當成子資料夾），換成全形
    static func clean(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: String(separator), with: "／")
    }
}

extension Meeting {
    /// 會議在不在這個資料夾（包括它的子資料夾）裡
    func isIn(folder scope: String) -> Bool { FolderPath.contains(scope, folder) }
}

import SwiftUI

/// 選一個資料夾的選單（fork，Ask、關係人地圖共用）：上層（客戶）是一段，第一項「整個 <客戶>」，
/// 下面縮排列它的案子；不把客戶和案子攤成同一排（使用者：「為什麼都放在同一個下拉選單」）
struct FolderScopePicker: View {
    @Binding var selection: String
    /// 有會議的資料夾（上層、子資料夾都在裡面）
    let folders: [String]
    /// 有值：多一項「所有會議」（tag 是空字串）
    var allTitle: String? = nil

    private var accounts: [String] {
        var seen: [String] = []
        for f in folders { let a = FolderPath.account(f); if !seen.contains(a) { seen.append(a) } }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func projects(_ account: String) -> [String] {
        folders.filter { FolderPath.isSub($0) && FolderPath.account($0) == account }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var label: String {
        if selection.isEmpty { return allTitle ?? "" }
        return FolderPath.project(selection) ?? selection
    }

    var body: some View {
        Menu {
            if let allTitle {
                Button { selection = "" } label: { check(selection.isEmpty, allTitle) }
                Divider()
            }
            ForEach(accounts, id: \.self) { account in
                let children = projects(account)
                if children.isEmpty {
                    Button { selection = account } label: { check(selection == account, account, icon: "folder") }
                } else {
                    Section(account) {
                        Button { selection = account } label: { check(selection == account, String(localized: "整個「\(account)」"), icon: "folder") }
                        ForEach(children, id: \.self) { path in
                            Button { selection = path } label: { check(selection == path, "    " + (FolderPath.project(path) ?? path)) }
                        }
                    }
                }
            }
        } label: {
            Label(label, systemImage: selection.isEmpty ? "tray.full" : FolderPath.isSub(selection) ? "folder" : "folder.fill")
        }
        .fixedSize()
        .help(selection.isEmpty ? (allTitle ?? "") : FolderPath.display(selection))
    }

    @ViewBuilder private func check(_ on: Bool, _ title: String, icon: String? = nil) -> some View {
        if on { Label(title, systemImage: "checkmark") }
        else if let icon { Label(title, systemImage: icon) }
        else { Text(title) }
    }
}
