import SwiftUI

@main
struct MythicApp: App {
    init() {
        // Register MetalLayer with DXMT display shim immediately on app start
        mythic_display_set_layer(MetalHostView.shared.metalLayer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
