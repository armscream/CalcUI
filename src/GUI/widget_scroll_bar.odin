package GUI

Scroll_Bar_Data :: struct {
	vertical: bool,
	content:  f32,
	view:     f32,
	offset:   f32,
	dragging: bool,
	idle:     f32,
	alpha:    f32,
	grab:     f32,
}

SCROLL_BAR_FADE_DELAY :: 1.5
SCROLL_BAR_FADE_SPEED :: 6
SCROLL_BAR_WIDTH :: 10
SCROLL_BAR_GRABBER_MIN :: 24
SCROLL_BAR_PAGE :: 0.9

make_scroll_bar :: proc(g: ^GUI, parent: Widget_ID) -> Widget_ID {
	kind_register(g, .ScrollBar, scroll_bar_kind())
	id := New_Widget(g, .ScrollBar, parent, Widget_Opts{name = "scroll_bar"})
	w := Widget_Get(g, id)
	w.data = Scroll_Bar_Data{}
	w.focus_mode = .None
	w.z_index = 1
	w.mouse_filter = .Ignore
	return id
}

scroll_bar_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_scroll_bar,
		pointer = pointer_scroll_bar,
		update = update_scroll_bar,
		theme_name = "ScrollBar",
	}
}

scroll_bar_data :: proc(g: ^GUI, id: Widget_ID) -> ^Scroll_Bar_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Scroll_Bar_Data:
		return &d
	}
	return nil
}

scroll_bar_width :: proc(g: ^GUI) -> f32 {
	if g != nil && g.theme != nil {
		if value, has := Theme_Get_Constant(g.theme, .ScrollBar, "width"); has && value > 0 {
			return value
		}
	}
	return SCROLL_BAR_WIDTH
}

scroll_bar_grabber_min :: proc(g: ^GUI) -> f32 {
	if g != nil && g.theme != nil {
		if value, has := Theme_Get_Constant(g.theme, .ScrollBar, "grabber_min"); has && value > 0 {
			return value
		}
	}
	return SCROLL_BAR_GRABBER_MIN
}

scroll_bar_hovered :: proc(g: ^GUI, w: ^Widget) -> bool {
	if g == nil || w == nil {return false}
	if !g.pointer_known {return false}
	return rect_contains(w.rect, g.pointer.x, g.pointer.y)
}

scroll_bar_grabber :: proc(g: ^GUI, w: ^Widget, d: ^Scroll_Bar_Data) -> Rect {
	if d == nil {return Rect{}}
	track := w.rect
	if d.content <= 0 || d.view <= 0 {return Rect{}}
	size := d.view * d.view / d.content
	minimum := scroll_bar_grabber_min(g)
	if size < minimum {size = minimum}
	length := d.vertical ? track.h : track.w
	if size > length {size = length}
	free := length - size
	space := d.content - d.view
	pos := f32(0)
	if free > 0 && space > 0 {
		pos = clamp(d.offset / space, 0, 1) * free
	}
	if d.vertical {
		return Rect{x = track.x, y = track.y + pos, w = track.w, h = size}
	}
	return Rect{x = track.x + pos, y = track.y, w = size, h = track.h}
}

scroll_bar_set_offset :: proc(g: ^GUI, id: Widget_ID, offset: f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	d := scroll_bar_data(g, id)
	if d == nil {return}
	container := Widget_Get(g, w.parent)
	if container == nil {return}
	current := Scroll_Container_Get_Offset(g, container.id)
	next := current
	if d.vertical {
		next.y = offset
	} else {
		next.x = offset
	}
	Scroll_Container_Set_Offset(g, container.id, next)
}

scroll_bar_drag :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	d: ^Scroll_Bar_Data,
	e: Pointer_Event,
) {
	track := w.rect
	grab := scroll_bar_grabber(g, w, d)
	free := (d.vertical ? track.h : track.w) - (d.vertical ? grab.h : grab.w)
	space := d.content - d.view
	if free <= 0 || space <= 0 {return}
	pos := (d.vertical ? e.pos.y : e.pos.x) - d.grab - (d.vertical ? track.y : track.x)
	pos = clamp(pos, 0, free)
	scroll_bar_set_offset(g, id, pos / free * space)
}

pointer_scroll_bar :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	d := scroll_bar_data(g, id)
	if d == nil {return}
	container := Widget_Get(g, w.parent)
	if container == nil {return}
	current := Scroll_Container_Get_Offset(g, container.id)
	offset := d.vertical ? current.y : current.x
	d.offset = offset
	#partial switch e.kind {
	case .Down:
		if e.button != .Left {return}
		grab := scroll_bar_grabber(g, w, d)
		if rect_contains(grab, e.pos.x, e.pos.y) {
			d.dragging = true
			d.grab = d.vertical ? e.pos.y - grab.y : e.pos.x - grab.x
			invalidate(g, id, Dirty_Flags{.Visual})
			return
		}
		page := d.view * SCROLL_BAR_PAGE
		if d.vertical {
			if e.pos.y < grab.y {offset -= page} else {offset += page}
		} else {
			if e.pos.x < grab.x {offset -= page} else {offset += page}
		}
		scroll_bar_set_offset(g, id, offset)
	case .Move:
		if !d.dragging {return}
		scroll_bar_drag(g, id, w, d, e)
	case .Up:
		if !d.dragging {return}
		d.dragging = false
		invalidate(g, id, Dirty_Flags{.Visual})
	case .Wheel:
	}
}

update_scroll_bar :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	d := scroll_bar_data(g, id)
	if d == nil {return}
	if d.dragging || scroll_bar_hovered(g, w) {
		d.idle = 0
	}
	d.idle += dt
	if d.idle < SCROLL_BAR_FADE_DELAY {
		d.alpha = min(1, d.alpha + dt * SCROLL_BAR_FADE_SPEED)
	} else {
		d.alpha = max(0, d.alpha - dt * SCROLL_BAR_FADE_SPEED)
	}
}

draw_scroll_bar :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := scroll_bar_data(g, id)
	if d == nil {return}
	if d.alpha <= 0 {return}

	track_box, has := Theme_Get_Stylebox(g.theme, .ScrollBar, "track")
	if !has {track_box = StyleBox{bg_color = RGBA(0.13, 0.14, 0.17, 1)}}
	draw_rect(
		g,
		w.rect,
		Scale_Colour(track_box.bg_color, d.alpha),
		stylebox_radius(&track_box),
	)

	grab := scroll_bar_grabber(g, w, d)
	if grab.w <= 0 || grab.h <= 0 {return}
	name := "grabber"
	if d.dragging {
		name = "grabber_pressed"
	} else if scroll_bar_hovered(g, w) {
		name = "grabber_hover"
	}
	box, found := Theme_Get_Stylebox(g.theme, .ScrollBar, name)
	if !found {box = StyleBox{bg_color = RGBA(0.55, 0.58, 0.66, 1)}}
	draw_rect(g, grab, Scale_Colour(box.bg_color, d.alpha), stylebox_radius(&box))
}