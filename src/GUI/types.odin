//* The types of the GUI: the widgets, their options, their styles
//* and the state the GUI keeps between frames.
//
//* == The fields of a widget ==
//* The fields of a widget are in two groups.
//
//* The first group belongs to the framework: the identity of the widget, the
//* links of the tree, the data of the widget, the size it has been measured
//* at, the place it has and the bookkeeping of the tree. A program that
//* writes to them breaks the tree.
//* The parent of a widget is changed with `Widget_Set_Parent`, the data of a
//* widget with the setter of the kind of the widget, the size that is kept
//* with `Widget_Set_Manual_Size`.
//*   id, type, class, parent, freeing, first_child, last_child, prev_sibling,
//*   next_sibling, data, min_size, rect, clip, manual_size, manual_w,
//*   manual_h, dirty, subtree_dirty, style_cache
//
//* The second group is the look and the place of the widget. A program may
//* write to it, but then it has to ask for the tree to be measured again
//* with `GUI_Invalidate_All`. The setters of setter.odin do that for the
//* program, one field at a time.
//
//* A few fields of the second group are not used by the toolkit at all:
//* `rotation`, `scale`, `pivot_offset` and `content`. A program may read
//* them and write them, and use them in its own way.
package GUI

import "core:math"


import runa "./dependencies/Runa"
import virt "core:mem/virtual"

Backend :: struct {
	ctx:                    rawptr,
	create:                 proc(ctx, window: rawptr, w, h: i32) -> bool,
	destroy:                proc(ctx: rawptr),
	resize:                 proc(ctx: rawptr, w, h: i32) -> bool,
	upload_texture:         proc(ctx: rawptr, id: Texture_ID, pixels: []u8, w, h: i32) -> bool,
	upload_texture_regions: proc(ctx: rawptr, id: Texture_ID, regions: []Texture_Upload) -> bool,
	destroy_texture:        proc(ctx: rawptr, id: Texture_ID),
	submit:                 proc(ctx: rawptr, dl: ^Draw_List),
	submit_target:          proc(ctx: rawptr, dl: ^Draw_List, window: rawptr),
	supports_shapes:        bool,
}

Texture_Upload :: struct {
	pixels: []u8,
	w, h, x, y: i32,
}

Rect :: struct {
	x, y, w, h: f32,
}
Vec2 :: struct {
	x, y: f32,
}

vec2_add :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a.x + b.x, a.y + b.y}
}

vec2_sub :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a.x - b.x, a.y - b.y}
}

vec2_scale :: proc(a: Vec2, s: f32) -> Vec2 {
	return Vec2{a.x * s, a.y * s}
}

vec2_add_to :: proc(a: ^Vec2, b: Vec2) {
	a.x += b.x
	a.y += b.y
}

vec2_sub_from :: proc(a: ^Vec2, b: Vec2) {
	a.x -= b.x
	a.y -= b.y
}

vec2_length :: proc(a: Vec2) -> f32 {
	return math.sqrt(a.x * a.x + a.y * a.y)
}

Colour :: struct {
	r, g, b, a: f32,
}

Texture_ID :: distinct u32
INVALID_TEXTURE_ID :: Texture_ID(0)

ATLAS_TEXTURE_ID :: Texture_ID(1)

Float_Panel :: struct {
	widget: Widget_ID,
	pos:    Vec2,
	size:   Vec2,
	title:  string,
	draw:   Draw_List,
}

Widget_Type :: enum {
	Panel,
	Button,
	Label,
	Image,
	TextInput,
	ScrollArea,
	Split,
	Tabs,
	VBox,
	HBox,

	GridContainer,
	MarginContainer,
	CenterContainer,
	PanelContainer,
	ScrollContainer,
	FlowContainer,
	AspectRatioContainer,
	TabContainer,

	ColorRect,
	TextureRect,
	NinePatchRect,
	ReferenceRect,
	RichTextLabel,
	TextEdit,
	ItemList,
	Tree,
	TabBar,
	HSeparator,
	VSeparator,
	MenuBar,

	CheckBox,
	CheckButton,
	OptionButton,
	MenuButton,
	LinkButton,

	HSlider,
	VSlider,
	SpinBox,
	ProgressBar,

	PopupMenu,
	PopupPanel,
	AcceptDialog,
	ConfirmationDialog,
	FileDialog,

	Toast,
	CommandPalette,
	Rating,
	Segmented,
	ToggleSwitch,
	ComboBox,
	VirtualList,
	DataTable,
	DatePicker,
	TimePicker,
	ColorPicker,
	EmojiPicker,
	Accordion,
	ContextMenu,
	ChatInput,
	SearchField,
	NumberInput,
	Tooltip,

	Chart,
	NodeGraph,
	Canvas,
	FileViewer,
	RichTextEditor,
	VectorDrawing,
	AudioPlayer,
}

Mouse_Filter :: enum {
	Stop,
	Pass,
	Ignore,
}

Focus_Mode :: enum {
	None,
	Click,
	All,
}

Clip_Contents :: enum {
	Default,
	On,
	Off,
}

//* The flags of a widget say how it takes the room of its parent along
//* one axis. There is one set of flags for the horizontal axis and one
//* for the vertical one.
Size_Flag :: enum u8 {
	//* The widget takes the room it is given: its minimum size plus its
	//* share of the room that is left over. It is the default.
	Fill          = 1,
	//* The widget takes a share of the room that is left over. Without
	//* this flag the widget takes only its minimum size, and the room
	//* that is left over goes to the widgets that expand.
	Expand        = 2,
	//* The widget takes only its minimum size and is centred in the
	//* room it would have had.
	Shrink_Center = 4,
}
Size_Flags :: bit_set[Size_Flag]

//* The direction a widget grows in.
Layout_Direction :: enum {
	//* The widget takes the direction of its parent, and the direction
	//* of the root of the GUI when the parent does not say one.
	Inherit,
	//* The direction of the language of the program. The toolkit has no
	//* locale yet, so the language is read from the left to the right.
	Locale,
	//* From the left to the right.
	LTR,
	//* From the right to the left: a box that stacks its children along
	//* the horizontal axis puts them in the other order.
	RTL,
}

Widget_ID :: struct {
	index:      u32,
	generation: u32,
}

INVALID_WIDGET_ID :: Widget_ID {
	index      = 0,
	generation = 0,
}

Text_Align :: enum {
	Left,
	Center,
	Right,
	Fill,
}

V_Align :: enum {
	Top,
	Center,
	Bottom,
}

Text_Wrap :: enum {
	Off,
	Word,
	Anywhere,
}

Text_Transform :: enum {
	None,
	Upper,
	Lower,
	Capitalize,
}

Text_Overrun :: enum {
	None,
	Ellipsis,
	Words,
}

Widget_State :: bit_set[Widget_State_Flag]
Widget_State_Flag :: enum {
	Visible,
	Enabled,
	Hovered,
	Pressed,
	Focused,
}

Anchor_Preset :: enum {
	Fill,
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
	Center,
	Left,
	Right,
	Top,
	Bottom,
	Custom,
}

Anchor :: struct {
	left, top, right, bottom: f32,
}
Offset :: struct {
	left, top, right, bottom: f32,
}
Grow :: enum {
	Begin,
	End,
	Both,
}

Dock_Zone :: enum {
	None,
	Left,
	Right,
	Top,
	Bottom,
	Center,
}

MAX_DOCK_SLOTS :: 16
MAX_TABS :: 16

Dock_Kind :: enum {
	None,
	Split,
	Tabs,
	Swap,
	Fill,
}

Dock_Plan :: struct {
	kind:              Dock_Kind,
	axis:              Split_Direction,

	container:         Widget_ID,

	create_split:      bool,
	children:          [MAX_DOCK_SLOTS]Widget_ID,
	weights:           [MAX_DOCK_SLOTS]f32,
	count:             int,
	panel_index:       int,

	create_tabs:       bool,
	tab_host:          Widget_ID,
	tab_index:         int,

	swap_panel_parent: Widget_ID,
	swap_panel_index:  int,
	swap_host_parent:  Widget_ID,
	swap_host_index:   int,

	preview:           Rect,
	tab_button:        Rect,
	tab_bar:           Rect,
	tab_widgets:       [MAX_TABS]Widget_ID,
	tab_widget_count:  int,
	tab_buttons:       [MAX_TABS]Rect,
	tab_button_count:  int,
	others:            [MAX_DOCK_SLOTS]Rect,
	other_count:       int,
}

anchor_of :: proc(preset: Anchor_Preset, custom: Anchor) -> Anchor {
	switch preset {
	case .Fill:
		return Anchor{0, 0, 1, 1}
	case .Top_Left:
		return Anchor{0, 0, 0, 0}
	case .Top_Right:
		return Anchor{1, 0, 1, 0}
	case .Bottom_Left:
		return Anchor{0, 1, 0, 1}
	case .Bottom_Right:
		return Anchor{1, 1, 1, 1}
	case .Center:
		return Anchor{0.5, 0.5, 0.5, 0.5}
	case .Left:
		return Anchor{0, 0, 0, 1}
	case .Right:
		return Anchor{1, 0, 1, 1}
	case .Top:
		return Anchor{0, 0, 1, 0}
	case .Bottom:
		return Anchor{0, 1, 1, 1}
	case .Custom:
		return custom
	}
	return Anchor{0, 0, 1, 1}
}

Style :: struct {
	set:  bit_set[Style_Field],
	box:  StyleBox,
	text: Text_Style,
}

Style_Cache :: struct {
	style:           Style,
	state:           Style,
	theme_state:     Style,
	style_of_widget: Style,
	default_style:   Style,
	use_theme:       bool,
	variation:       string,
	epoch:           int,
	valid:           bool,
}

Style_Field :: enum {
	BG,
	Border,
	Border_Width,
	Padding,
	Corner_Radius,
	Shadow,
	Expand_Margin,
	Text,
}

Text_Style :: struct {
	set:             bit_set[Text_Field],

	family:          Font_Family_ID,
	size:            f32,

	colour:          Colour,
	hover_colour:    Colour,
	pressed_colour:  Colour,
	disabled_colour: Colour,
	focus_colour:    Colour,

	align:           Text_Align,
	valign:          V_Align,

	wrap:            Text_Wrap,
	spacing:         f32,

	transform:       Text_Transform,

	overrun:         Text_Overrun,
	clip:            bool,

	outline_colour:  Colour,
	outline_size:    f32,
	shadow_colour:   Colour,
	shadow_offset:   Vec2,
}

Text_Field :: enum {
	Family,
	Size,
	Colour,
	Hover_Colour,
	Pressed_Colour,
	Disabled_Colour,
	Focus_Colour,
	Align,
	VAlign,
	Wrap,
	Spacing,
	Transform,
	Overrun,
	Clip,
	Outline_Colour,
	Outline_Size,
	Shadow_Colour,
	Shadow_Offset,
}

Theme :: struct {
	types:      map[Widget_Type]Theme_Type,
	classes:    map[string]Theme_Type,
	variations: map[string]Variation,
	family:     Font_Family_ID,
	size:       f32,
	owner:      ^GUI,
}

Theme_Type :: struct {
	styleboxes: map[string]StyleBox,
	colors:     map[string]Colour,
	constants:  map[string]f32,
	fonts:      map[string]Font_ID,
	font_sizes: map[string]f32,
	icons:      map[string]Texture_ID,
	text:       Text_Style,
	states:     State_Styles,
}

Variation :: struct {
	of:        Widget_Type,
	style:     Style,
	states:    State_Styles,
	colors:    map[string]Colour,
	constants: map[string]f32,
}

State_Styles :: struct {
	hover:    Style,
	pressed:  Style,
	disabled: Style,
	focus:    Style,
}

Style_State :: enum {
	Normal,
	Hovered,
	Pressed,
	Disabled,
	Focused,
}

Split_Direction :: enum {
	Horizontal,
	Vertical,
}

None_Data :: struct {}

Widget_Data :: union {
	None_Data,
	Button_Data,
	Label_Data,
	Split_Data,
	Tabs_Data,
	Text_Input_Data,
	Grid_Data,
	Margin_Data,
	Scroll_Data,
	Aspect_Data,
	Tab_Container_Data,
	Check_Box_Data,
	Check_Button_Data,
	Link_Button_Data,
	Menu_Button_Data,
	Option_Button_Data,
	Slider_Data,
	Spin_Box_Data,
	Progress_Bar_Data,
	Color_Rect_Data,
	Texture_Rect_Data,
	Nine_Patch_Data,
	Item_List_Data,
	Tree_Data,
	Text_Edit_Data,
	Rich_Text_Data,
	Popup_Menu_Data,
	Dialog_Data,
	File_Dialog_Data,
	Separator_Data,

	Toast_Data,
	Command_Palette_Data,
	Rating_Data,
	Segmented_Data,
	Toggle_Switch_Data,
	Combo_Box_Data,
	Virtual_List_Data,
	Data_Table_Data,
	Date_Picker_Data,
	Time_Picker_Data,
	Color_Picker_Data,
	Emoji_Picker_Data,
	Accordion_Data,
	Context_Menu_Data,
	Chat_Input_Data,
	Search_Field_Data,
	Number_Input_Data,
	Tooltip_Data,
	Chart_Data,
	Node_Graph_Data,
	Canvas_Data,
	File_Viewer_Data,
	Rich_Text_Editor_Data,
	Vector_Drawing_Data,
	Audio_Player_Data,

	Custom_Data,
}

Button_Data :: struct {
	text:     string,
	on_click: proc(g: ^GUI, id: Widget_ID),
}
Label_Data :: struct {
	text: string,
}
Split_Data :: struct {
	direction: Split_Direction,
}
Tabs_Data :: struct {
	active: int,
}

Text_Input_Data :: struct {
	text:      string,
	caret:     int,
	sel_start: int,
	sel_end:   int,
	selection: Text_Selection,
	rules:     Text_Rules,
}

Widget :: struct {
	//* The identity of the widget. The framework gives it and keeps it.
	id:               Widget_ID,
	//* The kind of the widget and the class it belongs to. The framework
	//* gives them when the widget is made.
	type:             Widget_Type,
	class:            Widget_Class_ID,
	//* The name of the widget. The program gives it.
	name:             string,
	//* The parent of the widget. The framework moves the widget with
	//* `Widget_Set_Parent`.
	parent:           Widget_ID,

	//* True while the widget is on its way out. The framework sets it.
	freeing:          bool,

	//* The children of the widget, in the order of the tree. The
	//* framework links them with `Widget_Attach` and `Widget_Detach`.
	first_child:      Widget_ID,
	last_child:       Widget_ID,
	prev_sibling:     Widget_ID,
	next_sibling:     Widget_ID,
	//* Where the widget sits in its parent. The program gives it.
	anchors:          Anchor,
	offsets:          Offset,
	//* The way the widget grows when it is given more room than it
	//* asks for.
	grow_h:           Grow,
	grow_v:           Grow,
	//* The smallest size the widget asks for. The framework measures
	//* the widget and puts the size it found in `min_size`.
	min_size:         Vec2,
	//* The smallest size the program asks for.
	base_min_size:    Vec2,
	//* The share of the space of the parent the widget takes.
	weight:           f32,
	//* The space between the children of the widget.
	separation:       f32,
	//* Whether the widget can be dragged by its title bar.
	draggable:        bool,

	//* The size the program gave the widget, and the axes it is fixed
	//* on. The framework sets them with `Widget_Set_Manual_Size`, and
	//* when the user pulls the widget into another size.
	manual_size:      Vec2,
	manual_w:         bool,
	manual_h:         bool,

	//* The place of the widget on the screen. The framework puts it
	//* there when the tree is laid out.
	rect:             Rect,
	//* The place of the content of the widget, inside its own margin.
	//* The toolkit does not use it: the content is worked out from the
	//* rect and the style of the widget when it is needed.
	content:          Rect,
	//* The part of the screen the widget is drawn in. The framework
	//* keeps it.
	clip:             Rect,
	//* The look of the widget. The program gives it.
	style:            Style,
	//* Whether the widget takes the look of the theme.
	use_theme:        bool,
	//* The name of the variation of the theme the widget takes.
	variation:        string,
	//* The state of the widget: the program gives .Visible and .Enabled,
	//* the framework gives .Hovered, .Pressed and .Focused.
	state:            Widget_State,
	//* The data of the widget. The framework gives it the data of the
	//* kind of the widget, and the setter of the kind changes it.
	data:             Widget_Data,

	//* What the widget does with the mouse.
	mouse_filter:     Mouse_Filter,
	//* Whether the widget can have the focus.
	focus_mode:       Focus_Mode,
	//* The widgets the arrow keys go to: left, up, right and down.
	//* The program gives them with `Widget_Set_Focus_Neighbour`.
	focus_neighbour:  [4]Widget_ID,
	//* The widget the tab key goes to, and the one it comes from.
	focus_next:       Widget_ID,
	focus_previous:   Widget_ID,
	//* The place of the widget in the order of the tab key.
	tab_index:        int,
	//* How the widget takes the room of its parent along the horizontal
	//* axis, and along the vertical one. The layout of the parent gives
	//* the room: a widget that expands takes a share of the room that is
	//* left over, and a widget that does not expand takes only its
	//* minimum size. A widget that fills takes the room it is given, and
	//* a widget that shrinks takes only its minimum size and is centred
	//* in the room it would have had.
	size_flags_h:     Size_Flags,
	size_flags_v:     Size_Flags,
	//* The share of the space of the parent the widget takes when there
	//* is room left over: the weight of the widget times this ratio. A
	//* ratio of 0 gives a share of nothing, so the widget takes only
	//* its minimum size.
	stretch_ratio:    f32,
	//* Whether the widget cuts its children to its own rect.
	clip_contents:    bool,
	//* The text that is shown when the pointer rests on the widget.
	tooltip_text:     string,
	//* The size the program insists on.
	custom_min_size:  Vec2,
	custom_max_size:  Vec2,
	//* The place of the widget in the order of the drawing.
	z_index:          int,
	//* The turn of the widget around its pivot. The toolkit does not
	//* use it: the draw list is made of rectangles that stand straight,
	//* so a turn would need a transform through the draw list, the hit
	//* test and the clip stack.
	rotation:         f32,
	//* The size of the widget compared to the size it is given. The
	//* toolkit does not use it: a scale would need the same transform
	//* as a turn.
	scale:            Vec2,
	//* The point the widget turns and grows around. The toolkit does not
	//* use it: it is the point of the transform that a turn and a scale
	//* would need.
	pivot_offset:     Vec2,
	//* The direction the widget grows in: from the left to the right or
	//* from the right to the left. A container that stacks its children
	//* along the horizontal axis puts them in the other order when the
	//* direction is from the right to the left. The direction does not
	//* change the room the children get, only the order they are put in.
	layout_direction: Layout_Direction,
	//* The signals of the widget and the connections to them.
	signals:          Signals,
	//* What the widget is to whatever reads the screen.
	access:           Access_Info,

	//* What is out of date about the widget, and about the branch
	//* under it. The framework keeps it.
	dirty:            Dirty_Flags,
	subtree_dirty:    Dirty_Flags,

	//* The look the widget had the last time it was drawn. The
	//* framework keeps it.
	style_cache:      Style_Cache,
}

//* The options a widget is made with. Every field belongs to the program.
Widget_Opts :: struct {
	//* The name of the widget.
	name:            string,
	//* Where the widget sits in its parent, and how far from it.
	preset:          Anchor_Preset,
	anchors:         Anchor,
	offsets:         Offset,
	//* The smallest size the widget asks for.
	min_size:        Vec2,
	//* The share of the space of the parent the widget takes.
	weight:          f32,
	//* Whether the widget keeps the size it asks for.
	fixed:           bool,
	//* The space between the children of the widget.
	separation:      f32,
	//* Whether the widget can be dragged by its title bar.
	draggable:       bool,
	//* The look of the widget.
	style:           Style,
	//* Whether the widget takes the look of the theme.
	use_theme:       bool,
	//* The name of the variation of the theme the widget takes.
	variation:       string,
	//* Whether the widget starts out not shown.
	hidden:          bool,
	//* The axis a split divides its children along.
	split:           Split_Direction,
	//* The text the widget shows. A text box keeps a copy of it: the
	//* string the program gives is not the string the widget holds.
	text:            string,
	//* The rules of a text box: how long the text may be, and which
	//* characters may go into it.
	text_rules:      Text_Rules,
	//* What happens when the widget is pressed.
	on_click:        proc(g: ^GUI, id: Widget_ID),

	//* What the widget does with the mouse.
	mouse_filter:    Mouse_Filter,
	//* Whether the widget can have the focus.
	focus_mode:      Focus_Mode,
	//* The place of the widget in the order of the tab key.
	tab_index:       int,
	//* How the widget takes the room of its parent along the horizontal
	//* axis, and along the vertical one. A widget that expands takes a
	//* share of the room that is left over, and a widget that does not
	//* expand takes only its minimum size. A widget that fills takes the
	//* room it is given, and a widget that shrinks takes only its
	//* minimum size and is centred in the room it would have had. The
	//* default of a widget is `.Fill` and `.Expand` on both axes, and a
	//* set of flags with nothing in it means the program says nothing
	//* about that axis.
	size_flags_h:    Size_Flags,
	size_flags_v:    Size_Flags,
	//* The share of the space of the parent the widget takes when there
	//* is room left over: the weight of the widget times this ratio. A
	//* ratio of 0 in the options is the same as saying nothing: the
	//* ratio of 1 is used. A ratio of 0 is set with
	//* `Widget_Set_Stretch_Ratio`.
	stretch_ratio:   f32,
	//* The direction the widget grows in: from the left to the right or
	//* from the right to the left. The default is to take the direction
	//* of the parent.
	layout_direction: Layout_Direction,
	//* Whether the widget cuts its children to its own rect.
	clip_contents:   Clip_Contents,
	//* The text that is shown when the pointer rests on the widget.
	tooltip:         string,
	//* The size the program insists on.
	custom_min_size: Vec2,
	custom_max_size: Vec2,
	//* The place of the widget in the order of the drawing.
	z_index:         int,
	//* What the widget is to whatever reads the screen.
	access_role:        Access_Role,
	access_name:        string,
	access_description: string,
}

Resize_Edge :: enum {
	Left,
	Right,
	Top,
	Bottom,
}

Resize_Edges :: bit_set[Resize_Edge]

Resize_State :: struct {
	active:      bool,
	widget:      Widget_ID,
	edges:       Resize_Edges,
	origin:      Vec2,
	last:        Vec2,
	float_index: int,
}

Cursor :: enum {
	Default,
	Pointer,
	Text,
	Crosshair,
	Wait,
	Not_Allowed,
	Grab,
	Grabbing,
	Resize_NS,
	Resize_W,
	Resize_E,
	Resize_N,
	Resize_S,
	Resize_NW,
	Resize_NE,
	Resize_SW,
	Resize_SE,
}

Drag_State :: struct {
	active:      bool,
	armed:       bool,
	origin:      Vec2,
	widget:      Widget_ID,
	target:      Widget_ID,
	tab_host:    Widget_ID,
	zone:        Dock_Zone,
	kind:        Dock_Kind,
	grab:        Vec2,
	pos:         Vec2,
	ghost:       Rect,
	size:        Vec2,
	slot:        Rect,
	swap:        bool,
	float_index: int,
	plan:        Dock_Plan,
}

GUI :: struct {
	arena:                     virt.Arena,
	frame_arena:               virt.Arena,
	widgets:                   [dynamic]^Widget,
	widget_generations:        [dynamic]u32,
	free_widgets:              [dynamic]u32,
	root:                      Widget_ID,
	viewport:                  Rect,
	scale:                     f32,
	window_rect:               Rect,

	floats:                    [dynamic]Float_Panel,
	popups:                    [dynamic]Popup_Entry,
	events:                    [dynamic]Event,
	pointer:                   Vec2,
	global_pointer:            Vec2,
	pointer_known:             bool,
	lmb_down:                  bool,
	lmb_pressed:               bool,
	lmb_released:              bool,
	mods:                      Mods,
	event_handled:             bool,
	hot:                       Widget_ID,
	active:                    Widget_ID,
	focused:                   Widget_ID,
	slider_active:             Widget_ID,
	quit_requested:            bool,
	drag:                      Drag_State,
	resize:                    Resize_State,
	resize_hover:              Widget_ID,
	resize_hover_edges:        Resize_Edges,
	cursor:                    Cursor,
	ime_compositions:          map[Widget_ID]IME_Composition,
	draw:                      Draw_List,
	target:                    ^Draw_List,
	backend:                   Backend,
	atlas:                     ^UI_Atlas,
	atlas_texture:             Texture_ID,
	atlas_failures:            int,
	dirty:                     Dirty_Flags,
	full_layout:               bool,
	measured_count:            int,
	arranged_count:            int,
	style_epoch:               int,

	fonts:                     [dynamic]^Font,
	font_files:                [dynamic]^Font_File,
	font_families:             [dynamic]^Font_Family,
	font_instances:            map[Font_Instance_Key]Font_ID,
	default_font:              Font_ID,
	default_family:            Font_Family_ID,
	default_font_size:         f32,
	shape_cache:               runa.Cache,
	cache_ready:               bool,
	glyphs:                    map[Glyph_Key]Glyph_Entry,
	upload_buf:                []u8,

	theme:                     ^Theme,
	commands:                  Commands,
	kinds:                     [dynamic]Widget_Kind,
	classes:                   [dynamic]Widget_Class,
	class_by_type:             map[Widget_Type]Widget_Class_ID,
	class_by_name:             map[string]Widget_Class_ID,
	signal_conns:              [dynamic]Signal_Conn_Entry,
	scene_constructors:        [dynamic]Scene_Constructor,
	scene_defaults_registered: bool,
	dt:                        f32,
	inspector:                 Inspector,
	measure_cache:             map[Measure_Key]Vec2,
	last_frame:                i64,
	clipboard:                 Clipboard,
	audio:                     ^Audio_State,
	default_style:             Style,
	access_bridge:             Access_Bridge,
	access_epoch:              int,
}

RGBA :: proc(r, g, b, a: f32) -> Colour {
	return Colour{r = r, g = g, b = b, a = a}
}

Scale_Colour :: proc(c: Colour, f: f32) -> Colour {
	return Colour{r = c.r * f, g = c.g * f, b = c.b * f, a = c.a}
}

Make_Text_Style :: proc(
	colour: Colour,
	size: f32 = 0,
	family: Font_Family_ID = INVALID_FONT_FAMILY_ID,
) -> Text_Style {
	return Text_Style{colour = colour, size = size, family = family}
}

UI_Scene :: struct {
	format: u32 `json:"format"`,
	name:   string `json:"name"`,
	root:   Node `json:"root"`,
}

Node :: struct {
	type:     string `json:"type"`,
	name:     string `json:"name"`,
	text:     string `json:"text,omitempty"`,
	anchors:  Anchor `json:"anchors"`,
	offsets:  Offset `json:"offsets"`,
	style:    Style `json:"style,omitempty"`,
	children: []Node `json:"children,omitempty"`,
}

