package Platform

import sdl "vendor:sdl3"
import "core:log"
import "core:strings"
import GUI "../GUI"

Sync_Popups :: proc(
	w: ^Window,
	floats: []GUI.Float_Panel,
	release_target: proc(ctx: rawptr, window: rawptr) = nil,
	ctx: rawptr = nil,
) {
	next: [dynamic]Popup
	defer delete(next)

	for f in floats {
		popup := Popup{widget = f.widget, pos = f.pos}
		if old := popup_of(w, f.widget); old != nil { popup = old^ }
		if popup.handle == nil {
			popup.handle = sdl.CreateWindow(
				strings.clone_to_cstring(f.title, context.temp_allocator),
				i32(f.size.x),
				i32(f.size.y),
				sdl.WindowFlags{.BORDERLESS},
			)
			if popup.handle == nil {
				log.warnf("could not create a window for '%s': %s", f.title, sdl.GetError())
				break
			}
			if !sdl.StartTextInput(popup.handle) {
				log.warnf("could not start text input: %s", sdl.GetError())
			}
		}
		popup.widget = f.widget
		popup.pos = f.pos
		append(&next, popup)
		sdl.SetWindowPosition(popup.handle, i32(f.pos.x), i32(f.pos.y))
		sdl.SetWindowSize(popup.handle, i32(f.size.x), i32(f.size.y))
		sdl.ShowWindow(popup.handle)
		if f.raise { sdl.RaiseWindow(popup.handle) }
	}

	for p in w.popups {
		if popup_kept(next[:], p.widget) { continue }
		if release_target != nil { release_target(ctx, cast(rawptr) p.handle) }
		if p.handle != nil { sdl.DestroyWindow(p.handle) }
	}

	delete(w.popups)
	w.popups = next
	next = nil
}

popup_of :: proc(w: ^Window, widget: GUI.Widget_ID) -> ^Popup {
	for &p in w.popups {
		if p.widget == widget { return &p }
	}
	return nil
}

popup_kept :: proc(popups: []Popup, widget: GUI.Widget_ID) -> bool {
	for p in popups {
		if p.widget == widget { return true }
	}
	return false
}
