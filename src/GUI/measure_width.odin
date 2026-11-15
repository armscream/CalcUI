//* == Measuring at a width ==
//* A widget whose preferred height depends on the width it is given is
//* first measured with no width, which gives the size it would like when
//* nothing constrains it. When a container knows the width it gives to a
//* child, the child is measured again at that width. Wrapped text, a
//* multiline text box and a widget of a class with a `measure_width` hook
//* grow taller when they are narrower.
//*
//* The measurement is a pure walk down the branch: it reads the sizes of
//* the children and writes the size of the parent, and it never places a
//* widget. The text cache of `text_measure` is keyed by the width, so a
//* text that is measured again at the same width is not shaped again.

package GUI

//* The preferred size of a widget when it is given `width` on the
//* outside. The measured size is stored in the widget, so the layout that
//* follows reads it from `min_size`.
Widget_Measure_At_Width :: proc(g: ^GUI, id: Widget_ID, width: f32) -> Vec2 {
	if g == nil {return {}}
	w := Widget_Get(g, id)
	if w == nil {return {}}
	//* The measure pass keeps the flag of the branch, but the call may
	//* come before the first pass ran.
	if !w.width_dependent {w.width_dependent = widget_branch_width_dependent(g, w)}
	measure_widget_at_width(g, w, max(width, 0))
	return w.min_size
}

//* True when the height of a widget or of a widget below it depends on
//* the width it is given.
widget_branch_width_dependent :: proc(g: ^GUI, w: ^Widget) -> bool {
	if w == nil {return false}
	if widget_width_dependent(g, w) {return true}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		if widget_branch_width_dependent(g, c) {return true}
		child = c.next_sibling
	}
	return false
}

//* True when the height of a widget depends on the width it is given.
//* A container is width-dependent when a child is.
widget_width_dependent :: proc(g: ^GUI, w: ^Widget) -> bool {
	if w == nil {return false}
	if kind := widget_kind(g, w); kind.measure_width != nil {return true}

	#partial switch d in w.data {
	case Text_Box_Data:
		return .Multiline in d.flags
	case Rich_Text_Data:
		return d.text != ""
	}

	if !widget_has_text(w) {return false}
	return resolved_style(g, w).text.wrap != .Off
}

//* Measures a widget and the branch below it at an outer width. A branch
//* whose height does not depend on its width keeps the size the measure
//* pass worked out.
measure_widget_at_width :: proc(g: ^GUI, w: ^Widget, width: f32) {
	if g == nil || w == nil {return}
	if !w.width_dependent {return}

	kind := widget_kind(g, w)
	//* A class that lays its children out itself and has no width hook
	//* decides for itself what the width means. The core leaves the
	//* size the measure pass worked out.
	if kind.layout != nil && kind.measure_width == nil {return}

	measure_widget_at(g, w, width)

	if widget_measures_children(g, w) {
		measure_children_at_width(g, w, width)
		measure_container_at_width(g, w)
		return
	}

	if kind.measure_width != nil {
		size := kind.measure_width(g, w.id, w, width)
		if size.x > w.min_size.x {w.min_size.x = size.x}
		if size.y > w.min_size.y {w.min_size.y = size.y}
		clamp_measured_size(w)
	}
}

//* The width inside the margin of the style of a widget.
content_width_of :: proc(g: ^GUI, w: ^Widget, width: f32) -> f32 {
	style := resolved_style(g, w)
	pad := style.box.content_margin
	return max(width - pad[0] - pad[2], 0)
}

//* The width a child may take, after the largest width of the child is
//* taken into account.
child_width_of :: proc(c: ^Widget, width: f32) -> f32 {
	w := max(width, 0)
	if c != nil && c.custom_max_size.x > 0 && w > c.custom_max_size.x {
		w = c.custom_max_size.x
	}
	return w
}

//* Measures the children of a container at the width the container gives
//* them. The rule is the one of the layout pass: a box gives its children
//* a share along its axis and the room across it, and a margin, a panel,
//* a scroll or a grid gives its children the room it has worked out.
measure_children_at_width :: proc(g: ^GUI, w: ^Widget, width: f32) {
	content_w := content_width_of(g, w, width)

	#partial switch w.type {
	case .VBox:
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			across, _ := cross_size(c, true, content_w)
			measure_widget_at_width(g, c, child_width_of(c, across))
		}
	case .HBox:
		measure_box_children_width(g, w, content_w, true)
	case .Split:
		horizontal := true
		#partial switch d in w.data {
		case Split_Data:
			horizontal = d.direction == .Horizontal
		}
		measure_split_children_width(g, w, content_w, horizontal)
	case .GridContainer:
		measure_grid_children_width(g, w, content_w)
	case .MarginContainer:
		margin := [4]f32{}
		#partial switch d in w.data {
		case Margin_Data:
			margin = d.margin
		}
		inner := max(content_w - margin[0] - margin[2], 0)
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			measure_widget_at_width(g, c, child_width_of(c, inner))
		}
	case .ScrollContainer, .ScrollArea:
		//* The content of a scroll is measured when the scroll is laid
		//* out, with the width its children ask for. The scroll reports
		//* the measured size of its content here, and its bars read the
		//* same size from the layout pass.
		return
	case .CenterContainer:
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			inner := min(c.min_size.x, content_w)
			measure_widget_at_width(g, c, child_width_of(c, inner))
		}
	case .FlowContainer:
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			inner := min(c.min_size.x, content_w)
			measure_widget_at_width(g, c, child_width_of(c, inner))
		}
	case .AspectRatioContainer:
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			measure_widget_at_width(g, c, child_width_of(c, content_w))
		}
	case .PanelContainer, .Tabs, .TabContainer:
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			measure_widget_at_width(g, c, child_width_of(c, content_w))
		}
	case:
		//* A plain control places its children by their anchors, over
		//* the whole room it has. The anchors of a child decide its
		//* width, so measuring at the room is the best the container
		//* can do here; the anchors are honoured by the layout pass.
		base, count := children_begin(g, w)
		defer children_end(g, base)
		for i in 0 ..< count {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			measure_widget_at_width(g, c, child_width_of(c, content_w))
		}
	}
}

//* The width of the slot a box gives a child along its axis. The solver
//* of the axis is the one of the layout pass, so the widths the children
//* are measured at are the widths they are placed at.
measure_box_children_width :: proc(
	g: ^GUI,
	w: ^Widget,
	content_w: f32,
	horizontal: bool,
) {
	base, total := children_begin(g, w)
	defer children_end(g, base)

	count := 0
	for i in 0 ..< total {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil || c.absolute {continue}
		count += 1
	}
	if count == 0 {return}

	sep := w.separation
	space := content_w - sep * f32(count - 1)
	room_base := floats_begin(g, total)
	defer floats_end(g, room_base)
	axis_solve(
		g,
		g.children_scratch[base:base + total],
		horizontal,
		space,
		g.float_scratch[room_base:room_base + total],
	)

	for i in 0 ..< total {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil || c.absolute {continue}
		room := g.float_scratch[room_base + i]
		size, _ := axis_size(c, horizontal, room)
		measure_widget_at_width(g, c, child_width_of(c, size))
	}
}

//* The width of the slot of a split child. A horizontal split shares its
//* width along its axis; a vertical one gives every child the whole
//* width across it.
measure_split_children_width :: proc(
	g: ^GUI,
	w: ^Widget,
	content_w: f32,
	horizontal: bool,
) {
	base, total := children_begin(g, w)
	defer children_end(g, base)

	count := 0
	for i in 0 ..< total {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil || c.absolute {continue}
		count += 1
	}
	if count == 0 {return}

	if !horizontal {
		for i in 0 ..< total {
			c := Widget_Get(g, g.children_scratch[base + i])
			if c == nil || c.absolute {continue}
			across, _ := cross_size(c, true, content_w)
			measure_widget_at_width(g, c, child_width_of(c, across))
		}
		return
	}

	room_base := floats_begin(g, total)
	defer floats_end(g, room_base)
	axis_solve(
		g,
		g.children_scratch[base:base + total],
		true,
		content_w,
		g.float_scratch[room_base:room_base + total],
	)
	for i in 0 ..< total {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil || c.absolute {continue}
		room := g.float_scratch[room_base + i]
		size, _ := axis_size(c, true, room)
		measure_widget_at_width(g, c, child_width_of(c, size))
	}
}

//* The width of the cell of a grid child. The columns are the ones the
//* layout pass works out: the widest child of a column decides it, and
//* the room that is left over is shared among the columns that have no
//* width of their own.
measure_grid_children_width :: proc(g: ^GUI, w: ^Widget, content_w: f32) {
	columns, h_separation, _, margin := grid_metrics(g, w)
	inner_w := max(content_w - margin[0] - margin[2], 0)

	base, count := children_begin_flow(g, w)
	defer children_end(g, base)
	if count == 0 {return}

	rows := (count + columns - 1) / columns
	track_base := floats_begin(g, columns + rows)
	defer floats_end(g, track_base)

	for i in 0 ..< count {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil {continue}
		col := track_base + i % columns
		if g.float_scratch[col] < c.min_size.x {g.float_scratch[col] = c.min_size.x}
	}

	total_w := f32(0)
	for col in 0 ..< columns {total_w += g.float_scratch[track_base + col]}
	available := inner_w - total_w - h_separation * f32(columns - 1)
	if available < 0 {available = 0}
	grow := 0
	for col in 0 ..< columns {
		if g.float_scratch[track_base + col] <= 0 {grow += 1}
	}
	if grow > 0 {
		for col in 0 ..< columns {
			if g.float_scratch[track_base + col] <= 0 {
				g.float_scratch[track_base + col] += available / f32(grow)
			}
		}
	}

	for i in 0 ..< count {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil {continue}
		cell_w := g.float_scratch[track_base + i % columns]
		measure_widget_at_width(g, c, child_width_of(c, cell_w))
	}
}

//* Works out the size a container asks for from the sizes of its
//* children. The size of the widget was reset by `measure_widget_at`, so
//* the height may shrink when the width grows.
measure_container_at_width :: proc(g: ^GUI, w: ^Widget) {
	content := container_content_size(g, w)
	style := resolved_style(g, w)
	pad := style.box.content_margin
	content.x += pad[0] + pad[2]
	content.y += pad[1] + pad[3]

	if content.x > w.min_size.x {w.min_size.x = content.x}
	if content.y > w.min_size.y {w.min_size.y = content.y}
	clamp_measured_size(w)
}

//* A measured size never asks for more than the largest size the program
//* allowed.
clamp_measured_size :: proc(w: ^Widget) {
	if w == nil {return}
	if w.custom_max_size.x > 0 && w.min_size.x > w.custom_max_size.x {
		w.min_size.x = w.custom_max_size.x
	}
	if w.custom_max_size.y > 0 && w.min_size.y > w.custom_max_size.y {
		w.min_size.y = w.custom_max_size.y
	}
}
