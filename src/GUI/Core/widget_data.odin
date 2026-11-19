package Core
Toast_Kind :: enum {
	Info,
	Success,
	Warning,
	Error,
}

Toast_Data :: struct {
	text:     string,
	duration: f32,
	//* The absolute time at which the toast goes away.
	until:    f32,
	kind:     Toast_Kind,
}

Palette_Command :: struct {
	label:    string,
	action:   proc(g: ^GUI, id: Widget_ID),
	keywords: string,
	tag:      int,
	detail:   string,
}

Palette_Match :: struct {
	index: int,
	score: int,
}

Command_Palette_Data :: struct {
	text:     string,
	commands: [dynamic]Palette_Command,
	matches:  [dynamic]Palette_Match,
	selected: int,
	scroll:   int,
	visible:  bool,
	owner:    Widget_ID,
	last_tag: int,
	commands_owned: bool,
	matches_dirty:  bool,
}

Rating_Data :: struct {
	value: f32,
	max:   f32,
	mark:  string,
}

Segmented_Item :: struct {
	text: string,
	icon: Texture_ID,
}

Segmented_Data :: struct {
	items:    [dynamic]Segmented_Item,
	selected: int,
}

Toggle_Switch_Data :: struct {
	text: string,
	on:   bool,
}

Combo_Box_Item :: struct {
	text: string,
	icon: Texture_ID,
}

Combo_Box_Data :: struct {
	items:    [dynamic]Combo_Box_Item,
	selected: int,
	open:     bool,
	popup:    Widget_ID,
}

Virtual_List_Pick :: struct {
	key:   u64,
	index: int,
}

Virtual_List :: struct {
	source:     List_Source,
	row_height: f32,
	scroll:     f32,
	selected:   [dynamic]Virtual_List_Pick,
	cursor:     int,
	cursor_key: u64,
	count:      int,
	offsets:    [dynamic]f32,
	offsets_ok: bool,
	resync:     bool,
}

Virtual_List_Data :: struct {
	list: ^Virtual_List,
}

Data_Table_Column :: struct {
	title:   string,
	width:   f32,
	size:    Data_Table_Column_Size,
	min_width: f32,
	sort:    Data_Table_Sort,
	compare: proc(a, b: string) -> int,
}

Data_Table_Column_Size :: enum {
	Fixed,
	Stretch,
}

Data_Table_Sort :: enum {
	None,
	Ascending,
	Descending,
}

Data_Table_Row :: struct {
	values: [dynamic]string,
	key:    u64,
}

Data_Table :: struct {
	source:           Table_Source,
	rows:             Table_Rows,
	columns:          [dynamic]Data_Table_Column,
	order:            [dynamic]int,
	order_ok:         bool,
	sorted_by:        int,
	sort:             Data_Table_Sort,
	selected_source:  int,
	selected_view:    int,
	selected_key:     u64,
	selected_column:  int,
	filter:           proc(ctx: rawptr, index: int, text: string) -> bool,
	filter_text:      string,
	scroll:           f32,
	h_scroll:         f32,
	row_height:       f32,
	header_height:    f32,
	layout_x:         [dynamic]f32,
	layout_w:         [dynamic]f32,
	layout_width:     f32,
	layout_ok:        bool,
}

Data_Table_Data :: struct {
	table: ^Data_Table,
}

Date_Picker_Data :: struct {
	year:      int,
	month:     int,
	day:       int,
	open:      bool,
	show_years: bool,
	editing:   bool,
	edit_text: string,
	caret:     int,
}

Time_Picker_Data :: struct {
	hour:      int,
	minute:    int,
	open:      bool,
	editing:   bool,
	edit_text: string,
	caret:     int,
}

Color_Picker_Data :: struct {
	colour:    Colour,
	hue:       f32,
	saturation: f32,
	value:     f32,
	open:      bool,
	editing:   bool,
	edit_text: string,
	caret:     int,
	sel_start: int,
	sel_end:   int,
	selection: Text_Selection,
	picking:   bool,
}

Emoji_Picker_Data :: struct {
	emoji:  string,
	group:  int,
	scroll: f32,
	open:   bool,
}

Accordion_Data :: struct {
	open: int,
}

Context_Menu_Item :: struct {
	text:      string,
	icon:      Texture_ID,
	separator: bool,
	disabled:  bool,
	checked:   bool,
	action:    proc(g: ^GUI, id: Widget_ID),
}

Context_Menu_Data :: struct {
	items:    [dynamic]Context_Menu_Item,
	selected: int,
	visible:  bool,
	pos:      Vec2,
}

Chat_Line :: struct {
	who:    string,
	text:   string,
	system: bool,
}

Chat_Input_Data :: struct {
	text:   string,
	lines:  [dynamic]Chat_Line,
	scroll: f32,
}

Search_Field_Data :: struct {
	text:        string,
	placeholder: string,
	show_icon:   bool,
	caret:       int,
	max_width:   f32,
}

Number_Input_Data :: struct {
	value:   f32,
	min:     f32,
	max:     f32,
	step:    f32,
	editing: bool,
}

Tooltip_Data :: struct {
	text:    string,
	target:  Widget_ID,
	visible: bool,
	//* The absolute time at which the tooltip appears.
	show_at: f32,
}

Chart_Kind :: enum {
	Bar,
	Line,
	Pie,
}

Chart_Series :: struct {
	name:   string,
	values: [dynamic]f32,
	colour: Colour,
}

Chart :: struct {
	kind:     Chart_Kind,
	series:   [dynamic]Chart_Series,
	min:      f32,
	max:      f32,
	labels:   [dynamic]string,
	selected: int,
}

Chart_Data :: struct {
	chart: ^Chart,
}

Node_Graph_Data :: struct {
	graph: rawptr,
	menu:  Widget_ID,
}

Canvas_State :: struct {
	items: [dynamic]Canvas_Item,
	last:  [dynamic]Canvas_Item,
}

Canvas_Item :: struct {
	kind:    Canvas_Item_Kind,
	pos:     Vec2,
	size:    Vec2,
	colour:  Colour,
	text:    string,
	texture: Texture,
}

Canvas_Item_Kind :: enum {
	Rect,
	Circle,
	Line,
	Text,
	Texture,
}

Canvas_Data :: struct {
	state:        ^Canvas_State,
	paint:        proc(g: ^GUI, id: Widget_ID, state: ^Canvas_State),
	repaint_rate: f32,
	//* The absolute time of the next repaint. Zero means "at once".
	next_repaint: f32,
}

Gizmo_Mode :: enum {
	All,
	Move,
	Rotate,
	Scale,
}

Gizmo_Handle :: enum {
	None,
	Move_X,
	Move_Y,
	Move_Free,
	Rotate,
	Scale_Top_Left,
	Scale_Top_Right,
	Scale_Bottom_Right,
	Scale_Bottom_Left,
}

Gizmo_Transform :: struct {
	position: Vec2,
	rotation: f32,
	scale:    Vec2,
}

Gizmo_Data :: struct {
	transform:      Gizmo_Transform,
	mode:           Gizmo_Mode,
	hover:          Gizmo_Handle,
	active:         Gizmo_Handle,
	drag_start:     Vec2,
	drag_transform: Gizmo_Transform,
	drag_angle:     f32,
	snap_position:  f32,
	snap_angle:     f32,
	min_scale:      f32,
	max_scale:      f32,
	base_size:      f32,
	on_changed:     proc(g: ^GUI, id: Widget_ID, transform: Gizmo_Transform),
	on_begin:       proc(g: ^GUI, id: Widget_ID, handle: Gizmo_Handle),
	on_end:         proc(g: ^GUI, id: Widget_ID, handle: Gizmo_Handle),
}


File_Entry :: struct {
	name:      string,
	directory: bool,
	size:      i64,
}

File_Viewer_State :: struct {
	path:     string,
	entries:  [dynamic]File_Entry,
	selected: int,
	scroll:   f32,
}

File_Viewer_Data :: struct {
	state:       ^File_Viewer_State,
	load:        proc(g: ^GUI, id: Widget_ID, state: ^File_Viewer_State),
	loaded_path: string,
}

Rich_Cursor :: struct {
	caret:     int,
	sel_start: int,
	sel_end:   int,
}

Rich_Text_Editor_State :: struct {
	text:      string,
	cursors:   [dynamic]Rich_Cursor,
	selection: Text_Selection,
	rules:     Text_Rules,
	scroll:    Vec2,
	wrap:      bool,
	pending:   u8,
}

Rich_Text_Editor_Data :: struct {
	state: ^Rich_Text_Editor_State,
}

Vector_Shape :: struct {
	kind:     Vector_Shape_Kind,
	points:   [dynamic]Vec2,
	colour:   Colour,
	width:    f32,
	selected: bool,
	filled:   bool,
}

Vector_Shape_Kind :: enum {
	Line,
	Rect,
	Ellipse,
	Polygon,
}

Vector_Drawing_State :: struct {
	shapes:   [dynamic]Vector_Shape,
	selected: int,
	dragging: int,
	scroll:   Vec2,
	zoom:     f32,
}

Vector_Drawing_Data :: struct {
	state: ^Vector_Drawing_State,
	grab:  Vec2,
}

Audio_Player_Data :: struct {
	path:     string,
	playing:  bool,
	volume:   f32,
	position: f32,
	length:   f32,
	loops:    bool,
}

Accordion_Opts :: struct {
	Base_Opts: Base_Opts,
}

Panel_Opts :: struct {
	Base_Opts: Base_Opts,
}

Button_Align :: enum {
	Theme,
	Left,
	Center,
	Right,
}

Button_Opts :: struct {
	Base_Opts:  Base_Opts,
	text:       string,
	on_pressed: proc(g: ^GUI, id: Widget_ID),
	text_align: Button_Align,
}

Label_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

Box_Opts :: struct {
	Base_Opts: Base_Opts,
}

Split_Opts :: struct {
	Base_Opts: Base_Opts,
	direction: Split_Direction,
}

Tabs_Opts :: struct {
	Base_Opts: Base_Opts,
}

Check_Box_Data :: struct {
	text: string,
	on:   bool,
}

Check_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	on:        bool,
}

Option_Button_Data :: struct {
	items:  [dynamic]string,
	active: int,
}

Option_Button_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Menu_Button_Data :: struct {
	text:  string,
	items: [dynamic]string,
	popup: Widget_ID,
}

Menu_Button_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	items:     []string,
}

Link_Button_Data :: struct {
	text: string,
	link: string,
}

Link_Button_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	link:      string,
}

Canvas_Opts :: struct {
	Base_Opts:    Base_Opts,
	repaint_rate: f32,
}

Gizmo_Opts :: struct {
	Base_Opts:     Base_Opts,
	transform:     Gizmo_Transform,
	mode:          Gizmo_Mode,
	base_size:     f32,
	min_scale:     f32,
	max_scale:     f32,
	snap_position: f32,
	snap_angle:    f32,
	on_changed:    proc(g: ^GUI, id: Widget_ID, transform: Gizmo_Transform),
	on_begin:      proc(g: ^GUI, id: Widget_ID, handle: Gizmo_Handle),
	on_end:        proc(g: ^GUI, id: Widget_ID, handle: Gizmo_Handle),
}


Chart_Opts :: struct {
	Base_Opts: Base_Opts,
	kind:      Chart_Kind,
}

Chat_Input_Opts :: struct {
	Base_Opts: Base_Opts,
}

Chat_Input_Layout :: struct {
	talk:  Rect,
	field: Rect,
}

Color_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	colour:    Colour,
}

Color_Picker_Layout :: struct {
	field: Rect,
	hue:   Rect,
	sv:    Rect,
}

Combo_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Combo_Box_Layout :: struct {
	field: Rect,
	list:  Rect,
}

Command_Palette_Opts :: struct {
	Base_Opts: Base_Opts,
}

Grid_Track_Kind :: enum {
	Auto,
	Fixed,
	Flexible,
}

Grid_Track :: struct {
	kind:     Grid_Track_Kind,
	size:     f32,
	weight:   f32,
	min_size: f32,
	max_size: f32,
}

Grid_Placement :: struct {
	row:         int,
	column:      int,
	row_span:    int,
	column_span: int,
}

grid_placement_normalize :: proc(placement: Grid_Placement) -> Grid_Placement {
	result := placement
	if result == (Grid_Placement{}) {
		result = Grid_Placement{row = -1, column = -1, row_span = 1, column_span = 1}
	}
	if result.row_span <= 0 {result.row_span = 1}
	if result.column_span <= 0 {result.column_span = 1}
	return result
}

Grid_Data :: struct {
	columns:         int,
	h_separation:    f32,
	v_separation:    f32,
	margin:          [4]f32,
	show_lines:      bool,
	line_colour:     Colour,
	cells:           []Rect,
	cell_count:      int,
	column_tracks:   []Grid_Track,
	row_tracks:      []Grid_Track,
	placements:      []Grid_Placement,
	placement_count: int,
	column_sizes:    []f32,
	row_sizes:       []f32,
}

Grid_Opts :: struct {
	Base_Opts:     Base_Opts,
	columns:       int,
	h_separation:  f32,
	v_separation:  f32,
	margin:        [4]f32,
	show_lines:    bool,
	line_colour:   Colour,
	column_tracks: []Grid_Track,
	row_tracks:    []Grid_Track,
}

Margin_Data :: struct {
	margin: [4]f32,
}

Margin_Opts :: struct {
	Base_Opts: Base_Opts,
	margin:    [4]f32,
}

Center_Opts :: struct {
	Base_Opts: Base_Opts,
}

Panel_Container_Opts :: struct {
	Base_Opts: Base_Opts,
}

Scroll_Bar_Side :: enum {
	Right,
	Left,
	Top,
	Bottom,
	None,
}

Scroll_Data :: struct {
	offset:        Vec2,
	bar:           Scroll_Bar_Side,
	bar_id:        Widget_ID,
	viewport:      Vec2,
	content:       Vec2,
	content_ready: bool,
}

Scroll_Container_Opts :: struct {
	Base_Opts:  Base_Opts,
	scroll_bar: Scroll_Bar_Side,
}

Flow_Container_Opts :: struct {
	Base_Opts: Base_Opts,
}

Aspect_Data :: struct {
	ratio: f32,
}

Aspect_Container_Opts :: struct {
	Base_Opts: Base_Opts,
	ratio:     f32,
}

Tab_Container_Data :: struct {
	active: int,
}

Tab_Container_Opts :: struct {
	Base_Opts: Base_Opts,
}

Context_Menu_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []Context_Menu_Item,
}

Data_Table_Opts :: struct {
	Base_Opts:  Base_Opts,
	//* Where the rows come from. The data stays in the program.
	source:     Table_Source,
	row_height: f32,
	header_height: f32,
}

Date_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	year:      int,
	month:     int,
	day:       int,
}

Date_Picker_Layout :: struct {
	field: Rect,
	head:  Rect,
	week:  Rect,
	days:  Rect,
}

Emoji_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	emoji:     string,
	group:     int,
}

Emoji_Picker_Layout :: struct {
	field:  Rect,
	groups: Rect,
	grid:   Rect,
}

File_Viewer_Opts :: struct {
	Base_Opts: Base_Opts,
}

Node_Graph_Opts :: struct {
	Base_Opts:    Base_Opts,
	zoom:         f32,
	min_zoom:     f32,
	max_zoom:     f32,
	grid_visible: bool,
	grid_size:    f32,
	grid_major:   f32,
	snap:         bool,
}

Number_Input_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	min:       f32,
	max:       f32,
	step:      f32,
}

Popup_Item :: struct {
	text:      string,
	icon:      Texture_ID,
	separator: bool,
	disabled:  bool,
	checked:   bool,
}

Popup_Menu_Data :: struct {
	items:    [dynamic]Popup_Item,
	selected: int,
	visible:  bool,
	owner:    Widget_ID,
}

Popup_Menu_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Popup_Panel_Opts :: struct {
	Base_Opts: Base_Opts,
}

Dialog_Data :: struct {
	text:     string,
	visible:  bool,
	accepted: bool,
}

Accept_Dialog_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

Dialog_Button :: enum {
	None,
	OK,
	Cancel,
	Open,
}

File_Dialog_Data :: struct {
	path:    string,
	mode:    File_Dialog_Mode,
	visible: bool,
}

File_Dialog_Mode :: enum {
	Open_File,
	Save_File,
	Open_Folder,
}

File_Dialog_Opts :: struct {
	Base_Opts: Base_Opts,
	mode:      File_Dialog_Mode,
}

Slider_Data :: struct {
	value: f32,
	min:   f32,
	max:   f32,
	step:  f32,
}

Slider_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	min:       f32,
	max:       f32,
	step:      f32,
}

Spin_Box_Data :: struct {
	value: f32,
	min:   f32,
	max:   f32,
	step:  f32,
}

Spin_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	min:       f32,
	max:       f32,
	step:      f32,
}

Progress_Bar_Data :: struct {
	value: f32,
	max:   f32,
}

Progress_Bar_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	max:       f32,
}

Rating_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	max:       f32,
	mark:      string,
}

Rich_Text_Editor_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	wrap:      bool,
	rules:     Text_Rules,
}

Rich_Edit :: struct {
	start: int,
	end:   int,
	text:  string,
	caret: int,
}

Scroll_Bar_Data :: struct {
	vertical: bool,
	content:  f32,
	view:     f32,
	offset:   f32,
	dragging:   bool,
	idle_until: f32,
	alpha:      f32,
	grab:     f32,
}

Search_Field_Opts :: struct {
	Base_Opts:   Base_Opts,
	text:        string,
	placeholder: string,
	hide_icon:   bool,
	max_width:   f32,
	on_submitted: proc(g: ^GUI, id: Widget_ID, text: string),
}

Segmented_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Color_Rect_Data :: struct {
	colour: Colour,
}

Color_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
	colour:    Colour,
}

Texture_Rect_Data :: struct {
	texture:      Texture,
	texture_path: string,
	region:       Rect,
}

Texture_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
	texture:   Texture,
}

Nine_Patch_Data :: struct {
	texture:         Texture,
	texture_path:    string,
	patch:           [4]f32,
	//* A sub-rectangle of the texture, in pixels. An empty rectangle
	//* means the whole texture.
	source:          Rect,
	tint:            Colour,
	horizontal_edge: Nine_Patch_Edge_Mode,
	vertical_edge:   Nine_Patch_Edge_Mode,
	centre_mode:     Nine_Patch_Centre_Mode,
}

Nine_Patch_Opts :: struct {
	Base_Opts: Base_Opts,
	texture:   Texture,
	patch:     [4]f32,
	//* A sub-rectangle of the texture, in pixels. An empty rectangle
	//* means the whole texture.
	source:          Rect,
	//* The colour multiplied into the texture. A zero colour means white,
	//* which leaves the texture unchanged.
	tint:            Colour,
	horizontal_edge: Nine_Patch_Edge_Mode,
	vertical_edge:   Nine_Patch_Edge_Mode,
	centre_mode:     Nine_Patch_Centre_Mode,
}

Reference_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
}

Rich_Text_Data :: struct {
	text:   string,
	offset: f32,
}

Rich_Text_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

Item_List_Item :: struct {
	text:     string,
	icon:     Texture_ID,
	selected: bool,
}

Item_List_Data :: struct {
	items:    [dynamic]Item_List_Item,
	selected: int,
	scroll:   f32,
}

Item_List_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Tree_Item :: struct {
	text:     string,
	depth:    int,
	parent:   int, // -1 for a root item
	expanded: bool,
	selected: bool,
	icon:     Texture_ID,
}

Tree_Data :: struct {
	items:    [dynamic]Tree_Item,
	selected: int,
	scroll:   f32,
}

Tree_Opts :: struct {
	Base_Opts: Base_Opts,
}

Tab_Bar_Opts :: struct {
	Base_Opts: Base_Opts,
}

Separator_Data :: struct {
	vertical: bool,
}

Separator_Opts :: struct {
	Base_Opts: Base_Opts,
}

Menu_Bar_Opts :: struct {
	Base_Opts: Base_Opts,
}

Time_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	hour:      int,
	minute:    int,
}

Time_Picker_Layout :: struct {
	field:   Rect,
	hours:   Rect,
	minutes: Rect,
}

Toast_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	kind:      Toast_Kind,
	duration:  f32,
}

Toggle_Switch_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	on:        bool,
}

Tooltip_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	target:    Widget_ID,
}

Vector_Drawing_Opts :: struct {
	Base_Opts: Base_Opts,
}

Virtual_List_Opts :: struct {
	Base_Opts: Base_Opts,
	source:     List_Source,
	row_height: f32,
}


//* The inspector view keeps its state in the node graph package, so the
//* core only carries the handle to it.
Node_Graph_Inspector_Data :: struct {
	state: rawptr,
}

//* == widget options ==
//*   GUI.Make_Button(g, parent, GUI.Button_Opts{
//*       Base_Opts = GUI.Base_Opts{name = "ok"},
//       text = "OK",
//   })

//* The shared options are in Base_Opts, so
//* a program only has to name the ones that are different.

Base_Opts :: struct {
	name:          string,
	preset:        Anchor_Preset,
	anchors:       Anchor,
	offsets:       Offset,
	min_size:      Vec2,
	max_size:      Vec2,
	weight:        f32,
	fixed:         bool,
	separation:    f32,
	draggable:     bool,
	style:         Style,
	use_theme:     bool,
	variation:     string,
	hidden:        bool,

	//* The control features.
	interactive:   bool,
	mouse_filter:  Mouse_Filter,
	focus_mode:    Focus_Mode,
	tab_index:     int,
	//* How the widget takes the room of its parent along the horizontal
	//* axis, and along the vertical one. A widget that expands takes a
	//* share of the room that is left over, and a widget that does not
	//* expand takes only its minimum size. A widget that fills takes the
	//* room it is given, and a widget that shrinks takes only its
	//* minimum size and is centred in the room it would have had. The
	//* default of a widget is `.Fill` and `.Expand` on both axes, and a
	//* set of flags with nothing in it means the program says nothing
	//* about that axis.
	size_flags_h:  Size_Flags,
	size_flags_v:  Size_Flags,
	//* The share of the space of the parent the widget takes when there
	//* is room left over: the weight of the widget times this ratio. A
	//* ratio of 0 in the options is the same as saying nothing: the
	//* ratio of 1 is used. A ratio of 0 is set with
	//* `Widget_Set_Stretch_Ratio`.
	stretch_ratio: f32,
	//* The share of a deficit the widget takes when the children of a
	//* container do not fit. The children that have a weight give way
	//* until they reach their floor, which is the size asked for with
	//* `min_size` or `Widget_Set_Custom_Min_Size`. A weight of 0, the
	//* default, keeps the widget at its preferred size and lets the
	//* container overflow.
	shrink_weight: f32,
	//* Takes the widget out of the flow of its container: it is placed by
	//* its anchors and offsets instead, and takes no share of the room of
	//* the container. The built-in containers honour it; a container of
	//* a custom class that lays itself out decides what it means.
	absolute:      bool,
	grid_placement: Grid_Placement,
	//* The direction the widget grows in: from the left to the right or
	//* from the right to the left. A container that stacks its children
	//* along the horizontal axis puts them in the other order when the
	//* direction is from the right to the left. The default is to take
	//* the direction of the parent.
	layout_direction: Layout_Direction,
	clip_contents: Clip_Contents,
	tooltip:       string,
	z_index:       int,
	access_role:        Access_Role,
	access_name:        string,
	access_description: string,
}

base_widget_opts :: proc(base: Base_Opts) -> Widget_Opts {
	return Widget_Opts {
		name = base.name,
		preset = base.preset,
		anchors = base.anchors,
		offsets = base.offsets,
		min_size = base.min_size,
		custom_max_size = base.max_size,
		weight = base.weight,
		fixed = base.fixed,
		separation = base.separation,
		draggable = base.draggable,
		style = base.style,
		use_theme = base.use_theme,
		variation = base.variation,
		hidden = base.hidden,
		interactive = base.interactive,
		mouse_filter = base.mouse_filter,
		focus_mode = base.focus_mode,
		tab_index = base.tab_index,
		size_flags_h = base.size_flags_h,
		size_flags_v = base.size_flags_v,
		stretch_ratio = base.stretch_ratio,
		shrink_weight = base.shrink_weight,
		absolute = base.absolute,
		grid_placement = grid_placement_normalize(base.grid_placement),
		layout_direction = base.layout_direction,
		clip_contents = base.clip_contents,
		tooltip = base.tooltip,
		z_index = base.z_index,
		access_role = base.access_role,
		access_name = base.access_name,
		access_description = base.access_description,
	}
}

//* A style with a background, a border and a margin on every side.
base_style :: proc(bg: Colour, border: Colour, width: f32, margin: f32) -> Style {
	return Style {
		box = StyleBox {
			bg_color = bg,
			border_color = {border, border, border, border},
			border_width = {width, width, width, width},
			content_margin = {margin, margin, margin, margin},
		},
	}
}
