import SwiftData
import SwiftUI
import LiqianCore

@main
struct LiqianApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Ledger.self, GiftRecord.self])
    }
}
