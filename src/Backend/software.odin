//* A software backend that consumes the real draw list and evaluates the
//* same shapes and glass the SDL3 GPU shader does. It is a correctness and
//* screenshot tool: single-threaded, no window, no GPU.
package Backend

import "core:fmt"
import "core:math"
import "core:os"
import GUI "../GUI"

Software_State :: struct {
	pixels:      []u8,
	width:       i32,
	height:      i32,
	target:      []u8,
	target_w:    i32,
	target_h:    i32,
	backdrop:    []u8,
	backdrop_w:  i32,
	backdrop_h:  i32,
	//* Levels one and up of the backdrop pyramid. Level zero is the
	//* backdrop buffer above.
	mip_pixels:  [BACKDROP_MIPS - 1][]u8,
	mip_w:       [BACKDROP_MIPS]i32,
	mip_h:       [BACKDROP_MIPS]i32,
	plan:        Backdrop_Plan,
	frame_w:     i32,
	frame_h:     i32,
	have_frame:  bool,
	atlas:       []u8,
	atlas_w:     i32,
	atlas_h:     i32,
	clear:       [4]u8,
}

software_create :: proc(ctx: rawptr, window: rawptr, w, h: i32) -> bool {
	state := cast(^Software_State)ctx
	if state == nil {return false}
	state.clear = {18, 20, 26, 255}
	return software_make_buffer(state, w, h)
}

software_destroy :: proc(ctx: rawptr) {
	state := cast(^Software_State)ctx
	if state == nil {return}
	delete(state.pixels)
	delete(state.target)
	delete(state.backdrop)
	for i in 0 ..< BACKDROP_MIPS - 1 {
		delete(state.mip_pixels[i])
		state.mip_pixels[i] = nil
	}
	backdrop_plan_destroy(&state.plan)
	delete(state.atlas)
	state^ = {}
}

software_resize :: proc(ctx: rawptr, w, h: i32) -> bool {
	state := cast(^Software_State)ctx
	if state == nil {return false}
	return software_make_buffer(state, w, h)
}

software_upload_texture :: proc(ctx: rawptr, id: GUI.Texture_ID, pixels: []u8, w, h: i32) -> bool {
	state := cast(^Software_State)ctx
	if state == nil {return false}
	if w <= 0 || h <= 0 {return false}
	delete(state.atlas)
	state.atlas = make([]u8, int(w) * int(h) * 4)
	copy(state.atlas, pixels)
	state.atlas_w = w
	state.atlas_h = h
	return true
}

software_upload_texture_regions :: proc(
	ctx: rawptr,
	id: GUI.Texture_ID,
	regions: []GUI.Texture_Upload,
) -> bool {
	state := cast(^Software_State)ctx
	if state == nil {return false}
	if state.atlas == nil {return false}
	for region in regions {
		row_bytes := int(region.w) * 4
		if row_bytes <= 0 {continue}
		for row in 0 ..< int(region.h) {
			src := region.pixels[row * row_bytes:][:row_bytes]
			dst := (int(region.y) + row) * int(state.atlas_w) * 4 + int(region.x) * 4
			copy(state.atlas[dst:][:row_bytes], src)
		}
	}
	return true
}

software_destroy_texture :: proc(ctx: rawptr, id: GUI.Texture_ID) {
	state := cast(^Software_State)ctx
	if state == nil {return}
	delete(state.atlas)
	state.atlas = nil
	state.atlas_w = 0
	state.atlas_h = 0
}

software_submit :: proc(ctx: rawptr, dl: ^GUI.Draw_List) {
	state := cast(^Software_State)ctx
	if state == nil {return}
	partial := dl != nil && dl.partial && state.have_frame && !software_list_has_glass(dl)
	if !partial {
		software_fill(state, state.pixels, state.width, state.height)
	}
	clip := partial ? dl.dirty_rect : GUI.Rect{}
	software_draw_into(state, dl, state.pixels, state.width, state.height, clip)
	state.have_frame = true
}

software_submit_target :: proc(ctx: rawptr, dl: ^GUI.Draw_List, window: rawptr) {
	state := cast(^Software_State)ctx
	if state == nil {return}
	if state.target == nil {
		state.target = make([]u8, int(state.width) * int(state.height) * 4)
		state.target_w = state.width
		state.target_h = state.height
	}
	software_fill(state, state.target, state.target_w, state.target_h)
	software_draw_into(state, dl, state.target, state.target_w, state.target_h)
}

software_write_ppm :: proc(state: ^Software_State, path: string) -> bool {
	if state == nil || state.pixels == nil {return false}
	header := fmt.tprintf("P6\n%d %d\n255\n", state.width, state.height)
	out := make([]u8, len(header) + int(state.width) * int(state.height) * 3)
	defer delete(out)
	copy(out, header)
	at := len(header)
	for row in 0 ..< int(state.height) {
		for col in 0 ..< int(state.width) {
			src := (row * int(state.width) + col) * 4
			out[at + 0] = state.pixels[src + 0]
			out[at + 1] = state.pixels[src + 1]
			out[at + 2] = state.pixels[src + 2]
			at += 3
		}
	}
	if dir := os.dir(path); dir != "" && dir != "." {
		_ = os.make_directory_all(dir)
	}
	return os.write_entire_file_from_bytes(path, out) == nil
}

software_make_buffer :: proc(state: ^Software_State, w, h: i32) -> bool {
	if w <= 0 || h <= 0 {return false}
	delete(state.pixels)
	state.pixels = make([]u8, int(w) * int(h) * 4)
	state.width = w
	state.height = h
	state.have_frame = false
	software_fill(state, state.pixels, w, h)
	return true
}

software_fill :: proc(state: ^Software_State, pixels: []u8, w, h: i32) {
	if pixels == nil {return}
	for i in 0 ..< len(pixels) / 4 {
		pixels[i * 4 + 0] = state.clear[0]
		pixels[i * 4 + 1] = state.clear[1]
		pixels[i * 4 + 2] = state.clear[2]
		pixels[i * 4 + 3] = state.clear[3]
	}
}

//* Whether any command of the list reads the backdrop.
software_list_has_glass :: proc(dl: ^GUI.Draw_List) -> bool {
	if dl == nil {return false}
	for command in dl.commands {
		if command.glass {return true}
	}
	return false
}

software_draw_into :: proc(
	state: ^Software_State,
	dl: ^GUI.Draw_List,
	pixels: []u8,
	w, h: i32,
	clip: GUI.Rect = {},
) {
	if dl == nil {return}
	state.frame_w = w
	state.frame_h = h
	backdrop_plan_build(&state.plan, dl)

	Stats_Reset()
	Stats.draw_passes += 1
	//* A glass surface reads the picture behind it. Outside the rectangle
	//* the pixels are the glass of the previous frame, not the content
	//* under it, so a scissored replay would blur the old composite into
	//* the new one. A list with glass is drawn whole.
	scissored := clip.w > 0 && clip.h > 0 && len(state.plan.groups) == 0
	active_clip := scissored ? clip : GUI.Rect{}
	if scissored {
		Stats.partial_updates += 1
	} else {
		Stats.full_updates += 1
	}
	Stats.scene_updates += 1

	for command, i in dl.commands {
		count := int(command.idx_count)
		base := int(command.idx_offset)
		if count < 3 {continue}
		if command.glass {
			group := i32(-1)
			if i < len(state.plan.command_group) {group = state.plan.command_group[i]}
			if group < 0 || int(group) >= len(state.plan.groups) {continue}
			if state.plan.groups[int(group)].first == i {
				software_capture_backdrop(state, pixels, w, h, state.plan.groups[int(group)].rect)
			}
			Stats.glass_commands += 1
			Stats.glass_pixels += int(max(command.bounds.w, 0) * max(command.bounds.h, 0))
			taps := 1
			if command.blur > 8 {
				//* One level of the chain plus four gradient taps.
				taps = 5
			} else if command.blur > 0.5 {
				radius := command.blur > 18 ? 1 : 2
				taps = (2 * radius + 1) * (2 * radius + 1)
			}
			Stats.glass_taps += int(max(command.bounds.w, 0) * max(command.bounds.h, 0)) * taps
		}
		for k := 0; k + 2 < count; k += 3 {
			a := dl.vertices[int(dl.indices[base + k + 0])]
			b := dl.vertices[int(dl.indices[base + k + 1])]
			c := dl.vertices[int(dl.indices[base + k + 2])]
			software_triangle(state, a, b, c, command.texture, pixels, w, h, active_clip)
		}
	}
}

software_capture_backdrop :: proc(
	state: ^Software_State,
	pixels: []u8,
	w, h: i32,
	region: GUI.Rect,
) {
	bw := max((int(w) + 1) / 2, 1)
	bh := max((int(h) + 1) / 2, 1)
	if len(state.backdrop) != bw * bh * 4 {
		delete(state.backdrop)
		state.backdrop = make([]u8, bw * bh * 4)
	}
	state.backdrop_w = i32(bw)
	state.backdrop_h = i32(bh)

	x0 := clamp(int(region.x), 0, int(w))
	y0 := clamp(int(region.y), 0, int(h))
	x1 := clamp(int(region.x + region.w + 0.999), 0, int(w))
	y1 := clamp(int(region.y + region.h + 0.999), 0, int(h))
	if x1 <= x0 || y1 <= y0 {return}

	bx0 := max(x0 / 2, 0)
	by0 := max(y0 / 2, 0)
	bx1 := min((x1 + 1) / 2, bw)
	by1 := min((y1 + 1) / 2, bh)

	for by in by0 ..< by1 {
		for bx in bx0 ..< bx1 {
			sum := [4]i32{}
			n := i32(0)
			for oy in 0 ..< 2 {
				for ox in 0 ..< 2 {
					px := bx * 2 + ox
					py := by * 2 + oy
					if px >= int(w) || py >= int(h) {continue}
					at := (py * int(w) + px) * 4
					for c in 0 ..< 4 {
						sum[c] += i32(pixels[at + c])
					}
					n += 1
				}
			}
			if n == 0 {continue}
			dst := (by * bw + bx) * 4
			for c in 0 ..< 4 {
				state.backdrop[dst + c] = u8(sum[c] / n)
			}
		}
	}

	Stats.capture_points += 1
	Stats.backdrop_blits += 1
	Stats.backdrop_pixels += (bx1 - bx0) * (by1 - by0)
	software_build_mips(state)
}

//* Builds the rest of the backdrop pyramid with a box downsample per
//* level, mirroring the mip chain the GPU generates.
software_build_mips :: proc(state: ^Software_State) {
	state.mip_w[0] = state.backdrop_w
	state.mip_h[0] = state.backdrop_h
	for level in 1 ..< BACKDROP_MIPS {
		sw := max(state.mip_w[level - 1], 1)
		sh := max(state.mip_h[level - 1], 1)
		dw := max(sw / 2, 1)
		dh := max(sh / 2, 1)
		buffer := &state.mip_pixels[level - 1]
		if len(buffer^) != int(dw) * int(dh) * 4 {
			delete(buffer^)
			buffer^ = make([]u8, int(dw) * int(dh) * 4)
		}
		src := state.backdrop
		src_w := state.backdrop_w
		if level > 1 {
			src = state.mip_pixels[level - 2]
			src_w = state.mip_w[level - 1]
		}
		for y in 0 ..< int(dh) {
			for x in 0 ..< int(dw) {
				sum := [4]i32{}
				n := i32(0)
				for oy in 0 ..< 2 {
					for ox in 0 ..< 2 {
						sx := x * 2 + ox
						sy := y * 2 + oy
						if sx >= int(sw) || sy >= int(sh) {continue}
						at := (sy * int(src_w) + sx) * 4
						for c in 0 ..< 4 {
							sum[c] += i32(src[at + c])
						}
						n += 1
					}
				}
				if n == 0 {continue}
				dst := (y * int(dw) + x) * 4
				for c in 0 ..< 4 {
					buffer[dst + c] = u8(sum[c] / n)
				}
			}
		}
		state.mip_w[level] = dw
		state.mip_h[level] = dh
	}
	Stats.mip_generations += 1
}

software_triangle :: proc(
	state: ^Software_State,
	a, b, c: GUI.Draw_Vertex,
	texture: GUI.Texture_ID,
	pixels: []u8,
	w, h: i32,
	clip: GUI.Rect = {},
) {
	denom := (b.pos[1] - c.pos[1]) * (a.pos[0] - c.pos[0]) +
		(c.pos[0] - b.pos[0]) * (a.pos[1] - c.pos[1])
	if math.abs(denom) < 0.000001 {return}

	left := int(math.floor(min(a.pos[0], min(b.pos[0], c.pos[0]))))
	right := int(math.ceil(max(a.pos[0], max(b.pos[0], c.pos[0]))))
	top := int(math.floor(min(a.pos[1], min(b.pos[1], c.pos[1]))))
	bottom := int(math.ceil(max(a.pos[1], max(b.pos[1], c.pos[1]))))
	left = max(left, 0)
	top = max(top, 0)
	right = min(right, int(w) - 1)
	bottom = min(bottom, int(h) - 1)
	if clip.w > 0 && clip.h > 0 {
		left = max(left, int(clip.x))
		top = max(top, int(clip.y))
		right = min(right, int(clip.x + clip.w) - 1)
		bottom = min(bottom, int(clip.y + clip.h) - 1)
	}
	if left > right || top > bottom {return}

	for py in top ..= bottom {
		for px in left ..= right {
			x := f32(px) + 0.5
			y := f32(py) + 0.5
			l0 := ((b.pos[1] - c.pos[1]) * (x - c.pos[0]) + (c.pos[0] - b.pos[0]) * (y - c.pos[1])) / denom
			l1 := ((c.pos[1] - a.pos[1]) * (x - c.pos[0]) + (a.pos[0] - c.pos[0]) * (y - c.pos[1])) / denom
			l2 := 1 - l0 - l1
			if l0 < 0 || l1 < 0 || l2 < 0 {continue}

			u := l0 * a.uv[0] + l1 * b.uv[0] + l2 * c.uv[0]
			v := l0 * a.uv[1] + l1 * b.uv[1] + l2 * c.uv[1]
			texel := software_sample(state, texture, u, v)

			red := l0 * a.colour.r + l1 * b.colour.r + l2 * c.colour.r
			green := l0 * a.colour.g + l1 * b.colour.g + l2 * c.colour.g
			blue := l0 * a.colour.b + l1 * b.colour.b + l2 * c.colour.b
			alpha := l0 * a.colour.a + l1 * b.colour.a + l2 * c.colour.a

			shape := [4]f32 {
				l0 * a.shape[0] + l1 * b.shape[0] + l2 * c.shape[0],
				l0 * a.shape[1] + l1 * b.shape[1] + l2 * c.shape[1],
				l0 * a.shape[2] + l1 * b.shape[2] + l2 * c.shape[2],
				l0 * a.shape[3] + l1 * b.shape[3] + l2 * c.shape[3],
			}
			local := [2]f32 {
				l0 * a.local[0] + l1 * b.local[0] + l2 * c.local[0],
				l0 * a.local[1] + l1 * b.local[1] + l2 * c.local[1],
			}
			softness := l0 * a.softness + l1 * b.softness + l2 * c.softness
			corners := [4]f32 {
				l0 * a.corners[0] + l1 * b.corners[0] + l2 * c.corners[0],
				l0 * a.corners[1] + l1 * b.corners[1] + l2 * c.corners[1],
				l0 * a.corners[2] + l1 * b.corners[2] + l2 * c.corners[2],
				l0 * a.corners[3] + l1 * b.corners[3] + l2 * c.corners[3],
			}
			border := [4]f32 {
				l0 * a.border[0] + l1 * b.border[0] + l2 * c.border[0],
				l0 * a.border[1] + l1 * b.border[1] + l2 * c.border[1],
				l0 * a.border[2] + l1 * b.border[2] + l2 * c.border[2],
				l0 * a.border[3] + l1 * b.border[3] + l2 * c.border[3],
			}
			opacity := l0 * a.opacity + l1 * b.opacity + l2 * c.opacity

			src_r := red * texel[0]
			src_g := green * texel[1]
			src_b := blue * texel[2]
			src_a := alpha * texel[3]

			kind := shape[0]
			if kind > 0.5 {
				half := [2]f32{shape[2], shape[3]}
				radii := GUI.clamp_corner_radii(corners, half[0] * 2, half[1] * 2)

				plain := false
				if kind < 2.5 {
					max_radius := max(max(radii[0], radii[1]), max(radii[2], radii[3]))
					if max_radius <= 0 {
						plain = true
					} else if abs(local[0]) <= half[0] - max_radius &&
						abs(local[1]) <= half[1] - max_radius {
						plain = true
					}
				}

				if plain {
					if kind < 1.5 {
						src_r = red
						src_g = green
						src_b = blue
					}
				} else {
					d := GUI.sdf_rounded_box(local, half, radii)

					if kind > 4.5 {
						back := software_glass(
							state,
							x,
							y,
							softness,
							d,
							local,
							half,
							radii,
							red,
							green,
							blue,
							alpha,
							opacity,
							border,
						)
						src_r = back[0]
						src_g = back[1]
						src_b = back[2]
						src_a = back[3]
					} else if kind > 3.5 {
						bw := [4]f32{max(border[0], 0), max(border[1], 0), max(border[2], 0), max(border[3], 0)}
						inner_half := [2]f32 {
							max(half[0] - 0.5 * (bw[0] + bw[2]), 0),
							max(half[1] - 0.5 * (bw[1] + bw[3]), 0),
						}
						inner_centre := [2]f32{0.5 * (bw[0] - bw[2]), 0.5 * (bw[1] - bw[3])}
						inner_radii := [4]f32 {
							max(radii[0] - max(bw[0], bw[1]), 0),
							max(radii[1] - max(bw[1], bw[2]), 0),
							max(radii[2] - max(bw[2], bw[3]), 0),
							max(radii[3] - max(bw[3], bw[0]), 0),
						}
						inner_radii = GUI.clamp_corner_radii(inner_radii, inner_half[0] * 2, inner_half[1] * 2)
						cover := GUI.sdf_coverage(d, 1)
						if inner_half[0] > 0 && inner_half[1] > 0 {
							inner_d := GUI.sdf_rounded_box(
								[2]f32{local[0] - inner_centre[0], local[1] - inner_centre[1]},
								inner_half,
								inner_radii,
							)
							cover = GUI.sdf_border_coverage(d, inner_d, 1, 1)
						}
						src_r = red
						src_g = green
						src_b = blue
						src_a = alpha * cover
					} else if kind > 2.5 {
						cover: f32
						if softness < 0 {
							shifted := [2]f32{local[0] - border[1], local[1] - border[2]}
							inner_d := GUI.sdf_rounded_box(shifted, half, radii)
							cover = GUI.sdf_inset_coverage(inner_d, border[0], -softness, 1)
						} else {
							cover = GUI.sdf_shadow_coverage(d, softness)
						}
						src_r = red
						src_g = green
						src_b = blue
						src_a = alpha * cover
					} else {
						cover := GUI.sdf_coverage(d, 1)
						src_a = alpha * texel[3] * cover
						if kind < 1.5 {
							src_r = red
							src_g = green
							src_b = blue
						}
					}
				}
			}

			at := (py * int(w) + px) * 4
			dst_r := f32(pixels[at + 0]) / 255
			dst_g := f32(pixels[at + 1]) / 255
			dst_b := f32(pixels[at + 2]) / 255
			dst_a := f32(pixels[at + 3]) / 255

			out_r := src_r * src_a + dst_r * (1 - src_a)
			out_g := src_g * src_a + dst_g * (1 - src_a)
			out_b := src_b * src_a + dst_b * (1 - src_a)
			out_a := src_a + dst_a * (1 - src_a)

			pixels[at + 0] = u8(clamp(out_r, 0, 1) * 255)
			pixels[at + 1] = u8(clamp(out_g, 0, 1) * 255)
			pixels[at + 2] = u8(clamp(out_b, 0, 1) * 255)
			pixels[at + 3] = u8(clamp(out_a, 0, 1) * 255)
		}
	}
}

GLASS_LENS_THETA_MAX :: 0.55
GLASS_LENS_LATERAL_MAX :: 0.19286

software_glass :: proc(
	state: ^Software_State,
	x, y: f32,
	blur: f32,
	d: f32,
	local, half: [2]f32,
	radii: [4]f32,
	tint_r, tint_g, tint_b, tint_a, list_opacity: f32,
	border: [4]f32,
) -> [4]f32 {
	refraction := max(border[0], 0)
	dispersion := max(border[1], 0)
	fresnel := max(border[2], 0)
	saturation := border[3]
	optics := refraction > 0 || dispersion > 0 || fresnel > 0 || saturation != 0

	shift: [2]f32
	outward := [2]f32{0, 1}
	normal := [3]f32{0, 0, 1}
	if optics {
		band := clamp(
			max(max(radii[0], radii[1]), max(radii[2], radii[3])),
			f32(8),
			min(half[0], half[1]),
		)
		rim := 1 - software_smoothstep(0, band, -d)
		bend := rim * rim

		if refraction > 0 || dispersion > 0 {
			dx := GUI.sdf_rounded_box([2]f32{local[0] + 1, local[1]}, half, radii)
			dy := GUI.sdf_rounded_box([2]f32{local[0], local[1] + 1}, half, radii)
			grad := [2]f32{dx - d, dy - d}
			glen := math.sqrt(grad[0] * grad[0] + grad[1] * grad[1])
			if glen > 0.00001 {
				outward = {grad[0] / glen, grad[1] / glen}
			}
		}

		theta := bend * GLASS_LENS_THETA_MAX
		sin_t := math.sin(theta)
		cos_t := math.cos(theta)
		normal = {outward[0] * sin_t, outward[1] * sin_t, cos_t}

		eta := f32(1.0 / 1.5)
		cos_i := -normal[2]
		k := max(1 - eta * eta * (1 - cos_i * cos_i), 0)
		factor := eta * cos_i + math.sqrt(k)
		shift = {
			-factor * normal[0] * (refraction / GLASS_LENS_LATERAL_MAX),
			-factor * normal[1] * (refraction / GLASS_LENS_LATERAL_MAX),
		}
	}

	cx := x + shift[0]
	cy := y + shift[1]
	back := software_sample_backdrop_bilinear(state, cx, cy)
	grad_x: [3]f32
	grad_y: [3]f32
	if blur > 8 {
		//* The mip chain replaces the Gaussian with a single trilinear tap.
		lod := clamp(math.log2(max(blur, 1) / 2), 0, f32(BACKDROP_MIPS - 1))
		back = software_sample_backdrop_mip(state, cx, cy, lod)
		if optics && dispersion > 0 {
			lod_g := max(lod - 2, 0)
			off := max(blur * 0.5, 1)
			right := software_sample_backdrop_mip(state, cx + off, cy, lod_g)
			left := software_sample_backdrop_mip(state, cx - off, cy, lod_g)
			down := software_sample_backdrop_mip(state, cx, cy + off, lod_g)
			up := software_sample_backdrop_mip(state, cx, cy - off, lod_g)
			for i in 0 ..< 3 {
				grad_x[i] = -(right[i] - left[i]) / (2 * off)
				grad_y[i] = -(down[i] - up[i]) / (2 * off)
			}
		}
	} else if blur > 0.5 {
		R := blur > 18 ? 1 : 2
		sigma := max(blur * (R == 1 ? 0.7 : 0.5), 0.5)
		spread := blur / f32(R)
		acc: [3]f32
		score_x: [3]f32
		score_y: [3]f32
		weight_sum := f32(0)
		for oy in -R ..= R {
			for ox in -R ..= R {
				dist := f32(ox * ox + oy * oy) * spread * spread
				weight := math.exp(-dist / (2 * sigma * sigma))
				sample := software_sample_backdrop_bilinear(
					state,
					cx + f32(ox) * spread,
					cy + f32(oy) * spread,
				)
				acc[0] += sample[0] * weight
				acc[1] += sample[1] * weight
				acc[2] += sample[2] * weight
				weight_sum += weight
				if optics && dispersion > 0 {
					score_x[0] += sample[0] * weight * f32(ox) * spread
					score_x[1] += sample[1] * weight * f32(ox) * spread
					score_x[2] += sample[2] * weight * f32(ox) * spread
					score_y[0] += sample[0] * weight * f32(oy) * spread
					score_y[1] += sample[1] * weight * f32(oy) * spread
					score_y[2] += sample[2] * weight * f32(oy) * spread
				}
			}
		}
		den := max(weight_sum, 0.0001)
		back = {acc[0] / den, acc[1] / den, acc[2] / den, 1}
		if optics && dispersion > 0 {
			norm := sigma * sigma * den
			grad_x = {-score_x[0] / norm, -score_x[1] / norm, -score_x[2] / norm}
			grad_y = {-score_y[0] / norm, -score_y[1] / norm, -score_y[2] / norm}
		}
	}

	if optics && dispersion > 0 {
		change: [3]f32
		for i in 0 ..< 3 {
			change[i] = (grad_x[i] * outward[0] + grad_y[i] * outward[1]) * dispersion
		}
		back[0] += change[0]
		back[2] -= change[2]
	}

	if optics && saturation != 0 {
		luma := back[0] * 0.2126 + back[1] * 0.7152 + back[2] * 0.0722
		back[0] = luma + (back[0] - luma) * saturation
		back[1] = luma + (back[1] - luma) * saturation
		back[2] = luma + (back[2] - luma) * saturation
	}

	q := [2]f32 {
		local[0] / max(half[0], 1),
		local[1] / max(half[1], 1),
	}
	sheen := software_smoothstep(0.1, -0.85, q[1]) * 0.07
	rim := math.exp(-max(d, 0) * 1.5) * 0.05
	if optics && fresnel > 0 {
		target_w := f32(state.frame_w)
		target_h := f32(state.frame_h)
		viewer_distance := max(min(target_w, target_h) * 0.25, 1)
		view := [3]f32{target_w * 0.5 - x, target_h * 0.5 - y, viewer_distance}
		vlen := math.sqrt(view[0] * view[0] + view[1] * view[1] + view[2] * view[2])
		if vlen > 0 {
			view = {view[0] / vlen, view[1] / vlen, view[2] / vlen}
		}
		light := [3]f32{-0.7, -0.7, 0.25}
		llen := math.sqrt(light[0] * light[0] + light[1] * light[1] + light[2] * light[2])
		light = {light[0] / llen, light[1] / llen, light[2] / llen}
		half_dir := [3]f32{light[0] + view[0], light[1] + view[1], light[2] + view[2]}
		hlen := math.sqrt(
			half_dir[0] * half_dir[0] +
			half_dir[1] * half_dir[1] +
			half_dir[2] * half_dir[2],
		)
		if hlen > 0 {
			half_dir = {half_dir[0] / hlen, half_dir[1] / hlen, half_dir[2] / hlen}
		}
		facing := 1 - clamp(normal[0] * view[0] + normal[1] * view[1] + normal[2] * view[2], 0, 1)
		facing5 := facing * facing * facing * facing * facing
		nh := clamp(normal[0] * half_dir[0] + normal[1] * half_dir[1] + normal[2] * half_dir[2], 0, 1)
		highlight := fresnel * 0.7 * math.pow(nh, 48)
		rim = fresnel * facing5 + highlight
	}

	tint_alpha := tint_a
	if optics {
		luma := back[0] * 0.299 + back[1] * 0.587 + back[2] * 0.114
		tint_alpha = clamp(tint_a * (1.35 - 0.7 * luma), 0, 1)
	}

	cover := GUI.sdf_coverage(d, 1)
	glass := [3]f32 {
		back[0] + (tint_r - back[0]) * tint_alpha,
		back[1] + (tint_g - back[1]) * tint_alpha,
		back[2] + (tint_b - back[2]) * tint_alpha,
	}
	fade := 1 - 0.05 * software_smoothstep(-0.1, 1.0, q[1])
	glass[0] = (glass[0] + sheen + rim) * fade
	glass[1] = (glass[1] + sheen + rim) * fade
	glass[2] = (glass[2] + sheen + rim) * fade
	return {glass[0], glass[1], glass[2], cover * list_opacity}
}

software_smoothstep :: proc(edge0, edge1, x: f32) -> f32 {
	if edge0 == edge1 {return x < edge0 ? 0 : 1}
	t := clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
}

software_sample :: proc(state: ^Software_State, texture: GUI.Texture_ID, u, v: f32) -> [4]f32 {
	if texture == GUI.INVALID_TEXTURE_ID {return {1, 1, 1, 1}}
	if state.atlas == nil {return {1, 1, 1, 1}}
	x := int(u * f32(state.atlas_w))
	y := int(v * f32(state.atlas_h))
	if x < 0 {x = 0}
	if y < 0 {y = 0}
	if x >= int(state.atlas_w) {x = int(state.atlas_w) - 1}
	if y >= int(state.atlas_h) {y = int(state.atlas_h) - 1}
	at := (y * int(state.atlas_w) + x) * 4
	return {
		f32(state.atlas[at + 0]) / 255,
		f32(state.atlas[at + 1]) / 255,
		f32(state.atlas[at + 2]) / 255,
		f32(state.atlas[at + 3]) / 255,
	}
}

software_backdrop_pixel :: proc(state: ^Software_State, x, y: int) -> [4]f32 {
	px := x
	py := y
	if px < 0 {px = 0}
	if py < 0 {py = 0}
	if px >= int(state.backdrop_w) {px = int(state.backdrop_w) - 1}
	if py >= int(state.backdrop_h) {py = int(state.backdrop_h) - 1}
	at := (py * int(state.backdrop_w) + px) * 4
	return {
		f32(state.backdrop[at + 0]) / 255,
		f32(state.backdrop[at + 1]) / 255,
		f32(state.backdrop[at + 2]) / 255,
		f32(state.backdrop[at + 3]) / 255,
	}
}

//* The buffer and the size of one level of the backdrop pyramid. Level
//* zero is the half resolution backdrop itself.
software_mip_buffer :: proc(state: ^Software_State, level: int) -> ([]u8, i32, i32) {
	l := clamp(level, 0, BACKDROP_MIPS - 1)
	if l == 0 {
		return state.backdrop, state.backdrop_w, state.backdrop_h
	}
	return state.mip_pixels[l - 1], state.mip_w[l], state.mip_h[l]
}

software_mip_pixel :: proc(state: ^Software_State, level: int, x, y: int) -> [4]f32 {
	buffer, w, h := software_mip_buffer(state, level)
	if len(buffer) == 0 || w <= 0 || h <= 0 {return {0, 0, 0, 1}}
	px := clamp(x, 0, int(w) - 1)
	py := clamp(y, 0, int(h) - 1)
	at := (py * int(w) + px) * 4
	return {
		f32(buffer[at + 0]) / 255,
		f32(buffer[at + 1]) / 255,
		f32(buffer[at + 2]) / 255,
		f32(buffer[at + 3]) / 255,
	}
}

//* One bilinear tap of a chosen level, for a physical pixel position.
software_sample_mip_level :: proc(
	state: ^Software_State,
	level: int,
	x, y: f32,
) -> [4]f32 {
	_, w, h := software_mip_buffer(state, level)
	if w <= 0 || h <= 0 || state.frame_w <= 0 || state.frame_h <= 0 {
		return {0, 0, 0, 1}
	}
	scale_x := f32(w) / f32(state.frame_w)
	scale_y := f32(h) / f32(state.frame_h)
	fx := clamp(x * scale_x - 0.5, 0, f32(w - 1))
	fy := clamp(y * scale_y - 0.5, 0, f32(h - 1))
	x0 := int(fx)
	y0 := int(fy)
	x1 := min(x0 + 1, int(w) - 1)
	y1 := min(y0 + 1, int(h) - 1)
	tx := fx - f32(x0)
	ty := fy - f32(y0)
	c00 := software_mip_pixel(state, level, x0, y0)
	c10 := software_mip_pixel(state, level, x1, y0)
	c01 := software_mip_pixel(state, level, x0, y1)
	c11 := software_mip_pixel(state, level, x1, y1)
	out: [4]f32
	for i in 0 ..< 4 {
		top := c00[i] + (c10[i] - c00[i]) * tx
		bottom := c01[i] + (c11[i] - c01[i]) * tx
		out[i] = top + (bottom - top) * ty
	}
	return out
}

//* Trilinear between the two levels the lod falls between, mirroring the
//* sampler the GPU uses.
software_sample_backdrop_mip :: proc(
	state: ^Software_State,
	x, y, lod: f32,
) -> [4]f32 {
	l0 := clamp(int(math.floor(lod)), 0, BACKDROP_MIPS - 1)
	l1 := min(l0 + 1, BACKDROP_MIPS - 1)
	t := clamp(lod - f32(l0), 0, 1)
	a := software_sample_mip_level(state, l0, x, y)
	if l1 == l0 || t <= 0 {return a}
	b := software_sample_mip_level(state, l1, x, y)
	out: [4]f32
	for i in 0 ..< 4 {
		out[i] = a[i] + (b[i] - a[i]) * t
	}
	return out
}

software_sample_backdrop_bilinear :: proc(
	state: ^Software_State,
	x, y: f32,
) -> [4]f32 {
	if state.backdrop == nil || state.backdrop_w <= 0 || state.backdrop_h <= 0 {
		return {0, 0, 0, 1}
	}
	fx := clamp(x * BACKDROP_SCALE - 0.5, 0, f32(state.backdrop_w - 1))
	fy := clamp(y * BACKDROP_SCALE - 0.5, 0, f32(state.backdrop_h - 1))
	x0 := int(fx)
	y0 := int(fy)
	x1 := min(x0 + 1, int(state.backdrop_w) - 1)
	y1 := min(y0 + 1, int(state.backdrop_h) - 1)
	tx := fx - f32(x0)
	ty := fy - f32(y0)
	c00 := software_backdrop_pixel(state, x0, y0)
	c10 := software_backdrop_pixel(state, x1, y0)
	c01 := software_backdrop_pixel(state, x0, y1)
	c11 := software_backdrop_pixel(state, x1, y1)
	out: [4]f32
	for i in 0 ..< 4 {
		top := c00[i] + (c10[i] - c00[i]) * tx
		bottom := c01[i] + (c11[i] - c01[i]) * tx
		out[i] = top + (bottom - top) * ty
	}
	return out
}
