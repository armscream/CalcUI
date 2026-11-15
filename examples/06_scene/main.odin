package main

import "core:fmt"
import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

g: ^GUI.GUI
family: GUI.Font_Family_ID
save_status: GUI.Widget_ID
save_buf: [96]u8

SCENE :: `
[node name="Root" type="Panel"]
    bg = {0.07, 0.08, 0.10, 1}

    [node name="Title" type="Label" parent="Root"]
        anchors = {0, 0, 0, 0}
        offsets = {28, 16, 520, 56}
        text = "A scene, loaded and themed"
        font_size = 26
        colour = {0.92, 0.94, 0.98, 1}

    [node name="Subtitle" type="Label" parent="Root"]
        anchors = {0, 0, 0, 0}
        offsets = {28, 58, 880, 92}
        text = "The tree below comes from a scene file. The code adds the theme, the transitions and the two tweens."
        font_size = 14
        colour = {0.52, 0.56, 0.64, 1}

    [node name="Body" type="Panel" parent="Root"]
        anchors = {0, 0, 1, 1}
        offsets = {28, 104, -28, -72}
        bg = {0.10, 0.12, 0.16, 1}
        border = {0.25, 0.28, 0.35, 1}
        border_width = 1
        padding = {18, 18, 18, 18}

        [node name="Press" type="Button" parent="Body"]
            anchors = {0, 0, 0, 0}
            offsets = {18, 18, 218, 54}
            text = "Press me"

        [node name="Name" type="TextBox" parent="Body"]
            anchors = {0, 0, 1, 0}
            offsets = {234, 18, -18, 54}
            text = "a value from the scene"

        [node name="Agree" type="CheckBox" parent="Body"]
            anchors = {0, 0, 0, 0}
            offsets = {18, 66, 338, 98}
            text = "The check box takes the theme"
            interactive = true

        [node name="Progress" type="ProgressBar" parent="Body"]
            anchors = {0, 0, 1, 0}
            offsets = {354, 70, -18, 94}
            colour = {0.30, 0.62, 1.0, 1}

        [node name="Swatch" type="ColorRect" parent="Body"]
            anchors = {0, 0, 0, 0}
            offsets = {18, 112, 138, 212}
            colour = {0.30, 0.62, 1.0, 1}

        [node name="Note" type="RichTextLabel" parent="Body"]
            anchors = {0, 0, 0, 0}
            offsets = {154, 112, 700, 212}
            text = "A rich text label wraps a paragraph: a scene can carry a whole form, its labels, its fields, its progress and its colour, and the code that loads it only has to name the nodes it wants to animate."
            font_size = 15
            colour = {0.82, 0.86, 0.93, 1}

        [node name="Second" type="ToggleSwitch" parent="Body"]
            anchors = {0, 0, 0, 0}
            offsets = {18, 226, 300, 262}
            text = "A toggle switch"
            interactive = true

        [node name="SecondLabel" type="Label" parent="Body"]
            anchors = {0, 0, 0, 0}
            offsets = {316, 230, 860, 258}
            text = "Every node keeps its name, so the code can find it again."
            font_size = 14
            colour = {0.60, 0.64, 0.72, 1}

    [node name="Footer" type="Label" parent="Root"]
        anchors = {0, 1, 0, 1}
        offsets = {28, -64, 520, -40}
        text = "The footer is part of the same scene."
        font_size = 13
        colour = {0.48, 0.52, 0.60, 1}
`

main :: proc() {
	App.Run("CalcUI - Scene", 900, 600, setup, nil)
	log.info("the scene example is done")
}

setup :: proc(app: ^App.App) {
	g = app.gui
	family = app.family
	GUI.Default_Theme_Use(g, true)

	root := GUI.Scene_Load(g, SCENE)
	if root == GUI.INVALID_WIDGET_ID {
		log.error("the scene did not load")
		return
	}
	scene_theme(g, family, root)

	progress := find(g, root, "Progress")
	if progress != GUI.INVALID_WIDGET_ID {
		GUI.progress_bar_set_value(g, progress, 68)
	}
	swatch := find(g, root, "Swatch")
	if swatch != GUI.INVALID_WIDGET_ID {
		GUI.color_rect_set_colour(g, swatch, GUI.RGBA(0.30, 0.62, 1.0, 1))
	}

	GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "save_scene",
				preset = .Bottom_Right,
				anchors = GUI.Anchor{1, 1, 1, 1},
				offsets = GUI.Offset{left = -184, top = -46, right = -28, bottom = -16},
				use_theme = true,
				tooltip = "Scene_Save writes the tree back to scene text.",
			},
			text = "Save the scene",
			on_pressed = on_save,
		},
	)
	save_status = GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "save_status",
				preset = .Bottom_Right,
				anchors = GUI.Anchor{1, 1, 1, 1},
				offsets = GUI.Offset{left = -620, top = -42, right = -196, bottom = -20},
				style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(0.52, 0.56, 0.64, 1), align = .Right, valign = .Center}},
			},
			text = "The tree has not been written yet.",
		},
	)
}

find :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, name: string) -> GUI.Widget_ID {
	w := GUI.Widget_Get(g, id)
	if w == nil {return GUI.INVALID_WIDGET_ID}
	if w.name == name {return id}
	child := w.first_child
	for child != GUI.INVALID_WIDGET_ID {
		c := GUI.Widget_Get(g, child)
		if c == nil {break}
		if found := find(g, child, name); found != GUI.INVALID_WIDGET_ID {return found}
		child = c.next_sibling
	}
	return GUI.INVALID_WIDGET_ID
}

scene_theme :: proc(g: ^GUI.GUI, body: GUI.Font_Family_ID, root: GUI.Widget_ID) {
	theme := g.theme
	if theme != nil {
		GUI.Theme_Set_Family(theme, body)
		GUI.Theme_Set_Size(theme, 15)
		GUI.Theme_Set_Type(
			theme,
			.Panel,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = GUI.RGBA(0.10, 0.12, 0.16, 1),
					border_color = {GUI.RGBA(0.25, 0.28, 0.35, 1), GUI.RGBA(0.25, 0.28, 0.35, 1), GUI.RGBA(0.25, 0.28, 0.35, 1), GUI.RGBA(0.25, 0.28, 0.35, 1)},
					border_width = {1, 1, 1, 1},
					corner_radius = {10, 10, 10, 10},
					content_margin = {12, 12, 12, 12},
				},
				text = GUI.Text_Style{colour = GUI.RGBA(0.86, 0.89, 0.95, 1)},
				transition = GUI.Style_Transition{duration = 0.20, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = GUI.RGBA(0.24, 0.43, 0.86, 1),
					border_color = {GUI.RGBA(0.36, 0.57, 1.00, 1), GUI.RGBA(0.36, 0.57, 1.00, 1), GUI.RGBA(0.36, 0.57, 1.00, 1), GUI.RGBA(0.36, 0.57, 1.00, 1)},
					border_width = {1, 1, 1, 1},
					corner_radius = {7, 7, 7, 7},
					content_margin = {12, 7, 12, 7},
				},
				text = GUI.Text_Style {
					colour = GUI.RGBA(1, 1, 1, 1),
					hover_colour = GUI.RGBA(1, 0.96, 0.78, 1),
					pressed_colour = GUI.RGBA(0.86, 0.92, 1, 1),
					disabled_colour = GUI.RGBA(0.52, 0.56, 0.64, 1),
					focus_colour = GUI.RGBA(0.74, 0.86, 1, 1),
					align = .Center,
					valign = .Center,
				},
				transition = GUI.Style_Transition{duration = 0.14, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.TextBox,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = GUI.RGBA(0.13, 0.15, 0.19, 1),
					border_color = {GUI.RGBA(0.26, 0.30, 0.37, 1), GUI.RGBA(0.26, 0.30, 0.37, 1), GUI.RGBA(0.26, 0.30, 0.37, 1), GUI.RGBA(0.26, 0.30, 0.37, 1)},
					border_width = {1, 1, 1, 1},
					corner_radius = {6, 6, 6, 6},
					content_margin = {8, 6, 8, 6},
				},
				text = GUI.Text_Style{colour = GUI.RGBA(0.86, 0.89, 0.95, 1), focus_colour = GUI.RGBA(0.47, 0.68, 1.0, 1)},
				transition = GUI.Style_Transition{duration = 0.14, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_Color(theme, .ProgressBar, "track_color", GUI.RGBA(0.13, 0.15, 0.19, 1))
		GUI.Theme_Set_Color(theme, .ProgressBar, "fill_color", GUI.RGBA(0.30, 0.62, 1.0, 1))
		GUI.Theme_Set_Color(theme, .HSlider, "track_color", GUI.RGBA(0.13, 0.15, 0.19, 1))
		GUI.Theme_Set_Color(theme, .HSlider, "fill_color", GUI.RGBA(0.30, 0.62, 1.0, 1))
	}

	scene_set_transition(g, root)

	body_panel := find(g, root, "Body")
	if body_panel != GUI.INVALID_WIDGET_ID {
		GUI.Animation_Start(
			g,
			GUI.Animation_Desc{
				target = body_panel,
				property = .Background,
				from = GUI.Animation_Value(GUI.RGBA(0.10, 0.12, 0.16, 1)),
				to = GUI.Animation_Value(GUI.RGBA(0.12, 0.19, 0.32, 1)),
				duration = 2.4,
				easing = .Smooth,
				repeat = -1,
				ping_pong = true,
			},
		)
	}
	title := find(g, root, "Title")
	if title != GUI.INVALID_WIDGET_ID {
		GUI.Animation_Start(
			g,
			GUI.Animation_Desc{
				target = title,
				property = .Opacity,
				from = GUI.Animation_Value(f32(1)),
				to = GUI.Animation_Value(f32(0.55)),
				duration = 1.8,
				easing = .In_Out_Sine,
				repeat = -1,
				ping_pong = true,
			},
		)
	}
}

scene_set_transition :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	w := GUI.Widget_Get(g, id)
	if w == nil {return}
	if w.use_theme && w.style.transition.duration == 0 {
		style := w.style
		style.transition = GUI.Style_Transition{duration = 0.16, easing = .Out_Cubic}
		GUI.Widget_Set_Style(g, id, style)
	}
	child := w.first_child
	for child != GUI.INVALID_WIDGET_ID {
		c := GUI.Widget_Get(g, child)
		if c == nil {break}
		scene_set_transition(g, child)
		child = c.next_sibling
	}
}

on_save :: proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
	root := find(gui, gui.root, "Root")
	if root == GUI.INVALID_WIDGET_ID {return}
	text := GUI.Scene_Save(gui, root)
	defer delete(text)
	if save_status != GUI.INVALID_WIDGET_ID {
		GUI.Widget_Set_Text(gui, save_status, fmt.bprintf(save_buf[:], "The tree is %d bytes of scene text.", len(text)))
	}
}
