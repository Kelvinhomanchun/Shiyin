import Foundation
import ImageIO

/// 匯出裡的會議中的畫面（design §83.6、R109.8、D189）：md 旁邊資料夾裡的檔名、HTML 裡的位置標記、Word 檔補圖片
enum ScreenExport {
    /// md 旁邊的圖片檔名：12-34.jpg，同一個時間第二張起加 -2、-3
    static func fileNames(_ screens: [MeetingDocument]) -> [String] {
        var used = Set<String>()
        return screens.map { screen in
            let base = TimeFormat.string(screen.at ?? 0).replacingOccurrences(of: ":", with: "-")
            var name = base + ".jpg"
            var n = 2
            while used.contains(name) { name = "\(base)-\(n).jpg"; n += 1 }
            used.insert(name)
            return name
        }
    }

    /// md 的圖片資料夾：「<檔名> 的畫面」（跟著會議語言）
    static func folderName(for url: URL, language: MeetingLanguage) -> String {
        url.deletingPathExtension().lastPathComponent + language.text(zh: " 的畫面", en: " screens", ja: " の画面")  // l10n-skip
    }

    /// 把圖片複製到 md 旁邊的資料夾
    static func writeFolder(_ screens: [MeetingDocument], next url: URL, language: MeetingLanguage) throws {
        guard !screens.isEmpty else { return }
        let folder = url.deletingLastPathComponent().appendingPathComponent(folderName(for: url, language: language), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (screen, name) in zip(screens, fileNames(screens)) {
            let target = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: screen.fileURL, to: target)
        }
    }

    /// HTML 裡圖片的位置標記（一段只有這個字的段落）：簡繁轉換做完才換成圖片，不讓幾 MB 的圖片資料經過轉換
    static func marker(_ index: Int) -> String { String(format: "SHIYINSCREEN%04d", index + 1) }

    /// PDF：標記的段落換成內嵌的圖片
    static func inlineImages(_ html: String, _ screens: [MeetingDocument]) -> String {
        var out = html
        for (index, screen) in screens.enumerated() {
            // 檔案不見了：拿掉那一段，不要把標記印出來
            let image = (try? Data(contentsOf: screen.fileURL)).map {
                "<p class=\"screen\"><img src=\"data:image/jpeg;base64,\($0.base64EncodedString())\" width=\"480\"></p>"
            } ?? ""
            out = out.replacingOccurrences(of: "<p class=\"screen\">\(marker(index))</p>", with: image)
        }
        return out
    }

    // MARK: 會議紀錄的圖（fork）

    /// 圖的位置標記（同畫面的做法）
    static func diagramMarker(_ index: Int) -> String { String(format: "SHIYINDIAGRAM%04d", index + 1) }

    /// md 旁邊的圖：diagram-1.png、diagram-2.png，放在畫面的同一個資料夾
    static func diagramFileName(_ index: Int) -> String { "diagram-\(index + 1).png" }

    static func writeDiagrams(_ pngs: [Data], next url: URL, language: MeetingLanguage) throws {
        guard !pngs.isEmpty else { return }
        let folder = url.deletingLastPathComponent().appendingPathComponent(folderName(for: url, language: language), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, png) in pngs.enumerated() { try png.write(to: folder.appendingPathComponent(diagramFileName(index))) }
    }

    /// PDF：圖的標記換成內嵌的 PNG（寬度是圖本身的寬，比頁面寬時縮到頁寬）
    static func inlineDiagrams(_ html: String, _ pngs: [Data]) -> String {
        var out = html
        for (index, png) in pngs.enumerated() {
            // 原本的大小、不超過欄寬；高的圖（泳道）縮到約大半頁高，標題才不會被單獨留在上一頁
            let size = pixelSize(png).map { (w: Double($0.width) / 2, h: Double($0.height) / 2) } ?? (w: 600, h: 400)
            let width = Int(min(size.w, size.w * 640 / max(size.h, 1)))
            out = out.replacingOccurrences(of: "<p class=\"diagram\">\(diagramMarker(index))</p>",
                with: "<p class=\"diagram\"><img src=\"data:image/png;base64,\(png.base64EncodedString())\" style=\"width:\(width)px;max-width:100%\"></p>")
        }
        return out
    }

    /// 圖片的像素大小
    static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }
}

/// Word 檔補上圖片（design §83.6、D189）：NSAttributedString 寫出的 docx 不帶圖片（2026-11-19 試過），
/// 所以先讓標記的段落照常寫出來，再解開 docx、把那一段換成圖片（w:drawing）、補 word/media/、關聯和內容類型，重新壓縮
enum DocxImages {
    struct Failure: LocalizedError {
        var reason: String
        var errorDescription: String? { reason }
    }

    /// 版面的寬度（A4 扣掉邊界約 15 公分），EMU
    static let maxWidth = 5_400_000

    static func embed(_ docx: Data, markers: [String], images: [Data]) throws -> Data {
        guard !images.isEmpty else { return docx }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ShiyinDocx-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent("docx", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("in.docx"), output = root.appendingPathComponent("out.docx")
        try docx.write(to: source)
        try run("/usr/bin/unzip", ["-q", "-o", source.path, "-d", dir.path])

        let documentURL = dir.appendingPathComponent("word/document.xml")
        var document = try String(contentsOf: documentURL, encoding: .utf8)
        let relsURL = dir.appendingPathComponent("word/_rels/document.xml.rels")
        var rels = try String(contentsOf: relsURL, encoding: .utf8)
        let media = dir.appendingPathComponent("word/media", isDirectory: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        for (index, (marker, jpeg)) in zip(markers, images).enumerated() {
            guard let at = document.range(of: marker), let start = paragraphStart(document, before: at.lowerBound),
                  let end = document.range(of: "</w:p>", range: at.upperBound..<document.endIndex)?.upperBound else { continue }
            // 檔案不見了：拿掉那一段，不要把標記留在文件裡
            guard let size = ScreenExport.pixelSize(jpeg) else {
                document.removeSubrange(start..<end)
                continue
            }
            let isPNG = jpeg.starts(with: [0x89, 0x50, 0x4E, 0x47])
            let name = "screen\(index + 1).\(isPNG ? "png" : "jpg")", id = "rIdShiyinScreen\(index + 1)"
            try jpeg.write(to: media.appendingPathComponent(name))
            // PNG（圖）是兩倍解析度
            let width = min(maxWidth, size.width * 9525 / (isPNG ? 2 : 1))
            let height = Int(Double(width) * Double(size.height) / Double(size.width))
            document.replaceSubrange(start..<end, with: drawing(id: id, number: index + 1, name: name, width: width, height: height))
            rels = rels.replacingOccurrences(of: "</Relationships>", with:
                "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(name)\"/></Relationships>")
        }
        try document.write(to: documentURL, atomically: true, encoding: .utf8)
        try rels.write(to: relsURL, atomically: true, encoding: .utf8)
        let typesURL = dir.appendingPathComponent("[Content_Types].xml")
        var types = try String(contentsOf: typesURL, encoding: .utf8)
        var typesChanged = false
        if !types.contains("Extension=\"jpg\"") {
            types = types.replacingOccurrences(of: "<Default Extension=\"xml\"", with: "<Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Default Extension=\"xml\"")
            typesChanged = true
        }
        if !types.contains("Extension=\"png\"") {
            types = types.replacingOccurrences(of: "<Default Extension=\"xml\"", with: "<Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"xml\"")
            typesChanged = true
        }
        if typesChanged { try types.write(to: typesURL, atomically: true, encoding: .utf8) }
        // [Content_Types].xml 放第一個（有些讀取程式要求）
        let entries = (try fm.contentsOfDirectory(atPath: dir.path)).filter { $0 != "[Content_Types].xml" }.sorted()
        try run("/usr/bin/zip", ["-X", "-q", "-r", output.path, "[Content_Types].xml"] + entries, in: dir)
        return try Data(contentsOf: output)
    }

    /// 標記所在的段落從哪裡開始（<w:p> 或 <w:p ...>，不是 <w:pPr>）
    private static func paragraphStart(_ xml: String, before index: String.Index) -> String.Index? {
        var search = xml.startIndex..<index
        while let found = xml.range(of: "<w:p", options: .backwards, range: search) {
            let next = xml[found.upperBound...].first
            if next == ">" || next == " " { return found.lowerBound }
            search = xml.startIndex..<found.lowerBound
        }
        return nil
    }

    private static func drawing(id: String, number: Int, name: String, width: Int, height: Int) -> String {
        "<w:p><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(width)\" cy=\"\(height)\"/>"
            + "<wp:docPr id=\"\(number)\" name=\"Screen \(number)\"/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
            + "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:nvPicPr><pic:cNvPr id=\"\(number)\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"\(id)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
    }

    private static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(reason: String(localized: "Word 檔加圖片失敗（\((tool as NSString).lastPathComponent) 結束代碼 \(process.terminationStatus)）"))
        }
    }
}
