import CoreMotion
import QuartzCore
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

/// Simulates the three background orbs as independent bodies. Each has its
/// own mass, so the phone's tilt (read from Core Motion) accelerates them by
/// different amounts, and its own slow autonomous wander so they drift apart
/// and roam the whole screen. Heavy damping keeps everything slow and viscous.
///
/// A single shared instance drives one `CADisplayLink` and one
/// `CMMotionManager`, since `MeshBackground` appears on several screens.
final class MeshMotion: ObservableObject {
    static let shared = MeshMotion()

    struct Orb: Identifiable {
        let id: Int
        /// Center position in normalised screen space (0...1 on each axis).
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        /// Heavier orbs accelerate less, so they lag and feel weightier.
        let mass: CGFloat
        let driftFreqX: CGFloat
        let driftFreqY: CGFloat
        let driftPhaseX: CGFloat
        let driftPhaseY: CGFloat
    }

    @Published private(set) var orbs: [Orb]

    private let manager = CMMotionManager()
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var elapsed: CGFloat = 0
    private var tiltX: CGFloat = 0
    private var tiltY: CGFloat = 0
    private var running = false

    private init() {
        orbs = [
            Orb(id: 0, x: 0.28, y: 0.24, mass: 0.6, driftFreqX: 0.031, driftFreqY: 0.043, driftPhaseX: 0.0, driftPhaseY: 1.7),
            Orb(id: 1, x: 0.72, y: 0.52, mass: 1.1, driftFreqX: 0.023, driftFreqY: 0.018, driftPhaseX: 2.1, driftPhaseY: 0.6),
            Orb(id: 2, x: 0.44, y: 0.80, mass: 2.0, driftFreqX: 0.013, driftFreqY: 0.027, driftPhaseX: 4.0, driftPhaseY: 3.2),
        ]
    }

    func start() {
        guard !running else { return }
        running = true
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 30.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.tiltX = max(-1, min(1, CGFloat(motion.attitude.roll) / (.pi / 4)))
                self.tiltY = max(-1, min(1, CGFloat(motion.attitude.pitch) / (.pi / 4)))
            }
        }
        lastTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var dt = CGFloat(now - lastTime)
        lastTime = now
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }   // ignore hitches / resumes
        elapsed += dt

        let damping = CGFloat(pow(0.5, Double(dt) / 1.6))   // ~1.6s half-life
        let tiltStrength: CGFloat = 0.05                    // gentle push
        let wanderStrength: CGFloat = 0.015
        let maxSpeed: CGFloat = 0.35

        var next = orbs
        for i in next.indices {
            var o = next[i]
            let wx = CGFloat(cos(Double(elapsed) * Double(o.driftFreqX) * 2 * .pi + Double(o.driftPhaseX)))
            let wy = CGFloat(sin(Double(elapsed) * Double(o.driftFreqY) * 2 * .pi + Double(o.driftPhaseY)))
            // Acceleration from tilt + autonomous wander, scaled by 1/mass.
            let ax = (tiltX * tiltStrength + wx * wanderStrength) / o.mass
            let ay = (tiltY * tiltStrength + wy * wanderStrength) / o.mass
            o.vx = min(maxSpeed, max(-maxSpeed, (o.vx + ax * dt) * damping))
            o.vy = min(maxSpeed, max(-maxSpeed, (o.vy + ay * dt) * damping))
            o.x += o.vx * dt
            o.y += o.vy * dt
            // Soft bounce so each orb stays on screen but roams edge to edge.
            if o.x < 0 { o.x = 0; o.vx = abs(o.vx) * 0.6 }
            if o.x > 1 { o.x = 1; o.vx = -abs(o.vx) * 0.6 }
            if o.y < 0 { o.y = 0; o.vy = abs(o.vy) * 0.6 }
            if o.y > 1 { o.y = 1; o.vy = -abs(o.vy) * 0.6 }
            next[i] = o
        }
        orbs = next
    }
}

struct MeshBackground: View {
    @ObservedObject private var motion = MeshMotion.shared

    /// Per-orb colour, fill opacity, diameter (× width) and gradient radius.
    private let styles: [(color: UInt, opacity: Double, size: CGFloat, radius: CGFloat)] = [
        (0x6366F1, 0.30, 0.80, 0.50),
        (0x8B5CF6, 0.25, 0.90, 0.60),
        (0x06B6D4, 0.15, 0.60, 0.40),
    ]

    var body: some View {
        ZStack {
            Color(hex: 0x0F0B1E)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ForEach(motion.orbs) { orb in
                    let style = styles[orb.id]
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: style.color).opacity(style.opacity), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: w * style.radius
                            )
                        )
                        .frame(width: w * style.size, height: w * style.size)
                        .position(x: orb.x * w, y: orb.y * h)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { motion.start() }
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
