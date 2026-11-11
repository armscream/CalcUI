//* == Docking ==
//* A small IDE: a menu bar, a toolbar, a tree of files on the left, an
//* editor and a log in the middle, a list of properties on the right
//* and a status bar at the bottom. Every panel has a title bar, so it
//* can be dragged out of its place and docked somewhere else. The
//* toolbar does the same thing from the program side, so the docking
//* can be tried without dragging.
//*   odin run examples\02_docking

package main

import "core:fmt"
import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

g: ^GUI.GUI
body: GUI.Widget_ID
centre: GUI.Widget_ID
editor_tabs: GUI.Widget_ID
properties: GUI.Widget_ID
status: GUI.Widget_ID
message: string

//* A menu of the menu bar: the name of the menu and the items it holds.
Menu :: struct {
	name:  string,
	items: []string,
}

//* The menus of the menu bar.
menus: [3]Menu = {
	{"File", {"New", "Open", "Save"}},
	{"Edit", {"Undo", "Redo", "Cut"}},
	{"View", {"Panels", "Layout"}},
}

main :: proc() {
	App.Run(
		"CalcUI - Docking",
		1100,
		700,
		setup,
		update,
	)
	log.info("the docking example is done")
}

//* The window: the menu bar, the toolbar, the body and the status bar.
setup :: proc(app: ^App.App) {
	g = app.gui
	GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

	column := GUI.Make_VBox(
		g,
		g.root,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "app",
				separation = 0,
			},
		},
	)

	make_menu_bar(g, column)
	make_tool_bar(g, column)

	body = GUI.Make_Split(
		g,
		column,
		GUI.Split_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "body",
				min_size = GUI.Vec2{0, 240},
				size_flags_v = GUI.Size_Flags{.Fill, .Expand},
			},
			direction = .Horizontal,
		},
	)

	left := GUI.Make_Split(
		g,
		body,
		GUI.Split_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "left",
				min_size = GUI.Vec2{210, 0},
				weight = 1,
			},
			direction = .Vertical,
		},
	)

	make_explorer(g, left)
	make_outline(g, left)

	centre = GUI.Make_Split(
		g,
		body,
		GUI.Split_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "centre",
				min_size = GUI.Vec2{320, 0},
				weight = 3,
			},
			direction = .Vertical,
		},
	)

	make_editor(g, centre)
	make_log(g, centre)

	properties = make_properties(g, body)

	make_status_bar(g, column)
}

//* The strip of menus at the top of the window.
make_menu_bar :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	bar := GUI.Make_Menu_Bar(
		g,
		parent,
		GUI.Menu_Bar_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "menubar",
				min_size = GUI.Vec2{0, 28},
				size_flags_v = GUI.Size_Flags{.Fill},
				style = GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.10, 0.11, 0.14, 1),
						border_color = {
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
						},
						border_width = {0, 0, 1, 0},
						content_margin = {4, 2, 4, 2},
					},
					text = GUI.Text_Style{colour = GUI.RGBA(0.86, 0.89, 0.95, 1)},
				},
			},
		},
	)

	for menu, i in menus {
		id := GUI.Make_Menu_Button(
			g,
			bar,
			GUI.Menu_Button_Opts{
				Base_Opts = GUI.Base_Opts{
					name = menu.name,
					preset = .Top_Left,
					offsets = GUI.Offset{left = 8 + f32(i) * 92, top = 2, right = 96 + f32(i) * 92, bottom = 26},
				},
				text = menu.name,
				items = menu.items,
			},
		)
		//* The program hears about a pick on the menu button itself.
		w := GUI.Widget_Get(g, id)
		w.signals.on_item_selected = on_menu_selected
	}
}

//* An item of a menu of the menu bar was picked. The status bar says
//* what was picked.
on_menu_selected :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, index: int) {
	name := GUI.Widget_Name(g, id)
	for menu in menus {
		if menu.name != name {continue}
		if index < 0 || index >= len(menu.items) {return}
		message = fmt.tprintf("%s > %s", name, menu.items[index])
		return
	}
}

//* The strip of buttons that dock the panels without dragging them.
make_tool_bar :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	bar := GUI.Make_HBox(
		g,
		parent,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "toolbar",
				min_size = GUI.Vec2{0, 38},
				size_flags_v = GUI.Size_Flags{.Fill},
				separation = 6,
				style = GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.12, 0.13, 0.17, 1),
						border_color = {
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
						},
						border_width = {0, 0, 1, 0},
						content_margin = {8, 5, 8, 5},
					},
				},
			},
		},
	)

	buttons := [5][2]string {
		{"Dock Left", "dock_left"},
		{"Dock Right", "dock_right"},
		{"Dock Top", "dock_top"},
		{"Dock Bottom", "dock_bottom"},
		{"Dock As Tab", "dock_as_tab"},
	}
	for button in buttons {
		GUI.Make_Button(
			g,
			bar,
			GUI.Button_Opts{
				Base_Opts = GUI.Base_Opts{
					name = button[1],
					size_flags_h = GUI.Size_Flags{.Fill},
				},
				text = button[0],
				on_pressed = on_dock,
			},
		)
	}

	GUI.Make_Label(
		g,
		bar,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "hint",
				size_flags_h = GUI.Size_Flags{.Fill},
				style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(0.48, 0.51, 0.58, 1)}},
			},
			text = "Drag a title bar to move a panel.",
		},
	)
}

//* The tree of the files of the project.
make_explorer :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	panel := make_panel(g, parent, "Explorer", GUI.Vec2{0, 150}, 1)

	tree := GUI.Make_Tree(
		g,
		panel,
		GUI.Tree_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "files",
				min_size = GUI.Vec2{170, 0},
				preset = .Fill,
				offsets = GUI.Offset{left = 6, top = 28, right = -6, bottom = -6},
			},
		},
	)

	root := GUI.tree_add_item(g, tree, "calcui", -1)
	src := GUI.tree_add_item(g, tree, "src", root)
	GUI.tree_add_item(g, tree, "GUI", src)
	GUI.tree_add_item(g, tree, "App", src)
	examples := GUI.tree_add_item(g, tree, "examples", root)
	GUI.tree_add_item(g, tree, "00_hello", examples)
	GUI.tree_add_item(g, tree, "01_gallery", examples)
	GUI.tree_add_item(g, tree, "02_docking", examples)
	docs := GUI.tree_add_item(g, tree, "docs", root)
	GUI.tree_add_item(g, tree, "widgets.md", docs)
	GUI.tree_add_item(g, tree, "extending.md", docs)
	GUI.tree_add_item(g, tree, "README.md", -1)
}

//* The list of the symbols of the file that is open.
make_outline :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	panel := make_panel(g, parent, "Outline", GUI.Vec2{0, 130}, 1)

	list := GUI.Make_Item_List(
		g,
		panel,
		GUI.Item_List_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "symbols",
				min_size = GUI.Vec2{170, 0},
				preset = .Fill,
				offsets = GUI.Offset{left = 6, top = 28, right = -6, bottom = -6},
			},
			items = {
				"main :: proc()",
				"setup :: proc(app)",
				"update :: proc(app)",
				"on_press :: proc(g, id)",
				"App :: struct",
				"Options :: struct",
			},
		},
	)
	GUI.item_list_select(g, list, 0)
}

//* The editor: a tab host with a file in every tab.
make_editor :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	panel := make_panel(g, parent, "Editor", GUI.Vec2{0, 240}, 2)

	editor_tabs = GUI.Make_Tab_Container(
		g,
		panel,
		GUI.Tab_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "tabs",
				preset = .Fill,
				offsets = GUI.Offset{left = 4, top = 26, right = -4, bottom = -4},
			},
		},
	)

	GUI.Make_Text_Box(
		g,
		editor_tabs,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "main.odin",
				preset = .Fill,
				offsets = GUI.Offset{left = 6, top = 6, right = -6, bottom = -6},
			},
			text = "package main\n\nimport GUI \"../../src/GUI\"\n\nmain :: proc() {\n\tg := GUI.Init_GUI(640, 400, backend)\n\tdefer GUI.Shutdown_GUI(g)\n\tfor !g.quit_requested {\n\t\tGUI.Frame(g)\n\t}\n}\n",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)

	GUI.Make_Rich_Text_Label(
		g,
		editor_tabs,
		GUI.Rich_Text_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "notes.md",
				preset = .Fill,
				offsets = GUI.Offset{left = 6, top = 6, right = -6, bottom = -6},
			},
			text = "The notes of the editor.\n\nA panel is dragged by its title bar. The edges of a panel split the one it is dropped on, the middle makes the two share a tab strip, and Ctrl swaps them around.",
		},
	)
}

//* The log of the program.
make_log :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	panel := make_panel(g, parent, "Log", GUI.Vec2{0, 120}, 1)

	list := GUI.Make_Item_List(
		g,
		panel,
		GUI.Item_List_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "lines",
				min_size = GUI.Vec2{170, 0},
				preset = .Fill,
				offsets = GUI.Offset{left = 6, top = 28, right = -6, bottom = -6},
			},
			items = {
				"09:12:03  the GUI was made",
				"09:12:03  the font was loaded",
				"09:12:03  the tree was laid out",
				"09:12:04  the first frame was drawn",
			},
		},
	)
	GUI.item_list_select(g, list, 3)
}

//* The list of the properties of the file that is open.
make_properties :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := make_panel(g, parent, "Properties", GUI.Vec2{220, 0}, 1)

	list := GUI.Make_Item_List(
		g,
		panel,
		GUI.Item_List_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "properties",
				min_size = GUI.Vec2{200, 0},
				preset = .Fill,
				offsets = GUI.Offset{left = 6, top = 28, right = -6, bottom = -6},
			},
			items = {
				"name: main.odin",
				"kind: source file",
				"size: 12 KiB",
				"lines: 341",
				"encoding: UTF-8",
				"modified: today",
			},
		},
	)
	GUI.item_list_select(g, list, 0)
	return panel
}

//* The strip at the bottom of the window.
make_status_bar :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID) {
	bar := GUI.Make_HBox(
		g,
		parent,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "statusbar",
				min_size = GUI.Vec2{0, 26},
				size_flags_v = GUI.Size_Flags{.Fill},
				separation = 12,
				style = GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.10, 0.11, 0.14, 1),
						border_color = {
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
							GUI.RGBA(0.18, 0.20, 0.24, 1),
						},
						border_width = {0, 1, 0, 0},
						content_margin = {8, 4, 8, 4},
					},
					text = GUI.Text_Style{colour = GUI.RGBA(0.70, 0.73, 0.80, 1)},
				},
			},
		},
	)

	GUI.Make_Label(
		g,
		bar,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "message",
				size_flags_h = GUI.Size_Flags{.Fill},
			},
			text = "Ready",
		},
	)

	status = GUI.Make_Label(
		g,
		bar,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "position",
				size_flags_h = GUI.Size_Flags{.Fill},
				style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(0.50, 0.53, 0.60, 1)}},
			},
			text = "CalcUI",
		},
	)
}

//* A panel with a title bar that can be dragged out of its place.
make_panel :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	min_size: GUI.Vec2,
	weight: f32,
) -> GUI.Widget_ID {
	return GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				draggable = true,
				min_size = min_size,
				weight = weight,
				style = GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.11, 0.12, 0.15, 1),
						border_color = {
							GUI.RGBA(0.20, 0.22, 0.27, 1),
							GUI.RGBA(0.20, 0.22, 0.27, 1),
							GUI.RGBA(0.20, 0.22, 0.27, 1),
							GUI.RGBA(0.20, 0.22, 0.27, 1),
						},
						border_width = {1, 1, 1, 1},
						content_margin = {4, 26, 4, 4},
						anti_aliasing = true,
					},
					text = GUI.Text_Style{colour = GUI.RGBA(0.86, 0.89, 0.95, 1)},
				},
			},
		},
	)
}

//* The buttons of the toolbar dock the panel of the properties into
//* another zone of the body.
on_dock :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	name := GUI.Widget_Name(g, id)
	zone := GUI.Dock_Zone.None
	switch name {
	case "dock_left":
		zone = .Left
	case "dock_right":
		zone = .Right
	case "dock_top":
		zone = .Top
	case "dock_bottom":
		zone = .Bottom
	case "dock_as_tab":
		GUI.Dock(g, properties, editor_tabs, .Center)
		message = "Properties became a tab of the editor."
		return
	}
	if zone == .None {return}
	GUI.Dock(g, properties, body, zone)
	message = fmt.tprintf("Properties were docked %v.", zone)
}

//* Once a frame: the status bar says what happened last.
update :: proc(app: ^App.App) {
	GUI.Widget_Set_Text(app.gui, status, message)
}
