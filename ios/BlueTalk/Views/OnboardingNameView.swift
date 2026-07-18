import SwiftUI

struct OnboardingNameView: View {

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var name = ""
    @State private var glowPhase: CGFloat = 0

    var body: some View {
        ZStack {
            MeshBackground()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0x6366F1).opacity(0.3), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(1 + sin(glowPhase) * 0.1)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(BlueTalkTheme.accentGradient)
                }
                .shadow(color: Color(hex: 0x6366F1).opacity(0.4), radius: 30)
                Text("Welcome to BlueTalk")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("What should people see when you message them nearby?")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                TextField("Your name", text: $name)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .submitLabel(.done)
                    .padding(.horizontal, 40)
                Button {
                    store.chooseName(name)
                    bluetooth.displayNameChanged(store.displayName)
                } label: {
                    Text("Continue")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(BlueTalkTheme.accentGradient)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white.opacity(0.1))
                                )
                        )
                        .shadow(color: Color(hex: 0x6366F1).opacity(0.5), radius: 12, y: 4)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .padding(.horizontal, 40)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            name = store.displayName
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                glowPhase = .pi
            }
        }
    }
}
