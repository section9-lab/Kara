import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class CursorCompanionModel {
    /// The smoothly-interpolated position the view reads each frame.
    var cursorPosition: CGPoint = .zero

    var isBlinking: Bool = false
    var screenSize: CGSize = CGSize(width: 1920, height: 1080)

    /// True while the cursor is physically on this screen.
    var wasActive: Bool = false

    // Raw target set by the controller (not yet lerped)
    private var targetX: CGFloat = 0
    private var targetY: CGFloat = 0

    private var blinkTask: Task<Void, Never>?
    private var lerpTask: Task<Void, Never>?
    private var floatPhase: Double = 0

    var floatOffset: CGFloat {
        CGFloat(sin(floatPhase) * 2.5)
    }

    // MARK: - Public API called by ScreenCompanionMonitor

    func setTarget(x: CGFloat, y: CGFloat) {
        targetX = x
        targetY = y
    }

    /// Instantly jump the rendered position to the current target (no interpolation).
    func snapToTarget() {
        cursorPosition = CGPoint(x: targetX, y: targetY)
    }

    // MARK: - Lifecycle

    func startAnimations() {
        startBlinking()
        startLerp()
        startFloat()
    }

    func stopAnimations() {
        blinkTask?.cancel()
        blinkTask = nil
        lerpTask?.cancel()
        lerpTask = nil
    }

    // MARK: - Per-frame lerp (replaces SwiftUI spring animation)

    /// Runs at ~60 fps. Each tick moves `cursorPosition` 18 % closer to the target.
    /// This gives a smooth trailing effect with zero animation-state issues across screens.
    private func startLerp() {
        lerpTask = Task { [weak self] in
            let factor: CGFloat = 0.18
            let threshold: CGFloat = 0.4
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))   // ~60 fps
                guard let self, !Task.isCancelled else { return }

                let dx = self.targetX - self.cursorPosition.x
                let dy = self.targetY - self.cursorPosition.y

                if abs(dx) < threshold && abs(dy) < threshold {
                    self.cursorPosition = CGPoint(x: self.targetX, y: self.targetY)
                } else {
                    self.cursorPosition = CGPoint(
                        x: self.cursorPosition.x + dx * factor,
                        y: self.cursorPosition.y + dy * factor
                    )
                }
            }
        }
    }

    // MARK: - Cosmetic animations

    private func startBlinking() {
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = Double.random(in: 2.5...5.0)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.isBlinking = true
                try? await Task.sleep(for: .milliseconds(150))
                self?.isBlinking = false
            }
        }
    }

    private func startFloat() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                self.floatPhase += 0.12
            }
        }
    }
}
