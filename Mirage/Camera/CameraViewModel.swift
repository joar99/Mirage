import SwiftUI
import Combine
import AVFoundation

@MainActor
protocol CameraViewModelCoordinating: AnyObject {

}

@MainActor
final class CameraViewModel: ObservableObject {

    // MARK: - Properties
    @Published var captureMode: CameraCaptureMode = .normal

    let cameraView: UIView = UIView()

    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated private let sessionQueue = DispatchQueue(label: "camera.session")
    nonisolated(unsafe) private var previewLayer: AVCaptureVideoPreviewLayer?

    weak var delegate: CameraViewModelCoordinating?

    // MARK: - Lifecycle

    init() {
        setupCameraView()
        checkPermissionsAndSetup()
    }

    // MARK: - Private Methods

    private func checkPermissionsAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCaptureSession()
                }
            }
        default:
            break
        }
    }

    private func setupCameraView() {
        cameraView.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        cameraView.layer.addSublayer(layer)
        previewLayer = layer
    }

    nonisolated private func setupCaptureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                self.captureSession.commitConfiguration()
                return
            }

            if self.captureSession.canAddInput(videoInput) {
                self.captureSession.addInput(videoInput)
            }

            self.captureSession.commitConfiguration()
        }
    }

    // MARK: - Public Methods

    func updateCameraViewFrame(_ frame: CGRect) {
        guard frame.width > 0 && frame.height > 0 else { return }
        previewLayer?.frame = frame
    }

    nonisolated func startSession() {
        sessionQueue.async {
            self.captureSession.startRunning()
        }
    }

    nonisolated func stopSession() {
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
    }
}

// MARK: Mocking

extension CameraViewModel {
    static func mockModel() -> CameraViewModel {
        return CameraViewModel()
    }
}
