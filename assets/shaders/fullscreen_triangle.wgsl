//! Fullscreen triangle.
//!
//! Generates a single hacky, oversized triangle that covers
//! the viewport.
//! [article](https://webgpufundamentals.org/webgpu/lessons/webgpu-large-triangle-to-cover-clip-space.html)

@group(0) @binding(0) var texture: texture_2d<f32>;
@group(0) @binding(1) var texture_sampler: sampler;

struct VSOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VSOut {
    var out: VSOut;
    // HACK: Fullscreen triangle that covers the screen
    // we use the builtin `vertex_index` as a hack to calculate the corner (vertex)

    let x = f32(i32(vi & 1u) * 4 - 1);  // -1, 3, -1. (odd vertex indices become 3)
    let y = f32(i32(vi & 2u) * 2 - 1);  // -1, -1, 3. (vertex indices >= 2 become 3)

    out.position = vec4<f32>(x, y, 0.0, 1.0);
    
    // UVs will be outside of [0,1], but clipping produces the
    // correct mapping inside the viewport.
    out.uv = vec2<f32>((x + 1.0) * 0.5, (1.0 - y) * 0.5); // `y` is flipped because texture coordinates are top-left origin

    return out;
}

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4<f32> {
    let color = textureSample(texture, texture_sampler, in.uv);
    return vec4<f32>(color.rgb, color.a);
}