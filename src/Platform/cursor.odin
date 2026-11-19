package Platform

import sdl "vendor:sdl3"
import GUI "../GUI"

Set_Cursor :: proc(w: ^Window, cursor: GUI.Cursor) {
	if w.cursor == cursor { return }
	w.cursor = cursor

	for len(w.cursors) <= int(cursor) {
		id := GUI.Cursor(len(w.cursors))
		append(&w.cursors, sdl.CreateSystemCursor(System_Cursor_Of(id)))
	}

	c := w.cursors[int(cursor)]
	if c == nil { return }
	_ = sdl.SetCursor(c)
}

SYSTEM_CURSORS := [?]sdl.SystemCursor {
	.DEFAULT, .POINTER, .TEXT, .CROSSHAIR, .WAIT, .NOT_ALLOWED, .MOVE, .MOVE,
	.NS_RESIZE, .W_RESIZE, .E_RESIZE, .N_RESIZE, .S_RESIZE,
	.NW_RESIZE, .NE_RESIZE, .SW_RESIZE, .SE_RESIZE,
}

System_Cursor_Of :: proc(cursor: GUI.Cursor) -> sdl.SystemCursor {
	i := int(cursor)
	if i < 0 || i >= len(SYSTEM_CURSORS) { return .DEFAULT }
	return SYSTEM_CURSORS[i]
}
