//* An overlay that says what the program is doing: how long the frame
//* took, how many things were drawn, and what is under the pointer.

package GUI

import "core:fmt"

Inspector :: struct {
	enabled:    bool,
	inspecting: bool,
}

inspector_enable :: proc(g: ^GUI, enabled: bool) {
	g.inspector.enabled = enabled
}

inspector_is_enabled :: proc(g: ^GUI) -> bool {
	return g.inspector.enabled
}

inspector_inspect :: proc(g: ^GUI, inspecting: bool) {
	g.inspector.inspecting = inspecting
}

draw_inspector :: proc(g: ^GUI) {
	if !g.inspector.enabled {return}

	lines: [dynamic]string
	defer delete(lines)

	append(&lines, fmt.tprintf("%.1f ms", f64(g.dt) * 1000))
	append(&lines, fmt.tprintf("%d widgets", len(g.widgets)))
	append(&lines, fmt.tprintf("%d commands", len(g.draw.commands)))
	append(&lines, fmt.tprintf("%d vertices", len(g.draw.vertices)))
	append(&lines, fmt.tprintf("atlas %d MiB", atlas_bytes(g)))

	if g.inspector.inspecting {
		id := hit_test(g, g.root, g.pointer)
		if w := Widget_Get(g, id); w != nil {
			append(&lines, fmt.tprintf("%s", w.name))
			append(
				&lines,
				fmt.tprintf(
					"%d %d %d %d",
					int(w.rect.x),
					int(w.rect.y),
					int(w.rect.w),
					int(w.rect.h),
				),
			)
		}
	}

	width := f32(0)
	for line in lines {
		size := Font_Measure(g, Font_Of(g, Widget_Get(g, g.root)), line).x
		if size > width {width = size}
	}
	height := f32(len(lines)) * 16 + 12
	rect := Rect {
		x = 8,
		y = 8,
		w = width + 16,
		h = height,
	}

	draw_rect(g, rect, RGBA(0.05, 0.05, 0.07, 0.85), 4)
	draw_border_box(g, rect, RGBA(0.30, 0.32, 0.38, 0.9))

	y := rect.y + 6
	for line in lines {
		Font_Draw(
			g,
			Font_Of(g, Widget_Get(g, g.root)),
			line,
			Rect{x = rect.x + 8, y = y, w = rect.w - 16, h = 16},
			RGBA(0.85, 0.88, 0.94, 1),
			.Left,
		)
		y += 16
	}
}

//* How much of the atlas is in use, in MiB.
atlas_bytes :: proc(g: ^GUI) -> int {
	if g.atlas == nil {return 0}
	return (g.atlas.width * g.atlas.height * 4) / (1024 * 1024)
}

draw_border_box :: proc(g: ^GUI, rect: Rect, colour: Colour) {
	t := f32(1)
	draw_quad(g.target, Rect{rect.x, rect.y, rect.w, t}, g.atlas.white_uv, colour, g.atlas_texture)
	draw_quad(
		g.target,
		Rect{rect.x, rect.y + rect.h - t, rect.w, t},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(g.target, Rect{rect.x, rect.y, t, rect.h}, g.atlas.white_uv, colour, g.atlas_texture)
	draw_quad(
		g.target,
		Rect{rect.x + rect.w - t, rect.y, t, rect.h},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
}
