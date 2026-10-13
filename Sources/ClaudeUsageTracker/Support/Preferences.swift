import Foundation

enum MenuBarMode: String, CaseIterable, Identifiable {
    case spend, spendAndPercent, percent, iconOnly
    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case es, en
    var id: String { rawValue }
    var locale: Locale { Locale(identifier: self == .es ? "es_ES" : "en_US") }
}

enum DisplayCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    var id: String { rawValue }
}

/// User settings persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let refreshOptions = [5, 15, 30, 60]

    private enum Keys {
        static let menuBarMode = "menuBarMode"
        static let language = "language"
        static let currency = "currency"
        static let refreshMinutes = "refreshMinutes"
    }

    private let defaults: UserDefaults

    @Published var menuBarMode: MenuBarMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Keys.menuBarMode) }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published var currency: DisplayCurrency {
        didSet { defaults.set(currency.rawValue, forKey: Keys.currency) }
    }
    @Published var refreshMinutes: Int {
        didSet { defaults.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMode = defaults.string(forKey: Keys.menuBarMode).flatMap(MenuBarMode.init(rawValue:)) ?? .spend
        let systemLanguage: AppLanguage = Locale.current.language.languageCode?.identifier == "es" ? .es : .en
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? systemLanguage
        currency = defaults.string(forKey: Keys.currency).flatMap(DisplayCurrency.init(rawValue:)) ?? .usd
        let minutes = defaults.integer(forKey: Keys.refreshMinutes)
        refreshMinutes = Self.refreshOptions.contains(minutes) ? minutes : 15
    }

    /// Picks the string for the current language.
    func tr(_ english: String, _ spanish: String) -> String {
        language == .es ? spanish : english
    }
}
