#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    const float2 vertices[] = {
        float2(-1, -1), // Bottom left
        float2(-1,  1), // Top left
        float2( 1, -1), // Bottom right
        float2( 1,  1), // Top right
    };
    
    const float2 texCoords[] = {
        float2(0, 1),
        float2(0, 0),
        float2(1, 1),
        float2(1, 0),
    };
    
    VertexOut out;
    out.position = float4(vertices[vertexID], 0, 1);
    out.texCoord = texCoords[vertexID];
    
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return texture.sample(textureSampler, in.texCoord);
} 