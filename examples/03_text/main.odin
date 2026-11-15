package main

import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

TEXT_WIDTH :: 900
INK :: GUI.Colour{0.88, 0.91, 0.96, 1}
DIM :: GUI.Colour{0.52, 0.56, 0.64, 1}
ACCENT :: GUI.Colour{0.47, 0.68, 1.00, 1}
SAMPLE_BG :: GUI.Colour{0.13, 0.15, 0.19, 1}
SAMPLE_BORDER :: GUI.Colour{0.22, 0.25, 0.31, 1}

g: ^GUI.GUI
family: GUI.Font_Family_ID

main :: proc() {
	App.Run(
		"CalcUI - Text",
		980,
		720,
		proc(app: ^App.App) {
			g = app.gui
			family = app.family
			GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)
			build_text_sample()
		},
		nil,
	)
	log.info("the text example is done")
}

caption :: proc(parent: GUI.Widget_ID, name, text: string) -> GUI.Widget_ID {
	return GUI.Make_Label(
		g,
		parent,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				min_size = GUI.Vec2{104, 16},
				fixed = true,
				style = GUI.Style{
					text = GUI.Text_Style{
						colour = ACCENT,
						size = 11,
						family = family,
						transform = .Upper,
					},
				},
			},
			text = text,
		},
	)
}

row :: proc(parent: GUI.Widget_ID, name: string, height: f32) -> GUI.Widget_ID {
	return GUI.Make_HBox(
		g,
		parent,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				min_size = GUI.Vec2{0, height},
				separation = 12,
			},
		},
	)
}

text_style :: proc(size: f32, colour: GUI.Colour, wrap: GUI.Text_Wrap = .Off) -> GUI.Style {
	return GUI.Style {
		text = GUI.Text_Style {
			colour = colour,
			size = size,
			family = family,
			wrap = wrap,
		},
	}
}

boxed_style :: proc(
	size: f32,
	colour: GUI.Colour,
	align: GUI.Text_Align,
	wrap: GUI.Text_Wrap = .Off,
) -> GUI.Style {
	return GUI.Style {
		box = GUI.StyleBox {
			bg_color = SAMPLE_BG,
			border_color = {SAMPLE_BORDER, SAMPLE_BORDER, SAMPLE_BORDER, SAMPLE_BORDER},
			border_width = {1, 1, 1, 1},
			content_margin = {10, 6, 10, 6},
		},
		text = GUI.Text_Style {
			colour = colour,
			size = size,
			family = family,
			align = align,
			wrap = wrap,
		},
	}
}

sample :: proc(
	parent: GUI.Widget_ID,
	name, text: string,
	style: GUI.Style,
	width, height: f32,
) -> GUI.Widget_ID {
	return GUI.Make_Label(
		g,
		parent,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				min_size = GUI.Vec2{width, height},
				max_size = GUI.Vec2{width, height},
				fixed = true,
				style = style,
			},
			text = text,
		},
	)
}

build_text_sample :: proc() {
	scroll := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "text_scroll",
				offsets = GUI.Offset{left = 24, top = 20, right = -24, bottom = -20},
			},
		},
	)

	column := GUI.Make_VBox(
		g,
		scroll,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "text_column",
				min_size = GUI.Vec2{TEXT_WIDTH, 0},
				separation = 14,
			},
		},
	)

	GUI.Make_Label(
		g,
		column,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "title",
				style = GUI.Style{text = GUI.Text_Style{colour = INK, size = 30, family = family}},
			},
			text = "Text",
		},
	)

	GUI.Make_Label(
		g,
		column,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "subtitle",
				min_size = GUI.Vec2{TEXT_WIDTH, 0},
				max_size = GUI.Vec2{TEXT_WIDTH, 0},
				size_flags_h = GUI.Size_Flags{.Fill},
				style = GUI.Style{
					text = GUI.Text_Style{
						colour = DIM,
						size = 14,
						family = family,
						wrap = .Word,
					},
				},
			},
			text = "One text engine reaches every size, colour, alignment, wrap, overrun, spacing, decoration and transform. The samples below are labels, so a change of the style changes the text alone.",
		},
	)

	sizes := row(column, "sizes", 62)
	caption(sizes, "caption_sizes", "size")
	sample(sizes, "size_12", "Ag", text_style(12, INK), 0, 24)
	sample(sizes, "size_16", "Ag", text_style(16, INK), 0, 32)
	sample(sizes, "size_24", "Ag", text_style(24, INK), 0, 42)
	sample(sizes, "size_32", "Ag", text_style(32, INK), 0, 52)
	sample(sizes, "size_48", "Ag", text_style(48, ACCENT), 0, 58)

	colours := row(column, "colours", 30)
	caption(colours, "caption_colours", "colour")
	sample(colours, "colour_red", "Red", text_style(16, GUI.RGBA(0.95, 0.42, 0.42, 1)), 0, 24)
	sample(colours, "colour_green", "Green", text_style(16, GUI.RGBA(0.40, 0.85, 0.52, 1)), 0, 24)
	sample(colours, "colour_blue", "Blue", text_style(16, GUI.RGBA(0.45, 0.65, 0.98, 1)), 0, 24)
	sample(colours, "colour_amber", "Amber", text_style(16, GUI.RGBA(0.98, 0.76, 0.30, 1)), 0, 24)
	sample(colours, "colour_violet", "Violet", text_style(16, GUI.RGBA(0.75, 0.55, 0.98, 1)), 0, 24)

	transforms := row(column, "transforms", 30)
	caption(transforms, "caption_transforms", "transform")
	sample(transforms, "transform_upper", "upper case", GUI.Style{text = GUI.Text_Style{colour = INK, size = 16, family = family, transform = .Upper}}, 0, 24)
	sample(transforms, "transform_lower", "LOWER CASE", GUI.Style{text = GUI.Text_Style{colour = INK, size = 16, family = family, transform = .Lower}}, 0, 24)
	sample(transforms, "transform_capitalize", "each word capitalized", GUI.Style{text = GUI.Text_Style{colour = INK, size = 16, family = family, transform = .Capitalize}}, 0, 24)

	aligns := row(column, "alignment", 46)
	caption(aligns, "caption_alignment", "align")
	sample(aligns, "align_left", "Left", boxed_style(15, INK, .Left), 180, 40)
	sample(aligns, "align_center", "Center", boxed_style(15, INK, .Center), 180, 40)
	sample(aligns, "align_right", "Right", boxed_style(15, INK, .Right), 180, 40)
	sample(aligns, "align_fill", "a b c\nd e f", boxed_style(15, INK, .Fill), 180, 40)

	wraps := row(column, "wrapping", 96)
	caption(wraps, "caption_wrapping", "wrap")
	sample(
		wraps,
		"wrap_word",
		"The words of this text break at the spaces, so every line ends on a word.",
		boxed_style(15, INK, .Left, .Word),
		360,
		84,
	)
	sample(
		wraps,
		"wrap_anywhere",
		"Textthatbreaksanywhereeveninsidethewordswhensomewordistoolong",
		boxed_style(15, INK, .Left, .Anywhere),
		360,
		84,
	)

	overruns := row(column, "overrun", 46)
	caption(overruns, "caption_overrun", "overrun")
	ellipsis_label := sample(
		overruns,
		"overrun_ellipsis",
		"A line that is far longer than its box",
		boxed_style(15, INK, .Left),
		220,
		40,
	)
	ellipsis_style := GUI.Widget_Get(g, ellipsis_label).style
	ellipsis_style.text.overrun = .Ellipsis
	ellipsis_style.text.clip = true
	GUI.Widget_Set_Style(g, ellipsis_label, ellipsis_style)
	words_label := sample(
		overruns,
		"overrun_words",
		"This line ends on whole words and loses the rest",
		boxed_style(15, INK, .Left),
		220,
		40,
	)
	words_style := GUI.Widget_Get(g, words_label).style
	words_style.text.overrun = .Words
	words_style.text.clip = true
	GUI.Widget_Set_Style(g, words_label, words_style)
	sample(
		overruns,
		"overrun_none",
		"No cut: this line runs past the box",
		boxed_style(15, INK, .Left),
		220,
		40,
	)

	spacing := row(column, "spacing", 70)
	caption(spacing, "caption_spacing", "spacing")
	sample(
		spacing,
		"spacing_0",
		"One two three four five six seven eight",
		boxed_style(15, INK, .Left, .Word),
		360,
		60,
	)
	spacing_style := boxed_style(15, INK, .Left, .Word)
	spacing_style.text.spacing = 6
	sample(
		spacing,
		"spacing_6",
		"One two three four five six seven eight",
		spacing_style,
		360,
		60,
	)

	decorations := row(column, "decorations", 44)
	caption(decorations, "caption_decorations", "decoration")
	sample(
		decorations,
		"outline",
		"Outline",
		GUI.Style{text = GUI.Text_Style{colour = INK, size = 24, family = family, outline_colour = GUI.RGBA(0.20, 0.24, 0.32, 1), outline_size = 2}},
		0,
		36,
	)
	sample(
		decorations,
		"shadow",
		"Shadow",
		GUI.Style{text = GUI.Text_Style{colour = INK, size = 24, family = family, shadow_colour = GUI.RGBA(0, 0, 0, 0.65), shadow_offset = GUI.Vec2{2, 2}}},
		0,
		36,
	)
	sample(
		decorations,
		"outline_shadow",
		"Both",
		GUI.Style{text = GUI.Text_Style{colour = ACCENT, size = 24, family = family, outline_colour = GUI.RGBA(0.05, 0.06, 0.08, 1), outline_size = 2, shadow_colour = GUI.RGBA(0, 0, 0, 0.65), shadow_offset = GUI.Vec2{3, 3}}},
		0,
		36,
	)

	paragraphs := row(column, "rich_text", 130)
	caption(paragraphs, "caption_rich_text", "rich text")
	GUI.Make_Rich_Text_Label(
		g,
		paragraphs,
		GUI.Rich_Text_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "rich_paragraph",
				min_size = GUI.Vec2{620, 120},
				fixed = true,
				style = boxed_style(15, INK, .Left, .Word),
			},
			text = "A rich text label wraps a paragraph of any length. The height of the label follows the number of lines it takes, so a long paragraph makes a taller widget and the scroll container gives it room.",
		},
	)

	editing := row(column, "editing", 130)
	caption(editing, "caption_editing", "editing")
	GUI.Make_Text_Box(
		g,
		editing,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "multiline_box",
				min_size = GUI.Vec2{620, 120},
				max_size = GUI.Vec2{620, 120},
				fixed = true,
				style = boxed_style(14, INK, .Left, .Word),
			},
			text = "A text box holds the text of a file.\nEvery line is edited, selected, cut and pasted.\nThe box wraps the text and scrolls when it overflows.",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)

	editor := row(column, "editor", 130)
	caption(editor, "caption_editor", "editor")
	GUI.Make_Rich_Text_Editor(
		g,
		editor,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "rich_editor",
				min_size = GUI.Vec2{620, 120},
				max_size = GUI.Vec2{620, 120},
				fixed = true,
				style = boxed_style(14, INK, .Left, .Word),
			},
			text = "The rich text editor keeps the text of the file and more than one cursor. The caret moves through the shaped text, and a selection is drawn from the same caret data.",
			wrap = true,
		},
	)

	themed := row(column, "themed_text", 46)
	caption(themed, "caption_themed", "theme")
	GUI.Make_Button(
		g,
		themed,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "themed_button", use_theme = true},
			text = "A themed button",
		},
	)
	GUI.Make_Check_Box(
		g,
		themed,
		GUI.Check_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "themed_check", use_theme = true},
			text = "A themed check box",
			on = true,
		},
	)
}
