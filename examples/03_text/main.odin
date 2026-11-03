//* == Text ==
//* The text of CalcUI: the sizes, the colours, the alignment, the
//* wrapping and the outline.

package main

import "core:fmt"
import "core:log"
import common "../common"
import GUI "../../src/GUI"

g: ^GUI.GUI

main :: proc() {
	common.Run(
		"CalcUI - Text",
		720,
		480,
		proc(app: ^common.App) {
			g = app.gui
			GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

			box := GUI.Make_VBox(
				g,
				g.root,
				GUI.Box_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "text",
						offsets = GUI.Offset{left = 20, top = 20, right = -20, bottom = -20},
						separation = 12,
					},
				},
			)

			sizes := [4]int{12, 16, 24, 32}
	for size in sizes {
				GUI.Make_Label(
					g,
					box,
					GUI.Label_Opts{
						Base_Opts = GUI.Base_Opts{
							name = fmt_label(size),
							//* The size of the text is part of the style,
							//* so every sample is drawn at its own size.
							style = GUI.Style{
								text = GUI.Text_Style{size = f32(size)},
							},
						},
						text = fmt_text(size),
					},
				)
			}

			GUI.Make_Label(
				g,
				box,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{name = "aligned"},
					text = "Left aligned",
				},
			)
			GUI.Make_Label(
				g,
				box,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "centred",
						style = GUI.Style{
							text = GUI.Text_Style{
								align = .Center,
								colour = GUI.RGBA(0.55, 0.75, 1.0, 1),
							},
						},
					},
					text = "Centred",
				},
			)
			GUI.Make_Label(
				g,
				box,
				GUI.Label_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "wrapped",
						style = GUI.Style{
							text = GUI.Text_Style{wrap = .Word},
						},
					},
					text = "A piece of text that is long enough to be wrapped, so that the " +
						"wrapping of the text can be seen.",
				},
			)
		},
		nil,
	)
	log.info("the text example is done")
}

fmt_label :: proc(size: int) -> string {
	return fmt.tprintf("size_%d", size)
}

fmt_text :: proc(size: int) -> string {
	return fmt.tprintf("The quick brown fox at %d pixels", size)
}
