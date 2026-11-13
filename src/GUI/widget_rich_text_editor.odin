package GUI

import virt "core:mem/virtual"
import "core:strings"
import "core:unicode/utf8"

Rich_Text_Editor_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	wrap:      bool,
	rules:     Text_Rules,
}

Make_Rich_Text_Editor :: proc(g: ^GUI, parent: Widget_ID, opts: Rich_Text_Editor_Opts) -> Widget_ID {
	kind_register(g, .RichTextEditor, rich_text_editor_kind())
	id := New_Widget(g, .RichTextEditor, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	state, err := virt.new(&g.arena, Rich_Text_Editor_State)
	if err != nil {return id}
	state^ = Rich_Text_Editor_State{wrap = opts.wrap, rules = opts.rules}

	if opts.text != "" {
		text, err := strings.clone(opts.text)
		if err == nil {state.text = text}
	}

	end := len(state.text)
	append(&state.cursors, Rich_Cursor{caret = end, sel_start = end, sel_end = end})
	w.data = Rich_Text_Editor_Data{state = state}
	w.focus_mode = .All
	w.focus_neighbour = {id, id, id, id}
	if w.style == (Style{}) {w.style = rich_text_editor_kind().style}
	return id
}

rich_text_editor_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_rich_text_editor,
		key = key_rich_text_editor,
		pointer = rich_text_editor_pointer,
		update = update_rich_text_editor,
		style = Style{
			box = StyleBox{bg_color = RGBA(0.11, 0.12, 0.15, 1), content_margin = {6, 6, 6, 6}},
		},
		theme_name = "RichTextEditor",
	}
}

rich_text_editor_data :: proc(g: ^GUI, id: Widget_ID) -> ^Rich_Text_Editor_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Rich_Text_Editor_Data:
		return &d
	}
	return nil
}

rich_text_editor_state :: proc(g: ^GUI, id: Widget_ID) -> ^Rich_Text_Editor_State {
	data := rich_text_editor_data(g, id)
	if data == nil {return nil}
	return data.state
}

rich_text_editor_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	state := rich_text_editor_state(g, id)
	if state == nil {return ""}
	return state.text
}

rich_text_editor_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	state := rich_text_editor_state(g, id)
	if state == nil || state.text == text {return}

	new_text, err := strings.clone(text)
	if err != nil {return}
	delete(state.text)
	state.text = new_text

	end := len(state.text)
	clear(&state.cursors)
	append(&state.cursors, Rich_Cursor{caret = end, sel_start = end, sel_end = end})
	state.selection.anchor = end
	state.selection.mode = .Character
	state.selection.dragging = false
	signal_text_changed(g, id, state.text)
	invalidate(g, id, Dirty_Flags{.Visual})
}

rich_text_editor_is_wrapped :: proc(g: ^GUI, id: Widget_ID) -> bool {
	state := rich_text_editor_state(g, id)
	return state != nil && state.wrap
}

rich_text_editor_set_wrap :: proc(g: ^GUI, id: Widget_ID, wrap: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	state.wrap = wrap
	invalidate(g, id, Dirty_Flags{.Visual})
}

rich_text_editor_scroll :: proc(g: ^GUI, id: Widget_ID, delta: Vec2) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	vec2_add_to(&state.scroll, delta)
	invalidate(g, id, Dirty_Flags{.Visual})
}

rich_text_editor_cursor_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	state := rich_text_editor_state(g, id)
	if state == nil {return 0}
	return len(state.cursors)
}

rich_text_editor_add_cursor :: proc(g: ^GUI, id: Widget_ID, offset: int) -> int {
	state := rich_text_editor_state(g, id)
	if state == nil {return -1}

	place := snap_offset(state.text, clamp(offset, 0, len(state.text)))
	for cursor, i in state.cursors {
		if cursor.caret == place {return i}
	}
	append(&state.cursors, Rich_Cursor{caret = place, sel_start = place, sel_end = place})
	return len(state.cursors) - 1
}

rich_text_editor_remove_cursor :: proc(g: ^GUI, id: Widget_ID, index: int) -> int {
	state := rich_text_editor_state(g, id)
	if state == nil || index < 0 || index >= len(state.cursors) {return -1}
	ordered_remove(&state.cursors, index)
	return len(state.cursors)
}

rich_text_editor_cursor :: proc(g: ^GUI, id: Widget_ID, index: int) -> Rich_Cursor {
	state := rich_text_editor_state(g, id)
	if state == nil || index < 0 || index >= len(state.cursors) {return {}}
	return state.cursors[index]
}

rich_text_editor_set_caret :: proc(g: ^GUI, id: Widget_ID, offset: int, extend: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	for &cursor in state.cursors {
		text_select_move(state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end, offset, extend)
	}
	caret_reset(g)
}

rich_text_editor_move_caret :: proc(g: ^GUI, id: Widget_ID, forward: bool, extend: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	for &cursor in state.cursors {
		offset := forward ? next_offset(state.text, cursor.caret) : prev_offset(state.text, cursor.caret)
		text_select_move(state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end, offset, extend)
	}
	caret_reset(g)
}

rich_text_editor_select_all :: proc(g: ^GUI, id: Widget_ID) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	for &cursor in state.cursors {
		text_select_all(state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end)
	}
}

Rich_Edit :: struct {
	start: int,
	end:   int,
	text:  string,
	caret: int,
}

rich_text_editor_insert :: proc(g: ^GUI, id: Widget_ID, text: string) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	if state.pending != 0 && len(text) == 1 && text[0] == state.pending {
		state.pending = 0
		return
	}
	state.pending = 0
	rich_text_editor_insert_text(g, id, text)
}

rich_text_editor_insert_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	state := rich_text_editor_state(g, id)
	if state == nil || text == "" {return}

	edits := make([dynamic]Rich_Edit, 0, len(state.cursors))
	defer delete(edits)

	removed := 0
	for cursor in state.cursors {
		start := snap_offset(state.text, min(cursor.sel_start, cursor.sel_end))
		end := snap_offset(state.text, max(max(cursor.sel_start, cursor.sel_end), start))
		removed += utf8.rune_count_in_string(state.text[start:end])
		append(&edits, Rich_Edit{start = start, end = end})
	}

	added := text_rules_filter(g, state.rules, text_for_box(g, text, true))
	if state.rules.max_length > 0 {
		room := state.rules.max_length - (utf8.rune_count_in_string(state.text) - removed)
		count := max(len(state.cursors), 1)
		added = text_take_runes(added, max(room, 0) / count)
	}
	if added == "" {return}

	for &edit in edits {edit.text = added}

	snapshot := undo_snapshot(g, id)
	rich_text_editor_apply(g, id, state, edits)
	undo_commit(g, id, &snapshot)
	signal_text_changed(g, id, state.text)
}

rich_text_editor_backspace :: proc(g: ^GUI, id: Widget_ID) {
	rich_text_editor_remove_text(g, id, true)
}

rich_text_editor_delete :: proc(g: ^GUI, id: Widget_ID) {
	rich_text_editor_remove_text(g, id, false)
}

rich_text_editor_remove_text :: proc(g: ^GUI, id: Widget_ID, backward: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}

	edits := make([dynamic]Rich_Edit, 0, len(state.cursors))
	defer delete(edits)

	removed := 0
	for cursor in state.cursors {
		start := snap_offset(state.text, min(cursor.sel_start, cursor.sel_end))
		end := snap_offset(state.text, max(max(cursor.sel_start, cursor.sel_end), start))

		if start == end {
			if backward {
				if start == 0 {continue}
				start = prev_offset(state.text, start)
			} else {
				if end >= len(state.text) {continue}
				end = next_offset(state.text, end)
			}
		}

		removed += utf8.rune_count_in_string(state.text[start:end])
		append(&edits, Rich_Edit{start = start, end = end})
	}

	if !text_rules_allows_removal(state.rules, utf8.rune_count_in_string(state.text) - removed) {
		return
	}

	snapshot := undo_snapshot(g, id)
	rich_text_editor_apply(g, id, state, edits)
	undo_commit(g, id, &snapshot)
	signal_text_changed(g, id, state.text)
}

rich_text_editor_apply :: proc(
	g: ^GUI,
	id: Widget_ID,
	state: ^Rich_Text_Editor_State,
	edits: [dynamic]Rich_Edit,
) {
	if len(edits) == 0 {return}

	for i in 1 ..< len(edits) {
		edit := edits[i]
		j := i - 1
		for j >= 0 && edits[j].start > edit.start {
			edits[j + 1] = edits[j]
			j -= 1
		}
		edits[j + 1] = edit
	}

	shift := 0
	for &edit in edits {
		edit.caret = edit.start + len(edit.text) + shift
		shift += len(edit.text) - (edit.end - edit.start)
	}

	text := state.text
	own := false
	for i := len(edits) - 1; i >= 0; i -= 1 {
		edit := edits[i]
		start := clamp(edit.start, 0, len(text))
		end := clamp(edit.end, start, len(text))
		next := strings.concatenate({text[:start], edit.text, text[end:]})
		if own {delete(text)}
		text = next
		own = true
	}

	delete(state.text)
	state.text = text
	clear(&state.cursors)
	for edit in edits {
		append(&state.cursors, Rich_Cursor{caret = edit.caret, sel_start = edit.caret, sel_end = edit.caret})
	}
	if len(state.cursors) > 0 {state.selection.anchor = state.cursors[0].caret}
	state.selection.mode = .Character
	state.selection.dragging = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

key_rich_text_editor :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	shift := .Shift in e.mods
	ctrl := .Ctrl in e.mods

	#partial switch e.key {
	case .Left:
		rich_text_editor_move_caret(g, id, false, shift)
	case .Right:
		rich_text_editor_move_caret(g, id, true, shift)
	case .Up:
		rich_text_editor_move_line(g, id, false, shift)
	case .Down:
		rich_text_editor_move_line(g, id, true, shift)
	case .Home:
		rich_text_editor_move_line_edge(g, id, false, shift)
	case .End:
		rich_text_editor_move_line_edge(g, id, true, shift)
	case .Backspace:
		rich_text_editor_backspace(g, id)
	case .Delete:
		rich_text_editor_delete(g, id)
	case .Space, .Enter:
		if !ctrl {rich_text_editor_type(g, id, key_character(g, e.key, shift))}
	case .Tab:
		if !ctrl {rich_text_editor_type(g, id, TEXT_INDENT)}
		Event_Handled(g)
	case .A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
	     .N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
	     .Digit0, .Digit1, .Digit2, .Digit3, .Digit4, .Digit5,
	     .Digit6, .Digit7, .Digit8, .Digit9:
		if ctrl {
			rich_text_editor_command(g, id, e.key, shift)
		} else {
			rich_text_editor_type(g, id, key_character(g, e.key, shift))
		}
	}
}

rich_text_editor_type :: proc(g: ^GUI, id: Widget_ID, text: string) {
	if text == "" {return}
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	state.pending = text[0]
	rich_text_editor_insert_text(g, id, text)
}

rich_text_editor_command :: proc(g: ^GUI, id: Widget_ID, key: Key, shift: bool) {
	#partial switch key {
	case .A:
		rich_text_editor_select_all(g, id)
	case .C:
		rich_text_editor_copy(g, id, false)
	case .X:
		rich_text_editor_copy(g, id, true)
	case .V:
		rich_text_editor_paste(g, id)
	case .Z:
		if shift {text_input_redo(g, id)} else {text_input_undo(g, id)}
	case .Y:
		text_input_redo(g, id)
	}
}

rich_text_editor_copy :: proc(g: ^GUI, id: Widget_ID, cut: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	for cursor in state.cursors {
		start := min(cursor.sel_start, cursor.sel_end)
		end := max(cursor.sel_start, cursor.sel_end)
		if start == end {continue}
		clipboard_set(g, state.text[start:end])
		if cut {rich_text_editor_delete(g, id)}
		return
	}
}

rich_text_editor_paste :: proc(g: ^GUI, id: Widget_ID) {
	text := clipboard_get(g)
	if text != "" {rich_text_editor_insert(g, id, text)}
}

key_character :: proc(g: ^GUI, key: Key, shift: bool) -> string {
	c: u8
	switch {
	case key >= .A && key <= .Z:
		offset := u8(int(key) - int(Key.A))
		c = (shift ? 'A' : 'a') + offset
	case key >= .Digit0 && key <= .Digit9:
		c = '0' + u8(int(key) - int(Key.Digit0))
	case key == .Space:
		c = ' '
	case key == .Enter:
		c = '\n'
	case:
		return ""
	}

	allocator := virt.arena_allocator(&g.frame_arena)
	b: strings.Builder
	if _, err := strings.builder_init_len_cap(&b, 0, 4, allocator); err != nil {return ""}
	strings.write_rune(&b, rune(c))
	return strings.to_string(b)
}

rich_text_editor_text_style :: proc(
	g: ^GUI,
	w: ^Widget,
	state: ^Rich_Text_Editor_State,
) -> Text_Style {
	ts := resolved_style(g, w).text
	ts.wrap = state.wrap ? .Word : .Off
	ts.transform = .None
	ts.overrun = .None
	return ts
}

draw_rich_text_editor :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}

	ts := rich_text_editor_text_style(g, w, state)
	colour := resolved_text_colour(g, id, w)
	lines := text_lines(g, ts, state.text, content.w)
	box := Rect{
		x = content.x - state.scroll.x,
		y = content.y - state.scroll.y,
		w = content.w,
		h = content.h,
	}

	draw_push_clip(g.target, content)
	for cursor in state.cursors {
		start := min(cursor.sel_start, cursor.sel_end)
		end := max(cursor.sel_start, cursor.sel_end)
		if start == end {continue}
		for rect in text_selection_rects(
			g, Font_Of(g, w), box, ts, lines[:], state.text, start, end,
		) {
			draw_quad(g.target, rect, g.atlas.white_uv, TEXT_SELECTION_COLOUR, g.atlas_texture)
		}
	}

	draw_text(g, ts, state.text, box, colour)
	if g.focused == id && caret_visible(g) {
		for cursor in state.cursors {
			x, y, h := text_place(g, Font_Of(g, w), box, ts, lines[:], state.text, cursor.caret)
			draw_quad(g.target, Rect{x = x, y = y, w = 2, h = h}, g.atlas.white_uv, colour, g.atlas_texture)
		}
	}
	draw_pop_clip(g.target)
}

rich_text_editor_offset_at_local :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	local: Vec2,
) -> int {
	state := rich_text_editor_state(g, id)
	if state == nil {return 0}

	content := content_rect(g, w)
	ts := rich_text_editor_text_style(g, w, state)
	lines := text_lines(g, ts, state.text, content.w)
	box := Rect{
		x = content.x - state.scroll.x,
		y = content.y - state.scroll.y,
		w = content.w,
		h = content.h,
	}
	p := Vec2{local.x + w.rect.x, local.y + w.rect.y}
	return text_offset_at(g, Font_Of(g, w), box, ts, lines[:], state.text, p)
}

rich_text_editor_click :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, p: Vec2, clicks: int) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}

	offset := rich_text_editor_offset_at_local(g, id, w, text_box_local(w, p))
	action := text_click_action(state.text, &state.selection, offset, clicks)
	for &cursor in state.cursors {
		text_select_apply(
			state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end,
			&state.selection, action, offset,
		)
	}
	caret_reset(g)
	invalidate(g, id, Dirty_Flags{.Visual})
}

rich_text_editor_pointer :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}

	#partial switch e.kind {
	case .Move:
		if !state.selection.dragging {return}
		offset := rich_text_editor_offset_at_local(g, id, w, e.local)
		for &cursor in state.cursors {
			text_select_extend(
				state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end,
				&state.selection, offset,
			)
		}
		invalidate(g, id, Dirty_Flags{.Visual})
	case .Up:
		state.selection.dragging = false
	case .Wheel:
		rich_text_editor_scroll_wheel(g, id, w, state, e)
	}
}

RICH_TEXT_EDITOR_WHEEL_LINES :: 3

rich_text_editor_scroll_wheel :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	state: ^Rich_Text_Editor_State,
	e: Pointer_Event,
) {
	content := content_rect(g, w)
	ts := rich_text_editor_text_style(g, w, state)
	lines := text_lines(g, ts, state.text, content.w)
	line: f32 = 0
	if len(lines) > 0 {line = lines[0].height}

	if state.scroll.x < 0 {state.scroll.x = 0}
	delta := e.amount * line * RICH_TEXT_EDITOR_WHEEL_LINES
	height := text_block_height(lines[:], ts.spacing)
	if !wheel_scroll(&state.scroll.y, delta, height, content.h) {return}

	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

rich_text_editor_move_line :: proc(g: ^GUI, id: Widget_ID, down: bool, extend: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}

	content := content_rect(g, w)
	ts := rich_text_editor_text_style(g, w, state)
	lines := text_lines(g, ts, state.text, content.w)
	box := Rect{
		x = content.x - state.scroll.x,
		y = content.y - state.scroll.y,
		w = content.w,
		h = content.h,
	}

	for &cursor in state.cursors {
		index := text_line_of(lines[:], state.text, cursor.caret)
		target := index + (down ? 1 : -1)
		if target < 0 || target >= len(lines) {continue}
		x := text_x_of(g, Font_Of(g, w), box, ts, lines[:], state.text, cursor.caret)
		place := text_offset_at_x(g, Font_Of(g, w), box, ts, lines[:], state.text, target, x)
		text_select_move(state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end, place, extend)
	}
}

rich_text_editor_move_line_edge :: proc(g: ^GUI, id: Widget_ID, end: bool, extend: bool) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}

	content := content_rect(g, w)
	ts := rich_text_editor_text_style(g, w, state)
	lines := text_lines(g, ts, state.text, content.w)
	for &cursor in state.cursors {
		index := text_line_of(lines[:], state.text, cursor.caret)
		if index < 0 || index >= len(lines) {continue}
		place := end ? min(lines[index].end, len(state.text)) : lines[index].start
		text_select_move(state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end, place, extend)
	}
}

update_rich_text_editor :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	state := rich_text_editor_state(g, id)
	if state != nil {state.pending = 0}
}