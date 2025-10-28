import Foundation
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import UIKit

/// Drop-in replacement for `PortraitEffectProcessor`.
/// Builds a tiny blur pyramid (1/2, 1/4, 1/8) and composites based on depth + person mask.
/// Returns a BGRA CVPixelBuffer you can hand to your UIImageView as before.
final class MetalPortraitProcessor {

    // MARK: - Config
    struct Config {
        var enableAsync: Bool = false              // if true, don't block on GPU; you'll get last frame until new one finishes
        var bokehStrength: Float = 1.0             // 0..1 extra gain on background blur
        var buildL3: Bool = true                   // if false: only L1/L2
        var useDepthR16: Bool = true               // create depth textures as r16Float when possible
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
            // Use default library (must include PortraitBokeh.metal in target)
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
            self.pComposite  = try makePS("compositePortrait")
        } catch {
            print("Pipeline build error: \(error)")
            return nil
        }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let tc = cache else { return nil }
        self.textureCache = tc
    }

    // MARK: - Public API
    func applyPortraitEffect(to videoBuffer: CVPixelBuffer,
                             depthData: AVDepthData?,
                             personMask: CVPixelBuffer) -> CVPixelBuffer? {

        guard let depthData else {
            // No depth: we can still keep subject sharp and do a single small blur level (optional).
            // For now, just return the source to match old fallback behavior.
            return videoBuffer
        }

        let width  = CVPixelBufferGetWidth(videoBuffer)
        let height = CVPixelBufferGetHeight(videoBuffer)

        // Prepare (or reuse) output pool
        if outputPool == nil || !poolMatches(pool: outputPool, width: width, height: height) {
            outputPool = makePool(width: width, height: height)
        }
        guard let outputBuffer = allocateFromPool(outputPool) else { return nil }

        // Convert depth to disparity float (0..1 normalized later)
        let disparity = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let depthMap  = disparity.depthDataMap

        // Create textures
        guard let tInput  = makeTex(from: videoBuffer, pixelFormat: .bgra8Unorm),
              let tDepth  = makeTex(from: depthMap,   pixelFormat: config.useDepthR16 ? .r16Float : .r32Float),
              let tMask   = makeTex(from: personMask, pixelFormat: .r8Unorm),
              let tOutput = makeTex(from: outputBuffer, pixelFormat: .bgra8Unorm) else {
            return nil
        }

        // Build pyramid textures (private, GPU-only)
        let w1 = max(1, width  / 2), h1 = max(1, height / 2)
        let w2 = max(1, w1     / 2), h2 = max(1, h1     / 2)
        let w3 = max(1, w2     / 2), h3 = max(1, h2     / 2)

        guard let L1a = makeTmpTex(width: w1, height: h1, format: .bgra8Unorm),
              let L1b = makeTmpTex(width: w1, height: h1, format: .bgra8Unorm),
              let L2a = makeTmpTex(width: w2, height: h2, format: .bgra8Unorm),
              let L2b = makeTmpTex(width: w2, height: h2, format: .bgra8Unorm) else {
            return nil
        }
        let L3a = config.buildL3 ? makeTmpTex(width: w3, height: h3, format: .bgra8Unorm) : nil
        let L3b = config.buildL3 ? makeTmpTex(width: w3, height: h3, format: .bgra8Unorm) : nil
        if config.buildL3 && (L3a == nil || L3b == nil) { return nil }

        guard let cmd = queue.makeCommandBuffer() else { return nil }

        // L1 = down2x(input) -> blur
        encodeDownsample(src: tInput, dst: L1a, in: cmd)
        encodeBlur(src: L1a, dst: L1b, in: cmd)  // Now uses Gaussian

        // L2 = down2x(L1b) -> blur
        encodeDownsample(src: L1b, dst: L2a, in: cmd)
        encodeBlur(src: L2a, dst: L2b, in: cmd)  // Now uses Gaussian

        // L3 = down2x(L2b) -> blur (optional)
        var L3blur: MTLTexture? = nil
        if let L3a = L3a, let L3b = L3b, config.buildL3 {
            encodeDownsample(src: L2b, dst: L3a, in: cmd)
            encodeBlur(src: L3a, dst: L3b, in: cmd)  // Now uses Gaussian
            L3blur = L3b
        }

        // 2) Composite
        do {
            guard let enc = cmd.makeComputeCommandEncoder() else { return nil }
            enc.setComputePipelineState(pComposite)

            // Full-res sharp and blurred levels
            enc.setTexture(tInput, index: 0)   // L0
            enc.setTexture(L1b,   index: 1)   // L1
            enc.setTexture(L2b,   index: 2)   // L2
            enc.setTexture(L3blur ?? L2b, index: 3) // L3 (fallback to L2 if not built)

            // Depth (float) + person mask (r8)
            enc.setTexture(tDepth, index: 4)
            enc.setTexture(tMask,  index: 5)

            // Output
            enc.setTexture(tOutput, index: 6)

            var strength = config.bokehStrength
            var invSize  = SIMD2<Float>(1.0 / Float(width), 1.0 / Float(height))
            enc.setBytes(&strength, length: MemoryLayout<Float>.size, index: 0)
            enc.setBytes(&invSize,  length: MemoryLayout<SIMD2<Float>>.size, index: 1)

            dispatch2D(enc: enc, w: width, h: height, pso: pComposite)
            enc.endEncoding()
        }

        if config.enableAsync {
            cmd.addCompletedHandler { [weak self] _ in
                self?.lastCompletedBuffer = outputBuffer
            }
            cmd.commit()
            // Return last finished frame (or current if none yet)
            return lastCompletedBuffer ?? outputBuffer
        } else {
            cmd.commit()
            cmd.waitUntilCompleted()
            return outputBuffer
        }
    }

    // MARK: - UIImage helper (optional)
    func makeUIImage(from buffer: CVPixelBuffer) -> UIImage? {
        // Keep CI out of the hot path; but okay for previews / snapshots.
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .right)
    }

    // MARK: - Encoders
    private func encodeDownsample(src: MTLTexture, dst: MTLTexture, in cmd: MTLCommandBuffer) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(pDownsample)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        dispatch2D(enc: enc, w: dst.width, h: dst.height, pso: pDownsample)
        enc.endEncoding()
    }

    private func encodeBlur(src: MTLTexture, dst: MTLTexture, in cmd: MTLCommandBuffer) {
        // Need intermediate texture for separable blur
        guard let temp = makeTmpTex(width: dst.width, height: dst.height, format: .bgra8Unorm) else {
            return
        }

        var radius: Float = 3.0  // Adjust this for more/less blur

        // Horizontal pass
        guard let encH = cmd.makeComputeCommandEncoder() else { return }
        encH.setComputePipelineState(pBlurH)
        encH.setTexture(src, index: 0)
        encH.setTexture(temp, index: 1)
        encH.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
        dispatch2D(enc: encH, w: temp.width, h: temp.height, pso: pBlurH)
        encH.endEncoding()

        // Vertical pass
        guard let encV = cmd.makeComputeCommandEncoder() else { return }
        encV.setComputePipelineState(pBlurV)
        encV.setTexture(temp, index: 0)
        encV.setTexture(dst, index: 1)
        encV.setBytes(&radius, length: MemoryLayout<Float>.size, index: 0)
        dispatch2D(enc: encV, w: dst.width, h: dst.height, pso: pBlurV)
        encV.endEncoding()
    }

    // MARK: - Dispatch helper
    private func dispatch2D(enc: MTLComputeCommandEncoder, w: Int, h: Int, pso: MTLComputePipelineState) {
        // Apple GPUs like 16x16 (or 8x8) for image kernels
        let tgW = min(16, pso.threadExecutionWidth)
        let tgH = max(1, min(16, pso.maxTotalThreadsPerThreadgroup / tgW))
        let tpg = MTLSize(width: tgW, height: tgH, depth: 1)
        let groups = MTLSize(width: (w + tgW - 1) / tgW, height: (h + tgH - 1) / tgH, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tpg)
    }

    // MARK: - Textures & Pools
    private func makeTex(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTex: CVMetalTexture?
        let res = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                            textureCache,
                                                            pixelBuffer,
                                                            nil,
                                                            pixelFormat,
                                                            width,
                                                            height,
                                                            0,
                                                            &cvTex)
        guard res == kCVReturnSuccess,
              let cv = cvTex,
              let tex = CVMetalTextureGetTexture(cv) else {
            return nil
        }
        return tex
    }

    private func makeTmpTex(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
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
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, attrs as CFDictionary, &pool)
        return pool
    }

    private func allocateFromPool(_ pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        return status == kCVReturnSuccess ? pb : nil
    }

    private func poolMatches(pool: CVPixelBufferPool?, width: Int, height: Int) -> Bool {
        guard let pool else { return false }
        guard let dict = CVPixelBufferPoolGetPixelBufferAttributes(pool) as? [String: Any] else {
            return false
        }
        return (dict[kCVPixelBufferWidthKey as String] as? Int == width) &&
               (dict[kCVPixelBufferHeightKey as String] as? Int == height)
    }
}

