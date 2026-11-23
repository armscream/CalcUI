//* == Overlays ==
//* A panel that is torn out of the tree gets a window of its own. The
//* platform gives the window, the toolkit keeps the position of it, so
//* the panel can be dragged anywhere on the screen.
package main

import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

g: ^GUI.GUI
panel: GUI.Widget_ID
float_index: int = GUI.FLOAT_NONE

main :: proc() {
	App.Run(
		"CalcUI - Overlays",
		720,
		420,
		proc(app: ^App.App) {
			g = app.gui
			GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

			row := GUI.Make_HBox(
				g,
				g.root,
				GUI.Box_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "row",
						offsets = GUI.Offset{left = 16, top = 16, right = -16, bottom = 56},
						separation = 12,
					},
				},
			)

			GUI.Make_Button(
				g,
				row,
				GUI.Button_Opts{
					Base_Opts = GUI.Base_Opts{name = "detach"},
					text = "Tear the panel out",
					on_pressed = on_detach,
				},
			)

			GUI.Make_Label(
				g,
				row,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{name = "state"},
					text = "the panel is in the window",
				},
			)

			panel = GUI.Make_Panel(
				g,
				g.root,
				GUI.Panel_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "detachable",
						offsets = GUI.Offset{left = 16, top = 72, right = -16, bottom = -16},
					},
				},
			)

			GUI.Make_Label(
				g,
				panel,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{name = "inside", offsets = GUI.Offset{left = 12, top = 12}},
					text = "This panel has a window of its own once it is torn out.",
				},
			)

			make_floating_panel()
		},
		nil,
	)
	log.info("the overlays example is done")
}

make_floating_panel :: proc() {
	other := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "floating",
				offsets = GUI.Offset{left = 16, top = 16, right = 240, bottom = 120},
			},
		},
	)

	GUI.Make_Label(
		g,
		other,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{name = "text", offsets = GUI.Offset{left = 8, top = 8}},
			text = "A panel in a window of its own.",
		},
	)

	GUI.Make_Float_Panel(g, other, GUI.Vec2{120, 120}, GUI.Vec2{280, 160})
}

on_detach :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	if float_index != GUI.FLOAT_NONE { return }
	float_index = GUI.Make_Float_Panel(g, panel, GUI.Vec2{260, 140}, GUI.Vec2{320, 220})
	if float_index == GUI.FLOAT_NONE { return }

	for child in GUI.Widget_Children(g, g.root) {
		if child == panel { continue }
		if GUI.Widget_Get(g, child).name != "state" { continue }
		GUI.Widget_Set_Text(g, child, "the panel is in a window of its own")
	}
}
