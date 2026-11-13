package GUI

import "core:fmt"
import "core:math"
import virt "core:mem/virtual"

NUMBER_INPUT_HEIGHT :: 28
NUMBER_INPUT_ARROWS :: 16

Number_Input_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	min:       f32,
	max:       f32,
	step:      f32,
}

Make_Number_Input :: proc(g: ^GUI, parent: Widget_ID, opts: Number_Input_Opts) -> Widget_ID {
	kind_register(g, .NumberInput, number_input_kind())
	id := New_Widget(g, .NumberInput, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	step := opts.step
	if step <= 0 {step = 1}
	w.data = Number_Input_Data{
		value = clamp(opts.value, opts.min, opts.max),
		min = opts.min,
		max = opts.max,
		step = step,
	}
	w.focus_mode = .All
	w.base_min_size.y = max(w.base_min_size.y, NUMBER_INPUT_HEIGHT)
	w.min_size.y = w.base_min_size.y
	return id
}

number_input_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_number_input,
		click = click_number_input,
		key = key_number_input,
		uses_arrow_keys = true,
		theme_name = "NumberInput",
	}
}

number_input_data :: proc(g: ^GUI, id: Widget_ID) -> ^Number_Input_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Number_Input_Data:
		return &d
	}
	return nil
}

number_input_value :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	d := number_input_data(g, id)
	if d == nil {return 0}
	return d.value
}

//* Clamps the value and emits value-changed when it changes.
number_input_set :: proc(g: ^GUI, id: Widget_ID, value: f32) {
	d := number_input_data(g, id)
	if d == nil {return}
	new_value := clamp(value, d.min, d.max)
	if d.value == new_value {return}
	d.value = new_value
	signal_value_changed(g, id, new_value)
	invalidate(g, id, Dirty_Flags{.Visual})
}

number_input_step :: proc(value, low, high, step: f32, direction: int) -> f32 {
	return clamp(value + f32(direction) * step, low, high)
}

number_input_step_by :: proc(g: ^GUI, id: Widget_ID, delta: int) {
	d := number_input_data(g, id)
	if d == nil {return}
	snapshot := undo_snapshot(g, id)
	number_input_set(g, id, number_input_step(d.value, d.min, d.max, d.step, delta))
	undo_commit(g, id, &snapshot)
	caret_reset(g)
}

number_input_increment :: proc(g: ^GUI, id: Widget_ID) {
	number_input_step_by(g, id, 1)
}

number_input_decrement :: proc(g: ^GUI, id: Widget_ID) {
	number_input_step_by(g, id, -1)
}

number_input_is_editing :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := number_input_data(g, id)
	return d != nil && d.editing
}

number_input_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

//* Formats whole numbers without decimals.
number_input_text :: proc(g: ^GUI, value: f32) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	if value == math.floor(value) && abs(value) < 1e9 {
		return fmt.aprintf("%d", int(value), allocator = allocator)
	}
	return fmt.aprintf("%.2f", value, allocator = allocator)
}

number_input_arrows :: proc(content: Rect) -> (up, down: Rect) {
	width := min(f32(NUMBER_INPUT_ARROWS), content.w * 0.3)
	half := content.h * 0.5
	right := content.x + content.w - width
	up = Rect{x = right, y = content.y, w = width, h = half}
	down = Rect{x = right, y = content.y + half, w = width, h = content.h - half}
	return
}

click_number_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := number_input_data(g, id)
	if d == nil {return}
	content := number_input_content(g, w)
	up, down := number_input_arrows(content)

	if rect_contains(up, g.pointer.x, g.pointer.y) {
		number_input_increment(g, id)
		return
	}
	if rect_contains(down, g.pointer.x, g.pointer.y) {
		number_input_decrement(g, id)
		return
	}
	if rect_contains(content, g.pointer.x, g.pointer.y) {
		d.editing = true
		focus_set(g, id)
	}
}

key_number_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := number_input_data(g, id)
	if d == nil {return}
	ctrl := .Ctrl in e.mods

	if ctrl {
		#partial switch e.key {
		case .Z:
			if .Shift in e.mods {text_input_redo(g, id)} else {text_input_undo(g, id)}
			Event_Handled(g)
			return
		case .Y:
			text_input_redo(g, id)
			Event_Handled(g)
			return
		}
	}

	#partial switch e.key {
	case .Up:
		number_input_increment(g, id)
		return
	case .Down:
		number_input_decrement(g, id)
		return
	case .Enter, .Escape:
		d.editing = false
		return
	}

	if !d.editing {return}
	snapshot := undo_snapshot(g, id)

	#partial switch e.key {
	case .Backspace:
		number_input_set(g, id, math.floor(d.value / 10))
	case:
		c := key_character(g, e.key, false)
		if c == "" {return}
		digit := int(c[0] - '0')
		number_input_set(g, id, d.value * 10 + f32(digit))
	}

	undo_commit(g, id, &snapshot)
	caret_reset(g)
}

draw_number_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := number_input_data(g, id)
	if d == nil {return}

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	text_style.valign = .Center

	up, down := number_input_arrows(content)
	label := Rect{
		x = content.x + 6,
		y = content.y,
		w = max(up.x - content.x - 10, 0),
		h = content.h,
	}
	draw_text(g, text_style, number_input_text(g, d.value), label, ink)
	draw_number_input_arrow(g, up, true, ink)
	draw_number_input_arrow(g, down, false, ink)
}

draw_number_input_arrow :: proc(g: ^GUI, button: Rect, up: bool, colour: Colour) {
	size := f32(4)
	cx := button.x + button.w * 0.5
	cy := button.y + button.h * 0.5
	points: [][2]f32

	if up {
		points = [][2]f32{
			{cx - size, cy + size * 0.5},
			{cx + size, cy + size * 0.5},
			{cx, cy - size},
		}
	} else {
		points = [][2]f32{
			{cx - size, cy - size * 0.5},
			{cx + size, cy - size * 0.5},
			{cx, cy + size},
		}
	}
	draw_polygon(g.target, points, colour, g.atlas_texture)
}