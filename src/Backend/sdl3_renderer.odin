package Backend

import GUI "../GUI"
import sdl "vendor:sdl3"
import "core:c"

Renderer_State :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
	//* The renderers of the floating panels. Each one belongs to a
	//* window of its own.
	targets:  [dynamic]Target,
	//* The textures of every renderer. A renderer cannot share its
	//* textures with another one, so every renderer gets its own copy.
	//* The main renderer comes first, the floating panels follow.
	textures: [dynamic][dynamic]^sdl.Texture,
	//* The pixels of every texture, so a renderer that is made later
	//* can be given the textures it missed.
	pixels:   [dynamic][]u8,
	sizes:    [dynamic][2]i32,
	verts:    [dynamic]sdl.Vertex,
	indices:  [dynamic]c.int, // RenderGeometry wants [^]c.int, not u32
}

//* The window and the renderer of a floating panel.
Target :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
}

renderer_create :: proc(ctx, window: rawptr, w, h: i32) -> bool {
	st := cast(^Renderer_State)ctx
	st.window = cast(^sdl.Window)window
	st.renderer = sdl.CreateRenderer(st.window, nil)
	if st.renderer == nil { return false }
	sdl.SetRenderVSync(st.renderer, 1)
	//* Straight alpha blending, matching the GPU backend's shader.
	sdl.SetRenderDrawBlendMode(st.renderer, sdl.BLENDMODE_BLEND)
	//* The texture table of the main renderer.
	append(&st.textures, nil)
	//* The atlas is the one texture of the UI. It is made by the first
	//* upload, which the GUI does when it flushes the atlas.
	return true
}

renderer_destroy :: proc(ctx: rawptr) {
	st := cast(^Renderer_State)ctx
	for list in st.textures {
		for tex in list {
			if tex != nil {sdl.DestroyTexture(tex)}
		}
	}
	clear(&st.textures)
	delete(st.textures)

	for tex in st.pixels {
		delete(tex)
	}
	clear(&st.pixels)
	delete(st.pixels)
	clear(&st.sizes)
	delete(st.sizes)

	for target in st.targets {
		if target.renderer != nil { sdl.DestroyRenderer(target.renderer) }
	}
	clear(&st.targets)
	delete(st.targets)

	if st.renderer != nil {
		sdl.DestroyRenderer(st.renderer)
		st.renderer = nil
	}
}

renderer_resize :: proc(ctx: rawptr, w, h: i32) -> bool {
	return true
}

//* Creates or updates a texture and uploads its pixels. Every renderer
//* gets a copy, because a texture belongs to the renderer it was made
//* with.
renderer_upload_texture :: proc(ctx: rawptr, id: GUI.Texture_ID, pixels: []u8, w, h: i32) -> bool {
	st := cast(^Renderer_State)ctx

	idx := int(id)
	for len(st.pixels) <= idx {
		append(&st.pixels, nil)
		append(&st.sizes, [2]i32{})
	}
	//* Keep the pixels, so a renderer that is made later can be given
	//* this texture as well.
	delete(st.pixels[idx])
	data := make([]u8, len(pixels))
	copy(data, pixels)
	st.pixels[idx] = data
	st.sizes[idx] = [2]i32{w, h}

	if st.renderer != nil {
		if !upload_to_renderer(st, 0, idx, pixels, w, h) { return false }
	}
	for i in 0 ..< len(st.targets) {
		if st.targets[i].renderer == nil { continue }
		if !upload_to_renderer(st, i + 1, idx, pixels, w, h) { return false }
	}
	return true
}

//* Uploads a part of a texture. The atlas is far too big to be sent
//* again every time one glyph changes, so only the part that changed
//* goes up.
renderer_upload_texture_region :: proc(
	ctx: rawptr,
	id: GUI.Texture_ID,
	pixels: []u8,
	w, h, x, y: i32,
) -> bool {
	st := cast(^Renderer_State)ctx
	idx := int(id)
	if idx >= len(st.pixels) { return false }

	//* The copy the renderer is made of has to keep up, or a renderer
	//* that is made later would get the old picture.
	size := st.sizes[idx]
	if size[0] > 0 && size[1] > 0 {
		full := st.pixels[idx]
		for row in 0 ..< int(h) {
			ty := int(y) + row
			if ty < 0 || ty >= int(size[1]) { continue }
			for col in 0 ..< int(w) {
				tx := int(x) + col
				if tx < 0 || tx >= int(size[0]) { continue }
				src := (row * int(w) + col) * 4
				dst := (ty * int(size[0]) + tx) * 4
				copy(full[dst:dst + 4], pixels[src:src + 4])
			}
		}
	}

	rect := sdl.Rect{x = i32(x), y = i32(y), w = i32(w), h = i32(h)}
	if st.renderer != nil {
		if !update_in_renderer(st, 0, idx, pixels, w, rect) { return false }
	}
	for i in 0 ..< len(st.targets) {
		if st.targets[i].renderer == nil { continue }
		if !update_in_renderer(st, i + 1, idx, pixels, w, rect) { return false }
	}
	return true
}

//* Puts a part of a texture into one renderer.
update_in_renderer :: proc(
	st: ^Renderer_State,
	renderer_index: int,
	idx: int,
	pixels: []u8,
	w: i32,
	rect: sdl.Rect,
) -> bool {
	if renderer_index >= len(st.textures) { return false }
	list := &st.textures[renderer_index]
	if idx >= len(list^) { return false }
	tex := list^[idx]
	if tex == nil { return false }
	region := rect
	return sdl.UpdateTexture(tex, &region, raw_data(pixels), i32(w) * 4)
}

//* Uploads one texture into one renderer.
upload_to_renderer :: proc(
	st: ^Renderer_State,
	renderer_index: int,
	idx: int,
	pixels: []u8,
	w, h: i32,
) -> bool {
	for len(st.textures) <= renderer_index {
		append(&st.textures, nil)
	}
	list := &st.textures[renderer_index]
	for len(list^) <= idx {
		append(list, nil)
	}
	tex := list^[idx]
	if tex == nil {
		renderer: ^sdl.Renderer = st.renderer
		if renderer_index > 0 { renderer = st.targets[renderer_index - 1].renderer }
		if renderer == nil { return false }
		tex = sdl.CreateTexture(renderer, .RGBA32, .STREAMING, w, h)
		if tex == nil {return false}
		list^[idx] = tex
	}
	sdl.UpdateTexture(tex, nil, raw_data(pixels), w * 4)
	return true
}

renderer_submit :: proc(ctx: rawptr, dl: ^GUI.Draw_List) {
	st := cast(^Renderer_State)ctx
	render_into(st, 0, dl)
	sdl.RenderPresent(st.renderer)
}

//* Renders a draw list into the window of a floating panel. The window
//* is given a renderer the first time it is used.
renderer_submit_target :: proc(ctx: rawptr, dl: ^GUI.Draw_List, window: rawptr) {
	st := cast(^Renderer_State)ctx
	handle := cast(^sdl.Window)window

	index := -1
	for target, i in st.targets {
		if target.window == handle {
			index = i
			break
		}
	}
	if index < 0 {
		renderer := sdl.CreateRenderer(handle, nil)
		if renderer == nil { return }
		sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND)
		append(&st.targets, Target{window = handle, renderer = renderer})
		append(&st.textures, nil)
		index = len(st.targets) - 1
		//* The new renderer needs every texture the others have.
		for i in 0 ..< len(st.pixels) {
			if st.pixels[i] == nil { continue }
			size := st.sizes[i]
			upload_to_renderer(st, index + 1, i, st.pixels[i], size[0], size[1])
		}
	}

	render_into(st, index + 1, dl)
	sdl.RenderPresent(st.targets[index].renderer)
}

//* Draws a list into one renderer.
render_into :: proc(st: ^Renderer_State, renderer_index: int, dl: ^GUI.Draw_List) {
	renderer: ^sdl.Renderer = st.renderer
	if renderer_index > 0 {
		if renderer_index - 1 >= len(st.targets) { return }
		renderer = st.targets[renderer_index - 1].renderer
	}
	if renderer == nil { return }

	sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
	sdl.RenderClear(renderer)

	clear(&st.verts)
	for v in dl.vertices {
		append(
			&st.verts,
			sdl.Vertex {
				position = sdl.FPoint{v.pos[0], v.pos[1]},
				color = sdl.FColor{v.colour.r, v.colour.g, v.colour.b, v.colour.a},
				tex_coord = sdl.FPoint{v.uv[0], v.uv[1]},
			},
		)
	}

	clear(&st.indices)
	for idx in dl.indices {
		append(&st.indices, c.int(idx))
	}

	list := st.textures[renderer_index]
	for cmd in dl.commands {
		tex: ^sdl.Texture = nil
		if int(cmd.texture) < len(list) {tex = list[cmd.texture]}

		//* The clip is already worked out in the draw list, so the
		//* renderer is not told about it.
		sdl.RenderGeometry(
			renderer,
			tex,
			raw_data(st.verts),
			i32(len(st.verts)),
			raw_data(st.indices[cmd.idx_offset:]),
			i32(cmd.idx_count),
		)
	}
}
