#include <metal_stdlib>
using namespace metal;

// Simple box blur helper
float4 sampleBlur(texture2d<float, access::sample> texture,
                  float2 coord,
                  float radius,
                  sampler textureSampler) {
    float4 color = float4(0.0);
    float totalWeight = 0.0;

    int iRadius = int(ceil(radius));
    float2 texelSize = float2(1.0) / float2(texture.get_width(), texture.get_height());

    for (int y = -iRadius; y <= iRadius; y++) {
        for (int x = -iRadius; x <= iRadius; x++) {
            float2 offset = float2(x, y) * texelSize;
            float dist = length(float2(x, y));

            if (dist <= radius) {
                float weight = 1.0 - (dist / radius);
                color += texture.sample(textureSampler, coord + offset) * weight;
                totalWeight += weight;
            }
        }
    }

    return totalWeight > 0.0 ? color / totalWeight : color;
}

kernel void portraitBlurKernel(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::sample> depthTexture [[texture(1)]],
    texture2d<float, access::sample> maskTexture [[texture(2)]],
    texture2d<float, access::write> outputTexture [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    constexpr sampler textureSampler(coord::normalized,
                                     address::clamp_to_edge,
                                     filter::linear);

    // Normalized coordinates
    float2 coord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());

    // Sample mask (person = high value, background = low value)
    float maskValue = maskTexture.sample(textureSampler, coord).r;

    // Sample depth (disparity - higher = closer)
    float depth = depthTexture.sample(textureSampler, coord).r;

    // Calculate blur radius based on depth
    // Closer objects (high disparity) = less blur
    // Far objects (low disparity) = more blur
    float maxBlurRadius = 15.0; // Adjust this
    float blurRadius = (1.0 - depth) * maxBlurRadius;

    // Apply blur
    float4 blurredColor = sampleBlur(inputTexture, coord, blurRadius, textureSampler);

    // Sample sharp pixel
    float4 sharpColor = inputTexture.sample(textureSampler, coord);

    // Blend: mask close to 1.0 = person (keep sharp), close to 0.0 = background (blur)
    // Soften the mask edge a bit
    float smoothMask = smoothstep(0.3, 0.7, maskValue);
    float4 finalColor = mix(blurredColor, sharpColor, smoothMask);

    outputTexture.write(finalColor, gid);
}
