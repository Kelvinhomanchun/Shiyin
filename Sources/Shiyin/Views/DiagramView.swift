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
        // 匯出的圖不放錄音的時間點（檔案可能給客戶，fork）；畫面上留著，點了播放
        var shown = diagram
        if exporting { shown.nodes = shown.nodes.map { var n = $0; n.time = ""; return n } }
        self.diagram = shown
        self.layout = DiagramLayout.layout(shown)
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
        for (k, lane) in layout.lanes.enumerated() where lane.horizontal {
            // 橫的道：一列一條，道名在左邊的欄
            let rect = CGRect(x: lane.x, y: lane.y, width: lane.w, height: lane.h)
            if k % 2 == 0 { context.fill(Path(rect), with: .color(p.laneFill)) }
            context.stroke(Path(rect), with: .color(p.rule), lineWidth: 1)
            let header = CGRect(x: lane.x, y: lane.y, width: DiagramLayout.laneLabel - 12, height: lane.h)
            context.fill(Path(header), with: .color(p.laneHeader))
            let text = Text(lane.name.uppercased()).font(font(10, weight: "semibold")).foregroundStyle(p.soft).tracking(0.8)
            context.draw(text, in: header.insetBy(dx: 8, dy: max(8, lane.h / 2 - 14)))
        }
        for (k, lane) in layout.lanes.enumerated() where !lane.horizontal {
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
            lines.append((Text(number).font(.custom("IBM Plex Sans", size: 10).weight(.semibold))
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

/// 會議紀錄頁上「圖」那一段（fork）：不會自己畫，使用者決定。
/// 1. 「建議可以畫的圖」：整理工具指出哪些段落畫成圖比較清楚（為什麼、哪一段），使用者按「畫」或「不需要」；也可以自己描述一張
/// 2. 畫好的圖：下面列出說過的意見，「提意見重新畫」把意見一起給整理工具、改之前的版本可以「復原」、⋯ 裡移動或移除
/// 3. 匯出只放畫好的圖（不放時間點）
struct DiagramsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.textScale) private var textScale
    let detail: MeetingDetail
    /// 按了「移除」、等確認的那張
    private var removing: MeetingDiagrams.Diagram? { model.diagramRemoving.flatMap { id in drawn.first { $0.id == id } } }

    private var record: DiagramRecord? { detail.diagrams }
    private var drawn: [MeetingDiagrams.Diagram] { record?.diagrams.diagrams ?? [] }
    private var suggestions: [MeetingDiagrams.Suggestion] { record?.suggestions ?? [] }
    private var locked: Bool { detail.meeting.deletedAt != nil || model.viewingNotes != nil }
    /// 使用者自己描述、正在畫的（還沒有卡片）
    private var describing: [MeetingDiagrams.Suggestion] {
        detail.diagramJobs.compactMap { $0.mode == .draw ? $0.suggestion : nil }.filter { s in !suggestions.contains { $0.id == s.id } }
    }

    var body: some View {
        NotesSection(title: String(localized: "圖")) {
            HStack(spacing: 14) {
                Button(detail.suggestingDiagrams ? String(localized: "找可以畫的地方…") : String(localized: "建議可以畫的圖"),
                       systemImage: "sparkles") { model.suggestDiagrams() }
                    .disabled(detail.suggestingDiagrams || locked)
                    .help("請整理工具看會議紀錄和逐字稿，建議哪些段落畫成圖比較清楚；你決定要畫哪一張")
                Button("自己描述一張圖…", systemImage: "square.and.pencil") { model.diagramComment = DiagramCommentRequest(meetingId: detail.meeting.id!, diagramId: nil) }
                    .disabled(locked)
                    .help("寫下要畫什麼，例如：Shing 每個月產生報表的步驟，分成 AMS 和 Shing 兩條道")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(locked ? Color.secondary : Color.celadon)
            .font(.callout)
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                if drawn.isEmpty && suggestions.isEmpty && describing.isEmpty && !detail.suggestingDiagrams {
                    Text(record?.suggested == true
                         ? String(localized: "整理工具覺得這場會議沒有適合畫成圖的地方。要的話可以自己描述一張。")
                         : String(localized: "講到流程、步驟或交接的會議，畫成圖比較容易看懂。按「建議可以畫的圖」，整理工具會指出可以畫的段落，你決定要畫哪些；不會自己畫。"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if detail.suggestingDiagrams {
                    Label("正在找這場會議裡可以畫成圖的地方…", systemImage: "hourglass").foregroundStyle(.secondary)
                }
                ForEach(drawn, id: \.id) { d in diagramCard(d) }
                ForEach(describing, id: \.id) { s in
                    Label("正在畫「\(s.title)」…", systemImage: "hourglass").foregroundStyle(.secondary)
                }
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(drawn.isEmpty ? String(localized: "可以畫的圖") : String(localized: "還可以畫的圖"))
                            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(suggestions) { s in suggestionCard(s) }
                    }
                }
            }
            .confirmationDialog(String(localized: "移除「\(removing?.title ?? "")」？"),
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { model.diagramRemoving = nil } })) {
                Button("移除", role: .destructive) { model.confirmRemoveDiagram() }
            } message: {
                Text(removing?.request?.userRequest.isEmpty == false
                     ? String(localized: "這張圖、你的意見和之前的版本都會拿掉。")
                     : String(localized: "這張圖、你的意見和之前的版本都會拿掉。整理工具的建議會放回「可以畫的圖」，之後可以再畫。"))
            }
        }
    }

    // MARK: 建議

    private func suggestionCard(_ s: MeetingDiagrams.Suggestion) -> some View {
        let drawing = detail.drawingSuggestions.contains(s.id)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.icon(s.kind)).foregroundStyle(Color.celadon).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title).fontWeight(.semibold)
                Text(Self.kindName(s.kind)).font(.callout).foregroundStyle(.secondary)
                if !s.why.isEmpty { Text(s.why).fixedSize(horizontal: false, vertical: true) }
                if !s.focus.isEmpty || !s.time.isEmpty {
                    HStack(spacing: 6) {
                        if !s.focus.isEmpty { Text(s.focus).foregroundStyle(.secondary).lineLimit(2) }
                        if let seconds = TimeFormat.seconds(s.time), model.player.isLoaded {
                            Button(s.time) { model.player.seek(to: seconds) }.buttonStyle(.borderless).foregroundStyle(Color.celadon)
                                .help("從 \(s.time) 播放")
                        } else if !s.time.isEmpty { Text(s.time).foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                }
                HStack(spacing: 14) {
                    if drawing {
                        ProgressView().controlSize(.small)
                        Text("畫圖中…").foregroundStyle(.secondary)
                    } else {
                        Button("畫這張圖", systemImage: "pencil.and.outline") { model.drawSuggestion(s) }
                            .foregroundStyle(Color.celadon)
                            .disabled(locked)
                        Button("不需要") { model.dismissSuggestion(s.id) }
                            .foregroundStyle(.secondary)
                            .disabled(locked)
                            .help("把這個建議拿掉")
                    }
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.celadon.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: 畫好的圖

    private func diagramCard(_ d: MeetingDiagrams.Diagram) -> some View {
        let redrawing = detail.redrawingDiagrams.contains(d.id)
        let canUndo = !(record?.history[d.id] ?? []).isEmpty
        let index = drawn.firstIndex { $0.id == d.id } ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(d.title).contentTitleFont(16)
            if !d.caption.isEmpty { Text(d.caption).foregroundStyle(.secondary) }
            if record?.isStale(d, notes: detail.notes) == true {
                Label("這張圖是依之前的會議紀錄畫的", systemImage: "clock.arrow.circlepath").font(.callout).foregroundStyle(.secondary)
            }
            DiagramFrame(view: DiagramView(diagram: d, onSeek: model.player.isLoaded ? { model.player.seek(to: $0) } : nil), textScale: textScale)
                .opacity(redrawing ? 0.4 : 1)
            if !d.comments.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("你的意見（重新畫時都會一起考慮）").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(d.comments.enumerated()), id: \.offset) { k, c in
                        Text("\(k + 1). \(c)").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
            }
            HStack(spacing: 14) {
                if redrawing {
                    ProgressView().controlSize(.small)
                    Text("依你的意見重新畫…").foregroundStyle(.secondary)
                } else {
                    Button("提意見重新畫…", systemImage: "text.bubble") {
                        model.diagramComment = DiagramCommentRequest(meetingId: detail.meeting.id!, diagramId: d.id)
                    }
                    .foregroundStyle(Color.celadon)
                    .help("說哪裡要改（只畫現在的做法、分成幾條道、少幾步…），整理工具照你的意見重新畫")
                    if canUndo {
                        Button("復原上一版", systemImage: "arrow.uturn.backward") { model.undoDiagram(d.id) }
                            .foregroundStyle(Color.celadon)
                            .help("換回重新畫之前的那張圖")
                    }
                    // 下載（給客戶的檔：白底、不放錄音時間點）；不受 locked 影響，舊版紀錄、垃圾桶裡的也能下載
                    FloatingMenuLabelButton(title: String(localized: "下載"), systemImage: "arrow.down.circle",
                                            help: String(localized: "存成圖片、PDF 或可以改的 draw.io 檔"), debugKey: "diagramdownload-\(index)") {
                        DiagramExport.Format.allCases.map { f in
                            MenuEntry.action(DiagramExport.title(f), icon: DiagramExport.icon(f)) { model.downloadDiagram(d, format: f) }
                        } + [.divider, .action(String(localized: "拷貝圖片"), icon: "doc.on.doc") { model.copyDiagram(d) }]
                    }
                    FloatingMenuButton {
                        [MenuEntry.action(String(localized: "照同樣的要求再畫一次"), icon: "arrow.clockwise") { _ = model.redrawDiagram(d.id, comment: "") },
                         .action(String(localized: "往上移"), icon: "arrow.up", enabled: index > 0) { model.moveDiagram(d.id, by: -1) },
                         .action(String(localized: "往下移"), icon: "arrow.down", enabled: index < drawn.count - 1) { model.moveDiagram(d.id, by: 1) }]
                    }
                    .help("更多")
                    Spacer(minLength: 0)
                    // 移除放在看得到的地方（使用者找不到 ⋯ 裡的）；意見和舊版本會一起丟掉，先問一次
                    Button("移除", systemImage: "trash") { model.diagramRemoving = d.id }
                        .foregroundStyle(.secondary)
                        .help("移除這張圖（整理工具建議的會放回「可以畫的圖」）")
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .disabled(locked)
        }
    }

    static func icon(_ kind: MeetingDiagrams.Kind) -> String {
        switch kind {
        case .flowchart: "arrow.triangle.branch"
        case .steps: "list.number"
        case .swimlane: "rectangle.split.3x1"
        case .dataFlow: "arrow.left.arrow.right"
        case .timeline: "calendar.day.timeline.left"
        }
    }

    static func kindName(_ kind: MeetingDiagrams.Kind) -> String {
        switch kind {
        case .flowchart: String(localized: "流程圖（有判斷、分支）")
        case .steps: String(localized: "步驟")
        case .swimlane: String(localized: "泳道圖（誰做哪一步、怎麼交接）")
        case .dataFlow: String(localized: "資料流向")
        case .timeline: String(localized: "時間軸")
        }
    }
}

/// 「提意見重新畫」「自己描述一張圖」的彈窗
struct DiagramCommentRequest: Identifiable, Equatable {
    var meetingId: Int64
    /// nil：自己描述一張新的圖
    var diagramId: String?
    var id: String { "\(meetingId)-\(diagramId ?? "new")" }
}

struct DiagramCommentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: DiagramCommentRequest
    @State private var text = ""
    @FocusState private var focused: Bool

    private var diagram: MeetingDiagrams.Diagram? { request.diagramId.flatMap { model.detail?.diagrams?.diagram($0) } }

    private var suggestions: [String] {
        if diagram != nil {
            return [String(localized: "只畫現在的做法，不要畫之後的計畫"),
                    String(localized: "分成幾條道，每條是一個人或團隊："),
                    String(localized: "少幾步，合併成主要的步驟"),
                    String(localized: "補上漏掉的步驟："),
                    String(localized: "重點應該是：")]
        }
        return [String(localized: "畫成泳道圖：誰做哪一步、怎麼交接"),
                String(localized: "畫成步驟："),
                String(localized: "畫成流程圖，包括判斷的地方："),
                String(localized: "畫出資料從哪裡來、到哪裡去")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: diagram.map { String(localized: "重新畫「\($0.title)」") } ?? String(localized: "自己描述一張圖"),
                        subtitle: diagram == nil
                            ? String(localized: "寫下要畫什麼、畫成哪一種圖。整理工具會對照會議紀錄和逐字稿來畫。")
                            : String(localized: "說哪裡要改。之前的意見也會一起考慮，改之前的那張可以復原。"))
            if let diagram, !diagram.comments.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("之前的意見").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(diagram.comments.enumerated()), id: \.offset) { k, c in
                        Text("\(k + 1). \(c)").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SheetFieldLabel(diagram == nil ? String(localized: "要畫什麼") : String(localized: "要怎麼改"))
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(diagram == nil
                             ? String(localized: "例如：Shing 每個月產生 Power BI 報表的步驟，從 AMS 給檔案到匯出報表")
                             : String(localized: "例如：只畫 Shing 現在的做法，不用畫新系統；下載和改檔名合成一步"))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(5)
                        .focused($focused)
                        .accessibilityLabel(Text(diagram == nil ? "要畫什麼" : "要怎麼改"))
                }
                .frame(minHeight: 96, maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.25)))
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) {
                            text = text.isEmpty ? s : text + (text.hasSuffix("\n") ? "" : "\n") + s
                            focused = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .help("放進輸入框，再自己補完")
                    }
                }
            }
            HStack(spacing: 10) {
                Text("⌘↩ 送出").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("取消") {
                    model.diagramDraft[request.id] = text.isEmpty ? nil : text
                    dismiss()
                }
                .buttonStyle(SheetPillButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
                Button(diagram == nil ? String(localized: "畫圖") : String(localized: "重新畫")) {
                    let sent = request.diagramId.map { model.redrawDiagram($0, comment: text) } ?? model.drawDescribed(text)
                    if sent { model.diagramDraft[request.id] = nil; dismiss() }
                }
                .buttonStyle(SheetPillButtonStyle(.primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheetChrome(width: 520)
        .onAppear {
            if let draft = model.diagramDraft[request.id] { text = draft }
            focused = true
        }
    }
}

/// 圖放進欄寬：跟著文字大小放大，比欄寬寬時縮到欄寬（最小縮到原本的 0.75 倍，字還看得清楚；再寬就左右捲）
struct DiagramFrame: View {
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

/// 匯出：跟畫面同一個 DiagramView，白底。PNG 給 Word、PDF 匯出用兩倍；下載的圖三倍（投影片放大也清楚）
@MainActor
enum DiagramExport {
    static func png(_ diagram: MeetingDiagrams.Diagram, scale: Double = 2) -> Data? {
        guard let image = cgImage(diagram, scale: scale) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        // 下載的圖記下解析度（216 dpi），放進 Word、PowerPoint 是原本的大小，不會大三倍；匯出用的兩倍照舊
        if scale != 2 { rep.size = NSSize(width: Double(image.width) / scale, height: Double(image.height) / scale) }
        return rep.representation(using: .png, properties: [:])
    }

    static func cgImage(_ diagram: MeetingDiagrams.Diagram, scale: Double) -> CGImage? {
        let renderer = ImageRenderer(content: DiagramView(diagram: diagram, exporting: true))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// JPEG：白底（沒有透明），品質 0.92
    static func jpeg(_ diagram: MeetingDiagrams.Diagram, scale: Double = 3) -> Data? {
        guard let image = cgImage(diagram, scale: scale) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    /// PDF：向量（放大不會糊），字嵌進檔案；頁面就是圖的大小
    static func pdf(_ diagram: MeetingDiagrams.Diagram) -> Data? {
        let renderer = ImageRenderer(content: DiagramView(diagram: diagram, exporting: true))
        let data = NSMutableData()
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box,
                                          [kCGPDFContextTitle: diagram.title, kCGPDFContextCreator: "KelNote"] as CFDictionary)  // l10n-skip
            else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            ok = true
        }
        return ok ? data as Data : nil
    }

    enum Format: String, CaseIterable, Identifiable {
        case png, jpg, svg, pdf, drawio
        var id: String { rawValue }
    }

    static func title(_ f: Format) -> String {
        switch f {
        case .png: return String(localized: "PNG（簡報、Word 用）")
        case .jpg: return String(localized: "JPEG（電子郵件用）")
        case .svg: return String(localized: "SVG（向量，網頁、Figma 用）")
        case .pdf: return String(localized: "PDF（向量，列印、寄給客戶）")
        case .drawio: return String(localized: "draw.io（可以再改）")
        }
    }

    static func icon(_ f: Format) -> String {
        switch f {
        case .png, .jpg: return "photo"
        case .svg: return "square.on.circle"
        case .pdf: return "doc.richtext"
        case .drawio: return "pencil.and.outline"
        }
    }

    static func data(_ diagram: MeetingDiagrams.Diagram, _ format: Format) -> Data? {
        switch format {
        case .png: return png(diagram, scale: 3)
        case .jpg: return jpeg(diagram)
        case .svg: return DiagramFiles.svg(diagram)
        case .pdf: return pdf(diagram)
        case .drawio: return DiagramFiles.drawio(diagram)
        }
    }

    /// 匯出、下載用的圖：簡體會議轉成簡體
    static func forExport(_ diagram: MeetingDiagrams.Diagram, meeting: Meeting) -> MeetingDiagrams.Diagram {
        guard AppSettings.simplifiedChinese(for: meeting.notesOutputLanguage) else { return diagram }
        return MeetingDiagrams(diagrams: [diagram]).mappingText(ChineseScript.toSimplified).diagrams.first ?? diagram
    }

    /// 匯出檔用的圖：簡體會議轉成簡體；圖不是依目前的紀錄畫的照樣放（畫面上有註明）
    static func pngs(_ b: ExportBundle) -> [(diagram: MeetingDiagrams.Diagram, png: Data)] {
        guard let record = b.diagrams else { return [] }
        let diagrams = AppSettings.simplifiedChinese(for: b.meeting.notesOutputLanguage)
            ? record.diagrams.mappingText(ChineseScript.toSimplified) : record.diagrams
        return diagrams.diagrams.compactMap { d in png(d).map { (d, $0) } }
    }
}
