import Foundation

/// 電子郵件（.eml，fork）當成參考文件：信頭（寄件人、收件人、日期、主旨）、內文、附件（PDF、Word、PowerPoint、文字、圖片照文件的讀法）。
/// 第 1 頁是信，每個讀得出來的附件各一頁，送給整理工具時跟 PDF 一樣標頁碼。內嵌在簽名檔的小圖不讀
enum EmailReader {
    struct Part {
        var headers: [String: String]
        var body: Data
        var contentType: String { (headers["content-type"] ?? "text/plain").lowercased() }
        var mime: String { contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "text/plain" }
        func parameter(_ key: String, in header: String) -> String? {
            guard let value = headers[header] else { return nil }
            for piece in value.split(separator: ";").dropFirst() {
                let pair = piece.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pair.count == 2, pair[0].lowercased() == key || pair[0].lowercased() == key + "*" {
                    return EmailReader.decodeWords(pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
            }
            return nil
        }
        var filename: String? { parameter("filename", in: "content-disposition") ?? parameter("name", in: "content-type") }
        var isAttachment: Bool { (headers["content-disposition"] ?? "").lowercased().hasPrefix("attachment") }
    }

    /// 回傳每一頁的文字；attachment 讀附件的方式交給呼叫的地方（DocumentReader 的同一套）
    static func read(_ data: Data, name: String, attachment: (URL) -> [String]?) throws -> [String] {
        let root = parse(data)
        let h = root.headers
        var header: [String] = []
        for (key, label) in [("from", "From"), ("to", "To"), ("cc", "Cc"), ("date", "Date"), ("subject", "Subject")] {
            if let value = h[key], !value.isEmpty { header.append("\(label): \(decodeWords(value))") }
        }
        var plain: [String] = [], html: [String] = [], files: [(String, Data)] = []
        collect(root, plain: &plain, html: &html, files: &files)
        var body = plain.joined(separator: "\n\n")
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body = html.map(htmlToText).joined(separator: "\n\n") }
        body = trimQuoteNoise(body)
        var pages = [(header + ["", body]).joined(separator: "\n")]
        // 附件：寫到暫存資料夾，照文件的讀法讀；讀不了的（xlsx、壓縮檔…）只記名字
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("kelnote-eml-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        var skipped: [String] = []
        for (index, (filename, content)) in files.enumerated() {
            let safe = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            let url = temp.appendingPathComponent("\(index)-\(safe)")
            guard (try? content.write(to: url)) != nil, let text = attachment(url), !text.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                skipped.append(filename); continue
            }
            pages.append("Attachment: \(filename)\n\n" + text.joined(separator: "\n\n"))
        }
        if !skipped.isEmpty { pages[0] += "\n\n(Attachments not read: \(skipped.joined(separator: ", ")))" }
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw DocumentReader.DocumentError.empty(name) }
        return pages
    }

    // MARK: MIME

    static func parse(_ data: Data) -> Part {
        // 信頭和內文之間是第一個空行
        let bytes = [UInt8](data)
        var split = bytes.count, skip = 0
        for i in 0..<bytes.count {
            if bytes[i] == 10 {
                if i + 1 < bytes.count, bytes[i + 1] == 10 { split = i; skip = 2; break }
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { split = i; skip = 3; break }
            }
        }
        let headerText = String(decoding: bytes[0..<split], as: UTF8.self)
        let body = split < bytes.count ? Data(bytes[min(bytes.count, split + skip)...]) : Data()
        var headers: [String: String] = [:]
        var last: String?
        for raw in headerText.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let first = line.first, first == " " || first == "\t", let key = last {
                headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if headers[key] == nil { headers[key] = value }
                last = key
            }
        }
        return Part(headers: headers, body: body)
    }

    private static func collect(_ part: Part, plain: inout [String], html: inout [String], files: inout [(String, Data)], depth: Int = 0) {
        guard depth < 8 else { return }
        let decoded = decodeBody(part)
        if part.mime.hasPrefix("multipart/"), let boundary = part.parameter("boundary", in: "content-type") {
            for child in split(part.body, boundary: boundary) {
                collect(parse(child), plain: &plain, html: &html, files: &files, depth: depth + 1)
            }
        } else if part.mime == "message/rfc822" {
            let inner = parse(decoded)
            let h = inner.headers
            plain.append(["From", "Date", "Subject"].compactMap { k in h[k.lowercased()].map { "\(k): \(decodeWords($0))" } }.joined(separator: "\n"))
            collect(inner, plain: &plain, html: &html, files: &files, depth: depth + 1)
        } else if let filename = part.filename, part.isAttachment || !part.mime.hasPrefix("text/") {
            // 簽名檔、信裡的小圖（inline 的圖片）不讀：通常是 logo
            if part.isAttachment || decoded.count > 60_000 { files.append((filename, decoded)) }
        } else if part.mime == "text/plain" {
            plain.append(text(decoded, charset: part.parameter("charset", in: "content-type")))
        } else if part.mime == "text/html" {
            html.append(text(decoded, charset: part.parameter("charset", in: "content-type")))
        }
    }

    /// 照分隔線切開（用位元組：Swift 的字串把 \r\n 當成一個字元，算長度會錯）
    private static func split(_ body: Data, boundary: String) -> [Data] {
        let bytes = [UInt8](body)
        let marker = [UInt8](("--" + boundary).utf8)
        var starts: [Int] = []
        var i = 0
        while i + marker.count <= bytes.count {
            // 分隔線在一行的開頭
            if (i == 0 || bytes[i - 1] == 10), bytes[i] == 45, Array(bytes[i..<(i + marker.count)]) == marker {
                starts.append(i); i += marker.count
            } else { i += 1 }
        }
        var parts: [Data] = []
        for (n, start) in starts.enumerated() {
            var from = start + marker.count
            if from + 1 < bytes.count, bytes[from] == 45, bytes[from + 1] == 45 { break }   // 結尾的 --boundary--
            while from < bytes.count, bytes[from] == 32 || bytes[from] == 9 { from += 1 }
            if from < bytes.count, bytes[from] == 13 { from += 1 }
            if from < bytes.count, bytes[from] == 10 { from += 1 }
            var to = n + 1 < starts.count ? starts[n + 1] : bytes.count
            if to > from, bytes[to - 1] == 10 { to -= 1 }
            if to > from, bytes[to - 1] == 13 { to -= 1 }
            parts.append(to > from ? Data(bytes[from..<to]) : Data())
        }
        return parts
    }

    private static func decodeBody(_ part: Part) -> Data {
        switch (part.headers["content-transfer-encoding"] ?? "").lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let clean = String(decoding: part.body, as: UTF8.self).components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: clean, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable": return quotedPrintable(part.body)
        default: return part.body
        }
    }

    static func quotedPrintable(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b { case 48...57: return b - 48; case 65...70: return b - 55; case 97...102: return b - 87; default: return nil }
        }
        while i < bytes.count {
            if bytes[i] == 61 {   // =
                if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { i += 3; continue }
                if i + 2 < bytes.count, let a = hex(bytes[i + 1]), let b = hex(bytes[i + 2]) { out.append(a << 4 | b); i += 3; continue }
            }
            out.append(bytes[i]); i += 1
        }
        return Data(out)
    }

    private static func text(_ data: Data, charset: String?) -> String {
        let name = (charset ?? "utf-8").lowercased()
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cf != kCFStringEncodingInvalidId {
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let s = String(data: data, encoding: encoding) { return s }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 信頭的 =?utf-8?B?...?= 和 =?utf-8?Q?...?=
    static func decodeWords(_ value: String) -> String {
        guard value.contains("=?") else { return value }
        let pattern = try! NSRegularExpression(pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=")
        var result = value
        let joined = value.replacingOccurrences(of: "?=\\s+=\\?", with: "?==?", options: .regularExpression)
        result = joined
        let ns = joined as NSString
        for match in pattern.matches(in: joined, range: NSRange(location: 0, length: ns.length)).reversed() {
            let charset = ns.substring(with: match.range(at: 1)), mode = ns.substring(with: match.range(at: 2)).uppercased()
            let payload = ns.substring(with: match.range(at: 3))
            let data: Data
            if mode == "B" { data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) ?? Data() }
            else { data = quotedPrintable(Data(payload.replacingOccurrences(of: "_", with: " ").utf8)) }
            result = (result as NSString).replacingCharacters(in: match.range, with: text(data, charset: charset))
        }
        return result
    }

    static func htmlToText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "(?is)<(script|style|head)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</td>", with: "\t", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (from, to) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&rsquo;", "'"), ("&ldquo;", "\""), ("&rdquo;", "\"")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }

    /// 內嵌圖片的佔位字（[cid:image001.png@…]）、Safe Links 的長網址換成短的
    private static func trimQuoteNoise(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\\[cid:[^\\]]*\\]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<https?://[^>]{120,}>", with: "", options: .regularExpression)
        return s
    }
}
