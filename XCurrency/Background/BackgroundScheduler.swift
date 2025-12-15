import Foundation
import BackgroundTasks
import SwiftData

/// Планировщик фоновых обновлений через BGAppRefreshTask.
final class BackgroundScheduler {
    private let taskIdentifier = "RUGyron.xcurrency.refresh"
    private let fetcher = RateFetcher()

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            self.handle(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // минимум раз в ~15 минут
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        let operation = Task {
            await self.performRefresh()
            if !Task.isCancelled {
                task.setTaskCompleted(success: true)
            }
        }

        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    @MainActor
    private func performRefresh() async {
        guard let container = try? ModelContainer(for: StoredRate.self) else { return }
        let store = RateStore(context: ModelContext(container))

        let codes = Currency.defaultSelection
        do {
            let result = try await fetcher.fetchAll(for: codes, includeFiat: true, includeCrypto: true)
            store.persist(result.rates, timestamp: result.combinedTimestamp)
        } catch {
            // Тихий fallback: офлайн данные остаются старыми
        }
    }
}

