//* The tree is walked and every widget is drawn into the list of the window it belongs to.
//* A floating panel is a window of its own and gets a list of its own.
package Core
import "core:fmt"
import "core:math"

build_draw_list :: proc(g: ^GUI) {
	if g == nil {return}
	epoch := g.draw_epoch
	g.draw_builds += 1
	atlas_build_begin(g.atlas)

	partial := g.dirty_rect_valid && !g.partial_blocked
	dirty_rect := g.dirty_rect
	partial_clear(g)
	g.partial_blocked = false
	if partial {
		root := Widget_Get(g, g.root)
		if root == nil {
			partial = false
		} else if style := resolved_style(g, root); style == nil || style.box.bg_color.a < 0.999 {
			partial = false
		}
	}

	g.target = &g.draw
	g.draw.scale = g.scale
	draw_list_clear(g.target, g.viewport)
	g.draw.white_uv = [2]f32{g.atlas.white_uv[0], g.atlas.white_uv[1]}
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
		f.draw.white_uv = [2]f32{g.atlas.white_uv[0], g.atlas.white_uv[1]}
		draw_widget(g, f.widget)
	}
	g.target = &g.draw
	g.draw_valid = g.draw_epoch == epoch
	if partial && g.draw_valid {
		g.draw.dirty_rect = dirty_rect
		g.draw.partial = true
	}
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

	box := style.box
	box.bg_color = resolved_bg(g, id, w)
	if w.type != .Tooltip {
		draw_stylebox_box(g, w.rect, &box)
	}

	clipped := w.clip_contents
	if clipped {
		radii := clamp_corner_radii(stylebox_radii(&style.box), w.rect.w, w.rect.h)
		if radii_are_zero(radii) {
			draw_push_clip(g.target, w.rect)
		} else {
			draw_push_clip_radii(g.target, w.rect, radii)
		}
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
	radii := stylebox_radii(&style.box)
	for i in 0 ..< 4 {
		if radii[i] > 0 {radii[i] += 1}
	}
	box := StyleBox {
		border_width = {2, 2, 2, 2},
		border_color = {colour, colour, colour, colour},
		corner_radius = radii,
	}
	draw_stylebox_border(g, Rect{x = r.x - 1, y = r.y - 1, w = r.w + 2, h = r.h + 2}, &box)
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
	radii := style.box.corner_radius
	draw_push_clip(g.target, h)
	draw_rect_radii(g, w.rect, bg, {radii[0], radii[1], 0, 0})
	draw_pop_clip(g.target)
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
	style := resolved_style(g, w)
	radii := style.box.corner_radius
	draw_push_clip(g.target, bar)
	draw_rect_radii(g, w.rect, RGBA(0.08, 0.09, 0.11, 1), {radii[0], radii[1], 0, 0})
	draw_pop_clip(g.target)

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

draw_stylebox_box :: proc(g: ^GUI, r: Rect, box: ^StyleBox) {
	if box == nil {return}
	if shadow_visible(box) && !box.shadow_inset {draw_shadow(g, r, box)}

	radii := stylebox_radii(box)
	if box.backdrop_blur > 0 && g.backend.supports_shapes && g.backend.supports_backdrop_blur {
		draw_glass(g, r, box.bg_color, radii, box.backdrop_blur, box.optics)
	} else {
		draw_rect_radii(g, r, box.bg_color, radii)
	}

	if stylebox_has_border(box) {draw_stylebox_border(g, r, box)}
	if shadow_visible(box) && box.shadow_inset {draw_shadow(g, r, box)}
}

draw_border :: proc(g: ^GUI, w: ^Widget, style: Style) {
	box := style.box
	draw_stylebox_border(g, w.rect, &box)
}

draw_stylebox_border :: proc(g: ^GUI, r: Rect, box: ^StyleBox) {
	if box == nil || !stylebox_has_border(box) {return}

	widths := box.border_width
	colours := box.border_color
	radii := stylebox_radii(box)

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

	clamped := clamp_corner_radii(radii, r.w, r.h)
	if radii_are_zero(clamped) {
		draw_border_rects(g, r, widths, colours)
		return
	}
	draw_side_border_radii(g, r, widths, colours, clamped)
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

BORDER_ARC_SEGMENTS :: 3

Border_Arc :: struct {
	corner: int,
	a0, a1: f32,
}

Border_Side_Arcs :: struct {
	first, second: Border_Arc,
}

BORDER_SIDE_ARCS := [4]Border_Side_Arcs {
	{{3, 135, 180}, {0, 180, 225}},
	{{0, 225, 270}, {1, 270, 315}},
	{{1, 315, 360}, {2, 0, 45}},
	{{2, 45, 90}, {3, 90, 135}},
}

draw_side_border_radii :: proc(
	g: ^GUI,
	r: Rect,
	widths: [4]f32,
	colours: [4]Colour,
	radii: [4]f32,
) {
	w := [4]f32{max(widths[0], 0), max(widths[1], 0), max(widths[2], 0), max(widths[3], 0)}
	inner := Rect {
		x = r.x + w[0],
		y = r.y + w[1],
		w = r.w - w[0] - w[2],
		h = r.h - w[1] - w[3],
	}
	if inner.w <= 0 || inner.h <= 0 {
		draw_round_polygon_radii(g, r, colours[0], radii)
		return
	}

	inner_radii := [4]f32 {
		max(radii[0] - max(w[0], w[1]), 0),
		max(radii[1] - max(w[1], w[2]), 0),
		max(radii[2] - max(w[2], w[3]), 0),
		max(radii[3] - max(w[3], w[0]), 0),
	}
	inner_radii = clamp_corner_radii(inner_radii, inner.w, inner.h)

	for side in 0 ..< 4 {
		if w[side] <= 0 || colours[side].a <= 0 {continue}

		side_radius := max(
			max(radii[BORDER_SIDE_ARCS[side].first.corner], radii[BORDER_SIDE_ARCS[side].second.corner]),
			max(inner_radii[BORDER_SIDE_ARCS[side].first.corner], inner_radii[BORDER_SIDE_ARCS[side].second.corner]),
		)
		segments := BORDER_ARC_SEGMENTS
		if side_radius > 192 {
			segments = 1
		} else if side_radius > 64 {
			segments = 2
		}

		outer_points: [2 * (BORDER_ARC_SEGMENTS + 1)][2]f32
		inner_points: [2 * (BORDER_ARC_SEGMENTS + 1)][2]f32
		count := 0
		count += append_border_arc(outer_points[:], count, r, radii, BORDER_SIDE_ARCS[side].first, segments)
		count += append_border_arc(outer_points[:], count, r, radii, BORDER_SIDE_ARCS[side].second, segments)
		inner_count := 0
		inner_count += append_border_arc(inner_points[:], inner_count, inner, inner_radii, BORDER_SIDE_ARCS[side].first, segments)
		inner_count += append_border_arc(inner_points[:], inner_count, inner, inner_radii, BORDER_SIDE_ARCS[side].second, segments)
		if count < 2 || inner_count != count {continue}

		for i in 0 ..< count - 1 {
			piece := [4][2]f32{outer_points[i], outer_points[i + 1], inner_points[i + 1], inner_points[i]}
			if polygon_area2(piece) <= 0.0001 {continue}
			draw_polygon(g.target, piece[:], colours[side], g.atlas_texture)
		}
	}
}

append_border_arc :: proc(
	points: [][2]f32,
	at: int,
	r: Rect,
	radii: [4]f32,
	arc: Border_Arc,
	segments: int,
) -> int {
	radius := radii[arc.corner]
	centre := border_corner_centre(r, arc.corner, radius)
	if radius <= 0 {
		points[at] = border_corner_point(r, arc.corner)
		return 1
	}
	written := 0
	for i in 0 ..= segments {
		a := (arc.a0 + (arc.a1 - arc.a0) * f32(i) / f32(segments)) * math.PI / 180
		points[at + i] = [2]f32 {
			centre[0] + radius * math.cos(a),
			centre[1] + radius * math.sin(a),
		}
		written += 1
	}
	return written
}

border_corner_centre :: proc(r: Rect, corner: int, radius: f32) -> [2]f32 {
	switch corner {
	case 0:
		return {r.x + radius, r.y + radius}
	case 1:
		return {r.x + r.w - radius, r.y + radius}
	case 2:
		return {r.x + r.w - radius, r.y + r.h - radius}
	case 3:
		return {r.x + radius, r.y + r.h - radius}
	}
	return {r.x, r.y}
}

border_corner_point :: proc(r: Rect, corner: int) -> [2]f32 {
	switch corner {
	case 0:
		return {r.x, r.y}
	case 1:
		return {r.x + r.w, r.y}
	case 2:
		return {r.x + r.w, r.y + r.h}
	case 3:
		return {r.x, r.y + r.h}
	}
	return {r.x, r.y}
}

border_colour_is_uniform :: proc(colours: [4]Colour) -> bool {
	if !(colours[0].a > 0) {return false}
	for i in 1 ..< 4 {
		if colours[i] != colours[0] {return false}
	}
	return true
}

BORDER_CORNER_SEGMENTS :: 3

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

SHADOW_LAYERS :: 4
INSET_SHADOW_LAYERS :: 3

shadow_visible :: proc(box: ^StyleBox) -> bool {
	if box == nil {return false}
	if box.shadow_color.a <= 0 {return false}
	return box.shadow_size > 0 ||
	       box.shadow_offset != (Vec2{}) ||
	       box.shadow_spread != 0 ||
	       box.shadow_inset
}

draw_shadow :: proc(g: ^GUI, r: Rect, box: ^StyleBox) {
	if !shadow_visible(box) {return}
	if box.shadow_inset {
		draw_inset_shadow(g, r, box)
		return
	}
	base := Rect {
		x = r.x + box.shadow_offset.x,
		y = r.y + box.shadow_offset.y,
		w = r.w,
		h = r.h,
	}
	if base.w <= 0 || base.h <= 0 {return}
	radii := stylebox_radii(box)
	blur := max(box.shadow_size, 0)
	spread := box.shadow_spread
	if g.backend.supports_shapes {
		draw_shadow_sdf(g, base, radii, blur, spread, box.shadow_color)
	} else {
		draw_shadow_layers(g, base, radii, blur, spread, box.shadow_color)
	}
}

draw_shadow_sdf :: proc(
	g: ^GUI,
	base: Rect,
	radii: [4]f32,
	blur, spread: f32,
	colour: Colour,
) {
	half := [2]f32{base.w * 0.5 + spread, base.h * 0.5 + spread}
	if half[0] <= 0 || half[1] <= 0 {return}

	grown := [4]f32{}
	for corner in 0 ..< 4 {
		if radii[corner] > 0 {
			grown[corner] = radii[corner] + spread
		}
	}
	clamped := clamp_corner_radii(grown, half[0] * 2, half[1] * 2)

	outer := Rect {
		x = base.x - spread - blur,
		y = base.y - spread - blur,
		w = base.w + (spread + blur) * 2,
		h = base.h + (spread + blur) * 2,
	}
	draw_quad_shape_full(
		g.target,
		outer,
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
		.Shadow,
		max_corner_radius(clamped),
		half,
		blur,
		clamped,
		{spread, 0, 0, 0},
	)
}

draw_shadow_layers :: proc(
	g: ^GUI,
	base: Rect,
	radii: [4]f32,
	blur, spread: f32,
	colour: Colour,
) {
	if blur <= 0 && spread == 0 {
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
		grow := spread + blur * (1 - f32(i) / f32(SHADOW_LAYERS - 1))
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

draw_inset_shadow :: proc(g: ^GUI, r: Rect, box: ^StyleBox) {
	widths := box.border_width
	inner := Rect {
		x = r.x + max(widths[0], 0),
		y = r.y + max(widths[1], 0),
		w = r.w - max(widths[0], 0) - max(widths[2], 0),
		h = r.h - max(widths[1], 0) - max(widths[3], 0),
	}
	if inner.w <= 0 || inner.h <= 0 {return}

	radii := stylebox_radii(box)
	inner_radii := [4]f32 {
		max(radii[0] - max(widths[0], widths[1]), 0),
		max(radii[1] - max(widths[1], widths[2]), 0),
		max(radii[2] - max(widths[2], widths[3]), 0),
		max(radii[3] - max(widths[3], widths[0]), 0),
	}
	inner_radii = clamp_corner_radii(inner_radii, inner.w, inner.h)

	blur := max(box.shadow_size, 0)
	spread := box.shadow_spread
	if g.backend.supports_shapes {
		draw_quad_shape_full(
			g.target,
			inner,
			g.atlas.white_uv,
			box.shadow_color,
			g.atlas_texture,
			.Shadow,
			max_corner_radius(inner_radii),
			{inner.w * 0.5, inner.h * 0.5},
			-blur,
			inner_radii,
			{spread, box.shadow_offset.x, box.shadow_offset.y, 0},
		)
		return
	}
	draw_inset_shadow_layers(g, inner, inner_radii, blur, spread, box.shadow_color)
}

draw_inset_shadow_layers :: proc(
	g: ^GUI,
	inner: Rect,
	radii: [4]f32,
	blur, spread: f32,
	colour: Colour,
) {
	depth := spread + blur
	if depth <= 0 {return}

	for i in 0 ..< INSET_SHADOW_LAYERS {
		d0 := i == 0 ? 0 : spread + blur * f32(i) / f32(INSET_SHADOW_LAYERS)
		d1 := spread + blur * f32(i + 1) / f32(INSET_SHADOW_LAYERS)
		r0 := inset_rect(inner, d0)
		r1 := inset_rect(inner, d1)
		if r1.w <= 0 || r1.h <= 0 {return}
		radii0 := shrink_radii(radii, d0)
		radii1 := shrink_radii(radii, d1)
		c := colour
		c.a *= 1 - 0.8 * f32(i) / f32(INSET_SHADOW_LAYERS)
		emit_round_ring(g, r0, radii0, r1, radii1, c)
	}
}

inset_rect :: proc(r: Rect, d: f32) -> Rect {
	return Rect{x = r.x + d, y = r.y + d, w = r.w - d * 2, h = r.h - d * 2}
}

shrink_radii :: proc(radii: [4]f32, d: f32) -> [4]f32 {
	return [4]f32{max(radii[0] - d, 0), max(radii[1] - d, 0), max(radii[2] - d, 0), max(radii[3] - d, 0)}
}

emit_round_ring :: proc(
	g: ^GUI,
	outer: Rect,
	outer_radii: [4]f32,
	inner: Rect,
	inner_radii: [4]f32,
	colour: Colour,
) {
	if outer.w <= 0 || outer.h <= 0 {return}
	if inner.w <= 0 || inner.h <= 0 {return}

	outer_clamped := clamp_corner_radii(outer_radii, outer.w, outer.h)
	inner_clamped := clamp_corner_radii(inner_radii, inner.w, inner.h)
	if radii_are_zero(outer_clamped) && radii_are_zero(inner_clamped) {
		draw_border_rects(
			g,
			outer,
			{
				inner.x - outer.x,
				inner.y - outer.y,
				outer.x + outer.w - inner.x - inner.w,
				outer.y + outer.h - inner.y - inner.h,
			},
			{colour, colour, colour, colour},
		)
		return
	}

	outer_points: [4 * (CORNER_SEGMENTS + 1)][2]f32
	inner_points: [4 * (CORNER_SEGMENTS + 1)][2]f32
	round_rect_loop(outer, outer_clamped, CORNER_SEGMENTS, outer_points[:])
	round_rect_loop(inner, inner_clamped, CORNER_SEGMENTS, inner_points[:])

	n := len(outer_points)
	for i in 0 ..< n {
		j := (i + 1) % n
		piece := [4][2]f32{outer_points[i], outer_points[j], inner_points[j], inner_points[i]}
		if polygon_area2(piece) <= 0.0001 {continue}
		draw_polygon(g.target, piece[:], colour, g.atlas_texture)
	}
}

draw_rect :: proc(g: ^GUI, r: Rect, colour: Colour, radius: f32) {
	draw_rect_radii(g, r, colour, {radius, radius, radius, radius})
}

draw_glass :: proc(
	g: ^GUI,
	r: Rect,
	colour: Colour,
	radii: [4]f32,
	blur: f32,
	optics: Glass_Optics = {},
) {
	if r.w <= 0 || r.h <= 0 {return}
	if blur <= 0 {
		draw_rect_radii(g, r, colour, radii)
		return
	}
	clamped := clamp_corner_radii(radii, r.w, r.h)
	if !g.backend.supports_shapes {
		draw_round_polygon_radii(g, r, colour, clamped)
		return
	}
	draw_quad_shape_full(
		g.target,
		r,
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
		.Glass,
		max_corner_radius(clamped),
		{r.w * 0.5, r.h * 0.5},
		blur,
		clamped,
		{optics.refraction, optics.dispersion, optics.fresnel, optics.saturation},
		true,
	)
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

CORNER_SEGMENTS :: 4

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
	style := resolved_style(g, w)
	radii := style.box.corner_radius
	draw_push_clip(g.target, bar)
	draw_rect_radii(g, w.rect, RGBA(0.08, 0.09, 0.11, 1), {radii[0], radii[1], 0, 0})
	draw_pop_clip(g.target)

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

//* An overlay that says what the program is doing: how long the frame
//* took, how many things were drawn, and what is under the pointer.


Inspector :: struct {
	enabled:    bool,
	inspecting: bool,
}

inspector_enable :: proc(g: ^GUI, enabled: bool) {
	g.inspector.enabled = enabled
	draw_invalidate(g)
}

inspector_is_enabled :: proc(g: ^GUI) -> bool {
	return g.inspector.enabled
}

inspector_inspect :: proc(g: ^GUI, inspecting: bool) {
	g.inspector.inspecting = inspecting
	draw_invalidate(g)
}

draw_inspector :: proc(g: ^GUI) {
	if !g.inspector.enabled {return}

	lines: [dynamic]string
	defer delete(lines)

	append(&lines, fmt.tprintf("%.1f ms", f64(g.dt) * 1000))
	append(&lines, fmt.tprintf("%d widgets", len(g.widgets)))
	append(&lines, fmt.tprintf("%d commands", len(g.draw.commands)))
	append(&lines, fmt.tprintf("%d vertices", len(g.draw.vertices)))
	append(&lines, fmt.tprintf("atlas %d MiB", atlas_bytes(g)))

	if g.inspector.inspecting {
		id := hit_test(g, g.root, g.pointer)
		if w := Widget_Get(g, id); w != nil {
			append(&lines, fmt.tprintf("%s", w.name))
			append(
				&lines,
				fmt.tprintf(
					"%d %d %d %d",
					int(w.rect.x),
					int(w.rect.y),
					int(w.rect.w),
					int(w.rect.h),
				),
			)
		}
	}

	width := f32(0)
	for line in lines {
		size := Font_Measure(g, Font_Of(g, Widget_Get(g, g.root)), line).x
		if size > width {width = size}
	}
	height := f32(len(lines)) * 16 + 12
	rect := Rect {
		x = 8,
		y = 8,
		w = width + 16,
		h = height,
	}

	draw_rect(g, rect, RGBA(0.05, 0.05, 0.07, 0.85), 4)
	draw_border_box(g, rect, RGBA(0.30, 0.32, 0.38, 0.9))

	y := rect.y + 6
	for line in lines {
		Font_Draw(
			g,
			Font_Of(g, Widget_Get(g, g.root)),
			line,
			Rect{x = rect.x + 8, y = y, w = rect.w - 16, h = 16},
			RGBA(0.85, 0.88, 0.94, 1),
			.Left,
		)
		y += 16
	}
}

//* How much of the atlas is in use, in MiB.
atlas_bytes :: proc(g: ^GUI) -> int {
	if g.atlas == nil {return 0}
	total := 0
	for &p in g.atlas.pages { total += p.width * p.height * 4 }
	return total / (1024 * 1024)
}

draw_border_box :: proc(g: ^GUI, rect: Rect, colour: Colour) {
	t := f32(1)
	draw_quad(g.target, Rect{rect.x, rect.y, rect.w, t}, g.atlas.white_uv, colour, g.atlas_texture)
	draw_quad(
		g.target,
		Rect{rect.x, rect.y + rect.h - t, rect.w, t},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(g.target, Rect{rect.x, rect.y, t, rect.h}, g.atlas.white_uv, colour, g.atlas_texture)
	draw_quad(
		g.target,
		Rect{rect.x + rect.w - t, rect.y, t, rect.h},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
}
