package Core
Toast_Kind :: enum {
	Info,
	Success,
	Warning,
	Error,
}

Toast_Data :: struct {
	text:      string,
	duration:  f32,
	remaining:  f32,
	kind:      Toast_Kind,
}

Palette_Command :: struct {
	label:    string,
	action:   proc(g: ^GUI, id: Widget_ID),
	keywords: string,
}

Command_Palette_Data :: struct {
	text:     string,
	commands: [dynamic]Palette_Command,
	selected: int,
	visible:  bool,
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
	timer:   f32,
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

Graph_Port :: struct {
	name:      string,
	direction: Graph_Port_Direction,
	wire:      int,
}

Graph_Port_Direction :: enum {
	Input,
	Output,
	Both,
}

Graph_Node :: struct {
	title:    string,
	pos:      Vec2,
	size:     Vec2,
	ports:    [dynamic]Graph_Port,
	colour:   Colour,
	selected: bool,
}

Graph_Wire :: struct {
	from_node: int,
	from_port: int,
	to_node:   int,
	to_port:   int,
	colour:    Colour,
}

Node_Graph :: struct {
	nodes:        [dynamic]Graph_Node,
	wires:        [dynamic]Graph_Wire,
	selected:     int,
	scroll:       Vec2,
	zoom:         f32,
	pan:          Vec2,
	dragging:     int,
	moving_node:  int,
	drag_offset:  Vec2,
	panning:      bool,
	pan_last:     Vec2,
}

Node_Graph_Data :: struct {
	graph: ^Node_Graph,
}

Canvas_State :: struct {
	items: [dynamic]Canvas_Item,
}

Canvas_Item :: struct {
	kind:   Canvas_Item_Kind,
	pos:    Vec2,
	size:   Vec2,
	colour: Colour,
	text:   string,
}

Canvas_Item_Kind :: enum {
	Rect,
	Circle,
	Line,
	Text,
}

Canvas_Data :: struct {
	state: ^Canvas_State,
	paint: proc(g: ^GUI, id: Widget_ID, state: ^Canvas_State),
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
	Base_Opts: Base_Opts,
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

Grid_Data :: struct {
	columns:      int,
	h_separation: f32,
	v_separation: f32,
	margin:       [4]f32,
	show_lines:   bool,
	line_colour:  Colour,
	cells:        []Rect,
	cell_count:   int,
}

Grid_Opts :: struct {
	Base_Opts:    Base_Opts,
	columns:      int,
	h_separation: f32,
	v_separation: f32,
	margin:       [4]f32,
	show_lines:   bool,
	line_colour:  Colour,
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
	Base_Opts: Base_Opts,
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
	dragging: bool,
	idle:     f32,
	alpha:    f32,
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
	texture: Texture,
	region:  Rect,
}

Texture_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
	texture:   Texture,
}

Nine_Patch_Data :: struct {
	texture: Texture,
	patch:   [4]f32,
}

Nine_Patch_Opts :: struct {
	Base_Opts: Base_Opts,
	texture:   Texture,
	patch:     [4]f32,
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
