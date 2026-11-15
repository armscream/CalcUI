package Core
Pointer_Event_Kind :: enum {
	Down,
	Up,
	Move,
	Wheel,
}

Pointer_Event :: struct {
	kind:    Pointer_Event_Kind,
	pos:     Vec2, //pointer event pos
	local:   Vec2, //local widget pointer pos
	global:  Vec2, //screen pointer pos	
	button:  Mouse_Button,
	clicks:  int,
	amount:  f32, // wheel scroll amount.
}

// hooks are optional and will default to base functionality if not defined.
Widget_Kind :: struct {
	//* Draws the content of the widget, in the space of the content: the
	//* rect of the widget without the margin of its style. The core draws
	//* the children of the widget after it, unless the hook draws them
	//* itself.
	draw: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect),
	//* Places every child of the widget. A kind without a hook lets the
	//* core place the children by their anchors.
	layout: proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect),
	//* The click happens when the button comes up over the pressed widget.
	click: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	key: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event),
	//* Runs before the layout pass of the frame. A change made here is
	//* measured and arranged in the same frame. Use it for state,
	//* animation and data changes.
	update: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
	//* Runs after the layout pass and before the draw pass. The geometry
	//* of the frame is current, so interaction code that reads rectangles
	//* or the pointer belongs here. A change that affects layout is seen
	//* by the next frame.
	post_update: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
	// specify a minimum size for the widget.
	measure: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2,
	//* The size the widget wants when it is given a width on the outside.
	//* Use it for a widget whose height depends on its width: wrapped
	//* text, a wrapping panel, a custom chart. The core measures a
	//* widget without this hook at its intrinsic size only.
	measure_width: proc(g: ^GUI, id: Widget_ID, w: ^Widget, width: f32) -> Vec2,
	//* The logical size of the content of the widget. A virtualized
	//* widget holds items of its own rather than a widget per item, so
	//* its measured size says nothing about how much there is to scroll.
	//* A scroll container asks for this size and uses the larger of it
	//* and the sizes of the children it holds. Return a zero vector when
	//* the widget has no content size of its own.
	content_size: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2,
	construct: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	destroy: proc(g: ^GUI, id: Widget_ID, w: ^Widget),
	//* Pointer event callbacks.
	pointer: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event),
	//* What the widget does with the typed text. 
	text_input: proc(g: ^GUI, id: Widget_ID, w: ^Widget, text: string),
	//* Whether the widget uses the arrow keys itself, so that they do not
	//* move the focus away from it.
	uses_arrow_keys: bool,
	//* Whether the draw hook draws the children of the widget itself: the
	//* core does not draw them a second time.
	owns_children: bool,
	//* The style the widget gets when the theme has nothing for it.
	style: Style,
	theme_name: string,
	//* The role of the widget: accessability information.
	access_role: Access_Role,
	//* change the metadata of the widget.
	access: proc(g: ^GUI, id: Widget_ID, w: ^Widget, info: ^Access_Info),
}

//* The hooks of a kind are the hooks of a class as well, so a program that
//* wants to change what a kind does can register a class with the same name.
kind_register :: proc(g: ^GUI, widget_type: Widget_Type, kind: Widget_Kind) {
	if g == nil { return }
	index := int(widget_type)
	for len(g.kinds) <= index {
		append(&g.kinds, Widget_Kind{})
	}
	if g.kinds[index].draw != nil { return }
	g.kinds[index] = kind
	//* The widgets of that kind belong to the class of that kind, so that a
	//* class can be found by the name of the kind as well.
	class_register_type(g, widget_type, kind)
}

//* The hooks of a kind of widget, if it has any.
kind_of :: proc(g: ^GUI, widget_type: Widget_Type) -> Widget_Kind {
	if g == nil { return {} }
	index := int(widget_type)
	if index >= len(g.kinds) { return {} }
	return g.kinds[index]
}

kind_style :: proc(g: ^GUI, w: ^Widget) -> Style {
	kind := kind_of(g, w.type)
	return kind.style
}
