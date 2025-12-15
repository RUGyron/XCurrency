import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class RateViewModel {
    private let fetcher: any RateFetching
    private let store: RateStore
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    private var pendingValue: Double?
    private var pendingOperator: CalculatorOperator?
    private var justCalculated = false
    private var isTypingCurrentOperand = false
    private var currentRates: [String: Double] = [:]
    var isFetching = false

    var selectedCodes: [String] {
        didSet { persistSelection() }
    }
    var baseCurrencyCode: String {
        didSet { persistBaseSelection() }
    }

    var amountText: String = "0" {
        didSet { persistAmount() }
    }
    var lastUpdatedFiat: Date?
    var lastUpdatedCrypto: Date?
    var lastUpdated: Date? { // сохранено для совместимости UI
        [lastUpdatedFiat, lastUpdatedCrypto].compactMap { $0 }.max()
    }
    var displayRates: [CurrencyAmount] = []

    init(
        context: ModelContext,
        fetcher: any RateFetching,
        initialRates: [String: Double]? = nil,
        autoRefresh: Bool = true,
        startTicker: Bool = true
    ) {
        self.fetcher = fetcher
        self.store = RateStore(context: context)

        let initialSelection = Self.loadSelection()
        self.selectedCodes = initialSelection
        self.baseCurrencyCode = Self.loadBaseSelection(selected: initialSelection)
        self.amountText = "0"

        // Для превью можем подложить стартовые курсы, но не чистим прод-кеш.
        if let initialRates {
            store.clearAll()
            store.persist(initialRates, timestamp: Date())
            currentRates = initialRates
        }

        loadStored()
        if autoRefresh {
            Task { await refreshNow() }
        }
        if startTicker {
            startForegroundTicker()
        }
    }

    deinit {
        tickerTask?.cancel()
    }

    func handleDigit(_ digit: String) {
        if justCalculated && pendingOperator == nil {
            // новый ввод после равно
            amountText = digit == "." ? "0." : digit
            justCalculated = false
            isTypingCurrentOperand = true
        } else if amountText == "0" {
            amountText = digit == "." ? "0." : digit
            isTypingCurrentOperand = true
        } else {
            if digit == "." && amountText.contains(".") { return }
            amountText.append(digit)
            isTypingCurrentOperand = true
        }
        recalc()
    }

    func handleOperator(_ op: CalculatorOperator) {
        let current = Double(amountText) ?? 0
        if let pending = pendingValue, let pendingOp = pendingOperator {
            let result = pendingOp.apply(lhs: pending, rhs: current)
            pendingValue = result
            amountText = Self.format(result)
        } else {
            pendingValue = current
        }
        pendingOperator = op
        amountText = "0"
        isTypingCurrentOperand = false
        justCalculated = false
    }

    func handleEquals() {
        guard let pending = pendingValue, let op = pendingOperator else { return }
        let current = Double(amountText) ?? 0
        let result = op.apply(lhs: pending, rhs: current)
        amountText = Self.format(result)
        pendingValue = nil
        pendingOperator = nil
        justCalculated = true
        isTypingCurrentOperand = false
        recalc()
    }

    func clear() {
        amountText = "0"
        pendingValue = nil
        pendingOperator = nil
        justCalculated = false
        isTypingCurrentOperand = false
        recalc()
    }

    func backspace() {
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
        if amountText.isEmpty || amountText == "-" { amountText = "0" }
        recalc()
    }

    func toggleSign() {
        guard amountText != "0" else { return }
        if amountText.hasPrefix("-") {
            amountText.removeFirst()
        } else {
            amountText = "-" + amountText
        }
        recalc()
    }

    func refreshNow(includeFiat: Bool = true, includeCrypto: Bool = true) async {
        isFetching = true
        defer { isFetching = false }

        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                print("RateViewModel: refreshNow start attempt=\(attempt) fiat=\(includeFiat) crypto=\(includeCrypto) selected=\(selectedCodes)")
                let result = try await fetcher.fetchAll(for: selectedCodes, includeFiat: includeFiat, includeCrypto: includeCrypto)
                store.persist(result.rates, timestamp: result.combinedTimestamp)
                currentRates = result.rates
                if includeFiat { lastUpdatedFiat = result.fiatTimestamp }
                if includeCrypto { lastUpdatedCrypto = result.cryptoTimestamp }
                recalc(using: result.rates)
                print("RateViewModel: refreshNow success attempt=\(attempt)")
                return
            } catch {
                print("RateViewModel: refreshNow failed attempt=\(attempt) error=\(error)")
                if attempt == maxAttempts { return }
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s backoff
            }
        }
    }

    var displayLine: String {
        if let op = pendingOperator, let pending = pendingValue {
            if isTypingCurrentOperand && !amountText.isEmpty {
                return "\(Self.format(pending)) \(op.symbol) \(amountText)"
            } else {
                return "\(Self.format(pending)) \(op.symbol)"
            }
        }
        return amountText
    }

    func updateSelection(_ codes: [String]) {
        selectedCodes = codes
        if !selectedCodes.contains(baseCurrencyCode) {
            baseCurrencyCode = selectedCodes.first ?? "USD"
        }
        recalc()
    }

    func setBaseCurrency(_ code: String) {
        guard selectedCodes.contains(code) else { return }

        baseCurrencyCode = code
        pendingValue = nil
        pendingOperator = nil
        justCalculated = false
        isTypingCurrentOperand = false
        recalc()
    }

    private func loadStored() {
        let stored = store.fetchAll()
        let rateMap = Dictionary(uniqueKeysWithValues: stored.map { ($0.code, $0.unitsPerUSD) })
        currentRates = rateMap
        if let ts = store.lastUpdated {
            lastUpdatedFiat = ts
            lastUpdatedCrypto = ts
        }
        recalc(using: rateMap)
    }

    private func makeRateMap() -> [String: Double] {
        if currentRates.isEmpty {
            let stored = store.fetchAll()
            currentRates = Dictionary(uniqueKeysWithValues: stored.map { ($0.code, $0.unitsPerUSD) })
        }
        var rateMap = currentRates
        rateMap["USD"] = 1.0
        return rateMap
    }

    private func recalc(using customRates: [String: Double]? = nil) {
        let baseAmount = Double(amountText) ?? 0
        var rateMap = makeRateMap()
        if let customRates { rateMap.merge(customRates) { _, new in new } }

        let baseUnitsPerUSD = rateMap[baseCurrencyCode]
        let amountUSD: Double?
        if baseCurrencyCode == "USD" {
            amountUSD = baseAmount
        } else if let baseUnitsPerUSD, baseUnitsPerUSD > 0 {
            amountUSD = baseAmount / baseUnitsPerUSD
        } else {
            amountUSD = nil
        }

        displayRates = selectedCodes.compactMap { code in
            guard let currency = Currency.lookup(code: code) else { return nil }
            let isBase = code == baseCurrencyCode
            let targetUnits = rateMap[code]

            if isBase {
                return CurrencyAmount(currency: currency, amount: baseAmount, hasRate: true, isBase: true)
            }

            guard let amountUSD, let targetUnits else {
                return CurrencyAmount(currency: currency, amount: 0, hasRate: false, isBase: false)
            }

            let converted = amountUSD * targetUnits
            return CurrencyAmount(currency: currency, amount: converted, hasRate: true, isBase: false)
        }
    }

    private func startForegroundTicker() {
        tickerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // раз в минуту
                await self.refreshNow(includeFiat: true, includeCrypto: true)
            }
        }
    }

    private func persistSelection() {
        UserDefaults.standard.set(selectedCodes, forKey: "selectedCodes")
    }

    private func persistBaseSelection() {
        UserDefaults.standard.set(baseCurrencyCode, forKey: "baseCurrencyCode")
    }

    private func persistAmount() {
        UserDefaults.standard.set(amountText, forKey: "amountText")
    }

    private static func loadSelection() -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: "selectedCodes")
        return stored?.isEmpty == false ? stored! : Currency.defaultSelection
    }

    private static func loadBaseSelection(selected: [String]) -> String {
        let stored = UserDefaults.standard.string(forKey: "baseCurrencyCode")
        if let stored, selected.contains(stored) {
            return stored
        }
        return selected.first ?? "USD"
    }

    private static func loadAmount() -> String {
        UserDefaults.standard.string(forKey: "amountText") ?? "0"
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

}

struct CurrencyAmount: Identifiable {
    let currency: Currency
    let amount: Double
    let hasRate: Bool
    let isBase: Bool
    var id: String { currency.code }
}

enum CalculatorOperator {
    case add, subtract, multiply, divide

    func apply(lhs: Double, rhs: Double) -> Double {
        switch self {
        case .add: return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide: return rhs == 0 ? lhs : lhs / rhs
        }
    }
}

extension CalculatorOperator {
    var symbol: String {
        switch self {
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        }
    }
}

