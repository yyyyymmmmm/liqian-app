import SwiftUI
import LiqianDesign

/// iOS 26 原生 Tab：玻璃底栏由系统提供，不做自定义栏（skill 口径）
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("礼簿", systemImage: "book.closed") {
                LedgersView()
            }
            Tab("人情", systemImage: "person.2") {
                PeopleView()
            }
            Tab("我的", systemImage: "person.crop.circle") {
                MeView()
            }
        }
        .tint(Palette.primary)
    }
}
