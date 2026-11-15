//* The tree is walked and every widget is drawn into the list of the window it belongs to.
//* A floating panel is a window of its own and gets a list of its own.
package GUI

import "core:math"

build_draw_list :: proc(g: ^GUI) {
	g.target = &g.draw
	g.draw.scale = g.scale
	draw_list_clear(g.target, g.viewport)
	if g.root != INVALID_WIDGET_ID {
		draw_widget(g, g.root)
		draw_drag_overlay(g)
		draw_inspector(g)
	}

	for &f in g.floats {
		rect := Rect {
			x = 0,
			y = 0,
			w = f.size.x,
			h = f.size.y,
		}
		g.target = &f.draw
		f.draw.scale = g.scale
		draw_list_clear(g.target, rect)
		draw_widget(g, f.widget)
	}
	g.target = &g.draw
}

draw_widget :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	if !(.Visible in w.state) {return}
	if g.drag.active && id == g.drag.widget && g.drag.float_index < 0 {return}
	if is_hidden_tab(g, id) {return}

	kind := widget_kind(g, w)

	style := resolved_style(g, w)

	clipped := w.clip_contents
	if clipped {draw_push_clip(g.target, w.rect)}

	bg := resolved_bg(g, id, w)
	radius := stylebox_radius(&style.box)
	if bg.a > 0 {
		draw_rect(g, w.rect, bg, radius)
	}
	if stylebox_has_border(&style.box) {
		draw_border(g, w, style^)
	}

	content := content_rect_with(w.rect, style.box.content_margin)

	if w.type == .Tabs {
		draw_tab_bar(g, w)
		content = tabs_content_rect(w)
	} else if w.type == .TabContainer {
		draw_tab_container_bar(g, w)
		content = tabs_content_rect(w)
	} else if w.draggable && !is_tab_child(g, id) {
		draw_header(g, w, style^)
		content.y += HEADER_HEIGHT
		content.h -= HEADER_HEIGHT
	}

	colour := resolved_text_colour(g, id, w)

	w.dirty -= Dirty_Flags{.Visual}
	w.subtree_dirty -= Dirty_Flags{.Visual}

	if kind.draw != nil {
		kind.draw(g, id, w, content)
	} else {
		#partial switch r in w.data {
		case Label_Data:
			draw_text(g, style.text, r.text, content, colour)
		case Button_Data:
			draw_text(g, style.text, r.text, content, colour)
		}
	}

	if kind.draw == nil || !kind.owns_children {
		draw_children(g, id, w)
	}

	if id == g.resize_hover {
		draw_resize_grip(g, id, g.resize_hover_edges)
	}

	if g.focused == id && (.Enabled in w.state) {
		draw_focus_ring(g, w)
	}

	if clipped {draw_pop_clip(g.target)}
}

draw_children :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	if w == nil {return}
	base, count := children_begin_sorted(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil {continue}
		draw_widget(g, child)
	}
}

draw_focus_ring :: proc(g: ^GUI, w: ^Widget) {
	style := resolved_style(g, w)
	colour := style.text.focus_colour
	if colour.a == 0 {colour = RGBA(0.35, 0.74, 1.0, 0.9)}
	r := w.rect
	t := f32(2)
	draw_quad(
		g.target,
		Rect{x = r.x - 1, y = r.y - 1, w = r.w + 2, h = t},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x - 1, y = r.y + r.h + 1 - t, w = r.w + 2, h = t},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x - 1, y = r.y - 1, w = t, h = r.h + 2},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x + r.w + 1 - t, y = r.y - 1, w = t, h = r.h + 2},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
}

draw_resize_grip :: proc(g: ^GUI, id: Widget_ID, edges: Resize_Edges) {
	w := Widget_Get(g, id)
	if w == nil {return}
	r := w.rect
	c := RGBA(0.35, 0.74, 1.0, 1)
	t := f32(2)
	if .Left in edges {
		draw_quad(
			g.target,
			Rect{x = r.x, y = r.y, w = t, h = r.h},
			g.atlas.white_uv,
			c,
			g.atlas_texture,
		)
	}
	if .Right in edges {
		draw_quad(
			g.target,
			Rect{x = r.x + r.w - t, y = r.y, w = t, h = r.h},
			g.atlas.white_uv,
			c,
			g.atlas_texture,
		)
	}
	if .Top in edges {
		draw_quad(
			g.target,
			Rect{x = r.x, y = r.y, w = r.w, h = t},
			g.atlas.white_uv,
			c,
			g.atlas_texture,
		)
	}
	if .Bottom in edges {
		draw_quad(
			g.target,
			Rect{x = r.x, y = r.y + r.h - t, w = r.w, h = t},
			g.atlas.white_uv,
			c,
			g.atlas_texture,
		)
	}
}

draw_header :: proc(g: ^GUI, w: ^Widget, style: Style) {
	h := header_rect(w)
	bg := Scale_Colour(style.box.bg_color, 1.6)
	draw_quad(g.target, h, g.atlas.white_uv, bg, g.atlas_texture)
	if style.box.border_color[3].a > 0 {
		draw_quad(
			g.target,
			Rect{x = h.x, y = h.y + h.h - 1, w = h.w, h = 1},
			g.atlas.white_uv,
			style.box.border_color[3],
			g.atlas_texture,
		)
	}
	title := Rect {
		x = h.x + 8,
		y = h.y,
		w = h.w - 16,
		h = h.h,
	}
	draw_text(g, style.text, w.name, title, resolved_text_colour(g, w.id, w))
}

draw_tab_bar :: proc(g: ^GUI, w: ^Widget) {
	bar := tab_bar_rect(w)
	draw_quad(g.target, bar, g.atlas.white_uv, RGBA(0.08, 0.09, 0.11, 1), g.atlas_texture)

	rects: [MAX_TABS]Rect
	n := tab_button_rects(g, w, &rects)
	active := tabs_active(w)

	child := w.first_child
	for i in 0 ..< n {
		c := Widget_Get(g, child)
		if c == nil {break}
		r := rect_intersect(rects[i], bar)
		if r.w > 0 {
			bg := RGBA(0.13, 0.14, 0.17, 1)
			fg := RGBA(0.58, 0.61, 0.68, 1)
			if i == active {
				bg = RGBA(0.19, 0.20, 0.24, 1)
				fg = RGBA(0.93, 0.95, 0.98, 1)
			}
			draw_quad(g.target, r, g.atlas.white_uv, bg, g.atlas_texture)
			label := Rect {
				x = r.x + TAB_PADDING,
				y = r.y,
				w = r.w - TAB_PADDING * 2,
				h = r.h,
			}
			Font_Draw(g, Font_Of(g, c), c.name, label, fg, .Left)
		}
		child = c.next_sibling
	}

	draw_quad(
		g.target,
		Rect{x = bar.x, y = bar.y + bar.h - 1, w = bar.w, h = 1},
		g.atlas.white_uv,
		RGBA(0.20, 0.22, 0.27, 1),
		g.atlas_texture,
	)
}

content_rect :: proc(g: ^GUI, w: ^Widget) -> Rect {
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

content_rect_with :: proc(rect: Rect, pad: [4]f32) -> Rect {
	return Rect {
		x = rect.x + pad[0],
		y = rect.y + pad[1],
		w = rect.w - pad[0] - pad[2],
		h = rect.h - pad[1] - pad[3],
	}
}

draw_drag_overlay :: proc(g: ^GUI) {
	if !g.drag.active {return}
	plan := &g.drag.plan

	if t := Widget_Get(g, g.drag.target); t != nil {
		draw_dock_zone(g, dock_zone_container(g, g.drag.target), g.drag.zone)
	}

	for i in 0 ..< plan.other_count {
		draw_quad(
			g.target,
			plan.others[i],
			g.atlas.white_uv,
			RGBA(0.60, 0.63, 0.70, 0.12),
			g.atlas_texture,
		)
		draw_outline(g, plan.others[i], RGBA(0.64, 0.67, 0.74, 0.45), 1)
	}

	switch plan.kind {
	case .Split, .Fill:
		draw_panel_preview(g, plan.preview, g.drag.widget)
	case .Tabs:
		draw_quad(
			g.target,
			plan.tab_bar,
			g.atlas.white_uv,
			RGBA(0.10, 0.11, 0.13, 0.9),
			g.atlas_texture,
		)
		for i in 0 ..< plan.tab_button_count {
			r := rect_intersect(plan.tab_buttons[i], plan.tab_bar)
			if r.w <= 0 {continue}
			bg := RGBA(0.13, 0.14, 0.17, 0.95)
			fg := RGBA(0.58, 0.61, 0.68, 1)
			if i == plan.tab_index {
				bg = RGBA(0.16, 0.44, 0.82, 1)
				fg = RGBA(1, 1, 1, 1)
			}
			draw_quad(g.target, r, g.atlas.white_uv, bg, g.atlas_texture)
			if i < plan.tab_widget_count {
				w := Widget_Get(g, plan.tab_widgets[i])
				if w != nil {
					label := Rect {
						x = r.x + TAB_PADDING,
						y = r.y,
						w = r.w - TAB_PADDING * 2,
						h = r.h,
					}
					Font_Draw(g, Font_Of(g, w), w.name, label, fg, .Left)
				}
			}
		}
		draw_outline(g, plan.tab_button, RGBA(0.40, 0.76, 1.0, 1), 2)
		draw_panel_preview(g, plan.preview, g.drag.widget)
	case .Swap:
		draw_panel_preview(g, plan.preview, g.drag.widget)
	case .None:
	}

	if g.drag.slot.w > 0 && g.drag.slot.h > 0 {
		draw_outline(g, g.drag.slot, RGBA(0.60, 0.63, 0.70, 0.45), 1)
	}

	if g.drag.float_index < 0 {
		draw_ghost(g)
	}
}

draw_dock_zone :: proc(g: ^GUI, rect: Rect, zone: Dock_Zone) {
	rects: [5]Rect
	n := dock_zone_rects(rect, &rects)
	active := dock_zone_index(zone)
	for i in 0 ..< n {
		if i == active {continue}
		draw_quad(
			g.target,
			rects[i],
			g.atlas.white_uv,
			RGBA(0.60, 0.63, 0.70, 0.09),
			g.atlas_texture,
		)
		draw_outline(g, rects[i], RGBA(0.64, 0.67, 0.74, 0.26), 1)
	}
}

draw_panel_preview :: proc(g: ^GUI, rect: Rect, id: Widget_ID) {
	if rect.w <= 0 || rect.h <= 0 {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	bg := resolved_style(g, w).box.bg_color
	if bg.a == 0 {bg = RGBA(0.16, 0.17, 0.21, 1)}
	draw_quad(g.target, rect, g.atlas.white_uv, bg, g.atlas_texture)
	draw_quad(g.target, rect, g.atlas.white_uv, RGBA(0.24, 0.62, 1.0, 0.28), g.atlas_texture)
	draw_outline(g, rect, RGBA(0.35, 0.74, 1.0, 1), 3)
	title := Rect {
		x = rect.x + 8,
		y = rect.y,
		w = rect.w - 16,
		h = HEADER_HEIGHT,
	}
	Font_Draw(g, Font_Of(g, w), w.name, title, RGBA(1, 1, 1, 1), .Left)
}

draw_ghost :: proc(g: ^GUI) {
	w := Widget_Get(g, g.drag.widget)
	if w == nil {return}
	ghost := g.drag.ghost
	if ghost.w <= 0 || ghost.h <= 0 {return}
	bg := resolved_style(g, w).box.bg_color
	if bg.a == 0 {bg = RGBA(0.18, 0.19, 0.23, 1)}
	draw_quad(g.target, ghost, g.atlas.white_uv, RGBA(bg.r, bg.g, bg.b, 0.9), g.atlas_texture)
	draw_outline(g, ghost, RGBA(0.70, 0.73, 0.80, 0.9), 1)
	title := Rect {
		x = ghost.x + 8,
		y = ghost.y,
		w = ghost.w - 16,
		h = HEADER_HEIGHT,
	}
	Font_Draw(g, Font_Of(g, w), w.name, title, RGBA(1, 1, 1, 1), .Left)
}

draw_outline :: proc(g: ^GUI, r: Rect, c: Colour, t: f32) {
	if t <= 0 || r.w <= 0 || r.h <= 0 {return}
	draw_quad(
		g.target,
		Rect{x = r.x, y = r.y, w = r.w, h = t},
		g.atlas.white_uv,
		c,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x, y = r.y + r.h - t, w = r.w, h = t},
		g.atlas.white_uv,
		c,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x, y = r.y + t, w = t, h = r.h - t * 2},
		g.atlas.white_uv,
		c,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x + r.w - t, y = r.y + t, w = t, h = r.h - t * 2},
		g.atlas.white_uv,
		c,
		g.atlas_texture,
	)
}

draw_border :: proc(g: ^GUI, w: ^Widget, style: Style) {
	r := w.rect
	widths := style.box.border_width
	colours := style.box.border_color

	//* A border of one width and one colour follows the rounded corners
	//* of the box. The ring is built on the CPU, so it does not depend on
	//* the shape attribute: the SDL3 renderer has no such attribute, and
	//* the GPU shader has no per-side border colours either. A border
	//* whose sides differ keeps the four rectangles below, which is the
	//* deliberate fallback of both backends.
	box := style.box
	radius := stylebox_radius(&box)
	if radius > 0 && border_is_uniform(widths, colours) {
		draw_round_border(g, r, widths[0], colours[0], radius)
		return
	}

	if widths[0] > 0 && colours[0].a > 0 {
		draw_quad(
			g.target,
			Rect{x = r.x, y = r.y, w = widths[0], h = r.h},
			g.atlas.white_uv,
			colours[0],
			g.atlas_texture,
		)
	}
	if widths[1] > 0 && colours[1].a > 0 {
		draw_quad(
			g.target,
			Rect{x = r.x, y = r.y, w = r.w, h = widths[1]},
			g.atlas.white_uv,
			colours[1],
			g.atlas_texture,
		)
	}
	if widths[2] > 0 && colours[2].a > 0 {
		draw_quad(
			g.target,
			Rect{x = r.x + r.w - widths[2], y = r.y, w = widths[2], h = r.h},
			g.atlas.white_uv,
			colours[2],
			g.atlas_texture,
		)
	}
	if widths[3] > 0 && colours[3].a > 0 {
		draw_quad(
			g.target,
			Rect{x = r.x, y = r.y + r.h - widths[3], w = r.w, h = widths[3]},
			g.atlas.white_uv,
			colours[3],
			g.atlas_texture,
		)
	}
}

//* True when every side of the border has the same width and the same
//* visible colour, so the four sides can be joined into one ring.
border_is_uniform :: proc(widths: [4]f32, colours: [4]Colour) -> bool {
	if !(widths[0] > 0) || !(colours[0].a > 0) {return false}
	for i in 1 ..< 4 {
		if widths[i] != widths[0] {return false}
		if colours[i] != colours[0] {return false}
	}
	return true
}

BORDER_CORNER_SEGMENTS :: 4

//* Draws a border that follows the rounded corners of the box: four
//* straight strips and four arcs, each arc cut into convex pieces. The
//* geometry is clipped and scaled by `draw_polygon`, like any other
//* polygon of the draw list, so clipping stays correct.
draw_round_border :: proc(g: ^GUI, r: Rect, width: f32, colour: Colour, radius: f32) {
	if r.w <= 0 || r.h <= 0 {return}

	//* A border that is as thick as the box is a filled box, and so is a
	//* corner radius that the box is too small to hold.
	t := min(width, min(r.w, r.h) * 0.5)
	rad := min(radius, min(r.w, r.h) * 0.5)
	if !(t > 0) {return}
	if rad <= 0 || r.w - t * 2 <= 0 || r.h - t * 2 <= 0 {
		draw_round_polygon(g, r, colour, rad)
		return
	}

	//* The straight strips between the corners. A strip of zero length
	//* is left out by `draw_quad`.
	draw_quad(
		g.target,
		Rect{x = r.x + rad, y = r.y, w = r.w - rad * 2, h = t},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x + rad, y = r.y + r.h - t, w = r.w - rad * 2, h = t},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x, y = r.y + rad, w = t, h = r.h - rad * 2},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{x = r.x + r.w - t, y = r.y + rad, w = t, h = r.h - rad * 2},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)

	//* The corners: an outer arc joined to the inner arc of the same
	//* centre and the radius the border leaves. Each piece is a convex
	//* trapezoid, so a fan of triangles draws it exactly.
	inner := max(rad - t, 0)
	centres := [4][2]f32 {
		{r.x + rad, r.y + rad},
		{r.x + r.w - rad, r.y + rad},
		{r.x + r.w - rad, r.y + r.h - rad},
		{r.x + rad, r.y + r.h - rad},
	}
	starts := [4]f32{180, 270, 0, 90}
	for c in 0 ..< 4 {
		for s in 0 ..< BORDER_CORNER_SEGMENTS {
			a0 := (starts[c] + 90 * f32(s) / f32(BORDER_CORNER_SEGMENTS)) * math.PI / 180
			a1 := (starts[c] + 90 * f32(s + 1) / f32(BORDER_CORNER_SEGMENTS)) * math.PI / 180
			piece := [4][2]f32 {
				{
					centres[c][0] + rad * math.cos(a0),
					centres[c][1] + rad * math.sin(a0),
				},
				{
					centres[c][0] + rad * math.cos(a1),
					centres[c][1] + rad * math.sin(a1),
				},
				{
					centres[c][0] + inner * math.cos(a1),
					centres[c][1] + inner * math.sin(a1),
				},
				{
					centres[c][0] + inner * math.cos(a0),
					centres[c][1] + inner * math.sin(a0),
				},
			}
			draw_polygon(g.target, piece[:], colour, g.atlas_texture)
		}
	}
}

draw_rect :: proc(g: ^GUI, r: Rect, colour: Colour, radius: f32) {
	if colour.a <= 0 {return}
	if r.w <= 0 || r.h <= 0 {return}
	if radius <= 0 {
		draw_quad(g.target, r, g.atlas.white_uv, colour, g.atlas_texture)
		return
	}
	if g.backend.supports_shapes {
		draw_quad_shape(g.target, r, g.atlas.white_uv, colour, g.atlas_texture, .Solid, radius)
		return
	}
	draw_round_polygon(g, r, colour, radius)
}

CORNER_SEGMENTS :: 5

draw_round_polygon :: proc(g: ^GUI, r: Rect, colour: Colour, radius: f32) {
	rad := min(radius, min(r.w, r.h) * 0.5)
	if rad <= 0 {
		draw_quad(g.target, r, g.atlas.white_uv, colour, g.atlas_texture)
		return
	}

	centres := [4][2]f32 {
		{r.x + rad, r.y + rad},
		{r.x + r.w - rad, r.y + rad},
		{r.x + r.w - rad, r.y + r.h - rad},
		{r.x + rad, r.y + r.h - rad},
	}
	starts := [4]f32{180, 270, 0, 90}

	points: [CORNER_SEGMENTS * 4 + 4][2]f32
	n := 0
	for c in 0 ..< 4 {
		for t in 0 ..= CORNER_SEGMENTS {
			a := (starts[c] + 90 * f32(t) / f32(CORNER_SEGMENTS)) * math.PI / 180
			points[n] = [2]f32 {
				centres[c][0] + rad * math.cos(a),
				centres[c][1] + rad * math.sin(a),
			}
			n += 1
		}
	}

	draw_polygon(g.target, points[:n], colour, g.atlas_texture)
}

