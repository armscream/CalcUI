package main

import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

Mode :: enum {
	Dark,
	Light,
	Ocean,
}

Palette :: struct {
	window:      GUI.Colour,
	surface:     GUI.Colour,
	field:       GUI.Colour,
	button:      GUI.Colour,
	hover:       GUI.Colour,
	pressed:     GUI.Colour,
	border:      GUI.Colour,
	text:        GUI.Colour,
	dim:         GUI.Colour,
	accent:      GUI.Colour,
	accent2:     GUI.Colour,
	danger:      GUI.Colour,
	danger_hi:   GUI.Colour,
	success:     GUI.Colour,
	success_hi:  GUI.Colour,
}

g: ^GUI.GUI
family: GUI.Font_Family_ID
mode: Mode
status: GUI.Widget_ID
banner: GUI.Widget_ID
variant_sample: GUI.Widget_ID
variant_toggle: GUI.Widget_ID
show_danger := true

swatch_rects: [5]GUI.Widget_ID

main :: proc() {
	App.Run(
		"CalcUI - Theming",
		980,
		660,
		proc(app: ^App.App) {
			g = app.gui
			family = app.family
			build()
			apply_mode(.Dark)
		},
		nil,
	)
	log.info("the theming example is done")
}

palette :: proc(mode: Mode) -> Palette {
	switch mode {
	case .Dark:
		return Palette {
			window = GUI.RGBA(0.07, 0.08, 0.10, 1),
			surface = GUI.RGBA(0.10, 0.12, 0.16, 1),
			field = GUI.RGBA(0.13, 0.15, 0.19, 1),
			button = GUI.RGBA(0.17, 0.19, 0.24, 1),
			hover = GUI.RGBA(0.24, 0.28, 0.35, 1),
			pressed = GUI.RGBA(0.12, 0.14, 0.18, 1),
			border = GUI.RGBA(0.25, 0.28, 0.35, 1),
			text = GUI.RGBA(0.88, 0.91, 0.96, 1),
			dim = GUI.RGBA(0.52, 0.56, 0.64, 1),
			accent = GUI.RGBA(0.30, 0.62, 1.00, 1),
			accent2 = GUI.RGBA(0.72, 0.42, 0.98, 1),
			danger = GUI.RGBA(0.58, 0.17, 0.20, 1),
			danger_hi = GUI.RGBA(0.74, 0.24, 0.28, 1),
			success = GUI.RGBA(0.15, 0.50, 0.30, 1),
			success_hi = GUI.RGBA(0.22, 0.66, 0.40, 1),
		}
	case .Light:
		return Palette {
			window = GUI.RGBA(0.90, 0.92, 0.96, 1),
			surface = GUI.RGBA(0.97, 0.98, 1.00, 1),
			field = GUI.RGBA(0.92, 0.94, 0.98, 1),
			button = GUI.RGBA(0.86, 0.89, 0.94, 1),
			hover = GUI.RGBA(0.78, 0.83, 0.92, 1),
			pressed = GUI.RGBA(0.72, 0.78, 0.88, 1),
			border = GUI.RGBA(0.74, 0.78, 0.85, 1),
			text = GUI.RGBA(0.12, 0.14, 0.18, 1),
			dim = GUI.RGBA(0.42, 0.45, 0.52, 1),
			accent = GUI.RGBA(0.16, 0.44, 0.86, 1),
			accent2 = GUI.RGBA(0.55, 0.25, 0.80, 1),
			danger = GUI.RGBA(0.78, 0.22, 0.24, 1),
			danger_hi = GUI.RGBA(0.88, 0.30, 0.32, 1),
			success = GUI.RGBA(0.16, 0.58, 0.33, 1),
			success_hi = GUI.RGBA(0.22, 0.70, 0.42, 1),
		}
	case .Ocean:
		return Palette {
			window = GUI.RGBA(0.04, 0.09, 0.11, 1),
			surface = GUI.RGBA(0.07, 0.14, 0.17, 1),
			field = GUI.RGBA(0.09, 0.17, 0.21, 1),
			button = GUI.RGBA(0.11, 0.21, 0.25, 1),
			hover = GUI.RGBA(0.15, 0.29, 0.34, 1),
			pressed = GUI.RGBA(0.08, 0.16, 0.20, 1),
			border = GUI.RGBA(0.18, 0.35, 0.40, 1),
			text = GUI.RGBA(0.82, 0.95, 0.96, 1),
			dim = GUI.RGBA(0.45, 0.66, 0.70, 1),
			accent = GUI.RGBA(0.12, 0.72, 0.68, 1),
			accent2 = GUI.RGBA(0.12, 0.48, 0.85, 1),
			danger = GUI.RGBA(0.72, 0.24, 0.26, 1),
			danger_hi = GUI.RGBA(0.86, 0.32, 0.34, 1),
			success = GUI.RGBA(0.14, 0.56, 0.42, 1),
			success_hi = GUI.RGBA(0.22, 0.72, 0.56, 1),
		}
	}
	return {}
}

build :: proc() {
	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "title",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 26, top = 18, right = 600, bottom = 52},
				use_theme = true,
				style = GUI.Style{text = GUI.Text_Style{size = 26, family = family}},
			},
			text = "Theming and motion",
		},
	)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "subtitle",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 26, top = 54, right = -26, bottom = 92},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{size = 14, family = family, wrap = .Word}},
			},
			text = "One theme decides the boxes, the ink, the states, the variations and the transition of every widget that takes it. Switch the palette and the same tree is laid out and drawn with another look.",
		},
	)

	modes := GUI.Make_HBox(
		g,
		g.root,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "modes",
				preset = .Top,
				offsets = GUI.Offset{left = 26, top = 100, right = -26, bottom = 140},
				separation = 10,
			},
		},
	)

	for entry in ([]struct {
		name: string,
		mode: Mode,
	}{{"Dark", .Dark}, {"Light", .Light}, {"Ocean", .Ocean}}) {
		GUI.Make_Button(
			g,
			modes,
			GUI.Button_Opts{
				Base_Opts = GUI.Base_Opts{
					name = entry.name,
					use_theme = true,
					min_size = GUI.Vec2{88, 30},
					fixed = true,
				},
				text = entry.name,
				on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
					switch GUI.Widget_Name(gui, id) {
					case "Dark":
						apply_mode(.Dark)
					case "Light":
						apply_mode(.Light)
					case "Ocean":
						apply_mode(.Ocean)
					}
				},
			},
		)
	}

	status = GUI.Make_Label(
		g,
		modes,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "status",
				size_flags_h = GUI.Size_Flags{.Fill},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{valign = .Center}},
			},
			text = "The dark theme is showing.",
		},
	)

	main_row := GUI.Make_HBox(
		g,
		g.root,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "main_row",
				preset = .Fill,
				offsets = GUI.Offset{left = 26, top = 152, right = -26, bottom = -58},
				separation = 14,
			},
		},
	)

	make_buttons_panel(main_row)
	make_controls_panel(main_row)
	make_colours_panel(main_row)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "footer",
				preset = .Bottom,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 26, top = -46, right = -26, bottom = -18},
				use_theme = true,
				variation = "dim",
			},
			text = "The buttons switch the theme. Hover a control to see its transition.",
		},
	)
}

make_buttons_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_panel",
				min_size = GUI.Vec2{250, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Buttons",
		},
	)

	box := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_box",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = -14},
				separation = 9,
			},
		},
	)

	GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "primary", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "Primary action",
		},
	)
	variant_sample = GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "variant_sample", use_theme = true, variation = "danger", size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A variation",
		},
	)
	variant_toggle = GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "variant_toggle", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "Switch the variation",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				show_danger = !show_danger
				if variant_sample == GUI.INVALID_WIDGET_ID {return}
				variation := show_danger ? "danger" : "success"
				GUI.Widget_Set_Variation(gui, variant_sample, variation)
				GUI.Widget_Set_Text(gui, variant_sample, show_danger ? "A danger button" : "A success button")
			},
		},
	)
	disabled := GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "disabled", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A disabled button",
		},
	)
	GUI.Widget_Set_Enabled(g, disabled, false)

	GUI.Make_Label(
		g,
		box,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_hint",
				size_flags_h = GUI.Size_Flags{.Fill},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{wrap = .Word}},
			},
			text = "The box, the ink, the margin and the corner are all in the theme.",
		},
	)
	return panel
}

make_controls_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "controls_panel",
				min_size = GUI.Vec2{280, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "controls_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Controls",
		},
	)
	box := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "controls_box",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = -14},
				separation = 10,
			},
		},
	)
	GUI.Make_Check_Box(
		g,
		box,
		GUI.Check_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "check", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A check box",
			on = true,
		},
	)
	GUI.Make_Toggle_Switch(
		g,
		box,
		GUI.Toggle_Switch_Opts{
			Base_Opts = GUI.Base_Opts{name = "toggle", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A toggle switch",
			on = true,
		},
	)
	make_text_box_field(box)
	GUI.Make_H_Slider(
		g,
		box,
		GUI.Slider_Opts{
			Base_Opts = GUI.Base_Opts{name = "slider", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 26}, fixed = true},
			value = 62,
			min = 0,
			max = 100,
		},
	)
	GUI.Make_Progress_Bar(
		g,
		box,
		GUI.Progress_Bar_Opts{
			Base_Opts = GUI.Base_Opts{name = "progress", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 16}, fixed = true},
			value = 72,
			max = 100,
		},
	)
	GUI.Make_Color_Picker(
		g,
		box,
		GUI.Color_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "color_picker", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 82}, fixed = true},
			colour = GUI.RGBA(0.30, 0.62, 1.0, 1),
		},
	)
	return panel
}

make_text_box_field :: proc(parent: GUI.Widget_ID) {
	GUI.Make_Text_Box(
		g,
		parent,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "The text box takes the field colour",
		},
	)
}
make_colours_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "colours_panel",
				min_size = GUI.Vec2{260, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "colours_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Palette",
		},
	)
	banner = GUI.Make_Panel(
		g,
		panel,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "banner",
				preset = .Top,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = 132},
			},
		},
	)
	GUI.Make_Label(
		g,
		banner,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "banner_text",
				preset = .Fill,
				offsets = GUI.Offset{left = 12, top = 12, right = -12, bottom = -12},
				style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1), size = 15, family = family, align = .Center, valign = .Center}},
			},
			text = "The banner is a tween",
		},
	)
	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "banner_button",
				preset = .Top,
				offsets = GUI.Offset{left = 14, top = 140, right = -14, bottom = 170},
				use_theme = true,
			},
			text = "A themed button",
		},
	)

	swatches := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "swatches",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 182, right = -14, bottom = -14},
				separation = 6,
			},
		},
	)
	p := palette(mode)
	swatch_rects[0] = make_swatch(swatches, "swatch_accent", "accent", p.accent)
	swatch_rects[1] = make_swatch(swatches, "swatch_accent2", "accent 2", p.accent2)
	swatch_rects[2] = make_swatch(swatches, "swatch_danger", "danger", p.danger)
	swatch_rects[3] = make_swatch(swatches, "swatch_success", "success", p.success)
	swatch_rects[4] = make_swatch(swatches, "swatch_text", "text", p.text)
	return panel
}

make_swatch :: proc(
	parent: GUI.Widget_ID,
	name, label: string,
	colour: GUI.Colour,
) -> GUI.Widget_ID {
	row := GUI.Make_HBox(
		g,
		parent,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{name = name, min_size = GUI.Vec2{0, 24}, fixed = true, separation = 8},
		},
	)
	swatch := GUI.Make_Color_Rect(
		g,
		row,
		GUI.Color_Rect_Opts{
			Base_Opts = GUI.Base_Opts{name = name, min_size = GUI.Vec2{24, 24}, fixed = true},
			colour = colour,
		},
	)
	GUI.Make_Label(
		g,
		row,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				size_flags_h = GUI.Size_Flags{.Fill},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{valign = .Center}},
			},
			text = label,
		},
	)
	return swatch
}

apply_mode :: proc(next: Mode) {
	mode = next
	p := palette(next)
	GUI.Default_Theme_Use(g, next != .Light)
	theme := g.theme
	if theme != nil {
		GUI.Theme_Set_Family(theme, family)
		GUI.Theme_Set_Size(theme, 15)

		GUI.Theme_Set_Type(
			theme,
			.Label,
			GUI.Style {
				text = GUI.Text_Style{colour = p.text},
			},
		)
		GUI.Theme_Add_Variation(
			theme,
			"dim",
			.Label,
			GUI.Style{text = GUI.Text_Style{colour = p.dim}},
		)
		GUI.Theme_Add_Variation(
			theme,
			"accent_label",
			.Label,
			GUI.Style{text = GUI.Text_Style{colour = p.accent}},
		)
		GUI.Theme_Set_Type(
			theme,
			.Panel,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.surface,
					border_color = {p.border, p.border, p.border, p.border},
					border_width = {1, 1, 1, 1},
					corner_radius = {10, 10, 10, 10},
					content_margin = {12, 12, 12, 12},
				},
				text = GUI.Text_Style{colour = p.text},
				transition = GUI.Style_Transition{duration = 0.18, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.button,
					border_color = {p.border, p.border, p.border, p.border},
					border_width = {1, 1, 1, 1},
					corner_radius = {8, 8, 8, 8},
					content_margin = {12, 7, 12, 7},
				},
				text = GUI.Text_Style {
					colour = p.text,
					hover_colour = p.text,
					pressed_colour = p.text,
					disabled_colour = p.dim,
					focus_colour = p.accent,
					align = .Center,
					valign = .Center,
				},
				transition = GUI.Style_Transition{duration = 0.15, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_State(theme, .Button, .Hovered, GUI.Style{box = GUI.StyleBox{bg_color = p.hover}})
		GUI.Theme_Set_State(theme, .Button, .Pressed, GUI.Style{box = GUI.StyleBox{bg_color = p.pressed}})
		GUI.Theme_Set_State(theme, .Button, .Disabled, GUI.Style{box = GUI.StyleBox{bg_color = p.field}})
		GUI.Theme_Set_State(
			theme,
			.Button,
			.Focused,
			GUI.Style {
				box = GUI.StyleBox{border_color = {p.accent, p.accent, p.accent, p.accent}},
				text = GUI.Text_Style{colour = p.accent},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.TextBox,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.field,
					border_color = {p.border, p.border, p.border, p.border},
					border_width = {1, 1, 1, 1},
					corner_radius = {6, 6, 6, 6},
					content_margin = {8, 6, 8, 6},
				},
				text = GUI.Text_Style {
					colour = p.text,
					disabled_colour = p.dim,
					focus_colour = p.accent,
					wrap = .Word,
				},
				transition = GUI.Style_Transition{duration = 0.15, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_State(
			theme,
			.TextBox,
			.Focused,
			GUI.Style{box = GUI.StyleBox{border_color = {p.accent, p.accent, p.accent, p.accent}}},
		)
		GUI.Theme_Set_Type(
			theme,
			.HSlider,
			GUI.Style{text = GUI.Text_Style{colour = p.accent}},
		)
		GUI.Theme_Set_Type(
			theme,
			.ProgressBar,
			GUI.Style{text = GUI.Text_Style{colour = p.text}},
		)
		GUI.Theme_Set_Color(theme, .HSlider, "track_color", p.field)
		GUI.Theme_Set_Color(theme, .HSlider, "fill_color", p.accent)
		GUI.Theme_Set_Color(theme, .ProgressBar, "track_color", p.field)
		GUI.Theme_Set_Color(theme, .ProgressBar, "fill_color", p.accent)

		GUI.Theme_Add_Variation(
			theme,
			"danger",
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.danger,
					border_color = {p.danger_hi, p.danger_hi, p.danger_hi, p.danger_hi},
					border_width = {1, 1, 1, 1},
					corner_radius = {8, 8, 8, 8},
					content_margin = {12, 7, 12, 7},
				},
				text = GUI.Text_Style{colour = GUI.RGBA(1, 0.95, 0.95, 1)},
			},
		)
		GUI.Theme_Set_Variation_State(
			theme,
			"danger",
			.Button,
			.Hovered,
			GUI.Style{box = GUI.StyleBox{bg_color = p.danger_hi}},
		)
		GUI.Theme_Add_Variation(
			theme,
			"success",
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.success,
					border_color = {p.success_hi, p.success_hi, p.success_hi, p.success_hi},
					border_width = {1, 1, 1, 1},
					corner_radius = {8, 8, 8, 8},
					content_margin = {12, 7, 12, 7},
				},
				text = GUI.Text_Style{colour = GUI.RGBA(0.94, 1, 0.95, 1)},
			},
		)
		GUI.Theme_Set_Variation_State(
			theme,
			"success",
			.Button,
			.Hovered,
			GUI.Style{box = GUI.StyleBox{bg_color = p.success_hi}},
		)
	}

	update_swatches()
	GUI.Widget_Set_Style(
		g,
		g.root,
		GUI.Style {
			box = GUI.StyleBox {
				bg_color = p.window,
			},
			text = GUI.Text_Style{colour = p.text},
		},
	)
	GUI.Widget_Set_Text(g, status, status_text(next))
	GUI.Animation_Stop_Target(g, status)
	GUI.Animation_Start(
		g,
		GUI.Animation_Desc{
			target = status,
			property = .Opacity,
			from = GUI.Animation_Value(f32(0.20)),
			to = GUI.Animation_Value(f32(1)),
			duration = 0.30,
			easing = .Out_Cubic,
		},
	)
	start_banner(p)
}

update_swatches :: proc() {
	p := palette(mode)
	GUI.color_rect_set_colour(g, swatch_rects[0], p.accent)
	GUI.color_rect_set_colour(g, swatch_rects[1], p.accent2)
	GUI.color_rect_set_colour(g, swatch_rects[2], p.danger)
	GUI.color_rect_set_colour(g, swatch_rects[3], p.success)
	GUI.color_rect_set_colour(g, swatch_rects[4], p.text)
}

status_text :: proc(m: Mode) -> string {
	switch m {
	case .Dark:
		return "The dark theme is showing."
	case .Light:
		return "The light theme is showing."
	case .Ocean:
		return "The ocean theme is showing."
	}
	return ""
}

start_banner :: proc(p: Palette) {
	if banner == GUI.INVALID_WIDGET_ID {return}
	GUI.Animation_Stop_Target(g, banner)
	GUI.Animation_Start(
		g,
		GUI.Animation_Desc{
			target = banner,
			property = .Background,
			from = GUI.Animation_Value(p.accent),
			to = GUI.Animation_Value(p.accent2),
			duration = 2.6,
			easing = .Smooth,
			repeat = -1,
			ping_pong = true,
		},
	)
}
