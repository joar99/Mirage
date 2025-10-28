import AVFoundation

actor FilterGate {
    private var busy = false
    private let processor: MetalPortraitProcessor
    private let onResult: @MainActor (CVPixelBuffer) -> Void

    init(processor: MetalPortraitProcessor, onResult: @escaping @MainActor (CVPixelBuffer) -> Void) {
        self.processor = processor
        self.onResult = onResult
    }

    func tryProcess(mask: CVPixelBuffer, video: CVPixelBuffer, depth: AVDepthData) {
        guard !busy else {
            return
        }

        busy = true
        Task.detached(priority: .userInitiated) {
            if let blurred = self.processor.applyPortraitEffect(to: video, depthData: depth, personMask: mask) {
                await MainActor.run {
                    self.onResult(blurred)
                }
                await self.done()
            }
        }
    }

    private func done() {
        busy = false
    }
}
