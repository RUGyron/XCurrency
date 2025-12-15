import Foundation
import SwiftData

@Model
final class StoredRate {
    @Attribute(.unique) var code: String
    var unitsPerUSD: Double
    var updatedAt: Date

    init(code: String, unitsPerUSD: Double, updatedAt: Date) {
        self.code = code
        self.unitsPerUSD = unitsPerUSD
        self.updatedAt = updatedAt
    }
}

