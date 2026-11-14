package GUI

Toggle_Switch_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	on:        bool,
}

TOGGLE_TRACK_WIDTH  :: 34
TOGGLE_TRACK_HEIGHT :: 18
TOGGLE_LABEL_GAP    :: 8

Make_Toggle_Switch :: proc(g: ^GUI, parent: Widget_ID, opts: Toggle_Switch_Opts) -> Widget_ID {
	kind_register(g, .ToggleSwitch, toggle_switch_kind())
	id := New_Widget(g, .ToggleSwitch, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Toggle_Switch_Data {
		text = opts.text,
		on   = opts.on,
	}
	w.focus_mode = .All
	return id
}

toggle_switch_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_toggle_switch,
		click = click_toggle_switch,
		measure = measure_toggle_switch,
		theme_name = "ToggleSwitch",
	}
}

measure_toggle_switch :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := toggle_switch_data(g, id)
	if d == nil {return Vec2{}}
	style := resolved_style(g, w)
	size := text_measure(g, style.text, d.text, 0)
	return Vec2 {
		x = TOGGLE_TRACK_WIDTH + TOGGLE_LABEL_GAP + size.x,
		y = max(size.y, TOGGLE_TRACK_HEIGHT),
	}
}

toggle_switch_data :: proc(g: ^GUI, id: Widget_ID) -> ^Toggle_Switch_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Toggle_Switch_Data:
		return &d
	}
	return nil
}

//* Sets the switch state and emits the toggled signal when it changes.
toggle_switch_set :: proc(g: ^GUI, id: Widget_ID, on: bool) {
	d := toggle_switch_data(g, id)
	if d == nil {return}
	if d.on == on {return}
	d.on = on
	signal_toggled(g, id, on)
	invalidate(g, id, Dirty_Flags{.Visual})
}

toggle_switch_is_on :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := toggle_switch_data(g, id)
	if d == nil {return false}
	return d.on
}

toggle_switch_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

click_toggle_switch :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := toggle_switch_data(g, id)
	if d == nil {return}
	toggle_switch_set(g, id, !d.on)
}

draw_toggle_switch :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := toggle_switch_data(g, id)
	if d == nil {return}
	style := resolved_style(g, w)
	track := Rect {
		x = content.x,
		y = content.y + (content.h - TOGGLE_TRACK_HEIGHT) * 0.5,
		w = TOGGLE_TRACK_WIDTH,
		h = TOGGLE_TRACK_HEIGHT,
	}
	track_colour := style.box.bg_color
	if track_colour.a <= 0 {track_colour = COLLECT_DIM}
	if d.on {track_colour = COLLECT_ACCENT}
	draw_rect(g, track, track_colour, track.h * 0.5)

	knob_side := track.h - 4
	knob := Rect {
		x = track.x + 2,
		y = track.y + 2,
		w = knob_side,
		h = knob_side,
	}
	if d.on {knob.x = track.x + track.w - knob_side - 2}
	draw_rect(g, knob, Colour{0.95, 0.96, 0.99, 1}, knob_side * 0.5)

	label := Rect {
		x = track.x + track.w + TOGGLE_LABEL_GAP,
		y = content.y,
		w = content.w - track.w - TOGGLE_LABEL_GAP,
		h = content.h,
	}
	draw_text(g, style.text, d.text, label, resolved_text_colour(g, id, w))
}