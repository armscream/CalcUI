package Core

import "core:math"

sdf_rounded_box :: proc(p: [2]f32, half_size: [2]f32, radii: [4]f32) -> f32 {
	radius: f32
	if p.x < 0 {
		radius = p.y < 0 ? radii[0] : radii[3]
	} else {
		radius = p.y < 0 ? radii[1] : radii[2]
	}
	q := [2]f32 {
		abs(p.x) - (half_size[0] - radius),
		abs(p.y) - (half_size[1] - radius),
	}
	qx := max(q[0], 0)
	qy := max(q[1], 0)
	return math.sqrt(qx * qx + qy * qy) + min(max(q[0], q[1]), 0) - radius
}

sdf_coverage :: proc(d, aa: f32) -> f32 {
	if aa <= 0 {
		return d <= 0 ? 1 : 0
	}
	t := clamp((d + aa) / (2 * aa), 0, 1)
	return 1 - t * t * (3 - 2 * t)
}

sdf_shadow_coverage :: proc(d, softness: f32) -> f32 {
	soft := max(abs(softness), 0.0001)
	t := clamp(d / soft, 0, 1)
	return 1 - t * t * (3 - 2 * t)
}

sdf_inset_coverage :: proc(d, spread, softness, aa: f32) -> f32 {
	soft := max(abs(softness), 0.0001)
	depth := -d - spread
	t := clamp(depth / soft, 0, 1)
	outer := 1 - t * t * (3 - 2 * t)
	return outer * sdf_coverage(d, aa)
}

sdf_border_coverage :: proc(outer_d, inner_d, outer_aa, inner_aa: f32) -> f32 {
	return clamp(sdf_coverage(outer_d, outer_aa) - sdf_coverage(inner_d, inner_aa), 0, 1)
}
