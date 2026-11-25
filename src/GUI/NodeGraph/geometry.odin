package NodeGraph

import Core "../Core"
import "core:math"
import "core:strings"

NODE_GRAPH_MIN_ZOOM :: 0.25
NODE_GRAPH_MAX_ZOOM :: 4.0
NODE_GRAPH_ZOOM_STEP :: 1.1
NODE_GRAPH_GRID_SIZE :: 20
NODE_GRAPH_GRID_MAJOR :: 4

NODE_WIDTH :: 140
NODE_HEIGHT :: 56
NODE_MIN_WIDTH :: 96
NODE_MIN_HEIGHT :: 40
NODE_MAX_WIDTH :: 1200
NODE_MAX_HEIGHT :: 1200
NODE_TITLE_HEIGHT :: 24
NODE_PORT_SIZE :: 10
NODE_PORT_SPACING :: 18
WIRE_WIDTH :: 2

//* The room below the last row of a node.
GRAPH_NODE_BODY_PADDING :: 4

//* The width of a character, as a share of the font size. The real font
//* measures a little wider; the estimate is only used where the font is not
//* available, such as the chips of a collapsed node.
GRAPH_CHAR_WIDTH :: 0.58

Graph_Wire_Path :: struct {
	points: [16]Core.Vec2,
	count:  int,
}

//* Throws the cached geometry away. Every change that moves a node, a port
//* or a wire ends here, so the next frame rebuilds what it needs.
Graph_Geometry_Invalidate :: proc(graph: ^Node_Graph) {
	if graph == nil {return}
	graph.cache_valid = false
	graph.cache.valid = false
	graph.cache.index.valid = false
	graph.geometry_epoch += 1
}

//* == Rows ==

//* What a row of a node body holds.
Graph_Node_Row_Kind :: enum {
	Pin,
	Config,
}

Graph_Node_Row :: struct {
	kind:         Graph_Node_Row_Kind,
	port_id:      Graph_Port_ID,
	port_index:   int,
	config_index: int,
	side:         Graph_Port_Direction,
	row:          int,
	text:         string,
}

//* The rows of a node body, in the order they are drawn. The measurement,
//* the drawing and the hit testing all read this one list.
Graph_Node_Layout :: struct {
	rows:        [48]Graph_Node_Row,
	count:       int,
	input_rows:  int,
	output_rows: int,
	config_rows: int,
	height:      f32,
}

//* The text a pin row shows: the type of the pin, never its name. An empty
//* type and a wildcard type both read as `any`.
Graph_Port_Type_Text :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> string {
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if port == nil {return "any"}
	if port.port_kind == .Exec {return "exec"}
	if port.type == "" {return "any"}
	if graph_type_name_equal(port.type, "wildcard") {return "any"}
	return port.type
}

//* The type of the first data pin of a node, used to hide a configuration
//* entry that repeats what the pin already says.
Graph_Node_Data_Type :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> string {
	if node == nil {return ""}
	for &port in node.ports {
		if !port.alive || !port.visible {continue}
		if port.port_kind != .Data {continue}
		if port.type == "" {continue}
		return port.type
	}
	return ""
}

//* The configuration an editor shows on the body of a node. A name that is
//* already the title is left out, a type that the data pin already shows is
//* left out, and an entry without a value says nothing.
Graph_Config_Relevant :: proc(graph: ^Node_Graph, node: ^Graph_Node, entry: Graph_Config_Entry) -> bool {
	if node == nil {return false}
	if entry.key == "name" {
		if name, ok := entry.value.(string); ok && name == node.title {return false}
	}
	if entry.key == "type" {
		if type_name, ok := entry.value.(string); ok && type_name == Graph_Node_Data_Type(graph, node) {return false}
	}
	#partial switch v in entry.value {
	case string:
		if len(v) == 0 {return false}
	}
	return true
}

Graph_Node_Config_Rows :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> int {
	count := 0
	for &entry in node.config {
		if Graph_Config_Relevant(graph, node, entry) {count += 1}
	}
	return count
}

//* Collects the rows of a node body: the pins of both sides and the
//* configuration entries that add information.
Graph_Node_Rows :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Graph_Node_Layout {
	layout: Graph_Node_Layout
	if node == nil {return layout}
	metrics := Graph_Metrics_Of(graph)

	input_row := 0
	output_row := 0
	for i in 0 ..< len(node.ports) {
		port := &node.ports[i]
		if !port.alive || !port.visible {continue}
		if layout.count >= len(layout.rows) {break}
		side := Graph_Port_Direction_Side(port)
		row := Graph_Node_Row{
			kind = .Pin,
			port_id = port.id,
			port_index = i,
			side = side,
			text = Graph_Port_Type_Text(graph, node.id, port.id),
		}
		if side == .Input {
			row.row = input_row
			input_row += 1
		} else {
			row.row = output_row
			output_row += 1
		}
		layout.rows[layout.count] = row
		layout.count += 1
	}
	layout.input_rows = input_row
	layout.output_rows = output_row

	for i in 0 ..< len(node.config) {
		if layout.count >= len(layout.rows) {break}
		entry := node.config[i]
		if !Graph_Config_Relevant(graph, node, entry) {continue}
		layout.rows[layout.count] = Graph_Node_Row{
			kind = .Config,
			config_index = i,
			row = layout.config_rows,
		}
		layout.config_rows += 1
		layout.count += 1
	}

	rows := max(layout.input_rows, layout.output_rows) + layout.config_rows
	layout.height = metrics.title_height + f32(rows) * metrics.port_spacing + GRAPH_NODE_BODY_PADDING
	return layout
}

//* == Geometry ==

//* The narrowest a node may become when its width follows its content.
GRAPH_NODE_MIN_CONTENT_WIDTH :: 44.0

//* The room a row keeps on both sides.
GRAPH_NODE_ROW_INSET :: 12.0

//* The room between the type of an input and the type of an output.
GRAPH_NODE_ROW_GAP :: 10.0

//* The number of characters a value takes, for the width of a node.
graph_value_chars :: proc(value: Graph_Value) -> int {
	#partial switch v in value {
	case bool:
		return v ? 4 : 5
	case i32, f32:
		return 6
	case string:
		return len(v) + 2
	case Core.Vec2:
		return 11
	case Core.Vec3:
		return 16
	case Core.Colour:
		return 21
	}
	return 0
}

//* The width a node asks for: the title with room for the collapse button,
//* the widest row of pin types and the widest configuration row. `size.x`
//* is a minimum, so a node that was resized keeps its width.
Graph_Node_Width :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> f32 {
	metrics := Graph_Metrics_Of(graph)
	//* A reroute keeps the size it was given, so a dot stays a circle.
	if node.kind == .Reroute_Dot || node.kind == .Reroute_Convert {
		return node.size.x
	}

	wide := f32(0)
	if node.collapsed {
		//* A collapsed node carries its title alone, so its width follows
		//* the title and the button beside it.
		label := len(node.short_title) > 0 ? node.short_title : node.title
		wide = f32(len(label)) * metrics.title_font_size * GRAPH_CHAR_WIDTH + GRAPH_NODE_ROW_INSET * 2
		if node.collapsible {wide += metrics.badge_height + 6}
		return clamp(max(wide, node.size.x), GRAPH_NODE_MIN_CONTENT_WIDTH, node.max_size.x)
	}

	wide = f32(len(node.title)) * metrics.title_font_size * GRAPH_CHAR_WIDTH + GRAPH_NODE_ROW_INSET * 2
	if node.collapsible {wide += metrics.badge_height + 6}

	input_width := f32(0)
	output_width := f32(0)
	for &port in node.ports {
		if !port.alive || !port.visible {continue}
		text := Graph_Port_Type_Text(graph, node.id, port.id)
		width := f32(len(text)) * metrics.pin_font_size * GRAPH_CHAR_WIDTH
		if Graph_Port_Direction_Side(&port) == .Input {
			input_width = max(input_width, width)
		} else {
			output_width = max(output_width, width)
		}
	}
	if input_width > 0 || output_width > 0 {
		wide = max(wide, input_width + output_width + GRAPH_NODE_ROW_INSET * 2 + GRAPH_NODE_ROW_GAP)
	}

	for &entry in node.config {
		if !Graph_Config_Relevant(graph, node, entry) {continue}
		key_width := f32(len(entry.key)) * metrics.config_font_size * GRAPH_CHAR_WIDTH
		value_width := f32(graph_value_chars(entry.value)) * metrics.config_font_size * GRAPH_CHAR_WIDTH
		wide = max(wide, key_width + value_width + GRAPH_NODE_ROW_INSET * 2 + GRAPH_NODE_ROW_GAP)
	}

	return clamp(max(wide, node.size.x), GRAPH_NODE_MIN_CONTENT_WIDTH, node.max_size.x)
}

Graph_Node_Height :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> f32 {
	metrics := Graph_Metrics_Of(graph)
	if node.kind == .Reroute_Dot {return node.size.y}
	if node.kind == .Reroute_Convert {return node.size.y}
	if node.collapsed {return metrics.title_height}
	rows := Graph_Node_Config_Rows(graph, node)
	inputs, outputs := 0, 0
	for &port in node.ports {
		if !port.alive || !port.visible {continue}
		if Graph_Port_Direction_Side(&port) == .Input {inputs += 1} else {outputs += 1}
	}
	rows += max(inputs, outputs)
	return max(node.size.y, metrics.title_height + f32(rows) * metrics.port_spacing + GRAPH_NODE_BODY_PADDING)
}

Graph_Node_Rect :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Core.Rect {
	return Core.Rect{
		x = node.pos.x,
		y = node.pos.y,
		w = Graph_Node_Width(graph, node),
		h = Graph_Node_Height(graph, node),
	}
}

Graph_Port_Position :: proc(graph: ^Node_Graph, node: ^Graph_Node, port_id: Graph_Port_ID) -> Core.Vec2 {
	port := Node_Graph_Port_Of(graph, node.id, port_id)
	if port == nil {return node.pos}
	metrics := Graph_Metrics_Of(graph)
	if node.kind == .Reroute_Dot {
		return Core.Vec2{node.pos.x + node.size.x * 0.5, node.pos.y + node.size.y * 0.5}
	}
	if node.kind == .Reroute_Convert {
		if port.direction == .Output {
			return Core.Vec2{node.pos.x + node.size.x, node.pos.y + node.size.y * 0.5}
		}
		inputs := 0
		row := 0
		for &other in node.ports {
			if !other.alive || !other.visible || other.direction != .Input {continue}
			if other.id == port_id {row = inputs}
			inputs += 1
		}
		span := f32(max(inputs, 1) - 1) * metrics.port_spacing
		y := node.pos.y + node.size.y * 0.5 - span * 0.5 + f32(row) * metrics.port_spacing
		return Core.Vec2{node.pos.x, y}
	}
	width := Graph_Node_Width(graph, node)
	if node.collapsed {
		//* A collapsed node keeps its title, so its pins sit on its edges,
		//* spread down the header.
		side := Graph_Port_Direction_Side(port)
		count := 0
		index := 0
		for &other in node.ports {
			if !other.alive || !other.visible {continue}
			if Graph_Port_Direction_Side(&other) != side {continue}
			if other.id == port_id {index = count}
			count += 1
		}
		x := node.pos.x
		if side == .Output {x += width}
		span := (f32(index) + 0.5) / f32(max(count, 1))
		return Core.Vec2{x, node.pos.y + metrics.title_height * span}
	}
	x := node.pos.x
	if Graph_Port_Direction_Side(port) == .Output {x += width}
	row := 0
	side := Graph_Port_Direction_Side(port)
	for i in 0 ..< len(node.ports) {
		other := &node.ports[i]
		if !other.alive || !other.visible {continue}
		if other.id == port_id {break}
		if Graph_Port_Direction_Side(other) == side {row += 1}
	}
	y := node.pos.y + metrics.title_height + f32(row) * metrics.port_spacing + metrics.port_size * 0.5
	return Core.Vec2{x, y}
}

Graph_Rect_Contains :: proc(rect: Core.Rect, x, y: f32) -> bool {
	return x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h
}

//* The scratch of a query: the candidates of the index are written here.
graph_index_scratch :: proc(scratch: ^[dynamic]int, size: int) -> []int {
	if len(scratch^) < size {resize(&scratch^, size)}
	return scratch^[:size]
}

Graph_Node_At_Position :: proc(graph: ^Node_Graph, pos: Core.Vec2) -> Graph_Node_ID {
	found := INVALID_GRAPH_NODE_ID
	Graph_Geometry_Ensure(graph)
	scratch := graph_index_scratch(&graph.node_scratch, len(graph.nodes))
	count := Graph_Index_Query_Nodes(graph, &graph.cache.index, Core.Rect{x = pos.x, y = pos.y, w = 0, h = 0}, scratch)
	for i in 0 ..< count {
		node := &graph.nodes[scratch[i]]
		if !node.alive {continue}
		if Graph_Rect_Contains(Graph_Node_Rect(graph, node), pos.x, pos.y) {found = node.id}
	}
	return found
}

//* The port under a pointer. A collapsed node keeps its pins on its edges,
//* so they are always there to be grabbed.
Graph_Port_At_Position :: proc(graph: ^Node_Graph, pos: Core.Vec2, tolerance: f32) -> (Graph_Node_ID, Graph_Port_ID) {
	found_node := INVALID_GRAPH_NODE_ID
	found_port := INVALID_GRAPH_PORT_ID
	best := tolerance
	Graph_Geometry_Ensure(graph)
	scratch := graph_index_scratch(&graph.node_scratch, len(graph.nodes))
	query := Core.Rect{x = pos.x - tolerance, y = pos.y - tolerance, w = tolerance * 2, h = tolerance * 2}
	count := Graph_Index_Query_Nodes(graph, &graph.cache.index, query, scratch)
	for i in 0 ..< count {
		node := &graph.nodes[scratch[i]]
		if !node.alive {continue}
		for port in node.ports {
			if !port.alive || !port.visible {continue}
			centre := Graph_Port_Position_Of(graph, node, port.id)
			dx := pos.x - centre.x
			dy := pos.y - centre.y
			distance := math.sqrt(dx * dx + dy * dy)
			if distance <= best {
				best = distance
				found_node = node.id
				found_port = port.id
			}
		}
	}
	return found_node, found_port
}

Graph_Point_Segment_Distance :: proc(p, a, b: Core.Vec2) -> f32 {
	dx := b.x - a.x
	dy := b.y - a.y
	if dx == 0 && dy == 0 {return math.sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y))}
	t := ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
	t = clamp(t, 0, 1)
	x := a.x + dx * t
	y := a.y + dy * t
	return math.sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y))
}

Graph_Wire_Candidate :: struct {
	points: [16]Core.Vec2,
	count:  int,
	length: f32,
}

wire_segment_hits_rect :: proc(a, b: Core.Vec2, rect: Core.Rect) -> bool {
	min_x := min(a.x, b.x)
	max_x := max(a.x, b.x)
	min_y := min(a.y, b.y)
	max_y := max(a.y, b.y)
	if a.x == b.x {
		return a.x > rect.x && a.x < rect.x + rect.w && max_y > rect.y && min_y < rect.y + rect.h
	}
	if a.y == b.y {
		return a.y > rect.y && a.y < rect.y + rect.h && max_x > rect.x && min_x < rect.x + rect.w
	}
	return false
}

wire_path_clear :: proc(points: []Core.Vec2, count: int, source_rect, target_rect: Core.Rect) -> bool {
	if count < 2 {return true}
	for index in 0 ..< count - 1 {
		if index == 0 || index == count - 2 {continue}
		if wire_segment_hits_rect(points[index], points[index + 1], source_rect) {return false}
		if wire_segment_hits_rect(points[index], points[index + 1], target_rect) {return false}
	}
	return true
}

wire_candidate_length :: proc(points: []Core.Vec2, count: int) -> f32 {
	length := f32(0)
	if count < 2 {return length}
	for index in 0 ..< count - 1 {
		dx := abs(points[index + 1].x - points[index].x)
		dy := abs(points[index + 1].y - points[index].y)
		length += dx + dy
	}
	return length
}

wire_candidate_make :: proc(
	a, b: Core.Vec2,
	source_x, target_x, lane_y: f32,
) -> Graph_Wire_Candidate {
	candidate: Graph_Wire_Candidate
	candidate.points[0] = a
	candidate.points[1] = Core.Vec2{source_x, a.y}
	candidate.points[2] = Core.Vec2{source_x, lane_y}
	candidate.points[3] = Core.Vec2{target_x, lane_y}
	candidate.points[4] = Core.Vec2{target_x, b.y}
	candidate.points[5] = b
	candidate.count = 6
	candidate.length = wire_candidate_length(candidate.points[:], candidate.count)
	return candidate
}

Graph_Build_Wire_Path :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> Graph_Wire_Path {
	from_node := Node_Graph_Node_Of(graph, wire.from_node)
	to_node := Node_Graph_Node_Of(graph, wire.to_node)
	if from_node == nil || to_node == nil {return {}}
	a := Graph_Port_Position(graph, from_node, wire.from_port)
	b := Graph_Port_Position(graph, to_node, wire.to_port)
	return graph_route_wire(graph, wire, from_node, to_node, a, b)
}

//* Routes a wire between two points that are already known.
graph_route_wire :: proc(
	graph: ^Node_Graph,
	wire: ^Graph_Wire,
	from_node: ^Graph_Node,
	to_node: ^Graph_Node,
	a: Core.Vec2,
	b: Core.Vec2,
) -> Graph_Wire_Path {
	path: Graph_Wire_Path
	if b.x >= a.x {
		mid := (a.x + b.x) * 0.5
		path.points[0] = a
		path.points[1] = Core.Vec2{mid, a.y}
		path.points[2] = Core.Vec2{mid, b.y}
		path.points[3] = b
		path.count = 4
		return path
	}
	from_rect := Graph_Node_Rect(graph, from_node)
	to_rect := Graph_Node_Rect(graph, to_node)
	source_right := from_rect.x + from_rect.w
	target_right := to_rect.x + to_rect.w
	lanes: [3]f32
	lane_count := 0
	source_mid := from_rect.y + from_rect.h * 0.5
	target_mid := to_rect.y + to_rect.h * 0.5
	if target_mid < source_mid {
		lanes[lane_count] = min(from_rect.y, to_rect.y) - 24
		lane_count += 1
	} else if target_mid > source_mid {
		lanes[lane_count] = max(from_rect.y + from_rect.h, to_rect.y + to_rect.h) + 24
		lane_count += 1
	} else {
		lanes[lane_count] = min(from_rect.y, to_rect.y) - 24
		lane_count += 1
		lanes[lane_count] = max(from_rect.y + from_rect.h, to_rect.y + to_rect.h) + 24
		lane_count += 1
	}
	source_bottom := from_rect.y + from_rect.h
	target_bottom := to_rect.y + to_rect.h
	if source_bottom < to_rect.y {
		lanes[lane_count] = (source_bottom + to_rect.y) * 0.5
		lane_count += 1
	} else if target_bottom < from_rect.y {
		lanes[lane_count] = (target_bottom + from_rect.y) * 0.5
		lane_count += 1
	}
	source_xs: [2]f32 = {a.x + 20, max(source_right, target_right) + 20}
	target_xs: [2]f32 = {min(from_rect.x, to_rect.x) - 20, b.x - 20}
	best: Graph_Wire_Candidate
	best_length := f32(1e30)
	for lane_index in 0 ..< lane_count {
		for source_index in 0 ..< 2 {
			for target_index in 0 ..< 2 {
				candidate := wire_candidate_make(a, b, source_xs[source_index], target_xs[target_index], lanes[lane_index])
				if !wire_path_clear(candidate.points[:], candidate.count, from_rect, to_rect) {continue}
				if candidate.length < best_length {
					best = candidate
					best_length = candidate.length
				}
			}
		}
	}
	if best.count > 0 {
		path.points = best.points
		path.count = best.count
		return path
	}
	lane_y := max(from_rect.y + from_rect.h, to_rect.y + to_rect.h) + 24
	if target_mid < source_mid {lane_y = min(from_rect.y, to_rect.y) - 24}
	source_stub_x := a.x + 20
	target_stub_x := b.x - 20
	source_clear := source_stub_x <= to_rect.x || source_stub_x >= target_right ||
		max(a.y, lane_y) <= to_rect.y || min(a.y, lane_y) >= to_rect.y + to_rect.h
	target_clear := target_stub_x <= from_rect.x || target_stub_x >= source_right ||
		max(b.y, lane_y) <= from_rect.y || min(b.y, lane_y) >= from_rect.y + from_rect.h
	if !source_clear {source_stub_x = max(source_right, target_right) + 20}
	if !target_clear {target_stub_x = min(from_rect.x, to_rect.x) - 20}
	path.points[0] = a
	path.points[1] = Core.Vec2{source_stub_x, a.y}
	path.points[2] = Core.Vec2{source_stub_x, lane_y}
	path.points[3] = Core.Vec2{target_stub_x, lane_y}
	path.points[4] = Core.Vec2{target_stub_x, b.y}
	path.points[5] = b
	path.count = 6
	return path
}

Graph_Wire_Segments :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> [3][2]Core.Vec2 {
	path := Graph_Build_Wire_Path(graph, wire)
	segments: [3][2]Core.Vec2
	for i in 0 ..< 3 {
		if i + 1 >= path.count {break}
		segments[i] = {path.points[i], path.points[i + 1]}
	}
	return segments
}

Graph_Wire_At_Position :: proc(graph: ^Node_Graph, pos: Core.Vec2, tolerance: f32) -> Graph_Wire_ID {
	best := tolerance
	found := INVALID_GRAPH_WIRE_ID
	Graph_Geometry_Ensure(graph)
	scratch := graph_index_scratch(&graph.wire_scratch, len(graph.wires))
	query := Core.Rect{x = pos.x - tolerance, y = pos.y - tolerance, w = tolerance * 2, h = tolerance * 2}
	count := Graph_Index_Query_Wires(graph, &graph.cache.index, query, scratch)
	for i in 0 ..< count {
		wire := &graph.wires[scratch[i]]
		if !wire.alive {continue}
		path := graph.cache.wire_paths[scratch[i]]
		if path.count >= 2 {
			for point_index in 0 ..< path.count - 1 {
				distance := Graph_Point_Segment_Distance(pos, path.points[point_index], path.points[point_index + 1])
				if distance <= best {
					best = distance
					found = wire.id
				}
			}
		}
	}
	return found
}

Graph_Zoom_Of :: proc(graph: ^Node_Graph) -> f32 {
	if graph == nil || !(graph.zoom > 0) {return 1}
	return graph.zoom
}

Graph_Pan_Of :: proc(graph: ^Node_Graph) -> Core.Vec2 {
	if graph == nil {return {}}
	zoom := Graph_Zoom_Of(graph)
	return Core.Vec2{-graph.scroll.x * zoom, -graph.scroll.y * zoom}
}

Graph_View_Sync :: proc(graph: ^Node_Graph) {
	if graph != nil {graph.pan = Graph_Pan_Of(graph)}
}

Node_Graph_Screen_Pos :: proc(graph: ^Node_Graph, content: Core.Rect, pos: Core.Vec2) -> Core.Vec2 {
	zoom := Graph_Zoom_Of(graph)
	return Core.Vec2{
		content.x + (pos.x - graph.scroll.x) * zoom,
		content.y + (pos.y - graph.scroll.y) * zoom,
	}
}

Node_Graph_Graph_Pos :: proc(graph: ^Node_Graph, content: Core.Rect, pos: Core.Vec2) -> Core.Vec2 {
	zoom := Graph_Zoom_Of(graph)
	return Core.Vec2{
		graph.scroll.x + (pos.x - content.x) / zoom,
		graph.scroll.y + (pos.y - content.y) / zoom,
	}
}

Graph_Defaults :: proc(graph: ^Node_Graph) {
	graph.zoom = 1
	graph.min_zoom = NODE_GRAPH_MIN_ZOOM
	graph.max_zoom = NODE_GRAPH_MAX_ZOOM
	graph.zoom_step = NODE_GRAPH_ZOOM_STEP
	graph.grid_visible = true
	graph.grid_size = NODE_GRAPH_GRID_SIZE
	graph.grid_major = NODE_GRAPH_GRID_MAJOR
	graph.snap = false
	graph.policy.allow_cycles = true
	graph.style = Graph_Style_Defaults()
	graph.metrics = Graph_Metrics_Defaults()
	graph.cache_valid = false
	if graph.kind_by_name == nil {graph.kind_by_name = make(map[string]int)}
	if len(graph.kind_name) > 0 {delete(graph.kind_name)}
	graph.kind_name = ""
}

Graph_Node_Local_ID :: proc(node: ^Graph_Node) -> u32 {
	return node.id.index
}

Graph_Port_Local_ID :: proc(port: ^Graph_Port) -> u32 {
	return port.id.index
}
Graph_Align_Mode :: enum {
	Left,
	Top,
	Horizontal_Centre,
	Vertical_Centre,
}

//* The bounds of the selected nodes.
Graph_Selected_Bounds :: proc(graph: ^Node_Graph) -> (Core.Rect, bool) {
	bounds := Core.Rect{}
	have := false
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		rect := Graph_Node_Rect(graph, node)
		if !have {
			bounds = rect
			have = true
			continue
		}
		x0 := min(bounds.x, rect.x)
		y0 := min(bounds.y, rect.y)
		x1 := max(bounds.x + bounds.w, rect.x + rect.w)
		y1 := max(bounds.y + bounds.h, rect.y + rect.h)
		bounds = Core.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
	}
	return bounds, have
}

//* Moves the selected nodes so that they line up on one side.
Graph_Align_Selection :: proc(graph: ^Node_Graph, mode: Graph_Align_Mode) -> bool {
	bounds, have := Graph_Selected_Bounds(graph)
	if !have {return false}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		rect := Graph_Node_Rect(graph, node)
		switch mode {
		case .Left:
			node.pos.x = bounds.x
		case .Top:
			node.pos.y = bounds.y
		case .Horizontal_Centre:
			node.pos.x = bounds.x + bounds.w * 0.5 - rect.w * 0.5
		case .Vertical_Centre:
			node.pos.y = bounds.y + bounds.h * 0.5 - rect.h * 0.5
		}
	}
	Graph_Geometry_Invalidate(graph)
	return true
}

//* Spreads the selected nodes evenly along one axis. The nodes keep their
//* order, and the gap between them stays the same.
Graph_Distribute_Selection :: proc(graph: ^Node_Graph, horizontal: bool) -> bool {
	ids: [dynamic]Graph_Node_ID
	defer delete(ids)
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		append(&ids, node.id)
	}
	if len(ids) < 3 {return false}

	//* A simple insertion sort keeps the order stable and needs no memory.
	for i in 1 ..< len(ids) {
		value := ids[i]
		value_pos := Node_Graph_Node_Of(graph, value).pos
		j := i - 1
		for j >= 0 {
			other := Node_Graph_Node_Of(graph, ids[j])
			other_pos := other.pos
			if (horizontal && other_pos.x <= value_pos.x) || (!horizontal && other_pos.y <= value_pos.y) {break}
			ids[j + 1] = ids[j]
			j -= 1
		}
		ids[j + 1] = value
	}

	first := Node_Graph_Node_Of(graph, ids[0])
	last := Node_Graph_Node_Of(graph, ids[len(ids) - 1])
	if first == nil || last == nil {return false}

	total: f32 = 0
	for id in ids {
		node := Node_Graph_Node_Of(graph, id)
		if node == nil {continue}
		size := node.size.x if horizontal else node.size.y
		total += size
	}
	span := (last.pos.x if horizontal else last.pos.y) - (first.pos.x if horizontal else first.pos.y)
	gap := (span - total) / f32(len(ids) - 1)

	cursor := first.pos.x if horizontal else first.pos.y
	for id in ids {
		node := Node_Graph_Node_Of(graph, id)
		if node == nil {continue}
		if horizontal {node.pos.x = cursor} else {node.pos.y = cursor}
		cursor += (node.size.x if horizontal else node.size.y) + gap
	}
	Graph_Geometry_Invalidate(graph)
	return true
}
Graph_Region_ID :: struct {
	index:      u32,
	generation: u32,
}

INVALID_GRAPH_REGION_ID :: Graph_Region_ID{0, 0}

Graph_Region :: struct {
	id:             Graph_Region_ID,
	alive:          bool,
	title:          string,
	pos:            Core.Vec2,
	size:           Core.Vec2,
	colour:         Core.Colour,
	selected:       bool,
	move_contained: bool,
}

//* The colours a region can take. The inspector shows them as a row of
//* swatches, and the first one is the colour of a new region.
GRAPH_REGION_COLOURS := [8]Core.Colour{
	{0.32, 0.42, 0.62, 1},
	{0.36, 0.50, 0.38, 1},
	{0.58, 0.42, 0.30, 1},
	{0.50, 0.34, 0.52, 1},
	{0.30, 0.48, 0.52, 1},
	{0.56, 0.34, 0.36, 1},
	{0.44, 0.44, 0.48, 1},
	{0.62, 0.50, 0.24, 1},
}

Graph_Region_Slot :: proc(graph: ^Node_Graph) -> ^Graph_Region {
	index := 0
	generation: u32 = 1
	if len(graph.free_regions) > 0 {
		last := len(graph.free_regions) - 1
		index = int(graph.free_regions[last])
		resize(&graph.free_regions, last)
		generation = graph.regions[index].id.generation + 1
	} else {
		index = len(graph.regions)
		append(&graph.regions, Graph_Region{})
	}
	if generation == 0 {generation = 1}
	region := &graph.regions[index]
	region^ = Graph_Region{}
	region.id = Graph_Region_ID{u32(index + 1), generation}
	region.alive = true
	region.size = Core.Vec2{320, 200}
	region.colour = GRAPH_REGION_COLOURS[0]
	region.move_contained = true
	return region
}

Graph_Region_Of :: proc(graph: ^Node_Graph, id: Graph_Region_ID) -> ^Graph_Region {
	if graph == nil || id.index == 0 {return nil}
	index := int(id.index) - 1
	if index < 0 || index >= len(graph.regions) {return nil}
	region := &graph.regions[index]
	if !region.alive || region.id != id {return nil}
	return region
}

Graph_Add_Region :: proc(graph: ^Node_Graph, title: string, pos: Core.Vec2, size: Core.Vec2) -> Graph_Region_ID {
	if graph == nil {return INVALID_GRAPH_REGION_ID}
	region := Graph_Region_Slot(graph)
	region.title = strings.clone(title)
	region.pos = pos
	if size.x > 0 {region.size = size}
	Graph_Geometry_Invalidate(graph)
	return region.id
}

Graph_Remove_Region :: proc(graph: ^Node_Graph, id: Graph_Region_ID) {
	region := Graph_Region_Of(graph, id)
	if region == nil {return}
	if len(region.title) > 0 {delete(region.title)}
	region.title = ""
	region.alive = false
	append(&graph.free_regions, id.index - 1)
	Graph_Geometry_Invalidate(graph)
}

Graph_Region_Rect :: proc(graph: ^Node_Graph, region: ^Graph_Region) -> Core.Rect {
	if region == nil {return {}}
	return Core.Rect{x = region.pos.x, y = region.pos.y, w = region.size.x, h = region.size.y}
}

Graph_Set_Region_Title :: proc(graph: ^Node_Graph, id: Graph_Region_ID, title: string) -> bool {
	region := Graph_Region_Of(graph, id)
	if region == nil {return false}
	if region.title == title {return true}
	if len(region.title) > 0 {delete(region.title)}
	region.title = strings.clone(title)
	return true
}

Graph_Set_Region_Colour :: proc(graph: ^Node_Graph, id: Graph_Region_ID, colour: Core.Colour) -> bool {
	region := Graph_Region_Of(graph, id)
	if region == nil {return false}
	region.colour = colour
	return true
}

Graph_Set_Region_Move_Contained :: proc(graph: ^Node_Graph, id: Graph_Region_ID, move_contained: bool) -> bool {
	region := Graph_Region_Of(graph, id)
	if region == nil {return false}
	region.move_contained = move_contained
	return true
}

Graph_Set_Region_Pos :: proc(graph: ^Node_Graph, id: Graph_Region_ID, pos: Core.Vec2) -> bool {
	region := Graph_Region_Of(graph, id)
	if region == nil {return false}
	region.pos = pos
	Graph_Geometry_Invalidate(graph)
	return true
}

Graph_Set_Region_Size :: proc(graph: ^Node_Graph, id: Graph_Region_ID, size: Core.Vec2) -> bool {
	region := Graph_Region_Of(graph, id)
	if region == nil {return false}
	region.size = size
	Graph_Geometry_Invalidate(graph)
	return true
}

//* The header of a region: the strip at the top that carries its title.
Graph_Region_Header_Rect :: proc(graph: ^Node_Graph, region: ^Graph_Region) -> Core.Rect {
	if region == nil {return {}}
	height := Graph_Metrics_Of(graph).region_header_height
	return Core.Rect{x = region.pos.x, y = region.pos.y, w = region.size.x, h = height}
}

//* The region whose header holds a point. The last one wins, so a region
//* drawn over another one takes the pointer.
Graph_Region_At_Position :: proc(graph: ^Node_Graph, pos: Core.Vec2) -> Graph_Region_ID {
	found := INVALID_GRAPH_REGION_ID
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive {continue}
		if Graph_Rect_Contains(Graph_Region_Header_Rect(graph, region), pos.x, pos.y) {found = region.id}
	}
	return found
}

//* The handle at the bottom right of a region.
Graph_Region_Handle_Rect :: proc(graph: ^Node_Graph, region: ^Graph_Region) -> Core.Rect {
	if region == nil {return {}}
	size: f32 = 12
	return Core.Rect{
		x = region.pos.x + region.size.x - size,
		y = region.pos.y + region.size.y - size,
		w = size,
		h = size,
	}
}

//* The region whose resize handle holds a point.
Graph_Region_Handle_At_Position :: proc(graph: ^Node_Graph, pos: Core.Vec2) -> Graph_Region_ID {
	found := INVALID_GRAPH_REGION_ID
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive {continue}
		if Graph_Rect_Contains(Graph_Region_Handle_Rect(graph, region), pos.x, pos.y) {found = region.id}
	}
	return found
}

//* The nodes that lie completely inside a region.
Graph_Region_Contains :: proc(graph: ^Node_Graph, region: ^Graph_Region, node: ^Graph_Node) -> bool {
	if region == nil || node == nil {return false}
	rect := Graph_Region_Rect(graph, region)
	node_rect := Graph_Node_Rect(graph, node)
	return node_rect.x >= rect.x && node_rect.y >= rect.y &&
		node_rect.x + node_rect.w <= rect.x + rect.w &&
		node_rect.y + node_rect.h <= rect.y + rect.h
}

//* Creates a region around the nodes that are selected.
Graph_Region_Around_Nodes :: proc(graph: ^Node_Graph, title: string) -> Graph_Region_ID {
	if graph == nil {return INVALID_GRAPH_REGION_ID}
	have := false
	bounds := Core.Rect{}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		rect := Graph_Node_Rect(graph, node)
		if !have {
			bounds = rect
			have = true
		} else {
			x0 := min(bounds.x, rect.x)
			y0 := min(bounds.y, rect.y)
			x1 := max(bounds.x + bounds.w, rect.x + rect.w)
			y1 := max(bounds.y + bounds.h, rect.y + rect.h)
			bounds = Core.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
		}
	}
	if !have {return INVALID_GRAPH_REGION_ID}
	padding := Graph_Metrics_Of(graph).region_padding + 8
	size := Core.Vec2{bounds.w + padding * 2, bounds.h + padding * 2 + Graph_Metrics_Of(graph).region_header_height}
	pos := Core.Vec2{bounds.x - padding, bounds.y - padding - Graph_Metrics_Of(graph).region_header_height}
	return Graph_Add_Region(graph, title, pos, size)
}

Graph_Regions_Free :: proc(graph: ^Node_Graph) {
	if graph == nil {return}
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive {continue}
		if len(region.title) > 0 {delete(region.title)}
		region.title = ""
	}
	delete(graph.regions)
	delete(graph.free_regions)
	graph.regions = nil
	graph.free_regions = nil
}
//* The largest number of cells on one side of the grid. A graph whose
//* bounds are far apart falls back to a linear scan.
GRAPH_INDEX_MAX_CELLS :: 256

//* The smallest cell of the grid.
GRAPH_INDEX_MIN_CELL :: 64.0

Graph_Spatial_Index :: struct {
	//* Whether the index holds the geometry of the current epoch.
	valid:     bool,
	//* Whether the bounds are too far apart for a grid.
	linear:    bool,
	cell_size: f32,
	origin:    Core.Vec2,
	columns:   int,
	rows:      int,
	//* The nodes of a cell, in a flat list with an offset per cell.
	node_offsets: [dynamic]int,
	node_items:   [dynamic]int,
	//* The wires of a cell, in the same shape.
	wire_offsets: [dynamic]int,
	wire_items:   [dynamic]int,
	//* The query a candidate was last seen in, so that a candidate that
	//* lies in several cells is only returned once.
	node_stamp: [dynamic]u32,
	wire_stamp: [dynamic]u32,
	stamp:      u32,
}

//* The geometry of a graph that does not change: the rectangles of the
//* nodes, the positions of the ports, the paths of the wires and the
//* rectangles of the regions.
Graph_Geometry_Cache :: struct {
	valid:           bool,
	epoch:           u64,
	node_rects:      [dynamic]Core.Rect,
	node_ports:      [dynamic]Core.Vec2,
	node_port_base:  [dynamic]int,
	node_port_count: [dynamic]int,
	wire_paths:      [dynamic]Graph_Wire_Path,
	wire_bboxes:     [dynamic]Core.Rect,
	region_rects:    [dynamic]Core.Rect,
	index:           Graph_Spatial_Index,
}

//* == Building ==

//* Gives the memory of the index back.
graph_index_clear :: proc(index: ^Graph_Spatial_Index) {
	delete(index.node_offsets)
	delete(index.node_items)
	delete(index.wire_offsets)
	delete(index.wire_items)
	delete(index.node_stamp)
	delete(index.wire_stamp)
	index^ = Graph_Spatial_Index{}
}

//* Gives the memory of the cache back.
graph_cache_clear :: proc(cache: ^Graph_Geometry_Cache) {
	delete(cache.node_rects)
	delete(cache.node_ports)
	delete(cache.node_port_base)
	delete(cache.node_port_count)
	delete(cache.wire_paths)
	delete(cache.wire_bboxes)
	delete(cache.region_rects)
	graph_index_clear(&cache.index)
	cache^ = Graph_Geometry_Cache{}
}

//* The bounds of the alive nodes of a graph.
graph_nodes_bounds :: proc(graph: ^Node_Graph) -> (Core.Rect, bool) {
	bounds := Core.Rect{}
	have := false
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		rect := Graph_Node_Rect(graph, node)
		if !have {
			bounds = rect
			have = true
			continue
		}
		x0 := min(bounds.x, rect.x)
		y0 := min(bounds.y, rect.y)
		x1 := max(bounds.x + bounds.w, rect.x + rect.w)
		y1 := max(bounds.y + bounds.h, rect.y + rect.h)
		bounds = Core.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
	}
	return bounds, have
}

//* Fills the cache with the geometry of the graph. The wire paths are built
//* here, once, so that the culling, the drawing and the hit testing all
//* read the same path.
Graph_Geometry_Ensure :: proc(graph: ^Node_Graph) {
	if graph == nil {return}
	cache := &graph.cache
	if cache.valid {return}

	resize(&cache.node_rects, len(graph.nodes))
	resize(&cache.node_port_base, len(graph.nodes))
	resize(&cache.node_port_count, len(graph.nodes))
	resize(&cache.wire_paths, len(graph.wires))
	resize(&cache.wire_bboxes, len(graph.wires))
	resize(&cache.region_rects, len(graph.regions))

	port_total := 0
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {
			cache.node_rects[i] = Core.Rect{}
			cache.node_port_base[i] = port_total
			cache.node_port_count[i] = 0
			continue
		}
		cache.node_rects[i] = Graph_Node_Rect(graph, node)
		cache.node_port_base[i] = port_total
		count := 0
		for &port in node.ports {
			if !port.alive || !port.visible {continue}
			count += 1
		}
		cache.node_port_count[i] = count
		port_total += count
	}

	resize(&cache.node_ports, port_total)
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		base := cache.node_port_base[i]
		index := base
		for &port in node.ports {
			if !port.alive || !port.visible {continue}
			cache.node_ports[index] = Graph_Port_Position(graph, node, port.id)
			index += 1
		}
	}

	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive {
			cache.wire_paths[i] = Graph_Wire_Path{}
			cache.wire_bboxes[i] = Core.Rect{}
			continue
		}
		path := graph_build_wire_path_from(graph, wire, cache)
		cache.wire_paths[i] = path
		cache.wire_bboxes[i] = graph_wire_path_bbox(path)
	}

	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive {
			cache.region_rects[i] = Core.Rect{}
			continue
		}
		cache.region_rects[i] = Graph_Region_Rect(graph, region)
	}

	graph_index_rebuild(graph, &cache.index)
	cache.valid = true
}

//* The position of a port, from the cache of the graph.
cache_port_position :: proc(graph: ^Node_Graph, cache: ^Graph_Geometry_Cache, node: ^Graph_Node, port_id: Graph_Port_ID) -> Core.Vec2 {
	node_index := int(node.id.index) - 1
	if node_index < 0 || node_index >= len(cache.node_port_base) {
		return Graph_Port_Position(graph, node, port_id)
	}
	base := cache.node_port_base[node_index]
	count := cache.node_port_count[node_index]
	port_index := 0
	for &port in node.ports {
		if !port.alive || !port.visible {continue}
		if port.id == port_id {
			//* A cache that a port change outran is not trusted: the
			//* position is worked out again instead of read past the end.
			if port_index < count {
				index := base + port_index
				if index >= 0 && index < len(cache.node_ports) {return cache.node_ports[index]}
			}
			break
		}
		port_index += 1
	}
	return Graph_Port_Position(graph, node, port_id)
}

//* Builds the path of a wire from the cached geometry.
graph_build_wire_path_from :: proc(graph: ^Node_Graph, wire: ^Graph_Wire, cache: ^Graph_Geometry_Cache) -> Graph_Wire_Path {
	from_node := Node_Graph_Node_Of(graph, wire.from_node)
	to_node := Node_Graph_Node_Of(graph, wire.to_node)
	if from_node == nil || to_node == nil {return {}}
	a := cache_port_position(graph, cache, from_node, wire.from_port)
	b := cache_port_position(graph, cache, to_node, wire.to_port)
	return graph_route_wire(graph, wire, from_node, to_node, a, b)
}

//* The bounds of a wire path.
graph_wire_path_bbox :: proc(path: Graph_Wire_Path) -> Core.Rect {
	if path.count < 2 {return {}}
	min_x := path.points[0].x
	min_y := path.points[0].y
	max_x := path.points[0].x
	max_y := path.points[0].y
	for i in 1 ..< path.count {
		point := path.points[i]
		min_x = min(min_x, point.x)
		min_y = min(min_y, point.y)
		max_x = max(max_x, point.x)
		max_y = max(max_y, point.y)
	}
	return Core.Rect{x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y}
}

//* == The index ==

//* Puts the nodes to zero without changing the length of the array.
graph_zero_ints :: proc(values: ^[dynamic]u32) {
	for &value in values^ {value = 0}
}

//* Builds the grid of the index. The cell size follows the size of the
//* grid of the canvas, so a cell holds about a node.
graph_index_rebuild :: proc(graph: ^Node_Graph, index: ^Graph_Spatial_Index) {
	if index.valid {return}
	index.linear = true
	index.columns = 0
	index.rows = 0

	bounds, have := graph_nodes_bounds(graph)
	if !have {
		index.valid = true
		return
	}

	cell := max(graph.grid_size * 4, GRAPH_INDEX_MIN_CELL)
	needed_w := max(bounds.w, 1)
	needed_h := max(bounds.h, 1)
	if needed_w / cell > GRAPH_INDEX_MAX_CELLS || needed_h / cell > GRAPH_INDEX_MAX_CELLS {
		cell = max(cell, max(needed_w, needed_h) / GRAPH_INDEX_MAX_CELLS)
	}
	columns := int(math.ceil(needed_w / cell)) + 1
	rows := int(math.ceil(needed_h / cell)) + 1
	columns = clamp(columns, 1, GRAPH_INDEX_MAX_CELLS)
	rows = clamp(rows, 1, GRAPH_INDEX_MAX_CELLS)

	index.cell_size = cell
	index.origin = Core.Vec2{bounds.x, bounds.y}
	index.columns = columns
	index.rows = rows
	index.linear = false

	resize(&index.node_stamp, len(graph.nodes))
	resize(&index.wire_stamp, len(graph.wires))
	graph_zero_ints(&index.node_stamp)
	graph_zero_ints(&index.wire_stamp)

	graph_index_fill_nodes(graph, index)
	graph_index_fill_wires(graph, index)
	index.valid = true
}

//* The number of cells a rectangle touches.
graph_index_cell_count :: proc(index: ^Graph_Spatial_Index, rect: Core.Rect) -> int {
	x0 := int(math.floor((rect.x - index.origin.x) / index.cell_size))
	y0 := int(math.floor((rect.y - index.origin.y) / index.cell_size))
	x1 := int(math.floor((rect.x + rect.w - index.origin.x) / index.cell_size))
	y1 := int(math.floor((rect.y + rect.h - index.origin.y) / index.cell_size))
	x0 = clamp(x0, 0, index.columns - 1)
	y0 = clamp(y0, 0, index.rows - 1)
	x1 = clamp(x1, 0, index.columns - 1)
	y1 = clamp(y1, 0, index.rows - 1)
	return (x1 - x0 + 1) * (y1 - y0 + 1)
}

//* The cells a rectangle touches.
graph_index_cell_range :: proc(index: ^Graph_Spatial_Index, rect: Core.Rect) -> (x0, y0, x1, y1: int) {
	x0 = int(math.floor((rect.x - index.origin.x) / index.cell_size))
	y0 = int(math.floor((rect.y - index.origin.y) / index.cell_size))
	x1 = int(math.floor((rect.x + rect.w - index.origin.x) / index.cell_size))
	y1 = int(math.floor((rect.y + rect.h - index.origin.y) / index.cell_size))
	x0 = clamp(x0, 0, index.columns - 1)
	y0 = clamp(y0, 0, index.rows - 1)
	x1 = clamp(x1, 0, index.columns - 1)
	y1 = clamp(y1, 0, index.rows - 1)
	return x0, y0, x1, y1
}

//* Puts the nodes into the cells of the grid.
graph_index_fill_nodes :: proc(graph: ^Node_Graph, index: ^Graph_Spatial_Index) {
	cells := index.columns * index.rows
	counts := make([]int, cells)
	defer delete(counts)
	resize(&index.node_offsets, cells + 1)
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		rect := graph.cache.node_rects[i]
		x0, y0, x1, y1 := graph_index_cell_range(index, rect)
		for y in y0 ..= y1 {
			for x in x0 ..= x1 {
				counts[y * index.columns + x] += 1
			}
		}
	}
	sum := 0
	for cell_index in 0 ..< cells {
		index.node_offsets[cell_index] = sum
		sum += counts[cell_index]
	}
	index.node_offsets[cells] = sum
	resize(&index.node_items, sum)

	cursor := make([]int, cells)
	defer delete(cursor)
	for cell_index in 0 ..< cells {cursor[cell_index] = index.node_offsets[cell_index]}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		rect := graph.cache.node_rects[i]
		x0, y0, x1, y1 := graph_index_cell_range(index, rect)
		for y in y0 ..= y1 {
			for x in x0 ..= x1 {
				cell_index := y * index.columns + x
				index.node_items[cursor[cell_index]] = i
				cursor[cell_index] += 1
			}
		}
	}
}

//* Puts the wires into the cells of the grid.
graph_index_fill_wires :: proc(graph: ^Node_Graph, index: ^Graph_Spatial_Index) {
	cells := index.columns * index.rows
	counts := make([]int, cells)
	defer delete(counts)
	resize(&index.wire_offsets, cells + 1)
	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		rect := graph.cache.wire_bboxes[i]
		x0, y0, x1, y1 := graph_index_cell_range(index, rect)
		for y in y0 ..= y1 {
			for x in x0 ..= x1 {
				counts[y * index.columns + x] += 1
			}
		}
	}
	sum := 0
	for cell_index in 0 ..< cells {
		index.wire_offsets[cell_index] = sum
		sum += counts[cell_index]
	}
	index.wire_offsets[cells] = sum
	resize(&index.wire_items, sum)

	cursor := make([]int, cells)
	defer delete(cursor)
	for cell_index in 0 ..< cells {cursor[cell_index] = index.wire_offsets[cell_index]}
	for i in 0 ..< len(graph.wires) {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		rect := graph.cache.wire_bboxes[i]
		x0, y0, x1, y1 := graph_index_cell_range(index, rect)
		for y in y0 ..= y1 {
			for x in x0 ..= x1 {
				cell_index := y * index.columns + x
				index.wire_items[cursor[cell_index]] = i
				cursor[cell_index] += 1
			}
		}
	}
}

//* The candidates of a rectangle: the nodes that touch it. The result is
//* written into the scratch of the caller, and every node is only in it
//* once.
Graph_Index_Query_Nodes :: proc(graph: ^Node_Graph, index: ^Graph_Spatial_Index, rect: Core.Rect, out: []int) -> int {
	if index.linear {
		count := 0
		for i in 0 ..< len(graph.nodes) {
		if count >= len(out) {break}
			node := &graph.nodes[i]
			if !node.alive {continue}
			out[count] = i
			count += 1
		}
		return count
	}
	index.stamp += 1
	if index.stamp == 0 {
		clear(&index.node_stamp)
		clear(&index.wire_stamp)
		index.stamp = 1
	}
	stamp := index.stamp
	count := 0
	x0, y0, x1, y1 := graph_index_cell_range(index, rect)
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			cell_index := y * index.columns + x
			start := index.node_offsets[cell_index]
			end := index.node_offsets[cell_index + 1]
			for item in start ..< end {
				node_index := index.node_items[item]
				if index.node_stamp[node_index] == stamp {continue}
				index.node_stamp[node_index] = stamp
				if count >= len(out) {return count}
				out[count] = node_index
				count += 1
			}
		}
	}
	return count
}

//* The candidates of a rectangle: the wires that touch it.
Graph_Index_Query_Wires :: proc(graph: ^Node_Graph, index: ^Graph_Spatial_Index, rect: Core.Rect, out: []int) -> int {
	if index.linear {
		count := 0
		for i := 0; i < len(graph.wires) && count < len(out); i += 1 {
			wire := &graph.wires[i]
			if !wire.alive {continue}
			out[count] = i
			count += 1
		}
		return count
	}
	index.stamp += 1
	if index.stamp == 0 {
		clear(&index.node_stamp)
		clear(&index.wire_stamp)
		index.stamp = 1
	}
	stamp := index.stamp
	count := 0
	x0, y0, x1, y1 := graph_index_cell_range(index, rect)
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			cell_index := y * index.columns + x
			start := index.wire_offsets[cell_index]
			end := index.wire_offsets[cell_index + 1]
			for item in start ..< end {
				wire_index := index.wire_items[item]
				if index.wire_stamp[wire_index] == stamp {continue}
				index.wire_stamp[wire_index] = stamp
				if count >= len(out) {return count}
				out[count] = wire_index
				count += 1
			}
		}
	}
	return count
}

//* == Reading the cache ==

//* The position of a port, from the cache when it is there.
Graph_Port_Position_Of :: proc(graph: ^Node_Graph, node: ^Graph_Node, port_id: Graph_Port_ID) -> Core.Vec2 {
	if graph == nil || node == nil {return {}}
	Graph_Geometry_Ensure(graph)
	return cache_port_position(graph, &graph.cache, node, port_id)
}

//* The path of a wire, from the cache when it is there.
Graph_Wire_Path_Of :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> Graph_Wire_Path {
	if graph == nil || wire == nil {return {}}
	Graph_Geometry_Ensure(graph)
	index := int(wire.id.index) - 1
	if index < 0 || index >= len(graph.cache.wire_paths) {return {}}
	return graph.cache.wire_paths[index]
}

//* The rectangle of a node, from the cache when it is there.
Graph_Node_Rect_Of :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Core.Rect {
	if graph == nil || node == nil {return {}}
	Graph_Geometry_Ensure(graph)
	index := int(node.id.index) - 1
	if index < 0 || index >= len(graph.cache.node_rects) {return Graph_Node_Rect(graph, node)}
	return graph.cache.node_rects[index]
}

//* The rectangle of a wire, from the cache when it is there.
Graph_Wire_BBox_Of :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> Core.Rect {
	if graph == nil || wire == nil {return {}}
	Graph_Geometry_Ensure(graph)
	index := int(wire.id.index) - 1
	if index < 0 || index >= len(graph.cache.wire_bboxes) {return {}}
	return graph.cache.wire_bboxes[index]
}
//* == View ==

node_graph_zoom :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> f32 {
	graph := node_graph_of(g, id)
	if graph == nil {return 1}
	return Graph_Zoom_Of(graph)
}

node_graph_set_zoom :: proc(g: ^Core.GUI, id: Core.Widget_ID, zoom: f32) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	value := clamp(zoom, graph.min_zoom, graph.max_zoom)
	if !(value > 0) {value = 1}
	if value == graph.zoom {return}
	pan := Graph_Pan_Of(graph)
	graph.zoom = value
	graph.scroll = Core.Vec2{-pan.x / value, -pan.y / value}
	Graph_View_Sync(graph)
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_zoom_at :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	graph: ^Node_Graph,
	content: Core.Rect,
	screen: Core.Vec2,
	zoom: f32,
) {
	if graph == nil {return}
	value := clamp(zoom, graph.min_zoom, graph.max_zoom)
	if !(value > 0) {value = 1}
	if value == graph.zoom {return}
	point := Node_Graph_Graph_Pos(graph, content, screen)
	graph.zoom = value
	graph.scroll = Core.Vec2{
		point.x - (screen.x - content.x) / value,
		point.y - (screen.y - content.y) / value,
	}
	Graph_View_Sync(graph)
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_pan :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> Core.Vec2 {
	graph := node_graph_of(g, id)
	if graph == nil {return {}}
	return Graph_Pan_Of(graph)
}

node_graph_set_pan :: proc(g: ^Core.GUI, id: Core.Widget_ID, pan: Core.Vec2) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	zoom := Graph_Zoom_Of(graph)
	graph.scroll = Core.Vec2{-pan.x / zoom, -pan.y / zoom}
	graph.pan = pan
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_reset_view :: proc(g: ^Core.GUI, id: Core.Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph.zoom = 1
	graph.scroll = {}
	graph.pan = {}
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

//* The bounds of the nodes, and of the regions when there are any.
graph_content_bounds :: proc(graph: ^Node_Graph, selection_only: bool) -> (Core.Rect, bool) {
	bounds := Core.Rect{}
	have := false
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		if selection_only && !node.selected {continue}
		rect := Graph_Node_Rect(graph, node)
		if !have {
			bounds = rect
			have = true
		} else {
			x0 := min(bounds.x, rect.x)
			y0 := min(bounds.y, rect.y)
			x1 := max(bounds.x + bounds.w, rect.x + rect.w)
			y1 := max(bounds.y + bounds.h, rect.y + rect.h)
			bounds = Core.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
		}
	}
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive {continue}
		if selection_only && !region.selected {continue}
		rect := Graph_Region_Rect(graph, region)
		if !have {
			bounds = rect
			have = true
		} else {
			x0 := min(bounds.x, rect.x)
			y0 := min(bounds.y, rect.y)
			x1 := max(bounds.x + bounds.w, rect.x + rect.w)
			y1 := max(bounds.y + bounds.h, rect.y + rect.h)
			bounds = Core.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
		}
	}
	return bounds, have
}

//* Moves the view so that the bounds sit in the middle of the canvas.
graph_frame_bounds :: proc(g: ^Core.GUI, id: Core.Widget_ID, graph: ^Node_Graph, bounds: Core.Rect, padding: f32) {
	w := Core.Widget_Get(g, id)
	if w == nil {return}
	content := Core.content_rect(g, w)
	if content.w <= 1 || content.h <= 1 {return}
	pad := max(padding, 0)
	avail_w := max(content.w - pad * 2, 1)
	avail_h := max(content.h - pad * 2, 1)
	zoom := min(avail_w / max(bounds.w, 1), avail_h / max(bounds.h, 1))
	graph.zoom = clamp(zoom, graph.min_zoom, graph.max_zoom)
	center := Core.Vec2{bounds.x + bounds.w * 0.5, bounds.y + bounds.h * 0.5}
	graph.scroll = Core.Vec2{
		center.x - content.w / (2 * graph.zoom),
		center.y - content.h / (2 * graph.zoom),
	}
	Graph_View_Sync(graph)
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_fit_view :: proc(g: ^Core.GUI, id: Core.Widget_ID, padding: f32 = 40) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	bounds, have := graph_content_bounds(graph, false)
	if !have {
		node_graph_reset_view(g, id)
		return
	}
	graph_frame_bounds(g, id, graph, bounds, padding)
}

//* Frames the selection, and the whole graph when nothing is selected.
node_graph_fit_selection :: proc(g: ^Core.GUI, id: Core.Widget_ID, padding: f32 = 40) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	bounds, have := graph_content_bounds(graph, true)
	if !have {
		node_graph_fit_view(g, id, padding)
		return
	}
	graph_frame_bounds(g, id, graph, bounds, padding)
}

node_graph_set_grid :: proc(
	g: ^Core.GUI,
	id: Core.Widget_ID,
	visible: bool,
	size: f32 = NODE_GRAPH_GRID_SIZE,
	major: f32 = NODE_GRAPH_GRID_MAJOR,
) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph.grid_visible = visible
	if size > 0 {graph.grid_size = size}
	if major > 0 {graph.grid_major = major}
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}

node_graph_set_snap :: proc(g: ^Core.GUI, id: Core.Widget_ID, snap: bool) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph.snap = snap
	Core.invalidate(g, id, Core.Dirty_Flags{.Visual})
}


GRAPH_TYPE_EXEC_COLOUR :: Core.Colour{0.92, 0.94, 0.98, 1}
GRAPH_TYPE_BOOL_COLOUR :: Core.Colour{0.95, 0.30, 0.32, 1}
GRAPH_TYPE_INT_COLOUR :: Core.Colour{0.20, 0.80, 0.90, 1}
GRAPH_TYPE_FLOAT_COLOUR :: Core.Colour{0.30, 0.85, 0.45, 1}
GRAPH_TYPE_VECTOR_COLOUR :: Core.Colour{0.95, 0.72, 0.25, 1}
GRAPH_TYPE_STRING_COLOUR :: Core.Colour{0.88, 0.35, 0.85, 1}
GRAPH_TYPE_OBJECT_COLOUR :: Core.Colour{0.35, 0.55, 0.95, 1}
GRAPH_TYPE_WILDCARD_COLOUR :: Core.Colour{0.62, 0.66, 0.72, 1}

GRAPH_UNKNOWN_TYPE_COLOURS :: [8]Core.Colour{
	Core.Colour{0.90, 0.55, 0.25, 1},
	Core.Colour{0.25, 0.75, 0.75, 1},
	Core.Colour{0.75, 0.45, 0.85, 1},
	Core.Colour{0.45, 0.80, 0.35, 1},
	Core.Colour{0.85, 0.40, 0.55, 1},
	Core.Colour{0.40, 0.60, 0.90, 1},
	Core.Colour{0.85, 0.75, 0.30, 1},
	Core.Colour{0.55, 0.75, 0.45, 1},
}

graph_type_name_equal :: proc(a, b: string) -> bool {
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

Graph_Set_Type_Colour :: proc(graph: ^Node_Graph, type_name: string, colour: Core.Colour) -> bool {
	if graph == nil || type_name == "" {return false}
	for &entry in graph.type_colours {
		if graph_type_name_equal(entry.name, type_name) {
			entry.colour = colour
			return true
		}
	}
	append(&graph.type_colours, Graph_Type_Colour{name = strings.clone(type_name), colour = colour})
	return true
}

Graph_Type_Colour_Of :: proc(graph: ^Node_Graph, type_name: string) -> Core.Colour {
	if type_name == "" {return GRAPH_TYPE_WILDCARD_COLOUR}
	for entry in graph.type_colours {
		if graph_type_name_equal(entry.name, type_name) {return entry.colour}
	}
	if graph_type_name_equal(type_name, "exec") {return GRAPH_TYPE_EXEC_COLOUR}
	if graph_type_name_equal(type_name, "bool") || graph_type_name_equal(type_name, "boolean") {return GRAPH_TYPE_BOOL_COLOUR}
	if graph_type_name_equal(type_name, "int") || graph_type_name_equal(type_name, "integer") {return GRAPH_TYPE_INT_COLOUR}
	if graph_type_name_equal(type_name, "float") || graph_type_name_equal(type_name, "double") {return GRAPH_TYPE_FLOAT_COLOUR}
	if graph_type_name_equal(type_name, "vec2") || graph_type_name_equal(type_name, "vector2") {return GRAPH_TYPE_VECTOR_COLOUR}
	if graph_type_name_equal(type_name, "vec3") || graph_type_name_equal(type_name, "vector3") {return GRAPH_TYPE_VECTOR_COLOUR}
	if graph_type_name_equal(type_name, "string") || graph_type_name_equal(type_name, "text") {return GRAPH_TYPE_STRING_COLOUR}
	if graph_type_name_equal(type_name, "object") {return GRAPH_TYPE_OBJECT_COLOUR}
	if graph_type_name_equal(type_name, "wildcard") || graph_type_name_equal(type_name, "any") {return GRAPH_TYPE_WILDCARD_COLOUR}
	hash: u32 = 2166136261
	for i := 0; i < len(type_name); i += 1 {
		hash ~= u32(type_name[i])
		hash *= 16777619
	}
	palette := GRAPH_UNKNOWN_TYPE_COLOURS
	return palette[int(hash % len(palette))]
}

Graph_Port_Colour :: proc(graph: ^Node_Graph, node_id: Graph_Node_ID, port_id: Graph_Port_ID) -> Core.Colour {
	port := Node_Graph_Port_Of(graph, node_id, port_id)
	if port == nil {return Core.Colour{}}
	if port.colour.a > 0 {return port.colour}
	if port.port_kind == .Exec {return GRAPH_TYPE_EXEC_COLOUR}
	return Graph_Type_Colour_Of(graph, Graph_Effective_Port_Type(graph, node_id, port_id))
}

Graph_Wire_Colour :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> Core.Colour {
	if wire == nil {return Core.Colour{}}
	if wire.colour.a > 0 {return wire.colour}
	from := Node_Graph_Port_Of(graph, wire.from_node, wire.from_port)
	if from == nil {return GRAPH_TYPE_WILDCARD_COLOUR}
	if from.port_kind == .Exec {return GRAPH_TYPE_EXEC_COLOUR}
	return Graph_Type_Colour_Of(graph, Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port))
}
//* Graph_Style overrides the metrics of one graph. A field that is zero
//* keeps the value of the theme, so a style only names what it changes.
Graph_Style :: struct {
	title_height:          f32,
	port_spacing:          f32,
	port_size:             f32,
	pin_ring_width:        f32,
	corner_radius:         f32,
	title_font_size:       f32,
	pin_font_size:         f32,
	config_font_size:      f32,
	wire_width:            f32,
	wire_glow_width:       f32,
	arrow_size:            f32,
	badge_height:          f32,
	badge_padding:         f32,
	node_shadow:           f32,
	shadow_opacity:        f32,
	lod_full_zoom:         f32,
	lod_compact_zoom:      f32,
	region_header_height:  f32,
	region_padding:        f32,
	region_title_font_size: f32,
}

//* Graph_Metrics is the resolved form of Graph_Style. Every field holds a
//* real value, so the geometry never has to ask the theme again.
Graph_Metrics :: struct {
	title_height:          f32,
	port_spacing:          f32,
	port_size:             f32,
	pin_ring_width:        f32,
	corner_radius:         f32,
	title_font_size:       f32,
	pin_font_size:         f32,
	config_font_size:      f32,
	wire_width:            f32,
	wire_glow_width:       f32,
	arrow_size:            f32,
	badge_height:          f32,
	badge_padding:         f32,
	node_shadow:           f32,
	shadow_opacity:        f32,
	lod_full_zoom:         f32,
	lod_compact_zoom:      f32,
	region_header_height:  f32,
	region_padding:        f32,
	region_title_font_size: f32,
}

//* The metrics a graph uses when the theme says nothing. The values are the
//* compact ones: a node reads as a small card, not as a form.
GRAPH_METRIC_DEFAULTS :: Graph_Style{
	title_height = 20,
	port_spacing = 16,
	port_size = 9,
	pin_ring_width = 1.5,
	corner_radius = 6,
	title_font_size = 12,
	pin_font_size = 9,
	config_font_size = 9,
	wire_width = 2,
	wire_glow_width = 5,
	arrow_size = 7,
	badge_height = 14,
	badge_padding = 4,
	node_shadow = 6,
	shadow_opacity = 0.35,
	lod_full_zoom = 0.75,
	lod_compact_zoom = 0.45,
	region_header_height = 18,
	region_padding = 8,
	region_title_font_size = 10,
}

//* The built-in metrics of a graph, before the theme and the style speak.
Graph_Metrics_Defaults :: proc() -> Graph_Metrics {
	return Graph_Metrics{
		title_height = GRAPH_METRIC_DEFAULTS.title_height,
		port_spacing = GRAPH_METRIC_DEFAULTS.port_spacing,
		port_size = GRAPH_METRIC_DEFAULTS.port_size,
		pin_ring_width = GRAPH_METRIC_DEFAULTS.pin_ring_width,
		corner_radius = GRAPH_METRIC_DEFAULTS.corner_radius,
		title_font_size = GRAPH_METRIC_DEFAULTS.title_font_size,
		pin_font_size = GRAPH_METRIC_DEFAULTS.pin_font_size,
		config_font_size = GRAPH_METRIC_DEFAULTS.config_font_size,
		wire_width = GRAPH_METRIC_DEFAULTS.wire_width,
		wire_glow_width = GRAPH_METRIC_DEFAULTS.wire_glow_width,
		arrow_size = GRAPH_METRIC_DEFAULTS.arrow_size,
		badge_height = GRAPH_METRIC_DEFAULTS.badge_height,
		badge_padding = GRAPH_METRIC_DEFAULTS.badge_padding,
		node_shadow = GRAPH_METRIC_DEFAULTS.node_shadow,
		shadow_opacity = GRAPH_METRIC_DEFAULTS.shadow_opacity,
		lod_full_zoom = GRAPH_METRIC_DEFAULTS.lod_full_zoom,
		lod_compact_zoom = GRAPH_METRIC_DEFAULTS.lod_compact_zoom,
		region_header_height = GRAPH_METRIC_DEFAULTS.region_header_height,
		region_padding = GRAPH_METRIC_DEFAULTS.region_padding,
		region_title_font_size = GRAPH_METRIC_DEFAULTS.region_title_font_size,
	}
}

//* The built-in style: nothing is overridden.
Graph_Style_Defaults :: proc() -> Graph_Style {
	return Graph_Style{}
}

//* Copies the fields of the override that are set over the resolved metrics.
Graph_Metrics_Apply :: proc(base: Graph_Metrics, over: Graph_Style) -> Graph_Metrics {
	out := base
	if over.title_height > 0 {out.title_height = over.title_height}
	if over.port_spacing > 0 {out.port_spacing = over.port_spacing}
	if over.port_size > 0 {out.port_size = over.port_size}
	if over.pin_ring_width > 0 {out.pin_ring_width = over.pin_ring_width}
	if over.corner_radius > 0 {out.corner_radius = over.corner_radius}
	if over.title_font_size > 0 {out.title_font_size = over.title_font_size}
	if over.pin_font_size > 0 {out.pin_font_size = over.pin_font_size}
	if over.config_font_size > 0 {out.config_font_size = over.config_font_size}
	if over.wire_width > 0 {out.wire_width = over.wire_width}
	if over.wire_glow_width > 0 {out.wire_glow_width = over.wire_glow_width}
	if over.arrow_size > 0 {out.arrow_size = over.arrow_size}
	if over.badge_height > 0 {out.badge_height = over.badge_height}
	if over.badge_padding > 0 {out.badge_padding = over.badge_padding}
	if over.node_shadow > 0 {out.node_shadow = over.node_shadow}
	if over.shadow_opacity > 0 {out.shadow_opacity = over.shadow_opacity}
	if over.lod_full_zoom > 0 {out.lod_full_zoom = over.lod_full_zoom}
	if over.lod_compact_zoom > 0 {out.lod_compact_zoom = over.lod_compact_zoom}
	if over.region_header_height > 0 {out.region_header_height = over.region_header_height}
	if over.region_padding > 0 {out.region_padding = over.region_padding}
	if over.region_title_font_size > 0 {out.region_title_font_size = over.region_title_font_size}
	return out
}

//* Whether two sets of metrics describe the same drawing.
Graph_Metrics_Equal :: proc(a, b: Graph_Metrics) -> bool {
	return a.title_height == b.title_height &&
		a.port_spacing == b.port_spacing &&
		a.port_size == b.port_size &&
		a.pin_ring_width == b.pin_ring_width &&
		a.corner_radius == b.corner_radius &&
		a.title_font_size == b.title_font_size &&
		a.pin_font_size == b.pin_font_size &&
		a.config_font_size == b.config_font_size &&
		a.wire_width == b.wire_width &&
		a.wire_glow_width == b.wire_glow_width &&
		a.arrow_size == b.arrow_size &&
		a.badge_height == b.badge_height &&
		a.badge_padding == b.badge_padding &&
		a.node_shadow == b.node_shadow &&
		a.shadow_opacity == b.shadow_opacity &&
		a.lod_full_zoom == b.lod_full_zoom &&
		a.lod_compact_zoom == b.lod_compact_zoom &&
		a.region_header_height == b.region_header_height &&
		a.region_padding == b.region_padding &&
		a.region_title_font_size == b.region_title_font_size
}

//* The style of a graph: the overrides it holds.
Graph_Style_Of :: proc(graph: ^Node_Graph) -> Graph_Style {
	if graph == nil {return Graph_Style{}}
	return graph.style
}

//* Sets the style of a graph. The metrics are resolved again on the next
//* frame, and the geometry is thrown away because the node sizes change.
Graph_Set_Style :: proc(graph: ^Node_Graph, style: Graph_Style) {
	if graph == nil {return}
	graph.style = style
	Graph_Geometry_Invalidate(graph)
}

//* The resolved metrics of a graph.
Graph_Metrics_Of :: proc(graph: ^Node_Graph) -> Graph_Metrics {
	if graph == nil {return Graph_Metrics_Defaults()}
	return graph.metrics
}

//* Stores the resolved metrics of a graph. The geometry is thrown away when
//* the metrics change, because every node size depends on them.
Graph_Set_Metrics :: proc(graph: ^Node_Graph, metrics: Graph_Metrics) {
	if graph == nil {return}
	if Graph_Metrics_Equal(graph.metrics, metrics) {return}
	graph.metrics = metrics
	Graph_Geometry_Invalidate(graph)
}

//* The level of detail a zoom asks for.
Graph_LOD :: enum {
	Full,
	Compact,
	Dots,
}

//* The level of detail for a zoom, from the thresholds of the metrics.
Graph_LOD_Of :: proc(graph: ^Node_Graph, zoom: f32) -> Graph_LOD {
	metrics := Graph_Metrics_Of(graph)
	if zoom >= metrics.lod_full_zoom {return .Full}
	if zoom >= metrics.lod_compact_zoom {return .Compact}
	return .Dots
}
