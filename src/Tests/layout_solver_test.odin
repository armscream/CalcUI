//* The essential tests of the layout: the constraint a widget reports, the
//* solver that grows and shrinks the children of a box, and the absolute
//* child that takes no room in it.

package Tests

import GUI "../GUI"
import "core:testing"

//* A widget of the tests that would like to be 200 by 20, whatever the
//* room it is given. Its floor is the size asked for with the options of
//* the test, so a shrink has somewhere to go.
solver_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	return GUI.Vec2{200, 20}
}

solver_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "SolverWidget",
		kind = GUI.Widget_Kind{measure = solver_measure},
	})
}

solver_widget :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	floor: f32,
	shrink_weight: f32,
	weight := f32(1),
	fixed := false,
) -> GUI.Widget_ID {
	return GUI.Make_Custom_Widget(g, parent, solver_class(g), GUI.Base_Opts{
		name = name,
		min_size = GUI.Vec2{floor, 20},
		shrink_weight = shrink_weight,
		weight = weight,
		fixed = fixed,
	})
}

solver_slot :: proc(rect: GUI.Rect) -> GUI.Widget_Opts {
	return GUI.Widget_Opts{
		name = "slot",
		preset = .Top_Left,
		offsets = GUI.Offset {
			left = rect.x,
			top = rect.y,
			right = rect.x + rect.w,
			bottom = rect.y + rect.h,
		},
	}
}

@(test)
test_a_constraint_reports_the_measured_size_as_the_preferred :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	panel := GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts{name = "panel", min_size = GUI.Vec2{120, 40}},
	)
	GUI.layout_pass(g)

	c := GUI.Widget_Layout_Constraint(g, panel, true)
	testing.expect_value(t, c.minimum, 120.0)
	testing.expect_value(t, c.preferred, 120.0)
	testing.expect_value(t, c.maximum, 0.0)

	c = GUI.Widget_Layout_Constraint(g, panel, false)
	testing.expect_value(t, c.minimum, 40.0)
	testing.expect_value(t, c.preferred, 40.0)
	testing.expect_value(t, c.maximum, 0.0)
}

@(test)
test_a_child_that_shrinks_gives_the_room_back_by_its_weight :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	box := GUI.New_Widget(g, .HBox, g.root, solver_slot(GUI.Rect{w = 300, h = 100}))
	GUI.Widget_Set_Separation(g, box, 0)

	first := solver_widget(g, box, "first", 50, 1)
	second := solver_widget(g, box, "second", 50, 3)

	GUI.layout_pass(g)

	//* The children would like 200 each, but the box has only 300: the
	//* 100 that are missing are shared one to three.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.x, 0.0)
	testing.expect_value(t, f.rect.w, 175.0)
	testing.expect_value(t, s.rect.x, 175.0)
	testing.expect_value(t, s.rect.w, 125.0)
}

@(test)
test_an_absolute_child_takes_no_room_in_a_box :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	flow := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "flow", weight = 1})
	floating := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts {
			name = "floating",
			preset = .Top_Left,
			offsets = GUI.Offset{10, 20, 60, 60},
			absolute = true,
		},
	)

	GUI.layout_pass(g)

	//* The child in the flow takes the whole box, as it would without
	//* the absolute child; the absolute child sits where its offsets say.
	f := GUI.Widget_Get(g, flow)
	a := GUI.Widget_Get(g, floating)
	testing.expect_value(t, f.rect.x, 0.0)
	testing.expect_value(t, f.rect.y, 0.0)
	testing.expect_value(t, f.rect.w, 800.0)
	testing.expect_value(t, f.rect.h, 600.0)
	testing.expect_value(t, a.rect.x, 10.0)
	testing.expect_value(t, a.rect.y, 20.0)
	testing.expect_value(t, a.rect.w, 50.0)
	testing.expect_value(t, a.rect.h, 40.0)
}

@(test)
test_one_flexible_child_takes_all_the_room_that_is_left :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	box := GUI.New_Widget(g, .HBox, g.root, solver_slot(GUI.Rect{w = 500, h = 100}))
	GUI.Widget_Set_Separation(g, box, 0)

	first := solver_widget(g, box, "first", 0, 0, 0, true)
	second := solver_widget(g, box, "second", 0, 0)

	GUI.layout_pass(g)

	//* Only the second child expands, so it takes the 100 that are left
	//* over on top of its preferred size.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.w, 200.0)
	testing.expect_value(t, s.rect.x, 200.0)
	testing.expect_value(t, s.rect.w, 300.0)
}
