//* Containers lay out their children.

package GUI

import virt "core:mem/virtual"

//* == Grid ==

Grid_Data :: struct {
	columns:      int,
	h_separation: f32,
	v_separation: f32,
	margin:       [4]f32,
	show_lines:   bool,
	line_colour:  Colour,
	cells:        []Rect,
	cell_count:   int,
}

Grid_Opts :: struct {
	Base_Opts:    Base_Opts,
	columns:      int,
	h_separation: f32,
	v_separation: f32,
	margin:       [4]f32,
	show_lines:   bool,
	line_colour:  Colour,
}

Make_Grid_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Grid_Opts) -> Widget_ID {
	kind_register(g, .GridContainer, grid_container_kind())
	id := New_Widget(g, .GridContainer, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	h_sep := opts.h_separation
	v_sep := opts.v_separation
	if h_sep <= 0 { h_sep = opts.Base_Opts.separation }
	if v_sep <= 0 { v_sep = opts.Base_Opts.separation }

	w.data = Grid_Data{
		columns      = opts.columns,
		h_separation = h_sep,
		v_separation = v_sep,
		margin       = opts.margin,
		show_lines   = opts.show_lines,
		line_colour  = opts.line_colour,
	}
	return id
}

grid_container_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_grid_container, theme_name = "GridContainer"}
}

grid_data :: proc(g: ^GUI, id: Widget_ID) -> ^Grid_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Grid_Data:
		return &d
	}
	return nil
}

grid_cells :: proc(g: ^GUI, id: Widget_ID, count: int) -> []Rect {
	d := grid_data(g, id)
	if d == nil { return nil }
	if count > len(d.cells) {
		d.cells = make([]Rect, count, virt.arena_allocator(&g.arena))
	}
	d.cell_count = count
	return d.cells[:count]
}

draw_grid_container :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Grid_Data:
		if d.show_lines { draw_grid_lines(g, w, d) }
	}
}

draw_grid_lines :: proc(g: ^GUI, w: ^Widget, d: Grid_Data) {
	cells := d.cells[:d.cell_count]
	columns := max(d.columns, 1)
	if len(cells) < columns { return }
	rows := len(cells) / columns

	colour := d.line_colour
	if colour.a <= 0 { colour = theme_color(g, w, "line_color") }
	if colour.a <= 0 { colour = RGBA(0.25, 0.27, 0.33, 1) }

	bottom := cells[(rows - 1) * columns].y + cells[(rows - 1) * columns].h

	for col in 0 ..< columns - 1 {
		cell := cells[col]
		draw_rect(g, Rect{x = cell.x + cell.w, y = cell.y, w = 1, h = bottom - cell.y}, colour, 0)
	}
	for row in 0 ..< rows - 1 {
		first := cells[row * columns]
		last := cells[row * columns + columns - 1]
		draw_rect(g, Rect{
			x = first.x,
			y = first.y + first.h,
			w = last.x + last.w - first.x,
			h = 1,
		}, colour, 0)
	}
}

//* == Margin ==

Margin_Data :: struct {
	margin: [4]f32,
}

Margin_Opts :: struct {
	Base_Opts: Base_Opts,
	margin:    [4]f32,
}

Make_Margin_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Margin_Opts) -> Widget_ID {
	id := New_Widget(g, .MarginContainer, parent, base_widget_opts(opts.Base_Opts))
	Widget_Get(g, id).data = Margin_Data{margin = opts.margin}
	return id
}

//* == Center ==

Center_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Center_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Center_Opts) -> Widget_ID {
	return New_Widget(g, .CenterContainer, parent, base_widget_opts(opts.Base_Opts))
}

//* == Panel ==

Panel_Container_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Panel_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Panel_Container_Opts) -> Widget_ID {
	return New_Widget(g, .PanelContainer, parent, base_widget_opts(opts.Base_Opts))
}

//* == Scroll ==

Scroll_Bar_Side :: enum {
	Right,
	Left,
	Top,
	Bottom,
	None,
}

Scroll_Data :: struct {
	offset: Vec2,
	bar:    Scroll_Bar_Side,
	bar_id: Widget_ID,
}

Scroll_Container_Opts :: struct {
	Base_Opts:  Base_Opts,
	scroll_bar: Scroll_Bar_Side,
}

SCROLL_WHEEL_STEP :: 60

Make_Scroll_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Scroll_Container_Opts) -> Widget_ID {
	kind_register(g, .ScrollContainer, scroll_container_kind())
	return make_scroll_container(g, parent, opts, .ScrollContainer)
}

Make_Scroll_Area :: proc(g: ^GUI, parent: Widget_ID, opts: Scroll_Container_Opts) -> Widget_ID {
	kind_register(g, .ScrollArea, scroll_area_kind())
	return make_scroll_container(g, parent, opts, .ScrollArea)
}

make_scroll_container :: proc(
	g: ^GUI,
	parent: Widget_ID,
	opts: Scroll_Container_Opts,
	widget_type: Widget_Type,
) -> Widget_ID {
	id := New_Widget(g, widget_type, parent, base_widget_opts(opts.Base_Opts))
	Widget_Get(g, id).data = Scroll_Data{
		offset = Vec2{},
		bar    = opts.scroll_bar,
		bar_id = INVALID_WIDGET_ID,
	}

	bar := make_scroll_bar(g, id)
	if d := scroll_data(g, id); d != nil {
		d.bar_id = bar
	}
	return id
}

scroll_container_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_scroll_container, pointer = pointer_scroll_container, theme_name = "ScrollContainer"}
}

scroll_area_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_scroll_container, pointer = pointer_scroll_container, theme_name = "ScrollArea"}
}

scroll_data :: proc(g: ^GUI, id: Widget_ID) -> ^Scroll_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Scroll_Data:
		return &d
	}
	return nil
}

scroll_bar_id :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	d := scroll_data(g, id)
	if d == nil { return INVALID_WIDGET_ID }
	return d.bar_id
}

scroll_viewport :: proc(g: ^GUI, w: ^Widget) -> Rect {
	if w == nil { return Rect{} }
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

scroll_content_size :: proc(g: ^GUI, w: ^Widget) -> Vec2 {
	if w == nil { return Vec2{} }

	size := Vec2{}
	bar := scroll_bar_id(g, w.id)
	for child := w.first_child; child != INVALID_WIDGET_ID; {
		c := Widget_Get(g, child)
		if c == nil { break }
		if child != bar {
			size.x = max(size.x, c.min_size.x)
			size.y = max(size.y, c.min_size.y)
		}
		child = c.next_sibling
	}
	return size
}

scroll_bar_sync :: proc(g: ^GUI, id: Widget_ID) {
	bar := scroll_bar_id(g, id)
	if bar == INVALID_WIDGET_ID { return }
	d := scroll_bar_data(g, bar)
	if d == nil { return }

	container := scroll_data(g, id)
	if container == nil { return }
	d.idle = 0
	d.offset = container.offset.y if d.vertical else container.offset.x
}

Scroll_Container_Set_Offset :: proc(g: ^GUI, id: Widget_ID, offset: Vec2) {
	w := Widget_Get(g, id)
	d := scroll_data(g, id)
	if w == nil || d == nil { return }

	viewport := scroll_viewport(g, w)
	content := scroll_content_size(g, w)
	d.offset.x = clamp(offset.x, 0, scroll_maximum(content.x, viewport.w))
	d.offset.y = clamp(offset.y, 0, scroll_maximum(content.y, viewport.h))
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit, .Visual})
	scroll_bar_sync(g, id)
}

Scroll_Container_Get_Offset :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	d := scroll_data(g, id)
	if d == nil { return Vec2{} }
	return d.offset
}

Scroll_Container_Set_Bar :: proc(g: ^GUI, id: Widget_ID, side: Scroll_Bar_Side) {
	d := scroll_data(g, id)
	if d == nil || d.bar == side { return }
	d.bar = side
	invalidate(g, id, Dirty_Flags{.Arrange, .Hit, .Visual})
}

draw_scroll_container :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
}

pointer_scroll_container :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel { return }
	d := scroll_data(g, id)
	if d == nil { return }

	viewport := scroll_viewport(g, w)
	content := scroll_content_size(g, w)
	next := d.offset
	step := e.amount * SCROLL_WHEEL_STEP

	if content.y > viewport.h {
		next.y -= step
	} else if content.x > viewport.w {
		next.x -= step
	} else {
		return
	}

	before := d.offset
	Scroll_Container_Set_Offset(g, id, next)
	if d.offset != before { Event_Handled(g) }
}

//* == Flow ==

Flow_Container_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Flow_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Flow_Container_Opts) -> Widget_ID {
	return New_Widget(g, .FlowContainer, parent, base_widget_opts(opts.Base_Opts))
}

//* == Aspect ratio ==

Aspect_Data :: struct {
	ratio: f32,
}

Aspect_Container_Opts :: struct {
	Base_Opts: Base_Opts,
	ratio:     f32,
}

Make_Aspect_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Aspect_Container_Opts) -> Widget_ID {
	id := New_Widget(g, .AspectRatioContainer, parent, base_widget_opts(opts.Base_Opts))
	ratio := opts.ratio
	if ratio <= 0 { ratio = 1 }
	Widget_Get(g, id).data = Aspect_Data{ratio = ratio}
	return id
}

//* == Tabs ==

Tab_Container_Data :: struct {
	active: int,
}

Tab_Container_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Tab_Container :: proc(g: ^GUI, parent: Widget_ID, opts: Tab_Container_Opts) -> Widget_ID {
	id := New_Widget(g, .TabContainer, parent, base_widget_opts(opts.Base_Opts))
	Widget_Get(g, id).data = Tab_Container_Data{active = 0}
	return id
}

tab_container_active :: proc(w: ^Widget) -> int {
	#partial switch d in w.data {
	case Tab_Container_Data:
		return d.active
	}
	return 0
}

tab_container_set_active :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Tab_Container_Data:
		d.active = index
	}
	invalidate(g, id, Dirty_Flags{.Measure, .Arrange, .Visual, .Hit})
}

//* == Tab bar ==

draw_tab_container_bar :: proc(g: ^GUI, w: ^Widget) {
	bar := Rect{x = w.rect.x, y = w.rect.y, w = w.rect.w, h = TAB_BAR_HEIGHT}
	draw_quad(g.target, bar, g.atlas.white_uv, RGBA(0.08, 0.09, 0.11, 1), g.atlas_texture)

	rects: [MAX_TABS]Rect
	n := tab_button_rects(g, w, &rects)
	active := tab_container_active(w)

	child := w.first_child
	for i in 0 ..< n {
		c := Widget_Get(g, child)
		if c == nil { break }

		r := rect_intersect(rects[i], bar)
		if r.w > 0 {
			bg := RGBA(0.13, 0.14, 0.17, 1)
			fg := RGBA(0.58, 0.61, 0.68, 1)
			if i == active {
				bg = RGBA(0.19, 0.20, 0.24, 1)
				fg = RGBA(0.93, 0.95, 0.98, 1)
			}
			draw_quad(g.target, r, g.atlas.white_uv, bg, g.atlas_texture)
			label := Rect{x = r.x + TAB_PADDING, y = r.y, w = r.w - TAB_PADDING * 2, h = r.h}
			Font_Draw(g, Font_Of(g, c), c.name, label, fg, .Left)
		}
		child = c.next_sibling
	}

	draw_quad(
		g.target,
		Rect{x = bar.x, y = bar.y + bar.h - 1, w = bar.w, h = 1},
		g.atlas.white_uv,
		RGBA(0.20, 0.22, 0.27, 1),
		g.atlas_texture,
	)
}