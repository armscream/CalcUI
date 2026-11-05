//* The windows that come up over the rest of the UI: a menu, palette, dialog etc.
// events propagate to popups first.
package GUI

//* A popup that is open, and prev focused widget.
Popup_Entry :: struct {
	id:             Widget_ID,
	previous_focus: Widget_ID,
}

is_popup :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	#partial switch w.type {
	case .PopupMenu, .PopupPanel, .AcceptDialog, .ConfirmationDialog, .FileDialog,
		.ContextMenu, .CommandPalette:
		return true
	}
	return false
}

Popup_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if popup_index(g, id) >= 0 { return }
	w.state += Widget_State{.Visible}
	w.mouse_filter = .Stop
	append(&g.popups, Popup_Entry{id = id, previous_focus = g.focused})
	if can_focus_now(g, id) { focus_set(g, id) }
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Closes a popup and gives the keyboard back.
Popup_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w != nil {
		w.state -= Widget_State{.Visible}
		w.mouse_filter = .Ignore
	}
	popup_forget(g, id)
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Takes a popup out of the stack of the open popups and gives the
//* keyboard back to the widget that had it.
popup_forget :: proc(g: ^GUI, id: Widget_ID) {
	for i := len(g.popups) - 1; i >= 0; i -= 1 {
		if g.popups[i].id != id { continue }
		previous := g.popups[i].previous_focus
		ordered_remove(&g.popups, i)
		if g.focused == id { focus_clear(g) }
		if previous != INVALID_WIDGET_ID && Widget_Alive(g, previous) {
			focus_set(g, previous)
		}
		return
	}
}

//* The place of a popup in the stack of the open popups, or -1.
popup_index :: proc(g: ^GUI, id: Widget_ID) -> int {
	for i := len(g.popups) - 1; i >= 0; i -= 1 {
		if g.popups[i].id == id { return i }
	}
	return -1
}

Popup_Is_Open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	return popup_index(g, id) >= 0
}

Popup_Top :: proc(g: ^GUI) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	if len(g.popups) == 0 { return INVALID_WIDGET_ID }
	return g.popups[len(g.popups) - 1].id
}

//* Closes the popup that is on top of the others. Returns true when a
//* popup was closed.
popup_close_top :: proc(g: ^GUI) -> bool {
	id := Popup_Top(g)
	if id == INVALID_WIDGET_ID { return false }
	w := Widget_Get(g, id)
	if w == nil {
		popup_forget(g, id)
		return true
	}
	#partial switch w.type {
	case .ContextMenu: Context_Menu_Close(g, id)
	case .CommandPalette: Command_Palette_Close(g, id)
	case .PopupMenu: Popup_Menu_Close(g, id)
	case .AcceptDialog, .ConfirmationDialog: Dialog_Close(g, id)
	case .FileDialog: File_Dialog_Close(g, id)
	case: Popup_Close(g, id)
	}
	return true
}
