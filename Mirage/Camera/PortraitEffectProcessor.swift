import AVFoundation
import CoreImage
import UIKit

final class PortraitEffectProcessor {
    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .useSoftwareRenderer: false,
        .priorityRequestLow: false
    ])

    private var previousMask: CIImage?
    private let maskSmoothingFactor: CGFloat = 0.7

    private var pixelBufferPool: CVPixelBufferPool?

    init() {
            // Create a buffer pool
            let poolAttributes: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 3
            ]
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1920,  // Adjust to your needs
                kCVPixelBufferHeightKey as String: 1080,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary,
                                   pixelBufferAttributes as CFDictionary,
                                   &pixelBufferPool)
        }

    func applyPortraitEffect(to videoBuffer: CVPixelBuffer, depthData: AVDepthData?, personMask: CVPixelBuffer) -> CVPixelBuffer? {
        let inputImage = CIImage(cvPixelBuffer: videoBuffer)
        let maskImage = CIImage(cvPixelBuffer: personMask)
        let videoWidth = CGFloat(CVPixelBufferGetWidth(videoBuffer))
        let videoHeight = CGFloat(CVPixelBufferGetHeight(videoBuffer))

        let processingScale: CGFloat = 0.5
        let processingWidth = videoWidth * processingScale
        let processingHeight = videoHeight * processingScale

        let scaledInput = inputImage.transformed(by: CGAffineTransform(scaleX: processingScale, y: processingScale))

        let maskWidth = maskImage.extent.width
        let maskHeight = maskImage.extent.height
        let scaleX = processingWidth / maskWidth
        let scaleY = processingHeight / maskHeight
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

        // ⭐ Scale erosion radius proportionally
        guard let erodedMask = CIFilter(name: "CIMorphologyMinimum", parameters: [
            kCIInputImageKey: temporallySmoothedMask,
            "inputRadius": 3.0 * processingScale  // Scale it down!
        ])?.outputImage else {
            return fallbackToSimpleBlur(inputImage: scaledInput, scaledMask: temporallySmoothedMask, videoBuffer: videoBuffer, originalSize: CGSize(width: videoWidth, height: videoHeight))
        }

        // ⭐ Scale mask blur proportionally
        let softenedMask = erodedMask.applyingGaussianBlur(sigma: 12.0 * processingScale)

        if let depthData = depthData {
            let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
            let depthImage = CIImage(cvPixelBuffer: converted.depthDataMap)

            let depthScaleX = processingWidth / depthImage.extent.width
            let depthScaleY = processingHeight / depthImage.extent.height
            let scaledDepth = depthImage.transformed(by: CGAffineTransform(scaleX: depthScaleX, y: depthScaleY))

            // ⭐ Scale depth blur proportionally
            let softenedDepth = scaledDepth.applyingGaussianBlur(sigma: 8.0 * processingScale)

            // ⭐ Scale blur radius proportionally
            guard let depthBlur = CIFilter(name: "CIMaskedVariableBlur", parameters: [
                kCIInputImageKey: scaledInput,
                "inputMask": softenedDepth,
                "inputRadius": 8.0 * processingScale  // Scale it down!
            ])?.outputImage else {
                return fallbackToSimpleBlur(inputImage: scaledInput, scaledMask: softenedMask, videoBuffer: videoBuffer, originalSize: CGSize(width: videoWidth, height: videoHeight))
            }

            guard let composite = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: scaledInput,
                kCIInputBackgroundImageKey: depthBlur,
                kCIInputMaskImageKey: softenedMask
            ])?.outputImage else {
                return nil
            }

            let upscaleFactor = 1.0 / processingScale
            let finalImage = composite.transformed(by: CGAffineTransform(scaleX: upscaleFactor, y: upscaleFactor))

            return renderToBuffer(finalImage, videoBuffer: videoBuffer)
        }

        return fallbackToSimpleBlur(inputImage: scaledInput, scaledMask: softenedMask, videoBuffer: videoBuffer, originalSize: CGSize(width: videoWidth, height: videoHeight))
    }


    private func fallbackToSimpleBlur(inputImage: CIImage, scaledMask: CIImage, videoBuffer: CVPixelBuffer, originalSize: CGSize) -> CVPixelBuffer? {
        let blurred = inputImage.applyingGaussianBlur(sigma: 15.0)  // Increased from 3.0 for more dramatic effect

        // Fix: Sharp person, blurred background
        guard let composite = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: inputImage,           // Sharp foreground (person)
            kCIInputBackgroundImageKey: blurred,    // Blurred background
            kCIInputMaskImageKey: scaledMask        // Person mask
        ])?.outputImage else {
            return nil
        }

        // ⭐ UPSCALE if we're working at reduced resolution
        let currentWidth = inputImage.extent.width
        if currentWidth < originalSize.width {
            let upscaleX = originalSize.width / currentWidth
            let upscaleY = originalSize.height / inputImage.extent.height
            let finalImage = composite.transformed(by: CGAffineTransform(scaleX: upscaleX, y: upscaleY))
            return renderToBuffer(finalImage, videoBuffer: videoBuffer)
        }

        return renderToBuffer(composite, videoBuffer: videoBuffer)
    }


    private func renderToBuffer(_ image: CIImage, videoBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }

        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)

        guard let outputBuffer = outputPixelBuffer else { return nil }
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
