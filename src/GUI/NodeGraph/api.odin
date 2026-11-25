package NodeGraph

import Core "../Core"
import "core:fmt"
import "core:os"
import "core:strings"

//* The pointer tolerances that the queries of the widget use. They are in
//* graph units, so the hit area stays the same at every zoom.
GRAPH_WIRE_HIT_TOLERANCE :: 7
GRAPH_PORT_HIT_TOLERANCE :: 11

node_graph_data :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> ^Core.Node_Graph_Data {
	w := Core.Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Core.Node_Graph_Data:
		return &d
	}
	return nil
}

node_graph_of :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> ^Node_Graph {
	d := node_graph_data(g, id)
	if d == nil {return nil}
	return cast(^Node_Graph)d.graph
}

node_graph_model :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> ^Node_Graph {
	return node_graph_of(g, id)
}


node_graph_node_of :: proc(graph: ^Node_Graph, id: Graph_Node_ID) -> ^Graph_Node {
	return Node_Graph_Node_Of(graph, id)
}

node_graph_port_of :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> ^Graph_Port {
	return Node_Graph_Port_Of(graph, node_id, port_id)
}

node_graph_wire_of :: proc(graph: ^Node_Graph, id: Graph_Wire_ID) -> ^Graph_Wire {
	return Node_Graph_Wire_Of(graph, id)
}

graph_node_slot :: proc(graph: ^Node_Graph) -> ^Graph_Node {
	return Graph_Node_Slot(graph)
}

graph_port_slot :: proc(node: ^Graph_Node) -> ^Graph_Port {
	return Graph_Port_Slot(node)
}

graph_wire_slot :: proc(graph: ^Node_Graph) -> ^Graph_Wire {
	return Graph_Wire_Slot(graph)
}

graph_value_clone :: proc(value: Graph_Value) -> Graph_Value {
	return Graph_Value_Clone(value)
}

graph_value_free :: proc(value: Graph_Value) {
	Graph_Value_Free(value)
}

graph_value_kind :: proc(value: Graph_Value) -> Graph_Value_Kind {
	return Graph_Value_Kind_Of(value)
}

graph_config_entry_free :: proc(entry: ^Graph_Config_Entry) {
	Graph_Config_Entry_Free(entry)
}

graph_config_free :: proc(entries: ^[dynamic]Graph_Config_Entry) {
	Graph_Config_Free(entries)
}

graph_port_desc_clone :: proc(desc: Graph_Port_Desc) -> Graph_Port_Desc {
	return Graph_Port_Desc_Clone(desc)
}

graph_port_desc_free :: proc(desc: ^Graph_Port_Desc) {
	Graph_Port_Desc_Free(desc)
}

graph_port_desc_list_clone :: proc(descs: []Graph_Port_Desc) -> [dynamic]Graph_Port_Desc {
	return Graph_Port_Desc_List_Clone(descs)
}

graph_port_desc_list_free :: proc(descs: ^[dynamic]Graph_Port_Desc) {
	Graph_Port_Desc_List_Free(descs)
}

graph_config_clone :: proc(entries: []Graph_Config_Entry) -> [dynamic]Graph_Config_Entry {
	return Graph_Config_Clone(entries)
}

graph_find_type :: proc(graph: ^Node_Graph, name: string) -> int {
	return Graph_Find_Type(graph, name)
}

graph_node_type_clear :: proc(node_type: ^Graph_Node_Type) {
	Graph_Node_Type_Clear(node_type)
}

graph_node_type_apply :: proc(node_type: ^Graph_Node_Type, desc: Graph_Node_Type_Desc) {
	Graph_Node_Type_Apply(node_type, desc)
}

node_graph_register_type :: proc(g: ^Core.GUI, id: Core.Widget_ID, desc: Graph_Node_Type_Desc) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return -1}
	index := Graph_Register_Type(graph, desc)
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
	return index
}

node_graph_register_kind :: proc(g: ^Core.GUI, id: Core.Widget_ID, desc: Graph_Kind_Desc) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return -1}
	index := Graph_Register_Kind(graph, desc)
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
	return index
}

node_graph_set_kind :: proc(g: ^Core.GUI, id: Core.Widget_ID, name: string) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	if graph.kind_name == name {return true}
	node_graph_undo_begin(g, id)
	ok := Graph_Set_Kind(graph, name)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "set kind")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_kind_name :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> string {
	graph := node_graph_of(g, id)
	if graph == nil {return ""}
	return Graph_Kind_Name(graph)
}

node_graph_kind_allows :: proc(g: ^Core.GUI, id: Core.Widget_ID, type_name: string) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	return Graph_Kind_Allows_Type(graph, type_name)
}

node_graph_rebuild_ports :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID) {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if graph == nil || node == nil {return}
	index := graph_find_type(graph, node.type_name)
	if index < 0 {return}
	configure := graph.types[index].configure
	if configure == nil {return}
	node_graph_undo_begin(g, id)
	configure(g, id, node_id)
	node_graph_undo_commit(g, id, "ports")
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

graph_add_node_internal :: proc(graph: ^Node_Graph, title: string, pos: Core.Vec2) -> Graph_Node_ID {
	return Graph_Add_Node(graph, title, pos)
}

graph_add_typed_node_internal :: proc(graph: ^Node_Graph, type_name: string, pos: Core.Vec2) -> Graph_Node_ID {
	return Graph_Add_Typed_Node(graph, type_name, pos)
}

node_graph_add_node :: proc(g: ^Core.GUI, id: Core.Widget_ID, title: string, pos: Core.Vec2) -> Graph_Node_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_NODE_ID}
	node_graph_undo_begin(g, id)
	node_id := graph_add_node_internal(graph, title, pos)
	node_graph_undo_commit(g, id, "add node")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return node_id
}

node_graph_add_typed_node :: proc(g: ^Core.GUI, id: Core.Widget_ID, type_name: string, pos: Core.Vec2) -> Graph_Node_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_NODE_ID}
	if !Graph_Kind_Allows_Type(graph, type_name) {return INVALID_GRAPH_NODE_ID}
	node_graph_undo_begin(g, id)
	node_id := graph_add_typed_node_internal(graph, type_name, pos)
	if configure := graph_configure_of(graph, node_id); configure != nil {
		configure(g, id, node_id)
	}
	node_graph_undo_commit(g, id, "add node")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return node_id
}

graph_configure_of :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID) -> proc(g: ^Core.GUI, graph: Core.Widget_ID, node: Graph_Node_ID) {
	return Graph_Configure_Of(graph, node_id)
}

graph_port_release :: proc(graph: ^Node_Graph, node: ^Graph_Node, index: int) {
	Graph_Port_Release(graph, node, index)
}

graph_wire_release :: proc(graph: ^Node_Graph, index: int) {
	Graph_Wire_Release(graph, index)
}

graph_node_release :: proc(graph: ^Node_Graph, node_index: int) {
	Graph_Node_Release(graph, node_index)
}

node_graph_remove_node :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID) {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil {return}
	node_graph_undo_begin(g, id)
	graph_node_release(graph, int(node_id.index) - 1)
	node_graph_undo_commit(g, id, "remove node")
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

graph_port_direction_side :: proc(port: ^Graph_Port) -> Graph_Port_Direction {
	return Graph_Port_Direction_Side(port)
}

graph_add_port_internal :: proc(node: ^Graph_Node, desc: Graph_Port_Desc) -> Graph_Port_ID {
	return Graph_Add_Port(node, desc)
}

node_graph_add_port :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, name: string, direction: Graph_Port_Direction) -> Graph_Port_ID {
	graph := node_graph_of(g, id)
	if node_graph_node_of(graph, node_id) == nil {return INVALID_GRAPH_PORT_ID}
	node_graph_undo_begin(g, id)
	node := node_graph_node_of(graph, node_id)
	port_id := graph_add_port_internal(node, Graph_Port_Desc{
		name = name,
		direction = direction,
		capacity = direction == .Input ? 1 : -1,
		visible = true,
	})
	node_graph_undo_commit(g, id, "add port")
	Graph_Geometry_Invalidate(graph)
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return port_id
}

node_graph_add_typed_port :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, desc: Graph_Port_Desc) -> Graph_Port_ID {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil {return INVALID_GRAPH_PORT_ID}
	node_graph_undo_begin(g, id)
	port_id := graph_add_port_internal(node, desc)
	node_graph_undo_commit(g, id, "add port")
	Graph_Geometry_Invalidate(graph)
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return port_id
}

node_graph_remove_port :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) -> bool {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	port := node_graph_port_of(graph, node_id, port_id)
	if node == nil || port == nil {return false}
	if !Graph_Port_Is_Removable(graph, node_id, port_id) {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Remove_Port(graph, node_id, port_id)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "remove port")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_set_ports :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, descs: []Graph_Port_Desc) {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil {return}
	node_graph_undo_begin(g, id)
	Graph_Set_Ports(graph, node_id, descs)
	node_graph_undo_commit(g, id, "ports")
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

node_graph_set_config_value :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, key: string, value: Graph_Value) {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil || key == "" {return}
	node_graph_undo_begin(g, id)
	Graph_Set_Config_Value(graph, node_id, key, value)
	node_graph_undo_commit(g, id, "config")
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_get_config_value :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, key: string) -> (Graph_Value, bool) {
	graph := node_graph_of(g, id)
	return Graph_Get_Config_Value(graph, node_id, key)
}

graph_type_compatible :: proc(graph: ^Node_Graph, from_type, to_type: string) -> bool {
	return Graph_Type_Compatible(graph, from_type, to_type)
}

graph_wire_find :: proc(graph: ^Node_Graph, from_node: Graph_Node_ID, from_port: Graph_Port_ID, to_node: Graph_Node_ID, to_port: Graph_Port_ID) -> Graph_Wire_ID {
	return Graph_Wire_Find(graph, from_node, from_port, to_node, to_port)
}

graph_wire_into :: proc(graph: ^Node_Graph, to_node: Graph_Node_ID, to_port: Graph_Port_ID) -> Graph_Wire_ID {
	return Graph_Wire_Into(graph, to_node, to_port)
}

graph_wire_reaches :: proc(graph: ^Node_Graph, start: Graph_Node_ID, target: Graph_Node_ID) -> bool {
	return Graph_Wire_Reaches(graph, start, target)
}

graph_connect_valid :: proc(graph: ^Node_Graph, from_node_id: Graph_Node_ID, from_port_id: Graph_Port_ID, to_node_id: Graph_Node_ID, to_port_id: Graph_Port_ID) -> bool {
	return Graph_Connect_Valid(graph, from_node_id, from_port_id, to_node_id, to_port_id)
}

graph_connect_internal :: proc(graph: ^Node_Graph, from_node_id: Graph_Node_ID, from_port_id: Graph_Port_ID, to_node_id: Graph_Node_ID, to_port_id: Graph_Port_ID, colour: Core.Colour) -> Graph_Wire_ID {
	return Graph_Connect(graph, from_node_id, from_port_id, to_node_id, to_port_id, colour)
}

node_graph_connect :: proc(g: ^Core.GUI, id: Core.Widget_ID, from_node: Graph_Node_ID, from_port: Graph_Port_ID, to_node: Graph_Node_ID, to_port: Graph_Port_ID) -> Graph_Wire_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_WIRE_ID}
	node_graph_undo_begin(g, id)
	wire := graph_connect_internal(graph, from_node, from_port, to_node, to_port, {})
	node_graph_undo_commit(g, id, "connect")
	if wire.index != 0 {Core.invalidate(g, id, Core.DIRTY_ALL)}
	return wire
}

node_graph_disconnect :: proc(g: ^Core.GUI, id: Core.Widget_ID, wire_id: Graph_Wire_ID) {
	graph := node_graph_of(g, id)
	if node_graph_wire_of(graph, wire_id) == nil {return}
	node_graph_undo_begin(g, id)
	graph_wire_release(graph, int(wire_id.index) - 1)
	node_graph_undo_commit(g, id, "disconnect")
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

node_graph_set_connection_policy :: proc(g: ^Core.GUI, id: Core.Widget_ID, policy: Graph_Connection_Policy) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph.policy = policy
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_node_count :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return 0}
	count := 0
	for node in graph.nodes {
		if node.alive {count += 1}
	}
	return count
}

node_graph_wire_count :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return 0}
	count := 0
	for wire in graph.wires {
		if wire.alive {count += 1}
	}
	return count
}

graph_node_height :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> f32 {
	return Graph_Node_Height(graph, node)
}

graph_node_rect :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Core.Rect {
	return Graph_Node_Rect(graph, node)
}

graph_port_position :: proc(graph: ^Node_Graph, node: ^Graph_Node, port_id: Graph_Port_ID) -> Core.Vec2 {
	return Graph_Port_Position(graph, node, port_id)
}

graph_node_at_position :: proc(graph: ^Node_Graph, pos: Core.Vec2) -> Graph_Node_ID {
	return Graph_Node_At_Position(graph, pos)
}

graph_port_at_position :: proc(graph: ^Node_Graph, pos: Core.Vec2, tolerance: f32) -> (Graph_Node_ID, Graph_Port_ID) {
	return Graph_Port_At_Position(graph, pos, tolerance)
}

graph_point_segment_distance :: proc(p, a, b: Core.Vec2) -> f32 {
	return Graph_Point_Segment_Distance(p, a, b)
}

graph_wire_segments :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> [3][2]Core.Vec2 {
	return Graph_Wire_Segments(graph, wire)
}

graph_wire_at_position :: proc(graph: ^Node_Graph, pos: Core.Vec2, tolerance: f32) -> Graph_Wire_ID {
	return Graph_Wire_At_Position(graph, pos, tolerance)
}

graph_zoom_of :: proc(graph: ^Node_Graph) -> f32 {
	return Graph_Zoom_Of(graph)
}

graph_pan_of :: proc(graph: ^Node_Graph) -> Core.Vec2 {
	return Graph_Pan_Of(graph)
}

graph_view_sync :: proc(graph: ^Node_Graph) {
	Graph_View_Sync(graph)
}

node_graph_screen_pos :: proc(graph: ^Node_Graph, content: Core.Rect, pos: Core.Vec2) -> Core.Vec2 {
	return Node_Graph_Screen_Pos(graph, content, pos)
}

node_graph_graph_pos :: proc(graph: ^Node_Graph, content: Core.Rect, pos: Core.Vec2) -> Core.Vec2 {
	return Node_Graph_Graph_Pos(graph, content, pos)
}

node_graph_node_rect :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID) -> Core.Rect {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil {return {}}
	return graph_node_rect(graph, node)
}

node_graph_port_pos :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> Core.Vec2 {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil {return {}}
	return graph_port_position(graph, node, port_id)
}

node_graph_node_at :: proc(g: ^Core.GUI, id: Core.Widget_ID, pos: Core.Vec2) -> Graph_Node_ID {
	graph := node_graph_of(g, id)
	w := Core.Widget_Get(g, id)
	if graph == nil || w == nil {return INVALID_GRAPH_NODE_ID}
	p := node_graph_graph_pos(graph, Core.content_rect(g, w), pos)
	return graph_node_at_position(graph, p)
}

node_graph_wire_at :: proc(g: ^Core.GUI, id: Core.Widget_ID, pos: Core.Vec2) -> Graph_Wire_ID {
	graph := node_graph_of(g, id)
	w := Core.Widget_Get(g, id)
	if graph == nil || w == nil {return INVALID_GRAPH_WIRE_ID}
	p := node_graph_graph_pos(graph, Core.content_rect(g, w), pos)
	return graph_wire_at_position(graph, p, GRAPH_WIRE_HIT_TOLERANCE / graph_zoom_of(graph))
}

node_graph_port_at :: proc(g: ^Core.GUI, id: Core.Widget_ID, pos: Core.Vec2) -> (Graph_Node_ID, Graph_Port_ID) {
	graph := node_graph_of(g, id)
	w := Core.Widget_Get(g, id)
	if graph == nil || w == nil {return INVALID_GRAPH_NODE_ID, INVALID_GRAPH_PORT_ID}
	p := node_graph_graph_pos(graph, Core.content_rect(g, w), pos)
	return graph_port_at_position(graph, p, GRAPH_PORT_HIT_TOLERANCE / graph_zoom_of(graph))
}

graph_defaults :: proc(graph: ^Node_Graph) {
	Graph_Defaults(graph)
}

graph_free_entities :: proc(graph: ^Node_Graph) {
	Graph_Free_Entities(graph)
}

graph_clear_contents :: proc(graph: ^Node_Graph) {
	Graph_Clear_Contents(graph)
}

graph_metadata_free :: proc(graph: ^Node_Graph) {
	Graph_Metadata_Free(graph)
}

graph_node_local_id :: proc(node: ^Graph_Node) -> u32 {
	return Graph_Node_Local_ID(node)
}

graph_port_local_id :: proc(port: ^Graph_Port) -> u32 {
	return Graph_Port_Local_ID(port)
}

node_graph_set_metadata :: proc(g: ^Core.GUI, id: Core.Widget_ID, key, value: string) {
	graph := node_graph_of(g, id)
	if graph == nil || key == "" {return}
	node_graph_undo_begin(g, id)
	graph_metadata_set(graph, key, value)
	node_graph_undo_commit(g, id, "metadata")
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

graph_metadata_set :: proc(graph: ^Node_Graph, key, value: string) {
	Graph_Metadata_Set(graph, key, value)
}

node_graph_get_metadata :: proc(g: ^Core.GUI, id: Core.Widget_ID, key: string) -> (string, bool) {
	graph := node_graph_of(g, id)
	return Graph_Metadata_Get(graph, key)
}

node_graph_reconnect :: proc(g: ^Core.GUI, id: Core.Widget_ID, wire_id: Graph_Wire_ID, to_node: Graph_Node_ID, to_port: Graph_Port_ID) -> Graph_Wire_ID {
	graph := node_graph_of(g, id)
	wire := node_graph_wire_of(graph, wire_id)
	if wire == nil {return INVALID_GRAPH_WIRE_ID}
	if wire.to_node == to_node && wire.to_port == to_port {return wire_id}
	source_node := wire.from_node
	source_port := wire.from_port
	old_target_node := wire.to_node
	old_target_port := wire.to_port
	colour := wire.colour
	index := int(wire_id.index) - 1
	node_graph_undo_begin(g, id)
	graph_wire_release(graph, index)
	new_wire := graph_connect_internal(graph, source_node, source_port, to_node, to_port, colour)
	if new_wire.index == 0 {
		graph_connect_internal(graph, source_node, source_port, old_target_node, old_target_port, colour)
		node_graph_undo_cancel(g, id)
		return INVALID_GRAPH_WIRE_ID
	}
	node_graph_undo_commit(g, id, "reconnect")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return new_wire
}

node_graph_insert_reroute_on_wire :: proc(g: ^Core.GUI, id: Core.Widget_ID, wire_id: Graph_Wire_ID, position: Core.Vec2) -> Graph_Node_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_NODE_ID}
	node_graph_undo_begin(g, id)
	node_id := Graph_Insert_Reroute_On_Wire(graph, wire_id, position)
	if node_id.index == 0 {
		node_graph_undo_cancel(g, id)
		return INVALID_GRAPH_NODE_ID
	}
	node_graph_undo_commit(g, id, "insert reroute")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return node_id
}

node_graph_set_reroute_conversion :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, input_type, output_type: string) -> bool {
	inputs := [1]string{input_type}
	return node_graph_set_reroute_conversion_types(g, id, node_id, inputs[:], output_type)
}

node_graph_set_reroute_conversion_types :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	node_id: Graph_Node_ID,
	input_types: []string,
	output_type: string,
) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Set_Reroute_Conversion_Types(graph, node_id, input_types, output_type)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "convert reroute")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_set_port_properties :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
	name, type_name: string,
) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Set_Port_Properties(graph, node_id, port_id, name, type_name)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "port properties")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_clear_reroute_conversion :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Clear_Reroute_Conversion(graph, node_id)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "clear conversion")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_can_add_port :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, direction: Graph_Port_Direction) -> bool {
	graph := node_graph_of(g, id)
	return Graph_Can_Add_Port(graph, node_id, direction)
}

node_graph_add_node_port :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, direction: Graph_Port_Direction) -> Graph_Port_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_PORT_ID}
	node_graph_undo_begin(g, id)
	port_id := Graph_Add_Node_Port(graph, node_id, direction)
	if port_id.index == 0 {
		node_graph_undo_cancel(g, id)
		return INVALID_GRAPH_PORT_ID
	}
	node_graph_undo_commit(g, id, "add port")
	Graph_Geometry_Invalidate(graph)
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return port_id
}

node_graph_remove_last_port :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, direction: Graph_Port_Direction) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Remove_Last_Port(graph, node_id, direction)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "remove port")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_can_remove_port :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) -> bool {
	graph := node_graph_of(g, id)
	return Graph_Port_Is_Removable(graph, node_id, port_id)
}

node_graph_set_type_colour :: proc(g: ^Core.GUI, id: Core.Widget_ID, type_name: string, colour: Core.Colour) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	ok := Graph_Set_Type_Colour(graph, type_name, colour)
	if ok {Core.invalidate(g, id, Core.Dirty_Flags{.Visual})}
	return ok
}

node_graph_type_colour :: proc(g: ^Core.GUI, id: Core.Widget_ID, type_name: string) -> Core.Colour {
	graph := node_graph_of(g, id)
	return Graph_Type_Colour_Of(graph, type_name)
}

node_graph_set_derived_value :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, key: string, value: Graph_Value) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	ok := Graph_Set_Derived_Value(graph, node_id, key, value)
	if ok {Core.invalidate(g, id, Core.Dirty_Flags{.Visual})}
	return ok
}

node_graph_revision :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> u64 {
	graph := node_graph_of(g, id)
	if graph == nil {return 0}
	return graph.revision
}

node_graph_set_callbacks :: proc(g: ^Core.GUI, id: Core.Widget_ID, callbacks: Graph_Callbacks) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph.callbacks = callbacks
}

node_graph_effective_port_type :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> string {
	graph := node_graph_of(g, id)
	return Graph_Effective_Port_Type(graph, node_id, port_id)
}

node_graph_port_colour :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> Core.Colour {
	graph := node_graph_of(g, id)
	return Graph_Port_Colour(graph, node_id, port_id)
}

node_graph_set_node_title :: proc(g: ^Core.GUI, id: Core.Widget_ID, node_id: Graph_Node_ID, title: string) -> bool {
	graph := node_graph_of(g, id)
	node := node_graph_node_of(graph, node_id)
	if node == nil {return false}
	node_graph_undo_begin(g, id)
	node.title = strings.clone(title)
	node_graph_undo_commit(g, id, "title")
	Graph_Geometry_Invalidate(graph)
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_wire_colour :: proc(g: ^Core.GUI, id: Core.Widget_ID, wire_id: Graph_Wire_ID) -> Core.Colour {
	graph := node_graph_of(g, id)
	wire := node_graph_wire_of(graph, wire_id)
	return Graph_Wire_Colour(graph, wire)
}

//* == Regions ==

node_graph_add_region :: proc(g: ^Core.GUI, id: Core.Widget_ID, title: string, pos: Core.Vec2, size: Core.Vec2) -> Graph_Region_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_REGION_ID}
	node_graph_undo_begin(g, id)
	region_id := Graph_Add_Region(graph, title, pos, size)
	node_graph_undo_commit(g, id, "add region")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return region_id
}

//* Creates a comment box around the nodes that are selected.
node_graph_add_region_around_selection :: proc(g: ^Core.GUI, id: Core.Widget_ID, title: string) -> Graph_Region_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_REGION_ID}
	node_graph_undo_begin(g, id)
	region_id := Graph_Region_Around_Nodes(graph, title)
	if region_id.index == 0 {
		node_graph_undo_cancel(g, id)
		return INVALID_GRAPH_REGION_ID
	}
	node_graph_undo_commit(g, id, "comment")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return region_id
}

node_graph_remove_region :: proc(g: ^Core.GUI, id: Core.Widget_ID, region_id: Graph_Region_ID) {
	graph := node_graph_of(g, id)
	if Graph_Region_Of(graph, region_id) == nil {return}
	node_graph_undo_begin(g, id)
	Graph_Remove_Region(graph, region_id)
	node_graph_undo_commit(g, id, "remove region")
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

node_graph_region_of :: proc(g: ^Core.GUI, id: Core.Widget_ID, region_id: Graph_Region_ID) -> ^Graph_Region {
	graph := node_graph_of(g, id)
	return Graph_Region_Of(graph, region_id)
}

node_graph_region_rect :: proc(g: ^Core.GUI, id: Core.Widget_ID, region_id: Graph_Region_ID) -> Core.Rect {
	graph := node_graph_of(g, id)
	region := Graph_Region_Of(graph, region_id)
	return Graph_Region_Rect(graph, region)
}

node_graph_set_region_title :: proc(g: ^Core.GUI, id: Core.Widget_ID, region_id: Graph_Region_ID, title: string) -> bool {
	graph := node_graph_of(g, id)
	if Graph_Region_Of(graph, region_id) == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Set_Region_Title(graph, region_id, title)
	node_graph_undo_commit(g, id, "region title")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return ok
}

node_graph_set_region_colour :: proc(g: ^Core.GUI, id: Core.Widget_ID, region_id: Graph_Region_ID, colour: Core.Colour) -> bool {
	graph := node_graph_of(g, id)
	if Graph_Region_Of(graph, region_id) == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Set_Region_Colour(graph, region_id, colour)
	node_graph_undo_commit(g, id, "region colour")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return ok
}

node_graph_set_region_move_contained :: proc(g: ^Core.GUI, id: Core.Widget_ID, region_id: Graph_Region_ID, move_contained: bool) -> bool {
	graph := node_graph_of(g, id)
	if Graph_Region_Of(graph, region_id) == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Set_Region_Move_Contained(graph, region_id, move_contained)
	node_graph_undo_commit(g, id, "region")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return ok
}

node_graph_region_count :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return 0}
	count := 0
	for region in graph.regions {
		if region.alive {count += 1}
	}
	return count
}

//* == Alignment ==

node_graph_align_selection :: proc(g: ^Core.GUI, id: Core.Widget_ID, mode: Graph_Align_Mode) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Align_Selection(graph, mode)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "align")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_distribute_selection :: proc(g: ^Core.GUI, id: Core.Widget_ID, horizontal: bool) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Distribute_Selection(graph, horizontal)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "distribute")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}


node_graph_save :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> string {
	graph := node_graph_of(g, id)
	if graph == nil {return ""}
	return Graph_Save(graph, true)
}

graph_save_snapshot :: proc(graph: ^Node_Graph) -> string {
	return Graph_Save(graph, false)
}

graph_save :: proc(graph: ^Node_Graph, include_view: bool) -> string {
	return Graph_Save(graph, include_view)
}

node_graph_save_file :: proc(g: ^Core.GUI, id: Core.Widget_ID, path: string) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil || path == "" {return false}
	return Graph_Save_File(graph, path)
}

node_graph_load :: proc(g: ^Core.GUI, id: Core.Widget_ID, text: string) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil {return false}
	node_graph_undo_begin(g, id)
	ok := Graph_Load_Into(graph, text, true)
	if !ok {
		node_graph_undo_cancel(g, id)
		return false
	}
	node_graph_undo_commit(g, id, "load")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_load_file :: proc(g: ^Core.GUI, id: Core.Widget_ID, path: string) -> bool {
	if path == "" {return false}
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {return false}
	defer delete(data)
	return node_graph_load(g, id, string(data))
}

graph_load_into :: proc(graph: ^Node_Graph, text: string, apply_view: bool) -> bool {
	return Graph_Load_Into(graph, text, apply_view)
}

node_graph_set_style :: proc(g: ^Core.GUI, id: Core.Widget_ID, style: Graph_Style) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	Graph_Set_Style(graph, style)
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

node_graph_style :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> Graph_Style {
	graph := node_graph_of(g, id)
	return Graph_Style_Of(graph)
}

node_graph_inspector_desc :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> Graph_Inspector_Desc {
	graph := node_graph_of(g, id)
	return Graph_Inspector_Build(graph)
}

node_graph_inspector_free :: proc(g: ^Core.GUI, id: Core.Widget_ID, desc: ^Graph_Inspector_Desc) {
	Graph_Inspector_Free(desc)
}

node_graph_inspector_summary :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> Graph_Selection_Summary {
	graph := node_graph_of(g, id)
	return Graph_Selection_Summarize(graph)
}

//* == The actions ==

//* Registers an action of the inspector. An action that is registered again
//* with the same name replaces the one before it.
node_graph_register_inspector_action :: proc(g: ^Core.GUI, id: Core.Widget_ID, action: Graph_Inspector_Action) -> bool {
	graph := node_graph_of(g, id)
	return Graph_Register_Inspector_Action(graph, action)
}

node_graph_inspector_actions :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> []Graph_Inspector_Action {
	graph := node_graph_of(g, id)
	return Graph_Inspector_Actions(graph)
}

//* Runs an action of the inspector by its name.
node_graph_inspector_action_invoke :: proc(g: ^Core.GUI, id: Core.Widget_ID, name: string) -> bool {
	graph := node_graph_of(g, id)
	return Graph_Inspector_Action_Invoke(graph, name, g, id)
}

//* The actions that apply to the selection of the graph.
node_graph_inspector_actions_for :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> [dynamic]Graph_Inspector_Action {
	graph := node_graph_of(g, id)
	summary := Graph_Selection_Summarize(graph)
	return Graph_Inspector_Actions_For(graph, summary)
}

//* == Selection ==

graph_selection_clear :: proc(graph: ^Node_Graph) {
	Graph_Clear_Selection(graph)
}

node_graph_clear_selection :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph_selection_clear(graph)
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_select_node :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	node_id: Graph_Node_ID,
	add := false,
) {
	graph := node_graph_of(g, id)
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return}

	if !add {
		graph_selection_clear(graph)
		node.selected = true
	} else {
		node.selected = !node.selected
	}
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_select_wire :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	wire_id: Graph_Wire_ID,
	add := false,
) {
	graph := node_graph_of(g, id)
	wire := Node_Graph_Wire_Of(graph, wire_id)
	if wire == nil {return}

	if !add {graph_selection_clear(graph)}
	wire.selected = true
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_select_all :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	for i := 0; i < len(graph.nodes); i += 1 {
		if graph.nodes[i].alive {graph.nodes[i].selected = true}
	}
	for i := 0; i < len(graph.wires); i += 1 {
		if graph.wires[i].alive {graph.wires[i].selected = true}
	}
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_delete_selection :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	node_graph_undo_begin(g, id)
	for i := len(graph.wires) - 1; i >= 0; i -= 1 {
		if graph.wires[i].alive && graph.wires[i].selected {Graph_Wire_Release(graph, i)}
	}
	for i := len(graph.regions) - 1; i >= 0; i -= 1 {
		if graph.regions[i].alive && graph.regions[i].selected {
			Graph_Remove_Region(graph, graph.regions[i].id)
		}
	}
	for i := len(graph.nodes) - 1; i >= 0; i -= 1 {
		if graph.nodes[i].alive && graph.nodes[i].selected {Graph_Node_Release(graph, i)}
	}
	node_graph_undo_commit(g, id, "delete")
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

graph_selection_count :: proc(graph: ^Node_Graph) -> int {
	count := 0
	for node in graph.nodes {
		if node.alive && node.selected {count += 1}
	}
	return count
}

//* == Clipboard ==

graph_clipboard_free :: proc(clipboard: ^Graph_Clipboard) {
	Graph_Clipboard_Free(clipboard)
}

node_graph_copy :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph_clipboard_free(&graph.clipboard)

	index_of := make(map[Graph_Node_ID]int)
	defer delete(index_of)

	origin := Core.Vec2{1e30, 1e30}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}

		index := len(graph.clipboard.nodes)
		index_of[node.id] = index
		clip := Graph_Clip_Node{
			type_name = strings.clone(node.type_name),
			title     = strings.clone(node.title),
			pos       = node.pos,
			size      = node.size,
			min_size  = node.min_size,
			max_size  = node.max_size,
			colour    = node.colour,
			collapsed = node.collapsed,
			collapsible = node.collapsible,
			resizable = node.resizable,
			config    = Graph_Config_Clone(node.config[:]),
		}
		for &port in node.ports {
			if !port.alive {continue}
			append(&clip.ports, Graph_Clip_Port{
				desc = Graph_Port_Desc_Clone(graph_port_desc_from_port(&port)),
			})
		}
		origin.x = min(origin.x, node.pos.x)
		origin.y = min(origin.y, node.pos.y)
		append(&graph.clipboard.nodes, clip)
	}
	if len(graph.clipboard.nodes) == 0 {return}

	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		from_index, has_from := index_of[wire.from_node]
		to_index, has_to := index_of[wire.to_node]
		if !has_from || !has_to {continue}
		from_port := Node_Graph_Port_Of(graph, wire.from_node, wire.from_port)
		to_port := Node_Graph_Port_Of(graph, wire.to_node, wire.to_port)
		if from_port == nil || to_port == nil {continue}
		append(&graph.clipboard.wires, Graph_Clip_Wire{
			from_node = from_index,
			from_port = graph_port_index_of(graph, wire.from_node, wire.from_port),
			to_node   = to_index,
			to_port   = graph_port_index_of(graph, wire.to_node, wire.to_port),
		})
	}
	graph.clipboard.origin = origin
	graph.clipboard.valid = true
}

graph_port_desc_from_port :: proc(port: ^Graph_Port) -> Graph_Port_Desc {
	return Graph_Port_Desc{
		name = port.name,
		direction = port.direction,
		port_kind = port.port_kind,
		type = port.type,
		colour = port.colour,
		capacity = port.capacity,
		default_value = port.default_value,
		tooltip = port.tooltip,
		visible = port.visible,
	}
}

graph_port_index_of :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) -> int {
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return int(port_id.index) - 1}
	live := 0
	for port in node.ports {
		if !port.alive {continue}
		if port.id == port_id {return live}
		live += 1
	}
	return int(port_id.index) - 1
}

graph_clip_port_index :: proc(node: ^Graph_Clip_Node, local: int) -> int {
	if local < 0 || local >= len(node.ports) {return -1}
	return local
}

node_graph_paste :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil || !graph.clipboard.valid || len(graph.clipboard.nodes) == 0 {return}

	w := Core.Widget_Get(g, id)
	if w == nil {return}
	content := Core.content_rect(g, w)
	target := Core.Vec2{graph.clipboard.origin.x + 24, graph.clipboard.origin.y + 24}
	if Core.rect_contains(content, g.pointer.x, g.pointer.y) {
		target = node_graph_graph_pos(graph, content, g.pointer)
	}
	offset := Core.Vec2{target.x - graph.clipboard.origin.x, target.y - graph.clipboard.origin.y}

	node_graph_undo_begin(g, id)
	graph_selection_clear(graph)

	new_nodes := make([]Graph_Node_ID, len(graph.clipboard.nodes))
	defer delete(new_nodes)
	new_ports := make([][]Graph_Port_ID, len(graph.clipboard.nodes))
	defer {
		for ports in new_ports {delete(ports)}
		delete(new_ports)
	}

	for clip, index in graph.clipboard.nodes {
		if !Graph_Kind_Allows_Type(graph, clip.type_name) {continue}
		node := Graph_Node_Slot(graph)
		node.type_name = strings.clone(clip.type_name)
		node.title = strings.clone(clip.title)
		node.pos = Core.Vec2{clip.pos.x + offset.x, clip.pos.y + offset.y}
		node.size = clip.size
		node.min_size = clip.min_size
		node.max_size = clip.max_size
		node.colour = clip.colour
		node.collapsed = clip.collapsed
		node.collapsible = clip.collapsible
		node.resizable = clip.resizable
		node.selected = true
		new_nodes[index] = node.id

		ports := make([]Graph_Port_ID, len(clip.ports))
		for port, port_index in clip.ports {
			ports[port_index] = Graph_Add_Port(node, port.desc)
		}
		new_ports[index] = ports
		for entry in clip.config {
			append(&node.config, Graph_Config_Entry{
				key = strings.clone(entry.key),
				value = Graph_Value_Clone(entry.value),
			})
		}
	}

	for wire in graph.clipboard.wires {
		if wire.from_node < 0 || wire.from_node >= len(new_nodes) {continue}
		if wire.to_node < 0 || wire.to_node >= len(new_nodes) {continue}
		if new_nodes[wire.from_node].index == 0 || new_nodes[wire.to_node].index == 0 {continue}
		from_index := graph_clip_port_index(&graph.clipboard.nodes[wire.from_node], wire.from_port)
		to_index := graph_clip_port_index(&graph.clipboard.nodes[wire.to_node], wire.to_port)
		if from_index < 0 || to_index < 0 {continue}
		if from_index >= len(new_ports[wire.from_node]) {continue}
		if to_index >= len(new_ports[wire.to_node]) {continue}
		Graph_Connect(
			graph,
			new_nodes[wire.from_node],
			new_ports[wire.from_node][from_index],
			new_nodes[wire.to_node],
			new_ports[wire.to_node][to_index],
			{},
		)
	}

	node_graph_undo_commit(g, id, "paste")
	Core.invalidate(g, id, Core.DIRTY_ALL)
}

node_graph_cut :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	node_graph_copy(g, id)
	node_graph_delete_selection(g, id)
}

node_graph_duplicate :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	node_graph_copy(g, id)
	node_graph_paste(g, id)
}

//* The clipboard copies the raw port description, so values must be
//* cloned before the source node can be released.
graph_clipboard_clone_value :: proc(value: Graph_Value) -> Graph_Value {
	return Graph_Value_Clone(value)
}

//* == Undo ==

GRAPH_UNDO_LIMIT :: 100

node_graph_undo_begin :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	if graph.undo_depth == 0 {
		if graph.undo_pending_valid && len(graph.undo_pending) > 0 {
			delete(graph.undo_pending)
		}
		graph.undo_pending = graph_save_snapshot(graph)
		graph.undo_pending_valid = graph.undo_pending != ""
	}
	graph.undo_depth += 1
}

node_graph_undo_commit :: proc(g: ^Core.GUI, id: Core.Widget_ID, label: string) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	if graph.undo_depth > 0 {graph.undo_depth -= 1}
	if graph.undo_depth > 0 {return}
	if !graph.undo_pending_valid {return}
	graph.undo_pending_valid = false

	after := graph_save_snapshot(graph)
	if after == graph.undo_pending {
		if len(after) > 0 {delete(after)}
		if len(graph.undo_pending) > 0 {delete(graph.undo_pending)}
		graph.undo_pending = ""
		return
	}

	//* A new edit replaces the redo history.
	for i := graph.undo_at; i < len(graph.undo_records); i += 1 {
		graph_undo_record_free(&graph.undo_records[i])
	}
	if graph.undo_at < len(graph.undo_records) {
		resize(&graph.undo_records, graph.undo_at)
	}

	append(&graph.undo_records, Graph_Undo_Record{
		before = graph.undo_pending,
		after = after,
		label = strings.clone(label),
	})
	graph.revision += 1
	graph.undo_pending = ""
	graph.undo_at = len(graph.undo_records)

	if len(graph.undo_records) > GRAPH_UNDO_LIMIT {
		graph_undo_record_free(&graph.undo_records[0])
		ordered_remove(&graph.undo_records, 0)
		graph.undo_at = len(graph.undo_records)
	}
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

graph_undo_record_free :: proc(record: ^Graph_Undo_Record) {
	Graph_Undo_Record_Free(record)
}

//* Drops a pending snapshot without recording an edit. Used when an
//* operation fails before it changed anything.
node_graph_undo_cancel :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	if graph.undo_depth > 0 {graph.undo_depth -= 1}
	if graph.undo_depth > 0 {return}
	graph.undo_pending_valid = false
	if len(graph.undo_pending) > 0 {delete(graph.undo_pending)}
	graph.undo_pending = ""
}

graph_undo_free :: proc(graph: ^Node_Graph) {
	Graph_Undo_Free(graph)
}

node_graph_can_undo :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> bool {
	graph := node_graph_of(g, id)
	return graph != nil && graph.undo_at > 0
}

node_graph_can_redo :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> bool {
	graph := node_graph_of(g, id)
	return graph != nil && graph.undo_at < len(graph.undo_records)
}

node_graph_undo :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil || graph.undo_at <= 0 {return false}
	graph.undo_at -= 1
	record := &graph.undo_records[graph.undo_at]
	if !graph_load_into(graph, record.before, false) {
		graph.undo_at += 1
		return false
	}
	graph.revision += 1
	graph.undo_pending_valid = false
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}

node_graph_redo :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> bool {
	graph := node_graph_of(g, id)
	if graph == nil || graph.undo_at >= len(graph.undo_records) {return false}
	record := &graph.undo_records[graph.undo_at]
	if !graph_load_into(graph, record.after, false) {return false}
	graph.revision += 1
	graph.undo_at += 1
	graph.undo_pending_valid = false
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return true
}
graph_auto_connect :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	from_node: Graph_Node_ID,
	from_port: Graph_Port_ID,
	to_node: Graph_Node_ID,
	from_direction: Graph_Port_Direction,
) {
	graph := node_graph_of(g, id)
	from := Node_Graph_Port_Of(graph, from_node, from_port)
	new_node := Node_Graph_Node_Of(graph, to_node)
	if graph == nil || from == nil || new_node == nil {return}

	node_graph_undo_begin(g, id)
	for port in new_node.ports {
		if !port.alive {continue}
		if port.port_kind != from.port_kind {continue}
		if from.type != "" && port.type != "" && port.type != from.type {continue}
		if from_direction == .Input {
			if port.direction == .Input {continue}
			if Graph_Connect(graph, to_node, port.id, from_node, from_port, {}).index != 0 {
				node_graph_undo_commit(g, id, "connect")
				return
			}
		} else {
			if port.direction == .Output {continue}
			if Graph_Connect(graph, from_node, from_port, to_node, port.id, {}).index != 0 {
				node_graph_undo_commit(g, id, "connect")
				return
			}
		}
	}
	node_graph_undo_commit(g, id, "connect")
}

node_graph_create_node_by_name :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	type_name: string,
	pos: Core.Vec2,
) -> Graph_Node_ID {
	return node_graph_add_typed_node(g, id, type_name, pos)
}

node_graph_create_node_by_index :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	type_index: int,
	pos: Core.Vec2,
) -> Graph_Node_ID {
	graph := node_graph_of(g, id)
	if graph == nil || type_index < 0 || type_index >= len(graph.types) {
		return INVALID_GRAPH_NODE_ID
	}
	return node_graph_add_typed_node(g, id, graph.types[type_index].name, pos)
}

node_graph_add_reroute :: proc(g: ^Core.GUI, id: Core.Widget_ID, pos: Core.Vec2) -> Graph_Node_ID {
	graph := node_graph_of(g, id)
	if graph == nil {return INVALID_GRAPH_NODE_ID}
	node_graph_undo_begin(g, id)
	node := Graph_Add_Reroute_Dot(graph, pos)
	if node.index == 0 {
		node_graph_undo_cancel(g, id)
		return node
	}
	node_graph_undo_commit(g, id, "add reroute")
	Core.invalidate(g, id, Core.DIRTY_ALL)
	return node
}

node_graph_create_node :: proc {
	node_graph_create_node_by_name,
	node_graph_create_node_by_index,
}
node_graph_begin_pending_connection :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) {
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if port == nil {return}
	graph.active_port_node = node_id
	graph.active_port = port_id
	graph.menu_direction = port.direction
	graph.menu_pending = true
}


//* A copy of a string in the memory of the caller.
graph_string_copy :: proc(s: string, allocator := context.allocator) -> string {
	if len(s) == 0 {return ""}
	return strings.clone(s, allocator)
}

//* == The summary of a selection ==

Graph_Selection_Kind :: enum {
	None,
	Node,
	Nodes,
	Wire,
	Wires,
	Region,
	Regions,
	Mixed,
}

//* What the selection holds. The counts say how many, the type is the type
//* the selected nodes share, and the title is a short name for the header.
Graph_Selection_Summary :: struct {
	kind:         Graph_Selection_Kind,
	node_count:   int,
	wire_count:   int,
	region_count: int,
	node_type:    string,
	title:        string,
}

//* Reads the selection of a graph.
Graph_Selection_Summarize :: proc(graph: ^Node_Graph) -> Graph_Selection_Summary {
	summary: Graph_Selection_Summary
	if graph == nil {return summary}
	shared_type := ""
	shared := true
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		summary.node_count += 1
		if shared_type == "" {
			shared_type = node.type_name
		} else if shared_type != node.type_name {
			shared = false
		}
	}
	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive || !wire.selected {continue}
		summary.wire_count += 1
	}
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive || !region.selected {continue}
		summary.region_count += 1
	}
	if shared {summary.node_type = shared_type}

	kinds := 0
	if summary.node_count > 0 {kinds += 1}
	if summary.wire_count > 0 {kinds += 1}
	if summary.region_count > 0 {kinds += 1}
	switch kinds {
	case 0:
		summary.kind = .None
	case 1:
		if summary.node_count > 0 {
			summary.kind = summary.node_count == 1 ? .Node : .Nodes
		} else if summary.wire_count > 0 {
			summary.kind = summary.wire_count == 1 ? .Wire : .Wires
		} else {
			summary.kind = summary.region_count == 1 ? .Region : .Regions
		}
	case:
		summary.kind = .Mixed
	}
	summary.title = Graph_Selection_Title_Of(graph, summary)
	return summary
}

//* The short name of the selection, the way the header of the inspector
//* shows it.
Graph_Selection_Title_Of :: proc(graph: ^Node_Graph, summary: Graph_Selection_Summary) -> string {
	switch summary.kind {
	case .None:
		return "Nothing selected"
	case .Node:
		node := Graph_Selected_Node(graph)
		if node == nil {return "1 node selected"}
		if node.type_name == "" {return node.title}
		if node.title == node.type_name {return node.type_name}
		return fmt.tprintf("%s (%s)", node.title, node.type_name)
	case .Nodes:
		return fmt.tprintf("%d nodes selected", summary.node_count)
	case .Wire:
		return "1 wire selected"
	case .Wires:
		return fmt.tprintf("%d wires selected", summary.wire_count)
	case .Region:
		region := Graph_Selected_Region(graph)
		if region == nil || region.title == "" {return "1 region selected"}
		return region.title
	case .Regions:
		return fmt.tprintf("%d regions selected", summary.region_count)
	case .Mixed:
		return fmt.tprintf(
			"%d nodes, %d wires, %d regions",
			summary.node_count,
			summary.wire_count,
			summary.region_count,
		)
	}
	return ""
}

Graph_Selected_Node :: proc(graph: ^Node_Graph) -> ^Graph_Node {
	if graph == nil {return nil}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if node.alive && node.selected {return node}
	}
	return nil
}

Graph_Selected_Wire :: proc(graph: ^Node_Graph) -> ^Graph_Wire {
	if graph == nil {return nil}
	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if wire.alive && wire.selected {return wire}
	}
	return nil
}

Graph_Selected_Region :: proc(graph: ^Node_Graph) -> ^Graph_Region {
	if graph == nil {return nil}
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if region.alive && region.selected {return region}
	}
	return nil
}

//* == The fields ==

//* What a field of the inspector shows.
Graph_Inspector_Field_Kind :: enum {
	Text,
	Number,
	Bool,
	Choice,
	Colour_Swatch,
	Read_Only,
	Button,
}

//* Where the value of a field comes from, so that the renderer knows what
//* to write it back to.
Graph_Inspector_Source :: enum {
	None,
	Node_Title,
	Config,
	Port_Name,
	Port_Type,
	Region_Title,
	Region_Colour,
	Region_Move_Nodes,
	Region_Count,
	Wire_Type,
	Wire_Endpoints,
	Action,
}

Graph_Inspector_Field :: struct {
	key:       string,
	label:     string,
	kind:      Graph_Inspector_Field_Kind,
	source:    Graph_Inspector_Source,
	value:     Graph_Value,
	options:   [dynamic]string,
	enabled:   bool,
	tooltip:   string,
	swatches:  [dynamic]Core.Colour,
	node_id:   Graph_Node_ID,
	port_id:   Graph_Port_ID,
	region_id: Graph_Region_ID,
	wire_id:   Graph_Wire_ID,
}

Graph_Inspector_Section :: struct {
	key:    string,
	title:  string,
	fields: [dynamic]Graph_Inspector_Field,
}

Graph_Inspector_Tab :: struct {
	key:      string,
	label:    string,
	sections: [dynamic]Graph_Inspector_Section,
}

Graph_Inspector_Desc :: struct {
	summary: Graph_Selection_Summary,
	tabs:    [dynamic]Graph_Inspector_Tab,
}

//* The kind of editor a value asks for.
Graph_Inspector_Field_Kind_Of :: proc(value: Graph_Value) -> Graph_Inspector_Field_Kind {
	#partial switch v in value {
	case bool:
		return .Bool
	case i32, f32:
		return .Number
	case string:
		return .Text
	}
	return .Text
}

//* == The actions ==

//* An action of the inspector. The predicate says when the action applies
//* to the selection, and the callback does the work.
Graph_Inspector_Action :: struct {
	name:        string,
	label:       string,
	description: string,
	applies:     proc(summary: Graph_Selection_Summary) -> bool,
	invoke:      proc(g: ^Core.GUI, graph: Core.Widget_ID, summary: Graph_Selection_Summary),
}

//* Registers an action of the graph. The name is the key: an action that
//* is registered again replaces the one before it.
Graph_Register_Inspector_Action :: proc(graph: ^Node_Graph, action: Graph_Inspector_Action) -> bool {
	if graph == nil || action.name == "" {return false}
	for i in 0 ..< len(graph.inspector_actions) {
		if graph.inspector_actions[i].name == action.name {
			graph.inspector_actions[i] = action
			return true
		}
	}
	append(&graph.inspector_actions, action)
	return true
}

//* The actions of a graph.
Graph_Inspector_Actions :: proc(graph: ^Node_Graph) -> []Graph_Inspector_Action {
	if graph == nil {return nil}
	return graph.inspector_actions[:]
}

//* The actions that apply to a selection.
Graph_Inspector_Actions_For :: proc(
	graph: ^Node_Graph,
	summary: Graph_Selection_Summary,
) -> [dynamic]Graph_Inspector_Action {
	out: [dynamic]Graph_Inspector_Action
	if graph == nil {return out}
	for action in graph.inspector_actions {
		if action.applies == nil {continue}
		if !action.applies(summary) {continue}
		append(&out, action)
	}
	return out
}

//* Runs an action of the graph. It says whether the action was there.
Graph_Inspector_Action_Invoke :: proc(
	graph: ^Node_Graph,
	name: string,
	g: ^Core.GUI,
	widget: Core.Widget_ID,
) -> bool {
	if graph == nil {return false}
	for action in graph.inspector_actions {
		if action.name != name {continue}
		if action.invoke == nil {return false}
		action.invoke(g, widget, Graph_Selection_Summarize(graph))
		return true
	}
	return false
}

//* == Building the description ==

Graph_Inspector_Build :: proc(graph: ^Node_Graph, allocator := context.allocator) -> Graph_Inspector_Desc {
	desc: Graph_Inspector_Desc
	if graph == nil {return desc}
	desc.tabs = make([dynamic]Graph_Inspector_Tab, 0, 0, allocator)
	desc.summary = Graph_Selection_Summarize(graph)

	switch desc.summary.kind {
	case .None:
		return desc
	case .Node:
		graph_inspector_build_node(graph, &desc, allocator)
	case .Nodes, .Mixed:
		graph_inspector_build_actions(graph, &desc, allocator)
	case .Wire:
		graph_inspector_build_wire(graph, &desc, allocator)
	case .Wires:
		graph_inspector_build_actions(graph, &desc, allocator)
	case .Region:
		graph_inspector_build_region(graph, &desc, allocator)
	case .Regions:
		graph_inspector_build_actions(graph, &desc, allocator)
	}
	return desc
}

graph_inspector_new_tab :: proc(
	desc: ^Graph_Inspector_Desc,
	key, label: string,
	allocator := context.allocator,
) -> ^Graph_Inspector_Tab {
	tab := Graph_Inspector_Tab{
		key = graph_string_copy(key, allocator),
		label = graph_string_copy(label, allocator),
	}
	tab.sections = make([dynamic]Graph_Inspector_Section, 0, 0, allocator)
	append(&desc.tabs, tab)
	return &desc.tabs[len(desc.tabs) - 1]
}

graph_inspector_new_section :: proc(
	tab: ^Graph_Inspector_Tab,
	key, title: string,
	allocator := context.allocator,
) -> ^Graph_Inspector_Section {
	section := Graph_Inspector_Section{
		key = graph_string_copy(key, allocator),
		title = graph_string_copy(title, allocator),
	}
	section.fields = make([dynamic]Graph_Inspector_Field, 0, 0, allocator)
	append(&tab.sections, section)
	return &tab.sections[len(tab.sections) - 1]
}

graph_inspector_add_field :: proc(
	section: ^Graph_Inspector_Section,
	field: Graph_Inspector_Field,
	allocator := context.allocator,
) {
	out := field
	out.key = graph_string_copy(field.key, allocator)
	out.label = graph_string_copy(field.label, allocator)
	out.tooltip = graph_string_copy(field.tooltip, allocator)
	out.value = Graph_Value_Clone(field.value)
	append(&section.fields, out)
}

//* The fields of a node.
graph_inspector_build_node :: proc(
	graph: ^Node_Graph,
	desc: ^Graph_Inspector_Desc,
	allocator := context.allocator,
) {
	node := Graph_Selected_Node(graph)
	if node == nil {return}

	tab := graph_inspector_new_tab(desc, "properties", "Properties", allocator)
	section := graph_inspector_new_section(tab, "node", "", allocator)

	graph_inspector_add_field(section, Graph_Inspector_Field{
		key = "title",
		label = "Title",
		kind = .Text,
		source = .Node_Title,
		value = Graph_Value(node.title),
		enabled = true,
		node_id = node.id,
	}, allocator)

	if node.type_name != "" && node.type_name != node.title {
		graph_inspector_add_field(section, Graph_Inspector_Field{
			key = "node_type",
			label = "Type",
			kind = .Read_Only,
			source = .None,
			value = Graph_Value(node.type_name),
			enabled = true,
			node_id = node.id,
		}, allocator)
	}

	for entry in node.config {
		if !Graph_Config_Relevant(graph, node, entry) {continue}
		kind := Graph_Inspector_Field_Kind_Of(entry.value)
		if entry.read_only {kind = .Read_Only}
		graph_inspector_add_field(section, Graph_Inspector_Field{
			key = entry.key,
			label = entry.key,
			kind = kind,
			source = entry.read_only ? Graph_Inspector_Source.None : Graph_Inspector_Source.Config,
			value = entry.value,
			enabled = !entry.read_only,
			node_id = node.id,
		}, allocator)
	}

	graph_inspector_build_pins(graph, node, desc, allocator)
	graph_inspector_build_actions(graph, desc, allocator)
}

//* The pins of a node. A custom node lists all of its ports, while a typed
//* node lists only the ports its policy generated.
graph_inspector_build_pins :: proc(
	graph: ^Node_Graph,
	node: ^Graph_Node,
	desc: ^Graph_Inspector_Desc,
	allocator := context.allocator,
) {
	custom := node.type_name == ""
	shown := 0
	for port in node.ports {
		if !port.alive || !port.visible {continue}
		if !custom && !Graph_Port_Is_Removable(graph, node.id, port.id) {continue}
		shown += 1
	}
	if shown == 0 {return}

	tab := graph_inspector_new_tab(desc, "pins", "Pins", allocator)
	section := graph_inspector_new_section(tab, "pins", "Pins", allocator)
	for port in node.ports {
		if !port.alive || !port.visible {continue}
		if !custom && !Graph_Port_Is_Removable(graph, node.id, port.id) {continue}

		graph_inspector_add_field(section, Graph_Inspector_Field{
			key = "name",
			label = "Name",
			kind = .Text,
			source = .Port_Name,
			value = Graph_Value(port.name),
			enabled = true,
			node_id = node.id,
			port_id = port.id,
		}, allocator)
		graph_inspector_add_field(section, Graph_Inspector_Field{
			key = "type",
			label = "Type",
			kind = .Text,
			source = .Port_Type,
			value = Graph_Value(port.type),
			enabled = true,
			node_id = node.id,
			port_id = port.id,
		}, allocator)
	}
}

//* The fields of a wire.
graph_inspector_build_wire :: proc(
	graph: ^Node_Graph,
	desc: ^Graph_Inspector_Desc,
	allocator := context.allocator,
) {
	wire := Graph_Selected_Wire(graph)
	if wire == nil {return}
	tab := graph_inspector_new_tab(desc, "properties", "Properties", allocator)
	section := graph_inspector_new_section(tab, "wire", "", allocator)

	from := Node_Graph_Port_Of(graph, wire.from_node, wire.from_port)
	to := Node_Graph_Port_Of(graph, wire.to_node, wire.to_port)
	from_name := from != nil ? from.name : ""
	to_name := to != nil ? to.name : ""
	type_name := Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port)

	graph_inspector_add_field(section, Graph_Inspector_Field{
		key = "type",
		label = "Type",
		kind = .Read_Only,
		source = .Wire_Type,
		value = Graph_Value(type_name),
		enabled = true,
		wire_id = wire.id,
	}, allocator)
	graph_inspector_add_field(section, Graph_Inspector_Field{
		key = "endpoints",
		label = "Endpoints",
		kind = .Read_Only,
		source = .Wire_Endpoints,
		value = Graph_Value(fmt.tprintf("%s -> %s", from_name, to_name)),
		enabled = true,
		wire_id = wire.id,
	}, allocator)
	graph_inspector_build_actions(graph, desc, allocator)
}

//* The fields of a comment region.
graph_inspector_build_region :: proc(
	graph: ^Node_Graph,
	desc: ^Graph_Inspector_Desc,
	allocator := context.allocator,
) {
	region := Graph_Selected_Region(graph)
	if region == nil {return}
	tab := graph_inspector_new_tab(desc, "properties", "Properties", allocator)
	section := graph_inspector_new_section(tab, "region", "", allocator)

	graph_inspector_add_field(section, Graph_Inspector_Field{
		key = "title",
		label = "Title",
		kind = .Text,
		source = .Region_Title,
		value = Graph_Value(region.title),
		enabled = true,
		region_id = region.id,
	}, allocator)

	colour := Graph_Inspector_Field{
		key = "colour",
		label = "Colour",
		kind = .Colour_Swatch,
		source = .Region_Colour,
		value = Graph_Value(region.colour),
		enabled = true,
		region_id = region.id,
	}
	for entry in GRAPH_REGION_COLOURS {
		append(&colour.swatches, entry)
	}
	graph_inspector_add_field(section, colour, allocator)

	graph_inspector_add_field(section, Graph_Inspector_Field{
		key = "move_contained",
		label = "Move nodes",
		kind = .Bool,
		source = .Region_Move_Nodes,
		value = Graph_Value(region.move_contained),
		enabled = true,
		region_id = region.id,
	}, allocator)

	graph_inspector_build_actions(graph, desc, allocator)
}

//* The tab of the actions that apply to the selection.
graph_inspector_build_actions :: proc(
	graph: ^Node_Graph,
	desc: ^Graph_Inspector_Desc,
	allocator := context.allocator,
) {
	actions := Graph_Inspector_Actions_For(graph, desc.summary)
	defer delete(actions)
	if len(actions) == 0 {return}
	tab := graph_inspector_new_tab(desc, "actions", "Actions", allocator)
	section := graph_inspector_new_section(tab, "actions", "", allocator)
	for action in actions {
		graph_inspector_add_field(section, Graph_Inspector_Field{
			key = action.name,
			label = action.label,
			kind = .Button,
			source = .Action,
			enabled = true,
			tooltip = action.description,
		}, allocator)
	}
}

//* == Freeing ==

graph_inspector_free_field :: proc(field: ^Graph_Inspector_Field, allocator := context.allocator) {
	delete(field.key, allocator)
	delete(field.label, allocator)
	delete(field.tooltip, allocator)
	Graph_Value_Free(field.value)
	for option in field.options {delete(option, allocator)}
	delete(field.options)
	delete(field.swatches)
}

graph_inspector_free_section :: proc(section: Graph_Inspector_Section, allocator := context.allocator) {
	delete(section.key, allocator)
	delete(section.title, allocator)
	for &field in section.fields {graph_inspector_free_field(&field, allocator)}
	delete(section.fields)
}

Graph_Inspector_Free :: proc(desc: ^Graph_Inspector_Desc, allocator := context.allocator) {
	if desc == nil {return}
	for &tab in desc.tabs {
		delete(tab.key, allocator)
		delete(tab.label, allocator)
		for section in tab.sections {graph_inspector_free_section(section, allocator)}
		delete(tab.sections)
	}
	delete(desc.tabs)
	desc.tabs = nil
}

//* == Tooltips ==

//* The tooltip of a pin: its own tooltip when it has one, and its name and
//* type otherwise.
Graph_Pin_Tooltip :: proc(
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
	buf: []u8,
) -> string {
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if port == nil {return ""}
	if port.tooltip != "" {return port.tooltip}
	if port.type != "" {return fmt.bprintf(buf, "%s: %s", port.name, port.type)}
	return port.name
}

//* The tooltip of a node: its title, and its type when the two differ.
Graph_Node_Tooltip :: proc(graph: ^Node_Graph, node: ^Graph_Node, buf: []u8) -> string {
	if node == nil {return ""}
	if node.type_name != "" && node.type_name != node.title {
		return fmt.bprintf(buf, "%s (%s)", node.title, node.type_name)
	}
	return node.title
}
