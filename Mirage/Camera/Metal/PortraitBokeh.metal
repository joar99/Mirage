#include <metal_stdlib>
using namespace metal;

// --- Common helpers ---------------------------------------------------------

inline float4 tent3(texture2d<float, access::sample> tex,
                    sampler s, float2 uv, float2 texel)
{
    // Simple tent (triangle) filter: 3x3 taps with weights:
    // 1 2 1
    // 2 4 2   (sum = 16)
    // 1 2 1
    float4 c = float4(0.0);
    c += tex.sample(s, uv + texel * float2(-1,-1)) * 1.0;
    c += tex.sample(s, uv + texel * float2( 0,-1)) * 2.0;
    c += tex.sample(s, uv + texel * float2( 1,-1)) * 1.0;

    c += tex.sample(s, uv + texel * float2(-1, 0)) * 2.0;
    c += tex.sample(s, uv)                           * 4.0;
    c += tex.sample(s, uv + texel * float2( 1, 0)) * 2.0;

    c += tex.sample(s, uv + texel * float2(-1, 1)) * 1.0;
    c += tex.sample(s, uv + texel * float2( 0, 1)) * 2.0;
    c += tex.sample(s, uv + texel * float2( 1, 1)) * 1.0;

    return c * (1.0 / 16.0);
}

// --- 2x downsample with box filter -----------------------------------------
// Reads 4 neighbors from the source at full res, writes a single pixel at half res.
// srcL? -> dst (1/2 size)
kernel void downsample2x_box(
    texture2d<float, access::sample> src    [[texture(0)]],
    texture2d<float, access::write>  dst    [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    // Map destination pixel coords to source
    float2 srcSize = float2(src.get_width(), src.get_height());
    float2 uv = (float2(gid) * 2.0 + 0.5) / srcSize; // center of 2x2 block

    // Box sample 2x2 (linear sampling with pixel coords is fine here)
    // Slight offset to gather corners
    float2 texel = 1.0 / srcSize;
    float4 c =
        src.sample(s, uv + texel * float2(-0.25, -0.25)) +
        src.sample(s, uv + texel * float2( 0.25, -0.25)) +
        src.sample(s, uv + texel * float2(-0.25,  0.25)) +
        src.sample(s, uv + texel * float2( 0.25,  0.25));

    dst.write(c * 0.25, gid);
}

// Proper Gaussian blur (approximates CIGaussianBlur)
// Two-pass separable: horizontal then vertical
kernel void blur_gaussian_h(
    texture2d<float, access::sample> src [[texture(0)]],
    texture2d<float, access::write>  dst [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size  = float2(dst.get_width(), dst.get_height());
    float2 uv    = (float2(gid) + 0.5) / size;
    float2 texel = float2(1.0 / size.x, 0.0);

    // Gaussian weights for radius ~3-4 pixels
    // For sigma = radius/2, these are approximate 9-tap weights
    float weights[9] = {
        0.05, 0.09, 0.12, 0.15, 0.18, 0.15, 0.12, 0.09, 0.05
    };

    float4 c = float4(0.0);
    for (int i = 0; i < 9; i++) {
        float offset = float(i - 4) * radius / 4.0;
        c += src.sample(s, uv + texel * offset) * weights[i];
    }

    dst.write(c, gid);
}

kernel void blur_gaussian_v(
    texture2d<float, access::sample> src [[texture(0)]],
    texture2d<float, access::write>  dst [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size  = float2(dst.get_width(), dst.get_height());
    float2 uv    = (float2(gid) + 0.5) / size;
    float2 texel = float2(0.0, 1.0 / size.y);

    float weights[9] = {
        0.05, 0.09, 0.12, 0.15, 0.18, 0.15, 0.12, 0.09, 0.05
    };

    float4 c = float4(0.0);
    for (int i = 0; i < 9; i++) {
        float offset = float(i - 4) * radius / 4.0;
        c += src.sample(s, uv + texel * offset) * weights[i];
    }

    dst.write(c, gid);
}

// --- Final composite --------------------------------------------------------
// Chooses a blur level by "bokeh" derived from depth, and keeps the person sharp by mask.
kernel void compositePortrait(
    // L0 is the original (full-res) image
    texture2d<float, access::sample> srcL0 [[texture(0)]], // full
    texture2d<float, access::sample> srcL1 [[texture(1)]], // 1/2 with blur
    texture2d<float, access::sample> srcL2 [[texture(2)]], // 1/4 with blur
    texture2d<float, access::sample> srcL3 [[texture(3)]], // 1/8 with blur

    // Depth & mask (normalized float, 0..1). Depth expected to be disparity in [0..1].
    texture2d<float, access::sample> depthTex [[texture(4)]],
    texture2d<float, access::sample> maskTex  [[texture(5)]],

    texture2d<float, access::write>  outTex   [[texture(6)]],

    constant float &bokehStrength [[buffer(0)]],   // 0..1 extra gain on blur
    constant float2 &invOutSize   [[buffer(1)]],   // 1 / (out width, out height)

    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    constexpr sampler snorm(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 uv = (float2(gid) + 0.5) * invOutSize;

    // Person mask: 1 = person (keep sharp), 0 = bg (blur)
    float person = smoothstep(0.3, 0.7, maskTex.sample(snorm, uv).r);

    // Depth to blur level. Assume disparity: near = high, far = low.
    float disp   = clamp(depthTex.sample(snorm, uv).r, 0.0, 1.0);
    float bokeh  = saturate((1.0 - disp) * (0.8 + 0.2 * bokehStrength)); // tweak curve a bit
    float level  = bokeh * 3.0; // map to [0..3]; 0: sharp, 1..3: L1..L3

    // Sample sharp
    float4 sharp = srcL0.sample(snorm, uv);

    // Pick blurred sample by LOD between L1/L2/L3
    float l = floor(level);
    float t = saturate(level - l);

    float4 b0 = (l < 1.0) ? srcL1.sample(snorm, uv)
              : (l < 2.0) ? srcL2.sample(snorm, uv)
                          : srcL3.sample(snorm, uv);

    float4 b1 = (l < 1.0) ? srcL2.sample(snorm, uv)
              : (l < 2.0) ? srcL3.sample(snorm, uv)
                          : srcL3.sample(snorm, uv);

    float4 blurred = mix(b0, b1, t);

    // Early out: if person ~1, write sharp (saves work on hot paths)
    if (person > 0.98) {
        outTex.write(sharp, gid);
        return;
    }

    // Mix: keep person sharp, bg blurred
    float4 out = mix(blurred, sharp, person);
    // outTex.write(out, gid);
    outTex.write(srcL2.sample(snorm, uv), gid);
}

// Utility
inline float saturate(float v) { return clamp(v, 0.0, 1.0); }
