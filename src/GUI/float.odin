//* A panel that is torn out of the dock tree and becomes a window of its own.
//* It keeps its children, is drawn into a list of its own and lives in screen
//* coordinates, so it can be dragged anywhere. The platform gives it a native
//* window and keeps it in step with the position held here.
package GUI

//* The index of no floating panel.
FLOAT_NONE :: -1

//* Tears a panel out of the tree and gives it a window of its own.
//* Returns the index of the new floating panel.
Make_Float_Panel :: proc(g: ^GUI, widget: Widget_ID, pos: Vec2, size: Vec2) -> int {
	w := Widget_Get(g, widget)
	if w == nil { return FLOAT_NONE }
	if size.x <= 0 || size.y <= 0 { return FLOAT_NONE }

	//* The panel leaves the tree, but keeps its children and its look.
	Widget_Detach(g, widget)

	f := Float_Panel{
		widget = widget,
		pos = pos,
		size = size,
		title = w.name,
	}
	append(&g.floats, f)
	//* The panel is a window of its own now, so it is laid out in its own space.
	invalidate(g, widget, DIRTY_ALL)
	return len(g.floats) - 1
}

//* Takes a floating panel out of the list and gives its widget back.
//* Returns the widget, which is still on its own.
unfloat_panel :: proc(g: ^GUI, index: int) -> Widget_ID {
	if index < 0 || index >= len(g.floats) { return INVALID_WIDGET_ID }
	f := g.floats[index]
	ordered_remove(&g.floats, index)
	draw_list_destroy(&f.draw)
	//* The panel is not a window of its own any more: it is laid out
	//* with the tree again, if it goes back into it.
	invalidate(g, f.widget, DIRTY_ALL)
	return f.widget
}

//* The floating panel a widget belongs to, or FLOAT_NONE.
float_of :: proc(g: ^GUI, id: Widget_ID) -> int {
	for i in 0 ..< len(g.floats) {
		if g.floats[i].widget == id { return i }
	}
	return FLOAT_NONE
}

//* The floating panel a widget is in, or FLOAT_NONE. A widget that is
//* under a floating panel is in that panel, and the panel itself is in
//* it as well.
float_index_of :: proc(g: ^GUI, id: Widget_ID) -> int {
	if id == INVALID_WIDGET_ID { return FLOAT_NONE }
	for i in 0 ..< len(g.floats) {
		if g.floats[i].widget == id { return i }
		if is_descendant(g, g.floats[i].widget, id) { return i }
	}
	return FLOAT_NONE
}

//* The bounds of the window a widget is in: the viewport of the main
//* window, or the size of the floating panel it is in. The bounds are
//* in the coordinates of that window.
widget_bounds :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	index := float_index_of(g, id)
	if index == FLOAT_NONE { return g.viewport }
	f := g.floats[index]
	return Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}
}

//* A point on the screen in the coordinates of the window a widget is
//* in.
window_local_pos :: proc(g: ^GUI, id: Widget_ID, global: Vec2) -> Vec2 {
	index := float_index_of(g, id)
	if index == FLOAT_NONE { return main_window_pos(g, global) }
	f := g.floats[index]
	return Vec2{global.x - f.pos.x, global.y - f.pos.y}
}

//* The place of a point on the screen in the main window.
main_window_pos :: proc(g: ^GUI, global: Vec2) -> Vec2 {
	return Vec2{global.x - g.window_rect.x, global.y - g.window_rect.y}
}

//* True when a point on the screen is outside of the main window.
outside_main_window :: proc(g: ^GUI, global: Vec2) -> bool {
	return !rect_contains(g.window_rect, global.x, global.y)
}
