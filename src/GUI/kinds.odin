//* == The kinds of the widgets ==
//* What a kind of widget does: how it is drawn, how it lays its
//* children out, what it does when it is clicked and what it does with
//* a key.
//
//* The widgets that were there from the beginning are in the switches
//* of the draw pass, the layout pass and the input. A widget that came
//* later puts its hooks in here instead, so that it does not have to
//* change a file that belongs to everybody.

package GUI

//* The hooks of a kind of widget.
Widget_Kind :: struct {
	//* How the widget is drawn. The rect is the space of the content:
	//* the rect of the widget without the margin of its style.
	draw: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect),
	//* How the widget lays its children out. A widget that has no
	//* children does not need one.
	layout: proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect),
	//* What the widget does when it is clicked.
	click: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	//* What the widget does with a key. The widget has the keyboard
	//* focus when the key arrives.
	key: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event),
	//* What the widget does every frame: a toast that counts down, a
	//* sound that plays, a graph that follows the pointer.
	update: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
	//* The style the widget gets when the theme has nothing for it.
	style: Style,
	//* The name of the widget in the theme.
	theme_name: string,
}

//* Puts the hooks of a kind of widget in the table. It may be called
//* as often as it is wanted: the entry is only filled once.
kind_register :: proc(g: ^GUI, widget_type: Widget_Type, kind: Widget_Kind) {
	if g == nil { return }
	index := int(widget_type)
	for len(g.kinds) <= index {
		append(&g.kinds, Widget_Kind{})
	}
	if g.kinds[index].draw != nil { return }
	g.kinds[index] = kind
}

//* The hooks of a kind of widget, if it has any.
kind_of :: proc(g: ^GUI, widget_type: Widget_Type) -> Widget_Kind {
	if g == nil { return {} }
	index := int(widget_type)
	if index >= len(g.kinds) { return {} }
	return g.kinds[index]
}

//* The style of a kind of widget: the one the theme gives it, or the
//* one that is the default of the kind.
kind_style :: proc(g: ^GUI, w: ^Widget) -> Style {
	kind := kind_of(g, w.type)
	return kind.style
}
