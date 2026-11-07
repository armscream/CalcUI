//* == The clipboard ==
//* The clipboard is a piece of text that the program and the window
//* share. The GUI keeps the text and owns it; the window layer puts it
//* in the clipboard of the system and reads it back.
//*
//* The flag `dirty` of the clipboard means one thing only: the text of
//* the GUI changed and the window layer has to push it to the clipboard
//* of the system. It is cleared by the window layer when it has done
//* so. A change that came from the system is pulled and never pushed, so
//* it does not set that flag; the flag `system_changed` says that the
//* clipboard of the system changed and that its text has to be read
//* again.
//*
//* The text that `Clipboard_Get` gives back belongs to the GUI: it is a
//* pointer into the buffer of the GUI, and the caller must not free it.
//* The text that `clipboard_take` gives back belongs to the caller: it
//* is a copy, and the caller has to free it.
//*
//* The public procs are: Clipboard_Set (the program changed the text,
//* the window layer pushes it to the system), Clipboard_Get (the text
//* of the GUI), Clipboard_Has_Text, and Clipboard_Pull / Clipboard_Pulled
//* (the system changed the text, the GUI takes it and nothing is pushed
//* back).
package GUI

import "core:strings"

Clipboard :: struct {
	text: string,
	dirty: bool,
	system_changed: bool,
}

clipboard_set :: proc(g: ^GUI, text: string) {
	if g == nil { return }
	if g.clipboard.text != text {
		delete(g.clipboard.text)
		g.clipboard.text = strings.clone(text)
	}
	g.clipboard.dirty = true
}

clipboard_get :: proc(g: ^GUI) -> string {
	if g == nil { return "" }
	return g.clipboard.text
}

clipboard_changed :: proc(g: ^GUI) {
	if g == nil { return }
	g.clipboard.system_changed = true
	g.clipboard.dirty = false
}

clipboard_pulled :: proc(g: ^GUI, text: string) {
	if g == nil { return }
	if g.clipboard.text != text {
		delete(g.clipboard.text)
		g.clipboard.text = strings.clone(text)
	}
	g.clipboard.dirty = false
}

clipboard_take :: proc(g: ^GUI) -> string {
	if g == nil { return "" }
	text := strings.clone(g.clipboard.text)
	delete(g.clipboard.text)
	g.clipboard.text = ""
	g.clipboard.dirty = true
	return text
}

Clipboard_Set :: proc(g: ^GUI, text: string) {
	clipboard_set(g, text)
}

Clipboard_Get :: proc(g: ^GUI) -> string {
	return clipboard_get(g)
}

Clipboard_Has_Text :: proc(g: ^GUI) -> bool {
	return clipboard_get(g) != ""
}

Clipboard_Pull :: proc(g: ^GUI, text: string) {
	clipboard_pulled(g, text)
}

Clipboard_Pulled :: proc(g: ^GUI, text: string) {
	clipboard_pulled(g, text)
}
