//* == The text input ==
//* The text input widget: a buffer, a caret, a selection and the
//* composition that an IME is making in it. The offsets of the caret and
//* of the selection are byte offsets into the buffer.
//*
//* The caret always stands on the boundary of a grapheme cluster, the
//* way UAX #29 says they are: a base letter and the marks that go with
//* it, a conjunct of a script and the emoji that are made of more than
//* one codepoint are one thing to the person that reads them, so they
//* are one thing to the caret. An offset that comes from outside is
//* snapped to the boundary of a cluster, so the text is never cut in
//* half.
//*
//* The place of the caret comes from the layout of the text and not from
//* the width of a prefix of it: the glyphs of the layout carry the byte
//* offsets of the clusters they were shaped from, and their advances
//* say how much room they take. The caret of a cluster stands at the
//* side of it that the reading order points at, which is what makes it
//* right in right-to-left text, where the clusters come back in the
//* other order. The advances of Runa are in physical pixels, so they
//* are divided by the scale of the font to come back to logical units.
//*
//* The composition of an IME stands in the buffer for the piece of it
//* that the composition replaces, and the caret stands at the end of it.
//* When the composition is committed, the text that was typed takes the
//* place of the composition. The range of the composition is kept in a
//* map of this file and not in the field itself, because the field
//* holds the text and the caret and nothing else.
//*
//* Odin unions bind an immutable copy in a type switch, so the payload
//* is reached through `switch &d in w.data` when it has to be mutated.
package GUI

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import runa "./dependencies/Runa"

Font_Of :: proc(g: ^GUI, w: ^Widget) -> Font_ID {
	return Font_Resolve(g, resolved_style(g, w).text)
}

prev_offset :: proc(s: string, offset: int) -> int {
	if offset <= 0 {return 0}
	it := runa.grapheme_iter_make(s)
	best := 0
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok {break}
		if lo >= offset {break}
		best = lo
	}
	return best
}

next_offset :: proc(s: string, offset: int) -> int {
	if offset >= len(s) {return len(s)}
	it := runa.grapheme_iter_make(s)
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok {break}
		if hi > offset {return hi}
	}
	return len(s)
}

snap_offset :: proc(s: string, offset: int) -> int {
	if offset <= 0 {return 0}
	if offset >= len(s) {return len(s)}
	it := runa.grapheme_iter_make(s)
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok {break}
		if offset < hi {return lo}
	}
	return len(s)
}

cluster_end :: proc(s: string, offset: int) -> int {
	it := runa.grapheme_iter_make(s)
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok {return len(s)}
		if lo == offset {return hi}
	}
}

word_rune :: proc(r: rune) -> bool {
	return unicode.is_letter(r) || unicode.is_digit(r) || r == '_'
}

word_prev_offset :: proc(s: string, offset: int) -> int {
	i := clamp(offset, 0, len(s))
	for i > 0 {
		r, size := utf8.decode_last_rune_in_string(s[:i])
		if size == 0 {break}
		if word_rune(r) {break}
		i -= size
	}
	for i > 0 {
		r, size := utf8.decode_last_rune_in_string(s[:i])
		if size == 0 {break}
		if !word_rune(r) {break}
		i -= size
	}
	return snap_offset(s, i)
}

word_next_offset :: proc(s: string, offset: int) -> int {
	i := clamp(offset, 0, len(s))
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		if size == 0 {break}
		if !word_rune(r) {break}
		i += size
	}
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		if size == 0 {break}
		if word_rune(r) {break}
		i += size
	}
	return snap_offset(s, i)
}

Caret_Search :: struct {
	offset: int,
	point: f32,
	found: bool,
	x: f32,
	prev: int,
	prev_x: f32,
	has_prev: bool,
	last: int,
	last_x: f32,
	has_last: bool,
	nearest: int,
	nearest_x: f32,
	nearest_dist: f32,
	has_nearest: bool,
}

caret_visit :: proc(s: ^Caret_Search, cluster: int, before, after: f32) {
	if cluster == s.offset {
		s.found = true
		s.x = before
	}
	if cluster <= s.offset && (!s.has_prev || cluster > s.prev) {
		s.has_prev = true
		s.prev = cluster
		s.prev_x = after
	}
	if !s.has_last || cluster > s.last {
		s.has_last = true
		s.last = cluster
		s.last_x = after
	}
	dist := abs(before - s.point)
	if !s.has_nearest || dist < s.nearest_dist {
		s.has_nearest = true
		s.nearest = cluster
		s.nearest_x = before
		s.nearest_dist = dist
	}
}

text_input_walk :: proc(lines: []runa.Line, scale: f32, s: ^Caret_Search) {
	if len(lines) == 0 {return}
	line := lines[0]
	pen: f32 = 0
	i := 0
	for i < len(line.glyphs) {
		cluster := int(line.glyphs[i].cluster)
		level := line.glyphs[i].level
		lo_x := pen
		j := i
		for j < len(line.glyphs) && int(line.glyphs[j].cluster) == cluster {
			pen += line.glyphs[j].x_advance / scale
			j += 1
		}
		hi_x := pen
		rtl := (level & 1) == 1
		before := rtl ? hi_x : lo_x
		after := rtl ? lo_x : hi_x
		caret_visit(s, cluster, before, after)
		i = j
	}
}

text_input_layout :: proc(g: ^GUI, f: ^Font, text: string) -> []runa.Line {
	if f == nil || text == "" {return nil}
	opts := f.opts
	opts.max_width = 0
	return font_layout(g, f, text, opts)
}

text_input_caret_x :: proc(lines: []runa.Line, scale: f32, offset: int) -> f32 {
	s := Caret_Search{offset = offset}
	text_input_walk(lines, scale, &s)
	if s.found {return s.x}
	if s.has_prev {return s.prev_x}
	return 0
}

text_input_offset_at :: proc(lines: []runa.Line, scale: f32, x: f32, text_len: int) -> int {
	s := Caret_Search{point = x}
	text_input_walk(lines, scale, &s)
	if !s.has_nearest {return 0}
	best := s.nearest
	if s.has_last {
		dist := abs(s.last_x - x)
		if dist < s.nearest_dist {best = text_len}
	}
	return best
}

text_input_line_range :: proc(g: ^GUI, f: ^Font, text: string) -> (start, end: int) {
	start = 0
	end = len(text)
	lines := text_input_layout(g, f, text)
	if len(lines) == 0 {return}
	low := -1
	high := -1
	for pg in lines[0].glyphs {
		c := int(pg.cluster)
		if low < 0 || c < low {low = c}
		if high < 0 || c > high {high = c}
	}
	if low >= 0 {start = low}
	if high >= 0 {end = cluster_end(text, high)}
	return
}

focus_click :: proc(g: ^GUI, id: Widget_ID, p: Vec2, clicks: int = 1) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch d in w.data {
	case Text_Input_Data:
		focus_set(g, id)
		if clicks >= 2 {
			text_input_select_all(g, id)
			return
		}
		text_input_place_caret(g, id, p)
		return
	}
	if w.focus_mode == .Click || w.focus_mode == .All {
		focus_set(g, id)
	}
}

text_input_blur :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	text_input_ime_cancel(g, id)
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
}

text_input_insert :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	#partial switch &d in w.data {
	case Text_Input_Data:
		start := snap_offset(d.text, min(d.sel_start, d.sel_end))
		end := snap_offset(d.text, max(d.sel_start, d.sel_end))
		new_text := strings.concatenate({d.text[:start], text, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, start + len(text))
		d.sel_start = d.caret
		d.sel_end = d.caret
		changed = true
	}
	if changed {
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
}

text_input_backspace :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	#partial switch &d in w.data {
	case Text_Input_Data:
		start := snap_offset(d.text, min(d.sel_start, d.sel_end))
		end := snap_offset(d.text, max(d.sel_start, d.sel_end))
		if start != end {
			new_text := strings.concatenate({d.text[:start], d.text[end:]})
			delete(d.text)
			d.text = new_text
			d.caret = start
			changed = true
		} else if d.caret > 0 {
			p := prev_offset(d.text, d.caret)
			new_text := strings.concatenate({d.text[:p], d.text[d.caret:]})
			delete(d.text)
			d.text = new_text
			d.caret = p
			changed = true
		}
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
	if changed {
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
}

text_input_clear :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	#partial switch &d in w.data {
	case Text_Input_Data:
		if d.text == "" {return}
		delete(d.text)
		d.text = strings.clone("")
		d.caret = 0
		d.sel_start = 0
		d.sel_end = 0
		changed = true
	}
	if changed {
		signal_text_changed(g, id, "")
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
}

text_input_delete :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	#partial switch &d in w.data {
	case Text_Input_Data:
		start := snap_offset(d.text, min(d.sel_start, d.sel_end))
		end := snap_offset(d.text, max(d.sel_start, d.sel_end))
		if start != end {
			new_text := strings.concatenate({d.text[:start], d.text[end:]})
			delete(d.text)
			d.text = new_text
			d.caret = start
			changed = true
		} else if d.caret < len(d.text) {
			n := next_offset(d.text, d.caret)
			new_text := strings.concatenate({d.text[:d.caret], d.text[n:]})
			delete(d.text)
			d.text = new_text
			changed = true
		}
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
	if changed {
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
}

text_input_move_caret :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		offset := forward ? next_offset(d.text, d.caret) : prev_offset(d.text, d.caret)
		text_input_move_to(g, id, offset, extend)
	}
}

text_input_move_word :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		offset := forward ? word_next_offset(d.text, d.caret) : word_prev_offset(d.text, d.caret)
		text_input_move_to(g, id, offset, extend)
	}
}

text_input_move_to :: proc(g: ^GUI, id: Widget_ID, offset: int, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		place := snap_offset(d.text, clamp(offset, 0, len(d.text)))
		if extend {
			if d.sel_start == d.sel_end {d.sel_start = d.caret}
			d.caret = place
			d.sel_end = d.caret
		} else {
			d.caret = place
			d.sel_start = d.caret
			d.sel_end = d.caret
		}
	}
}

text_input_set_caret :: proc(g: ^GUI, id: Widget_ID, offset: int, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.caret = snap_offset(d.text, clamp(offset, 0, len(d.text)))
		if !extend {
			d.sel_start = d.caret
			d.sel_end = d.caret
		} else {
			d.sel_end = d.caret
		}
	}
}

text_input_line_edge :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		f := font_get(g, Font_Of(g, w))
		start, end := text_input_line_range(g, f, d.text)
		text_input_move_to(g, id, forward ? end : start, extend)
	}
}

text_input_select_all :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		d.sel_start = 0
		d.sel_end = len(d.text)
		d.caret = len(d.text)
	}
}

text_input_copy :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch d in w.data {
	case Text_Input_Data:
		start := min(d.sel_start, d.sel_end)
		end := max(d.sel_start, d.sel_end)
		if start >= end {return}
		clipboard_set(g, d.text[start:end])
	}
}

text_input_cut :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch d in w.data {
	case Text_Input_Data:
		if d.sel_start == d.sel_end {return}
	}
	text_input_copy(g, id)
	text_input_delete(g, id)
}

text_input_paste :: proc(g: ^GUI, id: Widget_ID) {
	text := clipboard_get(g)
	if text == "" {return}
	text_input_insert(g, id, text)
}

text_input_offset_x :: proc(g: ^GUI, id: Widget_ID, content: Rect, offset: int) -> f32 {
	w := Widget_Get(g, id)
	if w == nil {return content.x}
	#partial switch d in w.data {
	case Text_Input_Data:
		f := font_get(g, Font_Of(g, w))
		if f == nil {return content.x}
		lines := text_input_layout(g, f, d.text)
		x := text_input_caret_x(lines, f.scale, clamp(offset, 0, len(d.text)))
		return content.x + x
	}
	return content.x
}

text_input_selection_rect :: proc(g: ^GUI, id: Widget_ID, content: Rect) -> Rect {
	w := Widget_Get(g, id)
	if w == nil {return {}}
	#partial switch d in w.data {
	case Text_Input_Data:
		start := min(d.sel_start, d.sel_end)
		end := max(d.sel_start, d.sel_end)
		if start == end {return {}}
		f := font_get(g, Font_Of(g, w))
		if f == nil {return {}}
		lines := text_input_layout(g, f, d.text)
		x0 := text_input_caret_x(lines, f.scale, clamp(start, 0, len(d.text)))
		x1 := text_input_caret_x(lines, f.scale, clamp(end, 0, len(d.text)))
		lo := content.x + min(x0, x1)
		hi := content.x + max(x0, x1)
		return Rect{x = lo, y = content.y, w = hi - lo, h = content.h}
	}
	return {}
}

text_input_place_caret :: proc(g: ^GUI, id: Widget_ID, p: Vec2) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		content := content_rect(g, w)
		f := font_get(g, Font_Of(g, w))
		if f == nil {return}
		lines := text_input_layout(g, f, d.text)
		offset := text_input_offset_at(lines, f.scale, p.x - content.x, len(d.text))
		d.caret = snap_offset(d.text, offset)
		d.sel_start = d.caret
		d.sel_end = d.caret
	}
}

IME_Composition :: struct {
	gui:    ^GUI,
	start:  int,
	length: int,
	before: string,
}

ime_composition_get :: proc(g: ^GUI, id: Widget_ID) -> (IME_Composition, bool) {
	if g.ime_compositions == nil {return {}, false}
	c, ok := g.ime_compositions[id]
	if !ok {return {}, false}
	if c.gui == nil {return {}, false}
	return c, true
}

ime_composition_set :: proc(g: ^GUI, id: Widget_ID, start, length: int, before: string) {
	if g.ime_compositions == nil {
		g.ime_compositions = make(map[Widget_ID]IME_Composition)
	}
	g.ime_compositions[id] = IME_Composition{gui = g, start = start, length = length, before = before}
}

ime_composition_clear :: proc(g: ^GUI, id: Widget_ID) {
	if g.ime_compositions == nil {return}
	c, ok := g.ime_compositions[id]
	if !ok {return}
	if len(c.before) > 0 {delete(c.before)}
	g.ime_compositions[id] = IME_Composition{}
}

text_input_ime_destroy :: proc(g: ^GUI) {
	if g.ime_compositions == nil {return}
	for _, c in g.ime_compositions {
		if len(c.before) > 0 {delete(c.before)}
	}
	delete(g.ime_compositions)
	g.ime_compositions = nil
}

text_input_ime_editing :: proc(g: ^GUI, text: string, start, length: int) {
	if g == nil {return}
	id := g.focused
	if id == INVALID_WIDGET_ID {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		text_input_kind_register(g)
		begin := clamp(start, 0, len(d.text))
		end := clamp(start + length, begin, len(d.text))
		old, has_old := ime_composition_get(g, id)
		if length == 0 && has_old && old.start == begin {
			end = clamp(old.start + old.length, begin, len(d.text))
		}
		before := ""
		if has_old && old.start == begin && old.length == end - begin {
			before = old.before
		} else {
			before = strings.clone(d.text[begin:end])
			if has_old {delete(old.before)}
		}
		new_text := strings.concatenate({d.text[:begin], text, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, begin + len(text))
		d.sel_start = d.caret
		d.sel_end = d.caret
		ime_composition_set(g, id, begin, len(text), before)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
}

text_input_ime_commit :: proc(g: ^GUI, id: Widget_ID, text: string) -> bool {
	c, ok := ime_composition_get(g, id)
	if !ok {return false}
	w := Widget_Get(g, id)
	if w == nil {return false}
	#partial switch &d in w.data {
	case Text_Input_Data:
		begin := clamp(c.start, 0, len(d.text))
		end := clamp(begin + c.length, begin, len(d.text))
		new_text := strings.concatenate({d.text[:begin], text, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, begin + len(text))
		d.sel_start = d.caret
		d.sel_end = d.caret
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
	ime_composition_clear(g, id)
	return true
}

text_input_ime_cancel :: proc(g: ^GUI, id: Widget_ID) {
	c, ok := ime_composition_get(g, id)
	if !ok {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Input_Data:
		begin := clamp(c.start, 0, len(d.text))
		end := clamp(begin + c.length, begin, len(d.text))
		new_text := strings.concatenate({d.text[:begin], c.before, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, begin + len(c.before))
		d.sel_start = d.caret
		d.sel_end = d.caret
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
	ime_composition_clear(g, id)
}

text_input_draw_ime :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	c, ok := ime_composition_get(g, id)
	if !ok {return}
	#partial switch d in w.data {
	case Text_Input_Data:
		f := font_get(g, Font_Of(g, w))
		if f == nil {return}
		lines := text_input_layout(g, f, d.text)
		x0 := text_input_caret_x(lines, f.scale, clamp(c.start, 0, len(d.text)))
		x1 := text_input_caret_x(lines, f.scale, clamp(c.start + c.length, 0, len(d.text)))
		lo := content.x + min(x0, x1)
		hi := content.x + max(x0, x1)
		baseline := content.y
		if len(lines) > 0 {baseline += lines[0].baseline / f.scale}
		draw_quad(
			g.target,
			Rect{x = lo, y = baseline + 1, w = hi - lo, h = 1},
			g.atlas.white_uv,
			resolved_text_colour(g, id, w),
			g.atlas_texture,
		)
	}
}

text_input_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = text_input_draw}
}

text_input_kind_register :: proc(g: ^GUI) {
	if g == nil {return}
	kind_register(g, .TextInput, text_input_kind())
}

text_input_draw :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	style := resolved_style(g, w)
	draw_text_input(g, id, w, content, style^)
	text_input_draw_ime(g, id, w, content)
}

fire_key :: proc(g: ^GUI, id: Widget_ID, e: Key_Down_Event) {
	if id == INVALID_WIDGET_ID {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	if !(.Enabled in w.state) {return}

	shift := .Shift in e.mods
	ctrl := .Ctrl in e.mods

	g.event_handled = false

	if kind := widget_kind(g, w); kind.key != nil {
		kind.key(g, id, w, e)
		return
	}

	#partial switch d in w.data {
	case Text_Input_Data:
		#partial switch e.key {
		case .Backspace:
			text_input_backspace(g, id)
		case .Delete:
			text_input_delete(g, id)
		case .Left:
			if ctrl {
				text_input_move_word(g, id, false, shift)
			} else {
				text_input_move_caret(g, id, false, shift)
			}
		case .Right:
			if ctrl {
				text_input_move_word(g, id, true, shift)
			} else {
				text_input_move_caret(g, id, true, shift)
			}
		case .Home:
			text_input_line_edge(g, id, false, shift)
		case .End:
			text_input_line_edge(g, id, true, shift)
		case .A:
			if ctrl {text_input_select_all(g, id)}
		case .C:
			if ctrl {text_input_copy(g, id)}
		case .X:
			if ctrl {text_input_cut(g, id)}
		case .V:
			if ctrl {text_input_paste(g, id)}
		case .Enter:
			signal_submitted(g, id, d.text)
		case .Escape:
			text_input_clear(g, id)
			Event_Handled(g)
		}
	}
}

fire_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	if id == INVALID_WIDGET_ID {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	if !(.Enabled in w.state) {return}

	if kind := widget_kind(g, w); kind.text_input != nil {
		kind.text_input(g, id, w, text)
		return
	}

	#partial switch d in w.data {
	case Text_Input_Data:
		if !text_input_ime_commit(g, id, text) {
			text_input_insert(g, id, text)
		}
	}
}
