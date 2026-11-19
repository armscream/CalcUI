package Tests

import GUI "../GUI"
import "core:fmt"
import "core:testing"
import virt "core:mem/virtual"

//* == The scenes ==

//* A GUI with a backend that does nothing, and with a font when the
//* text of the scene has to have a size.
bench_make_scene :: proc(t: ^testing.T, w, h: f32, with_font: bool) -> ^GUI.GUI {
	g := test_gui(t)
	g.viewport = GUI.Rect{w = w, h = h}
	g.window_rect = g.viewport
	g.backend = mock_backend
	if with_font {
		g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	}
	return g
}

//* Panels with a background and a border.
bench_scene_panels :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1),
			border_color = {GUI.RGBA(0.4, 0.4, 0.5, 1), GUI.RGBA(0.4, 0.4, 0.5, 1),
			                GUI.RGBA(0.4, 0.4, 0.5, 1), GUI.RGBA(0.4, 0.4, 0.5, 1)},
			border_width = {1, 1, 1, 1},
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel", style = style})
	}
}

//* Panels with rounded corners.
bench_scene_rounded :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1),
			corner_radius = {6, 6, 6, 6},
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel", style = style})
	}
}

//* Rounded glass panels with the optical stack, one standalone command each.
bench_scene_glass :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color      = GUI.RGBA(1, 1, 1, 0.15),
			corner_radius = {10, 10, 10, 10},
			backdrop_blur = 8,
			optics        = {refraction = 4, dispersion = 1.5, fresnel = 0.5, saturation = 1.1},
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "glass", style = style})
	}
}

//* Glass panels with a smaller glass panel inside each one.
bench_scene_glass_nested :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	outer_style := GUI.Style {
		box = GUI.StyleBox {
			bg_color      = GUI.RGBA(1, 1, 1, 0.15),
			corner_radius = {12, 12, 12, 12},
			backdrop_blur = 8,
			optics        = {refraction = 4, dispersion = 1.5, fresnel = 0.5, saturation = 1.1},
		},
	}
	inner_style := GUI.Style {
		box = GUI.StyleBox {
			bg_color      = GUI.RGBA(1, 1, 1, 0.10),
			corner_radius = {8, 8, 8, 8},
			backdrop_blur = 6,
			optics        = {refraction = 2, dispersion = 1, fresnel = 0.3, saturation = 1.05},
		},
	}
	for i in 0 ..< count {
		outer := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "glass_outer", style = outer_style})
		GUI.New_Widget(
			g,
			.Panel,
			outer,
			GUI.Widget_Opts {
				name = "glass_inner",
				preset = .Fill,
				offsets = GUI.Offset{left = 8, top = 8, right = -8, bottom = -8},
				style = inner_style,
			},
		)
	}
}

//* Rounded panels with an outer shadow, one SDF shadow quad each.
bench_scene_shadows :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color      = GUI.RGBA(0.2, 0.2, 0.3, 1),
			corner_radius = {10, 10, 10, 10},
			shadow_color  = GUI.RGBA(0, 0, 0, 0.5),
			shadow_size   = 8,
			shadow_offset = {0, 3},
			shadow_spread = 2,
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel", style = style})
	}
}

//* Rounded panels whose four borders have four colours, which needs the
//* strip geometry rather than one SDF border.
bench_scene_side_borders :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color      = GUI.RGBA(0.2, 0.2, 0.3, 1),
			border_color  = {
				GUI.RGBA(0.8, 0.8, 0.8, 1),
				GUI.RGBA(0.8, 0.8, 0.8, 1),
				GUI.RGBA(0.1, 0.1, 0.1, 1),
				GUI.RGBA(0.1, 0.1, 0.1, 1),
			},
			border_width  = {2, 2, 2, 2},
			corner_radius = {10, 10, 10, 10},
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel", style = style})
	}
}

//* Buttons with a short text.
bench_scene_buttons :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	for i in 0 ..< count {
		GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "button", text = "Press"})
	}
}

//* Labels with a long text, so that the text has to be measured and
//* broken into lines.
bench_scene_labels :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	for i in 0 ..< count {
		GUI.New_Widget(g, .Label, box, GUI.Widget_Opts{
			name = "label",
			text = "The quick brown fox jumps over the lazy dog",
		})
	}
}

//* The same labels inside one rounded clip that they never cross. Every
//* glyph stays inside the inner rectangle, so the fast path must keep
//* the clipper out of the text.
bench_scene_clip_labels :: proc(g: ^GUI.GUI, count: int) {
	style := GUI.Style {
		set = bit_set[GUI.Style_Field]{.BG, .Corner_Radius, .Padding},
		box = GUI.StyleBox {
			bg_color      = GUI.RGBA(0.1, 0.1, 0.13, 1),
			corner_radius = {24, 24, 24, 24},
			content_margin = {32, 32, 32, 32},
		},
	}
	panel := GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts{name = "clip", clip_contents = .On, preset = .Top_Left, offsets = {left = 0, top = 0, right = 1920, bottom = 4000}, style = style},
	)
	box := GUI.New_Widget(g, .VBox, panel, GUI.Widget_Opts{separation = 2})
	for i in 0 ..< count {
		GUI.New_Widget(g, .Label, box, GUI.Widget_Opts{
			name = "label",
			text = "The quick brown fox jumps over the lazy dog",
		})
	}
}

//* == The work ==

//* Builds the draw list of the scene again.
bench_work_draw :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	virt.arena_free_all(&g.frame_arena)
	GUI.build_draw_list(g)
}

//* Runs a whole frame, after the look of the scene was thrown away, so
//* that the frame has to draw it again.
bench_work_frame :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	GUI.Widget_Invalidate(g, g.root, GUI.Dirty_Flags{.Visual})
	GUI.Frame(g)
}

//* Runs a whole frame when nothing changed. The frame should do almost
//* nothing, because the dirty flags keep it from working.
bench_work_frame_idle :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	GUI.Frame(g)
}

//* Lays the whole scene out again.
bench_work_layout :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	GUI.invalidate_all(g, GUI.Dirty_Flags{.Arrange, .Hit})
	GUI.layout_pass(g)
}

//* Lays the scene out again after one widget changed. Only the branch
//* under that widget should be measured and arranged again.
bench_work_layout_one :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	scene := cast(^Bench_Scene)ctx
	GUI.Widget_Invalidate(g, scene.target, GUI.Dirty_Flags{.Measure})
	GUI.layout_pass(g)
}

//* Works out the style and the colours of every widget of the scene.
bench_work_style_colour :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	for w in g.widgets {
		if w == nil {continue}
		_ = GUI.resolved_bg(g, w.id, w)
		_ = GUI.resolved_text_colour(g, w.id, w)
	}
}

//* Makes a GUI with the given number of widgets and gives it back.
bench_work_make_gui :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	count := int(uintptr(ctx))
	ng := test_gui(t)
	bench_scene_panels(ng, count)
	GUI.layout_pass(ng)
	test_gui_destroy(ng)
}

//* Makes the atlas the pieces are taken from.
bench_make_atlas :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	return nil, cast(rawptr)GUI.atlas_make(512, 512)
}

bench_cleanup_atlas :: proc(g: ^GUI.GUI, ctx: rawptr) {
	if ctx == nil {return}
	GUI.atlas_destroy(cast(^GUI.UI_Atlas)ctx)
}

//* Makes an atlas and gives it back.
bench_work_make_atlas :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	a := GUI.atlas_make(GUI.ATLAS_DEFAULT_SIZE, GUI.ATLAS_DEFAULT_SIZE)
	GUI.atlas_destroy(a)
}

//* Takes a page of the atlas and gives it back.
bench_work_atlas_64 :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	a := cast(^GUI.UI_Atlas)ctx
	r := GUI.atlas_alloc(a, 64, 64, true)
	if r.id >= 0 {
		GUI.atlas_free(a, r)
	}
}

//* Builds the draw list of a virtual list again and counts the rows it
//* asked for.
bench_work_virtual_list :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	data := cast(^Bench_List_Data)ctx
	data.texts_asked = 0
	virt.arena_free_all(&g.frame_arena)
	GUI.build_draw_list(g)
}

//* Builds the draw list of a data table again and counts the rows it
//* asked for.
bench_work_data_table :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	data := cast(^Bench_Table_Data)ctx
	data.values_asked = 0
	virt.arena_free_all(&g.frame_arena)
	GUI.build_draw_list(g)
}

//* Builds the draw list of a node graph again.
bench_work_node_graph :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	virt.arena_free_all(&g.frame_arena)
	GUI.build_draw_list(g)
}

//* Moves the pointer over a node graph and lets the graph answer.
bench_work_node_graph_drag :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	scene := cast(^Bench_Graph)ctx
	pos := GUI.Vec2{
		x = scene.drag.x + f32(index % 40),
		y = scene.drag.y + f32((index / 40) % 5),
	}
	append(&g.events, mouse_move(pos))
	GUI.Handle_Events(g)
}

//* Moves the pointer over empty canvas of a node graph and asks the graph
//* what is under it. The index and the wire hit test are exercised.
bench_work_node_graph_hover_empty :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	scene := cast(^Bench_Graph)ctx
	pos := GUI.Vec2{
		x = scene.drag.x + f32(index % 4),
		y = scene.drag.y + f32((index / 4) % 4),
	}
	append(&g.events, mouse_move(pos))
	GUI.Handle_Events(g)
	_ = GUI.node_graph_node_at(g, scene.graph, pos)
	_ = GUI.node_graph_wire_at(g, scene.graph, pos)
}

//* == The virtualized data sources ==

BENCH_ROW_VALUES: [4]string = {"alpha", "bravo", "charlie", "delta"}

Bench_List_Data :: struct {
	count:       int,
	texts_asked: int,
}

Bench_Table_Data :: struct {
	count:        int,
	values_asked: int,
}

//* The widget of a scene that is changed by the benchmarks of the layout.
Bench_Scene :: struct {
	target: GUI.Widget_ID,
}

//* The node graph of the benchmarks of the graph.
Bench_Graph :: struct {
	graph: GUI.Widget_ID,
	drag:  GUI.Vec2,
}

bench_list_count :: proc(ctx: rawptr) -> int {
	return (cast(^Bench_List_Data)ctx).count
}

bench_list_text :: proc(ctx: rawptr, index: int) -> string {
	(cast(^Bench_List_Data)ctx).texts_asked += 1
	return "a row"
}

bench_list_height :: proc(ctx: rawptr, index: int) -> f32 {
	return 20 if index % 2 == 0 else 30
}

bench_list_source :: proc(data: ^Bench_List_Data) -> GUI.List_Source {
	return GUI.List_Source{count = bench_list_count, text = bench_list_text, ctx = cast(rawptr)data}
}

bench_list_source_with_heights :: proc(data: ^Bench_List_Data) -> GUI.List_Source {
	source := bench_list_source(data)
	source.height = bench_list_height
	return source
}

bench_table_count :: proc(ctx: rawptr) -> int {
	return (cast(^Bench_Table_Data)ctx).count
}

bench_table_values :: proc(ctx: rawptr, index: int) -> []string {
	(cast(^Bench_Table_Data)ctx).values_asked += 1
	return BENCH_ROW_VALUES[:]
}

bench_table_source :: proc(data: ^Bench_Table_Data) -> GUI.Table_Source {
	return GUI.Table_Source{count = bench_table_count, values = bench_table_values, ctx = cast(rawptr)data}
}

//* == The scenes of the benchmarks ==

bench_make_buttons :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, true)
	bench_scene_buttons(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_panels :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	bench_scene_panels(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_labels :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, true)
	bench_scene_labels(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

Bench_Pack :: struct {
	packed: [dynamic]GUI.Packed_Vertex,
}

bench_work_pack :: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int) {
	scene := cast(^Bench_Pack)ctx
	if scene == nil {return}
	resize(&scene.packed, len(g.draw.vertices))
	for v, i in g.draw.vertices {
		scene.packed[i] = GUI.pack_vertex(v)
	}
}

bench_make_pack :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = false
	bench_scene_rounded(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, cast(rawptr)new(Bench_Pack)
}

bench_cleanup_pack :: proc(g: ^GUI.GUI, ctx: rawptr) {
	scene := cast(^Bench_Pack)ctx
	if scene == nil {return}
	delete(scene.packed)
	free(scene)
}

bench_make_shadows :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = true
	bench_scene_shadows(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_side_borders :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = true
	bench_scene_side_borders(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_clip_labels :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, true)
	g.backend.supports_shapes = true
	bench_scene_clip_labels(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_rounded :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = true
	bench_scene_rounded(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_rounded_cpu :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = false
	bench_scene_rounded(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_glass :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = true
	g.backend.supports_backdrop_blur = true
	bench_scene_glass(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_glass_nested :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	g.backend.supports_shapes = true
	g.backend.supports_backdrop_blur = true
	bench_scene_glass_nested(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_panels_one :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 4000, false)
	bench_scene_panels(g, count)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	scene := new(Bench_Scene)
	scene.target = GUI.INVALID_WIDGET_ID
	box := GUI.Widget_Get(g, g.root)
	if box != nil {
		column := GUI.Widget_Get(g, box.first_child)
		if column != nil {
			panel := GUI.Widget_Get(g, column.first_child)
			if panel != nil {
				scene.target = panel.id
			}
		}
	}
	return g, cast(rawptr)scene
}

bench_cleanup_scene :: proc(g: ^GUI.GUI, ctx: rawptr) {
	if ctx == nil {return}
	free(cast(rawptr)cast(^Bench_Scene)ctx)
}

bench_make_virtual_list :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 800, 600, true)
	data := new(Bench_List_Data)
	data.count = count
	GUI.Make_Virtual_List(g, g.root, GUI.Virtual_List_Opts{
		Base_Opts = GUI.Base_Opts{name = "list"},
		source = bench_list_source(data),
		row_height = 20,
	})
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, cast(rawptr)data
}

bench_make_virtual_list_mixed :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 800, 600, true)
	data := new(Bench_List_Data)
	data.count = count
	GUI.Make_Virtual_List(g, g.root, GUI.Virtual_List_Opts{
		Base_Opts = GUI.Base_Opts{name = "list"},
		source = bench_list_source_with_heights(data),
		row_height = 20,
	})
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, cast(rawptr)data
}

bench_cleanup_list :: proc(g: ^GUI.GUI, ctx: rawptr) {
	if ctx == nil {return}
	free(cast(rawptr)cast(^Bench_List_Data)ctx)
}

bench_make_data_table :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 800, 600, true)
	data := new(Bench_Table_Data)
	data.count = count
	id := GUI.Make_Data_Table(g, g.root, GUI.Data_Table_Opts{
		Base_Opts = GUI.Base_Opts{name = "table"},
		source = bench_table_source(data),
	})
	GUI.data_table_add_column(g, id, "Name", 200)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
	return g, cast(rawptr)data
}

bench_cleanup_table :: proc(g: ^GUI.GUI, ctx: rawptr) {
	if ctx == nil {return}
	free(cast(rawptr)cast(^Bench_Table_Data)ctx)
}

bench_make_node_graph :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 1080, true)
	graph := bench_build_node_graph(g, count)
	GUI.layout_pass(g)
	GUI.node_graph_fit_view(g, graph)
	GUI.build_draw_list(g)
	return g, nil
}

bench_make_node_graph_drag :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 1080, true)
	graph := bench_build_node_graph(g, count)
	GUI.layout_pass(g)
	GUI.node_graph_fit_view(g, graph)
	GUI.node_graph_select_all(g, graph)

	content := GUI.content_rect(g, GUI.Widget_Get(g, graph))
	state := GUI.node_graph_model(g, graph)
	first := GUI.node_graph_node_of(state, state.nodes[0].id)
	start := GUI.node_graph_screen_pos(state, content, {first.pos.x + 20, first.pos.y + 10})

	scene := new(Bench_Graph)
	scene.graph = graph
	scene.drag = start
	append(&g.events, mouse_down(start))
	GUI.Handle_Events(g)
	return g, cast(rawptr)scene
}

bench_cleanup_graph :: proc(g: ^GUI.GUI, ctx: rawptr) {
	if ctx == nil {return}
	free(cast(rawptr)cast(^Bench_Graph)ctx)
}

//* Builds a graph and finds a point of the canvas that holds no node and no
//* wire, so the pointer can hover over empty canvas.
bench_make_node_graph_hover_empty :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	g := bench_make_scene(t, 1920, 1080, true)
	graph := bench_build_node_graph(g, count)
	GUI.layout_pass(g)
	GUI.node_graph_fit_view(g, graph)

	content := GUI.content_rect(g, GUI.Widget_Get(g, graph))
	point := GUI.Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5}
	found := false
	for y := content.y + 6; y < content.y + content.h - 6 && !found; y += 5 {
		for x := content.x + 6; x < content.x + content.w - 6; x += 5 {
			p := GUI.Vec2{x, y}
			if GUI.node_graph_node_at(g, graph, p).index != 0 {continue}
			if GUI.node_graph_wire_at(g, graph, p).index != 0 {continue}
			point = p
			found = true
			break
		}
	}

	scene := new(Bench_Graph)
	scene.graph = graph
	scene.drag = point
	return g, cast(rawptr)scene
}

//* Builds a graph with the given number of nodes, every node with four
//* ports, and two wires from every node to the next ones.
bench_build_node_graph :: proc(g: ^GUI.GUI, count: int) -> GUI.Widget_ID {
	graph := GUI.Make_Node_Graph(g, g.root, GUI.Node_Graph_Opts{})
	GUI.node_graph_undo_begin(g, graph)

	nodes := make([]GUI.Graph_Node_ID, count)
	defer delete(nodes)
	for i in 0 ..< count {
		x := f32(i % 25) * 180
		y := f32(i / 25) * 100
		nodes[i] = GUI.node_graph_add_node(g, graph, "Node", {x, y})
		GUI.node_graph_add_typed_port(g, graph, nodes[i], bench_port("A", .Input))
		GUI.node_graph_add_typed_port(g, graph, nodes[i], bench_port("B", .Input))
		GUI.node_graph_add_typed_port(g, graph, nodes[i], bench_port("X", .Output))
		GUI.node_graph_add_typed_port(g, graph, nodes[i], bench_port("Y", .Output))
	}

	state := GUI.node_graph_model(g, graph)
	for i in 0 ..< count {
		from := nodes[i]
		to_a := nodes[(i + 1) % count]
		to_b := nodes[(i + 2) % count]
		from_node := GUI.node_graph_node_of(state, from)
		to_a_node := GUI.node_graph_node_of(state, to_a)
		to_b_node := GUI.node_graph_node_of(state, to_b)
		GUI.node_graph_connect(g, graph, from, from_node.ports[2].id, to_a, to_a_node.ports[0].id)
		GUI.node_graph_connect(g, graph, from, from_node.ports[3].id, to_b, to_b_node.ports[1].id)
	}
	GUI.node_graph_undo_commit(g, graph, "bench")
	return graph
}

bench_port :: proc(name: string, direction: GUI.Graph_Port_Direction) -> GUI.Graph_Port_Desc {
	return GUI.Graph_Port_Desc{
		name = name,
		direction = direction,
		capacity = -1,
		visible = true,
	}
}

//* == The rules ==

//* A virtual list may only ask for the rows that are on the screen.
bench_verify_list :: proc(g: ^GUI.GUI, ctx: rawptr) -> string {
	if ctx == nil {return "the list had no data"}
	data := cast(^Bench_List_Data)ctx
	if data.texts_asked != 31 {
		return fmt.tprintf("the list asked for %d rows, it should have asked for 31", data.texts_asked)
	}
	return ""
}

//* A virtual list with rows of different heights may only ask for the
//* rows that are on the screen.
bench_verify_list_mixed :: proc(g: ^GUI.GUI, ctx: rawptr) -> string {
	if ctx == nil {return "the list had no data"}
	data := cast(^Bench_List_Data)ctx
	if data.texts_asked != 24 {
		return fmt.tprintf("the list asked for %d rows, it should have asked for 24", data.texts_asked)
	}
	return ""
}

//* A data table may only ask for the rows that are on the screen.
bench_verify_table :: proc(g: ^GUI.GUI, ctx: rawptr) -> string {
	if ctx == nil {return "the table had no data"}
	data := cast(^Bench_Table_Data)ctx
	if data.values_asked != 25 {
		return fmt.tprintf("the table asked for %d rows, it should have asked for 25", data.values_asked)
	}
	return ""
}

//* == The catalogue ==

bench_cases :: proc() -> []Bench_Case {
	cases: [dynamic]Bench_Case

	append(&cases, Bench_Case{
		id = "draw.buttons_200",
		title = "200 buttons",
		group = "draw",
		notes = "The cost of one draw list of a scene of 200 buttons.",
		iterations = 200,
		budget_ns = 30e6,
		count = 200,
		make = bench_make_buttons,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.panels_400",
		title = "400 panels with a border",
		group = "draw",
		notes = "The cost of one draw list of a scene of 400 panels with a background and a border.",
		iterations = 200,
		budget_ns = 20e6,
		count = 400,
		make = bench_make_panels,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.labels_60",
		title = "60 labels with a long text",
		group = "draw",
		notes = "The cost of one draw list of a scene of 60 labels, with the shaping and the placing of the text.",
		iterations = 50,
		budget_ns = 40e6,
		count = 60,
		make = bench_make_labels,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.pack_vertices",
		title = "the vertices of a draw list packed for the GPU",
		group = "draw",
		notes = "The cost of packing the vertices of a draw list into the compact GPU form, without uploading them.",
		iterations = 100,
		budget_ns = 7e6,
		count = 200,
		make = bench_make_pack,
		work = bench_work_pack,
		cleanup = bench_cleanup_pack,
	})
	append(&cases, Bench_Case{
		id = "draw.clip_labels_60",
		title = "60 labels inside a rounded clip",
		group = "draw",
		notes = "The cost of one draw list of a scene of 60 labels inside one rounded clip that none of the glyphs cross, so the fast path skips the shape clipper.",
		iterations = 50,
		budget_ns = 60e6,
		count = 60,
		make = bench_make_clip_labels,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.shadow_panels_200",
		title = "200 rounded panels with an outer shadow",
		group = "draw",
		notes = "The cost of one draw list of 200 rounded panels, each with one outer SDF shadow with spread.",
		iterations = 100,
		budget_ns = 7e6,
		count = 200,
		make = bench_make_shadows,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.side_borders_200",
		title = "200 rounded panels with four border colours",
		group = "draw",
		notes = "The cost of the strip geometry that a rounded border needs when its four sides have different colours.",
		iterations = 50,
		budget_ns = 60e6,
		count = 200,
		make = bench_make_side_borders,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.rounded_panels_200",
		title = "200 rounded panels, drawn by the shader",
		group = "draw",
		notes = "The cost of one draw list of a scene of 200 rounded panels, when the backend draws the corners with its shader.",
		iterations = 100,
		budget_ns = 8e6,
		count = 200,
		make = bench_make_rounded,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.rounded_panels_200_cpu",
		title = "200 rounded panels, drawn by the processor",
		group = "draw",
		notes = "The cost of one draw list of a scene of 200 rounded panels, when the backend has no shader and the corners are made on the processor.",
		iterations = 100,
		budget_ns = 15e6,
		count = 200,
		make = bench_make_rounded_cpu,
		work = bench_work_draw,
		compare_id = "draw.rounded_panels_200",
		compare_at = 4,
	})
	append(&cases, Bench_Case{
		id = "draw.glass_panels_200",
		title = "200 glass panels with the optical stack",
		group = "draw",
		notes = "The cost of one draw list of a scene of 200 glass panels, each a standalone command with the rim optics.",
		iterations = 100,
		budget_ns = 20e6,
		count = 200,
		make = bench_make_glass,
		work = bench_work_draw,
	})
	append(&cases, Bench_Case{
		id = "draw.glass_nested_100",
		title = "100 glass panels, each with a glass panel inside",
		group = "draw",
		notes = "The cost of one draw list of nested glass surfaces, which the backdrop plan has to split into a capture per nesting level.",
		iterations = 50,
		budget_ns = 30e6,
		count = 100,
		make = bench_make_glass_nested,
		work = bench_work_draw,
	})

	append(&cases, Bench_Case{
		id = "layout.panels_400",
		title = "400 panels, laid out from the top",
		group = "layout",
		notes = "The cost of one layout of the whole scene, when every widget is out of date.",
		iterations = 200,
		budget_ns = 5e6,
		count = 400,
		make = bench_make_panels,
		work = bench_work_layout,
	})
	append(&cases, Bench_Case{
		id = "layout.panels_400_one",
		title = "400 panels, laid out after one widget changed",
		group = "layout",
		notes = "The cost of one layout of the scene, when only one widget is out of date and the rest of the tree keeps its places.",
		iterations = 200,
		budget_ns = 3e6,
		count = 400,
		make = bench_make_panels_one,
		work = bench_work_layout_one,
		cleanup = bench_cleanup_scene,
	})

	append(&cases, Bench_Case{
		id = "style.panels_400_colour",
		title = "400 panels, with their colours",
		group = "style",
		notes = "The cost of working out the style, the background and the colour of the text of every widget of the scene.",
		iterations = 200,
		budget_ns = 6e6,
		count = 400,
		make = bench_make_panels,
		work = bench_work_style_colour,
	})

	append(&cases, Bench_Case{
		id = "frame.buttons_200",
		title = "200 buttons",
		group = "frame",
		notes = "The cost of one whole frame, with the update, the layout and the draw list of a scene of 200 buttons.",
		iterations = 100,
		budget_ns = 35e6,
		count = 200,
		make = bench_make_buttons,
		work = bench_work_frame,
	})
	append(&cases, Bench_Case{
		id = "frame.buttons_200_idle",
		title = "200 buttons, with nothing changed",
		group = "frame",
		notes = "The cost of one whole frame when nothing changed and the dirty flags keep the frame from working.",
		iterations = 100,
		budget_ns = 1500e3,
		count = 200,
		make = bench_make_buttons,
		work = bench_work_frame_idle,
	})

	append(&cases, Bench_Case{
		id = "lifecycle.gui_100_widgets",
		title = "a GUI with 100 widgets",
		group = "lifecycle",
		notes = "The cost of making a GUI with the atlas of 2048 by 2048 pixels it starts with, adding 100 widgets, laying it out and giving it back.",
		iterations = 20,
		budget_ns = 80e6,
		count = 100,
		make = bench_make_nothing,
		work = bench_work_make_gui,
	})
	append(&cases, Bench_Case{
		id = "lifecycle.atlas",
		title = "an atlas of the default size",
		group = "lifecycle",
		notes = "The cost of making the atlas of the glyphs of 2048 by 2048 pixels and giving it back.",
		iterations = 20,
		budget_ns = 60e6,
		make = bench_make_nothing,
		work = bench_work_make_atlas,
	})
	append(&cases, Bench_Case{
		id = "lifecycle.atlas_64",
		title = "a page of 64 by 64 of the atlas",
		group = "lifecycle",
		notes = "The cost of taking a page of 64 by 64 pixels out of an atlas of 512 by 512 and giving it back.",
		iterations = 2000,
		budget_ns = 5e3,
		make = bench_make_atlas,
		work = bench_work_atlas_64,
		cleanup = bench_cleanup_atlas,
	})

	sizes := [4]int{1000, 10000, 100000, 1000000}
	for count in sizes {
		append(&cases, Bench_Case{
			id = fmt.tprintf("widgets.virtual_list_%d", count),
			title = fmt.tprintf("a virtual list with %d rows", count),
			group = "widgets",
			notes = "The cost of one draw list of a virtual list with many rows, of which only the ones on the screen are asked for.",
			series = "virtual_list",
			iterations = 50,
		budget_ns = 4e6,
			count = count,
			make = bench_make_virtual_list,
			work = bench_work_virtual_list,
			verify = bench_verify_list,
			cleanup = bench_cleanup_list,
		})
	}
	for count in sizes {
		append(&cases, Bench_Case{
			id = fmt.tprintf("widgets.data_table_%d", count),
			title = fmt.tprintf("a data table with %d rows", count),
			group = "widgets",
			notes = "The cost of one draw list of a data table with many rows, of which only the ones on the screen are asked for.",
			series = "data_table",
			iterations = 50,
		budget_ns = 4e6,
			count = count,
			make = bench_make_data_table,
			work = bench_work_data_table,
			verify = bench_verify_table,
			cleanup = bench_cleanup_table,
		})
	}
	append(&cases, Bench_Case{
		id = "widgets.virtual_list_mixed_100000",
		title = "a virtual list with 100000 rows of different heights",
		group = "widgets",
		notes = "The cost of one draw list of a virtual list whose rows do not all have the same height.",
		iterations = 50,
		budget_ns = 3e6,
		count = 100000,
		make = bench_make_virtual_list_mixed,
		work = bench_work_virtual_list,
		verify = bench_verify_list_mixed,
		cleanup = bench_cleanup_list,
	})

	append(&cases, Bench_Case{
		id = "node_graph.draw_500",
		title = "a graph with 500 nodes and 1000 wires",
		group = "node_graph",
		notes = "The cost of one draw list of a node graph with 500 nodes and 1000 wires.",
		iterations = 20,
		budget_ns = 120e6,
		count = 500,
		make = bench_make_node_graph,
		work = bench_work_node_graph,
	})
	append(&cases, Bench_Case{
		id = "node_graph.drag_500",
		title = "a drag over a graph with 500 nodes and 1000 wires",
		group = "node_graph",
		notes = "The cost of one move of the pointer over a node graph with 500 nodes and 1000 wires.",
		iterations = 200,
		budget_ns = 100e3,
		count = 500,
		make = bench_make_node_graph_drag,
		work = bench_work_node_graph_drag,
		cleanup = bench_cleanup_graph,
	})
	append(&cases, Bench_Case{
		id = "node_graph.draw_2000",
		title = "a graph with 2000 nodes and 4000 wires",
		group = "node_graph",
		notes = "The cost of one draw list of a node graph with 2000 nodes and 4000 wires.",
		iterations = 10,
		budget_ns = 200e6,
		count = 2000,
		make = bench_make_node_graph,
		work = bench_work_node_graph,
	})
	append(&cases, Bench_Case{
		id = "node_graph.hover_empty_2000",
		title = "a pointer over empty canvas of a graph with 2000 nodes and 4000 wires",
		group = "node_graph",
		notes = "The cost of one frame while the pointer is over empty canvas of a graph with 2000 nodes and 4000 wires. The wire hit test and the index are exercised.",
		iterations = 50,
		budget_ns = 80e3,
		count = 2000,
		make = bench_make_node_graph_hover_empty,
		work = bench_work_node_graph_hover_empty,
		cleanup = bench_cleanup_graph,
	})

	return cases[:]
}

//* The benchmarks that do not need a scene. The count of the case is
//* kept in the context, so that the work of the case knows it.
bench_make_nothing :: proc(t: ^testing.T, count: int) -> (^GUI.GUI, rawptr) {
	return nil, cast(rawptr)(uintptr(count))
}

//* == The tests ==

@(test)
test_bench_the_draw_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "draw", cases)
}

@(test)
test_bench_the_layout_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "layout", cases)
}

@(test)
test_bench_the_style_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "style", cases)
}

@(test)
test_bench_the_frame_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "frame", cases)
}

@(test)
test_bench_the_lifecycle_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "lifecycle", cases)
}

@(test)
test_bench_the_widget_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "widgets", cases)
}

@(test)
test_bench_the_node_graph_benchmarks_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)
	bench_run_group(t, "node_graph", cases)
}

//* Every benchmark has to be named, measured and given a budget, so that
//* the report and the checks have something to work with.
@(test)
test_bench_the_catalogue_is_well_formed :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)

	testing.expect(t, len(cases) > 0, "the catalogue is empty")
	testing.expect(
		t,
		len(cases) <= BENCH_MAX_RESULTS,
		fmt.tprintf("the catalogue has %d benchmarks and the results hold %d", len(cases), BENCH_MAX_RESULTS),
	)

	for c in cases {
		testing.expect(t, c.id != "", "a benchmark has no id")
		testing.expect(t, c.group != "", fmt.tprintf("the benchmark %s has no group", c.id))
		testing.expect(t, c.title != "", fmt.tprintf("the benchmark %s has no title", c.id))
		testing.expect(t, c.notes != "", fmt.tprintf("the benchmark %s has no note", c.id))
		testing.expect(t, c.make != nil, fmt.tprintf("the benchmark %s has no scene", c.id))
		testing.expect(t, c.work != nil, fmt.tprintf("the benchmark %s has no work", c.id))
		testing.expect(t, c.iterations > 0, fmt.tprintf("the benchmark %s runs no times", c.id))
		testing.expect(t, c.budget_ns > 0, fmt.tprintf("the benchmark %s has no budget", c.id))
	}

	for c, i in cases {
		for other, j in cases {
			if i >= j {continue}
			if c.id != other.id {continue}
			testing.expect(t, false, fmt.tprintf("the benchmarks %s and %s share an id", c.id, other.id))
		}
	}
}

//* Every group of the catalogue has to have a test that runs it, so that
//* no benchmark is left out of a run.
@(test)
test_bench_every_group_is_run :: proc(t: ^testing.T) {
	cases := bench_cases()
	defer delete(cases)

	groups: [dynamic]string
	defer delete(groups)
	for c in cases {
		found := false
		for name in groups {
			if name == c.group {
				found = true
				break
			}
		}
		if !found {
			append(&groups, c.group)
		}
	}

	run := [7]string{"draw", "layout", "style", "frame", "lifecycle", "widgets", "node_graph"}
	for name in groups {
		found := false
		for other in run {
			if other == name {
				found = true
				break
			}
		}
		testing.expect(t, found, fmt.tprintf("the group %s has no test that runs it", name))
	}
}
