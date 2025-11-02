@preconcurrency import Vision
import AVFoundation

public struct UnsafeDepthDataBox: @unchecked Sendable {
    let depthData: AVDepthData
}

public struct UnsafeCVPixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

@MainActor
protocol VisionProcessorDelegate: AnyObject {
    func visionProcessor(_ processor: VisionProcessor, didDetectPersonWithMask mask: CVPixelBuffer)
    func visionProcessor(_ processor: VisionProcessor, didFailWith error: Error)
    func visionProcessorDidNotDetectPerson(_ processor: VisionProcessor)
}

@MainActor
final class VisionProcessor {

    weak var delegate: VisionProcessorDelegate?

    private let visionQueue = DispatchQueue(label: "camera.vision")
    private var personRequest: VNGeneratePersonSegmentationRequest?

    init() {
        setupVision()
    }

    private func setupVision() {
        personRequest = VNGeneratePersonSegmentationRequest()
        personRequest?.qualityLevel = .balanced
        personRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let latestRevision = VNGeneratePersonSegmentationRequest.supportedRevisions.last {
            personRequest?.revision = latestRevision
        }
    }

    nonisolated func runSegmentation(on pixelBuffer: CVPixelBuffer) {
        let safeInput = UnsafeCVPixelBufferBox(buffer: pixelBuffer)

        Task { @MainActor [weak self] in

            guard let self else {
                return
            }

            guard let personRequest = self.personRequest else {
                return
            }
            let segmentationRequest: VNRequest = personRequest

            self.visionQueue.async { [weak self, segmentationRequest] in
                guard let self else { return }

                let handler = VNImageRequestHandler(cvPixelBuffer: safeInput.buffer,
                                                    orientation: .up,
                                                    options: [:])

                do {
                    try handler.perform([segmentationRequest])

                    guard let result = segmentationRequest.results?.first as? VNPixelBufferObservation else { return }
                    let mask = result.pixelBuffer
                    let detected = self.analyzePersonMask(mask)
                    guard detected else {
                        return
                    }

                    let safeMask = UnsafeCVPixelBufferBox(buffer: mask)

                    Task { @MainActor in
                        self.delegate?.visionProcessor(self, didDetectPersonWithMask: safeMask.buffer)
                    }

                } catch {
                    Task { @MainActor in
                        self.delegate?.visionProcessor(self, didFailWith: error)
                    }
                }
            }
        }
    }

    nonisolated private func analyzePersonMask(_ mask: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return false
        }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total = 0
        for y in stride(from: 0, to: height, by: 8) {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: 8) {
                total += Int(row[x])
            }
        }

        let mean = Double(total) / Double((width / 8) * (height / 8) * 255)

        return mean > 0.05
    }
}
