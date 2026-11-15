package Core
collect_hits :: proc(g: ^GUI, id: Widget_ID, p: Vec2, out: ^[dynamic]Widget_ID) {
	collect_hits_with(g, id, p, out, true)
}

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
	base, count := children_begin_sorted(g, w)
	defer children_end(g, base)
	for i := count - 1; i >= 0; i -= 1 {
		child := g.children_scratch[base + i]
		if Widget_Get(g, child) == nil { continue }
		collect_hits_with(g, child, p, out, skip_disabled)
	}
	append(out, id)
}

hit_test :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> Widget_ID {
	clear(&g.hit_scratch)
	collect_hits(g, id, p, &g.hit_scratch)
	for h in g.hit_scratch {
		w := Widget_Get(g, h)
		if w == nil { continue }
		if w.mouse_filter != .Ignore { return h }
	}
	return INVALID_WIDGET_ID
}

hits_that_take_the_mouse :: proc(g: ^GUI, id: Widget_ID, p: Vec2, out: ^[dynamic]Widget_ID) {
	clear(&g.hit_scratch)
	collect_hits(g, id, p, &g.hit_scratch)
	for h in g.hit_scratch {
		w := Widget_Get(g, h)
		if w == nil { continue }
		if w.mouse_filter == .Ignore { continue }
		append(out, h)
		if w.mouse_filter == .Stop { return }
	}
}

wheel_chain :: proc(g: ^GUI, global: Vec2) -> (chain: []Widget_ID, local: Vec2) {
	clear(&g.chain_scratch)
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local = Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		collect_hits(g, f.widget, local, &g.chain_scratch)
		if len(g.chain_scratch) > 0 { return g.chain_scratch[:], local }
	}
	local = main_window_pos(g, global)
	collect_hits(g, g.root, local, &g.chain_scratch)
	return g.chain_scratch[:], local
}

can_focus :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	if w.freeing { return false }
	if w.focus_mode == .None { return false }
	if !(.Visible in w.state) { return false }
	if !(.Enabled in w.state) { return false }
	return true
}

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

focus_set :: proc(g: ^GUI, id: Widget_ID) {
	if id == g.focused { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if !can_focus_now(g, id) { return }

	old := g.focused
	g.focused = id
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

focus_release :: proc(g: ^GUI) {
	if g.focused == INVALID_WIDGET_ID { return }
	if can_focus_now(g, g.focused) { return }
	focus_clear(g)
}

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
		next := c.next_sibling
		focus_walk(g, child, out)
		child = next
	}
}

tab_order :: proc(g: ^GUI) -> [dynamic]Widget_ID {
	list: [dynamic]Widget_ID
	defer delete(list)
	focusable_widgets(g, &list)

	sorted := make([dynamic]Widget_ID, 0, len(list), context.allocator)
	for id in list {
		w := Widget_Get(g, id)
		if w == nil { continue }
		if w.focus_mode != .All { continue }
		append(&sorted, id)
	}
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

focus_next :: proc(g: ^GUI, from: Widget_ID, forward: bool) -> Widget_ID {
	order := tab_order(g)
	defer delete(order)
	if len(order) == 0 { return INVALID_WIDGET_ID }

	at := -1
	for id, i in order {
		if id == from { at = int(i); break }
	}
	if at < 0 && from == INVALID_WIDGET_ID {
		return order[0]
	}
	if at < 0 {
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


focus_neighbour :: proc(g: ^GUI, from: Widget_ID, direction: int) -> Widget_ID {
	w := Widget_Get(g, from)
	if w == nil { return INVALID_WIDGET_ID }

	named := w.focus_neighbour[direction]
	if named != INVALID_WIDGET_ID {
		if n := Widget_Get(g, named); n != nil && can_focus_now(g, named) { return named }
	}

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

tooltip_of :: proc(g: ^GUI, global: Vec2) -> Widget_ID {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local := Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		found, blocked := tooltip_of_branch(g, f.widget, local)
		if found != INVALID_WIDGET_ID { return found }
		if blocked { return INVALID_WIDGET_ID }
	}
	local := main_window_pos(g, global)
	found, _ := tooltip_of_branch(g, g.root, local)
	return found
}

//* Search stops at a widget with
//* the filter .Stop, so a tooltip from behind an opaque widget never
//* comes up.
@(private)
tooltip_of_branch :: proc(g: ^GUI, root: Widget_ID, p: Vec2) -> (found: Widget_ID, blocked: bool) {
	clear(&g.hit_scratch)
	collect_hits_with(g, root, p, &g.hit_scratch, false)

	for h in g.hit_scratch {
		w := Widget_Get(g, h)
		if w == nil { continue }
		if w.mouse_filter == .Ignore { continue }

		//* The nearest widget of the branch that says what it is.
		cur := h
		for cur != INVALID_WIDGET_ID {
			c := Widget_Get(g, cur)
			if c == nil { break }
			if c.tooltip_text != "" { return cur, false }
			cur = c.parent
		}

		//* Nothing on the branch has a tooltip. The search goes on only
		//* when the branch lets the pointer through.
		cur = h
		for cur != INVALID_WIDGET_ID {
			c := Widget_Get(g, cur)
			if c == nil { break }
			if c.mouse_filter == .Stop { return INVALID_WIDGET_ID, true }
			cur = c.parent
		}
	}
	return INVALID_WIDGET_ID, false
}
