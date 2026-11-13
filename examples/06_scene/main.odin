//* == Scene ==
// It is possible to load the scene from a string, which could be loaded from file. 
// This example doesnt show how to load from a file - just a string, you can unmarshal from
// json or your preferred format quite easily.

package main

import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

g: ^GUI.GUI

//* The scene: a panel with a title, a button and a field.
SCENE :: `
[node name="Root" type="Panel"]
    bg = {0.07, 0.08, 0.10, 1}

    [node name="Title" type="Label" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {20, 20, -20, 56}
        text = "A scene"
        font_size = 24
        colour = {0.92, 0.94, 0.98, 1}

    [node name="Press" type="Button" parent="Root"]
        anchors = {0, 0, 0, 0}
        offsets = {20, 72, 160, 108}
        text = "Press me"

    [node name="Name" type="TextBox" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {20, 124, -20, 160}
        text = "your name"
`

main :: proc() {
	App.Run(
		"CalcUI",
		720,
		420,
		proc(app: ^App.App) {
			g = app.gui

			//* The theme gives every widget its look. The argument says
			//* whether the dark one is wanted.
			GUI.default_theme_use(g, true)

			root := GUI.Scene_Load(g, SCENE)
			if root == GUI.INVALID_WIDGET_ID {
				log.error("the scene did not load")
				return
			}
		},
		nil,
	)
	log.info("the scene example is done")
}
