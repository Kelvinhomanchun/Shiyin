import AVFoundation
import AppKit
import Foundation
import WebKit

/// 匯出用的完整資料
struct ExportBundle {
    var meeting: Meeting
    var segments: [Segment]
    var speakers: [Int: String]
    var bookmarks: [Bookmark]
    var notes: MeetingNotes?
    /// 參考文件（design §39.5）：只有 .shiyin 封包用到
    var documents: [MeetingDocument] = []

    func speakerName(_ idx: Int?) -> String? { idx.map { speakers[$0] ?? text.speaker($0) } }

    /// 匯出內容的標題、欄位名稱：跟著會議語言，不是介面語言（design §16.6）
    var text: ExportText { ExportText(meeting.meetingLanguage) }
    /// 會議紀錄、心智圖的標題和欄位名稱：跟著會議紀錄的語言（可以跟會議語言不同）
    var notesText: ExportText { ExportText(meeting.notesOutputLanguage) }
}

/// 匯出檔裡的固定文字（design §16.6）
struct ExportText {
    let language: MeetingLanguage
    init(_ language: MeetingLanguage) { self.language = language }

    var transcriptSuffix: String { language.text(zh: "（逐字稿）", en: " (transcript)", ja: "（文字起こし）") }
    var date: String { language.text(zh: "日期", en: "Date", ja: "日付") }
    var participants: String { language.text(zh: "與會者", en: "Participants", ja: "参加者") }
    var speakers: String { language.text(zh: "說話者", en: "Speakers", ja: "話者") }
    var duration: String { language.text(zh: "長度", en: "Duration", ja: "所要時間") }
    var noNotes: String { language.text(zh: "（尚未整理成會議紀錄）", en: "(No meeting notes yet)", ja: "（議事録はまだありません）") }
    var details: String { language.text(zh: "詳細", en: "Details", ja: "詳細") }
    var review: String { language.text(zh: "待確認", en: "To confirm", ja: "要確認") }
    /// 本地 MCP 的會議紀錄接在後面的「我的筆記」（design §44.2）
    var meetingNotes: String { language.text(zh: "會議紀錄", en: "Meeting notes", ja: "議事録") }
    var footer: String { language.text(zh: "由 KelNote 根據會議錄音整理 · AI 產生的內容，請再確認", en: "Prepared with KelNote from the meeting recording · AI-generated, please verify", ja: "KelNote が会議の録音から作成 · AI 生成のため内容をご確認ください") }
    var userNotes: String { language.text(zh: "我的筆記", en: "My notes", ja: "メモ") }
    var owner: String { language.text(zh: "負責人", en: "Owner", ja: "担当") }
    var task: String { language.text(zh: "事項", en: "Item", ja: "内容") }
    var due: String { language.text(zh: "期限", en: "Due", ja: "期限") }
    var time: String { language.text(zh: "時間點", en: "Time", ja: "時刻") }
    var unassigned: String { language.text(zh: "未指定", en: "Unassigned", ja: "未定") }
    var colon: String { language.text(zh: "：", en: ": ", ja: "：") }
    var listSeparator: String { language.text(zh: "、", en: ", ", ja: "、") }
    func speaker(_ idx: Int) -> String { language.defaultSpeaker(idx) }
    func section(_ id: String) -> String { TemplateDefinition.sectionLabel(id, language: language) }
    /// 括號：中文用全形、英文用半形加空白
    func paren(_ inner: String) -> String { language.format(zh: "（%@）", en: " (%@)", ja: "（%@）", inner) }
    func dateLine(_ meetingDate: String) -> String { meetingDate + paren(DateText.weekday(meetingDate, language: language)) }
}

enum ExportItem: String, CaseIterable, Identifiable {
    case notes, mindMap, transcript, audio, package
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notes: return String(localized: "會議紀錄")
        case .mindMap: return String(localized: "心智圖")
        case .transcript: return String(localized: "逐字稿")
        case .audio: return String(localized: "錄音")
        case .package: return String(localized: "整場會議（.shiyin）")
        }
    }
    var formats: [String] {
        switch self {
        case .notes: return ["md", "pdf", "docx"]
        case .mindMap: return ["png", "pdf", "svg"]   // design §42.4
        case .transcript: return ["txt", "md", "srt", "vtt", "docx"]
        case .audio: return ["m4a", "wav"]
        case .package: return ["shiyin"]
        }
    }
}

enum ExportError: LocalizedError {
    case noAudio, failed(String)
    var errorDescription: String? {
        switch self {
        case .noAudio: return String(localized: "這場會議沒有錄音檔")
        case .failed(let reason): return String(localized: "匯出失敗：\(reason)")
        }
    }
}

// MARK: - 逐字稿（R7.2）

enum TranscriptExporter {
    static func text(_ b: ExportBundle, format: String, times: Bool, speakers: Bool) -> String {
        switch format {
        case "srt":
            return b.segments.enumerated().map { i, s in
                "\(i + 1)\n\(TimeFormat.subtitle(s.start, separator: ",")) --> \(TimeFormat.subtitle(max(s.end, s.start + 0.5), separator: ","))\n\(line(b, s, times: false, speakers: speakers))\n"
            }.joined(separator: "\n")
        case "vtt":
            return "WEBVTT\n\n" + b.segments.map { s in
                "\(TimeFormat.subtitle(s.start, separator: ".")) --> \(TimeFormat.subtitle(max(s.end, s.start + 0.5), separator: "."))\n\(line(b, s, times: false, speakers: speakers))\n"
            }.joined(separator: "\n")
        case "md":
            let x = b.text
            return "# \(b.meeting.displayTitle)\(x.transcriptSuffix)\n\n- \(x.date)\(x.colon)\(x.dateLine(b.meeting.meetingDate))\n\n"
                + b.segments.map { line(b, $0, times: times, speakers: speakers, markdown: true) }.joined(separator: "\n\n") + "\n"
        default:
            return b.segments.map { line(b, $0, times: times, speakers: speakers) }.joined(separator: "\n") + "\n"
        }
    }

    static func line(_ b: ExportBundle, _ s: Segment, times: Bool, speakers: Bool, markdown: Bool = false) -> String {
        var prefix = ""
        if times { prefix += markdown ? "`\(TimeFormat.string(s.start))` " : "[\(TimeFormat.string(s.start))] " }
        if speakers, let name = b.speakerName(s.speaker) { prefix += markdown ? "**\(name)**\(b.text.colon)" : "\(name)\(b.text.colon)" }
        return prefix + s.text
    }

    static func html(_ b: ExportBundle, times: Bool, speakers: Bool) -> String {
        let body = b.segments.map { s -> String in
            var prefix = ""
            if times { prefix += "<span class=\"time\">\(TimeFormat.string(s.start))</span> " }
            if speakers, let name = b.speakerName(s.speaker) { prefix += "<b>\(HTML.escape(name))</b>\(b.text.colon)" }
            return "<p>\(prefix)\(HTML.escape(s.text))</p>"
        }.joined(separator: "\n")
        let x = b.text
        return HTML.document(title: b.meeting.displayTitle + x.transcriptSuffix,
                             body: "<h1>\(HTML.escape(b.meeting.displayTitle + x.transcriptSuffix))</h1>\n<p class=\"meta\">\(b.meeting.meetingDate)</p>\n" + body,
                             language: x.language)
    }
}

// MARK: - 會議紀錄（R7.3）

enum NotesExporter {
    /// 數字兩位數的段落編號：01、02…（IBM 簡報的章節編號）
    private static func number(_ n: Int) -> String { String(format: "%02d", n) }

    /// 日期：英文「Mon 23 Nov 2026」、中文「2026-11-23（星期一）」
    static func reportDate(_ meetingDate: String, _ x: ExportText) -> String {
        guard x.language.base == .en, let date = DateText.date(meetingDate) else { return x.dateLine(meetingDate) }
        return date.formatted(Date.FormatStyle(locale: x.language.locale).weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// 頁首小字：「Meeting notes · 客戶 › 案子」
    static func kicker(_ b: ExportBundle) -> String {
        let x = b.notesText
        let folder = b.meeting.folder.isEmpty ? "" : " · " + FolderPath.display(b.meeting.folder)
        return x.meetingNotes + folder
    }

    /// 有內容的段落，照會議紀錄的順序（Markdown、PDF、Word 共用）
    enum Block {
        case list(String, [MeetingNotes.Item], style: String)
        case people(String, [MeetingNotes.Person])
        case actions(String, [MeetingNotes.ActionItem])
        case topics(String, [MeetingNotes.Topic])
        case review(String, [MeetingNotes.ReviewItem])
    }

    static func blocks(_ notes: MeetingNotes, _ x: ExportText) -> [Block] {
        var out: [Block] = []
        if !notes.summary.isEmpty { out.append(.list(x.section("summary"), notes.summary, style: "summary")) }
        if !notes.people.isEmpty { out.append(.people(x.section("people"), notes.people)) }
        if !notes.decisions.isEmpty { out.append(.list(x.section("decisions"), notes.decisions, style: "dec")) }
        if !notes.actionItems.isEmpty { out.append(.actions(x.section("actionItems"), notes.actionItems)) }
        if !notes.openQuestions.isEmpty { out.append(.list(x.section("openQuestions"), notes.openQuestions, style: "q")) }
        for custom in notes.custom where !custom.items.isEmpty { out.append(.list(custom.title, custom.items, style: "")) }
        if !notes.topics.isEmpty { out.append(.topics(x.section("topics"), notes.topics)) }
        if !notes.reviewItems.isEmpty { out.append(.review(x.review, notes.reviewItems)) }
        return out
    }

    static func markdown(_ b: ExportBundle) -> String {
        let m = b.meeting
        let x = b.notesText
        var out = ["# \(m.displayTitle)", "", "*\(kicker(b))*", ""]
        var meta = ["| \(x.date) | \(reportDate(m.meetingDate, x)) |", "|---|---|"]
        if m.durationSeconds != nil { meta.append("| \(x.duration) | \(TimeFormat.duration(m.durationSeconds, language: x.language)) |") }
        if !m.participantList.isEmpty { meta.append("| \(x.participants) | \(cell(m.participantList.joined(separator: x.listSeparator))) |") }
        let speakerNames = b.speakers.sorted { $0.key < $1.key }.map(\.value)
        if !speakerNames.isEmpty { meta.append("| \(x.speakers) | \(cell(speakerNames.joined(separator: x.listSeparator))) |") }
        out += meta
        guard let notes = b.notes, !notes.isEmpty else {
            out += ["", x.noNotes, "", "---", "", "*\(x.footer)*"]
            return out.joined(separator: "\n") + "\n"
        }
        func t(_ time: String) -> String { time.isEmpty ? "" : " `\(time)`" }
        let figures = [(x.section("decisions"), notes.decisions.count), (x.section("actionItems"), notes.actionItems.count),
                       (x.section("openQuestions"), notes.openQuestions.count)].filter { $0.1 > 0 }
        if !figures.isEmpty { out += ["", "> " + figures.map { "**\($0.1)** \($0.0)" }.joined(separator: " · ")] }
        for (i, block) in blocks(notes, x).enumerated() {
            let n = number(i + 1)
            switch block {
            case let .list(title, items, _):
                out += ["", "## \(n) · \(title)", ""] + items.map { "- \($0.text)\(t($0.time))" }
            case let .people(title, people):
                out += ["", "## \(n) · \(title)"]
                for person in people { out += ["", "**\(person.name)**", ""] + person.points.map { "- \($0.text)\(t($0.time))" } }
            case let .actions(title, items):
                out += ["", "## \(n) · \(title)", "", "| \(x.owner) | \(x.task) | \(x.due) | \(x.time) |", "|---|---|---|---|"]
                for item in items {
                    out.append("| **\(cell(item.owner.isEmpty ? x.unassigned : item.owner))** | \(cell(item.task)) | \(cell(item.due)) | \(cell(item.time)) |")
                }
            case let .topics(title, topics):
                out += ["", "## \(n) · \(title)"]
                for topic in topics {
                    out += ["", "### \(topic.title)\(t(topic.start))", ""] + topic.points.map { "- \($0.text)\(t($0.time))" }
                }
            case let .review(title, items):
                out += ["", "## \(n) · \(title)", ""] + items.map { "- [ ] \($0.question)\(t($0.time))" }
            }
        }
        out += ["", "---", "", "*\(x.footer)*"]
        return out.joined(separator: "\n") + "\n"
    }

    /// 純文字（貼到 Slack、訊息）
    static func plain(_ b: ExportBundle) -> String {
        let m = b.meeting
        let x = b.notesText
        var out = [m.displayTitle, kicker(b)]
        var meta = [reportDate(m.meetingDate, x)]
        if m.durationSeconds != nil { meta.append(TimeFormat.duration(m.durationSeconds, language: x.language)) }
        out.append(meta.joined(separator: " · "))
        if !m.participantList.isEmpty { out.append("\(x.participants)\(x.colon)\(m.participantList.joined(separator: x.listSeparator))") }
        guard let notes = b.notes, !notes.isEmpty else { return (out + ["", x.noNotes]).joined(separator: "\n") + "\n" }
        func t(_ time: String) -> String { time.isEmpty ? "" : x.paren(time) }
        for block in blocks(notes, x) {
            switch block {
            case let .list(title, items, _): out += ["", title.uppercased()] + items.map { "• \($0.text)\(t($0.time))" }
            case let .people(title, people):
                out += ["", title.uppercased()]
                for p in people { out += [p.name] + p.points.map { "  • \($0.text)\(t($0.time))" } }
            case let .actions(title, items):
                out += ["", title.uppercased()] + items.map {
                    "• \($0.owner.isEmpty ? x.unassigned : $0.owner) — \($0.task)" + ($0.due.isEmpty ? "" : x.paren("\(x.due)\(x.colon)\($0.due)"))
                }
            case let .topics(title, topics):
                out += ["", title.uppercased()]
                for topic in topics { out += ["[\(topic.start)] \(topic.title)"] + topic.points.map { "  • \($0.text)\(t($0.time))" } }
            case let .review(title, items): out += ["", title.uppercased()] + items.map { "• \($0.question)\(t($0.time))" }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// 給 Word、剪貼簿：NSAttributedString 不認得 flex 等版面，用表格和簡單的樣式，但同一套字型、顏色、編號
    static func html(_ b: ExportBundle) -> String {
        let m = b.meeting
        let x = b.notesText
        var body = "<p class=\"kicker\">\(HTML.escape(kicker(b)))</p>\n<h1>\(HTML.escape(m.displayTitle))</h1>\n"
        var meta = ["\(x.date)\(x.colon)<b>\(HTML.escape(reportDate(m.meetingDate, x)))</b>"]
        if m.durationSeconds != nil { meta.append("\(x.duration)\(x.colon)<b>\(TimeFormat.duration(m.durationSeconds, language: x.language))</b>") }
        if !m.participantList.isEmpty { meta.append("\(x.participants)\(x.colon)<b>\(HTML.escape(m.participantList.joined(separator: x.listSeparator)))</b>") }
        body += "<p class=\"meta\">" + meta.joined(separator: "&nbsp;&nbsp;&nbsp;·&nbsp;&nbsp;&nbsp;") + "</p>\n<hr>\n"
        guard let notes = b.notes, !notes.isEmpty else {
            return HTML.document(title: m.displayTitle, body: body + "<p>\(x.noNotes)</p>", language: x.language)
        }
        func t(_ time: String) -> String { time.isEmpty ? "" : "&nbsp;&nbsp;<span class=\"time\">\(time)</span>" }
        // Word 的清單縮排很寬：改成方塊符號加懸掛縮排的段落（同 PDF 的樣子）
        func bullet(_ text: String, _ time: String, _ mark: String = "■") -> String {
            "<p class=\"li\"><span class=\"mark\">\(mark)</span>&nbsp;&nbsp;&nbsp;\(HTML.escape(text))\(t(time))</p>"
        }
        func items(_ list: [MeetingNotes.Item]) -> String { list.map { bullet($0.text, $0.time) }.joined() + "\n" }
        for (i, block) in blocks(notes, x).enumerated() {
            let h2 = { (title: String) in "<h2><span class=\"no\">\(number(i + 1))</span>&nbsp;&nbsp;\(HTML.escape(title))</h2>\n" }
            switch block {
            case let .list(title, list, _): body += h2(title) + items(list)
            case let .people(title, people):
                body += h2(title)
                for p in people { body += "<h3>\(HTML.escape(p.name))</h3>\n" + items(p.points) }
            case let .actions(title, list):
                body += h2(title) + "<table><tr><th class=\"nowrap\">\(x.owner)</th><th>\(x.task)</th><th class=\"nowrap\">\(x.due)</th></tr>"
                body += list.map { "<tr><td class=\"nowrap\"><b>\(HTML.escape($0.owner.isEmpty ? x.unassigned : $0.owner))</b></td><td>\(HTML.escape($0.task))\(t($0.time))</td><td class=\"nowrap\">\(HTML.escape($0.due.isEmpty ? "—" : $0.due))</td></tr>" }.joined()
                body += "</table>\n"
            case let .topics(title, topics):
                body += h2(title)
                for topic in topics { body += "<h3><span class=\"time\">\(topic.start)</span>&nbsp;&nbsp;\(HTML.escape(topic.title))</h3>\n" + items(topic.points) }
            case let .review(title, list):
                body += h2(title) + list.map { bullet($0.question, $0.time, "□") }.joined() + "\n"
            }
        }
        body += "<hr>\n<p class=\"foot\">\(HTML.escape(x.footer))</p>\n"
        return HTML.document(title: m.displayTitle, body: body, language: x.language)
    }

    /// PDF：用 WebKit 排版，CSS 完整生效（IBM 簡報的樣子：白底、Plex、藍 60 的重點、細線、編號段落）
    static func report(_ b: ExportBundle) -> String {
        let m = b.meeting
        let x = b.notesText
        var body = "<header class=\"cover\"><div class=\"kicker\">\(HTML.escape(kicker(b)))</div><h1>\(HTML.escape(m.displayTitle))</h1><div class=\"meta\">"
        body += "<div>\(x.date)<b>\(HTML.escape(reportDate(m.meetingDate, x)))</b></div>"
        if m.durationSeconds != nil { body += "<div>\(x.duration)<b>\(TimeFormat.duration(m.durationSeconds, language: x.language))</b></div>" }
        if !m.participantList.isEmpty { body += "<div class=\"wide\">\(x.participants)<b>\(HTML.escape(m.participantList.joined(separator: x.listSeparator)))</b></div>" }
        body += "</div></header>\n"
        guard let notes = b.notes, !notes.isEmpty else {
            return HTML.report(title: m.displayTitle, body: body + "<p class=\"empty\">\(x.noNotes)</p>", footer: x.footer, language: x.language)
        }
        let figures = [(x.section("decisions"), notes.decisions.count), (x.section("actionItems"), notes.actionItems.count),
                       (x.section("openQuestions"), notes.openQuestions.count), (x.section("topics"), notes.topics.count)].filter { $0.1 > 0 }
        if figures.count >= 2 {
            body += "<div class=\"figs\">" + figures.map { "<div class=\"fig\"><div class=\"n\">\($0.1)</div><div class=\"l\">\(HTML.escape($0.0))</div></div>" }.joined() + "</div>\n"
        }
        func t(_ time: String) -> String { time.isEmpty ? "" : "<span class=\"t\">\(time)</span>" }
        func li(_ text: String, _ time: String) -> String { "<li>\(HTML.escape(text))\(t(time))</li>" }
        func ul(_ rows: [String], _ style: String) -> String { rows.isEmpty ? "" : "<ul class=\"\(style)\">" + rows.joined() + "</ul>" }
        /// 段落標題跟第一項放在一起不拆頁（WebKit 列印不管 break-after，標題會單獨留在頁尾）
        func section(_ title: String, _ n: Int, first: String, rest: String) -> String {
            "<section><div class=\"lead\"><h2><span class=\"no\">\(number(n))</span>\(HTML.escape(title))</h2>\(first)</div>\(rest)</section>\n"
        }
        func list(_ rows: [String], _ style: String) -> (String, String) {
            (ul(Array(rows.prefix(1)), style), ul(Array(rows.dropFirst()), style + " cont"))
        }
        for (i, block) in blocks(notes, x).enumerated() {
            switch block {
            case let .list(title, items, style):
                let (first, rest) = list(items.map { li($0.text, $0.time) }, style)
                body += section(title, i + 1, first: first, rest: rest)
            case let .people(title, people):
                let cards = people.map { "<div class=\"topic\"><h3>\(HTML.escape($0.name))</h3>\(ul($0.points.map { li($0.text, $0.time) }, ""))</div>" }
                body += section(title, i + 1, first: cards.first ?? "", rest: cards.dropFirst().joined())
            case let .actions(title, items):
                let rows = items.map { a -> String in
                    let due = a.due.isEmpty ? "<td class=\"d\">—</td>" : "<td class=\"d set\">\(HTML.escape(a.due))</td>"
                    return "<tr><td class=\"o\">\(HTML.escape(a.owner.isEmpty ? x.unassigned : a.owner))</td><td>\(HTML.escape(a.task))\(t(a.time))</td>\(due)</tr>"
                }
                // 第一列跟標題、表頭放在一起；其餘的另一個表格（欄寬固定，兩個表格對得齊）
                let head = "<colgroup><col class=\"co\"><col><col class=\"cd\"></colgroup>"
                let first = "<table>\(head)<thead><tr><th>\(x.owner)</th><th>\(x.task)</th><th>\(x.due)</th></tr></thead><tbody>\(rows[0])</tbody></table>"
                let rest = rows.count > 1 ? "<table class=\"cont\">\(head)<tbody>" + rows.dropFirst().joined() + "</tbody></table>" : ""
                body += section(title, i + 1, first: first, rest: rest)
            case let .topics(title, topics):
                let cards = topics.map { topic in
                    "<div class=\"topic\"><h3><span class=\"start\">\(topic.start)</span>\(HTML.escape(topic.title))</h3>\(ul(topic.points.map { li($0.text, $0.time) }, ""))</div>"
                }
                body += section(title, i + 1, first: cards.first ?? "", rest: cards.dropFirst().joined())
            case let .review(title, items):
                let (first, rest) = list(items.map { li($0.question, $0.time) }, "q")
                body += section(title, i + 1, first: first, rest: rest)
            }
        }
        return HTML.report(title: m.displayTitle, body: body, footer: x.footer, language: x.language)
    }

    private static func cell(_ text: String) -> String {
        text.isEmpty ? "—" : text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - HTML → PDF、docx、剪貼簿（design §10）

/// 中文會議用簡體時，匯出整份轉成簡體（R71.3、design §47.2）：標題、欄位名稱、預設的說話者名稱也一起轉
enum ExportScript {
    static func text(_ text: String, _ b: ExportBundle) -> String {
        AppSettings.script(text, for: b.meeting.meetingLanguage)
    }

    /// HTML 另外把語言標記、繁體中文的字型換成簡體的
    static func html(_ html: String, _ b: ExportBundle) -> String {
        guard AppSettings.simplifiedChinese(for: b.meeting.meetingLanguage) else { return html }
        var out = ChineseScript.toSimplified(html)
        for (from, to) in [("lang=\"zh-Hant\"", "lang=\"zh-Hans\""), ("PingFang TC", "PingFang SC"), ("Songti TC", "Songti SC")] {   // l10n-skip
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }
}

enum HTML {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 字型、lang 寫在語言檔（design §16.6、§18.5、§41.5）。fork：拉丁字用 IBM Plex Sans（app 裡附的字型），
    /// 中日韓字跟著語言檔的字型；樣子同 IBM 簡報：白底、藍 60 #0F62FE 標出重點、灰階文字、細線
    static func document(title: String, body: String, language: MeetingLanguage = .zh) -> String {
        let fonts = language.profile.fonts
        let bodyFont = "\"IBM Plex Sans\", " + fonts.htmlMac.body
        return """
        <!doctype html><html lang="\(fonts.lang)"><head><meta charset="utf-8"><title>\(escape(title))</title><style>
        body { font-family: \(bodyFont); font-size: 10.5pt; line-height: 1.55; color: #161616; }
        h1 { font-family: \(bodyFont); font-weight: 300; font-size: 24pt; margin: 2pt 0 6pt; color: #161616; }
        h2 { font-family: \(bodyFont); font-weight: 400; font-size: 14pt; margin-top: 20pt; margin-bottom: 4pt; color: #161616; }
        h3 { font-family: \(bodyFont); font-weight: 500; font-size: 11pt; margin-top: 10pt; margin-bottom: 2pt; color: #161616; }
        .no { color: #0F62FE; font-size: 9pt; font-weight: 500; }
        .kicker { color: #0F62FE; font-size: 8.5pt; font-weight: 500; margin: 0; }
        .meta { color: #525252; font-size: 9pt; } .meta b { color: #161616; font-weight: 500; }
        .time { color: #6F6F6F; font-size: 8.5pt; }
        h3 .time { color: #0F62FE; font-weight: 500; }
        hr { border: none; border-top: 1px solid #E0E0E0; }
        li { margin-bottom: 3pt; }
        p.li { margin: 0 0 4pt 14pt; text-indent: -14pt; }
        .mark { color: #0F62FE; font-size: 6.5pt; }
        table { border-collapse: collapse; width: 100%; } th, td { border-bottom: 1px solid #E0E0E0; padding: 5pt 7pt; text-align: left; vertical-align: top; }
        th { color: #525252; font-weight: 500; font-size: 8.5pt; border-bottom: 2px solid #161616; }
        .nowrap { white-space: nowrap; }  /* 負責人、期限不拆行，內容欄自己換行（中日文可以在任何字之間換行，表格會把短欄擠到一個字寬） */
        .foot { color: #8D8D8D; font-size: 8pt; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// 會議紀錄的 PDF 版面（WebKit 排版）：封面條、大標題、資訊列、數字列、編號段落、待辦表格
    static func report(title: String, body: String, footer: String, language: MeetingLanguage) -> String {
        let fonts = language.profile.fonts
        let face = ["Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600].map {
            "@font-face{font-family:\"KelPlex\";src:url(\"IBMPlexSans-\($0.key).ttf\");font-weight:\($0.value)}"
        }.sorted().joined(separator: "\n")
        let family = "\"KelPlex\", \"IBM Plex Sans\", " + fonts.htmlMac.body
        return """
        <!doctype html><html lang="\(fonts.lang)"><head><meta charset="utf-8"><title>\(escape(title))</title><style>
        \(face)
        *{box-sizing:border-box}
        body{margin:0;font-family:\(family);color:#161616;font-size:10pt;line-height:1.55;font-weight:400;-webkit-font-smoothing:antialiased}
        .cover{border-top:6px solid #0F62FE;padding-top:14pt;margin-bottom:6pt}
        .kicker{font-size:8.5pt;color:#0F62FE;font-weight:500;letter-spacing:.02em}
        h1{font-weight:300;font-size:26pt;line-height:1.18;margin:6pt 0 12pt;color:#161616}
        .meta{display:flex;gap:26pt;font-size:8.5pt;color:#525252;border-bottom:1px solid #E0E0E0;padding-bottom:10pt}
        .meta b{display:block;font-weight:500;color:#161616;font-size:9.5pt;margin-top:1pt}
        .meta .wide{flex:1}
        .figs{display:flex;margin:14pt 0 4pt;border-bottom:1px solid #E0E0E0}
        .fig{flex:1;padding:6pt 12pt 10pt 0}
        .fig+.fig{border-left:1px solid #E0E0E0;padding-left:12pt}
        .fig .n{font-size:24pt;font-weight:300;color:#0F62FE;line-height:1.1}
        .fig .l{font-size:8.5pt;color:#525252;margin-top:3pt}
        h2{font-weight:400;font-size:14pt;margin:22pt 0 8pt;color:#161616;display:flex;align-items:baseline;gap:8pt;break-after:avoid;page-break-after:avoid}
        h2 .no{font-size:8.5pt;color:#0F62FE;font-weight:500;min-width:16pt}
        ul{margin:0;padding:0;list-style:none}
        li{padding:5pt 0 5pt 14pt;text-indent:-14pt;border-bottom:1px solid #F4F4F4;break-inside:avoid;page-break-inside:avoid}
        li:before{content:"■";color:#0F62FE;font-size:6pt;margin-right:8pt;vertical-align:1.5pt}
        ul.summary{border-left:3px solid #0F62FE;padding:2pt 0 2pt 12pt}
        ul.summary li{border:none;padding:3pt 0 3pt 14pt}
        ul.dec li:before{color:#002D9C}
        ul.q li:before{content:"□";font-size:8pt;vertical-align:.5pt}
        .t{color:#6F6F6F;font-size:8pt;margin-left:6pt;white-space:nowrap}
        table{width:100%;border-collapse:collapse;font-size:9.5pt;table-layout:fixed}
        col.co{width:19%} col.cd{width:15%}
        thead{display:table-header-group}
        th{font-weight:500;font-size:8pt;color:#525252;text-align:left;padding:6pt 8pt;border-bottom:2px solid #161616}
        td{padding:7pt 8pt;border-bottom:1px solid #E0E0E0;vertical-align:top}
        td.o{font-weight:500;overflow-wrap:anywhere}
        td.d{white-space:nowrap;color:#8D8D8D}
        td.d.set{color:#0F62FE;font-weight:500}
        tr{break-inside:avoid;page-break-inside:avoid}
        .lead{break-inside:avoid;page-break-inside:avoid}
        .topic{margin:0 0 12pt;break-inside:avoid;page-break-inside:avoid}
        .topic h3{font-weight:500;font-size:10.5pt;margin:0 0 3pt}
        .topic h3 .start{margin-right:8pt;color:#0F62FE;font-weight:500;font-size:8.5pt}
        .empty{color:#6F6F6F;margin-top:18pt}
        .foot{margin-top:26pt;padding-top:8pt;border-top:1px solid #E0E0E0;font-size:7.5pt;color:#8D8D8D}
        </style></head><body>\(body)<div class="foot">\(escape(footer))</div></body></html>
        """
    }

    /// app 附的 IBM Plex Sans（Resources/Fonts，SIL OFL 1.1）；直接跑建置輸出時用原始碼樹的那份
    static var fontsDirectory: URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
           FileManager.default.fileExists(atPath: url.appendingPathComponent("IBMPlexSans-Regular.ttf").path) { return url }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
    }

    /// 開 app 時註冊字型（只給這個 app 用）：Word、剪貼簿的文字照名字找得到 IBM Plex Sans
    static func registerFonts() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "ttf" } ?? []
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, false, nil)
    }

    @MainActor
    static func attributed(_ html: String) throws -> NSAttributedString {
        guard let data = html.data(using: .utf8),
              let string = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil)
        else { throw ExportError.failed(String(localized: "無法產生文件")) }
        return plexFonts(fitShortColumns(string))
    }

    /// 表格欄寬：中日文可以在任何字之間換行，HTML 轉換時算的欄寬又是照它自己假設的版面寬度，排進 A4 等比例縮小後，
    /// 負責人、期限這種短欄會被擠成「小／田／切」「2026-1／0-15」。改成用百分比：內容最寬的那一欄自動換行，
    /// 其他欄是內容加內距佔 PDF 版面的比例（最多三成）
    private static func fitShortColumns(_ source: NSAttributedString) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: source)
        let whole = NSRange(location: 0, length: string.length)
        var widths: [ObjectIdentifier: [Int: CGFloat]] = [:]
        string.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
            guard let block = (value as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock else { return }
            // 量一行排開的寬度：去掉表格的段落樣式，不然會照儲存格的寬度排版
            let text = NSMutableAttributedString(attributedString: string.attributedSubstring(from: range))
            text.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: text.length))
            let extra = [NSTextBlock.Layer.padding, .border, .margin].reduce(CGFloat(0)) {
                $0 + block.width(for: $1, edge: .minX) + block.width(for: $1, edge: .maxX)
            }
            let width = text.boundingRect(with: NSSize(width: 10_000, height: 100), options: [.usesLineFragmentOrigin]).width + extra + 2
            let table = ObjectIdentifier(block.table)
            widths[table, default: [:]][block.startingColumn] = max(widths[table]?[block.startingColumn] ?? 0, width)
        }
        var percents: [ObjectIdentifier: [Int: CGFloat]] = [:]
        for (table, columns) in widths {
            guard let widest = columns.max(by: { $0.value < $1.value })?.key else { continue }
            var result = columns.filter { $0.key != widest }.mapValues { min(30, ceil($0 / pageWidth * 100)) }
            result[widest] = max(30, 100 - result.values.reduce(0, +))
            percents[table] = result
        }
        string.enumerateAttribute(.paragraphStyle, in: whole) { value, _, _ in
            guard let block = (value as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock,
                  let percent = percents[ObjectIdentifier(block.table)]?[block.startingColumn] else { return }
            block.setValue(percent, type: .percentageValueType, for: .width)
        }
        return string
    }

    /// WebKit 轉 HTML 時看不到 app 附的字型，拉丁字會變成 Helvetica Neue、系統字（Windows 的 Word 沒有系統字，會變 Times）。
    /// 換成同粗細的 IBM Plex Sans；中日韓字型（蘋方、ヒラギノ…）不動
    static func plexFonts(_ source: NSAttributedString) -> NSAttributedString {
        guard NSFont(name: "IBMPlexSans", size: 12) != nil else { return source }
        let string = NSMutableAttributedString(attributedString: source)
        string.enumerateAttribute(.font, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let family = font.familyName ?? ""
            let system = [family, font.fontName].contains { $0.hasPrefix(".") || $0.hasPrefix("SF") || $0.hasPrefix("System") }
            guard family.hasPrefix("Helvetica") || system else { return }
            let weight = (font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
            let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
            let name = weight < -0.2 ? "IBMPlexSans-Light" : bold || weight >= 0.35 ? "IBMPlexSans-SmBld"
                : weight >= 0.15 ? "IBMPlexSans-Medm" : "IBMPlexSans"
            let italic = font.fontDescriptor.symbolicTraits.contains(.italic) && name == "IBMPlexSans"
            if let plex = NSFont(name: italic ? "IBMPlexSans-Italic" : name, size: font.pointSize) {
                string.addAttribute(.font, value: plex, range: range)
            }
        }
        return string
    }

    /// PDF 的版面寬度：A4 減掉左右邊界
    private static let pageWidth: CGFloat = 595 - 56 * 2

    /// 非同步讀 HTML（design §21.13）：轉換在 WebKit 裡做，主執行緒不用等。
    /// 2,086 段的逐字稿：同步轉換主執行緒卡 665 ms，非同步最長卡 102 ms；產生的 Word 檔逐位元組相同
    @MainActor
    static func attributedAsync(_ html: String) async throws -> NSAttributedString {
        let string: NSAttributedString = try await withCheckedThrowingContinuation { continuation in
            NSAttributedString.loadFromHTML(string: html) { string, _, error in
                if let string { continuation.resume(returning: string) }
                else { continuation.resume(throwing: error ?? ExportError.failed(String(localized: "無法產生文件"))) }
            }
        }
        return plexFonts(fitShortColumns(string))
    }

    /// Word：讀 HTML 用 WebKit 非同步做，調整欄寬、轉成 Word 檔在背景做（design §21.13）
    @MainActor
    static func docx(_ html: String) async throws -> Data {
        let string: NSAttributedString = try await withCheckedThrowingContinuation { continuation in
            NSAttributedString.loadFromHTML(string: html) { string, _, error in
                if let string { continuation.resume(returning: string) }
                else { continuation.resume(throwing: error ?? ExportError.failed(String(localized: "無法產生文件"))) }
            }
        }
        let copy = NSAttributedString(attributedString: string)
        return try await Task.detached(priority: .userInitiated) { try docxData(plexFonts(fitShortColumns(copy))) }.value
    }

    static func docxData(_ string: NSAttributedString) throws -> Data {
        try string.data(from: NSRange(location: 0, length: string.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }

    /// 用 NSTextView 排版後印成 PDF（自動分頁，A4）：逐字稿等沒有特別版面的文件
    @MainActor
    static func pdf(_ html: String, to url: URL) async throws {
        let string = try await attributedAsync(html)
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.textStorage?.setAttributedString(string)
        view.isVerticallyResizable = true
        view.sizeToFit()
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let used = view.layoutManager?.usedRect(for: view.textContainer!).height ?? 100
        view.frame.size.height = used + 20
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ExportError.failed(String(localized: "PDF 產生失敗")) }
    }

    /// 會議紀錄的 PDF（fork）：WebKit 排版，CSS 和附的字型都生效；印好後每頁下方加上標題和頁碼
    @MainActor
    static func reportPDF(_ html: String, title: String, to url: URL) async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("kelnote-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        try await ReportPrinter().print(html, baseURL: fontsDirectory, to: temp)
        try stampPages(temp, title: title, to: url)
    }

    /// 每頁下方：左邊標題、右邊「2 / 5」，灰色小字，細線上面（同 IBM 簡報的頁尾）
    private static func stampPages(_ source: URL, title: String, to url: URL) throws {
        guard let document = CGPDFDocument(source as CFURL), document.numberOfPages > 0 else { throw ExportError.failed(String(localized: "PDF 產生失敗")) }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle: title, kCGPDFContextCreator: "KelNote"] as CFDictionary)
        else { throw ExportError.failed(String(localized: "PDF 產生失敗")) }
        let total = document.numberOfPages
        let font = NSFont(name: "IBMPlexSans", size: 7.5) ?? NSFont.systemFont(ofSize: 7.5)
        let grey = NSColor(srgbRed: 0x8D / 255, green: 0x8D / 255, blue: 0x8D / 255, alpha: 1)
        for index in 1...total {
            guard let page = document.page(at: index) else { continue }
            var media = page.getBoxRect(.mediaBox)
            context.beginPage(mediaBox: &media)
            context.drawPDFPage(page)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor(srgbRed: 0xE0 / 255, green: 0xE0 / 255, blue: 0xE0 / 255, alpha: 1).setFill()
            NSRect(x: 56, y: 36, width: media.width - 112, height: 0.5).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: grey]
            let number = NSAttributedString(string: "\(index) / \(total)", attributes: attributes)
            number.draw(at: NSPoint(x: media.width - 56 - number.size().width, y: 24))
            let maxWidth = media.width - 112 - number.size().width - 24
            NSAttributedString(string: title, attributes: attributes)
                .draw(with: NSRect(x: 56, y: 24, width: maxWidth, height: 12), options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
            NSGraphicsContext.restoreGraphicsState()
            context.endPage()
        }
        context.closePDF()
    }

    /// 同時放純文字、HTML、RTF，貼到哪裡都有合適的格式（R7.3）
    @MainActor
    static func copy(plain: String, html: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(plain, forType: .string)
        board.setString(html, forType: .html)
        if let rtf = try? attributed(html).rtf(from: NSRange(location: 0, length: (try? attributed(html).length) ?? 0)) {
            board.setData(rtf, forType: .rtf)
        }
    }
}

// MARK: - 錄音（R7.1）

enum AudioExporter {
    static func export(_ b: ExportBundle, format: String, to url: URL) async throws {
        guard b.meeting.hasAudio else { throw ExportError.noAudio }
        let source = b.meeting.audioURL
        try? FileManager.default.removeItem(at: url)
        // 「麥克風＋電腦聲音」的錄音（design §49.1、R73.2）：m4a 兩個聲道混在一起、wav 混成單聲道，原檔是同一種格式也要重新轉
        let both = b.meeting.channels == "both"
        let asset = AVURLAsset(url: source)
        let mix = format == "m4a" && both ? await ChannelMix.audioMix(for: asset) : nil
        if format == source.pathExtension.lowercased() && !both {
            try FileManager.default.copyItem(at: source, to: url)
        } else if format == "m4a" {
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
            else { throw ExportError.failed(String(localized: "無法建立轉檔")) }
            session.audioMix = mix
            try await session.export(to: url, as: .m4a)
        } else {
            // wav：解碼成 16 kHz 單聲道（轉錄用的格式，音質足夠聽清楚人聲）
            let samples = try await AudioDecoder.decode(source)
            try AudioDecoder.writeWAV(samples, to: url)
        }
    }
}

// MARK: - 會議紀錄 PDF 的 WebKit 排版（fork）

/// 在看不見的視窗裡載入 HTML，載完用 WebKit 的列印存成 PDF（A4）。NSAttributedString 不認得大部分 CSS，所以版面要用 WebKit
@MainActor
final class ReportPrinter: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var window: NSWindow?
    private var loaded: CheckedContinuation<Void, Error>?
    private var printed: CheckedContinuation<Bool, Never>?

    func print(_ html: String, baseURL: URL, to url: URL) async throws {
        let frame = NSRect(x: 0, y: 0, width: 595, height: 842)
        let web = WKWebView(frame: frame)
        let window = NSWindow(contentRect: frame.offsetBy(dx: -5000, dy: -5000), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        web.navigationDelegate = self
        self.web = web
        self.window = window
        defer { window.close(); self.web = nil; self.window = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            web.loadHTMLString(html, baseURL: baseURL)
        }
        // 字型載完才排版（@font-face 是非同步的）
        _ = try? await web.evaluateJavaScript("document.fonts.ready.then(() => true)")
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 54; info.bottomMargin = 60; info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = web.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = web.bounds
        let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            printed = continuation
            operation.runModal(for: window, delegate: self, didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        guard ok, FileManager.default.fileExists(atPath: url.path) else { throw ExportError.failed(String(localized: "PDF 產生失敗")) }
    }

    @objc private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printed?.resume(returning: success)
        printed = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.loaded?.resume(); self.loaded = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loaded?.resume(throwing: error); self.loaded = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loaded?.resume(throwing: error); self.loaded = nil }
    }
}
