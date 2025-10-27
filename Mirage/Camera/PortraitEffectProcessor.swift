import AVFoundation
import CoreImage
import UIKit

final class PortraitEffectProcessor {
    private let ciContext = CIContext()

    private var previousMask: CIImage?
    private let maskSmoothingFactor: CGFloat = 0.7

    func applyPortraitEffect(to videoBuffer: CVPixelBuffer, depthData: AVDepthData?, personMask: CVPixelBuffer) -> CVPixelBuffer? {
        let inputImage = CIImage(cvPixelBuffer: videoBuffer)
        let maskImage = CIImage(cvPixelBuffer: personMask)
        let videoWidth = CGFloat(CVPixelBufferGetWidth(videoBuffer))
        let videoHeight = CGFloat(CVPixelBufferGetHeight(videoBuffer))
        let maskWidth = maskImage.extent.width
        let maskHeight = maskImage.extent.height
        let scaleX = videoWidth / maskWidth
        let scaleY = videoHeight / maskHeight
        let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let temporallySmoothedMask: CIImage
        if let prevMask = previousMask {
            if let blended = CIFilter(name: "CIBlendWithAlphaMask", parameters: [kCIInputImageKey: scaledMask, kCIInputBackgroundImageKey: prevMask, kCIInputMaskImageKey: CIImage(color: CIColor(red: maskSmoothingFactor, green: 0, blue: 0)).cropped(to: scaledMask.extent)])?.outputImage {
                temporallySmoothedMask = blended
            } else {
                temporallySmoothedMask = scaledMask
            }
        } else {
            temporallySmoothedMask = scaledMask
        }

        previousMask = temporallySmoothedMask

        guard let erodedMask = CIFilter(name: "CIMorphologyMinimum", parameters: [kCIInputImageKey: temporallySmoothedMask,"inputRadius": 3.0])?.outputImage else {
            return fallbackToSimpleBlur(inputImage: inputImage, scaledMask: temporallySmoothedMask, videoBuffer: videoBuffer)
        }

        let softenedMask = erodedMask.applyingGaussianBlur(sigma: 12.0)

        if let depthData = depthData {
            let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
            let depthImage = CIImage(cvPixelBuffer: converted.depthDataMap)

            let depthScaleX = videoWidth / depthImage.extent.width
            let depthScaleY = videoHeight / depthImage.extent.height
            let scaledDepth = depthImage.transformed(by: CGAffineTransform(scaleX: depthScaleX, y: depthScaleY))

            let softenedDepth = scaledDepth.applyingGaussianBlur(sigma: 8.0)

            guard let depthBlur = CIFilter(name: "CIMaskedVariableBlur", parameters: [kCIInputImageKey: inputImage,"inputMask": softenedDepth,"inputRadius": 8.0])?.outputImage else {
                return fallbackToSimpleBlur(inputImage: inputImage, scaledMask: softenedMask, videoBuffer: videoBuffer)
            }

            guard let composite = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: inputImage, kCIInputBackgroundImageKey: depthBlur, kCIInputMaskImageKey: softenedMask])?.outputImage else {
                return nil
            }

            return renderToBuffer(composite, videoBuffer: videoBuffer)
        }

        return fallbackToSimpleBlur(inputImage: inputImage, scaledMask: softenedMask, videoBuffer: videoBuffer)
    }

    private func fallbackToSimpleBlur(inputImage: CIImage, scaledMask: CIImage, videoBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let blurred = inputImage.applyingGaussianBlur(sigma: 3.0)  // Very subtle
        guard let composite = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: blurred, kCIInputBackgroundImageKey: inputImage, kCIInputMaskImageKey: scaledMask])?.outputImage else {
            return nil
        }
        return renderToBuffer(composite, videoBuffer: videoBuffer)
    }

    private func renderToBuffer(_ image: CIImage, videoBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, CVPixelBufferGetWidth(videoBuffer), CVPixelBufferGetHeight(videoBuffer), kCVPixelFormatType_32BGRA, nil, &outputPixelBuffer)
        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            return nil
        }
        ciContext.render(image, to: outputBuffer)
        return outputBuffer
    }

    func makeUIImage(from buffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }

    func resetTemporalSmoothing() {
        previousMask = nil
    }
}
