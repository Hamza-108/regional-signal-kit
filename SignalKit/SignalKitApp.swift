import SwiftUI

@main struct SignalKitApp: App {
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { if phase != .active { Color(.systemBackground).ignoresSafeArea().overlay { Label("Signal Kit", systemImage: "waveform.path") } } }
        }
    }
}
