import Combine
import SwiftUI

/// Branded splash screen shown while the dsh host process is starting.
struct StartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var isFloating = false
    @State private var ringPulse = false
    @State private var dotsBounce = false
    @State private var messageIndex = 0

    private let messages = [
        "Starting Ozyune…",
        "Waking up the whale…",
        "Starting dsh web…",
        "Polishing the waves…",
    ]

    private let messageTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    /// Primary blue sampled from the Ozyune logo.
    private let brandBlue = Color(red: 0.22, green: 0.45, blue: 0.93)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 24) {
                logoBadge

                VStack(spacing: 14) {
                    statusText
                    loadingDots
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: startAnimations)
        .onReceive(messageTimer) { _ in advanceMessage() }
    }

    // MARK: - Subviews

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [brandBlue.opacity(0.10), brandBlue.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [brandBlue.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 190
                    )
                )
                .frame(width: 380, height: 380)
        }
        .ignoresSafeArea()
    }

    private var logoBadge: some View {
        ZStack {
            if !reduceMotion {
                rippleRings
            }

            Image("OzyuneLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .shadow(color: brandBlue.opacity(0.35), radius: 24, x: 0, y: 12)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.65)
                .scaleEffect(isFloating ? 1.03 : 1)
                .offset(y: isFloating ? -5 : 5)
                .animation(
                    .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                    value: isFloating
                )
        }
    }

    private var rippleRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(brandBlue.opacity(0.30), lineWidth: 2)
                    .frame(width: 168, height: 168)
                    .scaleEffect(ringPulse ? 1.5 : 0.6)
                    .opacity(ringPulse ? 0 : 0.55)
                    .animation(
                        .easeOut(duration: 2.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.85),
                        value: ringPulse
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var statusText: some View {
        ZStack {
            Text(messages[reduceMotion ? 0 : messageIndex])
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .id(messageIndex)
                .transition(.opacity)
        }
        .frame(height: 20)
    }

    private var loadingDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(brandBlue)
                    .frame(width: 7, height: 7)
                    .offset(y: dotsBounce ? -5 : 0)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: dotsBounce
                    )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Animations

    private func startAnimations() {
        if reduceMotion {
            appeared = true
            return
        }

        withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
            appeared = true
        }
        isFloating = true
        ringPulse = true
        dotsBounce = true
    }

    private func advanceMessage() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            messageIndex = (messageIndex + 1) % messages.count
        }
    }
}

#Preview {
    StartupView()
        .frame(width: 900, height: 600)
}
