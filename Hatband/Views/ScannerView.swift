import SwiftUI
import UIKit
import VisionKit

/// `DataScannerViewController` limited to QR codes. The first payload wins
/// and scanning stops on it; an unavailable camera is reported once.
@MainActor struct ScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onUnavailable: (any Error) -> Void

    init(onScan: @escaping (String) -> Void, onUnavailable: @escaping (any Error) -> Void) {
        self.onScan = onScan
        self.onUnavailable = onUnavailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    /// Starts once the controller is on screen; never after a payload.
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !context.coordinator.finished, !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.report(error)
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onUnavailable: onUnavailable)
    }

    /// `DataScannerViewControllerDelegate` is main-actor isolated, as is
    /// this coordinator.
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private(set) var finished = false
        private let onScan: (String) -> Void
        private let onUnavailable: (any Error) -> Void

        init(onScan: @escaping (String) -> Void, onUnavailable: @escaping (any Error) -> Void) {
            self.onScan = onScan
            self.onUnavailable = onUnavailable
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
