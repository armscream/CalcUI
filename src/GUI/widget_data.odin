package GUI

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
	year:  int,
	month: int,
	day:   int,
	open:  bool,
}

Time_Picker_Data :: struct {
	hour:   int,
	minute: int,
	open:   bool,
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