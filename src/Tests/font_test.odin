//* The essential tests of the text: glyph quarter-pixel positioning and
//* pixel-aligned drawing.

package Tests

import GUI "../GUI"
import "core:math"
import "core:os"
import "core:testing"

font_artifact_bytes :: proc(t: ^testing.T) -> []u8 {
	bytes, err := os.read_entire_file_from_path("assets/fonts/Roboto-Regular.ttf", context.allocator)
	if err != nil {
		testing.fail_now(t, "could not read the test font")
	}
	return bytes
}

@(test)
test_the_quarter_of_a_pixel_is_the_quarter_the_pen_falls_in :: proc(t: ^testing.T) {
	whole := GUI.glyph_snap(10)
	testing.expect_value(t, whole.pos, 10.0)
	testing.expect_value(t, whole.quarter, u8(0))

	one := GUI.glyph_snap(10.25)
	testing.expect_value(t, one.pos, 10.0)
	testing.expect_value(t, one.quarter, u8(1))

	two := GUI.glyph_snap(10.5)
	testing.expect_value(t, two.pos, 10.0)
	testing.expect_value(t, two.quarter, u8(2))

	three := GUI.glyph_snap(10.75)
	testing.expect_value(t, three.pos, 10.0)
	testing.expect_value(t, three.quarter, u8(3))

	over := GUI.glyph_snap(10.9)
	testing.expect_value(t, over.pos, 11.0)
	testing.expect_value(t, over.quarter, u8(0))

	before := GUI.glyph_snap(-0.5)
	testing.expect_value(t, before.pos, -1.0)
	testing.expect_value(t, before.quarter, u8(2))
}

@(test)
test_the_glyphs_are_drawn_on_whole_physical_pixels :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)
	bytes := font_artifact_bytes(t)
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	GUI.Font_At(g, family, 16)

	GUI.draw_list_clear(&g.draw, g.viewport)
	g.target = &g.draw
	GUI.draw_text(
		g,
		GUI.Text_Style{size = 16, family = family},
		"Hello, world",
		GUI.Rect{x = 3, y = 5, w = 400, h = 100},
		GUI.RGBA(1, 1, 1, 1),
	)

	testing.expect_value(t, len(g.draw.vertices) > 0, true)
	for v in g.draw.vertices {
		testing.expect_value(t, v.pos[0] == math.floor(v.pos[0]), true)
		testing.expect_value(t, v.pos[1] == math.floor(v.pos[1]), true)
	}
}
