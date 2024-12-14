//
//  Shaders.metal
//  iPhoneScreenExtender
//
//  Created by Arman Mahjoor on 12/14/24.
//

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
    out.position = float4(position.xy, 0.0, 1.0);
    out.texCoord = position.zw;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return texture.sample(textureSampler, in.texCoord);
} 
