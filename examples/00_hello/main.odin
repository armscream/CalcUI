//* == Hello ==
//* The smallest program that uses CalcUI: a window with a label, a
//* button and a text field in it.

package main

import "core:log"
import common "../common"
import GUI "../../src/GUI"

g: ^GUI.GUI
clicks: int

main :: proc() {
	common.Run(
		"CalcUI - Hello",
		520,
		240,
		proc(app: ^common.App) {
			g = app.gui

			GUI.Make_Label(
				g,
				g.root,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "title",
						offsets = GUI.Offset{left = 16, top = 16, right = -16},
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
						offsets = GUI.Offset{left = 16, top = 52, right = 140, bottom = 84},
					},
					text = "Press me",
					on_pressed = on_press,
				},
			)

			GUI.Make_Text_Input(
				g,
				g.root,
				GUI.Text_Input_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "name",
						offsets = GUI.Offset{left = 16, top = 100, right = -16, bottom = 132},
					},
					text = "type here",
				},
			)
		},
		nil,
	)
	log.info("the hello example is done")
}

on_press :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	clicks += 1
	log.infof("the button was pressed %d times", clicks)
}
