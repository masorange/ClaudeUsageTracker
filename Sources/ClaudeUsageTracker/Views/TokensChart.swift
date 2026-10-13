import Charts
import SwiftUI
import UsageCore

struct TokensChart: View {
    let report: MonthReport
    @ObservedObject var prefs: Preferences
    let money: (Double) -> String
    @State private var hovered: DayUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prefs.tr("Tokens per day", "Tokens por día"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(hoverText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Chart(report.days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Tokens", day.tokens))
                    .foregroundStyle(hovered?.day == day.day ? Color.accentColor : Color.accentColor.opacity(0.55))
                    .cornerRadius(2)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(Formatting.tokens(tokens, locale: prefs.language.locale))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let originX = geometry[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: location.x - originX) {
                                    hovered = report.days.first { Calendar.current.isDate($0.day, inSameDayAs: date) }
                                }
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .frame(height: 120)
            Text(prefs.tr("Month total: \(Formatting.tokens(report.totalTokens, locale: prefs.language.locale)) tokens",
                          "Total del mes: \(Formatting.tokens(report.totalTokens, locale: prefs.language.locale)) tokens"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var hoverText: String {
        guard let hovered else { return "" }
        let date = hovered.day.formatted(.dateTime.day().month(.abbreviated).locale(prefs.language.locale))
        let tokens = Formatting.tokens(hovered.tokens, locale: prefs.language.locale)
        return "\(date) · \(tokens) · \(money(hovered.spend))"
    }
}
