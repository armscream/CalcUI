#version 460

//* UI fragment shader.
//
//* One pipeline for the whole UI: everything comes out of the one
//* atlas, so a window is one draw call. The vertex colour tints what
//* the texture holds.
//
//* A vertex says what its fragment is: a plain one samples the texture
//* as it is, and a rounded one cuts its corners with the distance to
//* the edge of a rounded rectangle.

//* SDL3 GPU resource layout for fragment shaders:
//*   set 2 = samplers and storage resources
//*   set 3 = uniform data
//* The sampler is bound to fragment slot 0, so it is binding 0 of set 2.
layout(set = 2, binding = 0) uniform sampler2D tex;

layout(location=0) in vec2 uv;
layout(location=1) in vec4 v_colour;
layout(location=2) in vec4 v_shape;
layout(location=3) in vec2 v_local;

layout(location=0) out vec4 frag_colour;

//* How far a point is outside of a rounded rectangle. The point is
//* measured from the middle of the rectangle.
float rounded_box(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - (half_size - vec2(radius));
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    float kind = v_shape.x;
    vec4 texel = texture(tex, uv);

    vec3 rgb = texel.rgb * v_colour.rgb;
    float alpha = texel.a * v_colour.a;

    if (kind > 0.5) {
        //* A rounded rectangle. The radius cannot be bigger than the
        //* rectangle itself.
        float radius = min(v_shape.y, min(v_shape.z, v_shape.w));
        float d = rounded_box(v_local, vec2(v_shape.z, v_shape.w), radius);
        //* One pixel of softness on the edge.
        float aa = max(fwidth(d), 0.0001);
        float cover = 1.0 - smoothstep(-aa, aa, d);

        if (kind < 1.5) {
            //* A solid shape: the texture is not used at all.
            rgb = v_colour.rgb;
            alpha = v_colour.a * cover;
        } else {
            alpha = alpha * cover;
        }
    }

    //* The output is premultiplied, matching the ONE /
    //* ONE_MINUS_SRC_ALPHA blend state of the pipeline.
    frag_colour = vec4(rgb * alpha, alpha);
}
