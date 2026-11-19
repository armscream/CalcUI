//* A field with a list of selectable items.

package Widgets
COMBO_BOX_FIELD_HEIGHT :: 28
COMBO_BOX_ROW          :: 24
COMBO_BOX_ARROW_SPACE  :: 26


Make_Combo_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Combo_Box_Opts) -> Widget_ID {
	kind_register(g, .ComboBox, combo_box_kind())
	id := New_Widget(g, .ComboBox, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	popup := Make_Popup_Menu(g, g.root, Popup_Menu_Opts{items = opts.items})
	pw := Widget_Get(g, popup)
	if pw != nil {
		Widget_Set_Z_Index(g, popup, POPUP_Z_INDEX)
		pw.signals.on_item_selected = combo_box_popup_selected
		#partial switch &pd in pw.data {
		case Popup_Menu_Data:
			pd.owner = id
		}
	}

	data := Combo_Box_Data{selected = -1, popup = popup}
	for text in opts.items {
		append(&data.items, Combo_Box_Item{text = text})
	}
	w.data = data
	w.focus_mode = .All
	w.base_min_size.y = max(w.base_min_size.y, f32(COMBO_BOX_FIELD_HEIGHT))
	w.min_size.y = w.base_min_size.y
	return id
}

//* The popup of a combo box, or INVALID_WIDGET_ID.
combo_box_popup :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	d := combo_box_data(g, id)
	if d == nil { return INVALID_WIDGET_ID }
	return d.popup
}

//* The combo a popup menu lists for, or INVALID_WIDGET_ID.
combo_box_popup_owner :: proc(g: ^GUI, popup: Widget_ID) -> Widget_ID {
	w := Widget_Get(g, popup)
	if w == nil { return INVALID_WIDGET_ID }
	#partial switch d in w.data {
	case Popup_Menu_Data:
		return d.owner
	}
	return INVALID_WIDGET_ID
}

combo_box_popup_selected :: proc(g: ^GUI, popup: Widget_ID, index: int) {
	owner := combo_box_popup_owner(g, popup)
	if owner == INVALID_WIDGET_ID { return }
	d := combo_box_data(g, owner)
	if d == nil || index < 0 || index >= len(d.items) { return }
	d.selected = index
	d.open = false
	invalidate(g, owner, Dirty_Flags{.Visual})
}

combo_box_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw    = draw_combo_box,
		click   = click_combo_box,
		measure = measure_combo_box,
		destroy = destroy_combo_box,
		theme_name = "ComboBox",
	}
}

destroy_combo_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := combo_box_data(g, id)
	if d == nil || d.popup == INVALID_WIDGET_ID { return }
	if Widget_Alive(g, d.popup) { Widget_Free(g, d.popup) }
	d.popup = INVALID_WIDGET_ID
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
	if d.popup != INVALID_WIDGET_ID { Popup_Menu_Add_Item(g, d.popup, text) }
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
	if d.popup != INVALID_WIDGET_ID {
		Popup_Menu_Close(g, d.popup)
		if pw := Widget_Get(g, d.popup); pw != nil {
			#partial switch &pd in pw.data {
			case Popup_Menu_Data:
				pd.selected = index
			}
		}
	}
	if changed { signal_item_selected(g, id, index) }
	invalidate(g, id, Dirty_Flags{.Visual})
}

combo_box_is_open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := combo_box_data(g, id)
	if d == nil || d.popup == INVALID_WIDGET_ID { return false }
	return Popup_Is_Open(g, d.popup)
}

combo_box_open :: proc(g: ^GUI, id: Widget_ID) {
	d := combo_box_data(g, id)
	if d == nil || d.popup == INVALID_WIDGET_ID { return }
	w := Widget_Get(g, id)
	if w == nil { return }

	field := combo_box_field_rect(g, w)
	host := g.root
	if fi := float_index_of(g, id); fi != FLOAT_NONE {
		host = g.floats[fi].widget
	}
	if pw := Widget_Get(g, d.popup); pw != nil && pw.parent != host {
		Widget_Attach(g, host, d.popup)
	}
	popup_menu_place(g, d.popup, field)
	if pw := Widget_Get(g, d.popup); pw != nil {
		#partial switch &pd in pw.data {
		case Popup_Menu_Data:
			pd.selected = d.selected
		}
	}
	Popup_Menu_Open(g, d.popup)
	d.open = true
	invalidate(g, id, Dirty_Flags{.Visual})
}

combo_box_close :: proc(g: ^GUI, id: Widget_ID) {
	d := combo_box_data(g, id)
	if d == nil { return }
	if d.popup != INVALID_WIDGET_ID { Popup_Menu_Close(g, d.popup) }
	if !d.open { return }
	d.open = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

combo_box_set_open :: proc(g: ^GUI, id: Widget_ID, open: bool) {
	if open { combo_box_open(g, id) } else { combo_box_close(g, id) }
}

combo_box_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

combo_box_field_rect :: proc(g: ^GUI, w: ^Widget) -> Rect {
	content := combo_box_content(g, w)
	return combo_box_layout(content, false).field
}

//* The field is the only part of the combo that lives inside the widget;
//* the list is a popup of its own.
combo_box_layout :: proc(content: Rect, open: bool) -> Combo_Box_Layout {
	field_h := min(f32(COMBO_BOX_FIELD_HEIGHT), content.h)
	return Combo_Box_Layout{
		field = Rect{x = content.x, y = content.y, w = content.w, h = field_h},
	}
}

click_combo_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	if combo_box_is_open(g, id) {
		combo_box_close(g, id)
	} else {
		combo_box_open(g, id)
	}
}

draw_combo_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := combo_box_data(g, id)
	if d == nil { return }

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	open := combo_box_is_open(g, id)
	field := combo_box_layout(content, false).field

	text_style := style.text
	text_style.valign = .Center
	text := combo_box_text(g, id)
	colour := ink
	if text == "" {
		text = "..."
		colour = Scale_Colour(ink, 0.55)
	}

	draw_text(g, text_style, text,
		Rect{x = field.x + 6, y = field.y, w = field.w - 26, h = field.h}, colour)
	draw_combo_box_arrow(g, field, open, ink)
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
