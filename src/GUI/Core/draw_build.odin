//* The tree is walked and every widget is drawn into the list of the window it belongs to.
//* A floating panel is a window of its own and gets a list of its own.
package Core
import "core:math"

build_draw_list :: proc(g: ^GUI) {
	if g == nil {return}
	epoch := g.draw_epoch
	g.draw_builds += 1
	atlas_build_begin(g.atlas)
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
	g.draw_valid = g.draw_epoch == epoch
}

draw_widget :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	if !(.Visible in w.state) {return}
	if g.drag.active && id == g.drag.widget && g.drag.float_index < 0 {return}
	if is_hidden_tab(g, id) {return}

	kind := widget_kind(g, w)

	style := resolved_style(g, w)

	previous_opacity := g.target.opacity
	g.target.opacity = previous_opacity * clamp(w.opacity, 0, 1)
	defer g.target.opacity = previous_opacity

	if shadow_visible(&style.box) {
		draw_shadow(g, w.rect, &style.box)
	}

	clipped := w.clip_contents
	if clipped {draw_push_clip(g.target, w.rect)}

	bg := resolved_bg(g, id, w)
	if bg.a > 0 {
		draw_rect_radii(g, w.rect, bg, stylebox_radii(&style.box))
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

	if g.focused == id && (.Enabled in w.state) && kind.focus_ring {
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
	box := style.box
	if !stylebox_has_border(&box) {return}

	radii := stylebox_radii(&box)
	if border_colour_is_uniform(colours) {
		radius := max_corner_radius(radii)
		if radius > 0 && g.backend.supports_shapes {
			draw_quad_shape_full(
				g.target,
				r,
				g.atlas.white_uv,
				colours[0],
				g.atlas_texture,
				.Border,
				radius,
				{r.w * 0.5, r.h * 0.5},
				0,
				clamp_corner_radii(radii, r.w, r.h),
				widths,
			)
			return
		}
		if radius > 0 {
			draw_round_border_radii(g, r, widths, colours[0], radii)
			return
		}
	}
	draw_border_rects(g, r, widths, colours)
}

draw_border_rects :: proc(g: ^GUI, r: Rect, widths: [4]f32, colours: [4]Colour) {
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

border_colour_is_uniform :: proc(colours: [4]Colour) -> bool {
	if !(colours[0].a > 0) {return false}
	for i in 1 ..< 4 {
		if colours[i] != colours[0] {return false}
	}
	return true
}

BORDER_CORNER_SEGMENTS :: 4

draw_round_border :: proc(g: ^GUI, r: Rect, width: f32, colour: Colour, radius: f32) {
	draw_round_border_radii(
		g,
		r,
		{width, width, width, width},
		colour,
		{radius, radius, radius, radius},
	)
}

draw_round_border_radii :: proc(
	g: ^GUI,
	r: Rect,
	widths: [4]f32,
	colour: Colour,
	radii: [4]f32,
) {
	if r.w <= 0 || r.h <= 0 {return}
	if widths[0] <= 0 && widths[1] <= 0 && widths[2] <= 0 && widths[3] <= 0 {return}

	w := [4]f32 {
		max(widths[0], 0),
		max(widths[1], 0),
		max(widths[2], 0),
		max(widths[3], 0),
	}
	outer_radii := clamp_corner_radii(radii, r.w, r.h)
	if radii_are_zero(outer_radii) {
		draw_border_rects(g, r, widths, {colour, colour, colour, colour})
		return
	}

	inner := Rect {
		x = r.x + w[0],
		y = r.y + w[1],
		w = r.w - w[0] - w[2],
		h = r.h - w[1] - w[3],
	}
	if inner.w <= 0 || inner.h <= 0 {
		draw_round_polygon_radii(g, r, colour, outer_radii)
		return
	}

	inner_radii := [4]f32 {
		max(outer_radii[0] - max(w[0], w[1]), 0),
		max(outer_radii[1] - max(w[1], w[2]), 0),
		max(outer_radii[2] - max(w[2], w[3]), 0),
		max(outer_radii[3] - max(w[3], w[0]), 0),
	}
	inner_radii = clamp_corner_radii(inner_radii, inner.w, inner.h)

	outer_points: [4 * (BORDER_CORNER_SEGMENTS + 1)][2]f32
	inner_points: [4 * (BORDER_CORNER_SEGMENTS + 1)][2]f32
	round_rect_loop(r, outer_radii, BORDER_CORNER_SEGMENTS, outer_points[:])
	round_rect_loop(inner, inner_radii, BORDER_CORNER_SEGMENTS, inner_points[:])

	n := len(outer_points)
	for i in 0 ..< n {
		j := (i + 1) % n
		piece := [4][2]f32{outer_points[i], outer_points[j], inner_points[j], inner_points[i]}
		if polygon_area2(piece) <= 0.0001 {continue}
		draw_polygon(g.target, piece[:], colour, g.atlas_texture)
	}
}

round_rect_loop :: proc(r: Rect, radii: [4]f32, segments: int, points: [][2]f32) {
	centres := [4][2]f32 {
		{r.x + radii[0], r.y + radii[0]},
		{r.x + r.w - radii[1], r.y + radii[1]},
		{r.x + r.w - radii[2], r.y + r.h - radii[2]},
		{r.x + radii[3], r.y + r.h - radii[3]},
	}
	starts := [4]f32{180, 270, 0, 90}
	n := 0
	for c in 0 ..< 4 {
		for t in 0 ..= segments {
			a := (starts[c] + 90 * f32(t) / f32(segments)) * math.PI / 180
			points[n] = [2]f32 {
				centres[c][0] + radii[c] * math.cos(a),
				centres[c][1] + radii[c] * math.sin(a),
			}
			n += 1
		}
	}
}

polygon_area2 :: proc(points: [4][2]f32) -> f32 {
	area := f32(0)
	for i in 0 ..< 4 {
		j := (i + 1) % 4
		area += points[i][0] * points[j][1] - points[j][0] * points[i][1]
	}
	return abs(area)
}

SHADOW_LAYERS :: 6

shadow_visible :: proc(box: ^StyleBox) -> bool {
	if box == nil {return false}
	if box.shadow_color.a <= 0 {return false}
	return box.shadow_size > 0 || box.shadow_offset != (Vec2{})
}

draw_shadow :: proc(g: ^GUI, r: Rect, box: ^StyleBox) {
	if !shadow_visible(box) {return}
	base := Rect {
		x = r.x + box.shadow_offset.x,
		y = r.y + box.shadow_offset.y,
		w = r.w,
		h = r.h,
	}
	if base.w <= 0 || base.h <= 0 {return}
	radii := stylebox_radii(box)
	radius := max_corner_radius(radii)
	blur := max(box.shadow_size, 0)
	if g.backend.supports_shapes {
		draw_shadow_sdf(g, base, radius, radii, blur, box.shadow_color)
	} else {
		draw_shadow_layers(g, base, radii, blur, box.shadow_color)
	}
}

draw_shadow_sdf :: proc(
	g: ^GUI,
	base: Rect,
	radius: f32,
	radii: [4]f32,
	blur: f32,
	colour: Colour,
) {
	outer := Rect {
		x = base.x - blur,
		y = base.y - blur,
		w = base.w + blur * 2,
		h = base.h + blur * 2,
	}
	draw_quad_shape_full(
		g.target,
		outer,
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
		.Shadow,
		radius,
		{base.w * 0.5, base.h * 0.5},
		blur,
		clamp_corner_radii(radii, base.w, base.h),
		{},
	)
}

draw_shadow_layers :: proc(g: ^GUI, base: Rect, radii: [4]f32, blur: f32, colour: Colour) {
	if blur <= 0 {
		if !radii_are_zero(radii) {
			draw_round_polygon_radii(g, base, colour, radii)
		} else {
			draw_quad(g.target, base, g.atlas.white_uv, colour, g.atlas_texture)
		}
		return
	}

	for i in 0 ..< SHADOW_LAYERS {
		k := f32(i + 1)
		prev := colour.a * (k - 1) / f32(SHADOW_LAYERS)
		cur := colour.a * k / f32(SHADOW_LAYERS)
		alpha := (cur - prev) / max(1 - prev, 0.0001)
		grow := blur * (1 - f32(i) / f32(SHADOW_LAYERS - 1))
		r := Rect {
			x = base.x - grow,
			y = base.y - grow,
			w = base.w + grow * 2,
			h = base.h + grow * 2,
		}
		if r.w <= 0 || r.h <= 0 {continue}
		c := colour
		c.a = alpha
		grown := [4]f32{}
		for corner in 0 ..< 4 {
			if radii[corner] > 0 {
				grown[corner] = radii[corner] + grow
			}
		}
		if !radii_are_zero(grown) {
			draw_round_polygon_radii(g, r, c, grown)
		} else {
			draw_quad(g.target, r, g.atlas.white_uv, c, g.atlas_texture)
		}
	}
}

draw_rect :: proc(g: ^GUI, r: Rect, colour: Colour, radius: f32) {
	draw_rect_radii(g, r, colour, {radius, radius, radius, radius})
}

draw_rect_radii :: proc(g: ^GUI, r: Rect, colour: Colour, radii: [4]f32) {
	if colour.a <= 0 {return}
	if r.w <= 0 || r.h <= 0 {return}
	clamped := clamp_corner_radii(radii, r.w, r.h)
	if radii_are_zero(clamped) {
		draw_quad(g.target, r, g.atlas.white_uv, colour, g.atlas_texture)
		return
	}
	if g.backend.supports_shapes {
		draw_quad_shape_full(
			g.target,
			r,
			g.atlas.white_uv,
			colour,
			g.atlas_texture,
			.Solid,
			max_corner_radius(clamped),
			{r.w * 0.5, r.h * 0.5},
			0,
			clamped,
			{},
		)
		return
	}
	draw_round_polygon_radii(g, r, colour, clamped)
}

CORNER_SEGMENTS :: 5

draw_round_polygon :: proc(g: ^GUI, r: Rect, colour: Colour, radius: f32) {
	draw_round_polygon_radii(g, r, colour, {radius, radius, radius, radius})
}

draw_round_polygon_radii :: proc(g: ^GUI, r: Rect, colour: Colour, radii: [4]f32) {
	if r.w <= 0 || r.h <= 0 {return}
	clamped := clamp_corner_radii(radii, r.w, r.h)
	if radii_are_zero(clamped) {
		draw_quad(g.target, r, g.atlas.white_uv, colour, g.atlas_texture)
		return
	}

	points: [4 * (CORNER_SEGMENTS + 1)][2]f32
	round_rect_loop(r, clamped, CORNER_SEGMENTS, points[:])
	draw_polygon(g.target, points[:], colour, g.atlas_texture)
}


draw_tab_container_bar :: proc(g: ^GUI, w: ^Widget) {
	bar := Rect{x = w.rect.x, y = w.rect.y, w = w.rect.w, h = TAB_BAR_HEIGHT}
	draw_quad(g.target, bar, g.atlas.white_uv, RGBA(0.08, 0.09, 0.11, 1), g.atlas_texture)

	rects: [MAX_TABS]Rect
	n := tab_button_rects(g, w, &rects)
	active := tab_container_active(w)

	child := w.first_child
	for i in 0 ..< n {
		c := Widget_Get(g, child)
		if c == nil { break }

		r := rect_intersect(rects[i], bar)
		if r.w > 0 {
			bg := RGBA(0.13, 0.14, 0.17, 1)
			fg := RGBA(0.58, 0.61, 0.68, 1)
			if i == active {
				bg = RGBA(0.19, 0.20, 0.24, 1)
				fg = RGBA(0.93, 0.95, 0.98, 1)
			}
			draw_quad(g.target, r, g.atlas.white_uv, bg, g.atlas_texture)
			label := Rect{x = r.x + TAB_PADDING, y = r.y, w = r.w - TAB_PADDING * 2, h = r.h}
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


tab_container_active :: proc(w: ^Widget) -> int {
	#partial switch d in w.data {
	case Tab_Container_Data:
		return d.active
	}
	return 0
}

