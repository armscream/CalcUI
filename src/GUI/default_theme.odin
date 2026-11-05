//* The look of the GUI when the program wants one: a dark theme and a
//* light theme, with a style for every kind of widget.
//* The GUI ships no theme of its own; the widgets have no look until
//* one of these is put on them.
package GUI

//* == The default theme ==
//*   theme := GUI.default_theme_dark()
//*   GUI.GUI_Set_Theme(g, theme)
//
//* or, in one line:
//
//*   GUI.default_theme_use(g, true)
//
//* A widget takes the theme when it is made with `use_theme = true`, or
//* when `default_theme_use` is called after the tree is built.

//* The colours of a theme. A program that wants a colour that goes with
//* the theme asks for the palette.
Theme_Palette :: struct {
	//* The background of the window.
	window: Colour,
	//* The background of a panel.
	surface: Colour,
	//* The background of a field: a text field, a list, a tree.
	field: Colour,
	button: Colour,
	hover: Colour,
	pressed: Colour,
	disabled: Colour,
	//* The line around a panel.
	border: Colour,
	//* The ink of the text.
	text: Colour,
	//* The ink of the text that is not important.
	text_dim: Colour,
	//* The colour of the focus and of the selection.
	accent: Colour,
	//* The ink on the accent.
	accent_text: Colour,
}

//* The colours of the dark theme.
default_theme_palette_dark :: proc() -> Theme_Palette {
	return Theme_Palette{
		window      = RGBA(0.07, 0.08, 0.10, 1),
		surface     = RGBA(0.11, 0.12, 0.15, 1),
		field       = RGBA(0.15, 0.16, 0.20, 1),
		button      = RGBA(0.19, 0.21, 0.26, 1),
		hover       = RGBA(0.25, 0.27, 0.33, 1),
		pressed     = RGBA(0.13, 0.14, 0.18, 1),
		disabled    = RGBA(0.12, 0.13, 0.16, 1),
		border      = RGBA(0.24, 0.26, 0.31, 1),
		text        = RGBA(0.88, 0.90, 0.94, 1),
		text_dim    = RGBA(0.58, 0.61, 0.68, 1),
		accent      = RGBA(0.29, 0.58, 0.96, 1),
		accent_text = RGBA(1, 1, 1, 1),
	}
}

//* The colours of the light theme.
default_theme_palette_light :: proc() -> Theme_Palette {
	return Theme_Palette{
		window      = RGBA(0.93, 0.94, 0.95, 1),
		surface     = RGBA(0.99, 0.99, 1.00, 1),
		field       = RGBA(1.00, 1.00, 1.00, 1),
		button      = RGBA(0.91, 0.92, 0.94, 1),
		hover       = RGBA(0.85, 0.87, 0.90, 1),
		pressed     = RGBA(0.78, 0.80, 0.84, 1),
		disabled    = RGBA(0.95, 0.95, 0.96, 1),
		border      = RGBA(0.78, 0.79, 0.83, 1),
		text        = RGBA(0.13, 0.14, 0.16, 1),
		text_dim    = RGBA(0.42, 0.44, 0.48, 1),
		accent      = RGBA(0.16, 0.45, 0.85, 1),
		accent_text = RGBA(1, 1, 1, 1),
	}
}

//* The colours of a theme: the dark ones or the light ones.
default_theme_palette :: proc(dark: bool) -> Theme_Palette {
	if dark { return default_theme_palette_dark() }
	return default_theme_palette_light()
}

//* A box with a background, a border and rounded corners.
default_theme_box :: proc(bg, border: Colour, width, radius: f32) -> StyleBox {
	return StyleBox{
		bg_color      = bg,
		border_color  = {border, border, border, border},
		border_width  = {width, width, width, width},
		corner_radius = {radius, radius, radius, radius},
		anti_aliasing = radius > 0,
	}
}

//* The box of a widget, with the space kept free around its content.
default_theme_padded :: proc(bg, border: Colour, width, radius, pad_x, pad_y: f32) -> StyleBox {
	box := default_theme_box(bg, border, width, radius)
	box.content_margin = {pad_x, pad_y, pad_x, pad_y}
	return box
}

//* The theme of the GUI, in the dark.
default_theme_dark :: proc() -> ^Theme {
	return default_theme_make(true)
}

//* The theme of the GUI, in the light.
default_theme_light :: proc() -> ^Theme {
	return default_theme_make(false)
}

//* Puts the default theme on the GUI. The widgets that are already in the
//* tree take the theme; the ones that come later take it when they are
//* made with `use_theme = true`, or when the program calls
//* `default_theme_apply` again.
default_theme_use :: proc(g: ^GUI, dark: bool) {
	theme := default_theme_make(dark)
	GUI_Set_Theme(g, theme)

	p := default_theme_palette(dark)
	//* The look of a widget that does not take the theme.
	GUI_Set_Default_Style(g, Style{text = Text_Style{colour = p.text}})
	//* The root of the tree is the window: it has the background of the
	//* window and no border around it.
	if w := Widget_Get(g, g.root); w != nil {
		if w.style.box.bg_color.a == 0 {
			w.style.box.bg_color = p.window
			w.style_cache.valid = false
		}
	}
	default_theme_apply(g)
}

//* Turns the theme on for every widget of the tree.
default_theme_apply :: proc(g: ^GUI) {
	if g.root == INVALID_WIDGET_ID { return }
	default_theme_apply_node(g, g.root)
}

default_theme_apply_node :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !w.use_theme {
		w.use_theme = true
		w.style_cache.valid = false
		//* The widget takes the theme now, so it is measured again and
		//* drawn again.
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		default_theme_apply_node(g, child)
		child = c.next_sibling
	}
}

//* Makes a theme with a style for every kind of widget.
default_theme_make :: proc(dark: bool) -> ^Theme {
	theme := Theme_Make()
	p := default_theme_palette(dark)

	//* Every kind of widget gets a style, so that a widget which takes
	//* the theme never comes out without a look.
	for widget_type in Widget_Type {
		Theme_Set_Type(theme, widget_type, Style{text = Text_Style{colour = p.text}})
		theme_set_color(theme, widget_type, "font_color", p.text)
		theme_set_font_size(theme, widget_type, "font_size", 16)
	}

	//* == The panels ==
	//* A panel is a box with a border around it.
	Theme_Set_Type(theme, .Panel, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 8, 8),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .PanelContainer, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 8, 8),
		text = Text_Style{colour = p.text},
	})

	//* == The buttons ==
	//* A button is a rounded box. A link is only a piece of text.
	Theme_Set_Type(theme, .Button, Style{
		box = default_theme_padded(p.button, p.border, 1, 6, 12, 6),
		text = Text_Style{
			colour          = p.text,
			hover_colour    = p.text,
			pressed_colour  = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
			valign          = .Center,
		},
	})
	Theme_Set_State(theme, .Button, .Hovered, Style{box = StyleBox{bg_color = p.hover}})
	Theme_Set_State(theme, .Button, .Pressed, Style{box = StyleBox{bg_color = p.pressed}})
	Theme_Set_State(theme, .Button, .Disabled, Style{box = StyleBox{bg_color = p.disabled}})
	Theme_Set_State(theme, .Button, .Focused, Style{
		text = Text_Style{colour = p.accent},
	})
	//* The style box of the button is named, so that a program can put
	//* another one in its place.
	theme_set_stylebox(theme, .Button, "normal", default_theme_box(p.button, p.border, 1, 6))
	theme_set_stylebox(theme, .Button, "hover", default_theme_box(p.hover, p.border, 1, 6))
	theme_set_stylebox(theme, .Button, "pressed", default_theme_box(p.pressed, p.border, 1, 6))
	theme_set_stylebox(theme, .Button, "focus", default_theme_box(p.button, p.accent, 1, 6))
	theme_set_color(theme, .Button, "font_hover_color", p.text)
	theme_set_color(theme, .Button, "font_pressed_color", p.text)
	theme_set_color(theme, .Button, "font_disabled_color", p.text_dim)
	theme_set_color(theme, .Button, "font_focus_color", p.accent)
	theme_set_constant(theme, .Button, "h_separation", 8)

	Theme_Set_Type(theme, .CheckBox, Style{
		text = Text_Style{colour = p.text, valign = .Center},
	})
	Theme_Set_Type(theme, .CheckButton, Style{
		text = Text_Style{colour = p.text, valign = .Center},
	})
	Theme_Set_Type(theme, .LinkButton, Style{
		text = Text_Style{
			colour          = p.accent,
			hover_colour    = p.accent,
			disabled_colour = p.text_dim,
			valign          = .Center,
		},
	})
	Theme_Set_Type(theme, .MenuButton, Style{
		box = default_theme_padded(p.button, p.border, 1, 6, 10, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
			valign          = .Center,
		},
	})
	Theme_Set_State(theme, .MenuButton, .Hovered, Style{box = StyleBox{bg_color = p.hover}})
	Theme_Set_State(theme, .MenuButton, .Pressed, Style{box = StyleBox{bg_color = p.pressed}})

	//* == The text ==
	//* A label is only text. A field has a background of its own, so
	//* that it can be found on the background of a panel.
	Theme_Set_Type(theme, .Label, Style{
		text = Text_Style{colour = p.text, valign = .Center},
	})
	Theme_Set_Type(theme, .RichTextLabel, Style{
		text = Text_Style{colour = p.text, wrap = .Word},
	})
	Theme_Set_Type(theme, .TextInput, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_State(theme, .TextInput, .Focused, Style{
		box = StyleBox{border_color = {p.accent, p.accent, p.accent, p.accent}},
	})
	Theme_Set_Type(theme, .TextEdit, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
			wrap            = .Anywhere,
		},
	})
	Theme_Set_Type(theme, .ItemList, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .Tree, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	theme_set_color(theme, .ItemList, "selected_color", p.accent)
	theme_set_color(theme, .Tree, "selected_color", p.accent)

	//* == The ranges ==
	Theme_Set_Type(theme, .OptionButton, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_Type(theme, .SpinBox, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_Type(theme, .ProgressBar, Style{
		box  = default_theme_padded(p.field, p.field, 0, 4, 2, 2),
		text = Text_Style{colour = p.text_dim},
	})
	Theme_Set_Type(theme, .HSlider, Style{
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .VSlider, Style{
		text = Text_Style{colour = p.text},
	})

	//* == The containers ==
	//* The boxes and the grids have no background of their own: they
	//* show the panel they are in.
	Theme_Set_Type(theme, .VBox, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .HBox, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .GridContainer, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .MarginContainer, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .CenterContainer, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .ScrollContainer, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .ScrollArea, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .FlowContainer, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .AspectRatioContainer, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .Split, Style{text = Text_Style{colour = p.text}})
	theme_set_constant(theme, .VBox, "separation", 6)
	theme_set_constant(theme, .HBox, "separation", 6)
	theme_set_constant(theme, .GridContainer, "h_separation", 6)
	theme_set_constant(theme, .GridContainer, "v_separation", 6)
	theme_set_constant(theme, .FlowContainer, "separation", 6)

	//* == The strips ==
	Theme_Set_Type(theme, .Tabs, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .TabContainer, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .TabBar, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 0, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .MenuBar, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 0, 6, 4),
		text = Text_Style{colour = p.text},
	})

	//* == The lines and the pictures ==
	Theme_Set_Type(theme, .HSeparator, Style{text = Text_Style{colour = p.border}})
	Theme_Set_Type(theme, .VSeparator, Style{text = Text_Style{colour = p.border}})
	Theme_Set_Type(theme, .ColorRect, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .TextureRect, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .NinePatchRect, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .ReferenceRect, Style{text = Text_Style{colour = p.text}})
	Theme_Set_Type(theme, .Image, Style{text = Text_Style{colour = p.text}})

	//* == The popups ==
	//* A popup comes up over the rest of the UI, so it has a border and
	//* a shadow of its own.
	Theme_Set_Type(theme, .PopupMenu, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 6, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .PopupPanel, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 6, 8, 8),
		text = Text_Style{colour = p.text},
	})
	//* The overlays draw their own box, so the theme gives them no
	//* background of their own: the box of the widget would be drawn
	//* over the whole of the area the widget has.
	Theme_Set_Type(theme, .ContextMenu, Style{
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .AcceptDialog, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 6, 12, 12),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .ConfirmationDialog, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 6, 12, 12),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .FileDialog, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 6, 8, 8),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .Tooltip, Style{
		text = Text_Style{colour = p.text},
	})

	//* == The widgets that came later ==
	Theme_Set_Type(theme, .Toast, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 6, 12, 10),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .CommandPalette, Style{
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .Rating, Style{
		text = Text_Style{colour = p.accent, valign = .Center},
	})
	Theme_Set_Type(theme, .Segmented, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 2, 2),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .ToggleSwitch, Style{
		text = Text_Style{colour = p.text, valign = .Center},
	})
	Theme_Set_Type(theme, .ComboBox, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_Type(theme, .VirtualList, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 2, 2),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .DataTable, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 2, 2),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .DatePicker, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_Type(theme, .TimePicker, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_Type(theme, .ColorPicker, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .EmojiPicker, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .Accordion, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 8, 8),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .ChatInput, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .SearchField, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})
	Theme_Set_Type(theme, .NumberInput, Style{
		box = default_theme_padded(p.field, p.border, 1, 4, 8, 5),
		text = Text_Style{
			colour          = p.text,
			disabled_colour = p.text_dim,
			focus_colour    = p.accent,
		},
	})

	//* == The heavy widgets ==
	Theme_Set_Type(theme, .Chart, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .NodeGraph, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 4, 4),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .Canvas, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 0, 0),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .FileViewer, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 2, 2),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .RichTextEditor, Style{
		box  = default_theme_padded(p.field, p.border, 1, 4, 8, 8),
		text = Text_Style{colour = p.text, wrap = .Word},
	})
	Theme_Set_Type(theme, .VectorDrawing, Style{
		box  = default_theme_padded(p.surface, p.border, 1, 4, 0, 0),
		text = Text_Style{colour = p.text},
	})
	Theme_Set_Type(theme, .AudioPlayer, Style{
		text = Text_Style{colour = p.text},
	})

	return theme
}
