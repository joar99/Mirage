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

    /// nessecary for BASIC camera functionality
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated private let sessionQueue = DispatchQueue(label: "camera.session")
    nonisolated(unsafe) private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Depth additions (only these are new)
    nonisolated private let depthOutput = AVCaptureDepthDataOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer?

    weak var delegate: CameraViewModelCoordinating?

    // MARK: - Lifecycle

    override init() {
        super.init()
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
        Task { @MainActor in
            let mode = self.captureMode
            self.configureSessionOnQueue(for: mode)
        }
    }

    nonisolated private func configureSessionOnQueue(for mode: CameraCaptureMode) {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
            else {
                self.captureSession.commitConfiguration()
                return
            }

            if self.captureSession.canAddInput(videoInput) {
                self.captureSession.addInput(videoInput)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]

            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
            }

            if self.captureSession.canAddOutput(self.depthOutput) && mode == .portrait {
                self.configureDepthOutput()
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    nonisolated private func configureDepthOutput() {
        depthOutput.isFilteringEnabled = true
        captureSession.addOutput(depthOutput)

        guard let videoOutput = captureSession.outputs.first(where: { $0 is AVCaptureVideoDataOutput }) as? AVCaptureVideoDataOutput else {
            print("❌ No video output found for depth synchronization.")
            return
        }

        // Launch an async task to wait for connections, then build synchronizer
        Task.detached { [weak self] in
            guard let self else {
                return
            }

            await self.awaitValidConnections(videoOutput: videoOutput, depthOutput: self.depthOutput)

            let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, self.depthOutput])
            synchronizer.setDelegate(self, queue: self.sessionQueue)

            await MainActor.run { [weak self] in
                self?.dataOutputSynchronizer = synchronizer
            }

            print("✅ Depth Output Configured & synchronized")
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

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraViewModel: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let depthData = (synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData)?.depthData else {
            return
        }

        let depthBuffer = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        print("Depth frame: \(width)x\(height)")
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
