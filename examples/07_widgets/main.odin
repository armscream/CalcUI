//* == The widgets Godot does not have ==
//* The widgets that came after the Godot core controls: the fields,
//* the collections and the overlays.
//
//* Every one of them is in a group of its own, so that the example can
//* be read as a list of what a program can put on the screen.

package main

import "core:log"
import common "../common"
import GUI "../../src/GUI"

g: ^GUI.GUI
toast: GUI.Widget_ID
palette: GUI.Widget_ID
table: GUI.Widget_ID
list: GUI.Widget_ID

main :: proc() {
	common.Run(
		"CalcUI - The widgets",
		900,
		620,
		proc(app: ^common.App) {
			g = app.gui
			GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

			//* The fields.
			fields := GUI.Make_VBox(
				g,
				g.root,
				GUI.Box_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "fields",
						offsets = GUI.Offset{left = 20, top = 20, right = 440, bottom = -20},
						separation = 10,
					},
				},
			)

			GUI.Make_Combo_Box(
				g,
				fields,
				GUI.Combo_Box_Opts{
					Base_Opts = GUI.Base_Opts{name = "combo"},
					items = {"Red", "Green", "Blue"},
				},
			)

			GUI.Make_Search_Field(
				g,
				fields,
				GUI.Search_Field_Opts{
					Base_Opts = GUI.Base_Opts{name = "search"},
					placeholder = "Search",
				},
			)

			GUI.Make_Number_Input(
				g,
				fields,
				GUI.Number_Input_Opts{
					Base_Opts = GUI.Base_Opts{name = "number"},
					value = 12,
					min = 0,
					max = 100,
				},
			)

			GUI.Make_Date_Picker(
				g,
				fields,
				GUI.Date_Picker_Opts{
					Base_Opts = GUI.Base_Opts{name = "date"},
				},
			)

			GUI.Make_Time_Picker(
				g,
				fields,
				GUI.Time_Picker_Opts{
					Base_Opts = GUI.Base_Opts{name = "time"},
				},
			)

			GUI.Make_Rating(
				g,
				fields,
				GUI.Rating_Opts{
					Base_Opts = GUI.Base_Opts{name = "rating"},
					value = 3,
					max = 5,
				},
			)

			GUI.Make_Segmented(
				g,
				fields,
				GUI.Segmented_Opts{
					Base_Opts = GUI.Base_Opts{name = "segmented"},
					items = {"Day", "Week", "Month"},
				},
			)

			GUI.Make_Toggle_Switch(
				g,
				fields,
				GUI.Toggle_Switch_Opts{
					Base_Opts = GUI.Base_Opts{name = "switch"},
					text = "Notifications",
					on = true,
				},
			)

			//* The collections.
			collections := GUI.Make_VBox(
				g,
				g.root,
				GUI.Box_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "collections",
						offsets = GUI.Offset{left = 460, top = 20, right = -20, bottom = 340},
						separation = 10,
					},
				},
			)

			table = GUI.Make_Data_Table(
				g,
				collections,
				GUI.Data_Table_Opts{
					Base_Opts = GUI.Base_Opts{name = "table", min_size = GUI.Vec2{0, 140}},
				},
			)
			GUI.data_table_add_column(g, table, "Name", 140)
			GUI.data_table_add_column(g, table, "Size", 80)
			GUI.data_table_add_row(g, table, {"Cargo.toml", "3 KiB"})
			GUI.data_table_add_row(g, table, {"README.md", "1 KiB"})
			GUI.data_table_add_row(g, table, {"main.odin", "12 KiB"})

			list = GUI.Make_Virtual_List(
				g,
				collections,
				GUI.Virtual_List_Opts{
					Base_Opts = GUI.Base_Opts{name = "list", min_size = GUI.Vec2{0, 140}},
					count = 100000,
				},
			)

			GUI.Make_Color_Picker(
				g,
				collections,
				GUI.Color_Picker_Opts{
					Base_Opts = GUI.Base_Opts{name = "colour"},
				},
			)

			GUI.Make_Emoji_Picker(
				g,
				collections,
				GUI.Emoji_Picker_Opts{
					Base_Opts = GUI.Base_Opts{name = "emoji"},
				},
			)

			//* The overlays.
			toast = GUI.Make_Toast(
				g,
				g.root,
				GUI.Toast_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "toast",
						offsets = GUI.Offset{left = 20, top = 560, right = 360, bottom = 600},
					},
					text = "Saved",
				},
			)

			palette = GUI.Make_Command_Palette(
				g,
				g.root,
				GUI.Command_Palette_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "palette",
						offsets = GUI.Offset{left = 120, top = 80, right = 600, bottom = 400},
					},
				},
			)

			//* The commands of the program are the ones of the palette.
			GUI.command_add(g, "Save", GUI.Shortcut{key = .S, mods = GUI.Mods{.Ctrl}}, on_save)
			GUI.command_add(g, "Open", GUI.Shortcut{key = .O, mods = GUI.Mods{.Ctrl}}, on_open)
			GUI.command_add(g, "Quit", GUI.Shortcut{key = .Q, mods = GUI.Mods{.Ctrl}}, on_quit)

			GUI.Make_Accordion(
				g,
				g.root,
				GUI.Accordion_Opts{
					Base_Opts = GUI.Base_Opts{
						name = "accordion",
						offsets = GUI.Offset{left = 460, top = 360, right = -20, bottom = 600},
					},
				},
			)
		},
		nil,
	)
	log.info("the widgets example is done")
}

on_save :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	log.info("save")
}

on_open :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	log.info("open")
}

on_quit :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	g.quit_requested = true
}
