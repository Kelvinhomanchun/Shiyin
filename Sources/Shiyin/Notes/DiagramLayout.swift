import Foundation

/// 圖的排版（fork）：整理工具只給結構，這裡算座標。規則照 diagram-design：連線只有直角（轉角圓角 8）、
/// 同一邊的連線各有自己的接點、連線不穿過不是兩端的框、連線上的字不壓在線上。
/// 流程圖、資料流向由上往下分層；泳道是直的欄（一欄一個角色）；步驟、時間軸由左到右，一列最多 4 個
enum DiagramLayout {
    struct Point: Equatable { var x, y: Double }

    struct Box: Equatable {
        var index: Int
        var x, y, w, h: Double
        var label: [String]
        var detail: [String]
        var time: String
        var shape: MeetingDiagrams.Shape
        var focal: Bool
        /// 步驟的 ID（1、2a、2b…），印在框的最上面；沒有時 nil
        var number: String?
        var midX: Double { x + w / 2 }
        var maxX: Double { x + w }
        var maxY: Double { y + h }
    }

    struct Line: Equatable {
        var points: [Point]
        var dashed: Bool
        var arrow: Bool
        var label: String
        /// 字的位置：左上角
        var labelAt: Point?
        var labelSize: (w: Double, h: Double) = (0, 0)
        static func == (a: Line, b: Line) -> Bool { a.points == b.points && a.label == b.label && a.dashed == b.dashed }
    }

    struct Lane: Equatable {
        var name: String
        var x, w: Double
        /// 橫的泳道（由左往右的流程）：一條道是一列，y、h 是這一列；道名寫在左邊
        var y: Double = 0, h: Double = 0
        var horizontal: Bool = false
    }

    struct Layout: Equatable {
        var width, height: Double
        var boxes: [Box]
        var lines: [Line]
        var lanes: [Lane]
        /// 泳道的範圍（標題列在上面）
        var laneTop: Double = 0
        var laneHeaderHeight: Double = 0
        /// 時間軸的線（每一列一條）
        var axes: [(y: Double, x0: Double, x1: Double)] = []
        static func == (a: Layout, b: Layout) -> Bool { a.boxes == b.boxes && a.lines == b.lines && a.lanes == b.lanes && a.width == b.width }
    }

    // MARK: 尺寸

    static let labelSize = 13.0, labelLine = 18.0
    static let detailSize = 11.0, detailLine = 15.0
    static let edgeLabelSize = 10.0
    static let padH = 12.0, padV = 10.0
    static let boxWidth = 176.0, decisionWidth = 204.0
    static let rankGap = 56.0, labeledRankGap = 72.0, colGap = 40.0
    static let laneHeader = 34.0, lanePad = 20.0
    static let margin = 16.0
    static let perRow = 4

    private static func lines(_ text: String, width: Double, size: Double) -> [String] {
        text.isEmpty ? [] : MindMap.wrap(text, maxWidth: width * 0.92, size: size)
    }

    /// 框的大小：菱形裡的字要窄一點、上下多留空間
    private static func measure(_ n: MeetingDiagrams.Node, index: Int, number: String?) -> Box {
        let decision = n.shape == .decision
        let w = decision ? decisionWidth : boxWidth
        let inner = decision ? w - 88 : w - 2 * padH
        let label = lines(n.label, width: inner, size: labelSize)
        var detailText = n.detail
        if !n.time.isEmpty { detailText = detailText.isEmpty ? n.time : n.time + " · " + detailText }
        let detail = lines(detailText, width: inner, size: detailSize)
        var h = Double(label.count) * labelLine + Double(detail.count) * detailLine + 2 * padV
        if number != nil { h += detailLine }
        if decision { h = max(76, h + 34) }
        if n.shape == .start || n.shape == .end { h = max(40, h) }
        return Box(index: index, x: 0, y: 0, w: w, h: (h / 4).rounded(.up) * 4, label: label, detail: detail, time: n.time,
                   shape: n.shape, focal: n.focal, number: number)
    }

    static func layout(_ d: MeetingDiagrams.Diagram) -> Layout {
        switch d.kind {
        case .steps, .timeline: return row(d)
        case .swimlane: return d.across ? across(d, lanes: true) : layered(d, lanes: true)
        case .flowchart, .dataFlow: return d.across ? across(d, lanes: false) : layered(d, lanes: false)
        }
    }

    // MARK: 步驟、時間軸

    private static func row(_ d: MeetingDiagrams.Diagram) -> Layout {
        let timeline = d.kind == .timeline
        // 步驟沒給 ID 時照順序編 1、2、3；時間軸不編
        var boxes = d.nodes.enumerated().map { i, n in measure(n, index: i, number: n.ref.isEmpty ? (timeline ? nil : "\(i + 1)") : n.ref) }
        var lines: [Line] = []
        var axes: [(y: Double, x0: Double, x1: Double)] = []
        var y = margin
        let axisSpace = timeline ? 28.0 : 0
        for start in stride(from: 0, to: boxes.count, by: perRow) {
            let range = start..<min(start + perRow, boxes.count)
            let h = range.map { boxes[$0].h }.max() ?? 0
            let top = y + axisSpace
            for (k, i) in range.enumerated() {
                boxes[i].x = margin + Double(k) * (boxWidth + colGap)
                boxes[i].y = top
                boxes[i].h = h
            }
            if timeline {
                let axisY = y + 10
                axes.append((axisY, margin, boxes[range.last!].maxX))
                for i in range {   // 每個事件一條短線接到框
                    lines.append(Line(points: [Point(x: boxes[i].midX, y: axisY), Point(x: boxes[i].midX, y: top)], dashed: false, arrow: false, label: ""))
                }
            } else {
                for i in range.dropLast() {
                    let a = boxes[i], b = boxes[i + 1], cy = top + h / 2
                    lines.append(Line(points: [Point(x: a.maxX, y: cy), Point(x: b.x, y: cy)], dashed: false, arrow: true, label: ""))
                }
            }
            y = top + h + (timeline ? 24 : 32)
        }
        return finish(boxes: boxes, lines: lines, lanes: [], axes: axes)
    }

    // MARK: 分層（流程圖、資料流向、泳道）

    private static func layered(_ d: MeetingDiagrams.Diagram, lanes useLanes: Bool) -> Layout {
        let count = d.nodes.count
        let index = Dictionary(d.nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let edges = d.edges.compactMap { e -> (Int, Int, MeetingDiagrams.Edge)? in
            guard let a = index[e.from], let b = index[e.to] else { return nil }
            return (a, b, e)
        }
        // 找出往回的連線（DFS 照節點順序），其餘是 DAG
        var state = Array(repeating: 0, count: count)   // 0 沒看過、1 走到一半、2 看完
        var back = Set<Int>()
        let out = (0..<count).map { a in edges.enumerated().filter { $0.element.0 == a }.map { ($0.offset, $0.element.1) } }
        func visit(_ a: Int) {
            state[a] = 1
            for (e, b) in out[a] {
                if state[b] == 1 { back.insert(e) } else if state[b] == 0 { visit(b) }
            }
            state[a] = 2
        }
        for a in 0..<count where state[a] == 0 { visit(a) }
        let forward = edges.enumerated().filter { !back.contains($0.offset) }.map { ($0.element.0, $0.element.1) }

        // 層：最長路徑
        var rank = Array(repeating: 0, count: count)
        func relax() {
            for _ in 0..<count {
                var changed = false
                for (a, b) in forward where rank[b] < rank[a] + 1 { rank[b] = rank[a] + 1; changed = true }
                if !changed { break }
            }
        }
        relax()
        // 泳道：道名的順序照第一次出現；同一道同一層只能有一個框，後面的往下推
        var laneNames: [String] = []
        if useLanes {
            for n in d.nodes where !laneNames.contains(n.lane) { laneNames.append(n.lane) }
            for _ in 0..<count {
                var moved = false
                for lane in laneNames {
                    let members = (0..<count).filter { d.nodes[$0].lane == lane }.sorted { (rank[$0], $0) < (rank[$1], $1) }
                    for (a, b) in zip(members, members.dropFirst()) where rank[b] <= rank[a] { rank[b] = rank[a] + 1; moved = true }
                }
                relax()
                if !moved { break }
            }
        }
        var boxes = d.nodes.enumerated().map { i, n in measure(n, index: i, number: n.ref.isEmpty ? nil : n.ref) }
        let ranks = (rank.max() ?? 0) + 1
        var order: [[Int]] = (0..<ranks).map { r in (0..<count).filter { rank[$0] == r } }
        let gap = d.edges.contains { !$0.label.isEmpty } ? labeledRankGap : rankGap

        // 每一層的上緣
        var rankTop: [Double] = []
        var rankBottom: [Double] = []
        var y = margin + (useLanes ? laneHeader + 12 : 0)
        for r in 0..<ranks {
            let h = order[r].map { boxes[$0].h }.max() ?? 40
            rankTop.append(y)
            rankBottom.append(y + h)
            for i in order[r] { boxes[i].y = y + (h - boxes[i].h) / 2 }
            y += h + gap
        }

        var lanes: [Lane] = []
        if useLanes {
            let laneWidth = max(boxWidth, decisionWidth * (d.nodes.contains { $0.shape == .decision } ? 1 : 0)) + 2 * lanePad
            for (k, name) in laneNames.enumerated() {
                let x = margin + Double(k) * laneWidth
                lanes.append(Lane(name: name, x: x, w: laneWidth))
                for i in 0..<count where d.nodes[i].lane == name { boxes[i].x = x + (laneWidth - boxes[i].w) / 2 }
            }
        } else {
            // 照上一層的位置排（重心），兩輪；每層置中
            func place() {
                let widths = order.map { row in row.reduce(0) { $0 + boxes[$1].w } + colGap * Double(max(row.count - 1, 0)) }
                let total = widths.max() ?? 0
                for (r, row) in order.enumerated() {
                    var x = margin + (total - widths[r]) / 2
                    for i in row { boxes[i].x = x; x += boxes[i].w + colGap }
                }
            }
            place()
            for _ in 0..<2 {
                for r in 1..<max(ranks, 1) {
                    let center: (Int) -> Double = { i in
                        let parents = forward.filter { $0.1 == i }.map { boxes[$0.0].midX }
                        return parents.isEmpty ? boxes[i].midX : parents.reduce(0, +) / Double(parents.count)
                    }
                    order[r].sort { (center($0), $0) < (center($1), $1) }
                }
                place()
            }
        }

        // 接點：每個框的下緣往外、上緣往內，照另一端的 x 排
        var bottomPorts: [Int: [Int]] = [:], topPorts: [Int: [Int]] = [:]
        for (e, (a, b, _)) in edges.enumerated() where !back.contains(e) {
            bottomPorts[a, default: []].append(e)
            topPorts[b, default: []].append(e)
        }
        func portX(_ box: Box, _ list: [Int], _ e: Int, other: (Int) -> Double) -> Double {
            let sorted = list.sorted { (other($0), $0) < (other($1), $1) }
            let k = Double(sorted.firstIndex(of: e) ?? 0)
            let span = box.shape == .decision ? 0 : box.w
            return box.shape == .decision ? box.midX : box.x + span * (k + 1) / Double(sorted.count + 1)
        }
        // 菱形的出口：往左的從左角、往右的從右角、正下方的從下角（最多三個）
        enum Side { case bottom, left, right }
        var decisionSide: [Int: Side] = [:]
        for (a, list) in bottomPorts where boxes[a].shape == .decision && list.count > 1 {
            let sorted = list.sorted { boxes[edges[$0].1].midX < boxes[edges[$1].1].midX }
            for (k, e) in sorted.enumerated() {
                let dx = boxes[edges[e].1].midX - boxes[a].midX
                if sorted.count == 2 { decisionSide[e] = k == 0 ? (dx < -1 ? .left : .bottom) : (dx > 1 ? .right : .bottom) }
                else { decisionSide[e] = k == 0 ? .left : k == sorted.count - 1 ? .right : .bottom }
            }
            // 兩個都落在下角時，第二個改從右角
            let bottoms = sorted.filter { decisionSide[$0] == .bottom }
            if bottoms.count > 1 { for e in bottoms.dropFirst() { decisionSide[e] = .right } }
        }

        let rightEdge = (boxes.map(\.maxX).max() ?? 0)
        var channel = 0
        var gapUse: [Int: Int] = [:]
        func gapY(after r: Int) -> Double {
            let k = gapUse[r, default: 0]
            gapUse[r] = k + 1
            let offsets = [0.0, -10, 10, -20, 20]
            return rankBottom[r] + gap / 2 + offsets[min(k, offsets.count - 1)]
        }
        func clearVertical(x: Double, from y0: Double, to y1: Double, except: Set<Int>) -> Bool {
            !boxes.contains { b in !except.contains(b.index) && x > b.x - 4 && x < b.maxX + 4 && max(y0, y1) > b.y && min(y0, y1) < b.maxY }
        }
        func clearHorizontal(y: Double, from x0: Double, to x1: Double, except: Set<Int>) -> Bool {
            !boxes.contains { b in !except.contains(b.index) && y > b.y - 4 && y < b.maxY + 4 && max(x0, x1) > b.x && min(x0, x1) < b.maxX }
        }

        var slotLines: [Line?] = Array(repeating: nil, count: edges.count)
        // 擋路的框旁邊的直通道：框的左右各留 10，選離目標近、而且不擋到別的框的那邊；有泳道時不能出道
        var besideUse: [(x: Double, y0: Double, y1: Double)] = []
        func beside(from y0: Double, to y1: Double, near x: Double, except: Set<Int>, route: (Double) -> [Point]) -> Double? {
            let blockers = boxes.filter { b in !except.contains(b.index) && max(y0, y1) > b.y && min(y0, y1) < b.maxY && x > b.x - 4 && x < b.maxX + 4 }
            guard !blockers.isEmpty else { return nil }
            let lo = blockers.map(\.x).min()!, hi = blockers.map(\.maxX).max()!
            var options = [hi + 10, lo - 10, hi + 18, lo - 18]
            // 交叉少的那邊先，一樣時離目標近的先
            let drawn = slotLines.compactMap { $0 }
            let cost = Dictionary(uniqueKeysWithValues: options.map { ($0, crossings(route($0), drawn)) })
            options.sort { (cost[$0]!, abs($0 - x)) < (cost[$1]!, abs($1 - x)) }
            for xs in options {
                if useLanes, let lane = lanes.first(where: { x >= $0.x && x <= $0.x + $0.w }), xs < lane.x + 4 || xs > lane.x + lane.w - 4 { continue }
                if !clearVertical(x: xs, from: y0, to: y1, except: except) { continue }
                if besideUse.contains(where: { abs($0.x - xs) < 6 && max($0.y0, y0) < min($0.y1, y1) }) { continue }
                besideUse.append((xs, min(y0, y1), max(y0, y1)))
                return xs
            }
            return nil
        }
        let leftEdge = boxes.map(\.x).min() ?? 0
        var leftChannel = 0
        // 先畫往下的線，往回的線最後畫：看走左邊還是右邊交叉比較少
        let drawOrder = edges.indices.filter { !back.contains($0) } + edges.indices.filter { back.contains($0) }
        for e in drawOrder {
            let (a, b, edge) = edges[e]
            let sa = boxes[a], sb = boxes[b]
            var pts: [Point]
            var labelSide = 1.0   // 1：字在線的右邊；-1：左邊
            if back.contains(e) {
                // 往回：從旁邊出去，走旁邊的通道，從同一邊進來；兩邊都試，挑交叉少的（一樣時走右邊）
                let y0 = sa.y + sa.h / 2 + 6, y1 = sb.y + sb.h / 2 - 6
                let xr = rightEdge + 24 + Double(channel) * 12
                let right = [Point(x: sa.maxX, y: y0), Point(x: xr, y: y0), Point(x: xr, y: y1), Point(x: sb.maxX, y: y1)]
                let xl = leftEdge - 24 - Double(leftChannel) * 12
                let left = [Point(x: sa.x, y: y0), Point(x: xl, y: y0), Point(x: xl, y: y1), Point(x: sb.x, y: y1)]
                let drawn = slotLines.compactMap { $0 }
                if !useLanes, crossings(left, drawn) < crossings(right, drawn) {
                    pts = left; leftChannel += 1; labelSide = -1
                } else {
                    pts = right; channel += 1
                }
            } else {
                let x1 = portX(sb, topPorts[b] ?? [], e) { boxes[edges[$0].0].midX }
                let y1 = sb.y
                let side = decisionSide[e] ?? .bottom
                if side != .bottom {
                    // 菱形的左右角：先橫出去，再往下
                    let dir = side == .left ? -1.0 : 1.0
                    let x0 = side == .left ? sa.x : sa.maxX, y0 = sa.y + sa.h / 2
                    labelSide = dir
                    // 角的正下方就是目標框（框只有這一條進來的線）：橫出一小段就直接往下，不要再拐一下
                    let xs = x0 + dir * 24
                    if (x1 - x0) * dir > 8, clearVertical(x: x1, from: y0, to: y1, except: [a, b]),
                       clearHorizontal(y: y0, from: x0, to: x1, except: [a, b]) {
                        pts = [Point(x: x0, y: y0), Point(x: x1, y: y0), Point(x: x1, y: y1)]
                    } else if (topPorts[b] ?? []).count == 1, xs > sb.x + 16, xs < sb.maxX - 16,
                              clearVertical(x: xs, from: y0, to: y1, except: [a, b]) {
                        pts = [Point(x: x0, y: y0), Point(x: xs, y: y0), Point(x: xs, y: y1)]
                    } else {
                        let xs = x0 + dir * 20, ym = gapY(after: rank[a])
                        pts = [Point(x: x0, y: y0), Point(x: xs, y: y0), Point(x: xs, y: ym), Point(x: x1, y: ym), Point(x: x1, y: y1)]
                    }
                } else {
                    let x0 = portX(sa, bottomPorts[a] ?? [], e) { boxes[edges[$0].1].midX }
                    let y0 = sa.maxY
                    let list = (bottomPorts[a] ?? []).filter { !edges[$0].2.label.isEmpty }
                    if list.count > 1, list.sorted(by: { boxes[edges[$0].1].midX < boxes[edges[$1].1].midX }).first == e { labelSide = -1 }
                    if abs(x0 - x1) < 0.5, clearVertical(x: x0, from: y0, to: y1, except: [a, b]) {
                        pts = [Point(x: x0, y: y0), Point(x: x1, y: y1)]
                    } else {
                        let first = gapY(after: rank[a])
                        let last = rankTop[rank[b]] - gap / 2
                        if clearVertical(x: x1, from: first, to: y1, except: [a, b]) && clearVertical(x: x0, from: y0, to: first, except: [a, b]) {
                            pts = [Point(x: x0, y: y0), Point(x: x0, y: first), Point(x: x1, y: first), Point(x: x1, y: y1)]
                        } else if clearVertical(x: x0, from: y0, to: last, except: [a, b]) {
                            pts = [Point(x: x0, y: y0), Point(x: x0, y: last), Point(x: x1, y: last), Point(x: x1, y: y1)]
                        } else if let xs = beside(from: first, to: last, near: x1, except: [a, b], route: { xs in
                            [Point(x: x0, y: y0), Point(x: x0, y: first), Point(x: xs, y: first), Point(x: xs, y: last),
                             Point(x: x1, y: last), Point(x: x1, y: y1)] }) {
                            // 中間有框擋著：貼著那個框的旁邊往下（不要繞到整張圖的最右邊）
                            pts = [Point(x: x0, y: y0), Point(x: x0, y: first), Point(x: xs, y: first), Point(x: xs, y: last),
                                   Point(x: x1, y: last), Point(x: x1, y: y1)]
                        } else {
                            let xc = rightEdge + 24 + Double(channel) * 12
                            channel += 1
                            pts = [Point(x: x0, y: y0), Point(x: x0, y: first), Point(x: xc, y: first), Point(x: xc, y: last),
                                   Point(x: x1, y: last), Point(x: x1, y: y1)]
                        }
                    }
                }
            }
            var line = Line(points: simplify(pts), dashed: edge.dashed, arrow: true, label: edge.label)
            if !edge.label.isEmpty { placeLabel(&line, side: labelSide) }
            slotLines[e] = line
        }
        // 進同一個框的兩條線交叉時，交換它們在上緣的接點（只換最後那段直的）
        for (_, list) in topPorts where list.count > 1 {
            for i in list.indices { for j in list.indices where j > i {
                guard var p = slotLines[list[i]], var q = slotLines[list[j]], p.points.count >= 3, q.points.count >= 3 else { continue }
                let pn = p.points.count, qn = q.points.count
                guard abs(p.points[pn - 1].x - p.points[pn - 2].x) < 0.01, abs(q.points[qn - 1].x - q.points[qn - 2].x) < 0.01 else { continue }
                let others = slotLines.enumerated().filter { $0.offset != list[i] && $0.offset != list[j] }.compactMap { $0.element }
                let before = crossings(p.points, [q] + others) + crossings(q.points, others)
                let px = p.points[pn - 1].x, qx = q.points[qn - 1].x
                p.points[pn - 1].x = qx; p.points[pn - 2].x = qx
                q.points[qn - 1].x = px; q.points[qn - 2].x = px
                p.points = simplify(p.points); q.points = simplify(q.points)
                let after = crossings(p.points, [q] + others) + crossings(q.points, others)
                if after < before {
                    if !p.label.isEmpty { placeLabel(&p, side: 1) }
                    if !q.label.isEmpty { placeLabel(&q, side: 1) }
                    slotLines[list[i]] = p; slotLines[list[j]] = q
                }
            } }
        }
        let lines = slotLines.compactMap { $0 }
        var layout = finish(boxes: boxes, lines: lines, lanes: lanes, axes: [])
        if useLanes {
            layout.laneTop = margin
            layout.laneHeaderHeight = laneHeader
        }
        return layout
    }

    // MARK: 由左往右（使用者要橫的）

    /// 層變成欄、泳道變成列。連線從框的右緣出去、左緣進來，在兩欄之間的通道轉彎；往回的走最下面
    static let laneLabel = 120.0

    private static func across(_ d: MeetingDiagrams.Diagram, lanes useLanes: Bool) -> Layout {
        let count = d.nodes.count
        let index = Dictionary(d.nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let edges = d.edges.compactMap { e -> (Int, Int, MeetingDiagrams.Edge)? in
            guard let a = index[e.from], let b = index[e.to] else { return nil }
            return (a, b, e)
        }
        var state = Array(repeating: 0, count: count)
        var back = Set<Int>()
        let out = (0..<count).map { a in edges.enumerated().filter { $0.element.0 == a }.map { ($0.offset, $0.element.1) } }
        func visit(_ a: Int) {
            state[a] = 1
            for (e, b) in out[a] { if state[b] == 1 { back.insert(e) } else if state[b] == 0 { visit(b) } }
            state[a] = 2
        }
        for a in 0..<count where state[a] == 0 { visit(a) }
        let forward = edges.enumerated().filter { !back.contains($0.offset) }.map { ($0.element.0, $0.element.1) }
        // 欄：最長路徑。同一欄、同一條道的框疊起來放（平行的分支在同一欄，不要往後推），連線才不會繞
        var rank = Array(repeating: 0, count: count)
        for _ in 0..<count {
            var changed = false
            for (a, b) in forward where rank[b] < rank[a] + 1 { rank[b] = rank[a] + 1; changed = true }
            if !changed { break }
        }
        var laneNames: [String] = []
        if useLanes { for n in d.nodes where !laneNames.contains(n.lane) { laneNames.append(n.lane) } }
        let laneOf: (Int) -> Int = { useLanes ? (laneNames.firstIndex(of: d.nodes[$0].lane) ?? 0) : 0 }
        var boxes = d.nodes.enumerated().map { i, n in measure(n, index: i, number: n.ref.isEmpty ? nil : n.ref) }
        let ranks = (rank.max() ?? 0) + 1
        let gapX = d.edges.contains { !$0.label.isEmpty } ? 96.0 : 72.0, stackGap = 20.0
        let left = margin + (useLanes ? laneLabel : 0)

        // 一格（欄 × 道）裡的框照前一欄的高度排：先排好道的高，再排格子裡的順序
        var cell: [[Int]: [Int]] = [:]
        for i in 0..<count { cell[[rank[i], laneOf(i)], default: []].append(i) }
        var colX: [Double] = [], colW: [Double] = []
        var x = left
        for r in 0..<ranks {
            let w = (0..<count).filter { rank[$0] == r }.map { boxes[$0].w }.max() ?? boxWidth
            colX.append(x); colW.append(w)
            for i in 0..<count where rank[i] == r { boxes[i].x = x + (w - boxes[i].w) / 2 }
            x += w + gapX
        }
        let laneCount = useLanes ? laneNames.count : 1
        // 每條道的高：裡面最高的那一格
        var laneH = Array(repeating: 0.0, count: laneCount)
        for (key, list) in cell {
            let h = list.reduce(0) { $0 + boxes[$1].h } + stackGap * Double(list.count - 1)
            laneH[key[1]] = max(laneH[key[1]], h)
        }
        var laneTop: [Double] = []
        // 往回的線（沒有泳道時）走最上面：先留好位置
        let topRoom = (!useLanes && !back.isEmpty) ? 20.0 + 12 * Double(back.count - 1) : 0
        var y = margin + topRoom
        for k in 0..<laneCount { laneTop.append(y); y += laneH[k] + 2 * lanePad }
        func parentsCenter(_ i: Int) -> Double? {
            let ys = forward.filter { $0.1 == i }.map { boxes[$0.0].y + boxes[$0.0].h / 2 }
            return ys.isEmpty ? nil : ys.reduce(0, +) / Double(ys.count)
        }
        for r in 0..<ranks {
            for k in 0..<laneCount {
                guard var list = cell[[r, k]] else { continue }
                list.sort { (parentsCenter($0) ?? Double($0), $0) < (parentsCenter($1) ?? Double($1), $1) }
                let h = list.reduce(0) { $0 + boxes[$1].h } + stackGap * Double(list.count - 1)
                var yy = laneTop[k] + lanePad + (laneH[k] - h) / 2
                for i in list { boxes[i].y = yy; yy += boxes[i].h + stackGap }
            }
        }
        var lanes: [Lane] = []
        let rightEdge = boxes.map(\.maxX).max() ?? 0
        if useLanes {
            for (k, name) in laneNames.enumerated() {
                lanes.append(Lane(name: name, x: margin, w: rightEdge + lanePad - margin, y: laneTop[k], h: laneH[k] + 2 * lanePad, horizontal: true))
            }
        }
        let bottom = useLanes ? (laneTop.last.map { $0 + laneH[laneCount - 1] + 2 * lanePad } ?? 0) : (boxes.map(\.maxY).max() ?? 0)

        // 接點：右緣出去、左緣進來，照另一端的高度排，同一邊的線各有自己的點
        var outPorts: [Int: [Int]] = [:], inPorts: [Int: [Int]] = [:]
        for (e, (a, b, _)) in edges.enumerated() where !back.contains(e) {
            outPorts[a, default: []].append(e); inPorts[b, default: []].append(e)
        }
        func midY(_ i: Int) -> Double { boxes[i].y + boxes[i].h / 2 }
        // 同一邊有幾條線時各有自己的接點，間隔 8；和框一樣高的那條留在正中間，才不會多一個小彎
        func portY(_ box: Box, _ list: [Int], _ e: Int, other: (Int) -> Double) -> Double {
            let center = box.y + box.h / 2
            if list.count < 2 { return center }
            let sorted = list.sorted { (other($0), $0) < (other($1), $1) }
            let k = sorted.firstIndex(of: e) ?? 0
            let k0 = sorted.indices.min { abs(other(sorted[$0]) - center) < abs(other(sorted[$1]) - center) } ?? 0
            let step = min(8.0, box.h * 0.6 / Double(sorted.count - 1))
            let limit = box.h * (box.shape == .decision ? 0.25 : 0.35)
            return center + max(-limit, min(limit, step * Double(k - k0)))
        }
        // 菱形的接點在斜邊上（離尖角 dy 的地方往內縮）
        func edgeX(_ box: Box, y: Double, right: Bool) -> Double {
            let inset = box.shape == .decision ? (box.w / 2) * min(1, abs(y - (box.y + box.h / 2)) / (box.h / 2)) : 0
            return right ? box.maxX - inset : box.x + inset
        }
        func edgeY(_ box: Box, x: Double, top: Bool) -> Double {
            let inset = box.shape == .decision ? (box.h / 2) * min(1, abs(x - box.midX) / (box.w / 2)) : 0
            return top ? box.y + inset : box.maxY - inset
        }
        func blocked(y: Double, from x0: Double, to x1: Double, except: Set<Int>) -> Bool {
            boxes.contains { b in !except.contains(b.index) && y > b.y - 6 && y < b.maxY + 6 && max(x0, x1) > b.x - 2 && min(x0, x1) < b.maxX + 2 }
        }
        func blockedV(x: Double, from y0: Double, to y1: Double, except: Set<Int>) -> Bool {
            boxes.contains { b in !except.contains(b.index) && x > b.x - 6 && x < b.maxX + 6 && max(y0, y1) > b.y && min(y0, y1) < b.maxY }
        }
        // 兩欄之間的直通道：每條線一條，不疊在一起
        // 同一個通道裡的線排成不交叉的順序：往下走的，起點越上面的越靠右（晚轉彎）；往上走的相反。
        // 先算好每條線在通道裡的位置，畫的時候照用
        var slot: [String: Double] = [:]
        func planChannels() {
            var groups: [Int: [(key: String, y0: Double, y1: Double)]] = [:]
            for (e, (a, b, _)) in edges.enumerated() where !back.contains(e) && rank[b] > rank[a] {
                let y0 = portY(boxes[a], outPorts[a] ?? [], e) { midY(edges[$0].1) }
                let y1 = portY(boxes[b], inPorts[b] ?? [], e) { midY(edges[$0].0) }
                if abs(y0 - y1) < 0.5 { continue }
                for r in Set([rank[a], rank[b] - 1]) { groups[r, default: []].append(("\(e)-\(r)", y0, y1)) }
            }
            for (r, list) in groups {
                let center = colX[r] + colW[r] + gapX / 2
                let downs = list.filter { $0.y1 > $0.y0 }.sorted { $0.y0 < $1.y0 }
                let ups = list.filter { $0.y1 < $0.y0 }.sorted { $0.y0 > $1.y0 }
                // 往下的：起點最上面的最靠右；往上的：起點最下面的最靠右
                let ordered = downs.reversed() + ups.reversed()
                let step = min(14.0, (gapX - 24) / Double(max(ordered.count, 1)))
                let start = center - step * Double(ordered.count - 1) / 2
                for (k, item) in ordered.enumerated() { slot[item.key] = start + step * Double(k) }
            }
        }
        planChannels()
        func channel(after r: Int, edge e: Int) -> Double { slot["\(e)-\(r)"] ?? (colX[r] + colW[r] + gapX / 2) }
        // 橫的通道（跳過幾欄時）：在道與道之間、或道裡框的上下的空白；找不到才走最下面
        var trackUse: [(y: Double, x0: Double, x1: Double)] = []
        // 找離起點或終點最近的那條（不是兩端的中間），直的那段才短，也不會橫過別的線
        func track(near ends: (Double, Double), from x0: Double, to x1: Double, except: Set<Int>) -> Double? {
            let near = { (c: Double) in min(abs(c - ends.0), abs(c - ends.1)) }
            var candidates: [Double] = [ends.0, ends.1]
            for t in laneTop { candidates.append(t + 8); candidates.append(t + lanePad / 2) }
            for b in boxes { candidates.append(b.y - 14); candidates.append(b.maxY + 14) }
            // 一樣近時：離起點近的先，再來下面的先（沒有泳道時往回的線走上面）
            candidates.sort { (near($0), abs($0 - ends.0), -$0) < (near($1), abs($1 - ends.0), -$1) }
            // 沒有泳道時，最下面那個框的下面也可以走
            let floor = useLanes ? bottom : bottom + 20
            for c in candidates where c > margin - 4 && c <= floor {
                if blocked(y: c, from: x0, to: x1, except: except) { continue }
                if trackUse.contains(where: { abs($0.y - c) < 8 && max($0.x0, x0) < min($0.x1, x1) }) { continue }
                trackUse.append((c, min(x0, x1), max(x0, x1)))
                return c
            }
            return nil
        }
        var lines: [Line] = []
        var lowest = bottom + 16
        var highest = (boxes.map(\.y).min() ?? margin) - 20
        for (e, (a, b, edge)) in edges.enumerated() {
            let sa = boxes[a], sb = boxes[b]
            var pts: [Point]
            var labelSide = 1.0
            if back.contains(e) {
                if useLanes {
                    // 往回（有泳道）：從下緣出去，走所有道的下面，從下緣進來
                    let y = lowest; lowest += 12
                    pts = [Point(x: sa.midX + 6, y: edgeY(sa, x: sa.midX + 6, top: false)), Point(x: sa.midX + 6, y: y),
                           Point(x: sb.midX - 6, y: y), Point(x: sb.midX - 6, y: edgeY(sb, x: sb.midX - 6, top: false))]
                } else {
                    // 往回（沒有泳道）：從上緣出去，走最上面，從上緣進來；不會和往下繞的線交叉
                    let y = highest; highest -= 12
                    pts = [Point(x: sa.midX + 6, y: edgeY(sa, x: sa.midX + 6, top: true)), Point(x: sa.midX + 6, y: y),
                           Point(x: sb.midX - 6, y: y), Point(x: sb.midX - 6, y: edgeY(sb, x: sb.midX - 6, top: true))]
                }
            } else {
                let y0 = portY(sa, outPorts[a] ?? [], e) { midY(edges[$0].1) }
                let y1 = portY(sb, inPorts[b] ?? [], e) { midY(edges[$0].0) }
                let x0 = edgeX(sa, y: y0, right: true), x1 = edgeX(sb, y: y1, right: false)
                // 接點在中線下面的，字寫在線的下面，才不會壓到上面那條
                if y0 > sa.y + sa.h / 2 + 0.5 { labelSide = -1 }
                let ex: Set<Int> = [a, b]
                if abs(y0 - y1) < 0.5, !blocked(y: y0, from: x0, to: x1, except: ex) {
                    pts = [Point(x: x0, y: y0), Point(x: x1, y: y1)]
                } else if rank[b] == rank[a] + 1 {
                    // 隔壁欄：在兩欄中間轉彎
                    let xc = channel(after: rank[a], edge: e)
                    pts = [Point(x: x0, y: y0), Point(x: xc, y: y0), Point(x: xc, y: y1), Point(x: x1, y: y1)]
                } else if rank[b] > rank[a] {
                    // 跳過幾欄：先在目標前一欄後面轉彎（沿著出發的高度走得通時），不然在出發欄後面轉到一條空的橫通道
                    let xLate = channel(after: rank[b] - 1, edge: e)
                    if !blocked(y: y0, from: x0, to: xLate, except: ex), !blockedV(x: xLate, from: y0, to: y1, except: ex) {
                        pts = [Point(x: x0, y: y0), Point(x: xLate, y: y0), Point(x: xLate, y: y1), Point(x: x1, y: y1)]
                    } else {
                        let xEarly = channel(after: rank[a], edge: e)
                        if !blocked(y: y1, from: xEarly, to: x1, except: ex), !blockedV(x: xEarly, from: y0, to: y1, except: ex) {
                            pts = [Point(x: x0, y: y0), Point(x: xEarly, y: y0), Point(x: xEarly, y: y1), Point(x: x1, y: y1)]
                        } else if let t = track(near: (y0, y1), from: xEarly, to: xLate, except: ex) {
                            pts = [Point(x: x0, y: y0), Point(x: xEarly, y: y0), Point(x: xEarly, y: t), Point(x: xLate, y: t),
                                   Point(x: xLate, y: y1), Point(x: x1, y: y1)]
                        } else {
                            let t = lowest; lowest += 12
                            pts = [Point(x: x0, y: y0), Point(x: xEarly, y: y0), Point(x: xEarly, y: t), Point(x: xLate, y: t),
                                   Point(x: xLate, y: y1), Point(x: x1, y: y1)]
                        }
                    }
                } else {
                    // 同一欄（疊在一起的框）：從下緣接到上緣
                    let (top, low) = sa.y < sb.y ? (sa, sb) : (sb, sa)
                    let xm = top.midX
                    pts = sa.y < sb.y ? [Point(x: xm, y: top.maxY), Point(x: xm, y: low.y)] : [Point(x: xm, y: low.y), Point(x: xm, y: top.maxY)]
                }
            }
            var line = Line(points: simplify(pts), dashed: edge.dashed, arrow: true, label: edge.label)
            if !edge.label.isEmpty { placeLabel(&line, side: labelSide, below: labelSide < 0) }
            lines.append(line)
        }
        return finish(boxes: boxes, lines: lines, lanes: lanes, axes: [])
    }

    /// 一條直角折線和已經畫好的線交叉幾次（一橫一直真的穿過去，或平行疊在一起）
    private static func crossings(_ pts: [Point], _ lines: [Line]) -> Int {
        func segs(_ p: [Point]) -> [(Point, Point)] { p.count < 2 ? [] : (1..<p.count).map { (p[$0 - 1], p[$0]) } }
        func cross(_ s: (Point, Point), _ t: (Point, Point)) -> Bool {
            let sH = abs(s.0.y - s.1.y) < 0.01, tH = abs(t.0.y - t.1.y) < 0.01
            if sH == tH {
                // 平行又貼得很近、範圍重疊：看起來像同一條線，也算一次
                let (a0, a1, b0, b1, d) = sH ? (s.0.x, s.1.x, t.0.x, t.1.x, abs(s.0.y - t.0.y)) : (s.0.y, s.1.y, t.0.y, t.1.y, abs(s.0.x - t.0.x))
                return d < 6 && min(max(a0, a1), max(b0, b1)) - max(min(a0, a1), min(b0, b1)) > 8
            }
            let (h, v) = sH ? (s, t) : (t, s)
            let y = h.0.y, x = v.0.x
            return x > min(h.0.x, h.1.x) + 0.5 && x < max(h.0.x, h.1.x) - 0.5 && y > min(v.0.y, v.1.y) + 0.5 && y < max(v.0.y, v.1.y) - 0.5
        }
        let mine = segs(pts)
        return lines.reduce(0) { n, l in n + segs(l.points).reduce(0) { m, t in m + mine.filter { cross($0, t) }.count } }
    }

    /// 去掉重複、在同一直線上的點
    private static func simplify(_ pts: [Point]) -> [Point] {
        var out: [Point] = []
        for p in pts {
            if let last = out.last, abs(last.x - p.x) < 0.01 && abs(last.y - p.y) < 0.01 { continue }
            if out.count >= 2 {
                let a = out[out.count - 2], b = out[out.count - 1]
                if (abs(a.x - b.x) < 0.01 && abs(b.x - p.x) < 0.01) || (abs(a.y - b.y) < 0.01 && abs(b.y - p.y) < 0.01) { out.removeLast() }
            }
            out.append(p)
        }
        return out
    }

    /// 字放在第一段：直的段在線旁邊留 6 的空隙；橫的段在線上方留 6
    private static func placeLabel(_ line: inout Line, side: Double, below: Bool = false) {
        guard line.points.count >= 2 else { return }
        let w = MindMap.width(line.label, size: edgeLabelSize) * 1.05 + 8, h = 16.0
        line.labelSize = (w, h)
        let a = line.points[0], b = line.points[1]
        if abs(a.x - b.x) < 0.01 {
            let x = side < 0 ? a.x - 6 - w : a.x + 6
            line.labelAt = Point(x: x, y: min(a.y, b.y) + 4)
        } else {
            let left = min(a.x, b.x), length = abs(a.x - b.x)
            line.labelAt = Point(x: left + max(4, (length - w) / 2), y: below ? a.y + 6 : a.y - 6 - h)
        }
    }

    /// 平移到左上角留邊，算整張的大小
    private static func finish(boxes: [Box], lines: [Line], lanes: [Lane], axes: [(y: Double, x0: Double, x1: Double)]) -> Layout {
        var maxX = (boxes.map(\.maxX).max() ?? 0), maxY = (boxes.map(\.maxY).max() ?? 0)
        var minX = boxes.map(\.x).min() ?? 0
        for l in lines {
            for p in l.points { maxX = max(maxX, p.x); maxY = max(maxY, p.y); minX = min(minX, p.x) }
            if let at = l.labelAt { maxX = max(maxX, at.x + l.labelSize.w); minX = min(minX, at.x) }
        }
        for lane in lanes { maxX = max(maxX, lane.x + lane.w); minX = min(minX, lane.x); if lane.horizontal { maxY = max(maxY, lane.y + lane.h) } }
        let dx = margin - minX
        var boxes = boxes, lines = lines, lanes = lanes
        for i in boxes.indices { boxes[i].x += dx }
        for i in lines.indices {
            for j in lines[i].points.indices { lines[i].points[j].x += dx }
            if lines[i].labelAt != nil { lines[i].labelAt!.x += dx }
        }
        for i in lanes.indices { lanes[i].x += dx }
        let shiftedAxes = axes.map { ($0.y, $0.x0 + dx, $0.x1 + dx) }
        return Layout(width: maxX + dx + margin, height: maxY + margin + (lanes.isEmpty ? 0 : 8), boxes: boxes, lines: lines, lanes: lanes,
                      axes: shiftedAxes)
    }
}
