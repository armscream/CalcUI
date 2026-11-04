//* == The clipboard ==
//* The clipboard is a piece of text that the program and the window
//* share. The GUI keeps the text; the window layer puts it in the
//* clipboard of the system and reads it back.

package GUI

import "core:strings"

//* The clipboard of the GUI. The window layer keeps it in step with
//* the clipboard of the system.
Clipboard :: struct {
	//* The text that is in the clipboard.
	text: string,
	//* Whether the text was changed since the last time it was read.
	dirty: bool,
}

//* Puts a piece of text in the clipboard.
clipboard_set :: proc(g: ^GUI, text: string) {
	if g.clipboard.text == text { return }
	g.clipboard.text = strings.clone(text)
	g.clipboard.dirty = true
}

//* The text that is in the clipboard.
clipboard_get :: proc(g: ^GUI) -> string {
	return g.clipboard.text
}

//* Says that the clipboard of the system has changed, so that the text
//* is read again.
clipboard_changed :: proc(g: ^GUI) {
	g.clipboard.dirty = true
}

//* Takes the text out of the clipboard and leaves it empty. It is what
//* the cut command of a text field does.
clipboard_take :: proc(g: ^GUI) -> string {
	text := g.clipboard.text
	g.clipboard.text = ""
	g.clipboard.dirty = true
	return text
}
