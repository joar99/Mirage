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

    let cameraView: UIView = UIView()

    // Core session infrastructure
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated private let sessionQueue = DispatchQueue(label: "camera.session")
    nonisolated(unsafe) private var previewLayer: AVCaptureVideoPreviewLayer?

    // Outputs
    nonisolated private let depthOutput = AVCaptureDepthDataOutput()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer?

    // Vision
    private let visionQueue = DispatchQueue(label: "camera.vision")
    private var segmentationRequest: VNGeneratePersonSegmentationRequest?

    weak var delegate: CameraViewModelCoordinating?

    // MARK: - Lifecycle
    override init() {
        super.init()
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest?.qualityLevel = .accurate
        segmentationRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let latestRevision = VNGeneratePersonSegmentationRequest.supportedRevisions.last {
            segmentationRequest?.revision = latestRevision
        }

        setupCameraView()
        checkPermissionsAndSetup()
    }

    // MARK: - Permissions
    private func checkPermissionsAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCaptureSession()
                } else {
                }
            }
        default:
            print("Camera access denied or restricted")
        }
    }

    // MARK: - Camera View
    private func setupCameraView() {
        cameraView.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        cameraView.layer.addSublayer(layer)
        previewLayer = layer
    }

    // MARK: - Session Setup
    nonisolated private func setupCaptureSession() {
        Task { @MainActor in
            let mode = self.captureMode
            await self.configureSession(for: mode)
        }
    }

    nonisolated private func configureSession(for mode: CameraCaptureMode) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .high

                guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back), let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
                else {
                    self.captureSession.commitConfiguration()
                    continuation.resume()
                    return
                }

                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                }

                do {
                    try videoDevice.lockForConfiguration()
                    videoDevice.videoZoomFactor = 1.0
                    videoDevice.unlockForConfiguration()
                } catch {
                    print("Couldn't set zoom factor: \(error)")
                }

                // Video output
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                if self.captureSession.canAddOutput(self.videoOutput) {
                    self.captureSession.addOutput(self.videoOutput)
                    print("Added video output")
                }

                // Depth output
                self.depthOutput.isFilteringEnabled = true
                if self.captureSession.canAddOutput(self.depthOutput) {
                    self.captureSession.addOutput(self.depthOutput)
                }

                self.captureSession.commitConfiguration()
                continuation.resume()
            }
        }

        await awaitValidConnections(videoOutput: videoOutput, depthOutput: depthOutput)

        let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        synchronizer.setDelegate(self, queue: sessionQueue)
        await MainActor.run {
            self.dataOutputSynchronizer = synchronizer
        }

        sessionQueue.async {
            self.captureSession.startRunning()
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

    // MARK: - Frame / Session Controls
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

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraViewModel: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let depthData = (synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData)?.depthData, let videoData = (synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData)?.sampleBuffer else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(videoData) else {
            return
        }


        runVisionSegmentation(on: pixelBuffer)

        // TODO: Later use both mask + depth to apply Gaussian blur
    }
}
// MARK: Await AVCaptureConnections

extension CameraViewModel {
    // Waits asynchronously until both outputs have valid AVCaptureConnections.
    nonisolated private func awaitValidConnections(videoOutput: AVCaptureVideoDataOutput, depthOutput: AVCaptureDepthDataOutput) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            func checkReady() {
                if videoOutput.connection(with: .video) != nil &&
                   depthOutput.connection(with: .depthData) != nil {
                    continuation.resume()
                } else {
                    sessionQueue.asyncAfter(deadline: .now() + 0.02) {
                        checkReady()
                    }
                }
            }
            checkReady()
        }
    }
}

// MARK: Mocking

extension CameraViewModel {
    static func mockModel() -> CameraViewModel {
        return CameraViewModel()
    }
}
