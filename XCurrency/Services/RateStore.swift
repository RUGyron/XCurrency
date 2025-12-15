import Foundation
import SwiftData

/// Хранит курсы в SwiftData для офлайн-режима.
@MainActor
final class RateStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func persist(_ rates: [String: Double], timestamp: Date) {
        for (code, value) in rates {
            let existing = fetchRate(code: code)
            if let existing {
                existing.unitsPerUSD = value
                existing.updatedAt = timestamp
            } else {
                let new = StoredRate(code: code, unitsPerUSD: value, updatedAt: timestamp)
                context.insert(new)
            }
        }
        try? context.save()
    }

    func fetchAll() -> [StoredRate] {
        let descriptor = FetchDescriptor<StoredRate>()
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchRate(code: String) -> StoredRate? {
        let predicate = #Predicate<StoredRate> { $0.code == code }
        let descriptor = FetchDescriptor<StoredRate>(predicate: predicate, sortBy: [])
        return try? context.fetch(descriptor).first
    }

    var lastUpdated: Date? {
        fetchAll().compactMap { $0.updatedAt }.max()
    }

    func clearAll() {
        let all = fetchAll()
        all.forEach { context.delete($0) }
        try? context.save()
    }
}

