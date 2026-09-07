import SwiftUI

/// ADR 0010 · 测量记录。全产品第二个二级页——第一个是设备页。做成页面而不是 sheet，是因为
/// 它过了 F1 那道门槛：一份按月累积、会一直长的清单，一屏放不下。
///
/// 返回回「我的」，不回首页。清单里的一行点开是盖在这一页上的 sheet，不是第三级页面。
struct MeasurementsView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    #if DEBUG
    private var kept: [MeasurementRecord] { DebugEdge.on("empty") ? [] : data.measurements }
    #else
    private var kept: [MeasurementRecord] { data.measurements }
    #endif

    /// 按月分组，月内倒序。⚠️ 这里不做筛选也不做统计：清单只是清单。
    private var months: [(key: String, label: String, records: [MeasurementRecord])] {
        let sorted = kept.sorted { $0.at > $1.at }
        var order: [String] = []
        var buckets: [String: [MeasurementRecord]] = [:]
        for record in sorted {
            let key = Self.monthKey.string(from: record.at)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(record)
        }
        return order.map { key in
            let label = buckets[key]?.first.map { Self.monthLabel.string(from: $0.at).uppercased() } ?? key
            return (key: key, label: label, records: buckets[key] ?? [])
        }
    }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("MEASUREMENTS")) {
            // ⚠️ KEPT 是留下的行数，不是尝试次数——失败的测量从没进过这张表。
            Text(L("%d KEPT", kept.count))
                .font(NBFont.dot(500, 12)).tracking(0.04 * 12)
                .foregroundStyle(NB.macroValue)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if kept.isEmpty {
                    emptyState
                } else {
                    ForEach(months, id: \.key) { month in
                        monthHeader(month.label, count: month.records.count)
                        VStack(spacing: 0) {
                            ForEach(month.records) { record in
                                MeasurementRow(record: record) {
                                    router.sheet = .measurement(record.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            // 返回回「我的」——这一页是从那里进来的，不回首页。
            router.back()
        }
    }

    private func monthHeader(_ label: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(NBFont.dot(700, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.lime1)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text2)
        }
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    /// 一次都没测过。这一页仍然可达（模块的入口在没有记录时是灰的，但深链之外还有返回栈），
    /// 所以它得有话说，而且说的是怎么开始，不是「暂无数据」。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("NOTHING KEPT YET"))
                .font(NBFont.dot(700, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
            Text(L("A measurement is you holding the side key — a body scan or a balance check, from the plus menu. Thirty seconds makes the first row."))
                .font(NBFont.ui(300, 13.5)).tracking(0.02 * 13.5)
                .lineSpacing(5)
                .foregroundStyle(NB.text2)
        }
        .padding(.top, 26)
    }

    private static let monthKey: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"; return f
    }()
    /// ⚠️ 不能建一次就留着：语言是可以在「我的」里当场改的，一个记住了旧 locale 的静态
    /// formatter 会让这一页在切换语言后仍然印英文月份。
    private static var monthLabel: DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.shared.swiftLocale
        f.dateFormat = AppLanguage.shared.isEnglish ? "MMMM yyyy" : "yyyy年M月"
        return f
    }
}

/// 模块和清单画的是同一种行。⚠️ 一份实现——两处各写一遍，是这两块早晚说出不同话的方式。
/// `onTap` 为 nil 的行不可点：「我的」那块卡上唯一的热区是底部的 ALL MEASUREMENTS。
struct MeasurementRow: View {
    let record: MeasurementRecord
    var style: Style = .list
    var onTap: (() -> Void)? = nil

    enum Style {
        /// 「我的」那块卡上的一行：一行高，只印日期，没有分隔线也没有箭头。
        case card
        /// 记录页清单上的一行：两行高，印星期、日期和时刻，带分隔线和箭头。
        case list
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            // 实心点是身体扫描，空心点是平衡检查。
            Group {
                if record.isFilledDot {
                    Circle().fill(NB.lime1)
                } else {
                    Circle().stroke(NB.lime1, lineWidth: 1.5)
                }
            }
            .frame(width: 8, height: 8)

            switch style {
            case .card:
                // 卡上一行只有三样：类型、日期、两个数。日期是固定宽的一栏，三行才对得齐。
                Text(record.title)
                    .font(NBFont.ui(500, 12)).tracking(0.06 * 12)
                    .foregroundStyle(NB.text1)
                    .lineLimit(1)
                Text(Self.dayFormatter.string(from: record.at))
                    .font(NBFont.dot(500, 11))
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: 44, alignment: .leading)
            case .list:
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(NBFont.ui(500, 12)).tracking(0.06 * 12)
                        .foregroundStyle(NB.text1)
                    Text(Self.stamp(record.at))
                        .font(NBFont.dot(500, 11))
                        .foregroundStyle(NB.macroValue)
                }
            }
            Spacer(minLength: 8)
            Text(record.summary)
                .font(NBFont.dot(600, 13))
                .foregroundStyle(NB.emberPale)
                .lineLimit(1)
            if onTap != nil { Chevron() }
        }
        .frame(height: style == .list ? 60 : 34)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if style == .list { Hairline() } }
    }

    private static func stamp(_ at: Date) -> String {
        "\(Fmt.weekday(at).uppercased()) \(dayFormatter.string(from: at)) · \(timeFormatter.string(from: at))"
    }
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM·dd"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
