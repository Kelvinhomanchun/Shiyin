import Foundation

/// 每一種東西都能直接改、刪（R100、design §74）
extension AppModel {
    /// 重新命名一場會議：打開重新命名的彈窗（R102；日期、與會者照舊在會議頁的「編輯」改）
    func requestRenameMeeting(_ id: Int64) {
        renameTarget = .meeting(id)
    }

    /// 紀錄能不能就地改：有紀錄、不在垃圾桶、沒在錄這場、沒在整理（同「編輯」按鈕）
    var canEditNotes: Bool {
        guard let detail, detail.notes != nil, detail.meeting.deletedAt == nil else { return false }
        return detailStatus?.isActive != true && recorder.meetingId != detail.meeting.id
    }

    /// 就地改一條紀錄（雙擊、右鍵「編輯這一條」）：存成一個版本，同手動編輯
    func editNoteItem(_ ref: NoteItemRef, text: String) {
        editingNoteItem = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEditNotes, let id = detail?.meeting.id, var notes = detail?.notes, !trimmed.isEmpty,
              notes.text(at: ref) != trimmed else { return }
        notes.setText(trimmed, at: ref)
        saveEditedNotes(notes, meetingId: id)
    }

    /// 刪除一條紀錄：不確認，可以用「復原上一版會議紀錄」還原
    func deleteNoteItem(_ ref: NoteItemRef) {
        guard canEditNotes, let id = detail?.meeting.id, var notes = detail?.notes, notes.text(at: ref) != nil else { return }
        if editingNoteItem == ref { editingNoteItem = nil }
        notes.remove(at: ref)
        saveEditedNotes(notes, meetingId: id)
        noticeMessage = String(localized: "已刪除一條紀錄，按「編輯」旁的「復原上一版」可以還原")
    }

    func renameBookmark(_ id: Int64, label: String) {
        perform(.detail([.bookmarks])) { try db.renameBookmark(id, label: label.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func renameTerm(_ id: Int64, to term: String) { perform { try db.renameTerm(id, to: term) } }

    // MARK: 側欄的鍵盤：照現在選到、亮起來的是什麼

    /// Return：重新命名。回傳有沒有處理
    func sidebarReturn() -> Bool {
        guard !showTrash else { return false }
        if sidebarMode == .people {
            guard let id = selectedPerson else { return false }
            renameTarget = .person(id)
            return true
        }
        if selectedMeetings.count > 1 { return false }
        if let id = selection {
            requestRenameMeeting(id)
        } else if let folder = folderFilter {
            renameTarget = .folder(folder)
        } else {
            return false
        }
        return true
    }

    /// Delete：刪除或移除（都先確認）
    func sidebarDelete() {
        if sidebarMode == .people && !showTrash {
            if let id = selectedPerson { confirmRemovePerson = id }
            return
        }
        let ids = multiSelected.isEmpty ? [selection].compactMap { $0 } : multiSelected
        if !ids.isEmpty {
            if showTrash {
                confirmPurge = ids
            } else {
                deleteTargets = ids
                confirmDelete = true
            }
        } else if !showTrash, let folder = folderFilter {
            confirmDeleteFolder = folder
        }
    }
}


// MARK: - 用 AI 修正會議紀錄（fork）

/// 彈窗要修正的對象：整份紀錄，或右鍵選的那一條
struct RefineRequest: Identifiable, Equatable {
    var meetingId: Int64
    var ref: NoteItemRef?
    var text: String?
    var time: String?
    var id: String { "\(meetingId)-\(ref.map { "\($0)" } ?? "all")" }
}

extension AppModel {
    /// 打開「用 AI 修正」：跟「編輯」一樣的條件（有紀錄、不在垃圾桶、沒在錄、沒在整理）；整理工具沒設定時先說
    func requestRefine(_ ref: NoteItemRef? = nil, text: String? = nil, time: String? = nil) {
        guard let id = detail?.meeting.id else { return }
        guard canEditNotes else {
            noticeMessage = detail?.meeting.deletedAt != nil ? String(localized: "垃圾桶裡的會議要先還原才能操作")
                : String(localized: "這場會議還在處理中，完成後再試一次")
            return
        }
        if AppSettings.provider == .none {
            errorMessage = AppSettings.needsProviderSetup
                ? String(localized: "還沒設定整理工具，沒辦法用 AI 修正。請先到設定選擇 Claude、Codex 或 API")
                : String(localized: "整理工具設定為「不整理」，沒辦法用 AI 修正。請先到設定改成 Claude、Codex 或 API")
            return
        }
        if let problem = AppSettings.summarizerProblem { errorMessage = problem.message; return }
        refineRequest = RefineRequest(meetingId: id, ref: ref, text: text, time: time)
    }

    /// 送出修正：排一個校稿工作（同依回答修正那條線），完成後留一版可以復原
    @discardableResult
    func submitRefine(_ request: RefineRequest, instruction: String) -> Bool {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let meeting = try? db.meeting(request.meetingId), meeting.deletedAt == nil, meeting.decodedNotes != nil else {
            errorMessage = String(localized: "這場會議沒有會議紀錄可以修正")
            return false
        }
        if let latest = try? db.latestJob(request.meetingId), latest.status == .queued || latest.status == .running {
            noticeMessage = String(localized: "這場會議還在處理中，完成後再試一次")
            return false
        }
        var focus: String?
        if let text = request.text {
            let id: String
            switch request.ref {
            case .summary: id = "summary"
            case .decisions: id = "decisions"
            case .actionItems: id = "actionItems"
            case .openQuestions: id = "openQuestions"
            case .person: id = "people"
            case .custom(let c, _): id = meeting.decodedNotes?.custom.indices.contains(c) == true ? meeting.decodedNotes!.custom[c].title : "custom"
            default: id = "topics"
            }
            let label = ["summary", "decisions", "actionItems", "openQuestions", "people", "topics"].contains(id)
                ? TemplateDefinition.sectionLabel(id, language: meeting.notesOutputLanguage, prompt: true) : id
            focus = "[\(label)] " + text + ((request.time ?? "").isEmpty ? "" : " (\(request.time ?? ""))")
        }
        refineDraft[request.id] = trimmed
        perform {
            let payload = String(decoding: try JSONEncoder().encode(RevisePayload(answers: [], instruction: trimmed, focus: focus)), as: UTF8.self)
            try db.enqueue(request.meetingId, kind: .revise, payload: payload)
        }
        runner.wake()
        return true
    }
}
