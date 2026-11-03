//* A showcase of the text features: the sizes a family can be shown
//* at, the colours, the alignment, the wrapping, the decorations, the
//* themes and the text field.
//*
//* The panel is made without a parent and handed back, so the caller
//* can put it wherever it likes. Everything is in one column of rows,
//* and the rows of a feature sit next to each other, so that the whole
//* showcase fits in the space the caller gives it.
package main

import GUI "../../src/GUI"

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
Demo_Text_Caption :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
	body: GUI.Font_Family_ID,
) -> GUI.Widget_ID {
	return GUI.New_Widget(g, .Label, parent, GUI.Widget_Opts{
		name = name,
		text = text,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 10, body)},
	})
}

//* A row of the showcase. The height is given, because a box does not
//* work out the height of its children: it would give every row the
//* same share of the space and the taller samples would be cut off.
Demo_Text_Row :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	height: f32,
) -> GUI.Widget_ID {
	return GUI.New_Widget(g, .HBox, parent, GUI.Widget_Opts{
		name = name,
		min_size = GUI.Vec2{0, height},
		separation = 8,
	})
}

//* Builds the text showcase and returns its panel. The panel has no
//* parent: the caller puts it where it wants it.
Init_Demo_Text :: proc(g: ^GUI.GUI, body: GUI.Font_Family_ID) -> GUI.Widget_ID {
	//* The offsets put the panel in the top left corner of the space
	//* the caller gives it, and the minimum size gives it the width.
	panel := GUI.New_Widget(g, .Panel, GUI.INVALID_WIDGET_ID, GUI.Widget_Opts{
		name = "text_showcase",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 64, 16, 300},
		min_size = GUI.Vec2{560, 0},
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.10, 0.11, 0.14, 1),
				border_color = {GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1)},
				border_width = {1, 1, 1, 1},
			},
			text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 0, body),
		},
	})

	samples := GUI.New_Widget(g, .VBox, panel, GUI.Widget_Opts{
		name = "samples",
		preset = .Fill,
		offsets = GUI.Offset{12, 2, -12, -2},
		separation = 6,
	})

	//* Sizes: the same string at five sizes. One family serves all of
	//* them, because the size belongs to the widget and not to the
	//* typeface.
	sizes := Demo_Text_Row(g, samples, "sizes", 37)
	Demo_Text_Caption(g, sizes, "caption_Size", "Size", body)
	GUI.New_Widget(g, .Label, sizes, GUI.Widget_Opts{
		name = "size_10",
		text = DEMO_TEXT_SIZE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 10, body)},
	})
	GUI.New_Widget(g, .Label, sizes, GUI.Widget_Opts{
		name = "size_12",
		text = DEMO_TEXT_SIZE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 12, body)},
	})
	GUI.New_Widget(g, .Label, sizes, GUI.Widget_Opts{
		name = "size_16",
		text = DEMO_TEXT_SIZE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 16, body)},
	})
	GUI.New_Widget(g, .Label, sizes, GUI.Widget_Opts{
		name = "size_24",
		text = DEMO_TEXT_SIZE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 24, body)},
	})
	GUI.New_Widget(g, .Label, sizes, GUI.Widget_Opts{
		name = "size_32",
		text = DEMO_TEXT_SIZE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 32, body)},
	})

	//* Colours: the same string in four colours.
	colours := Demo_Text_Row(g, samples, "colours", 16)
	Demo_Text_Caption(g, colours, "caption_Colour", "GUI.Colour", body)
	GUI.New_Widget(g, .Label, colours, GUI.Widget_Opts{
		name = "colour_red",
		text = DEMO_TEXT_SAMPLE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.95, 0.42, 0.42, 1), 12, body)},
	})
	GUI.New_Widget(g, .Label, colours, GUI.Widget_Opts{
		name = "colour_green",
		text = DEMO_TEXT_SAMPLE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.40, 0.85, 0.52, 1), 12, body)},
	})
	GUI.New_Widget(g, .Label, colours, GUI.Widget_Opts{
		name = "colour_blue",
		text = DEMO_TEXT_SAMPLE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.65, 0.98, 1), 12, body)},
	})
	GUI.New_Widget(g, .Label, colours, GUI.Widget_Opts{
		name = "colour_amber",
		text = DEMO_TEXT_SAMPLE,
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.98, 0.76, 0.30, 1), 12, body)},
	})

	//* The transform is done to the string before it is laid out, so
	//* the three samples show the same text in three ways.
	//*
	//* The alignment is shown in boxes that are wider than the text,
	//* or there would be nothing to align it in.
	case_row := Demo_Text_Row(g, samples, "case_and_align", 30)
	Demo_Text_Caption(g, case_row, "caption_Case", "Case", body)
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "case_upper",
		text = DEMO_TEXT_SHORT,
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				transform = .Upper,
			},
		},
	})
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "case_lower",
		text = DEMO_TEXT_SHORT,
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				transform = .Lower,
			},
		},
	})
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "case_capitalize",
		text = DEMO_TEXT_SHORT,
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				transform = .Capitalize,
			},
		},
	})
	Demo_Text_Caption(g, case_row, "caption_Align", "Align", body)
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "align_left",
		text = DEMO_TEXT_SHORT,
		min_size = GUI.Vec2{72, 0},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Left,
			},
		},
	})
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "align_center",
		text = DEMO_TEXT_SHORT,
		min_size = GUI.Vec2{72, 0},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Center,
			},
		},
	})
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "align_right",
		text = DEMO_TEXT_SHORT,
		min_size = GUI.Vec2{72, 0},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Right,
			},
		},
	})
	//* The filled text is spread out so that it fills the box. That
	//* only shows on a line that is not the last one, so this sample
	//* has two lines in it.
	GUI.New_Widget(g, .Label, case_row, GUI.Widget_Opts{
		name = "align_fill",
		text = "a b c\nd e f",
		min_size = GUI.Vec2{72, 0},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				align = .Fill,
			},
		},
	})

	//* The vertical alignment is shown in boxes that are taller than
	//* the text, or there would be nothing to align it in.
	vals := Demo_Text_Row(g, samples, "valign", 24)
	Demo_Text_Caption(g, vals, "caption_VAlign", "VAlign", body)
	GUI.New_Widget(g, .Label, vals, GUI.Widget_Opts{
		name = "valign_top",
		text = DEMO_TEXT_SHORT,
		min_size = GUI.Vec2{72, 24},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				valign = .Top,
			},
		},
	})
	GUI.New_Widget(g, .Label, vals, GUI.Widget_Opts{
		name = "valign_center",
		text = DEMO_TEXT_SHORT,
		min_size = GUI.Vec2{72, 24},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				valign = .Center,
			},
		},
	})
	GUI.New_Widget(g, .Label, vals, GUI.Widget_Opts{
		name = "valign_bottom",
		text = DEMO_TEXT_SHORT,
		min_size = GUI.Vec2{72, 24},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.14, 0.16, 0.20, 1),
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				valign = .Bottom,
			},
		},
	})

	//* Wrapping: the text is broken into lines that fit the box. The
	//* word wrap breaks at the spaces, the anywhere wrap breaks even
	//* inside a word.
	wrap_row := Demo_Text_Row(g, samples, "wrap", 30)
	Demo_Text_Caption(g, wrap_row, "caption_Wrap", "Wrap", body)
	GUI.New_Widget(g, .Label, wrap_row, GUI.Widget_Opts{
		name = "wrap_word",
		text = "Text that wraps at word boundaries",
		min_size = GUI.Vec2{160, 0},
		fixed = true,
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				wrap = .Word,
			},
		},
	})
	GUI.New_Widget(g, .Label, wrap_row, GUI.Widget_Opts{
		name = "wrap_anywhere",
		text = "Textthatwrapsanywhereeveninsideaword",
		min_size = GUI.Vec2{160, 0},
		fixed = true,
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
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
	line_row := Demo_Text_Row(g, samples, "line_and_decoration", 38)
	Demo_Text_Caption(g, line_row, "caption_Line", "Line", body)
	overrun_box := GUI.New_Widget(g, .VBox, line_row, GUI.Widget_Opts{
		name = "overrun_box",
		min_size = GUI.Vec2{140, 0},
		fixed = true,
	})
	GUI.New_Widget(g, .Label, overrun_box, GUI.Widget_Opts{
		name = "overrun",
		text = "This text is far longer than the box it is in",
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				overrun = .Ellipsis,
			},
		},
	})
	GUI.New_Widget(g, .Label, line_row, GUI.Widget_Opts{
		name = "spacing",
		text = "One two three four five six seven",
		min_size = GUI.Vec2{150, 0},
		fixed = true,
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 12,
				family = body,
				wrap = .Word,
				spacing = 8,
			},
		},
	})
	GUI.New_Widget(g, .Label, line_row, GUI.Widget_Opts{
		name = "outline",
		text = "Outline",
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 14,
				family = body,
				outline_colour = GUI.RGBA(0.20, 0.24, 0.30, 1),
				outline_size = 2,
			},
		},
	})
	GUI.New_Widget(g, .Label, line_row, GUI.Widget_Opts{
		name = "shadow",
		text = "Shadow",
		style = GUI.Style{
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.86, 0.89, 0.95, 1),
				size = 14,
				family = body,
				shadow_colour = GUI.RGBA(0, 0, 0, 0.6),
				shadow_offset = GUI.Vec2{2, 2},
			},
		},
	})

	//* The theme: the look of every kind of widget in one place. It
	//* only reaches the widgets that ask for it, so the samples above
	//* keep the colours they were given.
	//*
	//* The GUI takes the theme over, so this one replaces the theme it
	//* had, if it had one.
	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Button, GUI.Style{
box = GUI.StyleBox{
			bg_color = GUI.RGBA(0.20, 0.24, 0.30, 1),
		},
		text = GUI.Text_Style{
			colour = GUI.RGBA(0.92, 0.94, 0.98, 1),
			size = 12,
			align = .Center,
			family = body,
		},
	})
	GUI.Theme_Set_State(theme, .Button, .Hovered, GUI.Style{
box = GUI.StyleBox{
			bg_color = GUI.RGBA(0.28, 0.34, 0.42, 1),
		},
		text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1)},
	})
	//* A named variation of a type: it is the style of the type with
	//* a different look on top of it.
	GUI.Theme_Add_Variation(theme, "danger", .Button, GUI.Style{
box = GUI.StyleBox{
			bg_color = GUI.RGBA(0.62, 0.18, 0.18, 1),
		},
		text = GUI.Text_Style{colour = GUI.RGBA(1, 0.94, 0.94, 1)},
	})
	GUI.GUI_Set_Theme(g, theme)

	widgets := Demo_Text_Row(g, samples, "widgets", 22)
	Demo_Text_Caption(g, widgets, "caption_Widget", "GUI.Widget", body)
	//* The ink of a button says what state it is in: under the pointer,
	//* while it is held down, and while it is disabled.
	stateful := GUI.Style{
box = GUI.StyleBox{
			bg_color = GUI.RGBA(0.16, 0.42, 0.82, 1),
		},
		text = GUI.Text_Style{
			colour = GUI.RGBA(1, 1, 1, 1),
			size = 12,
			align = .Center,
			family = body,
			hover_colour = GUI.RGBA(1, 0.95, 0.70, 1),
			pressed_colour = GUI.RGBA(0.86, 0.92, 1, 1),
			disabled_colour = GUI.RGBA(0.62, 0.64, 0.68, 1),
		},
	}
	GUI.New_Widget(g, .Button, widgets, GUI.Widget_Opts{
		name = "states",
		text = "States",
		min_size = GUI.Vec2{70, 22},
		fixed = true,
		style = stateful,
	})
	//* The same button, but not enabled: it is drawn with the
	//* disabled colour and the pointer leaves it alone.
	disabled := GUI.New_Widget(g, .Button, widgets, GUI.Widget_Opts{
		name = "disabled",
		text = "Disabled",
		min_size = GUI.Vec2{70, 22},
		fixed = true,
		style = stateful,
	})
	GUI.Widget_Get(g, disabled).state -= GUI.Widget_State{.Enabled}
	//* A button that takes the theme.
	GUI.New_Widget(g, .Button, widgets, GUI.Widget_Opts{
		name = "themed",
		text = "Themed",
		min_size = GUI.Vec2{70, 22},
		fixed = true,
		use_theme = true,
	})
	//* A button that takes the theme's danger variation.
	GUI.New_Widget(g, .Button, widgets, GUI.Widget_Opts{
		name = "danger",
		text = "Danger",
		min_size = GUI.Vec2{70, 22},
		fixed = true,
		use_theme = true,
		variation = "danger",
	})
	//* A text field: its text style has a colour and a size of its
	//* own, like the text of every other widget.
	GUI.New_Widget(g, .TextInput, widgets, GUI.Widget_Opts{
		name = "field",
		text = "type here",
		min_size = GUI.Vec2{150, 22},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.06, 0.07, 0.09, 1),
				border_color = {GUI.RGBA(0.30, 0.33, 0.40, 1), GUI.RGBA(0.30, 0.33, 0.40, 1), GUI.RGBA(0.30, 0.33, 0.40, 1), GUI.RGBA(0.30, 0.33, 0.40, 1)},
				border_width = {1, 1, 1, 1},
			},
			text = GUI.Text_Style{
				colour = GUI.RGBA(0.92, 0.94, 0.98, 1),
				size = 14,
				family = body,
			},
		},
	})

	return panel
}
