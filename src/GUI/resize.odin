package GUI

//* == Resizing ==
//* A dockable panel can be resized by pulling on its edges or on its
//* corners. A pull moves the edge that was grabbed: the panel gives
//* the space to the neighbour on the far side of that edge, and the
//* neighbour takes it back when the edge moves the other way.
//*
//* When there is no neighbour on the far side, the edge of the
//* container moves instead, and the container changes size in its own
//* parent. A panel that is in a tab host is the content of that host,
//* so the host is what changes size.

//* The width of the band around a panel that a pull can grab.
RESIZE_GRIP :: 6

RESIZE_MIN_SIZE :: 24

//* True when the panel has a title bar of its own. A panel that lives
//* in a tab strip is titled by its tab, so it has none.
has_header_of :: proc(g: ^GUI, w: ^Widget) -> bool {
	return w.draggable && !is_tab_child(g, w.id)
}

//* The edges of a panel a pull can grab. The title bar of a panel
//* belongs to the drag that moves it, so it is not a grip.
resize_grip :: proc(g: ^GUI, w: ^Widget, p: Vec2) -> Resize_Edges {
	edges := Resize_Edges{}
	r := w.rect
	if r.w <= 0 || r.h <= 0 {return edges}
	if !rect_contains(r, p.x, p.y) {return edges}

	if has_header_of(g, w) && p.y < r.y + HEADER_HEIGHT {return edges}

	if r.w > RESIZE_GRIP * 2 {
		if p.x - r.x <= RESIZE_GRIP {edges += Resize_Edges{.Left}}
		if r.x + r.w - p.x <= RESIZE_GRIP {edges += Resize_Edges{.Right}}
	}
	if r.h > RESIZE_GRIP * 2 {
		if p.y - r.y <= RESIZE_GRIP {edges += Resize_Edges{.Top}}
		if r.y + r.h - p.y <= RESIZE_GRIP {edges += Resize_Edges{.Bottom}}
	}
	return edges
}

//* The panel whose grip is under the pointer, and the edges it holds.
find_resize_grip :: proc(g: ^GUI, global: Vec2) -> (id: Widget_ID, edges: Resize_Edges) {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local := Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		id, edges = resize_grip_in(g, f.widget, local)
		if id != INVALID_WIDGET_ID {return}
	}
	local := main_window_pos(g, global)
	return resize_grip_in(g, g.root, local)
}

//* The deepest panel with a grip under the pointer. The children are
//* on top of their parent, so they are looked at first.
resize_grip_in :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> (Widget_ID, Resize_Edges) {
	w := Widget_Get(g, id)
	if w == nil {return INVALID_WIDGET_ID, Resize_Edges{}}
	if !(.Visible in w.state) {return INVALID_WIDGET_ID, Resize_Edges{}}

	child := w.last_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		hit, edges := resize_grip_in(g, child, p)
		if hit != INVALID_WIDGET_ID {return hit, edges}
		child = c.prev_sibling
	}

	if !w.draggable {return INVALID_WIDGET_ID, Resize_Edges{}}

	edges := resize_grip(g, w, p)
	if edges == (Resize_Edges{}) {return INVALID_WIDGET_ID, Resize_Edges{}}
	return id, edges
}

//* True when the panel keeps the size it was pulled to, instead of
//* taking a share of the space of its parent.
keeps_size :: proc(w: ^Widget, horizontal: bool) -> bool {
	return horizontal ? w.manual_w : w.manual_h
}

//* The size a panel was pulled to, in pixels.
manual_size_of :: proc(w: ^Widget, horizontal: bool) -> f32 {
	return horizontal ? w.manual_size.x : w.manual_size.y
}

//* The size a panel takes along an axis. A size the user pulled into
//* place wins over the one the layout gives it.
size_of :: proc(w: ^Widget, horizontal: bool) -> f32 {
	if keeps_size(w, horizontal) {return manual_size_of(w, horizontal)}
	return horizontal ? w.rect.w : w.rect.h
}

//* The smallest size a panel can be pulled to.
min_size_of :: proc(w: ^Widget, horizontal: bool) -> f32 {
	return horizontal ? w.min_size.x : w.min_size.y
}

//* Keeps the size a panel was pulled to. The size is never smaller
//* than the minimum of the panel.
keep_size :: proc(g: ^GUI, w: ^Widget, horizontal: bool, size: f32) {
	sized := max(size, min_size_of(w, horizontal))
	if horizontal {
		w.manual_w = true
		w.manual_size.x = sized
	} else {
		w.manual_h = true
		w.manual_size.y = sized
	}
	invalidate(g, w.id, Dirty_Flags{.Arrange, .Hit})
}

//* The resize that is not running. The index of the floating panel is
//* FLOAT_NONE, so that a resize that is not running does not point at
//* the first floating panel.
resize_state_none :: proc() -> Resize_State {
	return Resize_State{float_index = FLOAT_NONE}
}

//* Starts a resize. The edges that were grabbed follow the pointer.
resize_begin :: proc(g: ^GUI, id: Widget_ID, edges: Resize_Edges, global: Vec2) {
	g.resize.active = true
	g.resize.widget = id
	g.resize.edges = edges
	g.resize.origin = global
	g.resize.last = global
	g.resize.float_index = float_of(g, id)
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

resize_update :: proc(g: ^GUI, global: Vec2) {
	if !g.resize.active {return}
	dx := global.x - g.resize.last.x
	dy := global.y - g.resize.last.y
	g.resize.last = global
	if dx == 0 && dy == 0 {return}

	edges := g.resize.edges
	dl, dr, dt, db := f32(0), f32(0), f32(0), f32(0)
	if .Left in edges {dl = dx}
	if .Right in edges {dr = dx}
	if .Top in edges {dt = dy}
	if .Bottom in edges {db = dy}

	if g.resize.float_index >= 0 {
		resize_float(g, g.resize.float_index, dl, dt, dr, db)
	} else {
		resize_widget(g, g.resize.widget, dl, dt, dr, db)
	}
	invalidate(g, g.resize.widget, Dirty_Flags{.Arrange, .Hit})
}

resize_end :: proc(g: ^GUI) {
	if !g.resize.active {
		g.resize = resize_state_none()
		return
	}
	id := g.resize.widget
	size := Vec2{}
	if g.resize.float_index >= 0 && g.resize.float_index < len(g.floats) {
		size = g.floats[g.resize.float_index].size
	} else {
		w := Widget_Get(g, id)
		if w != nil {size = Vec2{w.manual_size.x, w.manual_size.y}}
	}
	g.resize = resize_state_none()
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
	signal_resized(g, id, size)
}

//* Gives up on the resize. The panel keeps the size it has now, the
//* same way it does when the mouse comes up.
resize_cancel :: proc(g: ^GUI) {
	resize_end(g)
}

//* The axis a split or a box divides its children along. A split
//* takes its direction from its own data, a box from its type.
container_horizontal :: proc(p: ^Widget) -> bool {
	#partial switch p.type {
	case .VBox:
		return false
	case .HBox:
		return true
	case .Split:
		return split_direction(p) == .Horizontal
	case:
		return true
	}
}

//* Moves the edges of a panel. The deltas are how far each edge
//* moves: a positive value moves it right or down.
resize_widget :: proc(g: ^GUI, id: Widget_ID, dl, dt, dr, db: f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	p := Widget_Get(g, w.parent)
	if p == nil {return}

	#partial switch p.type {
	case .Split, .VBox, .HBox:
		horizontal := container_horizontal(p)
		if horizontal {
			resize_in_container(g, p, w, true, dl, dr)
			if dt != 0 || db != 0 {resize_widget(g, p.id, 0, dt, 0, db)}
		} else {
			resize_in_container(g, p, w, false, dt, db)
			if dl != 0 || dr != 0 {resize_widget(g, p.id, dl, 0, dr, 0)}
		}
	case .Tabs:
		resize_widget(g, p.id, dl, dt, dr, db)
	case:
		resize_by_offset(g, w, dl, dt, dr, db)
	}
	invalidate(g, w.id, Dirty_Flags{.Arrange, .Hit})
}

//* Moves the edges of a panel that is placed by anchors. Only the
//* edges that were grabbed move: the others stay where they are.
resize_by_offset :: proc(g: ^GUI, w: ^Widget, dl_in, dt_in, dr_in, db_in: f32) {
	//* A panel cannot get smaller than its minimum, so an edge that
	//* is pulled stops when the panel is at its smallest.
	dl, dr := dl_in, dr_in
	dt, db := dt_in, db_in

	room_w := w.rect.w - w.min_size.x
	room_h := w.rect.h - w.min_size.y

	if dl > 0 && dl > room_w {dl = room_w}
	if dr < 0 && -dr > room_w {dr = -room_w}
	if dt > 0 && dt > room_h {dt = room_h}
	if db < 0 && -db > room_h {db = -room_h}

	w.offsets.left += dl
	w.offsets.right += dr
	w.offsets.top += dt
	w.offsets.bottom += db
	invalidate(g, w.id, Dirty_Flags{.Arrange, .Hit})
}


resize_in_container :: proc(g: ^GUI, p: ^Widget, w: ^Widget, horizontal: bool, d_neg, d_pos: f32) {
	if d_neg != 0 {
		prev := Widget_Get(g, w.prev_sibling)
		change := d_neg
		if change > 0 {
			change = min(change, size_of(w, horizontal) - min_size_of(w, horizontal))
		} else if prev != nil {
			change = max(change, min_size_of(prev, horizontal) - size_of(prev, horizontal))
		}

		if prev == nil {
			if horizontal {
				resize_widget(g, p.id, change, 0, 0, 0)
			} else {
				resize_widget(g, p.id, 0, change, 0, 0)
			}
		} else {
			keep_size(g, prev, horizontal, size_of(prev, horizontal) + change)
		}
		keep_size(g, w, horizontal, size_of(w, horizontal) - change)
	}

	if d_pos != 0 {
		next := Widget_Get(g, w.next_sibling)
		change := d_pos
		if change > 0 {
			if next != nil {
				change = min(change, size_of(next, horizontal) - min_size_of(next, horizontal))
			}
		} else {
			//* The panel narrows: it cannot go below its minimum.
			change = max(change, min_size_of(w, horizontal) - size_of(w, horizontal))
		}

		if next == nil {
			//* There is no child after this one: the edge of the container moves.
			if horizontal {
				resize_widget(g, p.id, 0, 0, change, 0)
			} else {
				resize_widget(g, p.id, 0, 0, 0, change)
			}
		} else {
			keep_size(g, next, horizontal, size_of(next, horizontal) - change)
		}
		keep_size(g, w, horizontal, size_of(w, horizontal) + change)
	}
}

//* Resizes a floating panel. The panel has a window of its own, so
//* the window is what changes size. An edge that is pulled moves the
//* window with it, so the opposite edge stays where it is.
resize_float :: proc(g: ^GUI, index: int, dl_in, dt_in, dr_in, db_in: f32) {
	if index < 0 || index >= len(g.floats) {return}
	f := &g.floats[index]
	w := Widget_Get(g, f.widget)

	minimum := Vec2{RESIZE_MIN_SIZE, RESIZE_MIN_SIZE}
	if w != nil {
		minimum.x = max(minimum.x, w.min_size.x)
		minimum.y = max(minimum.y, w.min_size.y)
	}

	dl, dr := dl_in, dr_in
	dt, db := dt_in, db_in
	if dl != 0 && f.size.x - dl < minimum.x {dl = f.size.x - minimum.x}
	if dr != 0 && f.size.x + dr < minimum.x {dr = minimum.x - f.size.x}
	if dt != 0 && f.size.y - dt < minimum.y {dt = f.size.y - minimum.y}
	if db != 0 && f.size.y + db < minimum.y {db = minimum.y - f.size.y}

	f.pos.x += dl
	f.pos.y += dt
	f.size.x += dr - dl
	f.size.y += db - dt
}

//* The grip under the pointer, and the cursor that goes with it. The
//* cursor is what tells the user that the edge can be pulled.
update_resize_hover :: proc(g: ^GUI) {
	g.resize_hover = INVALID_WIDGET_ID
	g.resize_hover_edges = Resize_Edges{}
	g.cursor = .Default
	if g.resize.active {
		//* The panel that is being resized keeps its grip marked.
		g.resize_hover = g.resize.widget
		g.resize_hover_edges = g.resize.edges
		return
	}

	//* The floating panels are looked at first: they are windows of
	//* their own and can be outside of the main window.
	id, edges := find_resize_grip(g, g.global_pointer)
	if id == INVALID_WIDGET_ID {return}
	g.resize_hover = id
	g.resize_hover_edges = edges
	g.cursor = cursor_of(edges)
}

cursor_of :: proc(edges: Resize_Edges) -> Cursor {
	horizontal := .Left in edges || .Right in edges
	vertical := .Top in edges || .Bottom in edges
	switch {
	case horizontal && vertical:
		if .Top in edges {
			return .Left in edges ? .Resize_NW : .Resize_NE
		}
		return .Left in edges ? .Resize_SW : .Resize_SE
	case horizontal:
		return .Left in edges ? .Resize_W : .Resize_E
	case vertical:
		return .Top in edges ? .Resize_N : .Resize_S
	}
	return .Default
}
