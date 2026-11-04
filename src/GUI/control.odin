//* == The control features ==
//* The things every Control of Godot has: the mouse filter, the focus,
//* the size flags, the clip, the tooltip, the transform and the order
//* the widgets are drawn in.
//
//* They live on the widget itself, so a program can reach them without
//* going through a setter: the widget is a struct and the fields are
//* there.

package GUI

//* == The mouse ==

//* Every widget under a point, from the topmost one down. The children
//* of a widget are drawn on top of it, so they are looked at first.
collect_hits :: proc(g: ^GUI, id: Widget_ID, p: Vec2, out: ^[dynamic]Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !(.Visible in w.state) { return }
	if !rect_contains(w.rect, p.x, p.y) { return }

	child := w.last_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		collect_hits(g, child, p, out)
		child = c.prev_sibling
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

//* == The focus ==

//* True when the widget can be given the keyboard focus.
can_focus :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	if w.focus_mode == .None { return false }
	if !(.Visible in w.state) { return false }
	if !(.Enabled in w.state) { return false }
	return true
}

//* Gives the keyboard focus to a widget. The widget that had it loses
//* it, and both of them say so through their signals.
focus_set :: proc(g: ^GUI, id: Widget_ID) {
	if id == g.focused { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if !can_focus(w) { return }

	old := g.focused
	g.focused = id
	if old != INVALID_WIDGET_ID {
		signal_focus_exited(g, old)
		text_input_blur(g, old)
	}
	signal_focus_entered(g, id)
}

//* Takes the keyboard focus away from whatever has it.
focus_clear :: proc(g: ^GUI) {
	if g.focused == INVALID_WIDGET_ID { return }
	old := g.focused
	g.focused = INVALID_WIDGET_ID
	signal_focus_exited(g, old)
	text_input_blur(g, old)
}

//* Every widget that can be focused, in the order of the tab key. The
//* tab index comes first, and the order of the tree breaks the tie.
focusable_widgets :: proc(g: ^GUI, out: ^[dynamic]Widget_ID) {
	focus_walk(g, g.root, out)
}

//* Walks the tree and gathers the widgets that can be focused.
focus_walk :: proc(g: ^GUI, id: Widget_ID, out: ^[dynamic]Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if can_focus(w) { append(out, id) }
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		focus_walk(g, child, out)
		child = c.next_sibling
	}
}

//* The widget the tab key moves to. The widgets are sorted by their tab
//* index, and the order of the tree breaks the tie.
focus_next :: proc(g: ^GUI, from: Widget_ID, forward: bool) -> Widget_ID {
	list: [dynamic]Widget_ID
	defer delete(list)
	focusable_widgets(g, &list)
	if len(list) == 0 { return INVALID_WIDGET_ID }

	//* The order of the list is the order of the tree. The tab index
	//* moves a widget up or down in it.
	sorted := make([dynamic]Widget_ID, 0, len(list), context.allocator)
	defer delete(sorted)
	for id in list { append(&sorted, id) }
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

	if from == INVALID_WIDGET_ID {
		return sorted[0]
	}
	at := -1
	for id, i in sorted {
		if id == from { at = int(i); break }
	}
	if at < 0 { return sorted[0] }
	next_at := at + 1
	if !forward { next_at = at - 1 }
	if next_at < 0 { next_at = len(sorted) - 1 }
	if next_at >= len(sorted) { next_at = 0 }
	return sorted[next_at]
}

//* The widget the arrow keys move to. A widget that names its
//* neighbours is obeyed; the others are found by their place on the
//* screen.
focus_neighbour :: proc(g: ^GUI, from: Widget_ID, direction: int) -> Widget_ID {
	w := Widget_Get(g, from)
	if w == nil { return INVALID_WIDGET_ID }

	//* The widget that names the neighbour wins.
	named := w.focus_neighbour[direction]
	if named != INVALID_WIDGET_ID {
		if n := Widget_Get(g, named); n != nil && can_focus(n) { return named }
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
		other := Widget_Get(g, id)
		if other == nil { continue }
		cx := other.rect.x + other.rect.w * 0.5
		cy := other.rect.y + other.rect.h * 0.5
		dx := cx - from_cx
		dy := cy - from_cy

		//* The neighbour has to be in that direction.
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

//* == The tooltip ==
//* The widget under the pointer that has a tooltip.

tooltip_of :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> Widget_ID {
	hits: [dynamic]Widget_ID
	defer delete(hits)
	collect_hits(g, id, p, &hits)
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
