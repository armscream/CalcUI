//* Every section shows one group of the widgets of the toolkit. The
//* widgets are filled with something that shows what they do: a list
//* has items in it, a tree has branches, a table has rows and columns,
//* a chart has a series, and the graph has nodes and a wire between
//* them.

package main

import "core:fmt"
import GUI "../../src/GUI"

//* The colours that the sections share.
SECTION_BG :: GUI.Colour{0.11, 0.12, 0.15, 1}
SECTION_BORDER :: GUI.Colour{0.20, 0.22, 0.27, 1}
DEMO_BG :: GUI.Colour{0.14, 0.15, 0.19, 1}
DEMO_BORDER :: GUI.Colour{0.24, 0.26, 0.32, 1}
DIM :: GUI.Colour{0.48, 0.51, 0.58, 1}
INK :: GUI.Colour{0.86, 0.89, 0.95, 1}

presses: int
press_label: GUI.Widget_ID
toast: GUI.Widget_ID
palette: GUI.Widget_ID
context_menu: GUI.Widget_ID
popup_menu: GUI.Widget_ID
popup_panel: GUI.Widget_ID
accept_dialog: GUI.Widget_ID
confirmation_dialog: GUI.Widget_ID
file_dialog: GUI.Widget_ID

//* A menu of a menu bar: the name of the menu and the items it holds.
Menu :: struct {
	name:  string,
	items: []string,
}

//* The menus of the menu bar of the buttons section.
menus: [3]Menu = {
	{"File", {"New", "Open", "Save"}},
	{"Edit", {"Undo", "Redo"}},
	{"View", {"Panels", "Layout"}},
}

demo_style :: proc() -> GUI.Style {
	return GUI.Style {
		box = GUI.StyleBox {
			bg_color = DEMO_BG,
			border_color = {DEMO_BORDER, DEMO_BORDER, DEMO_BORDER, DEMO_BORDER},
			border_width = {1, 1, 1, 1},
			content_margin = {6, 6, 6, 6},
		},
		text = GUI.Text_Style{colour = INK},
	}
}

//* == buttons ==

Section_Buttons :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(210)
	panel := Section(parent, "Buttons", height)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "button", preset = .Top_Left, offsets = Slot(0, 0)},
			text = "Press me",
			on_pressed = on_press,
			text_align = .Left,
		},
	)

	press_label = GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "press_count",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 150, top = 48, right = 300, bottom = 74},
				style = GUI.Style{text = GUI.Text_Style{colour = DIM}},
			},
			text = "pressed 0 times",
		},
	)

	GUI.Make_Check_Box(
		g,
		panel,
		GUI.Check_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "check_box", preset = .Top_Left, offsets = Slot(1, 0)},
			text = "A check box",
			on = true,
		},
	)

	GUI.Make_Option_Button(
		g,
		panel,
		GUI.Option_Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "option_button", preset = .Top_Left, offsets = Slot(0, 1)},
			items = {"Low", "Medium", "High"},
		},
	)

	GUI.Make_Menu_Button(
		g,
		panel,
		GUI.Menu_Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "menu_button", preset = .Top_Left, offsets = Slot(1, 1)},
			text = "A menu",
			items = {"Cut", "Copy", "Paste"},
		},
	)

	GUI.Make_Link_Button(
		g,
		panel,
		GUI.Link_Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "link_button", preset = .Top_Left, offsets = Slot(2, 1), tooltip = "https://github.com/armscream/CalcUI"},
			text = "A link",
			link = "https://github.com/armscream/CalcUI",
		},
	)

	GUI.Make_Segmented(
		g,
		panel,
		GUI.Segmented_Opts{
			Base_Opts = GUI.Base_Opts{name = "segmented", preset = .Top_Left, offsets = Slot(0, 2)},
			items = {"Day", "Week", "Month"},
		},
	)

	GUI.Make_Toggle_Switch(
		g,
		panel,
		GUI.Toggle_Switch_Opts{
			Base_Opts = GUI.Base_Opts{name = "toggle_switch", preset = .Top_Left, offsets = Slot(1, 2)},
			text = "Notifications",
			on = true,
		},
	)

	GUI.Make_Rating(
		g,
		panel,
		GUI.Rating_Opts{
			Base_Opts = GUI.Base_Opts{name = "rating", preset = .Top_Left, offsets = Slot(2, 2)},
			value = 3,
			max = 5,
		},
	)

	menu_bar := GUI.Make_Menu_Bar(
		g,
		panel,
		GUI.Menu_Bar_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "menu_bar",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 158, right = 472, bottom = 190},
				style = GUI.Style{
					box = GUI.StyleBox{
						bg_color = SECTION_BG,
						border_color = {SECTION_BORDER, SECTION_BORDER, SECTION_BORDER, SECTION_BORDER},
						border_width = {1, 1, 1, 1},
						content_margin = {6, 3, 6, 3},
					},
				},
			},
		},
	)

	for menu, i in menus {
		GUI.Make_Menu_Button(
			g,
			menu_bar,
			GUI.Menu_Button_Opts{
				Base_Opts = GUI.Base_Opts{
					name = menu.name,
					preset = .Top_Left,
					offsets = GUI.Offset{left = 8 + f32(i) * 92, top = 4, right = 96 + f32(i) * 92, bottom = 30},
				},
				text = menu.name,
				items = menu.items,
			},
		)
	}

	return height
}

on_press :: proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
	presses += 1
	GUI.Widget_Set_Text(gui, press_label, fmt.tprintf("pressed %d times", presses))
}

//* == inputs ==

Section_Inputs :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(370)
	panel := Section(parent, "Inputs", height)

	GUI.Make_Text_Box(
		g,
		panel,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "text_box", preset = .Top_Left, offsets = Slot(0, 0), tooltip = "a tooltip"},
			text = "a field",
			rules = GUI.Text_Rules{max_length = 24},
		},
	)

	GUI.Make_Search_Field(
		g,
		panel,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{name = "search_field", preset = .Top_Left, offsets = Slot(1, 0)},
			placeholder = "Search",
		},
	)

	GUI.Make_Number_Input(
		g,
		panel,
		GUI.Number_Input_Opts{
			Base_Opts = GUI.Base_Opts{name = "number_input", preset = .Top_Left, offsets = Slot(2, 0)},
			value = 12,
			min = 0,
			max = 100,
		},
	)

	GUI.Make_Text_Box(
		g,
		panel,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "text_box_multiline", preset = .Top_Left, offsets = Place(0, 1, 228, 90)},
			text = "A box of more than one line.\nThe enter key makes a new line.",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)

	GUI.Make_Rich_Text_Label(
		g,
		panel,
		GUI.Rich_Text_Opts{
			Base_Opts = GUI.Base_Opts{name = "rich_text_label", preset = .Top_Left, offsets = Place(1, 1, 228, 90)},
			text = "A label that holds a piece of text of any length. The text that does not fit is scrolled.",
		},
	)

	GUI.Make_Rich_Text_Editor(
		g,
		panel,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{name = "rich_text_editor", preset = .Top_Left, offsets = Place(2, 1, 228, 90)},
			text = "An editor with more than one cursor.\nIt keeps the text of the file.",
			wrap = true,
		},
	)

	GUI.Make_Combo_Box(
		g,
		panel,
		GUI.Combo_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "combo_box", preset = .Top_Left, offsets = Place(0, 2, 228, 100)},
			items = {"Red", "Green", "Blue", "Black"},
		},
	)

	chat := GUI.Make_Chat_Input(
		g,
		panel,
		GUI.Chat_Input_Opts{
			Base_Opts = GUI.Base_Opts{name = "chat_input", preset = .Top_Left, offsets = Place(1, 2, 228, 100)},
		},
	)
	GUI.chat_input_add_line(g, chat, "Ada", "The gallery is open.")
	GUI.chat_input_add_line(g, chat, "Ada", "Every widget has something in it.")
	GUI.chat_input_add_line(g, chat, "CalcUI", "Press the button of the first section.", true)

	return height
}

//* == ranges ==

Section_Ranges :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(150)
	panel := Section(parent, "Ranges", height)

	GUI.Make_H_Slider(
		g,
		panel,
		GUI.Slider_Opts{
			Base_Opts = GUI.Base_Opts{name = "h_slider", preset = .Top_Left, offsets = Slot(0, 0)},
			value = 40,
			min = 0,
			max = 100,
		},
	)

	GUI.Make_V_Slider(
		g,
		panel,
		GUI.Slider_Opts{
			Base_Opts = GUI.Base_Opts{name = "v_slider", preset = .Top_Left, offsets = Place(1, 0, 60, 90)},
			value = 65,
			min = 0,
			max = 100,
		},
	)

	GUI.Make_Spin_Box(
		g,
		panel,
		GUI.Spin_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "spin_box", preset = .Top_Left, offsets = Slot(2, 0)},
			value = 7,
			min = 0,
			max = 99,
			step = 1,
		},
	)

	GUI.Make_Progress_Bar(
		g,
		panel,
		GUI.Progress_Bar_Opts{
			Base_Opts = GUI.Base_Opts{name = "progress_bar", preset = .Top_Left, offsets = Slot(0, 1)},
			value = 64,
			max = 100,
		},
	)

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "range_hint",
				preset = .Top_Left,
				offsets = Slot(1, 1),
				style = GUI.Style{text = GUI.Text_Style{colour = DIM}},
			},
			text = "The bar is at 64 of 100.",
		},
	)

	return height
}

//* == choices ==

Section_Choices :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(320)
	panel := Section(parent, "Choices", height)

	list := GUI.Make_Item_List(
		g,
		panel,
		GUI.Item_List_Opts{
			Base_Opts = GUI.Base_Opts{name = "item_list", preset = .Top_Left, offsets = Place(0, 0, 228, 140)},
			items = {
				"The first item",
				"The second item",
				"The third item",
				"The fourth item",
				"The fifth item",
				"The sixth item",
				"The seventh item",
			},
		},
	)
	GUI.item_list_select(g, list, 2)

	tree := GUI.Make_Tree(
		g,
		panel,
		GUI.Tree_Opts{
			Base_Opts = GUI.Base_Opts{name = "tree", preset = .Top_Left, offsets = Place(1, 0, 228, 140)},
		},
	)
	root := GUI.tree_add_item(g, tree, "The project", -1)
	folder := GUI.tree_add_item(g, tree, "The source", root)
	GUI.tree_add_item(g, tree, "The core", folder)
	GUI.tree_add_item(g, tree, "The examples", folder)
	GUI.tree_add_item(g, tree, "The tests", root)
	GUI.tree_add_item(g, tree, "The readme", -1)

	tab_bar := GUI.Make_Tab_Bar(
		g,
		panel,
		GUI.Tab_Bar_Opts{
			Base_Opts = GUI.Base_Opts{name = "tab_bar", preset = .Top_Left, offsets = Place(2, 0, 228, 40)},
		},
	)
	for name in ([]string{"One", "Two", "Three"}) {
		GUI.Make_Label(
			g,
			tab_bar,
			GUI.Label_Opts{
				Base_Opts = GUI.Base_Opts{
					name = name,
					preset = .Top_Left,
					offsets = GUI.Offset{left = 8, top = 6, right = 70, bottom = 32},
				},
				text = name,
			},
		)
	}

	tabs := GUI.Make_Tabs(
		g,
		panel,
		GUI.Tabs_Opts{
			Base_Opts = GUI.Base_Opts{name = "tabs", preset = .Top_Left, offsets = Place(2, 1, 228, 90)},
		},
	)
	GUI.Make_Label(
		g,
		tabs,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "First",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 32, right = -8, bottom = -8},
			},
			text = "The first tab is showing.",
		},
	)
	GUI.Make_Label(
		g,
		tabs,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "Second",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 32, right = -8, bottom = -8},
			},
			text = "The second tab is showing.",
		},
	)

	tab_container := GUI.Make_Tab_Container(
		g,
		panel,
		GUI.Tab_Container_Opts{
			Base_Opts = GUI.Base_Opts{name = "tab_container", preset = .Top_Left, offsets = Place(0, 1, 228, 100)},
		},
	)
	GUI.Make_Label(
		g,
		tab_container,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "Overview",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 32, right = -8, bottom = -8},
			},
			text = "The container of the tabs draws the strip itself.",
		},
	)
	GUI.Make_Label(
		g,
		tab_container,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "Details",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 32, right = -8, bottom = -8},
			},
			text = "Every tab is a child of the container.",
		},
	)

	accordion := GUI.Make_Accordion(
		g,
		panel,
		GUI.Accordion_Opts{
			Base_Opts = GUI.Base_Opts{name = "accordion", preset = .Top_Left, offsets = Place(1, 1, 228, 100)},
		},
	)
	GUI.Make_Label(
		g,
		accordion,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "The first section",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 4, right = -8, bottom = -4},
				min_size = GUI.Vec2{0, 40},
			},
			text = "Only one section is open at a time.",
		},
	)
	GUI.Make_Label(
		g,
		accordion,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "The second section",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 4, right = -8, bottom = -4},
				min_size = GUI.Vec2{0, 40},
			},
			text = "The name of a child is the header of its section.",
		},
	)

	return height
}

//* == popups ==

Section_Popups :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(230)
	panel := Section(parent, "Popups", height)

	popup_menu := GUI.Make_Popup_Menu(
		g,
		panel,
		GUI.Popup_Menu_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "popup_menu",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 120, right = 244, bottom = 220},
			},
			items = {"Open", "Save", "Save as", "Close"},
		},
	)

	popup_panel := GUI.Make_Popup_Panel(
		g,
		panel,
		GUI.Popup_Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "popup_panel",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 260, top = 120, right = 488, bottom = 220},
				style = demo_style(),
			},
		},
	)
	GUI.Make_Label(
		g,
		popup_panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{name = "popup_text"},
			text = "A panel that comes up over the rest of the UI.",
		},
	)

	accept_dialog := GUI.Make_Accept_Dialog(
		g,
		panel,
		GUI.Accept_Dialog_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "accept_dialog",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 504, top = 120, right = 732, bottom = 200},
			},
			text = "Save the changes?",
		},
	)

	confirmation_dialog := GUI.Make_Confirmation_Dialog(
		g,
		panel,
		GUI.Accept_Dialog_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "confirmation_dialog",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 120, right = 244, bottom = 200},
			},
			text = "Close the file without saving?",
		},
	)

	file_dialog := GUI.Make_File_Dialog(
		g,
		panel,
		GUI.File_Dialog_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "file_dialog",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 260, top = 120, right = 488, bottom = 200},
			},
			mode = .Open_File,
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "open_menu", preset = .Top_Left, offsets = Slot(0, 0)},
			text = "Open the menu",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Popup_Menu_Open(gui, popup_menu)
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "open_panel", preset = .Top_Left, offsets = Slot(1, 0)},
			text = "Open the panel",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Popup_Panel_Open(gui, popup_panel)
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "open_accept", preset = .Top_Left, offsets = Slot(2, 0)},
			text = "Ask to accept",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Dialog_Open(gui, accept_dialog)
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "open_confirm", preset = .Top_Left, offsets = Slot(0, 1)},
			text = "Ask to confirm",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Dialog_Open(gui, confirmation_dialog)
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "open_file", preset = .Top_Left, offsets = Slot(1, 1)},
			text = "Ask for a file",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.File_Dialog_Open(gui, file_dialog)
			},
		},
	)

	return height
}

//* == overlays ==

Section_Overlays :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(330)
	panel := Section(parent, "Overlays", height)

	toast = GUI.Make_Toast(
		g,
		panel,
		GUI.Toast_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "toast",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 44, right = 244, bottom = 80},
			},
			text = "Saved",
			kind = .Success,
		},
	)

	palette = GUI.Make_Command_Palette(
		g,
		panel,
		GUI.Command_Palette_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "palette",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 90, right = 244, bottom = 210},
			},
		},
	)

	GUI.Command_Add(g, "Save", GUI.Shortcut{key = .S, mods = GUI.Mods{.Ctrl}}, nil)
	GUI.Command_Add(g, "Open", GUI.Shortcut{key = .O, mods = GUI.Mods{.Ctrl}}, nil)
	GUI.Command_Add(g, "Close", GUI.Shortcut{key = .W, mods = GUI.Mods{.Ctrl}}, nil)

	context_menu = GUI.Make_Context_Menu(
		g,
		panel,
		GUI.Context_Menu_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "context_menu",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 220, right = 244, bottom = 320},
			},
			items = {
				GUI.Context_Menu_Item{text = "Cut"},
				GUI.Context_Menu_Item{text = "Copy"},
				GUI.Context_Menu_Item{separator = true},
				GUI.Context_Menu_Item{text = "Paste"},
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "show_toast", preset = .Top_Left, offsets = Slot(1, 0)},
			text = "Show the toast",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Toast_Show(gui, toast, "The file was saved.", .Success, 3)
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "show_palette", preset = .Top_Left, offsets = Slot(2, 0)},
			text = "Open the palette",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Popup_Open(gui, palette)
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "show_context", preset = .Top_Left, offsets = Slot(1, 1)},
			text = "Open the menu",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				GUI.Context_Menu_Open(gui, context_menu, GUI.Vec2{280, 130})
			},
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "tooltip_subject",
				preset = .Top_Left,
				offsets = Slot(2, 1),
				tooltip = "The tooltip waits until the pointer rests on the thing.",
			},
			text = "Rest on me",
		},
	)

	GUI.Make_Date_Picker(
		g,
		panel,
		GUI.Date_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "date_picker", preset = .Top_Left, offsets = Place(0, 2, 228, 90)},
			year = 2026,
			month = 11,
			day = 9,
		},
	)

	GUI.Make_Time_Picker(
		g,
		panel,
		GUI.Time_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "time_picker", preset = .Top_Left, offsets = Place(1, 2, 228, 90)},
			hour = 14,
			minute = 30,
		},
	)

	GUI.Make_Color_Picker(
		g,
		panel,
		GUI.Color_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "color_picker", preset = .Top_Left, offsets = Place(2, 2, 228, 90)},
			colour = GUI.RGBA(0.25, 0.62, 1.0, 1),
		},
	)

	GUI.Make_Emoji_Picker(
		g,
		panel,
		GUI.Emoji_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "emoji_picker", preset = .Top_Left, offsets = Place(0, 3, 228, 90)},
			emoji = "\U0001F600",
			group = 0,
		},
	)

	return height
}

//* == containers ==

Section_Containers :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(470)
	panel := Section(parent, "Containers", height)

	//* A plain panel: it places its children where they are told to.
	box := GUI.Make_Panel(
		g,
		panel,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "panel_demo",
				preset = .Top_Left,
				offsets = Place(0, 0, 228, 96),
				style = demo_style(),
			},
		},
	)
	GUI.Make_Label(
		g,
		box,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "panel_label",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 8, top = 8, right = 200, bottom = 30},
			},
			text = "A panel and its children",
		},
	)

	//* A box that stacks its children from the top to the bottom.
	vbox := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "vbox_demo",
				preset = .Top_Left,
				offsets = Place(1, 0, 228, 96),
				separation = 4,
				style = demo_style(),
				tooltip = "vbox demo",
			},
		},
	)
	for text in ([]string{"First", "Second", "Third"}) {
		GUI.Make_Label(
			g,
			vbox,
			GUI.Label_Opts{
				Base_Opts = GUI.Base_Opts{
					name = text,
					size_flags_v = GUI.Size_Flags{.Fill},
					style = GUI.Style{text = GUI.Text_Style{colour = INK}},
				},
				text = text,
			},
		)
	}

	//* A box that stacks its children from the left to the right.
	hbox := GUI.Make_HBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "hbox_demo",
				preset = .Top_Left,
				offsets = Place(2, 0, 228, 96),
				separation = 8,
				style = demo_style(),
				tooltip = "hbox demo",
			},
		},
	)
	for text in ([]string{"One", "Two", "Three"}) {
		GUI.Make_Label(
			g,
			hbox,
			GUI.Label_Opts{
				Base_Opts = GUI.Base_Opts{
					name = text,
					size_flags_h = GUI.Size_Flags{.Fill},
					style = GUI.Style{text = GUI.Text_Style{colour = INK}},
				},
				text = text,
			},
		)
	}

	//* A grid: the children are put in rows and columns.
	grid := GUI.Make_Grid_Container(
		g,
		panel,
		GUI.Grid_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "grid_demo",
				preset = .Top_Left,
				offsets = Place(0, 1, 228, 96),
				style = demo_style(),
				tooltip = "grid container demo",
			},
			columns = 2,
		},
	)
	for text in ([]string{"A", "B", "C", "D"}) {
		GUI.Make_Label(
			g,
			grid,
			GUI.Label_Opts{
				Base_Opts = GUI.Base_Opts{
					name = text,
					style = GUI.Style{text = GUI.Text_Style{colour = INK}},
				},
				text = text,
			},
		)
	}

	//* A margin: the one child is kept away from the edges.
	margin := GUI.Make_Margin_Container(
		g,
		panel,
		GUI.Margin_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "margin_demo",
				preset = .Top_Left,
				offsets = Place(1, 1, 228, 96),
				style = demo_style(),
				tooltip = "margin container demo",
			},
			margin = {12, 12, 12, 12},
		},
	)
	GUI.Make_Label(
		g,
		margin,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{name = "margin_label"},
			text = "A margin of twelve points",
		},
	)

	//* A centre: the child sits in the middle.
	center := GUI.Make_Center_Container(
		g,
		panel,
		GUI.Center_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "center_demo",
				preset = .Top_Left,
				offsets = Place(2, 1, 228, 96),
				style = demo_style(),
				tooltip = "center container demo",
			},
		},
	)
	GUI.Make_Label(
		g,
		center,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{name = "center_label"},
			text = "In the middle",
		},
	)

	panel_container := GUI.Make_Panel_Container(
		g,
		panel,
		GUI.Panel_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "panel_container_demo",
				preset = .Top_Left,
				offsets = Place(0, 2, 228, 96),
				style = demo_style(),
				tooltip = "panel container demo",
			},
		},
	)
	GUI.Make_Label(
		g,
		panel_container,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{name = "panel_container_label"},
			text = "The child fills the box",
		},
	)

	//* A scroll container: it shows a part of something bigger.
	scroll := GUI.Make_Scroll_Container(
		g,
		panel,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "scroll_demo",
				preset = .Top_Left,
				offsets = Place(1, 2, 228, 96),
				style = demo_style(),
				tooltip = "scroll container demo",
			},
		},
	)
	GUI.Make_Label(
		g,
		scroll,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "scroll_label",
				min_size = GUI.Vec2{300, 180},
			},
			text = "A scroll container shows a part of something bigger. The part that is cut off is still there.",
		},
	)

	//* A scroll area: the same, under its other name.
	area := GUI.Make_Scroll_Area(
		g,
		panel,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "scroll_area_demo",
				preset = .Top_Left,
				offsets = Place(2, 2, 228, 96),
				style = demo_style(),
				tooltip = "scroll area demo",
			},
		},
	)
	GUI.Make_Label(
		g,
		area,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "scroll_area_label",
				min_size = GUI.Vec2{300, 180},
			},
			text = "A scroll area is a scroll container under its other name.",
		},
	)

	//* A flow container: the children are put one after the other.
	flow := GUI.Make_Flow_Container(
		g,
		panel,
		GUI.Flow_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "flow_demo",
				preset = .Top_Left,
				offsets = Place(0, 3, 228, 96),
				separation = 6,
				style = demo_style(),
				tooltip = "flow demo",
			},
		},
	)
	for text in ([]string{"One", "Two", "Three", "Four", "Five", "Six"}) {
		GUI.Make_Label(
			g,
			flow,
			GUI.Label_Opts{
				Base_Opts = GUI.Base_Opts{
					name = text,
					style = GUI.Style{text = GUI.Text_Style{colour = INK}},
				},
				text = text,
			},
		)
	}

	//* An aspect ratio container: the child keeps its shape.
	aspect := GUI.Make_Aspect_Container(
		g,
		panel,
		GUI.Aspect_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "aspect_demo",
				preset = .Top_Left,
				offsets = Place(1, 3, 228, 96),
				style = demo_style(),
			},
			ratio = 2,
		},
	)
	GUI.Make_Label(
		g,
		aspect,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "aspect_label",
				min_size = GUI.Vec2{160, 80},
			},
			text = "Twice as wide as it is high",
		},
	)

	//* A split: the space is divided among the children.
	split := GUI.Make_Split(
		g,
		panel,
		GUI.Split_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "split_demo",
				preset = .Top_Left,
				offsets = Place(2, 3, 228, 96),
				style = demo_style(),
				tooltip = "split demo",
			},
			direction = .Horizontal,
		},
	)
	for text in ([]string{"Left", "Right"}) {
		GUI.Make_Label(
			g,
			split,
			GUI.Label_Opts{
				Base_Opts = GUI.Base_Opts{
					name = text,
					size_flags_h = GUI.Size_Flags{.Fill},
					style = GUI.Style{text = GUI.Text_Style{colour = INK}},
				},
				text = text,
			},
		)
	}

	return height
}

//* == The simple drawings ==

Section_Drawings :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(220)
	panel := Section(parent, "Simple drawings", height)

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{name = "label", preset = .Top_Left, offsets = Slot(0, 0)},
			text = "A label",
		},
	)

	GUI.Make_Color_Rect(
		g,
		panel,
		GUI.Color_Rect_Opts{
			Base_Opts = GUI.Base_Opts{name = "color_rect", preset = .Top_Left, offsets = Slot(1, 0), tooltip = "A color rect"},
			colour = GUI.RGBA(0.25, 0.62, 1.0, 1),
		},
	)

	GUI.Make_Texture_Rect(
		g,
		panel,
		GUI.Texture_Rect_Opts{
			Base_Opts = GUI.Base_Opts{name = "texture_rect", preset = .Top_Left, offsets = Place(2, 0, 120, 96), tooltip = "texture rect demo"},
			texture = GUI.GUI_Atlas_Texture(g),
		},
	)

	GUI.Make_Nine_Patch_Rect(
		g,
		panel,
		GUI.Nine_Patch_Opts{
			Base_Opts = GUI.Base_Opts{name = "nine_patch_rect", preset = .Top_Left, offsets = Place(0, 1, 120, 96), tooltip = "nine patch rect demo"},
			texture = GUI.GUI_Atlas_Texture(g),
			patch = {24, 24, 24, 24},
		},
	)

	GUI.New_Widget(
		g,
		.Image,
		panel,
		GUI.Widget_Opts{
			name = "image",
			preset = .Top_Left,
			offsets = Place(1, 1, 120, 96),
			style = GUI.Style{
				box = GUI.StyleBox{bg_color = GUI.RGBA(0.20, 0.24, 0.32, 1)},
			},
			tooltip = "custom widget"
		},
	)

	GUI.Make_Reference_Rect(
		g,
		panel,
		GUI.Reference_Rect_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "reference_rect",
				preset = .Top_Left,
				offsets = Place(2, 1, 120, 96),
				tooltip = "reference rect",
			},
		},
	)

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "reference_hint",
				preset = .Top_Left,
				offsets = Slot(0, 2),
				style = GUI.Style{text = GUI.Text_Style{colour = DIM}},
			},
			text = "The rectangle before the label holds a place in the layout.",
		},
	)

	hsep := GUI.Make_Separator(g, panel, false)
	GUI.Widget_Set_Offsets(g, hsep, GUI.Offset{left = 16, top = 196, right = 300, bottom = 197})
	vsep := GUI.Make_Separator(g, panel, true)
	GUI.Widget_Set_Offsets(g, vsep, GUI.Offset{left = 480, top = 44, right = 481, bottom = 140})

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "separator_hint",
				preset = .Top_Left,
				offsets = Slot(0, 3),
				style = GUI.Style{text = GUI.Text_Style{colour = DIM}},
			},
			text = "The line across is a horizontal separator, the one at the side stands up.",
		},
	)

	return height
}

//* == data ==

Section_Data :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(230)
	panel := Section(parent, "Data", height)

	table := GUI.Make_Data_Table(
		g,
		panel,
		GUI.Data_Table_Opts{
			Base_Opts = GUI.Base_Opts{name = "data_table", preset = .Top_Left, offsets = Place(0, 0, 228, 170)},
		},
	)
	GUI.data_table_add_column(g, table, "Name", 130)
	GUI.data_table_add_column(g, table, "Size", 80)
	GUI.data_table_add_row(g, table, {"Cargo.toml", "3 KiB"})
	GUI.data_table_add_row(g, table, {"README.md", "1 KiB"})
	GUI.data_table_add_row(g, table, {"main.odin", "12 KiB"})
	GUI.data_table_add_row(g, table, {"gallery.odin", "18 KiB"})
	GUI.data_table_add_row(g, table, {"text_showcase.odin", "15 KiB"})

	list := GUI.Make_Virtual_List(
		g,
		panel,
		GUI.Virtual_List_Opts{
			Base_Opts = GUI.Base_Opts{name = "virtual_list", preset = .Top_Left, offsets = Place(1, 0, 228, 170)},
			source = gallery_list_source(),
		},
	)

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "virtual_hint",
				preset = .Top_Left,
				offsets = Slot(2, 0),
				style = GUI.Style{text = GUI.Text_Style{colour = DIM}},
			},
			text = "A list of a hundred thousand rows. Only the rows on the screen are drawn.",
		},
	)

	return height
}

//* The rows of the virtual list.
gallery_list_count: int = 100000

gallery_list_source :: proc() -> GUI.List_Source {
	return GUI.List_Source {
		count = proc(ctx: rawptr) -> int {
			return gallery_list_count
		},
		text = proc(ctx: rawptr, index: int) -> string {
			return fmt.tprintf("Row %d", index)
		},
	}
}

//* == The heavy widgets ==

Section_Heavy :: proc(parent: GUI.Widget_ID) -> f32 {
	height := f32(390)
	panel := Section(parent, "Heavy widgets", height)

	chart := GUI.Make_Chart(
		g,
		panel,
		GUI.Chart_Opts{
			Base_Opts = GUI.Base_Opts{name = "chart", preset = .Top_Left, offsets = Place(0, 0, 228, 170)},
			kind = .Bar,
		},
	)
	GUI.chart_add_series(g, chart, "Monday", {12, 18, 9, 24, 15}, GUI.RGBA(0.25, 0.62, 1.0, 1))
	GUI.chart_add_series(g, chart, "Tuesday", {8, 14, 12, 19, 11}, GUI.RGBA(0.95, 0.55, 0.20, 1))
	GUI.chart_set_labels(g, chart, {"Mon", "Tue", "Wed", "Thu", "Fri"})

	graph := GUI.Make_Node_Graph(
		g,
		panel,
		GUI.Node_Graph_Opts{
			Base_Opts = GUI.Base_Opts{name = "node_graph", preset = .Top_Left, offsets = Place(1, 0, 228, 170), tooltip = "Node Graph"},
		},
	)
	first := GUI.node_graph_add_node(g, graph, "Read", GUI.Vec2{30, 30})
	second := GUI.node_graph_add_node(g, graph, "Shape", GUI.Vec2{150, 100})
	out_port := GUI.node_graph_add_port(g, graph, first, "out", .Output)
	in_port := GUI.node_graph_add_port(g, graph, second, "in", .Input)
	GUI.node_graph_connect(g, graph, first, out_port, second, in_port)

	canvas := GUI.Make_Canvas(
		g,
		panel,
		GUI.Canvas_Opts{
			Base_Opts = GUI.Base_Opts{name = "canvas", preset = .Top_Left, offsets = Place(2, 0, 228, 170), tooltip = "a canvas"},
		},
	)
	GUI.canvas_set_paint(g, canvas, gallery_paint)

	drawing := GUI.Make_Vector_Drawing(
		g,
		panel,
		GUI.Vector_Drawing_Opts{
			Base_Opts = GUI.Base_Opts{name = "vector_drawing", preset = .Top_Left, offsets = Place(0, 1, 228, 170)},
		},
	)
	GUI.vector_drawing_add_rect(g, drawing, GUI.Vec2{40, 40}, GUI.Vec2{180, 140}, GUI.RGBA(0.40, 0.85, 0.50, 1))
	GUI.vector_drawing_add_line(g, drawing, GUI.Vec2{40, 140}, GUI.Vec2{180, 40}, GUI.RGBA(0.95, 0.55, 0.20, 1))
	GUI.vector_drawing_add_ellipse(g, drawing, GUI.Vec2{110, 90}, GUI.Vec2{60, 40}, GUI.RGBA(0.45, 0.65, 0.98, 1))

	files := GUI.Make_File_Viewer(
		g,
		panel,
		GUI.File_Viewer_Opts{
			Base_Opts = GUI.Base_Opts{name = "file_viewer", preset = .Top_Left, offsets = Place(1, 1, 228, 170), tooltip = "file viewer"},
		},
	)
	GUI.file_viewer_add_entry(g, files, "src", 0, true)
	GUI.file_viewer_add_entry(g, files, "examples", 0, true)
	GUI.file_viewer_add_entry(g, files, "assets", 0, true)
	GUI.file_viewer_add_entry(g, files, "README.md", 4096, false)
	GUI.file_viewer_add_entry(g, files, "LICENSE", 1024, false)

	GUI.Make_Audio_Player(
		g,
		panel,
		GUI.Audio_Player_Opts{
			Base_Opts = GUI.Base_Opts{name = "audio_player", preset = .Top_Left, offsets = Place(2, 1, 228, 60), tooltip = "audio player"},
			path = "assets/sounds/beep.wav",
			volume = 0.8,
			loops = true,
		},
	)

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "audio_hint",
				preset = .Top_Left,
				offsets = Slot(2, 1),
				style = GUI.Style{text = GUI.Text_Style{colour = DIM}},
			},
			text = "Audio player",
		},
	)

	return height
}

//* The paint of the canvas: it is called every frame and it puts a few
//* things in the canvas.
gallery_paint :: proc(gui: ^GUI.GUI, id: GUI.Widget_ID, state: ^GUI.Canvas_State) {
	GUI.canvas_add_rect(gui, id, GUI.Vec2{20, 20}, GUI.Vec2{120, 80}, GUI.RGBA(0.25, 0.60, 1.00, 1))
	GUI.canvas_add_circle(gui, id, GUI.Vec2{180, 20}, GUI.Vec2{90, 90}, GUI.RGBA(0.95, 0.55, 0.20, 1))
	GUI.canvas_add_line(gui, id, GUI.Vec2{20, 140}, GUI.Vec2{280, 220}, GUI.RGBA(0.40, 0.85, 0.50, 1))
	GUI.canvas_add_text(gui, id, GUI.Vec2{20, 240}, "The canvas", GUI.RGBA(0.92, 0.94, 0.98, 1))
}
