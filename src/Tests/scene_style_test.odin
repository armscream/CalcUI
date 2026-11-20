//* The tests of the shape and shadow fields of the scene format: the
//* corners, the shadow spread and inset and the backdrop blur survive a
//* save and a load, and a malformed value is ignored with a report.

package Tests

import GUI "../GUI"
import "core:strings"
import "core:testing"

scene_style_text :: `
[node name="Root" type="Panel"]
    bg = {0.1, 0.2, 0.3, 1}
    corner_radius = 12
    shadow = {0, 0, 0, 0.5}
    shadow_size = 8
    shadow_offset = {2, 3}
    shadow_spread = 4
    shadow_inset = true
    backdrop_blur = 6
`

@(test)
test_shape_and_shadow_fields_survive_a_scene_save_and_load :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	root, report := GUI.Scene_Load_Report(g, scene_style_text)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect(t, root != GUI.INVALID_WIDGET_ID)
	testing.expect(t, !GUI.Scene_Report_Has_Errors(&report))

	style := GUI.Widget_Style(g, root)
	testing.expect_value(t, style.box.corner_radius, [4]f32{12, 12, 12, 12})
	testing.expect_value(t, style.box.shadow_size, 8.0)
	testing.expect_value(t, style.box.shadow_spread, 4.0)
	testing.expect(t, style.box.shadow_inset)
	testing.expect_value(t, style.box.shadow_offset, GUI.Vec2{2, 3})
	testing.expect_value(t, style.box.backdrop_blur, 6.0)
	testing.expect_value(t, style.box.shadow_color.a, 0.5)

	saved := GUI.Scene_Save(g, root)
	defer delete(saved)
	order := []string {
		"corner_radius",
		"shadow",
		"shadow_size",
		"shadow_offset",
		"shadow_spread",
		"shadow_inset",
		"backdrop_blur",
	}
	last := 0
	for key in order {
		at := strings.index(saved[last:], key)
		testing.expect(t, at >= 0)
		if at < 0 {continue}
		last += at + len(key)
	}

	second_gui := test_gui(t)
	defer test_gui_destroy(second_gui)
	second, second_report := GUI.Scene_Load_Report(second_gui, saved)
	defer GUI.Scene_Report_Destroy(&second_report)
	testing.expect(t, second != GUI.INVALID_WIDGET_ID)

	again := GUI.Widget_Style(second_gui, second)
	testing.expect_value(t, again.box.corner_radius, style.box.corner_radius)
	testing.expect_value(t, again.box.shadow_size, style.box.shadow_size)
	testing.expect_value(t, again.box.shadow_spread, style.box.shadow_spread)
	testing.expect_value(t, again.box.shadow_inset, style.box.shadow_inset)
	testing.expect_value(t, again.box.shadow_offset, style.box.shadow_offset)
	testing.expect_value(t, again.box.backdrop_blur, style.box.backdrop_blur)
}

