//* == The pictures ==
//* A picture is put into the atlas like everything else, so it costs no
//* draw call of its own. The atlas gives the space back when it is
//* full: a picture that is not used for a while is the first to go.
//
//* A PNG is read with the reader of the Odin core, so the toolkit does
//* not need a picture library of its own.

package GUI

import "core:image/png"

//* A picture that lives in the atlas.
Texture :: struct {
	//* The place of the picture in the atlas.
	region: Atlas_Region,
	//* Its size in pixels.
	size:   [2]i32,
	//* The uv of the picture in the atlas.
	uv:     [4]f32,
}

//* Puts a picture into the atlas. The pixels are RGBA, four bytes
//* each, and there are `w` * `h` of them.
texture_from_pixels :: proc(g: ^GUI, pixels: []u8, w, h: int) -> Texture {
	if w <= 0 || h <= 0 {return Texture{}}
	if len(pixels) < w * h * 4 {return Texture{}}

	region := atlas_alloc(g.atlas, w, h, false)
	if region.id < 0 {return Texture{}}
	atlas_write(g.atlas, region, pixels)

	return Texture{region = region, size = [2]i32{i32(w), i32(h)}, uv = region.uv}
}

//* Reads a PNG and puts it into the atlas.
texture_from_png :: proc(g: ^GUI, data: []u8) -> (Texture, bool) {
	image, err := png.load_from_bytes(data)
	if err != nil {return {}, false}
	defer free(image)

	w := image.width
	h := image.height
	channels := image.channels
	if w <= 0 || h <= 0 {return {}, false}

	//* The reader gives the rows of the picture one after the other.
	//* They are copied into the atlas, which wants four bytes for
	//* every pixel.
	source := image.pixels.buf[image.pixels.off:]
	if len(source) < w * h * channels {return {}, false}

	pixels := make([]u8, w * h * 4, context.allocator)
	defer delete(pixels)

	for i in 0 ..< w * h {
		at := i * channels
		out := i * 4
		switch channels {
		case 1:
			//* Grey: the colour is white and the alpha is the grey.
			pixels[out + 0] = 255
			pixels[out + 1] = 255
			pixels[out + 2] = 255
			pixels[out + 3] = source[at]
		case 2:
			//* Grey and alpha.
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

//* Gives the space of a picture back to the atlas.
texture_free :: proc(g: ^GUI, texture: Texture) {
	if texture.region.id < 0 {return}
	atlas_free(g.atlas, texture.region)
}

//* Draws a picture in a rect. The picture keeps its shape: it is put
//* in the middle of the rect when it does not fill it.
//
//* A picture that was thrown out of the atlas is not drawn: the space
//* it had belongs to something else now.
draw_texture :: proc(g: ^GUI, texture: Texture, rect: Rect, colour: Colour) {
	if !atlas_region_valid(g.atlas, texture.region) {return}
	if rect.w <= 0 || rect.h <= 0 {return}

	//* The picture is on the screen, so it is the last one to be
	//* thrown out of the atlas.
	atlas_touch(g.atlas, texture.region)

	//* The place of the picture in the rect.
	w := f32(texture.size[0])
	h := f32(texture.size[1])
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
