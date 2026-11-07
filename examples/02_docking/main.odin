//* == Docking ==
//* Two panels with title bars. Drag one onto the other to dock it: the
//* edges split them, the middle makes them share a tab strip, and Ctrl
//* while dropping in the middle swaps the two panels around.

package main

import "core:log"
import common "../common"
import GUI "../../src/GUI"

g: ^GUI.GUI

main :: proc() {
	common.Run(
		"CalcUI - Docking",
		800,
		520,
		proc(app: ^common.App) {
			g = app.gui
			root_style := GUI.Widget_Get(g, g.root).style
			root_style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)
			GUI.Widget_Set_Style(g, g.root, root_style)

			split := GUI.Make_Split(
				g,
				g.root,
				GUI.Split_Opts{
					Base_Opts = GUI.Base_Opts{name = "main"},
					direction = .Horizontal,
				},
			)

			GUI.Make_Panel(
				g,
				split,
				GUI.Panel_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "left",
						draggable = true,
						weight = 1,
						style = GUI.Style{
							box = GUI.StyleBox{
								bg_color = GUI.RGBA(0.12, 0.14, 0.20, 1),
								border_color = {GUI.RGBA(0.22, 0.24, 0.30, 1), GUI.RGBA(0.22, 0.24, 0.30, 1), GUI.RGBA(0.22, 0.24, 0.30, 1), GUI.RGBA(0.22, 0.24, 0.30, 1)},
								border_width = {1, 1, 1, 1},
								content_margin = {12, 12, 12, 12},
							},
						},
					},
				},
			)

			GUI.Make_Panel(
				g,
				split,
				GUI.Panel_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "right",
						draggable = true,
						weight = 1,
						style = GUI.Style{
							box = GUI.StyleBox{
								bg_color = GUI.RGBA(0.18, 0.14, 0.14, 1),
								border_color = {GUI.RGBA(0.30, 0.22, 0.22, 1), GUI.RGBA(0.30, 0.22, 0.22, 1), GUI.RGBA(0.30, 0.22, 0.22, 1), GUI.RGBA(0.30, 0.22, 0.22, 1)},
								border_width = {1, 1, 1, 1},
								content_margin = {12, 12, 12, 12},
							},
						},
					},
				},
			)
		},
		nil,
	)
	log.info("the docking example is done")
}
