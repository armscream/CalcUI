package NodeGraph

import Core "../Core"
import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"
import "core:strconv"
import "core:strings"

GRAPH_FORMAT_VERSION :: 1

Graph_Line_Attr :: struct {
	key:   string,
	value: string,
}

Graph_Line :: struct {
	kind:  string,
	attrs: [dynamic]Graph_Line_Attr,
}

Graph_Port_Ref :: struct {
	node: u32,
	port: u32,
}

Graph_Port_Handle_Ref :: struct {
	node: Graph_Node_ID,
	port: Graph_Port_ID,
}

Graph_Save :: proc(graph: ^Node_Graph, include_view: bool) -> string {
	if graph == nil {return ""}
	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, 512, context.allocator); err != nil {return ""}
	strings.write_string(&builder, "graph version=")
	graph_save_write_int(&builder, GRAPH_FORMAT_VERSION)
	if len(graph.kind_name) > 0 {
		strings.write_string(&builder, " kind=")
		graph_save_write_quoted(&builder, graph.kind_name)
	}
	if include_view {
		strings.write_string(&builder, " zoom=")
		graph_save_write_float(&builder, Graph_Zoom_Of(graph))
		strings.write_string(&builder, " pan=")
		graph_save_write_vec2(&builder, Graph_Pan_Of(graph))
		strings.write_string(&builder, " grid=")
		graph_save_write_bool(&builder, graph.grid_visible)
		strings.write_string(&builder, " grid_size=")
		graph_save_write_float(&builder, graph.grid_size)
		strings.write_string(&builder, " grid_major=")
		graph_save_write_float(&builder, graph.grid_major)
		strings.write_string(&builder, " snap=")
		graph_save_write_bool(&builder, graph.snap)
	}
	strings.write_byte(&builder, '\n')
	if graph.metadata != nil {
		keys: [dynamic]string
		defer delete(keys)
		for key in graph.metadata {append(&keys, key)}
		sort.quick_sort(keys[:])
		for key in keys {
			strings.write_string(&builder, "meta key=")
			graph_save_write_quoted(&builder, key)
			strings.write_string(&builder, " value=")
			graph_save_write_quoted(&builder, graph.metadata[key])
			strings.write_byte(&builder, '\n')
		}
	}
	for entry in graph.type_colours {
		strings.write_string(&builder, "typecolour name=")
		graph_save_write_quoted(&builder, entry.name)
		strings.write_string(&builder, " colour=")
		graph_save_write_colour(&builder, entry.colour)
		strings.write_byte(&builder, '\n')
	}
	for kind in graph.kinds {
		strings.write_string(&builder, "kind name=")
		graph_save_write_quoted(&builder, kind.name)
		strings.write_string(&builder, " description=")
		graph_save_write_quoted(&builder, kind.description)
		strings.write_string(&builder, " execution=")
		graph_save_write_bool(&builder, kind.execution)
		strings.write_string(&builder, " allowed=")
		graph_save_write_quoted_list(&builder, kind.allowed_nodes[:])
		strings.write_byte(&builder, '\n')
	}
	for node_type in graph.types {
		strings.write_string(&builder, "type name=")
		graph_save_write_quoted(&builder, node_type.name)
		strings.write_string(&builder, " category=")
		graph_save_write_quoted(&builder, node_type.category)
		strings.write_string(&builder, " description=")
		graph_save_write_quoted(&builder, node_type.description)
		strings.write_string(&builder, " colour=")
		graph_save_write_colour(&builder, node_type.colour)
		strings.write_string(&builder, " default_size=")
		graph_save_write_vec2(&builder, node_type.default_size)
		strings.write_string(&builder, " min_size=")
		graph_save_write_vec2(&builder, node_type.min_size)
		strings.write_string(&builder, " max_size=")
		graph_save_write_vec2(&builder, node_type.max_size)
		strings.write_string(&builder, " resizable=")
		graph_save_write_bool(&builder, node_type.resizable)
		strings.write_string(&builder, " collapsible=")
		graph_save_write_bool(&builder, node_type.collapsible)
		strings.write_string(&builder, " add_inputs=")
		graph_save_write_bool(&builder, node_type.policy.add_inputs)
		strings.write_string(&builder, " add_outputs=")
		graph_save_write_bool(&builder, node_type.policy.add_outputs)
		strings.write_string(&builder, " max_inputs=")
		graph_save_write_int(&builder, int(node_type.policy.max_inputs))
		strings.write_string(&builder, " max_outputs=")
		graph_save_write_int(&builder, int(node_type.policy.max_outputs))
		strings.write_string(&builder, " input_type=")
		graph_save_write_quoted(&builder, node_type.policy.input_type)
		strings.write_string(&builder, " output_type=")
		graph_save_write_quoted(&builder, node_type.policy.output_type)
		strings.write_string(&builder, " input_prefix=")
		graph_save_write_quoted(&builder, node_type.policy.input_prefix)
		strings.write_string(&builder, " output_prefix=")
		graph_save_write_quoted(&builder, node_type.policy.output_prefix)
		strings.write_byte(&builder, '\n')
	}
	node_ids := make(map[Graph_Node_ID]u32)
	defer delete(node_ids)
	port_ids := make(map[Graph_Port_Handle_Ref]u32)
	defer delete(port_ids)
	next_node: u32 = 1
	for node in graph.nodes {
		if !node.alive {continue}
		node_ids[node.id] = next_node
		next_node += 1
	}
	for node in graph.nodes {
		if !node.alive {continue}
		next_port: u32 = 1
		for port in node.ports {
			if !port.alive {continue}
			port_ids[Graph_Port_Handle_Ref{node = node.id, port = port.id}] = next_port
			next_port += 1
		}
	}
	for node in graph.nodes {
		if !node.alive {continue}
		strings.write_string(&builder, "node id=")
		graph_save_write_int(&builder, int(node_ids[node.id]))
		strings.write_string(&builder, " type=")
		graph_save_write_quoted(&builder, node.type_name)
		strings.write_string(&builder, " kind=")
		strings.write_string(&builder, graph_node_kind_name(node.kind))
		strings.write_string(&builder, " input_type=")
		graph_save_write_quoted(&builder, node.reroute_input_type)
		strings.write_string(&builder, " output_type=")
		graph_save_write_quoted(&builder, node.reroute_output_type)
		strings.write_string(&builder, " title=")
		graph_save_write_quoted(&builder, node.title)
		strings.write_string(&builder, " short=")
		graph_save_write_quoted(&builder, node.short_title)
		strings.write_string(&builder, " pos=")
		graph_save_write_vec2(&builder, node.pos)
		strings.write_string(&builder, " size=")
		graph_save_write_vec2(&builder, node.size)
		strings.write_string(&builder, " collapsed=")
		graph_save_write_bool(&builder, node.collapsed)
		strings.write_string(&builder, " colour=")
		graph_save_write_colour(&builder, node.colour)
		strings.write_byte(&builder, '\n')
		for port in node.ports {
			if !port.alive {continue}
			strings.write_string(&builder, "port node=")
			graph_save_write_int(&builder, int(node_ids[node.id]))
			strings.write_string(&builder, " id=")
			graph_save_write_int(&builder, int(port_ids[Graph_Port_Handle_Ref{node = node.id, port = port.id}]))
			strings.write_string(&builder, " name=")
			graph_save_write_quoted(&builder, port.name)
			strings.write_string(&builder, " direction=")
			strings.write_string(&builder, graph_direction_name(port.direction))
			strings.write_string(&builder, " port_kind=")
			strings.write_string(&builder, graph_port_kind_name(port.port_kind))
			strings.write_string(&builder, " type=")
			graph_save_write_quoted(&builder, port.type)
			strings.write_string(&builder, " capacity=")
			graph_save_write_int(&builder, int(port.capacity))
			strings.write_string(&builder, " colour=")
			graph_save_write_colour(&builder, port.colour)
			strings.write_string(&builder, " visible=")
			graph_save_write_bool(&builder, port.visible)
			strings.write_string(&builder, " tooltip=")
			graph_save_write_quoted(&builder, port.tooltip)
			if port.default_value != nil {
				strings.write_string(&builder, " default_kind=")
				strings.write_string(&builder, graph_value_kind_name(Graph_Value_Kind_Of(port.default_value)))
				strings.write_string(&builder, " default=")
				graph_save_write_value(&builder, port.default_value)
			}
			strings.write_byte(&builder, '\n')
		}
		for entry in node.config {
			strings.write_string(&builder, "config node=")
			graph_save_write_int(&builder, int(node_ids[node.id]))
			strings.write_string(&builder, " key=")
			graph_save_write_quoted(&builder, entry.key)
			strings.write_string(&builder, " kind=")
			strings.write_string(&builder, graph_value_kind_name(Graph_Value_Kind_Of(entry.value)))
			strings.write_string(&builder, " value=")
			graph_save_write_value(&builder, entry.value)
			strings.write_string(&builder, " read_only=")
			graph_save_write_bool(&builder, entry.read_only)
			strings.write_byte(&builder, '\n')
		}
	}
	next_wire: u32 = 1
	for wire in graph.wires {
		if !wire.alive {continue}
		from_node := node_ids[wire.from_node]
		to_node := node_ids[wire.to_node]
		from_port := port_ids[Graph_Port_Handle_Ref{node = wire.from_node, port = wire.from_port}]
		to_port := port_ids[Graph_Port_Handle_Ref{node = wire.to_node, port = wire.to_port}]
		if from_node == 0 || to_node == 0 || from_port == 0 || to_port == 0 {continue}
		strings.write_string(&builder, "wire id=")
		graph_save_write_int(&builder, int(next_wire))
		next_wire += 1
		strings.write_string(&builder, " from_node=")
		graph_save_write_int(&builder, int(from_node))
		strings.write_string(&builder, " from_port=")
		graph_save_write_int(&builder, int(from_port))
		strings.write_string(&builder, " to_node=")
		graph_save_write_int(&builder, int(to_node))
		strings.write_string(&builder, " to_port=")
		graph_save_write_int(&builder, int(to_port))
		strings.write_string(&builder, " colour=")
		graph_save_write_colour(&builder, wire.colour)
		strings.write_byte(&builder, '\n')
	}
	for region in graph.regions {
		if !region.alive {continue}
		strings.write_string(&builder, "region title=")
		graph_save_write_quoted(&builder, region.title)
		strings.write_string(&builder, " pos=")
		graph_save_write_vec2(&builder, region.pos)
		strings.write_string(&builder, " size=")
		graph_save_write_vec2(&builder, region.size)
		strings.write_string(&builder, " colour=")
		graph_save_write_colour(&builder, region.colour)
		strings.write_string(&builder, " move_contained=")
		graph_save_write_bool(&builder, region.move_contained)
		strings.write_byte(&builder, '\n')
	}
	return strings.to_string(builder)
}

Graph_Save_File :: proc(graph: ^Node_Graph, path: string) -> bool {
	if graph == nil || path == "" {return false}
	text := Graph_Save(graph, true)
	defer delete(text)
	if text == "" {return false}
	return os.write_entire_file(path, text) == nil
}

Graph_Load_File :: proc(graph: ^Node_Graph, path: string) -> bool {
	if graph == nil || path == "" {return false}
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {return false}
	defer delete(data)
	return Graph_Load_Into(graph, string(data), true)
}

graph_save_write_int :: proc(builder: ^strings.Builder, value: int) {
	buf: [32]u8
	text := strconv.write_int(buf[:], i64(value), 10)
	strings.write_string(builder, text)
}

graph_save_write_float :: proc(builder: ^strings.Builder, value: f32) {
	buf: [64]u8
	text := strconv.write_float(buf[:], f64(value), 'g', -1, 32)
	if len(text) > 0 && text[0] == '+' {text = text[1:]}
	strings.write_string(builder, text)
}

graph_save_write_bool :: proc(builder: ^strings.Builder, value: bool) {
	strings.write_string(builder, value ? "1" : "0")
}

graph_save_write_vec2 :: proc(builder: ^strings.Builder, value: Core.Vec2) {
	graph_save_write_float(builder, value.x)
	strings.write_byte(builder, ',')
	graph_save_write_float(builder, value.y)
}

graph_save_write_vec3 :: proc(builder: ^strings.Builder, value: Core.Vec3) {
	graph_save_write_float(builder, value.x)
	strings.write_byte(builder, ',')
	graph_save_write_float(builder, value.y)
	strings.write_byte(builder, ',')
	graph_save_write_float(builder, value.z)
}

graph_save_write_colour :: proc(builder: ^strings.Builder, value: Core.Colour) {
	graph_save_write_float(builder, value.r)
	strings.write_byte(builder, ',')
	graph_save_write_float(builder, value.g)
	strings.write_byte(builder, ',')
	graph_save_write_float(builder, value.b)
	strings.write_byte(builder, ',')
	graph_save_write_float(builder, value.a)
}

graph_save_write_quoted :: proc(builder: ^strings.Builder, text: string) {
	strings.write_byte(builder, '"')
	for i := 0; i < len(text); i += 1 {
		c := text[i]
		switch c {
		case '\\': strings.write_string(builder, "\\\\")
		case '"':  strings.write_string(builder, "\\\"")
		case '\n': strings.write_string(builder, "\\n")
		case '\t': strings.write_string(builder, "\\t")
		case '\r': strings.write_string(builder, "\\r")
		case: strings.write_byte(builder, c)
		}
	}
	strings.write_byte(builder, '"')
}

graph_save_write_quoted_list :: proc(builder: ^strings.Builder, names: []string) {
	strings.write_byte(builder, '"')
	for name, name_index in names {
		if name_index > 0 {strings.write_byte(builder, ',')}
		for i := 0; i < len(name); i += 1 {
			c := name[i]
			switch c {
			case '\\': strings.write_string(builder, "\\\\")
			case '"':  strings.write_string(builder, "\\\"")
			case '\n': strings.write_string(builder, "\\n")
			case '\t': strings.write_string(builder, "\\t")
			case '\r': strings.write_string(builder, "\\r")
			case: strings.write_byte(builder, c)
			}
		}
	}
	strings.write_byte(builder, '"')
}

graph_save_write_value :: proc(builder: ^strings.Builder, value: Graph_Value) {
	switch v in value {
	case bool: graph_save_write_bool(builder, v)
	case i32: graph_save_write_int(builder, int(v))
	case f32: graph_save_write_float(builder, v)
	case Core.Vec2: graph_save_write_vec2(builder, v)
	case Core.Vec3: graph_save_write_vec3(builder, v)
	case Core.Colour: graph_save_write_colour(builder, v)
	case string: graph_save_write_quoted(builder, v)
	}
}

graph_value_kind_name :: proc(kind: Graph_Value_Kind) -> string {
	switch kind {
	case .Bool:   return "Bool"
	case .Int:    return "Int"
	case .Float:  return "Float"
	case .Vec2:   return "Vec2"
	case .Vec3:   return "Vec3"
	case .Colour: return "Colour"
	case .String: return "String"
	}
	return "Float"
}

graph_node_kind_name :: proc(kind: Graph_Node_Kind) -> string {
	switch kind {
	case .Normal:         return "normal"
	case .Reroute_Dot:    return "reroute"
	case .Reroute_Convert: return "conversion"
	}
	return "normal"
}

graph_port_kind_name :: proc(kind: Graph_Port_Kind) -> string {
	return kind == .Exec ? "exec" : "data"
}

graph_direction_name :: proc(direction: Graph_Port_Direction) -> string {
	switch direction {
	case .Input:  return "Input"
	case .Output: return "Output"
	case .Both:   return "Both"
	}
	return "Input"
}

Graph_Load_Into :: proc(graph: ^Node_Graph, text: string, apply_view: bool) -> bool {
	temp: Node_Graph
	Graph_Defaults(&temp)
	if !Graph_Parse(&temp, text) {
		Graph_Clear_Contents(&temp)
		return false
	}
	for &node_type in temp.types {Graph_Merge_Type(graph, &node_type)}
	for &kind in temp.kinds {Graph_Merge_Kind(graph, &kind)}
	for entry in temp.type_colours {Graph_Set_Type_Colour(graph, entry.name, entry.colour)}
	if len(temp.kind_name) > 0 {
		if Graph_Find_Kind(graph, temp.kind_name) < 0 {
			log.warnf("node graph: the kind %q is missing; the graph is unrestricted", temp.kind_name)
			Graph_Set_Kind(graph, "")
		} else {
			Graph_Set_Kind(graph, temp.kind_name)
		}
	} else {
		Graph_Set_Kind(graph, "")
	}
	Graph_Free_Entities(graph)
	graph.nodes = temp.nodes
	graph.free_nodes = temp.free_nodes
	graph.wires = temp.wires
	graph.free_wires = temp.free_wires
	graph.regions = temp.regions
	graph.free_regions = temp.free_regions
	temp.nodes = nil
	temp.free_nodes = nil
	temp.wires = nil
	temp.free_wires = nil
	temp.regions = nil
	temp.free_regions = nil
	graph.metadata = temp.metadata
	temp.metadata = nil
	if apply_view {
		graph.scroll = temp.scroll
		graph.pan = temp.pan
		graph.zoom = temp.zoom
		graph.min_zoom = temp.min_zoom
		graph.max_zoom = temp.max_zoom
		graph.zoom_step = temp.zoom_step
		graph.grid_visible = temp.grid_visible
		graph.grid_size = temp.grid_size
		graph.grid_major = temp.grid_major
		graph.snap = temp.snap
	}
	if !(graph.zoom > 0) {graph.zoom = 1}
	//* The entities are new, so the geometry of the graph is thrown away.
	Graph_Geometry_Invalidate(graph)
	Graph_View_Sync(graph)
	graph.mode = .None
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
	graph.active_wire = INVALID_GRAPH_WIRE_ID
	graph.hover_node = INVALID_GRAPH_NODE_ID
	graph.hover_port = INVALID_GRAPH_PORT_ID
	graph.hover_port_node = INVALID_GRAPH_NODE_ID
	graph.hover_wire = INVALID_GRAPH_WIRE_ID
	graph.resize_node = INVALID_GRAPH_NODE_ID
	graph.menu_pending = false
	clear(&graph.dragging_nodes)
	clear(&graph.drag_starts)
	for i := 0; i < len(temp.types); i += 1 {Graph_Node_Type_Clear(&temp.types[i])}
	delete(temp.types)
	if temp.type_by_name != nil {
		for key in temp.type_by_name {delete(key)}
		delete(temp.type_by_name)
	}
	for &kind in temp.kinds {Graph_Kind_Clear(&kind)}
	delete(temp.kinds)
	temp.kinds = nil
	if temp.kind_by_name != nil {
		for key in temp.kind_by_name {delete(key)}
		delete(temp.kind_by_name)
		temp.kind_by_name = nil
	}
	if len(temp.kind_name) > 0 {delete(temp.kind_name)}
	temp.kind_name = ""
	for &entry in temp.type_colours {
		if len(entry.name) > 0 {delete(entry.name)}
	}
	delete(temp.type_colours)
	temp.type_colours = nil
	return true
}

Graph_Merge_Type :: proc(graph: ^Node_Graph, source: ^Graph_Node_Type) {
	index := Graph_Find_Type(graph, source.name)
	if index >= 0 {
		live := &graph.types[index]
		if len(live.name) > 0 {delete(live.name)}
		if len(live.category) > 0 {delete(live.category)}
		if len(live.description) > 0 {delete(live.description)}
		live.name = strings.clone(source.name)
		live.category = strings.clone(source.category)
		live.description = strings.clone(source.description)
		live.colour = source.colour
		live.default_size = source.default_size
		live.min_size = source.min_size
		live.max_size = source.max_size
		live.resizable = source.resizable
		live.collapsible = source.collapsible
		return
	}
	desc := Graph_Node_Type_Desc{
		name = source.name,
		category = source.category,
		description = source.description,
		colour = source.colour,
		default_size = source.default_size,
		min_size = source.min_size,
		max_size = source.max_size,
		resizable = source.resizable,
		collapsible = source.collapsible,
		inputs = source.inputs[:],
		outputs = source.outputs[:],
		config = source.config[:],
		policy = source.policy,
		configure = source.configure,
		user_data = source.user_data,
	}
	append(&graph.types, Graph_Node_Type{})
	index = len(graph.types) - 1
	if graph.type_by_name == nil {graph.type_by_name = make(map[string]int)}
	graph.type_by_name[strings.clone(source.name)] = index
	Graph_Node_Type_Apply(&graph.types[index], desc)
}

Graph_Merge_Kind :: proc(graph: ^Node_Graph, source: ^Graph_Kind) {
	Graph_Register_Kind(graph, Graph_Kind_Desc{
		name = source.name,
		description = source.description,
		execution = source.execution,
		allowed_nodes = source.allowed_nodes[:],
	})
}

Graph_Parse :: proc(graph: ^Node_Graph, text: string) -> bool {
	lines := strings.split_lines(text)
	defer delete(lines)
	have_graph := false
	version := 0
	node_ids := make(map[u32]Graph_Node_ID)
	defer delete(node_ids)
	port_ids := make(map[Graph_Port_Ref]Graph_Port_ID)
	defer delete(port_ids)
	for line, number in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" || trimmed[0] == '#' {continue}
		parsed, ok := graph_parse_line(trimmed)
		if !ok {
			log.warnf("node graph: the line %d is malformed", number + 1)
			return false
		}
		switch parsed.kind {
		case "graph":
			if !graph_parse_graph(graph, &parsed) {
				graph_line_destroy(&parsed)
				return false
			}
			version_value, has := graph_line_int(&parsed, "version")
			if !has {
				graph_line_destroy(&parsed)
				return false
			}
			version = version_value
			have_graph = true
		case "type":
			if !graph_parse_type(graph, &parsed) {
				graph_line_destroy(&parsed)
				return false
			}
		case "kind":
			if !graph_parse_kind(graph, &parsed) {
				graph_line_destroy(&parsed)
				return false
			}
		case "typecolour":
			if !graph_parse_type_colour(graph, &parsed) {
				graph_line_destroy(&parsed)
				return false
			}
		case "meta":
			if key, has := graph_line_string(&parsed, "key"); has {
				value, _ := graph_line_string(&parsed, "value")
				Graph_Metadata_Set(graph, key, value)
			}
		case "node":
			local, has := graph_line_int(&parsed, "id")
			if !has || local <= 0 {
				log.warnf("node graph: a node on line %d has no id", number + 1)
				graph_line_destroy(&parsed)
				return false
			}
			node_id, node_ok := graph_parse_node(graph, &parsed)
			if !node_ok {
				graph_line_destroy(&parsed)
				return false
			}
			node_ids[u32(local)] = node_id
		}
		graph_line_destroy(&parsed)
	}
	if !have_graph || version != GRAPH_FORMAT_VERSION {return false}
	for line, number in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" || trimmed[0] == '#' {continue}
		parsed, ok := graph_parse_line(trimmed)
		if !ok {continue}
		if parsed.kind == "port" {
			if message := graph_parse_port(graph, &parsed, &node_ids, &port_ids); message != "" {
				log.warnf("node graph: the port on line %d was skipped: %s", number + 1, message)
			}
		}
		graph_line_destroy(&parsed)
	}
	for line, number in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" || trimmed[0] == '#' {continue}
		parsed, ok := graph_parse_line(trimmed)
		if !ok {continue}
		if parsed.kind == "config" {
			if message := graph_parse_config(graph, &parsed, &node_ids); message != "" {
				log.warnf("node graph: the config on line %d was skipped: %s", number + 1, message)
			}
		}
		graph_line_destroy(&parsed)
	}
	for line, number in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" || trimmed[0] == '#' {continue}
		parsed, ok := graph_parse_line(trimmed)
		if !ok {continue}
		if parsed.kind == "wire" {
			if message := graph_parse_wire(graph, &parsed, &node_ids, &port_ids); message != "" {
				log.warnf("node graph: the wire on line %d was skipped: %s", number + 1, message)
			}
		}
		if parsed.kind == "region" {
			if message := graph_parse_region(graph, &parsed); message != "" {
				log.warnf("node graph: the region on line %d was skipped: %s", number + 1, message)
			}
		}
		graph_line_destroy(&parsed)
	}
	for node in graph.nodes {
		if !node.alive || node.type_name == "" {continue}
		if Graph_Find_Type(graph, node.type_name) < 0 {
			log.warnf("node graph: the type %q is missing; the node keeps its ports", node.type_name)
		}
	}
	return true
}

graph_parse_graph :: proc(graph: ^Node_Graph, line: ^Graph_Line) -> bool {
	if kind_name, has := graph_line_string(line, "kind"); has {
		if len(graph.kind_name) > 0 {delete(graph.kind_name)}
		graph.kind_name = strings.clone(kind_name)
	}
	if zoom, has := graph_line_float(line, "zoom"); has && zoom > 0 {graph.zoom = zoom}
	if pan, has := graph_line_vec2(line, "pan"); has {
		graph.pan = pan
		graph.scroll = Core.Vec2{-pan.x / graph.zoom, -pan.y / graph.zoom}
	}
	if grid, has := graph_line_bool(line, "grid"); has {graph.grid_visible = grid}
	if size, has := graph_line_float(line, "grid_size"); has && size > 0 {graph.grid_size = size}
	if major, has := graph_line_float(line, "grid_major"); has && major > 0 {graph.grid_major = major}
	if snap, has := graph_line_bool(line, "snap"); has {graph.snap = snap}
	return true
}

graph_parse_type_colour :: proc(graph: ^Node_Graph, line: ^Graph_Line) -> bool {
	name, has := graph_line_string(line, "name")
	if !has || name == "" {return false}
	colour, has_colour := graph_line_colour(line, "colour")
	if !has_colour {return false}
	return Graph_Set_Type_Colour(graph, name, colour)
}

graph_parse_kind_allowed :: proc(text: string) -> [dynamic]string {
	allowed: [dynamic]string
	start := 0
	for index := 0; index <= len(text); index += 1 {
		if index < len(text) && text[index] != ',' {continue}
		name := strings.trim_space(text[start:index])
		if name != "" {append(&allowed, name)}
		start = index + 1
	}
	return allowed
}

graph_parse_kind :: proc(graph: ^Node_Graph, line: ^Graph_Line) -> bool {
	name, has := graph_line_string(line, "name")
	if !has || name == "" {return false}
	desc := Graph_Kind_Desc{
		name = name,
		description = graph_line_string_or(line, "description", ""),
		execution = graph_line_bool_or(line, "execution", false),
	}
	if allowed_text, has_allowed := graph_line_string(line, "allowed"); has_allowed {
		allowed := graph_parse_kind_allowed(allowed_text)
		desc.allowed_nodes = allowed[:]
		registered := Graph_Register_Kind(graph, desc)
		delete(allowed)
		return registered >= 0
	}
	return Graph_Register_Kind(graph, desc) >= 0
}

graph_parse_type :: proc(graph: ^Node_Graph, line: ^Graph_Line) -> bool {
	name, has := graph_line_string(line, "name")
	if !has || name == "" {return false}
	node_type: Graph_Node_Type
	node_type.name = strings.clone(name)
	node_type.category = strings.clone(graph_line_string_or(line, "category", ""))
	node_type.description = strings.clone(graph_line_string_or(line, "description", ""))
	node_type.colour = graph_line_colour_or(line, "colour", Core.Colour{0.2, 0.25, 0.32, 1})
	node_type.default_size = graph_line_vec2_or(line, "default_size", Core.Vec2{NODE_WIDTH, NODE_HEIGHT})
	node_type.min_size = graph_line_vec2_or(line, "min_size", Core.Vec2{NODE_MIN_WIDTH, NODE_MIN_HEIGHT})
	node_type.max_size = graph_line_vec2_or(line, "max_size", Core.Vec2{NODE_MAX_WIDTH, NODE_MAX_HEIGHT})
	node_type.resizable = graph_line_bool_or(line, "resizable", true)
	node_type.collapsible = graph_line_bool_or(line, "collapsible", true)
	node_type.policy.add_inputs = graph_line_bool_or(line, "add_inputs", false)
	node_type.policy.add_outputs = graph_line_bool_or(line, "add_outputs", false)
	node_type.policy.max_inputs = i32(graph_line_int_or(line, "max_inputs", -1))
	node_type.policy.max_outputs = i32(graph_line_int_or(line, "max_outputs", -1))
	node_type.policy.input_type = strings.clone(graph_line_string_or(line, "input_type", ""))
	node_type.policy.output_type = strings.clone(graph_line_string_or(line, "output_type", ""))
	node_type.policy.input_prefix = strings.clone(graph_line_string_or(line, "input_prefix", ""))
	node_type.policy.output_prefix = strings.clone(graph_line_string_or(line, "output_prefix", ""))
	index := Graph_Find_Type(graph, name)
	if index < 0 {
		index = len(graph.types)
		append(&graph.types, Graph_Node_Type{})
		if graph.type_by_name == nil {graph.type_by_name = make(map[string]int)}
		graph.type_by_name[strings.clone(name)] = index
	} else {
		Graph_Node_Type_Clear(&graph.types[index])
	}
	graph.types[index] = node_type
	return true
}

graph_parse_node :: proc(graph: ^Node_Graph, line: ^Graph_Line) -> (Graph_Node_ID, bool) {
	local, has := graph_line_int(line, "id")
	if !has || local <= 0 {return INVALID_GRAPH_NODE_ID, false}
	node := Graph_Node_Slot(graph)
	node.kind = graph_parse_node_kind(graph_line_string_or(line, "kind", "normal"))
	node.type_name = strings.clone(graph_line_string_or(line, "type", ""))
	node.title = strings.clone(graph_line_string_or(line, "title", ""))
	node.reroute_input_type = strings.clone(graph_line_string_or(line, "input_type", ""))
	node.reroute_output_type = strings.clone(graph_line_string_or(line, "output_type", ""))
	if pos, has := graph_line_vec2(line, "pos"); has {node.pos = pos}
	if size, has := graph_line_vec2(line, "size"); has && (size.x > 0 || size.y > 0) {node.size = size}
	node.short_title = graph_string_copy(graph_line_string_or(line, "short", ""))
	if collapsed, has := graph_line_bool(line, "collapsed"); has {node.collapsed = collapsed}
	if colour, has := graph_line_colour(line, "colour"); has {node.colour = colour}
	if node.kind == .Reroute_Dot {
		node.title = ""
		node.resizable = false
		node.collapsible = false
		node.size = Core.Vec2{REROUTE_DOT_SIZE, REROUTE_DOT_SIZE}
		node.min_size = node.size
		node.max_size = node.size
	} else if node.kind == .Reroute_Convert {
		node.title = ""
		node.resizable = false
		node.collapsible = false
		if node.size.x <= 0 || node.size.y <= 0 {
			node.size = Core.Vec2{REROUTE_CONVERT_WIDTH, REROUTE_CONVERT_HEIGHT}
		}
		node.min_size = node.size
		node.max_size = node.size
	}
	if node.colour.a <= 0 {node.colour = Core.Colour{0.18, 0.20, 0.25, 1}}
	if index := Graph_Find_Type(graph, node.type_name); index >= 0 {
		node_type := &graph.types[index]
		if node.title == "" {node.title = strings.clone(node_type.name)}
		if node.colour.a <= 0 {node.colour = node_type.colour}
		node.min_size = node_type.min_size
		node.max_size = node_type.max_size
		node.resizable = true
		node.collapsible = true
	}
	if node.title == "" {node.title = fmt.aprintf("Node %d", local)}
	return node.id, true
}

graph_parse_port :: proc(graph: ^Node_Graph, line: ^Graph_Line, node_ids: ^map[u32]Graph_Node_ID, port_ids: ^map[Graph_Port_Ref]Graph_Port_ID) -> string {
	node_local, has_node := graph_line_int(line, "node")
	if !has_node {return "the port has no node"}
	port_local, has_port := graph_line_int(line, "id")
	if !has_port {return "the port has no id"}
	node_id, found := node_ids[u32(node_local)]
	if !found {return "the node of the port is missing"}
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return "the node of the port is missing"}
	capacity_value: i32
	has_capacity := false
	if capacity, found := graph_line_int(line, "capacity"); found {
		capacity_value = i32(capacity)
		has_capacity = true
	}
	desc := Graph_Port_Desc{
		name = graph_line_string_or(line, "name", ""),
		direction = graph_parse_direction(graph_line_string_or(line, "direction", "Input")),
		port_kind = graph_parse_port_kind(graph_line_string_or(line, "port_kind", "data")),
		type = graph_line_string_or(line, "type", ""),
		capacity = capacity_value,
		tooltip = graph_line_string_or(line, "tooltip", ""),
		visible = graph_line_bool_or(line, "visible", true),
	}
	desc.colour = graph_line_colour_or(line, "colour", Core.Colour{})
	if kind_name, has := graph_line_string(line, "default_kind"); has {
		if raw, has_value := graph_line_string(line, "default"); has_value {
			value, ok := graph_parse_value(kind_name, raw)
			if ok {desc.default_value = value}
		}
	}
	port_id := Graph_Add_Port(node, desc)
	if has_capacity && capacity_value == 0 {
		if port := Node_Graph_Port_Of(graph, node.id, port_id); port != nil {port.capacity = 0}
	}
	Graph_Value_Free(desc.default_value)
	port_ids[Graph_Port_Ref{u32(node_local), u32(port_local)}] = port_id
	return ""
}

graph_parse_config :: proc(graph: ^Node_Graph, line: ^Graph_Line, node_ids: ^map[u32]Graph_Node_ID) -> string {
	node_local, has := graph_line_int(line, "node")
	if !has {return "the config has no node"}
	key, has_key := graph_line_string(line, "key")
	if !has_key {return "the config has no key"}
	kind_name, has_kind := graph_line_string(line, "kind")
	if !has_kind {return "the config has no kind"}
	raw, has_value := graph_line_string(line, "value")
	if !has_value {return "the config has no value"}
	node_id, found := node_ids[u32(node_local)]
	if !found {return "the node of the config is missing"}
	node := Node_Graph_Node_Of(graph, node_id)
	if node == nil {return "the node of the config is missing"}
	value, ok := graph_parse_value(kind_name, raw)
	if !ok {return "the config value is invalid"}
	Graph_Set_Config_Value(graph, node_id, key, value)
	for &entry in node.config {
		if entry.key == key {entry.read_only = graph_line_bool_or(line, "read_only", false)}
	}
	Graph_Value_Free(value)
	return ""
}

graph_parse_wire :: proc(graph: ^Node_Graph, line: ^Graph_Line, node_ids: ^map[u32]Graph_Node_ID, port_ids: ^map[Graph_Port_Ref]Graph_Port_ID) -> string {
	from_node_local, has_from_node := graph_line_int(line, "from_node")
	if !has_from_node {return "the wire has no source node"}
	from_port_local, has_from_port := graph_line_int(line, "from_port")
	if !has_from_port {return "the wire has no source port"}
	to_node_local, has_to_node := graph_line_int(line, "to_node")
	if !has_to_node {return "the wire has no target node"}
	to_port_local, has_to_port := graph_line_int(line, "to_port")
	if !has_to_port {return "the wire has no target port"}
	from_node, found_from_node := node_ids[u32(from_node_local)]
	if !found_from_node {return "the source node is missing"}
	to_node, found_to_node := node_ids[u32(to_node_local)]
	if !found_to_node {return "the target node is missing"}
	from_port, found_from_port := port_ids[Graph_Port_Ref{u32(from_node_local), u32(from_port_local)}]
	if !found_from_port {return "the source port is missing"}
	to_port, found_to_port := port_ids[Graph_Port_Ref{u32(to_node_local), u32(to_port_local)}]
	if !found_to_port {return "the target port is missing"}
	colour := graph_line_colour_or(line, "colour", Core.Colour{})
	if Graph_Connect(graph, from_node, from_port, to_node, to_port, colour).index == 0 {return "the wire is not valid"}
	return ""
}

//* Reads the region of a saved line.
graph_parse_region :: proc(graph: ^Node_Graph, line: ^Graph_Line) -> string {
	title := graph_line_string_or(line, "title", "")
	pos := graph_line_vec2_or(line, "pos", Core.Vec2{})
	size := graph_line_vec2_or(line, "size", Core.Vec2{320, 200})
	colour := graph_line_colour_or(line, "colour", GRAPH_REGION_COLOURS[0])
	move_contained := graph_line_bool_or(line, "move_contained", true)
	region_id := Graph_Add_Region(graph, title, pos, size)
	if region_id.index == 0 {return "the region could not be made"}
	Graph_Set_Region_Colour(graph, region_id, colour)
	Graph_Set_Region_Move_Contained(graph, region_id, move_contained)
	return ""
}

graph_parse_value :: proc(kind_name, raw: string) -> (Graph_Value, bool) {	switch kind_name {
	case "Bool":
		if value, ok := graph_parse_bool(raw); ok {return Graph_Value(value), true}
	case "Int":
		if value, ok := strconv.parse_int(raw); ok {return Graph_Value(i32(value)), true}
	case "Float":
		if value, ok := strconv.parse_f32(raw); ok {return Graph_Value(value), true}
	case "Vec2":
		values: [2]f32
		if graph_parse_floats(raw, values[:]) == 2 {return Graph_Value(Core.Vec2{values[0], values[1]}), true}
	case "Vec3":
		values: [3]f32
		if graph_parse_floats(raw, values[:]) == 3 {return Graph_Value(Core.Vec3{values[0], values[1], values[2]}), true}
	case "Colour":
		values: [4]f32
		if graph_parse_floats(raw, values[:]) == 4 {return Graph_Value(Core.Colour{values[0], values[1], values[2], values[3]}), true}
	case "String":
		return Graph_Value(strings.clone(raw)), true
	}
	return nil, false
}

graph_parse_node_kind :: proc(value: string) -> Graph_Node_Kind {
	switch value {
	case "reroute":    return .Reroute_Dot
	case "conversion": return .Reroute_Convert
	}
	return .Normal
}

graph_parse_port_kind :: proc(value: string) -> Graph_Port_Kind {
	return value == "exec" ? .Exec : .Data
}

graph_parse_direction :: proc(value: string) -> Graph_Port_Direction {
	switch value {
	case "Output": return .Output
	case "Both":   return .Both
	}
	return .Input
}

graph_parse_bool :: proc(value: string) -> (bool, bool) {
	switch value {
	case "1", "true", "True":  return true, true
	case "0", "false", "False": return false, true
	}
	return false, false
}

graph_parse_floats :: proc(text: string, out: []f32) -> int {
	count := 0
	start := 0
	for i := 0; i <= len(text); i += 1 {
		if i < len(text) && text[i] != ',' {continue}
		part := strings.trim_space(text[start:i])
		if part != "" {
			if value, ok := strconv.parse_f32(part); ok {
				if count < len(out) {out[count] = value}
			} else {
				return -1
			}
			count += 1
		}
		start = i + 1
	}
	return count
}

graph_parse_line :: proc(line: string) -> (Graph_Line, bool) {
	parsed: Graph_Line
	i := 0
	for i < len(line) && graph_is_space(line[i]) {i += 1}
	start := i
	for i < len(line) && !graph_is_space(line[i]) {i += 1}
	parsed.kind = line[start:i]
	if parsed.kind == "" {return parsed, false}
	for i < len(line) {
		for i < len(line) && graph_is_space(line[i]) {i += 1}
		if i >= len(line) {break}
		key_start := i
		for i < len(line) && line[i] != '=' && !graph_is_space(line[i]) {i += 1}
		key := line[key_start:i]
		for i < len(line) && graph_is_space(line[i]) {i += 1}
		if i >= len(line) || line[i] != '=' {
			graph_line_destroy(&parsed)
			return parsed, false
		}
		i += 1
		for i < len(line) && graph_is_space(line[i]) {i += 1}
		value := ""
		if i < len(line) && line[i] == '"' {
			i += 1
			decoded, next, ok := graph_parse_quoted(line, i)
			if !ok {
				graph_line_destroy(&parsed)
				return parsed, false
			}
			value = decoded
			i = next
			append(&parsed.attrs, Graph_Line_Attr{key = strings.clone(key), value = value})
		} else {
			value_start := i
			for i < len(line) && !graph_is_space(line[i]) {i += 1}
			append(&parsed.attrs, Graph_Line_Attr{key = strings.clone(key), value = strings.clone(line[value_start:i])})
		}
	}
	return parsed, true
}

graph_parse_quoted :: proc(text: string, start: int) -> (value: string, next: int, ok: bool) {
	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, 32, context.allocator); err != nil {return "", start, false}
	i := start
	for i < len(text) {
		c := text[i]
		if c == '"' {
			value = strings.clone(strings.to_string(builder))
			strings.builder_destroy(&builder)
			return value, i + 1, true
		}
		if c == '\\' && i + 1 < len(text) {
			i += 1
			switch text[i] {
			case 'n': strings.write_byte(&builder, '\n')
			case 't': strings.write_byte(&builder, '\t')
			case 'r': strings.write_byte(&builder, '\r')
			case '"': strings.write_byte(&builder, '"')
			case '\\': strings.write_byte(&builder, '\\')
			case: strings.write_byte(&builder, text[i])
			}
			i += 1
			continue
		}
		strings.write_byte(&builder, c)
		i += 1
	}
	strings.builder_destroy(&builder)
	return "", start, false
}

graph_line_destroy :: proc(line: ^Graph_Line) {
	for &attr in line.attrs {
		if len(attr.key) > 0 {delete(attr.key)}
		if len(attr.value) > 0 {delete(attr.value)}
	}
	delete(line.attrs)
	line.attrs = nil
}

graph_line_string :: proc(line: ^Graph_Line, key: string) -> (string, bool) {
	for attr in line.attrs {
		if attr.key == key {return attr.value, true}
	}
	return "", false
}

graph_line_float :: proc(line: ^Graph_Line, key: string) -> (f32, bool) {
	value, found := graph_line_string(line, key)
	if !found {return 0, false}
	return strconv.parse_f32(value)
}

graph_line_int :: proc(line: ^Graph_Line, key: string) -> (int, bool) {
	value, found := graph_line_string(line, key)
	if !found {return 0, false}
	return strconv.parse_int(value)
}

graph_line_bool :: proc(line: ^Graph_Line, key: string) -> (bool, bool) {
	value, found := graph_line_string(line, key)
	if !found {return false, false}
	return graph_parse_bool(value)
}

graph_line_vec2 :: proc(line: ^Graph_Line, key: string) -> (Core.Vec2, bool) {
	value, found := graph_line_string(line, key)
	if !found {return {}, false}
	values: [2]f32
	if graph_parse_floats(value, values[:]) != 2 {return {}, false}
	return Core.Vec2{values[0], values[1]}, true
}

graph_line_colour :: proc(line: ^Graph_Line, key: string) -> (Core.Colour, bool) {
	value, found := graph_line_string(line, key)
	if !found {return {}, false}
	values: [4]f32
	if graph_parse_floats(value, values[:]) != 4 {return {}, false}
	return Core.Colour{values[0], values[1], values[2], values[3]}, true
}

graph_line_string_or :: proc(line: ^Graph_Line, key: string, default: string) -> string {
	value, found := graph_line_string(line, key)
	return found ? value : default
}

graph_line_float_or :: proc(line: ^Graph_Line, key: string, default: f32) -> f32 {
	value, found := graph_line_float(line, key)
	return found ? value : default
}

graph_line_int_or :: proc(line: ^Graph_Line, key: string, default: int) -> int {
	value, found := graph_line_int(line, key)
	return found ? value : default
}

graph_line_bool_or :: proc(line: ^Graph_Line, key: string, default: bool) -> bool {
	value, found := graph_line_bool(line, key)
	return found ? value : default
}

graph_line_vec2_or :: proc(line: ^Graph_Line, key: string, default: Core.Vec2) -> Core.Vec2 {
	value, found := graph_line_vec2(line, key)
	return found ? value : default
}

graph_line_colour_or :: proc(line: ^Graph_Line, key: string, default: Core.Colour) -> Core.Colour {
	value, found := graph_line_colour(line, key)
	return found ? value : default
}

graph_is_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}
