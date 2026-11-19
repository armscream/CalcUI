package Platform

import sdl "vendor:sdl3"
import "core:strings"
import GUI "../GUI"

Sync_Clipboard :: proc(g: ^GUI.GUI) {
	if g == nil { return }
	if g.clipboard.dirty {
		text := strings.clone_to_cstring(GUI.Clipboard_Get(g), context.temp_allocator)
		_ = sdl.SetClipboardText(text)
		g.clipboard.dirty = false
		return
	}
	if !sdl.HasClipboardText() { return }
	data := sdl.GetClipboardText()
	if data == nil { return }
	text, _ := strings.clone_from_cstring(cstring(data))
	sdl.free(cast(rawptr)data)
	if text == GUI.Clipboard_Get(g) {
		if text != "" { delete(text) }
		return
	}
	GUI.Clipboard_Pulled(g, text)
	if text != "" { delete(text) }
}
