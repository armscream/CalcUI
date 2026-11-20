//* The essential tests of the frame lifecycle: the state update runs before
//* the layout pass, and a widget may be destroyed from an update hook.

package Tests

import GUI "../GUI"
import "core:testing"

frame_lifecycle_free_target: GUI.Widget_ID = GUI.INVALID_WIDGET_ID

//* A widget that asks for a size from its update hook. The size is
//* measured and arranged in the same frame.
frame_lifecycle_grow_update :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, dt: f32) {
	GUI.Widget_Set_Custom_Min_Size(g, id, GUI.Vec2{120, 40})
}

//* A widget whose update hook destroys the widget it was told to destroy,
//* once.
frame_lifecycle_free_update :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, dt: f32) {
	target := frame_lifecycle_free_target
	if target == GUI.INVALID_WIDGET_ID {return}
	frame_lifecycle_free_target = GUI.INVALID_WIDGET_ID
	GUI.Widget_Free(g, target)
}

@(test)
test_the_state_update_runs_before_the_layout_pass :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)
	g.backend = mock_backend

	class := GUI.Widget_Register_Class(
		g,
		GUI.Widget_Class_Desc {
			name = "FrameLifecycleGrow",
			kind = GUI.Widget_Kind{update = frame_lifecycle_grow_update},
		},
	)
	id := GUI.Make_Custom_Widget(
		g,
		g.root,
		class,
		GUI.Base_Opts{name = "grow", preset = .Top_Left},
	)

	GUI.Frame(g)

	//* The hook ran before the layout pass, so the size it asked for is
	//* the size of this frame, not the next one.
	w := GUI.Widget_Get(g, id)
	testing.expect(t, w != nil)
	if w != nil {
		testing.expect_value(t, w.rect.w, 120.0)
		testing.expect_value(t, w.rect.h, 40.0)
	}
}

@(test)
test_a_widget_can_be_destroyed_from_an_update_hook :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)
	g.backend = mock_backend

	class := GUI.Widget_Register_Class(
		g,
		GUI.Widget_Class_Desc {
			name = "FrameLifecycleFree",
			kind = GUI.Widget_Kind{update = frame_lifecycle_free_update},
		},
	)
	parent := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "parent"})
	doomed := GUI.Make_Custom_Widget(g, parent, class, GUI.Base_Opts{name = "doomed"})
	sibling := GUI.New_Widget(g, .Panel, parent, GUI.Widget_Opts{name = "sibling"})
	tail := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "tail"})

	//* The hook of `doomed` destroys its parent, which takes `doomed` and
	//* the sibling after it out of the tree. The walk has to skip the
	//* stale handles and reach the widget after them.
	frame_lifecycle_free_target = parent
	GUI.Frame(g)

	testing.expect_value(t, GUI.Widget_Get(g, parent), nil)
	testing.expect_value(t, GUI.Widget_Get(g, doomed), nil)
	testing.expect_value(t, GUI.Widget_Get(g, sibling), nil)
	testing.expect(t, GUI.Widget_Get(g, tail) != nil)
}
