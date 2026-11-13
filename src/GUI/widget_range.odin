package GUI

import "core:fmt"
import "core:math"

Slider_Data :: struct {
	value: f32,
	min:   f32,
	max:   f32,
	step:  f32,
}

Slider_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	min:       f32,
	max:       f32,
	step:      f32,
}

Make_Slider :: proc(g: ^GUI, parent: Widget_ID, kind: Widget_Type, opts: Slider_Opts) -> Widget_ID {
	kind_register(g, .HSlider, slider_kind())
	kind_register(g, .VSlider, slider_kind())
	id := New_Widget(g, kind, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	low, high := opts.min, opts.max
	if high <= low {high = low + 1}
	value := clamp(opts.value, low, high)
	step := opts.step
	if step <= 0 {step = (high - low) / 100}

	w.data = Slider_Data{value = value, min = low, max = high, step = step}
	w.focus_mode = .All
	return id
}

slider_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_slider, theme_name = "HSlider"}
}

Make_H_Slider :: proc(g: ^GUI, parent: Widget_ID, opts: Slider_Opts) -> Widget_ID {
	return Make_Slider(g, parent, .HSlider, opts)
}

Make_V_Slider :: proc(g: ^GUI, parent: Widget_ID, opts: Slider_Opts) -> Widget_ID {
	return Make_Slider(g, parent, .VSlider, opts)
}

slider_value :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	w := Widget_Get(g, id)
	if w == nil {return 0}
	#partial switch d in w.data {
	case Slider_Data:
		return d.value
	}
	return 0
}

//* Clamps the value, snaps it to the configured step and emits value-changed.
slider_set_value :: proc(g: ^GUI, id: Widget_ID, new_value: f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	value := new_value

	#partial switch &d in w.data {
	case Slider_Data:
		value = clamp(value, d.min, d.max)
		if d.step > 0 {
			value = clamp(d.min + math.round((value - d.min) / d.step) * d.step, d.min, d.max)
		}
		if d.value == value {return}
		d.value = value
	}
	signal_value_changed(g, id, value)
	invalidate(g, id, Dirty_Flags{.Visual})
}

draw_slider :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Slider_Data:
		vertical := w.type == .VSlider
		track := content
		if vertical {
			track.w = 6
			track.x = content.x + (content.w - 6) * 0.5
		} else {
			track.h = 6
			track.y = content.y + (content.h - 6) * 0.5
		}
		draw_rect(g, track, RGBA(0.16, 0.17, 0.21, 1), 3)

		span := d.max - d.min
		factor := f32(0)
		if span > 0 {factor = (d.value - d.min) / span}
		factor = clamp(factor, 0, 1)

		knob := Rect{w = 14, h = 14}
		if vertical {
			knob.x = track.x - 4
			knob.y = track.y + track.h - factor * track.h - knob.h * 0.5
		} else {
			knob.x = track.x + factor * track.w - knob.w * 0.5
			knob.y = track.y - 4
		}
		draw_rect(g, knob, resolved_text_colour(g, id, w), 7)
	}
}

Spin_Box_Data :: struct {
	value: f32,
	min:   f32,
	max:   f32,
	step:  f32,
}

Spin_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	min:       f32,
	max:       f32,
	step:      f32,
}

Make_Spin_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Spin_Box_Opts) -> Widget_ID {
	kind_register(g, .SpinBox, spin_box_kind())
	id := New_Widget(g, .SpinBox, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	low, high := opts.min, opts.max
	if high <= low {high = low + 100}
	step := opts.step
	if step <= 0 {step = 1}

	w.data = Spin_Box_Data{
		value = clamp(opts.value, low, high),
		min = low,
		max = high,
		step = step,
	}
	w.focus_mode = .All
	return id
}

spin_box_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_spin_box,
		click = click_spin_box,
		key = key_spin_box,
		uses_arrow_keys = true,
		theme_name = "SpinBox",
	}
}

spin_box_data :: proc(g: ^GUI, id: Widget_ID) -> ^Spin_Box_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Spin_Box_Data:
		return &d
	}
	return nil
}

spin_box_value :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	d := spin_box_data(g, id)
	if d == nil {return 0}
	return d.value
}

spin_box_set_value :: proc(g: ^GUI, id: Widget_ID, new_value: f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	value := new_value

	#partial switch &d in w.data {
	case Spin_Box_Data:
		value = clamp(value, d.min, d.max)
		if d.value == value {return}
		d.value = value
	}
	signal_value_changed(g, id, value)
	invalidate(g, id, Dirty_Flags{.Visual})
}

spin_box_step :: proc(g: ^GUI, id: Widget_ID, direction: int) {
	d := spin_box_data(g, id)
	if d == nil {return}
	spin_box_set_value(g, id, number_input_step(d.value, d.min, d.max, d.step, direction))
}

click_spin_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	up, down := number_input_arrows(content_rect(g, w))
	if rect_contains(up, g.pointer.x, g.pointer.y) {
		spin_box_step(g, id, 1)
		return
	}
	if rect_contains(down, g.pointer.x, g.pointer.y) {
		spin_box_step(g, id, -1)
		return
	}
	focus_set(g, id)
}

key_spin_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := spin_box_data(g, id)
	if d == nil {return}
	steps := 1
	if .Ctrl in e.mods {steps = 10}

	#partial switch e.key {
	case .Up:
		spin_box_step(g, id, steps)
	case .Down:
		spin_box_step(g, id, -steps)
	case .Page_Up:
		spin_box_step(g, id, 10)
	case .Page_Down:
		spin_box_step(g, id, -10)
	case .Home:
		spin_box_set_value(g, id, d.min)
	case .End:
		spin_box_set_value(g, id, d.max)
	}
}

draw_spin_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Spin_Box_Data:
		style := resolved_style(g, w)
		colour := resolved_text_colour(g, id, w)
		up, down := number_input_arrows(content)
		field := Rect{x = content.x, y = content.y, w = up.x - content.x, h = content.h}
		draw_text(g, style.text, fmt_value(d.value), field, colour)
		draw_quad(g.target, spin_box_arrow(up), g.atlas.white_uv, colour, g.atlas_texture)
		draw_quad(g.target, spin_box_arrow(down), g.atlas.white_uv, colour, g.atlas_texture)
	}
}

spin_box_arrow :: proc(arrow: Rect) -> Rect {
	return Rect{
		x = arrow.x + arrow.w * 0.5 - 4,
		y = arrow.y + arrow.h * 0.5 - 2,
		w = 8,
		h = 4,
	}
}

//* Formats whole numbers without a fractional part.
fmt_value :: proc(value: f32) -> string {
	if value == math.trunc(value) {return fmt.tprintf("%d", int(value))}
	return fmt.tprintf("%g", value)
}

Progress_Bar_Data :: struct {
	value: f32,
	max:   f32,
}

Progress_Bar_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	max:       f32,
}

Make_Progress_Bar :: proc(g: ^GUI, parent: Widget_ID, opts: Progress_Bar_Opts) -> Widget_ID {
	kind_register(g, .ProgressBar, progress_bar_kind())
	id := New_Widget(g, .ProgressBar, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	high := opts.max
	if high <= 0 {high = 100}
	w.data = Progress_Bar_Data{value = clamp(opts.value, 0, high), max = high}
	return id
}

progress_bar_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_progress_bar, theme_name = "ProgressBar"}
}

progress_bar_set_value :: proc(g: ^GUI, id: Widget_ID, new_value: f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	value := new_value

	#partial switch &d in w.data {
	case Progress_Bar_Data:
		value = clamp(value, 0, d.max)
		if d.value == value {return}
		d.value = value
	}
	signal_value_changed(g, id, value)
	invalidate(g, id, Dirty_Flags{.Visual})
}

draw_progress_bar :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Progress_Bar_Data:
		draw_rect(g, content, RGBA(0.16, 0.17, 0.21, 1), 4)
		if d.max > 0 {
			filled := Rect{
				x = content.x,
				y = content.y,
				w = content.w * clamp(d.value / d.max, 0, 1),
				h = content.h,
			}
			draw_rect(g, filled, RGBA(0.20, 0.62, 1.0, 1), 4)
		}
	}
}