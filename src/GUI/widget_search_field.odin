package GUI

import "core:math"
import virt "core:mem/virtual"
import "core:strings"

SEARCH_FIELD_HEIGHT :: 28
SEARCH_FIELD_ICON :: 12
SEARCH_FIELD_CLEAR :: 14
SEARCH_FIELD_GAP :: 8
SEARCH_FIELD_MAX_WIDTH :: 240

Search_Field_Opts :: struct {
	Base_Opts:   Base_Opts,
	text:        string,
	placeholder: string,
	hide_icon:   bool,
	max_width:   f32,
	on_submitted: proc(g: ^GUI, id: Widget_ID, text: string),
}

Make_Search_Field :: proc(g: ^GUI, parent: Widget_ID, opts: Search_Field_Opts) -> Widget_ID {
	kind_register(g, .SearchField, search_field_kind())
	id := New_Widget(g, .SearchField, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	max_width := opts.max_width
	if max_width <= 0 {max_width = SEARCH_FIELD_MAX_WIDTH}
	w.data = Search_Field_Data {
		text        = strings.clone(opts.text),
		placeholder = opts.placeholder,
		show_icon   = !opts.hide_icon,
		caret       = len(opts.text),
		max_width   = max_width,
	}
	w.focus_mode = .All
	w.signals.on_submitted = opts.on_submitted
	if w.base_min_size.y < SEARCH_FIELD_HEIGHT {w.base_min_size.y = SEARCH_FIELD_HEIGHT}
	w.min_size.y = w.base_min_size.y
	if w.custom_max_size.x <= 0 {w.custom_max_size.x = max_width}
	return id
}

search_field_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_search_field,
		click = click_search_field,
		key = key_search_field,
		measure = measure_search_field,
		uses_arrow_keys = true,
		theme_name = "SearchField",
	}
}

search_field_data :: proc(g: ^GUI, id: Widget_ID) -> ^Search_Field_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Search_Field_Data:
		return &d
	}
	return nil
}

search_field_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := search_field_data(g, id)
	if d == nil {return ""}
	return d.text
}

//* Sets the text and emits the text-changed signal.
search_field_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := search_field_data(g, id)
	if d == nil {return}
	if d.text == text {return}
	delete(d.text)
	d.text = strings.clone(text)
	d.caret = len(d.text)
	signal_text_changed(g, id, d.text)
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

//* Clears the field and emits the text-changed signal.
search_field_clear :: proc(g: ^GUI, id: Widget_ID) {
	d := search_field_data(g, id)
	if d == nil {return}
	if d.text == "" {return}
	snapshot := undo_snapshot(g, id)
	delete(d.text)
	d.text = strings.clone("")
	d.caret = 0
	undo_commit(g, id, &snapshot)
	signal_text_changed(g, id, d.text)
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	caret_reset(g)
}

search_field_is_empty :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := search_field_data(g, id)
	if d == nil {return true}
	return d.text == ""
}

search_field_placeholder :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := search_field_data(g, id)
	if d == nil {return ""}
	return d.placeholder
}

search_field_max_width :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	d := search_field_data(g, id)
	if d == nil {return 0}
	return d.max_width
}

//* Returns the caret position as a byte offset.
search_field_caret :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := search_field_data(g, id)
	if d == nil {return 0}
	return d.caret
}

//* Sets the caret position, snapping to a character boundary.
search_field_set_caret :: proc(g: ^GUI, id: Widget_ID, offset: int) {
	d := search_field_data(g, id)
	if d == nil {return}
	d.caret = snap_offset(d.text, clamp(offset, 0, len(d.text)))
	invalidate(g, id, Dirty_Flags{.Visual})
}

search_field_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

measure_search_field :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := search_field_data(g, id)
	if d == nil {return {}}
	style := resolved_style(g, w)

	text := search_field_shown_text(g, id)
	width := f32(0)
	if text != "" {
		width = text_measure(g, style.text, text, 0).x
	}
	if d.show_icon {width += f32(SEARCH_FIELD_ICON) + SEARCH_FIELD_GAP}
	if d.text != "" {width += f32(SEARCH_FIELD_CLEAR) + SEARCH_FIELD_GAP}
	pad := style.box.content_margin
	width += pad[0] + pad[2]

	return Vec2{min(width, d.max_width), f32(SEARCH_FIELD_HEIGHT)}
}

search_field_text_left :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> f32 {
	d := search_field_data(g, id)
	content := search_field_content(g, w)
	left := content.x
	if d != nil && d.show_icon {left += f32(SEARCH_FIELD_ICON) + SEARCH_FIELD_GAP}
	return left
}

search_field_caret_x :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> f32 {
	d := search_field_data(g, id)
	if d == nil {return 0}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return 0}
	lines := text_box_layout(g, f, d.text)
	return text_box_caret_x(lines, f.scale, clamp(d.caret, 0, len(d.text)))
}

search_field_shown_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := search_field_data(g, id)
	if d == nil {return ""}
	if d.text != "" {return d.text}
	return d.placeholder
}

search_field_text_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) -> Rect {
	d := search_field_data(g, id)
	left := content.x
	if d != nil && d.show_icon {left += f32(SEARCH_FIELD_ICON) + SEARCH_FIELD_GAP}
	right := content.x + content.w
	if d != nil && d.text != "" {right -= f32(SEARCH_FIELD_CLEAR) + SEARCH_FIELD_GAP}
	return Rect {
		x = left,
		y = content.y,
		w = max(right - left, 0),
		h = content.h,
	}
}

search_field_offset_at :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, x: f32) -> int {
	d := search_field_data(g, id)
	if d == nil {return 0}
	f := font_get(g, Font_Of(g, w))
	if f == nil {return 0}
	lines := text_box_layout(g, f, d.text)
	return text_box_offset_at(lines, f.scale, x - search_field_text_left(g, id, w), len(d.text))
}

search_field_type :: proc(g: ^GUI, id: Widget_ID, c: string) {
	d := search_field_data(g, id)
	if d == nil {return}
	if c == "" {return}
	caret := snap_offset(d.text, clamp(d.caret, 0, len(d.text)))
	snapshot := undo_snapshot(g, id)
	text := strings.concatenate({d.text[:caret], c, d.text[caret:]})
	delete(d.text)
	d.text = text
	d.caret = caret + len(c)
	undo_commit(g, id, &snapshot)
	signal_text_changed(g, id, d.text)
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	caret_reset(g)
}

search_field_backspace :: proc(g: ^GUI, id: Widget_ID) {
	d := search_field_data(g, id)
	if d == nil {return}
	caret := snap_offset(d.text, clamp(d.caret, 0, len(d.text)))
	if caret == 0 {return}
	start := prev_offset(d.text, caret)
	snapshot := undo_snapshot(g, id)
	text := strings.concatenate({d.text[:start], d.text[caret:]})
	delete(d.text)
	d.text = text
	d.caret = start
	undo_commit(g, id, &snapshot)
	signal_text_changed(g, id, d.text)
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	caret_reset(g)
}

search_field_delete :: proc(g: ^GUI, id: Widget_ID) {
	d := search_field_data(g, id)
	if d == nil {return}
	caret := snap_offset(d.text, clamp(d.caret, 0, len(d.text)))
	if caret >= len(d.text) {return}
	end := next_offset(d.text, caret)
	snapshot := undo_snapshot(g, id)
	text := strings.concatenate({d.text[:caret], d.text[end:]})
	delete(d.text)
	d.text = text
	d.caret = caret
	undo_commit(g, id, &snapshot)
	signal_text_changed(g, id, d.text)
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	caret_reset(g)
}

search_field_move_caret :: proc(g: ^GUI, id: Widget_ID, forward: bool) {
	d := search_field_data(g, id)
	if d == nil {return}
	caret := clamp(d.caret, 0, len(d.text))
	d.caret = forward ? next_offset(d.text, caret) : prev_offset(d.text, caret)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

search_field_move_caret_to_edge :: proc(g: ^GUI, id: Widget_ID, forward: bool) {
	d := search_field_data(g, id)
	if d == nil {return}
	d.caret = forward ? len(d.text) : 0
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

key_search_field :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := search_field_data(g, id)
	if d == nil {return}
	ctrl := .Ctrl in e.mods
	shift := .Shift in e.mods
	if ctrl {
		#partial switch e.key {
		case .Z:
			if shift {
				text_input_redo(g, id)
			} else {
				text_input_undo(g, id)
			}
			Event_Handled(g)
			return
		case .Y:
			text_input_redo(g, id)
			Event_Handled(g)
			return
		}
	}
	#partial switch e.key {
	case .Enter:
		signal_submitted(g, id, d.text)
		return
	case .Backspace:
		search_field_backspace(g, id)
		return
	case .Delete:
		search_field_delete(g, id)
		return
	case .Left:
		search_field_move_caret(g, id, false)
		return
	case .Right:
		search_field_move_caret(g, id, true)
		return
	case .Home:
		search_field_move_caret_to_edge(g, id, false)
		return
	case .End:
		search_field_move_caret_to_edge(g, id, true)
		return
	case .Escape:
		search_field_clear(g, id)
		Event_Handled(g)
		return
	case:
		c := key_character(g, e.key, .Shift in e.mods)
		if c != "" {search_field_type(g, id, c)}
	}
}

click_search_field :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := search_field_data(g, id)
	if d == nil {return}
	content := search_field_content(g, w)
	if d.text != "" {
		button := search_field_clear_rect(content)
		if rect_contains(button, g.pointer.x, g.pointer.y) {
			search_field_clear(g, id)
			return
		}
	}
	d.caret = search_field_offset_at(g, id, w, g.pointer.x)
	focus_set(g, id)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

search_field_clear_rect :: proc(content: Rect) -> Rect {
	size := f32(SEARCH_FIELD_CLEAR)
	return Rect {
		x = content.x + content.w - size - 4,
		y = content.y + (content.h - size) * 0.5,
		w = size,
		h = size,
	}
}

draw_search_field :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := search_field_data(g, id)
	if d == nil {return}
	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	text_style.valign = .Center
	text_style.wrap = .Off

	left := content.x
	if d.show_icon {
		draw_search_field_magnifier(g, content, ink)
		left += f32(SEARCH_FIELD_ICON) + SEARCH_FIELD_GAP
	}

	text := d.text
	colour := ink
	if text == "" {
		text = d.placeholder
		colour = Scale_Colour(ink, 0.55)
	}
	label := search_field_text_rect(g, id, w, content)

	if text_measure(g, text_style, text, 0).x > label.w + 0.5 {
		text_style.overrun = .Ellipsis
	}
	draw_text(g, text_style, text, label, colour)

	if d.text != "" {
		button := search_field_clear_rect(content)
		draw_search_field_cross(g, button, ink)
	}

	if g.focused == id && caret_visible(g) {
		draw_search_field_caret(g, id, w, label)
	}
}

draw_search_field_caret :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, label: Rect) {
	f := font_get(g, Font_Of(g, w))
	if f == nil {return}
	height := f.line_height
	if height <= 0 {return}

	d := search_field_data(g, id)
	if d == nil {return}
	lines := text_box_layout(g, f, d.text)
	block := height
	if len(lines) > 0 {block = lines[0].height / f.scale}

	top := label.y + (label.h - block) * 0.5
	x := label.x + search_field_caret_x(g, id, w)
	draw_quad(
		g.target,
		Rect{x = x, y = top, w = 2, h = height},
		g.atlas.white_uv,
		resolved_text_colour(g, id, w),
		g.atlas_texture,
	)
}

draw_search_field_magnifier :: proc(g: ^GUI, content: Rect, colour: Colour) {
	size := f32(SEARCH_FIELD_ICON)
	cx := content.x + size * 0.5
	cy := content.y + (content.h - size) * 0.5
	radius := size * 0.4

	segments :: 12
	points: [segments][2]f32
	for i in 0 ..< segments {
		angle := 2 * math.PI * f32(i) / f32(segments)
		points[i] = [2]f32{cx + radius * math.cos(angle), cy + radius * math.sin(angle)}
	}
	draw_polygon(g.target, points[:], colour, g.atlas_texture)

	draw_thick_line(
		g.target,
		{cx + radius * 0.7, cy + radius * 0.7},
		{cx + size * 0.5, cy + size * 0.5},
		1.5,
		colour,
		g.atlas_texture,
	)
}

draw_search_field_cross :: proc(g: ^GUI, button: Rect, colour: Colour) {
	x0 := button.x
	y0 := button.y
	x1 := button.x + button.w
	y1 := button.y + button.h
	draw_thick_line(g.target, {x0, y0}, {x1, y1}, 1.5, colour, g.atlas_texture)
	draw_thick_line(g.target, {x1, y0}, {x0, y1}, 1.5, colour, g.atlas_texture)
}