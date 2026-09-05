import SwiftUI
import UIKit
import VisionKit

/// `DataScannerViewController` limited to QR codes, as the child of a
/// controller of our own: scanning starts from its `viewDidAppear`, once
/// the camera view is in a window, so a refusal then is a real one. The
/// first payload wins and scanning stops on it; an unavailable camera is
/// reported once.
@MainActor struct ScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onUnavailable: (any Error) -> Void

    init(onScan: @escaping (String) -> Void, onUnavailable: @escaping (any Error) -> Void) {
        self.onScan = onScan
        self.onUnavailable = onUnavailable
    }

    func makeUIViewController(context: Context) -> ScannerHost {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        let coordinator = context.coordinator
        scanner.delegate = coordinator
        coordinator.scanner = scanner
        let host = ScannerHost(child: scanner)
        host.onAppear = { [weak coordinator, weak scanner] in
            guard let coordinator, let scanner else { return }
            coordinator.start(scanner)
        }
        return host
    }

    /// Nothing to push down: the host starts scanning when it appears.
    func updateUIViewController(_ host: ScannerHost, context: Context) {}

    static func dismantleUIViewController(_ host: ScannerHost, coordinator: Coordinator) {
        coordinator.scanner?.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onUnavailable: onUnavailable)
    }

    /// `DataScannerViewControllerDelegate` is main-actor isolated, as is
    /// this coordinator.
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private(set) var finished = false
        var scanner: DataScannerViewController?
        private let onScan: (String) -> Void
        private let onUnavailable: (any Error) -> Void

        init(onScan: @escaping (String) -> Void, onUnavailable: @escaping (any Error) -> Void) {
            self.onScan = onScan
            self.onUnavailable = onUnavailable
        }

        /// From the host's `viewDidAppear`, which can come more than once:
        /// idempotent, and never after a payload. A throw here is a real
        /// refusal, since the view is on screen.
        func start(_ scanner: DataScannerViewController) {
            guard !finished, !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
            } catch {
                report(error)
            }
        }

        func report(_ error: any Error) {
            guard !finished else { return }
            finished = true
            onUnavailable(error)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                finished = true
                dataScanner.stopScanning()
                onScan(payload)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            report(error)
        }
    }
}

/// A plain container: the scanner is its child, filling its view, and
/// `onAppear` fires from `viewDidAppear`, when the child's view is in a
/// window and the camera may start.
@MainActor final class ScannerHost: UIViewController {
    let child: UIViewController
    var onAppear: (@MainActor () -> Void)?

    init(child: UIViewController) {
        self.child = child
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}
