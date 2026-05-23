//! Sample a MSDF (multi-channel signed distance field) font atlas.
//!
//! You can think of an MSDF texture as a terrain/height map around the glyph:
//!
//!   - the glyph edge is the "coastline"
//!   - each texel stores approximately how far it is from a coastline
//!   - distance from the coastline corresponds to terrain height
//!
//! Unlike a normal old school grayscale distance field (SDF), MSDF stores edge distance
//! separately in the R/G/B channels. This preserves sharp corners.
//!
//! The GPU interpolates the R/G/B channels independently between texels.
//! Taking the median of those interpolated channels reconstructs the signed
//! distance to the nearest glyph edge.

struct FontUniform {
    view_proj: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> u: FontUniform;
@group(0) @binding(1) var font_atlas: texture_2d<f32>;
@group(0) @binding(2) var atlas_sampler: sampler;

// This is the information returned from the vertex shader that is automatically provided as input parameter for the fragment shader
// Note that all the values uv and color will be interpolated between the vertices before sent to the fragment shader
// You can return what you want from the vertex shader, as long as a position is provided (so it knows how to draw the triangle)
struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
};

@vertex
fn vs_main(
    // Slot 0 — shared unit 2D quad (two 2D triangles), same is used for all instances
    @location(0) quad_pos: vec2<f32>,
    // Slot 1 — per-glyph instance
    @location(1) dst_rect: vec4<f32>,   // x, y, w, h (world position and size)
    @location(2) uv_rect: vec4<f32>,    // u, v, uw, vh in normalised atlas [0..1]. 0,0 is the upper left of the texture
    @location(3) color: vec4<f32>,      // rgba tint
) -> VSOut {
    var out: VSOut;

    // Scale unit quad to the glyph's destination rectangle
    let world_pos = quad_pos * dst_rect.zw + dst_rect.xy;
    out.position = u.view_proj * vec4<f32>(world_pos, 0.0, 1.0);

    // Scale unit quad UV to the glyph's sub-region inside the atlas
    out.uv = quad_pos * uv_rect.zw + uv_rect.xy;

    out.color = color;

    return out;
}

fn median(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
    let distance_field = textureSample(font_atlas, atlas_sampler, in.uv);
    
    // The MSDF texture stores edge-distance information in the R/G/B channels.
    // We take the median (middle value) of the interpolated value as the signed distance
    let signed_distance = median(distance_field.r, distance_field.g, distance_field.b);

    // Fragment shaders are (typically) executed in parallel in small 2x2 groups.
    // fwidth() estimates how much that variable value changes across neighboring fragments.
    // It is kind of magical.
    let edge_softness = fwidth(signed_distance) * 0.5; // edge_softness is technically an `edge_width`

    // smoothstep() is like a clamped lerp with a cubic smoothing curve.
    // Smoothly fade opacity around the glyph edge for anti-aliasing.
    let alpha = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, signed_distance);

    return vec4<f32>(in.color.rgb, in.color.a * alpha);
}
