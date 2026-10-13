import Foundation

/// Formats USD amounts, optionally converted to EUR with a daily-cached exchange rate.
@MainActor
final class CurrencyService: ObservableObject {
    private static let rateKey = "lastExchangeRate"
    private static let dateKey = "lastExchangeRateUpdate"
    private static let fallbackRate = 0.92

    @Published private(set) var eurRate: Double
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        eurRate = defaults.object(forKey: Self.rateKey) as? Double ?? Self.fallbackRate
    }

    func refreshIfNeeded() async {
        if let last = defaults.object(forKey: Self.dateKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD"),
              let result = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let rates = json["rates"] as? [String: Double],
              let eur = rates["EUR"] else { return }
        eurRate = eur
        defaults.set(eur, forKey: Self.rateKey)
        defaults.set(Date(), forKey: Self.dateKey)
    }

    func format(_ usd: Double, currency: DisplayCurrency, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = language.locale
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = currency == .eur ? usd * eurRate : usd
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Per-million prices can be fractions of a cent; keep up to 4 decimals.
    func formatPrice(_ usd: Double, currency: DisplayCurrency, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = language.locale
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        let value = currency == .eur ? usd * eurRate : usd
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }
}
