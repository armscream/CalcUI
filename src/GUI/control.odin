//* The control features of Godot: the mouse filter, the focus, the
//* states, the tooltip and the order of the drawing.

package GUI

//* == The control features ==
//* The features live on the widget itself: the widget is a struct and
//* the fields are open, so a program can reach them without a setter.

//* == The mouse ==

//* Every widget under a point, from the topmost one down. The children
//* of a widget are drawn on top of it, so they are looked at first. A
//* widget that is not enabled does not take the mouse: what is behind
//* it is found instead.
collect_hits :: proc(g: ^GUI, id: Widget_ID, p: Vec2, out: ^[dynamic]Widget_ID) {
	collect_hits_with(g, id, p, out, true)
}

//* Every widget under a point, whether it takes the mouse or not. The
//* tooltip of a widget that is not enabled is still worth showing.
collect_hits_any :: proc(g: ^GUI, id: Widget_ID, p: Vec2, out: ^[dynamic]Widget_ID) {
	collect_hits_with(g, id, p, out, false)
}

collect_hits_with :: proc(
	g: ^GUI,
	id: Widget_ID,
	p: Vec2,
	out: ^[dynamic]Widget_ID,
	skip_disabled: bool,
) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !(.Visible in w.state) { return }
	if skip_disabled && !(.Enabled in w.state) { return }
	if !rect_contains(w.rect, p.x, p.y) { return }

	//* The children are looked at from the topmost one down: the number
	//* a child has in the order of the drawing decides, and the order
	//* of the tree breaks the tie.
	children: [dynamic]Widget_ID
	defer delete(children)
	z_sorted_children(g, w, &children)
	for i := len(children) - 1; i >= 0; i -= 1 {
		child := children[i]
		if Widget_Get(g, child) == nil { continue }
		collect_hits_with(g, child, p, out, skip_disabled)
	}
	append(out, id)
}

//* The widget under a point that takes the mouse. A widget with the
//* filter .Ignore is passed over, so the widget behind it is found.
hit_test :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> Widget_ID {
	hits: [dynamic]Widget_ID
	defer delete(hits)
	collect_hits(g, id, p, &hits)
	for h in hits {
		w := Widget_Get(g, h)
		if w == nil { continue }
		if w.mouse_filter != .Ignore { return h }
	}
	return INVALID_WIDGET_ID
}

//* The widgets under a point that take the mouse, from the topmost one
//* down. A widget with the filter .Stop ends the list: the widgets
//* behind it do not get the event.
hits_that_take_the_mouse :: proc(g: ^GUI, id: Widget_ID, p: Vec2, out: ^[dynamic]Widget_ID) {
	all: [dynamic]Widget_ID
	defer delete(all)
	collect_hits(g, id, p, &all)
	for h in all {
		w := Widget_Get(g, h)
		if w == nil { continue }
		if w.mouse_filter == .Ignore { continue }
		append(out, h)
		if w.mouse_filter == .Stop { return }
	}
}

wheel_chain :: proc(g: ^GUI, global: Vec2) -> (chain: [dynamic]Widget_ID, local: Vec2) {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local = Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		collect_hits(g, f.widget, local, &chain)
		if len(chain) > 0 { return chain, local }
	}
	local = main_window_pos(g, global)
	collect_hits(g, g.root, local, &chain)
	return chain, local
}

//* == The focus ==

can_focus :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	if w.freeing { return false }
	if w.focus_mode == .None { return false }
	if !(.Visible in w.state) { return false }
	if !(.Enabled in w.state) { return false }
	return true
}

//* True when the widget is shown: it is shown itself, and everything
//* above it is shown too. A widget under a hidden panel, or on a tab
//* that is not showing, is not shown.
widget_is_shown :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	if !(.Visible in w.state) { return false }
	parent := w.parent
	for parent != INVALID_WIDGET_ID {
		p := Widget_Get(g, parent)
		if p == nil { return true }
		if !(.Visible in p.state) { return false }
		if is_hidden_tab(g, parent) { return false }
		parent = p.parent
	}
	return true
}

can_focus_now :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	if !can_focus(w) { return false }
	return widget_is_shown(g, id)
}

//* Gives the keyboard focus to a widget. The widget that had it loses
//* it, and both of them say so through their signals.
focus_set :: proc(g: ^GUI, id: Widget_ID) {
	if id == g.focused { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if !can_focus_now(g, id) { return }

	old := g.focused
	g.focused = id
	//* The caret of the widget that takes the keyboard is there at once.
	caret_reset(g)
	if old != INVALID_WIDGET_ID {
		signal_focus_exited(g, old)
		text_box_blur(g, old)
	}
	signal_focus_entered(g, id)
	access_focus_changed(g, id)
}

focus_clear :: proc(g: ^GUI) {
	if g.focused == INVALID_WIDGET_ID { return }
	old := g.focused
	g.focused = INVALID_WIDGET_ID
	signal_focus_exited(g, old)
	text_box_blur(g, old)
	access_focus_changed(g, INVALID_WIDGET_ID)
}

//* Gives the keyboard focus away when the widget that has it cannot
//* have it any more: it was hidden, disabled, or taken out of the tree.
focus_release :: proc(g: ^GUI) {
	if g.focused == INVALID_WIDGET_ID { return }
	if can_focus_now(g, g.focused) { return }
	focus_clear(g)
}

//* Gives the keyboard focus to a widget. The widget has to be one that
//* can have the focus: shown, enabled, and made for it. Returns false
//* when the widget cannot have the focus.
Focus_Set :: proc(g: ^GUI, id: Widget_ID) -> bool {
	if g == nil { return false }
	if g.focused == id { return true }
	w := Widget_Get(g, id)
	if w == nil { return false }
	if !can_focus_now(g, id) { return false }
	focus_set(g, id)
	return true
}

Focus_Clear :: proc(g: ^GUI) {
	if g == nil { return }
	focus_clear(g)
}

Focused_Widget :: proc(g: ^GUI) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	return g.focused
}

Widget_Has_Focus :: proc(g: ^GUI, id: Widget_ID) -> bool {
	if g == nil { return false }
	if id == INVALID_WIDGET_ID { return false }
	return g.focused == id
}

//* Every widget that can be given the focus, in the order of the tree.
focusable_widgets :: proc(g: ^GUI, out: ^[dynamic]Widget_ID) {
	focus_walk(g, g.root, out)
}

focus_walk :: proc(g: ^GUI, id: Widget_ID, out: ^[dynamic]Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if can_focus_now(g, id) { append(out, id) }
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		//* The next one is remembered before the child is walked: a
		//* widget that is taken out of the tree takes its links with
		//* it, and the walk goes on.
		next := c.next_sibling
		focus_walk(g, child, out)
		child = next
	}
}

//* The widgets the tab key reaches, in the order of the tab key. The
//* tab index comes first, and the order of the tree breaks the tie.
tab_order :: proc(g: ^GUI) -> [dynamic]Widget_ID {
	list: [dynamic]Widget_ID
	defer delete(list)
	focusable_widgets(g, &list)

	sorted := make([dynamic]Widget_ID, 0, len(list), context.allocator)
	for id in list {
		w := Widget_Get(g, id)
		if w == nil { continue }
		//* A widget that is only focused when it is clicked is not in
		//* the order of the tab key.
		if w.focus_mode != .All { continue }
		append(&sorted, id)
	}
	//* A simple insertion sort: the list is short, and it keeps the
	//* order of the tree for the widgets with the same index.
	for i in 1 ..< len(sorted) {
		id := sorted[i]
		key := Widget_Get(g, id)
		j := i - 1
		for j >= 0 {
			other := Widget_Get(g, sorted[j])
			if other == nil { break }
			if other.tab_index <= key.tab_index { break }
			sorted[j + 1] = sorted[j]
			j -= 1
		}
		sorted[j + 1] = id
	}
	return sorted
}

//* The widget the tab key moves to. The widgets are sorted by their tab
//* index, and the order of the tree breaks the tie.
focus_next :: proc(g: ^GUI, from: Widget_ID, forward: bool) -> Widget_ID {
	order := tab_order(g)
	defer delete(order)
	if len(order) == 0 { return INVALID_WIDGET_ID }

	at := -1
	for id, i in order {
		if id == from { at = int(i); break }
	}
	if at < 0 && from == INVALID_WIDGET_ID {
		//* Nothing has the focus yet, so the focus goes to the first
		//* widget of the tab order.
		return order[0]
	}
	if at < 0 {
		//* A widget that names the widget that comes after it is
		//* obeyed.
		if w := Widget_Get(g, from); w != nil {
			named := forward ? w.focus_next : w.focus_previous
			if named != INVALID_WIDGET_ID && can_focus_now(g, named) {
				return named
			}
		}
	}
	if at >= 0 {
		next_at := at + 1
		if !forward { next_at = at - 1 }
		if next_at < 0 { next_at = len(order) - 1 }
		if next_at >= len(order) { next_at = 0 }
		return order[next_at]
	}

	//* The widget that has the focus is not one of the widgets the tab
	//* key reaches: a text field, or a widget in a window of its own.
	//* The focus goes to the next widget of the tree that the tab key
	//* does reach.
	list: [dynamic]Widget_ID
	defer delete(list)
	focusable_widgets(g, &list)
	pos := -1
	for id, i in list {
		if id == from { pos = int(i); break }
	}
	if pos < 0 { return INVALID_WIDGET_ID }
	step := 1
	if !forward { step = -1 }
	index := pos + step
	for n := 0; n < len(list); n += 1 {
		if index < 0 { index = len(list) - 1 }
		if index >= len(list) { index = 0 }
		id := list[index]
		w := Widget_Get(g, id)
		if w != nil && w.focus_mode == .All { return id }
		index += step
	}
	return INVALID_WIDGET_ID
}

//* The widget the arrow keys move to. A widget that names its
//* neighbours is obeyed; the others are found by their place on the
//* screen.
focus_neighbour :: proc(g: ^GUI, from: Widget_ID, direction: int) -> Widget_ID {
	w := Widget_Get(g, from)
	if w == nil { return INVALID_WIDGET_ID }

	named := w.focus_neighbour[direction]
	if named != INVALID_WIDGET_ID {
		if n := Widget_Get(g, named); n != nil && can_focus_now(g, named) { return named }
	}

	//* The other way: the widget whose middle is the closest in that
	//* direction.
	list: [dynamic]Widget_ID
	defer delete(list)
	focusable_widgets(g, &list)

	best := INVALID_WIDGET_ID
	best_distance := f32(0)
	from_cx := w.rect.x + w.rect.w * 0.5
	from_cy := w.rect.y + w.rect.h * 0.5
	for id in list {
		if id == from { continue }
		//* A widget in a window of its own has a place of its own, so
		//* it is not a neighbour of anything in this window.
		if float_of(g, id) != FLOAT_NONE { continue }
		other := Widget_Get(g, id)
		if other == nil { continue }
		cx := other.rect.x + other.rect.w * 0.5
		cy := other.rect.y + other.rect.h * 0.5
		dx := cx - from_cx
		dy := cy - from_cy

		ok := false
		switch direction {
		case 0: ok = dx < -1
		case 1: ok = dy < -1
		case 2: ok = dx > 1
		case 3: ok = dy > 1
		}
		if !ok { continue }

		distance := dx * dx + dy * dy
		if best == INVALID_WIDGET_ID || distance < best_distance {
			best = id
			best_distance = distance
		}
	}
	return best
}

//* == The states of the widgets ==
//* The state of a widget follows the pointer and the keyboard: the
//* widget under the pointer is hovered, the widget that took the
//* pointer is pressed, and the widget that has the keyboard has the
//* focus.
widget_states_sync :: proc(
	g: ^GUI,
	old_hot, old_active, old_focused, hot, active, focused: Widget_ID,
) {
	ids := [6]Widget_ID{old_hot, old_active, old_focused, hot, active, focused}
	for id in ids {
		if id == INVALID_WIDGET_ID { continue }
		w := Widget_Get(g, id)
		if w == nil { continue }
		if g.hot == id {
			w.state += Widget_State{.Hovered}
		} else {
			w.state -= Widget_State{.Hovered}
		}
		if g.active == id {
			w.state += Widget_State{.Pressed}
		} else {
			w.state -= Widget_State{.Pressed}
		}
		if g.focused == id {
			w.state += Widget_State{.Focused}
		} else {
			w.state -= Widget_State{.Focused}
		}
	}
}

//* == The tooltip ==
//* The widget under the pointer that has a tooltip. A widget that is
//* not enabled does not take the mouse, but it still says what it is.
tooltip_of :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> Widget_ID {
	hits: [dynamic]Widget_ID
	defer delete(hits)
	collect_hits_any(g, id, p, &hits)
	for h in hits {
		w := Widget_Get(g, h)
		if w == nil { continue }
		if w.tooltip_text != "" { return h }
	}
	return INVALID_WIDGET_ID
}

//* == The order of the drawing ==
//* The widgets of a branch, sorted by the number they have in the
//* order of the drawing. The order of the tree breaks the tie.

z_sorted_children :: proc(g: ^GUI, w: ^Widget, out: ^[dynamic]Widget_ID) {
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		append(out, child)
		child = c.next_sibling
	}
	//* An insertion sort: the list is short, and it keeps the order of
	//* the tree for the widgets with the same number.
	for i in 1 ..< len(out^) {
		id := out^[i]
		key := Widget_Get(g, id)
		if key == nil { continue }
		j := i - 1
		for j >= 0 {
			other := Widget_Get(g, out^[j])
			if other == nil { break }
			if other.z_index <= key.z_index { break }
			out^[j + 1] = out^[j]
			j -= 1
		}
		out^[j + 1] = id
	}
}
