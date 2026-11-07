//* The textures of the GUI: pictures that are put into the atlas and
//* drawn out of it, the same way the glyphs are.
package GUI

import "core:image/png"

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

texture_from_png :: proc(g: ^GUI, data: []u8) -> (Texture, bool) {
	image, err := png.load_from_bytes(data)
	if err != nil {return {}, false}
	defer free(image)

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

texture_free :: proc(g: ^GUI, texture: Texture) {
	if texture.region.id < 0 {return}
	atlas_free(g.atlas, texture.region)
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

	draw_quad(g.target, drawn, texture.uv, colour, g.atlas_texture)
}

