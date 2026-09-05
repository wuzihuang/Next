import SwiftUI

/// This destructive action succeeds only after the authenticated server transaction.
struct FastingAction: View {
    let day: UserDay
    @EnvironmentObject private var data: DataStore
    @State private var confirming = false
    @State private var saving = false
    @State private var error: String?

    private var fasted: Bool { data.today.day == day && data.today.fuelState == .fasted }
    private var hasFood: Bool {
        (data.meals + data.recentMeals).contains { $0.day == day }
            || (data.today.eIn ?? 0) > 0 || MealQueue.shared.pendingCount > 0
    }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                if hasFood { confirming = true } else { save() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(NB.ember1) }
                    Text(fasted ? L("Recorded: nothing eaten today") : L("I haven't eaten anything today"))
                        .font(NBFont.ui(400, 13))
                }
                .foregroundStyle(NB.text3Prod)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(saving || fasted)
            .accessibilityIdentifier("fasting-action")
            if let error { Text(error).font(NBFont.ui(400, 12)).foregroundStyle(NB.alert2) }
        }
        .sheet(isPresented: $confirming) {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("Confirm no food today")).font(NBFont.ui(600, 22)).foregroundStyle(NB.text1)
                Text(L("This will permanently clear all food recorded today and record zero intake. You will not be able to add or change food for today."))
                    .font(NBFont.ui(400, 15)).foregroundStyle(NB.text3Prod)
                if let error { Text(error).font(NBFont.ui(400, 12)).foregroundStyle(NB.alert2) }
                LimePillButton(title: saving ? L("Saving…") : L("Clear food and confirm")) { save(confirmed: true) }
                    .disabled(saving).accessibilityIdentifier("fasting-confirm")
                Button(L("Cancel")) { confirming = false; error = nil }
                    .disabled(saving).frame(maxWidth: .infinity).foregroundStyle(NB.text3Prod)
            }
            .padding(24)
            .presentationDetents([.medium])
            .presentationBackground(NB.carbon2)
            .presentationCornerRadius(NB.R.panel)
            .interactiveDismissDisabled(saving)
        }
    }

    private func save(confirmed: Bool = false) {
        guard !saving else { return }
        saving = true; error = nil
        Task { @MainActor in
            defer { saving = false }
            do {
                try await data.markTodayFasted(day: day, confirmed: confirmed)
                confirming = false
            } catch SupabaseClient.Failure.http(_, let message) where message.contains("FOOD_REQUIRES_CONFIRMATION") {
                confirming = true
            } catch {
                self.error = L("Couldn't confirm. Check your connection and wait for pending meals to sync, then try again.")
            }
        }
    }
}

extension DataStore {
    @MainActor
    func markTodayFasted(day: UserDay, confirmed: Bool) async throws {
        guard day == UserDay.containing(Date()), today.day == day,
              let owner = SupabaseClient.currentUserIdSnapshot(), ConsentStore.shared.granted else {
            throw CancellationError()
        }
        await MealQueue.shared.flush()
        MealQueue.shared.refreshStatus(owner: owner)
        guard MealQueue.shared.pendingCount == 0 else { throw CancellationError() }
        let receipt = try await SupabaseClient.shared.rpc("mark_day_fasted", args: ["p_day": day.key, "p_clear_existing": confirmed], expectedOwner: owner)
        guard SupabaseClient.currentUserIdSnapshot() == owner,
              let fields = receipt as? [String: Any], fields["user_day"] as? String == day.key,
              fields["intake_state"] as? String == "FASTED" else { throw CancellationError() }
        // A midnight rollover never applies yesterday's acknowledgment to a new day.
        guard today.day == day, day == UserDay.containing(Date()) else { return }
        meals = meals.filter { $0.day != day }
        recentMeals = recentMeals.filter { $0.day != day }
        var updated = today
        updated.fuelState = .fasted; updated.eIn = 0
        updated.proteinIn = 0; updated.carbIn = 0; updated.fatIn = 0
        updated.protein = updated.protein.map { MacroSlot(target: $0.target, eaten: 0) }
        updated.carb = updated.carb.map { MacroSlot(target: $0.target, eaten: 0) }
        updated.fat = updated.fat.map { MacroSlot(target: $0.target, eaten: 0) }
        updated.balance = updated.eOutNow.map { -$0 }
        updated.nextMeal = 0
        today = updated
        HomeSnapshot.save(from: self)
        await Repository.shared.loadToday(into: self)
    }
}
