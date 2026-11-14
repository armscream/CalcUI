package GUI

import "core:log"
import "core:math"
import virt "core:mem/virtual"

Vector_Drawing_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Vector_Drawing :: proc(g: ^GUI, parent: Widget_ID, opts: Vector_Drawing_Opts) -> Widget_ID {
	kind_register(g, .VectorDrawing, vector_drawing_kind())
	id := New_Widget(g, .VectorDrawing, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	state, err := virt.new(&g.arena, Vector_Drawing_State)
	if err != nil {
		log.panicf("the state of the drawing could not be made: %v", err)
	}
	state^ = Vector_Drawing_State{}
	state.shapes = make([dynamic]Vector_Shape, 0, 8, virt.arena_allocator(&g.arena))
	state.selected = -1
	state.dragging = -1
	state.zoom = 1
	w.data = Vector_Drawing_Data {
		state = state,
	}
	return id
}

vector_drawing_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_vector_drawing,
		update = update_vector_drawing,
		click = click_vector_drawing,
		style = Style {
			box = StyleBox {
				bg_color = RGBA(0.10, 0.11, 0.14, 1),
				border_color = {
					RGBA(0.20, 0.22, 0.27, 1),
					RGBA(0.20, 0.22, 0.27, 1),
					RGBA(0.20, 0.22, 0.27, 1),
					RGBA(0.20, 0.22, 0.27, 1),
				},
				border_width = {1, 1, 1, 1},
			},
		},
		theme_name = "VectorDrawing",
	}
}

vector_drawing_data :: proc(g: ^GUI, id: Widget_ID) -> ^Vector_Drawing_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Vector_Drawing_Data:
		return &d
	}
	return nil
}

//* Adds a shape and returns its index.
vector_drawing_add_shape :: proc(g: ^GUI, id: Widget_ID, shape: Vector_Shape) -> int {
	d := vector_drawing_data(g, id)
	if d == nil {return -1}
	if d.state == nil {return -1}
	append(&d.state.shapes, shape)
	invalidate(g, id, Dirty_Flags{.Visual})
	return len(d.state.shapes) - 1
}

vector_drawing_shape_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := vector_drawing_data(g, id)
	if d == nil {return 0}
	if d.state == nil {return 0}
	return len(d.state.shapes)
}

//* Returns the shape at a drawing-space point, or -1.
vector_drawing_shape_at :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) -> int {
	d := vector_drawing_data(g, id)
	if d == nil {return -1}
	if d.state == nil {return -1}
	return vector_state_shape_at(d.state, pos, VECTOR_PICK_TOLERANCE)
}

//* Moves a shape by a drawing-space delta.
vector_drawing_move_shape :: proc(g: ^GUI, id: Widget_ID, index: int, delta: Vec2) {
	d := vector_drawing_data(g, id)
	if d == nil {return}
	if d.state == nil {return}
	if index < 0 || index >= len(d.state.shapes) {return}
	vector_shape_move(&d.state.shapes[index], delta)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Returns the selected shape, or -1.
vector_drawing_selected :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := vector_drawing_data(g, id)
	if d == nil {return -1}
	if d.state == nil {return -1}
	return d.state.selected
}

vector_drawing_zoom :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	d := vector_drawing_data(g, id)
	if d == nil {return 1}
	if d.state == nil {return 1}
	return d.state.zoom
}

//* Sets the zoom. Non-positive values are ignored.
vector_drawing_set_zoom :: proc(g: ^GUI, id: Widget_ID, zoom: f32) {
	d := vector_drawing_data(g, id)
	if d == nil {return}
	if d.state == nil {return}
	if zoom <= 0 {return}
	d.state.zoom = zoom
	invalidate(g, id, Dirty_Flags{.Visual})
}

vector_drawing_add_line :: proc(
	g: ^GUI,
	id: Widget_ID,
	a, b: Vec2,
	colour: Colour,
	width: f32 = 0,
) -> int {
	points := [2]Vec2{a, b}
	return vector_drawing_add_shape(
		g,
		id,
		Vector_Shape {
			kind = .Line,
			points = vector_points(g, points[:]),
			colour = colour,
			width = width,
		},
	)
}

//* Adds a rectangle defined by its opposite corners.
vector_drawing_add_rect :: proc(
	g: ^GUI,
	id: Widget_ID,
	top_left, bottom_right: Vec2,
	colour: Colour,
	width: f32 = 0,
) -> int {
	points := [2]Vec2{top_left, bottom_right}
	return vector_drawing_add_shape(
		g,
		id,
		Vector_Shape {
			kind = .Rect,
			points = vector_points(g, points[:]),
			colour = colour,
			width = width,
		},
	)
}

//* Adds an ellipse defined by its centre and radii.
vector_drawing_add_ellipse :: proc(
	g: ^GUI,
	id: Widget_ID,
	centre, radii: Vec2,
	colour: Colour,
	width: f32 = 0,
) -> int {
	points := [2]Vec2{centre, radii}
	return vector_drawing_add_shape(
		g,
		id,
		Vector_Shape {
			kind = .Ellipse,
			points = vector_points(g, points[:]),
			colour = colour,
			width = width,
		},
	)
}

vector_drawing_add_polygon :: proc(
	g: ^GUI,
	id: Widget_ID,
	points: []Vec2,
	colour: Colour,
	width: f32 = 0,
) -> int {
	return vector_drawing_add_shape(
		g,
		id,
		Vector_Shape {
			kind = .Polygon,
			points = vector_points(g, points),
			colour = colour,
			width = width,
		},
	)
}

//* Copies shape points into the GUI arena.
vector_points :: proc(g: ^GUI, points: []Vec2) -> [dynamic]Vec2 {
	allocator := virt.arena_allocator(&g.arena)
	out := make([dynamic]Vec2, 0, len(points), allocator)
	for point in points {
		append(&out, point)
	}
	return out
}

VECTOR_LINE_WIDTH :: 2
VECTOR_PICK_TOLERANCE :: 6
VECTOR_ELLIPSE_SEGMENTS :: 32

vector_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

//* Converts between drawing-space and screen-space coordinates.
vector_to_screen :: proc(origin: Vec2, scroll: Vec2, zoom: f32, p: Vec2) -> [2]f32 {
	return [2]f32{origin.x + scroll.x + p.x * zoom, origin.y + scroll.y + p.y * zoom}
}

vector_to_drawing :: proc(origin: Vec2, scroll: Vec2, zoom: f32, p: Vec2) -> Vec2 {
	z := zoom
	if z <= 0 {z = 1}
	return Vec2{(p.x - origin.x - scroll.x) / z, (p.y - origin.y - scroll.y) / z}
}

vector_shape_reference :: proc(shape: Vector_Shape) -> Vec2 {
	if len(shape.points) == 0 {return Vec2{}}
	return shape.points[0]
}

vector_shape_move :: proc(shape: ^Vector_Shape, delta: Vec2) {
	for i in 0 ..< len(shape.points) {
		vec2_add_to(&shape.points[i], delta)
	}
}

//* Tests shapes from front to back.
vector_state_shape_at :: proc(st: ^Vector_Drawing_State, p: Vec2, tolerance: f32) -> int {
	for i := len(st.shapes) - 1; i >= 0; i -= 1 {
		if vector_shape_at(st.shapes[i], p, tolerance) {return i}
	}
	return -1
}

vector_state_select :: proc(st: ^Vector_Drawing_State, index: int) {
	for &shape in st.shapes {
		shape.selected = false
	}
	st.selected = index
	if index >= 0 && index < len(st.shapes) {
		st.shapes[index].selected = true
	}
}

//* Tests whether a drawing-space point hits a shape.
vector_shape_at :: proc(shape: Vector_Shape, p: Vec2, tolerance: f32) -> bool {
	switch shape.kind {
	case .Line:
		if len(shape.points) < 2 {return false}
		return point_near_segment(
			p,
			shape.points[0],
			shape.points[1],
			tolerance + shape.width * 0.5,
		)
	case .Rect:
		if len(shape.points) < 2 {return false}
		return point_in_rect(p, vector_rect_of(shape.points[0], shape.points[1]), tolerance)
	case .Ellipse:
		if len(shape.points) < 2 {return false}
		return point_in_ellipse(p, shape.points[0], shape.points[1], tolerance)
	case .Polygon:
		return point_in_polygon(p, shape.points[:])
	}
	return false
}

vector_rect_of :: proc(a, b: Vec2) -> Rect {
	x0 := min(a.x, b.x)
	y0 := min(a.y, b.y)
	x1 := max(a.x, b.x)
	y1 := max(a.y, b.y)
	return Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
}

point_in_rect :: proc(p: Vec2, r: Rect, tolerance: f32) -> bool {
	return(
		p.x >= r.x - tolerance &&
		p.x <= r.x + r.w + tolerance &&
		p.y >= r.y - tolerance &&
		p.y <= r.y + r.h + tolerance \
	)
}

point_in_ellipse :: proc(p, centre, radii: Vec2, tolerance: f32) -> bool {
	rx := radii.x + tolerance
	ry := radii.y + tolerance
	if rx <= 0 || ry <= 0 {return false}
	dx := (p.x - centre.x) / rx
	dy := (p.y - centre.y) / ry
	return dx * dx + dy * dy <= 1
}

point_in_polygon :: proc(p: Vec2, points: []Vec2) -> bool {
	n := len(points)
	if n < 3 {return false}
	inside := false
	j := n - 1
	for i in 0 ..< n {
		a := points[i]
		b := points[j]
		if (a.y > p.y) != (b.y > p.y) {
			x := a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if p.x < x {inside = !inside}
		}
		j = i
	}
	return inside
}

point_near_segment :: proc(p, a, b: Vec2, tolerance: f32) -> bool {
	dx := b.x - a.x
	dy := b.y - a.y
	length2 := dx * dx + dy * dy
	t := f32(0)
	if length2 > 0 {
		t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2
		t = clamp(t, 0, 1)
	}
	cx := a.x + dx * t
	cy := a.y + dy * t
	ex := p.x - cx
	ey := p.y - cy
	return ex * ex + ey * ey <= tolerance * tolerance
}

click_vector_drawing :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := vector_drawing_data(g, id)
	if d == nil {return}
	if d.state == nil {return}
	st := d.state

	content := vector_content(g, w)
	origin := Vec2{content.x, content.y}
	p := vector_to_drawing(origin, st.scroll, st.zoom, g.pointer)
	index := vector_state_shape_at(st, p, VECTOR_PICK_TOLERANCE)
	vector_state_select(st, index)
	signal_item_selected(g, id, index)
}

update_vector_drawing :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	d := vector_drawing_data(g, id)
	if d == nil {return}
	if d.state == nil {return}
	st := d.state

	if !g.lmb_down {
		st.dragging = -1
		return
	}

	content := vector_content(g, w)
	if !rect_contains(content, g.pointer.x, g.pointer.y) {return}

	origin := Vec2{content.x, content.y}
	p := vector_to_drawing(origin, st.scroll, st.zoom, g.pointer)

	if st.dragging < 0 {
		index := vector_state_shape_at(st, p, VECTOR_PICK_TOLERANCE)
		if index < 0 {return}
		vector_state_select(st, index)
		st.dragging = index
		d.grab = vec2_sub(p, vector_shape_reference(st.shapes[index]))
		return
	}

	if st.dragging >= len(st.shapes) {
		st.dragging = -1
		return
	}
	shape := &st.shapes[st.dragging]
	vector_shape_move(shape, vec2_sub(vec2_sub(p, d.grab), vector_shape_reference(shape^)))
}

draw_vector_drawing :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := vector_drawing_data(g, id)
	if d == nil {return}
	if d.state == nil {return}
	st := d.state
	ink := resolved_text_colour(g, id, w)
	zoom := st.zoom
	if zoom <= 0 {zoom = 1}
	origin := Vec2{content.x, content.y}

	draw_push_clip(g.target, content)
	for shape in st.shapes {
		colour := shape.colour
		if colour.a == 0 {colour = ink}
		draw_vector_shape(g, shape, origin, st.scroll, zoom, content, colour)
	}
	if st.selected >= 0 && st.selected < len(st.shapes) {
		draw_vector_handles(g, st.shapes[st.selected], origin, st.scroll, zoom)
	}
	draw_pop_clip(g.target)
}

draw_vector_shape :: proc(
	g: ^GUI,
	shape: Vector_Shape,
	origin: Vec2,
	scroll: Vec2,
	zoom: f32,
	clip: Rect,
	colour: Colour,
) {
	width := shape.width
	if width <= 0 {width = VECTOR_LINE_WIDTH}

	switch shape.kind {
	case .Line:
		if len(shape.points) < 2 {return}
		draw_clipped_line(
			g,
			vector_to_screen(origin, scroll, zoom, shape.points[0]),
			vector_to_screen(origin, scroll, zoom, shape.points[1]),
			width,
			colour,
			clip,
		)
	case .Rect:
		if len(shape.points) < 2 {return}
		tl := shape.points[0]
		br := shape.points[1]
		corners := [4][2]f32 {
			vector_to_screen(origin, scroll, zoom, tl),
			vector_to_screen(origin, scroll, zoom, Vec2{br.x, tl.y}),
			vector_to_screen(origin, scroll, zoom, br),
			vector_to_screen(origin, scroll, zoom, Vec2{tl.x, br.y}),
		}
		if shape.filled {
			draw_clipped_polygon(g, corners[:], colour, clip)
		}
		draw_vector_outline(g, corners[:], width, colour, clip, true)
	case .Ellipse:
		if len(shape.points) < 2 {return}
		points := vector_ellipse_points(shape, origin, scroll, zoom)
		if shape.filled {
			draw_clipped_polygon(g, points[:], colour, clip)
		}
		draw_vector_outline(g, points[:], width, colour, clip, true)
	case .Polygon:
		points := vector_shape_screen_points(g, shape, origin, scroll, zoom)
		if len(points) < 2 {return}
		if shape.filled {
			draw_clipped_polygon(g, points[:], colour, clip)
		}
		draw_vector_outline(g, points[:], width, colour, clip, true)
	}
}

//* Generates the ellipse vertices in screen space.
vector_ellipse_points :: proc(
	shape: Vector_Shape,
	origin: Vec2,
	scroll: Vec2,
	zoom: f32,
) -> [VECTOR_ELLIPSE_SEGMENTS][2]f32 {
	centre := shape.points[0]
	radii := shape.points[1]
	points: [VECTOR_ELLIPSE_SEGMENTS][2]f32
	for i in 0 ..< VECTOR_ELLIPSE_SEGMENTS {
		angle := 2 * math.PI * f32(i) / f32(VECTOR_ELLIPSE_SEGMENTS)
		p := Vec2{centre.x + radii.x * math.cos(angle), centre.y + radii.y * math.sin(angle)}
		points[i] = vector_to_screen(origin, scroll, zoom, p)
	}
	return points
}

//* Transforms polygon vertices into screen space using the frame arena.
vector_shape_screen_points :: proc(
	g: ^GUI,
	shape: Vector_Shape,
	origin: Vec2,
	scroll: Vec2,
	zoom: f32,
) -> [dynamic][2]f32 {
	allocator := virt.arena_allocator(&g.frame_arena)
	points := make([dynamic][2]f32, 0, len(shape.points), allocator)
	for point in shape.points {
		append(&points, vector_to_screen(origin, scroll, zoom, point))
	}
	return points
}

//* Draws connected edges, optionally closing the outline.
draw_vector_outline :: proc(
	g: ^GUI,
	points: [][2]f32,
	width: f32,
	colour: Colour,
	clip: Rect,
	closed: bool,
) {
	n := len(points)
	if n < 2 {return}
	for i in 0 ..< n - 1 {
		draw_clipped_line(g, points[i], points[i + 1], width, colour, clip)
	}
	if closed {
		draw_clipped_line(g, points[n - 1], points[0], width, colour, clip)
	}
}

//* Draws handles for the selected shape's vertices.
draw_vector_handles :: proc(g: ^GUI, shape: Vector_Shape, origin: Vec2, scroll: Vec2, zoom: f32) {
	for point in shape.points {
		screen := vector_to_screen(origin, scroll, zoom, point)
		draw_quad(
			g.target,
			Rect{x = screen[0] - 3, y = screen[1] - 3, w = 6, h = 6},
			g.atlas.white_uv,
			RGBA(0.35, 0.74, 1.0, 1),
			g.atlas_texture,
		)
	}
}