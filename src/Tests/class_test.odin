//* A reference custom widget implemented entirely through the public API.

package Tests

import GUI "../GUI"
import "core:strings"
import "core:testing"

Gauge_Data :: struct {
	value:   f32,
	pointer: GUI.Vec2,
	pressed: bool,
}

gauge_made: int
gauge_destroyed: int
gauge_freed: int
gauge_drawn: int
gauge_clicked: int
gauge_pointed: int
gauge_keyed: int
gauge_typed: int
gauge_signalled: int
gauge_signalled_value: f32

//* Register the class once; instances are made with GUI.Make_Custom_Widget.
gauge_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Gauge",
		kind = GUI.Widget_Kind{
			construct = gauge_construct,
			destroy = gauge_destroy,
			measure = gauge_measure,
			draw = gauge_draw,
			click = gauge_click,
			pointer = gauge_pointer,
			key = gauge_key,
			text_input = gauge_text_input,
			uses_arrow_keys = true,
			style = GUI.Style{box = StyleBox{
				bg_color = GUI.RGBA(0.15, 0.16, 0.20, 1),
				content_margin = {6, 4, 6, 4},
				corner_radius = {4, 4, 4, 4},
			}},
		},
		signals = {"value_changed"},
		constructor = gauge_scene_constructor,
	})
}

gauge_data :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> ^Gauge_Data {
	ptr := GUI.Widget_User_Data(g, id)
	return cast(^Gauge_Data)ptr if ptr != nil else nil
}

gauge_value :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> f32 {
	data := gauge_data(g, id)
	return data.value if data != nil else 0
}

gauge_set_value :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, value: f32) {
	data := gauge_data(g, id)
	if data == nil { return }

	value = clamp(value, 0, 1)
	if data.value == value { return }

	data.value = value
	GUI.Widget_Invalidate(g, id, GUI.Dirty_Flags{.Visual})
	GUI.Signal_Emit(g, id, "value_changed", value)
}

gauge_construct :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	gauge_made += 1
	GUI.Widget_Set_User_Data(g, id, cast(rawptr)new(Gauge_Data), gauge_free)
}

gauge_free :: proc(user: rawptr) {
	gauge_freed += 1
	free(user)
}

gauge_destroy :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	gauge_destroyed += 1
}

gauge_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	size := GUI.Measure_Text(g, GUI.Widget_Style(g, id).text, "100%", 0)
	return {size.x + 24, size.y + 8}
}

gauge_draw :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, content: GUI.Rect) {
	gauge_drawn += 1
	data := gauge_data(g, id)
	if data == nil { return }

	GUI.Draw_Rect(g, GUI.Rect{
		x = content.x,
		y = content.y,
		w = content.w * data.value,
		h = content.h,
	}, GUI.Widget_Text_Colour(g, id), 2)
}

gauge_click :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	gauge_clicked += 1
	gauge_set_value(g, id, gauge_value(g, id) + 0.25)
}

gauge_pointer :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, e: GUI.Pointer_Event) {
	gauge_pointed += 1
	data := gauge_data(g, id)
	if data == nil { return }

	data.pointer = e.local
	#partial switch e.kind {
	case .Down:
		data.pressed = true
	case .Up:
		data.pressed = false
	case .Move:
		if data.pressed {
			gauge_set_value(g, id, gauge_value_at(g, id, e.local))
		}
	}
}

gauge_value_at :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, local: GUI.Vec2) -> f32 {
	content := GUI.Widget_Content_Rect(g, id)
	if content.w <= 0 { return 0 }
	return clamp((local.x - content.x) / content.w, 0, 1)
}

gauge_key :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, e: GUI.Key_Down_Event) {
	gauge_keyed += 1
	#partial switch e.key {
	case .Right, .Up:
		gauge_set_value(g, id, gauge_value(g, id) + 0.25)
	case .Left, .Down:
		gauge_set_value(g, id, gauge_value(g, id) - 0.25)
	}
}

gauge_text_input :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, text: string) {
	gauge_typed += 1
	if len(text) != 1 || text[0] < '0' || text[0] > '9' { return }
	gauge_set_value(g, id, f32(text[0] - '0') / 10)
}

gauge_on_value_changed :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, value: any) {
	gauge_signalled += 1
	if v, ok := value.(f32); ok {
		gauge_signalled_value = v
	}
}

gauge_scene_constructor :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
) -> GUI.Widget_ID {
	return GUI.Make_Custom_Widget(g, parent, gauge_class(g), GUI.Base_Opts{name = name})
}

//* The custom class participates in construction, layout, drawing,
//* input, focus, signals and destruction like a built-in widget.

@(test)
test_a_widget_of_a_program_s_own_works_like_the_ones_that_are_built_in :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	gauge_made = 0
	gauge_destroyed = 0
	gauge_freed = 0
	gauge_drawn = 0
	gauge_clicked = 0
	gauge_pointed = 0
	gauge_keyed = 0
	gauge_typed = 0
	gauge_signalled = 0
	gauge_signalled_value = 0

	class := gauge_class(g)
	testing.expect_value(t, GUI.Widget_Class_Name(g, class), "Gauge")
	testing.expect_value(t, len(GUI.Widget_Class_Signals(g, class)), 1)

	gauge := GUI.Make_Custom_Widget(g, g.root, class, GUI.Base_Opts{
		name = "gauge",
		focus_mode = .Click,
	})
	testing.expect_value(t, gauge != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Class_Of(g, gauge), class)
	testing.expect_value(t, gauge_made, 1)

	GUI.layout_pass(g)
	w := GUI.Widget_Get(g, gauge)
	testing.expect_value(t, w.min_size.x > 0, true)
	testing.expect_value(t, w.min_size.y > 0, true)

	GUI.build_draw_list(g)
	testing.expect_value(t, gauge_drawn, 1)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)
	testing.expect_value(t, len(g.draw.clip_stack), 0)

	GUI.Widget_Connect(g, gauge, "value_changed", gauge_on_value_changed)

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, gauge_clicked, 1)
	testing.expect_value(t, gauge_signalled, 1)
	testing.expect_value(t, gauge_signalled_value, 0.25)
	testing.expect_value(t, gauge_value(g, gauge), 0.25)
	testing.expect_value(t, g.focused, gauge)

	append(&g.events, key_event(.Right))
	GUI.Handle_Events(g)
	testing.expect_value(t, gauge_keyed, 1)
	testing.expect_value(t, gauge_value(g, gauge), 0.5)

	append(&g.events, Text_Input_Event{text = strings.clone("7")})
	GUI.Handle_Events(g)
	testing.expect_value(t, gauge_typed, 1)
	testing.expect_value(t, gauge_value(g, gauge), 0.7)

	append(&g.events, mouse_move({100, 20}))
	GUI.Handle_Events(g)
	testing.expect_value(t, gauge_pointed > 0, true)

	test_gui_destroy(g)
}

@(test)
test_the_widget_of_a_program_s_own_is_destroyed_with_its_data :: proc(t: ^testing.T) {
	g := test_gui(t)
	gauge_made = 0
	gauge_destroyed = 0
	gauge_freed = 0

	gauge := GUI.Make_Custom_Widget(g, g.root, gauge_class(g), GUI.Base_Opts{name = "gauge"})
	testing.expect_value(t, gauge_made, 1)
	testing.expect_value(t, GUI.Widget_User_Data(g, gauge) != nil, true)

	GUI.Widget_Free(g, gauge)
	testing.expect_value(t, gauge_destroyed, 1)
	testing.expect_value(t, gauge_freed, 1)
	testing.expect_value(t, GUI.Widget_Alive(g, gauge), false)

	test_gui_destroy(g)
}

@(test)
test_the_theme_can_style_the_class_of_a_program_s_own :: proc(t: ^testing.T) {
	g := test_gui(t)
	gauge := GUI.Make_Custom_Widget(g, g.root, gauge_class(g), GUI.Base_Opts{name = "gauge"})

	testing.expect_value(t, GUI.Widget_Style(g, gauge).box.bg_color, GUI.RGBA(0.15, 0.16, 0.20, 1))

	w := GUI.Widget_Get(g, gauge)
	w.use_theme = true
	theme := GUI.Theme_Make()
	GUI.Theme_Set_Class(theme, "Gauge", GUI.Style{
		box = GUI.StyleBox{bg_color = GUI.RGBA(0.9, 0.2, 0.1, 1)},
	})
	GUI_Set_Theme(g, theme)

	testing.expect_value(t, GUI.Widget_Style(g, gauge).box.bg_color, GUI.RGBA(0.9, 0.2, 0.1, 1))
	test_gui_destroy(g)
}

@(test)
test_the_widgets_that_are_built_in_are_classes_as_well :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := Make_Check_Box(g, g.root, Check_Box_Opts{text = "agree"})
	class := GUI.Widget_Class_Of(g, box)
	testing.expect_value(t, class != INVALID_WIDGET_CLASS_ID, true)
	testing.expect_value(t, GUI.Widget_Class_Name(g, class), "CheckBox")

	by_name, found := class_by_name(g, "CheckBox")
	testing.expect_value(t, found, true)
	testing.expect_value(t, by_name, class)

	Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "CheckBox",
		kind = GUI.Widget_Kind{theme_name = "CheckBox"},
	})
	testing.expect_value(t, GUI.Widget_Class_Name(g, class), "CheckBox")
	testing.expect_value(t, GUI.Widget_Class_Of(g, box), class)

	test_gui_destroy(g)
}

@(test)
test_a_scene_file_can_name_the_class_of_a_program_s_own :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	gauge_made = 0

	gauge_class(g)
	root := Scene_Load(g, `
[node name="Root" type="Panel"]
    [node name="Gauge" type="Gauge" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {0, 0, 0, 40}
`)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)

	gauge := child_by_name(g, root, "Gauge")
	testing.expect_value(t, gauge != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, gauge_made, 1)
	testing.expect_value(t, GUI.Widget_Class_Name(g, GUI.Widget_Class_Of(g, gauge)), "Gauge")

	test_gui_destroy(g)
}