import SwiftUI

@main
struct BlueTalkApp: App {

    @StateObject private var store: ChatStore
    @StateObject private var bluetooth: BluetoothManager

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
