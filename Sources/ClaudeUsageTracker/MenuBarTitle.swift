import UsageCore

enum MenuBarTitle {
    static func make(report: MonthReport?, state: LoadState, mode: MenuBarMode,
                     money: (Double) -> String, percent: (Double) -> String) -> String {
        if state == .needsLogin { return "💰 ⚠︎" }
        guard let report else { return "💰 …" }
        let spend = money(report.spend)
        let share = report.budgetFraction.map(percent)
        switch mode {
        case .spend: return "💰 \(spend)"
        case .spendAndPercent: return share.map { "💰 \(spend) · \($0)" } ?? "💰 \(spend)"
        case .percent: return "💰 \(share ?? spend)"
        case .iconOnly: return "💰"
        }
    }
}
