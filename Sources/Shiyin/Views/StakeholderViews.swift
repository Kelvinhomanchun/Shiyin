import SwiftUI

/// 人物頁的「利害關係人分析」（fork）：個性、影響力、關心的議題、話中的意思。出處點了打開那場會議、從那裡播放
struct StakeholderSection: View {
    @Environment(AppModel.self) private var model
    let person: PersonOverview

    var body: some View {
        let record = model.stakeholderPersonId == person.id ? model.stakeholder : nil
        let analyzing = model.isAnalyzingStakeholder(person.id)
        let isMe = person.isMe || model.stakeholderMe.contains(person.id)
        NotesSection(title: String(localized: "利害關係人分析")) {
            if !isMe { HStack(spacing: 10) {
                if analyzing { ProgressView().controlSize(.small) }
                Button(record == nil ? String(localized: "分析") : String(localized: "重新分析"), systemImage: "sparkles") {
                    model.analyzeStakeholder(person.id)
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(analyzing || model.askUnavailableReason != nil)
                .help("用 \(AppSettings.provider.shortLabel) 從他出現過的每一場會議重新分析。每場會議整理完也會自動更新")
            } }
        } content: {
            if isMe {
                Text("這是你自己，不做分析。").foregroundStyle(.secondary)
            } else if let profile = record?.decoded {
                StakeholderProfileView(profile: profile, record: record!)
            } else if analyzing {
                Text("正在分析他在會議裡說的話…").foregroundStyle(.secondary)
            } else {
                Text("還沒有分析。按「分析」，拾音會把他在每場會議說的話交給整理工具，整理出他的個性、影響力、關心的議題，以及話背後可能的意思；之後每場有他的會議整理完都會自動更新。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: person.id) { model.loadStakeholder(person.id) }
    }
}

struct StakeholderProfileView: View {
    @Environment(AppModel.self) private var model
    let profile: StakeholderProfile
    let record: StakeholderRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !profile.summary.isEmpty {
                Text(profile.summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            // 角色、影響力、參與度
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                if !profile.role.isEmpty { row(String(localized: "角色"), Text(profile.role)) }
                row(String(localized: "影響力"), HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LevelBadge(level: profile.power)
                    Text(profile.powerReason).foregroundStyle(.secondary)
                })
                row(String(localized: "參與度"), LevelBadge(level: profile.interest))
            }
            group(String(localized: "個性與溝通風格"), profile.personality)
            group(String(localized: "在意的事、動機"), profile.motivations)
            if !profile.topics.isEmpty {
                subheading(String(localized: "關心的議題"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(profile.topics.enumerated()), id: \.offset) { _, topic in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                LevelBadge(level: topic.interest)
                                Text(topic.topic).fontWeight(.medium)
                                Text(topic.stance).foregroundStyle(.secondary)
                            }
                            evidence(topic.evidence)
                        }
                    }
                }
            }
            if !profile.readings.isEmpty {
                subheading(String(localized: "話中的意思"))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(profile.readings.enumerated()), id: \.offset) { _, reading in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("「\(reading.quote)」").italic().textSelection(.enabled)
                                citation(reading.meetingId, reading.time)
                            }
                            Text("→ " + reading.meaning).foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            bullets(String(localized: "互動建議"), profile.advice)
            bullets(String(localized: "還看不出來的地方"), profile.openQuestions)
            Text(footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        let count = record.analyzedMeetings.count
        let date = String(record.updatedAt.prefix(10))
        return String(localized: "根據 \(count) 場會議，\(date) 更新。這是整理工具從他說的話推測的，只供參考。")
    }

    private func row(_ label: String, _ value: some View) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            value.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func subheading(_ text: String) -> some View {
        Text(text).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func group(_ title: String, _ points: [StakeholderProfile.Point]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                subheading(title)
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• " + point.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        evidence(point.evidence)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bullets(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                subheading(title)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("• " + item).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func evidence(_ list: [StakeholderProfile.Evidence]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(list.prefix(3).enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        citation(e.meetingId, e.time)
                        Text("「\(e.quote)」").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .padding(.leading, 12)
        }
    }

    private func citation(_ meetingId: Int64, _ time: String) -> some View {
        // 同一個人的會議常常同名（定期會議）：用日期分得出是哪一場，標題放在滑過的說明
        let meeting = model.meetings.first { $0.id == meetingId }?.meeting
        return Button {
            model.openFromPersonPage(meetingId, seconds: TimeFormat.seconds(time))
        } label: {
            Text("\(meeting?.meetingDate ?? String(localized: "會議")) \(time)")
                .font(.callout).monospacedDigit().foregroundStyle(Color.celadon).lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
        .help((meeting?.displayTitle ?? "") + "\n" + String(localized: "打開這場會議，從 \(time) 開始"))
    }
}

/// 高、中、低
struct LevelBadge: View {
    let level: String

    var body: some View {
        let (label, color): (String, Color) = switch level {
        case "high": (String(localized: "高"), .red)
        case "medium": (String(localized: "中"), .orange)
        default: (String(localized: "低"), .secondary)
        }
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}
