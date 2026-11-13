//* == The context menu ==
//* A menu that comes up where the pointer was. The data of the widget is
//* in widget_data.odin.

package GUI

//* The height of a row of the menu.
CONTEXT_MENU_ROW :: 24
//* The height of a separator of the menu.
CONTEXT_MENU_SEPARATOR :: 9
//* The room there is around the text of an item.
CONTEXT_MENU_PADDING :: 24
//* The width of a menu that has no text in it.
CONTEXT_MENU_MIN_WIDTH :: 120

Context_Menu_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []Context_Menu_Item,
}

//* Makes a context menu. It stays hidden until it is opened.
Make_Context_Menu :: proc(g: ^GUI, parent: Widget_ID, opts: Context_Menu_Opts) -> Widget_ID {
	kind_register(g, .ContextMenu, context_menu_kind())
	id := New_Widget(g, .ContextMenu, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	data := Context_Menu_Data{selected = -1}
	for item in opts.items { append(&data.items, item) }
	w.data = data
	//* The menu is drawn over the rest of the UI, so it is not cut to
	//* the rect of the widget.
	w.clip_contents = false
	//* A menu that is shut takes nothing: it does not even take the
	//* clicks.
	w.mouse_filter = .Ignore
	w.focus_mode = .None
	w.state -= Widget_State{.Visible}
	return id
}

//* Opens the menu at a place, in the coordinates of the parent.
Context_Menu_Open :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Context_Menu_Data:
		d.visible = true
		d.pos = pos
		d.selected = -1
	}
	//* The widget of the menu takes the rect of the menu, so the menu
	//* takes only the clicks that are on it.
	context_menu_place(g, id)
	Popup_Open(g, id)
}

Context_Menu_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Context_Menu_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

Context_Menu_Is_Open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	#partial switch d in w.data {
	case Context_Menu_Data:
		return d.visible
	}
	return false
}

Context_Menu_Add_Item :: proc(g: ^GUI, id: Widget_ID, item: Context_Menu_Item) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Context_Menu_Data:
		append(&d.items, item)
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The hooks of the widget.
context_menu_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_context_menu,
		click = click_context_menu,
		style = Style{
			box = StyleBox{
				content_margin = {4, 4, 4, 4},
			},
		},
		theme_name = "ContextMenu",
	}
}

context_menu_data :: proc(g: ^GUI, id: Widget_ID) -> ^Context_Menu_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Context_Menu_Data:
		return &d
	}
	return nil
}

//* The size a context menu asks for: the width of the widest of its
//* items with the room around it, and the height of its rows.
context_menu_size :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	w := Widget_Get(g, id)
	if w == nil { return {} }
	style := resolved_style(g, w)
	width := f32(0)
	height := f32(0)
	#partial switch d in w.data {
	case Context_Menu_Data:
		for item in d.items {
			if item.separator {
				height += CONTEXT_MENU_SEPARATOR
				continue
			}
			size := text_measure(g, style.text, item.text, 0)
			width = max(width, size.x)
			height += CONTEXT_MENU_ROW
		}
	}
	width = max(width + CONTEXT_MENU_PADDING, CONTEXT_MENU_MIN_WIDTH)
	return Vec2{x = width, y = height}
}

//* Puts the menu where it belongs. The menu comes up at the place it
//* was opened at, in the coordinates of its parent, and it stays inside
//* the window.
context_menu_place :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	parent := Widget_Get(g, w.parent)
	if parent == nil { return }
	point := Vec2{}
	#partial switch d in w.data {
	case Context_Menu_Data:
		point = d.pos
	}
	size := context_menu_size(g, id)
	if size.x <= 0 { return }
	anchor := Rect{x = parent.rect.x + point.x, y = parent.rect.y + point.y}
	rect := menu_place(anchor, size, widget_bounds(g, id))
	popup_set_rect(g, id, rect)
}

//* Where the menu is drawn: the rect of the widget is the rect of the
//* menu.
context_menu_rect :: proc(w: ^Widget) -> Rect {
	return w.rect
}

//* The item of the menu that is under a point, or -1 when there is
//* none.
context_menu_item_at :: proc(w: ^Widget, d: Context_Menu_Data, p: Vec2) -> int {
	rect := context_menu_rect(w)
	y := rect.y
	index := 0
	for item in d.items {
		if item.separator {
			y += CONTEXT_MENU_SEPARATOR
			index += 1
			continue
		}
		row := Rect{x = rect.x, y = y, w = rect.w, h = CONTEXT_MENU_ROW}
		if rect_contains(row, p.x, p.y) { return index }
		y += CONTEXT_MENU_ROW
		index += 1
	}
	return -1
}

//* A click on an item does it and closes the menu. A click anywhere
//* else closes the menu and does nothing else.
click_context_menu :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	action: proc(g: ^GUI, id: Widget_ID)
	index := -1
	picked := -1
	#partial switch &d in w.data {
	case Context_Menu_Data:
		index = context_menu_item_at(w, d, g.pointer)
		if index >= 0 {
			item := d.items[index]
			if !item.disabled && !item.separator {
				action = item.action
				d.selected = index
				picked = index
			}
		}
	}
	Context_Menu_Close(g, id)
	if picked >= 0 { signal_item_selected(g, id, picked) }
	if action != nil { action(g, id) }
}

//* The drawing: the items one under the other, and the separators as
//* lines.
draw_context_menu :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	style := resolved_style(g, w)
	#partial switch d in w.data {
	case Context_Menu_Data:
		if !d.visible { return }
		rect := context_menu_rect(w)
		draw_rect(g, rect, RGBA(0.14, 0.15, 0.18, 1), 6)

		ink := resolved_text_colour(g, id, w)
		row_style := style.text
		row_style.valign = .Center

		y := rect.y
		for item in d.items {
			if item.separator {
				draw_quad(
					g.target,
					Rect{x = rect.x + 8, y = y + CONTEXT_MENU_SEPARATOR * 0.5, w = rect.w - 16, h = 1},
					g.atlas.white_uv,
					RGBA(0.25, 0.27, 0.33, 1),
					g.atlas_texture,
				)
				y += CONTEXT_MENU_SEPARATOR
				continue
			}

			item_ink := ink
			if item.disabled { item_ink = Scale_Colour(ink, 0.5) }
			if item.checked {
				//* The tick: two strokes of a line.
				tick := Rect{x = rect.x + 8, y = y + 6, w = 12, h = 12}
				draw_thick_line(
					g.target,
					{tick.x + 2, tick.y + 6},
					{tick.x + 5, tick.y + 9},
					2,
					item_ink,
					g.atlas_texture,
				)
				draw_thick_line(
					g.target,
					{tick.x + 5, tick.y + 9},
					{tick.x + 10, tick.y + 2},
					2,
					item_ink,
					g.atlas_texture,
				)
			}
			label := Rect{x = rect.x + 24, y = y, w = rect.w - 32, h = CONTEXT_MENU_ROW}
			draw_text(g, row_style, item.text, label, item_ink)
			y += CONTEXT_MENU_ROW
		}
	}
}
