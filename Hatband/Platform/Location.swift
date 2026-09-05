import CoreLocation
import Foundation

/// One coarse fix: reduced accuracy, one `requestLocation()`, nil after
/// 20 seconds or when permission is refused. Asks for when-in-use
/// permission only when it has never been asked.
nonisolated enum Location {
    static let timeout: Duration = .seconds(20)

    static func coarseFix() async -> Fix? {
        let request = await OneShotLocation()
        return await request.fix()
    }
}

nonisolated extension Fix {
    /// `Fix.init(latitude:longitude:accuracy:)` does the rounding.
    init(location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  accuracy: max(0, location.horizontalAccuracy))
    }
}

/// Owns the manager for one request. The delegate is not main-actor
/// annotated, so its methods hop back explicitly; the manager was made on
/// the main thread and calls them there.
@MainActor private final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Fix?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requested = false

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
    }

    func fix() async -> Fix? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Location.timeout)
                self?.finish(nil)
            }
            self.proceed(with: manager.authorizationStatus)
        }
    }

    private func proceed(with status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !requested else { return }
            requested = true
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        @unknown default:
            finish(nil)
        }
    }

    /// Resumes once; later calls are no-ops.
    private func finish(_ fix: Fix?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        manager.delegate = nil
        continuation.resume(returning: fix)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            self.proceed(with: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.map { Fix(location: $0) }
        MainActor.assumeIsolated {
            self.finish(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            self.finish(nil)
        }
    }
}
