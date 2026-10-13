import Foundation

/// Removes data stored by 1.x (LiteLLM key, Looker cookies, local-cost settings).
enum LegacyCleanup {
    private static let doneKey = "legacyCleanupV2Done"
    private static let keys = [
        "litellm_api_key", "litellm_cache_last_date", "litellm_cache_timestamp", "litellm_cached_daily_activity",
        "looker_connected", "looker_promo_shown_v1_12", "looker_secure_1psid", "looker_secure_1psidts",
        "api_blocked_notice_shown_v1_8", "accountFilter", "showCostInStatusBar",
        "longContextPricing", "standardContextPricing",
    ]

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        keys.forEach(defaults.removeObject(forKey:))
        defaults.set(true, forKey: doneKey)
    }
}
