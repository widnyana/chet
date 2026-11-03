#include <metal_stdlib>
using namespace metal;

// Per rectangle: rect = (x, y, width, height) in 0...1 with y pointing down; color = rgba.
struct TreemapInstance {
    float4 rect;
    float4 color;
};

struct TreemapOut {
    float4 position [[position]];
    float4 color;
    float2 local;
    float2 sizePx;
};

vertex TreemapOut treemap_vertex(uint vid [[vertex_id]],
                                 uint iid [[instance_id]],
                                 const device TreemapInstance *instances [[buffer(0)]],
                                 constant float2 &viewport [[buffer(1)]]) {
    float2 corners[4] = {float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1)};
    TreemapInstance item = instances[iid];
    float2 corner = corners[vid];
    float2 p = item.rect.xy + corner * item.rect.zw;
    TreemapOut out;
    out.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
    out.color = item.color;
    out.local = corner;
    out.sizePx = item.rect.zw * viewport;
    return out;
}

// 1 px dark border between rectangles, soft top-to-bottom shading inside.
fragment float4 treemap_fragment(TreemapOut in [[stage_in]]) {
    float2 px = in.local * in.sizePx;
    float2 edge = min(px, in.sizePx - px);
    float border = min(edge.x, edge.y);
    float shade = border < 1.0 ? 0.55 : 1.0 - 0.15 * in.local.y;
    return float4(in.color.rgb * shade, 1);
}
