//
//  AddTransactionScreen.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI
import UIKit
import Vision
import CoreImage

struct AddTransactionScreen: View {
    @ObservedObject var vm: DashboardViewModel
    let fixedAccountId: UUID?
    let initialDraft: TransactionQuickAddDraft?
    let onDone: () -> Void
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var selectedCategory: CategoryItem? = nil
    @State private var selectedDate: Date = Date()
    @State private var note: String = ""

    @State private var showSelectAccount: Bool = false
    @State private var showSelectTargetAccount: Bool = false
    @State private var showSelectCategory: Bool = false
    @State private var showLimitAlert: Bool = false
    @State private var showInsufficientCashAlert: Bool = false
    @State private var isCreditCardPayment: Bool = false
    @State private var selectedTargetAccount: Account? = nil
    @State private var hasAppliedAutoCategorySuggestion: Bool = false
    @State private var showDuplicateConfirm: Bool = false
    @State private var isRecurringIncome: Bool = false
    @State private var recurringIncomeName: String = ""
    @State private var recurringIncomeFrequency: FixedPaymentFrequency = .monthly
    @State private var recurringIncomeChargeDay: Int = max(1, min(31, Calendar.current.component(.day, from: Date())))
    @State private var showReceiptSourcePicker: Bool = false
    @State private var showCameraPicker: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedReceiptImage: UIImage? = nil
    @State private var isProcessingReceipt: Bool = false
    @State private var receiptResultTitle: String = "Receipt Scan"
    @State private var receiptResultMessage: String = ""
    @State private var showReceiptResultAlert: Bool = false
    @State private var hasAppliedInitialDraft: Bool = false

    init(vm: DashboardViewModel,
         fixedAccountId: UUID? = nil,
         initialDraft: TransactionQuickAddDraft? = nil,
         onDone: @escaping () -> Void) {
        self.vm = vm
        self.fixedAccountId = fixedAccountId
        self.initialDraft = initialDraft
        self.onDone = onDone
    }

    private var availableTargetAccounts: [Account] {
        guard let source = selectedAccount else { return [] }
        return vm.accounts.filter { account in
            guard account.id != source.id else { return false }
            if selectedType == .transfer {
                return true
            }
            return account.type == .credit
        }
    }

    private var isValid: Bool {
        guard let amt = Decimal(string: amountText), amt > 0 else { return false }
        guard selectedAccount != nil else { return false }

        if selectedType == .transfer {
            return selectedTargetAccount != nil
        }
        if selectedType == .income, isRecurringIncome {
            return !recurringIncomeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isCreditCardPayment {
            return selectedTargetAccount?.type == .credit
        }
        return selectedCategory != nil
    }

    private var isAccountLocked: Bool {
        fixedAccountId != nil
    }

    private var displayColor: Color {
        switch selectedType {
        case .expense: return theme.negative
        case .income: return theme.positive
        case .transfer: return theme.accent
        }
    }

    private var currentProfileName: String {
        let trimmed = currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    var body: some View {
        NavigationStack {
            screenContent
        }
        .sheet(isPresented: $showSelectAccount) {
            SelectAccountScreen(accounts: vm.accounts) { selectedAccount = $0 }
        }
        .sheet(isPresented: $showSelectTargetAccount) {
            SelectAccountScreen(accounts: availableTargetAccounts) { selectedTargetAccount = $0 }
        }
        .sheet(isPresented: $showSelectCategory) {
            SelectCategoryScreen(transactionType: selectedType) { selectedCategory = $0 }
        }
        .sheet(isPresented: $showCameraPicker) {
            ReceiptImagePicker(sourceType: .camera) { image in
                selectedReceiptImage = image
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            ReceiptImagePicker(sourceType: .photoLibrary) { image in
                selectedReceiptImage = image
            }
        }
        .confirmationDialog("Scan Receipt",
                            isPresented: $showReceiptSourcePicker,
                            titleVisibility: .visible) {
            Button("Take Photo") {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    presentReceiptResult(title: "Camera Unavailable",
                                         message: "This device cannot take photos.")
                    return
                }
                showCameraPicker = true
            }
            Button("Choose from Library") {
                showPhotoPicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert(receiptResultTitle, isPresented: $showReceiptResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(receiptResultMessage)
        }
        .alert("Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Free tier allows \(SubscriptionManager.monthlyTransactionLimitText) transactions per month. Upgrade to Pro for unlimited transactions.")
        }
        .alert("Insufficient Cash", isPresented: $showInsufficientCashAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The selected cash account does not have enough balance for this payment.")
        }
        .alert("Possible Duplicate", isPresented: $showDuplicateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Save Anyway") {
                persistTransaction(skipDuplicateCheck: true)
            }
        } message: {
            Text("A similar transaction exists within the last 2 days. Save anyway?")
        }
        .onChange(of: selectedType) { _, newType in
            selectedCategory = nil
            hasAppliedAutoCategorySuggestion = false
            if newType != .expense {
                isCreditCardPayment = false
            }
            if newType != .income {
                isRecurringIncome = false
                recurringIncomeName = ""
                recurringIncomeFrequency = .monthly
            }
            if newType != .transfer {
                selectedTargetAccount = nil
            }
        }
        .onChange(of: selectedAccount) { _, acct in
            if acct?.type != .cash {
                isCreditCardPayment = false
            }
            if selectedTargetAccount?.id == acct?.id {
                selectedTargetAccount = nil
            }
        }
        .onChange(of: note) { _, newNote in
            guard selectedType != .transfer else { return }
            guard hasAppliedAutoCategorySuggestion == false || selectedCategory == nil else { return }
            guard let suggested = vm.suggestedCategory(type: selectedType,
                                                       note: newNote,
                                                       currentProfile: currentProfileName) else { return }
            selectedCategory = CategoryItem(id: suggested,
                                            name: suggested,
                                            icon: TransactionCategory.iconSystemName(for: suggested))
            hasAppliedAutoCategorySuggestion = true
        }
        .onChange(of: selectedReceiptImage) { _, image in
            guard let image else { return }
            scanReceipt(image)
        }
        .onAppear {
            guard let fixedAccountId else { return }
            selectedAccount = vm.accounts.first(where: { $0.id == fixedAccountId })
            applyInitialDraftIfNeeded()
        }
        .onChange(of: vm.accounts.count) { _, _ in
            guard let fixedAccountId else { return }
            selectedAccount = vm.accounts.first(where: { $0.id == fixedAccountId })
        }
        .onAppear {
            applyInitialDraftIfNeeded()
        }
    }

    private var screenContent: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                typeTabs.padding(.top, 10)

                ScrollView {
                    VStack(spacing: 24) {
                        amountSection
                        receiptScanSection
                        accountSection
                        if selectedType == .expense { creditPaymentSection }
                        if isCreditCardPayment || selectedType == .transfer {
                            targetAccountSection
                        }
                        categorySection
                        dateSection
                        noteSection
                        if selectedType == .income { recurringIncomeSection }

                        // Space so content isn't hidden behind save bar
                        Color.clear.frame(height: 110)
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("New Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
    }

    private var typeTabs: some View {
        HStack(spacing: 0) {
            ForEach(TransactionType.allCases) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedType = type }
                } label: {
                    VStack(spacing: 8) {
                        Text(type.rawValue)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(selectedType == type ? theme.textPrimary : theme.textTertiary)

                        Rectangle()
                            .fill(selectedType == type ? tabColor(for: type) : .clear)
                            .frame(height: 3)
                            .cornerRadius(2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var amountSection: some View {
        VStack(spacing: 12) {
            Text(amountPrompt)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 6) {
                Text(amountSign)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(displayColor)

                Text("S$")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(displayColor.opacity(0.7))

                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(displayColor)
            }
            .padding(.vertical, 10)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button {
                if !isAccountLocked {
                    showSelectAccount = true
                }
            } label: {
                HStack {
                    if let acct = selectedAccount {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: acct.colorHex).opacity(0.95))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: acct.iconSystemName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        Text(acct.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Image(systemName: "creditcard").foregroundStyle(theme.textTertiary)
                        Text("Select Account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    if !isAccountLocked {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
            .disabled(isAccountLocked)
        }
    }

    private var categorySection: some View {
        if isCreditCardPayment || selectedType == .transfer {
            return AnyView(EmptyView())
        }

        return AnyView(
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button { showSelectCategory = true } label: {
                HStack {
                    if let cat = selectedCategory {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: cat.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            )
                        Text(cat.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Image(systemName: "square.grid.2x2").foregroundStyle(theme.textTertiary)
                        Text("Select Category")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
        }
        )
    }

    private var creditPaymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Payment to Credit Card", isOn: Binding(
                get: { isCreditCardPayment },
                set: { enabled in
                    if enabled, selectedAccount?.type != .cash {
                        isCreditCardPayment = false
                        return
                    }
                    isCreditCardPayment = enabled
                    if !enabled { selectedTargetAccount = nil }
                }
            ))
            .tint(theme.accent)
            .foregroundStyle(theme.textPrimary)

            if selectedAccount?.type != .cash {
                Text("Select a cash account first to enable credit card payment.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
    }

    private var targetAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedType == .transfer ? "Transfer To" : "Pay To")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button { showSelectTargetAccount = true } label: {
                HStack {
                    if let acct = selectedTargetAccount {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: acct.colorHex).opacity(0.95))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: acct.iconSystemName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        Text(acct.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Image(systemName: "creditcard").foregroundStyle(theme.textTertiary)
                        Text(selectedType == .transfer ? "Select Destination Account" : "Select Credit Card")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date & Time")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .tint(theme.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .colorScheme(themeIsDark ? .dark : .light)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note (optional)")
                Spacer()
                Button("Smart Parse") {
                    let parsed = vm.parseTransactionHints(from: note)
                    if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let amount = parsed.amount {
                        amountText = NSDecimalNumber(decimal: amount).stringValue
                    }
                    if let date = parsed.date {
                        selectedDate = date
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.accent)
            }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField("e.g. Lunch", text: $note)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var receiptScanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Receipt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button {
                if !isProcessingReceipt {
                    showReceiptSourcePicker = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isProcessingReceipt ? "Scanning receipt..." : "Scan Receipt")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Take a photo or select one to auto-fill amount, date, and note.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    if isProcessingReceipt {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
            .disabled(isProcessingReceipt)
        }
    }

    private var recurringIncomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Make this recurring income", isOn: $isRecurringIncome)
                .tint(theme.accent)
                .foregroundStyle(theme.textPrimary)

            if isRecurringIncome {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    TextField("e.g. Salary, Allowance, Rental", text: $recurringIncomeName)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
                        .foregroundStyle(theme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Frequency")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Picker("Frequency", selection: $recurringIncomeFrequency) {
                        Text("Monthly").tag(FixedPaymentFrequency.monthly)
                        Text("Yearly").tag(FixedPaymentFrequency.yearly)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Charge Day")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Picker("Charge Day", selection: $recurringIncomeChargeDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
    }

    private var saveBar: some View {
        Button {
            persistTransaction(skipDuplicateCheck: false)
        } label: {
            Text("Save Transaction")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isValid ? displayColor : displayColor.opacity(0.3))
                )
        }
        .disabled(!isValid)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(theme.surface)
    }

    private func persistTransaction(skipDuplicateCheck: Bool) {
        guard let amt = Decimal(string: amountText) else { return }
        let acct: Account
        if let fixedAccountId {
            guard let fixedAccount = vm.accounts.first(where: { $0.id == fixedAccountId }) else { return }
            acct = fixedAccount
        } else {
            guard let selectedAccount else { return }
            acct = selectedAccount
        }

        if !skipDuplicateCheck && selectedType != .transfer {
            let exists = vm.hasPotentialDuplicate(type: selectedType,
                                                  amount: amt,
                                                  accountId: acct.id,
                                                  date: selectedDate)
            if exists {
                showDuplicateConfirm = true
                return
            }
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let added: Bool

        if selectedType == .transfer {
            guard let target = selectedTargetAccount else { return }
            if acct.type == .cash, acct.amount < amt {
                showInsufficientCashAlert = true
                return
            }
            added = vm.transferBetweenAccounts(fromAccountId: acct.id,
                                               toAccountId: target.id,
                                               amount: amt,
                                               date: selectedDate,
                                               note: trimmedNote)
        } else if isCreditCardPayment {
            guard let target = selectedTargetAccount else { return }
            if acct.amount < amt {
                showInsufficientCashAlert = true
                return
            }
            added = vm.payCreditCard(fromCashAccountId: acct.id,
                                     toCreditAccountId: target.id,
                                     amount: amt,
                                     date: selectedDate,
                                     note: trimmedNote)
        } else {
            guard let cat = selectedCategory else { return }
            added = vm.addTransaction(type: selectedType,
                                      amount: amt,
                                      accountId: acct.id,
                                      categoryName: cat.name,
                                      date: selectedDate,
                                      note: trimmedNote)
        }
        if added {
            if selectedType == .income && isRecurringIncome {
                vm.addRecurringIncomePlan(name: recurringIncomeName,
                                          amount: amt,
                                          frequency: recurringIncomeFrequency,
                                          chargeDay: recurringIncomeChargeDay,
                                          accountId: acct.id,
                                          startDate: selectedDate,
                                          note: trimmedNote,
                                          profileName: currentProfileName)
            }
            onDone()
            dismiss()
        } else {
            showLimitAlert = true
        }
    }

    private var amountPrompt: String {
        switch selectedType {
        case .expense: return "How much did you spend?"
        case .income: return "How much did you receive?"
        case .transfer: return "How much do you want to transfer?"
        }
    }

    private var amountSign: String {
        switch selectedType {
        case .expense: return "−"
        case .income: return "+"
        case .transfer: return "⇄"
        }
    }

    private func tabColor(for type: TransactionType) -> Color {
        switch type {
        case .expense: return theme.negative
        case .income: return theme.positive
        case .transfer: return theme.accent
        }
    }

    private func scanReceipt(_ image: UIImage) {
        isProcessingReceipt = true
        Task {
            defer {
                Task { @MainActor in
                    isProcessingReceipt = false
                    selectedReceiptImage = nil
                }
            }

            do {
                let text = try await recognizeReceiptText(from: image)
                await MainActor.run {
                    applyRecognizedReceiptText(text)
                }
            } catch {
                await MainActor.run {
                    presentReceiptResult(title: "Scan Failed",
                                         message: "Could not read the receipt. Try a clearer photo.")
                }
            }
        }
    }

    private func recognizeReceiptText(from image: UIImage) async throws -> String {
        let cgImage: CGImage
        if let existing = image.cgImage {
            cgImage = existing
        } else if let ciImage = image.ciImage,
                  let converted = CIContext().createCGImage(ciImage, from: ciImage.extent) {
            cgImage = converted
        } else {
            throw NSError(domain: "ReceiptOCR", code: 1)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let text = observations
                        .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")

                    if text.isEmpty {
                        continuation.resume(throwing: NSError(domain: "ReceiptOCR", code: 2))
                        return
                    }
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyRecognizedReceiptText(_ text: String) {
        let parsed = vm.parseTransactionHints(from: text)
        var updatedFields: [String] = []

        if let receiptAmount = bestReceiptAmount(from: text) {
            let nextAmountText = NSDecimalNumber(decimal: receiptAmount).stringValue
            if amountText != nextAmountText {
                amountText = nextAmountText
                updatedFields.append("amount")
            }
        } else if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let fallbackAmount = parsed.amount {
            amountText = NSDecimalNumber(decimal: fallbackAmount).stringValue
            updatedFields.append("amount")
        }

        if let date = parsed.date {
            selectedDate = date
            updatedFields.append("date")
        }

        let existingNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingNote.isEmpty {
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let candidate = lines.first(where: { line in
                let lower = line.lowercased()
                return lower.range(of: "[a-z]", options: .regularExpression) != nil &&
                !lower.contains("total") &&
                !lower.contains("tax") &&
                !lower.contains("gst")
            }) {
                note = candidate
                updatedFields.append("note")
            }
        }

        if updatedFields.isEmpty {
            presentReceiptResult(title: "Scan Completed",
                                 message: "Receipt was scanned, but no fields were auto-filled.")
        } else {
            presentReceiptResult(title: "Scan Completed",
                                 message: "Updated: \(updatedFields.joined(separator: ", ")).")
        }
    }

    private func bestReceiptAmount(from text: String) -> Decimal? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        typealias Candidate = (lineIndex: Int, score: Int, amount: Decimal, isTotalLike: Bool, isSubtotal: Bool)
        var scoredCandidates: [Candidate] = []
        var genericCandidates: [Candidate] = []
        var allCandidates: [Candidate] = []
        var lastChargeIndex: Int? = nil

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let isTotalLike = isLikelyTotalLine(lower)
            let isChargeLike = isLikelyChargeLine(lower)
            let isSubtotal = lower.contains("subtotal")
            let amounts = extractCurrencyValues(from: line, allowCompact: isTotalLike || isChargeLike)
            guard !amounts.isEmpty else { continue }

            if isChargeLike {
                lastChargeIndex = index
            }

            let lineAmounts = amounts.filter { $0 > 0 }
            guard !lineAmounts.isEmpty else { continue }

            let score = receiptLineScore(lower)
            for value in lineAmounts {
                allCandidates.append((lineIndex: index,
                                      score: score,
                                      amount: value,
                                      isTotalLike: isTotalLike,
                                      isSubtotal: isSubtotal))
            }

            if score > 0 {
                for value in lineAmounts {
                    scoredCandidates.append((lineIndex: index,
                                             score: score,
                                             amount: value,
                                             isTotalLike: isTotalLike,
                                             isSubtotal: isSubtotal))
                }
            } else if lower.contains("$") || lower.contains("s$") {
                for value in lineAmounts {
                    genericCandidates.append((lineIndex: index,
                                              score: score,
                                              amount: value,
                                              isTotalLike: isTotalLike,
                                              isSubtotal: isSubtotal))
                }
            }
        }

        if let final = scoredCandidates.reversed().first(where: {
            $0.isTotalLike && !$0.isSubtotal
        }) {
            return final.amount
        }

        if let chargeIndex = lastChargeIndex,
           let afterCharge = allCandidates.reversed().first(where: { $0.lineIndex > chargeIndex }) {
            return afterCharge.amount
        }

        if let best = scoredCandidates.max(by: {
            if $0.score == $1.score {
                return $0.lineIndex < $1.lineIndex
            }
            return $0.score < $1.score
        }) {
            return best.amount
        }

        if let fallback = genericCandidates.reversed().first {
            return fallback.amount
        }

        if let lastSeen = allCandidates.reversed().first {
            return lastSeen.amount
        }
        return nil
    }

    private func receiptLineScore(_ lowercasedLine: String) -> Int {
        var score = 0

        if lowercasedLine.contains("grand total") { score += 120 }
        if lowercasedLine.contains("amount due") || lowercasedLine.contains("net total") || lowercasedLine.contains("total due") || lowercasedLine.contains("final total") {
            score += 110
        }
        if isLikelyTotalLine(lowercasedLine) { score += 90 }

        if lowercasedLine.contains("subtotal") { score -= 80 }
        if isLikelyChargeLine(lowercasedLine) { score -= 70 }
        if lowercasedLine.contains("discount") || lowercasedLine.contains("change") { score -= 40 }

        return score
    }

    private func isLikelyTotalLine(_ lowercasedLine: String) -> Bool {
        lowercasedLine.contains("total")
            || lowercasedLine.contains("tota")
            || lowercasedLine.contains("amount due")
            || lowercasedLine.contains("net total")
            || lowercasedLine.contains("final total")
    }

    private func isLikelyChargeLine(_ lowercasedLine: String) -> Bool {
        lowercasedLine.contains("gst")
            || lowercasedLine.contains("tax")
            || lowercasedLine.contains("vat")
            || lowercasedLine.contains("service charge")
            || lowercasedLine.contains("svc")
    }

    private func extractCurrencyValues(from line: String, allowCompact: Bool = false) -> [Decimal] {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = ReceiptRegex.currency.matches(in: line, range: range)

        var values: [Decimal] = matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: line) else {
                return nil
            }
            let raw = String(line[valueRange])
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Decimal(string: raw)
        }

        if values.isEmpty && allowCompact {
            // OCR sometimes drops separators: 26487 should be 264.87
            if let match = ReceiptRegex.compact.firstMatch(in: line, range: range),
               match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: line) {
                let raw = String(line[valueRange])
                if let integer = Decimal(string: raw), integer >= 100 {
                    values.append(integer / 100)
                }
            }
        }

        return values
    }

    private enum ReceiptRegex {
        static let currency = try! NSRegularExpression(
            pattern: #"(?:s\$|\$)?\s*([0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})|[0-9]+(?:[.,][0-9]{2}))"#,
            options: [.caseInsensitive]
        )
        static let compact = try! NSRegularExpression(pattern: #"\b([0-9]{3,7})\b"#)
    }

    private func presentReceiptResult(title: String, message: String) {
        receiptResultTitle = title
        receiptResultMessage = message
        showReceiptResultAlert = true
    }

    private func applyInitialDraftIfNeeded() {
        guard !hasAppliedInitialDraft, let draft = initialDraft else { return }
        hasAppliedInitialDraft = true

        if let parsedType = TransactionType(rawValue: draft.typeRaw), parsedType != .transfer {
            selectedType = parsedType
        }

        if let amount = draft.amount {
            amountText = NSDecimalNumber(decimal: amount).stringValue
        }

        if let date = draft.date {
            selectedDate = date
        }

        let trimmedNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            note = trimmedNote
        }

        if let categoryName = draft.categoryName,
           !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedCategory = CategoryItem(id: categoryName,
                                            name: categoryName,
                                            icon: TransactionCategory.iconSystemName(for: categoryName))
        }
    }
}

private struct ReceiptImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
