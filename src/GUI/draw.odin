//* The renderer-agnostic draw contract: one command type, one atlas,
//* one draw call for a whole window. The clip is resolved while the
//* list is built: a cut quad is cut on the CPU and its texture
//* coordinates are moved with it.
package GUI

import "core:math"

Shape_Kind :: enum u32 {
	Plain    = 0,
	Solid    = 1,
	Textured = 2,
}

Draw_Vertex :: struct {
	pos:    [2]f32,
	uv:     [2]f32,
	colour: Colour,
	shape:  [4]f32,
	local:  [2]f32,
}

Draw_Command :: struct {
	texture:    Texture_ID,
	idx_count:  u32,
	idx_offset: u32,
}

Draw_List :: struct {
	vertices:     [dynamic]Draw_Vertex,
	indices:      [dynamic]u32,
	commands:     [dynamic]Draw_Command,
	clip_stack:   [dynamic]Rect,
	base_clip:    Rect,
	current_clip: Rect,
	clip_a:       [dynamic][2]f32,
	clip_b:       [dynamic][2]f32,
	scaled:       [dynamic][2]f32,
	scale:        f32,
}

draw_list_clear :: proc(dl: ^Draw_List, viewport: Rect) {
	if !(dl.scale > 0) {dl.scale = 1}
	clear(&dl.vertices)
	clear(&dl.indices)
	clear(&dl.commands)
	clear(&dl.clip_stack)
	dl.base_clip = rect_scale(viewport, dl.scale)
	dl.current_clip = dl.base_clip
}

rect_scale :: proc(r: Rect, scale: f32) -> Rect {
	return Rect {
		x = r.x * scale,
		y = r.y * scale,
		w = r.w * scale,
		h = r.h * scale,
	}
}

draw_list_destroy :: proc(dl: ^Draw_List) {
	delete(dl.vertices)
	delete(dl.indices)
	delete(dl.commands)
	delete(dl.clip_stack)
	delete(dl.clip_a)
	delete(dl.clip_b)
	delete(dl.scaled)
}

draw_push_clip :: proc(dl: ^Draw_List, r: Rect) {
	append(&dl.clip_stack, rect_intersect(dl.current_clip, rect_scale(r, dl.scale)))
	dl.current_clip = dl.clip_stack[len(dl.clip_stack) - 1]
}

draw_pop_clip :: proc(dl: ^Draw_List) {
	if len(dl.clip_stack) == 0 {return}
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

draw_quad :: proc(dl: ^Draw_List, r: Rect, uv: [4]f32, c: Colour, tex: Texture_ID) {
	draw_quad_shape(dl, r, uv, c, tex, .Plain, 0)
}

draw_quad_shape :: proc(
	dl: ^Draw_List,
	r: Rect,
	uv: [4]f32,
	c: Colour,
	tex: Texture_ID,
	kind: Shape_Kind,
	radius: f32,
) {
	if r.w <= 0 || r.h <= 0 {return}

	quad := rect_scale(r, dl.scale)

	cr := rect_intersect(quad, dl.current_clip)
	if cr.w <= 0 || cr.h <= 0 {return}
	if cr.x == quad.x && cr.y == quad.y && cr.w == quad.w && cr.h == quad.h {
		draw_quad_vertices(dl, quad, quad, uv, c, tex, kind, radius * dl.scale)
		return
	}

	u0 := uv[0] + (cr.x - quad.x) / quad.w * (uv[2] - uv[0])
	u1 := uv[0] + (cr.x + cr.w - quad.x) / quad.w * (uv[2] - uv[0])
	v0 := uv[1] + (cr.y - quad.y) / quad.h * (uv[3] - uv[1])
	v1 := uv[1] + (cr.y + cr.h - quad.y) / quad.h * (uv[3] - uv[1])

	draw_quad_vertices(dl, cr, quad, [4]f32{u0, v0, u1, v1}, c, tex, kind, radius * dl.scale)
}

draw_quad_vertices :: proc(
	dl: ^Draw_List,
	r: Rect,
	full: Rect,
	uv: [4]f32,
	c: Colour,
	tex: Texture_ID,
	kind: Shape_Kind,
	radius: f32,
) {
	base := len(dl.vertices)
	resize(&dl.vertices, base + 4)
	p := [4][2]f32{{r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}}
	t := [4][2]f32{{uv[0], uv[1]}, {uv[2], uv[1]}, {uv[2], uv[3]}, {uv[0], uv[3]}}

	cx := full.x + full.w * 0.5
	cy := full.y + full.h * 0.5
	l := [4][2]f32 {
		{p[0][0] - cx, p[0][1] - cy},
		{p[1][0] - cx, p[1][1] - cy},
		{p[2][0] - cx, p[2][1] - cy},
		{p[3][0] - cx, p[3][1] - cy},
	}

	shape := [4]f32{f32(kind), radius, full.w * 0.5, full.h * 0.5}
	for i in 0 ..< 4 {
		dl.vertices[base + i] = Draw_Vertex {
			pos = p[i],
			uv = t[i],
			colour = c,
			shape = shape,
			local = l[i],
		}
	}

	idx_start := len(dl.indices)
	resize(&dl.indices, idx_start + 6)
	dl.indices[idx_start + 0] = u32(base + 0)
	dl.indices[idx_start + 1] = u32(base + 1)
	dl.indices[idx_start + 2] = u32(base + 2)
	dl.indices[idx_start + 3] = u32(base + 0)
	dl.indices[idx_start + 4] = u32(base + 2)
	dl.indices[idx_start + 5] = u32(base + 3)

	draw_command(dl, tex, u32(idx_start), 6)
}

draw_command :: proc(
	dl: ^Draw_List,
	tex: Texture_ID,
	idx_offset, idx_count: u32,
) {
	if len(dl.commands) > 0 {
		last := &dl.commands[len(dl.commands) - 1]
		if last.texture == tex {
			last.idx_count += idx_count
			return
		}
	}
	append(
		&dl.commands,
		Draw_Command{texture = tex, idx_offset = idx_offset, idx_count = idx_count},
	)
}

draw_polygon :: proc(dl: ^Draw_List, points: [][2]f32, c: Colour, tex: Texture_ID) {
	n := len(points)
	if n < 3 {return}

	clear(&dl.scaled)
	for p in points {
		append(&dl.scaled, [2]f32{p[0] * dl.scale, p[1] * dl.scale})
	}

	cut := draw_clip_polygon(dl, dl.scaled[:])
	n = len(cut)
	if n < 3 {return}

	centre := [2]f32{}
	for p in cut {centre[0] += p[0]; centre[1] += p[1]}
	centre[0] /= f32(n)
	centre[1] /= f32(n)

	base := u32(len(dl.vertices))
	append(
		&dl.vertices,
		Draw_Vertex{pos = centre, colour = c, shape = [4]f32{0, 0, 0, 0}, local = {0, 0}},
	)
	for p in cut {
		append(
			&dl.vertices,
			Draw_Vertex {
				pos = p,
				colour = c,
				shape = [4]f32{0, 0, 0, 0},
				local = {p[0] - centre[0], p[1] - centre[1]},
			},
		)
	}

	idx_start := u32(len(dl.indices))
	for i in 0 ..< n {
		append(&dl.indices, base + 1 + u32(i))
		append(&dl.indices, base + 1 + u32((i + 1) % n))
		append(&dl.indices, base)
	}
	draw_command(dl, tex, idx_start, u32(n * 3))
}

draw_thick_line :: proc(dl: ^Draw_List, a, b: [2]f32, width: f32, c: Colour, tex: Texture_ID) {
	dx := b[0] - a[0]
	dy := b[1] - a[1]
	length := math.sqrt(dx * dx + dy * dy)
	if length <= 0 {return}
	nx := -dy / length * width * 0.5
	ny := dx / length * width * 0.5
	points := [][2]f32 {
		{a[0] + nx, a[1] + ny},
		{b[0] + nx, b[1] + ny},
		{b[0] - nx, b[1] - ny},
		{a[0] - nx, a[1] - ny},
	}
	draw_polygon(dl, points, c, tex)
}

clip_edges :: proc(r: Rect) -> [4][4]f32 {
	return [4][4]f32{
		{r.x, r.y, r.x + r.w, r.y},
		{r.x + r.w, r.y, r.x + r.w, r.y + r.h},
		{r.x + r.w, r.y + r.h, r.x, r.y + r.h},
		{r.x, r.y + r.h, r.x, r.y},
	}
}

clip_side :: proc(edge: [4]f32, p: [2]f32) -> f32 {
	dx := edge[2] - edge[0]
	dy := edge[3] - edge[1]
	return dx * (p[1] - edge[1]) - dy * (p[0] - edge[0])
}

draw_clip_polygon :: proc(dl: ^Draw_List, points: [][2]f32) -> [][2]f32 {
	clip := dl.current_clip
	if clip.w <= 0 || clip.h <= 0 {return points[:0]}
	if polygon_inside(points, clip) {return points}

	clear(&dl.clip_a)
	clear(&dl.clip_b)

	src := points
	use_a := true
	for edge in clip_edges(clip) {
		if use_a {
			clear(&dl.clip_a)
			clip_polygon_edge(&dl.clip_a, src, edge)
			if len(dl.clip_a) == 0 {return dl.clip_a[:]}
			src = dl.clip_a[:]
		} else {
			clear(&dl.clip_b)
			clip_polygon_edge(&dl.clip_b, src, edge)
			if len(dl.clip_b) == 0 {return dl.clip_b[:]}
			src = dl.clip_b[:]
		}
		use_a = !use_a
	}
	return src
}

polygon_inside :: proc(points: [][2]f32, r: Rect) -> bool {
	for p in points {
		if p[0] < r.x || p[0] > r.x + r.w {return false}
		if p[1] < r.y || p[1] > r.y + r.h {return false}
	}
	return true
}

clip_polygon_edge :: proc(dst: ^[dynamic][2]f32, points: [][2]f32, edge: [4]f32) {
	n := len(points)
	if n == 0 {return}
	prev := points[n - 1]
	prev_side := clip_side(edge, prev)
	for point in points {
		side := clip_side(edge, point)
		prev_in := prev_side >= 0
		point_in := side >= 0
		if prev_in != point_in {
			t := prev_side / (prev_side - side)
			append(
				dst,
				[2]f32{
					prev[0] + (point[0] - prev[0]) * t,
					prev[1] + (point[1] - prev[1]) * t,
				},
			)
		}
		if point_in { append(dst, point) }
		prev = point
		prev_side = side
	}
}

