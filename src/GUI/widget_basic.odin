//* The widgets CalcUI started with: the panel, the button, the label and
//* the text field.

package GUI

//* == The widgets CalcUI started with ==
//* They have been there from the beginning, and each one is made straight
//* with `New_Widget`.

//* == The panel ==

Panel_Opts :: struct {
	Base_Opts: Base_Opts,
}

//* Makes a panel: the plain box that holds other widgets.
Make_Panel :: proc(g: ^GUI, parent: Widget_ID, opts: Panel_Opts) -> Widget_ID {
	return New_Widget(g, .Panel, parent, base_widget_opts(opts.Base_Opts))
}

//* == The button ==

Button_Opts :: struct {
	Base_Opts:  Base_Opts,
	text:       string,
	on_pressed: proc(g: ^GUI, id: Widget_ID),
}

//* Makes a button. It says so when it is pressed.
Make_Button :: proc(g: ^GUI, parent: Widget_ID, opts: Button_Opts) -> Widget_ID {
	widget_opts := base_widget_opts(opts.Base_Opts)
	widget_opts.text = opts.text
	widget_opts.on_click = opts.on_pressed
	return New_Widget(g, .Button, parent, widget_opts)
}

//* == The label ==

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

//* == The text field ==

Text_Input_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

//* Makes a text field. The text can be edited while the program runs.
Make_Text_Input :: proc(g: ^GUI, parent: Widget_ID, opts: Text_Input_Opts) -> Widget_ID {
	widget_opts := base_widget_opts(opts.Base_Opts)
	widget_opts.text = opts.text
	return New_Widget(g, .TextInput, parent, widget_opts)
}

//* == The boxes ==

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

//* == The split ==

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

//* == The tabs ==

Tabs_Opts :: struct {
	Base_Opts: Base_Opts,
}

//* Makes a tab host. Its children are its tabs, and one of them is
//* showing at a time.
Make_Tabs :: proc(g: ^GUI, parent: Widget_ID, opts: Tabs_Opts) -> Widget_ID {
	return New_Widget(g, .Tabs, parent, base_widget_opts(opts.Base_Opts))
}
