//
//  SmartToolsScreen.swift
//  FrugalPilot
//
//  Created by Codex on 1/3/26.
//

import SwiftUI
import SwiftData

struct SmartToolsScreen: View {
    let currentProfileName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]
    @Query(sort: [SortDescriptor(\Account.bankName), SortDescriptor(\Account.accountName)])
    private var allAccounts: [Account]

    @State private var budgets: [BudgetEnvelopeData] = []
    @State private var goals: [SavingsGoalData] = []
    @State private var reminders: [BillReminderData] = []
    @State private var rules: [AutoCategoryRuleData] = []

    @State private var budgetName = ""
    @State private var budgetCategory = ""
    @State private var budgetLimitText = ""

    @State private var goalName = ""
    @State private var goalTargetText = ""
    @State private var goalSavedText = ""

    @State private var reminderTitle = ""
    @State private var reminderAmountText = ""
    @State private var reminderDay: Int = 1
    @State private var reminderAccount: Account? = nil

    @State private var ruleKeyword = ""
    @State private var ruleCategory = ""
    @State private var ruleType: TransactionType = .expense

    private var profileAccountIds: Set<UUID> {
        Set(allAccounts.filter {
            let profile = $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (profile.isEmpty ? "Personal" : profile) == currentProfileName
        }.map(\.id))
    }

    private var profileTransactions: [Transaction] {
        allTransactions.filter { profileAccountIds.contains($0.accountId) }
    }

    private var recurringIncomeCount: Int {
        profileTransactions.filter { $0.categoryName == "Recurring Income" }.count
    }

    private var profileBudgets: [BudgetEnvelopeData] {
        budgets.filter { $0.profileName == currentProfileName }
    }

    private var profileGoals: [SavingsGoalData] {
        goals.filter { $0.profileName == currentProfileName }
    }

    private var profileReminders: [BillReminderData] {
        reminders.filter { $0.profileName == currentProfileName }
    }

    private var profileRules: [AutoCategoryRuleData] {
        rules.filter { $0.profileName == currentProfileName }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        howItWorksCard
                        insightCard
                        recurringIncomeCard
                        budgetsCard
                        savingsGoalsCard
                        remindersCard
                        rulesCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Smart Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .onAppear(perform: reload)
        }
    }

    private var howItWorksCard: some View {
        card("How Smart Tools Works") {
            VStack(alignment: .leading, spacing: 8) {
                infoLine("1. Recurring Income", "Go to Add Transaction > Income, enable recurring income, then set frequency and charge day.")
                infoLine("2. Budgets", "Set a monthly limit per category. Progress updates from this month expenses.")
                infoLine("3. Savings Goals", "Set target and saved amount. Progress bar tracks completion.")
                infoLine("4. Bill Reminders", "Set title, amount, and charge day. Bell icon shows upcoming reminders.")
                infoLine("5. Auto Category Rules", "Set keyword + category + type. While adding a transaction, matching notes auto-suggest category.")
                infoLine("6. Backup Support", "Backups include Smart Tools data, so import can restore your setup.")
            }
        }
    }

    private var insightCard: some View {
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        let spentThisMonth = profileTransactions
            .filter { $0.type == .expense && $0.date >= monthStart }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let budgetTotal = profileBudgets.reduce(Decimal.zero) { $0 + $1.monthlyLimit }
        let remaining = budgetTotal - spentThisMonth

        return card("Auto Insights") {
            Text("Recurring income entries: \(recurringIncomeCount)")
                .font(.custom("Avenir Next", size: 13).weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Text("Budget left this month: \(CurrencyFormatter.sgd(amount: remaining))")
                .font(.custom("Avenir Next", size: 13).weight(.semibold))
                .foregroundStyle(remaining >= 0 ? theme.positive : theme.negative)
            Text("Set it in Add Transaction > Income by enabling recurring income.")
                .font(.custom("Avenir Next", size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var recurringIncomeCard: some View {
        card("Recurring Income Automation") {
            Text("Configured in Add Transaction under the Income tab.")
                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Text("It auto-posts into transactions as +Recurring Income on due day.")
                .font(.custom("Avenir Next", size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var budgetsCard: some View {
        card("Budgets / Envelopes") {
            VStack(spacing: 8) {
                TextField("Budget name", text: $budgetName)
                    .textFieldStyle(.roundedBorder)
                TextField("Category", text: $budgetCategory)
                    .textFieldStyle(.roundedBorder)
                TextField("Monthly limit", text: $budgetLimitText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addBudget()
                } label: {
                    Text("Add Budget")
                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }

            ForEach(profileBudgets) { budget in
                let used = monthSpent(forCategory: budget.categoryName)
                let percent = budget.monthlyLimit > 0 ? min(1, (used as NSDecimalNumber).doubleValue / (budget.monthlyLimit as NSDecimalNumber).doubleValue) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(budget.name) (\(budget.categoryName))")
                            .font(.custom("Avenir Next", size: 13).weight(.semibold))
                        Spacer()
                        Text("\(CurrencyFormatter.sgd(amount: used)) / \(CurrencyFormatter.sgd(amount: budget.monthlyLimit))")
                            .font(.custom("Avenir Next", size: 11))
                    }
                    ProgressView(value: percent)
                        .tint(percent > 1 ? theme.negative : theme.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { removeBudget(budget) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var savingsGoalsCard: some View {
        card("Savings Goals") {
            VStack(spacing: 8) {
                TextField("Goal", text: $goalName)
                    .textFieldStyle(.roundedBorder)
                TextField("Target", text: $goalTargetText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Saved", text: $goalSavedText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addGoal()
                } label: {
                    Text("Add Goal")
                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }

            ForEach(profileGoals) { goal in
                let pct = goal.targetAmount > 0 ? min(1, (goal.savedAmount as NSDecimalNumber).doubleValue / (goal.targetAmount as NSDecimalNumber).doubleValue) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(goal.name)
                            .font(.custom("Avenir Next", size: 13).weight(.semibold))
                        Spacer()
                        Text("\(CurrencyFormatter.sgd(amount: goal.savedAmount)) / \(CurrencyFormatter.sgd(amount: goal.targetAmount))")
                            .font(.custom("Avenir Next", size: 11))
                    }
                    ProgressView(value: pct)
                        .tint(theme.positive)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { removeGoal(goal) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var remindersCard: some View {
        card("Bill Reminders") {
            VStack(spacing: 8) {
                TextField("Reminder title", text: $reminderTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Amount", text: $reminderAmountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Day")
                            .font(.custom("Avenir Next", size: 11).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                        Picker("Day", selection: $reminderDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account")
                            .font(.custom("Avenir Next", size: 11).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                        Menu {
                            Button("No account") { reminderAccount = nil }
                            ForEach(allAccounts.filter { profileAccountIds.contains($0.id) }) { account in
                                Button(account.displayName) { reminderAccount = account }
                            }
                        } label: {
                            Text(reminderAccount?.displayName ?? "Select account")
                                .lineLimit(1)
                                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Capsule().fill(theme.surfaceAlt))
                        }
                    }
                }

                Button {
                    addReminder()
                } label: {
                    Text("Add Reminder")
                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }

            ForEach(profileReminders) { reminder in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .font(.custom("Avenir Next", size: 13).weight(.semibold))
                        Text("Day \(reminder.chargeDay) • \(CurrencyFormatter.sgd(amount: reminder.amount))")
                            .font(.custom("Avenir Next", size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { removeReminder(reminder) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var rulesCard: some View {
        card("Rule-Based Auto Categorization") {
            VStack(spacing: 8) {
                TextField("Keyword", text: $ruleKeyword)
                    .textFieldStyle(.roundedBorder)
                TextField("Category", text: $ruleCategory)
                    .textFieldStyle(.roundedBorder)
                Picker("Type", selection: $ruleType) {
                    Text("Expense").tag(TransactionType.expense)
                    Text("Income").tag(TransactionType.income)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))

                Button {
                    addRule()
                } label: {
                    Text("Add Rule")
                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }

            ForEach(profileRules) { rule in
                HStack {
                    Text("\"\(rule.keyword)\" -> \(rule.categoryName)")
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                    Spacer()
                    Text(rule.transactionTypeRaw)
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { removeRule(rule) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Avenir Next", size: 14).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
    }

    private func infoLine(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.custom("Avenir Next", size: 12).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            Text(body)
                .font(.custom("Avenir Next", size: 11))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func monthSpent(forCategory categoryName: String) -> Decimal {
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return profileTransactions
            .filter { $0.type == .expense && $0.date >= monthStart && $0.categoryName == categoryName }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func reload() {
        budgets = SmartDataStore.loadBudgets()
        goals = SmartDataStore.loadGoals()
        reminders = SmartDataStore.loadReminders()
        rules = SmartDataStore.loadRules()
    }

    private func addBudget() {
        guard let limit = Decimal(string: budgetLimitText), limit > 0 else { return }
        let name = budgetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = budgetCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !category.isEmpty else { return }

        budgets.append(BudgetEnvelopeData(name: name, categoryName: category, monthlyLimit: limit, profileName: currentProfileName))
        SmartDataStore.saveBudgets(budgets)
        budgetName = ""
        budgetCategory = ""
        budgetLimitText = ""
    }

    private func removeBudget(_ budget: BudgetEnvelopeData) {
        budgets.removeAll { $0.id == budget.id }
        SmartDataStore.saveBudgets(budgets)
    }

    private func addGoal() {
        guard let target = Decimal(string: goalTargetText), target > 0 else { return }
        let saved = Decimal(string: goalSavedText) ?? .zero
        let name = goalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        goals.append(SavingsGoalData(name: name, targetAmount: target, savedAmount: saved, profileName: currentProfileName))
        SmartDataStore.saveGoals(goals)
        goalName = ""
        goalTargetText = ""
        goalSavedText = ""
    }

    private func removeGoal(_ goal: SavingsGoalData) {
        goals.removeAll { $0.id == goal.id }
        SmartDataStore.saveGoals(goals)
    }

    private func addReminder() {
        guard let amount = Decimal(string: reminderAmountText), amount > 0 else { return }
        let title = reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        reminders.append(BillReminderData(title: title,
                                          amount: amount,
                                          chargeDay: reminderDay,
                                          accountId: reminderAccount?.id,
                                          profileName: currentProfileName))
        SmartDataStore.saveReminders(reminders)
        reminderTitle = ""
        reminderAmountText = ""
    }

    private func removeReminder(_ reminder: BillReminderData) {
        reminders.removeAll { $0.id == reminder.id }
        SmartDataStore.saveReminders(reminders)
    }

    private func addRule() {
        let keyword = ruleKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = ruleCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !category.isEmpty else { return }

        rules.append(AutoCategoryRuleData(keyword: keyword,
                                          categoryName: category,
                                          transactionTypeRaw: ruleType.rawValue,
                                          profileName: currentProfileName))
        SmartDataStore.saveRules(rules)
        ruleKeyword = ""
        ruleCategory = ""
    }

    private func removeRule(_ rule: AutoCategoryRuleData) {
        rules.removeAll { $0.id == rule.id }
        SmartDataStore.saveRules(rules)
    }
}
