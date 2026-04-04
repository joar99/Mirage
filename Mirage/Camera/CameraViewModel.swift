import SwiftUI
import Combine
import AVFoundation
@preconcurrency import Vision

@MainActor
protocol CameraViewModelCoordinating: AnyObject {

}

@MainActor
final class CameraViewModel: NSObject, ObservableObject {

    @Published var captureMode: CameraCaptureMode = .portrait {
        didSet {
            previewImageView.image = nil
        }
    }

    @Published var cameraPosition: CameraPosition = .back {
        didSet {
            previewImageView.image = nil
        }
    }

    @Published var isReconfiguring: Bool = false

    let cameraView: UIView = UIView()
    private let previewImageView = UIImageView()

    private let sessionController = CameraSessionController()
    private let visionProcessor = VisionProcessor()
    private var portraitProcessor = MetalPortraitProcessor(config: .init(enableAsync: false))!

    private var lastVideoBuffer: CVPixelBuffer?
    private var lastDepthData: AVDepthData?

    private let visionGate: VisionGate
    private var filterGate: FilterGate

    weak var delegate: CameraViewModelCoordinating?

    override init() {

        visionGate = VisionGate(processor: visionProcessor)
        filterGate = FilterGate(metalPortraitProcessor: portraitProcessor)

        super.init()
        sessionController.delegate = self
        visionProcessor.delegate = self
        filterGate.delegate = self
        setupCameraView()
        checkPermissionsAndSetup()

    }

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
        guard captureMode == .portrait, cameraPosition == .front else {
            return
        }
        guard let uiImage = portraitProcessor.makeUIImage(from: buffer) else {
            return
        }
        previewImageView.image = uiImage
    }

    private func checkPermissionsAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionController.setupSession(mode: captureMode, position: cameraPosition)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    Task { @MainActor in
                        self.sessionController.setupSession(mode: self.captureMode, position: self.cameraPosition)
                    }
                }
            }
        default:
            print("Camera access denied or restricted")
        }
    }

    func updateCameraViewFrame(_ frame: CGRect) {
        previewImageView.frame = frame
        sessionController.updatePreviewFrame(frame)

        guard let previewLayer = cameraView.layer.sublayers?.compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first else {
            return
        }

        previewLayer.frame = frame

        if let connection = previewLayer.connection {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
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

// MARK: - CameraSessionControllerDelegate
extension CameraViewModel: CameraSessionControllerDelegate {
    func cameraSessionControllerDidStart(_ controller: CameraSessionController) {

    }

    func cameraSessionControllerDidStop(_ controller: CameraSessionController) {

    }

    func cameraSessionController(_ controller: CameraSessionController, didOutput videoBuffer: CVPixelBuffer, depthData: AVDepthData?) {
        guard captureMode == .portrait,
              cameraPosition == .front,
              let depthData = depthData else {
            return
        }

        Task {
            await visionGate.tryRunSegmentation(on: videoBuffer, depthData: depthData)
        }
    }

    func cameraSessionController(_ controller: CameraSessionController, didFailWith error: Error) {

    }
}

// MARK: - VisionProcessorDelegate

extension CameraViewModel: VisionProcessorDelegate {
    func visionProcessorDidNotDetectPerson(_ processor: VisionProcessor) {
        Task {
            await visionGate.done()
        }
    }

    func visionProcessor(_ processor: VisionProcessor, didDetectPersonWithMask mask: CVPixelBuffer, videoBuffer: CVPixelBuffer, depthData: AVDepthData) {
        Task {
            await visionGate.done()
        }

        guard let video = lastVideoBuffer, let depth = lastDepthData else {
            return
        }

        filterGate.tryProcess(mask: mask, video: video, depth: depth)
    }

    func visionProcessor(_ processor: VisionProcessor, didFailWith error: Error) {
        Task {
            await visionGate.done()
        }
    }
}

// MARK: - FilterGateDelegate
extension CameraViewModel: FilterGateDelegate {
    func filterGate(_ filterGate: FilterGate, didCreateBlurredImage blurredImage: CVPixelBuffer) {
        displayBlurredFrame(blurredImage)
    }
}

// MARK: - Mocking
extension CameraViewModel {
    static func mockModel() -> CameraViewModel {
        return CameraViewModel()
    }
}
