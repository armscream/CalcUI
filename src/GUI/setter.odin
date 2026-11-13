//* Widget setters update the relevant dirty state so only affected parts
//* of the tree are measured, arranged, drawn, or hit-tested.

package GUI

//* Widgets are public structs, so direct field changes are possible.
//* Call `GUI_Invalidate_All` after changing fields without a setter.

import "core:log"
import "core:mem"
import "core:strings"

//* == Text ==

//* Sets widget text and invalidates measurement and drawing when it changes.
//* Widget-owned buffers are copied before the old text is released, so the
//* input may refer to the widget's current text.
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
	case Text_Box_Data:
		if d.text != text {
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
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
	case Search_Field_Data:
		if d.text != text {
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			d.caret = len(text)
			changed = true
		}
	case Chat_Input_Data:
		if d.text != text {
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			changed = true
		}
	case Command_Palette_Data:
		if d.text != text {
			new_text := strings.clone(text)
			delete(d.text)
			d.text = new_text
			changed = true
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
	case Dialog_Data:
		changed = d.text != text
		d.text = text
	case Rich_Text_Editor_Data:
		if d.state != nil && d.state.text != text {
			new_text := strings.clone(text)
			delete(d.state.text)
			d.state.text = new_text
			clear(&d.state.cursors)
			append(&d.state.cursors, Rich_Cursor{caret = len(text), sel_start = len(text), sel_end = len(text)})
			d.state.selection.anchor = len(text)
			d.state.selection.mode = .Character
			d.state.selection.dragging = false
			changed = true
		}
	}
	if !changed { return }
	//* A changed palette filter invalidates its current command selection.
	if reset_palette { command_palette_reset(g, id) }
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* Sets the input rules for a text box or rich-text editor.
Widget_Set_Text_Rules :: proc(g: ^GUI, id: Widget_ID, rules: Text_Rules) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		d.rules = rules
	case Rich_Text_Editor_Data:
		if d.state != nil {d.state.rules = rules}
	}
}

Widget_Set_Style :: proc(g: ^GUI, id: Widget_ID, style: Style) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.style == style { return }
	//* Only size-affecting style changes require remeasurement.
	measured := style_size_of(w.style) != style_size_of(style)
	w.style = style
	w.style_cache.valid = false
	flags := Dirty_Flags{.Visual}
	if measured { flags += Dirty_Flags{.Measure} }
	invalidate(g, id, flags)
}

//* Returns the text-style fields that affect measurement.
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

//* Sets whether the widget uses its theme style.
Widget_Set_Use_Theme :: proc(g: ^GUI, id: Widget_ID, use_theme: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.use_theme == use_theme { return }
	w.use_theme = use_theme
	w.style_cache.valid = false
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* Sets the widget's base minimum size. Text may require more space.
Widget_Set_Min_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.base_min_size == size { return }
	w.base_min_size = size
	w.min_size = size
	invalidate(g, id, Dirty_Flags{.Measure})
}

//* Sets the minimum size imposed by the program.
Widget_Set_Custom_Min_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.custom_min_size == size { return }
	w.custom_min_size = size
	invalidate(g, id, Dirty_Flags{.Measure})
}

//* Sets the maximum size the widget may occupy.
Widget_Set_Max_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.custom_max_size == size { return }
	w.custom_max_size = size
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the widget's share of leftover parent space.
Widget_Set_Weight :: proc(g: ^GUI, id: Widget_ID, weight: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.weight == weight { return }
	w.weight = weight
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets horizontal and vertical sizing behavior.
//* Empty flags use minimum size without filling or expanding.
//* Unset flags use the default `.Fill` and `.Expand` behavior.
Widget_Set_Size_Flags :: proc(g: ^GUI, id: Widget_ID, horizontal, vertical: Size_Flags) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.size_flags_h == horizontal && w.size_flags_v == vertical { return }
	w.size_flags_h = horizontal
	w.size_flags_v = vertical
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the fraction of its weighted parent space the widget uses.
//* A ratio of zero leaves it at its minimum size.
Widget_Set_Stretch_Ratio :: proc(g: ^GUI, id: Widget_ID, ratio: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.stretch_ratio == ratio { return }
	w.stretch_ratio = ratio
	invalidate(g, id, Dirty_Flags{.Arrange})
}

//* Sets the widget's layout direction. Horizontal containers reverse
//* child order when set to right-to-left.
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

//* Sets the widget's anchors within its parent.
Widget_Set_Anchors :: proc(g: ^GUI, id: Widget_ID, anchors: Anchor) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.anchors == anchors { return }
	w.anchors = anchors
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Sets how the widget grows when given extra space.
Widget_Set_Grow :: proc(g: ^GUI, id: Widget_ID, horizontal, vertical: Grow) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.grow_h == horizontal && w.grow_v == vertical { return }
	w.grow_h = horizontal
	w.grow_v = vertical
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Sets the widget's offsets from its anchors.
Widget_Set_Offsets :: proc(g: ^GUI, id: Widget_ID, offsets: Offset) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.offsets == offsets { return }
	w.offsets = offsets
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Shows or hides a widget. Visibility does not affect layout.
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
	//* Hidden widgets cannot retain keyboard or pointer interaction.
	focus_release(g)
	if g.active == id { g.active = INVALID_WIDGET_ID }
	if g.slider_active == id { g.slider_active = INVALID_WIDGET_ID }
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Enables or disables a widget's interaction.
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
	//* Disabled widgets cannot retain keyboard or pointer interaction.
	focus_release(g)
	if g.active == id { g.active = INVALID_WIDGET_ID }
	if g.slider_active == id { g.slider_active = INVALID_WIDGET_ID }
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Sets the widget's name, used by panel title bars and tabs.
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

//* Sets the text shown when the pointer rests on the widget.
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
	//* A widget that cannot be focused cannot retain keyboard focus.
	focus_release(g)
	invalidate(g, id, Dirty_Flags{.Hit})
}

//* Sets the widget's position in tab order. Lower indices come first;
//* the tree order breaks ties.
Widget_Set_Tab_Index :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.tab_index == index { return }
	w.tab_index = index
}

//* == Placement and appearance ==

//* Sets drawing order. Higher indices draw later and appear on top.
Widget_Set_Z_Index :: proc(g: ^GUI, id: Widget_ID, z_index: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.z_index == z_index { return }
	w.z_index = z_index
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Sets whether the widget clips its children to its own rectangle.
Widget_Set_Clip_Contents :: proc(g: ^GUI, id: Widget_ID, clip: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.clip_contents == clip { return }
	w.clip_contents = clip
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Sets the widget's fixed size. A zero axis remains layout-controlled.
Widget_Set_Manual_Size :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	wide := size.x > 0
	high := size.y > 0
	if w.manual_size == size && w.manual_w == wide && w.manual_h == high { return }
	w.manual_size = size
	w.manual_w = wide
	w.manual_h = high
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
}

//* Sets whether the widget can be dragged by its title bar.
Widget_Set_Draggable :: proc(g: ^GUI, id: Widget_ID, draggable: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.draggable == draggable { return }
	w.draggable = draggable
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* == Focus ==

//* Sets the directional focus target: 0 left, 1 up, 2 right, 3 down.
//* The target must exist. The widget may target itself; an empty handle
//* clears the link.
//*
//* Focus order is resolved when a key is pressed, so no invalidation is needed.
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

//* Sets the next widget in tab focus order. The order is resolved on key press.
Widget_Set_Focus_Next :: proc(g: ^GUI, id: Widget_ID, next: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !focus_target_ok(g, w, next) { return }
	if w.focus_next == next { return }
	w.focus_next = next
}

//* Sets the previous widget in tab focus order. The order is resolved on key press.
Widget_Set_Focus_Previous :: proc(g: ^GUI, id: Widget_ID, previous: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !focus_target_ok(g, w, previous) { return }
	if w.focus_previous == previous { return }
	w.focus_previous = previous
}

//* Checks whether a focus link points to an existing widget.
//* Empty handles clear links, and self-links are allowed.
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

//* == Tree ==

//* Moves a widget under a new parent. Its identity is unchanged.
//* Invalid parents are rejected; use `Widget_Detach` to remove a widget
//* from the tree.
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

//* Compatibility alias for `Widget_Set_Parent`.
Widget_Reparent :: proc(g: ^GUI, parent, child: Widget_ID) {
	Widget_Set_Parent(g, parent, child)
}

//* Returns the child handles in tree order. The caller owns the slice
//* and must release it with `delete(children, allocator)`.
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
		//* Changing the split axis changes child placement.
		invalidate(g, id, Dirty_Flags{.Arrange, .Hit})
	}
}

//* Sets the number of columns in a grid container.
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

//* Sets the space a margin container leaves around its child.
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

//* Sets the aspect ratio maintained by an aspect-ratio container.
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

//* Invalidates the entire tree after direct widget field changes.
GUI_Invalidate_All :: proc(g: ^GUI) {
	invalidate_full(g)
}

//* Invalidates theme-based styles after the theme is changed externally.
GUI_Invalidate_Theme :: proc(g: ^GUI) {
	if g == nil { return }
	g.style_epoch += 1
	style_cache_drop(g)
	invalidate_theme(g)
}