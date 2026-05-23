import AppKit
import SwiftUI

@available(macOS 15.0, *)
struct PhoneVMApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("PhoneVM", systemImage: "rectangle.stack.badge.play") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}
