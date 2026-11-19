package Widgets
TOOLTIP_SHOW_DELAY :: 0.5
TOOLTIP_Z_INDEX :: 1000


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
		d.show_at = g.time
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

Tooltip_Hide :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Tooltip_Data:
		d.visible = false
		d.show_at = g.time
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
			d.show_at = g.time
			d.visible = false
			return
		}
		target := Widget_Get(g, d.target)
		if target != nil && (!(.Visible in target.state) || target.tooltip_text == "") {
			d.target = INVALID_WIDGET_ID
			d.text = ""
			d.show_at = g.time
			d.visible = false
			target = nil
		}
		over := false
		if target != nil {
			local := window_local_pos(g, target.id, g.global_pointer)
			over = rect_contains(target.rect, local.x, local.y)
		}
		if !over {
			hot := tooltip_of(g, g.global_pointer)
			if hot == INVALID_WIDGET_ID {
				if d.target != INVALID_WIDGET_ID || d.visible {
					invalidate(g, id, Dirty_Flags{.Visual})
				}
				d.target = INVALID_WIDGET_ID
				d.text = ""
				d.show_at = g.time
				d.visible = false
				return
			}
			found := Widget_Get(g, hot)
			if found == nil {return}
			if found.id != d.target || d.text != found.tooltip_text {
				d.target = hot
				d.text = found.tooltip_text
				d.show_at = g.time + TOOLTIP_SHOW_DELAY
				d.visible = false
				invalidate(g, id, Dirty_Flags{.Visual})
			}
			target = found
			local := window_local_pos(g, target.id, g.global_pointer)
			over = rect_contains(target.rect, local.x, local.y)
		}
		if over && d.text != "" {
			if !d.visible {
				if d.show_at <= 0 {
					d.show_at = g.time + TOOLTIP_SHOW_DELAY
				}
				if g.time >= d.show_at {
					d.visible = true
					invalidate(g, id, Dirty_Flags{.Visual})
				} else {
					wake_at(g, d.show_at)
				}
			}
			return
		}
		if d.visible || d.target != INVALID_WIDGET_ID {
			invalidate(g, id, Dirty_Flags{.Visual})
		}
		d.show_at = g.time
		d.visible = false
		d.target = INVALID_WIDGET_ID
		d.text = ""
	}
}

draw_tooltip :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	style := resolved_style(g, w)
	#partial switch d in w.data {
	case Tooltip_Data:
		if !d.visible || d.text == "" {return}
		text_style := style.text
		if text_style.wrap == .Off {text_style.wrap = .Word}
		max_width := max(min(f32(360), g.viewport.w - 32), 80)
		size := text_measure(g, text_style, d.text, max_width)
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
		draw_stylebox_box(g, box, &frame)
		ink := resolved_text_colour(g, id, w)
		label := Rect {
			x = box.x + pad[0],
			y = box.y + pad[1],
			w = box.w - pad[0] - pad[2],
			h = box.h - pad[1] - pad[3],
		}
		draw_text(g, text_style, d.text, label, ink)
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

