//* The node graph widget: the canvas, the drawing, the pointer and keyboard
//* input, the creation menu and the inspector view.

package NodeGraph

import Core "../Core"
import Widgets "../Widgets"
import "core:fmt"
import "core:log"
import "core:math"
import "core:strconv"
import "core:strings"
import virt "core:mem/virtual"

//* The GUI names the widget code uses, so the moved widget reads exactly
//* like it did in Widgets.
Base_Opts :: Core.Base_Opts
Box_Opts :: Core.Box_Opts
Button_Opts :: Core.Button_Opts
Check_Box_Opts :: Core.Check_Box_Opts
Colour :: Core.Colour
Combo_Box_Opts :: Core.Combo_Box_Opts
Command_Palette_Count :: Core.Command_Palette_Count
Command_Palette_Data :: Core.Command_Palette_Data
Command_Palette_Opts :: Core.Command_Palette_Opts
DIRTY_ALL :: Core.DIRTY_ALL
Dirty_Flags :: Core.Dirty_Flags
Event_Handled :: Core.Event_Handled
Focus_Set :: Core.Focus_Set
GUI :: Core.GUI
INVALID_WIDGET_ID :: Core.INVALID_WIDGET_ID
Key_Down_Event :: Core.Key_Down_Event
Label_Opts :: Core.Label_Opts
Make_Button :: Widgets.Make_Button
Make_Check_Box :: Widgets.Make_Check_Box
Make_Combo_Box :: Widgets.Make_Combo_Box
Make_Command_Palette :: Widgets.Make_Command_Palette
Make_HBox :: Widgets.Make_HBox
Make_Label :: Widgets.Make_Label
Make_Scroll_Container :: Widgets.Make_Scroll_Container
Make_Text_Box :: Core.Make_Text_Box
Make_VBox :: Widgets.Make_VBox
New_Widget :: Core.New_Widget
Node_Graph_Data :: Core.Node_Graph_Data
Node_Graph_Inspector_Data :: Core.Node_Graph_Inspector_Data
Node_Graph_Opts :: Core.Node_Graph_Opts
PALETTE_FIELD_HEIGHT :: Widgets.PALETTE_FIELD_HEIGHT
PALETTE_ROW :: Widgets.PALETTE_ROW
Palette_Command :: Core.Palette_Command
Pointer_Event :: Core.Pointer_Event
Popup_Attach_To_Root :: Core.Popup_Attach_To_Root
Popup_Is_Open :: Core.Popup_Is_Open
Popup_Open :: Core.Popup_Open
RGBA :: Core.RGBA
Rect :: Core.Rect
Scale_Colour :: Core.Scale_Colour
Scene_Constructor_Of :: Widgets.Scene_Constructor_Of
Scene_Register_Constructor :: Widgets.Scene_Register_Constructor
Scroll_Container_Opts :: Core.Scroll_Container_Opts
Style :: Core.Style
StyleBox :: Core.StyleBox
Text_Box_Data :: Core.Text_Box_Data
Text_Box_Opts :: Core.Text_Box_Opts
Text_Style :: Core.Text_Style
Vec2 :: Core.Vec2
Vec3 :: Core.Vec3
Widget :: Core.Widget
Widget_Alive :: Core.Widget_Alive
Widget_Capture_Pointer :: Core.Widget_Capture_Pointer
Widget_Free :: Core.Widget_Free
Widget_Get :: Core.Widget_Get
Widget_ID :: Core.Widget_ID
Widget_Kind :: Core.Widget_Kind
Widget_Release_Pointer :: Core.Widget_Release_Pointer
Widget_Set_Text :: Core.Widget_Set_Text
Widget_Set_Visible :: Core.Widget_Set_Visible
base_widget_opts :: Core.base_widget_opts
combo_box_select :: Widgets.combo_box_select
command_palette_data :: Core.command_palette_data
content_rect :: Core.content_rect
draw_outline :: Core.draw_outline
draw_polygon :: Core.draw_polygon
draw_rect :: Core.draw_rect
draw_round_border :: Core.draw_round_border
draw_stylebox_box :: Core.draw_stylebox_box
draw_text :: Core.draw_text
draw_thick_line :: Core.draw_thick_line
invalidate :: Core.invalidate
kind_register :: Core.kind_register
popup_set_rect :: Core.popup_set_rect
rect_contains :: Core.rect_contains
resolved_style :: Core.resolved_style
resolved_text_colour :: Core.resolved_text_colour
text_measure :: Core.text_measure
theme_color :: Core.theme_color
theme_constant_ok :: Core.theme_constant_ok
uses_arrow_keys :: Core.uses_arrow_keys

NODE_RADIUS :: 6
WIRE_HIT_TOLERANCE :: 7
PORT_HIT_TOLERANCE :: 11
COLLAPSE_BUTTON_SIZE :: 12
RESIZE_HANDLE_SIZE :: 12

NODE_COLOUR :: Colour{0.18, 0.20, 0.25, 1}
NODE_PORT_INPUT_COLOUR :: Colour{0.45, 0.72, 0.95, 1}
NODE_PORT_OUTPUT_COLOUR :: Colour{0.98, 0.72, 0.35, 1}
NODE_PORT_WIRED_COLOUR :: Colour{0.45, 0.85, 0.55, 1}
WIRE_COLOUR :: Colour{0.62, 0.66, 0.74, 1}
NODE_SELECTED_COLOUR :: Colour{0.35, 0.74, 1.00, 1}
NODE_HOVER_COLOUR :: Colour{0.55, 0.62, 0.72, 1}
NODE_COMPATIBLE_COLOUR :: Colour{0.40, 0.90, 0.55, 1}
NODE_INCOMPATIBLE_COLOUR :: Colour{0.95, 0.35, 0.35, 1}
GRAPH_GRID_MINOR_COLOUR :: Colour{0.16, 0.18, 0.22, 1}
GRAPH_GRID_MAJOR_COLOUR :: Colour{0.22, 0.25, 0.31, 1}
GRAPH_MARQUEE_COLOUR :: Colour{0.35, 0.74, 1.0, 0.16}
GRAPH_MARQUEE_BORDER_COLOUR :: Colour{0.35, 0.74, 1.0, 0.85}

Make_Node_Graph :: proc(g: ^GUI, parent: Widget_ID, opts: Node_Graph_Opts) -> Widget_ID {
	node_graph_register_scene(g)
	kind_register(g, .NodeGraph, node_graph_kind())
	id := New_Widget(g, .NodeGraph, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.clip_contents = opts.Base_Opts.clip_contents != .Off
	w.focus_mode = .Click
	w.mouse_filter = .Stop
	w.interactive = false

	graph, err := virt.new(&g.arena, Node_Graph)
	if err != nil {
		log.panicf("node graph allocation failed: %v", err)
	}
	graph^ = Node_Graph{}
	graph_defaults(graph)
	if opts.zoom > 0 {graph.zoom = clamp(opts.zoom, NODE_GRAPH_MIN_ZOOM, NODE_GRAPH_MAX_ZOOM)}
	if opts.min_zoom > 0 {graph.min_zoom = opts.min_zoom}
	if opts.max_zoom > 0 {graph.max_zoom = opts.max_zoom}
	if opts.grid_size > 0 {graph.grid_size = opts.grid_size}
	if opts.grid_major > 0 {graph.grid_major = opts.grid_major}
	graph.grid_visible = true
	graph.snap = opts.snap
	reset_graph_transient(graph)

	w.data = Node_Graph_Data{graph = rawptr(graph), menu = INVALID_WIDGET_ID}
	node_graph_register_builtin_actions(g, id)
	return id
}

node_graph_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw        = draw_node_graph,
		pointer     = pointer_node_graph,
		key         = key_node_graph,
		post_update = post_update_node_graph,
		destroy     = destroy_node_graph,
		interactive = true,
		uses_arrow_keys = true,
		style       = Style{},
		theme_name  = "NodeGraph",
		scene_save_text = scene_save_node_graph,
	}
}

//* The text a scene file writes for a node graph: its whole serialized model.
scene_save_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> string {
	return node_graph_save(g, id)
}

//* A scene file needs a constructor before it can read a node graph. The
//* widget registers its own, so a program that uses the node graph does not
//* have to know about the scene loader.
node_graph_register_scene :: proc(g: ^GUI) {
	if g == nil {return}
	if Scene_Constructor_Of(g, .NodeGraph) == nil {
		Scene_Register_Constructor(g, .NodeGraph, scene_constructor_node_graph)
	}
}

scene_constructor_node_graph :: proc(
	g: ^GUI,
	parent: Widget_ID,
	name: string,
	text: string,
) -> Widget_ID {
	id := Make_Node_Graph(g, parent, Node_Graph_Opts{Base_Opts = Base_Opts{name = name}})
	//* The text of a node graph is its serialized graph.
	if text != "" {node_graph_load(g, id, text)}
	return id
}

destroy_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	#partial switch &d in w.data {
	case Node_Graph_Data:
		if Widget_Alive(g, d.menu) {Widget_Free(g, d.menu)}
		d.menu = INVALID_WIDGET_ID
		graph := cast(^Node_Graph)d.graph
		if graph != nil {Graph_Free_Storage(graph)}
	}
}


reset_graph_transient :: proc(graph: ^Node_Graph) {
	graph.mode = .None
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
	graph.active_wire = INVALID_GRAPH_WIRE_ID
	graph.hover_node = INVALID_GRAPH_NODE_ID
	graph.hover_port = INVALID_GRAPH_PORT_ID
	graph.hover_port_node = INVALID_GRAPH_NODE_ID
	graph.hover_wire = INVALID_GRAPH_WIRE_ID
	graph.resize_node = INVALID_GRAPH_NODE_ID
	clear(&graph.dragging_nodes)
	clear(&graph.drag_starts)
}

//* == Appearance ==

Graph_Theme_Names :: struct {
	grid_minor:      string,
	grid_major:      string,
	node_bg:         string,
	node_border:     string,
	node_shadow:     string,
	header:          string,
	header_accent:   string,
	collapsed:       string,
	selected:        string,
	hovered:         string,
	input:           string,
	output:          string,
	wired:           string,
	compatible:      string,
	incompatible:    string,
	pin_ring:        string,
	wire:            string,
	wire_hover:      string,
	wire_selected:   string,
	wire_glow:       string,
	marquee:         string,
	resize:          string,
	text:            string,
	region_fill:     string,
	region_border:   string,
	region_header:   string,
	region_text:     string,
}

GRAPH_THEME :: Graph_Theme_Names{
	grid_minor = "grid_minor",
	grid_major = "grid_major",
	node_bg = "node_bg",
	node_border = "node_border",
	node_shadow = "node_shadow",
	header = "header",
	header_accent = "header_accent",
	collapsed = "collapsed",
	selected = "selected",
	hovered = "hovered",
	input = "input",
	output = "output",
	wired = "wired",
	compatible = "compatible",
	incompatible = "incompatible",
	pin_ring = "pin_ring",
	wire = "wire",
	wire_hover = "wire_hover",
	wire_selected = "wire_selected",
	wire_glow = "wire_glow",
	marquee = "marquee",
	resize = "resize",
	text = "text",
	region_fill = "region_fill",
	region_border = "region_border",
	region_header = "region_header",
	region_text = "region_text",
}

graph_colour :: proc(g: ^GUI, w: ^Widget, name: string, fallback: Colour) -> Colour {
	colour := theme_color(g, w, name)
	if colour.a <= 0 {return fallback}
	return colour
}

//* == Metrics ==

graph_metrics_of :: proc(graph: ^Node_Graph) -> Graph_Metrics {
	return Graph_Metrics_Of(graph)
}

//* The value of a theme constant, or the fallback when the theme does not
//* hold it. A theme that sets a constant to zero means zero.
graph_theme_metric :: proc(g: ^GUI, w: ^Widget, name: string, fallback: f32) -> f32 {
	value, found := theme_constant_ok(g, w, name)
	if !found {return fallback}
	return value
}

//* Resolves the metrics of a graph: the built-in ones, then the constants of
//* the theme, then the overrides of the style of the graph.
graph_resolve_metrics :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph) -> Graph_Metrics {
	base := Graph_Metrics_Defaults()
	base.title_height = graph_theme_metric(g, w, "title_height", base.title_height)
	base.port_spacing = graph_theme_metric(g, w, "port_spacing", base.port_spacing)
	base.port_size = graph_theme_metric(g, w, "port_size", base.port_size)
	base.pin_ring_width = graph_theme_metric(g, w, "pin_ring_width", base.pin_ring_width)
	base.corner_radius = graph_theme_metric(g, w, "corner_radius", base.corner_radius)
	base.title_font_size = graph_theme_metric(g, w, "title_font_size", base.title_font_size)
	base.pin_font_size = graph_theme_metric(g, w, "pin_font_size", base.pin_font_size)
	base.config_font_size = graph_theme_metric(g, w, "config_font_size", base.config_font_size)
	base.wire_width = graph_theme_metric(g, w, "wire_width", base.wire_width)
	base.wire_glow_width = graph_theme_metric(g, w, "wire_glow", base.wire_glow_width)
	base.arrow_size = graph_theme_metric(g, w, "arrow_size", base.arrow_size)
	base.badge_height = graph_theme_metric(g, w, "badge_height", base.badge_height)
	base.badge_padding = graph_theme_metric(g, w, "badge_padding", base.badge_padding)
	base.node_shadow = graph_theme_metric(g, w, "shadow_size", base.node_shadow)
	base.shadow_opacity = graph_theme_metric(g, w, "shadow_opacity", base.shadow_opacity)
	base.lod_full_zoom = graph_theme_metric(g, w, "lod_full_zoom", base.lod_full_zoom)
	base.lod_compact_zoom = graph_theme_metric(g, w, "lod_compact_zoom", base.lod_compact_zoom)
	base.region_header_height = graph_theme_metric(g, w, "region_header_height", base.region_header_height)
	base.region_padding = graph_theme_metric(g, w, "region_padding", base.region_padding)
	base.region_title_font_size = graph_theme_metric(g, w, "region_title_font_size", base.region_title_font_size)
	return Graph_Metrics_Apply(base, graph.style)
}

//* Reads the metrics of the theme into the graph. A change of the theme or
//* of the style invalidates the geometry of the graph.
graph_update_metrics :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph) {
	if graph == nil {return}
	Graph_Set_Metrics(graph, graph_resolve_metrics(g, w, graph))
}

//* == Drawing ==

node_graph_node_screen_rect :: proc(graph: ^Node_Graph, content: Rect, node: ^Graph_Node) -> Rect {
	pos := node_graph_screen_pos(graph, content, node.pos)
	zoom := graph_zoom_of(graph)
	rect := Graph_Node_Rect_Of(graph, node)
	return Rect{x = pos.x, y = pos.y, w = rect.w * zoom, h = rect.h * zoom}
}

graph_rect_visible :: proc(rect, clip: Rect) -> bool {
	return rect.x < clip.x + clip.w && rect.x + rect.w > clip.x &&
		rect.y < clip.y + clip.h && rect.y + rect.h > clip.y
}

draw_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph_update_metrics(g, w, graph)
	metrics := graph_metrics_of(graph)
	zoom := graph_zoom_of(graph)
	lod := Graph_LOD_Of(graph, zoom)

	draw_graph_grid(g, w, graph, content, lod)

	visible := graph_visible_rect(graph, content)
	draw_graph_regions(g, w, graph, content, visible)

	for i := 0; i < len(graph.wires); i += 1 {
		wire := &graph.wires[i]
		if !wire.alive {continue}
		if graph_wire_visible(graph, wire, visible) {draw_graph_wire(g, w, graph, content, wire, lod)}
	}
	if graph.mode == .Drag_Wire || graph.mode == .Reconnect_Wire {
		draw_graph_pending_wire(g, w, graph, content, lod)
	}

	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		if graph_rect_visible(graph_node_rect(graph, node), visible) {
			draw_graph_node(g, w, graph, content, node, lod)
		}
	}

	if graph.mode == .Marquee {draw_graph_marquee(g, w, graph, content)}
	draw_graph_tooltip(g, w, graph, content)
}

graph_visible_rect :: proc(graph: ^Node_Graph, content: Rect) -> Rect {
	a := node_graph_graph_pos(graph, content, {content.x, content.y})
	b := node_graph_graph_pos(graph, content, {content.x + content.w, content.y + content.h})
	return Rect{x = a.x, y = a.y, w = b.x - a.x, h = b.y - a.y}
}

draw_graph_grid :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph, content: Rect, lod: Graph_LOD) {
	if !graph.grid_visible {return}
	zoom := graph_zoom_of(graph)
	spacing := graph.grid_size * zoom
	if !(spacing > 0) {return}
	major := max(graph.grid_major, 1)

	minor_colour := graph_colour(g, w, GRAPH_THEME.grid_minor, GRAPH_GRID_MINOR_COLOUR)
	major_colour := graph_colour(g, w, GRAPH_THEME.grid_major, GRAPH_GRID_MAJOR_COLOUR)

	visible := graph_visible_rect(graph, content)
	step := graph.grid_size
	if step <= 0 {return}
	//* When the minor lines would be too dense to read, only the major
	//* lines are drawn; the stride keeps the line count bounded.
	minor := spacing >= 6 && lod != .Dots
	if !minor {step = graph.grid_size * major}
	first_x := math.floor(visible.x / step) * step
	first_y := math.floor(visible.y / step) * step
	columns := int(visible.w / step) + 2
	rows := int(visible.h / step) + 2

	for column in 0 ..= columns {
		x := first_x + f32(column) * step
		index := int(math.round(x / step))
		colour := major_colour
		if minor && index % int(major) != 0 {colour = minor_colour}
		a := node_graph_screen_pos(graph, content, Vec2{x, visible.y})
		b := node_graph_screen_pos(graph, content, Vec2{x, visible.y + visible.h})
		draw_thick_line(g.target, {a.x, max(a.y, content.y)}, {b.x, min(b.y, content.y + content.h)},
			1, colour, g.atlas_texture)
	}
	for row in 0 ..= rows {
		y := first_y + f32(row) * step
		index := int(math.round(y / step))
		colour := major_colour
		if minor && index % int(major) != 0 {colour = minor_colour}
		a := node_graph_screen_pos(graph, content, Vec2{visible.x, y})
		b := node_graph_screen_pos(graph, content, Vec2{visible.x + visible.w, y})
		draw_thick_line(g.target, {max(a.x, content.x), a.y}, {min(b.x, content.x + content.w), b.y},
			1, colour, g.atlas_texture)
	}
}

graph_wire_visible :: proc(graph: ^Node_Graph, wire: ^Graph_Wire, visible: Rect) -> bool {
	bounds := Graph_Wire_BBox_Of(graph, wire)
	if bounds.w <= 0 && bounds.h <= 0 {return false}
	return graph_rect_visible(Rect{
		x = bounds.x - 8,
		y = bounds.y - 8,
		w = bounds.w + 16,
		h = bounds.h + 16,
	}, visible)
}

//* The end of the wire that stays put while the other end follows the
//* pointer. A new drag starts at the active port; a reconnect keeps the end
//* the pointer is not over.
graph_wire_source_node :: proc(graph: ^Node_Graph) -> Graph_Node_ID {
	if graph.mode != .Reconnect_Wire {return graph.active_port_node}
	active := node_graph_wire_of(graph, graph.active_wire)
	if active == nil {return graph.active_port_node}
	if hovered := node_graph_port_of(graph, graph.hover_port_node, graph.hover_port); hovered != nil {
		if hovered.direction == .Output {return active.to_node}
	}
	return active.from_node
}

graph_wire_source_port :: proc(graph: ^Node_Graph) -> Graph_Port_ID {
	if graph.mode != .Reconnect_Wire {return graph.active_port}
	active := node_graph_wire_of(graph, graph.active_wire)
	if active == nil {return graph.active_port}
	if hovered := node_graph_port_of(graph, graph.hover_port_node, graph.hover_port); hovered != nil {
		if hovered.direction == .Output {return active.to_port}
	}
	return active.from_port
}

//* The colour of a wire: the colour of its type, the selection colour when
//* it is selected, and a brighter one when the pointer is on it.
graph_wire_draw_colour :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph, wire: ^Graph_Wire) -> Colour {
	colour := Graph_Wire_Colour(graph, wire)
	if colour.a <= 0 {colour = graph_colour(g, w, GRAPH_THEME.wire, WIRE_COLOUR)}
	if wire.selected {return graph_colour(g, w, GRAPH_THEME.wire_selected, NODE_SELECTED_COLOUR)}
	if graph.hover_wire == wire.id {
		return graph_colour(g, w, GRAPH_THEME.wire_hover, NODE_HOVER_COLOUR)
	}
	return colour
}

//* The colour of the source and the target of a wire, so that the core of
//* the wire can fade from one type into the other.
graph_wire_end_colours :: proc(graph: ^Node_Graph, wire: ^Graph_Wire) -> (Colour, Colour) {
	source := Graph_Port_Colour(graph, wire.from_node, wire.from_port)
	target := Graph_Port_Colour(graph, wire.to_node, wire.to_port)
	if source.a <= 0 {source = GRAPH_TYPE_WILDCARD_COLOUR}
	if target.a <= 0 {target = GRAPH_TYPE_WILDCARD_COLOUR}
	return source, target
}

draw_graph_wire :: proc(
	g: ^GUI,
	w: ^Widget,
	graph: ^Node_Graph,
	content: Rect,
	wire: ^Graph_Wire,
	lod: Graph_LOD,
) {
	colour := graph_wire_draw_colour(g, w, graph, wire)
	source_colour, target_colour := graph_wire_end_colours(graph, wire)
	metrics := graph_metrics_of(graph)
	zoom := graph_zoom_of(graph)
	width := max(metrics.wire_width * zoom, 1)
	if lod == .Dots {width = 1}
	glow := metrics.wire_glow_width * zoom
	graph_draw_wire_segments(g, graph, content, wire, colour, source_colour, target_colour, width, glow, lod)
}

//* Blends two colours. The wire core fades from the type of its source into
//* the type of its target.
graph_blend_colour :: proc(a, b: Colour, t: f32) -> Colour {
	if t <= 0 {return a}
	if t >= 1 {return b}
	return Colour{
		a.r + (b.r - a.r) * t,
		a.g + (b.g - a.g) * t,
		a.b + (b.b - a.b) * t,
		a.a + (b.a - a.a) * t,
	}
}

//* Rounds the bends of a path by cutting the corners. The path that routes
//* a wire stays sharp; only the drawn path is rounded.
graph_chamfer_path :: proc(points: []Vec2, count: int, radius: f32) -> ([32]Vec2, int) {
	out: [32]Vec2
	if count <= 0 {return out, 0}
	if count == 1 {
		out[0] = points[0]
		return out, 1
	}
	out_count := 0
	out[out_count] = points[0]
	out_count += 1
	for i in 1 ..< count - 1 {
		previous := points[i - 1]
		current := points[i]
		next := points[i + 1]
		in_x := current.x - previous.x
		in_y := current.y - previous.y
		out_x := next.x - current.x
		out_y := next.y - current.y
		in_len := math.sqrt(in_x * in_x + in_y * in_y)
		out_len := math.sqrt(out_x * out_x + out_y * out_y)
		if in_len <= 0.001 || out_len <= 0.001 {
			if out_count < len(out) {
				out[out_count] = current
				out_count += 1
			}
			continue
		}
		corner := min(radius, min(in_len, out_len) * 0.5)
		if corner <= 0.01 {
			if out_count < len(out) {
				out[out_count] = current
				out_count += 1
			}
			continue
		}
		if out_count + 1 < len(out) {
			out[out_count] = Vec2{current.x - in_x / in_len * corner, current.y - in_y / in_len * corner}
			out_count += 1
			out[out_count] = Vec2{current.x + out_x / out_len * corner, current.y + out_y / out_len * corner}
			out_count += 1
		}
	}
	if out_count < len(out) {
		out[out_count] = points[count - 1]
		out_count += 1
	}
	return out, out_count
}

graph_draw_wire_segments :: proc(
	g: ^GUI,
	graph: ^Node_Graph,
	content: Rect,
	wire: ^Graph_Wire,
	colour: Colour,
	source_colour: Colour,
	target_colour: Colour,
	width: f32,
	glow: f32,
	lod: Graph_LOD,
) {
	path := Graph_Wire_Path_Of(graph, wire)
	if path.count < 2 {return}

	chamfered: [32]Vec2
	points: []Vec2
	count: int
	if lod == .Dots {
		points = path.points[:path.count]
		count = path.count
	} else {
		chamfered, count = graph_chamfer_path(path.points[:], path.count, 6)
		points = chamfered[:count]
	}
	if count < 2 {return}

	//* The glow sits under the core and gives the wire its light.
	if lod == .Full && glow > 0 {
		glow_colour := colour
		glow_colour.a *= 0.22
		for i in 1 ..< count {
			previous := node_graph_screen_pos(graph, content, points[i - 1])
			current := node_graph_screen_pos(graph, content, points[i])
			draw_thick_line(g.target, {previous.x, previous.y}, {current.x, current.y}, glow, glow_colour, g.atlas_texture)
		}
	}

	segments := count - 1
	for i in 1 ..< count {
		previous := node_graph_screen_pos(graph, content, points[i - 1])
		current := node_graph_screen_pos(graph, content, points[i])
		segment_colour := colour
		if count > 2 {
			t := f32(i - 1) / f32(segments)
			segment_colour = graph_blend_colour(source_colour, target_colour, t)
			if wire.selected || graph.hover_wire == wire.id {segment_colour = colour}
		}
		draw_thick_line(g.target, {previous.x, previous.y}, {current.x, current.y}, width, segment_colour, g.atlas_texture)
	}

	if lod == .Dots {return}

	before := node_graph_screen_pos(graph, content, points[count - 2])
	b := node_graph_screen_pos(graph, content, points[count - 1])
	dx := b.x - before.x
	dy := b.y - before.y
	length := math.sqrt(dx * dx + dy * dy)
	if length <= 0.001 {return}
	ux := dx / length
	uy := dy / length
	metrics := graph_metrics_of(graph)
	size := metrics.arrow_size * graph_zoom_of(graph)
	if lod == .Compact {size *= 0.6}
	inset := max(metrics.port_size * graph_zoom_of(graph) * 0.8, 5)
	tip := Vec2{b.x - ux * inset, b.y - uy * inset}
	base := Vec2{tip.x - ux * size, tip.y - uy * size}
	px := -uy * size * 0.5
	py := ux * size * 0.5
	triangle: [3][2]f32 = {
		{tip.x, tip.y},
		{base.x + px, base.y + py},
		{base.x - px, base.y - py},
	}
	draw_polygon(g.target, triangle[:], colour, g.atlas_texture)
}

//* Whether a drag from the active port to the hovered port can connect.
//* A drag that starts on an input asks for a source, so the connection
//* runs the other way; the preview, the port ring and the drop all use
//* this one answer.
graph_connect_valid_for_drag :: proc(
	graph: ^Node_Graph,
	active_node: Graph_Node_ID,
	active_port: Graph_Port_ID,
	hover_node: Graph_Node_ID,
	hover_port: Graph_Port_ID,
) -> bool {
	active := node_graph_port_of(graph, active_node, active_port)
	if active != nil && active.direction == .Input {
		return graph_connect_valid(graph, hover_node, hover_port, active_node, active_port)
	}
	return graph_connect_valid(graph, active_node, active_port, hover_node, hover_port)
}

draw_graph_pending_wire :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph, content: Rect, lod: Graph_LOD) {
	source_node_id := graph_wire_source_node(graph)
	source_port_id := graph_wire_source_port(graph)
	colour := graph_colour(g, w, GRAPH_THEME.wire, WIRE_COLOUR)

	source := node_graph_port_of(graph, source_node_id, source_port_id)
	source_node := node_graph_node_of(graph, source_node_id)
	if source == nil || source_node == nil {return}

	from_pos := graph_port_position(graph, source_node, source_port_id)
	target := graph.cursor_graph
	if graph.hover_port.index != 0 {
		to := node_graph_port_of(graph, graph.hover_port_node, graph.hover_port)
		if to != nil {
			to_node := node_graph_node_of(graph, graph.hover_port_node)
			if to_node != nil {
				target = graph_port_position(graph, to_node, graph.hover_port)
				compatible := graph_connect_valid_for_drag(
					graph,
					source_node_id,
					source_port_id,
					graph.hover_port_node,
					graph.hover_port,
				)
				if compatible {
					colour = graph_colour(g, w, GRAPH_THEME.compatible, NODE_COMPATIBLE_COLOUR)
				} else {
					colour = graph_colour(g, w, GRAPH_THEME.incompatible, NODE_INCOMPATIBLE_COLOUR)
				}
			}
		}
	}

	metrics := graph_metrics_of(graph)
	zoom := graph_zoom_of(graph)
	width := max(metrics.wire_width * zoom, 1)
	glow := metrics.wire_glow_width * zoom

	a := node_graph_screen_pos(graph, content, from_pos)
	b := node_graph_screen_pos(graph, content, target)
	mid := (a.x + b.x) * 0.5
	if lod == .Full && glow > 0 {
		glow_colour := colour
		glow_colour.a *= 0.22
		draw_thick_line(g.target, {a.x, a.y}, {mid, a.y}, glow, glow_colour, g.atlas_texture)
		draw_thick_line(g.target, {mid, a.y}, {mid, b.y}, glow, glow_colour, g.atlas_texture)
		draw_thick_line(g.target, {mid, b.y}, {b.x, b.y}, glow, glow_colour, g.atlas_texture)
	}
	draw_thick_line(g.target, {a.x, a.y}, {mid, a.y}, width, colour, g.atlas_texture)
	draw_thick_line(g.target, {mid, a.y}, {mid, b.y}, width, colour, g.atlas_texture)
	draw_thick_line(g.target, {mid, b.y}, {b.x, b.y}, width, colour, g.atlas_texture)
}

//* == Nodes ==

//* The colour of the body of a node.
graph_node_bg :: proc(g: ^GUI, w: ^Widget, node: ^Graph_Node) -> Colour {
	if node.colour.a > 0 {return node.colour}
	return graph_colour(g, w, GRAPH_THEME.node_bg, NODE_COLOUR)
}

//* The accent of the header of a node: the colour of its type.
graph_node_accent :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Colour {
	if node.type_name == "" {return {}}
	return Graph_Type_Colour_Of(graph, node.type_name)
}

draw_graph_node :: proc(
	g: ^GUI,
	w: ^Widget,
	graph: ^Node_Graph,
	content: Rect,
	node: ^Graph_Node,
	lod: Graph_LOD,
) {
	zoom := graph_zoom_of(graph)
	metrics := graph_metrics_of(graph)
	r := node_graph_node_screen_rect(graph, content, node)
	if r.w <= 0 || r.h <= 0 {return}

	style := resolved_style(g, w)
	text_style := style.text
	text_style.size = clamp(metrics.title_font_size * zoom, 8, 42)
	text_style.valign = .Center
	text_style.overrun = .Ellipsis
	text_style.clip = true

	bg := graph_node_bg(g, w, node)
	radius := metrics.corner_radius * zoom
	if node.kind == .Reroute_Dot {radius = r.w * 0.5}

	if lod == .Full && metrics.node_shadow > 0 {
		//* The shadow sits under the card. The card itself is drawn after
		//* it, so the shadow is asked for without a colour of its own.
		shadow_colour := graph_colour(g, w, GRAPH_THEME.node_shadow, RGBA(0, 0, 0, 0.35))
		shadow_colour.a *= metrics.shadow_opacity / 0.35
		box := StyleBox{
			corner_radius = {radius, radius, radius, radius},
			shadow_color = shadow_colour,
			shadow_size = metrics.node_shadow * zoom,
			shadow_offset = {0, max(1, zoom)},
		}
		draw_stylebox_box(g, r, &box)
	}

	if lod == .Dots {
		//* A node that is too small to read is a card: a body and its pins.
		draw_rect(g, r, bg, radius)
		graph_draw_node_ports(g, w, graph, content, node, zoom, text_style, lod)
		return
	}

	//* The border is a card of its own with the body on top of it, so the
	//* corners stay round without a ring of geometry.
	border_width := max(1, zoom)
	border := graph_colour(g, w, GRAPH_THEME.node_border, Scale_Colour(bg, 1.6))
	draw_rect(g, r, border, radius)
	inner := Rect{
		x = r.x + border_width,
		y = r.y + border_width,
		w = max(r.w - border_width * 2, 1),
		h = max(r.h - border_width * 2, 1),
	}
	draw_rect(g, inner, bg, max(radius - border_width, 0))

	if node.kind == .Normal {
		header_h := min(metrics.title_height * zoom, inner.h)
		header := Rect{x = inner.x, y = inner.y, w = inner.w, h = header_h}
		header_colour := graph_colour(g, w, GRAPH_THEME.header, Scale_Colour(bg, 1.25))
		if node.collapsed {
			header_colour = graph_colour(g, w, GRAPH_THEME.collapsed, Scale_Colour(bg, 1.4))
		}
		//* The header takes a hint of the colour of the type instead of a
		//* bar beside the title, so the type still reads without a mark
		//* that looks like a stray line.
		accent := graph_node_accent(graph, node)
		if accent.a <= 0 {
			accent = graph_colour(g, w, GRAPH_THEME.header_accent, Colour{})
		}
		if accent.a > 0 {
			tint := accent
			tint.a = 0.30
			header_colour = graph_blend_colour(header_colour, tint, 0.30)
		}
		draw_rect(g, header, header_colour, max(radius - border_width, 0))
		//* The top of the header keeps a thin light line, so the card reads
		//* as raised even without a shadow.
		draw_thick_line(
			g.target,
			{inner.x + radius, inner.y + 0.5},
			{inner.x + inner.w - radius, inner.y + 0.5},
			1,
			Scale_Colour(header_colour, 1.5),
			g.atlas_texture,
		)

		title_colour := resolved_text_colour(g, w.id, w)
		if title_colour.a <= 0 {title_colour = graph_colour(g, w, GRAPH_THEME.text, RGBA(0.92, 0.94, 0.98, 1))}

		if node.collapsed {
			//* A collapsed node keeps its title. A type that carries a short
			//* title, such as the symbol of an operator, shows that instead,
			//* so a narrow card still says what it does.
			label := len(node.short_title) > 0 ? node.short_title : node.title
			collapsed_style := text_style
			collapsed_style.align = .Center
			button_room := f32(0)
			if node.collapsible {button_room = COLLAPSE_BUTTON_SIZE + 10}
			draw_text(g, collapsed_style, label, Rect{
				x = inner.x + 6 * zoom,
				y = header.y,
				w = max(inner.w - (12 + button_room) * zoom, 1),
				h = header.h,
			}, title_colour)
		} else {
			title_rect := Rect{
				x = inner.x + 10 * zoom,
				y = header.y,
				w = max(inner.w - 34 * zoom, 1),
				h = header.h,
			}
			draw_text(g, text_style, node.title, title_rect, title_colour)
			if lod == .Full {
				graph_draw_node_values(g, w, graph, node, inner, zoom, lod)
			}
		}
	} else if node.kind == .Reroute_Convert {
		ink := graph_colour(g, w, GRAPH_THEME.text, RGBA(0.92, 0.94, 0.98, 1))
		mid_y := inner.y + inner.h * 0.5
		draw_thick_line(g.target, {inner.x + 5 * zoom, mid_y}, {inner.x + inner.w - 5 * zoom, mid_y}, 2 * zoom, ink, g.atlas_texture)
		draw_thick_line(g.target, {inner.x + inner.w - 9 * zoom, mid_y - 4 * zoom}, {inner.x + inner.w - 5 * zoom, mid_y}, 2 * zoom, ink, g.atlas_texture)
		draw_thick_line(g.target, {inner.x + inner.w - 9 * zoom, mid_y + 4 * zoom}, {inner.x + inner.w - 5 * zoom, mid_y}, 2 * zoom, ink, g.atlas_texture)
	}
	graph_draw_node_ports(g, w, graph, content, node, zoom, text_style, lod)

	if node.selected {
		selected := graph_colour(g, w, GRAPH_THEME.selected, NODE_SELECTED_COLOUR)
		draw_round_border(g, r, max(2 * zoom, 1.5), selected, radius)
	} else if graph.hover_node == node.id {
		hovered := graph_colour(g, w, GRAPH_THEME.hovered, NODE_HOVER_COLOUR)
		draw_round_border(g, r, max(1.5 * zoom, 1), hovered, radius)
	}

	button := graph_collapse_rect(graph, node)
	button = Rect{
		x = node_graph_screen_pos(graph, content, Vec2{button.x, button.y}).x,
		y = node_graph_screen_pos(graph, content, Vec2{button.x, button.y}).y,
		w = button.w * zoom,
		h = button.h * zoom,
	}
	if node.collapsible {
		draw_rect(g, button, RGBA(0, 0, 0, 0.18), 3 * zoom)
		ink := RGBA(0.92, 0.94, 0.98, 0.95)
		cx := button.x + button.w * 0.5
		cy := button.y + button.h * 0.5
		if node.collapsed {
			draw_thick_line(g.target, {cx - 4 * zoom, cy}, {cx + 4 * zoom, cy}, 2, ink, g.atlas_texture)
			draw_thick_line(g.target, {cx, cy - 4 * zoom}, {cx, cy + 4 * zoom}, 2, ink, g.atlas_texture)
		} else {
			draw_thick_line(g.target, {cx - 4 * zoom, cy}, {cx + 4 * zoom, cy}, 2, ink, g.atlas_texture)
		}
	}

	if node.resizable && !node.collapsed && (node.selected || graph.hover_node == node.id) {
		handle := Rect{
			x = r.x + r.w - RESIZE_HANDLE_SIZE * zoom,
			y = r.y + r.h - RESIZE_HANDLE_SIZE * zoom,
			w = RESIZE_HANDLE_SIZE * zoom,
			h = RESIZE_HANDLE_SIZE * zoom,
		}
		ink := graph_colour(g, w, GRAPH_THEME.resize, Scale_Colour(bg, 2.0))
		for i in 1 ..= 3 {
			f := f32(i) / 4
			draw_thick_line(
				g.target,
				{handle.x + handle.w - handle.w * f, handle.y + handle.h - 2},
				{handle.x + handle.w - 2, handle.y + handle.h - handle.h * f},
				1,
				ink,
				g.atlas_texture,
			)
		}
	}
}

//* Draws the strip of a collapsed node: the type of every pin as a chip,
//* the inputs from the left and the outputs from the right.

graph_draw_node_ports :: proc(
	g: ^GUI,
	w: ^Widget,
	graph: ^Node_Graph,
	content: Rect,
	node: ^Graph_Node,
	zoom: f32,
	text_style: Text_Style,
	lod: Graph_LOD,
) {
	metrics := graph_metrics_of(graph)
	label_style := text_style
	label_style.size = clamp(metrics.pin_font_size * zoom, 7, 34)
	label_style.valign = .Center
	r := node_graph_node_screen_rect(graph, content, node)
	ink := graph_colour(g, w, GRAPH_THEME.text, RGBA(0.82, 0.86, 0.92, 1))

	layout := Graph_Node_Rows(graph, node)

	for &row in layout.rows[:layout.count] {
		if row.kind != .Pin {continue}
		port := node_graph_port_of(graph, node.id, row.port_id)
		if port == nil {continue}
		centre_graph := graph_port_position(graph, node, port.id)
		centre := node_graph_screen_pos(graph, content, centre_graph)
		size := max(metrics.port_size * zoom, 5)
		if lod == .Dots {size = max(size * 0.6, 3)}

		colour := Graph_Port_Colour(graph, node.id, port.id)
		if colour.a <= 0 {
			if port.direction == .Input {
				colour = graph_colour(g, w, GRAPH_THEME.input, NODE_PORT_INPUT_COLOUR)
			} else {
				colour = graph_colour(g, w, GRAPH_THEME.output, NODE_PORT_OUTPUT_COLOUR)
			}
		}
		if graph.hover_port == port.id && graph.hover_port_node == node.id {
			if graph.mode == .Drag_Wire || graph.mode == .Reconnect_Wire {
				compatible := graph_connect_valid_for_drag(
					graph,
					graph_wire_source_node(graph),
					graph_wire_source_port(graph),
					node.id,
					port.id,
				)
				if compatible {
					colour = graph_colour(g, w, GRAPH_THEME.compatible, NODE_COMPATIBLE_COLOUR)
				} else {
					colour = graph_colour(g, w, GRAPH_THEME.incompatible, NODE_INCOMPATIBLE_COLOUR)
				}
				size *= 1.15
			} else {
				colour = graph_colour(g, w, GRAPH_THEME.hovered, NODE_HOVER_COLOUR)
				size *= 1.15
			}
		} else if graph.mode == .Drag_Wire || graph.mode == .Reconnect_Wire {
			//* While a wire is dragged, the pins that cannot take it step
			//* back, so the ones that can are the ones that catch the eye.
			if !graph_connect_valid_for_drag(
				graph,
				graph_wire_source_node(graph),
				graph_wire_source_port(graph),
				node.id,
				port.id,
			) {
				colour.a *= 0.3
			}
		}

		ring := graph_colour(g, w, GRAPH_THEME.pin_ring, Scale_Colour(colour, 0.55))
		ring_width := max(metrics.pin_ring_width * zoom, 1)
		//* A dot that is too small to show a ring is a plain square: the
		//* ring would cost a shape and tell the eye nothing.
		if lod == .Dots || size < 6 {
			draw_rect(g, Rect{
				x = centre.x - size * 0.5,
				y = centre.y - size * 0.5,
				w = size,
				h = size,
			}, colour, 0)
		} else {
			draw_rect(g, Rect{
				x = centre.x - size * 0.5,
				y = centre.y - size * 0.5,
				w = size,
				h = size,
			}, ring, size * 0.5)
			inner := max(size - ring_width * 2, size * 0.45)
			draw_rect(g, Rect{
				x = centre.x - inner * 0.5,
				y = centre.y - inner * 0.5,
				w = inner,
				h = inner,
			}, colour, inner * 0.5)
		}

		if node.kind == .Reroute_Dot || node.kind == .Reroute_Convert {continue}
		if node.collapsed {continue}
		if lod == .Dots {continue}

		//* The body of a node shows the type of its pins, never their
		//* names: the type is what the wire carries.
		label := row.text
		if label == "" {continue}
		port_style := label_style
		port_style.overrun = .Ellipsis
		port_style.clip = true
		if row.side == .Output {port_style.align = .Right}
		half := max((r.w - 24 * zoom) * 0.5, 1)
		label_rect := Rect{
			x = r.x + 12 * zoom,
			y = centre.y - metrics.port_spacing * zoom * 0.5,
			w = half,
			h = metrics.port_spacing * zoom,
		}
		if row.side == .Output {
			label_rect.x = r.x + r.w - 12 * zoom - half
		}
		draw_text(g, port_style, label, label_rect, colour)
	}
}

graph_value_to_text :: proc(buf: []u8, value: Graph_Value) -> (string, bool) {
	switch v in value {
	case bool:
		return v ? "true" : "false", true
	case i32:
		return fmt.bprintf(buf, "%d", v), true
	case f32:
		return fmt.bprintf(buf, "%.3g", f64(v)), true
	case string:
		return v, true
	case Vec2:
		return fmt.bprintf(buf, "%.3g, %.3g", f64(v.x), f64(v.y)), true
	case Vec3:
		return fmt.bprintf(buf, "%.3g, %.3g, %.3g", f64(v.x), f64(v.y), f64(v.z)), true
	case Colour:
		return fmt.bprintf(buf, "%.3g, %.3g, %.3g, %.3g", f64(v.r), f64(v.g), f64(v.b), f64(v.a)), true
	}
	return "", false
}

//* Draws the configuration of a node as a compact two-column form: the key
//* on the left, the value on the right.
graph_draw_node_values :: proc(
	g: ^GUI,
	w: ^Widget,
	graph: ^Node_Graph,
	node: ^Graph_Node,
	r: Rect,
	zoom: f32,
	lod: Graph_LOD,
) {
	if len(node.config) == 0 {return}
	metrics := graph_metrics_of(graph)
	layout := Graph_Node_Rows(graph, node)
	if layout.config_rows == 0 {return}

	style := resolved_style(g, w).text
	style.size = clamp(metrics.config_font_size * zoom, 7, 30)
	style.valign = .Center
	style.overrun = .Ellipsis
	style.clip = true
	ink := graph_colour(g, w, GRAPH_THEME.text, RGBA(0.72, 0.77, 0.85, 1))

	row := max(layout.input_rows, layout.output_rows)
	for &item in layout.rows[:layout.count] {
		if item.kind != .Config {continue}
		if item.config_index >= len(node.config) {continue}
		entry := node.config[item.config_index]
		y := r.y + (metrics.title_height + f32(row) * metrics.port_spacing) * zoom
		row += 1

		value_buf: [96]u8
		value_text, ok := graph_value_to_text(value_buf[:], entry.value)
		if !ok {continue}

		//* A lone content value reads as the content itself, the way a
		//* constant or an output result is shown. Any other key keeps its
		//* name, so `type = int` is never mistaken for the value.
		lone := layout.config_rows == 1 && (entry.key == "value" || entry.key == "result")
		if lone {
			text := value_text
			if _, is_string := entry.value.(string); is_string {
				label_buf: [192]u8
				text = fmt.bprintf(label_buf[:], "\"%s\"", value_text)
			}
			draw_text(g, style, text, Rect{
				x = r.x + 10 * zoom,
				y = y,
				w = max(r.w - 20 * zoom, 1),
				h = metrics.port_spacing * zoom,
			}, ink)
			continue
		}

		key_style := style
		key_style.align = .Left
		value_style := style
		value_style.align = .Right
		half := max((r.w - 24 * zoom) * 0.5, 1)
		draw_text(g, key_style, entry.key, Rect{
			x = r.x + 10 * zoom,
			y = y,
			w = half,
			h = metrics.port_spacing * zoom,
		}, ink)
		draw_text(g, value_style, value_text, Rect{
			x = r.x + r.w - 10 * zoom - half,
			y = y,
			w = half,
			h = metrics.port_spacing * zoom,
		}, ink)
	}
}

//* Draws the comment regions. They sit behind the wires and the nodes.
draw_graph_regions :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph, content: Rect, visible: Rect) {
	metrics := graph_metrics_of(graph)
	zoom := graph_zoom_of(graph)
	radius := metrics.corner_radius * zoom
	for i := 0; i < len(graph.regions); i += 1 {
		region := &graph.regions[i]
		if !region.alive {continue}
		rect := Graph_Region_Rect(graph, region)
		if !graph_rect_visible(rect, visible) {continue}
		screen := node_graph_screen_pos(graph, content, Vec2{rect.x, rect.y})
		r := Rect{x = screen.x, y = screen.y, w = rect.w * zoom, h = rect.h * zoom}

		fill := region.colour
		fill.a *= 0.16
		draw_rect(g, r, fill, radius)

		border := graph_colour(g, w, GRAPH_THEME.region_border, region.colour)
		draw_round_border(g, r, max(1, zoom), border, radius)

		header_h := min(metrics.region_header_height * zoom, r.h)
		header := Rect{x = r.x, y = r.y, w = r.w, h = header_h}
		header_fill := region.colour
		header_fill.a *= 0.32
		draw_rect(g, header, header_fill, radius)

		if region.title != "" && zoom >= metrics.lod_compact_zoom {
			style := resolved_style(g, w).text
			style.size = clamp(metrics.region_title_font_size * zoom, 7, 30)
			style.valign = .Center
			style.overrun = .Ellipsis
			style.clip = true
			text_colour := graph_colour(g, w, GRAPH_THEME.region_text, RGBA(0.86, 0.90, 0.96, 1))
			draw_text(g, style, region.title, Rect{
				x = r.x + 8 * zoom,
				y = header.y,
				w = max(r.w - 16 * zoom, 1),
				h = header.h,
			}, text_colour)
		}

		if region.selected {
			selected := graph_colour(g, w, GRAPH_THEME.selected, NODE_SELECTED_COLOUR)
			draw_round_border(g, r, max(2 * zoom, 1.5), selected, radius)
		}

		if region.selected || graph.hover_region == region.id {
			handle_graph := Graph_Region_Handle_Rect(graph, region)
			handle_pos := node_graph_screen_pos(graph, content, Vec2{handle_graph.x, handle_graph.y})
			handle := Rect{
				x = handle_pos.x,
				y = handle_pos.y,
				w = handle_graph.w * zoom,
				h = handle_graph.h * zoom,
			}
			ink := graph_colour(g, w, GRAPH_THEME.resize, Scale_Colour(region.colour, 1.8))
			for i in 1 ..= 3 {
				f := f32(i) / 4
				draw_thick_line(
					g.target,
					{handle.x + handle.w - handle.w * f, handle.y + handle.h - 2},
					{handle.x + handle.w - 2, handle.y + handle.h - handle.h * f},
					1,
					ink,
					g.atlas_texture,
				)
			}
		}
	}
}

draw_graph_marquee :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph, content: Rect) {
	a := node_graph_screen_pos(graph, content, graph.marquee_start)
	b := node_graph_screen_pos(graph, content, graph.marquee_end)
	r := Rect{
		x = min(a.x, b.x),
		y = min(a.y, b.y),
		w = math.abs(a.x - b.x),
		h = math.abs(a.y - b.y),
	}
	draw_rect(g, r, graph_colour(g, w, GRAPH_THEME.marquee, GRAPH_MARQUEE_COLOUR), 0)
	draw_outline(g, r, graph_colour(g, w, GRAPH_THEME.marquee, GRAPH_MARQUEE_BORDER_COLOUR), 1)
}

//* == Geometry helpers used by input and drawing ==

graph_collapse_rect :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Rect {
	metrics := graph_metrics_of(graph)
	size: f32 = COLLAPSE_BUTTON_SIZE
	width := graph_node_rect(graph, node).w
	return Rect{
		x = node.pos.x + width - size - 6,
		y = node.pos.y + (metrics.title_height - size) * 0.5,
		w = size,
		h = size,
	}
}

graph_resize_rect :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Rect {
	rect := graph_node_rect(graph, node)
	return Rect{
		x = node.pos.x + rect.w - RESIZE_HANDLE_SIZE,
		y = node.pos.y + rect.h - RESIZE_HANDLE_SIZE,
		w = RESIZE_HANDLE_SIZE,
		h = RESIZE_HANDLE_SIZE,
	}
}

graph_node_header_rect :: proc(graph: ^Node_Graph, node: ^Graph_Node) -> Rect {
	metrics := graph_metrics_of(graph)
	width := graph_node_rect(graph, node).w
	return Rect{x = node.pos.x, y = node.pos.y, w = width, h = metrics.title_height}
}

//* == The tooltip ==

GRAPH_TOOLTIP_DELAY :: 0.45

//* Sets the tooltip of the canvas: the text, the node or the pin it belongs
//* to, and where the pointer rested.
graph_set_tooltip :: proc(graph: ^Node_Graph, text: string, node: Graph_Node_ID, port: Graph_Port_ID) {
	graph.tooltip_text = text
	graph.tooltip_node = node
	graph.tooltip_port = port
}

//* Updates the tooltip of the canvas. It appears only when the pointer has
//* rested for a moment, so a move across the canvas never shows one.
graph_update_tooltip :: proc(g: ^GUI, graph: ^Node_Graph, dt: f32) {
	if graph == nil {return}
	moved := math.abs(g.pointer.x - graph.tooltip_anchor.x) > 2 ||
		math.abs(g.pointer.y - graph.tooltip_anchor.y) > 2
	if moved {
		graph.tooltip_anchor = g.pointer
		graph.tooltip_timer = 0
		graph.tooltip_text = ""
		return
	}
	if graph.mode != .None {
		graph.tooltip_text = ""
		graph.tooltip_timer = 0
		return
	}
	graph.tooltip_timer += dt
	if graph.tooltip_timer < GRAPH_TOOLTIP_DELAY {return}
	if graph.tooltip_text != "" {return}

	if graph.hover_port.index != 0 {
		text := Graph_Pin_Tooltip(graph, graph.hover_port_node, graph.hover_port, graph.tooltip_buf[:])
		graph_set_tooltip(graph, text, graph.hover_port_node, graph.hover_port)
		graph.tooltip_graph = graph.cursor_graph
		return
	}
	if graph.hover_node.index != 0 {
		node := node_graph_node_of(graph, graph.hover_node)
		if node == nil {return}
		text := Graph_Node_Tooltip(graph, node, graph.tooltip_buf[:])
		graph_set_tooltip(graph, text, graph.hover_node, INVALID_GRAPH_PORT_ID)
		graph.tooltip_graph = graph.cursor_graph
	}
}

//* Draws the tooltip above the pointer, clear of the edge of the canvas.
draw_graph_tooltip :: proc(g: ^GUI, w: ^Widget, graph: ^Node_Graph, content: Rect) {
	if graph.tooltip_text == "" {return}
	style := resolved_style(g, w).text
	style.size = clamp(11 * g.scale, 10, 18)
	style.valign = .Top
	style.wrap = .Word

	padding := 6 * g.scale
	max_width := min(max(content.w * 0.4, 80), 280)
	text_width := min(
		max(text_measure_width(g, style, graph.tooltip_text, max_width - padding * 2), 20),
		max_width - padding * 2,
	)
	lines := 1
	for c in graph.tooltip_text {
		if c == '\n' {lines += 1}
	}
	text_height := (style.size + 2) * f32(lines)
	box_width := text_width + padding * 2
	box_height := text_height + padding * 2

	pos := node_graph_screen_pos(graph, content, graph.tooltip_graph)
	x := pos.x + 12 * g.scale
	y := pos.y - box_height - 8 * g.scale
	if y < content.y + 4 {y = pos.y + 20 * g.scale}
	x = clamp(x, content.x + 4, max(content.x + content.w - box_width - 4, content.x + 4))
	y = clamp(y, content.y + 4, max(content.y + content.h - box_height - 4, content.y + 4))

	box := Rect{x = x, y = y, w = box_width, h = box_height}
	draw_rect(g, box, RGBA(0.07, 0.08, 0.10, 0.94), 5)
	draw_round_border(g, box, 1, RGBA(0.36, 0.40, 0.48, 1), 5)
	draw_text(g, style, graph.tooltip_text, Rect{
		x = box.x + padding,
		y = box.y + padding,
		w = text_width,
		h = text_height,
	}, RGBA(0.88, 0.92, 0.97, 1))
}

//* The width a text takes at most, in the style of a tooltip.
text_measure_width :: proc(g: ^GUI, style: Text_Style, text: string, max_width: f32) -> f32 {
	return text_measure(g, style, text, max_width).x
}

//* == Hover and cursor ==

post_update_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	d := node_graph_data(g, id)
	graph_update_metrics(g, w, graph)

	//* A menu that went away without a choice clears the pending wire.
	if d != nil && Widget_Alive(g, d.menu) && !Popup_Is_Open(g, d.menu) && graph.menu_pending {
		graph.menu_pending = false
		graph.active_port_node = INVALID_GRAPH_NODE_ID
		graph.active_port = INVALID_GRAPH_PORT_ID
	}

	content := content_rect(g, w)
	inside := rect_contains(content, g.pointer.x, g.pointer.y)
	graph.cursor_graph = node_graph_graph_pos(graph, content, g.pointer)
	switch graph.mode {
	case .Pan:
		g.cursor = .Grabbing
	case .Resize_Node, .Resize_Region:
		g.cursor = .Resize_NW
	case .Drag_Wire, .Reconnect_Wire:
		g.cursor = .Crosshair
	case .Move_Nodes, .Move_Region:
		g.cursor = .Grabbing
	case .Marquee:
		g.cursor = .Crosshair
	case .None:
		graph_update_hover(g, graph, inside)
	}
	graph_update_tooltip(g, graph, dt)
}

//* The node, the pin, the wire and the region under the pointer, and the
//* cursor that goes with them.
graph_update_hover :: proc(g: ^GUI, graph: ^Node_Graph, inside: bool) {
	graph.hover_region = INVALID_GRAPH_REGION_ID
	if !inside {
		graph.hover_node = INVALID_GRAPH_NODE_ID
		graph.hover_port = INVALID_GRAPH_PORT_ID
		graph.hover_port_node = INVALID_GRAPH_NODE_ID
		graph.hover_wire = INVALID_GRAPH_WIRE_ID
			return
	}
	node, port := graph_port_at_position(
		graph,
		graph.cursor_graph,
		PORT_HIT_TOLERANCE / graph_zoom_of(graph),
	)
	graph.hover_port = port
	graph.hover_port_node = node
	if port.index != 0 {
		graph.hover_node = node
		graph.hover_wire = INVALID_GRAPH_WIRE_ID
			g.cursor = .Pointer
		return
	}

	region_id, on_handle := graph_region_control(graph, graph.cursor_graph)
	if region_id.index != 0 {
		graph.hover_region = region_id
		g.cursor = on_handle ? .Resize_NW : .Grab
		return
	}

	graph.hover_node = graph_node_at_position(graph, graph.cursor_graph)
	graph.hover_wire = INVALID_GRAPH_WIRE_ID
	if graph.hover_node.index != 0 {
		hovered := node_graph_node_of(graph, graph.hover_node)
			if hovered != nil && rect_contains(graph_collapse_rect(graph, hovered), graph.cursor_graph.x, graph.cursor_graph.y) {
			g.cursor = .Pointer
		} else if hovered != nil && hovered.resizable && !hovered.collapsed &&
		   rect_contains(graph_resize_rect(graph, hovered), graph.cursor_graph.x, graph.cursor_graph.y) {
			g.cursor = .Resize_NW
		} else {
			g.cursor = .Grab
		}
		return
	}
	graph.hover_wire = graph_wire_at_position(
		graph,
		graph.cursor_graph,
		WIRE_HIT_TOLERANCE / graph_zoom_of(graph),
	)
	if graph.hover_wire.index != 0 {g.cursor = .Pointer}
}

GRAPH_NUDGE_STEP :: f32(1)
GRAPH_PAN_STEP :: f32(40)
GRAPH_PAN_FAST :: f32(2)

pointer_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	content := content_rect(g, w)
	in_content := rect_contains(content, e.pos.x, e.pos.y)

	switch e.kind {
	case .Wheel:
		if !in_content || e.amount == 0 {return}
		zoom := graph_zoom_of(graph) * math.pow_f32(graph.zoom_step, e.amount)
		node_graph_zoom_at(g, id, graph, content, e.pos, zoom)
		if graph.mode == .Drag_Wire || graph.mode == .Reconnect_Wire {
			graph_update_wire_target(graph)
		}
		Event_Handled(g)

	case .Down:
		graph.cursor_graph = node_graph_graph_pos(graph, content, e.pos)
		switch e.button {
		case .Middle:
			graph.mode = .Pan
			graph.pan_origin = e.pos
			graph.pan_scroll = graph.scroll
			Widget_Capture_Pointer(g, id)
			Event_Handled(g)
		case .Right:
			if in_content {graph_right_down(g, id, graph, content, e.pos)}
		case .Left:
			if !in_content {return}
			Focus_Set(g, id)
			graph_left_down(g, id, graph, content, e.pos, e.clicks)
			Event_Handled(g)
		}

	case .Move:
		graph.cursor_graph = node_graph_graph_pos(graph, content, e.pos)
		switch graph.mode {
		case .Pan:
			zoom := graph_zoom_of(graph)
			delta := Vec2{
				(e.pos.x - graph.pan_origin.x) / zoom,
				(e.pos.y - graph.pan_origin.y) / zoom,
			}
			graph.scroll = Vec2{
				graph.pan_scroll.x - delta.x,
				graph.pan_scroll.y - delta.y,
			}
			graph_view_sync(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Marquee:
			graph.marquee_end = graph.cursor_graph
			graph_marquee_select(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Move_Nodes:
			graph_drag_nodes(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Resize_Node:
			graph_resize_node(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Move_Region:
			graph_drag_region(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Resize_Region:
			graph_resize_region(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .Drag_Wire, .Reconnect_Wire:
			graph_update_wire_target(graph)
			invalidate(g, id, Dirty_Flags{.Visual})
		case .None:
			//* Hover is refreshed in post_update, where geometry is current.
		}

	case .Up:
		switch e.button {
		case .Middle:
			if graph.mode == .Pan {
				graph.mode = .None
				Widget_Release_Pointer(g)
			}
		case .Left:
			graph_left_up(g, id, graph, content, e.pos)
		case .Right:
		}
	}
}

graph_right_down :: proc(
	g: ^GUI,
	id: Widget_ID,
	graph: ^Node_Graph,
	content: Rect,
	pos: Vec2,
) {
	//* A right click on empty canvas opens the creation menu there.
	graph_point := node_graph_graph_pos(graph, content, pos)
	if graph_node_at_position(graph, graph_point).index != 0 {return}
	graph.menu_pos = graph_point
	graph.menu_pending = false
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
	node_graph_open_create_menu(g, id)
	Event_Handled(g)
}

//* The region under the pointer: its header or its resize handle. The body
//* of a region is pass-through, so a marquee still works inside it.
graph_region_control :: proc(graph: ^Node_Graph, point: Vec2) -> (Graph_Region_ID, bool) {
	if region_id := Graph_Region_Handle_At_Position(graph, point); region_id.index != 0 {
		return region_id, true
	}
	return Graph_Region_At_Position(graph, point), false
}

graph_left_down :: proc(
	g: ^GUI,
	id: Widget_ID,
	graph: ^Node_Graph,
	content: Rect,
	pos: Vec2,
	clicks: int,
) {
	point := node_graph_graph_pos(graph, content, pos)
	graph.cursor_graph = point

	node_id := graph_node_at_position(graph, point)
	node := node_graph_node_of(graph, node_id)

	//* A region header takes the pointer before a node does, so a comment
	//* box can be picked up even when a node sits inside it.
	region_id, on_handle := graph_region_control(graph, point)
	if region_id.index != 0 {
		region := Graph_Region_Of(graph, region_id)
		if region != nil {
			node_graph_undo_begin(g, id)
			if on_handle {
				graph.mode = .Resize_Region
				graph.resize_region = region_id
				graph.resize_size = region.size
				graph.drag_origin = point
				invalidate(g, id, DIRTY_ALL)
				return
			}
			additive := .Ctrl in g.mods || .Shift in g.mods
			if additive {
				region.selected = !region.selected
			} else if !region.selected {
				graph_selection_clear(graph)
				region.selected = true
			}
			graph.mode = .Move_Region
			graph.drag_region = region_id
			graph.drag_origin = point
			graph_begin_region_drag(graph, region)
			invalidate(g, id, DIRTY_ALL)
			return
		}
	}

	if node != nil && clicks >= 2 {
		//* The collapse button and the resize handle are part of the node
		//* but are not the node itself. A second click still does its own
		//* job (collapse toggles again, resize starts); only the editor is
		//* kept shut.
		on_control := node.collapsible && rect_contains(graph_collapse_rect(graph, node), point.x, point.y)
		on_control = on_control ||
			(node.resizable && !node.collapsed && rect_contains(graph_resize_rect(graph, node), point.x, point.y))
		if !on_control {
			node_graph_select_node(g, id, node.id, false)
			if graph.callbacks.node_double_click != nil {
				graph.callbacks.node_double_click(g, id, node.id)
			}
			return
		}
	}

	if node != nil {
		//* The collapse button and the resize handle are part of the node.
		if node.collapsible && rect_contains(graph_collapse_rect(graph, node), point.x, point.y) {
			node_graph_undo_begin(g, id)
			node.collapsed = !node.collapsed
			node_graph_undo_commit(g, id, node.collapsed ? "collapse" : "expand")
			Graph_Geometry_Invalidate(graph)
			invalidate(g, id, DIRTY_ALL)
			return
		}
		if node.resizable && !node.collapsed &&
		   rect_contains(graph_resize_rect(graph, node), point.x, point.y) {
			node_graph_undo_begin(g, id)
			graph.mode = .Resize_Node
			graph.resize_node = node.id
			start := graph_node_rect(graph, node)
			graph.resize_start = Vec2{start.w, start.h}
			graph.resize_size = node.size
			graph.drag_origin = point
			return
		}
	}

	//* A port wins over the node under it.
	port_node, port_id := graph_port_at_position(
		graph,
		point,
		PORT_HIT_TOLERANCE / graph_zoom_of(graph),
	)
	if port_id.index != 0 {
		graph_begin_port_drag(g, id, graph, port_node, port_id)
		return
	}

	if node != nil {
		graph_begin_node_move(g, id, graph, node, point)
		return
	}

	wire_id := graph_wire_at_position(graph, point, WIRE_HIT_TOLERANCE / graph_zoom_of(graph))
	if wire_id.index != 0 {
		node_graph_select_wire(g, id, wire_id, .Ctrl in g.mods || .Shift in g.mods)
		if clicks >= 2 && graph.callbacks.wire_double_click != nil {
			graph.callbacks.wire_double_click(g, id, wire_id, point)
		}
		return
	}

	//* Empty canvas starts a marquee.
	additive := .Ctrl in g.mods || .Shift in g.mods
	if !additive {graph_selection_clear(graph)}
	graph.mode = .Marquee
	graph.marquee_additive = additive
	graph.marquee_start = point
	graph.marquee_end = point
	invalidate(g, id, Dirty_Flags{.Visual})
}

graph_begin_port_drag :: proc(
	g: ^GUI,
	id: Widget_ID,
	graph: ^Node_Graph,
	node_id: Graph_Node_ID,
	port_id: Graph_Port_ID,
) {
	port := node_graph_port_of(graph, node_id, port_id)
	if port == nil {return}

	graph.active_port_node = node_id
	graph.active_port = port_id
	graph.menu_direction = port.direction
	graph.hover_port = INVALID_GRAPH_PORT_ID
	graph.hover_port_node = INVALID_GRAPH_NODE_ID
	graph.menu_pending = false

	owner := node_graph_node_of(graph, node_id)
	if owner != nil && owner.kind == .Reroute_Dot {
		graph.mode = .Drag_Wire
		graph.drag_origin = graph.cursor_graph
		return
	}

	if (port.direction == .Input || port.direction == .Both) && port.connections > 0 && port.port_kind != .Exec {
		wire := graph_wire_into(graph, node_id, port_id)
		if wire.index != 0 {
			//* Pick up the input end of a wire, keeping it intact until a
			//* new target is dropped on.
			graph.active_wire = wire
			if existing := node_graph_wire_of(graph, wire); existing != nil {
				graph.active_port_node = existing.from_node
				graph.active_port = existing.from_port
			}
			graph.mode = .Reconnect_Wire
			graph.drag_origin = graph.cursor_graph
			return
		}
	}

	graph.mode = .Drag_Wire
	graph.drag_origin = graph.cursor_graph
}

graph_begin_node_move :: proc(
	g: ^GUI,
	id: Widget_ID,
	graph: ^Node_Graph,
	node: ^Graph_Node,
	point: Vec2,
) {
	additive := .Ctrl in g.mods || .Shift in g.mods
	if additive {
		node.selected = !node.selected
	} else if !node.selected {
		graph_selection_clear(graph)
		node.selected = true
	}

	clear(&graph.dragging_nodes)
	clear(&graph.drag_starts)
	for i := 0; i < len(graph.nodes); i += 1 {
		other := &graph.nodes[i]
		if !other.alive || !other.selected {continue}
		append(&graph.dragging_nodes, other.id)
		append(&graph.drag_starts, other.pos)
	}
	if len(graph.dragging_nodes) == 0 {return}

	node_graph_undo_begin(g, id)
	graph.mode = .Move_Nodes
	graph.drag_origin = point
	invalidate(g, id, Dirty_Flags{.Visual})
}

graph_drag_nodes :: proc(graph: ^Node_Graph) {
	delta := Vec2{
		graph.cursor_graph.x - graph.drag_origin.x,
		graph.cursor_graph.y - graph.drag_origin.y,
	}
	if graph.snap && graph.grid_size > 0 {
		delta.x = math.round(delta.x / graph.grid_size) * graph.grid_size
		delta.y = math.round(delta.y / graph.grid_size) * graph.grid_size
	}
	for node_id, index in graph.dragging_nodes {
		node := node_graph_node_of(graph, node_id)
		if node == nil || index >= len(graph.drag_starts) {continue}
		start := graph.drag_starts[index]
		node.pos = Vec2{start.x + delta.x, start.y + delta.y}
	}
	Graph_Geometry_Invalidate(graph)
}

graph_resize_node :: proc(graph: ^Node_Graph) {
	node := node_graph_node_of(graph, graph.resize_node)
	if node == nil {return}
	delta := Vec2{
		graph.cursor_graph.x - graph.drag_origin.x,
		graph.cursor_graph.y - graph.drag_origin.y,
	}
	size := Vec2{
		max(graph.resize_start.x + delta.x, node.min_size.x),
		max(graph.resize_start.y + delta.y, node.min_size.y),
	}
	size.x = min(size.x, node.max_size.x)
	size.y = min(size.y, node.max_size.y)
	if graph.snap && graph.grid_size > 0 {
		size.x = math.round(size.x / graph.grid_size) * graph.grid_size
		size.y = math.round(size.y / graph.grid_size) * graph.grid_size
		size.x = clamp(size.x, node.min_size.x, node.max_size.x)
		size.y = clamp(size.y, node.min_size.y, node.max_size.y)
	}
	node.size = size
	Graph_Geometry_Invalidate(graph)
}

//* Remembers the nodes a region carries, so a drag moves them with it.
graph_begin_region_drag :: proc(graph: ^Node_Graph, region: ^Graph_Region) {
	clear(&graph.region_drag_nodes)
	clear(&graph.region_drag_starts)
	if region == nil || !region.move_contained {return}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		if !Graph_Region_Contains(graph, region, node) {continue}
		append(&graph.region_drag_nodes, node.id)
		append(&graph.region_drag_starts, node.pos)
	}
}

graph_drag_region :: proc(graph: ^Node_Graph) {
	region := Graph_Region_Of(graph, graph.drag_region)
	if region == nil {return}
	delta := Vec2{
		graph.cursor_graph.x - graph.drag_origin.x,
		graph.cursor_graph.y - graph.drag_origin.y,
	}
	if graph.snap && graph.grid_size > 0 {
		delta.x = math.round(delta.x / graph.grid_size) * graph.grid_size
		delta.y = math.round(delta.y / graph.grid_size) * graph.grid_size
	}
	region.pos = Vec2{region.pos.x + delta.x, region.pos.y + delta.y}
	for node_id, index in graph.region_drag_nodes {
		node := node_graph_node_of(graph, node_id)
		if node == nil || index >= len(graph.region_drag_starts) {continue}
		start := graph.region_drag_starts[index]
		node.pos = Vec2{start.x + delta.x, start.y + delta.y}
	}
	Graph_Geometry_Invalidate(graph)
}

graph_resize_region :: proc(graph: ^Node_Graph) {
	region := Graph_Region_Of(graph, graph.resize_region)
	if region == nil {return}
	delta := Vec2{
		graph.cursor_graph.x - graph.drag_origin.x,
		graph.cursor_graph.y - graph.drag_origin.y,
	}
	size := Vec2{max(region.size.x + delta.x, f32(40)), max(region.size.y + delta.y, f32(40))}
	if graph.snap && graph.grid_size > 0 {
		size.x = math.round(size.x / graph.grid_size) * graph.grid_size
		size.y = math.round(size.y / graph.grid_size) * graph.grid_size
		size.x = max(size.x, f32(40))
		size.y = max(size.y, f32(40))
	}
	region.size = size
	Graph_Geometry_Invalidate(graph)
}

//* Finds the pin under the pointer. A drop that lands near a pin that can
//* take the wire snaps to it, so a connection does not need a pixel exact
//* hit.
graph_update_wire_target :: proc(graph: ^Node_Graph) {
	tolerance := PORT_HIT_TOLERANCE / graph_zoom_of(graph)
	node_id, port_id := graph_port_at_position(graph, graph.cursor_graph, tolerance)
	if port_id.index == 0 {
		node_id, port_id = graph_snap_wire_target(graph, graph.cursor_graph, tolerance * 2.5)
	}
	if port_id.index == 0 {
		graph.hover_port = INVALID_GRAPH_PORT_ID
		graph.hover_port_node = INVALID_GRAPH_NODE_ID
		graph.hover_node = INVALID_GRAPH_NODE_ID
			return
	}
	graph.hover_port = port_id
	graph.hover_port_node = node_id
	graph.hover_node = node_id
}

//* The nearest pin that can take the wire being dragged, within a radius.
Graph_Snap_Search :: 64

graph_snap_wire_target :: proc(
	graph: ^Node_Graph,
	point: Vec2,
	radius: f32,
) -> (Graph_Node_ID, Graph_Port_ID) {
	found_node := INVALID_GRAPH_NODE_ID
	found_port := INVALID_GRAPH_PORT_ID
	best := radius
	Graph_Geometry_Ensure(graph)
	scratch: [Graph_Snap_Search]int
	query := Rect{
		x = point.x - radius,
		y = point.y - radius,
		w = radius * 2,
		h = radius * 2,
	}
	count := Graph_Index_Query_Nodes(graph, &graph.cache.index, query, scratch[:])
	for i in 0 ..< count {
		node := &graph.nodes[scratch[i]]
		if !node.alive {continue}
		for port in node.ports {
			if !port.alive || !port.visible {continue}
			centre := Graph_Port_Position_Of(graph, node, port.id)
			dx := point.x - centre.x
			dy := point.y - centre.y
			distance := math.sqrt(dx * dx + dy * dy)
			if distance > best {continue}
			if !graph_connect_valid_for_drag(
				graph,
				graph.active_port_node,
				graph.active_port,
				node.id,
				port.id,
			) {continue}
			best = distance
			found_node = node.id
			found_port = port.id
		}
	}
	return found_node, found_port
}

graph_left_up :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph, content: Rect, pos: Vec2) {
	graph.cursor_graph = node_graph_graph_pos(graph, content, pos)
	switch graph.mode {
	case .Marquee:
		graph.marquee_end = graph.cursor_graph
		graph_marquee_select(graph)
		graph.mode = .None
		invalidate(g, id, Dirty_Flags{.Visual})
	case .Move_Nodes:
		node_graph_undo_commit(g, id, "move")
		graph.mode = .None
		clear(&graph.dragging_nodes)
		clear(&graph.drag_starts)
		invalidate(g, id, Dirty_Flags{.Visual})
	case .Resize_Node:
		node_graph_undo_commit(g, id, "resize")
		graph.mode = .None
		graph.resize_node = INVALID_GRAPH_NODE_ID
		invalidate(g, id, Dirty_Flags{.Visual})
	case .Move_Region:
		node_graph_undo_commit(g, id, "move region")
		graph.mode = .None
		graph.drag_region = INVALID_GRAPH_REGION_ID
		clear(&graph.region_drag_nodes)
		clear(&graph.region_drag_starts)
		invalidate(g, id, DIRTY_ALL)
	case .Resize_Region:
		node_graph_undo_commit(g, id, "resize region")
		graph.mode = .None
		graph.resize_region = INVALID_GRAPH_REGION_ID
		invalidate(g, id, DIRTY_ALL)
	case .Drag_Wire:
		graph_update_wire_target(graph)
		graph_drop_wire(g, id, graph)
	case .Reconnect_Wire:
		graph_update_wire_target(graph)
		graph_drop_reconnect(g, id, graph)
	case .Pan:
		graph.mode = .None
		Widget_Release_Pointer(g)
	case .None:
	}
}

graph_drop_wire :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph) {
	node_id := graph.hover_port_node
	port_id := graph.hover_port
	from_node := graph.active_port_node
	from_port := graph.active_port

	if node_id.index != 0 && port_id.index != 0 {
		active := node_graph_port_of(graph, from_node, from_port)
		node_graph_undo_begin(g, id)
		wire := INVALID_GRAPH_WIRE_ID
		if active != nil && active.direction == .Input {
			//* Dragging from an empty input asks for a source, so the
			//* connection runs from the target port into the input.
			wire = graph_connect_internal(graph, node_id, port_id, from_node, from_port, {})
		} else {
			wire = graph_connect_internal(graph, from_node, from_port, node_id, port_id, {})
		}
		if wire.index != 0 {
			node_graph_undo_commit(g, id, "connect")
		} else {
			node_graph_undo_cancel(g, id)
			if graph.callbacks.wire_connect_failed != nil {
				if active != nil && active.direction == .Input {
					graph.callbacks.wire_connect_failed(g, id, node_id, port_id, from_node, from_port)
				} else {
					graph.callbacks.wire_connect_failed(g, id, from_node, from_port, node_id, port_id)
				}
			}
		}
		graph.mode = .None
		graph.hover_port = INVALID_GRAPH_PORT_ID
		graph.hover_port_node = INVALID_GRAPH_NODE_ID
		if wire.index != 0 {invalidate(g, id, DIRTY_ALL)}
		return
	}

	//* Dropped over empty canvas: offer a node that fits the wire.
	graph.mode = .None
	graph.menu_pos = graph.cursor_graph
	if from := node_graph_port_of(graph, from_node, from_port); from != nil {
		graph.menu_direction = from.direction
	}
	graph.active_port_node = from_node
	graph.active_port = from_port
	graph.menu_pending = true
	node_graph_open_create_menu(g, id)
}

graph_drop_reconnect :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph) {
	old_wire := node_graph_wire_of(graph, graph.active_wire)
	if old_wire == nil {
		graph.mode = .None
		return
	}

	if graph.hover_port.index == 0 {
		//* Empty canvas: create a node that fits the source of the wire.
		graph.mode = .None
		graph.menu_pos = graph.cursor_graph
		graph.active_port_node = old_wire.from_node
		graph.active_port = old_wire.from_port
		graph.menu_direction = .Output
		graph.menu_pending = true
		node_graph_open_create_menu(g, id)
		return
	}

	target := node_graph_port_of(graph, graph.hover_port_node, graph.hover_port)
	if target == nil {
		graph.mode = .None
		return
	}

	source_node := old_wire.from_node
	source_port := old_wire.from_port
	target_node := old_wire.to_node
	target_port := old_wire.to_port
	colour := old_wire.colour
	old_from_node := source_node
	old_from_port := source_port
	old_to_node := target_node
	old_to_port := target_port

	//* An output under the pointer moves the source end of the wire; an
	//* input under it moves the target end. Dropping on either original
	//* end leaves the wire as it was.
	if target.direction == .Output {
		if graph.hover_port_node == old_wire.from_node && graph.hover_port == old_wire.from_port {
			graph.mode = .None
			graph.active_wire = INVALID_GRAPH_WIRE_ID
			return
		}
		source_node = graph.hover_port_node
		source_port = graph.hover_port
	} else {
		if graph.hover_port_node == old_wire.to_node && graph.hover_port == old_wire.to_port {
			graph.mode = .None
			graph.active_wire = INVALID_GRAPH_WIRE_ID
			return
		}
		target_node = graph.hover_port_node
		target_port = graph.hover_port
	}

	node_graph_undo_begin(g, id)
	graph_wire_release(graph, int(graph.active_wire.index) - 1)
	if graph_connect_internal(
		graph,
		source_node,
		source_port,
		target_node,
		target_port,
		colour,
	).index == 0 {
		//* Put the original wire back when the new endpoint is not valid.
		graph_connect_internal(graph, old_from_node, old_from_port, old_to_node, old_to_port, colour)
		node_graph_undo_cancel(g, id)
	} else {
		node_graph_undo_commit(g, id, "reconnect")
	}
	graph.mode = .None
	graph.active_wire = INVALID_GRAPH_WIRE_ID
	graph.hover_port = INVALID_GRAPH_PORT_ID
	graph.hover_port_node = INVALID_GRAPH_NODE_ID
	invalidate(g, id, DIRTY_ALL)
}

graph_marquee_select :: proc(graph: ^Node_Graph) {
	rect := Rect{
		x = min(graph.marquee_start.x, graph.marquee_end.x),
		y = min(graph.marquee_start.y, graph.marquee_end.y),
		w = math.abs(graph.marquee_start.x - graph.marquee_end.x),
		h = math.abs(graph.marquee_start.y - graph.marquee_end.y),
	}
	if !graph.marquee_additive {graph_selection_clear(graph)}
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive {continue}
		if rect_intersects(graph_node_rect(graph, node), rect) {node.selected = true}
	}
}

rect_intersects :: proc(a, b: Rect) -> bool {
	return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

//* == Escape and cancellation ==

graph_cancel_interaction :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph) -> bool {
	handled := true
	switch graph.mode {
	case .Move_Nodes:
		for node_id, index in graph.dragging_nodes {
			node := node_graph_node_of(graph, node_id)
			if node == nil || index >= len(graph.drag_starts) {continue}
			node.pos = graph.drag_starts[index]
		}
		node_graph_undo_cancel(g, id)
	case .Resize_Node:
		if node := node_graph_node_of(graph, graph.resize_node); node != nil {
			node.size = graph.resize_size
		}
		Graph_Geometry_Invalidate(graph)
		node_graph_undo_cancel(g, id)
	case .Move_Region:
		node_graph_undo_cancel(g, id)
	case .Resize_Region:
		if region := Graph_Region_Of(graph, graph.resize_region); region != nil {
			region.size = graph.resize_size
		}
		Graph_Geometry_Invalidate(graph)
		node_graph_undo_cancel(g, id)
	case .Drag_Wire, .Reconnect_Wire:
		graph.menu_pending = false
	case .Pan:
		Widget_Release_Pointer(g)
	case .Marquee:
	case .None:
		handled = graph.menu_pending
		graph.menu_pending = false
	}
	graph.mode = .None
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
	graph.active_wire = INVALID_GRAPH_WIRE_ID
	graph.hover_port = INVALID_GRAPH_PORT_ID
	graph.hover_port_node = INVALID_GRAPH_NODE_ID
	clear(&graph.dragging_nodes)
	clear(&graph.drag_starts)
	clear(&graph.region_drag_nodes)
	clear(&graph.region_drag_starts)
	graph.resize_node = INVALID_GRAPH_NODE_ID
	graph.resize_region = INVALID_GRAPH_REGION_ID
	graph.drag_region = INVALID_GRAPH_REGION_ID
	invalidate(g, id, DIRTY_ALL)
	return handled
}

//* == Keyboard ==

//* Moves the selected nodes by one step. Every press is its own undo
//* record, so a single arrow press can be taken back.
graph_nudge_selection :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph, delta: Vec2) {
	moved := false
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		moved = true
	}
	if !moved {return}
	node_graph_undo_begin(g, id)
	for i := 0; i < len(graph.nodes); i += 1 {
		node := &graph.nodes[i]
		if !node.alive || !node.selected {continue}
		node.pos = Vec2{node.pos.x + delta.x, node.pos.y + delta.y}
	}
	Graph_Geometry_Invalidate(graph)
	node_graph_undo_commit(g, id, "nudge")
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Pans the view by a step. The step shrinks with the zoom, so a pan
//* covers the same ground at every scale.
graph_pan_by :: proc(g: ^GUI, id: Widget_ID, graph: ^Node_Graph, delta: Vec2) {
	zoom := graph_zoom_of(graph)
	graph.scroll = Vec2{graph.scroll.x + delta.x / zoom, graph.scroll.y + delta.y / zoom}
	graph_view_sync(graph)
	invalidate(g, id, Dirty_Flags{.Visual})
}

key_node_graph :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	ctrl := .Ctrl in e.mods
	shift := .Shift in e.mods

	#partial switch e.key {
	case .Escape:
		if graph_cancel_interaction(g, id, graph) {Event_Handled(g)}
	case .Delete, .Backspace:
		node_graph_delete_selection(g, id)
		Event_Handled(g)
	case .A:
		if ctrl {
			node_graph_select_all(g, id)
			Event_Handled(g)
		} else {
			step := GRAPH_PAN_STEP * (shift ? GRAPH_PAN_FAST : f32(1))
			graph_pan_by(g, id, graph, {-step, 0})
			Event_Handled(g)
		}
	case .W:
		step := GRAPH_PAN_STEP * (shift ? GRAPH_PAN_FAST : f32(1))
		graph_pan_by(g, id, graph, {0, -step})
		Event_Handled(g)
	case .S:
		if ctrl {break}
		step := GRAPH_PAN_STEP * (shift ? GRAPH_PAN_FAST : f32(1))
		graph_pan_by(g, id, graph, {0, step})
		Event_Handled(g)
	case .D:
		if ctrl {break}
		step := GRAPH_PAN_STEP * (shift ? GRAPH_PAN_FAST : f32(1))
		graph_pan_by(g, id, graph, {step, 0})
		Event_Handled(g)
	case .F:
		if shift {
			node_graph_fit_view(g, id)
		} else {
			node_graph_fit_selection(g, id)
		}
		Event_Handled(g)
	case .C:
		if ctrl {
			node_graph_copy(g, id)
			Event_Handled(g)
		}
	case .X:
		if ctrl {
			node_graph_cut(g, id)
			Event_Handled(g)
		}
	case .V:
		if ctrl {
			node_graph_paste(g, id)
			Event_Handled(g)
		}
	case .Z:
		if ctrl {
			if shift {node_graph_redo(g, id)} else {node_graph_undo(g, id)}
			Event_Handled(g)
		}
	case .Y:
		if ctrl {
			node_graph_redo(g, id)
			Event_Handled(g)
		}
	case .Left:
		graph_nudge_selection(g, id, graph, {-graph_nudge_step(graph, shift, ctrl), 0})
		Event_Handled(g)
	case .Right:
		graph_nudge_selection(g, id, graph, {graph_nudge_step(graph, shift, ctrl), 0})
		Event_Handled(g)
	case .Up:
		graph_nudge_selection(g, id, graph, {0, -graph_nudge_step(graph, shift, ctrl)})
		Event_Handled(g)
	case .Down:
		graph_nudge_selection(g, id, graph, {0, graph_nudge_step(graph, shift, ctrl)})
		Event_Handled(g)
	}
}

//* How far a nudge moves a node: one unit, the size of the grid, or ten
//* times a unit.
graph_nudge_step :: proc(graph: ^Node_Graph, shift, ctrl: bool) -> f32 {
	step := GRAPH_NUDGE_STEP
	if shift {step = max(graph.grid_size, GRAPH_NUDGE_STEP)}
	if ctrl {step *= 10}
	return step
}

//* == Creation menu ==

//* Lazily creates the graph's private command palette.
graph_create_menu :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	d := node_graph_data(g, id)
	if d == nil {return INVALID_WIDGET_ID}
	if Widget_Alive(g, d.menu) {return d.menu}

	menu := Make_Command_Palette(g, g.root, Command_Palette_Opts{
		Base_Opts = Base_Opts{name = "node_graph_create"},
	})
	Popup_Attach_To_Root(g, menu)
	d.menu = menu
	if w := Widget_Get(g, menu); w != nil {w.skip_scene_save = true}
	if md := command_palette_data(g, menu); md != nil {
		md.owner = id
		md.commands_owned = true
	}
	return menu
}

graph_menu_clear_commands :: proc(d: ^Command_Palette_Data) {
	for &command in d.commands {
		if !d.commands_owned {continue}
		if len(command.label) > 0 {delete(command.label)}
		if len(command.keywords) > 0 {delete(command.keywords)}
		if len(command.detail) > 0 {delete(command.detail)}
	}
	clear(&d.commands)
}

graph_menu_rebuild :: proc(g: ^GUI, id: Widget_ID, menu: Widget_ID) {
	graph := node_graph_of(g, id)
	d := command_palette_data(g, menu)
	if graph == nil || d == nil {return}
	graph_menu_clear_commands(d)

	for index in 0 ..< len(graph.types) {
		node_type := &graph.types[index]
		if !graph_type_allowed_for_menu(graph, node_type) {continue}

		label := node_type.name
		if node_type.category != "" {
			label = fmt.aprintf("%s / %s", node_type.category, node_type.name)
		} else {
			label = strings.clone(node_type.name)
		}
		keywords := fmt.aprintf("%s %s %s", node_type.category, node_type.name, node_type.description)
		detail := strings.clone(node_type.description)
		append(&d.commands, Palette_Command{
			label = label,
			keywords = keywords,
			detail = detail,
			tag = index,
			action = command_palette_graph_create,
		})
	}
	//* A reroute is not a registered type, so it is offered after them:
	//* only when a wire is being completed, and only for a data pin.
	if graph_menu_reroute_allowed(graph) {
		append(&d.commands, Palette_Command{
			label = strings.clone("Reroute"),
			keywords = strings.clone("reroute wire dot split"),
			detail = strings.clone("Splits a wire at a point"),
			tag = -1,
			action = graph_menu_create_reroute,
		})
	}
	d.selected = len(d.commands) > 0 ? 0 : -1
	d.scroll = 0
	d.matches_dirty = true
}

graph_type_allowed_for_menu :: proc(graph: ^Node_Graph, node_type: ^Graph_Node_Type) -> bool {
	if !Graph_Kind_Allows_Type(graph, node_type.name) {return false}
	if !Graph_Kind_Is_Execution(graph) && Graph_Node_Type_Is_Exec(node_type) {return false}
	if !graph.menu_pending {return true}
	from := node_graph_port_of(graph, graph.active_port_node, graph.active_port)
	if from == nil {return true}
	if from.direction == .Input {
		return graph_type_has_compatible_output(graph, node_type, from)
	}
	return graph_type_has_compatible_input(graph, node_type, from)
}

graph_menu_type_matches :: proc(a, b: string) -> bool {
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

graph_type_has_compatible_input :: proc(
	graph: ^Node_Graph,
	node_type: ^Graph_Node_Type,
	from: ^Graph_Port,
) -> bool {
	for desc in node_type.inputs {
		if desc.direction == .Output {continue}
		if desc.port_kind != from.port_kind {continue}
		if graph_menu_type_matches(from.type, desc.type) {return true}
	}
	return false
}

graph_type_has_compatible_output :: proc(
	graph: ^Node_Graph,
	node_type: ^Graph_Node_Type,
	from: ^Graph_Port,
) -> bool {
	for desc in node_type.outputs {
		if desc.direction == .Input {continue}
		if desc.port_kind != from.port_kind {continue}
		if graph_menu_type_matches(desc.type, from.type) {return true}
	}
	return false
}

graph_menu_reroute_allowed :: proc(graph: ^Node_Graph) -> bool {
	//* A reroute is offered only while a wire is being completed in an
	//* empty region, and it carries data, so an exec wire has none.
	if !graph.menu_pending {return false}
	from := node_graph_port_of(graph, graph.active_port_node, graph.active_port)
	if from == nil {return true}
	return from.port_kind == .Data
}

graph_menu_create_reroute :: proc(g: ^GUI, menu: Widget_ID) {
	d := command_palette_data(g, menu)
	if d == nil || d.owner == INVALID_WIDGET_ID {return}
	graph := node_graph_of(g, d.owner)
	if graph == nil {return}

	pos := graph.menu_pos
	from_node := graph.active_port_node
	from_port := graph.active_port
	pending := graph.menu_pending
	direction := graph.menu_direction

	node_graph_undo_begin(g, d.owner)
	node := Graph_Add_Reroute_Dot(graph, pos)
	if node.index == 0 {
		node_graph_undo_cancel(g, d.owner)
		return
	}
	if pending {
		graph_auto_connect(g, d.owner, from_node, from_port, node, direction)
	}
	node_graph_undo_commit(g, d.owner, "create reroute")
	graph.menu_pending = false
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
	invalidate(g, d.owner, DIRTY_ALL)
}

command_palette_graph_create :: proc(g: ^GUI, palette: Widget_ID) {
	d := command_palette_data(g, palette)
	if d == nil || d.owner == INVALID_WIDGET_ID {return}
	graph := node_graph_of(g, d.owner)
	if graph == nil {return}
	if d.last_tag < 0 || d.last_tag >= len(graph.types) {return}

	type_name := graph.types[d.last_tag].name
	pos := graph.menu_pos
	from_node := graph.active_port_node
	from_port := graph.active_port
	pending := graph.menu_pending
	direction := graph.menu_direction

	node_graph_undo_begin(g, d.owner)
	node_id := node_graph_create_node(g, d.owner, type_name, pos)
	if node_id.index == 0 {
		node_graph_undo_cancel(g, d.owner)
		return
	}

	if pending {
		graph_auto_connect(g, d.owner, from_node, from_port, node_id, direction)
	}
	node_graph_undo_commit(g, d.owner, "create node")
	graph.menu_pending = false
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
}
node_graph_open_create_menu :: proc(g: ^GUI, id: Widget_ID) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	menu := graph_create_menu(g, id)
	if menu == INVALID_WIDGET_ID {return}
	graph_menu_rebuild(g, id, menu)

	content := Rect{}
	if w := Widget_Get(g, id); w != nil {content = content_rect(g, w)}
	point := node_graph_screen_pos(graph, content, graph.menu_pos)
	//* Keep the menu inside the canvas even when the creation position is
	//* outside the current view.
	rows := min(max(Command_Palette_Count(g, menu), 1), 12)
	height := PALETTE_FIELD_HEIGHT + f32(rows) * PALETTE_ROW + 16
	point.x = clamp(point.x, content.x + 4, max(content.x + 4, content.x + content.w - 424))
	point.y = clamp(point.y, content.y + 4, max(content.y + 4, content.y + content.h - height - 4))
	popup_set_rect(g, menu, Rect{
		x = point.x,
		y = point.y,
		w = 420,
		h = height,
	})
	Popup_Open(g, menu)
	if d := command_palette_data(g, menu); d != nil {
		d.selected = len(d.commands) > 0 ? 0 : -1
	}
}

node_graph_drop_on_empty :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) {
	graph := node_graph_of(g, id)
	if graph == nil {return}
	graph.menu_pos = pos
	node_graph_open_create_menu(g, id)
}

//* The menu was cancelled by Escape or by an outside click.
node_graph_menu_closed :: proc(g: ^GUI, graph: ^Node_Graph, id: Widget_ID) {
	_ = id
	graph.menu_pending = false
	graph.active_port_node = INVALID_GRAPH_NODE_ID
	graph.active_port = INVALID_GRAPH_PORT_ID
	_ = g
}

//* == The built-in actions ==

inspector_action_applies_to_nodes :: proc(summary: Graph_Selection_Summary) -> bool {
	return summary.node_count > 0
}

//* Wraps the selected nodes in a comment box and selects the box, so its
//* text and its colour are the first thing the inspector shows.
inspector_comment :: proc(g: ^GUI, id: Widget_ID, summary: Graph_Selection_Summary) {
	region := node_graph_add_region_around_selection(g, id, "Comment")
	if region.index == 0 {return}
	graph := node_graph_of(g, id)
	if graph == nil {return}
	for i in 0 ..< len(graph.nodes) {
		if graph.nodes[i].alive {graph.nodes[i].selected = false}
	}
	if box := Graph_Region_Of(graph, region); box != nil {
		box.selected = true
		//* The comment takes the colour of the theme, so a new box belongs
		//* to the document it lands in.
		if widget := Widget_Get(g, id); widget != nil {
			if colour := graph_colour(g, widget, GRAPH_THEME.region_border, Colour{}); colour.a > 0 {
				box.colour = colour
				box.colour.a = 1
			}
		}
	}
	invalidate(g, id, DIRTY_ALL)
}

//* Registers the actions that every graph has. An application adds its own
//* actions with node_graph_register_inspector_action.
node_graph_register_builtin_actions :: proc(g: ^GUI, id: Widget_ID) {
	//* The only action every graph carries is the comment: it wraps the
	//* selection in a region whose title and colour the inspector then
	//* edits.
	node_graph_register_inspector_action(g, id, Graph_Inspector_Action{
		name = "comment",
		label = "Add comment",
		description = "Puts the selection inside a comment box with a text and a colour.",
		applies = inspector_action_applies_to_nodes,
		invoke = inspector_comment,
	})
}


NODE_GRAPH_INSPECTOR_ROW_HEIGHT :: 28.0
NODE_GRAPH_INSPECTOR_LABEL_WIDTH :: 92.0
NODE_GRAPH_INSPECTOR_APPLY_WIDTH :: 52.0
NODE_GRAPH_INSPECTOR_SWATCH_WIDTH :: 20.0
NODE_GRAPH_INSPECTOR_TAB_HEIGHT :: 24.0

//* What one widget of the inspector writes back.
Inspector_Binding :: struct {
	source:    Graph_Inspector_Source,
	key:       string,
	node_id:   Graph_Node_ID,
	port_id:   Graph_Port_ID,
	region_id: Graph_Region_ID,
	wire_id:   Graph_Wire_ID,
	kind:      Graph_Inspector_Field_Kind,
	editor:    Widget_ID,
	index:     int,
}

//* A tab of the inspector: the key of the tab, the text it shows and the
//* place it takes, in window coordinates.
Inspector_Tab :: struct {
	key:   string,
	text:  string,
	rect:  Rect,
}

Node_Graph_Inspector_State :: struct {
	graph:       Widget_ID,
	status:      Widget_ID,
	body:        Widget_ID,
	desc:        Graph_Inspector_Desc,
	desc_live:   bool,
	rows:        [dynamic]Widget_ID,
	//* The tab a row belongs to. A tab button carries an empty key.
	row_tab:     [dynamic]string,
	bindings:    map[Widget_ID]Inspector_Binding,
	texts:       [dynamic]string,
	active:      string,
	tab_items:   [dynamic]Inspector_Tab,
	tabs_top:    f32,
	signature:   u64,
	label_width: f32,
	//* The width the body of the fields was last told it has.
	content_width: f32,
	show_header: bool,
	show_tabs:   bool,
}

Node_Graph_Inspector_Opts :: struct {
	Base_Opts: Base_Opts,
	graph:       Widget_ID,
	show_header: bool,
	show_tabs:   bool,
	label_width: f32,
	//* The width of the body of the fields, when the caller knows it
	//* already. The inspector follows its own width afterwards.
	content_width: f32,
}

//* Makes an inspector for a node graph. It shows the selection after the
//* first call to node_graph_inspector_refresh.
Make_Node_Graph_Inspector :: proc(g: ^GUI, parent: Widget_ID, opts: Node_Graph_Inspector_Opts) -> Widget_ID {
	kind_register(g, .NodeGraphInspector, node_graph_inspector_kind())
	id := New_Widget(g, .NodeGraphInspector, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.clip_contents = true

	state, err := virt.new(&g.arena, Node_Graph_Inspector_State)
	if err != nil {
		log.panicf("inspector allocation failed: %v", err)
	}
	state^ = Node_Graph_Inspector_State{
		graph = opts.graph,
		label_width = opts.label_width > 0 ? opts.label_width : NODE_GRAPH_INSPECTOR_LABEL_WIDTH,
		content_width = opts.content_width,
		show_header = opts.show_header,
		show_tabs = opts.show_tabs,
	}
	top := f32(4)
	if state.show_header {
		state.status = Make_Label(g, id, Label_Opts{
			Base_Opts = Base_Opts{
				name = "inspector_status",
				anchors = {0, 0, 1, 0},
				offsets = {left = 8, top = 4, right = -8, bottom = 30},
				size_flags_h = {.Fill},
				style = Style{text = Text_Style{colour = RGBA(0.72, 0.78, 0.88, 1), overrun = .Ellipsis}},
			},
			text = "Nothing selected",
		})
		top = 34
	}
	if state.show_tabs {
		state.tabs_top = top
		top += NODE_GRAPH_INSPECTOR_TAB_HEIGHT + 4
	}
	scroll := Make_Scroll_Container(g, id, Scroll_Container_Opts{
		Base_Opts = Base_Opts{
			name = "inspector_scroll",
			anchors = {0, 0, 1, 1},
			offsets = {left = 6, top = top, right = -6, bottom = -6},
			size_flags_h = {.Fill},
			size_flags_v = {.Fill},
			use_theme = true,
		},
	})
	state.body = Make_VBox(g, scroll, Box_Opts{
		Base_Opts = Base_Opts{name = "inspector_body", size_flags_h = {.Fill}, separation = 2},
	})
	w.data = Node_Graph_Inspector_Data{state = rawptr(state)}
	return id
}

node_graph_inspector_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw        = draw_node_graph_inspector,
		pointer     = pointer_node_graph_inspector,
		destroy     = destroy_node_graph_inspector,
		post_update = post_update_node_graph_inspector,
		style       = Style{},
		theme_name  = "NodeGraphInspector",
	}
}

//* Draws the tabs, which the inspector owns so that their place does not
//* depend on a row of buttons.
draw_node_graph_inspector :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	data := node_graph_inspector_state(g, id)
	if data == nil || !data.show_tabs {return}
	if len(data.tab_items) == 0 {return}
	style := resolved_style(g, w).text
	style.size = 15
	style.valign = .Center
	style.clip = false
	x := w.rect.x + 8
	y := w.rect.y + data.tabs_top
	for &item in data.tab_items {
		width := text_measure(g, style, item.text, 240).x
		rect := Rect{x = x, y = y, w = width, h = NODE_GRAPH_INSPECTOR_TAB_HEIGHT - 6}
		item.rect = rect
		active := item.key == data.active
		colour := active ? RGBA(0.94, 0.96, 1.0, 1) : RGBA(0.58, 0.64, 0.74, 1)
		draw_text(g, style, item.text, rect, colour)
		if active {
			draw_thick_line(
				g.target,
				{rect.x, rect.y + rect.h + 3},
				{rect.x + rect.w, rect.y + rect.h + 3},
				2,
				RGBA(0.35, 0.74, 1.0, 1),
				g.atlas_texture,
			)
		}
		x += width + 18
	}
}

//* A click on a tab opens it.
pointer_node_graph_inspector :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Down || e.button != .Left {return}
	data := node_graph_inspector_state(g, id)
	if data == nil {return}
	for item in data.tab_items {
		if !rect_contains(item.rect, e.pos.x, e.pos.y) {continue}
		data.active = item.key
		inspector_show_active_tab(g, data)
		inspector_size_content(g, data)
		invalidate(g, id, DIRTY_ALL)
		Event_Handled(g)
		return
	}
}

//* The body of the fields follows the width of the inspector, so a panel
//* that was resized still lays its editors out.
post_update_node_graph_inspector :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	data := node_graph_inspector_state(g, id)
	if data == nil {return}
	width := max(w.rect.w - 12, 120)
	if width == data.content_width {return}
	data.content_width = width
	inspector_size_content(g, data)
}

destroy_node_graph_inspector :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	#partial switch &data in w.data {
	case Node_Graph_Inspector_Data:
		if state := cast(^Node_Graph_Inspector_State)data.state; state != nil {
			inspector_release(g, state)
		}
	}
}

node_graph_inspector_state :: proc(g: ^GUI, id: Widget_ID) -> ^Node_Graph_Inspector_State {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &data in w.data {
	case Node_Graph_Inspector_Data:
		return cast(^Node_Graph_Inspector_State)data.state
	}
	return nil
}

//* The node graph an inspector describes.
node_graph_inspector_graph :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	data := node_graph_inspector_state(g, id)
	if data == nil {return INVALID_WIDGET_ID}
	return data.graph
}

//* Frees the fields, the description and the text the inspector holds.
inspector_release :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State) {
	for id in data.rows {Widget_Free(g, id)}
	for text in data.texts {delete(text)}
	if data.desc_live {
		Graph_Inspector_Free(&data.desc)
		data.desc_live = false
	}
	delete(data.rows)
	delete(data.row_tab)
	delete(data.texts)
	delete(data.bindings)
	delete(data.tab_items)
	data.rows = nil
	data.row_tab = nil
	data.texts = nil
	data.tab_items = nil
}

//* A copy of a text the inspector formats. A label borrows the text it is
//* given, so the text is held until the inspector looks again.
inspector_keep :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State, text: string) -> string {
	if len(text) == 0 {return ""}
	kept := strings.clone(text, context.allocator)
	append(&data.texts, kept)
	return kept
}

//* The text of a value, held by the inspector.
inspector_value_text :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State, value: Graph_Value) -> string {
	buf: [96]u8
	#partial switch v in value {
	case bool:
		return v ? "true" : "false"
	case i32:
		return inspector_keep(g, data, strconv.write_int(buf[:], i64(v), 10))
	case f32:
		return inspector_keep(g, data, fmt.bprintf(buf[:], "%.3g", f64(v)))
	case string:
		return v
	}
	return ""
}

//* The value a text holds, in the kind the field had before.
inspector_parse_value :: proc(text: string, previous: Graph_Value) -> Graph_Value {
	trimmed := strings.trim_space(text)
	#partial switch v in previous {
	case bool:
		return Graph_Value(strings.to_lower(trimmed) == "true")
	case i32:
		number, ok := strconv.parse_int(trimmed)
		if !ok {return Graph_Value(i32(0))}
		return Graph_Value(i32(number))
	case f32:
		number, ok := strconv.parse_f32(trimmed)
		if !ok {return Graph_Value(f32(0))}
		return Graph_Value(number)
	case string:
		return Graph_Value(text)
	}
	return Graph_Value(text)
}

//* The signature of what the inspector shows, so it only looks again when
//* the selection or the values change.
graph_inspector_signature :: proc(graph: ^Node_Graph) -> u64 {
	if graph == nil {return 0}
	summary := Graph_Selection_Summarize(graph)
	signature := u64(summary.kind) * 1000003 + 17
	signature += u64(summary.node_count) * 10007
	signature += u64(summary.wire_count) * 101
	signature += u64(summary.region_count) * 7
	signature += graph.revision * 131
	if node := Graph_Selected_Node(graph); node != nil {
		signature += u64(node.id.index) * 31 + u64(len(node.title)) + u64(len(node.config)) * 3
	}
	if wire := Graph_Selected_Wire(graph); wire != nil {
		signature += u64(wire.id.index) * 37
	}
	if region := Graph_Selected_Region(graph); region != nil {
		signature += u64(region.id.index) * 41 + u64(len(region.title))
	}
	return signature
}

//* Looks at the selection of the graph again. The inspector does nothing
//* when nothing it shows has changed, so this is cheap to call every frame.
node_graph_inspector_refresh :: proc(g: ^GUI, id: Widget_ID) -> bool {
	data := node_graph_inspector_state(g, id)
	if data == nil {return false}
	graph := node_graph_of(g, data.graph)
	if graph == nil {return false}
	signature := graph_inspector_signature(graph)
	if data.desc_live && signature == data.signature {return false}
	data.signature = signature
	inspector_rebuild(g, data, graph)
	return true
}

//* Builds the fields again from the description of the selection.
inspector_rebuild :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State, graph: ^Node_Graph) {
	for row in data.rows {Widget_Free(g, row)}
	clear(&data.rows)
	clear(&data.row_tab)
	clear(&data.bindings)
	for text in data.texts {delete(text, context.allocator)}
	clear(&data.texts)
	if data.desc_live {
		Graph_Inspector_Free(&data.desc)
		data.desc_live = false
	}

	data.desc = Graph_Inspector_Build(graph)
	data.desc_live = true
	if data.status != INVALID_WIDGET_ID {
		Widget_Set_Text(g, data.status, data.desc.summary.title)
	}

	if len(data.desc.tabs) == 0 {
		append(&data.rows, Make_Label(g, data.body, Label_Opts{
			Base_Opts = Base_Opts{name = "inspector_empty", size_flags_h = {.Fill}, min_size = {0, 24}},
			text = "Select a node, a wire or a region.",
		}))
		append(&data.row_tab, "")
		return
	}

	//* The tab that was open stays open when it is still there.
	active := ""
	for tab in data.desc.tabs {
		if tab.key == data.active {active = tab.key}
	}
	if active == "" {active = data.desc.tabs[0].key}
	data.active = active

	//* The tabs are drawn by the inspector, so their place is known without
	//* the layout of a row of buttons.
	if data.show_tabs {
		clear(&data.tab_items)
		for tab in data.desc.tabs {
			append(&data.tab_items, Inspector_Tab{
				key = tab.key,
				text = inspector_keep(g, data, tab.label),
			})
		}
	}

	for tab in data.desc.tabs {
		for section in tab.sections {
			if section.title != "" {
				append(&data.rows, Make_Label(g, data.body, Label_Opts{
					Base_Opts = Base_Opts{name = "inspector_section", size_flags_h = {.Fill}, min_size = {0, 22},
						style = Style{text = Text_Style{colour = RGBA(0.62, 0.70, 0.82, 1), transform = .Upper}},
					},
					text = inspector_keep(g, data, section.title),
				}))
				append(&data.row_tab, tab.key)
			}
			for &field in section.fields {
				inspector_make_field(g, data, &field, tab.key)
			}
		}
	}
	inspector_show_active_tab(g, data)
	inspector_size_content(g, data)
}

//* Shows only the rows of the tab that is open.
inspector_show_active_tab :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State) {
	for row, index in data.rows {
		if index >= len(data.row_tab) {continue}
		key := data.row_tab[index]
		if key == "" {continue}
		Widget_Set_Visible(g, row, key == data.active)
	}
}

//* A scroll container measures its child by the size the child asks for, so
//* the body of the fields is told how wide it is and how tall the rows of the
//* open tab are.
inspector_size_content :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State) {
	body := Widget_Get(g, data.body)
	if body == nil {return}
	width := max(data.content_width, 120)
	height := f32(0)
	for row, index in data.rows {
		if index < len(data.row_tab) {
			key := data.row_tab[index]
			if key != "" && key != data.active {continue}
		}
		if row_widget := Widget_Get(g, row); row_widget != nil {
			height += max(row_widget.min_size.y, 20) + 2
		}
	}
	body.min_size = Vec2{width, height}
	body.base_min_size = body.min_size
	//* A row asks for the width of the body, because a box inside a scroll
	//* takes the width of its widest child and not the width of the view.
	for row, index in data.rows {
		if row_widget := Widget_Get(g, row); row_widget != nil {
			row_widget.min_size.x = width
			row_widget.base_min_size.x = width
			invalidate(g, row, Dirty_Flags{.Measure, .Arrange, .Visual})
		}
		_ = index
	}
	invalidate(g, data.body, Dirty_Flags{.Measure, .Arrange, .Visual})
}

//* The row of a field: its name on the left, the editor of its value in the
//* room that is left, and the button that writes the value back.
inspector_make_field :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State, field: ^Graph_Inspector_Field, tab_key: string) {
	row := Make_HBox(g, data.body, Box_Opts{
		Base_Opts = Base_Opts{name = "inspector_field", size_flags_h = {.Fill}, separation = 4,
			min_size = {max(data.content_width, 120), NODE_GRAPH_INSPECTOR_ROW_HEIGHT}},
	})
	append(&data.rows, row)
	append(&data.row_tab, tab_key)

	//* The name keeps its width, so the editor takes all the room that is
	//* left instead of sharing it with a label that would grow. An action
	//* is a button that carries its own name, so it takes the whole row.
	if field.kind != .Button {
		Make_Label(g, row, Label_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_name", size_flags_h = {.Shrink_Center},
				min_size = {data.label_width, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2},
				style = Style{text = Text_Style{overrun = .Ellipsis}}},
			text = inspector_keep(g, data, field.label),
		})
	}

	editor := INVALID_WIDGET_ID
	#partial switch field.kind {
	case .Read_Only:
		Make_Label(g, row, Label_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_value", size_flags_h = {.Fill, .Expand},
				min_size = {0, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2},
				style = Style{text = Text_Style{overrun = .Ellipsis}}},
			text = inspector_value_text(g, data, field.value),
		})
	case .Bool:
		on := false
		#partial switch v in field.value {
		case bool:
			on = v
		}
		editor = Make_Check_Box(g, row, Check_Box_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_bool", size_flags_h = {.Shrink_Center},
				min_size = {0, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2}},
			on = on,
		})
	case .Choice:
		items := make([]string, len(field.options), context.temp_allocator)
		for option, index in field.options {
			if index < len(items) {items[index] = option}
		}
		editor = Make_Combo_Box(g, row, Combo_Box_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_choice", size_flags_h = {.Fill, .Expand}, use_theme = true,
				min_size = {0, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2}},
			items = items,
		})
		if choice := inspector_value_text(g, data, field.value); choice != "" {
			for option, index in items {
				if option == choice {
					combo_box_select(g, editor, index)
					break
				}
			}
		}
	case .Colour_Swatch:
		for swatch, index in field.swatches {
			button := Make_Button(g, row, Button_Opts{
				Base_Opts = Base_Opts{name = "inspector_field_swatch", fixed = true,
					min_size = {NODE_GRAPH_INSPECTOR_SWATCH_WIDTH, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2},
					style = Style{box = StyleBox{bg_color = swatch, content_margin = {1, 1, 1, 1}}}},
				text = "",
				on_pressed = inspector_on_swatch,
			})
			binding := inspector_binding_of(field)
			binding.index = index
			data.bindings[button] = binding
		}
	case .Button:
		button := Make_Button(g, row, Button_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_action", size_flags_h = {.Fill, .Expand}, use_theme = true,
				min_size = {0, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2}},
			text = inspector_keep(g, data, field.label),
			on_pressed = inspector_on_action,
		})
		binding := inspector_binding_of(field)
		data.bindings[button] = binding
	case .Text, .Number:
		editor = Make_Text_Box(g, row, Text_Box_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_text", size_flags_h = {.Fill, .Expand}, use_theme = true,
				min_size = {0, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2}},
			text = inspector_value_text(g, data, field.value),
		})
	}

	if editor != INVALID_WIDGET_ID {
		binding := inspector_binding_of(field)
		binding.editor = editor
		data.bindings[editor] = binding
		apply := Make_Button(g, row, Button_Opts{
			Base_Opts = Base_Opts{name = "inspector_field_apply", fixed = true, use_theme = true,
				min_size = {NODE_GRAPH_INSPECTOR_APPLY_WIDTH, NODE_GRAPH_INSPECTOR_ROW_HEIGHT - 2}},
			text = "Apply",
			on_pressed = inspector_on_apply,
		})
		data.bindings[apply] = binding
	}
}

//* The inspector a widget belongs to, found by walking up the tree, so a
//* callback of a field does not need to know the id of its own view.
inspector_state_of :: proc(g: ^GUI, id: Widget_ID) -> ^Node_Graph_Inspector_State {
	w := Widget_Get(g, id)
	for w != nil {
		#partial switch &d in w.data {
		case Node_Graph_Inspector_Data:
			return cast(^Node_Graph_Inspector_State)d.state
		}
		if w.parent == INVALID_WIDGET_ID {return nil}
		w = Widget_Get(g, w.parent)
	}
	return nil
}

//* The state of the inspector a widget belongs to, and the binding of that
//* widget.
inspector_lookup :: proc(g: ^GUI, id: Widget_ID) -> (data: ^Node_Graph_Inspector_State, binding: Inspector_Binding, found: bool) {
	data = inspector_state_of(g, id)
	if data == nil {return data, binding, false}
	binding, found = data.bindings[id]
	return data, binding, found
}

//* What a field writes back.
inspector_binding_of :: proc(field: ^Graph_Inspector_Field) -> Inspector_Binding {
	return Inspector_Binding{
		source = field.source,
		key = field.key,
		node_id = field.node_id,
		port_id = field.port_id,
		region_id = field.region_id,
		wire_id = field.wire_id,
		kind = field.kind,
	}
}

//* The text a field editor holds.
inspector_text_of :: proc(g: ^GUI, id: Widget_ID) -> string {
	w := Widget_Get(g, id)
	if w == nil {return ""}
	#partial switch &d in w.data {
	case Text_Box_Data:
		return d.text
	}
	return ""
}

//* Writes a value back to the model.
inspector_on_apply :: proc(g: ^GUI, id: Widget_ID) {
	data, binding, found := inspector_lookup(g, id)
	if !found {return}
	graph := node_graph_of(g, data.graph)
	if graph == nil {return}
	text := inspector_text_of(g, binding.editor)

	#partial switch binding.source {
	case .Node_Title:
		node_graph_set_node_title(g, data.graph, binding.node_id, text)
	case .Config:
		inspector_apply_config(g, data, graph, binding, text)
	case .Port_Name:
		if port := node_graph_port_of(graph, binding.node_id, binding.port_id); port != nil {
			node_graph_set_port_properties(g, data.graph, binding.node_id, binding.port_id, text, port.type)
		}
	case .Port_Type:
		if port := node_graph_port_of(graph, binding.node_id, binding.port_id); port != nil {
			node_graph_set_port_properties(g, data.graph, binding.node_id, binding.port_id, port.name, text)
		}
	case .Region_Title:
		node_graph_set_region_title(g, data.graph, binding.region_id, text)
	}
	inspector_rebuild_after_change(g, data, graph)
}

//* Writes a configuration entry back. The name of a node follows its title
//* and the type of a node follows its pins, so both are written together.
inspector_apply_config :: proc(
	g: ^GUI,
	data: ^Node_Graph_Inspector_State,
	graph: ^Node_Graph,
	binding: Inspector_Binding,
	text: string,
) {
	switch binding.key {
	case "name":
		node_graph_set_config_value(g, data.graph, binding.node_id, "name", Graph_Value(text))
		node_graph_set_node_title(g, data.graph, binding.node_id, text)
	case "type":
		node_graph_set_config_value(g, data.graph, binding.node_id, "type", Graph_Value(text))
		inspector_apply_type_to_pins(g, data, graph, binding, text)
	case:
		value := Graph_Value(text)
		if previous, found := node_graph_get_config_value(g, data.graph, binding.node_id, binding.key); found {
			value = inspector_parse_value(text, previous)
		}
		node_graph_set_config_value(g, data.graph, binding.node_id, binding.key, value)
	}
}

//* Writes the type of a node to its data pins, so a variable input changes
//* with its type.
inspector_apply_type_to_pins :: proc(
	g: ^GUI,
	data: ^Node_Graph_Inspector_State,
	graph: ^Node_Graph,
	binding: Inspector_Binding,
	type_name: string,
) {
	node := node_graph_node_of(graph, binding.node_id)
	if node == nil {return}
	for port in node.ports {
		if !port.alive || port.port_kind == .Exec {continue}
		node_graph_set_port_properties(g, data.graph, binding.node_id, port.id, port.name, type_name)
	}
}

//* Writes the colour of a region back.
inspector_on_swatch :: proc(g: ^GUI, id: Widget_ID) {
	data, binding, found := inspector_lookup(g, id)
	if !found {return}
	swatches := GRAPH_REGION_COLOURS
	if binding.index < 0 || binding.index >= len(swatches) {return}
	graph := node_graph_of(g, data.graph)
	if graph == nil {return}
	node_graph_set_region_colour(g, data.graph, binding.region_id, swatches[binding.index])
	inspector_rebuild_after_change(g, data, graph)
}

//* Runs an action of the model by its name.
inspector_on_action :: proc(g: ^GUI, id: Widget_ID) {
	data, binding, found := inspector_lookup(g, id)
	if !found {return}
	graph := node_graph_of(g, data.graph)
	if graph == nil {return}
	node_graph_inspector_action_invoke(g, data.graph, binding.key)
	inspector_rebuild_after_change(g, data, node_graph_of(g, data.graph))
}

//* Builds the fields again after a value changed.
inspector_rebuild_after_change :: proc(g: ^GUI, data: ^Node_Graph_Inspector_State, graph: ^Node_Graph) {
	data.signature = graph_inspector_signature(graph)
	inspector_rebuild(g, data, graph)
	//* The fields changed under the pointer, so the frame is redrawn.
	invalidate(g, data.graph, DIRTY_ALL)
}
