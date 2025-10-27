import AVFoundation
import CoreImage
import UIKit

@MainActor
final class PortraitEffectProcessor {

    private let ciContext = CIContext()

    func applyPortraitEffect(to videoBuffer: CVPixelBuffer, depthData: AVDepthData?, personMask: CVPixelBuffer) -> CVPixelBuffer? {

        let inputImage = CIImage(cvPixelBuffer: videoBuffer)
        var depthImage: CIImage? = nil

        if let depthData {
            let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
            depthImage = CIImage(cvPixelBuffer: converted.depthDataMap)
        }

        let maskImage = CIImage(cvPixelBuffer: personMask)

        let blurred = inputImage.applyingGaussianBlur(sigma: 15)

        guard let composite = CIFilter(name: "CIBlendWithMask", parameters: [ kCIInputImageKey: blurred, kCIInputBackgroundImageKey: inputImage, kCIInputMaskImageKey: maskImage ])?.outputImage else {
            return nil
        }

        // Step 3: Render to pixel buffer for display
        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil,
                                         CVPixelBufferGetWidth(videoBuffer),
                                         CVPixelBufferGetHeight(videoBuffer),
                                         kCVPixelFormatType_32BGRA,
                                         nil,
                                         &outputPixelBuffer)
        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            return nil
        }

        ciContext.render(composite, to: outputBuffer)
        return outputBuffer
    }

    func makeUIImage(from buffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }

}
