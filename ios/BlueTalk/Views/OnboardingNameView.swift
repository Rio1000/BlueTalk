import SwiftUI

/// First-run screen that asks the user for the name peers will see.
struct OnboardingNameView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var name = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 52))
                .foregroundStyle(.blue)
            Text("Welcome to BlueTalk")
                .font(.title.bold())
            Text("What should people see when you message them nearby?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .padding(.horizontal, 40)
            Button {
                store.chooseName(name)
                bluetooth.displayNameChanged(store.displayName)
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 40)
            Spacer()
        }
        .onAppear { name = store.displayName }
    }
}
