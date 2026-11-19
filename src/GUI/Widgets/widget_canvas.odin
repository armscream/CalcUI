//* A widget the program draws itself. Its paint procedure runs every
//* frame and fills the canvas state with drawing commands.

package Widgets
import "core:log"
import "core:math"
import virt "core:mem/virtual"


Make_Canvas :: proc(g: ^GUI, parent: Widget_ID, opts: Canvas_Opts) -> Widget_ID {
	kind_register(g, .Canvas, canvas_kind())
	id := New_Widget(g, .Canvas, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	state, err := virt.new(&g.arena, Canvas_State)
	if err != nil {
		log.panicf("canvas state allocation failed: %v", err)
	}
	state^ = Canvas_State{}
	state.items = make([dynamic]Canvas_Item, 0, 8, virt.arena_allocator(&g.arena))
	state.last = make([dynamic]Canvas_Item, 0, 8, virt.arena_allocator(&g.arena))
	w.data = Canvas_Data{state = state, repaint_rate = opts.repaint_rate}
	return id
}

canvas_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_canvas,
		update = update_canvas,
		style = Style{
			box = StyleBox{
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
		theme_name = "Canvas",
	}
}

canvas_data :: proc(g: ^GUI, id: Widget_ID) -> ^Canvas_Data {
	w := Widget_Get(g, id)
	if w == nil {
		return nil
	}
	#partial switch &d in w.data {
	case Canvas_Data:
		return &d
	}
	return nil
}

canvas_set_paint :: proc(
	g: ^GUI,
	id: Widget_ID,
	paint: proc(g: ^GUI, id: Widget_ID, state: ^Canvas_State),
) {
	d := canvas_data(g, id)
	if d == nil {
		return
	}
	d.paint = paint
	d.next_repaint = 0
	if d.state != nil {
		clear(&d.state.last)
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

canvas_set_repaint_rate :: proc(g: ^GUI, id: Widget_ID, rate: f32) {
	d := canvas_data(g, id)
	if d == nil {
		return
	}
	d.repaint_rate = rate
	d.next_repaint = 0
}

canvas_add_item :: proc(g: ^GUI, id: Widget_ID, item: Canvas_Item) {
	d := canvas_data(g, id)
	if d == nil || d.state == nil {
		return
	}
	append(&d.state.items, item)
	invalidate(g, id, Dirty_Flags{.Visual})
}

canvas_clear :: proc(g: ^GUI, id: Widget_ID) {
	d := canvas_data(g, id)
	if d == nil || d.state == nil {
		return
	}
	clear(&d.state.items)
	invalidate(g, id, Dirty_Flags{.Visual})
}

canvas_item_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := canvas_data(g, id)
	if d == nil || d.state == nil {
		return 0
	}
	return len(d.state.items)
}

canvas_add_rect :: proc(g: ^GUI, id: Widget_ID, pos, size: Vec2, colour: Colour) {
	canvas_add_item(g, id, Canvas_Item{kind = .Rect, pos = pos, size = size, colour = colour})
}

canvas_add_circle :: proc(g: ^GUI, id: Widget_ID, pos, size: Vec2, colour: Colour) {
	canvas_add_item(g, id, Canvas_Item{kind = .Circle, pos = pos, size = size, colour = colour})
}

canvas_add_line :: proc(g: ^GUI, id: Widget_ID, from, to: Vec2, colour: Colour) {
	canvas_add_item(g, id, Canvas_Item{
		kind = .Line,
		pos = from,
		size = vec2_sub(to, from),
		colour = colour,
	})
}

canvas_add_text :: proc(g: ^GUI, id: Widget_ID, pos: Vec2, text: string, colour: Colour) {
	canvas_add_item(g, id, Canvas_Item{kind = .Text, pos = pos, text = text, colour = colour})
}

canvas_add_texture :: proc(
	g: ^GUI,
	id: Widget_ID,
	pos, size: Vec2,
	texture: Texture,
	colour: Colour = {},
) {
	canvas_add_item(
		g,
		id,
		Canvas_Item{kind = .Texture, pos = pos, size = size, texture = texture, colour = colour},
	)
}

//* A canvas without a paint procedure retains its items.
update_canvas :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	d := canvas_data(g, id)
	if d == nil || d.state == nil || d.paint == nil {
		return
	}
	if d.repaint_rate > 0 {
		if d.next_repaint <= 0 {
			d.next_repaint = g.time
		}
		if g.time < d.next_repaint {
			wake_at(g, d.next_repaint)
			return
		}
		d.next_repaint = g.time + 1 / d.repaint_rate
		wake_at(g, d.next_repaint)
	}
	clear(&d.state.items)
	d.paint(g, id, d.state)

	changed := len(d.state.items) != len(d.state.last)
	if !changed {
		for item, i in d.state.items {
			if item != d.state.last[i] {
				changed = true
				break
			}
		}
	}
	if changed {
		clear(&d.state.last)
		append(&d.state.last, ..d.state.items[:])
		invalidate(g, id, Dirty_Flags{.Visual})
	}
}

CANVAS_LINE_WIDTH     :: 2
CANVAS_CIRCLE_SEGMENTS :: 24

draw_canvas :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := canvas_data(g, id)
	if d == nil || d.state == nil {
		return
	}
	style := resolved_style(g, w)
	colour := resolved_text_colour(g, id, w)

	draw_push_clip(g.target, content)
	for item in d.state.items {
		switch item.kind {
		case .Rect:
			draw_rect(g, Rect{
				x = item.pos.x,
				y = item.pos.y,
				w = item.size.x,
				h = item.size.y,
			}, item.colour, 0)
		case .Circle:
			draw_canvas_circle(g, item, content)
		case .Line:
			draw_clipped_line(
				g,
				{item.pos.x, item.pos.y},
				{item.pos.x + item.size.x, item.pos.y + item.size.y},
				CANVAS_LINE_WIDTH,
				item.colour,
				content,
			)
		case .Text:
			ink := item.colour
			if ink.a == 0 {
				ink = colour
			}
			draw_text(
				g,
				style.text,
				item.text,
				Rect{
					x = item.pos.x,
					y = item.pos.y,
					w = item.size.x,
					h = item.size.y,
				},
				ink,
			)
		case .Texture:
			if !atlas_region_valid(g.atlas, item.texture.region) {
				continue
			}
			atlas_touch(g.atlas, item.texture.region)
			ink := item.colour
			if ink.a == 0 {
				ink = RGBA(1, 1, 1, 1)
			}
			draw_quad(
				g.target,
				Rect{
					x = item.pos.x,
					y = item.pos.y,
					w = item.size.x,
					h = item.size.y,
				},
				item.texture.uv,
				ink,
				g.atlas_texture,
			)
		}
	}
	draw_pop_clip(g.target)
}

draw_canvas_circle :: proc(g: ^GUI, item: Canvas_Item, clip: Rect) {
	cx := item.pos.x + item.size.x * 0.5
	cy := item.pos.y + item.size.y * 0.5
	r := min(item.size.x, item.size.y) * 0.5
	if r <= 0 {
		return
	}

	points: [CANVAS_CIRCLE_SEGMENTS][2]f32
	for i in 0 ..< CANVAS_CIRCLE_SEGMENTS {
		angle := 2 * math.PI * f32(i) / f32(CANVAS_CIRCLE_SEGMENTS)
		points[i] = [2]f32{cx + r * math.cos(angle), cy + r * math.sin(angle)}
	}
	draw_clipped_polygon(g, points[:], item.colour, clip)
}

//* == Clipping ==

//* Clips a polygon to a rectangle. Results live in the frame arena.
clip_polygon :: proc(g: ^GUI, points: [][2]f32, r: Rect) -> [dynamic][2]f32 {
	allocator := virt.arena_allocator(&g.frame_arena)
	front := make([dynamic][2]f32, 0, len(points) + 8, allocator)
	back := make([dynamic][2]f32, 0, len(points) + 8, allocator)
	if len(points) < 3 {
		return front
	}
	for point in points {
		append(&front, point)
	}
	for edge in clip_edges(r) {
		if len(front) == 0 {
			break
		}
		clear(&back)
		clip_polygon_edge(&back, front[:], edge)
		front, back = back, front
	}
	return front
}

//* Clips a line segment to a rectangle.
clip_segment :: proc(a, b: [2]f32, r: Rect) -> (out_a, out_b: [2]f32, ok: bool) {
	dx := b[0] - a[0]
	dy := b[1] - a[1]
	p := [4]f32{-dx, dx, -dy, dy}
	q := [4]f32{a[0] - r.x, r.x + r.w - a[0], a[1] - r.y, r.y + r.h - a[1]}

	t0, t1 := f32(0), f32(1)
	for i in 0 ..< 4 {
		if p[i] == 0 {
			if q[i] < 0 {
				return
			}
			continue
		}
		t := q[i] / p[i]
		if p[i] < 0 {
			if t > t1 {
				return
			}
			if t > t0 {
				t0 = t
			}
		} else {
			if t < t0 {
				return
			}
			if t < t1 {
				t1 = t
			}
		}
	}
	out_a = [2]f32{a[0] + dx * t0, a[1] + dy * t0}
	out_b = [2]f32{a[0] + dx * t1, a[1] + dy * t1}
	ok = true
	return
}

draw_clipped_line :: proc(g: ^GUI, a, b: [2]f32, width: f32, colour: Colour, clip: Rect) {
	ca, cb, ok := clip_segment(a, b, clip)
	if !ok {
		return
	}
	draw_thick_line(g.target, ca, cb, width, colour, g.atlas_texture)
}

draw_clipped_polygon :: proc(g: ^GUI, points: [][2]f32, colour: Colour, clip: Rect) {
	clipped := clip_polygon(g, points, clip)
	if len(clipped) >= 3 {
		draw_polygon(g.target, clipped[:], colour, g.atlas_texture)
	}
}
