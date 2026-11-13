//* A field with a list of selectable items.

package GUI

COMBO_BOX_FIELD_HEIGHT :: 28
COMBO_BOX_ROW          :: 24
COMBO_BOX_ARROW_SPACE  :: 26

Combo_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Make_Combo_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Combo_Box_Opts) -> Widget_ID {
	kind_register(g, .ComboBox, combo_box_kind())
	id := New_Widget(g, .ComboBox, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	data := Combo_Box_Data{selected = -1}
	for text in opts.items {
		append(&data.items, Combo_Box_Item{text = text})
	}
	w.data = data
	w.focus_mode = .All
	w.base_min_size.y = max(w.base_min_size.y, f32(COMBO_BOX_FIELD_HEIGHT))
	w.min_size.y = w.base_min_size.y
	return id
}

combo_box_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw    = draw_combo_box,
		click   = click_combo_box,
		measure = measure_combo_box,
		theme_name = "ComboBox",
	}
}

measure_combo_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := combo_box_data(g, id)
	if d == nil { return Vec2{} }

	style := resolved_style(g, w)
	width := f32(0)
	for item in d.items {
		width = max(width, text_measure(g, style.text, item.text, 0).x)
	}

	pad := style.box.content_margin
	return Vec2{
		width + f32(COMBO_BOX_ARROW_SPACE) + pad[0] + pad[2],
		f32(COMBO_BOX_FIELD_HEIGHT) + pad[1] + pad[3],
	}
}

combo_box_data :: proc(g: ^GUI, id: Widget_ID) -> ^Combo_Box_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Combo_Box_Data:
		return &d
	}
	return nil
}

combo_box_add_item :: proc(g: ^GUI, id: Widget_ID, text: string, icon: Texture_ID = INVALID_TEXTURE_ID) {
	d := combo_box_data(g, id)
	if d == nil { return }
	append(&d.items, Combo_Box_Item{text = text, icon = icon})
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

combo_box_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := combo_box_data(g, id)
	if d == nil { return 0 }
	return len(d.items)
}

combo_box_item_text :: proc(g: ^GUI, id: Widget_ID, index: int) -> string {
	d := combo_box_data(g, id)
	if d == nil || index < 0 || index >= len(d.items) { return "" }
	return d.items[index].text
}

combo_box_selected :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := combo_box_data(g, id)
	if d == nil { return -1 }
	return d.selected
}

combo_box_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := combo_box_data(g, id)
	if d == nil || d.selected < 0 || d.selected >= len(d.items) { return "" }
	return d.items[d.selected].text
}

combo_box_select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	d := combo_box_data(g, id)
	if d == nil || index < 0 || index >= len(d.items) { return }

	changed := d.selected != index
	d.selected = index
	d.open = false
	if changed { signal_item_selected(g, id, index) }
	invalidate(g, id, Dirty_Flags{.Visual})
}

combo_box_is_open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := combo_box_data(g, id)
	return d != nil && d.open
}

combo_box_set_open :: proc(g: ^GUI, id: Widget_ID, open: bool) {
	d := combo_box_data(g, id)
	if d == nil || d.open == open { return }
	d.open = open
	invalidate(g, id, Dirty_Flags{.Visual})
}

combo_box_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

Combo_Box_Layout :: struct {
	field: Rect,
	list:  Rect,
}

combo_box_layout :: proc(content: Rect, open: bool) -> Combo_Box_Layout {
	field_h := min(f32(COMBO_BOX_FIELD_HEIGHT), content.h)
	layout := Combo_Box_Layout{
		field = Rect{x = content.x, y = content.y, w = content.w, h = field_h},
	}
	if !open { return layout }

	top := content.y + field_h + 2
	height := content.y + content.h - top
	if height > 0 {
		layout.list = Rect{x = content.x, y = top, w = content.w, h = height}
	}
	return layout
}

combo_box_item_at :: proc(list: Rect, count: int, y: f32) -> int {
	if count <= 0 || y < list.y || y >= list.y + list.h { return -1 }
	index := int((y - list.y) / f32(COMBO_BOX_ROW))
	if index < 0 || index >= count { return -1 }
	return index
}

click_combo_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := combo_box_data(g, id)
	if d == nil { return }

	layout := combo_box_layout(combo_box_content(g, w), d.open)
	if d.open && layout.list.h > 0 && rect_contains(layout.list, g.pointer.x, g.pointer.y) {
		if index := combo_box_item_at(layout.list, len(d.items), g.pointer.y); index >= 0 {
			combo_box_select(g, id, index)
		}
		return
	}
	if rect_contains(layout.field, g.pointer.x, g.pointer.y) {
		combo_box_set_open(g, id, !d.open)
	} else {
		combo_box_set_open(g, id, false)
	}
}

draw_combo_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := combo_box_data(g, id)
	if d == nil { return }

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	layout := combo_box_layout(content, d.open)

	text_style := style.text
	text_style.valign = .Center
	text := combo_box_text(g, id)
	colour := ink
	if text == "" {
		text = "..."
		colour = Scale_Colour(ink, 0.55)
	}

	field := layout.field
	draw_text(g, text_style, text,
		Rect{x = field.x + 6, y = field.y, w = field.w - 26, h = field.h}, colour)
	draw_combo_box_arrow(g, field, d.open, ink)

	if !d.open { return }

	draw_rect(g, layout.list, COLLECT_PANEL, 4)
	row_style := style.text
	row_style.valign = .Center
	y := layout.list.y

	for item, i in d.items {
		if y >= layout.list.y + layout.list.h { break }
		row := Rect{x = layout.list.x + 2, y = y, w = layout.list.w - 4, h = COMBO_BOX_ROW}
		row_ink := ink
		if i == d.selected {
			draw_rect(g, row, COLLECT_ACCENT, 3)
			row_ink = RGBA(1, 1, 1, 1)
		}
		draw_text(g, row_style, item.text,
			Rect{x = row.x + 6, y = row.y, w = row.w - 12, h = row.h}, row_ink)
		y += COMBO_BOX_ROW
	}
}

draw_combo_box_arrow :: proc(g: ^GUI, field: Rect, open: bool, colour: Colour) {
	size := f32(4)
	cx := field.x + field.w - size - 8
	cy := field.y + field.h * 0.5

	points: [3][2]f32
	if open {
		points = {
			{cx - size, cy + size * 0.5},
			{cx + size, cy + size * 0.5},
			{cx, cy - size},
		}
	} else {
		points = {
			{cx - size, cy - size * 0.5},
			{cx + size, cy - size * 0.5},
			{cx, cy + size},
		}
	}
	draw_polygon(g.target, points[:], colour, g.atlas_texture)
}