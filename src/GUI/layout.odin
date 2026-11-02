package GUI

//* Text widgets grow to fit their text. This runs before the layout pass
//* so the parent already sees the right minimum size.
measure_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID { return }
	measure_node(g, g.root)
}

measure_node :: proc(g: ^GUI, id: Widget_ID) {
	w := widget_get(g, id)
	if w == nil { return }

	text := ""
	#partial switch d in w.data {
	case Label_Data:
		text = d.text
	case Button_Data:
		text = d.text
	case Text_Input_Data:
		text = d.text
	}
	style := resolved_style(g, w)
	if text != "" {
		//* The text is measured as it is drawn, so a text that is
		//* transformed takes the room of the transformed text.
		size := text_measure(g, style.text, text, 0)
		if style.text.wrap != .Off {
			//* A text that wraps only has to be as wide as its
			//* longest word: the rest of it fits on the lines below.
			font := font_resolve(g, style.text)
			src := apply_text_transform(g, style.text, text)
			size.x = longest_word_width(g, font, src)
		}
		pad := style.padding
		w.min_size.x = max(w.min_size.x, size.x + pad[0] + pad[2])
		w.min_size.y = max(w.min_size.y, size.y + pad[1] + pad[3])
	}

	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		measure_node(g, child)
		child = c.next_sibling
	}
}

//* The width of the longest word in the text.
longest_word_width :: proc(g: ^GUI, font: Font_ID, text: string) -> f32 {
	widest := f32(0)
	start := 0
	for i in 0 ..= len(text) {
		if i < len(text) && text[i] != ' ' { continue }
		if i > start {
			w := font_measure(g, font, text[start:i]).x
			if w > widest { widest = w }
		}
		start = i + 1
	}
	return widest
}

//* Lays the tree out. Measuring (text sizes) happens first so the
//* parents already see the right minimum sizes.
layout_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID { return }
	measure_pass(g)
	if !g.layout_dirty { return }
	layout_node(g, g.root, g.viewport, g.viewport)
	//* A floating panel is a window of its own, so it is laid out in
	//* its own space.
	for &f in g.floats {
		rect := Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}
		layout_node(g, f.widget, rect, rect)
	}
	g.layout_dirty = false
}

layout_node :: proc(g: ^GUI, id: Widget_ID, rect, clip: Rect) {
	w := widget_get(g, id)
	if w == nil { return }
	//* A tab that is not showing keeps no geometry.
	if is_hidden_tab(g, id) {
		w.rect = Rect{}
		w.clip = Rect{}
		return
	}
	//* A widget being dragged has left its slot: it is drawn as a
	//* floating ghost and no longer takes part in the layout. A panel
	//* that is a window of its own keeps its place: the window moves.
	if g.drag.active && id == g.drag.widget && g.drag.float_index < 0 {
		w.rect = Rect{}
		w.clip = Rect{}
		return
	}

	w.rect = rect
	w.clip = rect_intersect(clip, rect)

	#partial switch w.type {
	case .Split:
		layout_split(g, w, rect)
	case .Tabs:
		layout_tabs(g, w, rect)
	case .VBox, .HBox:
		layout_box(g, w, rect)
	case:
		// A plain control positions its children by anchors.
		child := w.first_child
		for child != INVALID_WIDGET_ID {
			c := widget_get(g, child)
			if c == nil { break }
			child_rect := resolve_rect(rect, c.anchors, c.offsets, c.min_size, c.grow_h, c.grow_v)
			layout_node(g, child, child_rect, w.clip)
			child = c.next_sibling
		}
	}
}

//* A VBox / HBox stacks its children along one axis. Every child gets
//* its minimum size on that axis plus a share of the leftover space,
//* weighted. A child that was pulled to a size keeps that size, and
//* takes it out of the space the others share.
layout_box :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	vertical := w.type == .VBox
	horizontal := !vertical
	sep := w.separation

	// First pass: minimum sizes and weights.
	total_weight := f32(0)
	total_min := f32(0)
	count := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		if keeps_size(c, horizontal) {
			total_min += manual_size_of(c, horizontal)
		} else {
			total_min += (vertical ? c.min_size.y : c.min_size.x)
			total_weight += c.weight
		}
		count += 1
		child = c.next_sibling
	}
	if total_weight <= 0 { total_weight = 1 }
	if count == 0 { return }

	available := (vertical ? rect.h : rect.w) - total_min - sep * f32(count - 1)
	if available < 0 { available = 0 }

	offset := vertical ? rect.y : rect.x
	child = w.first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		size := f32(0)
		if keeps_size(c, horizontal) {
			size = manual_size_of(c, horizontal)
		} else {
			min_size := vertical ? c.min_size.y : c.min_size.x
			size = min_size + available * (c.weight / total_weight)
		}
		if vertical {
			layout_node(g, child, Rect{x = rect.x, y = offset, w = rect.w, h = size}, w.clip)
			offset += size + sep
		} else {
			layout_node(g, child, Rect{x = offset, y = rect.y, w = size, h = rect.h}, w.clip)
			offset += size + sep
		}
		child = c.next_sibling
	}
}

//* A Split divides its rect among its children along one axis, weighted.
//* A child with weight 0 keeps its minimum size and takes no share.
//* A child that was pulled to a size keeps that size, and takes it out
//* of the space the others share.
layout_split :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	dir := Split_Direction.Horizontal
	#partial switch d in w.data {
	case Split_Data:
		dir = d.direction
	}
	horizontal := dir == .Horizontal

	total_weight := f32(0)
	total_min := f32(0)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		if keeps_size(c, horizontal) {
			total_min += manual_size_of(c, horizontal)
		} else {
			total_min += horizontal ? c.min_size.x : c.min_size.y
			total_weight += c.weight
		}
		child = c.next_sibling
	}
	if total_weight <= 0 { total_weight = 1 }

	available := (horizontal ? rect.w : rect.h) - total_min
	if available < 0 { available = 0 }

	offset := horizontal ? rect.x : rect.y
	child = w.first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		size := f32(0)
		if keeps_size(c, horizontal) {
			size = manual_size_of(c, horizontal)
		} else {
			size = (horizontal ? c.min_size.x : c.min_size.y) + available * (c.weight / total_weight)
		}
		if horizontal {
			layout_node(g, child, Rect{x = offset, y = rect.y, w = size, h = rect.h}, w.clip)
			offset += size
		} else {
			layout_node(g, child, Rect{x = rect.x, y = offset, w = rect.w, h = size}, w.clip)
			offset += size
		}
		child = c.next_sibling
	}
}

//* A Tabs shows one child at a time. The strip of buttons sits at the
//* top of the node and the active tab fills the rest of it. A tab that
//* is not showing keeps no geometry, so it is neither drawn nor hit.
layout_tabs :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	active := tabs_active(w)
	content := tabs_content_rect(w)

	child := w.first_child
	index := 0
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		if index == active {
			layout_node(g, child, content, w.clip)
		} else {
			c.rect = Rect{}
			c.clip = Rect{}
		}
		index += 1
		child = c.next_sibling
	}
}

//* Resolve a widget's rect from its parent's rect (Godot's Control maths).
resolve_rect :: proc(parent: Rect, anchors: Anchor, offsets: Offset, min_size: Vec2, grow_h, grow_v: Grow) -> Rect {
	left   := parent.x + parent.w * anchors.left   + offsets.left
	top    := parent.y + parent.h * anchors.top    + offsets.top
	right  := parent.x + parent.w * anchors.right  + offsets.right
	bottom := parent.y + parent.h * anchors.bottom + offsets.bottom

	w := right - left
	h := bottom - top

	if w < min_size.x {
		d := min_size.x - w
		switch grow_h {
		case .Begin: left -= d
		case .End:   right += d
		case .Both:  left -= d * 0.5; right += d * 0.5
		}
		w = min_size.x
	}
	if h < min_size.y {
		d := min_size.y - h
		switch grow_v {
		case .Begin: top -= d
		case .End:   bottom += d
		case .Both:  top -= d * 0.5; bottom += d * 0.5
		}
		h = min_size.y
	}
	return Rect{x = left, y = top, w = w, h = h}
}
