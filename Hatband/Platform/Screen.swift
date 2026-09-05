import UIKit

/// Brightness while a QR is shown, and whether the screen is being captured.
/// Reads the foreground window scene's screen, never `UIScreen.main`.
@MainActor enum Screen {
    private static var saved: CGFloat?

    static func raiseBrightness() {
        guard let screen = foregroundScreen else { return }
        if saved == nil {
            saved = screen.brightness
        }
        screen.brightness = 1
    }

    static func restoreBrightness() {
        guard let previous = saved else { return }
        saved = nil
        foregroundScreen?.brightness = previous
    }

    static var isCaptured: Bool {
        foregroundScreen?.isCaptured ?? false
    }

    private static var foregroundScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen
    }
}
