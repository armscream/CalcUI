package GUI

Panel_Opts :: struct {
	Base_Opts: Base_Opts,
}

//* Makes a panel: the plain box that holds other widgets.
Make_Panel :: proc(g: ^GUI, parent: Widget_ID, opts: Panel_Opts) -> Widget_ID {
	return New_Widget(g, .Panel, parent, base_widget_opts(opts.Base_Opts))
}

Button_Align :: enum {
	Theme,
	Left,
	Center,
	Right,
}

Button_Opts :: struct {
	Base_Opts:  Base_Opts,
	text:       string,
	on_pressed: proc(g: ^GUI, id: Widget_ID),
	text_align: Button_Align,
}

Make_Button :: proc(g: ^GUI, parent: Widget_ID, opts: Button_Opts) -> Widget_ID {
	widget_opts := base_widget_opts(opts.Base_Opts)
	widget_opts.text = opts.text
	widget_opts.on_click = opts.on_pressed
	id := New_Widget(g, .Button, parent, widget_opts)
	if opts.text_align != .Theme {
		w := Widget_Get(g, id)
		if w != nil {
			align := button_align_of(opts.text_align)
			fields := text_fields_of(&w.style.text)
			fields += {.Align}
			w.style.text.set = fields
			w.style.text.align = align
		}
	}
	return id
}

button_align_of :: proc(align: Button_Align) -> Text_Align {
	switch align {
	case .Left:
		return .Left
	case .Center:
		return .Center
	case .Right:
		return .Right
	case .Theme:
		return .Left
	}
	return .Left
}

button_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_button,
		style = Style{text = Text_Style{align = .Center, valign = .Center}},
		theme_name = "Button",
	}
}

//* The kind of the button is registered when a button is made, so that
//* a button made with `New_Widget` has it as well.
button_kind_register :: proc(g: ^GUI) {
	if g == nil {return}
	kind_register(g, .Button, button_kind())
}

draw_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Button_Data:
		draw_text(g, resolved_style(g, w).text, d.text, content, resolved_text_colour(g, id, w))
	}
}

Label_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

//* Makes a label: a piece of text that cannot be edited.
Make_Label :: proc(g: ^GUI, parent: Widget_ID, opts: Label_Opts) -> Widget_ID {
	widget_opts := base_widget_opts(opts.Base_Opts)
	widget_opts.text = opts.text
	return New_Widget(g, .Label, parent, widget_opts)
}
Box_Opts :: struct {
	Base_Opts: Base_Opts,
}

//* Makes a box that stacks its children from the top to the bottom.
Make_VBox :: proc(g: ^GUI, parent: Widget_ID, opts: Box_Opts) -> Widget_ID {
	return New_Widget(g, .VBox, parent, base_widget_opts(opts.Base_Opts))
}

//* Makes a box that stacks its children from the left to the right.
Make_HBox :: proc(g: ^GUI, parent: Widget_ID, opts: Box_Opts) -> Widget_ID {
	return New_Widget(g, .HBox, parent, base_widget_opts(opts.Base_Opts))
}

Split_Opts :: struct {
	Base_Opts: Base_Opts,
	direction: Split_Direction,
}

//* Makes a split: it divides its space among its children, and the
//* edges between them can be pulled.
Make_Split :: proc(g: ^GUI, parent: Widget_ID, opts: Split_Opts) -> Widget_ID {
	widget_opts := base_widget_opts(opts.Base_Opts)
	widget_opts.split = opts.direction
	return New_Widget(g, .Split, parent, widget_opts)
}

Tabs_Opts :: struct {
	Base_Opts: Base_Opts,
}

//* Makes a tab host. Its children are its tabs, and one of them is showing at a time.
Make_Tabs :: proc(g: ^GUI, parent: Widget_ID, opts: Tabs_Opts) -> Widget_ID {
	return New_Widget(g, .Tabs, parent, base_widget_opts(opts.Base_Opts))
}
