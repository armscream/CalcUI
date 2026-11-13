package GUI

Accordion_Opts :: struct {
	Base_Opts: Base_Opts,
}

ACCORDION_HEADER_HEIGHT :: 26

Make_Accordion :: proc(g: ^GUI, parent: Widget_ID, opts: Accordion_Opts) -> Widget_ID {
	kind_register(g, .Accordion, accordion_kind())
	id := New_Widget(g, .Accordion, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Accordion_Data {
		open = -1,
	}
	return id
}

accordion_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_accordion,
		layout = layout_accordion,
		click = click_accordion,
		theme_name = "Accordion",
		owns_children = true,
	}
}

accordion_data :: proc(g: ^GUI, id: Widget_ID) -> ^Accordion_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Accordion_Data:
		return &d
	}
	return nil
}

//* Opens a section, or closes it if it is already open.
accordion_open :: proc(g: ^GUI, id: Widget_ID, index: int) {
	d := accordion_data(g, id)
	if d == nil {return}
	if index < 0 || index >= Widget_Child_Count(g, id) {return}
	d.open = -1 if d.open == index else index
	invalidate(g, id, Dirty_Flags{.Arrange, .Visual, .Hit})
}

//* Returns the open section, or -1 if all are closed.
accordion_open_section :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := accordion_data(g, id)
	if d == nil {return -1}
	return d.open
}

accordion_header_rect :: proc(c: ^Widget) -> Rect {
	return Rect {
		x = c.rect.x,
		y = c.rect.y - ACCORDION_HEADER_HEIGHT,
		w = c.rect.w,
		h = ACCORDION_HEADER_HEIGHT,
	}
}

layout_accordion :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect) {
	d := accordion_data(g, id)
	if d == nil {return}
	y := rect.y
	index := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		if index == d.open {
			top := y + ACCORDION_HEADER_HEIGHT
			height := c.min_size.y
			room := rect.y + rect.h - top
			if height <= 0 || height > room {height = room}
			if height < 0 {height = 0}
			layout_node(g, child, Rect{x = rect.x, y = top, w = rect.w, h = height}, w.clip)
			y = top + height
		} else {
			layout_node(
				g,
				child,
				Rect{x = rect.x, y = y + ACCORDION_HEADER_HEIGHT, w = rect.w, h = 0},
				w.clip,
			)
			y += ACCORDION_HEADER_HEIGHT
		}
		child = c.next_sibling
		index += 1
	}
}

click_accordion :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := accordion_data(g, id)
	if d == nil {return}
	index := -1
	section := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		if rect_contains(accordion_header_rect(c), g.pointer.x, g.pointer.y) {
			index = section
		}
		child = c.next_sibling
		section += 1
	}
	if index >= 0 {accordion_open(g, id, index)}
}

draw_accordion :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := accordion_data(g, id)
	if d == nil {return}
	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	index := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		header := accordion_header_rect(c)
		if header.h > 0 && header.y < content.y + content.h {
			bg := COLLECT_PANEL
			if index == d.open {bg = COLLECT_ACCENT_SOFT}
			draw_rect(g, header, bg, 0)
			draw_accordion_triangle(g, header, index == d.open, ink)
			label := Rect {
				x = header.x + 22,
				y = header.y,
				w = header.w - 28,
				h = header.h,
			}
			draw_text(g, text_style, c.name, label, ink)
		}
		draw_widget(g, child)
		child = c.next_sibling
		index += 1
	}
}

draw_accordion_triangle :: proc(g: ^GUI, header: Rect, open: bool, colour: Colour) {
	cx := header.x + 12
	cy := header.y + header.h * 0.5
	size := f32(4)
	points: [][2]f32
	if open {
		points = [][2]f32 {
			{cx - size, cy - size * 0.5},
			{cx + size, cy - size * 0.5},
			{cx, cy + size},
		}
	} else {
		points = [][2]f32 {
			{cx - size * 0.5, cy - size},
			{cx - size * 0.5, cy + size},
			{cx + size, cy},
		}
	}
	draw_polygon(g.target, points, colour, g.atlas_texture)
}