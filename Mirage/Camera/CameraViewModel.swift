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
    private var segmentationRequest: VNGeneratePersonSegmentationRequest?
    private let visionQueue = DispatchQueue(label: "camera.vision")

    weak var delegate: CameraViewModelCoordinating?

    // MARK: - Lifecycle
    override init() {
        super.init()
        sessionController.delegate = self
        setupVision()
        setupCameraView()
        checkPermissionsAndSetup()
    }

    // MARK: - Setup
    private func setupVision() {
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest?.qualityLevel = .accurate
        segmentationRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let latestRevision = VNGeneratePersonSegmentationRequest.supportedRevisions.last {
            segmentationRequest?.revision = latestRevision
        }
    }

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

    nonisolated private func runVisionSegmentation(on pixelBuffer: CVPixelBuffer) {
        struct UnsafeCVPixelBuffer: @unchecked Sendable {
            let buffer: CVPixelBuffer
        }

        let safeBuffer = UnsafeCVPixelBuffer(buffer: pixelBuffer)

        Task { @MainActor [weak self] in
            guard let request = self?.segmentationRequest else { return }

            self?.visionQueue.async {
                let handler = VNImageRequestHandler(cvPixelBuffer: safeBuffer.buffer, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    guard let result = request.results?.first as? VNPixelBufferObservation else {
                        return
                    }

                    let mask = result.pixelBuffer

                    self?.analyzePersonMask(mask)

                } catch {
                    print("❌ Vision segmentation error: \(error)")
                }
            }
        }
    }

    nonisolated private func analyzePersonMask(_ mask: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return
        }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total: Int = 0
        for y in stride(from: 0, to: height, by: 8) {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: 8) {
                total += Int(row[x])
            }
        }

        let mean = Double(total) / Double((width / 8) * (height / 8) * 255)

        if mean > 0.01 {
            print("Person detected (mean mask intensity: \(String(format: "%.2f", mean)))")
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

    func cameraSessionController(_ controller: CameraSessionController,
                                 didOutput videoBuffer: CVPixelBuffer,
                                 depthData: AVDepthData?) {
        runVisionSegmentation(on: videoBuffer)
    }

    func cameraSessionController(_ controller: CameraSessionController, didFailWith error: Error) {
        print("Camera error: \(error)")
    }
}

// MARK: Mocking

extension CameraViewModel {
    static func mockModel() -> CameraViewModel {
        return CameraViewModel()
    }
}
