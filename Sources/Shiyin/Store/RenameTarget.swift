import Foundation

/// 重新命名的彈窗要改的東西（R102、design §76）
enum RenameTarget: Identifiable, Equatable {
    case meeting(Int64)
    case folder(String)
    /// 新資料夾：建立後把這幾場會議移進去
    case newFolder([Int64])
    /// 在這個上層資料夾裡建子資料夾（fork：客戶 → 案子）
    case newSubfolder(String)
    case person(Int64)
    case bookmark(Int64)
    /// 人物群組（fork）：新群組（建立後把這幾個人放進去）、改群組名稱
    case newPersonGroup([Int64])
    case personGroup(String)

    var id: String { "\(self)" }
}

extension AppModel {
    /// 彈窗打開時輸入框裡的字
    func currentName(for target: RenameTarget) -> String {
        switch target {
        case .meeting(let id):
            guard let meeting = (meetings + trash).first(where: { $0.id == id })?.meeting ?? (try? db.meeting(id)) else { return "" }
            return meeting.title.isEmpty ? meeting.displayTitle : meeting.title
        case .folder(let name): return FolderPath.project(name) ?? name
        case .newFolder, .newSubfolder, .newPersonGroup: return ""
        case .personGroup(let name): return name
        case .person(let id):
            // 人物總覽只在打開過人物列表後才有；沒有時從資料庫讀
            return peopleOverview.first { $0.id == id }?.name ?? ((try? db.peopleSummaries()) ?? people).first { $0.id == id }?.name ?? ""
        case .bookmark(let id): return detail?.bookmarks.first { $0.id == id }?.label ?? ""
        }
    }

    /// 改成這個名字會跟別的東西合併時，那個東西的名字（資料夾同名、人物同名大小寫不分）
    func renameConflict(for target: RenameTarget, name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        switch target {
        case .folder(let old):
            let path = FolderPath.isSub(old) ? FolderPath.join(FolderPath.account(old), FolderPath.clean(name)) : FolderPath.clean(name)
            return path != old && folders.contains { $0.name == path } ? FolderPath.display(path) : nil
        case .newFolder:
            return folders.contains { $0.name == FolderPath.clean(name) } ? name : nil
        case .newSubfolder(let parent):
            let path = FolderPath.join(parent, FolderPath.clean(name))
            return folders.contains { $0.name == path } ? FolderPath.display(path) : nil
        case .newPersonGroup:
            return personGroups.first { $0.caseInsensitiveCompare(name) == .orderedSame }
        case .personGroup(let old):
            return personGroups.first { $0.caseInsensitiveCompare(name) == .orderedSame && $0.caseInsensitiveCompare(old) != .orderedSame }
        case .person(let id):
            let all = peopleOverview.isEmpty ? ((try? db.peopleSummaries()) ?? people).map { ($0.id, $0.name) } : peopleOverview.map { ($0.id, $0.name) }
            return all.first { $0.0 != id && $0.1.caseInsensitiveCompare(name) == .orderedSame }?.1
        default:
            return nil
        }
    }

    /// 彈窗按「儲存」（或「建立並移入」）
    func commitRename(_ target: RenameTarget, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch target {
        case .meeting(let id):
            guard let meeting = try? db.meeting(id), name != currentName(for: target) else { return }
            perform { try db.updateInfo(id, title: name, date: meeting.meetingDate, participants: meeting.participants) }
        case .folder(let old): renameFolder(old, to: name)
        case .newFolder(let ids):
            // 「+」建的是空的資料夾（R104），從會議的選單建的會把會議移進去
            if ids.isEmpty { createFolder(FolderPath.clean(name)) } else { moveToFolder(ids, folder: FolderPath.clean(name)) }
        case .newSubfolder(let parent): createSubfolder(name, in: parent)
        case .person(let id):
            renamePerson(id, to: name)
            // 改成已經有的名字時合併過去，選那個人
            if sidebarMode == .people {
                selectedPerson = peopleOverview.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            }
        case .bookmark(let id): renameBookmark(id, label: name)
        case .newPersonGroup(let ids): createPersonGroup(name, adding: ids)
        case .personGroup(let old): renamePersonGroup(old, to: name)
        }
    }
}
