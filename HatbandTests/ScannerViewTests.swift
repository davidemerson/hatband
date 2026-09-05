import Foundation
import Testing
import UIKit
import VisionKit
@testable import Hatband

/// The scanner starts from its host's `viewDidAppear`, once in a window,
/// and refusals reach the sheet once.
@MainActor struct ScannerViewTests {
    /// The host owns the scanner as a child and fires `onAppear` from
    /// `viewDidAppear`, never from loading the view.
    @Test func hostFiresOnAppearOnceInAWindow() {
        let child = UIViewController()
        let host = ScannerHost(child: child)
        var appearances = 0
        host.onAppear = { appearances += 1 }
        host.loadViewIfNeeded()
        #expect(child.parent === host)
        #expect(child.view.superview === host.view)
        #expect(appearances == 0)
        host.viewDidAppear(false)
        #expect(appearances == 1)
        host.viewDidAppear(false)
        #expect(appearances == 2)
    }

    /// One report, whatever comes after it, and a start after a report
    /// does nothing. The simulator has no scanner, so starting either
    /// refuses (reported once) or idles; either way one report in all.
    @Test func coordinatorReportsOnceAndStartsIdempotently() {
        var reported: [String] = []
        let coordinator = ScannerView.Coordinator(onScan: { _ in }, onUnavailable: { reported.append(ScanView.unavailableText($0)) })
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        coordinator.start(scanner)
        coordinator.start(scanner)
        #expect(reported.count <= 1)
        coordinator.report(CocoaError(.fileNoSuchFile))
        coordinator.report(CocoaError(.fileNoSuchFile))
        #expect(reported.count == 1)
        #expect(coordinator.finished)
        #expect(reported.first?.hasSuffix("Pick a photo of the code instead.") == true)
        coordinator.start(scanner)
        #expect(reported.count == 1)
        scanner.stopScanning()
    }
}
