//* == Frame scheduling ==
//* The application owns the clock. Every pass of its loop it hands the
//* elapsed seconds to `GUI_Tick`; the core adds them to its one clock and
//* never reads a clock of its own. Widgets arm wake timers, and the core
//* says when the earliest one is due. An application asks
//* `GUI_Needs_Frame` after it has handled the events of the window, and
//* then either runs `Frame`, waits for the next event or the next wake,
//* or keeps going without touching the widget tree.
package Core

import "core:math"

//* Adds the delta of one application loop pass to the clock of the GUI.
//* A negative or non-finite delta is ignored: time never runs backwards.
GUI_Tick :: proc(g: ^GUI, dt: f32) {
	if g == nil {return}
	if math.is_nan(dt) || math.is_inf(dt) || dt < 0 {return}
	g.time += dt
}

GUI_Next_Frame_Delay_MS :: proc(g: ^GUI) -> i32 {
	if g == nil || !g.wake_valid {return -1}
	if g.time >= g.next_wake {return 0}
	ms := math.ceil((g.next_wake - g.time) * 1000)
	if ms < 0 {return 0}
	return i32(ms)
}

wake_at :: proc(g: ^GUI, at: f32) {
	if g == nil {return}
	g.wake_count += 1
	if !g.wake_valid || at < g.next_wake {
		g.next_wake = at
		g.wake_valid = true
	}
}

GUI_Request_Frame :: proc(g: ^GUI) {
	if g == nil {return}
	g.frame_requested = true
	draw_invalidate(g)
}


GUI_Needs_Frame :: proc(g: ^GUI) -> bool {
	if g == nil {return false}
	if g.frame_requested {return true}
	if g.inspector.enabled {return true}
	if draw_needs_rebuild(g) {return true}
	if g.full_layout {return true}
	if g.dirty != (Dirty_Flags{}) {return true}
	if g.wake_valid && g.time >= g.next_wake {return true}
	if animations_need_frame(g) {return true}
	if style_transitions_need_frame(g) {return true}
	if caret_needs_frame(g) {return true}
	if atlas_needs_frame(g) {return true}
	return false
}

//* True when the retained draw lists have to be built again.
draw_needs_rebuild :: proc(g: ^GUI) -> bool {
	if g == nil {return false}
	return !g.draw_valid || g.inspector.enabled
}

//* Starts a frame: the request that made it run has been answered, and the
//* requests that arrive during the frame belong to the next one.
Frame_Begin :: proc(g: ^GUI) {
	if g == nil {return}
	g.frame_requested = false
	g.frame_count += 1
	g.wake_count = 0
	g.next_wake = 0
	g.wake_valid = false
}

animations_need_frame :: proc(g: ^GUI) -> bool {
	for tween in g.animations {
		if tween.state == .Delayed || tween.state == .Running {return true}
	}
	return false
}

style_transitions_need_frame :: proc(g: ^GUI) -> bool {
	for w in g.widgets {
		if w == nil {continue}
		if w.style_cache.transition.active {return true}
	}
	return false
}

caret_needs_frame :: proc(g: ^GUI) -> bool {
	return false
}

atlas_needs_frame :: proc(g: ^GUI) -> bool {
	if g.atlas == nil {return false}
	if g.backend.upload_texture == nil {return false}
	return !g.atlas.uploaded || len(g.atlas.dirty) > 0
}
