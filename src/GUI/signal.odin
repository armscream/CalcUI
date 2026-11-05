//* The signals of a widget: every widget has the same set of them, so a
//* program can connect to any of them without the tree knowing what kind of
//* widget it is. A signal that is not connected is nil, and firing it costs
//* nothing but the check.

package GUI

//* == Signals ==

Signals :: struct {
	//* The widget was pressed. A button fires it when the pointer is
	//* let go over it.
	on_pressed: proc(g: ^GUI, id: Widget_ID),
	on_toggled: proc(g: ^GUI, id: Widget_ID, on: bool),
	on_value_changed: proc(g: ^GUI, id: Widget_ID, value: f32),
	on_colour_changed: proc(g: ^GUI, id: Widget_ID, colour: Colour),
	on_text_changed: proc(g: ^GUI, id: Widget_ID, text: string),
	on_item_selected: proc(g: ^GUI, id: Widget_ID, index: int),
	//* The widget was submitted: the enter key in a text field, or a
	//* double click in a list.
	on_submitted: proc(g: ^GUI, id: Widget_ID, text: string),
	on_focus_entered: proc(g: ^GUI, id: Widget_ID),
	on_focus_exited: proc(g: ^GUI, id: Widget_ID),
	on_dragged: proc(g: ^GUI, id: Widget_ID, delta: Vec2),
	on_resized: proc(g: ^GUI, id: Widget_ID, size: Vec2),
}

signal_pressed :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_pressed != nil { w.signals.on_pressed(g, id) }
}

signal_toggled :: proc(g: ^GUI, id: Widget_ID, on: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_toggled != nil { w.signals.on_toggled(g, id, on) }
}

signal_value_changed :: proc(g: ^GUI, id: Widget_ID, value: f32) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_value_changed != nil { w.signals.on_value_changed(g, id, value) }
}

signal_colour_changed :: proc(g: ^GUI, id: Widget_ID, colour: Colour) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_colour_changed != nil { w.signals.on_colour_changed(g, id, colour) }
}

signal_text_changed :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_text_changed != nil { w.signals.on_text_changed(g, id, text) }
}

signal_item_selected :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_item_selected != nil { w.signals.on_item_selected(g, id, index) }
}

signal_submitted :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_submitted != nil { w.signals.on_submitted(g, id, text) }
}

signal_focus_entered :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_focus_entered != nil { w.signals.on_focus_entered(g, id) }
}

signal_focus_exited :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_focus_exited != nil { w.signals.on_focus_exited(g, id) }
}

signal_dragged :: proc(g: ^GUI, id: Widget_ID, delta: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_dragged != nil { w.signals.on_dragged(g, id, delta) }
}

signal_resized :: proc(g: ^GUI, id: Widget_ID, size: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.signals.on_resized != nil { w.signals.on_resized(g, id, size) }
}
