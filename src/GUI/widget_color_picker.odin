//* A field showing a colour, with controls for picking and editing it.
//* The colour is stored as both RGB and HSV values.

package GUI

import "core:math"
import "core:strings"
import virt "core:mem/virtual"

Color_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	colour:    Colour,
}

COLOR_FIELD_HEIGHT   :: 24
COLOR_HUE_WIDTH      :: 26
COLOR_SWATCH         :: 18
COLOR_CODE_GAP       :: 6
COLOR_GRADIENT_STEPS :: 24

Make_Color_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Color_Picker_Opts) -> Widget_ID {
	kind_register(g, .ColorPicker, color_picker_kind())
	id := New_Widget(g, .ColorPicker, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	hue, saturation, value := hsv_from_colour(opts.colour)
	w.data = Color_Picker_Data{
		colour = opts.colour,
		hue = hue,
		saturation = saturation,
		value = value,
	}
	w.focus_mode = .All
	return id
}

color_picker_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_color_picker,
		click = click_color_picker,
		pointer = pointer_color_picker,
		key = key_color_picker,
		text_input = text_color_picker,
		theme_name = "ColorPicker",
	}
}

color_picker_data :: proc(g: ^GUI, id: Widget_ID) -> ^Color_Picker_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Color_Picker_Data:
		return &d
	}
	return nil
}

color_picker_colour :: proc(g: ^GUI, id: Widget_ID) -> Colour {
	d := color_picker_data(g, id)
	if d == nil { return {} }
	return d.colour
}

color_picker_set :: proc(g: ^GUI, id: Widget_ID, colour: Colour) {
	d := color_picker_data(g, id)
	if d == nil { return }
	d.colour = colour
	d.hue, d.saturation, d.value = hsv_from_colour(colour)
	color_picker_discard_edit(g, id)
	signal_colour_changed(g, id, colour)
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_set_hsv :: proc(g: ^GUI, id: Widget_ID, hue, saturation, value: f32) {
	d := color_picker_data(g, id)
	if d == nil { return }
	d.hue = clamp(hue, 0, 1)
	d.saturation = clamp(saturation, 0, 1)
	d.value = clamp(value, 0, 1)
	d.colour = colour_from_hsv(d.hue, d.saturation, d.value)
	color_picker_discard_edit(g, id)
	signal_colour_changed(g, id, d.colour)
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_is_open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := color_picker_data(g, id)
	return d != nil && d.open
}

color_picker_set_open :: proc(g: ^GUI, id: Widget_ID, open: bool) {
	d := color_picker_data(g, id)
	if d == nil || d.open == open { return }
	d.open = open
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_is_editing :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := color_picker_data(g, id)
	return d != nil && d.editing
}

color_picker_edit_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := color_picker_data(g, id)
	if d == nil { return "" }
	return d.edit_text
}

//* Colour conversion

colour_from_hsv :: proc(hue, saturation, value: f32) -> Colour {
	h := hue - math.floor(hue)
	s := clamp(saturation, 0, 1)
	v := clamp(value, 0, 1)
	part := h * 6
	i := int(part)
	f := part - f32(i)
	p := v * (1 - s)
	q := v * (1 - f * s)
	t := v * (1 - (1 - f) * s)

	switch i % 6 {
	case 0: return Colour{v, t, p, 1}
	case 1: return Colour{q, v, p, 1}
	case 2: return Colour{p, v, t, 1}
	case 3: return Colour{p, q, v, 1}
	case 4: return Colour{t, p, v, 1}
	case 5: return Colour{v, p, q, 1}
	}
	return Colour{v, v, v, 1}
}

hsv_from_colour :: proc(c: Colour) -> (f32, f32, f32) {
	brightest := max(c.r, max(c.g, c.b))
	darkest := min(c.r, min(c.g, c.b))
	difference := brightest - darkest
	hue := f32(0)

	if difference > 0 {
		if brightest == c.r {
			hue = (c.g - c.b) / difference
		} else if brightest == c.g {
			hue = 2 + (c.b - c.r) / difference
		} else {
			hue = 4 + (c.r - c.g) / difference
		}
		hue /= 6
		if hue < 0 { hue += 1 }
	}

	saturation := f32(0)
	if brightest > 0 { saturation = difference / brightest }
	return hue, saturation, brightest
}

//* Hex conversion

colour_to_hex :: proc(g: ^GUI, c: Colour) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	builder: strings.Builder
	err := strings.builder_init_len_cap(&builder, 0, 7, allocator)
	if err != nil { return "" }

	strings.write_string(&builder, "#")
	digits := "0123456789ABCDEF"
	parts := [3]f32{c.r, c.g, c.b}
	for i in 0..<3 {
		n := int(clamp(parts[i], 0, 1) * 255 + 0.5)
		strings.write_byte(&builder, digits[n >> 4])
		strings.write_byte(&builder, digits[n & 15])
	}
	return strings.to_string(builder)
}

hex_digit :: proc(ch: rune) -> int {
	if ch >= '0' && ch <= '9' { return int(ch - '0') }
	if ch >= 'a' && ch <= 'f' { return int(ch - 'a') + 10 }
	if ch >= 'A' && ch <= 'F' { return int(ch - 'A') + 10 }
	return -1
}

colour_from_hex :: proc(text: string) -> (Colour, bool) {
	code := strings.trim_space(text)
	if len(code) > 0 && code[0] == '#' { code = code[1:] }

	values: [6]int
	count := 0
	for ch in code {
		n := hex_digit(ch)
		if n < 0 || count >= 6 { return {}, false }
		values[count] = n
		count += 1
	}

	if count == 3 {
		values[3] = values[2]
		values[4] = values[1]
		values[5] = values[0]
		count = 6
	}
	if count != 6 { return {}, false }

	r := f32(values[0] * 16 + values[1]) / 255
	green := f32(values[2] * 16 + values[3]) / 255
	b := f32(values[4] * 16 + values[5]) / 255
	return Colour{r, green, b, 1}, true
}

//* Layout

Color_Picker_Layout :: struct {
	field: Rect,
	hue:   Rect,
	sv:    Rect,
}

color_picker_layout :: proc(content: Rect, open: bool) -> Color_Picker_Layout {
	layout := Color_Picker_Layout{field = content}
	if !open { return layout }

	field_h := min(f32(COLOR_FIELD_HEIGHT), content.h)
	layout.field = Rect{x = content.x, y = content.y, w = content.w, h = field_h}
	top := content.y + field_h + 4
	height := content.y + content.h - top
	if height <= 0 { return layout }

	hue_w := min(f32(COLOR_HUE_WIDTH), content.w * 0.25)
	layout.hue = Rect{x = content.x, y = top, w = hue_w, h = height}
	side := min(height, content.w - hue_w - 8)
	if side > 0 {
		layout.sv = Rect{x = content.x + hue_w + 8, y = top, w = side, h = side}
	}
	return layout
}

color_picker_swatch_rect :: proc(layout: Color_Picker_Layout) -> Rect {
	return Rect{
		x = layout.field.x,
		y = layout.field.y + (layout.field.h - COLOR_SWATCH) * 0.5,
		w = COLOR_SWATCH,
		h = COLOR_SWATCH,
	}
}

color_picker_code :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := color_picker_data(g, id)
	if d == nil { return "" }
	if d.editing { return d.edit_text }
	return colour_to_hex(g, d.colour)
}

color_picker_code_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, layout: Color_Picker_Layout) -> Rect {
	d := color_picker_data(g, id)
	if d == nil { return {} }

	style := resolved_style(g, w)
	text := color_picker_code(g, id)
	width := f32(0)
	if text != "" { width = text_measure(g, style.text, text, 0).x }

	height := f32(COLOR_SWATCH)
	if f := font_get(g, Font_Of(g, w)); f != nil && f.line_height > 0 {
		height = f.line_height
	}
	swatch := color_picker_swatch_rect(layout)
	return Rect{
		x = swatch.x + swatch.w + COLOR_CODE_GAP,
		y = layout.field.y,
		w = width,
		h = height,
	}
}

color_picker_caret_x :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> f32 {
	d := color_picker_data(g, id)
	if d == nil { return 0 }
	f := font_get(g, Font_Of(g, w))
	if f == nil { return 0 }
	code := color_picker_code(g, id)
	lines := text_box_layout(g, f, code)
	return text_box_caret_x(lines, f.scale, clamp(d.caret, 0, len(code)))
}

color_picker_offset_at :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, layout: Color_Picker_Layout, x: f32) -> int {
	d := color_picker_data(g, id)
	if d == nil { return 0 }
	f := font_get(g, Font_Of(g, w))
	if f == nil { return 0 }
	code := color_picker_code(g, id)
	lines := text_box_layout(g, f, code)
	left := color_picker_code_rect(g, id, w, layout).x
	return text_box_offset_at(lines, f.scale, x - left, len(code))
}

//* Editing

color_picker_begin_edit :: proc(g: ^GUI, id: Widget_ID, caret: int) {
	d := color_picker_data(g, id)
	if d == nil { return }
	if d.edit_text == "" {
		d.edit_text = strings.clone(colour_to_hex(g, d.colour))
	}
	d.editing = true
	d.caret = snap_offset(d.edit_text, clamp(caret, 0, len(d.edit_text)))
	d.sel_start = d.caret
	d.sel_end = d.caret
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_end_edit :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil || !d.editing { return }
	d.editing = false
	d.caret = 0
	d.sel_start = 0
	d.sel_end = 0
	d.selection = Text_Selection{}
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_discard_edit :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil { return }
	d.editing = false
	delete(d.edit_text)
	d.edit_text = ""
	d.caret = 0
	d.sel_start = 0
	d.sel_end = 0
	d.selection = Text_Selection{}
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_confirm_edit :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := color_picker_data(g, id)
	if d == nil { return false }
	colour, ok := colour_from_hex(d.edit_text)
	color_picker_discard_edit(g, id)
	if !ok { return false }
	color_picker_set(g, id, colour)
	return true
}

color_picker_clean :: proc(g: ^GUI, text: string) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, len(text), allocator); err != nil {
		return ""
	}
	for ch in text {
		if ch == '#' || hex_digit(ch) >= 0 {
			strings.write_rune(&builder, ch)
		}
	}
	return strings.to_string(builder)
}

color_picker_selection :: proc(d: ^Color_Picker_Data) -> (start, end: int) {
	return min(d.sel_start, d.sel_end), max(d.sel_start, d.sel_end)
}

color_picker_type :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := color_picker_data(g, id)
	if d == nil || !d.editing || text == "" { return }
	typed := color_picker_clean(g, text)
	if typed == "" { return }

	start, end := color_picker_selection(d)
	snapshot := undo_snapshot(g, id)
	code := strings.concatenate({d.edit_text[:start], typed, d.edit_text[end:]})
	delete(d.edit_text)
	d.edit_text = code
	d.caret = start + len(typed)
	d.sel_start = d.caret
	d.sel_end = d.caret
	undo_commit(g, id, &snapshot)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

color_picker_backspace :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil { return }
	start, end := color_picker_selection(d)
	if start == end {
		if d.caret <= 0 { return }
		start = prev_offset(d.edit_text, d.caret)
	}

	snapshot := undo_snapshot(g, id)
	code := strings.concatenate({d.edit_text[:start], d.edit_text[end:]})
	delete(d.edit_text)
	d.edit_text = code
	d.caret = start
	d.sel_start = start
	d.sel_end = start
	undo_commit(g, id, &snapshot)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

color_picker_delete :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil { return }
	start, end := color_picker_selection(d)
	if start == end {
		if d.caret >= len(d.edit_text) { return }
		end = next_offset(d.edit_text, d.caret)
	}

	snapshot := undo_snapshot(g, id)
	code := strings.concatenate({d.edit_text[:start], d.edit_text[end:]})
	delete(d.edit_text)
	d.edit_text = code
	d.caret = start
	d.sel_start = start
	d.sel_end = start
	undo_commit(g, id, &snapshot)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

color_picker_move_caret :: proc(g: ^GUI, id: Widget_ID, forward, extend: bool) {
	d := color_picker_data(g, id)
	if d == nil { return }
	offset := prev_offset(d.edit_text, d.caret)
	if forward { offset = next_offset(d.edit_text, d.caret) }
	text_select_move(d.edit_text, &d.caret, &d.sel_start, &d.sel_end, offset, extend)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

color_picker_move_caret_to_edge :: proc(g: ^GUI, id: Widget_ID, forward, extend: bool) {
	d := color_picker_data(g, id)
	if d == nil { return }
	offset := 0
	if forward { offset = len(d.edit_text) }
	text_select_move(d.edit_text, &d.caret, &d.sel_start, &d.sel_end, offset, extend)
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_select_all :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil { return }
	text_select_all(d.edit_text, &d.caret, &d.sel_start, &d.sel_end)
	invalidate(g, id, Dirty_Flags{.Visual})
}

color_picker_copy :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil { return }
	start, end := color_picker_selection(d)
	if start < end { clipboard_set(g, d.edit_text[start:end]) }
}

color_picker_cut :: proc(g: ^GUI, id: Widget_ID) {
	d := color_picker_data(g, id)
	if d == nil { return }
	start, end := color_picker_selection(d)
	if start >= end { return }
	clipboard_set(g, d.edit_text[start:end])
	color_picker_delete(g, id)
}

color_picker_paste :: proc(g: ^GUI, id: Widget_ID) {
	text := clipboard_get(g)
	if text != "" { color_picker_type(g, id, text) }
}

//* Input

key_color_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := color_picker_data(g, id)
	if d == nil || !d.editing { return }

	shift := .Shift in e.mods
	ctrl := .Ctrl in e.mods
	#partial switch e.key {
	case .Enter:
		color_picker_confirm_edit(g, id)
		Event_Handled(g)
	case .Escape:
		color_picker_discard_edit(g, id)
		Event_Handled(g)
	case .Backspace:
		color_picker_backspace(g, id)
	case .Delete:
		color_picker_delete(g, id)
	case .Left:
		color_picker_move_caret(g, id, false, shift)
		Event_Handled(g)
	case .Right:
		color_picker_move_caret(g, id, true, shift)
		Event_Handled(g)
	case .Home:
		color_picker_move_caret_to_edge(g, id, false, shift)
	case .End:
		color_picker_move_caret_to_edge(g, id, true, shift)
	case .A:
		if ctrl {
			color_picker_select_all(g, id)
			Event_Handled(g)
		}
	case .C:
		if ctrl {
			color_picker_copy(g, id)
			Event_Handled(g)
		}
	case .X:
		if ctrl {
			color_picker_cut(g, id)
			Event_Handled(g)
		}
	case .V:
		if ctrl {
			color_picker_paste(g, id)
			Event_Handled(g)
		}
	case .Z:
		if ctrl {
			if shift { text_input_redo(g, id) } else { text_input_undo(g, id) }
			Event_Handled(g)
		}
	case .Y:
		if ctrl {
			text_input_redo(g, id)
			Event_Handled(g)
		}
	}
}

text_color_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, text: string) {
	d := color_picker_data(g, id)
	if d != nil && d.editing { color_picker_type(g, id, text) }
}

pointer_color_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	d := color_picker_data(g, id)
	if d == nil { return }

	#partial switch e.kind {
	case .Down:
		layout := color_picker_layout(color_picker_content(g, w), d.open)
		if d.open && (rect_contains(layout.hue, e.pos.x, e.pos.y) || rect_contains(layout.sv, e.pos.x, e.pos.y)) {
			d.picking = true
			color_picker_pick_at(g, id, w, layout, e.pos)
			return
		}

		code := color_picker_code_rect(g, id, w, layout)
		if !rect_contains(code, e.pos.x, e.pos.y) { return }
		offset := color_picker_offset_at(g, id, w, layout, e.pos.x)
		if !d.editing { color_picker_begin_edit(g, id, offset) }
		text_select_click(d.edit_text, &d.caret, &d.sel_start, &d.sel_end, &d.selection, offset, e.clicks)
		invalidate(g, id, Dirty_Flags{.Visual})

	case .Move:
		if d.picking {
			layout := color_picker_layout(color_picker_content(g, w), d.open)
			color_picker_pick_at(g, id, w, layout, e.pos)
			return
		}
		if !d.editing || !d.selection.dragging { return }
		layout := color_picker_layout(color_picker_content(g, w), d.open)
		offset := color_picker_offset_at(g, id, w, layout, e.pos.x)
		text_select_extend(d.edit_text, &d.caret, &d.sel_start, &d.sel_end, &d.selection, offset)
		invalidate(g, id, Dirty_Flags{.Visual})

	case .Up:
		d.selection.dragging = false
		d.picking = false
	}
}

color_picker_pick_at :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, layout: Color_Picker_Layout, pos: Vec2) {
	d := color_picker_data(g, id)
	if d == nil { return }

	if rect_contains(layout.hue, pos.x, pos.y) {
		hue := (pos.x - layout.hue.x) / layout.hue.w
		color_picker_set_hsv(g, id, hue, d.saturation, d.value)
	} else if rect_contains(layout.sv, pos.x, pos.y) {
		saturation := (pos.x - layout.sv.x) / layout.sv.w
		value := 1 - (pos.y - layout.sv.y) / layout.sv.h
		color_picker_set_hsv(g, id, d.hue, saturation, value)
	}
}

click_color_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := color_picker_data(g, id)
	if d == nil { return }

	layout := color_picker_layout(color_picker_content(g, w), d.open)
	if rect_contains(color_picker_code_rect(g, id, w, layout), g.pointer.x, g.pointer.y) { return }

	swatch := color_picker_swatch_rect(layout)
	if rect_contains(swatch, g.pointer.x, g.pointer.y) {
		d.open = !d.open
		invalidate(g, id, Dirty_Flags{.Visual})
		return
	}

	if !d.open {
		d.open = true
		return
	}

	if rect_contains(layout.hue, g.pointer.x, g.pointer.y) {
		hue := (g.pointer.x - layout.hue.x) / layout.hue.w
		color_picker_set_hsv(g, id, hue, d.saturation, d.value)
		return
	}
	if rect_contains(layout.sv, g.pointer.x, g.pointer.y) {
		saturation := (g.pointer.x - layout.sv.x) / layout.sv.w
		value := 1 - (g.pointer.y - layout.sv.y) / layout.sv.h
		color_picker_set_hsv(g, id, d.hue, saturation, value)
		return
	}
	if !rect_contains(layout.field, g.pointer.x, g.pointer.y) {
		d.open = false
		invalidate(g, id, Dirty_Flags{.Visual})
	}
}

color_picker_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

//* Drawing

draw_color_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := color_picker_data(g, id)
	if d == nil { return }

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	layout := color_picker_layout(content, d.open)
	swatch := color_picker_swatch_rect(layout)
	draw_rect(g, swatch, d.colour, 2)
	draw_outline(g, swatch, COLLECT_BORDER, 1)

	label := color_picker_code_rect(g, id, w, layout)
	label.w = max(layout.field.w - (label.x - layout.field.x), label.w)
	draw_color_picker_selection(g, id, w, label)
	draw_text(g, style.text, color_picker_code(g, id), label, ink)

	if d.editing && g.focused == id && caret_visible(g) {
		draw_color_picker_caret(g, id, w, label)
	}
	if !d.open { return }

	for i in 0 ..< COLOR_GRADIENT_STEPS {
		hue := f32(i) / f32(COLOR_GRADIENT_STEPS - 1)
		x := layout.hue.x + layout.hue.w * f32(i) / f32(COLOR_GRADIENT_STEPS)
		draw_rect(g, Rect{
			x = x,
			y = layout.hue.y,
			w = layout.hue.w / f32(COLOR_GRADIENT_STEPS) + 1,
			h = layout.hue.h,
		}, colour_from_hsv(hue, 1, 1), 0)
	}

	for i in 0 ..< COLOR_GRADIENT_STEPS {
		saturation := f32(i) / f32(COLOR_GRADIENT_STEPS - 1)
		x := layout.sv.x + layout.sv.w * f32(i) / f32(COLOR_GRADIENT_STEPS)
		draw_rect(g, Rect{
			x = x,
			y = layout.sv.y,
			w = layout.sv.w / f32(COLOR_GRADIENT_STEPS) + 1,
			h = layout.sv.h,
		}, colour_from_hsv(d.hue, saturation, 1), 0)
	}

	for i in 0 ..< COLOR_GRADIENT_STEPS {
		shade := f32(i) / f32(COLOR_GRADIENT_STEPS - 1)
		y := layout.sv.y + layout.sv.h * f32(i) / f32(COLOR_GRADIENT_STEPS)
		draw_rect(g, Rect{
			x = layout.sv.x,
			y = y,
			w = layout.sv.w,
			h = layout.sv.h / f32(COLOR_GRADIENT_STEPS) + 1,
		}, Colour{0, 0, 0, shade}, 0)
	}
}

draw_color_picker_selection :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, label: Rect) {
	d := color_picker_data(g, id)
	if d == nil { return }
	start, end := color_picker_selection(d)
	if start == end { return }

	f := font_get(g, Font_Of(g, w))
	if f == nil { return }
	lines := text_box_layout(g, f, d.edit_text)
	x0 := text_box_caret_x(lines, f.scale, clamp(start, 0, len(d.edit_text)))
	x1 := text_box_caret_x(lines, f.scale, clamp(end, 0, len(d.edit_text)))
	lo := label.x + min(x0, x1)
	hi := label.x + max(x0, x1)
	draw_rect(g, Rect{x = lo, y = label.y, w = hi - lo, h = label.h}, TEXT_SELECTION_COLOUR, 0)
}

draw_color_picker_caret :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, label: Rect) {
	f := font_get(g, Font_Of(g, w))
	if f == nil || f.line_height <= 0 { return }

	d := color_picker_data(g, id)
	if d == nil { return }
	lines := text_box_layout(g, f, d.edit_text)
	block := f.line_height
	if len(lines) > 0 { block = lines[0].height / f.scale }

	x := label.x + color_picker_caret_x(g, id, w)
	y := label.y + (label.h - block) * 0.5
	draw_quad(
		g.target,
		Rect{x = x, y = y, w = 2, h = f.line_height},
		g.atlas.white_uv,
		resolved_text_colour(g, id, w),
		g.atlas_texture,
	)
}