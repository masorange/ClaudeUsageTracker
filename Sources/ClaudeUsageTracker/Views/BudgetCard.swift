import SwiftUI
import UsageCore

struct BudgetCard: View {
    let report: MonthReport
    @ObservedObject var prefs: Preferences
    let money: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(money(report.spend))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(prefs.tr("spent this month", "gastado este mes"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let budget = report.budget {
                tierLine(budget: budget)
                    .padding(.top, 8)
                ProgressView(value: min(report.budgetFraction ?? 0, 1))
                    .tint(color)
                HStack {
                    Text(availabilityText)
                    Spacer()
                    Text(Formatting.percent(report.budgetFraction ?? 0, locale: prefs.language.locale))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let projection = report.projection {
                    Text(forecastText(projection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let tier = report.tier {
                Text(tierLabel(tier)).font(.callout).padding(.top, 8)
            }
        }
        .padding(12)
    }

    private func tierLine(budget: Double) -> some View {
        HStack(spacing: 4) {
            if let tier = report.tier {
                Text(tierLabel(tier)).fontWeight(.medium)
                Text("·").foregroundStyle(.secondary)
            }
            Text(money(budget) + prefs.tr("/month", "/mes"))
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func tierLabel(_ tier: String) -> String {
        TierMedal.medal(for: tier).map { "\($0) \(tier)" } ?? tier
    }

    private var color: Color {
        switch BudgetLevel(fraction: report.budgetFraction ?? 0) {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var availabilityText: String {
        let available = money(report.available ?? 0)
        guard let reset = report.budgetResetAt else {
            return prefs.tr("Available \(available)", "Disponible \(available)")
        }
        let calendar = Calendar.current
        let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                               to: calendar.startOfDay(for: reset)).day ?? 0, 0)
        return prefs.tr("Available \(available) · renews in \(days) d",
                        "Disponible \(available) · se renueva en \(days) d")
    }

    private func forecastText(_ projection: Double) -> String {
        let share = report.projectionFraction.map { " (\(Formatting.percent($0, locale: prefs.language.locale)))" } ?? ""
        return prefs.tr("Month-end forecast: \(money(projection))\(share)",
                        "Previsión de cierre: \(money(projection))\(share)")
    }
}
