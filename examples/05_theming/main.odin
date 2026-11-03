//* == Theming ==
//* A theme holds the look of every kind of widget. This one gives the
//* buttons rounded corners, a colour of their own and a variation for
//* the dangerous ones.

package main

import "core:log"
import common "../common"
import GUI "../../src/GUI"

g: ^GUI.GUI

main :: proc() {
	common.Run(
		"CalcUI - Theming",
		640,
		320,
		proc(app: ^common.App) {
			g = app.gui
			GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

			theme := GUI.Theme_Make()
			theme.family = app.family
			theme.size = common.BODY_SIZE

			//* The style of a button: a rounded box with a border.
			GUI.Theme_Set_Type(
				theme,
				.Button,
				GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.18, 0.20, 0.26, 1),
						border_color = {GUI.RGBA(0.28, 0.30, 0.36, 1), GUI.RGBA(0.28, 0.30, 0.36, 1), GUI.RGBA(0.28, 0.30, 0.36, 1), GUI.RGBA(0.28, 0.30, 0.36, 1)},
						border_width = {1, 1, 1, 1},
						corner_radius = {6, 6, 6, 6},
						content_margin = {12, 6, 12, 6},
						anti_aliasing = true,
					},
					text = GUI.Text_Style{colour = GUI.RGBA(0.92, 0.94, 0.98, 1)},
				},
			)

			//* A button under the pointer is a little brighter.
			GUI.Theme_Set_State(
				theme,
				.Button,
				.Hovered,
				GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.26, 0.30, 0.38, 1),
					},
				},
			)

			//* A variation of the button: the dangerous ones.
			GUI.Theme_Add_Variation(
				theme,
				"danger",
				.Button,
				GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.55, 0.14, 0.16, 1),
						border_color = {GUI.RGBA(0.75, 0.24, 0.26, 1), GUI.RGBA(0.75, 0.24, 0.26, 1), GUI.RGBA(0.75, 0.24, 0.26, 1), GUI.RGBA(0.75, 0.24, 0.26, 1)},
						border_width = {1, 1, 1, 1},
						corner_radius = {6, 6, 6, 6},
						content_margin = {12, 6, 12, 6},
						anti_aliasing = true,
					},
				},
			)

			GUI.GUI_Set_Theme(g, theme)

			box := GUI.Make_HBox(
				g,
				g.root,
				GUI.Box_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "buttons",
						offsets = GUI.Offset{left = 24, top = 24, right = -24, bottom = 80},
						separation = 12,
					},
				},
			)

			GUI.Make_Button(
				g,
				box,
				GUI.Button_Opts{
					Base_Opts = GUI.Base_Opts{name = "ok", use_theme = true},
					text = "OK",
				},
			)
			GUI.Make_Button(
				g,
				box,
				GUI.Button_Opts{
					Base_Opts = GUI.Base_Opts{name = "cancel", use_theme = true},
					text = "Cancel",
				},
			)
			GUI.Make_Button(
				g,
				box,
				GUI.Button_Opts{
					Base_Opts = GUI.Base_Opts{name = "delete", use_theme = true, variation = "danger"},
					text = "Delete",
				},
			)
		},
		nil,
	)
	log.info("the theming example is done")
}
