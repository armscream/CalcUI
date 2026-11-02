//* The renderer-agnostic draw contract.
//
//* There is exactly ONE command type: a range of indices into a shared
//* vertex/index buffer, the texture it samples, and the clip rect it is
//* clipped to. Clipping is resolved while the list is built, so there
//* are no push/pop commands and every command is self-contained.
package GUI

Draw_Vertex :: struct {
	pos:    [2]f32,
	uv:     [2]f32,
	colour: Colour, // premultiplied RGBA
}

Draw_Command :: struct {
	texture:    Texture_ID,
	clip:       Rect,
	idx_count:  u32,
	idx_offset: u32,
}

Draw_List :: struct {
	vertices:     [dynamic]Draw_Vertex,
	indices:      [dynamic]u32,
	commands:     [dynamic]Draw_Command,
	clip_stack:   [dynamic]Rect,
	base_clip:    Rect, // the clip of the whole list
	current_clip: Rect,
}

draw_list_clear :: proc(dl: ^Draw_List, viewport: Rect) {
	clear(&dl.vertices)
	clear(&dl.indices)
	clear(&dl.commands)
	clear(&dl.clip_stack)
	dl.base_clip = viewport
	dl.current_clip = viewport
}

//* Releases the backing arrays. The per-frame clear keeps the capacity
//* alive between frames, so this is only called at shutdown.
draw_list_destroy :: proc(dl: ^Draw_List) {
	delete(dl.vertices)
	delete(dl.indices)
	delete(dl.commands)
	delete(dl.clip_stack)
}

//* Clip state lives in the builder, never in the command list.
draw_push_clip :: proc(dl: ^Draw_List, r: Rect) {
	append(&dl.clip_stack, rect_intersect(dl.current_clip, r))
	dl.current_clip = dl.clip_stack[len(dl.clip_stack) - 1]
}

//* Popping the last clip goes back to the clip of the whole list, so
//* anything drawn after the tree is not clipped away.
draw_pop_clip :: proc(dl: ^Draw_List) {
	if len(dl.clip_stack) == 0 { return }
	_ = pop(&dl.clip_stack)
	dl.current_clip = len(dl.clip_stack) > 0 ? dl.clip_stack[len(dl.clip_stack) - 1] : dl.base_clip
}

rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	if x1 < x0 do x1 = x0
	if y1 < y0 do y1 = y0
	return Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
}

rect_contains :: proc(r: Rect, x, y: f32) -> bool {
	return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
}

rect_equal :: proc(a, b: Rect) -> bool {
	return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h
}

//* Emits one textured quad. Consecutive quads sharing a texture and a
//* clip rect merge into the previous command, so the list is already
//* batched by the time the backend sees it.
draw_quad :: proc(dl: ^Draw_List, r: Rect, uv: [4]f32, c: Colour, tex: Texture_ID) {
	if r.w <= 0 || r.h <= 0 { return }

	base := u32(len(dl.vertices))
	p := [4][2]f32{{r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}}
	t := [4][2]f32{{uv[0], uv[1]}, {uv[2], uv[1]}, {uv[2], uv[3]}, {uv[0], uv[3]}}
	//* Straight alpha: the backend blends with SRC_ALPHA, and the GPU
	//* backend premultiplies in the fragment shader. Both agree.
	for i in 0 ..< 4 {
		append(&dl.vertices, Draw_Vertex{pos = p[i], uv = t[i], colour = c})
	}

	idx_start := u32(len(dl.indices))
	append(&dl.indices, base + 0)
	append(&dl.indices, base + 1)
	append(&dl.indices, base + 2)
	append(&dl.indices, base + 0)
	append(&dl.indices, base + 2)
	append(&dl.indices, base + 3)

	if len(dl.commands) > 0 {
		last := &dl.commands[len(dl.commands) - 1]
		if last.texture == tex && rect_equal(last.clip, dl.current_clip) {
			last.idx_count += 6
			return
		}
	}
	append(
		&dl.commands,
		Draw_Command{texture = tex, clip = dl.current_clip, idx_offset = idx_start, idx_count = 6},
	)
}
