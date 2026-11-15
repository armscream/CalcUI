//* == Frame scheduling ==
//* The core says whether a frame is worth building. An application loop
//* asks `GUI_Needs_Frame` after it has handled the events of the window,
//* and then either runs `Frame`, waits for the next event, or keeps going
//* without touching the widget tree. The backends still own presentation
//* and any waiting they do; the core only answers the question.
package Core

//* Asks for a frame. A program calls this when it changed something the
//* setters did not see, or when a frame is needed for its own sake.
GUI_Request_Frame :: proc(g: ^GUI) {
	if g == nil {return}
	g.frame_requested = true
	draw_invalidate(g)
}

//* Sets whether the GUI is drawn on every pass of the application loop or
//* only when it needs to be. The change asks for a frame, so the first
//* state of the new mode is drawn at once.
GUI_Set_Frame_Mode :: proc(g: ^GUI, mode: Frame_Mode) {
	if g == nil {return}
	g.frame_mode = mode
	g.frame_requested = true
}

//* The mode the GUI is drawing in.
GUI_Frame_Mode :: proc(g: ^GUI) -> Frame_Mode {
	if g == nil {return .Continuous}
	return g.frame_mode
}

//* True when `Frame` has something to do: the GUI is in continuous mode, a
//* frame was asked for, the tree is dirty, an animation or a style
//* transition is running, the caret flashes, or the atlas has pixels that
//* the backend has not taken yet.
GUI_Needs_Frame :: proc(g: ^GUI) -> bool {
	if g == nil {return false}
	if g.frame_mode == .Continuous {return true}
	if g.frame_requested {return true}
	if g.inspector.enabled {return true}
	if draw_needs_rebuild(g) {return true}
	if g.full_layout {return true}
	if g.dirty != (Dirty_Flags{}) {return true}
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
	w := Widget_Get(g, g.focused)
	if w == nil {return false}
	if !(.Visible in w.state) || !(.Enabled in w.state) {return false}
	return widget_takes_text(g, g.focused)
}

atlas_needs_frame :: proc(g: ^GUI) -> bool {
	if g.atlas == nil {return false}
	if g.backend.upload_texture == nil {return false}
	return !g.atlas.uploaded || len(g.atlas.dirty) > 0
}
