package NodeGraph

import Core "../Core"
import "core:fmt"
import "core:strings"

Graph_Port_Direction :: enum {
	Input,
	Output,
	Both,
}

Graph_Node_ID :: struct {
	index:      u32,
	generation: u32,
}

Graph_Port_ID :: struct {
	index:      u32,
	generation: u32,
}

Graph_Wire_ID :: struct {
	index:      u32,
	generation: u32,
}

INVALID_GRAPH_NODE_ID :: Graph_Node_ID{0, 0}
INVALID_GRAPH_PORT_ID :: Graph_Port_ID{0, 0}
INVALID_GRAPH_WIRE_ID :: Graph_Wire_ID{0, 0}

Graph_Value_Kind :: enum {
	Bool,
	Int,
	Float,
	Vec2,
	Vec3,
	Colour,
	String,
}

Graph_Value :: union {
	bool,
	i32,
	f32,
	Core.Vec2,
	Core.Vec3,
	Core.Colour,
	string,
}

Graph_Config_Entry :: struct {
	key:       string,
	value:     Graph_Value,
	read_only: bool,
}

Graph_Port_Kind :: enum {
	Data,
	Exec,
}

Graph_Port_Desc :: struct {
	name:          string,
	direction:     Graph_Port_Direction,
	port_kind:     Graph_Port_Kind,
	type:          string,
	colour:        Core.Colour,
	capacity:      i32,
	default_value: Graph_Value,
	tooltip:       string,
	visible:       bool,
}

Graph_Port_Policy :: struct {
	add_inputs:    bool,
	add_outputs:   bool,
	max_inputs:    i32,
	max_outputs:   i32,
	input_type:    string,
	output_type:   string,
	input_prefix:  string,
	output_prefix: string,
}

Graph_Node_Type_Desc :: struct {
	name:         string,
	short_title:  string,
	category:     string,
	description:  string,
	colour:       Core.Colour,
	default_size: Core.Vec2,
	min_size:     Core.Vec2,
	max_size:     Core.Vec2,
	resizable:    bool,
	collapsible:  bool,
	inputs:       []Graph_Port_Desc,
	outputs:      []Graph_Port_Desc,
	config:       []Graph_Config_Entry,
	policy:       Graph_Port_Policy,
	configure:    proc(g: ^Core.GUI, graph: Core.Widget_ID, node: Graph_Node_ID),
	user_data:    rawptr,
}

Graph_Node_Type :: struct {
	name:         string,
	short_title:  string,
	category:     string,
	description:  string,
	colour:       Core.Colour,
	default_size: Core.Vec2,
	min_size:     Core.Vec2,
	max_size:     Core.Vec2,
	resizable:    bool,
	collapsible:  bool,
	inputs:       [dynamic]Graph_Port_Desc,
	outputs:      [dynamic]Graph_Port_Desc,
	config:       [dynamic]Graph_Config_Entry,
	policy:       Graph_Port_Policy,
	configure:    proc(g: ^Core.GUI, graph: Core.Widget_ID, node: Graph_Node_ID),
	user_data:    rawptr,
}

Graph_Kind_Desc :: struct {
	name:          string,
	description:   string,
	execution:     bool,
	allowed_nodes: []string,
}

Graph_Kind :: struct {
	name:          string,
	description:   string,
	execution:     bool,
	allowed_nodes: [dynamic]string,
}

Graph_Connection_Policy :: struct {
	user_data:       rawptr,
	type_compatible: proc(user_data: rawptr, from_type, to_type: string) -> bool,
	validate:        proc(
		user_data: rawptr,
		graph: ^Node_Graph,
		from_node: Graph_Node_ID,
		from_port: Graph_Port_ID,
		to_node: Graph_Node_ID,
		to_port: Graph_Port_ID,
	) -> bool,
	allow_cycles:    bool,
}

Graph_Port :: struct {
	id:            Graph_Port_ID,
	alive:         bool,
	name:          string,
	direction:     Graph_Port_Direction,
	port_kind:     Graph_Port_Kind,
	type:          string,
	colour:        Core.Colour,
	capacity:      i32,
	default_value: Graph_Value,
	tooltip:       string,
	visible:       bool,
	connections:   i32,
}

Graph_Node_Kind :: enum {
	Normal,
	Reroute_Dot,
	Reroute_Convert,
}

Graph_Node :: struct {
	id:         Graph_Node_ID,
	alive:      bool,
	kind:       Graph_Node_Kind,
	type_name:  string,
	title:      string,
	short_title: string,
	pos:        Core.Vec2,
	size:       Core.Vec2,
	min_size:   Core.Vec2,
	max_size:   Core.Vec2,
	colour:     Core.Colour,
	selected:   bool,
	collapsed:  bool,
	collapsible: bool,
	resizable:  bool,
	ports:      [dynamic]Graph_Port,
	free_ports: [dynamic]u32,
	config:     [dynamic]Graph_Config_Entry,
	user:       rawptr,
	reroute_input_type:  string,
	reroute_output_type: string,
}

Graph_Wire :: struct {
	id:        Graph_Wire_ID,
	alive:     bool,
	from_node: Graph_Node_ID,
	from_port: Graph_Port_ID,
	to_node:   Graph_Node_ID,
	to_port:   Graph_Port_ID,
	colour:    Core.Colour,
	selected:  bool,
}

Graph_Clip_Port :: struct {
	desc: Graph_Port_Desc,
}

Graph_Clip_Node :: struct {
	type_name: string,
	title:     string,
	pos:       Core.Vec2,
	size:      Core.Vec2,
	min_size:  Core.Vec2,
	max_size:  Core.Vec2,
	colour:    Core.Colour,
	collapsed: bool,
	collapsible: bool,
	resizable: bool,
	ports:     [dynamic]Graph_Clip_Port,
	config:    [dynamic]Graph_Config_Entry,
}

Graph_Clip_Wire :: struct {
	from_node: int,
	from_port: int,
	to_node:   int,
	to_port:   int,
}

Graph_Clipboard :: struct {
	nodes:  [dynamic]Graph_Clip_Node,
	wires:  [dynamic]Graph_Clip_Wire,
	origin: Core.Vec2,
	valid:  bool,
}

Graph_Undo_Record :: struct {
	before: string,
	after:  string,
	label:  string,
}

Graph_Interaction_Mode :: enum {
	None,
	Pan,
	Marquee,
	Move_Nodes,
	Resize_Node,
	Drag_Wire,
	Reconnect_Wire,
	Move_Region,
	Resize_Region,
}

Graph_Type_Colour :: struct {
	name:   string,
	colour: Core.Colour,
}

Graph_Node_Double_Click_Callback :: proc(
	g: ^Core.GUI,
	graph: Core.Widget_ID,
	node: Graph_Node_ID,
)

Graph_Wire_Double_Click_Callback :: proc(
	g: ^Core.GUI,
	graph: Core.Widget_ID,
	wire: Graph_Wire_ID,
	position: Core.Vec2,
)

Graph_Wire_Connect_Failed_Callback :: proc(
	g: ^Core.GUI,
	graph: Core.Widget_ID,
	from_node: Graph_Node_ID,
	from_port: Graph_Port_ID,
	to_node: Graph_Node_ID,
	to_port: Graph_Port_ID,
)

Graph_Callbacks :: struct {
	node_double_click:     Graph_Node_Double_Click_Callback,
	wire_double_click:     Graph_Wire_Double_Click_Callback,
	wire_connect_failed:   Graph_Wire_Connect_Failed_Callback,
}

Node_Graph :: struct {
	nodes:        [dynamic]Graph_Node,
	free_nodes:   [dynamic]u32,
	wires:        [dynamic]Graph_Wire,
	free_wires:   [dynamic]u32,
	regions:      [dynamic]Graph_Region,
	free_regions: [dynamic]u32,
	types:        [dynamic]Graph_Node_Type,
	type_by_name: map[string]int,
	kinds:        [dynamic]Graph_Kind,
	kind_by_name: map[string]int,
	kind_name:    string,
	policy:       Graph_Connection_Policy,
	metadata:     map[string]string,
	type_colours: [dynamic]Graph_Type_Colour,

	scroll:       Core.Vec2,
	pan:          Core.Vec2,
	zoom:         f32,
	min_zoom:     f32,
	max_zoom:     f32,
	zoom_step:    f32,
	grid_visible: bool,
	grid_size:    f32,
	grid_major:   f32,
	snap:         bool,

	mode:            Graph_Interaction_Mode,
	pan_origin:      Core.Vec2,
	pan_scroll:      Core.Vec2,
	marquee_start:   Core.Vec2,
	marquee_end:     Core.Vec2,
	marquee_additive: bool,
	drag_origin:     Core.Vec2,
	drag_offset:     Core.Vec2,
	dragging_nodes:  [dynamic]Graph_Node_ID,
	drag_starts:     [dynamic]Core.Vec2,
	resize_node:     Graph_Node_ID,
	resize_start:    Core.Vec2,
	resize_size:     Core.Vec2,
	resize_region:   Graph_Region_ID,
	drag_region:     Graph_Region_ID,
	region_drag_nodes: [dynamic]Graph_Node_ID,
	region_drag_starts: [dynamic]Core.Vec2,
	active_port_node: Graph_Node_ID,
	active_port:     Graph_Port_ID,
	active_wire:     Graph_Wire_ID,
	hover_node:      Graph_Node_ID,
	hover_port:      Graph_Port_ID,
	hover_port_node: Graph_Node_ID,
	hover_wire:      Graph_Wire_ID,
	hover_region:    Graph_Region_ID,
	cursor_graph:    Core.Vec2,

	clipboard: Graph_Clipboard,

	cycle_seen:   [dynamic]Graph_Node_ID,
	cycle_stack:  [dynamic]Graph_Node_ID,

	undo_records:       [dynamic]Graph_Undo_Record,
	undo_at:            int,
	undo_pending:       string,
	undo_pending_valid: bool,
	undo_depth:         int,

	menu_pos:        Core.Vec2,
	menu_pending:    bool,
	menu_from_node:  Graph_Node_ID,
	menu_from_port:  Graph_Port_ID,
	menu_direction:  Graph_Port_Direction,
	revision:        u64,
	callbacks:       Graph_Callbacks,

	style:       Graph_Style,
	metrics:     Graph_Metrics,
	geometry_epoch: u64,
	cache_valid: bool,
	cache:       Graph_Geometry_Cache,
	node_scratch: [dynamic]int,
	wire_scratch: [dynamic]int,
	inspector_actions: [dynamic]Graph_Inspector_Action,
	//* The tooltip of the canvas: the text, where it started, and how long
	//* the pointer has rested.
	tooltip_text:   string,
	tooltip_node:   Graph_Node_ID,
	tooltip_port:   Graph_Port_ID,
	tooltip_anchor: Core.Vec2,
	tooltip_graph:  Core.Vec2,
	tooltip_timer:  f32,
	tooltip_buf:    [256]u8,
}

Node_Graph_Node_Of :: proc(graph: ^Node_Graph, id: Graph_Node_ID) -> ^Graph_Node {
	if graph == nil || id.index == 0 {return nil}
	index := int(id.index) - 1
	if index < 0 || index >= len(graph.nodes) {return nil}
	node := &graph.nodes[index]
	if !node.alive || node.id != id {return nil}
	return node
}

Node_Graph_Port_Of :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> ^Graph_Port {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil || port_id.index == 0 {return nil}
	index := int(port_id.index) - 1
	if index < 0 || index >= len(node.ports) {return nil}
	port := &node.ports[index]
	if !port.alive || port.id != port_id {return nil}
	return port
}

Node_Graph_Wire_Of :: proc(graph: ^Node_Graph, id: Graph_Wire_ID) -> ^Graph_Wire {
	if graph == nil || id.index == 0 {return nil}
	index := int(id.index) - 1
	if index < 0 || index >= len(graph.wires) {return nil}
	wire := &graph.wires[index]
	if !wire.alive || wire.id != id {return nil}
	return wire
}

Graph_Value_Clone :: proc(value: Graph_Value) -> Graph_Value {
	clone := value
	#partial switch v in value {
	case string:
		return Graph_Value(strings.clone(v))
	}
	return clone
}

Graph_Value_Free :: proc(value: Graph_Value) {
	#partial switch v in value {
	case string:
		if len(v) > 0 {delete(v)}
	}
}

Graph_Value_Kind_Of :: proc(value: Graph_Value) -> Graph_Value_Kind {
	switch v in value {
	case bool:   return .Bool
	case i32:    return .Int
	case f32:    return .Float
	case Core.Vec2:   return .Vec2
	case Core.Vec3:   return .Vec3
	case Core.Colour: return .Colour
	case string: return .String
	}
	return .Bool
}

Graph_Config_Entry_Free :: proc(entry: ^Graph_Config_Entry) {
	if len(entry.key) > 0 {delete(entry.key)}
	Graph_Value_Free(entry.value)
	entry.key = ""
	entry.value = nil
}

Graph_Config_Free :: proc(entries: ^[dynamic]Graph_Config_Entry) {
	for &entry in entries {Graph_Config_Entry_Free(&entry)}
	delete(entries^)
	entries^ = nil
}

Graph_Config_Clone :: proc(entries: []Graph_Config_Entry) -> [dynamic]Graph_Config_Entry {
	out: [dynamic]Graph_Config_Entry
	for entry in entries {
		append(&out, Graph_Config_Entry{key = strings.clone(entry.key), value = Graph_Value_Clone(entry.value), read_only = entry.read_only})
	}
	return out
}

Graph_Port_Desc_Clone :: proc(desc: Graph_Port_Desc) -> Graph_Port_Desc {
	clone := desc
	clone.name = strings.clone(desc.name)
	clone.type = strings.clone(desc.type)
	clone.tooltip = strings.clone(desc.tooltip)
	clone.default_value = Graph_Value_Clone(desc.default_value)
	return clone
}

Graph_Port_Desc_Free :: proc(desc: ^Graph_Port_Desc) {
	if len(desc.name) > 0 {delete(desc.name)}
	if len(desc.type) > 0 {delete(desc.type)}
	if len(desc.tooltip) > 0 {delete(desc.tooltip)}
	Graph_Value_Free(desc.default_value)
	desc.name = ""
	desc.type = ""
	desc.tooltip = ""
	desc.default_value = nil
}

Graph_Port_Desc_List_Clone :: proc(descs: []Graph_Port_Desc) -> [dynamic]Graph_Port_Desc {
	out: [dynamic]Graph_Port_Desc
	for desc in descs {append(&out, Graph_Port_Desc_Clone(desc))}
	return out
}

Graph_Port_Desc_List_Free :: proc(descs: ^[dynamic]Graph_Port_Desc) {
	for &desc in descs {Graph_Port_Desc_Free(&desc)}
	delete(descs^)
	descs^ = nil
}

Graph_Find_Type :: proc(graph: ^Node_Graph, name: string) -> int {
	if graph == nil || graph.type_by_name == nil {return -1}
	index, found := graph.type_by_name[name]
	if !found {return -1}
	if index < 0 || index >= len(graph.types) {return -1}
	return index
}

Graph_Node_Type_Clear :: proc(node_type: ^Graph_Node_Type) {
	if len(node_type.name) > 0 {delete(node_type.name)}
	if len(node_type.short_title) > 0 {delete(node_type.short_title)}
	if len(node_type.category) > 0 {delete(node_type.category)}
	if len(node_type.description) > 0 {delete(node_type.description)}
	Graph_Port_Desc_List_Free(&node_type.inputs)
	Graph_Port_Desc_List_Free(&node_type.outputs)
	Graph_Config_Free(&node_type.config)
	if len(node_type.policy.input_type) > 0 {delete(node_type.policy.input_type)}
	if len(node_type.policy.output_type) > 0 {delete(node_type.policy.output_type)}
	if len(node_type.policy.input_prefix) > 0 {delete(node_type.policy.input_prefix)}
	if len(node_type.policy.output_prefix) > 0 {delete(node_type.policy.output_prefix)}
	node_type^ = Graph_Node_Type{}
}

Graph_Node_Type_Apply :: proc(node_type: ^Graph_Node_Type, desc: Graph_Node_Type_Desc) {
	node_type.name = strings.clone(desc.name)
	node_type.short_title = graph_string_copy(desc.short_title)
	node_type.category = strings.clone(desc.category)
	node_type.description = strings.clone(desc.description)
	node_type.colour = desc.colour
	node_type.default_size = desc.default_size
	//* A size of zero means the node follows its content.
	//* A height of zero means the node grows with its rows.
	node_type.min_size = desc.min_size
	if node_type.min_size.x <= 0 {node_type.min_size.x = NODE_MIN_WIDTH}
	if node_type.min_size.y <= 0 {node_type.min_size.y = NODE_MIN_HEIGHT}
	node_type.max_size = desc.max_size
	if node_type.max_size.x <= 0 {node_type.max_size.x = NODE_MAX_WIDTH}
	if node_type.max_size.y <= 0 {node_type.max_size.y = NODE_MAX_HEIGHT}
	node_type.resizable = desc.resizable
	node_type.collapsible = desc.collapsible
	node_type.inputs = Graph_Port_Desc_List_Clone(desc.inputs)
	node_type.outputs = Graph_Port_Desc_List_Clone(desc.outputs)
	node_type.config = Graph_Config_Clone(desc.config)
	node_type.policy = desc.policy
	node_type.policy.input_type = strings.clone(desc.policy.input_type)
	node_type.policy.output_type = strings.clone(desc.policy.output_type)
	node_type.policy.input_prefix = strings.clone(desc.policy.input_prefix)
	node_type.policy.output_prefix = strings.clone(desc.policy.output_prefix)
	node_type.configure = desc.configure
	node_type.user_data = desc.user_data
}

Graph_Register_Type :: proc(graph: ^Node_Graph, desc: Graph_Node_Type_Desc) -> int {
	if graph == nil || desc.name == "" {return -1}
	index := Graph_Find_Type(graph, desc.name)
	if index < 0 {
		index = len(graph.types)
		append(&graph.types, Graph_Node_Type{})
		if graph.type_by_name == nil {graph.type_by_name = make(map[string]int)}
		graph.type_by_name[strings.clone(desc.name)] = index
		Graph_Node_Type_Apply(&graph.types[index], desc)
	} else {
		Graph_Node_Type_Clear(&graph.types[index])
		Graph_Node_Type_Apply(&graph.types[index], desc)
	}
	return index
}

Graph_Find_Kind :: proc(graph: ^Node_Graph, name: string) -> int {
	if graph == nil || graph.kind_by_name == nil || name == "" {return -1}
	index, found := graph.kind_by_name[name]
	if !found {return -1}
	if index < 0 || index >= len(graph.kinds) {return -1}
	return index
}

Graph_Kind_Clear :: proc(kind: ^Graph_Kind) {
	if kind == nil {return}
	if len(kind.name) > 0 {delete(kind.name)}
	if len(kind.description) > 0 {delete(kind.description)}
	for &name in kind.allowed_nodes {
		if len(name) > 0 {delete(name)}
	}
	delete(kind.allowed_nodes)
	kind^ = Graph_Kind{}
}

Graph_Kind_Allowed_Clone :: proc(names: []string) -> [dynamic]string {
	clone: [dynamic]string
	for name in names {append(&clone, strings.clone(name))}
	return clone
}

Graph_Kind_Apply :: proc(kind: ^Graph_Kind, desc: Graph_Kind_Desc) {
	kind.name = strings.clone(desc.name)
	kind.description = strings.clone(desc.description)
	kind.execution = desc.execution
	kind.allowed_nodes = Graph_Kind_Allowed_Clone(desc.allowed_nodes)
}

Graph_Register_Kind :: proc(graph: ^Node_Graph, desc: Graph_Kind_Desc) -> int {
	if graph == nil || desc.name == "" {return -1}
	index := Graph_Find_Kind(graph, desc.name)
	if index < 0 {
		index = len(graph.kinds)
		append(&graph.kinds, Graph_Kind{})
		if graph.kind_by_name == nil {graph.kind_by_name = make(map[string]int)}
		graph.kind_by_name[strings.clone(desc.name)] = index
		Graph_Kind_Apply(&graph.kinds[index], desc)
	} else {
		Graph_Kind_Clear(&graph.kinds[index])
		Graph_Kind_Apply(&graph.kinds[index], desc)
	}
	return index
}

Graph_Set_Kind :: proc(graph: ^Node_Graph, name: string) -> bool {
	if graph == nil {return false}
	if name == "" {
		if len(graph.kind_name) > 0 {delete(graph.kind_name)}
		graph.kind_name = ""
		return true
	}
	if Graph_Find_Kind(graph, name) < 0 {return false}
	if graph.kind_name == name {return true}
	new_name := strings.clone(name)
	if len(graph.kind_name) > 0 {delete(graph.kind_name)}
	graph.kind_name = new_name
	return true
}

Graph_Kind_Name :: proc(graph: ^Node_Graph) -> string {
	if graph == nil {return ""}
	return graph.kind_name
}

Graph_Kind_Of :: proc(graph: ^Node_Graph) -> ^Graph_Kind {
	if graph == nil {return nil}
	index := Graph_Find_Kind(graph, graph.kind_name)
	if index < 0 {return nil}
	return &graph.kinds[index]
}

Graph_Kind_Is_Execution :: proc(graph: ^Node_Graph) -> bool {
	kind := Graph_Kind_Of(graph)
	if kind == nil {return true}
	return kind.execution
}

Graph_Kind_Allows_Type :: proc(graph: ^Node_Graph, type_name: string) -> bool {
	kind := Graph_Kind_Of(graph)
	if kind == nil {return true}
	if len(kind.allowed_nodes) == 0 {return true}
	for name in kind.allowed_nodes {
		if name == type_name {return true}
	}
	return false
}

Graph_Node_Type_Is_Exec :: proc(node_type: ^Graph_Node_Type) -> bool {
	if node_type == nil {return false}
	for desc in node_type.inputs {
		if desc.port_kind == .Exec {return true}
	}
	for desc in node_type.outputs {
		if desc.port_kind == .Exec {return true}
	}
	return false
}

Graph_Clear_Kinds :: proc(graph: ^Node_Graph) {
	if graph == nil {return}
	for &kind in graph.kinds {Graph_Kind_Clear(&kind)}
	delete(graph.kinds)
	graph.kinds = nil
	if graph.kind_by_name != nil {
		for key in graph.kind_by_name {delete(key)}
		delete(graph.kind_by_name)
		graph.kind_by_name = nil
	}
	if len(graph.kind_name) > 0 {delete(graph.kind_name)}
	graph.kind_name = ""
}

Graph_Node_Slot :: proc(graph: ^Node_Graph) -> ^Graph_Node {
	index := 0
	generation: u32 = 1
	if len(graph.free_nodes) > 0 {
		last := len(graph.free_nodes) - 1
		index = int(graph.free_nodes[last])
		resize(&graph.free_nodes, last)
		generation = graph.nodes[index].id.generation + 1
	} else {
		index = len(graph.nodes)
		append(&graph.nodes, Graph_Node{})
	}
	if generation == 0 {generation = 1}
	node := &graph.nodes[index]
	node^ = Graph_Node{}
	node.id = Graph_Node_ID{u32(index + 1), generation}
	node.alive = true
	node.size = Core.Vec2{0, 0}
	node.min_size = Core.Vec2{NODE_MIN_WIDTH, NODE_MIN_HEIGHT}
	node.max_size = Core.Vec2{NODE_MAX_WIDTH, NODE_MAX_HEIGHT}
	node.resizable = true
	node.collapsible = true
	return node
}

Graph_Port_Slot :: proc(node: ^Graph_Node) -> ^Graph_Port {
	index := 0
	generation: u32 = 1
	if len(node.free_ports) > 0 {
		last := len(node.free_ports) - 1
		index = int(node.free_ports[last])
		resize(&node.free_ports, last)
		generation = node.ports[index].id.generation + 1
	} else {
		index = len(node.ports)
		append(&node.ports, Graph_Port{})
	}
	if generation == 0 {generation = 1}
	port := &node.ports[index]
	port^ = Graph_Port{}
	port.id = Graph_Port_ID{u32(index + 1), generation}
	port.alive = true
	port.visible = true
	port.capacity = 1
	return port
}

Graph_Wire_Slot :: proc(graph: ^Node_Graph) -> ^Graph_Wire {
	index := 0
	generation: u32 = 1
	if len(graph.free_wires) > 0 {
		last := len(graph.free_wires) - 1
		index = int(graph.free_wires[last])
		resize(&graph.free_wires, last)
		generation = graph.wires[index].id.generation + 1
	} else {
		index = len(graph.wires)
		append(&graph.wires, Graph_Wire{})
	}
	if generation == 0 {generation = 1}
	wire := &graph.wires[index]
	wire^ = Graph_Wire{}
	wire.id = Graph_Wire_ID{u32(index + 1), generation}
	wire.alive = true
	return wire
}

Graph_Add_Node :: proc(graph: ^Node_Graph, title: string, pos: Core.Vec2) -> Graph_Node_ID {
	node := Graph_Node_Slot(graph)
	node.title = strings.clone(title)
	node.pos = pos
	Graph_Geometry_Invalidate(graph)
	return node.id
}

Graph_Add_Typed_Node :: proc(graph: ^Node_Graph, type_name: string, pos: Core.Vec2) -> Graph_Node_ID {
	if !Graph_Kind_Allows_Type(graph, type_name) {return INVALID_GRAPH_NODE_ID}
	index := Graph_Find_Type(graph, type_name)
	if index < 0 {
		id := Graph_Add_Node(graph, type_name, pos)
		node := Node_Graph_Node_Of(graph, id)
		node.type_name = strings.clone(type_name)
		return id
	}
	node_type := &graph.types[index]
	node := Graph_Node_Slot(graph)
	node.type_name = strings.clone(node_type.name)
	node.title = strings.clone(node_type.name)
	node.short_title = graph_string_copy(node_type.short_title)
	node.pos = pos
	node.size = node_type.default_size
	node.min_size = node_type.min_size
	node.max_size = node_type.max_size
	node.colour = node_type.colour
	node.resizable = true
	node.collapsible = true
	for desc in node_type.inputs {Graph_Add_Port(node, desc)}
	for desc in node_type.outputs {Graph_Add_Port(node, desc)}
	for entry in node_type.config {
		append(&node.config, Graph_Config_Entry{key = strings.clone(entry.key), value = Graph_Value_Clone(entry.value), read_only = entry.read_only})
	}
	Graph_Geometry_Invalidate(graph)
	return node.id
}

Graph_Configure_Of :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID) -> proc(g: ^Core.GUI, graph: Core.Widget_ID, node: Graph_Node_ID) {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return nil}
	index := Graph_Find_Type(graph, node.type_name)
	if index < 0 {return nil}
	return graph.types[index].configure
}

Graph_Port_Release :: proc(graph: ^Node_Graph, node: ^Graph_Node, index: int) {
	port := &node.ports[index]
	if !port.alive {return}
	if len(port.name) > 0 {delete(port.name)}
	if len(port.type) > 0 {delete(port.type)}
	if len(port.tooltip) > 0 {delete(port.tooltip)}
	Graph_Value_Free(port.default_value)
	port.name = ""
	port.type = ""
	port.tooltip = ""
	port.default_value = nil
	port.connections = 0
	port.alive = false
	append(&node.free_ports, u32(index))
	Graph_Geometry_Invalidate(graph)
}

Graph_Wire_Release :: proc(graph: ^Node_Graph, index: int) {
	wire := &graph.wires[index]
	if !wire.alive {return}
	if from := Node_Graph_Port_Of(graph, wire.from_node, wire.from_port); from != nil {
		if from.connections > 0 {from.connections -= 1}
	}
	if to := Node_Graph_Port_Of(graph, wire.to_node, wire.to_port); to != nil {
		if to.connections > 0 {to.connections -= 1}
	}
	wire.alive = false
	append(&graph.free_wires, u32(index))
	Graph_Geometry_Invalidate(graph)
}

Graph_Node_Release :: proc(graph: ^Node_Graph, node_index: int) {
	node := &graph.nodes[node_index]
	if !node.alive {return}
	for i := len(graph.wires) - 1; i >= 0; i -= 1 {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		if wire.from_node == node.id || wire.to_node == node.id {Graph_Wire_Release(graph, i)}
	}
	for i := 0; i < len(node.ports); i += 1 {Graph_Port_Release(graph, node, i)}
	delete(node.ports)
	node.ports = nil
	delete(node.free_ports)
	node.free_ports = nil
	Graph_Config_Free(&node.config)
	if len(node.title) > 0 {delete(node.title)}
	if len(node.short_title) > 0 {delete(node.short_title)}
	if len(node.type_name) > 0 {delete(node.type_name)}
	if len(node.reroute_input_type) > 0 {delete(node.reroute_input_type)}
	if len(node.reroute_output_type) > 0 {delete(node.reroute_output_type)}
	node.title = ""
	node.short_title = ""
	node.type_name = ""
	node.user = nil
	node.alive = false
	append(&graph.free_nodes, u32(node_index))
	Graph_Geometry_Invalidate(graph)
}

Graph_Port_Direction_Side :: proc(port: ^Graph_Port) -> Graph_Port_Direction {
	if port.direction == .Input {return .Input}
	return .Output
}

Graph_Add_Port :: proc(node: ^Graph_Node, desc: Graph_Port_Desc) -> Graph_Port_ID {
	port := Graph_Port_Slot(node)
	port.name = strings.clone(desc.name)
	port.direction = desc.direction
	port.port_kind = desc.port_kind
	port.type = strings.clone(desc.type)
	port.colour = desc.colour
	port.capacity = desc.capacity
	port.default_value = Graph_Value_Clone(desc.default_value)
	port.tooltip = strings.clone(desc.tooltip)
	port.visible = desc.visible
	return port.id
}
Graph_Set_Port_Properties :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
	name, type_name: string,
) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if node == nil || port == nil || name == "" {return false}
	if node.kind == .Reroute_Convert {return false}
	if type_name != port.type {
		for wire in graph.wires {
			if !wire.alive {continue}
			if wire.from_node == node.id && wire.from_port == port_id {
				target := Graph_Effective_Port_Type(graph, wire.to_node, wire.to_port)
				if !reroute_type_matches(type_name, target) {return false}
			}
			if wire.to_node == node.id && wire.to_port == port_id {
				source := Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port)
				if !reroute_type_matches(source, type_name) {return false}
			}
		}
	}
	new_name := strings.clone(name)
	new_type := strings.clone(type_name)
	if len(port.name) > 0 {delete(port.name)}
	if len(port.type) > 0 {delete(port.type)}
	port.name = new_name
	port.type = new_type
	Graph_Geometry_Invalidate(graph)
	return true
}

Graph_Set_Ports :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, descs: []Graph_Port_Desc) {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return}
	matched: [dynamic]bool
	defer delete(matched)
	for _ in node.ports {append(&matched, false)}
	for desc in descs {
		found := -1
		for i in 0 ..< len(node.ports) {
			port := &node.ports[i]
			if !port.alive || matched[i] {continue}
			if port.name == desc.name && port.direction == desc.direction && port.port_kind == desc.port_kind {
				found = i
				break
			}
		}
		if found < 0 {
			port_id := Graph_Add_Port(node, desc)
			for len(matched) < len(node.ports) {append(&matched, false)}
			matched[int(port_id.index) - 1] = true
			continue
		}
		port := &node.ports[found]
		matched[found] = true
		new_name := strings.clone(desc.name)
		new_type := strings.clone(desc.type)
		new_tooltip := strings.clone(desc.tooltip)
		new_default := Graph_Value_Clone(desc.default_value)
		if len(port.name) > 0 {delete(port.name)}
		if len(port.type) > 0 {delete(port.type)}
		if len(port.tooltip) > 0 {delete(port.tooltip)}
		Graph_Value_Free(port.default_value)
		port.name = new_name
		port.type = new_type
		port.colour = desc.colour
		port.port_kind = desc.port_kind
		port.capacity = desc.capacity
		port.default_value = new_default
		port.tooltip = new_tooltip
		port.visible = desc.visible
	}
	for i := len(node.ports) - 1; i >= 0; i -= 1 {
		if !node.ports[i].alive || matched[i] {continue}
		port_id := node.ports[i].id
		for j := len(graph.wires) - 1; j >= 0; j -= 1 {
			wire := &graph.wires[j]
			if !wire.alive {continue}
			if (wire.from_node == node_id && wire.from_port == port_id) || (wire.to_node == node_id && wire.to_port == port_id) {
				Graph_Wire_Release(graph, j)
			}
		}
		Graph_Port_Release(graph, node, i)
	}
	Graph_Geometry_Invalidate(graph)
}

Graph_Set_Config_Value :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, key: string, value: Graph_Value) {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil || key == "" {return}
	for &entry in node.config {
		if entry.key == key {
			new_value := Graph_Value_Clone(value)
			Graph_Value_Free(entry.value)
			entry.value = new_value
			Graph_Geometry_Invalidate(graph)
			return
		}
	}
	append(&node.config, Graph_Config_Entry{key = strings.clone(key), value = Graph_Value_Clone(value), read_only = false})
	Graph_Geometry_Invalidate(graph)
}

Graph_Get_Config_Value :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, key: string) -> (Graph_Value, bool) {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return nil, false}
	for entry in node.config {
		if entry.key == key {return entry.value, true}
	}
	return nil, false
}

Graph_Set_Derived_Value :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, key: string, value: Graph_Value) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil || key == "" {return false}
	for &entry in node.config {
		if entry.key != key || !entry.read_only {continue}
		new_value := Graph_Value_Clone(value)
		Graph_Value_Free(entry.value)
		entry.value = new_value
		return true
	}
	return false
}

Graph_Type_Compatible :: proc(graph: ^Node_Graph, from_type, to_type: string) -> bool {
	if graph.policy.type_compatible != nil {
		return graph.policy.type_compatible(graph.policy.user_data, from_type, to_type)
	}
	if from_type == to_type {return true}
	return from_type == "" || to_type == ""
}

Graph_Wire_Find :: proc(graph: ^Node_Graph, from_node: Graph_Node_ID, from_port: Graph_Port_ID, to_node: Graph_Node_ID, to_port: Graph_Port_ID) -> Graph_Wire_ID {
	for i in 0 ..< len(graph.wires) {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		if wire.from_node == from_node && wire.from_port == from_port && wire.to_node == to_node && wire.to_port == to_port {return wire.id}
	}
	return INVALID_GRAPH_WIRE_ID
}

Graph_Wire_Into :: proc(graph: ^Node_Graph, to_node: Graph_Node_ID, to_port: Graph_Port_ID) -> Graph_Wire_ID {
	for i in 0 ..< len(graph.wires) {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		if wire.to_node == to_node && wire.to_port == to_port {return wire.id}
	}
	return INVALID_GRAPH_WIRE_ID
}

Graph_Wire_Reaches :: proc(graph: ^Node_Graph, start: Graph_Node_ID, target: Graph_Node_ID) -> bool {
	if start == target {return true}
	clear(&graph.cycle_seen)
	clear(&graph.cycle_stack)
	append(&graph.cycle_stack, start)
	for len(graph.cycle_stack) > 0 {
		last := len(graph.cycle_stack) - 1
		current := graph.cycle_stack[last]
		resize(&graph.cycle_stack, last)
		if current == target {return true}
		seen := false
		for value in graph.cycle_seen {
			if value == current {seen = true; break}
		}
		if seen {continue}
		append(&graph.cycle_seen, current)
		for i in 0 ..< len(graph.wires) {
			wire := &graph.wires[i]
			if !wire.alive || wire.from_node != current {continue}
			append(&graph.cycle_stack, wire.to_node)
		}
	}
	return false
}

Graph_Connect_Valid :: proc(graph: ^Node_Graph, from_node_id: Graph_Node_ID, from_port_id: Graph_Port_ID, to_node_id: Graph_Node_ID, to_port_id: Graph_Port_ID) -> bool {
	if from_node_id == to_node_id {return false}
	from := Node_Graph_Port_Of(graph, from_node_id, from_port_id)
	to := Node_Graph_Port_Of(graph, to_node_id, to_port_id)
	if from == nil || to == nil {return false}
	if from.direction == .Input {return false}
	if to.direction == .Output {return false}
	if from.port_kind != to.port_kind {return false}
	if from.port_kind == .Exec && !Graph_Kind_Is_Execution(graph) {return false}
	if Graph_Wire_Find(graph, from_node_id, from_port_id, to_node_id, to_port_id).index != 0 {return false}
	if from.capacity == 0 || to.capacity == 0 {return false}
	if from.port_kind != .Exec && from.capacity > 0 && from.connections >= from.capacity {return false}
	if to.port_kind != .Exec && to.capacity > 1 && to.connections >= to.capacity {return false}
	from_type := Graph_Effective_Port_Type(graph, from_node_id, from_port_id)
	to_type := Graph_Effective_Port_Type(graph, to_node_id, to_port_id)
	if !Graph_Type_Compatible(graph, from_type, to_type) {return false}
	from_node := Node_Graph_Node_Of(graph, from_node_id)
	to_node := Node_Graph_Node_Of(graph, to_node_id)
	if from_node != nil && from_node.kind == .Reroute_Dot {
		if !Graph_Reroute_Wire_Compatible(graph, from_node_id, from_port_id, from_type) {return false}
	}
	if to_node != nil && to_node.kind == .Reroute_Dot {
		if !Graph_Reroute_Wire_Compatible(graph, to_node_id, to_port_id, from_type) {return false}
	}
	if from_node != nil && from_node.kind == .Reroute_Convert {
		if !reroute_type_matches(from_type, to_type) {return false}
	}
	if to_node != nil && to_node.kind == .Reroute_Convert {
		if !reroute_type_matches(from_type, to_type) {return false}
	}
	if !graph.policy.allow_cycles && Graph_Wire_Reaches(graph, to_node_id, from_node_id) {return false}
	if graph.policy.validate != nil {
		if !graph.policy.validate(graph.policy.user_data, graph, from_node_id, from_port_id, to_node_id, to_port_id) {return false}
	}
	return true
}

Graph_Connect :: proc(graph: ^Node_Graph, from_node_id: Graph_Node_ID, from_port_id: Graph_Port_ID, to_node_id: Graph_Node_ID, to_port_id: Graph_Port_ID, colour: Core.Colour) -> Graph_Wire_ID {
	if !Graph_Connect_Valid(graph, from_node_id, from_port_id, to_node_id, to_port_id) {return INVALID_GRAPH_WIRE_ID}
	to := Node_Graph_Port_Of(graph, to_node_id, to_port_id)
	if to.capacity == 1 || to.port_kind == .Exec {
		existing := Graph_Wire_Into(graph, to_node_id, to_port_id)
		if existing.index != 0 {Graph_Wire_Release(graph, int(existing.index) - 1)}
	}
	from := Node_Graph_Port_Of(graph, from_node_id, from_port_id)
	if from.port_kind == .Exec {
		for i := 0; i < len(graph.wires); i += 1 {
			wire := &graph.wires[i]
			if !wire.alive || wire.from_node != from_node_id || wire.from_port != from_port_id {continue}
			Graph_Wire_Release(graph, i)
		}
	}
	wire := Graph_Wire_Slot(graph)
	wire.from_node = from_node_id
	wire.from_port = from_port_id
	wire.to_node = to_node_id
	wire.to_port = to_port_id
	wire.colour = colour
	from.connections += 1
	to.connections += 1
	Graph_Geometry_Invalidate(graph)
	return wire.id
}

Graph_Disconnect :: proc(graph: ^Node_Graph, wire_id: Graph_Wire_ID) {
	if Node_Graph_Wire_Of(graph, wire_id) == nil {return}
	Graph_Wire_Release(graph, int(wire_id.index) - 1)
}

Graph_Clear_Selection :: proc(graph: ^Node_Graph) {
	for i := 0; i < len(graph.nodes); i += 1 {
		if graph.nodes[i].alive {graph.nodes[i].selected = false}
	}
	for i := 0; i < len(graph.wires); i += 1 {
		if graph.wires[i].alive {graph.wires[i].selected = false}
	}
	for i := 0; i < len(graph.regions); i += 1 {
		if graph.regions[i].alive {graph.regions[i].selected = false}
	}
}

Graph_Clipboard_Free :: proc(clipboard: ^Graph_Clipboard) {
	for &node in clipboard.nodes {
		if len(node.title) > 0 {delete(node.title)}
		if len(node.type_name) > 0 {delete(node.type_name)}
		for &port in node.ports {Graph_Port_Desc_Free(&port.desc)}
		delete(node.ports)
		Graph_Config_Free(&node.config)
	}
	delete(clipboard.nodes)
	delete(clipboard.wires)
	clipboard^ = Graph_Clipboard{}
}

Graph_Undo_Record_Free :: proc(record: ^Graph_Undo_Record) {
	if len(record.before) > 0 {delete(record.before)}
	if len(record.after) > 0 {delete(record.after)}
	if len(record.label) > 0 {delete(record.label)}
	record^ = {}
}

Graph_Undo_Free :: proc(graph: ^Node_Graph) {
	for i := 0; i < len(graph.undo_records); i += 1 {Graph_Undo_Record_Free(&graph.undo_records[i])}
	delete(graph.undo_records)
	graph.undo_records = nil
	graph.undo_at = 0
	if len(graph.undo_pending) > 0 {delete(graph.undo_pending)}
	graph.undo_pending = ""
	graph.undo_pending_valid = false
	graph.undo_depth = 0
}

Graph_Metadata_Free :: proc(graph: ^Node_Graph) {
	if graph.metadata == nil {return}
	for key, value in graph.metadata {
		if len(key) > 0 {delete(key)}
		if len(value) > 0 {delete(value)}
	}
	delete(graph.metadata)
	graph.metadata = nil
}

Graph_Metadata_Set :: proc(graph: ^Node_Graph, key, value: string) {
	if graph == nil || key == "" {return}
	if graph.metadata == nil {graph.metadata = make(map[string]string)}
	stored_key: string
	stored_value: string
	for existing_key, existing_value in graph.metadata {
		if existing_key == key {
			stored_key = existing_key
			stored_value = existing_value
			break
		}
	}
	if len(stored_key) > 0 {
		delete_key(&graph.metadata, stored_key)
		delete(stored_key)
		if len(stored_value) > 0 {delete(stored_value)}
	}
	graph.metadata[strings.clone(key)] = strings.clone(value)
}

Graph_Metadata_Get :: proc(graph: ^Node_Graph, key: string) -> (string, bool) {
	if graph == nil || graph.metadata == nil {return "", false}
	value, found := graph.metadata[key]
	return value, found
}

Graph_Free_Entities :: proc(graph: ^Node_Graph) {
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		for j := 0; j < len(node.ports); j += 1 {Graph_Port_Release(graph, node, j)}
		delete(node.ports)
		delete(node.free_ports)
		Graph_Config_Free(&node.config)
		if len(node.title) > 0 {delete(node.title)}
		if len(node.short_title) > 0 {delete(node.short_title)}
		if len(node.type_name) > 0 {delete(node.type_name)}
		if len(node.reroute_input_type) > 0 {delete(node.reroute_input_type)}
		if len(node.reroute_output_type) > 0 {delete(node.reroute_output_type)}
	}
	delete(graph.nodes)
	delete(graph.free_nodes)
	delete(graph.wires)
	delete(graph.free_wires)
	graph.nodes = nil
	graph.free_nodes = nil
	graph.wires = nil
	graph.free_wires = nil
	Graph_Regions_Free(graph)
	Graph_Metadata_Free(graph)
}

Graph_Clear_Contents :: proc(graph: ^Node_Graph) {
	if graph == nil {return}
	Graph_Free_Entities(graph)
	for i := 0; i < len(graph.types); i += 1 {Graph_Node_Type_Clear(&graph.types[i])}
	delete(graph.types)
	graph.types = nil
	if graph.type_by_name != nil {
		for key in graph.type_by_name {delete(key)}
		delete(graph.type_by_name)
		graph.type_by_name = nil
	}
	Graph_Clear_Kinds(graph)
	Graph_Clipboard_Free(&graph.clipboard)
	Graph_Undo_Free(graph)
	for &entry in graph.type_colours {
		if len(entry.name) > 0 {delete(entry.name)}
	}
	delete(graph.type_colours)
	graph.type_colours = nil
}

Graph_Free_Storage :: proc(graph: ^Node_Graph) {
	if graph == nil {return}
	Graph_Clear_Contents(graph)
	delete(graph.dragging_nodes)
	delete(graph.drag_starts)
	delete(graph.region_drag_nodes)
	delete(graph.region_drag_starts)
	delete(graph.cycle_seen)
	delete(graph.cycle_stack)
	delete(graph.node_scratch)
	delete(graph.wire_scratch)
	graph.dragging_nodes = nil
	graph.drag_starts = nil
	graph.region_drag_nodes = nil
	graph.region_drag_starts = nil
	graph.cycle_seen = nil
	graph.cycle_stack = nil
	graph.node_scratch = nil
	graph.wire_scratch = nil
	delete(graph.inspector_actions)
	graph.inspector_actions = nil
	graph_cache_clear(&graph.cache)
}
Graph_Port_Policy_Of :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID) -> Graph_Port_Policy {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return {}}
	index := Graph_Find_Type(graph, node.type_name)
	if index < 0 {return {}}
	return graph.types[index].policy
}

Graph_Can_Add_Port :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, direction: Graph_Port_Direction) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return false}
	policy := Graph_Port_Policy_Of(graph, node_id)
	if direction == .Input && !policy.add_inputs {return false}
	if direction == .Output && !policy.add_outputs {return false}
	count := 0
	for port in node.ports {
		if !port.alive || !port.visible {continue}
		if direction == .Input && port.direction == .Input {count += 1}
		if direction == .Output && port.direction == .Output {count += 1}
	}
	limit := policy.max_inputs
	if direction == .Output {limit = policy.max_outputs}
	if limit >= 0 && i32(count) >= limit {return false}
	return true
}

Graph_Add_Node_Port :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, direction: Graph_Port_Direction) -> Graph_Port_ID {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return INVALID_GRAPH_PORT_ID}
	if !Graph_Can_Add_Port(graph, node_id, direction) {return INVALID_GRAPH_PORT_ID}
	policy := Graph_Port_Policy_Of(graph, node_id)
	port_type := ""
	last_type := ""
	last_kind := Graph_Port_Kind.Data
	count := 0
	for port in node.ports {
		if !port.alive || !port.visible {continue}
		if direction == .Input && port.direction == .Input {
			count += 1
			if port.type != "" {last_type = port.type}
			last_kind = port.port_kind
		}
		if direction == .Output && port.direction == .Output {
			count += 1
			if port.type != "" {last_type = port.type}
			last_kind = port.port_kind
		}
	}
	if direction == .Input && policy.input_type != "" {port_type = policy.input_type}
	if direction == .Output && policy.output_type != "" {port_type = policy.output_type}
	if port_type == "" {port_type = last_type}
	prefix := policy.input_prefix
	if direction == .Output {prefix = policy.output_prefix}
	if prefix == "" {prefix = direction == .Input ? "Input" : "Output"}
	name := fmt.aprintf("%s %d", prefix, count + 1)
	defer delete(name)
	return Graph_Add_Port(node, Graph_Port_Desc{
		name = name,
		direction = direction,
		port_kind = last_kind,
		type = port_type,
		capacity = direction == .Input ? 1 : -1,
		visible = true,
	})
}

//* The number of ports of a direction that the registered type declares.
//* The ports that were added later come after these in the port array.
graph_port_template_count :: proc(
	graph: ^Node_Graph,
	node: ^Graph_Node,
	direction: Graph_Port_Direction,
) -> int {
	index := Graph_Find_Type(graph, node.type_name)
	if index < 0 {return 0}
	count := 0
	node_type := &graph.types[index]
	if direction == .Input {
		for desc in node_type.inputs {
			if desc.direction == .Input {count += 1}
		}
	} else {
		for desc in node_type.outputs {
			if desc.direction == .Output {count += 1}
		}
	}
	return count
}

//* True when a port was added after the ports the type declares, so that
//* it can be taken away again without changing the identity of the node.
Graph_Port_Is_Removable :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return false}
	target_index := -1
	for &port, i in node.ports {
		if port.alive && port.id == port_id {
			target_index = i
			break
		}
	}
	if target_index < 0 {return false}
	direction := node.ports[target_index].direction
	template_count := graph_port_template_count(graph, node, direction)
	live := 0
	for &port, i in node.ports {
		if !port.alive {continue}
		if port.direction != direction {continue}
		live += 1
		if i == target_index {return live > template_count}
	}
	return false
}

//* Takes away one port that was added after the template ports, and the
//* wires that touch it. A template port is refused; use the ports of the
//* type for those.
Graph_Remove_Port :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return false}
	if !Graph_Port_Is_Removable(graph, node_id, port_id) {return false}
	target_index := -1
	for &port, i in node.ports {
		if port.alive && port.id == port_id {
			target_index = i
			break
		}
	}
	if target_index < 0 {return false}
	for i := len(graph.wires) - 1; i >= 0; i -= 1 {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		if (wire.from_node == node_id && wire.from_port == port_id) || (wire.to_node == node_id && wire.to_port == port_id) {
			Graph_Wire_Release(graph, i)
		}
	}
	Graph_Port_Release(graph, node, target_index)
	return true
}

Graph_Remove_Last_Port :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, direction: Graph_Port_Direction) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return false}
	template_count := graph_port_template_count(graph, node, direction)
	live_count := 0
	target_index := -1
	for i in 0 ..< len(node.ports) {
		port := &node.ports[i]
		if !port.alive || !port.visible {continue}
		if direction == .Input && port.direction == .Input {
			live_count += 1
			target_index = i
		}
		if direction == .Output && port.direction == .Output {
			live_count += 1
			target_index = i
		}
	}
	if target_index < 0 || live_count <= template_count {return false}
	port_id := node.ports[target_index].id
	for i := len(graph.wires) - 1; i >= 0; i -= 1 {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		if (wire.from_node == node_id && wire.from_port == port_id) || (wire.to_node == node_id && wire.to_port == port_id) {
			Graph_Wire_Release(graph, i)
		}
	}
	Graph_Port_Release(graph, node, target_index)
	return true
}

REROUTE_DOT_SIZE :: 20
REROUTE_CONVERT_WIDTH :: 42
REROUTE_CONVERT_HEIGHT :: 24
REROUTE_EFFECTIVE_DEPTH_LIMIT :: 64

Graph_Add_Reroute_Dot :: proc(graph: ^Node_Graph, pos: Core.Vec2) -> Graph_Node_ID {
	node := Graph_Node_Slot(graph)
	node.kind = .Reroute_Dot
	node.type_name = ""
	node.title = ""
	node.pos = pos
	node.size = Core.Vec2{REROUTE_DOT_SIZE, REROUTE_DOT_SIZE}
	node.min_size = node.size
	node.max_size = node.size
	node.resizable = false
	node.collapsible = false
	Graph_Add_Port(node, Graph_Port_Desc{
		name = "Reroute",
		direction = .Both,
		port_kind = .Data,
		type = "",
		capacity = -1,
		visible = true,
	})
	return node.id
}

reroute_type_matches :: proc(a, b: string) -> bool {
	if a == "" || b == "" {return true}
	if len(a) != len(b) {return false}
	for i := 0; i < len(a); i += 1 {
		left := a[i]
		right := b[i]
		if left >= 'A' && left <= 'Z' {left += 'a' - 'A'}
		if right >= 'A' && right <= 'Z' {right += 'a' - 'A'}
		if left != right {return false}
	}
	return true
}

reroute_conversion_height :: proc(graph: ^Node_Graph, input_count: int) -> f32 {
	rows := max(input_count, 1)
	spacing := Graph_Metrics_Of(graph).port_spacing
	return max(f32(REROUTE_CONVERT_HEIGHT), f32(rows - 1) * spacing + 16)
}

reroute_set_string :: proc(dst: ^string, value: string) {
	copy := strings.clone(value)
	if len(dst^) > 0 {delete(dst^)}
	dst^ = copy
}

reroute_live_inputs :: proc(node: ^Graph_Node, ids: ^[16]Graph_Port_ID) -> int {
	count := 0
	for &port in node.ports {
		if !port.alive || !port.visible || port.direction != .Input {continue}
		if count < len(ids) {ids[count] = port.id}
		count += 1
	}
	return min(count, len(ids))
}

reroute_live_outputs :: proc(node: ^Graph_Node, ids: ^[16]Graph_Port_ID) -> int {
	count := 0
	for &port in node.ports {
		if !port.alive || !port.visible || port.direction != .Output {continue}
		if count < len(ids) {ids[count] = port.id}
		count += 1
	}
	return min(count, len(ids))
}

Graph_Effective_Port_Type :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, port_id: Graph_Port_ID, depth := 0) -> string {
	node := Node_Graph_Node_Of(graph, node_id)
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if node == nil || port == nil {return ""}
	if node.kind == .Normal {return port.type}
	if node.kind == .Reroute_Convert {
		if len(port.type) > 0 {return port.type}
		return port.direction == .Input ? node.reroute_input_type : node.reroute_output_type
	}
	if node.kind != .Reroute_Dot || depth >= REROUTE_EFFECTIVE_DEPTH_LIMIT {return ""}
	for wire in graph.wires {
		if !wire.alive {continue}
		if wire.to_node != node.id || wire.to_port != port.id {continue}
		source_type := Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port, depth + 1)
		if source_type != "" {return source_type}
	}
	return ""
}

Graph_Reroute_Wire_Compatible :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, port_id: Graph_Port_ID, type_name: string) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if node == nil || port == nil {return false}
	for wire in graph.wires {
		if !wire.alive {continue}
		if wire.to_node == node.id && wire.to_port == port.id {
			source_type := Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port)
			if !Graph_Type_Compatible(graph, source_type, type_name) {return false}
		}
		if wire.from_node == node.id && wire.from_port == port.id {
			target_type := Graph_Effective_Port_Type(graph, wire.to_node, wire.to_port)
			if !Graph_Type_Compatible(graph, type_name, target_type) {return false}
		}
	}
	return true
}

Graph_Validate_Reroute_Conversion :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, input_type, output_type: string) -> bool {
	inputs := [1]string{input_type}
	return Graph_Validate_Reroute_Conversion_Types(graph, node_id, inputs[:], output_type)
}

Graph_Validate_Reroute_Conversion_Types :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	input_types: []string,
	output_type: string,
) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil || len(input_types) == 0 || output_type == "" {return false}
	for type_name in input_types {
		if type_name == "" {return false}
	}
	incoming := 0
	for wire in graph.wires {
		if !wire.alive {continue}
		if wire.to_node == node.id {
			incoming += 1
			source_type := Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port)
			matched := false
			for type_name in input_types {
				if reroute_type_matches(source_type, type_name) {matched = true; break}
			}
			if !matched {return false}
		}
		if wire.from_node == node.id {
			target_type := Graph_Effective_Port_Type(graph, wire.to_node, wire.to_port)
			if !reroute_type_matches(output_type, target_type) {return false}
		}
	}
	return incoming <= len(input_types)
}

Graph_Set_Reroute_Conversion_Types :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	input_types: []string,
	output_type: string,
) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil || node.kind == .Normal {return false}
	if !Graph_Validate_Reroute_Conversion_Types(graph, node_id, input_types, output_type) {return false}
	switch node.kind {
	case .Reroute_Dot:
		return reroute_convert_from_dot(graph, node, input_types, output_type)
	case .Reroute_Convert:
		return reroute_update_conversion(graph, node, input_types, output_type)
	case .Normal:
	}
	return false
}

Graph_Set_Reroute_Conversion :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, input_type, output_type: string) -> bool {
	inputs := [1]string{input_type}
	return Graph_Set_Reroute_Conversion_Types(graph, node_id, inputs[:], output_type)
}

reroute_convert_from_dot :: proc(
	graph: ^Node_Graph,
	node: ^Graph_Node,
	input_types: []string,
	output_type: string,
) -> bool {
	dot_port := INVALID_GRAPH_PORT_ID
	for &port in node.ports {
		if port.alive && port.direction == .Both {
			dot_port = port.id
			break
		}
	}
	if dot_port.index == 0 {return false}

	incoming: [16]int
	incoming_count := 0
	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive || wire.to_node != node.id || wire.to_port != dot_port {continue}
		if incoming_count < len(incoming) {incoming[incoming_count] = i}
		incoming_count += 1
	}
	if incoming_count > len(input_types) {return false}

	outgoing := 0
	for wire in graph.wires {
		if wire.alive && wire.from_node == node.id && wire.from_port == dot_port {outgoing += 1}
	}

	inputs: [16]Graph_Port_ID
	inputs[0] = dot_port
	for i in 1 ..< len(input_types) {
		buf: [16]u8
		name := fmt.bprintf(buf[:], "In %d", i + 1)
		inputs[i] = Graph_Add_Port(node, Graph_Port_Desc{
			name = name,
			direction = .Input,
			port_kind = .Data,
			type = input_types[i],
			capacity = 1,
			visible = true,
		})
		if inputs[i].index == 0 {return false}
	}

	output := Graph_Add_Port(node, Graph_Port_Desc{
		name = "Out",
		direction = .Output,
		port_kind = .Data,
		type = output_type,
		capacity = -1,
		visible = true,
	})
	if output.index == 0 {return false}

	if input := Node_Graph_Port_Of(graph, node.id, dot_port); input != nil {
		reroute_set_string(&input.name, "In 1")
		reroute_set_string(&input.type, input_types[0])
		input.direction = .Input
		input.capacity = 1
		input.connections = 0
	}
	for i in 0 ..< incoming_count {
		wire := &graph.wires[incoming[i]]
		if i < len(inputs) {
			wire.to_port = inputs[i]
			if port := Node_Graph_Port_Of(graph, node.id, inputs[i]); port != nil {
				port.connections += 1
			}
		}
	}
	for &wire in graph.wires {
		if !wire.alive || wire.from_node != node.id || wire.from_port != dot_port {continue}
		wire.from_port = output
	}
	if port := Node_Graph_Port_Of(graph, node.id, output); port != nil {
		port.connections = i32(outgoing)
	}

	reroute_set_string(&node.reroute_input_type, input_types[0])
	reroute_set_string(&node.reroute_output_type, output_type)
	node.kind = .Reroute_Convert
	node.size = Core.Vec2{REROUTE_CONVERT_WIDTH, reroute_conversion_height(graph, len(input_types))}
	node.min_size = node.size
	node.max_size = node.size
	return true
}

reroute_update_conversion :: proc(
	graph: ^Node_Graph,
	node: ^Graph_Node,
	input_types: []string,
	output_type: string,
) -> bool {
	inputs: [16]Graph_Port_ID
	input_count := reroute_live_inputs(node, &inputs)
	total_inputs := input_count
	outputs: [16]Graph_Port_ID
	output_count := reroute_live_outputs(node, &outputs)
	if input_count == 0 {return false}

	for i in input_count ..< len(input_types) {
		buf: [16]u8
		name := fmt.bprintf(buf[:], "In %d", i + 1)
		inputs[i] = Graph_Add_Port(node, Graph_Port_Desc{
			name = name,
			direction = .Input,
			port_kind = .Data,
			type = input_types[i],
			capacity = 1,
			visible = true,
		})
		if inputs[i].index == 0 {return false}
	}
	if len(input_types) > input_count {input_count = len(input_types)}

	output := INVALID_GRAPH_PORT_ID
	if output_count > 0 {
		output = outputs[0]
	} else {
		output = Graph_Add_Port(node, Graph_Port_Desc{
			name = "Out",
			direction = .Output,
			port_kind = .Data,
			type = output_type,
			capacity = -1,
			visible = true,
		})
		if output.index == 0 {return false}
	}
	for i in 1 ..< output_count {
		for &wire in graph.wires {
			if wire.alive && wire.from_node == node.id && wire.from_port == outputs[i] {
				wire.from_port = output
			}
		}
		for &port in node.ports {
			if port.alive && port.id == outputs[i] {port.connections = 0}
		}
	}
	for &port in node.ports {
		if !port.alive {continue}
		for i in 0 ..< input_count {
			if port.id == inputs[i] {
				buf: [16]u8
				reroute_set_string(&port.name, fmt.bprintf(buf[:], "In %d", i + 1))
			}
		}
		if port.id == output {
			reroute_set_string(&port.name, "Out")
			reroute_set_string(&port.type, output_type)
			port.direction = .Output
			port.capacity = -1
		}
	}

	incoming: [64]int
	incoming_count := 0
	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive || wire.to_node != node.id {continue}
		if incoming_count < len(incoming) {incoming[incoming_count] = i}
		incoming_count += 1
	}
	if incoming_count > len(input_types) {return false}
	for &port in node.ports {
		if !port.alive || port.direction == .Output {continue}
		port.connections = 0
	}
	for i := 0; i < incoming_count; i += 1 {
		wire := &graph.wires[incoming[i]]
		wire.to_port = inputs[i]
		if port := Node_Graph_Port_Of(graph, node.id, inputs[i]); port != nil {
			port.connections = 1
		}
	}

	for &port in node.ports {
		if !port.alive || port.direction == .Output {continue}
		for i in 0 ..< len(input_types) {
			if port.id != inputs[i] {continue}
			reroute_set_string(&port.type, input_types[i])
			port.capacity = 1
			break
		}
	}

	if port := Node_Graph_Port_Of(graph, node.id, output); port != nil {
		count: i32 = 0
		for wire in graph.wires {
			if wire.alive && wire.from_node == node.id && wire.from_port == output {count += 1}
		}
		port.connections = count
	}

	remove_inputs: [16]int
	remove_input_count := 0
	for i := len(input_types); i < total_inputs; i += 1 {
		for &wire in graph.wires {
			if wire.alive && wire.to_node == node.id && wire.to_port == inputs[i] {
				wire.to_port = inputs[0]
			}
		}
		remove_inputs[remove_input_count] = int(inputs[i].index) - 1
		remove_input_count += 1
	}
	remove_outputs: [16]int
	remove_output_count := 0
	for i := 1; i < output_count; i += 1 {
		remove_outputs[remove_output_count] = int(outputs[i].index) - 1
		remove_output_count += 1
	}
	for i := 0; i < remove_input_count; i += 1 {
		Graph_Port_Release(graph, node, remove_inputs[i])
	}
	for i := 0; i < remove_output_count; i += 1 {
		Graph_Port_Release(graph, node, remove_outputs[i])
	}

	reroute_set_string(&node.reroute_input_type, input_types[0])
	reroute_set_string(&node.reroute_output_type, output_type)
	node.kind = .Reroute_Convert
	node.size = Core.Vec2{REROUTE_CONVERT_WIDTH, reroute_conversion_height(graph, len(input_types))}
	node.min_size = node.size
	node.max_size = node.size
	return true
}

Graph_Clear_Reroute_Conversion :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID) -> bool {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil || node.kind != .Reroute_Convert {return false}
	inputs: [16]Graph_Port_ID
	input_count := reroute_live_inputs(node, &inputs)
	outputs: [16]Graph_Port_ID
	output_count := reroute_live_outputs(node, &outputs)
	if input_count == 0 {return false}

	common_type := ""
	have_type := false
	for wire in graph.wires {
		if !wire.alive || (wire.from_node != node.id && wire.to_node != node.id) {continue}
		var_type := ""
		if wire.from_node == node.id {
			var_type = Graph_Effective_Port_Type(graph, wire.to_node, wire.to_port)
		} else {
			var_type = Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port)
		}
		if !have_type {
			common_type = var_type
			have_type = true
			continue
		}
		if !reroute_type_matches(common_type, var_type) {return false}
	}

	keep := inputs[0]
	released_inputs: [16]int
	released_input_count := 0
	for i := 1; i < input_count; i += 1 {
		released_inputs[released_input_count] = int(inputs[i].index) - 1
		released_input_count += 1
	}
	released_outputs: [16]int
	released_output_count := 0
	for i := 0; i < output_count; i += 1 {
		released_outputs[released_output_count] = int(outputs[i].index) - 1
		released_output_count += 1
	}

	connections: i32 = 0
	for &wire in graph.wires {
		if !wire.alive {continue}
		if wire.to_node == node.id {wire.to_port = keep}
		if wire.from_node == node.id {wire.from_port = keep}
		if wire.from_node == node.id || wire.to_node == node.id {connections += 1}
	}

	for i := 0; i < released_input_count; i += 1 {
		Graph_Port_Release(graph, node, released_inputs[i])
	}
	for i := 0; i < released_output_count; i += 1 {
		Graph_Port_Release(graph, node, released_outputs[i])
	}

	if port := Node_Graph_Port_Of(graph, node.id, keep); port != nil {
		owned_type := strings.clone(common_type)
		if len(port.type) > 0 {delete(port.type)}
		port.type = owned_type
		port.direction = .Both
		port.capacity = -1
		port.connections = connections
	}
	if len(node.reroute_input_type) > 0 {delete(node.reroute_input_type)}
	if len(node.reroute_output_type) > 0 {delete(node.reroute_output_type)}
	node.reroute_input_type = ""
	node.reroute_output_type = ""
	node.kind = .Reroute_Dot
	node.size = Core.Vec2{REROUTE_DOT_SIZE, REROUTE_DOT_SIZE}
	node.min_size = node.size
	node.max_size = node.size
	return true
}

Graph_Insert_Reroute_On_Wire :: proc(graph: ^Node_Graph, wire_id: Graph_Wire_ID, position: Core.Vec2) -> Graph_Node_ID {
	wire := Node_Graph_Wire_Of(graph, wire_id)
	if wire == nil {return INVALID_GRAPH_NODE_ID}
	from_node := wire.from_node
	from_port := wire.from_port
	to_node := wire.to_node
	to_port := wire.to_port
	source_type := Graph_Effective_Port_Type(graph, from_node, from_port)
	target_type := Graph_Effective_Port_Type(graph, to_node, to_port)
	if !Graph_Type_Compatible(graph, source_type, target_type) {return INVALID_GRAPH_NODE_ID}
	node_id := Graph_Add_Reroute_Dot(graph, position)
	if node_id.index == 0 {return INVALID_GRAPH_NODE_ID}
	node := Node_Graph_Node_Of(graph, node_id)
	dot_port := node.ports[0].id
	wire.to_node = node_id
	wire.to_port = dot_port
	if target := Node_Graph_Port_Of(graph, to_node, to_port); target != nil && target.connections > 0 {target.connections -= 1}
	if dot := Node_Graph_Port_Of(graph, node_id, dot_port); dot != nil {dot.connections += 1}
	new_wire := Graph_Connect(graph, node_id, dot_port, to_node, to_port, wire.colour)
	if new_wire.index == 0 {
		wire.to_node = to_node
		wire.to_port = to_port
		if dot := Node_Graph_Port_Of(graph, node_id, dot_port); dot != nil && dot.connections > 0 {dot.connections -= 1}
		if target := Node_Graph_Port_Of(graph, to_node, to_port); target != nil {target.connections += 1}
		Graph_Node_Release(graph, int(node_id.index) - 1)
		return INVALID_GRAPH_NODE_ID
	}
	return node_id
}
