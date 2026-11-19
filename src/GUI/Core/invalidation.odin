package Core
//* A widget carries two sets of flags: the flags of the widget itself
	//* and the flags of the whole branch under it. The branch is what the
	//* measure pass and the layout pass walk, so they can leave a branch
	//* alone that nothing happened to.

Dirty_Kind :: enum {
	//* The measured size of the widget is out of date: its text, its
	//* typeface, the padding of its style or the size asked for changed.
	Measure,
	//* The place of the widget in its parent is out of date: its
	//* anchors, its offsets, its weight or the space of its parent.
	Arrange,
	//* The look of the widget is out of date: its style, its colour or
	//* the text it shows changed. The size of the widget does not.
	Visual,
	//* The hit test of the widget is out of date: it moved, it came or
	//* went, or it changed what it does with the mouse.
	Hit,
	//* The widget takes its look from the theme, and the theme changed.
	Theme,
}

Dirty_Flags :: bit_set[Dirty_Kind]

DIRTY_ALL :: Dirty_Flags{.Measure, .Arrange, .Visual, .Hit, .Theme}

//* The flags that come with a measurement: a size that changed moves
//* the widget, and a widget that moved is hit in another place.
DIRTY_FROM_MEASURE :: Dirty_Flags{.Measure, .Arrange, .Hit}

//* The flags that come with a place: a widget that moved is hit in
//* another place.
DIRTY_FROM_ARRANGE :: Dirty_Flags{.Arrange, .Hit}

draw_invalidate :: proc(g: ^GUI) {
	if g == nil {return}
	g.draw_epoch += 1
	g.draw_valid = false
	partial_clear(g)
	g.partial_blocked = true
}

draw_invalidate_visual :: proc(g: ^GUI) {
	if g == nil {return}
	g.draw_epoch += 1
	g.draw_valid = false
}

partial_clear :: proc(g: ^GUI) {
	if g == nil {return}
	g.dirty_rect = {}
	g.dirty_rect_valid = false
}

//* The padding a widget's pixels can reach beyond its own bounds: the shadow it casts and the backdrop a glass surface reads.
partial_padding :: proc(g: ^GUI, w: ^Widget) -> f32 {
	if g == nil || w == nil {return 0}
	style := resolved_style(g, w)
	if style == nil {style = &w.style}
	box := style.box
	pad := f32(0)
	if box.shadow_color.a > 0 {
		offset := max(abs(box.shadow_offset.x), abs(box.shadow_offset.y))
		pad = max(pad, max(box.shadow_size, 0) + abs(box.shadow_spread) + offset)
	}
	if box.backdrop_blur > 0 {
		pad = max(pad, box.backdrop_blur)
	}
	return pad
}

//* Adds a widget's arranged bounds to the dirty rectangle, in physical pixels, padded by what the widget draws outside them.
partial_add :: proc(g: ^GUI, w: ^Widget) {
	if g == nil || w == nil {return}
	r := w.rect
	if r.w <= 0 || r.h <= 0 {return}
	pad := partial_padding(g, w)
	scale := g.scale
	if !(scale > 0) {scale = 1}
	r = Rect {
		x = (r.x - pad) * scale,
		y = (r.y - pad) * scale,
		w = (r.w + pad * 2) * scale,
		h = (r.h + pad * 2) * scale,
	}
	if !g.dirty_rect_valid {
		g.dirty_rect = r
		g.dirty_rect_valid = true
		return
	}
	old := g.dirty_rect
	x0 := min(old.x, r.x)
	y0 := min(old.y, r.y)
	x1 := max(old.x + old.w, r.x + r.w)
	y1 := max(old.y + old.h, r.y + r.h)
	g.dirty_rect = Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
}

	//* it. The ancestors are marked as well: a parent lays its children
	//* out, and a child that changed changes the place of its brothers.
invalidate :: proc(g: ^GUI, id: Widget_ID, flags: Dirty_Flags) {
	if g == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	invalidate_widget(g, w, flags)
}

invalidate_widget :: proc(g: ^GUI, w: ^Widget, flags: Dirty_Flags) {
	if g == nil || w == nil {return}
	if flags == (Dirty_Flags{}) {return}

	all := dirty_with(flags)

	g.dirty += all
	w.dirty += all
	w.subtree_dirty += all
	propagate_up(g, w, all)

	if .Visual in flags {
		access_mark(g, w.id)
	}
	visual_only := flags == Dirty_Flags{.Visual}
	if visual_only {
		draw_invalidate_visual(g)
		partial_add(g, w)
	} else {
		draw_invalidate(g)
	}
}

invalidate_subtree :: proc(g: ^GUI, id: Widget_ID, flags: Dirty_Flags) {
	if g == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	all := dirty_with(flags)
	mark_subtree(g, w, all)
	propagate_up(g, w, all)
	draw_invalidate(g)
}

//* The flags with the ones that come with them: a measured size that
	//* changed moves the widget, and a widget that moved is hit in
	//* another place.
dirty_with :: proc(flags: Dirty_Flags) -> Dirty_Flags {
	all := flags
	if .Measure in all {all += DIRTY_FROM_MEASURE}
	if .Arrange in all {all += DIRTY_FROM_ARRANGE}
	return all
}

mark_subtree :: proc(g: ^GUI, w: ^Widget, flags: Dirty_Flags) {
	if w == nil {return}
	w.dirty += flags
	w.subtree_dirty += flags
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		mark_subtree(g, c, flags)
		child = c.next_sibling
	}
}

propagate_up :: proc(g: ^GUI, w: ^Widget, flags: Dirty_Flags) {
	if w == nil {return}
	parent := w.parent
	for parent != INVALID_WIDGET_ID {
		p := Widget_Get(g, parent)
		if p == nil {break}
		p.subtree_dirty += flags
		//* A scroll measures its content from its children, so a child
		//* that is measured again can change the size there is to
		//* scroll. The kept content size is dropped; the next query or
		//* layout pass measures it from the current sizes.
		if .Measure in flags {
			#partial switch p.type {
			case .ScrollContainer, .ScrollArea:
				if d := scroll_data(g, p.id); d != nil {
					d.content_ready = false
				}
			}
		}
		parent = p.parent
	}
}

//* Marks the whole tree as out of date. This is the way out for a
	//* program that writes to a widget itself, without the setters: it
	//* asks for the tree to be measured and laid out again from the top.
invalidate_all :: proc(g: ^GUI, flags: Dirty_Flags) {
	if g == nil {return}
	all := dirty_with(flags)
	g.dirty += all
	for w in g.widgets {
		if w == nil {continue}
		w.dirty += all
		w.subtree_dirty += all
	}
	draw_invalidate(g)
}

//* Marks the whole tree as out of date, and asks for the layout to be
	//* done from the top, whatever the flags say.
invalidate_full :: proc(g: ^GUI) {
	if g == nil {return}
	invalidate_all(g, DIRTY_ALL)
	g.full_layout = true
}

//* Marks the widgets that take their look from the theme as out of
//* date. A theme can change the typeface and the size of the text of a
//* widget, so the size of the widget has to be measured again as well.
invalidate_theme :: proc(g: ^GUI) {
	if g == nil {return}
	flags := Dirty_Flags{.Measure, .Visual, .Theme}
	g.dirty += flags
	draw_invalidate(g)
	for w in g.widgets {
		if w == nil {continue}

		if !w.use_theme {continue}
		invalidate_widget(g, w, flags)
	}
}

Widget_Is_Dirty :: proc(g: ^GUI, id: Widget_ID, kind: Dirty_Kind) -> bool {
	if g == nil {return false}
	w := Widget_Get(g, id)
	if w == nil {return false}
	return kind in w.dirty
}

//* True when the widget, or anything under it, is out of date in one
//* of these ways.
Widget_Subtree_Is_Dirty :: proc(g: ^GUI, id: Widget_ID, kind: Dirty_Kind) -> bool {
	if g == nil {return false}
	w := Widget_Get(g, id)
	if w == nil {return false}
	return kind in w.subtree_dirty
}

//* True when the GUI has something out of date in one of these ways.
GUI_Is_Dirty :: proc(g: ^GUI, kind: Dirty_Kind) -> bool {
	if g == nil {return false}
	return kind in g.dirty
}
