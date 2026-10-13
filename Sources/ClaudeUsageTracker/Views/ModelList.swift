import SwiftUI
import UsageCore

struct ModelList: View {
    let models: [ModelUsage]
    @ObservedObject var prefs: Preferences
    let money: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prefs.tr("Most used models", "Modelos más usados"))
                .font(.subheadline.weight(.semibold))
            if models.isEmpty {
                Text(prefs.tr("No usage this month yet.", "Todavía no hay uso este mes."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(models) { model in
                row(model)
            }
        }
        .padding(12)
    }

    private func row(_ model: ModelUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(name(model))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if let discount = model.discount {
                    Text(money(model.listSpend))
                        .strikethrough()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("−" + Formatting.percent(discount, locale: prefs.language.locale))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                Text(money(model.spend))
                    .monospacedDigit()
            }
            Text("\(model.requests) \(prefs.tr("requests", "peticiones")) · \(Formatting.tokens(model.tokens, locale: prefs.language.locale)) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func name(_ model: ModelUsage) -> String {
        guard model.isOthers else { return model.displayName }
        let count = model.groupedCount ?? 0
        return prefs.tr("Others (\(count))", "Otros (\(count))")
    }
}
