package Core
import "core:image/png"

import "core:os"

Texture :: struct {
	region: Atlas_Region,
	size:   [2]i32,
	uv:     [4]f32,
}

texture_from_pixels :: proc(g: ^GUI, pixels: []u8, w, h: int) -> Texture {
	if w <= 0 || h <= 0 {return Texture{}}
	if len(pixels) < w * h * 4 {return Texture{}}

	region := atlas_alloc(g.atlas, w, h, false)
	if region.id < 0 {return Texture{}}
	atlas_write(g.atlas, region, pixels)

	return Texture{region = region, size = [2]i32{i32(w), i32(h)}, uv = region.uv}
}

texture_update :: proc(g: ^GUI, texture: Texture, pixels: []u8) -> bool {
	if g == nil || !atlas_region_valid(g.atlas, texture.region) {return false}
	if len(pixels) < texture.region.w * texture.region.h * 4 {return false}
	atlas_write(g.atlas, texture.region, pixels)
	draw_invalidate(g)
	return true
}

texture_from_png :: proc(g: ^GUI, data: []u8) -> (Texture, bool) {
	image, err := png.load_from_bytes(data)
	if err != nil {return {}, false}
	defer png.destroy(image)

	w := image.width
	h := image.height
	channels := image.channels
	if w <= 0 || h <= 0 {return {}, false}

	source := image.pixels.buf[image.pixels.off:]
	if len(source) < w * h * channels {return {}, false}

	pixels := make([]u8, w * h * 4, context.allocator)
	defer delete(pixels)

	for i in 0 ..< w * h {
		at := i * channels
		out := i * 4
		switch channels {
		case 1:
			pixels[out + 0] = 255
			pixels[out + 1] = 255
			pixels[out + 2] = 255
			pixels[out + 3] = source[at]
		case 2:
			pixels[out + 0] = 255
			pixels[out + 1] = 255
			pixels[out + 2] = 255
			pixels[out + 3] = source[at + 1]
		case 3:
			pixels[out + 0] = source[at + 0]
			pixels[out + 1] = source[at + 1]
			pixels[out + 2] = source[at + 2]
			pixels[out + 3] = 255
		case:
			pixels[out + 0] = source[at + 0]
			pixels[out + 1] = source[at + 1]
			pixels[out + 2] = source[at + 2]
			pixels[out + 3] = source[at + 3]
		}
	}

	texture := texture_from_pixels(g, pixels, w, h)
	if texture.region.id < 0 {return {}, false}
	return texture, true
}

//* Reads a picture from a file and puts it into the atlas. The picture
//* keeps its region, its size and its uv, so it is drawn the same way
//* the glyphs are. The second value says whether the picture was read.
Texture_Load_File :: proc(g: ^GUI, path: string) -> (Texture, bool) {
	if g == nil {return {}, false}
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {return {}, false}
	defer delete(data)
	return texture_from_png(g, data)
}

texture_free :: proc(g: ^GUI, texture: Texture) {
	if texture.region.id < 0 {return}
	atlas_free(g.atlas, texture.region)
	draw_invalidate(g)
}

texture_logical_size :: proc(g: ^GUI, texture: Texture) -> Vec2 {
	scale := g.scale
	if !(scale > 0) {scale = 1}
	return Vec2 {
		x = f32(texture.size[0]) / scale,
		y = f32(texture.size[1]) / scale,
	}
}

draw_texture :: proc(g: ^GUI, texture: Texture, rect: Rect, colour: Colour) {
	if !atlas_region_valid(g.atlas, texture.region) {return}
	if rect.w <= 0 || rect.h <= 0 {return}

	atlas_touch(g.atlas, texture.region)

	size := texture_logical_size(g, texture)
	w := size.x
	h := size.y
	if w <= 0 || h <= 0 {return}
	scale := min(rect.w / w, rect.h / h)
	drawn := Rect {
		w = w * scale,
		h = h * scale,
	}
	drawn.x = rect.x + (rect.w - drawn.w) * 0.5
	drawn.y = rect.y + (rect.h - drawn.h) * 0.5

	draw_quad(g.target, drawn, texture.uv, colour, atlas_texture_for(texture.region))
}

draw_texture_rounded :: proc(
	g: ^GUI,
	texture: Texture,
	rect: Rect,
	colour: Colour,
	radii: [4]f32,
) {
	if !atlas_region_valid(g.atlas, texture.region) {return}
	if rect.w <= 0 || rect.h <= 0 {return}

	atlas_touch(g.atlas, texture.region)

	size := texture_logical_size(g, texture)
	w := size.x
	h := size.y
	if w <= 0 || h <= 0 {return}
	scale := min(rect.w / w, rect.h / h)
	drawn := Rect {
		w = w * scale,
		h = h * scale,
	}
	drawn.x = rect.x + (rect.w - drawn.w) * 0.5
	drawn.y = rect.y + (rect.h - drawn.h) * 0.5

	draw_quad_rounded(g.target, drawn, texture.uv, colour, atlas_texture_for(texture.region), radii, g.backend.supports_shapes)
}

draw_quad_rounded :: proc(
	dl: ^Draw_List,
	r: Rect,
	uv: [4]f32,
	c: Colour,
	tex: Texture_ID,
	radii: [4]f32,
	shapes: bool,
) {
	if r.w <= 0 || r.h <= 0 {return}
	clamped := clamp_corner_radii(radii, r.w, r.h)
	if radii_are_zero(clamped) {
		draw_quad(dl, r, uv, c, tex)
		return
	}

	if shapes {
		draw_quad_shape_full(
			dl,
			r,
			uv,
			c,
			tex,
			.Textured,
			max_corner_radius(clamped),
			{r.w * 0.5, r.h * 0.5},
			0,
			clamped,
			{},
		)
		return
	}

	scaled := rect_scale(r, dl.scale)
	scaled_radii := [4]f32 {
		clamped[0] * dl.scale,
		clamped[1] * dl.scale,
		clamped[2] * dl.scale,
		clamped[3] * dl.scale,
	}
	scaled_radii = clamp_corner_radii(scaled_radii, scaled.w, scaled.h)

	colour := c
	if dl.opacity != 1 {colour.a *= dl.opacity}

	points: [4 * (CORNER_SEGMENTS + 1)][2]f32
	round_rect_loop(scaled, scaled_radii, CORNER_SEGMENTS, points[:])
	n := len(points)

	clear(&dl.clip_source)
	for i in 0 ..< n {
		p := points[i]
		u := uv[0] + (p[0] - scaled.x) / scaled.w * (uv[2] - uv[0])
		v := uv[1] + (p[1] - scaled.y) / scaled.h * (uv[3] - uv[1])
		append(
			&dl.clip_source,
			Draw_Vertex{pos = p, uv = {u, v}, colour = colour, opacity = dl.opacity},
		)
	}

	if clip_needs_any(dl, scaled) {
		clipped := clip_polygon_vertices(dl, dl.clip_source[:])
		emit_polygon_vertices(dl, clipped, tex)
		return
	}
	emit_polygon_vertices(dl, dl.clip_source[:], tex)
}

