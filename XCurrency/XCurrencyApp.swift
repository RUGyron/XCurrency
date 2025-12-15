import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct CurrencyCalcApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let backgroundScheduler = BackgroundScheduler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    backgroundScheduler.register()
                    backgroundScheduler.scheduleAppRefresh()
                }
        }
        .modelContainer(for: [StoredRate.self])
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                backgroundScheduler.scheduleAppRefresh()
            }
        }
    }
}
