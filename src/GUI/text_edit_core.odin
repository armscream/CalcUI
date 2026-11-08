//* == The model of a text box ==
//* Every text box follows the same model: a buffer of text, a caret, a
//* selection that has a fixed end and a moving end, and the rules that
//* say what may be typed in it. The widgets that hold text share the
//* parts of the model that do not depend on how the text is laid out, so
//* that a click and a drag mean the same thing in all of them.
//*
//* The selection of a text box is a pair of offsets: the anchor is the
//* end that stays where it is, and the caret is the end that follows the
//* pointer. The mode of the selection says how the text around the
//* pointer is taken: one character at a time, a word at a time or a line
//* at a time.
//*
//* The rules of a text box are per instance: the program says them when
//* it makes the widget, and they are said again when the rules change.
//* The rules are kept when the text is typed and when it is pasted, and
//* they are not kept when the program sets the text itself, because the
//* program knows what it is doing.

package GUI

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import virt "core:mem/virtual"

Text_Select_Mode :: enum {
	Character,
	Word,
}

Text_Selection :: struct {
	//* The end of the selection that stays where it is.
	anchor: int,
	//* How the text around the pointer is taken.
	mode: Text_Select_Mode,
	//* Whether a drag is taking the text at the moment.
	dragging: bool,
	//* The word that the last double click took.
	word_start: int,
	word_end:   int,
	has_word:   bool,
}

Text_Rules :: struct {
	//* The most characters the text may have. 0 means that it may have
	//* as many as it likes.
	max_length: int,
	//* The fewest characters the text must have. 0 means that it may be
	//* empty.
	min_length: int,
	//* The characters that may be typed. An empty string means that any
	//* character may be typed.
	allowed: string,
	//* A pattern that every character must match. An empty string means
	//* that any character may be typed.
	pattern: string,
}

Text_Click_Action :: enum {
	Caret,
	Word,
	All,
}

//* The text the tab key puts in: four spaces of indent.
TEXT_INDENT :: "    "

//* The colour of the text that is taken.
TEXT_SELECTION_COLOUR :: Colour{r = 0.25, g = 0.45, b = 0.78, a = 0.55}

//* == The lines of a text box ==
//* The text of a box that is more than one line long is broken into
//* lines, and the caret and the selection are put on the lines.

text_lines :: proc(g: ^GUI, ts: Text_Style, text: string, width: f32) -> [dynamic]Text_Line {
	font := font_get(g, Font_Resolve(g, ts))
	if font == nil {return nil}
	return wrap_text_lines(g, font, ts, text, width)
}

text_line_of :: proc(lines: []Text_Line, text: string, offset: int) -> int {
	for i in 0 ..< len(lines) {
		line_end := min(lines[i].end, len(text))
		if offset < line_end || i == len(lines) - 1 {return i}
	}
	return -1
}

//* The place of an offset on the lines: where it is and how tall it is.
text_place :: proc(
	g: ^GUI,
	font: Font_ID,
	box: Rect,
	ts: Text_Style,
	lines: []Text_Line,
	text: string,
	offset: int,
) -> (x, y, h: f32) {
	y = box.y
	for i in 0 ..< len(lines) {
		line := lines[i]
		line_start := line.start
		line_end := min(line.end, len(text))
		if offset < line_end || i == len(lines) - 1 {
			place := clamp(offset, line_start, line_end)
			x = box.x + Font_Measure(g, font, text[line_start:place]).x
			return x, y, line.height
		}
		y += line.height + ts.spacing
	}
	return box.x, box.y, box.h
}

//* The places of the text that is taken, one rectangle for every line
//* that has a part of it.
text_selection_rects :: proc(
	g: ^GUI,
	font: Font_ID,
	box: Rect,
	ts: Text_Style,
	lines: []Text_Line,
	text: string,
	start, end: int,
) -> [dynamic]Rect {
	allocator := virt.arena_allocator(&g.frame_arena)
	out := make([dynamic]Rect, 0, 4, allocator)
	y := box.y
	for i in 0 ..< len(lines) {
		line := lines[i]
		line_start := line.start
		line_end := min(line.end, len(text))
		a := max(start, line_start)
		b := min(end, line_end)
		if a < b {
			x0 := box.x + Font_Measure(g, font, text[line_start:a]).x
			x1 := box.x + Font_Measure(g, font, text[line_start:b]).x
			append(&out, Rect{x = x0, y = y, w = x1 - x0, h = line.height})
		}
		y += line.height + ts.spacing
	}
	return out
}

//* The offset of the text that a point is over.
text_offset_at :: proc(
	g: ^GUI,
	font: Font_ID,
	box: Rect,
	ts: Text_Style,
	lines: []Text_Line,
	text: string,
	p: Vec2,
) -> int {
	y := box.y
	for i in 0 ..< len(lines) {
		line := lines[i]
		line_start := line.start
		line_end := min(line.end, len(text))
		if p.y < y + line.height || i == len(lines) - 1 {
			best := line_start
			best_dist := f32(1e9)
			place := line_start
			for {
				x := box.x + Font_Measure(g, font, text[line_start:place]).x
				dist := abs(x - p.x)
				if dist < best_dist {
					best_dist = dist
					best = place
				}
				if place >= line_end {break}
				place = next_offset(text, place)
			}
			return best
		}
		y += line.height + ts.spacing
	}
	return len(text)
}

//* How far the offset is from the left of its line.
text_x_of :: proc(
	g: ^GUI,
	font: Font_ID,
	box: Rect,
	ts: Text_Style,
	lines: []Text_Line,
	text: string,
	offset: int,
) -> f32 {
	index := text_line_of(lines[:], text, offset)
	if index < 0 {return 0}
	line_start := lines[index].start
	line_end := min(lines[index].end, len(text))
	place := clamp(offset, line_start, line_end)
	return Font_Measure(g, font, text[line_start:place]).x
}

//* The offset that is at that distance from the left of a line.
text_offset_at_x :: proc(
	g: ^GUI,
	font: Font_ID,
	box: Rect,
	ts: Text_Style,
	lines: []Text_Line,
	text: string,
	index: int,
	x: f32,
) -> int {
	if index < 0 || index >= len(lines) {return len(text)}
	line_start := lines[index].start
	line_end := min(lines[index].end, len(text))
	best := line_start
	best_dist := f32(1e9)
	place := line_start
	for {
		px := box.x + Font_Measure(g, font, text[line_start:place]).x
		dist := abs(px - x)
		if dist < best_dist {
			best_dist = dist
			best = place
		}
		if place >= line_end {break}
		place = next_offset(text, place)
	}
	return best
}

word_rune :: proc(r: rune) -> bool {
	return unicode.is_letter(r) || unicode.is_digit(r) || r == '_'
}

//* The word that the offset is in: the run of letters, digits and
//* underscores around it.
text_word_range :: proc(text: string, offset: int) -> (start, end: int) {
	i := clamp(offset, 0, len(text))
	lo := i
	for lo > 0 {
		r, size := utf8.decode_last_rune_in_string(text[:lo])
		if size == 0 {break}
		if !word_rune(r) {break}
		lo -= size
	}
	hi := i
	for hi < len(text) {
		r, size := utf8.decode_rune_in_string(text[hi:])
		if size == 0 {break}
		if !word_rune(r) {break}
		hi += size
	}
	return lo, hi
}

//* Puts the caret at the offset and takes nothing.
text_select_place :: proc(text: string, caret: ^int, sel_start: ^int, sel_end: ^int, offset: int) {
	place := snap_offset(text, clamp(offset, 0, len(text)))
	caret^ = place
	sel_start^ = place
	sel_end^ = place
}

//* Takes the text between the two offsets and puts the caret at the end
//* of it.
text_select_range :: proc(
	text: string,
	caret: ^int,
	sel_start: ^int,
	sel_end: ^int,
	start: int,
	end: int,
) {
	lo := snap_offset(text, clamp(min(start, end), 0, len(text)))
	hi := snap_offset(text, clamp(max(start, end), 0, len(text)))
	sel_start^ = lo
	sel_end^ = hi
	caret^ = hi
}

//* Takes all of the text.
text_select_all :: proc(text: string, caret: ^int, sel_start: ^int, sel_end: ^int) {
	sel_start^ = 0
	sel_end^ = len(text)
	caret^ = len(text)
}

//* Moves the caret, and takes the text between the old caret and the
//* new one when the selection is extended.
text_select_move :: proc(
	text: string,
	caret: ^int,
	sel_start: ^int,
	sel_end: ^int,
	offset: int,
	extend: bool,
) {
	place := snap_offset(text, clamp(offset, 0, len(text)))
	if extend {
		if sel_start^ == sel_end^ {sel_start^ = caret^}
		caret^ = place
		sel_end^ = place
	} else {
		caret^ = place
		sel_start^ = place
		sel_end^ = place
	}
}

//* Takes the text from the anchor to the offset. A word or a line is
//* taken as a whole, so that the pointer may sit anywhere in it.
text_select_extend :: proc(
	text: string,
	caret: ^int,
	sel_start: ^int,
	sel_end: ^int,
	sel: ^Text_Selection,
	offset: int,
) {
	place := snap_offset(text, clamp(offset, 0, len(text)))
	switch sel.mode {
	case .Word:
		start, end := text_word_range(text, place)
		anchor_start, anchor_end := text_word_range(text, sel.anchor)
		if place >= sel.anchor {
			sel_start^ = anchor_start
			sel_end^ = end
		} else {
			sel_start^ = start
			sel_end^ = anchor_end
		}
		caret^ = place
	case .Character:
		sel_start^ = sel.anchor
		sel_end^ = place
		caret^ = place
	}
}

//* What a click does: it puts the caret, it takes a word, or it takes
//* all of the text. A double click that comes after a double click on
//* the same word takes all of the text.
text_click_action :: proc(text: string, sel: ^Text_Selection, offset: int, clicks: int) -> Text_Click_Action {
	if clicks >= 3 {return .All}
	if clicks == 2 {
		start, end := text_word_range(text, offset)
		if sel.has_word && sel.word_start == start && sel.word_end == end {return .All}
		sel.word_start = start
		sel.word_end = end
		sel.has_word = true
		return .Word
	}
	if sel.has_word {
		start, end := text_word_range(text, offset)
		if offset < start || offset > end {sel.has_word = false}
	}
	return .Caret
}

//* A click on a text box: it puts the caret, or it takes a word, or it
//* takes all of the text.
text_select_click :: proc(
	text: string,
	caret: ^int,
	sel_start: ^int,
	sel_end: ^int,
	sel: ^Text_Selection,
	offset: int,
	clicks: int,
) {
	action := text_click_action(text, sel, offset, clicks)
	text_select_apply(text, caret, sel_start, sel_end, sel, action, offset)
}

//* Does what the click was decided to do.
text_select_apply :: proc(
	text: string,
	caret: ^int,
	sel_start: ^int,
	sel_end: ^int,
	sel: ^Text_Selection,
	action: Text_Click_Action,
	offset: int,
) {
	switch action {
	case .All:
		text_select_all(text, caret, sel_start, sel_end)
		sel.anchor = len(text)
		sel.mode = .Character
		sel.dragging = false
	case .Word:
		start, end := text_word_range(text, offset)
		text_select_range(text, caret, sel_start, sel_end, start, end)
		sel.anchor = start
		sel.mode = .Word
		sel.dragging = true
	case .Caret:
		text_select_place(text, caret, sel_start, sel_end, offset)
		sel.anchor = snap_offset(text, clamp(offset, 0, len(text)))
		sel.mode = .Character
		sel.dragging = true
	}
}

//* The place of the pointer in the widget, in the space of the widget.
text_box_local :: proc(w: ^Widget, p: Vec2) -> Vec2 {
	return Vec2{p.x - w.rect.x, p.y - w.rect.y}
}

//* The click on a text box: the caret goes where the pointer is, and a
//* drag takes the text between the two ends.
text_box_click :: proc(g: ^GUI, id: Widget_ID, p: Vec2, clicks: int) -> bool {
	w := Widget_Get(g, id)
	if w == nil {return false}
	#partial switch &d in w.data {
	case Text_Input_Data:
		text_input_click(g, id, w, p, clicks)
		return true
	case Text_Edit_Data:
		text_edit_click(g, id, w, p, clicks)
		return true
	case Rich_Text_Editor_Data:
		rich_text_editor_click(g, id, w, p, clicks)
		return true
	}
	return false
}

//* == The rules of a text box ==

//* The text as a box takes it. A box of more than one line takes a
//* carriage return as a line feed, and a box of one line takes no line
//* break at all. A carriage return and a line feed together are one
//* break.
text_for_box :: proc(g: ^GUI, text: string, many_lines: bool) -> string {
	if text == "" {return text}
	has_break := false
	for r in text {
		if r == '\n' || r == '\r' {has_break = true; break}
	}
	if !has_break {return text}
	allocator := virt.arena_allocator(&g.frame_arena)
	b: strings.Builder
	if _, err := strings.builder_init_len_cap(&b, 0, len(text), allocator); err != nil {return text}
	i := 0
	for i < len(text) {
		r, size := utf8.decode_rune_in_string(text[i:])
		if r == '\r' {
			if many_lines {strings.write_rune(&b, '\n')}
			i += size
			if i < len(text) && text[i] == '\n' {i += 1}
			continue
		}
		if r == '\n' {
			if many_lines {strings.write_rune(&b, '\n')}
			i += size
			continue
		}
		strings.write_rune(&b, r)
		i += size
	}
	return strings.to_string(b)
}

//* The characters that the rules let through.
text_rules_allow :: proc(
	g: ^GUI,
	rules: Text_Rules,
	pattern: ^Text_Pattern,
	r: rune,
) -> bool {
	if rules.allowed != "" {
		found := false
		for ch in rules.allowed {
			if ch == r {found = true; break}
		}
		if !found {return false}
	}
	if rules.pattern != "" {
		buf, n := utf8.encode_rune(r)
		if !pattern_matches(pattern, string(buf[:n])) {return false}
	}
	return true
}

//* The text without the characters that the rules do not let through.
text_rules_filter :: proc(g: ^GUI, rules: Text_Rules, text: string) -> string {
	if rules.allowed == "" && rules.pattern == "" {return text}
	pattern := pattern_compile(g, rules.pattern)
	allocator := virt.arena_allocator(&g.frame_arena)
	b: strings.Builder
	if _, err := strings.builder_init_len_cap(&b, 0, len(text), allocator); err != nil {return text}
	for r in text {
		if !text_rules_allow(g, rules, &pattern, r) {continue}
		strings.write_rune(&b, r)
	}
	return strings.to_string(b)
}

//* The text that may go into a box that holds `current` characters
//* already.
text_rules_insert :: proc(g: ^GUI, rules: Text_Rules, text: string, current: int) -> string {
	kept := text_rules_filter(g, rules, text)
	if rules.max_length <= 0 {return kept}
	room := rules.max_length - current
	if room <= 0 {return ""}
	return text_take_runes(kept, room)
}

//* Whether the text may be the new text of the box.
text_rules_allows_removal :: proc(rules: Text_Rules, count: int) -> bool {
	if rules.min_length <= 0 {return true}
	return count >= rules.min_length
}

//* The first `count` characters of the text.
text_take_runes :: proc(text: string, count: int) -> string {
	if count <= 0 {return ""}
	offset := 0
	n := 0
	for offset < len(text) && n < count {
		_, size := utf8.decode_rune_in_string(text[offset:])
		offset += size
		n += 1
	}
	return text[:offset]
}
