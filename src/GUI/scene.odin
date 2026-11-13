//* Loads scene files: widget trees described in a Godot-style text format.
//* See docs/scene-format.md for the syntax and supported properties.
//
//* The loader parses and validates a document before creating its widget
//* tree. Issues are collected in a report with severity, line, node, and
//* property information.
//
//* | Issue | Severity | Result |
//* |---|---|---|
//* | Unknown property | Warning | Ignored |
//* | Unsupported property for widget type | Warning | Ignored |
//* | Invalid property value | Warning | Ignored |
//* | Missing node type | Error | Node skipped |
//* | Unknown widget type | Error | Node skipped |
//* | Missing constructor | Error | Node skipped |
//* | Duplicate node name | Error | Later node skipped |
//* | Missing parent | Error | Node attached to root |
//* | Node is its own parent | Error | Node attached to root |
//* | Parent cycle | Error | Affected nodes attached to root |
//
//* Skipped nodes retain their names, so their children attach to the
//* skipped node's resolved parent. For duplicate names, the first node
//* owns the name.
//
//* Unknown sections and lines are ignored. Nodes whose parents appear
//* later are deferred until their parents are created.
//
//* == Document ownership ==
//* Parsed strings are allocated by the allocator passed to Scene_Parse.
//* Scene_Doc_Destroy releases them, including strings replaced while
//* parsing or validation. Hand-built documents have no owned allocator;
//* their strings remain the caller's responsibility.
//
//* Arena allocations are reclaimed when the arena is destroyed. With a
//* heap allocator, destroying the document releases its strings.
//
//* == Widget ownership ==
//* Widgets copy their node name and text into the GUI arena. The document
//* can therefore be destroyed after instantiation.
//
//* == Font ownership ==
//* Font families belong to the GUI and are released with it. Widgets
//* store only a family ID; font names remain owned by the document.
//
//* == Report ownership ==
//* Reports own their entries and message strings. Release them with
//* Scene_Report_Destroy.

package GUI

import "core:fmt"
import "core:log"
import "core:mem"
import virt "core:mem/virtual"
import "core:strconv"
import "core:strings"

//* == Node properties ==
//* Properties shared by all widget types.
SCENE_PROPERTIES_COMMON :: [12]string {
	"anchors",
	"offsets",
	"min_size",
	"custom_min_size",
	"visible",
	"font_size",
	"font",
	"colour",
	"border",
	"border_width",
	"padding",
	"bg",
}

//* Widget types that accept their own text property.
SCENE_TYPES_WITH_TEXT :: [17]Widget_Type {
	.Button,
	.Label,
	.TextBox,
	.CheckBox,
	.MenuButton,
	.LinkButton,
	.RichTextLabel,
	.AcceptDialog,
	.ConfirmationDialog,
	.Toast,
	.CommandPalette,
	.ToggleSwitch,
	.RichTextEditor,
	.ChatInput,
	.SearchField,
	.Tooltip,
	.EmojiPicker,
}

//* Creates a widget for a scene node.
Scene_Constructor :: proc(g: ^GUI, parent: Widget_ID, name: string, text: string) -> Widget_ID

//* == Scene document ==
//* A scene is a list of nodes, each introduced by a [node ...] header.
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

//* A parsed property and its source line.
Scene_Property :: struct {
	key:   string,
	value: string,
	line:  int,
}

//* A scene node and its parsed properties.
Scene_Node :: struct {
	name:                string,
	type:                string,
	parent:              string,
	text:                string,
	//* The name of the family of the fonts of the GUI that the text of
	//* the node is set in.
	font:                string,
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
	has_font:            bool,
	has_visible:         bool,
	//* The line of the file the node begins on. The first line of the
	//* file is line 1.
	line:                int,
	//* The path of the node: the name of the node under the path of its
	//* parent. The path of a node without a parent is its name.
	path:                string,
	//* The lines of the node that were read, with the line they are on.
	properties:          [dynamic]Scene_Property,
	//* Whether the node keeps the name: the first node of that name in
	//* the file keeps it.
	owns_name:           bool,
	//* Whether the node cannot be made.
	skipped:             bool,
}

//* Parsed scene document. Parsed strings belong to allocator.
Scene_Doc :: struct {
	nodes:     [dynamic]Scene_Node,
	allocator: mem.Allocator,
}

//* Releases document strings and property arrays. Hand-built documents
//* have no allocator, so their strings are left untouched.
//
//* Root paths share the node name and are not freed separately.
Scene_Doc_Destroy :: proc(doc: ^Scene_Doc) {
	if doc == nil {return}
	allocator := doc.allocator
	for &node in doc.nodes {
		if allocator.procedure != nil {
			delete(node.name, allocator)
			delete(node.type, allocator)
			delete(node.parent, allocator)
			delete(node.text, allocator)
			delete(node.font, allocator)
			if node.parent != "" {delete(node.path, allocator)}
			for &property in node.properties {
				delete(property.key, allocator)
				delete(property.value, allocator)
			}
		}
		delete(node.properties)
	}
	delete(doc.nodes)
}

//* == Loading scenes ==

//* Loads a scene and logs any reported issues.
Scene_Load :: proc(g: ^GUI, text: string) -> Widget_ID {
	root, report := Scene_Load_Report(g, text)
	defer Scene_Report_Destroy(&report)
	scene_report_log(report)
	return root
}

//* Loads a scene and returns its report. Report strings use the GUI arena;
//* release the report with Scene_Report_Destroy.
Scene_Load_Report :: proc(g: ^GUI, text: string) -> (Widget_ID, Scene_Report) {
	report: Scene_Report
	if g == nil {return INVALID_WIDGET_ID, report}

	allocator := virt.arena_allocator(&g.arena)
	doc, parse_report := Scene_Parse(text, allocator)
	defer Scene_Doc_Destroy(&doc)
	report = parse_report

	root, more := Scene_Instantiate(g, doc)
	scene_report_merge(&report, &more)
	return root, report
}

//* Parses a scene into a reusable document. Document strings and report
//* strings use the supplied allocator.
Scene_Parse :: proc(text: string, allocator: mem.Allocator) -> (Scene_Doc, Scene_Report) {
	return scene_parse(text, allocator)
}

//* Instantiates a document without modifying it. The document can be
//* instantiated more than once. Report strings use the GUI arena.
Scene_Instantiate :: proc(g: ^GUI, doc: Scene_Doc) -> (Widget_ID, Scene_Report) {
	report: Scene_Report
	if g == nil {return INVALID_WIDGET_ID, report}
	report.allocator = virt.arena_allocator(&g.arena)

	scene_register_defaults(g)

	built := make(map[string]Widget_ID)
	defer delete(built)

	waiting: [dynamic]int
	defer delete(waiting)

	root := INVALID_WIDGET_ID
	for index in 0 ..< len(doc.nodes) {
		node := doc.nodes[index]

		parent := g.root
		if node.parent != "" {
			p, found := built[node.parent]
			if !found {
				append(&waiting, index)
				continue
			}
			parent = p
		}

		id := INVALID_WIDGET_ID
		if !node.skipped {
			id = scene_make(g, node, parent, &report)
		}
		if node.owns_name {
			if id == INVALID_WIDGET_ID {
				//* The node could not be made: the children of the
				//* node hang under the node it would have hung under.
				built[node.name] = parent
			} else {
				built[node.name] = id
			}
		}
		if id != INVALID_WIDGET_ID && root == INVALID_WIDGET_ID {
			root = id
		}

		made := scene_make_waiting(g, doc, &built, &waiting, &report)
		if root == INVALID_WIDGET_ID && made != INVALID_WIDGET_ID {
			root = made
		}
	}

	return root, report
}

//* Registers a widget constructor. A nil constructor is rejected;
//* registering an existing type replaces its constructor.
Scene_Register_Constructor :: proc(
	g: ^GUI,
	widget_type: Widget_Type,
	constructor: Scene_Constructor,
) -> bool {
	if g == nil {return false}
	if constructor == nil {
		log.warnf("scene: the constructor of the widget %q is nothing", type_name_of(widget_type))
		return false
	}

	index := int(widget_type)
	for len(g.scene_constructors) <= index {
		append(&g.scene_constructors, nil)
	}
	if g.scene_constructors[index] != nil {
		log.warnf(
			"scene: the constructor of the widget %q replaces the one that was there",
			type_name_of(widget_type),
		)
	}
	g.scene_constructors[index] = constructor
	return true
}

//* Returns the registered constructor, or nil if none exists.
Scene_Constructor_Of :: proc(g: ^GUI, widget_type: Widget_Type) -> Scene_Constructor {
	if g == nil {return nil}
	index := int(widget_type)
	if index < 0 || index >= len(g.scene_constructors) {return nil}
	return g.scene_constructors[index]
}

//* == Finding widgets ==
//* Paths use node names separated by '/'. For example:
//* Root/Box/Ok
//*
//* Duplicate child names resolve to the first matching child.
Scene_Find :: proc(g: ^GUI, root: Widget_ID, path: string) -> Widget_ID {
	if g == nil || path == "" {return INVALID_WIDGET_ID}

	names: [dynamic]string
	defer delete(names)
	scene_split_path(path, &names)
	if len(names) == 0 {return INVALID_WIDGET_ID}

	w := Widget_Get(g, root)
	if w == nil {return INVALID_WIDGET_ID}
	if w.name != names[0] {return INVALID_WIDGET_ID}

	current := root
	for name in names[1:] {
		current = scene_find_child(g, current, name)
		if current == INVALID_WIDGET_ID {return INVALID_WIDGET_ID}
	}
	return current
}

//* Splits a widget path into its names.
scene_split_path :: proc(path: string, names: ^[dynamic]string) {
	start := 0
	for i in 0 ..< len(path) {
		if path[i] != '/' {continue}
		append(names, path[start:i])
		start = i + 1
	}
	append(names, path[start:])
}

//* Returns the first child with the requested name.
scene_find_child :: proc(g: ^GUI, id: Widget_ID, name: string) -> Widget_ID {
	w := Widget_Get(g, id)
	if w == nil {return INVALID_WIDGET_ID}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil {break}
		if c.name == name {return child}
		child = c.next_sibling
	}
	return INVALID_WIDGET_ID
}

//* == Widget constructors ==

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

scene_constructor_text_box :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	return Make_Text_Box(
		g,
		parent,
		Text_Box_Opts{Base_Opts = Base_Opts{name = name}, text = text},
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
	Widget_Set_Name(g, id, name)
	return id
}

scene_constructor_v_separator :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	id := Make_Separator(g, parent, true)
	Widget_Set_Name(g, id, name)
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
	id := Make_Command_Palette(
		g,
		parent,
		Command_Palette_Opts{Base_Opts = Base_Opts{name = name}},
	)
	//* The text of a palette is the text of its filter.
	if text != "" {Command_Palette_Set_Text(g, id, text)}
	return id
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
	id := Make_Chat_Input(g, parent, Chat_Input_Opts{Base_Opts = Base_Opts{name = name}})
	//* The text of a chat input is the text in its field.
	if text != "" {chat_input_set_text(g, id, text)}
	return id
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

//* Registers the built-in constructors once. Custom registrations are
//* preserved and can override defaults.
scene_register_defaults :: proc(g: ^GUI) {
	if g == nil {return}
	if g.scene_defaults_registered {return}
	g.scene_defaults_registered = true

	scene_register_default(g, .Panel, scene_constructor_panel)
	scene_register_default(g, .Button, scene_constructor_button)
	scene_register_default(g, .Label, scene_constructor_label)
	scene_register_default(g, .TextBox, scene_constructor_text_box)
	scene_register_default(g, .VBox, scene_constructor_vbox)
	scene_register_default(g, .HBox, scene_constructor_hbox)
	scene_register_default(g, .Split, scene_constructor_split)
	scene_register_default(g, .Tabs, scene_constructor_tabs)

	scene_register_default(g, .GridContainer, scene_constructor_grid)
	scene_register_default(g, .MarginContainer, scene_constructor_margin)
	scene_register_default(g, .CenterContainer, scene_constructor_center)
	scene_register_default(g, .PanelContainer, scene_constructor_panel_container)
	scene_register_default(g, .ScrollContainer, scene_constructor_scroll_container)
	scene_register_default(g, .FlowContainer, scene_constructor_flow)
	scene_register_default(g, .AspectRatioContainer, scene_constructor_aspect)
	scene_register_default(g, .TabContainer, scene_constructor_tab_container)

	scene_register_default(g, .CheckBox, scene_constructor_check_box)
	scene_register_default(g, .OptionButton, scene_constructor_option_button)
	scene_register_default(g, .MenuButton, scene_constructor_menu_button)
	scene_register_default(g, .LinkButton, scene_constructor_link_button)

	scene_register_default(g, .HSlider, scene_constructor_h_slider)
	scene_register_default(g, .VSlider, scene_constructor_v_slider)
	scene_register_default(g, .SpinBox, scene_constructor_spin_box)
	scene_register_default(g, .ProgressBar, scene_constructor_progress_bar)

	scene_register_default(g, .ColorRect, scene_constructor_color_rect)
	scene_register_default(g, .TextureRect, scene_constructor_texture_rect)
	scene_register_default(g, .NinePatchRect, scene_constructor_nine_patch)
	scene_register_default(g, .ReferenceRect, scene_constructor_reference_rect)
	scene_register_default(g, .RichTextLabel, scene_constructor_rich_text_label)
	scene_register_default(g, .ItemList, scene_constructor_item_list)
	scene_register_default(g, .Tree, scene_constructor_tree)
	scene_register_default(g, .TabBar, scene_constructor_tab_bar)
	scene_register_default(g, .HSeparator, scene_constructor_h_separator)
	scene_register_default(g, .VSeparator, scene_constructor_v_separator)
	scene_register_default(g, .MenuBar, scene_constructor_menu_bar)

	scene_register_default(g, .PopupMenu, scene_constructor_popup_menu)
	scene_register_default(g, .PopupPanel, scene_constructor_popup_panel)
	scene_register_default(g, .AcceptDialog, scene_constructor_accept_dialog)
	scene_register_default(g, .ConfirmationDialog, scene_constructor_confirmation_dialog)
	scene_register_default(g, .FileDialog, scene_constructor_file_dialog)

	scene_register_default(g, .Toast, scene_constructor_toast)
	scene_register_default(g, .CommandPalette, scene_constructor_command_palette)
	scene_register_default(g, .Rating, scene_constructor_rating)
	scene_register_default(g, .Segmented, scene_constructor_segmented)
	scene_register_default(g, .ToggleSwitch, scene_constructor_toggle_switch)
	scene_register_default(g, .ComboBox, scene_constructor_combo_box)
	scene_register_default(g, .VirtualList, scene_constructor_virtual_list)
	scene_register_default(g, .DataTable, scene_constructor_data_table)
	scene_register_default(g, .DatePicker, scene_constructor_date_picker)
	scene_register_default(g, .TimePicker, scene_constructor_time_picker)
	scene_register_default(g, .ColorPicker, scene_constructor_color_picker)
	scene_register_default(g, .EmojiPicker, scene_constructor_emoji_picker)
	scene_register_default(g, .Accordion, scene_constructor_accordion)
	scene_register_default(g, .ContextMenu, scene_constructor_context_menu)
	scene_register_default(g, .ChatInput, scene_constructor_chat_input)
	scene_register_default(g, .SearchField, scene_constructor_search_field)
	scene_register_default(g, .NumberInput, scene_constructor_number_input)
	scene_register_default(g, .Tooltip, scene_constructor_tooltip)

	scene_register_default(g, .Chart, scene_constructor_chart)
	scene_register_default(g, .NodeGraph, scene_constructor_node_graph)
	scene_register_default(g, .Canvas, scene_constructor_canvas)
	scene_register_default(g, .FileViewer, scene_constructor_file_viewer)
	scene_register_default(g, .RichTextEditor, scene_constructor_rich_text_editor)
	scene_register_default(g, .VectorDrawing, scene_constructor_vector_drawing)
	scene_register_default(g, .AudioPlayer, scene_constructor_audio_player)
}

//* Registers a default only when no constructor is already present.
scene_register_default :: proc(g: ^GUI, widget_type: Widget_Type, constructor: Scene_Constructor) {
	index := int(widget_type)
	for len(g.scene_constructors) <= index {
		append(&g.scene_constructors, nil)
	}
	if g.scene_constructors[index] != nil {return}
	g.scene_constructors[index] = constructor
}

//* == Parsing ==

//* Parses nodes and properties, then validates the document.
//* Document and report strings use the supplied allocator.
scene_parse :: proc(text: string, allocator: mem.Allocator) -> (Scene_Doc, Scene_Report) {
	doc: Scene_Doc
	doc.allocator = allocator
	report: Scene_Report
	report.allocator = allocator

	node := Scene_Node {
		visible = true,
	}
	props: [dynamic]Scene_Property
	have_node := false

	lines := strings.split_lines(text)
	defer delete(lines)

	for line, number in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {continue}
		//* A line that begins with a hash is a comment.
		if trimmed[0] == '#' {continue}

		if trimmed[0] == '[' {
			//* A new node, or a section the loader does not know.
			if have_node {
				node.properties = props
				append(&doc.nodes, node)
				props = nil
				have_node = false
			}
			if scene_is_node_header(trimmed) {
				node = Scene_Node {
					name    = scene_attr(trimmed, "name", allocator),
					type    = scene_attr(trimmed, "type", allocator),
					parent  = scene_attr(trimmed, "parent", allocator),
					visible = true,
					line    = number + 1,
				}
				have_node = true
			}
			continue
		}

		if !have_node {continue}
		scene_read_line(&node, &props, trimmed, number + 1, allocator)
	}
	if have_node {
		node.properties = props
		append(&doc.nodes, node)
	}

	scene_validate(&doc, &report, allocator)
	return doc, report
}

//* Returns true for a [node ...] header.
scene_is_node_header :: proc(line: string) -> bool {
	i := 1
	for i < len(line) && scene_is_space(line[i]) {i += 1}
	start := i
	for i < len(line) && !scene_is_space(line[i]) && line[i] != ']' {i += 1}
	return line[start:i] == "node"
}

//* Reads a quoted or unquoted node-header attribute.
//* Quoted values support backslash escapes.
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
			return scene_quoted(header[i:], allocator)
		}
		//* A value that is not quoted runs to the next space.
		begin := i
		for i < len(header) && !scene_is_space(header[i]) && header[i] != ']' {i += 1}
		return strings.clone(header[begin:i], allocator)
	}
	return ""
}

//* Parses a property line and records its source line.
//* Unrecognized or invalid values are left unused.
scene_read_line :: proc(
	node: ^Scene_Node,
	props: ^[dynamic]Scene_Property,
	line: string,
	number: int,
	allocator: mem.Allocator,
) {
	eq := strings.index(line, "=")
	if eq < 0 {return}
	key := strings.trim_space(line[:eq])
	value := strings.trim_space(line[eq + 1:])
	if key == "" {return}

	append(props, Scene_Property {
		key   = strings.clone(key, allocator),
		value = strings.clone(value, allocator),
		line  = number,
	})

	switch key {
	case "name":
		scene_replace_string(&node.name, value, allocator)
	case "type":
		scene_replace_string(&node.type, value, allocator)
	case "parent":
		scene_replace_string(&node.parent, value, allocator)
	case "text":
		scene_replace_string(&node.text, value, allocator)
	case "anchors":
		node.has_anchors = scene_read_numbers(value, node.anchors[:], 4)
	case "offsets":
		node.has_offsets = scene_read_numbers(value, node.offsets[:], 4)
	case "colour":
		node.has_colour = scene_read_numbers(value, node.colour[:], 4)
	case "bg":
		node.has_bg = scene_read_numbers(value, node.bg[:], 4)
	case "border":
		node.has_border = scene_read_numbers(value, node.border[:], 4)
	case "border_width":
		number, ok := scene_number(value)
		if ok {
			node.border_width = number
			node.has_border_width = true
		}
	case "padding":
		node.has_padding = scene_read_numbers(value, node.padding[:], 4)
	case "font_size":
		number, ok := scene_number(value)
		if ok {
			node.font_size = number
			node.has_font_size = true
		}
	case "font":
		scene_replace_string(&node.font, value, allocator)
		node.has_font = true
	case "visible":
		flag, ok := scene_bool(value)
		if ok {
			node.visible = flag
			node.has_visible = true
		}
	case "min_size":
		node.has_min_size = scene_read_numbers(value, node.min_size[:], 2)
	case "custom_min_size":
		node.has_custom_min_size = scene_read_numbers(value, node.custom_min_size[:], 2)
	}
}

//* Replaces a string using the supplied allocator.
scene_replace_string :: proc(target: ^string, value: string, allocator: mem.Allocator) {
	old := target^
	target^ = scene_string(value, allocator)
	delete(old, allocator)
}

//* Clears a string and releases its allocation.
scene_clear_string :: proc(target: ^string, allocator: mem.Allocator) {
	old := target^
	target^ = ""
	delete(old, allocator)
}

//* Copies a value, removing surrounding quotes and decoding escapes.
scene_string :: proc(value: string, allocator: mem.Allocator) -> string {
	trimmed := strings.trim_space(value)
	if len(trimmed) == 0 || trimmed[0] != '"' {
		return strings.clone(trimmed, allocator)
	}
	return scene_quoted(trimmed[1:], allocator)
}

//* Decodes a quoted value. Supports \n, \t, \r, \", and \\.
scene_quoted :: proc(rest: string, allocator: mem.Allocator) -> string {
	end := scene_quote_end(rest)
	body := rest
	if end >= 0 {body = rest[:end]}

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

//* Finds the closing quote, accounting for escaped backslashes.
scene_quote_end :: proc(text: string) -> int {
	slashes := 0
	for i in 0 ..< len(text) {
		if text[i] == '\\' {
			slashes += 1
			continue
		}
		if text[i] == '"' && slashes % 2 == 0 {return i}
		slashes = 0
	}
	return -1
}

//* Parses comma-separated numbers, optionally enclosed in braces.
//* Returns the number parsed, or -1 on invalid input.
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
	for i < len(value) {
		for i < len(value) && (scene_is_space(value[i]) || value[i] == ',') {i += 1}
		if i >= len(value) {break}
		if braced && value[i] == '}' {break}
		start := i
		for i < len(value) && value[i] != ',' && value[i] != '}' {i += 1}
		number, ok := strconv.parse_f32(strings.trim_space(value[start:i]))
		if !ok {return -1}
		if count < len(out) {out[count] = number}
		count += 1
	}
	return count
}

//* Reads exactly count numbers into out.
scene_read_numbers :: proc(value: string, out: []f32, count: int) -> bool {
	return scene_numbers(value, out) == count
}

//* Parses a floating-point value.
scene_number :: proc(value: string) -> (f32, bool) {
	return strconv.parse_f32(strings.trim_space(value))
}

//* Parses true or false.
scene_bool :: proc(value: string) -> (bool, bool) {
	trimmed := strings.trim_space(value)
	if trimmed == "true" {return true, true}
	if trimmed == "false" {return false, true}
	return false, false
}

//* Returns whether a character is whitespace.
scene_is_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

//* == Validation ==

//* Returns the expected number of values for a list property.
scene_property_count :: proc(key: string) -> int {
	switch key {
	case "anchors", "offsets", "colour", "bg", "border", "padding":
		return 4
	case "min_size", "custom_min_size":
		return 2
	}
	return 0
}

//* Formats a report message using the supplied allocator.
scene_message :: proc(allocator: mem.Allocator, format: string, args: ..any) -> string {
	return fmt.aprintf(format, ..args, allocator = allocator)
}

//* Identifies node-header attributes.
scene_property_attribute :: proc(key: string) -> bool {
	return key == "name" || key == "type" || key == "parent"
}

//* Returns whether the loader recognizes a property.
scene_property_known :: proc(key: string) -> bool {
	if scene_property_attribute(key) {return true}
	if key == "text" {return true}
	return scene_property_common(key)
}

//* Returns whether a property applies to every widget type.
scene_property_common :: proc(key: string) -> bool {
	for common in SCENE_PROPERTIES_COMMON {
		if common == key {return true}
	}
	return false
}

//* Returns whether a widget type accepts its own text.
scene_type_shows_text :: proc(widget_type: Widget_Type) -> bool {
	for kind in SCENE_TYPES_WITH_TEXT {
		if kind == widget_type {return true}
	}
	return false
}

//* Returns whether a property applies to the given widget type.
scene_property_used :: proc(widget_type: Widget_Type, key: string) -> bool {
	if scene_property_attribute(key) {return true}
	if key == "text" {return scene_type_shows_text(widget_type)}
	return scene_property_common(key)
}

//* Validates node names, types, parents, and parent cycles.
//* Invalid nodes are marked for skipping; invalid parent links are
//* cleared so affected nodes attach to the GUI root.
scene_validate :: proc(doc: ^Scene_Doc, report: ^Scene_Report, allocator: mem.Allocator) {
	first := make(map[string]int)
	defer delete(first)

	for index in 0 ..< len(doc.nodes) {
		node := &doc.nodes[index]
		scene_check_properties(node, report)

		bad := false
		if node.type == "" {
			scene_report_add(report, .Error, node.line, node.name, "", "the node has no type")
			bad = true
		}
		if node.name != "" {
			if _, taken := first[node.name]; taken {
				scene_report_add(
					report,
					.Error,
					node.line,
					node.name,
					"",
					"the name %q is used by more than one node",
					node.name,
				)
				bad = true
			} else {
				first[node.name] = index
				node.owns_name = true
			}
		}
		if bad {node.skipped = true}
	}

	//* The parent of a node has to be in the file, and it has to be
	//* another node.
	parent_of := make([]int, len(doc.nodes))
	defer delete(parent_of)
	for index in 0 ..< len(doc.nodes) {
		node := &doc.nodes[index]
		parent_of[index] = -1
		if node.parent == "" {continue}

		p, found := first[node.parent]
		if !found {
			scene_report_add(
				report,
				.Error,
				node.line,
				node.name,
				"",
				"the parent %q of the node %q is not in the file",
				node.parent,
				node.name,
			)
			//* The node goes to the root, and the string of the parent
			//* is given back.
			scene_clear_string(&node.parent, allocator)
			continue
		}
		if p == index {
			scene_report_add(
				report,
				.Error,
				node.line,
				node.name,
				"",
				"the node %q is its own parent",
				node.name,
			)
			//* The node goes to the root, and the string of the parent
			//* is given back.
			scene_clear_string(&node.parent, allocator)
			continue
		}
		parent_of[index] = p
	}

	//* The parents of the nodes cannot make a circle.
	scene_check_circles(doc, parent_of, report, allocator)

	//* The path of every node.
	for index in 0 ..< len(doc.nodes) {
		scene_path_of(doc, index, &first, allocator)
	}
}

//* Reports unknown and unsupported properties.
scene_check_properties :: proc(node: ^Scene_Node, report: ^Scene_Report) {
	widget_type, is_kind := fmt.string_to_enum_value(Widget_Type, node.type)
	for property in node.properties {
		if !scene_property_known(property.key) {
			scene_report_add(
				report,
				.Warning,
				property.line,
				node.name,
				property.key,
				"unknown property %q",
				property.key,
			)
			continue
		}
		if is_kind && !scene_property_used(widget_type, property.key) {
			scene_report_add(
				report,
				.Warning,
				property.line,
				node.name,
				property.key,
				"the property %q is not used by a %s",
				property.key,
				type_name_of(widget_type),
			)
			continue
		}
		scene_check_value(node, property, report)
	}
}

//* Reports properties unsupported by the given widget type.
scene_check_kind_properties :: proc(
	node: Scene_Node,
	widget_type: Widget_Type,
	report: ^Scene_Report,
) {
	for property in node.properties {
		if !scene_property_known(property.key) {continue}
		if scene_property_used(widget_type, property.key) {continue}
		scene_report_add(
			report,
			.Warning,
			property.line,
			node.name,
			property.key,
			"the property %q is not used by a %s",
			property.key,
			type_name_of(widget_type),
		)
	}
}

//* Checks whether a property value matches its expected format.
scene_check_value :: proc(
	node: ^Scene_Node,
	property: Scene_Property,
	report: ^Scene_Report,
) {
	switch property.key {
	case "border_width", "font_size":
		if _, ok := scene_number(property.value); !ok {
			scene_report_add(
				report,
				.Warning,
				property.line,
				node.name,
				property.key,
				"the value of %q is not a number",
				property.key,
			)
		}
	case "visible":
		if _, ok := scene_bool(property.value); !ok {
			scene_report_add(
				report,
				.Warning,
				property.line,
				node.name,
				property.key,
				"the value of %q is not true or false",
				property.key,
			)
		}
	case:
		count := scene_property_count(property.key)
		if count == 0 {return}
		numbers: [4]f32
		if scene_numbers(property.value, numbers[:]) != count {
			scene_report_add(
				report,
				.Warning,
				property.line,
				node.name,
				property.key,
				"the value of %q is not %d numbers",
				property.key,
				count,
			)
		}
	}
}

//* Finds parent cycles and detaches their nodes from the hierarchy.
scene_check_circles :: proc(
	doc: ^Scene_Doc,
	parent_of: []int,
	report: ^Scene_Report,
	allocator: mem.Allocator,
) {
	//* The state of a node: 0 when it has not been looked at, 1 when it
	//* is in the chain that is being walked, and 2 when it is done.
	state := make([]int, len(doc.nodes))
	defer delete(state)
	chain: [dynamic]int
	defer delete(chain)

	for index in 0 ..< len(doc.nodes) {
		if state[index] != 0 {continue}
		clear(&chain)

		cur := index
		for cur >= 0 && state[cur] == 0 {
			state[cur] = 1
			append(&chain, cur)
			cur = parent_of[cur]
		}

		if cur >= 0 && state[cur] == 1 {
			//* The walk came back to a node of the chain: the parents
			//* of the nodes make a circle.
			start := 0
			for k in 0 ..< len(chain) {
				if chain[k] == cur {start = k; break}
			}
			for k in start ..< len(chain) {
				node := &doc.nodes[chain[k]]
				//* The node goes to the root, and the string of the
				//* parent is given back.
				scene_clear_string(&node.parent, allocator)
				parent_of[chain[k]] = -1
				state[chain[k]] = 2
			}
			//* The message names every node of the circle.
			scene_report_add_message(
				report,
				.Error,
				doc.nodes[chain[start]].line,
				doc.nodes[chain[start]].name,
				"",
				scene_circle_message(doc, chain[start:], report),
			)
		}

		for k in 0 ..< len(chain) {
			if state[chain[k]] == 1 {state[chain[k]] = 2}
		}
	}
}

//* Builds the error message listing the nodes in a parent cycle.
scene_circle_message :: proc(doc: ^Scene_Doc, circle: []int, report: ^Scene_Report) -> string {
	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(
		&builder,
		0,
		128,
		scene_report_allocator(report),
	); err != nil {
		return ""
	}
	strings.write_string(&builder, "the parents of the nodes ")
	for index, node in circle {
		if index > 0 {strings.write_string(&builder, ", ")}
		strings.write_byte(&builder, '"')
		strings.write_string(&builder, doc.nodes[node].name)
		strings.write_byte(&builder, '"')
	}
	strings.write_string(&builder, " make a circle")
	return strings.to_string(builder)
}

//* Builds a node's path from its parent's path.
scene_path_of :: proc(
	doc: ^Scene_Doc,
	index: int,
	first: ^map[string]int,
	allocator: mem.Allocator,
) -> string {
	node := &doc.nodes[index]
	if node.path != "" {return node.path}

	parent_index := -1
	if node.parent != "" {
		if p, found := first[node.parent]; found {parent_index = p}
	}
	if parent_index < 0 || parent_index == index {
		node.path = node.name
		return node.path
	}

	parent_path := scene_path_of(doc, parent_index, first, allocator)
	node.path = scene_message(allocator, "%s/%s", parent_path, node.name)
	return node.path
}

//* == Instantiation ==

//* Creates a widget and applies its node properties.
//* Returns INVALID_WIDGET_ID when creation fails.
scene_make :: proc(g: ^GUI, node: Scene_Node, parent: Widget_ID, report: ^Scene_Report) -> Widget_ID {
	allocator := virt.arena_allocator(&g.arena)

	name := strings.clone(node.name, allocator)
	text := strings.clone(node.text, allocator)

	if id, found := class_by_name(g, node.type); found {
		c, ok := class_get(g, id)
		if ok && c.constructor != nil {

			scene_check_kind_properties(node, c.type, report)
			return scene_place(g, c.constructor(g, parent, name, text), node, c.type, report)
		}
	}

	type_name := node.type
	multiline := false
	if type_name == "TextInput" {
		type_name = "TextBox"
	} else if type_name == "TextEdit" {
		type_name = "TextBox"
		multiline = true
	}

	widget_type, ok := fmt.string_to_enum_value(Widget_Type, type_name)
	if !ok {
		scene_report_add(
			report,
			.Error,
			node.line,
			node.name,
			"",
			"there is no widget called %q",
			node.type,
		)
		return INVALID_WIDGET_ID
	}
	constructor := Scene_Constructor_Of(g, widget_type)
	if constructor == nil {
		scene_report_add(
			report,
			.Error,
			node.line,
			node.name,
			"",
			"there is no constructor for the widget %q",
			node.type,
		)
		return INVALID_WIDGET_ID
	}
	widget := constructor(g, parent, name, text)
	if multiline {text_box_set_multiline(g, widget, true)}
	return scene_place(g, widget, node, widget_type, report)
}

//* Creates nodes deferred until their parents become available.
//* Repeats until no more waiting nodes can be created.
scene_make_waiting :: proc(
	g: ^GUI,
	doc: Scene_Doc,
	built: ^map[string]Widget_ID,
	waiting: ^[dynamic]int,
	report: ^Scene_Report,
) -> Widget_ID {
	first := INVALID_WIDGET_ID
	made := true
	for made {
		made = false
		i := 0
		for i < len(waiting) {
			node := doc.nodes[waiting[i]]
			p, found := built^[node.parent]
			if !found {
				i += 1
				continue
			}

			id := INVALID_WIDGET_ID
			if !node.skipped {
				id = scene_make(g, node, p, report)
			}
			if node.owns_name {
				if id == INVALID_WIDGET_ID {
					built^[node.name] = p
				} else {
					built^[node.name] = id
				}
			}
			if id != INVALID_WIDGET_ID && first == INVALID_WIDGET_ID {
				first = id
			}
			ordered_remove(waiting, i)
			made = true
		}
	}
	return first
}

//* Applies layout, visibility, font, and style properties to a widget.
scene_place :: proc(
	g: ^GUI,
	id: Widget_ID,
	node: Scene_Node,
	widget_type: Widget_Type,
	report: ^Scene_Report,
) -> Widget_ID {
	if id == INVALID_WIDGET_ID {return INVALID_WIDGET_ID}
	w := Widget_Get(g, id)
	if w == nil {return INVALID_WIDGET_ID}

	if node.has_anchors {
		Widget_Set_Anchors(g, id, Anchor{node.anchors[0], node.anchors[1], node.anchors[2], node.anchors[3]})
	}
	if node.has_offsets {
		Widget_Set_Offsets(g, id, Offset{node.offsets[0], node.offsets[1], node.offsets[2], node.offsets[3]})
	}
	if node.has_min_size {
		Widget_Set_Min_Size(g, id, Vec2{node.min_size[0], node.min_size[1]})
	}
	if node.has_custom_min_size {
		Widget_Set_Custom_Min_Size(g, id, Vec2{node.custom_min_size[0], node.custom_min_size[1]})
	}
	if node.has_visible && !node.visible {
		Widget_Set_Visible(g, id, false)
	}
	//* The family of the fonts of the text is looked up here: a name
	//* that is not a family of the GUI is an error, and the widget
	//* takes the font of the theme.
	family := scene_font_family(g, node, report)
	Widget_Set_Use_Theme(g, id, true)
	Widget_Set_Style(g, id, scene_style(node, family))
	if widget_type == .ColorRect && node.has_bg {
		#partial switch &d in w.data {
		case Color_Rect_Data:
			d.colour = Colour{node.bg[0], node.bg[1], node.bg[2], node.bg[3]}
		}
	}

	return id
}

//* Resolves a node's font family. Missing families are reported;
//* an unset or invalid family falls back to the theme.
scene_font_family :: proc(g: ^GUI, node: Scene_Node, report: ^Scene_Report) -> Font_Family_ID {
	if !node.has_font {return INVALID_FONT_FAMILY_ID}

	allocator := virt.arena_allocator(&g.arena)
	if node.font == "" {
		scene_report_add(
			report,
			.Warning,
			node.line,
			node.name,
			"font",
			"the name of the family of the fonts is empty",
		)
		return INVALID_FONT_FAMILY_ID
	}

	family := Font_Family_By_Name(g, node.font)
	if family == INVALID_FONT_FAMILY_ID {
		scene_report_add(
			report,
			.Error,
			node.line,
			node.name,
			"font",
			"there is no family of the fonts called %q",
			node.font,
		)
		return INVALID_FONT_FAMILY_ID
	}
	return family
}

//* Builds a style from the properties present on a node.
//* Explicit field flags preserve valid zero values and transparent colours.
scene_style :: proc(node: Scene_Node, family: Font_Family_ID) -> Style {
	style := Style{}
	if node.has_bg {
		style.box.bg_color = Colour{node.bg[0], node.bg[1], node.bg[2], node.bg[3]}
		style.set += bit_set[Style_Field]{.BG}
	}
	if node.has_border {
		c := Colour{node.border[0], node.border[1], node.border[2], node.border[3]}
		style.box.border_color = {c, c, c, c}
		style.set += bit_set[Style_Field]{.Border}
	}
	if node.has_border_width {
		width := node.border_width
		style.box.border_width = {width, width, width, width}
		style.set += bit_set[Style_Field]{.Border_Width}
	}
	if node.has_padding {
		style.box.content_margin = {
			node.padding[0],
			node.padding[1],
			node.padding[2],
			node.padding[3],
		}
		style.set += bit_set[Style_Field]{.Padding}
	}
	if node.has_colour {
		style.text.colour = Colour{node.colour[0], node.colour[1], node.colour[2], node.colour[3]}
		style.set += bit_set[Style_Field]{.Text}
		style.text.set += bit_set[Text_Field]{.Colour}
	}
	if node.has_font_size {
		style.text.size = node.font_size
		style.set += bit_set[Style_Field]{.Text}
		style.text.set += bit_set[Text_Field]{.Size}
	}
	if family != INVALID_FONT_FAMILY_ID {
		style.text.family = family
		style.set += bit_set[Style_Field]{.Text}
		style.text.set += bit_set[Text_Field]{.Family}
	}
	return style
}

//* Logs report entries. Errors are logged as warnings because loading
//* continues; callers can inspect the report for exact severity.
scene_report_log :: proc(report: Scene_Report) {
	for entry in report.entries {
		switch entry.severity {
		case .Note:
			log.infof("scene:%d: %s: %s", entry.line, scene_severity_name(entry.severity), entry.message)
		case .Warning:
			log.warnf("scene:%d: %s: %s", entry.line, scene_severity_name(entry.severity), entry.message)
		case .Error:
			log.warnf("scene:%d: %s: %s", entry.line, scene_severity_name(entry.severity), entry.message)
		}
	}
}
