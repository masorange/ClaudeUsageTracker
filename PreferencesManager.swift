import Foundation
import SwiftUI

enum AccountFilter: String, CaseIterable {
    case all = "all"
    case workOnly = "workOnly"
    case personalOnly = "personalOnly"
}

class PreferencesManager: ObservableObject {
    private let showCostKey = "showCostInStatusBar"
    private let accountFilterKey = "accountFilter"

    @Published var showCostInStatusBar: Bool {
        didSet {
            UserDefaults.standard.set(showCostInStatusBar, forKey: showCostKey)
        }
    }

    @Published var accountFilter: AccountFilter {
        didSet {
            UserDefaults.standard.set(accountFilter.rawValue, forKey: accountFilterKey)
        }
    }

    init() {
        // Default to true (showing cost) if not set
        if UserDefaults.standard.object(forKey: showCostKey) != nil {
            self.showCostInStatusBar = UserDefaults.standard.bool(forKey: showCostKey)
        } else {
            self.showCostInStatusBar = true
        }

        // Default to .all if not set
        if let filterRaw = UserDefaults.standard.string(forKey: accountFilterKey),
           let filter = AccountFilter(rawValue: filterRaw) {
            self.accountFilter = filter
        } else {
            self.accountFilter = .all
        }
    }
}
