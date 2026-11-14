package GUI

import "core:log"
import "core:math"
import virt "core:mem/virtual"

Node_Graph_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Node_Graph :: proc(g: ^GUI, parent: Widget_ID, opts: Node_Graph_Opts) -> Widget_ID {
	kind_register(g, .NodeGraph, node_graph_kind())
	id := New_Widget(g, .NodeGraph, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	graph, err := virt.new(&g.arena, Node_Graph)
	if err != nil {
		log.panicf("node graph allocation failed: %v", err)
	}
	graph^ = Node_Graph{
		selected = -1,
		dragging = -1,
		moving_node = -1,
		zoom = 1,
	}
	w.data = Node_Graph_Data{graph = graph}
	return id
}

node_graph_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_node_graph,
		click = click_node_graph,
		update = update_node_graph,
		pointer = pointer_node_graph,
		style = Style{},
		theme_name = "NodeGraph",
	}
}

node_graph_data :: proc(g: ^GUI, id: Widget_ID) -> ^Node_Graph_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Node_Graph_Data:
		return &d
	}
	return nil
}

node_graph_of :: proc(g: ^GUI, id: Widget_ID) -> ^Node_Graph {
	d := node_graph_data(g, id)
	if d == nil {return nil}
	return d.graph
}

//* Adds a node and returns its index.
node_graph_add_node :: proc(g: ^GUI, id: Widget_ID, title: string, pos: Vec2) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return -1}

	append(&graph.nodes, Graph_Node{
		title = title,
		pos = pos,
		size = Vec2{NODE_WIDTH, NODE_HEIGHT},
		colour = NODE_COLOUR,
	})
	invalidate(g, id, Dirty_Flags{.Visual})
	return len(graph.nodes) - 1
}

//* Adds an input or output port to a node.
node_graph_add_port :: proc(
	g: ^GUI,
	id: Widget_ID,
	node: int,
	name: string,
	direction: Graph_Port_Direction,
) -> int {
	graph := node_graph_of(g, id)
	if graph == nil || node < 0 || node >= len(graph.nodes) {return -1}

	append(&graph.nodes[node].ports, Graph_Port{
		name = name,
		direction = direction,
		wire = -1,
	})
	graph.nodes[node].size.y = node_graph_node_height(&graph.nodes[node])
	invalidate(g, id, Dirty_Flags{.Visual})
	return len(graph.nodes[node].ports) - 1
}

//* Connects two ports and returns the wire index.
node_graph_connect :: proc(
	g: ^GUI,
	id: Widget_ID,
	from_node, from_port, to_node, to_port: int,
) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return -1}
	if !node_graph_port_exists(graph, from_node, from_port) {return -1}
	if !node_graph_port_exists(graph, to_node, to_port) {return -1}

	append(&graph.wires, Graph_Wire{
		from_node = from_node,
		from_port = from_port,
		to_node = to_node,
		to_port = to_port,
		colour = WIRE_COLOUR,
	})
	index := len(graph.wires) - 1
	graph.nodes[from_node].ports[from_port].wire = index
	graph.nodes[to_node].ports[to_port].wire = index
	invalidate(g, id, Dirty_Flags{.Visual})
	return index
}

node_graph_node_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return 0}
	return len(graph.nodes)
}

node_graph_wire_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return 0}
	return len(graph.wires)
}

node_graph_node_at :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) -> int {
	graph := node_graph_of(g, id)
	if graph == nil {return -1}
	w := Widget_Get(g, id)
	if w == nil {return -1}

	p := node_graph_graph_pos(graph, content_rect(g, w), pos)
	found := -1
	for i in 0 ..< len(graph.nodes) {
		if rect_contains(node_graph_node_rect(&graph.nodes[i]), p.x, p.y) {
			found = i
		}
	}
	return found
}

node_graph_move_node :: proc(g: ^GUI, id: Widget_ID, node: int, pos: Vec2) {
	graph := node_graph_of(g, id)
	if graph == nil || node < 0 || node >= len(graph.nodes) {return}
	graph.nodes[node].pos = pos
	invalidate(g, id, Dirty_Flags{.Visual})
}

node_graph_select :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph, node: int) {
	if node < 0 || node >= len(graph.nodes) {return}
	graph.selected = node
	for i in 0 ..< len(graph.nodes) {
		graph.nodes[i].selected = i == node
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* View

NODE_GRAPH_MIN_ZOOM :: 0.25
NODE_GRAPH_MAX_ZOOM :: 4.0
NODE_GRAPH_ZOOM_STEP :: 1.1

node_graph_zoom_of :: proc(graph: ^Node_Graph) -> f32 {
	if graph == nil || !(graph.zoom > 0) {return 1}
	return graph.zoom
}

node_graph_pan_of :: proc(graph: ^Node_Graph) -> Vec2 {
	if graph == nil {return {}}
	zoom := node_graph_zoom_of(graph)
	return Vec2{-graph.scroll.x * zoom, -graph.scroll.y * zoom}
}

node_graph_view_sync :: proc(graph: ^Node_Graph) {
	if graph != nil {graph.pan = node_graph_pan_of(graph)}
}

node_graph_zoom :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	d := node_graph_data(g, id)
	if d == nil {return 1}
	return node_graph_zoom_of(d.graph)
}

//* Changes zoom while keeping the graph's screen position.
node_graph_set_zoom :: proc(g: ^GUI, id: Widget_ID, zoom: f32) {
	d := node_graph_data(g, id)
	if d == nil || d.graph == nil {return}

	graph := d.graph
	value := clamp(zoom, NODE_GRAPH_MIN_ZOOM, NODE_GRAPH_MAX_ZOOM)
	if !(value > 0) {value = 1}
	if value == graph.zoom {return}

	pan := node_graph_pan_of(graph)
	graph.zoom = value
	graph.scroll = Vec2{-pan.x / value, -pan.y / value}
	node_graph_view_sync(graph)
	invalidate(g, id, Dirty_Flags{.Visual})
}

node_graph_pan :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	d := node_graph_data(g, id)
	if d == nil {return {}}
	return node_graph_pan_of(d.graph)
}

node_graph_set_pan :: proc(g: ^GUI, id: Widget_ID, pan: Vec2) {
	d := node_graph_data(g, id)
	if d == nil || d.graph == nil {return}

	graph := d.graph
	zoom := node_graph_zoom_of(graph)
	graph.scroll = Vec2{-pan.x / zoom, -pan.y / zoom}
	graph.pan = pan
	invalidate(g, id, Dirty_Flags{.Visual})
}

node_graph_reset_view :: proc(g: ^GUI, id: Widget_ID) {
	d := node_graph_data(g, id)
	if d == nil || d.graph == nil {return}

	d.graph.zoom = 1
	d.graph.scroll = {}
	d.graph.pan = {}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Geometry and appearance

NODE_WIDTH :: 140
NODE_HEIGHT :: 56
NODE_TITLE_HEIGHT :: 24
NODE_PORT_SIZE :: 10
NODE_PORT_SPACING :: 18
NODE_RADIUS :: 6
WIRE_WIDTH :: 2

NODE_COLOUR :: Colour{0.18, 0.20, 0.25, 1}
NODE_PORT_INPUT_COLOUR :: Colour{0.45, 0.72, 0.95, 1}
NODE_PORT_OUTPUT_COLOUR :: Colour{0.98, 0.72, 0.35, 1}
NODE_PORT_WIRED_COLOUR :: Colour{0.45, 0.85, 0.55, 1}
WIRE_COLOUR :: Colour{0.62, 0.66, 0.74, 1}
NODE_SELECTED_COLOUR :: Colour{0.35, 0.74, 1.00, 1}

node_graph_screen_pos :: proc(graph: ^Node_Graph, content: Rect, pos: Vec2) -> Vec2 {
	zoom := node_graph_zoom_of(graph)
	return Vec2{
		content.x + (pos.x - graph.scroll.x) * zoom,
		content.y + (pos.y - graph.scroll.y) * zoom,
	}
}

node_graph_graph_pos :: proc(graph: ^Node_Graph, content: Rect, pos: Vec2) -> Vec2 {
	zoom := node_graph_zoom_of(graph)
	return Vec2{
		graph.scroll.x + (pos.x - content.x) / zoom,
		graph.scroll.y + (pos.y - content.y) / zoom,
	}
}

node_graph_node_rect :: proc(node: ^Graph_Node) -> Rect {
	return Rect{
		x = node.pos.x,
		y = node.pos.y,
		w = node.size.x,
		h = node_graph_node_height(node),
	}
}

node_graph_node_height :: proc(node: ^Graph_Node) -> f32 {
	inputs, outputs := 0, 0
	for port in node.ports {
		if node_graph_port_side(port) == .Input {
			inputs += 1
		} else {
			outputs += 1
		}
	}
	return max(node.size.y, NODE_TITLE_HEIGHT + f32(max(inputs, outputs)) * NODE_PORT_SPACING + 6)
}

node_graph_port_side :: proc(port: Graph_Port) -> Graph_Port_Direction {
	if port.direction == .Input {return .Input}
	return .Output
}

node_graph_port_pos :: proc(graph: ^Node_Graph, node_index, port_index: int) -> Vec2 {
	node := &graph.nodes[node_index]
	port := node.ports[port_index]
	x := node.pos.x
	if node_graph_port_side(port) == .Output {x += node.size.x}

	n := 0
	for i in 0 ..< port_index {
		if node_graph_port_side(node.ports[i]) == node_graph_port_side(port) {n += 1}
	}
	y := node.pos.y + NODE_TITLE_HEIGHT + f32(n) * NODE_PORT_SPACING + NODE_PORT_SIZE * 0.5
	return Vec2{x, y}
}

node_graph_port_exists :: proc(graph: ^Node_Graph, node, port: int) -> bool {
	return node >= 0 && node < len(graph.nodes) &&
		port >= 0 && port < len(graph.nodes[node].ports)
}

node_graph_port_at :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) -> (node, port: int) {
	graph := node_graph_of(g, id)
	if graph == nil {return -1, -1}
	w := Widget_Get(g, id)
	if w == nil {return -1, -1}

	p := node_graph_graph_pos(graph, content_rect(g, w), pos)
	found_node, found_port := -1, -1
	for i in 0 ..< len(graph.nodes) {
		for j in 0 ..< len(graph.nodes[i].ports) {
			centre := node_graph_port_pos(graph, i, j)
			r := Rect{
				x = centre.x - NODE_PORT_SIZE * 0.5,
				y = centre.y - NODE_PORT_SIZE * 0.5,
				w = NODE_PORT_SIZE,
				h = NODE_PORT_SIZE,
			}
			if rect_contains(r, p.x, p.y) {
				found_node, found_port = i, j
			}
		}
	}
	return found_node, found_port
}

//* Drawing

draw_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	graph := node_graph_of(g, id)
	if graph == nil {return}

	for i in 0 ..< len(graph.wires) {
		node_graph_draw_wire(g, graph, content, i)
	}
	for i in 0 ..< len(graph.nodes) {
		node_graph_draw_node(g, graph, w, content, i)
	}
}

node_graph_draw_wire :: proc(g: ^GUI, graph: ^Node_Graph, content: Rect, index: int) {
	wire := &graph.wires[index]
	if !node_graph_port_exists(graph, wire.from_node, wire.from_port) {return}

	a := node_graph_screen_pos(graph, content,
		node_graph_port_pos(graph, wire.from_node, wire.from_port))
	b: Vec2
	if index == graph.dragging {
		b = node_graph_screen_pos(graph, content,
			node_graph_graph_pos(graph, content, g.pointer))
	} else {
		if !node_graph_port_exists(graph, wire.to_node, wire.to_port) {return}
		b = node_graph_screen_pos(graph, content,
			node_graph_port_pos(graph, wire.to_node, wire.to_port))
	}

	colour := wire.colour
	if colour.a <= 0 {colour = WIRE_COLOUR}
	mid := Vec2{(a.x + b.x) * 0.5, a.y}
	width := WIRE_WIDTH * node_graph_zoom_of(graph)
	draw_thick_line(g.target, {a.x, a.y}, {mid.x, mid.y}, width, colour, g.atlas_texture)
	draw_thick_line(g.target, {mid.x, mid.y}, {b.x, b.y}, width, colour, g.atlas_texture)
}

node_graph_node_screen_rect :: proc(graph: ^Node_Graph, content: Rect, index: int) -> Rect {
	node := &graph.nodes[index]
	r := node_graph_node_rect(node)
	pos := node_graph_screen_pos(graph, content, node.pos)
	zoom := node_graph_zoom_of(graph)
	return Rect{x = pos.x, y = pos.y, w = r.w * zoom, h = r.h * zoom}
}

node_graph_draw_node :: proc(g: ^GUI, graph: ^Node_Graph, w: ^Widget, content: Rect, index: int) {
	node := &graph.nodes[index]
	zoom := node_graph_zoom_of(graph)
	r := node_graph_node_screen_rect(graph, content, index)
	colour := node.colour
	if colour.a <= 0 {colour = NODE_COLOUR}
	draw_rect(g, r, colour, NODE_RADIUS * zoom)

	style := resolved_style(g, w)
	title := Rect{
		x = r.x + 8 * zoom,
		y = r.y,
		w = max(r.w - 16 * zoom, 1),
		h = NODE_TITLE_HEIGHT,
	}
	draw_text(g, style.text, node.title, title, resolved_text_colour(g, w.id, w))

	for j in 0 ..< len(node.ports) {
		port := node.ports[j]
		centre := node_graph_screen_pos(graph, content, node_graph_port_pos(graph, index, j))
		size := NODE_PORT_SIZE * zoom
		draw_rect(g, Rect{
			x = centre.x - size * 0.5,
			y = centre.y - size * 0.5,
			w = size,
			h = size,
		}, node_graph_port_colour(port), 0)
	}

	if graph.selected == index {
		draw_outline(g, r, NODE_SELECTED_COLOUR, 2 * zoom)
	}
}

node_graph_port_colour :: proc(port: Graph_Port) -> Colour {
	if port.wire >= 0 {return NODE_PORT_WIRED_COLOUR}
	if port.direction == .Input {return NODE_PORT_INPUT_COLOUR}
	return NODE_PORT_OUTPUT_COLOUR
}

//* Pointer and interaction

pointer_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	graph := node_graph_of(g, id)
	if graph == nil {return}

	switch e.kind {
	case .Wheel:
		node_graph_wheel(g, id, w, graph, e)
	case .Down:
		node_graph_pointer_down(graph, e)
	case .Move:
		node_graph_pointer_move(g, id, graph, e)
	case .Up:
		node_graph_pointer_up(graph, e)
	}
}

node_graph_wheel :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, graph: ^Node_Graph, e: Pointer_Event) {
	if e.amount == 0 {return}
	content := content_rect(g, w)
	zoom := node_graph_zoom_of(graph) * math.pow_f32(NODE_GRAPH_ZOOM_STEP, e.amount)
	node_graph_zoom_at(graph, content, e.pos, zoom)
	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

//* Zooms around the pointer, keeping its graph position fixed.
node_graph_zoom_at :: proc(graph: ^Node_Graph, content: Rect, screen: Vec2, zoom: f32) {
	value := clamp(zoom, NODE_GRAPH_MIN_ZOOM, NODE_GRAPH_MAX_ZOOM)
	if !(value > 0) {value = 1}
	if value == graph.zoom {return}

	point := node_graph_graph_pos(graph, content, screen)
	graph.zoom = value
	graph.scroll = Vec2{
		point.x - (screen.x - content.x) / value,
		point.y - (screen.y - content.y) / value,
	}
	node_graph_view_sync(graph)
}

node_graph_pointer_down :: proc(graph: ^Node_Graph, e: Pointer_Event) {
	if e.button != .Middle {return}
	graph.panning = true
	graph.pan_last = e.pos
}

node_graph_pointer_move :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph, e: Pointer_Event) {
	if !graph.panning {return}
	delta := vec2_sub(e.pos, graph.pan_last)
	graph.pan_last = e.pos
	if delta.x == 0 && delta.y == 0 {return}

	node_graph_pan_by(graph, delta)
	invalidate(g, id, Dirty_Flags{.Visual})
}

node_graph_pointer_up :: proc(graph: ^Node_Graph, e: Pointer_Event) {
	if e.button == .Middle {graph.panning = false}
}

node_graph_pan_by :: proc(graph: ^Node_Graph, delta: Vec2) {
	zoom := node_graph_zoom_of(graph)
	graph.scroll = Vec2{
		graph.scroll.x - delta.x / zoom,
		graph.scroll.y - delta.y / zoom,
	}
	node_graph_view_sync(graph)
}

click_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	graph := node_graph_of(g, id)
	if graph == nil {return}

	node_graph_end_wire(g, id, graph)
	node := node_graph_node_at(g, id, g.pointer)
	if node < 0 {return}

	node_graph_select(g, id, graph, node)
	signal_item_selected(g, id, node)
}

update_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	graph := node_graph_of(g, id)
	if graph == nil {return}

	content := content_rect(g, w)
	pointer := node_graph_graph_pos(graph, content, g.pointer)

	if graph.panning &&
		(!g.lmb_down || !rect_contains(content, g.pointer.x, g.pointer.y)) {
		graph.panning = false
	}

	if g.lmb_down && g.active == id {
		if graph.dragging >= 0 {return}
		node, port := node_graph_port_at(g, id, g.pointer)
		if port >= 0 {
			node_graph_begin_wire(g, graph, node, port)
			return
		}
		node_graph_drag_node(g, id, graph, pointer)
		return
	}

	if graph.dragging >= 0 {
		node_graph_end_wire(g, id, graph)
	}
	graph.moving_node = -1
}

//* Drags a node while preserving the pointer's offset from its origin.
node_graph_drag_node :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph, pointer: Vec2) {
	if graph.moving_node >= 0 && graph.moving_node < len(graph.nodes) {
		node := &graph.nodes[graph.moving_node]
		node.pos = Vec2{pointer.x - graph.drag_offset.x, pointer.y - graph.drag_offset.y}
		return
	}

	node := node_graph_node_at(g, id, g.pointer)
	if node < 0 {return}

	node_graph_select(g, id, graph, node)
	graph.moving_node = node
	graph.drag_offset = Vec2{
		pointer.x - graph.nodes[node].pos.x,
		pointer.y - graph.nodes[node].pos.y,
	}
}

node_graph_begin_wire :: proc(g: ^GUI, graph: ^Node_Graph, node, port: int) {
	if graph.dragging >= 0 || !node_graph_port_exists(graph, node, port) {return}

	append(&graph.wires, Graph_Wire{
		from_node = node,
		from_port = port,
		to_node = -1,
		to_port = -1,
		colour = WIRE_COLOUR,
	})
	graph.dragging = len(graph.wires) - 1
	graph.nodes[node].ports[port].wire = graph.dragging
}

node_graph_end_wire :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph) {
	index := graph.dragging
	if index < 0 {return}
	if index >= len(graph.wires) {
		graph.dragging = -1
		return
	}

	from_node := graph.wires[index].from_node
	node, port := node_graph_port_at(g, id, g.pointer)
	if node >= 0 && port >= 0 && node != from_node {
		graph.wires[index].to_node = node
		graph.wires[index].to_port = port
		graph.nodes[node].ports[port].wire = index
		graph.dragging = -1
		return
	}

	node_graph_remove_wire(graph, index)
	graph.dragging = -1
}

node_graph_remove_wire :: proc(graph: ^Node_Graph, index: int) {
	if index < 0 || index >= len(graph.wires) {return}

	wire := graph.wires[index]
	if node_graph_port_exists(graph, wire.from_node, wire.from_port) {
		port := &graph.nodes[wire.from_node].ports[wire.from_port]
		if port.wire == index {port.wire = -1}
	}

	ordered_remove(&graph.wires, index)
	for i in 0 ..< len(graph.nodes) {
		for j in 0 ..< len(graph.nodes[i].ports) {
			if graph.nodes[i].ports[j].wire > index {
				graph.nodes[i].ports[j].wire -= 1
			}
		}
	}
}