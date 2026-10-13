import Foundation

enum Formatting {
    /// Compact token count: 144.6 M, 8.9 K, 512.
    static func tokens(_ count: Int, locale: Locale) -> String {
        let value = Double(count)
        let (scaled, suffix): (Double, String) = switch value {
        case 1e9...: (value / 1e9, "B")
        case 1e6...: (value / 1e6, "M")
        case 1e3...: (value / 1e3, "K")
        default: (value, "")
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = suffix.isEmpty ? 0 : 1
        let number = formatter.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    /// Percentage with up to one decimal: 5,1 %, 100 %.
    static func percent(_ fraction: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: fraction)) ?? "\(Int(fraction * 100))%"
    }
}
