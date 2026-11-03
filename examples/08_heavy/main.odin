//* == The heavy features ==
//* The things that are more than a widget: the charts, the graph, the
//* canvas, the drawings, the files and the editor.

package main

import "core:log"
import common "../common"
import GUI "../../src/GUI"

g: ^GUI.GUI
chart: GUI.Widget_ID
graph: GUI.Widget_ID

main :: proc() {
	common.Run(
		"CalcUI - The heavy features",
		960,
		640,
		proc(app: ^common.App) {
			g = app.gui
			GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

			//* A chart with two series.
			chart = GUI.Make_Chart(
				g,
				g.root,
				GUI.Chart_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "chart",
						offsets = GUI.Offset{left = 20, top = 20, right = 460, bottom = 300},
					},
					kind = .Bar,
				},
			)
			GUI.chart_add_series(
				g,
				chart,
				"Monday",
				{12, 18, 9, 24, 15},
				GUI.RGBA(0.25, 0.60, 1.00, 1),
			)
			GUI.chart_add_series(
				g,
				chart,
				"Tuesday",
				{8, 14, 12, 19, 11},
				GUI.RGBA(0.95, 0.55, 0.20, 1),
			)

			//* A graph with three nodes and a wire between two of them.
			graph = GUI.Make_Node_Graph(
				g,
				g.root,
				GUI.Node_Graph_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "graph",
						offsets = GUI.Offset{left = 480, top = 20, right = -20, bottom = 300},
					},
				},
			)
			first := GUI.node_graph_add_node(g, graph, "Read", GUI.Vec2{40, 40})
			second := GUI.node_graph_add_node(g, graph, "Shape", GUI.Vec2{220, 120})
			out := GUI.node_graph_add_port(g, graph, first, "out", .Output)
			in := GUI.node_graph_add_port(g, graph, second, "in", .Input)
			GUI.node_graph_connect(g, graph, first, out, second, in)

			//* A canvas the program draws in itself.
			GUI.Make_Canvas(
				g,
				g.root,
				GUI.Canvas_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "canvas",
						offsets = GUI.Offset{left = 20, top = 320, right = 460, bottom = 620},
					},
				},
			)

			//* A drawing whose shapes can be pulled around.
			GUI.Make_Vector_Drawing(
				g,
				g.root,
				GUI.Vector_Drawing_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "drawing",
						offsets = GUI.Offset{left = 480, top = 320, right = 720, bottom = 620},
					},
				},
			)

			//* The files of a directory.
			GUI.Make_File_Viewer(
				g,
				g.root,
				GUI.File_Viewer_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "files",
						offsets = GUI.Offset{left = 740, top = 320, right = -20, bottom = 620},
					},
				},
			)

			//* A text with more than one cursor.
			GUI.Make_Rich_Text_Editor(
				g,
				g.root,
				GUI.Rich_Text_Editor_Opts{
					Base_Opts = GUI.Base_Opts{name = "editor", hidden = true},
					text = "The text of the editor.",
				},
			)
		},
		nil,
	)
	log.info("the heavy example is done")
}
