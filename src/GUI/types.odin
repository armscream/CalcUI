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
	open_url:               proc(ctx: rawptr, url: string) -> bool,
}

Texture_Upload :: struct {
	pixels:     []u8,
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
	TextBox,
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
	ScrollBar,
	FlowContainer,
	AspectRatioContainer,
	TabContainer,
	ColorRect,
	TextureRect,
	NinePatchRect,
	ReferenceRect,
	RichTextLabel,
	ItemList,
	Tree,
	TabBar,
	HSeparator,
	VSeparator,
	MenuBar,
	CheckBox,
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

//* Layout behavior along one axis.
Size_Flag :: enum u8 {
	//* Use the available space, including a share of remaining space.
	Fill          = 1,
	//* Take a share of remaining space beyond the minimum size.
	Expand        = 2,
	//* Stay at minimum size and centre within the allocated space.
	Shrink_Center = 4,
}
Size_Flags :: bit_set[Size_Flag]

//* Horizontal layout direction and inheritance.
Layout_Direction :: enum {
	Inherit,
	Locale,
	LTR,
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
	Text_Box_Data,
	Grid_Data,
	Margin_Data,
	Scroll_Data,
	Scroll_Bar_Data,
	Aspect_Data,
	Tab_Container_Data,
	Check_Box_Data,
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

Widget :: struct {
	//* Framework-owned identity and tree links. Use the widget APIs to modify them.
	id:               Widget_ID,
	type:             Widget_Type,
	class:            Widget_Class_ID,
	name:             string,
	parent:           Widget_ID,
	freeing:          bool,
	first_child:      Widget_ID,
	last_child:       Widget_ID,
	prev_sibling:     Widget_ID,
	next_sibling:     Widget_ID,

	//* Layout inputs.
	anchors:          Anchor,
	offsets:          Offset,
	grow_h:           Grow,
	grow_v:           Grow,
	base_min_size:    Vec2,
	weight:           f32,
	separation:       f32,
	draggable:        bool,

	//* Framework-measured minimum size and assigned geometry.
	min_size:         Vec2,
	manual_size:      Vec2,
	manual_w:         bool,
	manual_h:         bool,
	rect:             Rect,
	content:          Rect,
	clip:             Rect,

	//* Appearance and theme selection.
	style:            Style,
	use_theme:        bool,
	variation:        string,

	//* Program-controlled visibility and enabled state; interaction state is framework-controlled.
	state:            Widget_State,
	data:             Widget_Data,

	//* Input and focus navigation.
	mouse_filter:     Mouse_Filter,
	focus_mode:       Focus_Mode,
	focus_neighbour:  [4]Widget_ID,
	focus_next:       Widget_ID,
	focus_previous:   Widget_ID,
	tab_index:        int,

	//* Parent layout behavior.
	size_flags_h:     Size_Flags,
	size_flags_v:     Size_Flags,
	stretch_ratio:    f32,
	clip_contents:    bool,

	//* Additional widget properties.
	tooltip_text:     string,
	custom_min_size:  Vec2,
	custom_max_size:  Vec2,
	z_index:          int,

	//* Unused by the toolkit; available for application-defined transforms.
	rotation:         f32,
	scale:            Vec2,
	pivot_offset:     Vec2,

	layout_direction: Layout_Direction,
	signals:          Signals,
	access:           Access_Info,

	//* Framework-maintained invalidation and style cache.
	dirty:            Dirty_Flags,
	subtree_dirty:    Dirty_Flags,
	style_cache:      Style_Cache,
}

//* All fields are supplied by the program when creating a widget.
Widget_Opts :: struct {
	name:               string,
	preset:             Anchor_Preset,
	anchors:            Anchor,
	offsets:            Offset,
	min_size:           Vec2,
	weight:             f32,
	fixed:              bool,
	separation:         f32,
	draggable:          bool,
	style:              Style,
	use_theme:          bool,
	variation:          string,
	hidden:             bool,
	split:              Split_Direction,
	text:               string,
	text_rules:         Text_Rules,
	on_click:           proc(g: ^GUI, id: Widget_ID),
	mouse_filter:       Mouse_Filter,
	focus_mode:         Focus_Mode,
	tab_index:          int,
	size_flags_h:       Size_Flags,
	size_flags_v:       Size_Flags,
	stretch_ratio:      f32,
	layout_direction:   Layout_Direction,
	clip_contents:      Clip_Contents,
	tooltip:            string,
	custom_min_size:    Vec2,
	custom_max_size:    Vec2,
	z_index:            int,
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
	undo_stacks:               map[Widget_ID]^Undo_Stack,
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
	caret_timer:               f32,
	inspector:                 Inspector,
	measure_cache:             map[Measure_Key]Vec2,
	last_frame:                i64,
	clipboard:                 Clipboard,
	audio:                     ^Audio_State,
	default_style:             Style,
	access_bridge:             Access_Bridge,
	access_epoch:              int,
	tooltip_id:                Widget_ID,
	tooltip_enabled:           bool,
	shutdown:                  bool,
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