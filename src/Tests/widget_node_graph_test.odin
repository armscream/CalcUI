//* Node graph interaction and view tests.

package Tests

import GUI "../GUI"
import "core:math"
import "core:testing"

Mouse_Down_Event :: GUI.Mouse_Down_Event

node_graph_test_make :: proc(t: ^testing.T) -> (g: ^GUI.GUI, graph: GUI.Widget_ID) {
	g = test_gui(t)
	g.backend = mock_backend
	graph = GUI.Make_Node_Graph(g, g.root, GUI.Node_Graph_Opts{})
	GUI.layout_pass(g)
	return
}

node_graph_test_near :: proc(a, b: f32) -> bool {
	return math.abs(a - b) < 0.01
}

node_graph_test_data :: proc(t: ^testing.T, g: ^GUI.GUI, graph: GUI.Widget_ID) -> ^GUI.Node_Graph_Data {
	data := GUI.node_graph_data(g, graph)
	if data == nil {
		testing.fail_now(t, "the graph has no data")
	}
	return data
}

@(test)
test_the_node_graph_zooms_with_the_wheel :: proc(t: ^testing.T) {
	g, graph := node_graph_test_make(t)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), 1.0)

	append(&g.events, mouse_move({100, 100}))
	append(&g.events, GUI.Wheel_Event{amount = 1})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph) > 1, true)

	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)
	testing.expect_value(t, node_graph_test_near(GUI.node_graph_zoom(g, graph), 1), true)

	for i in 0 ..< 100 {
		append(&g.events, GUI.Wheel_Event{amount = 1})
	}
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), GUI.NODE_GRAPH_MAX_ZOOM)

	for i in 0 ..< 200 {
		append(&g.events, GUI.Wheel_Event{amount = -1})
	}
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), GUI.NODE_GRAPH_MIN_ZOOM)

	test_gui_destroy(g)
}

@(test)
test_the_node_graph_pans_with_the_middle_button :: proc(t: ^testing.T) {
	g, graph := node_graph_test_make(t)
	testing.expect_value(t, GUI.node_graph_pan(g, graph), GUI.Vec2{})

	node := GUI.node_graph_add_node(g, graph, "Read", {40, 40})
	GUI.layout_pass(g)
	state := node_graph_test_data(t, g, graph).graph
	node_pos := state.nodes[node].pos

	append(&g.events, Mouse_Down_Event{
		pos = {100, 100}, global = {100, 100}, button = .Middle, clicks = 1,
	})
	append(&g.events, GUI.Mouse_Move_Event{
		pos = {150, 130}, global = {150, 130},
	})
	GUI.Handle_Events(g)

	pan := GUI.node_graph_pan(g, graph)
	testing.expect_value(t, pan, GUI.Vec2{50, 30})
	testing.expect_value(t, state.nodes[node].pos, node_pos)

	append(&g.events, GUI.Mouse_Up_Event{
		pos = {150, 130}, global = {150, 130}, button = .Middle,
	})
	append(&g.events, GUI.Mouse_Move_Event{
		pos = {200, 160}, global = {200, 160},
	})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.node_graph_pan(g, graph), pan)
	testing.expect_value(t, state.nodes[node].pos, node_pos)

	test_gui_destroy(g)
}

@(test)
test_the_node_graph_keeps_the_point_under_the_pointer :: proc(t: ^testing.T) {
	g, graph := node_graph_test_make(t)
	state := node_graph_test_data(t, g, graph).graph
	content := GUI.content_rect(g, GUI.Widget_Get(g, graph))
	pointer := GUI.Vec2{300, 200}
	before := GUI.node_graph_graph_pos(state, content, pointer)

	append(&g.events, mouse_move(pointer))
	append(&g.events, GUI.Wheel_Event{amount = 1})
	GUI.Handle_Events(g)

	after := GUI.node_graph_graph_pos(state, content, pointer)
	testing.expect_value(t, node_graph_test_near(after.x, before.x), true)
	testing.expect_value(t, node_graph_test_near(after.y, before.y), true)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph) > 1, true)

	test_gui_destroy(g)
}

@(test)
test_the_node_graph_zoom_is_clamped :: proc(t: ^testing.T) {
	g, graph := node_graph_test_make(t)

	GUI.node_graph_set_zoom(g, graph, 100)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), GUI.NODE_GRAPH_MAX_ZOOM)

	GUI.node_graph_set_zoom(g, graph, 0.01)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), GUI.NODE_GRAPH_MIN_ZOOM)

	GUI.node_graph_set_zoom(g, graph, 2)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), 2.0)

	test_gui_destroy(g)
}

@(test)
test_the_node_graph_pan_can_be_set_and_reset :: proc(t: ^testing.T) {
	g, graph := node_graph_test_make(t)

	GUI.node_graph_set_pan(g, graph, {30, 40})
	testing.expect_value(t, GUI.node_graph_pan(g, graph), GUI.Vec2{30, 40})

	GUI.node_graph_set_zoom(g, graph, 2)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), 2.0)
	testing.expect_value(t, GUI.node_graph_pan(g, graph), GUI.Vec2{30, 40})

	GUI.node_graph_reset_view(g, graph)
	testing.expect_value(t, GUI.node_graph_zoom(g, graph), 1.0)
	testing.expect_value(t, GUI.node_graph_pan(g, graph), GUI.Vec2{})

	test_gui_destroy(g)
}

@(test)
test_the_node_graph_still_drags_a_node_with_the_left_button :: proc(t: ^testing.T) {
	g, graph := node_graph_test_make(t)
	node := GUI.node_graph_add_node(g, graph, "Read", {40, 40})
	GUI.layout_pass(g)

	state := node_graph_test_data(t, g, graph).graph
	content := GUI.content_rect(g, GUI.Widget_Get(g, graph))
	start := GUI.node_graph_screen_pos(state, content, {50, 50})
	pan := state.pan

	append(&g.events, mouse_down(start))
	GUI.Handle_Events(g)
	GUI.Frame(g)

	append(&g.events, mouse_move({start.x + 20, start.y + 10}))
	GUI.Handle_Events(g)
	GUI.Frame(g)

	testing.expect_value(t, node_graph_test_near(state.nodes[node].pos.x, 60), true)
	testing.expect_value(t, node_graph_test_near(state.nodes[node].pos.y, 50), true)
	testing.expect_value(t, state.pan, pan)

	test_gui_destroy(g)
}