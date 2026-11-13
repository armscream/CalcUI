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

//* The place of an overlay in the order of the drawing: the overlays
//* come up over the ordinary widgets.
POPUP_Z_INDEX :: 100

//* Puts a popup under the root of the window, so that it comes up over
//* the scroll container and over the other parts of the UI. The popup
//* keeps its identity, so the handles of the program stay good.
Popup_Attach_To_Root :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if g.root == INVALID_WIDGET_ID { return }
	Widget_Set_Parent(g, g.root, id)
	Widget_Set_Z_Index(g, id, POPUP_Z_INDEX)
	Widget_Set_Clip_Contents(g, id, false)
	Widget_Set_Anchors(g, id, Anchor{0, 0, 0, 0})
}

//* Opens a popup. A popup of a kind that has an open of its own is
//* opened by the open of that kind: a palette gets its commands and its
//* filter, and a dialog is reset before it comes up.
Popup_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch w.type {
	case .CommandPalette:
		Command_Palette_Open(g, id)
		return
	case .AcceptDialog, .ConfirmationDialog:
		Dialog_Open(g, id)
		return
	case .FileDialog:
		File_Dialog_Open(g, id)
		return
	case:
	}
	popup_open_core(g, id)
}

//* The work of opening a popup: the popup comes up, it takes the mouse
//* and the keyboard, and it is put on the stack of the open popups. The
//* openers of the kinds of popup call this, so that a popup is never
//* opened by itself.
popup_open_core :: proc(g: ^GUI, id: Widget_ID) {
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
	if Widget_Get(g, id) == nil {
		popup_forget(g, id)
		return true
	}
	popup_close_one(g, id)
	return true
}

//* Closes a popup with the close of its own kind: the close of a menu
//* takes the menu out of the stack, and the close of a dialog tells the
//* dialog that it is shut.
popup_close_one :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch w.type {
	case .ContextMenu: Context_Menu_Close(g, id)
	case .CommandPalette: Command_Palette_Close(g, id)
	case .PopupMenu: Popup_Menu_Close(g, id)
	case .AcceptDialog, .ConfirmationDialog: Dialog_Close(g, id)
	case .FileDialog: File_Dialog_Close(g, id)
	case: Popup_Close(g, id)
	}
}

//* == The place of a popup ==
//* The rect of a widget is in the coordinates of the window the widget
//* is in: the place of the main window, or the place of the floating
//* panel. The rect of a popup on the screen is the rect of the widget
//* with the place of that window added to it.

//* The rect of a widget in the coordinates of the screen.
widget_global_rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	w := Widget_Get(g, id)
	if w == nil { return Rect{} }
	origin := Vec2{g.window_rect.x, g.window_rect.y}
	index := float_index_of(g, id)
	if index != FLOAT_NONE {
		origin = g.floats[index].pos
	}
	return Rect {
		x = origin.x + w.rect.x,
		y = origin.y + w.rect.y,
		w = w.rect.w,
		h = w.rect.h,
	}
}

//* The rect a popup really covers, in the coordinates of the screen. The
//* drop-down has the rect it was placed at, and the context menu has
//* the rect it is drawn at.
popup_rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	return widget_global_rect(g, id)
}

//* Puts a popup widget where it belongs. The anchors of the widget go
//* to zero, the offsets are the place of the widget in its parent, and
//* the rect of the widget is written, so that the layout puts it in the
//* same place again.
popup_set_rect :: proc(g: ^GUI, id: Widget_ID, rect: Rect) {
	w := Widget_Get(g, id)
	if w == nil { return }
	parent := Widget_Get(g, w.parent)
	if parent == nil { return }
	left := rect.x - parent.rect.x
	top := rect.y - parent.rect.y
	Widget_Set_Anchors(g, id, Anchor{0, 0, 0, 0})
	Widget_Set_Offsets(g, id, Offset{
		left = left,
		top = top,
		right = left + rect.w,
		bottom = top + rect.h,
	})
	w.rect = rect
}

//* == The click outside a menu ==
//* A click outside a menu closes it, and the click goes to the widget
//* under the pointer. The rule is for the menus: the dialogs, the
//* command palette and the popup panel keep the behaviour they have.

//* A click outside the menu that is open closes it. The menu belongs to
//* the button it belongs to: a click on the button itself is left to
//* the button, which closes the menu when it is clicked again.
popup_close_outside :: proc(g: ^GUI, global: Vec2) {
	id := Popup_Top(g)
	if id == INVALID_WIDGET_ID { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch w.type {
	case .PopupMenu, .ContextMenu:
		rect := popup_rect(g, id)
		if rect_contains(rect, global.x, global.y) { return }
		if popup_owner_hit(g, id, global) { return }
		popup_close_one(g, id)
	}
}

//* Whether a point is on the button a drop-down belongs to.
popup_owner_hit :: proc(g: ^GUI, id: Widget_ID, global: Vec2) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	owner := INVALID_WIDGET_ID
	#partial switch d in w.data {
	case Popup_Menu_Data:
		owner = d.owner
	}
	if owner == INVALID_WIDGET_ID { return false }
	rect := widget_global_rect(g, owner)
	return rect_contains(rect, global.x, global.y)
}
