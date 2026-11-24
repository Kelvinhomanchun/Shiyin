import Foundation
import GRDB

/// 側欄「人物」的一列（design §60.1、R85.1）
struct PersonOverview: Identifiable, Hashable {
    var id: Int64
    var name: String
    var meetingCount: Int
    var lastMeetingDate: String?
    /// 錄過「我的聲音」的人（R80）
    var isMe: Bool
    /// 使用者放進的人物群組（fork）；nil：未分組
    var group: String? = nil
}

/// 人物頁的一場會議：他說了多久（秒）
struct PersonMeeting: Identifiable, Hashable {
    var meeting: Meeting
    var seconds: Double
    var id: Int64 { meeting.id ?? 0 }
}

/// 人物頁的一條待辦：負責人是他（R85.3）
struct PersonActionItem: Identifiable, Hashable {
    var meeting: Meeting
    var index: Int
    var item: MeetingNotes.ActionItem
    var id: String { "\(meeting.id ?? 0)-\(index)" }
}

extension AppDatabase {
    /// 認識的人：一起開過幾場（不在垃圾桶的）、最近一場的日期；我排第一，其他照最近一場由新到舊
    func peopleOverview() throws -> [PersonOverview] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.id, p.name,
                  (SELECT count(DISTINCT s.meeting_id) FROM speakers s JOIN meetings m ON m.id = s.meeting_id
                     WHERE s.person_id = p.id AND m.deleted_at IS NULL) AS meetings,
                  (SELECT max(m.meeting_date) FROM speakers s JOIN meetings m ON m.id = s.meeting_id
                     WHERE s.person_id = p.id AND m.deleted_at IS NULL) AS last_date,
                  EXISTS (SELECT 1 FROM voiceprints v WHERE v.person_id = p.id AND v.audio_source = 'enroll') AS me,
                  p.group_name
                FROM people p
                """).map { row in
                    PersonOverview(id: row["id"], name: row["name"], meetingCount: row["meetings"],
                                   lastMeetingDate: row["last_date"], isMe: row["me"], group: row["group_name"])
                }
        }
        // 依名字排（使用者要的，fork）；你自己放最上面
        .sorted { a, b in
            if a.isMe != b.isMe { return a.isMe }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 每場會議連到哪些人物（說話者對到的人；列表的「有誰參加」篩選，design §71）
    func meetingPeople() throws -> [Int64: Set<Int64>] {
        try pool.read { db in
            var result: [Int64: Set<Int64>] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT DISTINCT meeting_id, person_id FROM speakers WHERE person_id IS NOT NULL") {
                result[row["meeting_id"], default: []].insert(row["person_id"])
            }
            return result
        }
    }

    /// 他出現過的會議（不在垃圾桶），說了多久是那場他的說話者的正式逐字稿加總；照日期由新到舊
    func personMeetings(_ personId: Int64) throws -> [PersonMeeting] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.meeting_id,
                  (SELECT COALESCE(SUM(g."end" - g.start), 0) FROM segments g
                     WHERE g.meeting_id = s.meeting_id AND g.kind = 'final' AND g.speaker = s.idx) AS seconds
                FROM speakers s JOIN meetings m ON m.id = s.meeting_id
                WHERE s.person_id = ? AND m.deleted_at IS NULL
                """, arguments: [personId])
            var seconds: [Int64: Double] = [:]
            for row in rows { seconds[row["meeting_id"], default: 0] += row["seconds"] }
            return try seconds.compactMap { id, total in
                try Meeting.fetchOne(db, key: id).map { PersonMeeting(meeting: $0, seconds: total) }
            }
            .sorted { ($0.meeting.meetingDate, $0.id) > ($1.meeting.meetingDate, $1.id) }
        }
    }

    /// 負責人跟名字一樣或包含名字（不分大小寫，同本地 MCP 的 list_action_items）的待辦；照會議日期由新到舊、會議裡的順序
    func personActionItems(_ name: String) throws -> [PersonActionItem] {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return [] }
        let meetings = try pool.read { db in
            try Meeting.filter(Column("deleted_at") == nil && Column("notes") != nil && Column("notes") != "")
                .order(sql: "meeting_date DESC, id DESC").fetchAll(db)
        }
        return meetings.flatMap { meeting -> [PersonActionItem] in
            guard let notes = meeting.decodedNotes else { return [] }
            return notes.actionItems.enumerated().compactMap { index, item in
                item.owner.range(of: target, options: .caseInsensitive) != nil
                    ? PersonActionItem(meeting: meeting, index: index, item: item) : nil
            }
        }
    }
}

/// 側欄是會議還是人物（design §60.2）
enum SidebarMode: String {
    case meetings, people
}

/// 人物頁（design §60、R85）
extension AppModel {
    func reloadPeopleOverview() {
        peopleOverview = (try? db.peopleOverview()) ?? []
        stakeholderRecordsCache = nil
        personGroups = (try? db.personGroups()) ?? []
        meetingPeople = (try? db.meetingPeople()) ?? [:]
        if let filtered = meetingFilter.personId, !peopleOverview.contains(where: { $0.id == filtered }) { meetingFilter.personId = nil }
        if let selected = selectedPerson, !peopleOverview.contains(where: { $0.id == selected }) { selectedPerson = nil }
    }

    // MARK: 利害關係人分析（fork）

    func loadStakeholder(_ personId: Int64) {
        stakeholderMe = (try? db.myPersonIds()) ?? []
        stakeholder = (try? db.stakeholderProfile(personId)).flatMap { $0 }
        stakeholderPersonId = personId
    }

    /// 這個人正在分析中（排隊或執行中）
    func isAnalyzingStakeholder(_ personId: Int64) -> Bool { analyzingStakeholders.contains(personId) }

    /// 從他全部的會議重新分析（人物頁的按鈕）。工作要掛在一場會議上：用他最近的一場
    func analyzeStakeholder(_ personId: Int64) {
        guard let meetingId = (try? db.personMeetings(personId))?.first?.id else {
            noticeMessage = String(localized: "這個人還沒有出現在任何會議裡")
            return
        }
        if let reason = askUnavailableReason { errorMessage = reason; return }
        let payload = (try? JSONEncoder().encode(JobRunner.StakeholderPayload(personId: personId))).flatMap { String(data: $0, encoding: .utf8) }
        do { _ = try db.enqueue(meetingId, kind: .stakeholders, payload: payload) } catch { errorMessage = error.localizedDescription; return }
        analyzingStakeholders.insert(personId)
        runner.wake()
    }

    /// 使用者填的角色、組織、背景：存起來、重新分析這個人
    func saveStakeholderContext(_ personId: Int64, role: String, org: String, notes: String) {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        do { try db.saveStakeholderContext(personId, role: trim(role), org: trim(org), notes: trim(notes)) }
        catch { errorMessage = error.localizedDescription; return }
        loadStakeholder(personId)
        if askUnavailableReason == nil { analyzeStakeholder(personId) }
    }

    /// 關係人地圖：每個分析過的人，可以只看一個資料夾裡的會議出現過的人
    func stakeholderMap(folder: String?, group: String? = nil) -> [(person: PersonOverview, record: StakeholderRecord, profile: StakeholderProfile)] {
        let records = (try? db.allStakeholderProfiles()) ?? []
        let allowed: Set<Int64>? = folder.map { f in
            let ids = Set(meetings.filter { $0.meeting.isIn(folder: f) }.map(\.id))
            return Set(meetingPeople.filter { ids.contains($0.key) }.flatMap(\.value))
        }
        return records.compactMap { r in
            guard let person = peopleOverview.first(where: { $0.id == r.personId }), let profile = r.decoded,
                  allowed?.contains(r.personId) ?? true,
                  group.map({ g in person.group?.caseInsensitiveCompare(g) == .orderedSame }) ?? true else { return nil }
            return (person, r, profile)
        }
    }

    /// 人物群組標題的選單：只看這個群組的人（資料夾維持原本選的）
    func openStakeholderMap(group: String) {
        stakeholderMapGroup = group
        stakeholderMapChosen = true
        openWindowById?("stakeholders")
    }

    /// 資料夾的右鍵選單：打開這個資料夾的關係人地圖
    func openStakeholderMap(folder: String?) {
        stakeholderMapFolder = folder ?? ""
        stakeholderMapChosen = true
        openWindowById?("stakeholders")
    }

    /// 滑過名字的小卡用：每個人的分析（不在人物頁也讀得到），會議頁打開時讀一次
    func stakeholderSummary(_ personId: Int64) -> StakeholderProfile? {
        if let cached = stakeholderCache[personId] { return cached }
        let profile = (try? db.stakeholderProfile(personId))??.decoded
        stakeholderCache[personId] = profile
        return profile
    }

    /// 搜尋人物（fork）：名字、你填的或推測的角色、組織、群組裡有這段字的人
    func peopleMatching(_ query: String) -> [PersonOverview] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        if stakeholderRecordsCache == nil { stakeholderRecordsCache = (try? db.allStakeholderProfiles()) ?? [] }
        let records = Dictionary((stakeholderRecordsCache ?? []).map { ($0.personId, $0) }, uniquingKeysWith: { a, _ in a })
        return peopleOverview.filter { p in
            if p.name.localizedCaseInsensitiveContains(q) || (p.group ?? "").localizedCaseInsensitiveContains(q) { return true }
            guard let r = records[p.id] else { return false }
            let profile = r.decoded
            return [r.userRole, r.userOrg, profile?.role ?? "", profile?.organization ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// 搜尋結果裡人名下面那一行：角色 · 組織（你填的優先）
    func personRoleLine(_ personId: Int64) -> String? {
        guard let r = (stakeholderRecordsCache ?? []).first(where: { $0.personId == personId }) else { return nil }
        let role = r.userRole.isEmpty ? (r.decoded?.role ?? "") : r.userRole
        let org = r.userOrg.isEmpty ? (r.decoded?.organization ?? "") : r.userOrg
        let line = [role, org].filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// 打開人物頁（從搜尋、會議裡的名字、待辦的負責人、地圖、小卡）：離開垃圾桶、展開「人物」和他的群組，
    /// 主視窗在後面時拉到前面（fork：使用者點了搜尋結果沒反應）
    func openPerson(_ personId: Int64) {
        if peopleOverview.first(where: { $0.id == personId }) == nil { reloadPeopleOverview() }
        guard let person = peopleOverview.first(where: { $0.id == personId }) else {
            noticeMessage = String(localized: "找不到這個人，可能已經合併或移除了")
            return
        }
        showTrash = false
        sidebarMode = .people
        selectedPerson = personId
        setSection("people", expanded: true)
        if let group = person.group { setSection(Self.personGroupKey(group), expanded: true) }
        openMainWindow?()
    }

    func stakeholdersFinished(_ job: Job, error: Error?) {
        let payload = job.payload.flatMap { try? JSONDecoder().decode(JobRunner.StakeholderPayload.self, from: Data($0.utf8)) }
        guard let personId = payload?.personId else { return }
        analyzingStakeholders.remove(personId)
        if let error, stakeholderPersonId == personId { errorMessage = String(localized: "分析失敗：\(error.localizedDescription)") }
    }

    /// 重新分析所有認得名字的人（你自己除外），每人從他所有的會議重做；已經在分析的跳過
    func reanalyzeAllStakeholders() {
        if let reason = askUnavailableReason { errorMessage = reason; return }
        let me = (try? db.myPersonIds()) ?? []
        let people = peopleOverview.filter { !me.contains($0.id) && !$0.isMe && $0.meetingCount > 0 && !analyzingStakeholders.contains($0.id) }
        for person in people { analyzeStakeholder(person.id) }
        noticeMessage = people.isEmpty ? String(localized: "沒有要分析的人")
            : String(localized: "開始重新分析 \(people.count) 個人，每人大約半分鐘，在背景進行")
    }

    func stakeholderUpdated(_ personId: Int64) {
        stakeholderCache[personId] = nil
        stakeholderRecordsCache = nil
        analyzingStakeholders.remove(personId)
        if stakeholderPersonId == personId { loadStakeholder(personId) }
    }

    /// 從人物頁打開一場會議（切回「會議」）；有時間點時從那裡播放
    func openFromPersonPage(_ meetingId: Int64, seconds: Double? = nil) {
        sidebarMode = .meetings   // reveal 也會設，這裡先設讓右邊馬上換
        if let seconds {
            openMeetingLink(meetingId, seconds: seconds, activate: false)
        } else {
            reveal(meetingId)
        }
    }

    /// 他負責的待辦一次加到提醒事項（R85.2、§52）：照各自的會議加，加過的不重複
    func addPersonItemsToReminders(_ items: [PersonActionItem]) {
        guard !items.isEmpty, !addingReminders else { return }
        addingReminders = true
        Task {
            defer { addingReminders = false }
            let store = Reminders.store
            if store.access == .notDetermined { _ = await store.requestAccess() }
            guard store.access == .granted else {
                errorMessage = String(localized: "拾音沒有使用提醒事項的權限：請到「系統設定 → 隱私權與安全性 → 提醒事項」允許拾音。")
                return
            }
            do {
                let list = try store.list()
                var added = 0
                for (meetingId, group) in Dictionary(grouping: items, by: { $0.meeting.id ?? 0 }) {
                    guard let meeting = group.first?.meeting, let notes = meeting.decodedNotes else { continue }
                    let keys = Set(group.map { Reminders.key($0.item.task) })
                    let existing = try await store.existing(meetingId: meetingId)
                    let fresh = Reminders.items(meeting: meeting, notes: notes).filter { keys.contains($0.key) && existing[$0.key] == nil }
                    try store.add(fresh, to: list)
                    added += fresh.count
                }
                noticeMessage = added == 0 ? String(localized: "這些待辦都已經在提醒事項了")
                    : String(localized: "已加到提醒事項的「\(Reminders.listTitle)」列表：\(added) 項")
            } catch {
                errorMessage = String(localized: "沒辦法加到提醒事項：\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 待辦完成了（fork，UX 檢查 B1）

enum ActionDone {
    /// 會議＋事項內容（同提醒事項的鍵）：「會議 id:鍵」
    static func key(_ meetingId: Int64, _ task: String) -> String { "\(meetingId):\(Reminders.key(task))" }
}

extension AppDatabase {
    /// 所有完成了的待辦（「會議 id:鍵」）
    func doneActionItems() throws -> Set<String> {
        try pool.read { db in
            Set(try Row.fetchAll(db, sql: "SELECT meeting_id, task_key FROM action_done").map { row in
                "\(row["meeting_id"] as Int64):\(row["task_key"] as String)"
            })
        }
    }

    func setActionDone(_ meetingId: Int64, task: String, done: Bool) throws {
        try pool.write { db in
            if done {
                try db.execute(sql: "INSERT OR REPLACE INTO action_done (meeting_id, task_key, done_at) VALUES (?, ?, ?)",
                               arguments: [meetingId, Reminders.key(task), Clock.now()])
            } else {
                try db.execute(sql: "DELETE FROM action_done WHERE meeting_id = ? AND task_key = ?", arguments: [meetingId, Reminders.key(task)])
            }
        }
    }
}

extension AppModel {
    func isActionDone(_ meetingId: Int64?, _ task: String) -> Bool {
        guard let meetingId else { return false }
        return actionDone.contains(ActionDone.key(meetingId, task)) || reminderStatus[Reminders.key(task)] == true
    }

    func toggleActionDone(_ meetingId: Int64?, _ task: String) {
        guard let meetingId else { return }
        let done = !isActionDone(meetingId, task)
        do { try db.setActionDone(meetingId, task: task, done: done) } catch { errorMessage = error.localizedDescription; return }
        reloadActionDone()
    }

    func reloadActionDone() { actionDone = (try? db.doneActionItems()) ?? [] }
}


// MARK: - 人物群組（fork）：使用者自己建、自己把人放進去，像資料夾

extension AppDatabase {
    func personGroups() throws -> [String] {
        try pool.read { db in try String.fetchAll(db, sql: "SELECT name FROM person_groups ORDER BY position, name COLLATE NOCASE") }
    }

    func createPersonGroup(_ name: String) throws {
        try pool.write { db in
            let next = try Int.fetchOne(db, sql: "SELECT coalesce(max(position), 0) + 1 FROM person_groups") ?? 1
            try db.execute(sql: "INSERT OR IGNORE INTO person_groups (name, position, created_at) VALUES (?, ?, ?)",
                           arguments: [name, next, Clock.now()])
        }
    }

    /// 改名（同名已經有時併過去）
    func renamePersonGroup(_ old: String, to new: String) throws {
        try pool.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM person_groups WHERE name = ? AND name <> ?)", arguments: [new, old]) ?? false
            if exists {
                try db.execute(sql: "DELETE FROM person_groups WHERE name = ?", arguments: [old])
            } else {
                try db.execute(sql: "UPDATE person_groups SET name = ? WHERE name = ?", arguments: [new, old])
            }
            try db.execute(sql: "UPDATE people SET group_name = ? WHERE group_name = ? COLLATE NOCASE", arguments: [new, old])
        }
    }

    /// 刪群組：裡面的人回到未分組，人不會被刪
    func deletePersonGroup(_ name: String) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM person_groups WHERE name = ?", arguments: [name])
            try db.execute(sql: "UPDATE people SET group_name = NULL WHERE group_name = ? COLLATE NOCASE", arguments: [name])
        }
    }

    func movePersonGroup(_ name: String, before other: String?) throws {
        try pool.write { db in
            var names = try String.fetchAll(db, sql: "SELECT name FROM person_groups ORDER BY position, name COLLATE NOCASE")
            names.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
            let index = other.flatMap { o in names.firstIndex { $0.caseInsensitiveCompare(o) == .orderedSame } } ?? names.count
            names.insert(name, at: index)
            for (position, n) in names.enumerated() {
                try db.execute(sql: "UPDATE person_groups SET position = ? WHERE name = ?", arguments: [position, n])
            }
        }
    }

    /// nil：移出群組
    func setPersonGroup(_ ids: [Int64], group: String?) throws {
        try pool.write { db in
            if let group {
                try db.execute(sql: "INSERT OR IGNORE INTO person_groups (name, position, created_at) VALUES (?, (SELECT coalesce(max(position), 0) + 1 FROM person_groups), ?)",
                               arguments: [group, Clock.now()])
            }
            for id in ids {
                try db.execute(sql: "UPDATE people SET group_name = ? WHERE id = ?", arguments: [group, id])
            }
        }
    }
}

extension AppModel {
    /// 側欄人物的分段：使用者的群組（照順序，空的也顯示），最後是未分組
    var peopleSections: [(group: String?, people: [PersonOverview])] {
        var result: [(group: String?, people: [PersonOverview])] = personGroups.map { name in
            (name, peopleOverview.filter { $0.group?.caseInsensitiveCompare(name) == .orderedSame })
        }
        let known = Set(personGroups.map { $0.lowercased() })
        result.append((nil, peopleOverview.filter { $0.group.map { !known.contains($0.lowercased()) } ?? true }))
        return result
    }

    static func personGroupKey(_ name: String?) -> String { name.map { "pgroup:\($0.lowercased())" } ?? "pgroup:" }

    func reloadPersonGroups() { personGroups = (try? db.personGroups()) ?? [] }

    func createPersonGroup(_ name: String, adding ids: [Int64] = []) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        perform {
            try db.createPersonGroup(name)
            if !ids.isEmpty { try db.setPersonGroup(ids, group: name) }
        }
        reloadPersonGroups(); reloadPeopleOverview()
    }

    func renamePersonGroup(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != old else { return }
        perform { try db.renamePersonGroup(old, to: new) }
        reloadPersonGroups(); reloadPeopleOverview()
    }

    func deletePersonGroup(_ name: String) {
        perform { try db.deletePersonGroup(name) }
        reloadPersonGroups(); reloadPeopleOverview()
    }

    func movePersonGroup(_ name: String, before other: String?) {
        perform { try db.movePersonGroup(name, before: other) }
        reloadPersonGroups()
    }

    func setPersonGroup(_ ids: [Int64], group: String?) {
        guard !ids.isEmpty else { return }
        perform { try db.setPersonGroup(ids, group: group) }
        reloadPersonGroups(); reloadPeopleOverview()
    }

    /// 人物右鍵選單的「移到群組」
    func personGroupMenu(_ person: PersonOverview) -> MenuEntry {
        var items: [MenuEntry] = personGroups.map { name in
            .action(name, icon: person.group?.caseInsensitiveCompare(name) == .orderedSame ? "checkmark" : "person.3",
                    enabled: person.group?.caseInsensitiveCompare(name) != .orderedSame) { self.setPersonGroup([person.id], group: name) }
        }
        if !items.isEmpty { items.append(.divider) }
        items.append(.action(String(localized: "新群組…"), icon: "plus") { self.renameTarget = .newPersonGroup([person.id]) })
        if person.group != nil {
            items.append(.action(String(localized: "移出群組"), icon: "minus.circle") { self.setPersonGroup([person.id], group: nil) })
        }
        return .submenu(String(localized: "移到群組"), icon: "person.3", items)
    }

    /// 群組標題的選單
    func personGroupHeaderMenu(_ name: String) -> [MenuEntry] {
        [.action(String(localized: "重新命名群組…"), icon: "pencil") { self.renameTarget = .personGroup(name) },
         .action(String(localized: "這個群組的關係人地圖"), icon: "square.grid.2x2") { self.openStakeholderMap(group: name) },
         .divider,
         .action(String(localized: "刪除群組"), icon: "trash", destructive: true) { self.deletePersonGroup(name) }]
    }
}
