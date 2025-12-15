import Foundation

enum CurrencyKind: String, CaseIterable, Codable {
    case fiat
    case crypto
}

struct Currency: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    let kind: CurrencyKind

    var id: String { code }

    var displayName: String {
        if let custom = CurrencyLoader.cryptoNames[code] {
            return custom
        }
        let locale = Locale(identifier: "ru_RU")
        if let localized = locale.localizedString(forCurrencyCode: code) {
            return Currency.capitalizeFirst(localized)
        }
        return name
    }

    static let defaultSelection: [String] = ["USD", "EUR", "RUB", "BTC", "ETH", "USDT"]

    static let all: [Currency] = CurrencyLoader.loadAll()

    static func lookup(code: String) -> Currency? {
        all.first { $0.code == code }
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

private enum CurrencyLoader {
    // Минимальный набор локализованных названий для крипты.
    static let cryptoNames: [String: String] = [
        "BTC": "Биткоин",
        "ETH": "Эфир",
        "USDT": "Tether USD",
        "USDC": "USD Coin",
        "DAI": "DAI",
        "BUSD": "Binance USD",
        "TUSD": "TrueUSD",
        "USDP": "Pax Dollar",
        "GUSD": "Gemini Dollar",
        "FDUSD": "First Digital USD",
        "SOL": "Солана",
        "BNB": "BNB",
        "DOGE": "Доджкоин",
        "TON": "TON",
        "LTC": "Лайткоин",
        "ADA": "Cardano",
        "XRP": "XRP"
    ]

    static func loadAll() -> [Currency] {
        if let url = Bundle.main.url(forResource: "Currencies", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Currency].self, from: data) {
            return decoded.sorted { $0.code < $1.code }
        }
        return fallback
    }

    private static let fallback: [Currency] = [
        Currency(code: "USD", name: "US Dollar", kind: .fiat),
        Currency(code: "EUR", name: "Euro", kind: .fiat),
        Currency(code: "GBP", name: "British Pound", kind: .fiat),
        Currency(code: "CHF", name: "Swiss Franc", kind: .fiat),
        Currency(code: "JPY", name: "Japanese Yen", kind: .fiat),
        Currency(code: "CNY", name: "Chinese Yuan", kind: .fiat),
        Currency(code: "RUB", name: "Russian Ruble", kind: .fiat),
        Currency(code: "AED", name: "UAE Dirham", kind: .fiat),
        Currency(code: "TRY", name: "Turkish Lira", kind: .fiat),
        Currency(code: "KZT", name: "Kazakhstani Tenge", kind: .fiat),
        Currency(code: "UAH", name: "Ukrainian Hryvnia", kind: .fiat),
        Currency(code: "PLN", name: "Polish Zloty", kind: .fiat),
        Currency(code: "BTC", name: "Bitcoin", kind: .crypto),
        Currency(code: "ETH", name: "Ethereum", kind: .crypto),
        Currency(code: "USDT", name: "Tether", kind: .crypto),
        Currency(code: "USDC", name: "USD Coin", kind: .crypto),
        Currency(code: "DAI", name: "Dai", kind: .crypto)
    ]
}

