//* The storage that the hot paths reuse. The arrays live in the GUI and
//* are used as stacks: a walk remembers the length it found, appends its
//* own entries, and cuts the array back to that length when it returns.
//*
//* A nested walk appends above its parent, so the entries of the parent
//* stay where they are. A walk reads its entries by index rather than
//* keeping a slice, because a nested walk can grow the backing array and
//* move it: the index is always read through the array of the GUI again.
package GUI

//* Starts a snapshot of the children of a widget. Returns the length the
//* stack had before the snapshot, and how many children were added.
children_begin :: proc(g: ^GUI, w: ^Widget) -> (base, count: int) {
	if g == nil || w == nil {return}
	base = len(g.children_scratch)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		append(&g.children_scratch, child)
		child = c.next_sibling
	}
	return base, len(g.children_scratch) - base
}

//* Like `children_begin`, but leaves the absolute children out. A
//* container that puts its children in cells of its own wants only the
//* children that take part in the flow.
children_begin_flow :: proc(g: ^GUI, w: ^Widget) -> (base, count: int) {
	if g == nil || w == nil {return}
	base = len(g.children_scratch)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		if !c.absolute {append(&g.children_scratch, child)}
		child = c.next_sibling
	}
	return base, len(g.children_scratch) - base
}

//* Starts a snapshot of the children of a widget in drawing order: the
//* children sorted by their z index, with the order of the tree kept for
//* the ones that have the same number.
children_begin_sorted :: proc(g: ^GUI, w: ^Widget) -> (base, count: int) {
	base, count = children_begin(g, w)
	for i in 1 ..< count {
		id := g.children_scratch[base + i]
		key := Widget_Get(g, id)
		j := i - 1
		for j >= 0 {
			other := Widget_Get(g, g.children_scratch[base + j])
			if other == nil {break}
			if other.z_index <= key.z_index {break}
			g.children_scratch[base + j + 1] = g.children_scratch[base + j]
			j -= 1
		}
		g.children_scratch[base + j + 1] = id
	}
	return
}

//* Gives the children snapshot back.
children_end :: proc(g: ^GUI, base: int) {
	if g == nil {return}
	length := clamp(base, 0, len(g.children_scratch))
	resize(&g.children_scratch, length)
}

//* Starts a stack of numbers in the float scratch. The room of the
//* children of a container and the tracks of a grid are kept there.
floats_begin :: proc(g: ^GUI, count: int) -> int {
	if g == nil {return 0}
	base := len(g.float_scratch)
	if count <= 0 {return base}
	resize(&g.float_scratch, base + count)
	for i in base ..< base + count {
		g.float_scratch[i] = 0
	}
	return base
}

//* Gives a stack of numbers back.
floats_end :: proc(g: ^GUI, base: int) {
	if g == nil {return}
	length := clamp(base, 0, len(g.float_scratch))
	resize(&g.float_scratch, length)
}

//* Copies the connections of a signal into the signal scratch, so that a
//* callback that connects or breaks a connection does not change the
//* ones that are called by the emission that is running.
signal_matches_begin :: proc(g: ^GUI, id: Widget_ID, name: string) -> (base, count: int) {
	if g == nil {return}
	base = len(g.signal_scratch)
	for entry in g.signal_conns {
		if entry.id != id {continue}
		if entry.conn.name != name {continue}
		append(&g.signal_scratch, entry.conn)
	}
	return base, len(g.signal_scratch) - base
}

//* Gives the copied connections back.
signal_matches_end :: proc(g: ^GUI, base: int) {
	if g == nil {return}
	length := clamp(base, 0, len(g.signal_scratch))
	resize(&g.signal_scratch, length)
}
