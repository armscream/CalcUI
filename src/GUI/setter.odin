//* The setters of the widgets: each one says what it made stale, so the
//* tree is measured and laid out again where it has to be, and nowhere
//* else.

package GUI

//* == The setters of the widgets ==
//* A widget is a struct and its fields are open, so a program can write
//* to a widget itself. A program that does that, without these setters,
//* can call `GUI_Invalidate_All` to have the whole tree done again.

import "core:log"
import "core:mem"
import "core:strings"

//* == The text ==

//* Sets the text of a widget: the labels, the buttons, the text fields,
//* the search and chat fields, the command palette, the toast and the
//* tooltip. The size of the widget can change with the text, so the
//* widget is measured again.
//
//* The text of the widgets that keep a buffer of their own belongs to the
//* widget. The copy is made before the old text is given back, so the text
//* of the caller may be the text of the widget: `Widget_Set_Text(g, id,
//* Command_Palette_Text(g, id)[:2])` is allowed.
Widget_Set_Text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	changed := false
	reset_palette := false
	#partial switch &d in w.data {
	case Label_Data:
		changed = d.text != text
		d.text = text
	case Button_Data:
		changed = d.text != text
		d.text = text
	case Text_Input_Data:
		//* The buffer of a text field belongs to the widget.
		if d.text != text {
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			//* The caret goes to the end of the new text.
			d.caret = len(text)
			d.sel_start = d.caret
			d.sel_end = d.caret
			changed = true
		}
	case Check_Box_Data:
		changed = d.text != text
		d.text = text
	case Link_Button_Data:
		changed = d.text != text
		d.text = text
	case Menu_Button_Data:
		changed = d.text != text
		d.text = text
	case Rich_Text_Data:
		changed = d.text != text
		d.text = text
	case Text_Edit_Data:
		//* The buffer of a text edit belongs to the widget.
		if d.text != text {
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			d.caret = len(text)
			d.sel_start = d.caret
			d.sel_end = d.caret
			changed = true
		}
	case Search_Field_Data:
		if d.text != text {
			//* The text of a search field belongs to the widget.
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			changed = true
		}
	case Chat_Input_Data:
		if d.text != text {
			//* The text of a chat field belongs to the widget.
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			changed = true
		}
	case Command_Palette_Data:
		if d.text != text {
			//* The text of a command palette belongs to the widget.
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			changed = true
			//* The filter has changed: the command that was picked is
			//* not one of the commands that are left.
			reset_palette = true
		}
	case Toast_Data:
		changed = d.text != text
		d.text = text
	case Tooltip_Data:
		changed = d.text != text
		d.text = text
	case Toggle_Switch_Data:
		changed = d.text != text
		d.text = text
	case Check_Button_Data:
		changed = d.text != text
		d.text = text
	case Dialog_Data:
		changed = d.text != text
		d.text = text
	case Rich_Text_Editor_Data:
		//* The text of the editor belongs to the editor.
		if d.state != nil && d.state.text != text {
			new_text := strings.clone(text)
			delete(d.state.text)
			d.state.text = new_text
			//* The cursor goes to the end of the new text.
			clear(&d.state.cursors)
			append(&d.state.cursors, Rich_Cursor{caret = len(text), sel_start = len(text), sel_end = len(text)})
			d.state.selection.anchor = len(text)
			d.state.selection.mode = .Character
			d.state.selection.dragging = false
			changed = true
		}
	}
	if !changed { return }
	//* The selection of a command palette is the number of a command that
	//* the filter lets through. The filter has changed, so the number
	//* that was picked names no command any more: the selection starts
	//* again at the first command that is left.
	if reset_palette { command_palette_reset(g, id) }
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* Sets the rules of a text box: how long the text may be, and which
//* characters may go into it. The rules are kept when the text is typed
//* and when it is pasted.
Widget_Set_Text_Rules :: proc(g: ^GUI, id: Widget_ID, rules: Text_Rules) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.rules = rules
	case Text_Edit_Data:
		d.rules = rules
	case Rich_Text_Editor_Data:
		if d.state != nil {d.state.rules = rules}
	}
}

Widget_Set_Style :: proc(g: ^GUI, id: Widget_ID, style: Style) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.style == style { return }
	//* The size of the widget depends on the padding of the box and on
	//* the parts of the text that change how big the text is. A colour
	//* does not change it, so a widget that only changes its colour is
	//* not measured again.
	measured := style_size_of(w.style) != style_size_of(style)
	w.style = style
	w.style_cache.valid = false
	flags := Dirty_Flags{.Visual}
	if measured { flags += Dirty_Flags{.Measure} }
	invalidate(g, id, flags)
}

//* The parts of a text style that change the size of the text. The set
//* of fields is kept as well: a style that says that the size is set
//* and a style that says nothing about it are not the same, even when
//* the numbers are the same.
text_style_size_of :: proc(ts: Text_Style) -> Text_Style {
	return Text_Style{
		set = ts.set,
		family = ts.family,
		size = ts.size,
		wrap = ts.wrap,
		spacing = ts.spacing,
		transform = ts.transform,
	}
}

Widget_Set_Variation :: proc(g: ^GUI, id: Widget_ID, variation: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.variation == variation { return }
	w.variation = variation
	w.style_cache.valid = false
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* Says whether the widget takes the look of the theme for its kind.
Widget_Set_Use_Theme :: proc(g: ^GUI, id: Widget_ID, use_theme: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.use_theme == use_theme { return }
	w.use_theme = use_theme
	w.style_cache.valid = false
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* Sets the smallest size the widget asks for. The text of the widget
//* can ask for more, so the size that is measured can be bigger.
Widget_Set_Min_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.base_min_size == size { return }
	w.base_min_size = size
	w.min_size = size
	invalidate(g, id, Dirty_Flags{.Measure})
}
//* Sets the smallest size the program asks for. It wins over the size
//* of the text of the widget.
Widget_Set_Custom_Min_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.custom_min_size == size { return }
	w.custom_min_size = size
	invalidate(g, id, Dirty_Flags{.Measure})
}

//* Sets the largest size the widget may have. A widget that is given
//* more space than this does not take it.
Widget_Set_Max_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.custom_max_size == size { return }
	w.custom_max_size = size
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the share of the space of the parent the widget takes when
//* there is space left over.
Widget_Set_Weight :: proc(g: ^GUI, id: Widget_ID, weight: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.weight == weight { return }
	w.weight = weight
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the flags that say how the widget takes the room of its parent
//* along the horizontal axis and along the vertical one. A widget that
//* expands takes a share of the room that is left over, and a widget
//* that does not expand takes only its minimum size. A widget that
//* fills takes the room it is given, and a widget that shrinks takes
//* only its minimum size and is centred in the room it would have had.
//*
//* A set of flags with nothing in it is a set of flags: the widget takes
//* only its minimum size and leaves the rest of its room empty. A widget
//* that says nothing in the options gets the default, which is `.Fill`
//* and `.Expand` on both axes.
//*
//* The flags change the room of the children of the parent, so the tree
//* is laid out again.
Widget_Set_Size_Flags :: proc(g: ^GUI, id: Widget_ID, horizontal, vertical: Size_Flags) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.size_flags_h == horizontal && w.size_flags_v == vertical { return }
	w.size_flags_h = horizontal
	w.size_flags_v = vertical
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the ratio that says how much of its share of the room of the
//* parent the widget takes. The share of a widget is its weight times
//* its ratio, so a ratio of 0 gives a share of nothing and the widget
//* takes only its minimum size.
//*
//* The ratio changes the room of the children of the parent, so the tree
//* is laid out again.
Widget_Set_Stretch_Ratio :: proc(g: ^GUI, id: Widget_ID, ratio: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.stretch_ratio == ratio { return }
	w.stretch_ratio = ratio
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the direction the widget grows in: from the left to the right or
//* from the right to the left. A container that stacks its children
//* along the horizontal axis puts them in the other order when the
//* direction is from the right to the left. The direction does not
//* change the room the children get, only the order they are put in.
//*
//* The direction changes the order of the children, so the tree is laid
//* out again.
Widget_Set_Layout_Direction :: proc(g: ^GUI, id: Widget_ID, direction: Layout_Direction) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.layout_direction == direction { return }
	w.layout_direction = direction
	invalidate(g, id, Dirty_Flags{.Arrange})
}

Widget_Set_Separation :: proc(g: ^GUI, id: Widget_ID, separation: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.separation == separation { return }
	w.separation = separation
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the anchors of the widget: where it sits in its parent.
Widget_Set_Anchors :: proc(g: ^GUI, id: Widget_ID, anchors: Anchor) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.anchors == anchors { return }
	w.anchors = anchors
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Sets the direction the widget grows in when it is given more room
//* than it asks for.
Widget_Set_Grow :: proc(g: ^GUI, id: Widget_ID, horizontal, vertical: Grow) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.grow_h == horizontal && w.grow_v == vertical { return }
	w.grow_h = horizontal
	w.grow_v = vertical
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Sets the offsets of the widget: how far it sits from its anchors.
Widget_Set_Offsets :: proc(g: ^GUI, id: Widget_ID, offsets: Offset) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.offsets == offsets { return }
	w.offsets = offsets
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Shows a widget or takes it away. A widget that is not shown is
//* neither drawn nor hit. The room of the widget in its parent does not
//* change: the layout counts the children that are not shown as well, so
//* a visibility change measures nothing and arranges nothing.
Widget_Set_Visible :: proc(g: ^GUI, id: Widget_ID, visible: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	shown := .Visible in w.state
	if shown == visible { return }
	if visible {
		w.state += Widget_State{.Visible}
	} else {
		w.state -= Widget_State{.Visible}
	}
	//* A widget that is not shown cannot have the keyboard.
	focus_release(g)
	//* A widget that is not shown cannot hold the pointer.
	if g.active == id { g.active = INVALID_WIDGET_ID }
	if g.slider_active == id { g.slider_active = INVALID_WIDGET_ID }
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Enables a widget or takes it away. A widget that is not enabled is
//* not drawn as it is and does not take the mouse.
Widget_Set_Enabled :: proc(g: ^GUI, id: Widget_ID, enabled: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	on := .Enabled in w.state
	if on == enabled { return }
	if enabled {
		w.state += Widget_State{.Enabled}
	} else {
		w.state -= Widget_State{.Enabled}
	}
	//* A widget that is not enabled cannot have the keyboard, and it
	//* does not hold the pointer.
	focus_release(g)
	if g.active == id { g.active = INVALID_WIDGET_ID }
	if g.slider_active == id { g.slider_active = INVALID_WIDGET_ID }
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Sets the name of the widget. The name is shown in the title bar of
//* a panel and in the tab of a panel.
Widget_Set_Name :: proc(g: ^GUI, id: Widget_ID, name: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.name == name { return }
	w.name = name
	invalidate(g, id, Dirty_Flags{.Visual})
}

Widget_Set_Mouse_Filter :: proc(g: ^GUI, id: Widget_ID, filter: Mouse_Filter) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.mouse_filter == filter { return }
	w.mouse_filter = filter
	invalidate(g, id, Dirty_Flags{.Hit})
}

//* Sets the text that is shown when the pointer rests on the widget.
Widget_Set_Tooltip :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.tooltip_text == text { return }
	w.tooltip_text = text
	invalidate(g, id, Dirty_Flags{.Visual})
}

Widget_Set_Focus_Mode :: proc(g: ^GUI, id: Widget_ID, mode: Focus_Mode) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.focus_mode == mode { return }
	w.focus_mode = mode
	//* A widget that cannot be focused does not have the keyboard.
	focus_release(g)
	invalidate(g, id, Dirty_Flags{.Hit})
}

//* Sets the place of the widget in the order of the tab key. The widget
//* with the lowest number comes first, and the tree breaks the tie.
Widget_Set_Tab_Index :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.tab_index == index { return }
	w.tab_index = index
}

//* == The place and the look of the widget ==

//* Sets the place of the widget in the order of the drawing: the widget
//* with the highest number is drawn last, so it lies on top of the others.
//* The place of the widget does not change: the order of the drawing and
//* the order of the hit test change, and nothing else.
Widget_Set_Z_Index :: proc(g: ^GUI, id: Widget_ID, z_index: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.z_index == z_index { return }
	w.z_index = z_index
	//* The order of the drawing changes, and the widget that lies on
	//* top is the one that takes the mouse.
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Says whether the widget cuts its children to its own rect.
Widget_Set_Clip_Contents :: proc(g: ^GUI, id: Widget_ID, clip: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.clip_contents == clip { return }
	w.clip_contents = clip
	//* The look of the widget changes: what is drawn under it is cut
	//* off or is not.
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Sets the size the program gives the widget. A size of zero in one
//* direction means that the program does not fix that direction, and the
//* layout gives the widget the room it asks for.
Widget_Set_Manual_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	wide := size.x > 0
	high := size.y > 0
	if w.manual_size == size && w.manual_w == wide && w.manual_h == high { return }
	w.manual_size = size
	w.manual_w = wide
	w.manual_h = high
	//* The widget is placed again, and it is hit in another place.
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Says whether the widget can be dragged by its title bar.
Widget_Set_Draggable :: proc(g: ^GUI, id: Widget_ID, draggable: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.draggable == draggable { return }
	w.draggable = draggable
	//* A widget that can be dragged has a title bar, and it takes the
	//* mouse on it.
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* == The focus ==

//* Sets the widget the arrow keys go to in one direction: 0 is left, 1 is
//* up, 2 is right and 3 is down. The neighbour has to be a widget that is
//* there. A widget may be its own neighbour: the command palette names
//* itself on every side, so that the arrow keys stay where they are. The
//* empty handle takes the neighbour away.
//
//* The order of the focus is worked out when a key is pressed, and it is
//* never kept, so nothing is marked out of date here.
Widget_Set_Focus_Neighbour :: proc(g: ^GUI, id: Widget_ID, direction: int, neighbour: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if direction < 0 || direction >= len(w.focus_neighbour) {
		log.warnf(
			"the focus neighbour of the widget %q is set for the direction %d, which is not one of the four directions",
			w.name,
			direction,
		)
		return
	}
	if !focus_target_ok(g, w, neighbour) { return }
	if w.focus_neighbour[direction] == neighbour { return }
	w.focus_neighbour[direction] = neighbour
}

//* Sets the widget the tab key goes to after this one. The order of the
//* focus is worked out when a key is pressed, so nothing is marked out of
//* date here.
Widget_Set_Focus_Next :: proc(g: ^GUI, id: Widget_ID, next: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !focus_target_ok(g, w, next) { return }
	if w.focus_next == next { return }
	w.focus_next = next
}

//* Sets the widget the tab key comes back to from this one. The order of
//* the focus is worked out when a key is pressed, so nothing is marked
//* out of date here.
Widget_Set_Focus_Previous :: proc(g: ^GUI, id: Widget_ID, previous: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !focus_target_ok(g, w, previous) { return }
	if w.focus_previous == previous { return }
	w.focus_previous = previous
}

//* True when the widget may be named in the focus order of another one.
//* The empty handle takes the link away; every other handle has to name
//* a widget that is there. A widget may name itself.
focus_target_ok :: proc(g: ^GUI, w: ^Widget, target: Widget_ID) -> bool {
	if target == INVALID_WIDGET_ID { return true }
	if Widget_Get(g, target) == nil {
		log.warnf(
			"the focus neighbour %d of the widget %q is not a widget that is there",
			int(target.index),
			w.name,
		)
		return false
	}
	return true
}

//* == The tree ==

//* Moves a widget under a new parent. The widget keeps its identity, and
//* the tree is measured and laid out again where it has to be.
//
//* A parent that is not there is refused: the tree is left as it was.
//* `Widget_Detach` is the way to take a widget out of the tree.
Widget_Set_Parent :: proc(g: ^GUI, parent, child: Widget_ID) {
	if parent == INVALID_WIDGET_ID {
		log.warnf("the widget %d cannot go under a parent that is not there", int(child.index))
		return
	}
	if Widget_Get(g, parent) == nil {
		log.warnf(
			"the widget %d cannot go under the parent %d, which is not a widget that is there",
			int(child.index),
			int(parent.index),
		)
		return
	}
	Widget_Attach(g, parent, child)
}

//* Moves a widget under a new parent. This is the old name of
//* `Widget_Set_Parent`, and it does the same.
Widget_Reparent :: proc(g: ^GUI, parent, child: Widget_ID) {
	Widget_Set_Parent(g, parent, child)
}

//* The children of a widget, in the order of the tree. The slice belongs
//* to the caller, who gives the memory back with `delete(children,
//* allocator)`.
Widget_Children :: proc(
	g: ^GUI,
	id: Widget_ID,
	allocator: mem.Allocator = context.allocator,
) -> []Widget_ID {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	count := Widget_Child_Count(g, id)
	if count == 0 { return nil }
	children := make([]Widget_ID, count, allocator)
	i := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID && i < count {
		c := Widget_Get(g, child)
		if c == nil { break }
		children[i] = child
		i += 1
		child = c.next_sibling
	}
	return children
}

Widget_Set_Split_Direction :: proc(g: ^GUI, id: Widget_ID, direction: Split_Direction) {
	w := Widget_Get(g, id)
	if w == nil { return }
	changed := false
	#partial switch &d in w.data {
	case Split_Data:
		changed = d.direction != direction
		d.direction = direction
	}
	if changed {
		//* The axis of the split changed: every child is placed again.
		invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
	}
}

//* Sets the number of columns a grid puts its children in.
Widget_Set_Grid_Columns :: proc(g: ^GUI, id: Widget_ID, columns: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	changed := false
	#partial switch &d in w.data {
	case Grid_Data:
		changed = d.columns != columns
		d.columns = columns
	}
	if changed {
		invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
	}
}

//* Sets the space a margin container keeps between its child and its edges.
Widget_Set_Margin :: proc(g: ^GUI, id: Widget_ID, margin: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	changed := false
	#partial switch &d in w.data {
	case Margin_Data:
		changed = d.margin != margin
		d.margin = margin
	}
	if changed {
		invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
	}
}

//* Sets the ratio an aspect ratio container keeps its child at.
Widget_Set_Aspect_Ratio :: proc(g: ^GUI, id: Widget_ID, ratio: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	changed := false
	#partial switch &d in w.data {
	case Aspect_Data:
		changed = d.ratio != ratio
		d.ratio = ratio
	}
	if changed {
		invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
	}
}

//* Asks for the whole tree to be measured and laid out again. A program
//* that writes to a widget itself, without the setters, calls this so
//* that nothing is left stale.
GUI_Invalidate_All :: proc(g: ^GUI) {
	invalidate_full(g)
}

//* Asks for the widgets that take their look from the theme to be
//* measured and drawn again. A theme that is changed after it is put on
//* the GUI says so by itself, so this is only needed for a theme that is
//* changed behind the back of the toolkit.
GUI_Invalidate_Theme :: proc(g: ^GUI) {
	if g == nil { return }
	g.style_epoch += 1
	style_cache_drop(g)
	invalidate_theme(g)
}
