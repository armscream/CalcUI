package GUI

//* == The layout pass ==
//* The tree is laid out every frame. A layout that is only done when
//* something changed goes stale as soon as the data of a widget
//* changes, and the data of a widget changes at runtime: a label gets
//* a new text, a list gets a new row, a slider is moved.
//
//* The tree is walked every frame, but the work is only done where
//* something changed. Every change says what it made stale (see
//* invalidation.odin), and the measure pass and the layout pass leave
//* the branches alone that nothing happened to. A change that goes
//* around the setters asks for the whole tree to be done again, so
//* nothing is ever left stale.
//
//* A widget of a container kind gets its children laid out by the
//* container: a box stacks them, a split divides its space among them,
//* a grid puts them in rows and columns. Every other widget places its
//* children by their anchors.

//* Text widgets grow to fit their text. This runs before the layout pass
//* so the parent already sees the right minimum size.
measure_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID {return}
	measure_node(g, g.root)
}

measure_node :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	//* Nothing under this widget changed: the sizes are the ones they
	//* were, and they are right.
	if !(.Measure in w.subtree_dirty) {return}

	//* The size of the widget is only worked out again when the widget
	//* itself changed. A child that changed does not change the size of
	//* its parent: in CalcUI a container does not add up the sizes of
	//* its children.
	if .Measure in w.dirty {
		measure_widget(g, w)
		g.measured_count += 1
		w.dirty -= Dirty_Flags{.Measure}
	}

	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		measure_node(g, child)
		child = c.next_sibling
	}
	w.subtree_dirty -= Dirty_Flags{.Measure}
}

//* Works out the smallest size of a widget: the size the program asked
//* for, the size of its text and the size the program insists on. The
//* size of the text is added to the padding of the style of the widget,
//* so a widget with a text is as big as its text and its padding.
measure_widget :: proc(g: ^GUI, w: ^Widget) {
	text := ""
	#partial switch d in w.data {
	case Label_Data:
		text = d.text
	case Button_Data:
		text = d.text
	case Text_Input_Data:
		text = d.text
	case Check_Box_Data:
		text = d.text
	case Link_Button_Data:
		text = d.text
	case Menu_Button_Data:
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
			font := Font_Resolve(g, style.text)
			src := apply_text_transform(g, style.text, text)
			size.x = longest_word_width(g, font, src)
		}
		pad := style.box.content_margin
		w.min_size.x = max(w.base_min_size.x, size.x + pad[0] + pad[2])
		w.min_size.y = max(w.base_min_size.y, size.y + pad[1] + pad[3])
	} else {
		w.min_size.x = w.base_min_size.x
		w.min_size.y = w.base_min_size.y
	}

	//* A widget can ask for a size of its own.
	w.min_size.x = max(w.min_size.x, w.custom_min_size.x)
	w.min_size.y = max(w.min_size.y, w.custom_min_size.y)

	//* A class can ask for a size of its own as well. The size it asks
	//* for is never smaller than the size the program asked for.
	if kind := widget_kind(g, w); kind.measure != nil {
		size := kind.measure(g, w.id, w)
		w.min_size.x = max(w.min_size.x, size.x)
		w.min_size.y = max(w.min_size.y, size.y)
	}
}

//* The width of the longest word in the text.
longest_word_width :: proc(g: ^GUI, font: Font_ID, text: string) -> f32 {
	widest := f32(0)
	start := 0
	for i in 0 ..= len(text) {
		if i < len(text) && text[i] != ' ' {continue}
		if i > start {
			w := Font_Measure(g, font, text[start:i]).x
			if w > widest {widest = w}
		}
		start = i + 1
	}
	return widest
}

//* Lays the tree out. Measuring (text sizes) happens first so the
//* parents already see the right minimum sizes.
//
//* The tree is only walked where something changed. A widget that did
//* not move and that nothing happened to keeps the place it has, and
//* so does everything under it.
layout_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID {return}

	//* The counters say how much work this frame did.
	g.measured_count = 0
	g.arranged_count = 0

	//* The flags of this frame are taken off the GUI. An invalidation
	//* that happens while the tree is being laid out is for the next
	//* frame: the tree is never half laid out.
	pending := g.dirty
	g.dirty = Dirty_Flags{}

	//* The whole tree has to be done again: every widget is measured
	//* and every widget is laid out, whatever the flags say.
	if g.full_layout {
		g.full_layout = false
		for w in g.widgets {
			if w == nil {continue}
			w.dirty += Dirty_Flags{.Measure, .Arrange}
			w.subtree_dirty += Dirty_Flags{.Measure, .Arrange}
		}
		pending += Dirty_Flags{.Measure, .Arrange}
	}

	if .Measure in pending {
		measure_pass(g)
	}
	if .Arrange in pending {
		arrange_pass(g)
	}

	//* The widget under the pointer is looked up again when the tree
	//* moved under it: the widget that was under the pointer may not
	//* be under it any more.
	if .Hit in pending && g.pointer_known {
		hot, _ := hit_test_top(g, g.global_pointer)
		if hot != g.hot {
			//* The look of the two widgets changed: the one that was
			//* under the pointer is not under it any more, and the one
			//* that is under it now was not under it before.
			if old := Widget_Get(g, g.hot); old != nil {
				invalidate_widget(g, old, Dirty_Flags{.Visual})
			}
			if new := Widget_Get(g, hot); new != nil {
				invalidate_widget(g, new, Dirty_Flags{.Visual})
			}
		}
		g.hot = hot
	}

	//* The hit test and the theme are done with: the pointer has been
	//* looked up and the styles have been worked out again.
	consumed := Dirty_Flags{}
	if .Hit in pending {consumed += Dirty_Flags{.Hit}}
	if .Theme in pending {consumed += Dirty_Flags{.Theme}}
	if consumed != (Dirty_Flags{}) {
		for w in g.widgets {
			if w == nil {continue}
			w.dirty -= consumed
			w.subtree_dirty -= consumed
		}
	}
}

//* Lays the tree out and the floating panels, which are windows of
//* their own.
arrange_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID {return}
	layout_node(g, g.root, g.viewport, g.viewport)
	//* A floating panel is a window of its own, so it is laid out in
	//* its own space.
	for &f in g.floats {
		rect := Rect {
			x = 0,
			y = 0,
			w = f.size.x,
			h = f.size.y,
		}
		layout_node(g, f.widget, rect, rect)
	}
}

layout_node :: proc(g: ^GUI, id: Widget_ID, rect, clip: Rect) {
	w := Widget_Get(g, id)
	if w == nil {return}

	//* A widget that has a largest size does not go past it.
	new_rect := rect
	if w.custom_max_size.x > 0 && new_rect.w > w.custom_max_size.x {
		new_rect.w = w.custom_max_size.x
	}
	if w.custom_max_size.y > 0 && new_rect.h > w.custom_max_size.y {
		new_rect.h = w.custom_max_size.y
	}
	new_clip := rect_intersect(clip, new_rect)

	//* A tab that is not showing keeps no geometry. This is looked at
	//* before the skip below: a tab that stops being shown keeps the
	//* place it had until the layout pass knows about it, and it would
	//* still be drawn and hit if it were left alone.
	if is_hidden_tab(g, id) {
		hide_branch(g, w)
		return
	}

	//* The widget did not move, its clip did not change and nothing
	//* under it changed: it keeps the place it has.
	if rect_equal(w.rect, new_rect) &&
	   rect_equal(w.clip, new_clip) &&
	   !(.Arrange in w.subtree_dirty) {
		return
	}

	//* A widget being dragged has left its slot: it is drawn as a
	//* floating ghost and no longer takes part in the layout. A panel
	//* that is a window of its own keeps its place: the window moves.
	if g.drag.active && id == g.drag.widget && g.drag.float_index < 0 {
		hide_branch(g, w)
		return
	}

	w.rect = new_rect
	w.clip = new_clip
	g.arranged_count += 1

	//* A container keeps its children inside its own margin.
	style := resolved_style(g, w)
	inner := content_rect_with(new_rect, style.box.content_margin)

	//* A widget that came after the first ones lays its children out
	//* with its own hooks. The ones that were there from the beginning
	//* are in the switch below.
	if kind := widget_kind(g, w); kind.layout != nil {
		kind.layout(g, id, w, inner)
		forget_arrange(g, w)
		return
	}

	#partial switch w.type {
	case .Split:
		layout_split(g, w, inner)
	case .Tabs, .TabContainer:
		layout_tabs(g, w, inner)
	case .VBox, .HBox:
		layout_box(g, w, inner)
	case .GridContainer:
		layout_grid(g, w, inner)
	case .MarginContainer:
		layout_margin(g, w, inner)
	case .CenterContainer:
		layout_center(g, w, inner)
	case .PanelContainer:
		layout_panel_container(g, w, inner)
	case .ScrollContainer, .ScrollArea:
		layout_scroll(g, w, inner)
	case .FlowContainer:
		layout_flow(g, w, inner)
	case .AspectRatioContainer:
		layout_aspect(g, w, inner)
	case:
		// A plain control positions its children by anchors.
		child := w.first_child
		for child != INVALID_WIDGET_ID {
			c := Widget_Get(g, child)
			if c == nil {break}
			child_rect := resolve_rect(
				new_rect,
				c.anchors,
				c.offsets,
				c.min_size,
				c.grow_h,
				c.grow_v,
			)
			layout_node(g, child, child_rect, w.clip)
			child = c.next_sibling
		}
	}

	forget_arrange(g, w)
}

//* Forgets that a widget has to be laid out again. The widgets under
//* it have been laid out as well, so they are left alone.
forget_arrange :: proc(g: ^GUI, w: ^Widget) {
	if w == nil {return}
	w.dirty -= Dirty_Flags{.Arrange}
	w.subtree_dirty -= Dirty_Flags{.Arrange}
	//* A child that was not laid out keeps the branch out of date.
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		if .Arrange in c.subtree_dirty {
			w.subtree_dirty += Dirty_Flags{.Arrange}
			return
		}
		child = c.next_sibling
	}
}

//* Takes the geometry away from a whole branch: a tab that is not
//* showing, or a panel that is being dragged. The widgets under it lose
//* their place as well, so that they are placed again when the branch
//* gets its geometry back. A change that was made under a branch that
//* has no geometry is not lost this way: the place of a widget is
//* worked out from its anchors and its offsets, not from the place it
//* had.
hide_branch :: proc(g: ^GUI, w: ^Widget) {
	if w == nil { return }
	w.rect = Rect{}
	w.clip = Rect{}
	w.dirty -= Dirty_Flags{.Arrange}
	w.subtree_dirty -= Dirty_Flags{.Arrange}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		hide_branch(g, c)
		child = c.next_sibling
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
		c := Widget_Get(g, child)
		if c == nil {break}
		if keeps_size(c, horizontal) {
			total_min += manual_size_of(c, horizontal)
		} else {
			total_min += (vertical ? c.min_size.y : c.min_size.x)
			total_weight += c.weight
		}
		count += 1
		child = c.next_sibling
	}
	if total_weight <= 0 {total_weight = 1}
	if count == 0 {return}

	available := (vertical ? rect.h : rect.w) - total_min - sep * f32(count - 1)
	if available < 0 {available = 0}

	offset := vertical ? rect.y : rect.x
	child = w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
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
		c := Widget_Get(g, child)
		if c == nil {break}
		if keeps_size(c, horizontal) {
			total_min += manual_size_of(c, horizontal)
		} else {
			total_min += horizontal ? c.min_size.x : c.min_size.y
			total_weight += c.weight
		}
		child = c.next_sibling
	}
	if total_weight <= 0 {total_weight = 1}

	available := (horizontal ? rect.w : rect.h) - total_min
	if available < 0 {available = 0}

	offset := horizontal ? rect.x : rect.y
	child = w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		size := f32(0)
		if keeps_size(c, horizontal) {
			size = manual_size_of(c, horizontal)
		} else {
			size =
				(horizontal ? c.min_size.x : c.min_size.y) + available * (c.weight / total_weight)
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
	content := tabs_content_rect(w)

	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		//* Every child is laid out: the ones that are not showing keep
		//* no geometry, and the layout pass works that out.
		layout_node(g, child, content, w.clip)
		child = c.next_sibling
	}
}

//* A Grid puts its children in rows and columns. The number of columns
//* is in the data of the widget; a column of 0 means one column for
//* every child.
layout_grid :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	columns := 1
	#partial switch d in w.data {
	case Grid_Data:
		columns = d.columns
	}
	if columns <= 0 {columns = 1}

	sep := w.separation
	children: [dynamic]Widget_ID
	defer delete(children)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		append(&children, child)
		child = c.next_sibling
	}
	if len(children) == 0 {return}

	//* The width of every column and the height of every row: the
	//* biggest child of the column decides.
	rows := (len(children) + columns - 1) / columns
	col_w := make([dynamic]f32, 0, columns, context.allocator)
	defer delete(col_w)
	for _ in 0 ..< columns {append(&col_w, 0)}
	row_h := make([dynamic]f32, 0, rows, context.allocator)
	defer delete(row_h)
	for _ in 0 ..< rows {append(&row_h, 0)}

	for id, i in children {
		c := Widget_Get(g, id)
		if c == nil {continue}
		col := i % columns
		row := i / columns
		if col_w[col] < c.min_size.x {col_w[col] = c.min_size.x}
		if row_h[row] < c.min_size.y {row_h[row] = c.min_size.y}
	}

	//* The space that is left is shared out among the columns that can
	//* grow.
	total_w := f32(0)
	for w_ in col_w {total_w += w_}
	available := rect.w - total_w - sep * f32(columns - 1)
	if available < 0 {available = 0}
	grow := 0
	for w_ in col_w {
		if w_ <= 0 {grow += 1}
	}
	if grow > 0 {
		for &w_ in col_w {
			if w_ <= 0 {w_ += available / f32(grow)}
		}
	}

	x := rect.x
	for col in 0 ..< columns {
		y := rect.y
		for row in 0 ..< rows {
			i := row * columns + col
			if i < len(children) {
				c := Widget_Get(g, children[i])
				if c != nil {
					layout_node(
						g,
						children[i],
						Rect{x = x, y = y, w = col_w[col], h = row_h[row]},
						w.clip,
					)
				}
			}
			y += row_h[row] + sep
		}
		x += col_w[col] + sep
	}
}

//* A Margin puts its child inside a margin of its own. The margin is
//* in the data of the widget; the content margin of the style is added
//* to it.
layout_margin :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	margin := [4]f32{}
	#partial switch d in w.data {
	case Margin_Data:
		margin = d.margin
	}
	inner := Rect {
		x = rect.x + margin[0],
		y = rect.y + margin[1],
		w = rect.w - margin[0] - margin[2],
		h = rect.h - margin[1] - margin[3],
	}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		layout_node(g, child, inner, w.clip)
		child = c.next_sibling
	}
}

//* A Center puts its child in the middle of the space it has, at the
//* size the child asks for.
layout_center :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		size := c.min_size
		if size.x > rect.w {size.x = rect.w}
		if size.y > rect.h {size.y = rect.h}
		layout_node(
			g,
			child,
			Rect {
				x = rect.x + (rect.w - size.x) * 0.5,
				y = rect.y + (rect.h - size.y) * 0.5,
				w = size.x,
				h = size.y,
			},
			w.clip,
		)
		child = c.next_sibling
	}
}

//* A PanelContainer puts its child in all of the space it has, so that
//* the child fills the panel.
layout_panel_container :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		layout_node(g, child, rect, w.clip)
		child = c.next_sibling
	}
}

//* A ScrollContainer shows a part of a child that is bigger than it.
//* The child keeps its own size, and the container remembers how far it
//* is scrolled.
layout_scroll :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	scroll := Vec2{}
	#partial switch d in w.data {
	case Scroll_Data:
		scroll = d.offset
	}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		//* The child is as big as it wants to be, and it is moved by
		//* the scroll of the container.
		size := c.min_size
		inner := Rect {
			x = rect.x - scroll.x,
			y = rect.y - scroll.y,
			w = size.x,
			h = size.y,
		}
		layout_node(g, child, inner, w.clip)
		child = c.next_sibling
	}
}

//* A FlowContainer puts its children one after the other, and starts a
//* new row when there is no room left.
layout_flow :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	sep := w.separation
	x := rect.x
	y := rect.y
	row_h := f32(0)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		size := c.min_size
		if size.x > rect.w {size.x = rect.w}
		if x > rect.x && x + size.x > rect.x + rect.w {
			//* There is no room left on this row: the next one starts.
			x = rect.x
			y += row_h + sep
			row_h = 0
		}
		layout_node(g, child, Rect{x = x, y = y, w = size.x, h = size.y}, w.clip)
		x += size.x + sep
		if size.y > row_h {row_h = size.y}
		child = c.next_sibling
	}
}

//* An AspectRatioContainer keeps the ratio of its child, so that the
//* child is as wide as the box is tall, or the other way round.
layout_aspect :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	ratio := f32(1)
	#partial switch d in w.data {
	case Aspect_Data:
		ratio = d.ratio
	}
	if ratio <= 0 {ratio = 1}

	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		size := c.min_size
		w_ := rect.w
		h_ := w_ / ratio
		if h_ > rect.h {
			h_ = rect.h
			w_ = h_ * ratio
		}
		layout_node(
			g,
			child,
			Rect {
				x = rect.x + (rect.w - w_) * 0.5,
				y = rect.y + (rect.h - h_) * 0.5,
				w = w_,
				h = h_,
			},
			w.clip,
		)
		child = c.next_sibling
	}
}

//* Resolve a widget's rect from its parent's rect (Godot's Control maths).
resolve_rect :: proc(
	parent: Rect,
	anchors: Anchor,
	offsets: Offset,
	min_size: Vec2,
	grow_h, grow_v: Grow,
) -> Rect {
	left := parent.x + parent.w * anchors.left + offsets.left
	top := parent.y + parent.h * anchors.top + offsets.top
	right := parent.x + parent.w * anchors.right + offsets.right
	bottom := parent.y + parent.h * anchors.bottom + offsets.bottom

	w := right - left
	h := bottom - top

	if w < min_size.x {
		d := min_size.x - w
		switch grow_h {
		case .Begin:
			left -= d
		case .End:
			right += d
		case .Both:
			left -= d * 0.5; right += d * 0.5
		}
		w = min_size.x
	}
	if h < min_size.y {
		d := min_size.y - h
		switch grow_v {
		case .Begin:
			top -= d
		case .End:
			bottom += d
		case .Both:
			top -= d * 0.5; bottom += d * 0.5
		}
		h = min_size.y
	}
	return Rect{x = left, y = top, w = w, h = h}
}
