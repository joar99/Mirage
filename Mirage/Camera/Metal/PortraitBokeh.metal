#include <metal_stdlib>
using namespace metal;

kernel void downsample2x_box(texture2d<float, access::sample> src    [[texture(0)]], texture2d<float, access::write>  dst    [[texture(1)]], uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 srcSize = float2(src.get_width(), src.get_height());
    float2 uv = (float2(gid) * 2.0 + 0.5) / srcSize;

    float2 texel = 1.0 / srcSize;
    float4 c =
        src.sample(s, uv + texel * float2(-0.25, -0.25)) +
        src.sample(s, uv + texel * float2( 0.25, -0.25)) +
        src.sample(s, uv + texel * float2(-0.25,  0.25)) +
        src.sample(s, uv + texel * float2( 0.25,  0.25));

    dst.write(c * 0.25, gid);
}

kernel void blur_gaussian_h(texture2d<float, access::sample> src [[texture(0)]], texture2d<float, access::write>  dst [[texture(1)]], uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size  = float2(dst.get_width(), dst.get_height());
    float2 uv    = (float2(gid) + 0.5) / size;
    float2 texel = float2(1.0 / size.x, 0.0);

    float weights[9] = {0.05, 0.09, 0.12, 0.15, 0.18, 0.15, 0.12, 0.09, 0.05};

    float4 c = float4(0.0);
    for (int i = 0; i < 9; i++) {
        float offset = float(i - 4);
        c += src.sample(s, uv + texel * offset) * weights[i];
    }

    dst.write(c, gid);
}

kernel void blur_gaussian_v(texture2d<float, access::sample> src [[texture(0)]], texture2d<float, access::write>  dst [[texture(1)]], uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size  = float2(dst.get_width(), dst.get_height());
    float2 uv    = (float2(gid) + 0.5) / size;
    float2 texel = float2(0.0, 1.0 / size.y);

    float weights[9] = {0.05, 0.09, 0.12, 0.15, 0.18, 0.15, 0.12, 0.09, 0.05};

    float4 c = float4(0.0);
    for (int i = 0; i < 9; i++) {
        float offset = float(i - 4);
        c += src.sample(s, uv + texel * offset) * weights[i];
    }

    dst.write(c, gid);
}

kernel void compositePortraitSimple(texture2d<float, access::sample> srcSharp [[texture(0)]], texture2d<float, access::sample> srcBlurred [[texture(1)]], texture2d<float, access::sample> maskTex [[texture(2)]], texture2d<float, access::write>  outTex [[texture(3)]], constant float2 &invOutSize [[buffer(0)]], uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    constexpr sampler snorm(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) * invOutSize;

    float person = smoothstep(0.3, 0.7, maskTex.sample(snorm, uv).r);

    float4 sharp = srcSharp.sample(snorm, uv);
    float4 blurred = srcBlurred.sample(snorm, uv);

    float4 out = mix(blurred, sharp, person);

    outTex.write(out, gid);
}
