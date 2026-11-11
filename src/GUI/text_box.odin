//* == The text box ==
//* The text box widget: a buffer, a caret, a selection and the
//* composition that an IME is making in it. The offsets of the caret and
//* of the selection are byte offsets into the buffer.
//*
//* A text box is a field of one line or a box of more than one line.
//* The flags of the box say which one it is. A field of one line is as
//* tall as one line of the font, and it shows a window of the text: at
//* most so many characters, and no more than fit in the room of the
//* box. The window is scrolled sideways, and the offset of the scroll is
//* a number of characters, so that the window always begins on the
//* boundary of a character.
//*
//* A box of more than one line breaks the text into lines that fit the
//* width of the box, and it scrolls down when the lines do not fit in
//* the room it is given.
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
import "core:unicode/utf8"
import runa "./dependencies/Runa"
import virt "core:mem/virtual"

//* == The flags of a text box ==
//* Every text box of the toolkit is a field of one line or a box of
//* more than one line. The flags say which one it is.

Text_Box_Flag :: enum {
	//* The box takes more than one line: the text is broken into lines
	//* that fit the width of the box, the enter key makes a new line
	//* in it, and the box scrolls down when the lines do not fit.
	Multiline,
}

Text_Box_Flags :: bit_set[Text_Box_Flag]

//* == The options of a text box ==

Text_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	//* The rules of the box: how long the text may be, and which
	//* characters may go into it.
	rules:     Text_Rules,
	flags:     Text_Box_Flags,
	//* How many characters a box of one line shows at once. 0 is the
	//* default of fifty characters, and a negative number shows as many
	//* as fit in the box.
	shown_chars: int,
}

//* == The data of a text box ==

Text_Box_Data :: struct {
	text:        string,
	caret:       int,
	sel_start:   int,
	sel_end:     int,
	selection:   Text_Selection,
	rules:       Text_Rules,
	flags:       Text_Box_Flags,
	shown_chars: int,
	//* The first character that is shown, in a box of one line.
	scroll_chars: int,
	//* How far the text is scrolled down, in logical units.
	scroll_y:    f32,
}

//* The number of characters a box of one line shows when the program
//* says nothing.
TEXT_BOX_DEFAULT_SHOWN_CHARS :: 50

//* The number of characters the wheel goes over at a time.
TEXT_BOX_WHEEL_CHARS :: 3

//* The number of lines the wheel goes over at a time.
TEXT_BOX_WHEEL_LINES :: 3

//* The room that the scroll bar of a box takes.
TEXT_BOX_SCROLLBAR_SIZE :: 8

//* The colour of the track of the scroll bar when the theme says
//* nothing.
TEXT_BOX_SCROLLBAR_TRACK :: Colour{r = 0.13, g = 0.14, b = 0.17, a = 1}

//* The colour of the thumb of the scroll bar when the theme says
//* nothing.
TEXT_BOX_SCROLLBAR_THUMB :: Colour{r = 0.55, g = 0.58, b = 0.66, a = 1}

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

//* == The engine of the box ==

//* The walk of the clusters of a line: the caret of every cluster is
//* found, and the cluster that is nearest to a point is found too. The
//* walk of a line is the piece that every other part of the engine is
//* built on.
text_box_walk_line :: proc(glyphs: []runa.Paragraph_Glyph, scale: f32, s: ^Caret_Search) {
	pen: f32 = 0
	i := 0
	for i < len(glyphs) {
		cluster := int(glyphs[i].cluster)
		level := glyphs[i].level
		lo_x := pen
		j := i
		for j < len(glyphs) && int(glyphs[j].cluster) == cluster {
			pen += glyphs[j].x_advance / scale
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

//* The layout of a piece of text in one line.
text_box_layout :: proc(g: ^GUI, f: ^Font, text: string) -> []runa.Line {
	if f == nil || text == "" {return nil}
	opts := f.opts
	opts.max_width = 0
	return font_layout(g, f, text, opts)
}

//* The x of the caret at an offset of a line of the layout.
text_box_caret_x :: proc(lines: []runa.Line, scale: f32, offset: int) -> f32 {
	s := Caret_Search{offset = offset}
	if len(lines) > 0 {text_box_walk_line(lines[0].glyphs, scale, &s)}
	if s.found {return s.x}
	if s.has_prev {return s.prev_x}
	return 0
}

//* The offset of the text that is under a point of a line of the layout.
text_box_offset_at :: proc(lines: []runa.Line, scale: f32, x: f32, text_len: int) -> int {
	s := Caret_Search{point = x}
	if len(lines) > 0 {text_box_walk_line(lines[0].glyphs, scale, &s)}
	if !s.has_nearest {return 0}
	best := s.nearest
	if s.has_last {
		dist := abs(s.last_x - x)
		if dist < s.nearest_dist {best = text_len}
	}
	return best
}

//* The range of the text of a box of one line.
text_box_line_range :: proc(g: ^GUI, f: ^Font, text: string) -> (start, end: int) {
	start = 0
	end = len(text)
	lines := text_box_layout(g, f, text)
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

//* == The lines of a box ==

//* The style of the text of a box. A box of one line takes no line
//* break, and a box of more than one line breaks its text at the
//* boundaries of the words.
text_box_text_style :: proc(g: ^GUI, w: ^Widget, multiline: bool) -> Text_Style {
	ts := resolved_style(g, w).text
	ts.transform = .None
	ts.overrun = .None
	ts.align = .Left
	ts.wrap = multiline ? .Word : .Off
	ts.valign = multiline ? .Top : .Center
	return ts
}

//* The lines of the text of a box.
text_box_lines :: proc(g: ^GUI, w: ^Widget, text: string, multiline: bool, width: f32) -> []Text_Line {
	f := font_get(g, Font_Of(g, w))
	if f == nil {return nil}
	ts := text_box_text_style(g, w, multiline)
	lines := wrap_text_lines(g, f, ts, text, multiline ? width : 0)
	return lines[:]
}

//* The line of the text that is under a y.
text_box_line_at_y :: proc(lines: []Text_Line, spacing: f32, y: f32) -> int {
	top: f32 = 0
	for i in 0 ..< len(lines) {
		if y < top + lines[i].height {return i}
		top += lines[i].height + spacing
	}
	return len(lines) - 1
}

//* The height of all the lines of the text of a box.
text_box_content_height :: proc(lines: []Text_Line, spacing: f32) -> f32 {
	return text_block_height(lines, spacing)
}

//* == The clusters of a line ==
//* A cluster is one character as the person that reads it sees it: a
//* letter and the marks that go with it are one cluster. The clusters of
//* a line are in the order of the text, and every one of them knows the
//* room it takes and where it stands.

Text_Box_Cluster :: struct {
	offset: int,
	x:      f32,
	width:  f32,
}

text_box_clusters :: proc(g: ^GUI, line: Text_Line, scale: f32) -> []Text_Box_Cluster {
	allocator := virt.arena_allocator(&g.frame_arena)
	out := make([dynamic]Text_Box_Cluster, 0, len(line.glyphs), allocator)
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
		append(
			&out,
			Text_Box_Cluster {
				offset = cluster,
				x = rtl ? hi_x : lo_x,
				width = hi_x - lo_x,
			},
		)
		i = j
	}
	//* The glyphs of a line are in the order they are seen, and the text
	//* of a right-to-left line goes the other way.
	sort_text_box_clusters(out[:])
	return out[:]
}

sort_text_box_clusters :: proc(clusters: []Text_Box_Cluster) {
	for i in 1 ..< len(clusters) {
		c := clusters[i]
		j := i - 1
		for j >= 0 && clusters[j].offset > c.offset {
			clusters[j + 1] = clusters[j]
			j -= 1
		}
		clusters[j + 1] = c
	}
}

//* The number of the cluster that holds an offset: the cluster that
//* stands at the offset, or the last one when the offset is at the end
//* of the text.
text_box_cluster_of :: proc(clusters: []Text_Box_Cluster, offset: int) -> int {
	for i in 0 ..< len(clusters) {
		if clusters[i].offset >= offset {return i}
	}
	return len(clusters)
}

//* The byte offset of the n-th character of the text. The characters of
//* the text are the clusters of it, so the offset is always the
//* boundary of one of them.
text_box_char_offset :: proc(text: string, n: int) -> int {
	if n <= 0 {return 0}
	i := 0
	it := runa.grapheme_iter_make(text)
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok {return len(text)}
		i += 1
		if i >= n {return lo}
	}
}

//* The number of clusters that fit in a room, starting at one of them.
text_box_clusters_that_fit :: proc(clusters: []Text_Box_Cluster, from: int, width: f32) -> int {
	count := 0
	used: f32 = 0
	for i in from ..< len(clusters) {
		if used + clusters[i].width > width {break}
		used += clusters[i].width
		count += 1
	}
	return count
}

//* The number of clusters at the end of the line that fit in a room.
text_box_clusters_that_fit_at_end :: proc(clusters: []Text_Box_Cluster, width: f32) -> int {
	count := 0
	used: f32 = 0
	for i := len(clusters) - 1; i >= 0; i -= 1 {
		if used + clusters[i].width > width {break}
		used += clusters[i].width
		count += 1
	}
	return count
}

//* The room that a number of clusters takes.
text_box_clusters_width :: proc(clusters: []Text_Box_Cluster, from: int, count: int) -> f32 {
	if count <= 0 || from >= len(clusters) {return 0}
	last := from + count - 1
	if last >= len(clusters) {last = len(clusters) - 1}
	return clusters[last].x + clusters[last].width - clusters[from].x
}

//* == The window of a box of one line ==

Text_Box_Window :: struct {
	//* The number of the first character that is shown.
	first: int,
	//* The number of characters that are shown.
	count: int,
	//* The number of the last character that the scroll may begin at.
	last: int,
	//* The x of the first character that is shown.
	x: f32,
	//* The room the window takes.
	width: f32,
}

//* The number of characters a box of one line shows. A number of zero
//* is the default of fifty characters, and a negative number says that
//* as many characters as fit in the box are shown.
text_box_shown_chars :: proc(d: ^Text_Box_Data) -> int {
	if d.shown_chars == 0 {return TEXT_BOX_DEFAULT_SHOWN_CHARS}
	return d.shown_chars
}

//* The window of a box of one line: the characters that are shown, and
//* the place the scroll may be at.
text_box_window :: proc(
	clusters: []Text_Box_Cluster,
	shown: int,
	scroll: int,
	width: f32,
) -> Text_Box_Window {
	win := Text_Box_Window{}
	total := len(clusters)
	if total == 0 {return win}

	//* The scroll goes no further than the end of the text: the last
	//* characters of the text have to be able to be shown.
	tail := text_box_clusters_that_fit_at_end(clusters, width)
	room := tail
	if shown >= 0 && shown < room {room = shown}
	if room < 1 {room = 1}
	last := total - room
	if last < 0 {last = 0}

	first := clamp(scroll, 0, last)

	//* The characters that are shown from there.
	count := text_box_clusters_that_fit(clusters, first, width)
	if shown >= 0 && shown < count {count = shown}
	if count < 1 {count = 1}

	win.first = first
	win.count = count
	win.last = last
	win.x = clusters[first].x
	win.width = text_box_clusters_width(clusters, first, count)
	return win
}

//* == The box ==

//* The data of a text box.
text_box_data :: proc(g: ^GUI, id: Widget_ID) -> ^Text_Box_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Text_Box_Data:
		return &d
	}
	return nil
}

//* Whether the box takes more than one line.
text_box_is_multiline :: proc(d: ^Text_Box_Data) -> bool {
	return d != nil && (.Multiline in d.flags)
}

//* Makes a text box. A box of one line is a field, and a box of more
//* than one line is an editor: the text of it is broken into lines that
//* fit the width of the box.
Make_Text_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Text_Box_Opts) -> Widget_ID {
	kind_register(g, .TextBox, text_box_kind())
	widget_opts := base_widget_opts(opts.Base_Opts)
	widget_opts.text = opts.text
	widget_opts.text_rules = opts.rules
	id := New_Widget(g, .TextBox, parent, widget_opts)
	w := Widget_Get(g, id)
	//* The kind of the box and the window it shows are not in the
	//* options of every widget, so they are put in the data here.
	#partial switch &d in w.data {
	case Text_Box_Data:
		d.flags = opts.flags
		d.shown_chars = opts.shown_chars
	}
	w.focus_mode = .All
	return id
}

text_box_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_text_box,
		key = key_text_box,
		text_input = text_box_text_input,
		pointer = text_box_pointer,
		measure = measure_text_box,
		uses_arrow_keys = true,
		theme_name = "TextBox",
	}
}

text_box_kind_register :: proc(g: ^GUI) {
	if g == nil {return}
	kind_register(g, .TextBox, text_box_kind())
}

//* The text of a box.
text_box_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := text_box_data(g, id)
	if d == nil {return ""}
	return d.text
}

//* Sets the text of a box. The text of the box belongs to the box.
text_box_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := text_box_data(g, id)
	if d == nil {return}
	if d.text == text {return}
	new_text, err := strings.clone(text)
	if err != nil {return}
	delete(d.text)
	d.text = new_text
	d.caret = len(text)
	d.sel_start = d.caret
	d.sel_end = d.caret
	d.selection.anchor = d.caret
	d.selection.mode = .Character
	d.selection.dragging = false
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	signal_text_changed(g, id, text)
}

//* The rules of a box.
text_box_set_rules :: proc(g: ^GUI, id: Widget_ID, rules: Text_Rules) {
	d := text_box_data(g, id)
	if d == nil {return}
	d.rules = rules
}

//* Makes the box take more than one line, or makes it take one line
//* again.
text_box_set_multiline :: proc(g: ^GUI, id: Widget_ID, multiline: bool) {
	d := text_box_data(g, id)
	if d == nil {return}
	if multiline {
		d.flags += Text_Box_Flags{.Multiline}
	} else {
		d.flags -= Text_Box_Flags{.Multiline}
	}
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* == The size of a box ==
//* A box of one line is as tall as one line of the font, and a box of
//* more than one line is as tall as the lines of its text. The width of
//* a box is the room it is given: the text of it is broken into the
//* lines that fit in that room.

measure_text_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := text_box_data(g, id)
	if d == nil {return {}}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return {}}
	style := resolved_style(g, w)
	pad := style.box.content_margin
	pad[0] = max(pad[0], 1)
	pad[1] = max(pad[1], 1)
	pad[2] = max(pad[2], 1)
	pad[3] = max(pad[3], 1)

	height := f.line_height
	if height <= 0 {height = 1}

	if text_box_is_multiline(d) {
		//* A box of more than one line is as tall as the lines of its
		//* text: the lines are the ones that the text is broken into
		//* when it is not broken at all.
		ts := text_box_text_style(g, w, true)
		lines := wrap_text_lines(g, f, ts, d.text, 0)
		height = max(height, text_box_content_height(lines[:], ts.spacing))
	}

	return Vec2{0, height + pad[1] + pad[3]}
}

//* == The click on a box ==

focus_click :: proc(g: ^GUI, id: Widget_ID, p: Vec2, clicks: int = 1) {
	w := Widget_Get(g, id)
	if w == nil {return}
	if w.focus_mode == .Click || w.focus_mode == .All {
		focus_set(g, id)
	}
	text_box_click(g, id, p, clicks)
}

//* The offset of the text that the pointer is over.
text_box_offset_at_local :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, local: Vec2) -> int {
	d := text_box_data(g, id)
	if d == nil {return 0}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return 0}
	content := content_rect(g, w)
	multiline := text_box_is_multiline(d)
	lines := text_box_lines(g, w, d.text, multiline, content.w)
	if len(lines) == 0 {return 0}

	//* The place of the pointer in the content of the box.
	x := local.x - (content.x - w.rect.x)
	y := local.y - (content.y - w.rect.y)

	if !multiline {
		line := lines[0]
		clusters := text_box_clusters(g, line, f.scale)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		return text_box_line_offset_at(line, f.scale, x + win.x, len(d.text))
	}

	//* A box of more than one line: the line under the pointer, and the
	//* place in that line.
	ts := text_box_text_style(g, w, true)
	index := text_box_line_at_y(lines, ts.spacing, y + d.scroll_y)
	line := lines[index]
	line_start := line.start
	line_end := min(line.end, len(d.text))
	offset := text_box_line_offset_at(line, f.scale, x, line_end)
	return clamp(offset, line_start, line_end)
}

//* The offset of the text that is under a point of a line.
text_box_line_offset_at :: proc(line: Text_Line, scale: f32, x: f32, line_end: int) -> int {
	s := Caret_Search{point = x}
	text_box_walk_line(line.glyphs, scale, &s)
	if !s.has_nearest {return line.start}
	best := s.nearest
	if s.has_last {
		dist := abs(s.last_x - x)
		if dist < s.nearest_dist {best = line_end}
	}
	return best
}

//* The x of the caret at an offset of a line.
text_box_line_caret_x :: proc(line: Text_Line, scale: f32, offset: int) -> f32 {
	s := Caret_Search{offset = offset}
	text_box_walk_line(line.glyphs, scale, &s)
	if s.found {return s.x}
	if s.has_prev {return s.prev_x}
	return 0
}

//* A click in the box: the caret goes where the pointer is, and a
//* double click takes the word under it.
text_box_click_at :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, p: Vec2, clicks: int) {
	#partial switch &d in w.data {
	case Text_Box_Data:
		offset := text_box_offset_at_local(g, id, w, text_box_local(w, p))
		text_select_click(
			d.text,
			&d.caret,
			&d.sel_start,
			&d.sel_end,
			&d.selection,
			offset,
			clicks,
		)
		text_box_scroll_to_caret(g, id)
		caret_reset(g)
		invalidate(g, id, Dirty_Flags{.Visual})
	}
}

//* The pointer of the box: a drag takes the text between the two ends.
text_box_pointer :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	#partial switch &d in w.data {
	case Text_Box_Data:
		#partial switch e.kind {
		case .Move:
			if !d.selection.dragging {return}
			offset := text_box_offset_at_local(g, id, w, e.local)
			text_select_extend(d.text, &d.caret, &d.sel_start, &d.sel_end, &d.selection, offset)
			text_box_scroll_to_caret(g, id)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Up:
			d.selection.dragging = false
		case .Wheel:
			text_box_scroll_wheel(g, id, w, &d, e)
		}
	}
}

//* The wheel scrolls the text of the box: sideways in a box of one line,
//* and down in a box of more than one line. The box takes the wheel only
//* when it has room to scroll: when the text fits in it, the wheel goes
//* on to the container around the box.
text_box_scroll_wheel :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	d: ^Text_Box_Data,
	e: Pointer_Event,
) {
	if text_box_is_multiline(d) {
		f := font_get(g, Font_Of(g, w))
		if f == nil {return}
		content := content_rect(g, w)
		ts := text_box_text_style(g, w, true)
		lines := text_box_lines(g, w, d.text, true, content.w)
		height := text_box_content_height(lines, ts.spacing)
		line_height := f.line_height
		if len(lines) > 0 {line_height = lines[0].height}
		delta := e.amount * line_height * TEXT_BOX_WHEEL_LINES
		if !wheel_scroll(&d.scroll_y, delta, height, content.h) {return}
	} else {
		f := font_get(g, Font_Of(g, w))
		if f == nil {return}
		content := content_rect(g, w)
		lines := text_box_lines(g, w, d.text, false, content.w)
		if len(lines) == 0 {return}
		clusters := text_box_clusters(g, lines[0], f.scale)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		before := d.scroll_chars
		d.scroll_chars = clamp(
			d.scroll_chars - int(e.amount * f32(TEXT_BOX_WHEEL_CHARS)),
			0,
			win.last,
		)
		if d.scroll_chars == before {return}
	}
	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

//* == The editing of a box ==

text_box_blur :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	text_input_ime_cancel(g, id)
	#partial switch &d in w.data {
	case Text_Box_Data:
		d.sel_start = d.caret
		d.sel_end = d.caret
		d.selection.dragging = false
	case Rich_Text_Editor_Data:
		if d.state == nil {return}
		for &cursor in d.state.cursors {
			cursor.sel_start = cursor.caret
			cursor.sel_end = cursor.caret
		}
		d.state.selection.dragging = false
	case Color_Picker_Data:
		//* The typing of the code of the colour is over when the
		//* picker loses the keyboard. The code that was typed is kept,
		//* so that a click on it goes on where it was left.
		color_picker_end_edit(g, id)
	}
}

//* The text that is typed goes into the box. The enter key is not text:
//* it is a key of its own, and it makes a new line in a box of more than
//* one line. The text that the keyboard sends along with the enter key
//* is passed over, so that the box does not get two new lines.
text_box_text_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, text: string) {
	if text == "" {return}
	if text == "\r" || text == "\n" {return}
	if !text_input_ime_commit(g, id, text) {
		text_input_insert(g, id, text)
	}
}

text_input_insert :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	snapshot := Undo_Snapshot{}
	#partial switch &d in w.data {
	case Text_Box_Data:
		start := snap_offset(d.text, min(d.sel_start, d.sel_end))
		end := snap_offset(d.text, max(d.sel_start, d.sel_end))
		kept := utf8.rune_count_in_string(d.text[:start]) + utf8.rune_count_in_string(d.text[end:])
		added := text_rules_insert(g, d.rules, text_for_box(g, text, text_box_is_multiline(&d)), kept)
		if added == "" {return}
		//* The text before the change is kept, so that the change can
		//* be taken back.
		snapshot = undo_snapshot(g, id)
		new_text := strings.concatenate({d.text[:start], added, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, start + len(added))
		d.sel_start = d.caret
		d.sel_end = d.caret
		d.selection.anchor = d.caret
		changed = true
	}
	if changed {
		undo_commit(g, id, &snapshot)
		text_box_scroll_to_caret(g, id)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
		signal_text_changed(g, id, text_box_text(g, id))
		caret_reset(g)
	}
}

text_input_backspace :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	snapshot := Undo_Snapshot{}
	#partial switch &d in w.data {
	case Text_Box_Data:
		start := snap_offset(d.text, min(d.sel_start, d.sel_end))
		end := snap_offset(d.text, max(d.sel_start, d.sel_end))
		if start == end {
			if d.caret <= 0 {
				d.sel_start = d.caret
				d.sel_end = d.caret
				return
			}
			start = prev_offset(d.text, d.caret)
		}
		//* The text is only made when the rules let the removal
		//* through, so nothing is left behind when they do not.
		kept := utf8.rune_count_in_string(d.text[:start]) + utf8.rune_count_in_string(d.text[end:])
		if !text_rules_allows_removal(d.rules, kept) {
			d.sel_start = d.caret
			d.sel_end = d.caret
			return
		}
		snapshot = undo_snapshot(g, id)
		new_text := strings.concatenate({d.text[:start], d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = start
		d.sel_start = d.caret
		d.sel_end = d.caret
		d.selection.anchor = d.caret
		changed = true
	}
	if changed {
		undo_commit(g, id, &snapshot)
		text_box_scroll_to_caret(g, id)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
		signal_text_changed(g, id, text_box_text(g, id))
		caret_reset(g)
	}
}

text_input_clear :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	snapshot := Undo_Snapshot{}
	#partial switch &d in w.data {
	case Text_Box_Data:
		if d.text == "" {return}
		if !text_rules_allows_removal(d.rules, 0) {
			return
		}
		snapshot = undo_snapshot(g, id)
		delete(d.text)
		d.text = strings.clone("")
		d.caret = 0
		d.sel_start = 0
		d.sel_end = 0
		d.scroll_chars = 0
		d.scroll_y = 0
		changed = true
	}
	if changed {
		undo_commit(g, id, &snapshot)
		signal_text_changed(g, id, "")
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
		caret_reset(g)
	}
}

text_input_delete :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	changed := false
	snapshot := Undo_Snapshot{}
	#partial switch &d in w.data {
	case Text_Box_Data:
		start := snap_offset(d.text, min(d.sel_start, d.sel_end))
		end := snap_offset(d.text, max(d.sel_start, d.sel_end))
		if start == end {
			if d.caret >= len(d.text) {
				d.sel_start = d.caret
				d.sel_end = d.caret
				return
			}
			end = next_offset(d.text, d.caret)
		}
		//* The text is only made when the rules let the removal
		//* through, so nothing is left behind when they do not.
		kept := utf8.rune_count_in_string(d.text[:start]) + utf8.rune_count_in_string(d.text[end:])
		if !text_rules_allows_removal(d.rules, kept) {
			d.sel_start = d.caret
			d.sel_end = d.caret
			return
		}
		snapshot = undo_snapshot(g, id)
		new_text := strings.concatenate({d.text[:start], d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = start
		d.sel_start = d.caret
		d.sel_end = d.caret
		d.selection.anchor = d.caret
		changed = true
	}
	if changed {
		undo_commit(g, id, &snapshot)
		text_box_scroll_to_caret(g, id)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
		signal_text_changed(g, id, text_box_text(g, id))
		caret_reset(g)
	}
}

text_input_move_caret :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		offset := forward ? next_offset(d.text, d.caret) : prev_offset(d.text, d.caret)
		text_input_move_to(g, id, offset, extend)
	}
}

text_input_move_word :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		offset := forward ? word_next_offset(d.text, d.caret) : word_prev_offset(d.text, d.caret)
		text_input_move_to(g, id, offset, extend)
	}
}

text_input_move_to :: proc(g: ^GUI, id: Widget_ID, offset: int, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		text_select_move(d.text, &d.caret, &d.sel_start, &d.sel_end, offset, extend)
	}
	text_box_scroll_to_caret(g, id)
	caret_reset(g)
}

text_input_set_caret :: proc(g: ^GUI, id: Widget_ID, offset: int, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		text_select_move(d.text, &d.caret, &d.sel_start, &d.sel_end, offset, extend)
	}
	text_box_scroll_to_caret(g, id)
	caret_reset(g)
}

//* The home key and the end key: the start of the line of the caret, and
//* the end of it. A box of one line has one line, and the whole of the
//* text is taken.
text_input_line_edge :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		if !text_box_is_multiline(&d) {
			f := font_get(g, Font_Of(g, w))
			start, end := text_box_line_range(g, f, d.text)
			text_input_move_to(g, id, forward ? end : start, extend)
			return
		}
		content := content_rect(g, w)
		lines := text_box_lines(g, w, d.text, true, content.w)
		index := text_line_of(lines, d.text, d.caret)
		if index < 0 || index >= len(lines) {return}
		line_start := lines[index].start
		line_end := min(lines[index].end, len(d.text))
		text_input_move_to(g, id, forward ? line_end : line_start, extend)
	}
}

text_input_select_all :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		text_select_all(d.text, &d.caret, &d.sel_start, &d.sel_end)
	}
}

text_input_copy :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch d in w.data {
	case Text_Box_Data:
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
	case Text_Box_Data:
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

//* == The scroll of the box ==

//* Scrolls the box so that the caret is in the room of it. A box of one
//* line scrolls sideways, and a box of more than one line scrolls down.
text_box_scroll_to_caret :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	d := text_box_data(g, id)
	if d == nil {return}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return}
	content := content_rect(g, w)

	if !text_box_is_multiline(d) {
		lines := text_box_lines(g, w, d.text, false, content.w)
		if len(lines) == 0 {return}
		clusters := text_box_clusters(g, lines[0], f.scale)
		if len(clusters) == 0 {return}
		index := text_box_cluster_of(clusters, d.caret)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		if index < win.first {
			d.scroll_chars = index
		} else if index >= win.first + win.count {
			d.scroll_chars = index - win.count + 1
		}
		win = text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		d.scroll_chars = clamp(d.scroll_chars, 0, win.last)
		return
	}

	ts := text_box_text_style(g, w, true)
	lines := text_box_lines(g, w, d.text, true, content.w)
	if len(lines) == 0 {return}
	height := text_box_content_height(lines, ts.spacing)
	if height <= content.h {
		d.scroll_y = 0
		return
	}
	index := text_line_of(lines, d.text, d.caret)
	if index < 0 {return}
	top: f32 = 0
	for i in 0 ..< index {top += lines[i].height + ts.spacing}
	bottom := top + lines[index].height
	if top < d.scroll_y {
		d.scroll_y = top
	} else if bottom > d.scroll_y + content.h {
		d.scroll_y = bottom - content.h
	}
	scroll_clamp(&d.scroll_y, height, content.h)
}

//* == The place of the caret ==

//* The place on the screen of a character of the text of a box.
text_input_offset_x :: proc(g: ^GUI, id: Widget_ID, content: Rect, offset: int) -> f32 {
	w := Widget_Get(g, id)
	if w == nil {return content.x}
	d := text_box_data(g, id)
	if d == nil {return content.x}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return content.x}
	multiline := text_box_is_multiline(d)
	lines := text_box_lines(g, w, d.text, multiline, content.w)
	if len(lines) == 0 {return content.x}
	if !multiline {
		line := lines[0]
		clusters := text_box_clusters(g, line, f.scale)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		x := text_box_line_caret_x(line, f.scale, clamp(offset, 0, len(d.text)))
		return content.x + x - win.x
	}
	index := text_line_of(lines, d.text, clamp(offset, 0, len(d.text)))
	if index < 0 {return content.x}
	x := text_box_line_caret_x(lines[index], f.scale, clamp(offset, 0, len(d.text)))
	return content.x + x
}

//* The place of the caret in the box: the x comes from the text that is
//* in the box, and the height comes from the font, so the caret is as
//* tall as the text it stands in.
text_input_caret_rect :: proc(g: ^GUI, id: Widget_ID, content: Rect) -> Rect {
	w := Widget_Get(g, id)
	if w == nil {return {}}
	d := text_box_data(g, id)
	if d == nil {return {}}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return {}}
	height := f.line_height
	if height <= 0 {return {}}

	multiline := text_box_is_multiline(d)
	lines := text_box_lines(g, w, d.text, multiline, content.w)
	if len(lines) == 0 {return {}}

	if !multiline {
		line := lines[0]
		clusters := text_box_clusters(g, line, f.scale)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		block := line.height
		if block <= 0 {block = height}
		top := content.y
		switch text_box_text_style(g, w, false).valign {
		case .Center: top += (content.h - block) * 0.5
		case .Bottom: top += content.h - block
		case .Top:
		}
		return Rect {
			x = text_input_offset_x(g, id, content, d.caret),
			y = top,
			w = 2,
			h = block,
		}
	}

	//* A box of more than one line: the caret stands on the line that
	//* holds it.
	ts := text_box_text_style(g, w, true)
	index := text_line_of(lines, d.text, d.caret)
	if index < 0 {return {}}
	line := lines[index]
	y := content.y - d.scroll_y
	for i in 0 ..< index {y += lines[i].height + ts.spacing}
	block := line.height
	if block <= 0 {block = height}
	return Rect {
		x = content.x + text_box_line_caret_x(line, f.scale, clamp(d.caret, 0, len(d.text))),
		y = y,
		w = 2,
		h = block,
	}
}

//* The places of the text that is taken: one rectangle for every line
//* that has a part of it.
text_box_selection_rects :: proc(
	g: ^GUI,
	f: ^Font,
	lines: []Text_Line,
	ts: Text_Style,
	content: Rect,
	text: string,
	start, end: int,
) -> [dynamic]Rect {
	allocator := virt.arena_allocator(&g.frame_arena)
	out := make([dynamic]Rect, 0, 4, allocator)
	y := content.y
	for i in 0 ..< len(lines) {
		line := lines[i]
		line_start := line.start
		line_end := min(line.end, len(text))
		a := max(start, line_start)
		b := min(end, line_end)
		if a < b {
			x0 := text_box_line_caret_x(line, f.scale, clamp(a, line_start, line_end))
			x1 := text_box_line_caret_x(line, f.scale, clamp(b, line_start, line_end))
			lo := content.x + min(x0, x1)
			hi := content.x + max(x0, x1)
			append(&out, Rect{x = lo, y = y, w = hi - lo, h = line.height})
		}
		y += line.height + ts.spacing
	}
	return out
}

//* The place of the text that is taken. A box of one line takes its text
//* in one piece, and a box of more than one line takes it in a piece for
//* every line of it.
text_input_selection_rect :: proc(g: ^GUI, id: Widget_ID, content: Rect) -> Rect {
	w := Widget_Get(g, id)
	if w == nil {return {}}
	d := text_box_data(g, id)
	if d == nil {return {}}
	start := min(d.sel_start, d.sel_end)
	end := max(d.sel_start, d.sel_end)
	if start == end {return {}}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return {}}
	multiline := text_box_is_multiline(d)
	lines := text_box_lines(g, w, d.text, multiline, content.w)
	if len(lines) == 0 {return {}}
	if !multiline {
		line := lines[0]
		clusters := text_box_clusters(g, line, f.scale)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		x0 := text_box_line_caret_x(line, f.scale, clamp(start, 0, len(d.text)))
		x1 := text_box_line_caret_x(line, f.scale, clamp(end, 0, len(d.text)))
		lo := content.x + min(x0, x1) - win.x
		hi := content.x + max(x0, x1) - win.x
		caret := text_input_caret_rect(g, id, content)
		return Rect{x = lo, y = caret.y, w = hi - lo, h = caret.h}
	}
	ts := text_box_text_style(g, w, true)
	box := Rect{x = content.x, y = content.y - d.scroll_y, w = content.w, h = content.h}
	rects := text_box_selection_rects(g, f, lines, ts, box, d.text, start, end)
	if len(rects) == 0 {return {}}
	return rects[0]
}

//* == The IME ==

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
	case Text_Box_Data:
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
		typed := text_rules_filter(g, d.rules, text_for_box(g, text, text_box_is_multiline(&d)))
		new_text := strings.concatenate({d.text[:begin], typed, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, begin + len(typed))
		d.sel_start = d.caret
		d.sel_end = d.caret
		ime_composition_set(g, id, begin, len(typed), before)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
}

text_input_ime_commit :: proc(g: ^GUI, id: Widget_ID, text: string) -> bool {
	c, ok := ime_composition_get(g, id)
	if !ok {return false}
	w := Widget_Get(g, id)
	if w == nil {return false}
	#partial switch &d in w.data {
	case Text_Box_Data:
		begin := clamp(c.start, 0, len(d.text))
		end := clamp(begin + c.length, begin, len(d.text))
		kept := utf8.rune_count_in_string(d.text[:begin]) + utf8.rune_count_in_string(d.text[end:])
		added := text_rules_insert(g, d.rules, text_for_box(g, text, text_box_is_multiline(&d)), kept)
		//* The text before the change is kept, so that the change can
		//* be taken back.
		snapshot := undo_snapshot(g, id)
		new_text := strings.concatenate({d.text[:begin], added, d.text[end:]})
		delete(d.text)
		d.text = new_text
		d.caret = snap_offset(d.text, begin + len(added))
		d.sel_start = d.caret
		d.sel_end = d.caret
		undo_commit(g, id, &snapshot)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
		caret_reset(g)
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
	case Text_Box_Data:
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

//* The line under the composition of an IME.
text_input_draw_ime :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	c, ok := ime_composition_get(g, id)
	if !ok {return}
	d := text_box_data(g, id)
	if d == nil {return}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return}
	multiline := text_box_is_multiline(d)
	ts := text_box_text_style(g, w, multiline)
	lines := text_box_lines(g, w, d.text, multiline, content.w)
	if len(lines) == 0 {return}

	//* The composition stands on the line that holds it.
	index := 0
	if multiline {
		index = text_line_of(lines, d.text, clamp(c.start, 0, len(d.text)))
		if index < 0 {index = 0}
	}
	line := lines[index]

	//* The place of the composition in the box.
	x := content.x
	y := content.y
	if !multiline {
		clusters := text_box_clusters(g, line, f.scale)
		win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
		x -= win.x
	} else {
		y -= d.scroll_y
		for i in 0 ..< index {y += lines[i].height + ts.spacing}
	}

	x0 := text_box_line_caret_x(line, f.scale, clamp(c.start, 0, len(d.text)))
	x1 := text_box_line_caret_x(line, f.scale, clamp(c.start + c.length, 0, len(d.text)))
	lo := x + min(x0, x1)
	hi := x + max(x0, x1)
	baseline := y + line.baseline
	draw_quad(
		g.target,
		Rect{x = lo, y = baseline + 1, w = hi - lo, h = 1},
		g.atlas.white_uv,
		resolved_text_colour(g, id, w),
		g.atlas_texture,
	)
}

//* == The drawing of a box ==

draw_text_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := text_box_data(g, id)
	if d == nil {return}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return}
	multiline := text_box_is_multiline(d)
	ts := text_box_text_style(g, w, multiline)
	colour := resolved_text_colour(g, id, w)
	lines := text_box_lines(g, w, d.text, multiline, content.w)

	draw_push_clip(g.target, content)

	if multiline {
		text_box_draw_lines(g, id, w, d, f, ts, lines, content, colour)
	} else {
		text_box_draw_line(g, id, w, d, f, ts, lines, content, colour)
	}

	text_input_draw_ime(g, id, w, content)

	draw_pop_clip(g.target)
}

//* The drawing of a box of one line: the text of it, the part of it that
//* is taken, the caret, and the scroll bar at the bottom.
text_box_draw_line :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	d: ^Text_Box_Data,
	f: ^Font,
	ts: Text_Style,
	lines: []Text_Line,
	content: Rect,
	colour: Colour,
) {
	line := Text_Line{}
	if len(lines) > 0 {line = lines[0]}
	clusters := text_box_clusters(g, line, f.scale)
	win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
	caret := text_input_caret_rect(g, id, content)

	//* The text that is taken.
	start := min(d.sel_start, d.sel_end)
	end := max(d.sel_start, d.sel_end)
	if start != end {
		x0 := text_box_line_caret_x(line, f.scale, clamp(start, 0, len(d.text)))
		x1 := text_box_line_caret_x(line, f.scale, clamp(end, 0, len(d.text)))
		lo := content.x + min(x0, x1) - win.x
		hi := content.x + max(x0, x1) - win.x
		draw_quad(
			g.target,
			Rect{x = lo, y = caret.y, w = hi - lo, h = caret.h},
			g.atlas.white_uv,
			TEXT_SELECTION_COLOUR,
			g.atlas_texture,
		)
	}

	//* The text itself, moved by the scroll of the window.
	box := Rect{x = content.x - win.x, y = content.y, w = content.w, h = content.h}
	if win.width < content.w {
		//* The window shows no more characters than the program allows,
		//* and the text past the end of it is cut away.
		draw_push_clip(g.target, Rect{x = content.x, y = content.y, w = win.width, h = content.h})
		draw_text(g, ts, d.text, box, colour)
		draw_pop_clip(g.target)
	} else {
		draw_text(g, ts, d.text, box, colour)
	}

	//* The caret. It flashes while the box has the keyboard.
	if g.focused == id && caret_visible(g) {
		if caret.h > 0 {
			draw_quad(g.target, caret, g.atlas.white_uv, colour, g.atlas_texture)
		}
	}

	//* The scroll bar at the bottom of the box.
	if win.count < len(clusters) {
		text_box_draw_scrollbar_h(g, w, content, win, len(clusters))
	}
}

//* The drawing of a box of more than one line: the lines of the text,
//* the part of it that is taken, the caret, and the scroll bar at the
//* right of the box.
text_box_draw_lines :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	d: ^Text_Box_Data,
	f: ^Font,
	ts: Text_Style,
	lines: []Text_Line,
	content: Rect,
	colour: Colour,
) {
	height := text_box_content_height(lines, ts.spacing)
	scroll_clamp(&d.scroll_y, height, content.h)

	//* The text that is taken.
	start := min(d.sel_start, d.sel_end)
	end := max(d.sel_start, d.sel_end)
	if start != end {
		box := Rect{x = content.x, y = content.y - d.scroll_y, w = content.w, h = content.h}
		for rect in text_box_selection_rects(g, f, lines, ts, box, d.text, start, end) {
			draw_quad(g.target, rect, g.atlas.white_uv, TEXT_SELECTION_COLOUR, g.atlas_texture)
		}
	}

	//* The text itself, moved by the scroll of the box.
	box := Rect{x = content.x, y = content.y - d.scroll_y, w = content.w, h = content.h}
	draw_text(g, ts, d.text, box, colour)

	//* The caret. It flashes while the box has the keyboard.
	if g.focused == id && caret_visible(g) {
		caret := text_input_caret_rect(g, id, content)
		if caret.h > 0 {
			draw_quad(g.target, caret, g.atlas.white_uv, colour, g.atlas_texture)
		}
	}

	//* The scroll bar at the right of the box.
	if text_box_scrollbar_v(g, id) {
		text_box_draw_scrollbar_v(g, w, content, d.scroll_y, height)
	}
}

//* == The scroll bars of a box ==
//* The toolkit has no scroll bar widget for the text boxes: the bar is
//* drawn over the text, at the bottom of a box of one line, and at the
//* right of a box of more than one line.

text_box_scrollbar_colours :: proc(g: ^GUI, w: ^Widget) -> (track, thumb: Colour) {
	track = theme_color(g, w, "scrollbar_track")
	if track.a <= 0 {track = TEXT_BOX_SCROLLBAR_TRACK}
	thumb = theme_color(g, w, "scrollbar_thumb")
	if thumb.a <= 0 {thumb = TEXT_BOX_SCROLLBAR_THUMB}
	return
}

//* Whether the text of a box of one line does not fit in the room of
//* the box: the box shows a scroll bar at its bottom.
text_box_scrollbar_h :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil {return false}
	d := text_box_data(g, id)
	if d == nil {return false}
	if text_box_is_multiline(d) {return false}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return false}
	content := content_rect(g, w)
	lines := text_box_lines(g, w, d.text, false, content.w)
	if len(lines) == 0 {return false}
	clusters := text_box_clusters(g, lines[0], f.scale)
	win := text_box_window(clusters, text_box_shown_chars(d), d.scroll_chars, content.w)
	return win.count < len(clusters)
}

//* Whether the lines of the text of a box of more than one line do not
//* fit in the room of the box: the box shows a scroll bar at its right.
text_box_scrollbar_v :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil {return false}
	d := text_box_data(g, id)
	if d == nil {return false}
	if !text_box_is_multiline(d) {return false}
	content := content_rect(g, w)
	ts := text_box_text_style(g, w, true)
	lines := text_box_lines(g, w, d.text, true, content.w)
	height := text_box_content_height(lines, ts.spacing)
	return height > content.h
}

//* The scroll bar at the bottom of a box of one line.
text_box_draw_scrollbar_h :: proc(
	g: ^GUI,
	w: ^Widget,
	content: Rect,
	win: Text_Box_Window,
	total: int,
) {
	size: f32 = TEXT_BOX_SCROLLBAR_SIZE
	bar := Rect {
		x = content.x,
		y = content.y + content.h - size,
		w = content.w,
		h = size,
	}
	track, thumb := text_box_scrollbar_colours(g, w)
	draw_quad(g.target, bar, g.atlas.white_uv, track, g.atlas_texture)
	if total <= 0 {return}
	free := bar.w - size
	if free <= 0 {return}
	pos := f32(win.first) / f32(total) * free
	draw_quad(
		g.target,
		Rect{x = bar.x + pos, y = bar.y, w = size, h = bar.h},
		g.atlas.white_uv,
		thumb,
		g.atlas_texture,
	)
}

//* The scroll bar at the right of a box of more than one line.
text_box_draw_scrollbar_v :: proc(
	g: ^GUI,
	w: ^Widget,
	content: Rect,
	offset: f32,
	height: f32,
) {
	size: f32 = TEXT_BOX_SCROLLBAR_SIZE
	bar := Rect {
		x = content.x + content.w - size,
		y = content.y,
		w = size,
		h = content.h,
	}
	track, thumb := text_box_scrollbar_colours(g, w)
	draw_quad(g.target, bar, g.atlas.white_uv, track, g.atlas_texture)
	free := bar.h - size
	if free <= 0 || height <= 0 {return}
	pos := clamp(offset / height, 0, 1) * free
	draw_quad(
		g.target,
		Rect{x = bar.x, y = bar.y + pos, w = bar.w, h = size},
		g.atlas.white_uv,
		thumb,
		g.atlas_texture,
	)
}

//* == The keys of a box ==

//* The keys of a text box. A box of one line submits its text when the
//* enter key is pressed, and the tab key goes to the next widget. A box
//* of more than one line takes the enter key as a new line, and the tab
//* key indents the text.
key_text_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := text_box_data(g, id)
	if d == nil {return}
	multiline := text_box_is_multiline(d)

	shift := .Shift in e.mods
	ctrl := .Ctrl in e.mods

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
	case .Up:
		if multiline {text_box_move_line(g, id, false, shift)}
	case .Down:
		if multiline {text_box_move_line(g, id, true, shift)}
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
	case .Z:
		//* The ctrl key and the Z take the last change back, and the
		//* ctrl key and the Y make it happen again. The ctrl key, the
		//* shift key and the Z do the same as the ctrl key and the Y.
		if ctrl {
			if shift {
				text_input_redo(g, id)
			} else {
				text_input_undo(g, id)
			}
			Event_Handled(g)
		}
	case .Y:
		if ctrl {
			text_input_redo(g, id)
			Event_Handled(g)
		}
	case .Enter:
		if multiline {
			//* The box has more than one line, so the enter key makes
			//* a new line in it.
			text_input_insert(g, id, "\n")
			Event_Handled(g)
		} else {
			signal_submitted(g, id, d.text)
		}
	case .Escape:
		text_input_clear(g, id)
		Event_Handled(g)
	case .Tab:
		if multiline {
			//* The tab key indents the text: the box has more than one
			//* line, so the focus stays where it is.
			text_input_insert(g, id, TEXT_INDENT)
			Event_Handled(g)
		}
	}
}

//* The up key and the down key of a box of more than one line: the caret
//* goes to the line above or to the line below, and it keeps the place it
//* had across the line.
text_box_move_line :: proc(g: ^GUI, id: Widget_ID, down: bool, extend: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	d := text_box_data(g, id)
	if d == nil {return}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return}
	content := content_rect(g, w)
	lines := text_box_lines(g, w, d.text, true, content.w)
	if len(lines) == 0 {return}
	index := text_line_of(lines, d.text, d.caret)
	if index < 0 {return}
	target := index + (down ? 1 : -1)
	if target < 0 || target >= len(lines) {return}
	x := text_box_line_caret_x(lines[index], f.scale, clamp(d.caret, 0, len(d.text)))
	line_end := min(lines[target].end, len(d.text))
	place := text_box_line_offset_at(lines[target], f.scale, x, line_end)
	text_select_move(d.text, &d.caret, &d.sel_start, &d.sel_end, place, extend)
	text_box_scroll_to_caret(g, id)
	caret_reset(g)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* == The keys and the text of the tree ==

//* The keys of the widget that has the focus.
fire_key :: proc(g: ^GUI, id: Widget_ID, e: Key_Down_Event) {
	if id == INVALID_WIDGET_ID {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	if !(.Enabled in w.state) {return}

	g.event_handled = false

	if kind := widget_kind(g, w); kind.key != nil {
		kind.key(g, id, w, e)
		return
	}
}

//* The text that is typed goes to the widget that has the focus.
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
	case Text_Box_Data:
		if !text_input_ime_commit(g, id, text) {
			text_input_insert(g, id, text)
		}
	}
}
