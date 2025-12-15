import Foundation

typealias RateFetchResult = (rates: [String: Double], fiatTimestamp: Date?, cryptoTimestamp: Date?, combinedTimestamp: Date)

protocol RateFetching {
    func fetchAll(for currencyCodes: [String], includeFiat: Bool, includeCrypto: Bool) async throws -> RateFetchResult
}

/// Получает свежие курсы. Бесплатные источники:
/// - Fiat: open.er-api.com (бесплатно, без ключа)
/// - Crypto: api.coingecko.com/simple/price
struct RateFetcher: RateFetching {
    // Порядок опроса фиата: несколько публичных бесплатных API без ключа
    private let fiatEndpoints: [URL] = [
        URL(string: "https://api.exchangerate.host/latest?base=USD")!,
        URL(string: "https://api.frankfurter.app/latest?from=USD")!,
        URL(string: "https://open.er-api.com/v6/latest/USD")!
    ]

    private let cryptoMapping: [String: String] = [
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "USDT": "tether",
        "USDC": "usd-coin",
        "DAI": "dai",
        "BUSD": "binance-usd",
        "TUSD": "true-usd",
        "USDP": "paxos-standard",
        "GUSD": "gemini-dollar",
        "FDUSD": "first-digital-usd",
        "SOL": "solana",
        "BNB": "binancecoin",
        "DOGE": "dogecoin",
        "TON": "the-open-network",
        "LTC": "litecoin",
        "ADA": "cardano",
        "XRP": "ripple"
    ]

    func fetchAll(for currencyCodes: [String], includeFiat: Bool, includeCrypto: Bool) async throws -> RateFetchResult {
        print("RateFetcher: start fetchAll, codes=\(currencyCodes), fiat=\(includeFiat), crypto=\(includeCrypto)")

        let fiatNeeded = Set(currencyCodes) // тянем только нужные фиат-коды
        async let fiat = includeFiat ? fetchFiatRates(neededCodes: fiatNeeded) : (rates: [String: Double](), timestamp: Date.distantPast)
        async let crypto = includeCrypto ? fetchCryptoRates(codes: currencyCodes.filter { cryptoMapping[$0] != nil }) : (rates: [String: Double](), timestamp: Date.distantPast)

        let (fiatResult, cryptoResult) = try await (fiat, crypto)

        var combined = fiatResult.rates
        combined.merge(cryptoResult.rates) { _, new in new }

        // Всегда держим USD как 1:1
        combined["USD"] = 1.0

        let ts = max(fiatResult.timestamp, cryptoResult.timestamp)
        print("RateFetcher: fetched fiat=\(fiatResult.rates.count) crypto=\(cryptoResult.rates.count) timestamp=\(ts)")
        return (combined, includeFiat ? fiatResult.timestamp : nil, includeCrypto ? cryptoResult.timestamp : nil, ts)
    }

    private func fetchFiatRates(neededCodes: Set<String>) async throws -> (rates: [String: Double], timestamp: Date) {
        var lastError: Error?
        var aggregated: [String: Double] = [:]
        var timestamp = Date.distantPast

        for url in fiatEndpoints {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let parsed = try parseFiat(data: data, host: url.host ?? "")
                print("RateFetcher: fiat success host=\(url.host ?? "unknown") rates=\(parsed.count)")
                aggregated.merge(parsed) { _, new in new }
                timestamp = max(timestamp, Date())
                // Если закрыли все нужные коды, выходим
                let covered = neededCodes.allSatisfy { aggregated[$0] != nil } || neededCodes.isEmpty
                if covered {
                    return (aggregated, timestamp)
                }
            } catch {
                lastError = error
                print("RateFetcher: fiat failed host=\(url.host ?? "unknown") error=\(error)")
            }
        }
        if !aggregated.isEmpty {
            return (aggregated, timestamp == .distantPast ? Date() : timestamp)
        }
        throw lastError ?? URLError(.cannotFindHost)
    }

    private func fetchCryptoRates(codes: [String]) async throws -> (rates: [String: Double], timestamp: Date) {
        guard !codes.isEmpty else {
            return ([:], Date())
        }

        let ids = codes.compactMap { cryptoMapping[$0] }
        let joinedIds = ids.joined(separator: ",")
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(joinedIds)&vs_currencies=usd")!

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: data)

        var result: [String: Double] = [:]
        for (code, id) in cryptoMapping {
            guard ids.contains(id),
                  let priceUSD = decoded[id]?["usd"],
                  priceUSD > 0 else { continue }
            // priceUSD = сколько USD за 1 монету -> unitsPerUSD = 1 / priceUSD
            result[code] = 1.0 / priceUSD
        }
        let ts = Date()
        print("RateFetcher: crypto success, codes=\(result.keys)")
        return (result, ts)
    }
}

private func parseFiat(data: Data, host: String) throws -> [String: Double] {
    switch host {
    case "api.exchangerate.host":
        struct Response: Decodable { let base: String; let date: String; let rates: [String: Double] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.rates
    case "api.frankfurter.app":
        struct Response: Decodable { let amount: Double; let base: String; let date: String; let rates: [String: Double] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.rates
    case "open.er-api.com":
        struct Response: Decodable { let result: String; let rates: [String: Double] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.rates
    default:
        throw URLError(.badServerResponse)
    }
}

