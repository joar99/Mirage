import AVFoundation

actor VisionGate {
    private var busy = false
    private unowned let processor: VisionProcessor

    init(processor: VisionProcessor) {
        self.processor = processor
    }

    func tryRunSegmentation(on buffer: CVPixelBuffer, depthData: AVDepthData) {
        guard !busy else {
            return
        }
        busy = true
        processor.runSegmentation(on: buffer, depthData: depthData)
    }

    func done() {
        busy = false
    }
}
