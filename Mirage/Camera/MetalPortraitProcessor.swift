import Foundation
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import UIKit

/// Builds a blur pyramid and composites: person sharp, background blurred.
/// Returns a BGRA CVPixelBuffer you can hand to your UIImageView.
final class MetalPortraitProcessor {

    // MARK: - Config
    struct Config {
        var enableAsync: Bool = false
        var buildL3: Bool = false
    }

    // MARK: - Metal
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let lib: MTLLibrary

    // Pipelines
    private let pDownsample: MTLComputePipelineState
    private let pBlurH: MTLComputePipelineState
    private let pBlurV: MTLComputePipelineState
    private let pComposite: MTLComputePipelineState

    // CV Metal texture cache
    private var textureCache: CVMetalTextureCache!

    // Output pool (reused buffers)
    private var outputPool: CVPixelBufferPool?

    // Last completed output (when running async)
    private var lastCompletedBuffer: CVPixelBuffer?

    // Config
    private var config = Config()

    // MARK: - Init
    init?(config: Config = .init()) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("Metal unavailable")
            return nil
        }
        self.device = device
        self.queue = queue
        self.config = config

        do {
            guard let lib = device.makeDefaultLibrary() else { return nil }
            self.lib = lib

            func makePS(_ name: String) throws -> MTLComputePipelineState {
                guard let fn = lib.makeFunction(name: name) else {
                    throw NSError(domain: "MetalPortrait", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing function \(name)"])
                }
                return try device.makeComputePipelineState(function: fn)
            }

            self.pDownsample = try makePS("downsample2x_box")
            self.pBlurH = try makePS("blur_gaussian_h")
            self.pBlurV = try makePS("blur_gaussian_v")
            self.pComposite = try makePS("compositePortraitSimple")
        } catch {
            print("Pipeline build error: \(error)")
            return nil
        }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let tc = cache else { return nil }
        self.textureCache = tc
    }

    func applyBookehBlur(to videoBuffer: CVPixelBuffer, capturableObject: CameraCapturable) -> CVPixelBuffer? {
        switch capturableObject {
        case .person(depthData: let depthData, personMask: let personMask):
            return applyBookehBlurToPersons(videoBuffer, depthData, personMask)
        case .inanimateObject(depthData: let depthData):
            /// TODO: Allow for capture of inanimate objects without a mask
            return nil
        }
    }

    private func applyBookehBlurToPersons(_ videoBuffer: CVPixelBuffer, _ depthData: AVDepthData, _ personMask: CVPixelBuffer) -> CVPixelBuffer? {
        let width  = CVPixelBufferGetWidth(videoBuffer)
        let height = CVPixelBufferGetHeight(videoBuffer)

        if outputPool == nil || !poolMatches(pool: outputPool, width: width, height: height) {
            outputPool = makePool(width: width, height: height)
        }

        guard let outputBuffer = allocateFromPool(outputPool) else {
            return nil
        }

        guard let tInput  = makeTex(from: videoBuffer, pixelFormat: .bgra8Unorm), let tMask   = makeTex(from: personMask, pixelFormat: .r8Unorm), let tOutput = makeTex(from: outputBuffer, pixelFormat: .bgra8Unorm) else {
            return nil
        }

        let w1 = max(1, width  / 2), h1 = max(1, height / 2)
        let w2 = max(1, w1     / 2), h2 = max(1, h1     / 2)

        guard let L1temp = makeTmpTex(width: w1, height: h1, format: .bgra8Unorm), let L2a = makeTmpTex(width: w2, height: h2, format: .bgra8Unorm), let L2b = makeTmpTex(width: w2, height: h2, format: .bgra8Unorm) else {
            return nil
        }

        guard let cmd = queue.makeCommandBuffer() else {
            return nil
        }

        encodeDownsample(src: tInput, dst: L1temp, in: cmd)
        encodeDownsample(src: L1temp, dst: L2a, in: cmd)
        encodeBlur(src: L2a, dst: L2b, in: cmd)

        guard let enc = cmd.makeComputeCommandEncoder() else {
            return nil
        }
        enc.setComputePipelineState(pComposite)

        enc.setTexture(tInput, index: 0)
        enc.setTexture(L2b, index: 1)
        enc.setTexture(tMask, index: 2)
        enc.setTexture(tOutput, index: 3)

        var invSize = SIMD2<Float>(1.0 / Float(width), 1.0 / Float(height))
        enc.setBytes(&invSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)

        dispatch2D(enc: enc, w: width, h: height, pso: pComposite)
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()
        return outputBuffer
    }

    // MARK: - UIImage helper

    func makeUIImage(from buffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .right)
    }

    private func encodeDownsample(src: MTLTexture, dst: MTLTexture, in cmd: MTLCommandBuffer) {
        guard let enc = cmd.makeComputeCommandEncoder() else {
            return
        }
        enc.setComputePipelineState(pDownsample)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        dispatch2D(enc: enc, w: dst.width, h: dst.height, pso: pDownsample)
        enc.endEncoding()
    }

    private func encodeBlur(src: MTLTexture, dst: MTLTexture, in cmd: MTLCommandBuffer) {
        guard let temp = makeTmpTex(width: dst.width, height: dst.height, format: .bgra8Unorm) else {
            return
        }

        guard let encH = cmd.makeComputeCommandEncoder() else {
            return
        }
        encH.setComputePipelineState(pBlurH)
        encH.setTexture(src, index: 0)
        encH.setTexture(temp, index: 1)
        dispatch2D(enc: encH, w: temp.width, h: temp.height, pso: pBlurH)
        encH.endEncoding()

        guard let encV = cmd.makeComputeCommandEncoder() else {
            return
        }
        encV.setComputePipelineState(pBlurV)
        encV.setTexture(temp, index: 0)
        encV.setTexture(dst, index: 1)
        dispatch2D(enc: encV, w: dst.width, h: dst.height, pso: pBlurV)
        encV.endEncoding()
    }

    private func dispatch2D(enc: MTLComputeCommandEncoder, w: Int, h: Int, pso: MTLComputePipelineState) {
        let tgW = min(16, pso.threadExecutionWidth)
        let tgH = max(1, min(16, pso.maxTotalThreadsPerThreadgroup / tgW))
        let tpg = MTLSize(width: tgW, height: tgH, depth: 1)
        let groups = MTLSize(width: (w + tgW - 1) / tgW, height: (h + tgH - 1) / tgH, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tpg)
    }

    private func makeTex(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTex: CVMetalTexture?
        let res = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, pixelFormat, width, height, 0, &cvTex)

        guard res == kCVReturnSuccess, let cv = cvTex, let tex = CVMetalTextureGetTexture(cv) else {
            return nil
        }
        return tex
    }

    private func makeTmpTex(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelFormatOpenGLESCompatibility as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let poolAttrs: [String: Any] = [ kCVPixelBufferPoolMinimumBufferCountKey as String: 3 ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, attrs as CFDictionary, &pool)
        return pool
    }

    private func allocateFromPool(_ pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else {
            return nil
        }
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        return status == kCVReturnSuccess ? pb : nil
    }

    private func poolMatches(pool: CVPixelBufferPool?, width: Int, height: Int) -> Bool {
        guard let pool else {
            return false
        }
        guard let dict = CVPixelBufferPoolGetPixelBufferAttributes(pool) as? [String: Any] else {
            return false
        }
        return (dict[kCVPixelBufferWidthKey as String] as? Int == width) &&
               (dict[kCVPixelBufferHeightKey as String] as? Int == height)
    }
}
