//* A showcase of the text features: the sizes a family can be shown
//* at, the colours, the alignment, the wrapping, the decorations, the
//* themes and the text field.
//*
//* The panel is made without a parent and handed back, so the caller
//* can put it wherever it likes. Everything is in one column of rows,
//* and the rows of a feature sit next to each other, so that the whole
//* showcase fits in the space the caller gives it.
package GUI

//* The text the size samples show: two letters, so that five sizes fit
//* in a row.
DEMO_TEXT_SIZE :: "Ag"

//* The text the colour samples show. It has ascenders and descenders,
//* so the sizes can be compared against each other.
DEMO_TEXT_SAMPLE :: "Sample text"

//* The text the samples that need a narrow box show.
DEMO_TEXT_SHORT :: "text"

//* The caption: the small dim label that says what the samples next to
//* it are showing. It is dim so that it does not compete with them.
demo_text_caption :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
	body: Font_Family_ID,
) -> Widget_ID {
	return widget(g, .Label, parent, Widget_Opts{
		name = name,
		text = text,
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 10, body)},
	})
}

//* A row of the showcase. The height is given, because a box does not
//* work out the height of its children: it would give every row the
//* same share of the space and the taller samples would be cut off.
demo_text_row :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	height: f32,
) -> Widget_ID {
	return widget(g, .HBox, parent, Widget_Opts{
		name = name,
		min_size = Vec2{0, height},
		separation = 8,
	})
}

//* Builds the text showcase and returns its panel. The panel has no
//* parent: the caller puts it where it wants it.
init_demo_text :: proc(g: ^GUI, body: Font_Family_ID) -> Widget_ID {
	//* The offsets put the panel in the top left corner of the space
	//* the caller gives it, and the minimum size gives it the width.
	panel := widget(g, .Panel, INVALID_WIDGET_ID, Widget_Opts{
		name = "text_showcase",
		preset = .Top_Left,
		offsets = Offset{16, 64, 16, 300},
		min_size = Vec2{560, 0},
		style = Style{
			bg = rgba(0.10, 0.11, 0.14, 1),
			border = rgba(0.20, 0.22, 0.27, 1),
			border_width = 1,
			text = text_style(rgba(0.86, 0.89, 0.95, 1), 0, body),
		},
	})

	samples := widget(g, .VBox, panel, Widget_Opts{
		name = "samples",
		preset = .Fill,
		offsets = Offset{12, 2, -12, -2},
		separation = 6,
	})

	//* Sizes: the same string at five sizes. One family serves all of
	//* them, because the size belongs to the widget and not to the
	//* typeface.
	sizes := demo_text_row(g, samples, "sizes", 37)
	demo_text_caption(g, sizes, "caption_Size", "Size", body)
	widget(g, .Label, sizes, Widget_Opts{
		name = "size_10",
		text = DEMO_TEXT_SIZE,
		style = Style{text = text_style(rgba(0.86, 0.89, 0.95, 1), 10, body)},
	})
	widget(g, .Label, sizes, Widget_Opts{
		name = "size_12",
		text = DEMO_TEXT_SIZE,
		style = Style{text = text_style(rgba(0.86, 0.89, 0.95, 1), 12, body)},
	})
	widget(g, .Label, sizes, Widget_Opts{
		name = "size_16",
		text = DEMO_TEXT_SIZE,
		style = Style{text = text_style(rgba(0.86, 0.89, 0.95, 1), 16, body)},
	})
	widget(g, .Label, sizes, Widget_Opts{
		name = "size_24",
		text = DEMO_TEXT_SIZE,
		style = Style{text = text_style(rgba(0.86, 0.89, 0.95, 1), 24, body)},
	})
	widget(g, .Label, sizes, Widget_Opts{
		name = "size_32",
		text = DEMO_TEXT_SIZE,
		style = Style{text = text_style(rgba(0.86, 0.89, 0.95, 1), 32, body)},
	})

	//* Colours: the same string in four colours.
	colours := demo_text_row(g, samples, "colours", 16)
	demo_text_caption(g, colours, "caption_Colour", "Colour", body)
	widget(g, .Label, colours, Widget_Opts{
		name = "colour_red",
		text = DEMO_TEXT_SAMPLE,
		style = Style{text = text_style(rgba(0.95, 0.42, 0.42, 1), 12, body)},
	})
	widget(g, .Label, colours, Widget_Opts{
		name = "colour_green",
		text = DEMO_TEXT_SAMPLE,
		style = Style{text = text_style(rgba(0.40, 0.85, 0.52, 1), 12, body)},
	})
	widget(g, .Label, colours, Widget_Opts{
		name = "colour_blue",
		text = DEMO_TEXT_SAMPLE,
		style = Style{text = text_style(rgba(0.45, 0.65, 0.98, 1), 12, body)},
	})
	widget(g, .Label, colours, Widget_Opts{
		name = "colour_amber",
		text = DEMO_TEXT_SAMPLE,
		style = Style{text = text_style(rgba(0.98, 0.76, 0.30, 1), 12, body)},
	})

	//* The transform is done to the string before it is laid out, so
	//* the three samples show the same text in three ways.
	//*
	//* The alignment is shown in boxes that are wider than the text,
	//* or there would be nothing to align it in.
	case_row := demo_text_row(g, samples, "case_and_align", 30)
	demo_text_caption(g, case_row, "caption_Case", "Case", body)
	widget(g, .Label, case_row, Widget_Opts{
		name = "case_upper",
		text = DEMO_TEXT_SHORT,
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				transform = .Upper,
			},
		},
	})
	widget(g, .Label, case_row, Widget_Opts{
		name = "case_lower",
		text = DEMO_TEXT_SHORT,
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				transform = .Lower,
			},
		},
	})
	widget(g, .Label, case_row, Widget_Opts{
		name = "case_capitalize",
		text = DEMO_TEXT_SHORT,
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				transform = .Capitalize,
			},
		},
	})
	demo_text_caption(g, case_row, "caption_Align", "Align", body)
	widget(g, .Label, case_row, Widget_Opts{
		name = "align_left",
		text = DEMO_TEXT_SHORT,
		min_size = Vec2{72, 0},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Left,
			},
		},
	})
	widget(g, .Label, case_row, Widget_Opts{
		name = "align_center",
		text = DEMO_TEXT_SHORT,
		min_size = Vec2{72, 0},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Center,
			},
		},
	})
	widget(g, .Label, case_row, Widget_Opts{
		name = "align_right",
		text = DEMO_TEXT_SHORT,
		min_size = Vec2{72, 0},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Right,
			},
		},
	})
	//* The filled text is spread out so that it fills the box. That
	//* only shows on a line that is not the last one, so this sample
	//* has two lines in it.
	widget(g, .Label, case_row, Widget_Opts{
		name = "align_fill",
		text = "a b c\nd e f",
		min_size = Vec2{72, 0},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Fill,
			},
		},
	})

	//* The vertical alignment is shown in boxes that are taller than
	//* the text, or there would be nothing to align it in.
	vals := demo_text_row(g, samples, "valign", 24)
	demo_text_caption(g, vals, "caption_VAlign", "VAlign", body)
	widget(g, .Label, vals, Widget_Opts{
		name = "valign_top",
		text = DEMO_TEXT_SHORT,
		min_size = Vec2{72, 24},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				valign = .Top,
			},
		},
	})
	widget(g, .Label, vals, Widget_Opts{
		name = "valign_center",
		text = DEMO_TEXT_SHORT,
		min_size = Vec2{72, 24},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				valign = .Center,
			},
		},
	})
	widget(g, .Label, vals, Widget_Opts{
		name = "valign_bottom",
		text = DEMO_TEXT_SHORT,
		min_size = Vec2{72, 24},
		fixed = true,
		style = Style{
			bg = rgba(0.14, 0.16, 0.20, 1),
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				valign = .Bottom,
			},
		},
	})

	//* Wrapping: the text is broken into lines that fit the box. The
	//* word wrap breaks at the spaces, the anywhere wrap breaks even
	//* inside a word.
	wrap_row := demo_text_row(g, samples, "wrap", 30)
	demo_text_caption(g, wrap_row, "caption_Wrap", "Wrap", body)
	widget(g, .Label, wrap_row, Widget_Opts{
		name = "wrap_word",
		text = "Text that wraps at word boundaries",
		min_size = Vec2{160, 0},
		fixed = true,
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				wrap = .Word,
			},
		},
	})
	widget(g, .Label, wrap_row, Widget_Opts{
		name = "wrap_anywhere",
		text = "Textthatwrapsanywhereeveninsideaword",
		min_size = Vec2{160, 0},
		fixed = true,
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				wrap = .Anywhere,
			},
		},
	})

	//* The overrun: the text is cut short where it does not fit and an
	//* ellipsis is put in its place. It sits in a box of its own, so
	//* that the text is far longer than the box it is in.
	//*
	//* The line spacing: the extra pixels between the lines.
	//*
	//* The outline is drawn under the text and the shadow under that.
	line_row := demo_text_row(g, samples, "line_and_decoration", 38)
	demo_text_caption(g, line_row, "caption_Line", "Line", body)
	overrun_box := widget(g, .VBox, line_row, Widget_Opts{
		name = "overrun_box",
		min_size = Vec2{140, 0},
		fixed = true,
	})
	widget(g, .Label, overrun_box, Widget_Opts{
		name = "overrun",
		text = "This text is far longer than the box it is in",
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				overrun = .Ellipsis,
			},
		},
	})
	widget(g, .Label, line_row, Widget_Opts{
		name = "spacing",
		text = "One two three four five six seven",
		min_size = Vec2{150, 0},
		fixed = true,
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				wrap = .Word,
				spacing = 8,
			},
		},
	})
	widget(g, .Label, line_row, Widget_Opts{
		name = "outline",
		text = "Outline",
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 14,
				family = body,
				outline_colour = rgba(0.20, 0.24, 0.30, 1),
				outline_size = 2,
			},
		},
	})
	widget(g, .Label, line_row, Widget_Opts{
		name = "shadow",
		text = "Shadow",
		style = Style{
			text = Text_Style{
				colour = rgba(0.86, 0.89, 0.95, 1),
				size = 14,
				family = body,
				shadow_colour = rgba(0, 0, 0, 0.6),
				shadow_offset = Vec2{2, 2},
			},
		},
	})

	//* The theme: the look of every kind of widget in one place. It
	//* only reaches the widgets that ask for it, so the samples above
	//* keep the colours they were given.
	//*
	//* The GUI takes the theme over, so this one replaces the theme it
	//* had, if it had one.
	theme := theme_make()
	theme_set_type(theme, .Button, Style{
		bg = rgba(0.20, 0.24, 0.30, 1),
		text = Text_Style{
			colour = rgba(0.92, 0.94, 0.98, 1),
			size = 12,
			align = .Center,
			family = body,
		},
	})
	theme_set_state(theme, .Button, .Hovered, Style{
		bg = rgba(0.28, 0.34, 0.42, 1),
		text = Text_Style{colour = rgba(1, 1, 1, 1)},
	})
	//* A named variation of a type: it is the style of the type with
	//* a different look on top of it.
	theme_add_variation(theme, "danger", .Button, Style{
		bg = rgba(0.62, 0.18, 0.18, 1),
		text = Text_Style{colour = rgba(1, 0.94, 0.94, 1)},
	})
	gui_set_theme(g, theme)

	widgets := demo_text_row(g, samples, "widgets", 22)
	demo_text_caption(g, widgets, "caption_Widget", "Widget", body)
	//* The ink of a button says what state it is in: under the pointer,
	//* while it is held down, and while it is disabled.
	stateful := Style{
		bg = rgba(0.16, 0.42, 0.82, 1),
		text = Text_Style{
			colour = rgba(1, 1, 1, 1),
			size = 12,
			align = .Center,
			family = body,
			hover_colour = rgba(1, 0.95, 0.70, 1),
			pressed_colour = rgba(0.86, 0.92, 1, 1),
			disabled_colour = rgba(0.62, 0.64, 0.68, 1),
		},
	}
	widget(g, .Button, widgets, Widget_Opts{
		name = "states",
		text = "States",
		min_size = Vec2{70, 22},
		fixed = true,
		style = stateful,
	})
	//* The same button, but not enabled: it is drawn with the
	//* disabled colour and the pointer leaves it alone.
	disabled := widget(g, .Button, widgets, Widget_Opts{
		name = "disabled",
		text = "Disabled",
		min_size = Vec2{70, 22},
		fixed = true,
		style = stateful,
	})
	widget_get(g, disabled).state -= Widget_State{.Enabled}
	//* A button that takes the theme.
	widget(g, .Button, widgets, Widget_Opts{
		name = "themed",
		text = "Themed",
		min_size = Vec2{70, 22},
		fixed = true,
		use_theme = true,
	})
	//* A button that takes the theme's danger variation.
	widget(g, .Button, widgets, Widget_Opts{
		name = "danger",
		text = "Danger",
		min_size = Vec2{70, 22},
		fixed = true,
		use_theme = true,
		variation = "danger",
	})
	//* A text field: its text style has a colour and a size of its
	//* own, like the text of every other widget.
	widget(g, .TextInput, widgets, Widget_Opts{
		name = "field",
		text = "type here",
		min_size = Vec2{150, 22},
		fixed = true,
		style = Style{
			bg = rgba(0.06, 0.07, 0.09, 1),
			border = rgba(0.30, 0.33, 0.40, 1),
			border_width = 1,
			text = Text_Style{
				colour = rgba(0.92, 0.94, 0.98, 1),
				size = 14,
				family = body,
			},
		},
	})

	return panel
}
