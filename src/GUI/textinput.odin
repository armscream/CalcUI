//* The text input widget: a buffer, a caret and a selection.
//
//* Odin unions bind an immutable copy in a type switch, so the payload is
//* reached through `switch &d in w.data` when it has to be mutated.
package GUI

import "core:strings"

//* The font a widget's text uses: the one its style asks for, at the
//* size the style asks for.
font_of :: proc(g: ^GUI, w: ^Widget) -> Font_ID {
	return font_resolve(g, resolved_style(g, w).text)
}

//* == UTF-8 helpers ==
//* The caret moves by codepoint, not by byte.

prev_offset :: proc(s: string, offset: int) -> int {
	if offset <= 0 { return 0 }
	i := offset - 1
	for i > 0 && (s[i] & 0xC0) == 0x80 { i -= 1 }
	return i
}

next_offset :: proc(s: string, offset: int) -> int {
	if offset >= len(s) { return len(s) }
	i := offset + 1
	for i < len(s) && (s[i] & 0xC0) == 0x80 { i += 1 }
	return i
}

//* Snaps a byte offset back to a codepoint boundary, so the text is
//* never cut in the middle of a multi-byte character.
snap_offset :: proc(s: string, offset: int) -> int {
	if offset <= 0 { return 0 }
	if offset >= len(s) { return len(s) }
	i := offset
	for i > 0 && (s[i] & 0xC0) == 0x80 { i -= 1 }
	return i
}

//* == Focus ==

//* Called on a mouse press: gives the keyboard focus to a text field
//* and places the caret where the pointer landed. A double click
//* selects the whole text instead.
focus_click :: proc(g: ^GUI, id: Widget_ID, p: Vec2, clicks: int = 1) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch d in w.data {
	case Text_Input_Data:
		g.focused = id
		if clicks >= 2 {
			text_input_select_all(g, id)
			return
		}
		text_input_place_caret(g, id, p)
	}
}

//* Called when a text field loses the focus: the selection goes away
//* together with the caret.
text_input_blur :: proc(g: ^GUI, id: Widget_ID) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
}

//* == Editing ==

text_input_insert :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		start := min(d.sel_start, d.sel_end)
		end := max(d.sel_start, d.sel_end)
		//* Never cut a codepoint in half.
		start = snap_offset(d.text, start)
		end = snap_offset(d.text, end)
		new_text := strings.concatenate({d.text[:start], text, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, start + len(text))
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
}

text_input_backspace :: proc(g: ^GUI, id: Widget_ID) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		start := min(d.sel_start, d.sel_end)
		end := max(d.sel_start, d.sel_end)
		if start != end {
			new_text := strings.concatenate({d.text[:start], d.text[end:]})
			delete(d.text)
			d.text = new_text
			d.caret = start
		} else if d.caret > 0 {
			p := prev_offset(d.text, d.caret)
			new_text := strings.concatenate({d.text[:p], d.text[d.caret:]})
			delete(d.text)
			d.text = new_text
			d.caret = p
		}
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
}

text_input_delete :: proc(g: ^GUI, id: Widget_ID) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		start := min(d.sel_start, d.sel_end)
		end := max(d.sel_start, d.sel_end)
		if start != end {
			new_text := strings.concatenate({d.text[:start], d.text[end:]})
			delete(d.text)
			d.text = new_text
			d.caret = start
		} else if d.caret < len(d.text) {
			n := next_offset(d.text, d.caret)
			new_text := strings.concatenate({d.text[:d.caret], d.text[n:]})
			delete(d.text)
			d.text = new_text
		}
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
}

text_input_move_caret :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		if extend {
			//* Keep the anchor, move the active end.
			if d.sel_start == d.sel_end { d.sel_start = d.caret }
			d.caret = forward ? next_offset(d.text, d.caret) : prev_offset(d.text, d.caret)
			d.sel_end = d.caret
		} else {
			d.caret = forward ? next_offset(d.text, d.caret) : prev_offset(d.text, d.caret)
			d.sel_start = d.caret
			d.sel_end = d.caret
		}
	}
}

text_input_set_caret :: proc(g: ^GUI, id: Widget_ID, offset: int, extend: bool) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.caret = clamp(offset, 0, len(d.text))
		if !extend {
			d.sel_start = d.caret
			d.sel_end = d.caret
		} else {
			d.sel_end = d.caret
		}
	}
}

text_input_select_all :: proc(g: ^GUI, id: Widget_ID) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.sel_start = 0
		d.sel_end = len(d.text)
		d.caret = len(d.text)
	}
}

//* == Geometry ==

//* The x position of a byte offset inside the text.
text_input_offset_x :: proc(g: ^GUI, id: Widget_ID, content: Rect, offset: int) -> f32 {
	w := widget_get(g, id)
	if w == nil { return content.x }
	#partial switch d in w.data {
	case Text_Input_Data:
		size := font_measure(g, font_of(g, w), d.text[:clamp(offset, 0, len(d.text))])
		return content.x + size.x
	}
	return content.x
}

//* The highlighted selection, in content coordinates.
text_input_selection_rect :: proc(g: ^GUI, id: Widget_ID, content: Rect) -> Rect {
	w := widget_get(g, id)
	if w == nil { return {} }
	#partial switch d in w.data {
	case Text_Input_Data:
		x0 := text_input_offset_x(g, id, content, min(d.sel_start, d.sel_end))
		x1 := text_input_offset_x(g, id, content, max(d.sel_start, d.sel_end))
		return Rect{x = x0, y = content.y, w = x1 - x0, h = content.h}
	}
	return {}
}

//* Puts the caret at the codepoint nearest to the pointer.
text_input_place_caret :: proc(g: ^GUI, id: Widget_ID, p: Vec2) {
	w := widget_get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Text_Input_Data:
		content := content_rect(g, w)
		font := font_of(g, w)
		offset := len(d.text)
		best := f32(1e9)
		//* Walk the codepoints and find the closest boundary.
		i := 0
		for i <= len(d.text) {
			size := font_measure(g, font, d.text[:i])
			dist := abs(content.x + size.x - p.x)
			if dist < best {
				best = dist
				offset = i
			}
			if i >= len(d.text) { break }
			i = next_offset(d.text, i)
		}
		d.caret = offset
		d.sel_start = offset
		d.sel_end = offset
	}
}

//* == Key and text routing ==

fire_key :: proc(g: ^GUI, id: Widget_ID, e: Key_Down_Event) {
	if id == INVALID_WIDGET_ID { return }
	w := widget_get(g, id)
	if w == nil { return }
	if !(.Enabled in w.state) { return }

	shift := .Shift in e.mods
	ctrl := .Ctrl in e.mods

	#partial switch d in w.data {
	case Text_Input_Data:
		#partial switch e.key {
		case .Backspace: text_input_backspace(g, id)
		case .Delete:    text_input_delete(g, id)
		case .Left:      text_input_move_caret(g, id, false, shift)
		case .Right:     text_input_move_caret(g, id, true, shift)
		case .Home:      text_input_set_caret(g, id, 0, shift)
		case .End:       text_input_set_caret(g, id, len(d.text), shift)
		case .A:         if ctrl { text_input_select_all(g, id) }
		}
	}
}

fire_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	if id == INVALID_WIDGET_ID { return }
	w := widget_get(g, id)
	if w == nil { return }
	if !(.Enabled in w.state) { return }

	#partial switch d in w.data {
	case Text_Input_Data:
		text_input_insert(g, id, text)
	}
}
