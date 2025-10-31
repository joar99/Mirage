import AVFoundation

actor VisionGate {
    private var busy = false
    private unowned let processor: VisionProcessor

    init(processor: VisionProcessor) {
        self.processor = processor
    }

    func tryRunSegmentation(on buffer: CVPixelBuffer, for segmentableObjectType: SegmentableObject) {
        guard !busy else {
            return
        }
        busy = true
        processor.runSegmentation(on: buffer, for: segmentableObjectType)
    }

    func done() {
        busy = false
    }
}
