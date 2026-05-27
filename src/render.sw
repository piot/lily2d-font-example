use lily::wgpu_types::{Vec4f, Vec2f, Mat4f}
use lily::wgpu
use lily::bmf
use lily::gm
mod simulation::{ExampleSimulation}

/// Per-glyph instance: destination rect, atlas UV rect, and color (48 bytes, matches glyph_render.wgsl)
struct GlyphInstance {
    dst_rect: Vec4f  // x, y, w, h  in offscreen pixels
    uv_rect: Vec4f   // u, v, uw, vh in normalised atlas [0..1]
    color: Vec4f     // rgba tint
}

/// Uniform for the glyph render pass
#[repr(uniform)]
struct FontUniform {
    view_proj: Mat4f
}

/// Shared unit quad — one quad reused for every glyph instance
const GLYPH_QUAD_VERTICES: Block<Vec2f; 4> = [
    [ 0.0, 0.0 ]
    [ 1.0, 0.0 ]
    [ 1.0, 1.0 ]
    [ 0.0, 1.0 ]
]
const GLYPH_QUAD_INDICES: Block<U16; 6> = [ 
    0, 1, 2 
    0, 2, 3
]

struct ExampleRender {

    // background things
    background_pipeline: wgpu::RenderPipelineHandle
    background_pipeline_layout: wgpu::PipelineLayoutHandle
    background_bind_group_layout: wgpu::BindGroupLayoutHandle
    background_bind_group: wgpu::BindGroupHandle



    font_atlas_texture: wgpu::TextureHandle
    font_atlas_texture_view: wgpu::TextureViewHandle

    bm_font: bmf::BmFont

    glyph_pipeline_layout: wgpu::PipelineLayoutHandle
    glyph_bind_group_layout: wgpu::BindGroupLayoutHandle

    glyph_quad_vertices: wgpu::BufferHandle
    glyph_quad_indices: wgpu::BufferHandle

    glyph_pipeline: wgpu::RenderPipelineHandle
    glyph_bind_group: wgpu::BindGroupHandle

    glyph_uniform_buffer: wgpu::BufferHandle
    glyph_instance_buffer: wgpu::BufferHandle
}

impl ExampleRender {
    fn new() -> ExampleRender {

        // Background layout and pipeline
        background_bind_group_layout := wgpu::create_bind_group_layout([
            { binding: 0, ty: Texture },
            { binding: 1, ty: Sampler }
        ], 'background bind group layout')

        background_pipeline_layout := wgpu::create_pipeline_layout([background_bind_group_layout], 'background pipeline layout')

        empty_vertex_layouts: [wgpu::VertexBufferLayout; 0] = []
        background_pipeline := wgpu::create_render_pipeline(background_pipeline_layout, empty_vertex_layouts, @shaders/fullscreen_triangle.wgsl, Alpha, Back, false, 'background pipeline')

        background_sampler_config := wgpu::SamplerConfig {
            address_mode: ClampToEdge
            mag_filter: Linear
            min_filter: Linear
        }

        // Background texture, sampler and bind group
        background_texture := wgpu::create_texture_png(@images/water_lily_2018.png, Rgba8Unorm, RenderAndSample, 'background texture')
        background_texture_view := wgpu::create_texture_view(background_texture, 'background texture view')

        background_sampler := wgpu::create_sampler(background_sampler_config, 'background sampler')
        background_bind_group := wgpu::create_bind_group(background_pipeline_layout, [
            TextureView(background_texture_view),
            Sampler(background_sampler)
        ], 'background bind group')


        // Font
        font_atlas_texture := wgpu::create_texture_png(@fonts/example.png, Rgba8Unorm, RenderAndSample, 'font atlas')
        font_atlas_texture_view := wgpu::create_texture_view(font_atlas_texture, 'font atlas view')

        msdf_sampler_config := wgpu::SamplerConfig {
            address_mode: ClampToEdge
            mag_filter: Linear
            min_filter: Linear
        }

        msdf_atlas_sampler := wgpu::create_sampler(msdf_sampler_config, 'linear sampler for msdf atlas')

        // === Glyph instanced rendering (same structure as tilemap) ===
        glyph_quad_vertices := wgpu::create_vertex_buffer(GLYPH_QUAD_VERTICES, 'glyph quad vertices')
        glyph_quad_indices := wgpu::create_index_buffer_u16(GLYPH_QUAD_INDICES, 'glyph quad indices')
        // Pre-allocated instance buffer: up to 256 glyphs × 48 bytes each
        glyph_instance_buffer := wgpu::create_buffer(256 * size_of::<GlyphInstance>, Vertex, 'glyph instance buffer')

        font_uniform := FontUniform {
            view_proj: gm::Mat4::ortho_2d_pixel_near_far_int(512, 512, 0, 256).to_mat4f()
        }

        glyph_uniform_buffer := wgpu::create_uniform_buffer(font_uniform, 'font uniform')

        glyph_bind_group_layout := wgpu::create_bind_group_layout([
            { binding: 0, ty: Buffer(Uniform) },
            { binding: 1, ty: Texture },
            { binding: 2, ty: Sampler }
        ], 'glyph bind group layout')

        glyph_bind_group := wgpu::create_bind_group(glyph_bind_group_layout, [
            Buffer(glyph_uniform_buffer),
            TextureView(font_atlas_texture_view),
            Sampler(msdf_atlas_sampler)
        ], 'glyph bind group')

        glyph_pipeline_layout := wgpu::create_pipeline_layout([glyph_bind_group_layout], 'glyph pipeline layout')

        // Slot 0: unit quad positions (Vertex step)
        glyph_quad_layout := wgpu::VertexBufferLayout {
            array_stride: size_of::<Vec2f>  // Vec2f = 2 × F32 = 8 bytes
            vertex_attribute: [
                wgpu::VertexAttribute {
                    offset: 0
                    location: 0
                    format: Float32x2
                },
            ],
            vertex_attribute_count: 1
            step_mode: Vertex
        }


        // Slot 1: GlyphInstance layout: per-glyph instance data (Instance step)
        glyph_instance_layout := wgpu::VertexBufferLayout {
            array_stride: size_of::<GlyphInstance>
            vertex_attribute: [
                wgpu::VertexAttribute {
                    offset: offset_of::<GlyphInstance::dst_rect>
                    location: 1
                    format: Float32x4
                },
                wgpu::VertexAttribute {
                    offset: offset_of::<GlyphInstance::uv_rect>
                    location: 2
                    format: Float32x4
                },
                wgpu::VertexAttribute {
                    offset: offset_of::<GlyphInstance::color>
                    location: 3
                    format: Float32x4
                },
            ],
            vertex_attribute_count: 3
            step_mode: Instance
        }

        glyph_pipeline := wgpu::create_render_pipeline(
            glyph_pipeline_layout,
            [glyph_quad_layout, glyph_instance_layout],
            @shaders/glyph_render.wgsl,
            Alpha, None, false,
            'glyph render pipeline'
        )

        fnt: bmf::BmFontRes = @fonts/example.fnt

        {
            bm_font: fnt.load()

            background_pipeline: background_pipeline
            background_pipeline_layout: background_pipeline_layout
            background_bind_group_layout: background_bind_group_layout
            background_bind_group: background_bind_group

            font_atlas_texture: font_atlas_texture
            font_atlas_texture_view: font_atlas_texture_view


            glyph_quad_vertices: glyph_quad_vertices
            glyph_quad_indices: glyph_quad_indices
            glyph_instance_buffer: glyph_instance_buffer
            glyph_uniform_buffer: glyph_uniform_buffer
            glyph_bind_group_layout: glyph_bind_group_layout
            glyph_bind_group: glyph_bind_group
            glyph_pipeline_layout: glyph_pipeline_layout
            glyph_pipeline: glyph_pipeline
        }
    }


    #[host_call]
    fn render(mut self, sim: ExampleSimulation) {
        normalized_int_time := sim.time % 62800
        normalized_float_time := (normalized_int_time.float() * 0.1)

        // Build glyph instance data by iterating the string — atlas is 248×237 px (from .fnt scaleW/scaleH)
        atlas_w := 248.0
        atlas_h := 237.0

        mut instances: Block<GlyphInstance; 32>
        mut glyph_count := 0
        mut pen_x := 40.0
        pen_y := 300.0

        cool_factor := 0.6 + (((normalized_float_time * 0.15 ).cos() + 1.0) * 0.5) * 4.0
        factor_x := cool_factor
        factor_y := cool_factor

        codepoints: Vec<Char; 32> = "#Hello Lily2D!".chars() // we call chars() since we want the Codepoint (Unicode) instead of a U8

        for idx, codepoint in codepoints {
            g := .bm_font.glyphs[codepoint]
            u := g.x.float().div(atlas_w)
            v := g.y.float().div(atlas_h)
            uw := g.width.float().div(atlas_w)
            vh := g.height.float().div(atlas_h)
            dst_x := pen_x + g.x_offset.float() 
            dst_y := pen_y - g.y_offset.float() * factor_y // Font assumes y going down, so we invert it
            modified_y := (normalized_float_time + idx.float()).sin() * 5.0
            fun_y := dst_y - modified_y
            modified_intensity := 0.3 + ((normalized_float_time * 0.4 + idx.float() * 0.5).cos() + 1.0 ) * 0.7
            alpha := 
                | idx != 0 -> 1.0 
                | _ -> 0.4
            instances[glyph_count] = GlyphInstance {
                dst_rect: Vec4f { 
                    x: dst_x
                    y: fun_y
                    z: g.width.float() * factor_x
                    w: -g.height.float() * factor_y // Font assumes y going down, so we invert it
                }
                uv_rect: Vec4f { x: u, y: v, z: uw, w: vh }
                color: Vec4f { x: modified_intensity, y: 0.1, z: modified_intensity * 0.3, w: alpha }
            }
            glyph_count += 1
            pen_x = pen_x + g.x_advance.float() * factor_x
        }

        .glyph_instance_buffer.write(instances)

        // PASS: Render glyphs
        {
            mut render_pass: wgpu::RenderPass
            render_pass.depth_attachment = -1

            // Render Background as a fullscreen triangle
            // No vertex buffer is needed, since it calculates the corners in the shader.
            render_pass.set_pipeline(.background_pipeline)
            render_pass.set_bind_group( group_index: 0, bind_group: .background_bind_group )
            render_pass.draw( [0, 3], [0, 1] )

            // MSDF Font
            render_pass.set_pipeline(.glyph_pipeline)
            render_pass.set_bind_group( group_index: 0, bind_group: .glyph_bind_group )
            render_pass.set_vertex_buffer( slot: 0, vertex_buffer: .glyph_quad_vertices )
            render_pass.set_vertex_buffer( slot: 1, vertex_buffer: .glyph_instance_buffer )
            render_pass.set_index_buffer( .glyph_quad_indices )
            render_pass.draw_indexed( [0, 6], [0, glyph_count] ) // instanced rendering. reuse two triangles (quad) to render all glyphs

            wgpu::add_pass(render_pass, 'render glyphs to screen')
        }
    }

    #[host_call]
    fn resize(mut self) {
        
    }
}
