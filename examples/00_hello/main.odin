//* == Hello ==
//* The smallest program that uses CalcUI: a window with a label, a
//* button and a text field in it. The button counts its presses and the
//* count is shown next to it. Every widget takes the size of its text.
package main

import "core:fmt"
import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

g: ^GUI.GUI
clicks: int
count_label: GUI.Widget_ID

main :: proc() {
	App.Run(
		"CalcUI - Hello",
		420,
		180,
		proc(app: ^App.App) {
			g = app.gui

			GUI.Make_Label(
				g,
				g.root,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "title",
						offsets = GUI.Offset{left = 16, top = 16, right = -16, bottom = 40},
					},
					text = "Hello, CalcUI",
				},
			)

			GUI.Make_Button(
				g,
				g.root,
				GUI.Button_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "press",
						offsets = GUI.Offset{left = 16, top = 52, right = -16, bottom = 84},
					},
					text = "Press me",
					on_pressed = on_press,
				},
			)

			count_label = GUI.Make_Label(
				g,
				g.root,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "count",
						offsets = GUI.Offset{left = 16, top = 92, right = -16, bottom = 116},
					},
					text = "0 presses",
				},
			)

			GUI.Make_Text_Box(
				g,
				g.root,
				GUI.Text_Box_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "name",
						offsets = GUI.Offset{left = 16, top = 124, right = -16, bottom = 156},
					},
					text = "type here",
				},
			)
		},
		proc(app: ^App.App) {
			GUI.Widget_Set_Text(app.gui, count_label, fmt.tprintf("%d presses", clicks))
		},
	)
	log.info("the hello example is done")
}

on_press :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	clicks += 1
	log.infof("the button was pressed %d times", clicks)
}
