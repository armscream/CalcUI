//* The renderer-agnostic draw contract: one command type, one atlas,
//* one draw call for a whole window. The clip is resolved while the
//* list is built: a cut quad is cut on the CPU and its texture
//* coordinates are moved with it.
package Core
import "core:math"

Shape_Kind :: enum u32 {
	Plain    = 0,
	Solid    = 1,
	Textured = 2,
	Shadow   = 3,
	Border   = 4,
	//* A frosted box: the shader reads the target behind it, blurs that
	//* and tints the result. Its command is never batched with another,
	//* because the renderer has to take a snapshot at its boundary.
	Glass    = 5,
}

Draw_Vertex :: struct {
	pos:      [2]f32,
	uv:       [2]f32,
	colour:   Colour,
	shape:    [4]f32,
	local:    [2]f32,
	softness: f32,
	corners:  [4]f32,
	border:   [4]f32,
	//* The opacity of the list when the vertex was made. A glass shape
	//* reads it to fade the backdrop it took, since its colour alpha is
	//* the tint and not the coverage.
	opacity:  f32,
}

Packed_Vertex :: struct {
	pos:     [2]f32,
	uv:      [2]u16,
	colour:  [4]u8,
	shape:   [4]f32,
	local:   [2]f32,
	corners: [4]u16,
	border:  [4]i16,
	opacity: f32,
}

pack_vertex :: proc(v: Draw_Vertex) -> Packed_Vertex {
	out := Packed_Vertex {
		pos     = v.pos,
		shape   = {v.shape[0], v.softness, v.shape[2], v.shape[3]},
		local   = v.local,
		opacity = v.opacity,
	}
	out.uv[0] = pack_unit(v.uv[0])
	out.uv[1] = pack_unit(v.uv[1])
	out.colour[0] = pack_byte(v.colour.r)
	out.colour[1] = pack_byte(v.colour.g)
	out.colour[2] = pack_byte(v.colour.b)
	out.colour[3] = pack_byte(v.colour.a)
	for i in 0 ..< 4 {
		out.corners[i] = u16(math.round(clamp(v.corners[i], 0, 4095.9375) * 16))
		out.border[i] = i16(math.round(clamp(v.border[i], -256, 255.99) * 128))
	}
	return out
}

unpack_vertex :: proc(p: Packed_Vertex) -> Draw_Vertex {
	out := Draw_Vertex {
		pos      = p.pos,
		shape    = {p.shape[0], 0, p.shape[2], p.shape[3]},
		local    = p.local,
		softness = p.shape[1],
		opacity  = p.opacity,
	}
	out.uv[0] = f32(p.uv[0]) / 65535
	out.uv[1] = f32(p.uv[1]) / 65535
	out.colour = Colour {
		r = f32(p.colour[0]) / 255,
		g = f32(p.colour[1]) / 255,
		b = f32(p.colour[2]) / 255,
		a = f32(p.colour[3]) / 255,
	}
	for i in 0 ..< 4 {
		out.corners[i] = f32(p.corners[i]) / 16
		out.border[i] = f32(p.border[i]) / 128
	}
	return out
}

pack_unit :: proc(v: f32) -> u16 {
	return u16(math.round(clamp(v, 0, 1) * 65535))
}

pack_byte :: proc(v: f32) -> u8 {
	return u8(math.round(clamp(v, 0, 1) * 255))
}

Draw_Command :: struct {
	texture:    Texture_ID,
	idx_count:  u32,
	idx_offset: u32,
	glass:      bool,
	bounds:     Rect,
	blur:       f32,
}

Clip_Shape :: struct {
	rect:      Rect,
	radii:     [4]f32,
	clip_rect: Rect,
	inner:     Rect,
	rounded:   bool,
}

Draw_List :: struct {
	vertices:     [dynamic]Draw_Vertex,
	indices:      [dynamic]u32,
	commands:     [dynamic]Draw_Command,
	clip_stack:   [dynamic]Clip_Shape,
	base_clip:    Rect,
	current_clip: Rect,
	clip_inner:   Rect,
	clip_rounded: bool,
	white_uv:     [2]f32,
	clip_a:       [dynamic][2]f32,
	clip_b:        [dynamic][2]f32,
	scaled:       [dynamic][2]f32,
	clip_verts_a: [dynamic]Draw_Vertex,
	clip_verts_b: [dynamic]Draw_Vertex,
	clip_source:  [dynamic]Draw_Vertex,
	scale:        f32,
	opacity:      f32,
	revision:     u64,
	dirty_rect:   Rect,
	partial:      bool,
	has_glass:    bool,
}

draw_list_clear :: proc(dl: ^Draw_List, viewport: Rect) {
	if !(dl.scale > 0) {dl.scale = 1}
	clear(&dl.vertices)
	clear(&dl.indices)
	clear(&dl.commands)
	clear(&dl.clip_stack)
	clear(&dl.clip_verts_a)
	clear(&dl.clip_verts_b)
	clear(&dl.clip_source)
	dl.base_clip = rect_scale(viewport, dl.scale)
	dl.current_clip = dl.base_clip
	dl.clip_inner = dl.base_clip
	dl.clip_rounded = false
	dl.opacity = 1
	dl.revision += 1
	dl.dirty_rect = {}
	dl.partial = false
	dl.has_glass = false
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
	delete(dl.clip_verts_a)
	delete(dl.clip_verts_b)
	delete(dl.clip_source)
	dl^ = {}
}

draw_push_clip :: proc(dl: ^Draw_List, r: Rect) {
	draw_push_clip_radii(dl, r, {})
}

draw_push_clip_radii :: proc(dl: ^Draw_List, r: Rect, radii: [4]f32) {
	scaled := rect_scale(r, dl.scale)
	clip_rect := rect_intersect(dl.current_clip, scaled)
	clamped := clamp_corner_radii(
		[4]f32 {
			radii[0] * dl.scale,
			radii[1] * dl.scale,
			radii[2] * dl.scale,
			radii[3] * dl.scale,
		},
		scaled.w,
		scaled.h,
	)
	inset := max_corner_radius(clamped)
	inner := Rect {
		x = scaled.x + inset,
		y = scaled.y + inset,
		w = max(scaled.w - inset * 2, 0),
		h = max(scaled.h - inset * 2, 0),
	}
	append(
		&dl.clip_stack,
		Clip_Shape {
			rect = scaled,
			radii = clamped,
			clip_rect = clip_rect,
			inner = inner,
			rounded = !radii_are_zero(clamped),
		},
	)
	if len(dl.clip_stack) == 1 {
		dl.clip_inner = inner
	} else {
		dl.clip_inner = rect_intersect(dl.clip_inner, inner)
	}
	if !radii_are_zero(clamped) {dl.clip_rounded = true}
	dl.current_clip = clip_rect
}

draw_pop_clip :: proc(dl: ^Draw_List) {
	if len(dl.clip_stack) == 0 {return}
	_ = pop(&dl.clip_stack)
	dl.current_clip = len(dl.clip_stack) > 0 ? dl.clip_stack[len(dl.clip_stack) - 1].clip_rect : dl.base_clip
	dl.clip_inner = dl.base_clip
	dl.clip_rounded = false
	for shape, i in dl.clip_stack {
		if i == 0 {
			dl.clip_inner = shape.inner
		} else {
			dl.clip_inner = rect_intersect(dl.clip_inner, shape.inner)
		}
		if shape.rounded {dl.clip_rounded = true}
	}
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

rect_inside :: proc(inner, outer: Rect) -> bool {
	return inner.x >= outer.x &&
	       inner.y >= outer.y &&
	       inner.x + inner.w <= outer.x + outer.w &&
	       inner.y + inner.h <= outer.y + outer.h
}

rect_overlaps :: proc(a, b: Rect) -> bool {
	return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

clip_needs_shape :: proc(dl: ^Draw_List, r: Rect) -> bool {
	if !dl.clip_rounded {return false}
	if rect_inside(r, dl.clip_inner) {return false}
	for shape in dl.clip_stack {
		if !shape.rounded {continue}
		if rect_inside(r, shape.inner) {continue}
		if !rect_overlaps(r, shape.clip_rect) {return false}
		return true
	}
	return false
}

clip_needs_any :: proc(dl: ^Draw_List, r: Rect) -> bool {
	if len(dl.clip_stack) == 0 {return false}
	if !rect_inside(r, dl.current_clip) {return true}
	return clip_needs_shape(dl, r)
}

draw_vertex_mix :: proc(a, b: Draw_Vertex, t: f32) -> Draw_Vertex {
	out := a
	out.pos = [2]f32{a.pos[0] + (b.pos[0] - a.pos[0]) * t, a.pos[1] + (b.pos[1] - a.pos[1]) * t}
	out.uv = [2]f32{a.uv[0] + (b.uv[0] - a.uv[0]) * t, a.uv[1] + (b.uv[1] - a.uv[1]) * t}
	out.colour = Colour {
		r = a.colour.r + (b.colour.r - a.colour.r) * t,
		g = a.colour.g + (b.colour.g - a.colour.g) * t,
		b = a.colour.b + (b.colour.b - a.colour.b) * t,
		a = a.colour.a + (b.colour.a - a.colour.a) * t,
	}
	out.shape = [4]f32 {
		a.shape[0] + (b.shape[0] - a.shape[0]) * t,
		a.shape[1] + (b.shape[1] - a.shape[1]) * t,
		a.shape[2] + (b.shape[2] - a.shape[2]) * t,
		a.shape[3] + (b.shape[3] - a.shape[3]) * t,
	}
	out.local = [2]f32 {
		a.local[0] + (b.local[0] - a.local[0]) * t,
		a.local[1] + (b.local[1] - a.local[1]) * t,
	}
	out.softness = a.softness + (b.softness - a.softness) * t
	out.corners = [4]f32 {
		a.corners[0] + (b.corners[0] - a.corners[0]) * t,
		a.corners[1] + (b.corners[1] - a.corners[1]) * t,
		a.corners[2] + (b.corners[2] - a.corners[2]) * t,
		a.corners[3] + (b.corners[3] - a.corners[3]) * t,
	}
	out.border = [4]f32 {
		a.border[0] + (b.border[0] - a.border[0]) * t,
		a.border[1] + (b.border[1] - a.border[1]) * t,
		a.border[2] + (b.border[2] - a.border[2]) * t,
		a.border[3] + (b.border[3] - a.border[3]) * t,
	}
	out.opacity = a.opacity + (b.opacity - a.opacity) * t
	return out
}

clip_vertex_edge :: proc(
	dst: ^[dynamic]Draw_Vertex,
	src: []Draw_Vertex,
	ax, ay, bx, by: f32,
) {
	n := len(src)
	if n == 0 {return}
	dx := bx - ax
	dy := by - ay
	prev := src[n - 1]
	prev_side := dx * (prev.pos[1] - ay) - dy * (prev.pos[0] - ax)
	for point in src {
		side := dx * (point.pos[1] - ay) - dy * (point.pos[0] - ax)
		prev_in := prev_side >= 0
		point_in := side >= 0
		if prev_in != point_in {
			t := prev_side / (prev_side - side)
			append(dst, draw_vertex_mix(prev, point, t))
		}
		if point_in {append(dst, point)}
		prev = point
		prev_side = side
	}
}

clip_shape_points :: proc(shape: Clip_Shape, points: ^[4 * (CORNER_SEGMENTS + 1)][2]f32) -> int {
	if !shape.rounded {
		points[0] = {shape.rect.x, shape.rect.y}
		points[1] = {shape.rect.x + shape.rect.w, shape.rect.y}
		points[2] = {shape.rect.x + shape.rect.w, shape.rect.y + shape.rect.h}
		points[3] = {shape.rect.x, shape.rect.y + shape.rect.h}
		return 4
	}
	round_rect_loop(shape.rect, shape.radii, CORNER_SEGMENTS, points[:])
	return 4 * (CORNER_SEGMENTS + 1)
}

clip_polygon_vertices :: proc(dl: ^Draw_List, src: []Draw_Vertex) -> []Draw_Vertex {
	if len(dl.clip_stack) == 0 {return src}
	clear(&dl.clip_verts_a)
	append(&dl.clip_verts_a, ..src)
	cur := &dl.clip_verts_a
	other := &dl.clip_verts_b

	for shape in dl.clip_stack {
		points: [4 * (CORNER_SEGMENTS + 1)][2]f32
		count := clip_shape_points(shape, &points)
		for i in 0 ..< count {
			a := points[i]
			b := points[(i + 1) % count]
			clear(other)
			clip_vertex_edge(other, cur[:], a[0], a[1], b[0], b[1])
			if len(other) == 0 {return other[:]}
			cur, other = other, cur
		}
	}

	base_points := [4][2]f32 {
		{dl.base_clip.x, dl.base_clip.y},
		{dl.base_clip.x + dl.base_clip.w, dl.base_clip.y},
		{dl.base_clip.x + dl.base_clip.w, dl.base_clip.y + dl.base_clip.h},
		{dl.base_clip.x, dl.base_clip.y + dl.base_clip.h},
	}
	for i in 0 ..< 4 {
		a := base_points[i]
		b := base_points[(i + 1) % 4]
		clear(other)
		clip_vertex_edge(other, cur[:], a[0], a[1], b[0], b[1])
		if len(other) == 0 {return other[:]}
		cur, other = other, cur
	}
	return cur[:]
}

emit_polygon_vertices :: proc(
	dl: ^Draw_List,
	verts: []Draw_Vertex,
	tex: Texture_ID,
	glass: bool = false,
	bounds: Rect = {},
	blur: f32 = 0,
) {
	n := len(verts)
	if n < 3 {return}
	base := u32(len(dl.vertices))
	old_len := len(dl.vertices)
	resize(&dl.vertices, old_len + n)
	copy(dl.vertices[old_len:][:n], verts)

	idx_start := len(dl.indices)
	triangles := n - 2
	resize(&dl.indices, idx_start + triangles * 3)
	for i in 0 ..< triangles {
		at := idx_start + i * 3
		dl.indices[at + 0] = base
		dl.indices[at + 1] = base + u32(i + 1)
		dl.indices[at + 2] = base + u32(i + 2)
	}
	draw_command(dl, tex, u32(idx_start), u32(triangles * 3), glass, bounds, blur)
}

polygon_bounds :: proc(points: [][2]f32) -> Rect {
	if len(points) == 0 {return {}}
	x0, y0 := points[0][0], points[0][1]
	x1, y1 := x0, y0
	for p in points {
		x0 = min(x0, p[0])
		y0 = min(y0, p[1])
		x1 = max(x1, p[0])
		y1 = max(y1, p[1])
	}
	return Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
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
	glass: bool = false,
) {
	draw_quad_shape_full(
		dl,
		r,
		uv,
		c,
		tex,
		kind,
		radius,
		{r.w * 0.5, r.h * 0.5},
		0,
		{radius, radius, radius, radius},
		{},
		glass,
	)
}


draw_quad_shape_full :: proc(
	dl: ^Draw_List,
	r: Rect,
	uv: [4]f32,
	c: Colour,
	tex: Texture_ID,
	kind: Shape_Kind,
	radius: f32,
	shape_half: [2]f32,
	softness: f32,
	corners: [4]f32,
	border: [4]f32,
	glass: bool = false,
) {
	if r.w <= 0 || r.h <= 0 {return}

	quad := rect_scale(r, dl.scale)
	half := [2]f32{shape_half[0] * dl.scale, shape_half[1] * dl.scale}
	blur := softness * dl.scale
	scaled_corners := [4]f32 {
		corners[0] * dl.scale,
		corners[1] * dl.scale,
		corners[2] * dl.scale,
		corners[3] * dl.scale,
	}
	scaled_border := border
	scaled_border[0] = border[0] * dl.scale
	scaled_border[1] = border[1] * dl.scale
	if kind != .Glass {
		scaled_border[2] = border[2] * dl.scale
		scaled_border[3] = border[3] * dl.scale
	}

	cr := rect_intersect(quad, dl.current_clip)
	if cr.w <= 0 || cr.h <= 0 {return}
	if cr.x == quad.x && cr.y == quad.y && cr.w == quad.w && cr.h == quad.h {
		draw_quad_vertices(
			dl,
			quad,
			quad,
			uv,
			c,
			tex,
			kind,
			radius * dl.scale,
			half,
			blur,
			scaled_corners,
			scaled_border,
			glass,
		)
		return
	}

	u0 := uv[0] + (cr.x - quad.x) / quad.w * (uv[2] - uv[0])
	u1 := uv[0] + (cr.x + cr.w - quad.x) / quad.w * (uv[2] - uv[0])
	v0 := uv[1] + (cr.y - quad.y) / quad.h * (uv[3] - uv[1])
	v1 := uv[1] + (cr.y + cr.h - quad.y) / quad.h * (uv[3] - uv[1])

	draw_quad_vertices(
		dl,
		cr,
		quad,
		[4]f32{u0, v0, u1, v1},
		c,
		tex,
		kind,
		radius * dl.scale,
		half,
		blur,
		scaled_corners,
		scaled_border,
		glass,
	)
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
	shape_half: [2]f32,
	softness: f32,
	corners: [4]f32 = {},
	border: [4]f32 = {},
	glass: bool = false,
) {
	colour := c
	if dl.opacity != 1 {
		colour.a *= dl.opacity
	}
	dl.revision += 1
	corner_radii := corners
	if radii_are_zero(corner_radii) && radius > 0 {
		corner_radii = {radius, radius, radius, radius}
	}
	if shape_half[0] > 0 && shape_half[1] > 0 {
		corner_radii = clamp_corner_radii(corner_radii, shape_half[0] * 2, shape_half[1] * 2)
	} else {
		corner_radii = {}
	}

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

	shape := [4]f32{f32(kind), radius, shape_half[0], shape_half[1]}
	glass_reach := glass ? abs(softness) + max(border[0], 0) + max(border[1], 0) : 0
	verts: [4]Draw_Vertex
	for i in 0 ..< 4 {
		verts[i] = Draw_Vertex {
			pos = p[i],
			uv = t[i],
			colour = colour,
			shape = shape,
			local = l[i],
			softness = softness,
			corners = corner_radii,
			border = border,
			opacity = dl.opacity,
		}
	}

	if clip_needs_shape(dl, r) {
		clear(&dl.clip_source)
		append(&dl.clip_source, ..verts[:])
		clipped := clip_polygon_vertices(dl, dl.clip_source[:])
		emit_polygon_vertices(dl, clipped, tex, glass, full, glass_reach)
		return
	}
	emit_polygon_vertices(dl, verts[:], tex, glass, full, glass_reach)
}

draw_command :: proc(
	dl: ^Draw_List,
	tex: Texture_ID,
	idx_offset, idx_count: u32,
	glass: bool = false,
	bounds: Rect = {},
	blur: f32 = 0,
) {
	if len(dl.commands) > 0 {
		last := &dl.commands[len(dl.commands) - 1]
		if !glass && !last.glass && last.texture == tex {
			last.idx_count += idx_count
			return
		}
	}
	append(
		&dl.commands,
		Draw_Command {
			texture = tex,
			idx_offset = idx_offset,
			idx_count = idx_count,
			glass = glass,
			bounds = bounds,
			blur = blur,
		},
	)
	if glass {dl.has_glass = true}
}

draw_polygon :: proc(dl: ^Draw_List, points: [][2]f32, c: Colour, tex: Texture_ID) {
	n := len(points)
	if n < 3 {return}

	dl.revision += 1

	colour := c
	if dl.opacity != 1 {
		colour.a *= dl.opacity
	}
	clear(&dl.scaled)
	for p in points {
		append(&dl.scaled, [2]f32{p[0] * dl.scale, p[1] * dl.scale})
	}

	cut := draw_clip_polygon(dl, dl.scaled[:])
	n = len(cut)
	if n < 3 {return}

	if clip_needs_shape(dl, polygon_bounds(cut)) {
		clear(&dl.clip_source)
		for p in cut {
			append(&dl.clip_source, Draw_Vertex{pos = p, uv = dl.white_uv, colour = colour, opacity = dl.opacity})
		}
		clipped := clip_polygon_vertices(dl, dl.clip_source[:])
		emit_polygon_vertices(dl, clipped, tex)
		return
	}

	centre := [2]f32{}
	for p in cut {centre[0] += p[0]; centre[1] += p[1]}
	centre[0] /= f32(n)
	centre[1] /= f32(n)

	base := u32(len(dl.vertices))
	append(
		&dl.vertices,
		Draw_Vertex{pos = centre, uv = dl.white_uv, colour = colour, shape = [4]f32{0, 0, 0, 0}, local = {0, 0}, opacity = dl.opacity},
	)
	for p in cut {
		append(
			&dl.vertices,
			Draw_Vertex {
				pos = p,
				uv = dl.white_uv,
				colour = colour,
				shape = [4]f32{0, 0, 0, 0},
				local = {p[0] - centre[0], p[1] - centre[1]},
				opacity = dl.opacity,
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
