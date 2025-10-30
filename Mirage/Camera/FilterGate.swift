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
            let capturable = CameraCapturable.person(depthData: depth, personMask: mask)

            if let blurredImage = self.processor.applyBookehBlur(to: video, capturableObject: capturable) {
                await MainActor.run {
                    self.onResult(blurredImage)
                }
                await self.done()
            }
        }
    }

    private func done() {
        busy = false
    }
}
