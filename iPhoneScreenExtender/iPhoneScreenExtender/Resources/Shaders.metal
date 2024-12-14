#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                             constant float4* vertices [[buffer(0)]]) {
    VertexOut out;
    float4 position = vertices[vertexID];
    
    // Validate and clamp position values
    float2 clampedXY = clamp(position.xy, float2(-1.0), float2(1.0));
    float2 clampedZW = clamp(position.zw, float2(0.0), float2(1.0));
    
    out.position = float4(clampedXY, 0.0, 1.0);
    out.texCoord = clampedZW;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, 
                                   min_filter::linear,
                                   address::clamp_to_edge);
    
    // Validate and clamp texture coordinates
    float2 clampedCoords = clamp(in.texCoord, float2(0.0), float2(1.0));
    float4 color = texture.sample(textureSampler, clampedCoords);
    
    // Ensure color values are valid
    return select(float4(0.0), color, !isnan(color));
}