import SwiftUI

@main
struct BlueTalkApp: App {

    @StateObject private var store: ChatStore
    @StateObject private var bluetooth: BluetoothManager

    init() {
        let store = ChatStore()
        _store = StateObject(wrappedValue: store)
        _bluetooth = StateObject(wrappedValue: BluetoothManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView()
                .environmentObject(store)
                .environmentObject(bluetooth)
        }
    }
}
