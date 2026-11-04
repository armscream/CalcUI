//* == The kinds of the widgets ==
//* What a kind of widget does: how it is drawn, how it lays its
//* children out, what it does when it is clicked and what it does with
//* a key.
//
//* The widgets that were there from the beginning are in the switches
//* of the draw pass, the layout pass and the input. A widget that came
//* later puts its hooks in a class (see class.odin), so that it does
//* not have to change a file that belongs to everybody. A program that
//* brings a widget of its own does the same: the hooks of its class
//* are the only thing that has to change.

package GUI

//* What the pointer did.
Pointer_Event_Kind :: enum {
	//* The button went down on the widget.
	Down,
	//* The button came up over the widget.
	Up,
	//* The pointer moved over the widget.
	Move,
	//* The wheel turned over the widget.
	Wheel,
}

//* What the pointer did to a widget. The place of the pointer is given
//* twice: once in the window of the GUI and once in the widget itself,
//* so that a widget does not have to work out where the pointer is in
//* it.
Pointer_Event :: struct {
	kind:    Pointer_Event_Kind,
	//* Where the pointer is in the window of the GUI.
	pos:     Vec2,
	//* Where the pointer is in the widget itself.
	local:   Vec2,
	//* Where the pointer is on the screen.
	global:  Vec2,
	//* The button that went down or came up.
	button:  Mouse_Button,
	//* How many clicks there were: 1 for one click, 2 for a double one.
	clicks:  int,
	//* How far the wheel turned.
	amount:  f32,
}

//* The hooks of a kind of widget.
//
//* Every hook is optional: a hook that is nil is not called, and the
//* widget falls back on what the core does for a plain control. The
//* hooks are the whole of the contract between a widget and the core:
//* a widget that puts them in a class works like one of the built-in
//* ones, and the core does not have to know anything about it.
Widget_Kind :: struct {
	//* How the widget is drawn. The rect is the space of the content:
	//* the rect of the widget without the margin of its style.
	//
	//* The hook draws the content of the widget. The core draws the
	//* children of the widget after it, unless the kind says that the
	//* hook draws them itself.
	draw: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect),
	//* How the widget lays its children out. A widget that has no
	//* children does not need one.
	//
	//* The hook owns the children of the widget: it places every one
	//* of them. A kind without a hook lets the core place the children
	//* by their anchors.
	layout: proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect),
	//* What the widget does when it is clicked. The click happens when
	//* the button comes up over the widget that was pressed.
	click: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	//* What the widget does with a key. The widget has the keyboard
	//* focus when the key arrives.
	key: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event),
	//* What the widget does every frame: a toast that counts down, a
	//* sound that plays, a graph that follows the pointer.
	update: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
	//* The smallest size the widget asks for. The core works out the
	//* size of the text of the widget on its own; a kind that has
	//* something of its own to say says it here. The size that is asked
	//* for here is never smaller than the size the program asked for.
	measure: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2,
	//* The widget is made. The hook puts the widget in the state it
	//* starts in, and it puts the data of the program in it.
	construct: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	//* The widget is destroyed. The hook gives back what the program
	//* put in the widget. It is called before the data of the widget
	//* is given back.
	destroy: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	//* What the widget does with the pointer: it goes down on it, it
	//* comes up over it, it moves over it or the wheel turns over it.
	pointer: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event),
	//* What the widget does with the text that was typed. The widget
	//* has the keyboard focus when the text arrives.
	text_input: proc(g: ^GUI, id: Widget_ID, w: ^Widget, text: string),
	//* Whether the widget uses the arrow keys itself, so that they do
	//* not move the focus away from it.
	uses_arrow_keys: bool,
	//* Whether the draw hook draws the children of the widget itself.
	//* A widget that draws a list of its own, or the sections of an
	//* accordion, says so here: the core does not draw them a second
	//* time.
	owns_children: bool,
	//* The style the widget gets when the theme has nothing for it.
	style: Style,
	//* The name of the widget in the theme, when the class has no name
	//* of its own.
	theme_name: string,
}

//* Puts the hooks of a kind of widget in the table. It may be called
//* as often as it is wanted: the entry is only filled once.
//
//* The hooks of a kind are the hooks of a class as well: the widgets of
//* that kind belong to the class, so a program that wants to change
//* what a kind does can register a class with the same name.
kind_register :: proc(g: ^GUI, widget_type: Widget_Type, kind: Widget_Kind) {
	if g == nil { return }
	index := int(widget_type)
	for len(g.kinds) <= index {
		append(&g.kinds, Widget_Kind{})
	}
	if g.kinds[index].draw != nil { return }
	g.kinds[index] = kind
	//* The widgets of that kind belong to the class of that kind, so
	//* that a class can be found by the name of the kind as well.
	class_register_type(g, widget_type, kind)
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
