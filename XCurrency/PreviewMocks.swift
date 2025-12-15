import Foundation
import SwiftData

#if DEBUG
enum PreviewMocks {
    /// Готовый набор курсов для SwiftUI превью.
    static let rates: [String: Double] = [
        "USD": 1.0,
        "EUR": 0.92,
        "GBP": 0.79,
        "RUB": 88.3,
        "KZT": 470.0,
        "VND": 24500.0,
        "BTC": 0.000016,
        "ETH": 0.00025,
        "USDT": 1.0,
        "USDC": 1.0,
        "SOL": 0.0083,
        "TON": 0.9
    ]

    static let selection: [String] = ["USD", "EUR", "RUB", "BTC", "ETH", "USDT"]

    static func makeContext() -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: StoredRate.self, configurations: configuration)
        return ModelContext(container)
    }

    static func makeViewModel() -> RateViewModel {
        let ctx = makeContext()
        let vm = RateViewModel(
            context: ctx,
            fetcher: MockRateFetcher(),
            initialRates: rates,
            autoRefresh: false,
            startTicker: false
        )
        vm.updateSelection(selection)
        return vm
    }
}

struct MockRateFetcher: RateFetching {
    func fetchAll(for currencyCodes: [String], includeFiat: Bool, includeCrypto: Bool) async throws -> RateFetchResult {
        // Имитация сетевой задержки
        let delayMs = UInt64(Int.random(in: 120...600))
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)

        // Вероятность ошибок по отдельности для фиата и крипты
        let fiatFail = Bool.random() && Bool.random() // ~25%
        let cryptoFail = Bool.random() && Bool.random() // ~25%

        if includeFiat && fiatFail {
            throw NSError(domain: "MockFiatAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Fiat API error"])
        }
        if includeCrypto && cryptoFail {
            throw NSError(domain: "MockCryptoAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Crypto API error"])
        }

        let filtered = currencyCodes.reduce(into: [String: Double]()) { result, code in
            if let value = PreviewMocks.rates[code] {
                result[code] = value
            }
        }
        let now = Date()
        let fiatTs = includeFiat ? now : nil
        let cryptoTs = includeCrypto ? now : nil
        return (filtered, fiatTs, cryptoTs, now)
    }
}
#endif
