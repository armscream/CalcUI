package GUI

Segmented_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Make_Segmented :: proc(g: ^GUI, parent: Widget_ID, opts: Segmented_Opts) -> Widget_ID {
	kind_register(g, .Segmented, segmented_kind())
	id := New_Widget(g, .Segmented, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	data := Segmented_Data {
		selected = -1,
	}
	for text in opts.items {
		append(&data.items, Segmented_Item{text = text})
	}
	w.data = data
	w.focus_mode = .All
	return id
}

segmented_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_segmented, click = click_segmented, theme_name = "Segmented"}
}

segmented_data :: proc(g: ^GUI, id: Widget_ID) -> ^Segmented_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Segmented_Data:
		return &d
	}
	return nil
}

segmented_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := segmented_data(g, id)
	if d == nil {return 0}
	return len(d.items)
}

//* Selects an item and emits the item-selected signal.
segmented_select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	d := segmented_data(g, id)
	if d == nil {return}
	if index < 0 || index >= len(d.items) {return}
	if d.selected == index {return}
	d.selected = index
	signal_item_selected(g, id, index)
	invalidate(g, id, Dirty_Flags{.Visual})
}

segmented_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := segmented_data(g, id)
	if d == nil {return ""}
	if d.selected < 0 || d.selected >= len(d.items) {return ""}
	return d.items[d.selected].text
}

segmented_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

segmented_piece_at :: proc(content: Rect, count: int, x: f32) -> int {
	if count <= 0 {return -1}
	if x < content.x || x >= content.x + content.w {return -1}
	index := int((x - content.x) / (content.w / f32(count)))
	if index < 0 || index >= count {return -1}
	return index
}

segmented_piece_rect :: proc(content: Rect, count: int, index: int) -> Rect {
	width := content.w / f32(count)
	x := content.x + f32(index) * width
	w := width
	if index == count - 1 {w = content.x + content.w - x}
	return Rect{x = x, y = content.y, w = w, h = content.h}
}

click_segmented :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := segmented_data(g, id)
	if d == nil {return}
	content := segmented_content(g, w)
	index := segmented_piece_at(content, len(d.items), g.pointer.x)
	if index < 0 {return}
	segmented_select(g, id, index)
}

draw_segmented :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := segmented_data(g, id)
	if d == nil {return}
	count := len(d.items)
	if count == 0 {return}
	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	text_style.align = .Center
	for i in 0 ..< count {
		piece := segmented_piece_rect(content, count, i)
		if i == d.selected {
			draw_rect(g, piece, COLLECT_ACCENT, stylebox_radius(&style.box))
			draw_text(g, text_style, d.items[i].text, piece, Colour{1, 1, 1, 1})
		} else {
			draw_text(g, text_style, d.items[i].text, piece, ink)
		}
	}
}