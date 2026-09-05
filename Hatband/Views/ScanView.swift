import Accessibility
import HatbandCore
import PhotosUI
import SwiftUI
import UIKit
import Vision
import VisionKit

/// The scan sheet: the camera when the data scanner is supported and
/// available, a photo otherwise; a photo is always offered for screenshots.
/// The payload reaches the model after the sheet is gone, so the review
/// sheet never competes with this one.
@MainActor struct ScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var permission: Bool?
    @State private var photoItem: PhotosPickerItem?
    @State private var foundText: String?
    @State private var foundSource = CardSource.scan
    @State private var recognitions = 0
    @State private var problem: String?

    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("From photo", systemImage: "photo")
                        }
                    }
                }
        }
        .task {
            permission = await CameraPermission.ensure()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                await scan(item)
            }
        }
        .sensoryFeedback(.success, trigger: recognitions)
        .onDisappear {
            if let foundText {
                deliver(foundText, source: foundSource)
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 16) {
            switch permission {
            case nil:
                ProgressView()
            case false?:
                denied
            case true?:
                if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    ScannerView(onScan: { recognised($0, source: .scan) },
                                onUnavailable: { problem = ScanView.unavailableText($0) })
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.tertiary)
                    Text("The camera scanner is not available here. Pick a photo of the code instead.")
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private var denied: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.largeTitle)
                .foregroundStyle(Theme.tertiary)
            Text("Hatband uses the camera only to read a card's QR code.")
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Allow the camera in Settings", destination: url)
            }
            Text("Or pick a photo of the code.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func recognised(_ text: String, source: CardSource) {
        guard foundText == nil else { return }
        foundText = text
        foundSource = source
        recognitions += 1
        AccessibilityNotification.Announcement("Card found").post()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }
    }

    private func deliver(_ text: String, source: CardSource) {
        do {
            try model.receive(text: text, source: source)
        } catch {
            model.error = AppError(error)
        }
    }

    /// `DetectBarcodesRequest` over the picked image, QR only.
    private func scan(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                problem = "That photo could not be read."
                return
            }
            var request = DetectBarcodesRequest()
            request.symbologies = [.qr]
            let observations = try await request.perform(on: data, orientation: nil)
            guard let payload = observations.compactMap({ $0.payloadString }).first else {
                problem = "No QR code in that photo."
                return
            }
            recognised(payload, source: .photo)
        } catch {
            problem = "That photo could not be read."
        }
    }

    /// What the sheet says when the data scanner cannot run. The photo
    /// path is always open, so every line ends by pointing at it.
    nonisolated static func unavailableText(_ error: any Error) -> String {
        let photo = " Pick a photo of the code instead."
        if let reason = error as? DataScannerViewController.ScanningUnavailable {
            switch reason {
            case .cameraRestricted:
                return "The camera is restricted on this iPhone." + photo
            case .unsupported:
                return "The camera scanner is not available here." + photo
            @unknown default:
                break
            }
        }
        return "The camera could not start." + photo
    }
}
