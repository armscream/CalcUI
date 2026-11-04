//* The renderer-agnostic draw contract.
//
//* There is exactly ONE command type: a range of indices into a shared
//* vertex/index buffer and the texture it samples. Clipping is
//* resolved while the list is built, so a quad that is partly outside
//* of its clip rect is cut on the CPU and its texture coordinates are
//* moved with it. A quad that is cut away entirely is not in the list
//* at all.
//
//* Because every quad of the UI comes out of the one atlas, and
//* because the clip is already resolved, the whole of a window is one
//* command: one draw call.
package GUI

import "core:math"

//* What a vertex does with the texture it samples.
Shape_Kind :: enum u32 {
	//* The texture is sampled as it is. This is what the glyphs and
	//* the images use.
	Plain    = 0,
	//* The colour of the vertex is the whole of the fragment: the
	//* texture is not sampled. A solid quad with rounded corners.
	Solid    = 1,
	//* The texture is sampled and the rounded corners cut it.
	Textured = 2,
}

Draw_Vertex :: struct {
	pos:    [2]f32,
	uv:     [2]f32,
	//* Straight alpha: the colour is not multiplied by the alpha
	//* here. A backend that blends with premultiplied alpha does the
	//* multiplying itself.
	colour: Colour,
	//* The shape of the fragment: the kind, the radius of the corners
	//* and the half size of the quad the vertex belongs to.
	shape:  [4]f32,
	//* Where the vertex sits inside its quad, measured from the
	//* middle of the quad. The shader uses it to work out how far a
	//* fragment is from a rounded corner.
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
	base_clip:    Rect, // the clip of the whole list
	current_clip: Rect,
	//* The two buffers the polygons are cut in. They keep their
	//* capacity between frames.
	clip_a:       [dynamic][2]f32,
	clip_b:       [dynamic][2]f32,
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
	delete(dl.clip_a)
	delete(dl.clip_b)
}

//* Clip state lives in the builder, never in the command list.
draw_push_clip :: proc(dl: ^Draw_List, r: Rect) {
	append(&dl.clip_stack, rect_intersect(dl.current_clip, r))
	dl.current_clip = dl.clip_stack[len(dl.clip_stack) - 1]
}

//* Popping the last clip goes back to the clip of the whole list, so
//* anything drawn after the tree is not clipped away.
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

//* == The quads ==

//* Emits one textured quad. The quad is cut to the clip rect of the
//* builder, and its texture coordinates are moved with it, so the
//* part of the texture the quad shows is the part it showed before.
//* A quad that is cut away entirely is dropped: it costs no vertices
//* and no indices.
draw_quad :: proc(dl: ^Draw_List, r: Rect, uv: [4]f32, c: Colour, tex: Texture_ID) {
	draw_quad_shape(dl, r, uv, c, tex, .Plain, 0)
}

//* Emits a quad that is cut to the clip rect, with a shape effect on
//* top: a rounded rectangle, with or without a texture.
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

	cr := rect_intersect(r, dl.current_clip)
	if cr.w <= 0 || cr.h <= 0 {return}

	//* A quad that is not cut keeps its texture coordinates, so there
	//* is no arithmetic to do. That is the common case.
	if cr.x == r.x && cr.y == r.y && cr.w == r.w && cr.h == r.h {
		draw_quad_vertices(dl, r, r, uv, c, tex, kind, radius)
		return
	}

	//* The texture coordinates follow the cut: the part of the
	//* texture the quad shows is the part it showed before.
	u0 := uv[0] + (cr.x - r.x) / r.w * (uv[2] - uv[0])
	u1 := uv[0] + (cr.x + cr.w - r.x) / r.w * (uv[2] - uv[0])
	v0 := uv[1] + (cr.y - r.y) / r.h * (uv[3] - uv[1])
	v1 := uv[1] + (cr.y + cr.h - r.y) / r.h * (uv[3] - uv[1])

	draw_quad_vertices(dl, cr, r, [4]f32{u0, v0, u1, v1}, c, tex, kind, radius)
}

//* The vertices of a quad. `r` is the part that is drawn, `full` is
//* the quad the shape belongs to: the rounded corners keep their
//* place when the quad is cut.
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

	//* Where every corner sits inside the quad it belongs to, measured
	//* from the middle of that quad.
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

//* Adds a command to the list, or adds to the last one when it is the
//* same texture: the whole of a window is then one command.
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

//* == The polygons ==

//* Emits a polygon: a fan of triangles around its middle. The polygon
//* is cut to the clip of the builder, so a shape that reaches out of
//* it is cut on the CPU. It is still part of the command of the list,
//* so it costs no draw call of its own.
//
//* The polygon has one colour: it samples the texel at the origin of
//* its texture. The atlas keeps a white texel there, so a polygon
//* drawn from the atlas is the colour it is given.
draw_polygon :: proc(dl: ^Draw_List, points: [][2]f32, c: Colour, tex: Texture_ID) {
	n := len(points)
	if n < 3 {return}

	cut := draw_clip_polygon(dl, points)
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

//* A thick line between two points. It is not a rectangle, so it goes
//* into the polygon path.
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

//* == The clipping of the polygons ==
//* The quads are cut by the builder itself. A polygon is not a quad,
//* so it is cut here: against the four sides of the clip, one after
//* the other. The clip is a rect, and a rect is convex, so the cut is
//* exact for a polygon that is convex itself.

//* The edges of a rect, in the order the clipping wants them. The
//* inside of an edge is on its left.
clip_edges :: proc(r: Rect) -> [4][4]f32 {
	return [4][4]f32{
		{r.x, r.y, r.x + r.w, r.y},
		{r.x + r.w, r.y, r.x + r.w, r.y + r.h},
		{r.x + r.w, r.y + r.h, r.x, r.y + r.h},
		{r.x, r.y + r.h, r.x, r.y},
	}
}

//* How far a point is to the left of an edge. It is positive when the
//* point is inside the rect the edge belongs to.
clip_side :: proc(edge: [4]f32, p: [2]f32) -> f32 {
	dx := edge[2] - edge[0]
	dy := edge[3] - edge[1]
	return dx * (p[1] - edge[1]) - dy * (p[0] - edge[0])
}

//* Cuts a polygon to the clip of the builder. The points that come
//* back live in the scratch buffers of the list, so they are only good
//* until the next polygon is cut.
draw_clip_polygon :: proc(dl: ^Draw_List, points: [][2]f32) -> [][2]f32 {
	clip := dl.current_clip
	if clip.w <= 0 || clip.h <= 0 {return points[:0]}

	//* A polygon that is inside the clip is left alone: that is the
	//* common case, and the cut is not cheap.
	if polygon_inside(points, clip) {return points}

	clear(&dl.clip_a)
	clear(&dl.clip_b)

	src := points
	use_a := true
	for edge in clip_edges(clip) {
		//* The buffer that is written to is emptied first: the two
		//* buffers trade places, so it holds the result of the edge
		//* before it otherwise.
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

//* True when every point of the polygon is inside the rect. The rect
//* is convex, so then the whole polygon is inside it.
polygon_inside :: proc(points: [][2]f32, r: Rect) -> bool {
	for p in points {
		if p[0] < r.x || p[0] > r.x + r.w {return false}
		if p[1] < r.y || p[1] > r.y + r.h {return false}
	}
	return true
}

//* Keeps the points that are on the inside of one side of the clip and
//* cuts the ones that are not.
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
			//* The polygon crosses the edge: the point of the
			//* crossing goes in.
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
