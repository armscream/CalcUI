package Backend

import GUI "../GUI"

BACKDROP_SCALE :: f32(0.5)

//* The levels of the backdrop mip chain: level 0 is half the window, and
//* every level after it is half of the level before.
BACKDROP_MIPS :: 5

Backdrop_Group :: struct {
	first: int,
	rect:  GUI.Rect,
}

Backdrop_Plan :: struct {
	groups:        [dynamic]Backdrop_Group,
	command_group: [dynamic]i32,
}

backdrop_plan_destroy :: proc(plan: ^Backdrop_Plan) {
	if plan == nil {return}
	delete(plan.groups)
	delete(plan.command_group)
	plan^ = {}
}

backdrop_rect_union :: proc(a, b: GUI.Rect) -> GUI.Rect {
	if a.w <= 0 || a.h <= 0 {return b}
	if b.w <= 0 || b.h <= 0 {return a}
	x0 := min(a.x, b.x)
	y0 := min(a.y, b.y)
	x1 := max(a.x + a.w, b.x + b.w)
	y1 := max(a.y + a.h, b.y + b.h)
	return GUI.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
}

backdrop_rect_meets :: proc(a, b: GUI.Rect) -> bool {
	if a.w <= 0 || a.h <= 0 || b.w <= 0 || b.h <= 0 {return false}
	return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

backdrop_rect_expand :: proc(r: GUI.Rect, pad: f32) -> GUI.Rect {
	p := max(pad, 0)
	return GUI.Rect{x = r.x - p, y = r.y - p, w = r.w + p * 2, h = r.h + p * 2}
}

backdrop_command_bounds :: proc(dl: ^GUI.Draw_List, cmd: GUI.Draw_Command) -> GUI.Rect {
	if cmd.glass {return cmd.bounds}
	if cmd.idx_count == 0 {return {}}
	if int(cmd.idx_offset) + int(cmd.idx_count) > len(dl.indices) {return {}}

	x0, y0 := f32(0), f32(0)
	x1, y1 := f32(0), f32(0)
	found := false
	for i in 0 ..< int(cmd.idx_count) {
		index := int(dl.indices[int(cmd.idx_offset) + i])
		if index < 0 || index >= len(dl.vertices) {continue}
		pos := dl.vertices[index].pos
		if !found {
			x0, y0 = pos[0], pos[1]
			x1, y1 = pos[0], pos[1]
			found = true
			continue
		}
		x0 = min(x0, pos[0])
		y0 = min(y0, pos[1])
		x1 = max(x1, pos[0])
		y1 = max(y1, pos[1])
	}
	if !found {return {}}
	return GUI.Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
}

backdrop_plan_build :: proc(plan: ^Backdrop_Plan, dl: ^GUI.Draw_List) {
	if plan == nil {return}
	clear(&plan.groups)
	clear(&plan.command_group)
	if dl == nil {return}

	for cmd in dl.commands {
		append(&plan.command_group, -1)
	}

	dirty_solid: GUI.Rect
	dirty_glass: GUI.Rect
	have_solid := false
	have_glass := false
	current := -1
	for cmd, i in dl.commands {
		if cmd.idx_count == 0 {continue}
		bounds := backdrop_command_bounds(dl, cmd)
		if cmd.glass {
			read := backdrop_rect_expand(bounds, cmd.blur)
			needs_capture := current < 0 ||
				(have_solid && backdrop_rect_meets(read, dirty_solid)) ||
				(have_glass && backdrop_rect_meets(bounds, dirty_glass))
			if needs_capture {
				append(&plan.groups, Backdrop_Group{first = i, rect = read})
				current = len(plan.groups) - 1
				dirty_solid = {}
				dirty_glass = {}
				have_solid = false
				have_glass = false
			} else {
				plan.groups[current].rect = backdrop_rect_union(plan.groups[current].rect, read)
			}
			plan.command_group[i] = i32(current)
			dirty_glass = backdrop_rect_union(dirty_glass, bounds)
			have_glass = true
		} else {
			dirty_solid = backdrop_rect_union(dirty_solid, bounds)
			have_solid = true
		}
	}
}
