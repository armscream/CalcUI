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

//* The metrics that map a physical pixel to the backdrop, and the length
//* of the mip chain the glass samples.
layout(set = 3, binding = 0) uniform Glass_UBO {
    vec4 metrics;
    vec4 levels;
};

layout(location=0) in vec2 uv;
layout(location=1) in vec4 v_colour;
layout(location=2) in vec4 v_shape;
layout(location=3) in vec2 v_local;
layout(location=4) in vec4 v_corners;
layout(location=5) in vec4 v_border;
layout(location=6) in float v_opacity;

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

        if (kind > 4.5) {
            //* Glass: the shared backdrop is bound to `tex`. Level zero is
            //* a half resolution copy of the whole window and every level
            //* after it is half of the level before, so a physical pixel
            //* maps to the same place of the window at every level.
            vec2 target_size = metrics.zw;
            vec2 backdrop_scale = metrics.xy;
            float max_level = max(levels.x - 1.0, 0.0);

            float blur = max(v_shape.y, 0.0);
            //* Level zero is two physical pixels wide, so a blur of four
            //* wants level one.
            float lod = clamp(log2(max(blur, 1.0) / 2.0), 0.0, max_level);
            float refraction = max(v_border.x, 0.0);
            float dispersion = max(v_border.y, 0.0);
            float fresnel = max(v_border.z, 0.0);
            float saturation = v_border.w;
            bool optics = refraction > 0.0 || dispersion > 0.0 ||
                fresnel > 0.0 || saturation != 0.0;

            vec2 shift = vec2(0.0);
            vec2 outward = vec2(0.0, 1.0);
            vec3 glass_normal = vec3(0.0, 0.0, 1.0);
            if (optics) {
                float band = clamp(
                    max(max(radii.x, radii.y), max(radii.z, radii.w)),
                    8.0,
                    min(half_size.x, half_size.y)
                );
                float rim = 1.0 - smoothstep(0.0, band, -d);
                float bend = rim * rim;

                if (refraction > 0.0 || dispersion > 0.0) {
                    float d_dx = rounded_box(v_local + vec2(1.0, 0.0), half_size, radii);
                    float d_dy = rounded_box(v_local + vec2(0.0, 1.0), half_size, radii);
                    vec2 grad = vec2(d_dx - d, d_dy - d);
                    float grad_len = length(grad);
                    if (grad_len > 0.00001) { outward = grad / grad_len; }
                }

                float theta = bend * 0.55;
                glass_normal = normalize(vec3(outward * sin(theta), cos(theta)));

                vec3 ray = refract(vec3(0.0, 0.0, -1.0), glass_normal, 1.0 / 1.5);
                shift = ray.xy * (refraction / 0.19286);
            }

            vec2 centre_uv = (gl_FragCoord.xy + shift) / target_size;
            vec3 back = vec3(0.0);

            vec3 grad_x = vec3(0.0);
            vec3 grad_y = vec3(0.0);
            if (blur > 8.0) {
                //* One trilinear tap of the chain replaces the Gaussian.
                back = textureLod(tex, centre_uv, lod).rgb;

                if (optics && dispersion > 0.0) {
                    //* The split needs a less blurred picture. Four taps of
                    //* the level two steps sharper give the gradient, with
                    //* the normalisation of the old kernel.
                    float lod_g = max(lod - 2.0, 0.0);
                    float off = max(blur * 0.5, 1.0);
                    vec2 duv = vec2(off) / target_size;
                    vec3 right = textureLod(tex, centre_uv + vec2(duv.x, 0.0), lod_g).rgb;
                    vec3 left = textureLod(tex, centre_uv - vec2(duv.x, 0.0), lod_g).rgb;
                    vec3 down = textureLod(tex, centre_uv + vec2(0.0, duv.y), lod_g).rgb;
                    vec3 up = textureLod(tex, centre_uv - vec2(0.0, duv.y), lod_g).rgb;
                    grad_x = -(right - left) / (2.0 * off);
                    grad_y = -(down - up) / (2.0 * off);
                }
            } else if (blur > 0.5) {
                //* A thin surface keeps the small kernel and its sharp
                //* dispersion.
                int R = blur > 18.0 ? 1 : 2;
                float spread = blur / float(R);
                float sigma = max(blur * (R == 1 ? 0.7 : 0.5), 0.5);
                vec3 acc = vec3(0.0);
                vec3 score_x = vec3(0.0);
                vec3 score_y = vec3(0.0);
                float weight_sum = 0.0;
                for (int y = -R; y <= R; ++y) {
                    for (int x = -R; x <= R; ++x) {
                        float dist = float(x * x + y * y) * spread * spread;
                        float weight = exp(-dist / (2.0 * sigma * sigma));
                        vec2 offset = vec2(float(x), float(y)) * spread;
                        vec2 tap_uv = (gl_FragCoord.xy + shift + offset) / target_size;
                        vec3 tap = textureLod(tex, tap_uv, 0.0).rgb;
                        acc += tap * weight;
                        weight_sum += weight;
                        if (optics && dispersion > 0.0) {
                            score_x += tap * weight * offset.x;
                            score_y += tap * weight * offset.y;
                        }
                    }
                }
                back = acc / max(weight_sum, 0.0001);
                if (optics && dispersion > 0.0) {
                    float norm = sigma * sigma * max(weight_sum, 0.0001);
                    grad_x = -score_x / norm;
                    grad_y = -score_y / norm;
                }
            } else {
                back = textureLod(tex, centre_uv, 0.0).rgb;
            }

            if (optics && dispersion > 0.0) {
                vec3 change = (grad_x * outward.x + grad_y * outward.y) * dispersion;
                back.r += change.r;
                back.b -= change.b;
            }

            if (optics && saturation != 0.0) {
                float luma = dot(back, vec3(0.2126, 0.7152, 0.0722));
                back = mix(vec3(luma), back, saturation);
            }

            //* A sheen down from the top edge and a light rim inside the
            //* border give the surface its liquid look.
            vec2 q = v_local / max(half_size, vec2(1.0));
            float sheen = smoothstep(0.1, -0.85, q.y) * 0.07;
            float rim_light = exp(-max(d, 0.0) * 1.5) * 0.05;
            if (optics && fresnel > 0.0) {
                float viewer_distance = max(min(target_size.x, target_size.y) * 0.25, 1.0);
                vec3 view_dir = normalize(
                    vec3(target_size * 0.5 - gl_FragCoord.xy, viewer_distance)
                );
                vec3 light_dir = normalize(vec3(-0.7, -0.7, 0.25));
                vec3 half_dir = normalize(light_dir + view_dir);
                float facing = 1.0 - clamp(dot(glass_normal, view_dir), 0.0, 1.0);
                float facing2 = facing * facing;
                float facing5 = facing2 * facing2 * facing;
                float nh = max(dot(glass_normal, half_dir), 0.0);
                float nh2 = nh * nh;
                float nh4 = nh2 * nh2;
                float nh8 = nh4 * nh4;
                float nh16 = nh8 * nh8;
                float nh32 = nh16 * nh16;
                float nh48 = nh32 * nh16;
                float schlick = fresnel * facing5;
                float highlight = fresnel * 0.7 * nh48;
                rim_light = schlick + highlight;
            }

            float tint_alpha = v_colour.a;
            if (optics) {
                float luma = dot(back, vec3(0.299, 0.587, 0.114));
                tint_alpha = clamp(v_colour.a * (1.35 - 0.7 * luma), 0.0, 1.0);
            }

            vec3 glass = mix(back, v_colour.rgb, tint_alpha);
            glass += vec3(sheen + rim_light);
            glass *= 1.0 - 0.05 * smoothstep(-0.1, 1.0, q.y);

            float aa = max(fwidth(d), 0.0001);
            float cover = 1.0 - smoothstep(-aa, aa, d);
            rgb = glass;
            alpha = cover * v_opacity;
        } else if (kind > 3.5) {
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
            float signed_softness = v_shape.y;
            float cover;
            if (signed_softness < 0.0) {
                float spread = v_border.x;
                vec2 offset = vec2(v_border.y, v_border.z);
                float inner_d = rounded_box(v_local - offset, half_size, radii);
                float depth = -inner_d - spread;
                float soft = max(abs(signed_softness), 0.0001);
                float t = clamp(depth / soft, 0.0, 1.0);
                float fade = 1.0 - t * t * (3.0 - 2.0 * t);
                float inner_aa = max(fwidth(inner_d), 0.0001);
                float inside = 1.0 - smoothstep(-inner_aa, inner_aa, inner_d);
                cover = fade * inside;
            } else {
                float soft = max(abs(signed_softness), 0.0001);
                cover = 1.0 - smoothstep(0.0, soft, d);
            }
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
