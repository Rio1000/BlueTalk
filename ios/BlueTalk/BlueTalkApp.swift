import SwiftUI

@main
struct BlueTalkApp: App {

    @StateObject private var store: ChatStore
    @StateObject private var bluetooth: BluetoothManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ChatStore()
        _store = StateObject(wrappedValue: store)
        _bluetooth = StateObject(wrappedValue: BluetoothManager(store: store))
        LocalNotifications.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            // Flush any debounced changes before the app leaves the foreground.
            if phase != .active { store.flush() }
        }
    }
}

/// Shows onboarding until the user has picked a display name, then the app.
private struct RootView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        if store.hasChosenName {
            ConversationsView()
        } else {
            OnboardingNameView()
        }
    }
}
