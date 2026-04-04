import AVFoundation

@MainActor
protocol FilterGateDelegate: AnyObject {
    func filterGate(_ filterGate: FilterGate, didCreateBlurredImage blurredImage: CVPixelBuffer)
}

@MainActor
class FilterGate {

    private var busy = false
    private let metalPortraitProcessor: MetalPortraitProcessor

    weak var delegate: FilterGateDelegate?

    init(metalPortraitProcessor: MetalPortraitProcessor) {
        self.metalPortraitProcessor = metalPortraitProcessor
    }

    func tryProcess(mask: CVPixelBuffer, video: CVPixelBuffer, depth: AVDepthData) {
        guard !busy else {
            return
        }

        busy = true

        let capturable = CameraCapturable.person(depthData: depth, personMask: mask)

        if let blurredImage = metalPortraitProcessor.applyBookehBlur(to: video, capturableObject: capturable) {
            delegate?.filterGate(self, didCreateBlurredImage: blurredImage)
        }

        busy = false
    }
}
