package GUI

COLLECT_ACCENT :: Colour{0.20, 0.52, 0.92, 1}
COLLECT_ACCENT_SOFT :: Colour{0.20, 0.52, 0.92, 0.35}
COLLECT_PANEL :: Colour{0.16, 0.17, 0.21, 1}
COLLECT_BORDER :: Colour{0.28, 0.30, 0.36, 1}
COLLECT_DIM :: Colour{0.45, 0.47, 0.53, 1}

Rating_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	max:       f32,
	mark:      string,
}

//* Width of each mark's hit-test slot.
RATING_MARK_WIDTH :: 16
RATING_DEFAULT_MAX :: 5

Make_Rating :: proc(g: ^GUI, parent: Widget_ID, opts: Rating_Opts) -> Widget_ID {
	kind_register(g, .Rating, rating_kind())
	id := New_Widget(g, .Rating, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	marks := opts.max
	if marks <= 0 {marks = RATING_DEFAULT_MAX}
	mark := opts.mark
	if mark == "" {mark = "*"}

	w.data = Rating_Data{value = opts.value, max = marks, mark = mark}
	w.focus_mode = .All
	w.custom_min_size.x = RATING_MARK_WIDTH * marks
	w.min_size.x = max(w.min_size.x, w.custom_min_size.x)
	return id
}

rating_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_rating,
		click = click_rating,
		key = key_rating,
		uses_arrow_keys = true,
		theme_name = "Rating",
	}
}

rating_data :: proc(g: ^GUI, id: Widget_ID) -> ^Rating_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Rating_Data:
		return &d
	}
	return nil
}

rating_value :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	d := rating_data(g, id)
	if d == nil {return 0}
	return d.value
}

//* Clamps the value and emits the value-changed signal.
rating_set :: proc(g: ^GUI, id: Widget_ID, new_value: f32) {
	d := rating_data(g, id)
	if d == nil {return}

	value := clamp(new_value, 0, d.max)
	if d.value == value {return}
	d.value = value
	signal_value_changed(g, id, value)
	invalidate(g, id, Dirty_Flags{.Visual})
}

rating_mark_at :: proc(g: ^GUI, id: Widget_ID, x: f32) -> int {
	w := Widget_Get(g, id)
	if w == nil {return -1}
	d := rating_data(g, id)
	if d == nil {return -1}

	content := rating_content(g, w)
	if x < content.x || x >= content.x + content.w {return -1}
	mark := int((x - content.x) / RATING_MARK_WIDTH)
	if mark < 0 || mark >= int(d.max) {return -1}
	return mark
}

rating_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

click_rating :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	mark := rating_mark_at(g, id, g.pointer.x)
	if mark >= 0 {rating_set(g, id, f32(mark + 1))}
}

key_rating :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	#partial switch e.key {
	case .Left, .Down:
		rating_set(g, id, rating_value(g, id) - 1)
	case .Right, .Up:
		rating_set(g, id, rating_value(g, id) + 1)
	case:
		return
	}
}

draw_rating :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := rating_data(g, id)
	if d == nil {return}

	ink := resolved_text_colour(g, id, w)
	dim := Scale_Colour(ink, 0.3)
	text_style := resolved_style(g, w).text
	text_style.align = .Center

	for i in 0 ..< int(d.max) {
		slot := Rect{
			x = content.x + f32(i) * RATING_MARK_WIDTH,
			y = content.y,
			w = RATING_MARK_WIDTH,
			h = content.h,
		}
		colour := dim
		if f32(i) < d.value {colour = ink}
		draw_text(g, text_style, d.mark, slot, colour)
	}
}