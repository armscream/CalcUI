//* The loader of scene files: a tree of widgets written down as text, in
//* the format of Godot. The keys, the anchors, the styles and the rules
//* of the loader are in docs/scene-format.md.

package GUI

//* == Scene file ==
//* A scene file describes a tree of widgets in a text form: a list of
//* nodes, and every node is a block of `key = value` lines that starts
//* with a `[node ...]` line.
//*
//*   [node name="Root" type="Panel"]
//*       anchors = {0, 0, 1, 1}
//*       offsets = {0, 0, 0, 0}
//*       bg = {0.11, 0.12, 0.15, 1}
//*
//*       [node name="Title" type="Label" parent="Root"]
//*           text = "Hello"
//*           font_size = 28
//*           colour = {0.9, 0.9, 0.95, 1}
//*
//* The loader is forgiving. A line it does not know is skipped, so a file
//* of a newer version still loads. A node whose kind of widget has no
//* constructor is skipped as well, and its children go to the node it
//* would have hung under.

import "core:fmt"
import "core:log"
import "core:mem"
import virt "core:mem/virtual"
import "core:strconv"
import "core:strings"

Scene_Constructor :: proc(g: ^GUI, parent: Widget_ID, name: string, text: string) -> Widget_ID

scene_register :: proc(g: ^GUI, widget_type: Widget_Type, constructor: Scene_Constructor) {
	if g == nil {return}
	index := int(widget_type)
	for len(g.scene_constructors) <= index {
		append(&g.scene_constructors, nil)
	}
	g.scene_constructors[index] = constructor
}

scene_constructor :: proc(g: ^GUI, widget_type: Widget_Type) -> Scene_Constructor {
	if g == nil {return nil}
	index := int(widget_type)
	if index < 0 || index >= len(g.scene_constructors) {return nil}
	return g.scene_constructors[index]
}

scene_constructor_panel :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Panel(g, parent, Panel_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_button :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Button(g, parent, Button_Opts{Base_Opts = Base_Opts{name = name}, text = text})
}

scene_constructor_label :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Label(g, parent, Label_Opts{Base_Opts = Base_Opts{name = name}, text = text})
}

scene_constructor_text_input :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Text_Input(
		g,
		parent,
		Text_Input_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_vbox :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_VBox(g, parent, Box_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_hbox :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_HBox(g, parent, Box_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_split :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Split(g, parent, Split_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_tabs :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Tabs(g, parent, Tabs_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_grid :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Grid_Container(g, parent, Grid_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_margin :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Margin_Container(g, parent, Margin_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_center :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Center_Container(g, parent, Center_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_panel_container :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Panel_Container(
		g,
		parent,
		Panel_Container_Opts{Base_Opts = Base_Opts{name = name}},
	)
}

scene_constructor_scroll_container :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Scroll_Container(
		g,
		parent,
		Scroll_Container_Opts{Base_Opts = Base_Opts{name = name}},
	)
}

scene_constructor_flow :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Flow_Container(g, parent, Flow_Container_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_aspect :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Aspect_Container(
		g,
		parent,
		Aspect_Container_Opts{Base_Opts = Base_Opts{name = name}},
	)
}

scene_constructor_tab_container :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Tab_Container(g, parent, Tab_Container_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_check_box :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Check_Box(
		g,
		parent,
		Check_Box_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_check_button :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Check_Button(
		g,
		parent,
		Check_Button_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_option_button :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Option_Button(g, parent, Option_Button_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_menu_button :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Menu_Button(
		g,
		parent,
		Menu_Button_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_link_button :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Link_Button(
		g,
		parent,
		Link_Button_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_h_slider :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_H_Slider(g, parent, Slider_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_v_slider :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_V_Slider(g, parent, Slider_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_spin_box :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Spin_Box(g, parent, Spin_Box_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_progress_bar :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Progress_Bar(g, parent, Progress_Bar_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_color_rect :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Color_Rect(g, parent, Color_Rect_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_texture_rect :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Texture_Rect(g, parent, Texture_Rect_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_nine_patch :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Nine_Patch_Rect(g, parent, Nine_Patch_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_reference_rect :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Reference_Rect(g, parent, Reference_Rect_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_rich_text_label :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Rich_Text_Label(
		g,
		parent,
		Rich_Text_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_text_edit :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Text_Edit(
		g,
		parent,
		Text_Edit_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_item_list :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Item_List(g, parent, Item_List_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_tree :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Tree(g, parent, Tree_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_tab_bar :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Tab_Bar(g, parent, Tab_Bar_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_menu_bar :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Menu_Bar(g, parent, Menu_Bar_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_h_separator :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	id := Make_Separator(g, parent, false)
	if w := Widget_Get(g, id); w != nil {w.name = name}
	return id
}

scene_constructor_v_separator :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	id := Make_Separator(g, parent, true)
	if w := Widget_Get(g, id); w != nil {w.name = name}
	return id
}

scene_constructor_popup_menu :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Popup_Menu(g, parent, Popup_Menu_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_popup_panel :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Popup_Panel(g, parent, Popup_Panel_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_accept_dialog :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Accept_Dialog(
		g,
		parent,
		Accept_Dialog_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_confirmation_dialog :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Confirmation_Dialog(
		g,
		parent,
		Accept_Dialog_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_file_dialog :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_File_Dialog(g, parent, File_Dialog_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_toast :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Toast(g, parent, Toast_Opts{Base_Opts = Base_Opts{name = name}, text = text})
}

scene_constructor_command_palette :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Command_Palette(
		g,
		parent,
		Command_Palette_Opts{Base_Opts = Base_Opts{name = name}},
	)
}

scene_constructor_rating :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Rating(g, parent, Rating_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_segmented :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Segmented(g, parent, Segmented_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_toggle_switch :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Toggle_Switch(
		g,
		parent,
		Toggle_Switch_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_combo_box :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Combo_Box(g, parent, Combo_Box_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_virtual_list :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Virtual_List(g, parent, Virtual_List_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_data_table :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Data_Table(g, parent, Data_Table_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_date_picker :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Date_Picker(g, parent, Date_Picker_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_time_picker :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Time_Picker(g, parent, Time_Picker_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_color_picker :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Color_Picker(g, parent, Color_Picker_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_emoji_picker :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Emoji_Picker(
		g,
		parent,
		Emoji_Picker_Opts{Base_Opts = Base_Opts{name = name}, emoji = text},
	)
}

scene_constructor_accordion :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Accordion(g, parent, Accordion_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_context_menu :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Context_Menu(g, parent, Context_Menu_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_chat_input :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Chat_Input(g, parent, Chat_Input_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_search_field :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Search_Field(
		g,
		parent,
		Search_Field_Opts{Base_Opts = Base_Opts{name = name}, placeholder = text},
	)
}

scene_constructor_number_input :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Number_Input(g, parent, Number_Input_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_tooltip :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Tooltip(g, parent, Tooltip_Opts{Base_Opts = Base_Opts{name = name}, text = text})
}

//* == Constructors for heavy widgets ==

scene_constructor_chart :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Chart(g, parent, Chart_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_node_graph :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Node_Graph(g, parent, Node_Graph_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_canvas :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Canvas(g, parent, Canvas_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_file_viewer :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_File_Viewer(g, parent, File_Viewer_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_rich_text_editor :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Rich_Text_Editor(
		g,
		parent,
		Rich_Text_Editor_Opts{Base_Opts = Base_Opts{name = name}, text = text},
	)
}

scene_constructor_vector_drawing :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Vector_Drawing(g, parent, Vector_Drawing_Opts{Base_Opts = Base_Opts{name = name}})
}

scene_constructor_audio_player :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Audio_Player(g, parent, Audio_Player_Opts{Base_Opts = Base_Opts{name = name}})
}

//* Puts the constructors of the widgets that exist today in the table.
//* The table is filled once: a program that brings a widget of its own
//* puts its constructor in it with `scene_register`.
scene_register_defaults :: proc(g: ^GUI) {
	if g == nil {return}
	if g.scene_defaults_registered {return}
	g.scene_defaults_registered = true

	scene_register(g, .Panel, scene_constructor_panel)
	scene_register(g, .Button, scene_constructor_button)
	scene_register(g, .Label, scene_constructor_label)
	scene_register(g, .TextInput, scene_constructor_text_input)
	scene_register(g, .VBox, scene_constructor_vbox)
	scene_register(g, .HBox, scene_constructor_hbox)
	scene_register(g, .Split, scene_constructor_split)
	scene_register(g, .Tabs, scene_constructor_tabs)

	scene_register(g, .GridContainer, scene_constructor_grid)
	scene_register(g, .MarginContainer, scene_constructor_margin)
	scene_register(g, .CenterContainer, scene_constructor_center)
	scene_register(g, .PanelContainer, scene_constructor_panel_container)
	scene_register(g, .ScrollContainer, scene_constructor_scroll_container)
	scene_register(g, .FlowContainer, scene_constructor_flow)
	scene_register(g, .AspectRatioContainer, scene_constructor_aspect)
	scene_register(g, .TabContainer, scene_constructor_tab_container)

	scene_register(g, .CheckBox, scene_constructor_check_box)
	scene_register(g, .CheckButton, scene_constructor_check_button)
	scene_register(g, .OptionButton, scene_constructor_option_button)
	scene_register(g, .MenuButton, scene_constructor_menu_button)
	scene_register(g, .LinkButton, scene_constructor_link_button)

	scene_register(g, .HSlider, scene_constructor_h_slider)
	scene_register(g, .VSlider, scene_constructor_v_slider)
	scene_register(g, .SpinBox, scene_constructor_spin_box)
	scene_register(g, .ProgressBar, scene_constructor_progress_bar)

	scene_register(g, .ColorRect, scene_constructor_color_rect)
	scene_register(g, .TextureRect, scene_constructor_texture_rect)
	scene_register(g, .NinePatchRect, scene_constructor_nine_patch)
	scene_register(g, .ReferenceRect, scene_constructor_reference_rect)
	scene_register(g, .RichTextLabel, scene_constructor_rich_text_label)
	scene_register(g, .TextEdit, scene_constructor_text_edit)
	scene_register(g, .ItemList, scene_constructor_item_list)
	scene_register(g, .Tree, scene_constructor_tree)
	scene_register(g, .TabBar, scene_constructor_tab_bar)
	scene_register(g, .HSeparator, scene_constructor_h_separator)
	scene_register(g, .VSeparator, scene_constructor_v_separator)
	scene_register(g, .MenuBar, scene_constructor_menu_bar)

	scene_register(g, .PopupMenu, scene_constructor_popup_menu)
	scene_register(g, .PopupPanel, scene_constructor_popup_panel)
	scene_register(g, .AcceptDialog, scene_constructor_accept_dialog)
	scene_register(g, .ConfirmationDialog, scene_constructor_confirmation_dialog)
	scene_register(g, .FileDialog, scene_constructor_file_dialog)

	scene_register(g, .Toast, scene_constructor_toast)
	scene_register(g, .CommandPalette, scene_constructor_command_palette)
	scene_register(g, .Rating, scene_constructor_rating)
	scene_register(g, .Segmented, scene_constructor_segmented)
	scene_register(g, .ToggleSwitch, scene_constructor_toggle_switch)
	scene_register(g, .ComboBox, scene_constructor_combo_box)
	scene_register(g, .VirtualList, scene_constructor_virtual_list)
	scene_register(g, .DataTable, scene_constructor_data_table)
	scene_register(g, .DatePicker, scene_constructor_date_picker)
	scene_register(g, .TimePicker, scene_constructor_time_picker)
	scene_register(g, .ColorPicker, scene_constructor_color_picker)
	scene_register(g, .EmojiPicker, scene_constructor_emoji_picker)
	scene_register(g, .Accordion, scene_constructor_accordion)
	scene_register(g, .ContextMenu, scene_constructor_context_menu)
	scene_register(g, .ChatInput, scene_constructor_chat_input)
	scene_register(g, .SearchField, scene_constructor_search_field)
	scene_register(g, .NumberInput, scene_constructor_number_input)
	scene_register(g, .Tooltip, scene_constructor_tooltip)

	scene_register(g, .Chart, scene_constructor_chart)
	scene_register(g, .NodeGraph, scene_constructor_node_graph)
	scene_register(g, .Canvas, scene_constructor_canvas)
	scene_register(g, .FileViewer, scene_constructor_file_viewer)
	scene_register(g, .RichTextEditor, scene_constructor_rich_text_editor)
	scene_register(g, .VectorDrawing, scene_constructor_vector_drawing)
	scene_register(g, .AudioPlayer, scene_constructor_audio_player)
}

Scene_Node :: struct {
	name:                string,
	type:                string,
	parent:              string,
	text:                string,
	anchors:             [4]f32,
	offsets:             [4]f32,
	colour:              [4]f32,
	bg:                  [4]f32,
	border:              [4]f32,
	padding:             [4]f32,
	min_size:            [2]f32,
	custom_min_size:     [2]f32,
	border_width:        f32,
	font_size:           f32,
	visible:             bool,
	has_anchors:         bool,
	has_offsets:         bool,
	has_colour:          bool,
	has_bg:              bool,
	has_border:          bool,
	has_border_width:    bool,
	has_padding:         bool,
	has_min_size:        bool,
	has_custom_min_size: bool,
	has_font_size:       bool,
	has_visible:         bool,
}

//* Reads a scene file into the nodes it describes. The strings of the
//* nodes are made in the allocator that is given, so that the widgets
//* that are made of them keep strings that are there for as long as the
//* program is.
scene_parse :: proc(text: string, allocator: mem.Allocator) -> [dynamic]Scene_Node {
	nodes: [dynamic]Scene_Node
	node := Scene_Node {
		visible = true,
	}
	have_node := false

	lines := strings.split_lines(text)
	defer delete(lines)

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {continue}
		//* A line that begins with a hash is a comment.
		if trimmed[0] == '#' {continue}

		if trimmed[0] == '[' {
			//* A new node, or a section the loader does not know.
			if have_node {
				append(&nodes, node)
				have_node = false
			}
			if scene_is_node_header(trimmed) {
				node = Scene_Node {
					name    = scene_attr(trimmed, "name", allocator),
					type    = scene_attr(trimmed, "type", allocator),
					parent  = scene_attr(trimmed, "parent", allocator),
					visible = true,
				}
				have_node = true
			}
			continue
		}

		if !have_node {continue}
		scene_apply_line(&node, trimmed, allocator)
	}
	if have_node {append(&nodes, node)}

	return nodes
}

//* Whether a line is the head of a node, e.g. `[node name="Root"]`.
scene_is_node_header :: proc(line: string) -> bool {
	i := 1
	for i < len(line) && scene_is_space(line[i]) {i += 1}
	start := i
	for i < len(line) && !scene_is_space(line[i]) && line[i] != ']' {i += 1}
	return line[start:i] == "node"
}

//* The value of an attribute of the head of a node, e.g. the "type" of
//* `[node name="Root" type="Panel"]`. The value is empty when the node
//* does not have the attribute, and it is made in the allocator that is
//* given, so that it is there for as long as the widgets are.
scene_attr :: proc(header: string, key: string, allocator: mem.Allocator) -> string {
	at := 0
	for at < len(header) {
		found := strings.index(header[at:], key)
		if found < 0 {return ""}
		start := at + found
		//* The key has to begin a word, or "type" would be found in "prototype".
		if start > 0 {
			c := header[start - 1]
			if !scene_is_space(c) && c != '[' {
				at = start + 1
				continue
			}
		}
		i := start + len(key)
		for i < len(header) && scene_is_space(header[i]) {i += 1}
		//* The key has to be followed by an '='.
		if i >= len(header) || header[i] != '=' {
			at = start + 1
			continue
		}
		i += 1
		for i < len(header) && scene_is_space(header[i]) {i += 1}
		if i < len(header) && header[i] == '"' {
			i += 1
			begin := i
			for i < len(header) && header[i] != '"' {i += 1}
			return strings.clone(header[begin:i], allocator)
		}
		//* A value that is not quoted runs to the next space.
		begin := i
		for i < len(header) && !scene_is_space(header[i]) && header[i] != ']' {i += 1}
		return strings.clone(header[begin:i], allocator)
	}
	return ""
}

//* Reads one `key = value` line into a node. A line that is not
//* understood is skipped, so that a file of a newer version still loads.
scene_apply_line :: proc(node: ^Scene_Node, line: string, allocator: mem.Allocator) {
	eq := strings.index(line, "=")
	if eq < 0 {return}
	key := strings.trim_space(line[:eq])
	value := strings.trim_space(line[eq + 1:])

	switch key {
	case "name":
		node.name = scene_string(value, allocator)
	case "type":
		node.type = scene_string(value, allocator)
	case "parent":
		node.parent = scene_string(value, allocator)
	case "text":
		node.text = scene_string(value, allocator)
	case "anchors":
		node.has_anchors = scene_numbers(value, node.anchors[:]) == 4
	case "offsets":
		node.has_offsets = scene_numbers(value, node.offsets[:]) == 4
	case "colour":
		node.has_colour = scene_numbers(value, node.colour[:]) == 4
	case "bg":
		node.has_bg = scene_numbers(value, node.bg[:]) == 4
	case "border":
		node.has_border = scene_numbers(value, node.border[:]) == 4
	case "border_width":
		number, ok := scene_number(value)
		if ok {
			node.border_width = number
			node.has_border_width = true
		}
	case "padding":
		node.has_padding = scene_numbers(value, node.padding[:]) == 4
	case "font_size":
		number, ok := scene_number(value)
		if ok {
			node.font_size = number
			node.has_font_size = true
		}
	case "visible":
		flag, ok := scene_bool(value)
		if ok {
			node.visible = flag
			node.has_visible = true
		}
	case "min_size":
		node.has_min_size = scene_numbers(value, node.min_size[:]) == 2
	case "custom_min_size":
		node.has_custom_min_size = scene_numbers(value, node.custom_min_size[:]) == 2
	}
}

//* The text of a value: the quotes around it are taken off, and the
//* escapes in it are worked out. The text is made in the allocator that
//* is given, so that it is there for as long as the widgets are.
scene_string :: proc(value: string, allocator: mem.Allocator) -> string {
	trimmed := strings.trim_space(value)
	if len(trimmed) == 0 || trimmed[0] != '"' {
		return strings.clone(trimmed, allocator)
	}

	rest := trimmed[1:]
	end := strings.index(rest, "\"")
	if end < 0 {return strings.clone(rest, allocator)}
	body := rest[:end]

	if strings.index(body, "\\") < 0 {return strings.clone(body, allocator)}

	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, len(body), allocator); err != nil {
		return strings.clone(body, allocator)
	}
	i := 0
	for i < len(body) {
		c := body[i]
		if c == '\\' && i + 1 < len(body) {
			i += 1
			switch body[i] {
			case 'n':
				strings.write_byte(&builder, '\n')
			case 't':
				strings.write_byte(&builder, '\t')
			case 'r':
				strings.write_byte(&builder, '\r')
			case '"':
				strings.write_byte(&builder, '"')
			case '\\':
				strings.write_byte(&builder, '\\')
			case:
				strings.write_byte(&builder, body[i])
			}
			i += 1
			continue
		}
		strings.write_byte(&builder, c)
		i += 1
	}
	return strings.to_string(builder)
}

//* The numbers of a value: "{1, 2, 3, 4}" and "1, 2, 3, 4" are the same.
//* The count of the numbers is returned.
scene_numbers :: proc(value: string, out: []f32) -> int {
	count := 0
	i := 0
	braced := false
	for i < len(value) {
		if value[i] == '{' {
			braced = true
			i += 1
			break
		}
		if !scene_is_space(value[i]) {break}
		i += 1
	}
	for i < len(value) && count < len(out) {
		for i < len(value) && (scene_is_space(value[i]) || value[i] == ',') {i += 1}
		if i >= len(value) {break}
		if braced && value[i] == '}' {break}
		start := i
		for i < len(value) && value[i] != ',' && value[i] != '}' {i += 1}
		number, ok := strconv.parse_f32(strings.trim_space(value[start:i]))
		if !ok {break}
		out[count] = number
		count += 1
	}
	return count
}

scene_number :: proc(value: string) -> (f32, bool) {
	return strconv.parse_f32(strings.trim_space(value))
}

//* The flag of a value: "true" or "false".
scene_bool :: proc(value: string) -> (bool, bool) {
	trimmed := strings.trim_space(value)
	if trimmed == "true" {return true, true}
	if trimmed == "false" {return false, true}
	return false, false
}

scene_is_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}


scene_load :: proc(g: ^GUI, text: string) -> Widget_ID {
	scene_register_defaults(g)
	nodes := scene_parse(text, virt.arena_allocator(&g.arena))
	defer delete(nodes)

	built := make(map[string]Widget_ID)
	defer delete(built)

	waiting: [dynamic]int
	defer delete(waiting)

	root := INVALID_WIDGET_ID
	for i in 0 ..< len(nodes) {
		node := nodes[i]

		parent := g.root
		if node.parent != "" {
			p, found := built[node.parent]
			if !found {
				append(&waiting, i)
				continue
			}
			parent = p
		}

		id := scene_make(g, node, parent)
		if node.name != "" {
			if id == INVALID_WIDGET_ID {
				built[node.name] = parent
			} else {
				built[node.name] = id
			}
		}
		if id != INVALID_WIDGET_ID && root == INVALID_WIDGET_ID {
			root = id
		}

		scene_make_waiting(g, nodes, &built, &waiting)
	}

	for i in waiting {
		node := nodes[i]
		log.warnf("scene: the parent %q of %q is not in the file", node.parent, node.name)
		scene_make(g, node, g.root)
	}

	return root
}

scene_make_waiting :: proc(
	g: ^GUI,
	nodes: [dynamic]Scene_Node,
	built: ^map[string]Widget_ID,
	waiting: ^[dynamic]int,
) {
	i := 0
	for i < len(waiting) {
		node := nodes[waiting[i]]
		p, found := built^[node.parent]
		if !found {
			i += 1
			continue
		}
		id := scene_make(g, node, p)
		if node.name != "" {
			if id == INVALID_WIDGET_ID {
				built^[node.name] = p
			} else {
				built^[node.name] = id
			}
		}
		ordered_remove(waiting, i)
	}
}

//* Makes the widget of a node and puts the look of the node on it. An
//* invalid widget is returned when the kind of widget has no constructor.
scene_make :: proc(g: ^GUI, node: Scene_Node, parent: Widget_ID) -> Widget_ID {
	//* A class of a program's own is named in the file as well: the
	//* class says how one of its widgets is made. A class without a
	//* constructor of its own falls back on the widget of that type.
	if id, found := class_by_name(g, node.type); found {
		c, _ := class_get(g, id)
		if c.constructor != nil {
			return scene_place(g, c.constructor(g, parent, node.name, node.text), node, c.type)
		}
	}

	widget_type, ok := fmt.string_to_enum_value(Widget_Type, node.type)
	if !ok {
		log.warnf("scene: there is no widget called %q", node.type)
		return INVALID_WIDGET_ID
	}
	constructor := scene_constructor(g, widget_type)
	if constructor == nil {
		log.warnf("scene: there is no constructor for the widget %q", node.type)
		return INVALID_WIDGET_ID
	}
	return scene_place(g, constructor(g, parent, node.name, node.text), node, widget_type)
}

scene_place :: proc(
	g: ^GUI,
	id: Widget_ID,
	node: Scene_Node,
	widget_type: Widget_Type,
) -> Widget_ID {
	if id == INVALID_WIDGET_ID {return INVALID_WIDGET_ID}
	w := Widget_Get(g, id)
	if w == nil {return INVALID_WIDGET_ID}

	if node.has_anchors {
		w.anchors = Anchor{node.anchors[0], node.anchors[1], node.anchors[2], node.anchors[3]}
	}
	if node.has_offsets {
		w.offsets = Offset{node.offsets[0], node.offsets[1], node.offsets[2], node.offsets[3]}
	}
	if node.has_min_size {
		w.base_min_size = Vec2{node.min_size[0], node.min_size[1]}
		w.min_size = w.base_min_size
	}
	if node.has_custom_min_size {
		w.custom_min_size = Vec2{node.custom_min_size[0], node.custom_min_size[1]}
	}
	if node.has_visible && !node.visible {
		w.state -= Widget_State{.Visible}
	}
	w.use_theme = true
	w.style = scene_style(node)
	if widget_type == .ColorRect && node.has_bg {
		#partial switch &d in w.data {
		case Color_Rect_Data:
			d.colour = Colour{node.bg[0], node.bg[1], node.bg[2], node.bg[3]}
		}
	}

	return id
}

//* The style of a node: the box around the widget and the text in it.
scene_style :: proc(node: Scene_Node) -> Style {
	style := Style{}
	if node.has_bg {
		style.box.bg_color = Colour{node.bg[0], node.bg[1], node.bg[2], node.bg[3]}
	}
	if node.has_border {
		c := Colour{node.border[0], node.border[1], node.border[2], node.border[3]}
		style.box.border_color = {c, c, c, c}
	}
	if node.has_border_width {
		width := node.border_width
		style.box.border_width = {width, width, width, width}
	}
	if node.has_padding {
		style.box.content_margin = {
			node.padding[0],
			node.padding[1],
			node.padding[2],
			node.padding[3],
		}
	}
	if node.has_colour {
		style.text.colour = Colour{node.colour[0], node.colour[1], node.colour[2], node.colour[3]}
	}
	if node.has_font_size {
		style.text.size = node.font_size
	}
	return style
}
