//* == The invalidation ==
//* Everything in the toolkit that changes a widget says what it made
//* stale. The flags say what has to be done again before the next frame
//* is drawn, so that a change which only touches the look of a widget
//* does not make the whole tree be measured and laid out again.
//
//* There are five kinds of staleness:
//
//* | Kind | What it means |
//* |---|---|
//* | `Measure` | The measured size of the widget is out of date. |
//* | `Arrange` | The place of the widget in its parent is out of date. |
//* | `Visual` | The look of the widget is out of date. |
//* | `Hit` | The hit test of the widget is out of date. |
//* | `Theme` | The widget takes its look from the theme, and the theme changed. |
//
//* A widget carries two sets of flags: the flags of the widget itself
//* and the flags of the whole branch under it. The branch under a
//* widget is what the measure pass and the layout pass walk, so they
//* can leave a branch alone that nothing happened to.

package GUI

//* What a change to a widget can make stale.
Dirty_Kind :: enum {
	//* The measured size of the widget is out of date: the text of the
	//* widget, the typeface, the padding of its style or the size the
	//* program asked for changed.
	Measure,
	//* The place of the widget in its parent is out of date: its
	//* anchors, its offsets, its weight or the space of its parent
	//* changed.
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

//* The kinds of staleness, as a set of flags.
Dirty_Flags :: bit_set[Dirty_Kind]

//* Every kind of staleness there is.
DIRTY_ALL :: Dirty_Flags{.Measure, .Arrange, .Visual, .Hit, .Theme}

//* The flags that come with a measurement: a size that changed moves
//* the widget, and a widget that moved is hit in another place.
DIRTY_FROM_MEASURE :: Dirty_Flags{.Measure, .Arrange, .Hit}

//* The flags that come with a place: a widget that moved is hit in
//* another place.
DIRTY_FROM_ARRANGE :: Dirty_Flags{.Arrange, .Hit}

//* == Marking a widget as out of date ==

//* Marks a widget as out of date. The flags say what is stale about
//* it. The ancestors are marked as well: a parent lays its children
//* out, and a child that changed changes the place of its brothers.
invalidate :: proc(g: ^GUI, id: Widget_ID, flags: Dirty_Flags) {
	if g == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	invalidate_widget(g, w, flags)
}

//* Marks a widget as out of date.
invalidate_widget :: proc(g: ^GUI, w: ^Widget, flags: Dirty_Flags) {
	if g == nil || w == nil {return}
	if flags == (Dirty_Flags{}) {return}

	//* A measured size that changed moves the widget, and a widget
	//* that moved is hit in another place.
	all := dirty_with(flags)

	g.dirty += all
	w.dirty += all
	w.subtree_dirty += all
	propagate_up(g, w, all)
}

//* Marks a widget and everything under it as out of date.
invalidate_subtree :: proc(g: ^GUI, id: Widget_ID, flags: Dirty_Flags) {
	if g == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	all := dirty_with(flags)
	mark_subtree(g, w, all)
	propagate_up(g, w, all)
}

//* The flags with the ones that come with them. A measured size that
//* changed moves the widget, and a widget that moved is hit in another
//* place.
dirty_with :: proc(flags: Dirty_Flags) -> Dirty_Flags {
	all := flags
	if .Measure in all {all += DIRTY_FROM_MEASURE}
	if .Arrange in all {all += DIRTY_FROM_ARRANGE}
	return all
}

//* Marks a widget and everything under it as out of date.
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

//* Marks the ancestors of a widget as out of date. A parent lays its
//* children out, so a child that changed changes the place of the
//* others. The flags of the parent itself are not touched: the size of
//* the parent does not depend on the size of its children.
propagate_up :: proc(g: ^GUI, w: ^Widget, flags: Dirty_Flags) {
	if w == nil {return}
	parent := w.parent
	for parent != INVALID_WIDGET_ID {
		p := Widget_Get(g, parent)
		if p == nil {break}
		p.subtree_dirty += flags
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
}

//* Marks the whole tree as out of date, and asks for the layout to be
//* done from the top. The measure pass and the layout pass then walk
//* every widget, whatever the flags say.
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
	for w in g.widgets {
		if w == nil {continue}
		//* A widget that does not take the theme is not touched by it.
		if !w.use_theme {continue}
		invalidate_widget(g, w, flags)
	}
}

//* == Asking about the staleness ==

//* True when the widget itself is out of date in one of these ways.
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
