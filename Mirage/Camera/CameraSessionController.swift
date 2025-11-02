import AVFoundation
import UIKit

@MainActor
protocol CameraSessionControllerDelegate: AnyObject {
    func cameraSessionControllerDidStart(_ controller: CameraSessionController)
    func cameraSessionControllerDidStop(_ controller: CameraSessionController)
    func cameraSessionController(_ controller: CameraSessionController, didOutput videoBuffer: CVPixelBuffer, depthData: AVDepthData?)
    func cameraSessionController(_ controller: CameraSessionController, didFailWith error: Error)
}

final class CameraSessionController: NSObject {

    // MARK: - Properties

    weak var delegate: CameraSessionControllerDelegate?

    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated private let sessionQueue = DispatchQueue(label: "camera.session")

    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let depthOutput = AVCaptureDepthDataOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer?

    nonisolated(unsafe) private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Configuration
    private var currentPosition: CameraPosition = .back
    private var currentMode: CameraCaptureMode = .portrait

    // MARK: - Lifecycle
    override init() {
        super.init()
    }

    // MARK: - Setup
    func setupSession(mode: CameraCaptureMode, position: CameraPosition) {
        currentMode = mode
        currentPosition = position

        Task { @MainActor in
            await configureSession(for: mode, position: position)
        }
    }

    // MARK: - Reconfiguration
    func reconfigureSession(mode: CameraCaptureMode, position: CameraPosition) async {
        currentMode = mode
        currentPosition = position

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                continuation.resume()
            }
        }

        await MainActor.run {
            self.dataOutputSynchronizer = nil
        }

        await configureSession(for: mode, position: position)
    }

    // MARK: - Core Configuration
    nonisolated private func configureSession(for mode: CameraCaptureMode, position: CameraPosition) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.captureSession.beginConfiguration()

                // Remove existing inputs/outputs
                for input in self.captureSession.inputs {
                    self.captureSession.removeInput(input)
                }
                for output in self.captureSession.outputs {
                    self.captureSession.removeOutput(output)
                }

                self.captureSession.sessionPreset = .high

                // Select camera
                let videoDevice: AVCaptureDevice?
                if position == .back {
                    videoDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                } else {
                    videoDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                }

                guard let device = videoDevice,
                      let videoInput = try? AVCaptureDeviceInput(device: device) else {
                    self.captureSession.commitConfiguration()
                    continuation.resume()
                    return
                }

                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = 1.0
                    device.unlockForConfiguration()
                } catch {
                    print("Couldn't set zoom factor: \(error)")
                }

                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                }

                // Configure outputs
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                if self.captureSession.canAddOutput(self.videoOutput) {
                    self.captureSession.addOutput(self.videoOutput)
                }

                // Portrait Effects Matte is available via AVCapturePhotoOutput, not AVCaptureVideoDataOutput. Add a photo output if needed.

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

        await MainActor.run {
            self.delegate?.cameraSessionControllerDidStart(self)
        }
    }

    // MARK: - Preview Layer
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let previewLayer = previewLayer {
            return previewLayer
        }
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }

    func updatePreviewFrame(_ frame: CGRect) {
        previewLayer?.frame = frame
    }

    // MARK: - Start / Stop
    func startSession() {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.cameraSessionControllerDidStop(self)
        }
    }

    // MARK: - Camera Switching
    func switchCamera() async {
        let newPosition: CameraPosition = currentPosition == .back ? .front : .back
        await reconfigureSession(mode: currentMode, position: newPosition)
    }

    // MARK: - Await Connections
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

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraSessionController: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let depthData = (synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData)?.depthData, let videoData = (synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData)?.sampleBuffer, let pixelBuffer = CMSampleBufferGetImageBuffer(videoData) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.cameraSessionController(self, didOutput: pixelBuffer, depthData: depthData)
        }
    }
}

