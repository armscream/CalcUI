//* Making a widget, moving it in the tree and taking it away again.
//* A widget keeps its identity when it moves, so a handle stays valid and
//* the tree can be rearranged without losing anything.
package GUI

import "core:log"
import "core:strings"
import virt "core:mem/virtual"

//* The widget with a handle, or nil if the handle names nothing.
Widget_Get :: proc(g: ^GUI, id: Widget_ID) -> ^Widget {
	if g == nil { return nil }
	if id.index == 0 { return nil }
	idx := int(id.index) - 1
	if idx >= len(g.widgets) { return nil }
	w := g.widgets[idx]
	if w == nil { return nil }
	//* The slot holds another widget now, or it is empty: the handle is stale.
	if w.id != id { return nil }
	return w
}

//* Whether the handle names a widget that is still there.
Widget_Alive :: proc(g: ^GUI, id: Widget_ID) -> bool {
	return Widget_Get(g, id) != nil
}

widget_slot :: proc(g: ^GUI) -> int {
	if len(g.free_widgets) > 0 {
		last := len(g.free_widgets) - 1
		slot := int(g.free_widgets[last])
		resize(&g.free_widgets, last)
		return slot
	}
	slot := len(g.widgets)
	append(&g.widgets, nil)
	append(&g.widget_generations, 0)
	return slot
}

//* Creates a widget. Everything is in `opts`; afterwards a widget is
//* mutated by writing to the struct returned by Widget_Get. The widget
//* belongs to the class of its kind, when there is one.
New_Widget :: proc(g: ^GUI, type: Widget_Type, parent: Widget_ID, opts: Widget_Opts = {}) -> Widget_ID {
	return new_widget(g, type, parent, opts, class_of_type(g, type))
}

//* Creates a widget of a class. The class says what the widget does.
new_widget :: proc(
	g: ^GUI,
	type: Widget_Type,
	parent: Widget_ID,
	opts: Widget_Opts,
	class: Widget_Class_ID,
) -> Widget_ID {
	slot := widget_slot(g)

	w := g.widgets[slot]
	if w == nil {
		created, err := virt.new(&g.arena, Widget)
		if err != nil {
			log.panicf("widget allocation failed: %v", err)
		}
		w = created
		g.widgets[slot] = w
	}

	g.widget_generations[slot] += 1
	if g.widget_generations[slot] == 0 { g.widget_generations[slot] = 1 }

	//* Arena memory is not zeroed, so start from a clean slate.
	w^ = Widget{}
	w.id = Widget_ID{index = u32(slot + 1), generation = g.widget_generations[slot]}

	w.type = type
	w.class = class
	w.name = opts.name
	w.parent = INVALID_WIDGET_ID
	w.first_child = INVALID_WIDGET_ID
	w.last_child = INVALID_WIDGET_ID
	w.prev_sibling = INVALID_WIDGET_ID
	w.next_sibling = INVALID_WIDGET_ID

	w.anchors = anchor_of(opts.preset, opts.anchors)
	w.offsets = opts.offsets
	w.min_size = opts.min_size
	w.base_min_size = opts.min_size
	w.weight = opts.weight
	if w.weight == 0 && !opts.fixed { w.weight = 1 }
	w.separation = opts.separation
	if w.separation == 0 { w.separation = 4 }
	w.draggable = opts.draggable
	//* A widget that has to grow past its minimum size grows right and
	//* down, like Godot's default grow direction.
	w.grow_h = .End
	w.grow_v = .End
	w.style = opts.style
	w.use_theme = opts.use_theme
	w.variation = opts.variation
	w.state = Widget_State{.Visible, .Enabled}
	if opts.hidden { w.state -= Widget_State{.Visible} }

	//* The control features. A widget takes the mouse and cuts its children to
	//* its own rect unless it is told otherwise. The mouse filter of .Stop is
	//* the first of the enum, so it is what a widget gets when nothing is asked.
	w.mouse_filter = opts.mouse_filter
	w.focus_neighbour = {INVALID_WIDGET_ID, INVALID_WIDGET_ID, INVALID_WIDGET_ID, INVALID_WIDGET_ID}
	w.focus_next = INVALID_WIDGET_ID
	w.focus_previous = INVALID_WIDGET_ID
	w.tab_index = opts.tab_index
	w.size_flags_h = opts.size_flags_h
	w.size_flags_v = opts.size_flags_v
	if w.size_flags_h == (Size_Flags{}) { w.size_flags_h = Size_Flags{.Fill} }
	if w.size_flags_v == (Size_Flags{}) { w.size_flags_v = Size_Flags{.Fill} }
	w.stretch_ratio = opts.stretch_ratio
	w.clip_contents = opts.clip_contents != .Off
	w.tooltip_text = opts.tooltip
	w.custom_min_size = opts.custom_min_size
	w.custom_max_size = opts.custom_max_size
	w.z_index = opts.z_index
	if opts.access_role != .None {
		w.access.role = opts.access_role
		w.access.role_set = true
	}
	if opts.access_name != "" {
		w.access.name = opts.access_name
		w.access.name_set = true
	}
	w.access.description = opts.access_description
	w.scale = Vec2{1, 1}
	w.layout_direction = .Inherit

	#partial switch type {
	case .Button:
		w.data = Button_Data{text = opts.text, on_click = opts.on_click}
		w.focus_mode = .All
	case .Label:
		w.data = Label_Data{text = opts.text}
	case .Split:
		w.data = Split_Data{direction = opts.split}
	case .Tabs:
		w.data = Tabs_Data{active = 0}
	case .TextInput:
		w.data = Text_Input_Data{text = strings.clone(opts.text)}
		w.focus_mode = .All
	case:
		w.data = None_Data{}
	}

	//* The focus of a widget comes from its kind, unless the caller
	//* asks for another one.
	if opts.focus_mode != .None { w.focus_mode = opts.focus_mode }

	if parent != INVALID_WIDGET_ID {
		if Widget_Get(g, parent) == nil {
			log.warnf("the widget %q has no parent to go under", opts.name)
		} else {
			Widget_Attach(g, parent, w.id)
		}
	}
	//* A widget that is new has not been measured and has no place yet.
	invalidate(g, w.id, DIRTY_ALL)

	if kind := widget_kind(g, w); kind.construct != nil {
		kind.construct(g, w.id, w)
	}
	return w.id
}

//* Unlinks a widget from its parent and siblings. The widget keeps its
//* identity, so every reference to it stays valid — this is the core
//* primitive behind docking.
Widget_Detach :: proc(g: ^GUI, child: Widget_ID) {
	w := Widget_Get(g, child)
	if w == nil { return }

	old_parent := w.parent
	if w.parent != INVALID_WIDGET_ID {
		if p := Widget_Get(g, w.parent); p != nil {
			//* A tab host that loses a tab keeps showing a tab that is there.
			tab_host_forgets(g, p, child)
			if p.first_child == child { p.first_child = w.next_sibling }
			if p.last_child == child { p.last_child = w.prev_sibling }
		}
	}
	if w.prev_sibling != INVALID_WIDGET_ID {
		if s := Widget_Get(g, w.prev_sibling); s != nil { s.next_sibling = w.next_sibling }
	}
	if w.next_sibling != INVALID_WIDGET_ID {
		if s := Widget_Get(g, w.next_sibling); s != nil { s.prev_sibling = w.prev_sibling }
	}

	w.parent = INVALID_WIDGET_ID
	w.prev_sibling = INVALID_WIDGET_ID
	w.next_sibling = INVALID_WIDGET_ID
	//* A widget that leaves the tree cannot have the keyboard: the
	//* keyboard belongs to the tree.
	if g.focused == child { focus_clear(g) }
	//* A panel that changes place starts out with the size the layout gives it:
	//* the size it was pulled to belonged to the old place.
	w.manual_w = false
	w.manual_h = false
	//* The widget left its place, and the parent it left has one child
	//* less: both of them are out of date.
	if old_parent != INVALID_WIDGET_ID {
		invalidate(g, old_parent, DIRTY_ALL)
	}
	invalidate(g, w.id, DIRTY_ALL)
}

//* A tab host that loses a tab keeps showing a tab that is there: the tab
//* that was showing moves along, or the one before it takes its place.
//* Without this the host would show a tab that does not exist.
tab_host_forgets :: proc(g: ^GUI, host: ^Widget, child: Widget_ID) {
	if host == nil { return }
	if host.type != .Tabs && host.type != .TabContainer { return }
	index := Widget_Index_Of(g, host.id, child)
	if index < 0 { return }
	active := tabs_active(host)
	if index == active {
		set_tab_active(g, host, max(active - 1, 0))
	} else if index < active {
		set_tab_active(g, host, active - 1)
	}
}

//* The tab of a tab host that is showing.
set_tab_active :: proc(g: ^GUI, host: ^Widget, active: int) {
	if host == nil { return }
	changed := false
	#partial switch &d in host.data {
	case Tabs_Data:
		changed = d.active != active
		d.active = active
	case Tab_Container_Data:
		changed = d.active != active
		d.active = active
	}
	//* Another tab is showing now: the one that was showing keeps no
	//* geometry, and the one that is showing now takes the place.
	if changed {
		invalidate(g, host.id, Dirty_Flags{.Measure, .Arrange, .Visual, .Hit})
	}
}

//* Moves a widget under a new parent, preserving its identity.
Widget_Attach :: proc(g: ^GUI, parent, child: Widget_ID) {
	if parent == INVALID_WIDGET_ID { return }
	//* A widget cannot go under itself, and it cannot go under one of
	//* its own children: the tree has to stay a tree.
	if parent == child { return }
	if is_descendant(g, child, parent) { return }

	Widget_Detach(g, child)

	w := Widget_Get(g, child)
	p := Widget_Get(g, parent)
	if w == nil || p == nil { return }

	w.parent = parent
	w.prev_sibling = p.last_child
	w.next_sibling = INVALID_WIDGET_ID
	if p.last_child != INVALID_WIDGET_ID {
		if s := Widget_Get(g, p.last_child); s != nil { s.next_sibling = child }
	} else {
		p.first_child = child
	}
	p.last_child = child
	//* The widget has a new place, and the parent has one child more.
	invalidate(g, parent, DIRTY_ALL)
	invalidate(g, w.id, DIRTY_ALL)
}

//* Moves a widget under a new parent at a given place in the child
//* list. Docking uses this to put a panel in front of the others.
Widget_Insert_At :: proc(g: ^GUI, parent, child: Widget_ID, index: int) {
	if parent == INVALID_WIDGET_ID { return }
	//* A widget cannot go under itself, and it cannot go under one of
	//* its own children: the tree has to stay a tree.
	if parent == child { return }
	if is_descendant(g, child, parent) { return }

	Widget_Detach(g, child)

	w := Widget_Get(g, child)
	p := Widget_Get(g, parent)
	if w == nil || p == nil { return }
	at := index
	if at < 0 { at = 0 }

	//* The child that currently sits at `at`.
	prev := INVALID_WIDGET_ID
	next := p.first_child
	i := 0
	for next != INVALID_WIDGET_ID && i < at {
		c := Widget_Get(g, next)
		if c == nil {
			//* The child is not there any more, so the list ends
			//* here: the widget goes at the end of it.
			next = INVALID_WIDGET_ID
			break
		}
		prev = next
		next = c.next_sibling
		i += 1
	}

	w.parent = parent
	w.prev_sibling = prev
	w.next_sibling = next
	if prev != INVALID_WIDGET_ID {
		if s := Widget_Get(g, prev); s != nil { s.next_sibling = child }
	} else {
		p.first_child = child
	}
	if next != INVALID_WIDGET_ID {
		if s := Widget_Get(g, next); s != nil { s.prev_sibling = child }
	} else {
		p.last_child = child
	}
	//* A tab host that gets a tab in front of the one it is showing
	//* keeps showing that one.
	if p.type == .Tabs || p.type == .TabContainer {
		active := tabs_active(p)
		if at <= active { set_tab_active(g, p, active + 1) }
	}
	//* The widget has a new place, and the parent has one child more.
	invalidate(g, parent, DIRTY_ALL)
	invalidate(g, w.id, DIRTY_ALL)
}

//* The place a child holds in its parent's child list, or -1.
Widget_Index_Of :: proc(g: ^GUI, parent, child: Widget_ID) -> int {
	p := Widget_Get(g, parent)
	if p == nil { return -1 }
	index := 0
	cur := p.first_child
	for cur != INVALID_WIDGET_ID {
		if cur == child { return index }
		c := Widget_Get(g, cur)
		if c == nil { break }
		cur = c.next_sibling
		index += 1
	}
	return -1
}

//* Number of children of a widget.
Widget_Child_Count :: proc(g: ^GUI, id: Widget_ID) -> int {
	w := Widget_Get(g, id)
	if w == nil { return 0 }
	count := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		count += 1
		child = c.next_sibling
	}
	return count
}

//* == Destroying ==
//* Destroys a widget and everything under it. Returns false when the handle
//* named no widget, or when the widget is the root: the root is the tree
//* itself, so it cannot go away.
Widget_Free :: proc(g: ^GUI, id: Widget_ID) -> bool {
	if g == nil { return false }
	w := Widget_Get(g, id)
	if w == nil { return false }
	if id == g.root { return false }
	if w.freeing { return false }
	w.freeing = true

	subtree: [dynamic]Widget_ID
	defer delete(subtree)
	collect_subtree(g, id, &subtree)

	//* Every widget of the subtree is marked as going away before any hook is
	//* called: a hook that destroys one of them finds it already gone, and the
	//* slot of a widget is given back once.
	for gone in subtree {
		gone_widget := Widget_Get(g, gone)
		if gone_widget == nil { continue }
		gone_widget.freeing = true
	}

	//* The widget that has the keyboard gives it up, whether it is the
	//* one that is destroyed or one of the widgets under it.
	for gone in subtree {
		if g.focused == gone {
			focus_clear(g)
			break
		}
	}

	//* The parent it left has one child less, so it is out of date.
	Widget_Detach(g, id)

	//* Every widget of the subtree leaves its place in the tree as
	//* well, so that the links of the tree are whole at every step.
	for gone in subtree {
		Widget_Detach(g, gone)
	}

	//* Everything that holds on to one of the widgets lets go of it.
	for gone in subtree {
		widget_forget(g, gone)
	}

	//* What the widgets own is given back, and their slots are free again.
	for gone in subtree {
		gone_widget := Widget_Get(g, gone)
		if gone_widget == nil { continue }
		//* The class of the widget is told that it goes away, before its data
		//* is given back.
		widget_notify_destroy(g, gone, gone_widget)
		widget_release_data(g, gone_widget)
		slot := int(gone.index) - 1
		gone_widget.id = INVALID_WIDGET_ID
		append(&g.free_widgets, u32(slot))
	}

	return true
}

//* The widget and everything under it, the children before their parent.
collect_subtree :: proc(g: ^GUI, id: Widget_ID, out: ^[dynamic]Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		collect_subtree(g, child, out)
		child = c.next_sibling
	}
	append(out, id)
}

//* Everything that holds on to a widget lets go of it when the widget
//* is destroyed: the pointer, the capture of the mouse, the drag, the
//* resize, the floating panels and the other widgets.
widget_forget :: proc(g: ^GUI, id: Widget_ID) {
	if g.hot == id { g.hot = INVALID_WIDGET_ID }
	if g.active == id { g.active = INVALID_WIDGET_ID }
	if g.slider_active == id { g.slider_active = INVALID_WIDGET_ID }
	if g.resize_hover == id { g.resize_hover = INVALID_WIDGET_ID }
	if g.resize.widget == id { g.resize = resize_state_none() }
	//* The drag that is running: the widget that is dragged is gone,
	//* so the drag cannot go on.
	if g.drag.widget == id { g.drag = drag_state_none() }
	if g.drag.target == id { g.drag.target = INVALID_WIDGET_ID }
	if g.drag.tab_host == id { g.drag.tab_host = INVALID_WIDGET_ID }
	dock_plan_forget(&g.drag.plan, id)

	//* The floating panels. The panel that is gone is taken out of the
	//* list, and the ones behind it move up, so the drag and the
	//* resize are told about it.
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		if g.floats[i].widget != id { continue }
		draw_list_destroy(&g.floats[i].draw)
		ordered_remove(&g.floats, i)
		if g.drag.float_index == i { g.drag.float_index = FLOAT_NONE }
		else if g.drag.float_index > i { g.drag.float_index -= 1 }
		if g.resize.float_index == i { g.resize.float_index = FLOAT_NONE }
		else if g.resize.float_index > i { g.resize.float_index -= 1 }
	}

	//* The other widgets: the neighbours of the focus and the thing a
	//* tooltip is about.
	for other in g.widgets {
		if other == nil { continue }
		widget_unreference(other, id)
	}

	//* The connections to the signals of the widget go with it.
	for i := len(g.signal_conns) - 1; i >= 0; i -= 1 {
		if g.signal_conns[i].id != id { continue }
		ordered_remove(&g.signal_conns, i)
	}

	//* A popup that is gone is closed: it is not on the screen any
	//* more.
	for i := len(g.popups) - 1; i >= 0; i -= 1 {
		if g.popups[i].id != id { continue }
		ordered_remove(&g.popups, i)
	}
}

//* Takes a widget out of the references of another widget: the links of
//* the tree, the neighbours of the focus and the target of a tooltip.
widget_unreference :: proc(w: ^Widget, id: Widget_ID) {
	if w == nil { return }
	if w.parent == id { w.parent = INVALID_WIDGET_ID }
	if w.first_child == id { w.first_child = INVALID_WIDGET_ID }
	if w.last_child == id { w.last_child = INVALID_WIDGET_ID }
	if w.prev_sibling == id { w.prev_sibling = INVALID_WIDGET_ID }
	if w.next_sibling == id { w.next_sibling = INVALID_WIDGET_ID }
	for &neighbour in w.focus_neighbour {
		if neighbour == id { neighbour = INVALID_WIDGET_ID }
	}
	if w.focus_next == id { w.focus_next = INVALID_WIDGET_ID }
	if w.focus_previous == id { w.focus_previous = INVALID_WIDGET_ID }
	#partial switch &d in w.data {
	case Tooltip_Data:
		if d.target == id { d.target = INVALID_WIDGET_ID }
	}
}

//* Gives back what a widget owns. The texts of a widget are the texts of the
//* program, and they are not freed; what the widget made for itself is.
widget_release_data :: proc(g: ^GUI, w: ^Widget) {
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		delete(d.text)
	case Popup_Menu_Data:
		delete(d.items)
	case Search_Field_Data:
		delete(d.text)
	case Item_List_Data:
		delete(d.items)
	case Tree_Data:
		delete(d.items)
	case Option_Button_Data:
		delete(d.items)
	case Menu_Button_Data:
		delete(d.items)
	case Combo_Box_Data:
		delete(d.items)
	case Context_Menu_Data:
		delete(d.items)
	case Command_Palette_Data:
		delete(d.text)
		delete(d.commands)
	case Segmented_Data:
		delete(d.items)
	case Chat_Input_Data:
		//* The lines of a chat are in the arena of the GUI, so only
		//* the list itself is given back.
		delete(d.lines)
	case Virtual_List_Data:
		if d.list != nil { delete(d.list.selected) }
	case Data_Table_Data:
		if d.table != nil {
			for &row in d.table.rows {
				for &value in row.values { delete(value) }
				delete(row.values)
			}
			delete(d.table.rows)
			delete(d.table.columns)
		}
	case Chart_Data:
		if d.chart != nil {
			for &series in d.chart.series { delete(series.values) }
			delete(d.chart.series)
			delete(d.chart.labels)
		}
	case Node_Graph_Data:
		if d.graph != nil {
			for &node in d.graph.nodes { delete(node.ports) }
			delete(d.graph.nodes)
			delete(d.graph.wires)
		}
	case Rich_Text_Editor_Data:
		if d.state != nil {
			delete(d.state.text)
			delete(d.state.cursors)
		}
	case Custom_Data:
		//* The data of a program is given back by the program.
		if d.destroy != nil && d.user != nil { d.destroy(d.user) }
	}
	w.data = None_Data{}
}
