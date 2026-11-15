//* The measure pass and the layout pass of the widget tree.
//* The tree is walked every frame, but the work is only done where
//* something changed; a change says what it made stale (see
//* invalidation.odin).
//*
//* == The constraint of a widget ==
//* Along one axis a widget has three sizes: the least it may take, the
//* size it would like to take and the most it may take. The preferred
//* size is the size the measure pass worked out, the floor is the size
//* the program asked for, and the cap is the largest size it allowed.
//* A cap of 0 means that there is no cap. The three are normalized, so
//* the floor is never above the preferred size and a cap below the
//* preferred size wins over it (see `Layout_Constraint`).
//*
//* == The room of a child ==
//* A container that gives its children a share of its room works it out
//* like this. The room is the content rect of the container: the padding
//* of the style is taken off before the children are placed, and the
//* separations are taken off the axis before the solver sees the room.
//* Every child is measured, so it knows the preferred size it asks for.
//* The room that is left over after the preferred sizes and the
//* separations are taken out is shared among the children that expand,
//* and the share of a child is its weight times its stretch ratio. A
//* child that reaches its cap is taken out of the sharing, and the room
//* that is left is shared again among the children that can still grow.
//*
//* When the children do not fit, the room is taken away from the ones
//* that have a shrink weight until they reach their floor. A child
//* without a shrink weight keeps its preferred size, and a container
//* whose children have no shrink weight overflows the way it did before
//* there were shrink weights.
//*
//* The flags of a child say what it does with the room it is given. A
//* child that expands takes its preferred size plus its share of the
//* room that is left over. A child that does not expand takes only its
//* preferred size, and the room that is left over goes to the children
//* that expand. A child that is centred in its room (the `.Shrink_Center`
//* flag) takes only its preferred size and sits in the middle of the room
//* it would have had.
//*
//* The flags of the other axis say how the child sits across the
//* container: it fills the width of a vertical box, or it is centred in
//* it. There is no room to share across that axis.
//*
//* == Absolute children ==
//* A child that is absolute is taken out of the flow of its container:
//* it takes no share of the room and it does not move the cursor that
//* places the other children. It is placed by its anchors and offsets
//* inside the content of the parent instead. A container of a custom
//* class that lays itself out decides for itself what an absolute child
//* means.
package Core
import virt "core:mem/virtual"
//* == The flags of the size ==

//* The flags of a widget along one axis. `horizontal` is true when the
//* axis is the horizontal one.
size_flags_of :: proc(c: ^Widget, horizontal: bool) -> Size_Flags {
	return horizontal ? c.size_flags_h : c.size_flags_v
}

//* The share of the room of the parent a widget asks for: the weight of
//* the widget times the ratio of the widget. A share that is not a number,
//* or a share below zero, is a share of nothing.
share_of :: proc(c: ^Widget) -> f32 {
	share := c.weight * c.stretch_ratio
	if share != share || share < 0 {return 0}
	return share
}

//* The share of a deficit a widget takes. A weight that is not a number,
//* or a weight below zero, is a weight of nothing, the same way the
//* setter and the constructor read it.
shrink_of :: proc(c: ^Widget) -> f32 {
	weight := c.shrink_weight
	if weight != weight || weight < 0 {return 0}
	return weight
}

//* The least, the wanted and the most a widget may take along one axis.
//*
//* `preferred` is the size the measure pass worked out: the size of the
//* text and the padding of the style, raised by the sizes the program
//* asked for and clamped by the largest size it allowed. `minimum` is
//* the floor the program asked for, which is where a shrink stops.
//* `maximum` is the largest size the program allowed; a value of 0 means
//* that there is no maximum, the same convention as the options.
//*
//* A constraint is always normalized: a floor above the preferred size is
//* folded into the preferred size, a maximum below the preferred size
//* wins over it, and a maximum below the floor wins over the floor. A
//* constraint therefore always satisfies
//* `minimum <= preferred <= maximum`, unless there is no maximum, in
//* which case `maximum` is 0.
//*
//* The constraint describes the content of a widget. A size the program
//* pulled into place (`manual_size`) is kept whatever the constraint says,
//* the same way it was before there were constraints.
Layout_Constraint :: struct {
	minimum:   f32,
	preferred: f32,
	maximum:   f32,
}

//* The constraint of a widget along one axis. The preferred size comes
//* from the measure pass, so it is only up to date after the pass ran.
layout_constraint :: proc(w: ^Widget, horizontal: bool) -> Layout_Constraint {
	preferred := horizontal ? w.min_size.x : w.min_size.y
	floor := horizontal ? max(w.base_min_size.x, w.custom_min_size.x) : max(w.base_min_size.y, w.custom_min_size.y)
	maximum := horizontal ? w.custom_max_size.x : w.custom_max_size.y

	//* A size that is not a number, or a size below zero, says nothing.
	if preferred != preferred || preferred < 0 {preferred = 0}
	if floor != floor || floor < 0 {floor = 0}
	if maximum != maximum || maximum < 0 {maximum = 0}

	if maximum > 0 && preferred > maximum {preferred = maximum}
	if floor > preferred {floor = preferred}

	return Layout_Constraint {
		minimum = floor,
		preferred = preferred,
		maximum = maximum,
	}
}

//* The constraint of a widget of the GUI along one axis. The preferred
//* size is measured lazily, so the constraint is only up to date after
//* a measure pass.
Widget_Layout_Constraint :: proc(g: ^GUI, id: Widget_ID, horizontal: bool) -> Layout_Constraint {
	w := Widget_Get(g, id)
	if w == nil {return {}}
	return layout_constraint(w, horizontal)
}

//* Fills `rooms` with the room each child of a container gets along an
//* axis. `space` is the room of the axis after the separations have been
//* taken out, so it is the room the children share between them.
//*
//* A child that was pulled to a size keeps it, and it is taken out of the
//* room first, the same way it was before there were constraints. The
//* other children start at their preferred size.
//*
//* When there is room left over, the children that expand take their
//* preferred size plus a share of it, and their share is their weight
//* times their stretch ratio. When the children do not fit, the deficit
//* is taken from the children that have a shrink weight, by their
//* weight, until they reach their floor. A child without a shrink weight
//* keeps its preferred size and the container overflows.
//*
//* The solver always ends: every pass pins at least one child at its cap
//* or at its floor, and a container with n children cannot pin more than
//* n of them. A pass that pins nothing is the last one.
axis_solve :: proc(
	g: ^GUI,
	children: []Widget_ID,
	horizontal: bool,
	space: f32,
	rooms: []f32,
) {
	if len(children) == 0 || len(rooms) < len(children) {return}

	preferred_total := f32(0)
	for id, i in children {
		rooms[i] = 0
		c := Widget_Get(g, id)
		if c == nil || c.absolute {continue}
		if keeps_size(c, horizontal) {
			rooms[i] = manual_size_of(c, horizontal)
		} else {
			rooms[i] = layout_constraint(c, horizontal).preferred
		}
		preferred_total += rooms[i]
	}

	spare := space - preferred_total
	if spare >= 0 {
		axis_grow(g, children, horizontal, spare, rooms)
	} else {
		axis_shrink(g, children, horizontal, -spare, rooms)
	}
}

//* Shares the room that is left over among the children that expand,
//* and takes a child that reaches its cap out of the sharing so that the
//* room it did not use goes to the children that can still grow.
axis_grow :: proc(
	g: ^GUI,
	children: []Widget_ID,
	horizontal: bool,
	spare_in: f32,
	rooms: []f32,
) {
	spare := spare_in
	if spare <= 0 {return}

	for _ in 0 ..= len(children) {
		total_share := f32(0)
		for id, i in children {
			c := Widget_Get(g, id)
			if c == nil || c.absolute || keeps_size(c, horizontal) {continue}
			if !(.Expand in size_flags_of(c, horizontal)) {continue}
			share := share_of(c)
			if share <= 0 {continue}
			con := layout_constraint(c, horizontal)
			if con.maximum > 0 && rooms[i] >= con.maximum {continue}
			total_share += share
		}
		if total_share <= 0 {return}

		added := f32(0)
		pinned := false
		for id, i in children {
			c := Widget_Get(g, id)
			if c == nil || c.absolute || keeps_size(c, horizontal) {continue}
			if !(.Expand in size_flags_of(c, horizontal)) {continue}
			share := share_of(c)
			if share <= 0 {continue}
			con := layout_constraint(c, horizontal)
			if con.maximum > 0 && rooms[i] >= con.maximum {continue}

			room := rooms[i] + spare * (share / total_share)
			if con.maximum > 0 && room >= con.maximum {
				room = con.maximum
				pinned = true
			}
			added += room - rooms[i]
			rooms[i] = room
		}

		spare -= added
		//* Nothing was pinned, so every child took all of its share:
		//* there is nothing left to share again.
		if !pinned {return}
		if spare <= 0.0001 {return}
	}
}

//* Takes the room that the children need but do not have from the ones
//* that have a shrink weight, and pins a child at its floor once it can
//* give no more so that the deficit goes to the children that can.
axis_shrink :: proc(
	g: ^GUI,
	children: []Widget_ID,
	horizontal: bool,
	deficit_in: f32,
	rooms: []f32,
) {
	deficit := deficit_in
	if deficit <= 0 {return}

	for _ in 0 ..= len(children) {
		total_weight := f32(0)
		for id, i in children {
			c := Widget_Get(g, id)
			if c == nil || c.absolute || keeps_size(c, horizontal) {continue}
			if shrink_of(c) <= 0 {continue}
			//* A child that is centred in its room takes only its
			//* preferred size whatever the room is, so it cannot give
			//* any room back.
			if .Shrink_Center in size_flags_of(c, horizontal) {continue}
			con := layout_constraint(c, horizontal)
			if rooms[i] <= con.minimum {continue}
			total_weight += shrink_of(c)
		}
		if total_weight <= 0 {return}

		taken := f32(0)
		pinned := false
		for id, i in children {
			c := Widget_Get(g, id)
			if c == nil || c.absolute || keeps_size(c, horizontal) {continue}
			if shrink_of(c) <= 0 {continue}
			if .Shrink_Center in size_flags_of(c, horizontal) {continue}
			con := layout_constraint(c, horizontal)
			if rooms[i] <= con.minimum {continue}

			room := rooms[i] - deficit * (shrink_of(c) / total_weight)
			if room <= con.minimum {
				room = con.minimum
				pinned = true
			}
			taken += rooms[i] - room
			rooms[i] = room
		}

		deficit -= taken
		//* Nothing was pinned, so every child gave all of its share:
		//* there is nothing left to take.
		if !pinned {return}
		if deficit <= 0.0001 {return}
	}
}

//* The size a child takes along the axis its parent stacks the children
//* along, and how far the child sits from the start of its room.
//*
//* A child that fills takes the whole room. A child that is centred in
//* its room takes only its preferred size and sits in the middle of it.
//* A child that neither fills nor is centred takes only its preferred
//* size and leaves the rest of its room empty. A child that has no size
//* of its own keeps the room it is given.
axis_size :: proc(c: ^Widget, horizontal: bool, room: f32) -> (size, offset: f32) {
	flags := size_flags_of(c, horizontal)
	min_size := horizontal ? c.min_size.x : c.min_size.y
	if .Shrink_Center in flags {
		return min_size, (room - min_size) * 0.5
	}
	if .Fill in flags {
		return room, 0
	}
	if !widget_sizes_to_content(c, horizontal) {
		return room, 0
	}
	return min_size, 0
}

//* The size of a child across the axis its parent stacks the children
//* along, and where the child sits. There is no room to share across
//* that axis: the child fills it, or it is centred in it.
cross_size :: proc(c: ^Widget, horizontal: bool, room: f32) -> (size, offset: f32) {
	flags := size_flags_of(c, horizontal)
	min_size := horizontal ? c.min_size.x : c.min_size.y
	if .Shrink_Center in flags {
		return min_size, (room - min_size) * 0.5
	}
	if .Fill in flags {
		return room, 0
	}
	if !widget_sizes_to_content(c, horizontal) {
		return room, 0
	}
	return min_size, 0
}

//* == The direction ==
//* The direction of a widget is the direction it says when it says one,
//* otherwise the direction of its parent, otherwise the direction of the
//* root of the GUI, otherwise from the left to the right.

//* The direction of the language of the program. The toolkit has no
//* locale yet, so the language is read from the left to the right.
locale_direction :: proc(g: ^GUI) -> Layout_Direction {
	return .LTR
}

//* The direction a widget grows in.
layout_direction_of :: proc(g: ^GUI, id: Widget_ID) -> Layout_Direction {
	w := Widget_Get(g, id)
	if w == nil { return .LTR }
	switch w.layout_direction {
	case .LTR:
		return .LTR
	case .RTL:
		return .RTL
	case .Locale:
		return locale_direction(g)
	case .Inherit:
		parent := Widget_Get(g, w.parent)
		if parent != nil { return layout_direction_of(g, parent.id) }
		return .LTR
	}
	return .LTR
}

//* Text widgets grow to fit their text. This runs before the layout pass
//* so the parent already sees the right minimum size.
measure_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID {return}
	measure_node(g, g.root)
}


measure_node :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	//* Nothing under this widget changed: the sizes are the ones they were.
	if !(.Measure in w.subtree_dirty) {return}

	//* The children are measured first. A container that derives its
	//* preferred size from its children needs their sizes, so the pass
	//* is post-order: the leaves work out their size, then their
	//* parents add them up. A container only sees the branch that
	//* changed, because a child that did not change kept its size.
	dependent := widget_width_dependent(g, w)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		//* A measure hook of a class can change the tree, so the link
		//* to the next sibling is read before the child is measured.
		next := c.next_sibling
		measure_node(g, child)
		if measured := Widget_Get(g, child); measured != nil && measured.width_dependent {
			dependent = true
		}
		child = next
	}
	w.width_dependent = dependent

	//* The size of the widget itself is worked out again when the widget
	//* changed, and for a container whenever a child changed: the
	//* container adds up the sizes of its children.
	intrinsic := widget_measures_children(g, w)
	if .Measure in w.dirty || intrinsic {
		measure_widget(g, w)
		g.measured_count += 1
		w.dirty -= Dirty_Flags{.Measure}
	}
	if intrinsic {
		measure_container(g, w)
	}

	w.subtree_dirty -= Dirty_Flags{.Measure}
}

//* True when a widget draws text of its own. A widget with text
//* takes the size of that text, a widget without text takes the room
//* it is given.
widget_has_text :: proc(w: ^Widget) -> bool {
	#partial switch d in w.data {
	case Label_Data:
		return d.text != ""
	case Button_Data:
		return d.text != ""
	case Check_Box_Data:
		return d.text != ""
	case Link_Button_Data:
		return d.text != ""
	case Menu_Button_Data:
		return d.text != ""
	case Search_Field_Data:
		return d.text != "" || d.placeholder != ""
	case Toggle_Switch_Data:
		return d.text != ""
	case Rich_Text_Data:
		return d.text != ""
	}
	return false
}

//* True when the widget takes the size of its own content along the axis
//* instead of the room it is given.
//*
//* A widget with text of its own takes the size of that text on both of
//* its axes. A widget that holds a list of things takes the size of the
//* widest of them across, and the room it is given along the stack: the
//* rows of a tree that do not fit are scrolled away, so the tree is as
//* tall as the room of its parent and no taller.
//*
//* A text box takes the room it is given across, so that the text of it
//* has room to wrap in, and the height of its text along the other
//* axis.
widget_sizes_to_content :: proc(w: ^Widget, horizontal: bool) -> bool {
	#partial switch d in w.data {
	case Text_Box_Data:
		return !horizontal
	}
	if widget_has_text(w) {return true}
	#partial switch w.type {
	case .ComboBox, .Tree:
		return horizontal
	}
	return false
}

//* The smallest size of a widget: the size the program asked for, the
//* size of its text plus the padding of its style, and the size the
//* program insists on.
//*
//* The padding of the style is never less than a point on a side, so
//* the content of a widget never touches its border.
measure_widget :: proc(g: ^GUI, w: ^Widget) {
	measure_widget_at(g, w, -1)
}

//* Measures a widget. A `width` below zero means that the width is not
//* known, which gives the intrinsic size. A width that is known is the
//* width of the widget on the outside: a text that wraps is measured at
//* the room its content has, so the height reflects the lines it takes.
measure_widget_at :: proc(g: ^GUI, w: ^Widget, width: f32) {
	style := resolved_style(g, w)
	pad := style.box.content_margin
	pad[0] = max(pad[0], 1)
	pad[1] = max(pad[1], 1)
	pad[2] = max(pad[2], 1)
	pad[3] = max(pad[3], 1)

	//* A text box takes the width it is given and its height is the
	//* height of the lines of its text. Its own measure hook works out
	//* the height of one line; the width-aware version is used here so
	//* that a multiline box grows when its text wraps.
	#partial switch d in w.data {
	case Text_Box_Data:
		content_w := f32(0)
		if width >= 0 {
			content_w = max(width - pad[0] - pad[2], 0)
		}
		size := measure_text_box_at_width(g, w.id, w, content_w)
		//* A class of its own may measure a box as well; its size is a
		//* floor under the size the lines of the text need.
		if kind := widget_kind(g, w); kind.measure != nil {
			hook := kind.measure(g, w.id, w)
			size.x = max(size.x, hook.x)
			size.y = max(size.y, hook.y)
		}
		w.min_size.x = max(w.base_min_size.x, max(w.custom_min_size.x, size.x))
		w.min_size.y = max(w.base_min_size.y, size.y)
		clamp_measured_size(w)
		return
	}

	text := ""
	extra_x := f32(0)
	extra_y := f32(0)
	force_wrap := false
	#partial switch d in w.data {
	case Label_Data:
		text = d.text
	case Button_Data:
		text = d.text
	case Check_Box_Data:
		text = d.text
		extra_x = CHECK_BOX_SIZE + CHECK_BOX_GAP
		extra_y = CHECK_BOX_SIZE
	case Link_Button_Data:
		text = d.text
	case Menu_Button_Data:
		text = d.text
	case Toggle_Switch_Data:
		text = d.text
		extra_x = TOGGLE_TRACK_WIDTH + TOGGLE_LABEL_GAP
		extra_y = TOGGLE_TRACK_HEIGHT
	case Rich_Text_Data:
		//* A rich text label is drawn with the words wrapped, whatever
		//* the style says.
		text = d.text
		force_wrap = true
	}

	if text != "" {
		ts := style.text
		if force_wrap {ts.wrap = .Word}

		//* The text is measured as it is drawn, so a text that is
		//* transformed takes the room of the transformed text. A text
		//* that wraps is measured at the width it is given.
		text_width := f32(0)
		if width >= 0 && ts.wrap != .Off {
			text_width = max(width - pad[0] - pad[2] - extra_x, 0)
		}
		size := text_measure(g, ts, text, text_width)
		if ts.wrap != .Off {
			//* A text that wraps only has to be as wide as its
			//* longest word: the rest of it fits on the lines below.
			font := Font_Resolve(g, ts)
			src := apply_text_transform(g, ts, text)
			size.x = longest_word_width(g, font, src)
		}
		w.min_size.x = max(w.base_min_size.x, size.x + pad[0] + pad[2] + extra_x)
		w.min_size.y = max(w.base_min_size.y, max(size.y, extra_y) + pad[1] + pad[3])
	} else {
		w.min_size.x = max(w.base_min_size.x, extra_x)
		w.min_size.y = max(w.base_min_size.y, extra_y)
	}

	w.min_size.x = max(w.min_size.x, w.custom_min_size.x)
	w.min_size.y = max(w.min_size.y, w.custom_min_size.y)

	//* A class can ask for a size of its own as well, and it is never
	//* smaller than the size asked for before it.
	if kind := widget_kind(g, w); kind.measure != nil {
		size := kind.measure(g, w.id, w)
		w.min_size.x = max(w.min_size.x, size.x)
		w.min_size.y = max(w.min_size.y, size.y)
	}

	//* A widget never asks for more room than the largest size it may
	//* have: the room that is left over goes to the other widgets.
	clamp_measured_size(w)
}

//* True when a widget works out its preferred size from the preferred
//* sizes of its children. The children are measured before their parent,
//* so the pass sees the size each one asks for.
//*
//* A class that places its children itself decides for itself what they
//* mean, so the core does not add them up for it.
widget_measures_children :: proc(g: ^GUI, w: ^Widget) -> bool {
	if w == nil {return false}
	if widget_kind(g, w).layout != nil {return false}
	#partial switch w.type {
	case .VBox,
	     .HBox,
	     .GridContainer,
	     .MarginContainer,
	     .CenterContainer,
	     .PanelContainer,
	     .ScrollContainer,
	     .ScrollArea,
	     .FlowContainer,
	     .AspectRatioContainer,
	     .TabContainer,
	     .Tabs,
	     .Split:
		return true
	}
	return false
}

//* The size a child asks for. A size the user pulled into place wins over
//* the measured size, the same way it wins in the solver.
preferred_size_of :: proc(c: ^Widget) -> Vec2 {
	size := c.min_size
	if size.x != size.x || size.x < 0 {size.x = 0}
	if size.y != size.y || size.y < 0 {size.y = 0}
	if keeps_size(c, true) {size.x = manual_size_of(c, true)}
	if keeps_size(c, false) {size.y = manual_size_of(c, false)}
	return size
}

//* The largest size a child asks for. `skip` is left out of the count
//* when it is a child of the container, which is what a scroll container
//* needs for its bar.
container_max_child_size :: proc(g: ^GUI, w: ^Widget, skip: Widget_ID) -> Vec2 {
	size := Vec2{}
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if !c.absolute && child != skip {
			s := preferred_size_of(c)
			size.x = max(size.x, s.x)
			size.y = max(size.y, s.y)
		}
		child = next
	}
	return size
}

//* The size a box asks for: the largest child across the stack, and the
//* children one after the other along it, with the separations between
//* them. An absolute child takes no part in the stack.
container_box_size :: proc(g: ^GUI, w: ^Widget, vertical: bool) -> Vec2 {
	size := Vec2{}
	count := 0
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if !c.absolute {
			s := preferred_size_of(c)
			if vertical {
				size.x = max(size.x, s.x)
				size.y += s.y
			} else {
				size.x += s.x
				size.y = max(size.y, s.y)
			}
			count += 1
		}
		child = next
	}
	if count > 1 {
		sep := w.separation * f32(count - 1)
		if vertical {
			size.y += sep
		} else {
			size.x += sep
		}
	}
	return size
}

//* The size a split asks for: the children one after the other along the
//* axis of the split, and the largest across it.
container_split_size :: proc(g: ^GUI, w: ^Widget) -> Vec2 {
	horizontal := true
	#partial switch d in w.data {
	case Split_Data:
		horizontal = d.direction == .Horizontal
	}

	size := Vec2{}
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if !c.absolute {
			s := preferred_size_of(c)
			if horizontal {
				size.x += s.x
				size.y = max(size.y, s.y)
			} else {
				size.x = max(size.x, s.x)
				size.y += s.y
			}
		}
		child = next
	}
	return size
}

//* The settings of a grid: the number of columns, the two separations and
//* the margin. A grid that says nothing about the separations takes the
//* ones of the theme, and the one of the widget when the theme says
//* nothing either. The measure pass and the layout pass read them here,
//* so the two cannot disagree.
grid_metrics :: proc(
	g: ^GUI,
	w: ^Widget,
) -> (
	columns: int,
	h_separation: f32,
	v_separation: f32,
	margin: [4]f32,
) {
	#partial switch d in w.data {
	case Grid_Data:
		columns = d.columns
		margin = d.margin
		h_separation = d.h_separation
		v_separation = d.v_separation
	}
	if columns <= 0 {columns = 1}
	if h_separation <= 0 {h_separation = theme_constant(g, w, "h_separation")}
	if h_separation <= 0 {h_separation = w.separation}
	if v_separation <= 0 {v_separation = theme_constant(g, w, "v_separation")}
	if v_separation <= 0 {v_separation = w.separation}
	return
}

//* The size a grid asks for: the widest child of every column, the
//* tallest child of every row, the separations between the tracks and
//* the margin of the grid.
container_grid_size :: proc(g: ^GUI, w: ^Widget) -> Vec2 {
	columns, h_separation, v_separation, margin := grid_metrics(g, w)

	count := 0
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if !c.absolute {count += 1}
		child = next
	}

	margin_x := margin[0] + margin[2]
	margin_y := margin[1] + margin[3]
	if count == 0 {
		return Vec2{margin_x, margin_y}
	}

	rows := (count + columns - 1) / columns
	track_base := floats_begin(g, columns + rows)
	defer floats_end(g, track_base)

	i := 0
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if !c.absolute {
			s := preferred_size_of(c)
			col := track_base + i % columns
			row := track_base + columns + i / columns
			if g.float_scratch[col] < s.x {g.float_scratch[col] = s.x}
			if g.float_scratch[row] < s.y {g.float_scratch[row] = s.y}
			i += 1
		}
		child = next
	}

	size := Vec2{x = margin_x, y = margin_y}
	for col in 0 ..< columns {
		size.x += g.float_scratch[track_base + col]
	}
	if columns > 1 {
		size.x += h_separation * f32(columns - 1)
	}
	for row in 0 ..< rows {
		size.y += g.float_scratch[track_base + columns + row]
	}
	if rows > 1 {
		size.y += v_separation * f32(rows - 1)
	}
	return size
}

//* Adds the sizes of the children to the size a container asks for. Each
//* container type reads its children in its own way; the padding of the
//* style is added on top of that, because the content of the container
//* sits inside it.
measure_container :: proc(g: ^GUI, w: ^Widget) {
	content := container_content_size(g, w)

	style := resolved_style(g, w)
	pad := style.box.content_margin
	content.x += pad[0] + pad[2]
	content.y += pad[1] + pad[3]

	if content.x > w.min_size.x {w.min_size.x = content.x}
	if content.y > w.min_size.y {w.min_size.y = content.y}
	clamp_measured_size(w)
}

//* The size the content of a container asks for, without the padding of
//* its style. The measure pass and the measurement at a width both read
//* it, so the two cannot disagree.
container_content_size :: proc(g: ^GUI, w: ^Widget) -> Vec2 {
	content := Vec2{}
	#partial switch w.type {
	case .VBox:
		content = container_box_size(g, w, true)
	case .HBox:
		content = container_box_size(g, w, false)
	case .Split:
		content = container_split_size(g, w)
	case .GridContainer:
		content = container_grid_size(g, w)
	case .MarginContainer:
		content = container_max_child_size(g, w, INVALID_WIDGET_ID)
		margin := [4]f32{}
		#partial switch d in w.data {
		case Margin_Data:
			margin = d.margin
		}
		content.x += margin[0] + margin[2]
		content.y += margin[1] + margin[3]
	case .CenterContainer, .PanelContainer, .FlowContainer:
		content = container_max_child_size(g, w, INVALID_WIDGET_ID)
	case .ScrollContainer, .ScrollArea:
		//* The bar of the scroll is not part of the content: it sits
		//* over the viewport.
		content = container_max_child_size(g, w, scroll_bar_id(g, w.id))
	case .AspectRatioContainer:
		child := container_max_child_size(g, w, INVALID_WIDGET_ID)
		ratio := f32(1)
		#partial switch d in w.data {
		case Aspect_Data:
			ratio = d.ratio
		}
		if ratio <= 0 {ratio = 1}
		width := max(child.x, child.y * ratio)
		content = Vec2{width, width / ratio}
	case .Tabs, .TabContainer:
		content = container_max_child_size(g, w, INVALID_WIDGET_ID)
		content.y += TAB_BAR_HEIGHT
	case:
		return content
	}
	return content
}

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

layout_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID {return}

	g.measured_count = 0
	g.arranged_count = 0

	pending := g.dirty
	g.dirty = Dirty_Flags{}

	if g.full_layout {
		g.full_layout = false
		for w in g.widgets {
			if w == nil {continue}
			w.dirty += Dirty_Flags{.Measure, .Arrange}
			w.subtree_dirty += Dirty_Flags{.Measure, .Arrange}
		}
		pending += Dirty_Flags{.Measure, .Arrange}
	}

	if .Measure in pending {measure_pass(g)}
	if .Arrange in pending {arrange_pass(g)}

	if .Hit in pending && g.pointer_known {
		hot, _ := hit_test_top(g, g.global_pointer)
		if hot != g.hot {
			if old := Widget_Get(g, g.hot); old != nil {
				invalidate_widget(g, old, Dirty_Flags{.Visual})
			}
			if new := Widget_Get(g, hot); new != nil {
				invalidate_widget(g, new, Dirty_Flags{.Visual})
			}
		}
		g.hot = hot
	}

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

arrange_pass :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID {return}
	layout_node(g, g.root, g.viewport, g.viewport)
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
		layout_by_anchors(g, w, new_rect)
	}

	forget_arrange(g, w)
}


//* The smallest size the anchors of a widget may give it. A container
//* reports the size it would like from its children, but its anchors
//* decide its viewport: a box, a scroll or a split may be smaller than
//* that, and the children shrink, overflow or scroll. The size the
//* program asked for is still a floor.
anchor_min_size :: proc(g: ^GUI, c: ^Widget) -> Vec2 {
	size := c.min_size
	if widget_measures_children(g, c) {
		size.x = max(c.base_min_size.x, c.custom_min_size.x)
		size.y = max(c.base_min_size.y, c.custom_min_size.y)
	}
	return size
}

//* Places the absolute children of a container by their anchors and
//* offsets inside `content`. They are placed after the children that
//* take part in the flow, so they sit on top of them in the order of the
//* tree, and they take no share of the room of the container.
//*
//* The children are looked at through the links of the tree rather than
//* through a snapshot, because a widget that is placed can be taken out
//* of the tree by a hook of a class of the program.
layout_absolute_children :: proc(g: ^GUI, w: ^Widget, content: Rect) {
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if c.absolute {
			layout_node(g, child, resolve_child_rect(g, content, c), w.clip)
		}
		child = next
	}
}

//* The rect the anchors of a child give it inside `parent`. When the
//* child is one whose height depends on its width, the anchors are
//* applied twice: the first pass gives the room, the measurement at that
//* width gives the height, and the second pass places the child with the
//* height it asked for.
resolve_child_rect :: proc(g: ^GUI, parent: Rect, c: ^Widget) -> Rect {
	rect := resolve_rect(
		parent,
		c.anchors,
		c.offsets,
		c.min_size,
		anchor_min_size(g, c),
		c.grow_h,
		c.grow_v,
		c.size_flags_h,
		c.size_flags_v,
		widget_sizes_to_content(c, true),
		widget_sizes_to_content(c, false),
		c.manual_size,
		c.manual_w,
		c.manual_h,
	)
	if c.width_dependent && rect.w > 0 {
		measure_widget_at_width(g, c, child_width_of(c, rect.w))
		rect = resolve_rect(
			parent,
			c.anchors,
			c.offsets,
			c.min_size,
			anchor_min_size(g, c),
			c.grow_h,
			c.grow_v,
			c.size_flags_h,
			c.size_flags_v,
			widget_sizes_to_content(c, true),
			widget_sizes_to_content(c, false),
			c.manual_size,
			c.manual_w,
			c.manual_h,
		)
	}
	return rect
}

layout_by_anchors :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil {continue}
		layout_node(g, child, resolve_child_rect(g, rect, c), w.clip)
	}
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

hide_branch :: proc(g: ^GUI, w: ^Widget) {
	if w == nil {return}
	w.rect = Rect{}
	w.clip = Rect{}
	w.dirty -= Dirty_Flags{.Arrange}
	w.subtree_dirty -= Dirty_Flags{.Arrange}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		hide_branch(g, c)
		child = next
	}
}

//* A VBox / HBox stacks its children along one axis. Every child gets
//* its preferred size on that axis plus a share of the leftover space,
//* weighted. A child that was pulled to a size keeps that size, and
//* takes it out of the space the others share. A child that reaches its
//* maximum stops growing, and the room it does not take goes to the
//* children that can still grow.
//*
//* The flags of a child say how much of that room it takes: a child that
//* expands takes its preferred size plus its share of the leftover
//* space, and a child that does not expand takes only its preferred size
//* and leaves the rest of its room empty. A child that is centred in its
//* room (the `.Shrink_Center` flag) takes only its preferred size.
//*
//* When the children do not fit, the children that have a shrink weight
//* give the room back, by their weight, until they reach their floor. A
//* child without a shrink weight keeps its preferred size, and the box
//* overflows. An absolute child is taken out of the flow altogether.
//*
//* The flags of the other axis say how the child sits across the box: it
//* fills the width of a vertical box, or it is centred in it.
//*
//* A box that stacks its children along the horizontal axis puts them in
//* the other order when the direction is from the right to the left. The
//* room the children get does not change: only the order they are put in.
layout_box :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	vertical := w.type == .VBox
	horizontal := !vertical
	sep := w.separation

	base, total := children_begin(g, w)
	defer children_end(g, base)

	//* An absolute child takes no part in the flow, so it does not count
	//* for the separations either.
	count := 0
	for i in 0 ..< total {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil || c.absolute {continue}
		count += 1
	}
	if count == 0 {
		layout_absolute_children(g, w, rect)
		return
	}

	//* A vertical box knows the width it gives every child before it
	//* shares the height, so a child whose height depends on its width
	//* is measured again here. A horizontal box knows the width of a
	//* child only after the solver ran: it is measured at its slot while
	//* the children are placed.
	if vertical && w.width_dependent {
		measure_children_at_width(g, w, rect.w)
	}

	//* The room the children share is the room of the axis after the
	//* separations are taken out. It is not cut to zero: a box whose
	//* children do not fit tells the solver how much it lacks, and the
	//* children that can shrink give the room back.
	space := (vertical ? rect.h : rect.w) - sep * f32(count - 1)
	room_base := floats_begin(g, total)
	defer floats_end(g, room_base)
	axis_solve(
		g,
		g.children_scratch[base:base + total],
		horizontal,
		space,
		g.float_scratch[room_base:room_base + total],
	)

	//* A box that stacks its children from the left to the right puts
	//* them in the other order when the direction is from the right to
	//* the left. A vertical box is not affected by the direction.
	rtl := horizontal && layout_direction_of(g, w.id) == .RTL

	offset := vertical ? rect.y : rect.x
	if rtl {offset += rect.w}
	for i in 0 ..< total {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		room := g.float_scratch[room_base + i]
		size := f32(0)
		in_room := f32(0)
		if keeps_size(c, horizontal) {
			size = room
		} else {
			size, in_room = axis_size(c, horizontal, room)
		}
		//* A horizontal box knows the width of a child only now: a
		//* child whose height depends on its width is measured at the
		//* slot it was given.
		if !vertical && w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, size))
		}
		//* Across the box there is no room to share: the child fills
		//* the box, or it is centred in it.
		across, across_offset := cross_size(c, !horizontal, vertical ? rect.w : rect.h)
		if vertical {
			layout_node(
				g,
				child,
				Rect {
					x = rect.x + across_offset,
					y = offset + in_room,
					w = across,
					h = size,
				},
				w.clip,
			)
		} else if rtl {
			layout_node(
				g,
				child,
				Rect {
					x = offset - room + in_room,
					y = rect.y + across_offset,
					w = size,
					h = across,
				},
				w.clip,
			)
		} else {
			layout_node(
				g,
				child,
				Rect {
					x = offset + in_room,
					y = rect.y + across_offset,
					w = size,
					h = across,
				},
				w.clip,
			)
		}
		//* The room of the child is taken out of the room of the box,
		//* even when the child does not fill it.
		if rtl {
			offset -= room + sep
		} else {
			offset += room + sep
		}
	}

	layout_absolute_children(g, w, rect)
}

//* A Split divides its rect among its children along one axis, weighted.
//* A child with weight 0 keeps its minimum size and takes no share.
//* A child that was pulled to a size keeps that size, and takes it out
//* of the space the others share.
//*
//* The flags of a child say how much of that room it takes, and the
//* flags of the other axis say how it sits across the split.
//*
//* A split keeps the order of the tree, whatever the direction is: a
//* split is the container of the docking system, and the docking system
//* works from the left to the right.
layout_split :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	dir := Split_Direction.Horizontal
	#partial switch d in w.data {
	case Split_Data:
		dir = d.direction
	}
	horizontal := dir == .Horizontal

	base, total := children_begin(g, w)
	defer children_end(g, base)

	count := 0
	for i in 0 ..< total {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil || c.absolute {continue}
		count += 1
	}
	if count == 0 {
		layout_absolute_children(g, w, rect)
		return
	}

	//* A vertical split gives every child the whole width, so a child
	//* whose height depends on its width is measured before the height
	//* is shared. A horizontal split measures a child at its slot.
	if !horizontal && w.width_dependent {
		measure_split_children_width(g, w, rect.w, false)
	}

	space := horizontal ? rect.w : rect.h
	room_base := floats_begin(g, total)
	defer floats_end(g, room_base)
	axis_solve(
		g,
		g.children_scratch[base:base + total],
		horizontal,
		space,
		g.float_scratch[room_base:room_base + total],
	)

	offset := horizontal ? rect.x : rect.y
	for i in 0 ..< total {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		room := g.float_scratch[room_base + i]
		size := f32(0)
		in_room := f32(0)
		if keeps_size(c, horizontal) {
			size = room
		} else {
			size, in_room = axis_size(c, horizontal, room)
		}
		if horizontal && w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, size))
		}
		across, across_offset := cross_size(c, !horizontal, horizontal ? rect.h : rect.w)
		if horizontal {
			layout_node(
				g,
				child,
				Rect {
					x = offset + in_room,
					y = rect.y + across_offset,
					w = size,
					h = across,
				},
				w.clip,
			)
		} else {
			layout_node(
				g,
				child,
				Rect {
					x = rect.x + across_offset,
					y = offset + in_room,
					w = across,
					h = size,
				},
				w.clip,
			)
		}
		//* The room of the child is taken out of the room of the split,
		//* even when the child does not fill it.
		offset += room
	}

	layout_absolute_children(g, w, rect)
}

//* A tab that is not showing keeps no geometry, so it is neither drawn nor hit.
layout_tabs :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	content := tabs_content_rect(w)

	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, content.w))
		}
		layout_node(g, child, content, w.clip)
	}

	layout_absolute_children(g, w, content)
}

//* A Grid puts its children in rows and columns. The number of columns
//* is in the data of the widget; a count of 0 means one column.
//*
//* The room that is left over is shared among the columns that have no
//* width of their own, and not among the children: the flags of a child
//* say nothing here, because the column decides how wide a child is.
//*
//* The separations of the grid are the ones of the data of the widget;
//* when the grid says nothing about them, the separations of the theme
//* are used, and the separation of the widget itself when the theme says
//* nothing either.
//*
//* The margin of the grid keeps the cells away from its edges, and the
//* room of every cell is kept in the data of the widget, so that the
//* lines between the cells can be drawn.
layout_grid :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	columns, h_separation, v_separation, margin := grid_metrics(g, w)

	//* The margin of the grid is taken off the room of the grid.
	inner := Rect {
		x = rect.x + margin[0],
		y = rect.y + margin[1],
		w = rect.w - margin[0] - margin[2],
		h = rect.h - margin[1] - margin[3],
	}

	base, count := children_begin_flow(g, w)
	defer children_end(g, base)
	if count == 0 {
		grid_cells(g, w.id, 0)
		layout_absolute_children(g, w, inner)
		return
	}

	//* The width of every column and the height of every row: the
	//* biggest child of the column decides. The numbers live in the
	//* float scratch of the GUI, one stack for the two of them.
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
	available := inner.w - total_w - h_separation * f32(columns - 1)
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

	//* A cell has its width now, so a child whose height depends on its
	//* width is measured at the width of the column. The height of every
	//* row is the tallest child in it.
	for i in 0 ..< count {
		c := Widget_Get(g, g.children_scratch[base + i])
		if c == nil {continue}
		cell_w := g.float_scratch[track_base + i % columns]
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, cell_w))
		}
		row := track_base + columns + i / columns
		if g.float_scratch[row] < c.min_size.y {g.float_scratch[row] = c.min_size.y}
	}

	//* The room of every cell of the grid, the ones that have a child
	//* in them and the ones that have not.
	cells := grid_cells(g, w.id, columns * rows)

	x := inner.x
	for col in 0 ..< columns {
		col_w := g.float_scratch[track_base + col]
		y := inner.y
		for row in 0 ..< rows {
			i := row * columns + col
			row_h := g.float_scratch[track_base + columns + row]
			cell := Rect{x = x, y = y, w = col_w, h = row_h}
			cells[i] = cell
			if i < count {
				child := g.children_scratch[base + i]
				c := Widget_Get(g, child)
				if c != nil {
					layout_node(g, child, cell, w.clip)
				}
			}
			y += row_h + v_separation
		}
		x += col_w + h_separation
	}

	layout_absolute_children(g, w, inner)
}

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
	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, inner.w))
		}
		layout_node(g, child, inner, w.clip)
	}

	layout_absolute_children(g, w, inner)
}

layout_center :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		size := c.min_size
		if size.x > rect.w {size.x = rect.w}
		if size.y > rect.h {size.y = rect.h}
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, size.x))
			size = c.min_size
			if size.x > rect.w {size.x = rect.w}
			if size.y > rect.h {size.y = rect.h}
		}
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
	}

	layout_absolute_children(g, w, rect)
}

layout_panel_container :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, rect.w))
		}
		layout_node(g, child, rect, w.clip)
	}

	layout_absolute_children(g, w, rect)
}

layout_scroll :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	scroll := Vec2{}
	bar := INVALID_WIDGET_ID
	side := Scroll_Bar_Side.None
	#partial switch &d in w.data {
	case Scroll_Data:
		scroll = d.offset
		bar = d.bar_id
		side = d.bar
	}

	//* The content is measured before it is placed: the bars need its
	//* size, and a child whose height depends on its width is measured
	//* before the height it takes is read. The size is kept, so the
	//* bars and the pointer code read the same content the layout used.
	content := scroll_content_measure(g, w)
	viewport := Vec2{max(rect.w, 0), max(rect.h, 0)}
	#partial switch &d in w.data {
	case Scroll_Data:
		d.viewport = viewport
		d.content = content
		d.content_ready = true
		//* A viewport that grew may leave the offset past the end of
		//* the content: it is pulled back, so the content is not lost
		//* above the top of the viewport.
		d.offset.x = clamp(d.offset.x, 0, scroll_maximum(content.x, viewport.x))
		d.offset.y = clamp(d.offset.y, 0, scroll_maximum(content.y, viewport.y))
		scroll = d.offset
	}

	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		if child == bar {continue}
		//* A child keeps the size it asks for; the measure pass has
		//* already worked it out, including the height of a container
		//* whose wrapped text depends on its width.
		size := preferred_size_of(c)
		inner := Rect {
			x = rect.x - scroll.x,
			y = rect.y - scroll.y,
			w = size.x,
			h = size.y,
		}
		layout_node(g, child, inner, w.clip)
	}
	layout_scroll_bar(g, w, rect, bar, side, content, scroll)

	//* An absolute child is placed in the viewport and does not move
	//* with the content.
	layout_absolute_children(g, w, rect)
}

layout_scroll_bar :: proc(
	g: ^GUI,
	w: ^Widget,
	viewport: Rect,
	bar_id: Widget_ID,
	side: Scroll_Bar_Side,
	content: Vec2,
	scroll: Vec2,
) {
	if bar_id == INVALID_WIDGET_ID {return}
	bw := Widget_Get(g, bar_id)
	if bw == nil {return}
	vertical := side == .Right || side == .Left
	width := scroll_bar_width(g)
	rect := Rect{}
	shown := false
	switch side {
	case .Right:
		rect = Rect {
			x = viewport.x + viewport.w - width,
			y = viewport.y,
			w = width,
			h = viewport.h,
		}
		shown = content.y > viewport.h
	case .Left:
		rect = Rect{x = viewport.x, y = viewport.y, w = width, h = viewport.h}
		shown = content.y > viewport.h
	case .Top:
		rect = Rect{x = viewport.x, y = viewport.y, w = viewport.w, h = width}
		shown = content.x > viewport.w
	case .Bottom:
		rect = Rect {
			x = viewport.x,
			y = viewport.y + viewport.h - width,
			w = viewport.w,
			h = width,
		}
		shown = content.x > viewport.w
	case .None:
		shown = false
	}
	#partial switch &d in bw.data {
	case Scroll_Bar_Data:
		d.vertical = vertical
		d.content = vertical ? content.y : content.x
		d.view = vertical ? viewport.h : viewport.w
		d.offset = vertical ? scroll.y : scroll.x
	}
	if !shown {
		Widget_Set_Visible(g, bar_id, false)
		Widget_Set_Mouse_Filter(g, bar_id, .Ignore)
		layout_node(g, bar_id, Rect{}, w.clip)
		return
	}
	Widget_Set_Visible(g, bar_id, true)
	Widget_Set_Mouse_Filter(g, bar_id, .Stop)
	layout_node(g, bar_id, rect, w.clip)
}

//* A Flow container puts its children one after the other and starts a
//* new row when there is no room left. Every child keeps the size it
//* asks for, so no room is shared and the flags of a child say nothing
//* here.
layout_flow :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	sep := w.separation
	x := rect.x
	y := rect.y
	row_h := f32(0)
	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		size := c.min_size
		if size.x > rect.w {size.x = rect.w}
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, size.x))
			size.y = c.min_size.y
		}
		if x > rect.x && x + size.x > rect.x + rect.w {
			//* There is no room left on this row: the next one starts.
			x = rect.x
			y += row_h + sep
			row_h = 0
		}
		layout_node(g, child, Rect{x = x, y = y, w = size.x, h = size.y}, w.clip)
		x += size.x + sep
		if size.y > row_h {row_h = size.y}
	}

	layout_absolute_children(g, w, rect)
}

layout_aspect :: proc(g: ^GUI, w: ^Widget, rect: Rect) {
	ratio := f32(1)
	#partial switch d in w.data {
	case Aspect_Data:
		ratio = d.ratio
	}
	if ratio <= 0 {ratio = 1}

	base, count := children_begin(g, w)
	defer children_end(g, base)
	for i in 0 ..< count {
		child := g.children_scratch[base + i]
		c := Widget_Get(g, child)
		if c == nil || c.absolute {continue}
		w_ := rect.w
		h_ := w_ / ratio
		if h_ > rect.h {
			h_ = rect.h
			w_ = h_ * ratio
		}
		if w.width_dependent {
			measure_widget_at_width(g, c, child_width_of(c, w_))
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
	}

	layout_absolute_children(g, w, rect)
}

resolve_rect :: proc(
	parent: Rect,
	anchors: Anchor,
	offsets: Offset,
	min_size: Vec2,
	floor: Vec2,
	grow_h, grow_v: Grow,
	flags_h, flags_v: Size_Flags,
	content_h, content_v: bool,
	manual: Vec2,
	manual_w, manual_h: bool,
) -> Rect {
	left := parent.x + parent.w * anchors.left + offsets.left
	top := parent.y + parent.h * anchors.top + offsets.top
	right := parent.x + parent.w * anchors.right + offsets.right
	bottom := parent.y + parent.h * anchors.bottom + offsets.bottom

	w := right - left
	h := bottom - top

	//* A widget whose anchors span its parent is given a room that is
	//* bigger than it needs. A widget that has content of its own takes
	//* the size of that content and stands at the start of the room,
	//* unless it asks to fill it. A widget without content of its own
	//* has no size of its own, so it keeps the room it is given.
	if content_h && anchors.right > anchors.left && !(.Fill in flags_h) && min_size.x > 0 {
		w = min_size.x
		if grow_h == .Begin {
			left = right - w
		} else {
			right = left + w
		}
	}
	if content_v && anchors.bottom > anchors.top && !(.Fill in flags_v) && min_size.y > 0 {
		h = min_size.y
		if grow_v == .Begin {
			top = bottom - h
		} else {
			bottom = top + h
		}
	}

	if w < floor.x {
		d := floor.x - w
		switch grow_h {
		case .Begin:
			left -= d
		case .End:
			right += d
		case .Both:
			left -= d * 0.5; right += d * 0.5
		}
		w = floor.x
	}
	if h < floor.y {
		d := floor.y - h
		switch grow_v {
		case .Begin:
			top -= d
		case .End:
			bottom += d
		case .Both:
			top -= d * 0.5; bottom += d * 0.5
		}
		h = floor.y
	}

	if manual_w {
		w = max(manual.x, 0)
		switch grow_h {
		case .Begin:
			left = right - w
		case .End:
			right = left + w
		case .Both:
			centre := (left + right) * 0.5
			left = centre - w * 0.5
			right = centre + w * 0.5
		}
	}
	if manual_h {
		h = max(manual.y, 0)
		switch grow_v {
		case .Begin:
			top = bottom - h
		case .End:
			bottom = top + h
		case .Both:
			centre := (top + bottom) * 0.5
			top = centre - h * 0.5
			bottom = centre + h * 0.5
		}
	}
	return Rect{x = left, y = top, w = w, h = h}
}

CHECK_BOX_SIZE :: 16

CHECK_BOX_GAP  :: 8

TOGGLE_TRACK_HEIGHT :: 18

TOGGLE_LABEL_GAP    :: 8


TOGGLE_TRACK_WIDTH  :: 34


SCROLL_BAR_WIDTH :: 10
SCROLL_BAR_GRABBER_MIN :: 24

grid_data :: proc(g: ^GUI, id: Widget_ID) -> ^Grid_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Grid_Data:
		return &d
	}
	return nil
}

grid_cells :: proc(g: ^GUI, id: Widget_ID, count: int) -> []Rect {
	d := grid_data(g, id)
	if d == nil {return nil}
	if count > len(d.cells) {
		d.cells = make([]Rect, count, virt.arena_allocator(&g.arena))
	}
	d.cell_count = count
	return d.cells[:count]
}

scroll_data :: proc(g: ^GUI, id: Widget_ID) -> ^Scroll_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Scroll_Data:
		return &d
	}
	return nil
}

scroll_bar_id :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	d := scroll_data(g, id)
	if d == nil {return INVALID_WIDGET_ID}
	return d.bar_id
}

scroll_viewport :: proc(g: ^GUI, w: ^Widget) -> Rect {
	if w == nil {return Rect{}}
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

scroll_content_measure :: proc(g: ^GUI, w: ^Widget) -> Vec2 {
	size := Vec2{}
	if w == nil {return size}

	bar := scroll_bar_id(g, w.id)
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil {break}
		next := c.next_sibling
		if child != bar && !c.absolute {
			if c.width_dependent && widget_measures_children(g, c) {
				measure_widget_at_width(g, c, child_width_of(c, max(c.min_size.x, 0)))
			}
			s := preferred_size_of(c)
			size.x = max(size.x, s.x)
			size.y = max(size.y, s.y)
			if kind := widget_kind(g, c); kind.content_size != nil {
				logical := kind.content_size(g, child, c)
				size.x = max(size.x, logical.x)
				size.y = max(size.y, logical.y)
			}
		}
		child = next
	}
	return size
}

scroll_content_size :: proc(g: ^GUI, w: ^Widget) -> Vec2 {
	if w == nil {return Vec2{}}
	if d := scroll_data(g, w.id); d != nil && d.content_ready {
		return d.content
	}
	return scroll_content_measure(g, w)
}

Scroll_Container_Get_Offset :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	d := scroll_data(g, id)
	if d == nil {return Vec2{}}
	return d.offset
}

Scroll_Container_Viewport_Size :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	w := Widget_Get(g, id)
	if w == nil {return Vec2{}}
	viewport := scroll_viewport(g, w)
	return Vec2{max(viewport.w, 0), max(viewport.h, 0)}
}

Scroll_Container_Content_Size :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	return scroll_content_size(g, Widget_Get(g, id))
}

Scroll_Container_Visible_Rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	w := Widget_Get(g, id)
	if w == nil {return Rect{}}
	viewport := scroll_viewport(g, w)
	content := scroll_content_size(g, w)
	offset := Scroll_Container_Get_Offset(g, id)

	x0 := max(viewport.x, viewport.x - offset.x)
	y0 := max(viewport.y, viewport.y - offset.y)
	x1 := min(viewport.x + viewport.w, viewport.x - offset.x + content.x)
	y1 := min(viewport.y + viewport.h, viewport.y - offset.y + content.y)
	return Rect {
		x = x0,
		y = y0,
		w = max(x1 - x0, 0),
		h = max(y1 - y0, 0),
	}
}

scroll_bar_data :: proc(g: ^GUI, id: Widget_ID) -> ^Scroll_Bar_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Scroll_Bar_Data:
		return &d
	}
	return nil
}

scroll_bar_width :: proc(g: ^GUI) -> f32 {
	if g != nil && g.theme != nil {
		if value, has := Theme_Get_Constant(g.theme, .ScrollBar, "width"); has && value > 0 {
			return value
		}
	}
	return SCROLL_BAR_WIDTH
}

scroll_bar_grabber_min :: proc(g: ^GUI) -> f32 {
	if g != nil && g.theme != nil {
		if value, has := Theme_Get_Constant(g.theme, .ScrollBar, "grabber_min"); has && value > 0 {
			return value
		}
	}
	return SCROLL_BAR_GRABBER_MIN
}
