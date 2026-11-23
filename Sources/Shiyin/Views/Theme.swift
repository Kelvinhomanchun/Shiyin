import AppKit
import SwiftUI

extension EnvironmentValues {
    /// DEBUG 截圖（ImageRenderer）時為 true：不包 ScrollView，內容才畫得出來（design §13）
    @Entry var snapshotMode = false
    /// 正在看的會議的語言：決定會議內容的字形和標題字型（design §18.6）
    @Entry var meetingLanguage: MeetingLanguage = .zh
    /// 會議內容的文字大小倍率（design §38.5、R59）：`contentFont`、`contentTitleFont` 和內容的欄寬乘上它
    @Entry var textScale: CGFloat = 1
}

/// 會議內容的文字大小（design §38.5、R59、D131）：設定存 −1～5，0 是 100%
enum TextSize {
    static let levels = -1...5
    static let scales: [CGFloat] = [0.85, 1, 1.15, 1.3, 1.5, 1.75, 2]

    static var level: Int { min(max(UserDefaults.standard.integer(forKey: AppSettings.textSizeKey), levels.lowerBound), levels.upperBound) }

    static func scale(_ level: Int) -> CGFloat {
        scales[min(max(level, levels.lowerBound), levels.upperBound) - levels.lowerBound]
    }

    static func label(_ level: Int) -> String {
        level == 0 ? String(localized: "100%（標準）") : "\(Int((scale(level) * 100).rounded()))%"
    }

    /// 放大（+1）、縮小（−1）、實際大小（nil）；到頭就不動
    static func change(_ step: Int?) {
        let next = step.map { min(max(level + $0, levels.lowerBound), levels.upperBound) } ?? 0
        UserDefaults.standard.set(next, forKey: AppSettings.textSizeKey)
    }
}

/// 視覺 token（design §9.3）
extension Color {
    /// 主題色：主要動作、連結、目前播放的段落。KelNote 用 IBM Blue 60（#0f62fe），深色模式用 Blue 40（#78a9ff），
    /// 深底上 Blue 60 太暗看不清楚。名字沿用 celadon（原本的青瓷綠），全 app 都用這個
    static let celadon = Color(nsColor: .dynamic(light: 0x0F62FE, dark: 0x78A9FF))
    /// 警示（低信心、待確認、進行中）：IBM Orange 60／40（淺色在白底 5.0:1，深色 6.8:1）。
    /// IBM 的黃在白底只有 3.3:1，文字讀不清楚，改用橘（同 Carbon 的 warning 用法）
    static let signal = Color(nsColor: .dynamic(light: 0xBA4E00, dark: 0xFF832B))

    // KelNote 的配色（IBM Design Language，https://www.ibm.com/design/language/color/）：
    // 以 Blue 60 為主色，其他顏色只在有意義時用；淺色模式用 60、深色模式用 40（兩邊對背景都 ≥ 4.5:1）
    /// 正面（支持、完成）：Green 60／40
    static let positive = Color(nsColor: .dynamic(light: 0x198038, dark: 0x42BE65))
    /// 注意（存疑、中）：Orange 60／40，同 signal
    static let caution = signal
    /// 負面（反對、高風險、錯誤）：Red 60／40
    static let negative = Color(nsColor: .dynamic(light: 0xDA1E28, dark: 0xFF8389))
    /// 次要的結構色（讓他滿意的象限等）：Purple 60／40
    static let accent2 = Color(nsColor: .dynamic(light: 0x8A3FFC, dark: 0xBE95FF))
    /// 側欄的底色（使用者要淺藍）：IBM Blue 10 #EDF5FF（深色 Blue 100 #001141）。
    /// 選到的列 Blue 20 #D0E2FF（深色 Blue 90 #001D6C）、滑過 Blue 20 的一半，同 Carbon 的 selected／hover 用法。
    /// 整個側欄用 Blue 20 太重，灰字對比也會掉到 4.5:1 以下，所以 Blue 20 只給選到的列
    static let sidebarSurface = Color(nsColor: .dynamic(light: 0xEDF5FF, dark: 0x001141))
    static let sidebarSelected = Color(nsColor: .dynamic(light: 0xD0E2FF, dark: 0x001D6C))
    /// 搜尋找到的字：Yellow 20／Yellow 30 的底色（IBM 的黃只當底色用，上面的字照舊是一般文字色）
    static let highlight = Color(nsColor: .dynamic(light: 0xFDDC69, dark: 0x8E6A00))
}

extension Color {
    /// 說話者的顏色（8 色循環），也是頭像的顏色（design §58.1）。KelNote 用 IBM 的色系，淺色 60、深色 40
    /// （對背景都 ≥ 4.5:1）：Cyan、Purple、Teal、Magenta、Green、Blue 80/30、Red、Gray。
    /// 主色 Blue 60 是連結的顏色、橘是警示，所以都不放進來；紅放後面（人少的會議不會用到，不會看起來像錯誤）
    static func speaker(_ idx: Int) -> Color {
        let palette: [(UInt32, UInt32)] = [
            (0x0072C3, 0x33B1FF), (0x8A3FFC, 0xBE95FF), (0x007D79, 0x08BDBA), (0xD02670, 0xFF7EB6),
            (0x198038, 0x42BE65), (0x002D9C, 0xA6C8FF), (0xA2191F, 0xFF8389), (0x525252, 0xC6C6C6),
        ]
        let pair = palette[(max(idx, 1) - 1) % palette.count]
        return Color(nsColor: .dynamic(light: pair.0, dark: pair.1))
    }
}

extension NSColor {
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

extension Font {
    /// 會議標題、會議紀錄段落標題：宋體，讓紀錄讀起來像一份文件。簡體介面用宋體-簡（design §48.2）
    static func songti(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(MeetingLanguage.simplifiedInterface ? "Songti SC" : "Songti TC", size: size).weight(weight)  // l10n-skip
    }
}

/// 會議內容的文字（逐字稿、會議紀錄的條目、筆記）：字形跟著會議語言，日文會議用日文字形（design §18.6）。
/// 只套在內容上，介面的說明文字、按鈕維持繁中字形
private struct MeetingText: ViewModifier {
    @Environment(\.meetingLanguage) private var language

    func body(content: Content) -> some View {
        content.typesettingLanguage(Locale.Language(identifier: language.contentTypesetting))
    }
}

/// 會議內容的標題（會議標題、段落、議題）：宋體-繁；日文會議改用ヒラギノ明朝，宋體的漢字是中文寫法（design §18.6）。
/// 字級跟著文字大小（design §38.5）
private struct ContentTitleFont: ViewModifier {
    @Environment(\.meetingLanguage) private var language
    @Environment(\.textScale) private var scale
    let size: CGFloat

    func body(content: Content) -> some View {
        let size = size * scale
        return content.font(.custom(language.contentTitleFont, size: size).weight(.semibold))   // 語言檔（design §41.5），簡體跟著「中文的字」（§48.2）
            .meetingText()
    }
}

/// 會議內容的字級（design §38.5）：macOS 的字級乘上文字大小的倍率。
/// macOS 的 SwiftUI 不理 `dynamicTypeSize`，所以自己算（D131）
private struct ContentFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: Font.TextStyle
    let weight: Font.Weight?
    let monospacedDigit: Bool

    func body(content: Content) -> some View {
        var font = Font.system(size: Self.size(style) * scale, weight: weight ?? (style == .headline ? .bold : .regular))
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }

    /// macOS 的字級（NSFont.preferredFont(forTextStyle:)，2026-10-30 在 macOS 26 量的）
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline, .body: return 13
        case .callout: return 12
        case .subheadline: return 11
        default: return 10   // footnote、caption、caption2
        }
    }
}

/// 依設定把文字大小的倍率放進 environment（會議頁、問所有會議）
private struct TextScaleFromSettings: ViewModifier {
    @AppStorage(AppSettings.textSizeKey) private var level = 0

    func body(content: Content) -> some View {
        content.environment(\.textScale, TextSize.scale(level))
    }
}

extension View {
    func meetingText() -> some View { modifier(MeetingText()) }
    func contentTitleFont(_ size: CGFloat) -> some View { modifier(ContentTitleFont(size: size)) }
    func contentFont(_ style: Font.TextStyle = .body, weight: Font.Weight? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ContentFont(style: style, weight: weight, monospacedDigit: monospacedDigit))
    }
    func contentTextScale() -> some View { modifier(TextScaleFromSettings()) }
}

/// 可以點的時間點：跳到錄音的那個位置播放（R4.2、R5.2）
struct TimeButton: View {
    @Environment(AppModel.self) private var model
    let time: String
    /// 要跳到的秒數；沒給就照顯示的時間。逐字稿的段落給真正的開始時間（24.4 秒的段落顯示 00:24，跳到 24.0 高亮會落在上一段）
    var seek: Double? = nil
    /// 會議紀錄裡的時間點小一號、淡一點，滑過才變成連結的顏色（UX 檢查 C3：原本跟內文搶眼）。
    /// 逐字稿每段開頭的時間點照舊（那裡是欄位，不是夾在文字後面）
    var quiet = false
    @State private var hovering = false

    var body: some View {
        // 沒有錄音的會議（例如匯入逐字稿）點了也沒辦法播，顯示成一般文字
        if let seconds = seek ?? TimeFormat.seconds(time), model.player.isLoaded {
            Button(time) { model.player.seek(to: seconds) }
                .buttonStyle(.plain)
                .contentFont(quiet ? .caption : .callout, monospacedDigit: true)   // 跟著文字大小（design §38.5）
                .foregroundStyle(quiet && !hovering ? Color.celadon.opacity(0.65) : Color.celadon)
                .underline(quiet && hovering)
                .onHover { hovering = $0 }
                .help("從 \(time) 開始播放")
        } else if !time.isEmpty {
            Text(time).contentFont(quiet ? .caption : .callout, monospacedDigit: true).foregroundStyle(.tertiary)
        }
    }
}

/// 錄音音量表：模仿 VU 表的分段 LED，滿格的地方是琥珀色（design §9.3）
struct VUMeter: View {
    var level: Float
    var segments = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(i))
                    .frame(width: 4, height: 12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int(level * 100))%")
    }

    private func color(_ i: Int) -> Color {
        let lit = Float(i) < level * Float(segments)
        guard lit else { return Color.secondary.opacity(0.18) }
        return i >= segments - 3 ? .signal : .celadon
    }
}

/// 跟 VUMeter 長得一樣的音量條，但用 AppKit 的圖層畫、自己每 0.08 秒讀一次音量（design §25）：
/// SwiftUI 的 view 每變一次，整個視窗都要重新排版、重算最小尺寸，錄音時音量一直在變，CPU 會多用三成
struct LevelMeter: NSViewRepresentable {
    var segments = 14
    let level: @MainActor () -> Float

    func makeNSView(context: Context) -> LevelMeterView { LevelMeterView(segments: segments, level: level) }

    func updateNSView(_ view: LevelMeterView, context: Context) { view.level = level }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LevelMeterView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

final class LevelMeterView: NSView {
    var level: @MainActor () -> Float
    private let segments: Int
    private var bars: [CALayer] = []
    private var lit = -1
    private var timer: Timer?

    init(segments: Int, level: @escaping @MainActor () -> Float) {
        self.segments = segments
        self.level = level
        super.init(frame: NSRect(origin: .zero, size: CGSize(width: segments * 6 - 2, height: 12)))
        wantsLayer = true
        for i in 0..<segments {
            let bar = CALayer()
            bar.frame = CGRect(x: i * 6, y: 0, width: 4, height: 12)
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel(String(localized: "音量"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: segments * 6 - 2, height: 12) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        lit = -1
        refresh()
    }

    /// 亮的格數變了才改顏色（跟 VUMeter 同樣的規則：最後三格是琥珀色）
    private func refresh() {
        let value = level()
        let count = (0..<segments).filter { Float($0) < value * Float(segments) }.count
        guard count != lit else { return }
        lit = count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let off = NSColor.secondaryLabelColor.withAlphaComponent(0.18).cgColor
            // VU 表：Blue 60／40，最後三格是警示的橘
            let green = NSColor.dynamic(light: 0x0F62FE, dark: 0x78A9FF).cgColor
            let amber = NSColor.dynamic(light: 0xBA4E00, dark: 0xFF832B).cgColor
            for (i, bar) in bars.enumerated() {
                bar.backgroundColor = i < count ? (i >= segments - 3 ? amber : green) : off
            }
        }
        CATransaction.commit()
        setAccessibilityValue("\(Int(value * 100))%")
    }
}

/// 錄音經過時間，每秒更新
struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(TimeFormat.string(context.date.timeIntervalSince(since)))
                .monospacedDigit()
        }
    }
}

/// 一排標籤放不下就換行（出處的小標籤用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
