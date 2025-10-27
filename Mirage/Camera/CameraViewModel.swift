import SwiftUI
import Combine
import AVFoundation
@preconcurrency import Vision

@MainActor
protocol CameraViewModelCoordinating: AnyObject {

}

@MainActor
final class CameraViewModel: NSObject, ObservableObject {

    // MARK: - Properties
    @Published var captureMode: CameraCaptureMode = .portrait
    @Published var cameraPosition: CameraPosition = .back
    @Published var isReconfiguring: Bool = false

    let cameraView: UIView = UIView()

    private let sessionController = CameraSessionController()
    private let visionProcessor = VisionProcessor()

    weak var delegate: CameraViewModelCoordinating?

    // MARK: - Lifecycle
    override init() {
        super.init()
        sessionController.delegate = self
        visionProcessor.delegate = self
        setupCameraView()
        checkPermissionsAndSetup()
    }

    // MARK: - Camera setup
    private func setupCameraView() {
        cameraView.backgroundColor = .black
        let layer = sessionController.makePreviewLayer()
        cameraView.layer.addSublayer(layer)
    }

    private func checkPermissionsAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionController.setupSession(mode: captureMode, position: cameraPosition)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    Task { @MainActor in
                        self.sessionController.setupSession(mode: self.captureMode,
                                                            position: self.cameraPosition)
                    }
                }
            }
        default:
            print("Camera access denied or restricted")
        }
    }

    // MARK: - UI Interaction
    func updateCameraViewFrame(_ frame: CGRect) {
        sessionController.updatePreviewFrame(frame)
    }

    func didTapToggleCameraPosition() {
        isReconfiguring = true
        Task {
            await sessionController.switchCamera()
            await MainActor.run {
                self.isReconfiguring = false
                self.cameraPosition = self.cameraPosition == .back ? .front : .back
            }
        }
    }
}

// MARK: - CameraSessionControllerDelegate

extension CameraViewModel: CameraSessionControllerDelegate {
    func cameraSessionControllerDidStart(_ controller: CameraSessionController) {
        print("Camera session started")
    }

    func cameraSessionControllerDidStop(_ controller: CameraSessionController) {
        print("Camera session stopped")
    }

    func cameraSessionController(_ controller: CameraSessionController, didOutput videoBuffer: CVPixelBuffer, depthData: AVDepthData?) {
        visionProcessor.runSegmentation(on: videoBuffer)
    }

    func cameraSessionController(_ controller: CameraSessionController, didFailWith error: Error) {
        print("Camera error: \(error)")
    }
}

// MARK: - VisionProcessorDelegate

extension CameraViewModel: VisionProcessorDelegate {
    func visionProcessor(_ processor: VisionProcessor, didDetectPersonWithMask mask: CVPixelBuffer) {
        // Currently, we only log; original logic already printed in analyzePersonMask.
    }

    func visionProcessor(_ processor: VisionProcessor, didFailWith error: Error) {
        print("Vision segmentation error: \(error)")
    }
}

// MARK: - Mocking
extension CameraViewModel {
    static func mockModel() -> CameraViewModel {
        return CameraViewModel()
    }
}

