import AVFoundation
import Foundation

/// Camera access for the scanner: the current status first, the system
/// prompt only when it has never been shown.
nonisolated enum CameraPermission {
    static func ensure() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
