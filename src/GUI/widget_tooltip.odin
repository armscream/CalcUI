package GUI

TOOLTIP_SHOW_DELAY :: 0.5
TOOLTIP_Z_INDEX :: 1000

Tooltip_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	target:    Widget_ID,
}

Make_Tooltip :: proc(g: ^GUI, parent: Widget_ID, opts: Tooltip_Opts) -> Widget_ID {
	kind_register(g, .Tooltip, tooltip_kind())
	id := New_Widget(g, .Tooltip, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Tooltip_Data {
		text   = opts.text,
		target = opts.target,
	}
	w.mouse_filter = .Ignore
	w.focus_mode = .None
	w.clip_contents = false
	fields := style_fields_of(&w.style)
	fields += bit_set[Style_Field]{.BG, .Border, .Border_Width, .Corner_Radius}
	w.style.set = fields
	w.style.box.bg_color = Colour{}
	w.style.box.border_color = [4]Colour{}
	w.style.box.border_width = [4]f32{}
	w.style.box.corner_radius = [4]f32{}
	return id
}

Tooltip_Show :: proc(g: ^GUI, id: Widget_ID, target: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Tooltip_Data:
		d.target = target
		d.text = text
		d.visible = true
		d.timer = TOOLTIP_SHOW_DELAY
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

Tooltip_Hide :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Tooltip_Data:
		d.visible = false
		d.timer = 0
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

Tooltip_Is_Visible :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil {return false}
	#partial switch d in w.data {
	case Tooltip_Data:
		return d.visible
	}
	return false
}

Tooltip_Widget :: proc(g: ^GUI) -> Widget_ID {
	if g == nil {return INVALID_WIDGET_ID}
	return g.tooltip_id
}

Set_Tooltip_Enabled :: proc(g: ^GUI, enabled: bool) {
	if g == nil {return}
	g.tooltip_enabled = enabled
	if !enabled && g.tooltip_id != INVALID_WIDGET_ID {
		Tooltip_Hide(g, g.tooltip_id)
	}
}

Tooltip_Enabled :: proc(g: ^GUI) -> bool {
	if g == nil {return false}
	return g.tooltip_enabled
}

gui_make_tooltip :: proc(g: ^GUI) -> Widget_ID {
	if g == nil {return INVALID_WIDGET_ID}
	id := Make_Tooltip(g, g.root, Tooltip_Opts{})
	Widget_Set_Z_Index(g, id, TOOLTIP_Z_INDEX)
	g.tooltip_id = id
	g.tooltip_enabled = true
	return id
}

tooltip_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_tooltip,
		update = update_tooltip,
		style = Style{box = StyleBox{content_margin = {8, 5, 8, 5}}},
		theme_name = "Tooltip",
	}
}

tooltip_data :: proc(g: ^GUI, id: Widget_ID) -> ^Tooltip_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Tooltip_Data:
		return &d
	}
	return nil
}

update_tooltip :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	#partial switch &d in w.data {
	case Tooltip_Data:
		if id == g.tooltip_id && !g.tooltip_enabled {
			d.timer = 0
			d.visible = false
			return
		}
		target := Widget_Get(g, d.target)
		over := target != nil && rect_contains(target.rect, g.pointer.x, g.pointer.y)
		if !over {
			hot := tooltip_of(g, g.root, g.pointer)
			if hot == INVALID_WIDGET_ID {
				d.timer = 0
				d.visible = false
				return
			}
			found := Widget_Get(g, hot)
			if found == nil {return}
			if found.id != d.target {
				d.target = hot
				d.text = found.tooltip_text
				d.timer = 0
				d.visible = false
			}
			target = found
			over = rect_contains(target.rect, g.pointer.x, g.pointer.y)
		}
		if over {
			d.timer += dt
			if d.timer >= TOOLTIP_SHOW_DELAY {d.visible = true}
			return
		}
		d.timer = 0
		d.visible = false
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

draw_tooltip :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	style := resolved_style(g, w)
	#partial switch d in w.data {
	case Tooltip_Data:
		if !d.visible {return}
		size := text_measure(g, style.text, d.text, 0)
		pad := style.box.content_margin
		box := Rect {
			x = g.pointer.x + 12,
			y = g.pointer.y + 18,
			w = size.x + pad[0] + pad[2],
			h = size.y + pad[1] + pad[3],
		}
		if box.x + box.w > g.viewport.w {
			box.x = g.pointer.x - 12 - box.w
		}
		if box.x < 0 {box.x = 0}
		if box.y + box.h > g.viewport.h {
			box.y = g.pointer.y - 18 - box.h
		}
		if box.y < 0 {box.y = 0}
		frame := tooltip_box(g, style)
		draw_stylebox_at(g, &frame, box)
		ink := resolved_text_colour(g, id, w)
		label := Rect {
			x = box.x + pad[0],
			y = box.y + pad[1],
			w = box.w - pad[0] - pad[2],
			h = box.h - pad[1] - pad[3],
		}
		draw_text(g, style.text, d.text, label, ink)
	}
}

tooltip_box :: proc(g: ^GUI, style: ^Style) -> StyleBox {
	box := style.box
	if box.bg_color.a > 0 {return box}
	if themed, has := Theme_Get_Stylebox(g.theme, .Tooltip, "normal"); has {
		return themed
	}
	return StyleBox {
		bg_color      = RGBA(0.10, 0.11, 0.14, 0.96),
		corner_radius = {5, 5, 5, 5},
	}
}

draw_stylebox_at :: proc(g: ^GUI, box: ^StyleBox, rect: Rect) {
	draw_rect(g, rect, box.bg_color, stylebox_radius(box))
	widths := box.border_width
	colours := box.border_color
	if widths[0] > 0 && colours[0].a > 0 {
		draw_quad(
			g.target,
			Rect{x = rect.x, y = rect.y, w = widths[0], h = rect.h},
			g.atlas.white_uv,
			colours[0],
			g.atlas_texture,
		)
	}
	if widths[1] > 0 && colours[1].a > 0 {
		draw_quad(
			g.target,
			Rect{x = rect.x, y = rect.y, w = rect.w, h = widths[1]},
			g.atlas.white_uv,
			colours[1],
			g.atlas_texture,
		)
	}
	if widths[2] > 0 && colours[2].a > 0 {
		draw_quad(
			g.target,
			Rect{x = rect.x + rect.w - widths[2], y = rect.y, w = widths[2], h = rect.h},
			g.atlas.white_uv,
			colours[2],
			g.atlas_texture,
		)
	}
	if widths[3] > 0 && colours[3].a > 0 {
		draw_quad(
			g.target,
			Rect{x = rect.x, y = rect.y + rect.h - widths[3], w = rect.w, h = widths[3]},
			g.atlas.white_uv,
			colours[3],
			g.atlas_texture,
		)
	}
}