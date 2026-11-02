#version 460

//* UI fragment shader.
//
//* One pipeline for the whole UI: solid quads sample a 1x1 white texel
//* and glyphs sample the atlas page, so the vertex colour tints both.
//* The output is premultiplied, matching the ONE / ONE_MINUS_SRC_ALPHA
//* blend state of the pipeline.

//* SDL3 GPU resource layout for fragment shaders:
//*   set 2 = samplers and storage resources
//*   set 3 = uniform data
//* The sampler is bound to fragment slot 0, so it is binding 0 of set 2.
layout(set = 2, binding = 0) uniform sampler2D tex;

layout(location=0) in vec2 uv;
layout(location=1) in vec4 v_colour;

layout(location=0) out vec4 frag_colour;

void main() {
    vec4 c = texture(tex, uv) * v_colour;
    frag_colour = vec4(c.rgb * c.a, c.a);
}
