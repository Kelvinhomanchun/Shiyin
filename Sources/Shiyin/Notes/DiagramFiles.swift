import Foundation

/// 圖下載成檔案（fork）：SVG、draw.io 從同一份排版（DiagramLayout）寫出來，跟畫面、PNG 長得一樣。
/// 都是白底淺色（給客戶的），不放錄音的時間點
enum DiagramFiles {
    /// 排版本身四周已經留了 DiagramLayout.margin，這裡不再加（跟 PNG 一樣大）
    static let pad = 0.0

    /// IBM 淺色（同 DiagramPalette 的淺色）
    private enum C {
        static let paper = "#FFFFFF", ink = "#161616", soft = "#525252", muted = "#6F6F6F", line = "#525252"
        static let rule = "#E0E0E0", accent = "#0F62FE", focalFill = "#EDF5FF", dataFill = "#F4F4F4"
        static let systemFill = "#FAFAFA", laneFill = "#F9F9F9", laneHeader = "#F4F4F4"
    }
    private static let fonts = "'IBM Plex Sans', 'Helvetica Neue', Helvetica, Arial, sans-serif"

    /// 給客戶的檔不放錄音的時間點（同 DiagramView 的 exporting）
    private static func clientLayout(_ diagram: MeetingDiagrams.Diagram) -> DiagramLayout.Layout {
        var d = diagram
        d.nodes = d.nodes.map { var n = $0; n.time = ""; return n }
        return DiagramLayout.layout(d)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func n(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    private static func fill(_ b: DiagramLayout.Box) -> String {
        b.focal ? C.focalFill : b.shape == .data ? C.dataFill : b.shape == .system ? C.systemFill : C.paper
    }
    private static func stroke(_ b: DiagramLayout.Box) -> String {
        b.focal ? C.accent : b.shape == .data || b.shape == .system ? C.muted : C.ink
    }

    // MARK: SVG

    static func svg(_ diagram: MeetingDiagrams.Diagram) -> Data {
        let layout = clientLayout(diagram)
        let w = layout.width + 2 * pad, h = layout.height + 2 * pad
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(n(w))" height="\(n(h))" viewBox="0 0 \(n(w)) \(n(h))" font-family="\(fonts)">
        <title>\(esc(diagram.title))</title>
        <rect width="100%" height="100%" fill="\(C.paper)"/>
        <g transform="translate(\(n(pad)) \(n(pad)))">

        """
        for (k, lane) in layout.lanes.enumerated() {
            let rect = lane.horizontal ? (lane.x, lane.y, lane.w, lane.h)
                : (lane.x, layout.laneTop, lane.w, layout.height - layout.laneTop - 8)
            let header = lane.horizontal ? (lane.x, lane.y, DiagramLayout.laneLabel - 12, lane.h)
                : (lane.x, layout.laneTop, lane.w, layout.laneHeaderHeight)
            out += "<rect x=\"\(n(rect.0))\" y=\"\(n(rect.1))\" width=\"\(n(rect.2))\" height=\"\(n(rect.3))\" fill=\"\(k % 2 == 0 ? C.laneFill : C.paper)\" stroke=\"\(C.rule)\"/>\n"
            out += "<rect x=\"\(n(header.0))\" y=\"\(n(header.1))\" width=\"\(n(header.2))\" height=\"\(n(header.3))\" fill=\"\(C.laneHeader)\"/>\n"
            let name = lane.name.uppercased()
            let wrapped = lane.horizontal ? MindMap.wrap(name, maxWidth: header.2 - 16, size: 10.5) : [name]
            let top = lane.horizontal ? header.1 + max(8, lane.h / 2 - 14) + 7 : header.1 + 17
            for (i, l) in wrapped.enumerated() {
                out += "<text x=\"\(n(header.0 + 8))\" y=\"\(n(top + Double(i) * 13))\" font-size=\"10\" font-weight=\"600\" letter-spacing=\"0.8\" fill=\"\(C.soft)\" dominant-baseline=\"central\">\(esc(l))</text>\n"
            }
        }
        for axis in layout.axes {
            out += "<line x1=\"\(n(axis.x0))\" y1=\"\(n(axis.y))\" x2=\"\(n(axis.x1))\" y2=\"\(n(axis.y))\" stroke=\"\(C.muted)\" stroke-width=\"1.5\"/>\n"
        }
        for line in layout.lines {
            out += "<path d=\"\(path(line.points))\" fill=\"none\" stroke=\"\(C.line)\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(line.dashed ? " stroke-dasharray=\"5 4\"" : "")/>\n"
            if line.arrow, line.points.count >= 2 {
                let a = line.points[line.points.count - 2], b = line.points.last!
                let angle = atan2(b.y - a.y, b.x - a.x), size = 8.0, half = 3.5
                let p1 = (b.x - size * cos(angle) + half * sin(angle), b.y - size * sin(angle) - half * cos(angle))
                let p2 = (b.x - size * cos(angle) - half * sin(angle), b.y - size * sin(angle) + half * cos(angle))
                out += "<path d=\"M\(n(b.x)) \(n(b.y)) L\(n(p1.0)) \(n(p1.1)) L\(n(p2.0)) \(n(p2.1)) Z\" fill=\"\(C.line)\"/>\n"
            } else if !layout.axes.isEmpty, let p = line.points.first {
                out += "<circle cx=\"\(n(p.x))\" cy=\"\(n(p.y))\" r=\"4\" fill=\"\(C.muted)\"/>\n"
            }
        }
        for line in layout.lines {
            guard let at = line.labelAt else { continue }
            out += "<rect x=\"\(n(at.x))\" y=\"\(n(at.y))\" width=\"\(n(line.labelSize.w))\" height=\"\(n(line.labelSize.h))\" rx=\"2\" fill=\"\(C.paper)\"/>\n"
            out += "<text x=\"\(n(at.x + line.labelSize.w / 2))\" y=\"\(n(at.y + line.labelSize.h / 2))\" font-size=\"\(n(DiagramLayout.edgeLabelSize))\" font-weight=\"500\" letter-spacing=\"0.4\" fill=\"\(C.soft)\" text-anchor=\"middle\" dominant-baseline=\"central\">\(esc(line.label.uppercased()))</text>\n"
        }
        for b in layout.boxes {
            let attrs = "fill=\"\(fill(b))\" stroke=\"\(stroke(b))\" stroke-width=\"\(b.focal ? 2 : 1.25)\""
            switch b.shape {
            case .decision:
                out += "<path d=\"M\(n(b.midX)) \(n(b.y)) L\(n(b.maxX)) \(n(b.y + b.h / 2)) L\(n(b.midX)) \(n(b.maxY)) L\(n(b.x)) \(n(b.y + b.h / 2)) Z\" \(attrs)/>\n"
            case .start, .end:
                out += "<rect x=\"\(n(b.x))\" y=\"\(n(b.y))\" width=\"\(n(b.w))\" height=\"\(n(b.h))\" rx=\"\(n(min(20, b.h / 2)))\" \(attrs)/>\n"
            default:
                out += "<rect x=\"\(n(b.x))\" y=\"\(n(b.y))\" width=\"\(n(b.w))\" height=\"\(n(b.h))\" rx=\"6\" \(attrs)/>\n"
            }
            if b.shape == .data {
                out += "<line x1=\"\(n(b.x + 6))\" y1=\"\(n(b.y + 6))\" x2=\"\(n(b.maxX - 6))\" y2=\"\(n(b.y + 6))\" stroke=\"\(C.rule)\"/>\n"
            }
            for t in texts(b) {
                out += "<text x=\"\(n(b.midX))\" y=\"\(n(t.y))\" font-size=\"\(n(t.size))\" font-weight=\"\(t.weight)\" fill=\"\(t.color)\" text-anchor=\"middle\" dominant-baseline=\"central\">\(esc(t.text))</text>\n"
            }
        }
        out += "</g>\n</svg>\n"
        return Data(out.utf8)
    }

    /// 框裡的字：一行一個，上下置中（跟 DiagramView 一樣）
    private static func texts(_ b: DiagramLayout.Box) -> [(text: String, y: Double, size: Double, weight: Int, color: String)] {
        var rows: [(String, Double, Double, Int, String)] = []
        if let number = b.number { rows.append((number, DiagramLayout.detailLine, 10, 600, b.focal ? C.accent : C.soft)) }
        for l in b.label { rows.append((l, DiagramLayout.labelLine, DiagramLayout.labelSize, 600, C.ink)) }
        for l in b.detail { rows.append((l, DiagramLayout.detailLine, DiagramLayout.detailSize, 400, C.soft)) }
        var y = b.y + b.h / 2 - rows.reduce(0) { $0 + $1.1 } / 2
        return rows.map { row in
            defer { y += row.1 }
            return (row.0, y + row.1 / 2, row.2, row.3, row.4)
        }
    }

    /// 直角折線，轉角圓角 8；最後一段停在箭頭的底
    private static func path(_ pts: [DiagramLayout.Point]) -> String {
        guard pts.count >= 2 else { return "" }
        var p = pts
        let last = p.count - 1
        let dx = p[last].x - p[last - 1].x, dy = p[last].y - p[last - 1].y
        let length = max(hypot(dx, dy), 0.001)
        p[last] = DiagramLayout.Point(x: p[last].x - dx / length * 6, y: p[last].y - dy / length * 6)
        var d = "M\(n(p[0].x)) \(n(p[0].y))"
        for i in 1..<p.count {
            if i < p.count - 1 {
                let a = p[i - 1], b = p[i], c = p[i + 1]
                let la = hypot(b.x - a.x, b.y - a.y), lc = hypot(c.x - b.x, c.y - b.y)
                let r = min(8, la / 2, lc / 2)
                let s = DiagramLayout.Point(x: b.x - (b.x - a.x) / max(la, 0.001) * r, y: b.y - (b.y - a.y) / max(la, 0.001) * r)
                let e = DiagramLayout.Point(x: b.x + (c.x - b.x) / max(lc, 0.001) * r, y: b.y + (c.y - b.y) / max(lc, 0.001) * r)
                d += " L\(n(s.x)) \(n(s.y)) Q\(n(b.x)) \(n(b.y)) \(n(e.x)) \(n(e.y))"
            } else {
                d += " L\(n(p[i].x)) \(n(p[i].y))"
            }
        }
        return d
    }

    // MARK: draw.io

    /// draw.io（diagrams.net）可以改的檔：框、菱形、泳道都是 draw.io 的圖形，連線接在框上（拖框線會跟著）。
    /// Visio、Lucidchart 也能匯入 .drawio
    static func drawio(_ diagram: MeetingDiagrams.Diagram) -> Data {
        let layout = clientLayout(diagram)
        var cells: [String] = []
        // 沒裝 IBM Plex Sans 的電腦（draw.io 照字型名字找）退到 Helvetica
        let font = "fontFamily=IBM Plex Sans,Helvetica Neue,Helvetica,Arial,sans-serif;"
        // 泳道：框是道的子項（拖道的時候框跟著走）
        var laneRects: [(id: String, x: Double, y: Double, w: Double, h: Double)] = []
        for (k, lane) in layout.lanes.enumerated() {
            let id = "lane\(k)"
            let r = lane.horizontal ? (lane.x, lane.y, lane.w, lane.h) : (lane.x, layout.laneTop, lane.w, layout.height - layout.laneTop - 8)
            let style = "swimlane;html=1;whiteSpace=wrap;\(lane.horizontal ? "horizontal=0;startSize=\(n(DiagramLayout.laneLabel - 12));" : "startSize=\(n(layout.laneHeaderHeight));")"
                + "fillColor=\(C.laneHeader);swimlaneFillColor=\(k % 2 == 0 ? C.laneFill : C.paper);strokeColor=\(C.rule);"
                + "\(font)fontSize=10;fontStyle=1;fontColor=\(C.soft);align=\(lane.horizontal ? "center" : "left");spacingLeft=8;"
            cells.append("<mxCell id=\"\(id)\" value=\"\(esc(lane.name.uppercased()))\" style=\"\(style)\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"\(n(r.0 + pad))\" y=\"\(n(r.1 + pad))\" width=\"\(n(r.2))\" height=\"\(n(r.3))\" as=\"geometry\"/></mxCell>")
            laneRects.append((id, r.0, r.1, r.2, r.3))
        }
        for b in layout.boxes {
            var style: String
            switch b.shape {
            case .decision: style = "rhombus;"
            case .start, .end: style = "rounded=1;arcSize=50;"
            default: style = "rounded=1;absoluteArcSize=1;arcSize=12;"
            }
            style += "whiteSpace=wrap;html=1;fillColor=\(fill(b));strokeColor=\(stroke(b));strokeWidth=\(b.focal ? 2 : 1.25);"
                + "\(font)fontSize=13;fontColor=\(C.ink);verticalAlign=middle;spacing=8;"
            var value = ""
            if let number = b.number { value += "<div style=\"font-size:10px;font-weight:600;color:\(b.focal ? C.accent : C.soft)\">\(esc(number))</div>" }
            value += "<b>\(esc(b.label.joined(separator: " ")))</b>"
            if !b.detail.isEmpty { value += "<div style=\"font-size:11px;color:\(C.soft);margin-top:2px\">\(esc(b.detail.joined(separator: " ")))</div>" }
            let lane = laneRects.first { b.midX >= $0.x && b.midX <= $0.x + $0.w && b.y + b.h / 2 >= $0.y && b.y + b.h / 2 <= $0.y + $0.h }
            let (parent, x, y) = lane.map { ($0.id, b.x - $0.x, b.y - $0.y) } ?? ("1", b.x + pad, b.y + pad)
            cells.append("<mxCell id=\"n\(b.index)\" value=\"\(esc(value))\" style=\"\(style)\" vertex=\"1\" parent=\"\(parent)\"><mxGeometry x=\"\(n(x))\" y=\"\(n(y))\" width=\"\(n(b.w))\" height=\"\(n(b.h))\" as=\"geometry\"/></mxCell>")
        }
        func at(_ p: DiagramLayout.Point) -> String { "x=\"\(n(p.x + pad))\" y=\"\(n(p.y + pad))\"" }
        // 線的兩端落在哪個框上（菱形的接點在斜邊上，所以看框的範圍）
        func boxAt(_ p: DiagramLayout.Point) -> DiagramLayout.Box? {
            layout.boxes.first { p.x >= $0.x - 1 && p.x <= $0.maxX + 1 && p.y >= $0.y - 1 && p.y <= $0.maxY + 1 }
        }
        for axis in layout.axes {
            cells.append("<mxCell id=\"axis\(cells.count)\" style=\"endArrow=none;html=1;strokeColor=\(C.muted);strokeWidth=1.5;\" edge=\"1\" parent=\"1\"><mxGeometry relative=\"1\" as=\"geometry\"><mxPoint \(at(.init(x: axis.x0, y: axis.y))) as=\"sourcePoint\"/><mxPoint \(at(.init(x: axis.x1, y: axis.y))) as=\"targetPoint\"/></mxGeometry></mxCell>")
        }
        for (k, line) in layout.lines.enumerated() where line.points.count >= 2 {
            let first = line.points[0], last = line.points.last!
            let source = boxAt(first), target = boxAt(last)
            var style = "edgeStyle=orthogonalEdgeStyle;rounded=1;arcSize=16;html=1;strokeColor=\(C.line);strokeWidth=1.5;"
                + (line.arrow ? "endArrow=block;endFill=1;endSize=6;" : "endArrow=none;startArrow=oval;startFill=1;startSize=6;")
                + (line.dashed ? "dashed=1;dashPattern=5 4;" : "")
                + "\(font)fontSize=10;fontColor=\(C.soft);labelBackgroundColor=\(C.paper);"
            if let s = source {
                style += "exitX=\(n((first.x - s.x) / s.w));exitY=\(n((first.y - s.y) / s.h));exitDx=0;exitDy=0;exitPerimeter=0;"
            }
            if let t = target {
                style += "entryX=\(n((last.x - t.x) / t.w));entryY=\(n((last.y - t.y) / t.h));entryDx=0;entryDy=0;entryPerimeter=0;"
            }
            // 字的位置跟畫面上一樣：從起點算的位移（x=-1 是起點）
            var geometry = "<mxGeometry\(line.labelAt == nil ? "" : " x=\"-1\"") relative=\"1\" as=\"geometry\">"
            if let at = line.labelAt {
                geometry += "<mxPoint x=\"\(n(at.x + line.labelSize.w / 2 - first.x))\" y=\"\(n(at.y + line.labelSize.h / 2 - first.y))\" as=\"offset\"/>"
            }
            if source == nil { geometry += "<mxPoint \(at(first)) as=\"sourcePoint\"/>" }
            if target == nil { geometry += "<mxPoint \(at(last)) as=\"targetPoint\"/>" }
            if line.points.count > 2 {
                geometry += "<Array as=\"points\">" + line.points.dropFirst().dropLast().map { "<mxPoint \(at($0))/>" }.joined() + "</Array>"
            }
            geometry += "</mxGeometry>"
            let ends = (source.map { " source=\"n\($0.index)\"" } ?? "") + (target.map { " target=\"n\($0.index)\"" } ?? "")
            cells.append("<mxCell id=\"e\(k)\" value=\"\(esc(line.label.uppercased()))\" style=\"\(style)\" edge=\"1\" parent=\"1\"\(ends)>\(geometry)</mxCell>")
        }
        let w = layout.width + 2 * pad, h = layout.height + 2 * pad
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mxfile host="KelNote" type="device">
        <diagram id="kelnote" name="\(esc(diagram.title))">
        <mxGraphModel dx="\(n(w))" dy="\(n(h))" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="\(n(w))" pageHeight="\(n(h))" background="#FFFFFF" math="0" shadow="0">
        <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        \(cells.joined(separator: "\n"))
        </root>
        </mxGraphModel>
        </diagram>
        </mxfile>

        """
        return Data(xml.utf8)
    }
}
