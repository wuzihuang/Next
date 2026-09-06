import SwiftUI

/// ADR 0010 · 一条测量记录的全部字段，盖在清单上。**只读**：没有删除，没有编辑，没有分享，
/// 也没有「去成分详情页」——两个详情页之间没有路。
struct MeasurementSheet: View {
    let id: UUID
    @EnvironmentObject private var data: DataStore

    private var record: MeasurementRecord? { data.measurements.first { $0.id == id } }

    var body: some View {
        Group {
            if let record {
                switch record.detail {
                case .bodyScan(let scan):     bodyScan(scan, at: record.at)
                case .balanceCheck(let check): balanceCheck(check, at: record.at)
                }
            } else {
                // 上一条记录被另一次读取换掉了（换账号、重新拉取）。不猜，也不留空白。
                SheetFrame(title: L("Measurement")) {
                    Text(L("This record isn't loaded any more."))
                        .font(NBFont.ui(300, 13.5)).tracking(0.02 * 13.5)
                        .foregroundStyle(NB.text2)
                } footer: { EmptyView() }
            }
        }
        .background(NB.carbon2)
    }

    // MARK: 身体扫描

    private func bodyScan(_ scan: MeasurementRecord.BodyScan, at date: Date) -> some View {
        SheetFrame(title: L("Body scan")) {
            VStack(alignment: .leading, spacing: 18) {
                stamp("\(Self.stamp(date)) · \(L("BAND BIA"))")
                // 顶部这两个大数就是清单行右列那两个数——同一条记录在两处必须说同一句话。
                HStack(spacing: 16) {
                    bigNumber(L("BODY FAT"),
                              scan.bodyFatPercent.map { "\(Fmt.kg($0)) %" } ?? Fmt.dash,
                              tint: NB.lime1)
                    bigNumber(L("LEAN MASS"),
                              scan.leanMassKg.map { "\(Fmt.kg($0)) KG" } ?? Fmt.dash,
                              tint: NB.emberPale)
                }
                VStack(spacing: 0) {
                    field(L("FAT MASS"), scan.fatMassKg.map { "\(Fmt.kg($0)) KG" })
                    field(L("BMR ESTIMATE"), scan.bmrKcal.map { "\(Fmt.kcal(Double($0))) KCAL/DAY" })
                    // ⚠️ 手环不产生体重。这一行必须说明这个数是我们推下去的，否则读起来像
                    // 手环把人称了一遍。
                    field(L("INPUT WEIGHT"), scan.inputWeightKg.map { "\(Fmt.kg($0)) KG" },
                          last: true)
                }
                Text(L("The band has no scale. Its BIA numbers are computed from the weight this app sent down, so a wrong weight moves every field here."))
                    .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                    .lineSpacing(4)
                    .foregroundStyle(NB.text3Prod)
            }
        } footer: { EmptyView() }
    }

    // MARK: 平衡检查

    private func balanceCheck(_ check: MeasurementRecord.BalanceCheck, at date: Date) -> some View {
        SheetFrame(title: L("Balance check")) {
            VStack(alignment: .leading, spacing: 18) {
                stamp("\(Self.stamp(date)) · 40 S")
                // ⚠️ 没有曲线。大数是结论词，不是波形，也不是一条可以被读成心电的东西。
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("WHICH SIDE LED"))
                        .font(NBFont.ui(500, 11)).tracking(0.16 * 11)
                        .foregroundStyle(NB.text3Prod)
                    Text(check.lead.word)
                        .font(NBFont.dot(700, 36))
                        .foregroundStyle(NB.lime1)
                }
                HStack(spacing: 16) {
                    smallNumber(L("HEART RATE"), check.heartRate.map { "\($0) BPM" } ?? Fmt.dash)
                    smallNumber(L("BEATS"), "\(check.beatCount)")
                    // ⚠️ 这个词只能叫 SPREAD。它是这次四十秒采样的 SD1，不是 RMSSD，也不是
                    // 夜间 HRV——那是睡眠页的词，两个数不可比。
                    smallNumber(L("SPREAD"), String(format: "%.0f MS", check.spreadMs))
                }
                Text(L("Forty seconds of beat-to-beat spacing, kept as a summary. The rhythm itself was not recorded."))
                    .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                    .lineSpacing(4)
                    .foregroundStyle(NB.text3Prod)
            }
        } footer: { EmptyView() }
    }

    // MARK: pieces

    private func stamp(_ text: String) -> some View {
        Text(text)
            .font(NBFont.dot(500, 12)).tracking(0.04 * 12)
            .foregroundStyle(NB.macroValue)
    }

    private func bigNumber(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.16 * 11)
                .foregroundStyle(NB.text3Prod)
            Text(value)
                .font(NBFont.dot(700, 30))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallNumber(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.16 * 11)
                .foregroundStyle(NB.text3Prod)
            Text(value)
                .font(NBFont.dot(600, 20))
                .foregroundStyle(NB.text1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 缺的字段印 ——，不隐藏：一行不见了，读的人不知道是没测到还是产品不给看。
    private func field(_ label: String, _ value: String?, last: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(NBFont.ui(500, 12)).tracking(0.08 * 12)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 8)
            Text(value ?? Fmt.dash)
                .font(NBFont.dot(600, 13))
                .foregroundStyle(NB.text1)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
    }

    private static func stamp(_ at: Date) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "MM·dd"
        let time = DateFormatter(); time.dateFormat = "HH:mm"
        return "\(Fmt.weekday(at).uppercased()) \(day.string(from: at)) · \(time.string(from: at))"
    }
}
