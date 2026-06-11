import SwiftUI

struct CursorCompanionView: View {
    let model: CursorCompanionModel

    private let companionSize: CGFloat = 38
    private let followOffset = CGSize(width: 36, height: -2)

    var body: some View {
        ZStack {
            companionCharacter
                .position(
                    x: model.cursorPosition.x + followOffset.width,
                    y: model.cursorPosition.y + followOffset.height + model.floatOffset
                )
            // No .animation modifier — position is already lerp-smoothed by the model
        }
        .frame(width: model.screenSize.width, height: model.screenSize.height)
        .allowsHitTesting(false)
    }

    private var companionCharacter: some View {
        let pupilOffset = pupilDirection

        return ZStack {
            // Shadow
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 28, height: 8)
                .offset(y: 20)
                .blur(radius: 2)

            // Body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.82, blue: 0.36), Color(red: 1.0, green: 0.68, blue: 0.22)],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 2,
                        endRadius: 22
                    )
                )
                .frame(width: companionSize, height: companionSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                )
                .shadow(color: Color.orange.opacity(0.25), radius: 6, y: 2)

            // Left eye
            eyeView(pupilOffset: pupilOffset)
                .offset(x: -7, y: -3)

            // Right eye
            eyeView(pupilOffset: pupilOffset)
                .offset(x: 7, y: -3)

            // Blush marks
            Circle()
                .fill(Color.pink.opacity(0.22))
                .frame(width: 7, height: 4)
                .blur(radius: 1.5)
                .offset(x: -12, y: 5)

            Circle()
                .fill(Color.pink.opacity(0.22))
                .frame(width: 7, height: 4)
                .blur(radius: 1.5)
                .offset(x: 12, y: 5)

            // Mouth
            mouthView
                .offset(y: 7)

            // Antenna
            antennaView
                .offset(y: -20)
        }
        .frame(width: companionSize + 10, height: companionSize + 24)
    }

    private var mouthView: some View {
        Path { path in
            path.move(to: CGPoint(x: -4, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: 4, y: 0),
                control: CGPoint(x: 0, y: 3.5)
            )
        }
        .stroke(Color.brown.opacity(0.55), lineWidth: 1.2)
        .frame(width: 8, height: 4)
    }

    private var antennaView: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: -4),
                    control: CGPoint(x: 4, y: 0)
                )
            }
            .stroke(Color.orange.opacity(0.6), lineWidth: 1.5)
            .frame(width: 6, height: 10)

            Circle()
                .fill(Color.yellow)
                .frame(width: 5, height: 5)
                .shadow(color: .yellow.opacity(0.5), radius: 3)
                .offset(y: -5)
        }
    }

    private func eyeView(pupilOffset: CGSize) -> some View {
        ZStack {
            // Eye white
            Capsule()
                .fill(Color.white)
                .frame(width: 10, height: model.isBlinking ? 2 : 11)

            if !model.isBlinking {
                // Pupil
                Circle()
                    .fill(Color(red: 0.15, green: 0.12, blue: 0.1))
                    .frame(width: 5, height: 5)
                    .offset(pupilOffset)

                // Eye highlight
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 2)
                    .offset(x: pupilOffset.width + 1.2, y: pupilOffset.height - 1.2)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: model.isBlinking)
    }

    private var pupilDirection: CGSize {
        let maxOffset: CGFloat = 1.8
        let dx = -followOffset.width   // pupil looks back toward cursor
        let dy = -followOffset.height
        let distance = max(sqrt(dx * dx + dy * dy), 1)
        let normalized = min(distance / 150, 1.0)

        return CGSize(
            width: (dx / distance) * maxOffset * normalized,
            height: (dy / distance) * maxOffset * normalized
        )
    }
}
