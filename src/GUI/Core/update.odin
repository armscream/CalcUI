//* The update phase of a frame. It runs twice: once before the layout
//* pass, for state, data and animation changes, and once after it, for
//* interaction that reads the geometry of the frame.
//*
//* The widgets that take part are gathered into a snapshot of handles
//* before any hook runs, and every handle is looked up again before its
//* hook is called. A hook that destroys a widget therefore leaves the
//* walk with a stale handle, not a stale pointer, and the walk skips it.
package Core
//* Fills `out` with the widgets that take part in the frame, in draw
//* order: the tree of the main window, then every floating panel.
update_collect :: proc(g: ^GUI, out: ^[dynamic]Widget_ID) {
	clear(out)
	if g == nil {return}
	if g.root != INVALID_WIDGET_ID {
		update_collect_node(g, g.root, out)
	}
	for &f in g.floats {
		update_collect_node(g, f.widget, out)
	}
}

update_collect_node :: proc(g: ^GUI, id: Widget_ID, out: ^[dynamic]Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	if !(.Visible in w.state) {return}
	if g.drag.active && id == g.drag.widget && g.drag.float_index < 0 {return}
	if is_hidden_tab(g, id) {return}

	append(out, id)

	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		update_collect_node(g, child, out)
		child = c.next_sibling
	}
}

//* Runs the state and animation part of the update phase, before the
//* layout pass.
widget_update_pass :: proc(g: ^GUI) {
	if g == nil {return}
	update_collect(g, &g.update_scratch)
	for id in g.update_scratch {
		w := Widget_Get(g, id)
		if w == nil {continue}
		kind := widget_kind(g, w)
		if kind.update != nil {
			kind.update(g, id, w, g.dt)
		}
	}
}

//* Runs the interaction part of the update phase, after the layout pass
//* and before the draw pass.
widget_post_update_pass :: proc(g: ^GUI) {
	if g == nil {return}
	update_collect(g, &g.update_scratch)
	for id in g.update_scratch {
		w := Widget_Get(g, id)
		if w == nil {continue}
		kind := widget_kind(g, w)
		if kind.post_update != nil {
			kind.post_update(g, id, w, g.dt)
		}
	}
}
