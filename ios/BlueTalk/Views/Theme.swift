import SwiftUI

enum BlueTalkTheme {

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x6366F1), Color(hex: 0x8B5CF6), Color(hex: 0xA855F7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.15),
            Color.white.opacity(0.05),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let meshColors: [Color] = [
        Color(hex: 0x1E1B4B),
        Color(hex: 0x312E81),
        Color(hex: 0x1E1B4B),
        Color(hex: 0x0F172A),
        Color(hex: 0x1E293B),
        Color(hex: 0x0F172A),
    ]

    static let sendBubbleGradient = LinearGradient(
        colors: [Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let avatarGradients: [[Color]] = [
        [Color(hex: 0x6366F1), Color(hex: 0xA855F7)],
        [Color(hex: 0x06B6D4), Color(hex: 0x3B82F6)],
        [Color(hex: 0xEC4899), Color(hex: 0xF43F5E)],
        [Color(hex: 0xF59E0B), Color(hex: 0xEF4444)],
        [Color(hex: 0x10B981), Color(hex: 0x06B6D4)],
        [Color(hex: 0x8B5CF6), Color(hex: 0xEC4899)],
        [Color(hex: 0x3B82F6), Color(hex: 0x10B981)],
        [Color(hex: 0xF43F5E), Color(hex: 0xF59E0B)],
    ]
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(BlueTalkTheme.surfaceGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.05),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

struct MeshBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Color(hex: 0x0F0B1E)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x6366F1).opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: w * 0.5
                        )
                    )
                    .frame(width: w * 0.8, height: w * 0.8)
                    .offset(x: w * 0.1 + sin(phase) * 20, y: h * 0.05 + cos(phase) * 15)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x8B5CF6).opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: w * 0.6
                        )
                    )
                    .frame(width: w * 0.9, height: w * 0.9)
                    .offset(x: -w * 0.1 + cos(phase * 0.7) * 15, y: h * 0.5 + sin(phase * 0.7) * 20)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x06B6D4).opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: w * 0.4
                        )
                    )
                    .frame(width: w * 0.6, height: w * 0.6)
                    .offset(x: w * 0.4 + sin(phase * 1.3) * 10, y: h * 0.7 + cos(phase * 1.3) * 10)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
