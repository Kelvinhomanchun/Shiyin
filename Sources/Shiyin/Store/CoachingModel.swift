import Foundation
import GRDB

/// 我的表現（fork）：自己人物頁的資料
extension AppModel {
    /// 打開自己的人物頁時讀：數字是現算的（不用整理工具），建議是存著的
    func loadCoaching(_ personId: Int64) {
        if let result = try? db.coachingStats(personId) {
            coachingStats = result.stats
            coachingSkipped = result.skipped
        }
        coaching = (try? db.coachingRecord(personId)).flatMap { $0 }
        coachingRunning = (try? db.hasQueuedJob(kind: .coaching)) ?? false
    }

    /// 「重新整理」：從我所有的會議重寫教練建議。工作要掛在一場會議上：用最近的一場
    func refreshCoaching(_ personId: Int64) {
        guard let meetingId = coachingStats.last?.id else {
            noticeMessage = String(localized: "你還沒有可以分析的會議")
            return
        }
        if let reason = askUnavailableReason { errorMessage = reason; return }
        let payload = (try? JSONEncoder().encode(JobRunner.CoachingPayload())).flatMap { String(data: $0, encoding: .utf8) }
        do { _ = try db.enqueue(meetingId, kind: .coaching, payload: payload) } catch { errorMessage = error.localizedDescription; return }
        coachingRunning = true
        runner.wake()
    }

    func coachingFinished(_ job: Job, error: Error?) {
        coachingRunning = (try? db.hasQueuedJob(kind: .coaching)) ?? false
        if let error, job.payload != nil { errorMessage = String(localized: "整理我的表現失敗：\(error.localizedDescription)") }
        if let me = stakeholderMe.sorted().first { loadCoaching(me) }
    }

    /// 「有用」：記下來（再按一次取消），之後重新整理時保留這一點
    func toggleUsefulCoachingFinding(_ personId: Int64, title: String) {
        do { try db.toggleUsefulCoachingFinding(personId, title: title) } catch { errorMessage = error.localizedDescription; return }
        coaching = (try? db.coachingRecord(personId)).flatMap { $0 }
    }

    /// 「不對」：拿掉這一點，之後不再寫
    func rejectCoachingFinding(_ personId: Int64, title: String) {
        do { try db.rejectCoachingFinding(personId, title: title) } catch { errorMessage = error.localizedDescription; return }
        loadCoaching(personId)
    }
}

extension AppDatabase {
    /// 有沒有這種工作在排隊或執行中
    func hasQueuedJob(kind: JobKind) throws -> Bool {
        try pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT 1 FROM jobs WHERE kind = ? AND status IN ('queued', 'running') LIMIT 1", arguments: [kind.rawValue]) ?? false
        }
    }
}
