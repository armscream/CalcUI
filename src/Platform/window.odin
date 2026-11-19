//* The window layer is the only part of the program that knows about
//* physical pixels. SDL gives the pointer, the size of the window and the
//* place of the window on the screen in points, and a point is the logical
//* unit the GUI works in; the drawable area is in pixels. The scale says
//* how many pixels one point is worth on the display the window is on.
package Platform

import sdl "vendor:sdl3"
import "core:log"
import "core:strings"
import GUI "../GUI"

Popup :: struct {
	handle: ^sdl.Window,
	widget: GUI.Widget_ID,
	pos:    GUI.Vec2,
}

Window :: struct {
	handle:    ^sdl.Window,
	pixel_w:   i32,
	pixel_h:   i32,
	logical_w: i32,
	logical_h: i32,
	popups:    [dynamic]Popup,
	cursors:   [dynamic]^sdl.Cursor,
	cursor:    GUI.Cursor,
}

Init_SDL :: proc() -> bool {
	return sdl.Init({.VIDEO})
}

Create_Window :: proc(w, h: i32, title: string) -> (Window, bool) {
	handle := sdl.CreateWindow(
		strings.clone_to_cstring(title, context.temp_allocator), w, h, {.RESIZABLE}
	)
	if handle == nil { return Window{}, false }
	if !sdl.StartTextInput(handle) {
		log.warnf("could not start text input: %s", sdl.GetError())
	}
	window := Window{handle = handle}
	read_size(&window)
	return window, true
}

Destroy_Window :: proc(w: ^Window) {
	for popup in w.popups {
		if popup.handle != nil { sdl.DestroyWindow(popup.handle) }
	}
	delete(w.popups)
	for cursor in w.cursors {
		if cursor != nil { sdl.DestroyCursor(cursor) }
	}
	delete(w.cursors)
	if w.handle != nil { sdl.DestroyWindow(w.handle) }
}

read_size :: proc(w: ^Window) {
	sdl.GetWindowSizeInPixels(w.handle, &w.pixel_w, &w.pixel_h)
	sdl.GetWindowSize(w.handle, &w.logical_w, &w.logical_h)
}

Scale :: proc(w: Window) -> f32 {
	if w.pixel_w <= 0 || w.logical_w <= 0 { return 1 }
	return f32(w.pixel_w) / f32(w.logical_w)
}
