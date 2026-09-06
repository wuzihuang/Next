import Foundation
import Combine

/// ADR 0010 · 平衡检查的账号自有外发队列，语义与 `BodyCompositionQueue` 相同：一次四十秒的
/// 测量不该因为手机当时离线就白做，也绝不能在换账号之后上传到新账号名下。
///
/// ⚠️ 只带摘要。`AutonomicBalance` 算完就把逐拍序列丢了，这里没有 intervals 字段可填,
/// 将来也不要加——见迁移 20260905160000 的表注释。
@MainActor
final class BalanceCheckQueue {
    static let shared = BalanceCheckQueue()

    struct Pending: Codable, Identifiable {
        let id: UUID
        let ownerUserId: String
        let measuredAt: Date
        let userDay: String
        let sampledTz: String
        let lead: String
        let restShare: Int
        let sd1Ms: Double
        let sd2Ms: Double
        let sdnnMs: Double
        let heartRate: Int?
        let beatCount: Int
    }

    private(set) var pending: [Pending] = []
    private var reachability: AnyCancellable?
    private var flushing = false
    private(set) var persistenceError: String?

    private func durable() throws -> DurableQueue<Pending> {
        DurableQueue(kind: "balance-check", store: try LocalDataStore.shared())
    }

    private init() {
        do { pending = try durable().items() }
        catch { persistenceError = error.localizedDescription }
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }

    func enqueue(_ balance: AutonomicBalance, heartRate: Int?, at date: Date,
                 ownerUserId: String) throws {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let lead: String = switch balance.lead {
        case .parasympathetic: "rest"
        case .sympathetic:     "drive"
        case .even:            "even"
        }
        let item = Pending(
            id: UUID(), ownerUserId: ownerUserId, measuredAt: date,
            userDay: day.string(from: UserDay.containing(date).date),
            sampledTz: TimeZone.current.identifier,
            lead: lead, restShare: balance.split.rest,
            sd1Ms: balance.sd1, sd2Ms: balance.sd2, sdnnMs: balance.sdnn,
            // 手环报了几次心率就用它的，没报过就用区间均值折出来的那个——两者都是这次测量
            // 自己的数，不会拿别的时刻的心率来充数。
            // ⚠️ 越界的值写成 nil，不写进去。表上有 25–220 的 CHECK，一条被拒的行会以 400
            // 卡在队列里无限重试，把它后面所有的测量一起堵死；这一列可空，空比堵好。
            heartRate: Self.plausible(heartRate ?? balance.beatsPerMinute),
            beatCount: balance.points.count + 1)
        try durable().save(item, id: item.id.uuidString, account: ownerUserId)
        pending = try durable().items()
        Task { await flush() }
    }

    /// `balance_checks.heart_rate` 的 CHECK 是 25–220，和表保持一致。
    private static func plausible(_ bpm: Int?) -> Int? {
        guard let bpm, (25...220).contains(bpm) else { return nil }
        return bpm
    }

    func flush() async {
        guard !flushing, Reachability.shared.isOnline, !DebugEdge.on("offline"),
              let currentUser = await SupabaseClient.shared.currentUserId else { return }
        flushing = true
        defer { flushing = false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for item in pending where item.ownerUserId == currentUser {
            guard await SupabaseClient.shared.currentUserId == currentUser else { return }
            var row: [String: Any] = [
                "user_id": item.ownerUserId,
                "measured_at": iso.string(from: item.measuredAt),
                "user_day": item.userDay,
                "sampled_tz": item.sampledTz,
                "lead": item.lead,
                "rest_share": item.restShare,
                "sd1_ms": item.sd1Ms,
                "sd2_ms": item.sd2Ms,
                "sdnn_ms": item.sdnnMs,
                "beat_count": item.beatCount,
                // 同一次测量重放多少次都只有一行。
                "client_op_id": item.id.uuidString.lowercased(),
            ]
            if let hr = item.heartRate { row["heart_rate"] = hr }
            do {
                _ = try await SupabaseClient.shared.insert("balance_checks", rows: [row],
                                                           returning: false)
                guard SupabaseClient.currentUserIdSnapshot() == currentUser, !Task.isCancelled else { return }
                try durable().acknowledge(id: item.id.uuidString, account: currentUser)
                pending = pending.filter { $0.id != item.id }
                await Analytics.shared.track("MEASUREMENT_SYNCED", ["KIND": "balance_check"])
            } catch SupabaseClient.Failure.http(let code, _) where code == 409 {
                // 唯一索引挡下的重放：这一行已经在库里了，确认掉即可。
                guard SupabaseClient.currentUserIdSnapshot() == currentUser, !Task.isCancelled else { return }
                do {
                    try durable().acknowledge(id: item.id.uuidString, account: currentUser)
                    pending = pending.filter { $0.id != item.id }
                } catch { persistenceError = error.localizedDescription; break }
            } catch {
                BandLog.shared.record("balance check outbox", error: error)
                break
            }
        }
    }

    func purge() {
        do {
            for item in pending { try durable().acknowledge(id: item.id.uuidString, account: item.ownerUserId) }
            pending = []
        } catch { persistenceError = error.localizedDescription }
    }
}
