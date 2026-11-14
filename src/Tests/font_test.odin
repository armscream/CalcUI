//* Tests for glyph quarter-pixel positioning, atlas caching, gutters,
//* and pixel-aligned drawing.

package Tests

import GUI "../GUI"
import "core:math"
import "core:os"
import "core:testing"
import runa "../GUI/dependencies/Runa"

font_artifact_bytes :: proc(t: ^testing.T) -> []u8 {
	bytes, err := os.read_entire_file_from_path("assets/fonts/Roboto-Regular.ttf", context.allocator)
	if err != nil {
		testing.fail_now(t, "could not read the test font")
	}
	return bytes
}

font_artifact_alpha :: proc(a: ^GUI.UI_Atlas, region: GUI.Atlas_Region, x, y: int) -> u8 {
	at := ((region.y + y) * a.width + region.x + x) * 4
	return a.pixels[at + 3]
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
test_two_glyphs_next_to_each_other_have_different_buckets :: proc(t: ^testing.T) {
	g := test_gui(t)
	bytes := font_artifact_bytes(t)
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	f := GUI.font_get(g, GUI.Font_At(g, family, 16))
	lines := GUI.font_layout(g, f, "Handgloves", f.opts)

	testing.expect_value(t, len(lines), 1)
	line := lines[0]
	testing.expect_value(t, len(line.glyphs) > 1, true)

	pg := line.glyphs[0]
	_, _, _, ok := GUI.font_glyph_place(g, f, pg, 10.0, 20.0)
	testing.expect_value(t, ok, true)
	_, _, _, ok = GUI.font_glyph_place(g, f, pg, 10.3, 20.0)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, len(g.glyphs), 2)

	pen: f32 = 0
	apart := 0
	for gi in 1 ..< len(line.glyphs) {
		advance := line.glyphs[gi - 1].x_advance
		pen += advance
		if GUI.glyph_snap(pen).quarter != GUI.glyph_snap(pen - advance).quarter {
			apart += 1
		}
	}
	testing.expect_value(t, apart > 0, true)

	test_gui_destroy(g)
}

@(test)
test_the_glyph_cache_holds_a_glyph_for_every_quarter :: proc(t: ^testing.T) {
	g := test_gui(t)
	bytes := font_artifact_bytes(t)
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	f := GUI.font_get(g, GUI.Font_At(g, family, 16))
	gid := runa.font_lookup_glyph(&f.file.font, 'A')
	testing.expect_value(t, gid != runa.Glyph_ID(0), true)

	regions: [4]GUI.Atlas_Region
	for q in 0 ..< 4 {
		entry, ok := GUI.font_slot(g, f, &f.file.font, gid, u8(q))
		testing.expect_value(t, ok, true)
		regions[q] = entry.region
	}
	testing.expect_value(t, len(g.glyphs), 4)

	for i in 0 ..< 4 {
		for j in i + 1 ..< 4 {
			testing.expect_value(t, regions[i].id != regions[j].id, true)
			testing.expect_value(t, regions[i].x != regions[j].x || regions[i].y != regions[j].y, true)
		}
	}

	test_gui_destroy(g)
}

@(test)
test_the_uv_of_a_glyph_is_one_pixel_inside_its_region :: proc(t: ^testing.T) {
	g := test_gui(t)
	bytes := font_artifact_bytes(t)
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	f := GUI.font_get(g, GUI.Font_At(g, family, 16))
	gid := runa.font_lookup_glyph(&f.file.font, 'A')
	entry, ok := GUI.font_slot(g, f, &f.file.font, gid, 0)
	testing.expect_value(t, ok, true)

	region := entry.region
	w, h := int(entry.px_size[0]), int(entry.px_size[1])
	testing.expect_value(t, w > 0, true)
	testing.expect_value(t, h > 0, true)
	testing.expect_value(t, region.w, w + 2)
	testing.expect_value(t, region.h, h + 2)

	inner := GUI.atlas_region_uv_inside(g.atlas, region, 1, 1, w, h)
	testing.expect_value(t, entry.uv, inner)
	testing.expect_value(t, entry.uv[0] > region.uv[0], true)
	testing.expect_value(t, entry.uv[1] > region.uv[1], true)
	testing.expect_value(t, entry.uv[2] < region.uv[2], true)
	testing.expect_value(t, entry.uv[3] < region.uv[3], true)

	for x in 0 ..< region.w {
		testing.expect_value(t, font_artifact_alpha(g.atlas, region, x, 0), u8(0))
		testing.expect_value(t, font_artifact_alpha(g.atlas, region, x, region.h - 1), u8(0))
	}
	for y in 0 ..< region.h {
		testing.expect_value(t, font_artifact_alpha(g.atlas, region, 0, y), u8(0))
		testing.expect_value(t, font_artifact_alpha(g.atlas, region, region.w - 1, y), u8(0))
	}

	test_gui_destroy(g)
}

@(test)
test_the_glyphs_are_drawn_on_whole_physical_pixels :: proc(t: ^testing.T) {
	g := test_gui(t)
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

	test_gui_destroy(g)
}
@(test)
test_colour_glyphs_keep_their_own_colour_and_skip_the_effects :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	bytes, err := os.read_entire_file_from_path("assets/fonts/Twemoji-Mozilla.ttf", context.allocator)
	if err != nil { return }
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Twemoji", bytes)
	GUI.Font_At(g, family, 24)

	GUI.draw_list_clear(&g.draw, g.viewport)
	g.target = &g.draw
	GUI.draw_text(
		g,
		GUI.Text_Style{
			size = 24,
			family = family,
			shadow_colour = GUI.RGBA(0, 0, 1, 1),
			shadow_offset = {1, 1},
			outline_colour = GUI.RGBA(0, 1, 0, 1),
			outline_size = 1,
		},
		"😀",
		GUI.Rect{x = 0, y = 0, w = 100, h = 100},
		GUI.RGBA(1, 0, 0, 1),
	)

	testing.expect_value(t, len(g.draw.vertices), 4)
	for v in g.draw.vertices {
		testing.expect_value(t, v.colour, GUI.RGBA(1, 1, 1, 1))
	}
}