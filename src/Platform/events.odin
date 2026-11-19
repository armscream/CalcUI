package Platform

import sdl "vendor:sdl3"
import "core:c"
import "core:strings"
import GUI "../GUI"

client_origin :: proc(w: Window) -> GUI.Vec2 {
	x, y: c.int
	sdl.GetWindowPosition(w.handle, &x, &y)
	top, left, bottom, right: c.int
	sdl.GetWindowBordersSize(w.handle, &top, &left, &bottom, &right)
	s := Scale(w)
	return GUI.Vec2{f32(x) + f32(left) / s, f32(y) + f32(top) / s}
}

Global_Rect :: proc(w: Window) -> GUI.Rect {
	origin := client_origin(w)
	return GUI.Rect{x = origin.x, y = origin.y, w = f32(w.logical_w), h = f32(w.logical_h)}
}

event_global :: proc(w: Window, window_id: sdl.WindowID, pos: GUI.Vec2) -> GUI.Vec2 {
	if window_id == sdl.GetWindowID(w.handle) {
		origin := client_origin(w)
		return GUI.Vec2{origin.x + pos.x, origin.y + pos.y}
	}
	for popup in w.popups {
		if sdl.GetWindowID(popup.handle) == window_id {
			return GUI.Vec2{popup.pos.x + pos.x, popup.pos.y + pos.y}
		}
	}
	return pos
}

report_size :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	pw, ph := w.pixel_w, w.pixel_h
	read_size(w)
	if w.pixel_w == pw && w.pixel_h == ph { return }
	append(out, GUI.Resized_Event{size = {f32(w.logical_w), f32(w.logical_h)}})
}

Poll_Events :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	report_size(w, out)
	drain_events(w, out)
}

drain_events :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	ev: sdl.Event
	for sdl.PollEvent(&ev) {
		append_sdl_event(w, ev, out)
	}
}

//* Waits for an event, so a program that draws only when something happens
//* does not spin. A negative timeout waits until an event comes. The event
//* that wakes it and the ones already queued are put in `out`.
Wait_Events :: proc(w: ^Window, out: ^[dynamic]GUI.Event, timeout_ms: i32 = -1) {
	if len(out) > 0 { return }

	report_size(w, out)
	if len(out) > 0 { return }

	ev: sdl.Event
	waited :=
		timeout_ms < 0 ? sdl.WaitEvent(&ev) : sdl.WaitEventTimeout(&ev, timeout_ms)
	if !waited { return }

	append_sdl_event(w, ev, out)
	drain_events(w, out)
}

append_sdl_event :: proc(w: ^Window, ev: sdl.Event, out: ^[dynamic]GUI.Event) {
	#partial switch ev.type {
	case .MOUSE_MOTION:
		pos := GUI.Vec2{ev.motion.x, ev.motion.y}
		append(
			out,
			GUI.Mouse_Move_Event {
				pos = pos,
				global = event_global(w^, ev.motion.windowID, pos),
			},
		)
	case .MOUSE_BUTTON_DOWN:
		_ = sdl.CaptureMouse(true)
		pos := GUI.Vec2{ev.button.x, ev.button.y}
		append(
			out,
			GUI.Mouse_Down_Event {
				pos = pos,
				global = event_global(w^, ev.button.windowID, pos),
				button = translate_button(ev.button.button),
				clicks = int(ev.button.clicks),
			},
		)
	case .MOUSE_BUTTON_UP:
		_ = sdl.CaptureMouse(false)
		pos := GUI.Vec2{ev.button.x, ev.button.y}
		append(
			out,
			GUI.Mouse_Up_Event {
				pos = pos,
				global = event_global(w^, ev.button.windowID, pos),
				button = translate_button(ev.button.button),
			},
		)
	case .MOUSE_WHEEL:
		append(out, GUI.Wheel_Event{amount = ev.wheel.y})
	case .KEY_DOWN:
		append(
			out,
			GUI.Key_Down_Event {
				key = translate_key(ev.key.key),
				mods = translate_mods(ev.key.mod),
				repeat = ev.key.repeat,
			},
		)
	case .KEY_UP:
		append(
			out,
			GUI.Key_Up_Event {
				key = translate_key(ev.key.key),
				mods = translate_mods(ev.key.mod),
			},
		)
	case .TEXT_INPUT:
		text, _ := strings.clone_from_cstring(ev.text.text)
		append(out, GUI.Text_Input_Event{text = text})
	case .TEXT_EDITING:
		text, _ := strings.clone_from_cstring(ev.edit.text)
		append(
			out,
			GUI.Ime_Editing_Event {
				text = text,
				start = int(ev.edit.start),
				length = int(ev.edit.length),
			},
		)
	case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
		report_size(w, out)
	case .WINDOW_EXPOSED:
		append(out, GUI.Exposed_Event{})
	case .WINDOW_CLOSE_REQUESTED:
		//* A floating panel is a window of its own, so the quit is taken
		//* from the window the program owns and not from any of them.
		if ev.window.windowID == sdl.GetWindowID(w.handle) {
			append(out, GUI.Quit_Event{})
		}
	case .QUIT:
		append(out, GUI.Quit_Event{})
	}
}

translate_button :: proc(b: u8) -> GUI.Mouse_Button {
	switch b {
	case 1: return .Left
	case 2: return .Middle
	case 3: return .Right
	}
	return .Left
}

translate_mods :: proc(m: sdl.Keymod) -> GUI.Mods {
	mods: GUI.Mods
	if .LCTRL in m || .RCTRL in m do mods += GUI.Mods{.Ctrl}
	if .LSHIFT in m || .RSHIFT in m do mods += GUI.Mods{.Shift}
	if .LALT in m || .RALT in m do mods += GUI.Mods{.Alt}
	return mods
}

translate_key :: proc(k: sdl.Keycode) -> GUI.Key {
	if k >= sdl.K_A && k <= sdl.K_Z {
		return GUI.Key(int(k - sdl.K_A) + int(GUI.Key.A))
	}
	if k >= sdl.K_0 && k <= sdl.K_9 {
		return GUI.Key(int(k - sdl.K_0) + int(GUI.Key.Digit0))
	}
	switch k {
	case sdl.K_RETURN:    return .Enter
	case sdl.K_ESCAPE:    return .Escape
	case sdl.K_TAB:       return .Tab
	case sdl.K_SPACE:     return .Space
	case sdl.K_BACKSPACE: return .Backspace
	case sdl.K_DELETE:    return .Delete
	case sdl.K_LEFT:      return .Left
	case sdl.K_RIGHT:     return .Right
	case sdl.K_UP:        return .Up
	case sdl.K_DOWN:      return .Down
	case sdl.K_HOME:      return .Home
	case sdl.K_END:       return .End
	case sdl.K_PAGEUP:    return .Page_Up
	case sdl.K_PAGEDOWN:  return .Page_Down
	}
	return .None
}
