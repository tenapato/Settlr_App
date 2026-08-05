import AVFoundation
import PhotosUI
import SwiftUI

/// Full-screen receipt camera: live preview, a receipt-shaped guide, and one
/// lime shutter in the centre.
///
/// This is a custom capture surface rather than VisionKit's document scanner
/// because that screen is Apple's chrome end to end — no way to put a Settlr
/// glyph on the button. Deskewing (the main thing the system scanner adds) is
/// recovered in `ReceiptOCR`.
struct ReceiptCaptureView: View {
    let onCapture: (UIImage) -> Void
    var onManualEntry: (() -> Void)?
    var onOpenSplits: (() -> Void)?
    /// Shown over the preview while OCR and parsing run.
    var busyMessage: String?
    /// The shot being read, shown under the scan animation.
    var busyImage: UIImage?
    var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var pickerError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .running:
                CameraPreview(controller: camera).ignoresSafeArea()
                guideOverlay
            case .denied:
                unavailableState(ReceiptScanError.cameraDenied.localizedDescription, showSettings: true)
            case .unavailable:
                unavailableState(ReceiptScanError.cameraUnavailable.localizedDescription, showSettings: false)
            case .starting:
                ProgressView().tint(Theme.accent)
            }

            VStack {
                topBar
                Spacer()
                bottomControls
            }

            if let busyMessage {
                if let busyImage {
                    ScanningOverlay(image: busyImage, message: busyMessage)
                } else {
                    busyOverlay(busyMessage)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            circleButton("xmark") { dismiss() }
            Spacer()
            if onOpenSplits != nil {
                circleButton("list.bullet") { onOpenSplits?() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial))
        }
    }

    /// A receipt-shaped cut-out — tall and narrow — so people frame the whole
    /// bill instead of cropping the totals off the bottom.
    private var guideOverlay: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.74
            let height = min(geo.size.height * 0.56, width * 1.5)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .frame(width: width, height: height)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.44)
                .allowsHitTesting(false)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
            if let message = errorMessage ?? pickerError {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.expense)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else if camera.state == .running {
                Text("Fit the whole receipt in the frame")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .shadow(radius: 6)
            }

            // Shutter centred, photo picker to its left. The spacer on the right
            // keeps the shutter on the screen's centre line rather than the
            // remaining space's.
            HStack(spacing: 0) {
                photoPickerButton.frame(maxWidth: .infinity)
                shutter
                Color.clear.frame(width: 52, height: 52).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 26)

            if onManualEntry != nil {
                Button {
                    onManualEntry?()
                } label: {
                    Text("Enter items by hand")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
            }
        }
        .padding(.bottom, 34)
    }

    /// Pick a receipt you already photographed. Stays enabled when the camera
    /// isn't available, so this is the whole flow's escape hatch on a device
    /// without one — and the only way to exercise it in the simulator.
    private var photoPickerButton: some View {
        PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.18), lineWidth: 1))
                if isLoadingPhoto {
                    ProgressView().tint(Theme.ink)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .disabled(isLoadingPhoto || busyMessage != nil)
        .accessibilityLabel("Choose a receipt photo")
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            loadPickedPhoto(item)
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        pickerError = nil
        Task {
            defer {
                isLoadingPhoto = false
                // Clear the selection so picking the same photo twice still fires.
                pickedPhoto = nil
            }
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                pickerError = "That photo couldn't be opened. Try another one."
                return
            }
            onCapture(image)
        }
    }

    /// The one control that matters: lime disc, dark receipt glyph, lime glow —
    /// same treatment as the `+` button it was launched from.
    private var shutter: some View {
        Button {
            camera.capture { image in
                if let image { onCapture(image) }
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 2)
                    .frame(width: 92, height: 92)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 18, y: 4)
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.bg)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.state != .running || busyMessage != nil)
        .opacity(camera.state == .running ? 1 : 0.35)
        .accessibilityLabel("Scan receipt")
    }

    private func busyOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(Theme.accent).scaleEffect(1.3)
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
        }
        .transition(.opacity)
    }

    private func unavailableState(_ message: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.faint)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Camera plumbing

/// Owns the capture session. Session setup and teardown run off the main thread
/// — `startRunning` blocks, and on the main queue it stutters the presentation
/// animation the camera is appearing in.
@Observable
final class CameraController: NSObject {
    enum State: Equatable { case starting, running, denied, unavailable }

    private(set) var state: State = .starting

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "cash.settlr.camera")
    private var captureHandler: ((UIImage?) -> Void)?
    private var isConfigured = false

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }

        queue.async { [self] in
            if !isConfigured {
                guard configure() else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                isConfigured = true
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else { return false }

        session.addInput(input)
        session.addOutput(output)

        // Receipts are printed close up; without this the text lands soft.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        }
        return true
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        guard state == .running else { return completion(nil) }
        captureHandler = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        queue.async { [self] in
            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async { [self] in
            captureHandler?(image)
            captureHandler = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = controller.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.videoPreviewLayer.session !== controller.session {
            view.videoPreviewLayer.session = controller.session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
