import AppKit
import SwiftUI

/// 會議紀錄的圖（fork）：DiagramLayout 算好的座標，用 Canvas 畫線、框和字。
/// 配色是 IBM：一般的框白底、Gray 100 的線；重點的框 Blue 10 底、Blue 60 的線；連線 Gray 70；資料是 Gray 10 底；
/// 匯出（exporting）一律白底淺色，畫面上跟著深色模式
struct DiagramView: View {
    @Environment(\.colorScheme) private var colorScheme
    let diagram: MeetingDiagrams.Diagram
    let layout: DiagramLayout.Layout
    var exporting = false
    var onSeek: ((Double) -> Void)? = nil

    init(diagram: MeetingDiagrams.Diagram, exporting: Bool = false, onSeek: ((Double) -> Void)? = nil) {
        self.diagram = diagram
        self.layout = DiagramLayout.layout(diagram)
        self.exporting = exporting
        self.onSeek = onSeek
    }

    private var dark: Bool { !exporting && colorScheme == .dark }
    private var palette: DiagramPalette { DiagramPalette(dark: dark) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(&context) }
                .frame(width: layout.width, height: layout.height)
            // 時間點：點了播放（只有畫面上、有錄音時）
            if let onSeek {
                ForEach(Array(layout.boxes.enumerated()), id: \.offset) { _, box in
                    if let seconds = TimeFormat.seconds(box.time) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: box.w, height: box.h)
                            .offset(x: box.x, y: box.y)
                            .onTapGesture { onSeek(seconds) }
                            .help("從 \(box.time) 播放")
                    }
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .background(exporting ? Color.white : Color.clear)
        .environment(\.colorScheme, exporting ? .light : colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(diagram.title))
        .accessibilityValue(Text(diagram.nodes.map(\.label).joined(separator: ", ")))
    }

    private func font(_ size: Double, weight: String) -> Font {
        // app 啟動時登錄了 IBM Plex Sans（HTML.registerFonts）；中日文的字系統會自己補
        .custom("IBM Plex Sans", size: size).weight(weight == "semibold" ? .semibold : weight == "medium" ? .medium : .regular)
    }

    private func draw(_ context: inout GraphicsContext) {
        let p = palette
        // 泳道：欄的底色交錯、上面一列道名
        for (k, lane) in layout.lanes.enumerated() {
            let rect = CGRect(x: lane.x, y: layout.laneTop, width: lane.w, height: layout.height - layout.laneTop - 8)
            if k % 2 == 0 { context.fill(Path(rect), with: .color(p.laneFill)) }
            context.stroke(Path(rect), with: .color(p.rule), lineWidth: 1)
            let header = CGRect(x: lane.x, y: layout.laneTop, width: lane.w, height: layout.laneHeaderHeight)
            context.fill(Path(header), with: .color(p.laneHeader))
            let text = Text(lane.name.uppercased()).font(font(10, weight: "semibold")).foregroundStyle(p.soft).tracking(0.8)
            context.draw(text, in: header.insetBy(dx: 8, dy: 10))
        }
        // 時間軸
        for axis in layout.axes {
            var path = Path()
            path.move(to: CGPoint(x: axis.x0, y: axis.y))
            path.addLine(to: CGPoint(x: axis.x1, y: axis.y))
            context.stroke(path, with: .color(p.muted), lineWidth: 1.5)
        }
        // 線先畫（在框的下面）
        for line in layout.lines {
            let path = rounded(line.points, radius: 8)
            let color = p.line
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                                                       dash: line.dashed ? [5, 4] : []))
            if line.arrow, line.points.count >= 2 { arrowhead(&context, from: line.points[line.points.count - 2], to: line.points.last!, color: color) }
            if layout.axes.isEmpty == false, !line.arrow {
                let end = line.points[0]
                context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(p.muted))
            }
        }
        // 線上的字（有底色遮住後面的線，跟線留空隙）
        for line in layout.lines {
            guard let at = line.labelAt else { continue }
            let rect = CGRect(x: at.x, y: at.y, width: line.labelSize.w, height: line.labelSize.h)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(p.paper))
            let text = Text(line.label.uppercased()).font(.custom("IBM Plex Sans", size: DiagramLayout.edgeLabelSize).weight(.medium))
                .foregroundStyle(p.soft).tracking(0.4)
            context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
        }
        for box in layout.boxes { drawBox(&context, box) }
    }

    private func drawBox(_ context: inout GraphicsContext, _ box: DiagramLayout.Box) {
        let p = palette
        let rect = CGRect(x: box.x, y: box.y, width: box.w, height: box.h)
        let shape: Path
        switch box.shape {
        case .decision:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            shape = path
        case .start, .end: shape = Path(roundedRect: rect, cornerRadius: min(20, rect.height / 2))
        default: shape = Path(roundedRect: rect, cornerRadius: 6)
        }
        let fill: Color = box.focal ? p.focalFill : box.shape == .data ? p.dataFill : box.shape == .system ? p.systemFill : p.paper
        let stroke: Color = box.focal ? p.accent : box.shape == .data || box.shape == .system ? p.muted : p.ink
        context.fill(shape, with: .color(fill))
        context.stroke(shape, with: .color(stroke), lineWidth: box.focal ? 2 : 1.25)
        if box.shape == .data {
            // 資料：上緣一條細線（像表格、檔案）
            var top = Path()
            top.move(to: CGPoint(x: rect.minX + 6, y: rect.minY + 6))
            top.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 6))
            context.stroke(top, with: .color(p.rule), lineWidth: 1)
        }
        // 字：置中
        var lines: [(Text, Double)] = []
        if let number = box.number {
            lines.append((Text(String(format: "%02d", number)).font(.custom("IBM Plex Sans", size: 10).weight(.semibold))
                .foregroundStyle(box.focal ? p.accent : p.soft), DiagramLayout.detailLine))
        }
        for l in box.label {
            lines.append((Text(l).font(font(DiagramLayout.labelSize, weight: "semibold")).foregroundStyle(p.ink), DiagramLayout.labelLine))
        }
        for l in box.detail {
            lines.append((Text(l).font(font(DiagramLayout.detailSize, weight: "regular")).foregroundStyle(p.soft), DiagramLayout.detailLine))
        }
        let total = lines.reduce(0) { $0 + $1.1 }
        var y = rect.midY - total / 2
        for (text, h) in lines {
            context.draw(text, at: CGPoint(x: rect.midX, y: y + h / 2))
            y += h
        }
    }

    private func arrowhead(_ context: inout GraphicsContext, from a: DiagramLayout.Point, to b: DiagramLayout.Point, color: Color) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let tip = CGPoint(x: b.x, y: b.y)
        let size = 8.0, half = 3.5
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle) + half * sin(angle), y: tip.y - size * sin(angle) - half * cos(angle)))
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle) - half * sin(angle), y: tip.y - size * sin(angle) + half * cos(angle)))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    /// 直角的折線，轉角是圓角；最後一段停在箭頭的底（箭頭的尖端在框邊上）
    private func rounded(_ pts: [DiagramLayout.Point], radius: Double) -> Path {
        var path = Path()
        guard pts.count >= 2 else { return path }
        var points = pts.map { CGPoint(x: $0.x, y: $0.y) }
        let last = points.count - 1
        let dx = points[last].x - points[last - 1].x, dy = points[last].y - points[last - 1].y
        let length = max(hypot(dx, dy), 0.001)
        points[last] = CGPoint(x: points[last].x - dx / length * 6, y: points[last].y - dy / length * 6)
        path.move(to: points[0])
        for i in 1..<points.count {
            if i < points.count - 1 {
                let p0 = points[i - 1], p1 = points[i], p2 = points[i + 1]
                let r = min(radius, hypot(p1.x - p0.x, p1.y - p0.y) / 2, hypot(p2.x - p1.x, p2.y - p1.y) / 2)
                path.addArc(tangent1End: p1, tangent2End: p2, radius: r)
            } else {
                path.addLine(to: points[i])
            }
        }
        return path
    }
}

/// IBM 的顏色（淺色 / 深色）
struct DiagramPalette {
    let dark: Bool
    var paper: Color { dark ? Color(hex: "#161616") : .white }
    var ink: Color { dark ? Color(hex: "#F4F4F4") : Color(hex: "#161616") }
    var soft: Color { dark ? Color(hex: "#A8A8A8") : Color(hex: "#525252") }
    var muted: Color { dark ? Color(hex: "#8D8D8D") : Color(hex: "#6F6F6F") }
    var line: Color { dark ? Color(hex: "#A8A8A8") : Color(hex: "#525252") }
    var rule: Color { dark ? Color(hex: "#393939") : Color(hex: "#E0E0E0") }
    var accent: Color { dark ? Color(hex: "#78A9FF") : Color(hex: "#0F62FE") }
    var focalFill: Color { dark ? Color(hex: "#001D6C") : Color(hex: "#EDF5FF") }
    var dataFill: Color { dark ? Color(hex: "#262626") : Color(hex: "#F4F4F4") }
    var systemFill: Color { dark ? Color(hex: "#1C1C1C") : Color(hex: "#FAFAFA") }
    var laneFill: Color { dark ? Color(hex: "#1C1C1C") : Color(hex: "#F9F9F9") }
    var laneHeader: Color { dark ? Color(hex: "#262626") : Color(hex: "#F4F4F4") }
}

/// 會議紀錄頁上「圖」那一段：每張圖一個標題、一句說明、圖（比欄寬寬時左右捲）
struct DiagramsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.textScale) private var textScale
    let detail: MeetingDetail
    let record: DiagramRecord

    var body: some View {
        let stale = detail.notes.map { Diagrams.notesKey($0) != record.notesKey } ?? false
        NotesSection(title: String(localized: "圖")) {
            Button(detail.drawingDiagrams ? String(localized: "畫圖中…") : String(localized: "重新畫"), systemImage: "arrow.clockwise") { model.redrawDiagrams() }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(detail.drawingDiagrams || detail.meeting.deletedAt != nil)
                .help("請整理工具依目前的會議紀錄重新判斷要畫哪些圖")
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                if stale {
                    Label("這些圖是依之前的會議紀錄畫的", systemImage: "clock.arrow.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(record.diagrams.diagrams.enumerated()), id: \.offset) { _, diagram in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(diagram.title).contentTitleFont(16)
                        if !diagram.caption.isEmpty {
                            Text(diagram.caption).foregroundStyle(.secondary)
                        }
                        DiagramFrame(view: DiagramView(diagram: diagram, onSeek: model.player.isLoaded ? { model.player.seek(to: $0) } : nil),
                                     textScale: textScale)
                    }
                }
            }
        }
    }
}

/// 圖放進欄寬：跟著文字大小放大，比欄寬寬時縮到欄寬（最小縮到原本的 0.75 倍，字還看得清楚；再寬就左右捲）
private struct DiagramFrame: View {
    let view: DiagramView
    let textScale: Double
    @State private var available: Double = 0

    var body: some View {
        let width = view.layout.width
        let fit = available > 0 ? available / width : textScale
        let scale = max(min(textScale, fit), min(0.75, textScale))
        ScrollView(.horizontal) {
            view.scaleEffect(scale, anchor: .topLeading)
                .frame(width: width * scale, height: view.layout.height * scale, alignment: .topLeading)
        }
        .frame(height: view.layout.height * scale)
        .scrollIndicators(.automatic)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { available = $0 }
    }
}

/// 匯出：跟畫面同一個 DiagramView，白底，兩倍解析度的 PNG
@MainActor
enum DiagramExport {
    static func png(_ diagram: MeetingDiagrams.Diagram) -> Data? {
        let renderer = ImageRenderer(content: DiagramView(diagram: diagram, exporting: true))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// 匯出檔用的圖：簡體會議轉成簡體；圖不是依目前的紀錄畫的照樣放（畫面上有註明）
    static func pngs(_ b: ExportBundle) -> [(diagram: MeetingDiagrams.Diagram, png: Data)] {
        guard let record = b.diagrams else { return [] }
        let diagrams = AppSettings.simplifiedChinese(for: b.meeting.notesOutputLanguage)
            ? record.diagrams.mappingText(ChineseScript.toSimplified) : record.diagrams
        return diagrams.diagrams.compactMap { d in png(d).map { (d, $0) } }
    }
}
