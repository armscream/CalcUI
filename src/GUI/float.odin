package GUI

//* Floating panels.
//
//* A panel can be torn out of the dock tree and become a window of its
//* own. A floating panel keeps its children, is drawn into a list of
//* its own and lives in screen coordinates, so it can be dragged
//* anywhere: onto another monitor, or off the edge of the screen.
//
//* The platform gives every floating panel a native window and keeps
//* it in step with the position held here.

FLOAT_NONE :: -1

//* Tears a panel out of the tree and gives it a window of its own.
//* Returns the index of the new floating panel.
Make_Float_Panel :: proc(g: ^GUI, widget: Widget_ID, pos: Vec2, size: Vec2) -> int {
	w := Widget_Get(g, widget)
	if w == nil { return FLOAT_NONE }
	if size.x <= 0 || size.y <= 0 { return FLOAT_NONE }

	//* The panel leaves the tree, but keeps its children and its look.
	//* A tab host that loses a tab keeps showing a tab that is there.
	Widget_Detach(g, widget)

	f := Float_Panel{
		widget = widget,
		pos = pos,
		size = size,
		title = w.name,
	}
	append(&g.floats, f)
	//* The panel is a window of its own now, so it is laid out in its
	//* own space.
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

//* The floating panel under a point on the screen, and the widget in
//* it. The last one is on top of the others.
hit_test_float :: proc(g: ^GUI, global: Vec2) -> (index: int, id: Widget_ID) {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local := Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		id = hit_test(g, f.widget, local)
		if id != INVALID_WIDGET_ID { return i, id }
	}
	return FLOAT_NONE, INVALID_WIDGET_ID
}

//* The place of a point on the screen in the main window.
main_window_pos :: proc(g: ^GUI, global: Vec2) -> Vec2 {
	return Vec2{global.x - g.window_rect.x, global.y - g.window_rect.y}
}

//* True when a point on the screen is outside of the main window.
outside_main_window :: proc(g: ^GUI, global: Vec2) -> bool {
	return !rect_contains(g.window_rect, global.x, global.y)
}
