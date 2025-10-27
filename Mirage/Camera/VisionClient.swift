import Foundation
import AVFoundation

struct VisionClient {

    /// This method takes in a CVPixelBuffer and returns whether or not this contais
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
