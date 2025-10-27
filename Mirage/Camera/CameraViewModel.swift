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
    private let previewImageView = UIImageView()

    private let sessionController = CameraSessionController()
    private let visionProcessor = VisionProcessor()

    private var portraitProcessor = PortraitEffectProcessor()
    private var lastVideoBuffer: CVPixelBuffer?
    private var lastDepthData: AVDepthData?

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
    /*private func setupCameraView() {
        cameraView.backgroundColor = .black
        let layer = sessionController.makePreviewLayer()
        cameraView.layer.addSublayer(layer)
    }*/

    private func setupCameraView() {
        cameraView.backgroundColor = .black

        let layer = sessionController.makePreviewLayer()
        layer.videoGravity = .resizeAspectFill
        cameraView.layer.addSublayer(layer)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.backgroundColor = .clear
        previewImageView.isUserInteractionEnabled = false
        cameraView.addSubview(previewImageView)
    }

    func displayBlurredFrame(_ buffer: CVPixelBuffer) {
        guard let uiImage = portraitProcessor.makeUIImage(from: buffer) else { return }
        UIView.transition(with: previewImageView, duration: 0.1, options: .transitionCrossDissolve, animations: { self.previewImageView.image = uiImage})
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
        previewImageView.frame = frame
        sessionController.updatePreviewFrame(frame)

        guard let previewLayer = cameraView.layer.sublayers?.compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first else {
            return
        }

        previewLayer.frame = frame

        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    func didTapToggleCameraPosition() {
        isReconfiguring = true
        Task {
            await sessionController.switchCamera()
            await MainActor.run {
                self.isReconfiguring = false
                self.cameraPosition = self.cameraPosition == .back ? .front : .back
                self.previewImageView.transform = self.cameraPosition == .front ? CGAffineTransform(scaleX: -1, y: 1) : .identity
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
        lastVideoBuffer = videoBuffer
        lastDepthData = depthData
        visionProcessor.runSegmentation(on: videoBuffer)
    }

    func cameraSessionController(_ controller: CameraSessionController, didFailWith error: Error) {
        print("Camera error: \(error)")
    }
}

// MARK: - VisionProcessorDelegate

extension CameraViewModel: VisionProcessorDelegate {
    func visionProcessor(_ processor: VisionProcessor, didDetectPersonWithMask mask: CVPixelBuffer) {
        guard let latestVideoBuffer = lastVideoBuffer, let latestDepthData = lastDepthData else {
            return
        }

        if let blurred = portraitProcessor.applyPortraitEffect(to: latestVideoBuffer, depthData: latestDepthData, personMask: mask) {
            DispatchQueue.main.async {
                self.displayBlurredFrame(blurred)
            }
        }
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

