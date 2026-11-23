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
