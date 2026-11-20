//* The tests of the compact GPU vertex: its layout, its quantization and
//* the revision that tells the GPU whether the geometry changed.

package Tests

import GUI "../GUI"
import "core:testing"

@(test)
test_the_packed_vertex_layout_is_the_gpu_attribute_table :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(GUI.Packed_Vertex), 60)
	testing.expect(t, size_of(GUI.Packed_Vertex) < size_of(GUI.Draw_Vertex))
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, pos), 0)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, uv), 8)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, colour), 12)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, shape), 16)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, local), 32)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, corners), 40)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, border), 48)
	testing.expect_value(t, offset_of(GUI.Packed_Vertex, opacity), 56)
}

@(test)
test_a_packed_vertex_round_trips :: proc(t: ^testing.T) {
	v := GUI.Draw_Vertex {
		pos = {12.5, 7.25},
		uv = {0.25, 0.75},
		colour = GUI.RGBA(0.4, 0.5, 0.6, 0.8),
		shape = {4, -6, 50, 40},
		local = {-1.5, 2.5},
		softness = -6,
		corners = {12.25, 0, 8, 4},
		border = {2, -1.5, 0.25, 0},
		opacity = 0.5,
	}
	p := GUI.pack_vertex(v)
	u := GUI.unpack_vertex(p)

	testing.expect_value(t, p.shape, [4]f32{4, -6, 50, 40})
	testing.expect_value(t, u.pos, v.pos)
	testing.expect_value(t, u.shape[0], v.shape[0])
	testing.expect_value(t, u.shape[2], v.shape[2])
	testing.expect_value(t, u.shape[3], v.shape[3])
	testing.expect_value(t, u.local, v.local)
	testing.expect_value(t, u.opacity, v.opacity)
	testing.expect_value(t, u.softness, v.softness)
	testing.expect(t, abs(u.uv[0] - v.uv[0]) <= 1.0 / 65535)
	testing.expect(t, abs(u.uv[1] - v.uv[1]) <= 1.0 / 65535)
	testing.expect(t, abs(u.colour.r - v.colour.r) <= 1.0 / 255)
	testing.expect(t, abs(u.colour.g - v.colour.g) <= 1.0 / 255)
	testing.expect(t, abs(u.colour.b - v.colour.b) <= 1.0 / 255)
	testing.expect(t, abs(u.colour.a - v.colour.a) <= 1.0 / 255)
	for i in 0 ..< 4 {
		testing.expect(t, abs(u.corners[i] - v.corners[i]) <= 1.0 / 16)
		testing.expect(t, abs(u.border[i] - v.border[i]) <= 1.0 / 128)
	}
}


@(test)
test_the_draw_list_revision_advances :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)
	begin_draw(g)

	start := g.draw.revision
	GUI.Draw_Rect(g, GUI.Rect{x = 0, y = 0, w = 10, h = 10}, GUI.RGBA(1, 0, 0, 1), 0)
	after_quad := g.draw.revision
	testing.expect(t, after_quad > start)

	GUI.Draw_Polygon(g, [][2]f32{{0, 0}, {10, 0}, {10, 10}}, GUI.RGBA(0, 1, 0, 1))
	testing.expect(t, g.draw.revision > after_quad)
}
