#version 460

//* UI fragment shader.
//
//* One pipeline for the whole UI: everything comes out of the one
//* atlas, so a window is one draw call. The vertex colour tints what
//* the texture holds.
//
//* A vertex says what its fragment is: a plain one samples the texture
//* as it is, and a shaped one cuts its corners with the distance to the
//* edge of a rounded rectangle.

//* SDL3 GPU resource layout for fragment shaders:
//*   set 2 = samplers and storage resources
//*   set 3 = uniform data
//* The sampler is bound to fragment slot 0, so it is binding 0 of set 2.
layout(set = 2, binding = 0) uniform sampler2D tex;

layout(location=0) in vec2 uv;
layout(location=1) in vec4 v_colour;
layout(location=2) in vec4 v_shape;
layout(location=3) in vec2 v_local;
layout(location=4) in float v_softness;
layout(location=5) in vec4 v_corners;
layout(location=6) in vec4 v_border;

layout(location=0) out vec4 frag_colour;

vec4 clamp_corner_radii(vec4 radii, vec2 half_size) {
    float limit = min(half_size.x, half_size.y);
    vec4 r = clamp(radii, vec4(0.0), vec4(limit));
    float w = half_size.x * 2.0;
    float h = half_size.y * 2.0;
    if (r.x + r.y > w) { float s = w / (r.x + r.y); r.x *= s; r.y *= s; }
    if (r.w + r.z > w) { float s = w / (r.w + r.z); r.w *= s; r.z *= s; }
    if (r.x + r.w > h) { float s = h / (r.x + r.w); r.x *= s; r.w *= s; }
    if (r.y + r.z > h) { float s = h / (r.y + r.z); r.y *= s; r.z *= s; }
    return r;
}

float rounded_box(vec2 p, vec2 half_size, vec4 corner_radii) {
    float radius = (p.x < 0.0)
        ? ((p.y < 0.0) ? corner_radii.x : corner_radii.w)
        : ((p.y < 0.0) ? corner_radii.y : corner_radii.z);
    vec2 q = abs(p) - (half_size - vec2(radius));
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    float kind = v_shape.x;
    vec4 texel = texture(tex, uv);

    vec3 rgb = texel.rgb * v_colour.rgb;
    float alpha = texel.a * v_colour.a;

    if (kind > 0.5) {
        vec2 half_size = vec2(v_shape.z, v_shape.w);
        vec4 radii = clamp_corner_radii(v_corners, half_size);
        float d = rounded_box(v_local, half_size, radii);

        if (kind > 3.5) {
            vec4 bw = max(v_border, vec4(0.0));
            vec2 inner_half = max(
                half_size - vec2(0.5 * (bw.x + bw.z), 0.5 * (bw.y + bw.w)),
                vec2(0.0)
            );
            vec2 inner_centre = vec2(0.5 * (bw.x - bw.z), 0.5 * (bw.y - bw.w));
            vec4 inner_radii = max(
                radii - vec4(
                    max(bw.x, bw.y),
                    max(bw.y, bw.z),
                    max(bw.z, bw.w),
                    max(bw.w, bw.x)
                ),
                vec4(0.0)
            );
            inner_radii = clamp_corner_radii(inner_radii, inner_half);

            float aa = max(fwidth(d), 0.0001);
            float outer_cover = 1.0 - smoothstep(-aa, aa, d);
            float border_cover = outer_cover;
            if (inner_half.x > 0.0 && inner_half.y > 0.0) {
                float inner_d = rounded_box(v_local - inner_centre, inner_half, inner_radii);
                float inner_aa = max(fwidth(inner_d), 0.0001);
                float inner_cover = 1.0 - smoothstep(-inner_aa, inner_aa, inner_d);
                border_cover = clamp(outer_cover - inner_cover, 0.0, 1.0);
            }

            rgb = v_colour.rgb;
            alpha = v_colour.a * border_cover;
        } else if (kind > 2.5) {
            float softness = max(v_softness, 0.0001);
            float cover = 1.0 - smoothstep(0.0, softness, d);
            rgb = v_colour.rgb;
            alpha = v_colour.a * cover;
        } else {
            float aa = max(fwidth(d), 0.0001);
            float cover = 1.0 - smoothstep(-aa, aa, d);

            if (kind < 1.5) {
                rgb = v_colour.rgb;
                alpha = v_colour.a * cover;
            } else {
                alpha = alpha * cover;
            }
        }
    }

    //* The output is premultiplied, matching the ONE /
    //* ONE_MINUS_SRC_ALPHA blend state of the pipeline.
    frag_colour = vec4(rgb * alpha, alpha);
}
