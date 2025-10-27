@preconcurrency import Vision
import AVFoundation

@MainActor
protocol VisionProcessorDelegate: AnyObject {
    func visionProcessor(_ processor: VisionProcessor, didDetectPersonWithMask mask: CVPixelBuffer)
    func visionProcessor(_ processor: VisionProcessor, didFailWith error: Error)
}

@MainActor
final class VisionProcessor {

    private struct UnsafeCVPixelBufferBox: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    weak var delegate: VisionProcessorDelegate?

    private let visionQueue = DispatchQueue(label: "camera.vision")
    private var segmentationRequest: VNGeneratePersonSegmentationRequest?

    init() {
        setupVision()
    }

    private func setupVision() {
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest?.qualityLevel = .accurate
        segmentationRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let latestRevision = VNGeneratePersonSegmentationRequest.supportedRevisions.last {
            segmentationRequest?.revision = latestRevision
        }
    }

    nonisolated func runSegmentation(on pixelBuffer: CVPixelBuffer) {
        let safeInput = UnsafeCVPixelBufferBox(buffer: pixelBuffer)

        Task { @MainActor [weak self] in
            guard let self, let request = self.segmentationRequest else {
                return
            }

            self.visionQueue.async { [weak self, request] in
                guard let self else {
                    return
                }

                let handler = VNImageRequestHandler(cvPixelBuffer: safeInput.buffer,
                                                    orientation: .up,
                                                    options: [:])
                do {
                    try handler.perform([request])

                    guard let result = request.results?.first as? VNPixelBufferObservation else { return }
                    let mask = result.pixelBuffer

                    self.analyzePersonMask(mask)

                    let safeMask = UnsafeCVPixelBufferBox(buffer: mask)
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        self.delegate?.visionProcessor(self, didDetectPersonWithMask: safeMask.buffer)
                    }

                } catch {
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        self.delegate?.visionProcessor(self, didFailWith: error)
                    }
                }
            }
        }
    }

    nonisolated private func analyzePersonMask(_ mask: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else { return }

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
