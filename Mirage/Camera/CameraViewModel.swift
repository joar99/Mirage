import SwiftUI
import Combine
import AVFoundation

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

    weak var delegate: CameraViewModelCoordinating?

    // MARK: - Lifecycle
    override init() {
        super.init()
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
        guard let depthData = (synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData)?.depthData else {
            return
        }

        /// TODO: Apply Gaussian Blur

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
