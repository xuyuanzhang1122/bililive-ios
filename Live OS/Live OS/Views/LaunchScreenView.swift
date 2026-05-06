import SwiftUI

struct LaunchScreenView: View {
    let onComplete: () -> Void

    // Browser slides in from left
    @State private var browserX: CGFloat = -500
    // Phone slides in from right
    @State private var phoneX: CGFloat = 500
    // Lightning strikes downward from top anchor
    @State private var lightningScaleY: CGFloat = 0
    @State private var lightningOpacity: Double = 0
    // Flash overlay on lightning impact
    @State private var flashOpacity: Double = 0
    // Title text
    @State private var titleOpacity: Double = 0
    // Final fade out
    @State private var screenOpacity: Double = 1

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            // Lightning flash
            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)

            VStack(spacing: 44) {
                // Logo assembly
                ZStack(alignment: .center) {
                    // Browser window – behind, left
                    Image("SplashBrowser")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200)
                        .offset(x: browserX + (-44), y: 8)

                    // Phone – front, right
                    Image("SplashPhone")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300)
                        .offset(x: phoneX + 50)

                    // Lightning bolt – center, strikes downward
                    Image("SplashLightning")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150)
                        .offset(x: 4)
                        .scaleEffect(x: 1, y: lightningScaleY, anchor: .top)
                        .opacity(lightningOpacity)
                }
                .frame(height: 210)

                // App name
                VStack(spacing: 7) {
                    Text("哔哩录播")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundStyle(.primary)
                    Text("网页端 · iOS 录播工具")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("bililive")
                        .font(.system(size: 13, weight: .light, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .opacity(titleOpacity)
            }
        }
        .opacity(screenOpacity)
        .onAppear(perform: animate)
    }

    private func animate() {
        // Phase 1 – icons slide in from both sides
        withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
            browserX = 0
            phoneX = 0
        }

        // Phase 2 – lightning strikes downward
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            withAnimation(.easeOut(duration: 0.22)) {
                lightningScaleY = 1
                lightningOpacity = 1
            }
            // Brief white flash
            withAnimation(.easeOut(duration: 0.1)) {
                flashOpacity = 0.25
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 0.18)) {
                    flashOpacity = 0
                }
            }
        }

        // Phase 3 – title fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.54) {
            withAnimation(.easeIn(duration: 0.32)) {
                titleOpacity = 1
            }
        }

        // Phase 4 – fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            withAnimation(.easeInOut(duration: 0.38)) {
                screenOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            onComplete()
        }
    }
}

#Preview {
    LaunchScreenView(onComplete: {})
}
