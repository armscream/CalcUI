//* The window of the program: the events that come from it, and the
//* floating panels that get a window of their own.
//* SDL gives the mouse in points and the GUI works in pixels, so
//* everything that comes from the mouse is scaled on the way in.
package Window

import sdl "vendor:sdl3"
import "core:c"
import "core:log"
import "core:strings"
import GUI "../GUI"

//* The window of the program. Its size is kept in pixels, not in points.
Window :: struct {
	handle: ^sdl.Window,
	//* The size of the drawable area the last time the GUI was told
	//* about it. The size the platform gives is looked at every time
	//* the events are polled, so a resize is reported even when the
	//* platform does not send an event for it.
	pixel_w: i32,
	pixel_h: i32,
	//* The windows of the floating panels. They are in the same order
	//* as the floating panels in the GUI.
	popups: [dynamic]^sdl.Window,
	//* Where the floating panels are on the screen, in pixels.
	popup_pos: [dynamic]GUI.Vec2,
	//* The cursors the GUI asks for, indexed by GUI.Cursor, and the
	//* one that is active.
	cursors: [dynamic]^sdl.Cursor,
	cursor:  GUI.Cursor,
}

Init_SDL :: proc() -> bool {
	return sdl.Init({.VIDEO})
}

Create_Window :: proc(w, h: i32, title: string) -> (Window, bool) {
	handle := sdl.CreateWindow(
		strings.clone_to_cstring(title, context.temp_allocator), w, h, {.RESIZABLE}
	)
	if handle == nil { return Window{}, false }
	//* Text input (and the IME) has to be started explicitly on SDL3,
	//* otherwise the window never delivers TEXT_INPUT events.
	if !sdl.StartTextInput(handle) {
		log.warnf("could not start text input: %s", sdl.GetError())
	}
	window := Window{handle = handle}
	window.pixel_w, window.pixel_h = Pixel_Size(window)
	return window, true
}

Destroy_Window :: proc(w: Window) {
	for popup in w.popups {
		if popup != nil { sdl.DestroyWindow(popup) }
	}
	delete(w.popups)
	delete(w.popup_pos)
	for cursor in w.cursors {
		if cursor != nil { sdl.DestroyCursor(cursor) }
	}
	delete(w.cursors)
	if w.handle != nil { sdl.DestroyWindow(w.handle) }
}

//* The size of the drawable area in pixels.
Pixel_Size :: proc(w: Window) -> (i32, i32) {
	pw, ph: i32
	sdl.GetWindowSizeInPixels(w.handle, &pw, &ph)
	return pw, ph
}

//* The size of the window in points (logical coordinates).
point_size :: proc(w: Window) -> (i32, i32) {
	tw, th: i32
	sdl.GetWindowSize(w.handle, &tw, &th)
	return tw, th
}

//* How many pixels one point covers. 1.0 on a normal display.
scale :: proc(w: Window) -> f32 {
	pw, _ := Pixel_Size(w)
	tw, _ := point_size(w)
	if pw <= 0 || tw <= 0 { return 1 }
	return f32(pw) / f32(tw)
}

//* The client area starts below the title bar, so the border sizes
//* have to be added to the position of the window.
client_origin :: proc(w: Window) -> GUI.Vec2 {
	x, y: c.int
	sdl.GetWindowPosition(w.handle, &x, &y)
	top, left, bottom, right: c.int
	sdl.GetWindowBordersSize(w.handle, &top, &left, &bottom, &right)
	s := scale(w)
	return GUI.Vec2{f32(x + left) * s, f32(y + top) * s}
}

//* Where the client area of the window is on the screen, in pixels.
Global_Rect :: proc(w: Window) -> GUI.Rect {
	origin := client_origin(w)
	pw, ph := Pixel_Size(w)
	return GUI.Rect{x = origin.x, y = origin.y, w = f32(pw), h = f32(ph)}
}

//* == The cursor ==
//* The GUI asks for a cursor when the pointer is on an edge that can
//* be pulled. The cursors are made once and kept, so the pointer does
//* not flicker.

Set_Cursor :: proc(w: ^Window, cursor: GUI.Cursor) {
	if w.cursor == cursor { return }
	w.cursor = cursor

	for len(w.cursors) <= int(cursor) {
		id := GUI.Cursor(len(w.cursors))
		append(&w.cursors, sdl.CreateSystemCursor(System_Cursor_Of(id)))
	}

	c := w.cursors[int(cursor)]
	if c == nil { return }
	_ = sdl.SetCursor(c)
}

System_Cursor_Of :: proc(cursor: GUI.Cursor) -> sdl.SystemCursor {
	switch cursor {
	case .Default:      return .DEFAULT
	case .Pointer:      return .POINTER
	case .Text:         return .TEXT
	case .Crosshair:    return .CROSSHAIR
	case .Wait:         return .WAIT
	case .Not_Allowed:  return .NOT_ALLOWED
	case .Grab:         return .MOVE
	case .Grabbing:     return .MOVE
	case .Resize_NS:    return .NS_RESIZE
	case .Resize_W:     return .W_RESIZE
	case .Resize_E:     return .E_RESIZE
	case .Resize_N:     return .N_RESIZE
	case .Resize_S:     return .S_RESIZE
	case .Resize_NW:    return .NW_RESIZE
	case .Resize_NE:    return .NE_RESIZE
	case .Resize_SW:    return .SW_RESIZE
	case .Resize_SE:    return .SE_RESIZE
	}
	return .DEFAULT
}

//* == The clipboard ==
//* The clipboard of the GUI and the clipboard of the system are kept in
//* step: what the program puts in the GUI's clipboard goes to the
//* system, and what is in the system comes back.

Sync_Clipboard :: proc(g: ^GUI.GUI) {
	if g.clipboard.dirty {
		text := strings.clone_to_cstring(g.clipboard.text, context.temp_allocator)
		_ = sdl.SetClipboardText(text)
		g.clipboard.dirty = false
		return
	}
	if !sdl.HasClipboardText() { return }
	data := sdl.GetClipboardText()
	if data == nil { return }
	text, _ := strings.clone_from_cstring(cstring(data))
	if text != g.clipboard.text {
		g.clipboard.text = text
	}
}

//* == Floating panels ==
//* Every floating panel gets a window of its own, so it can be moved
//* off the main window and onto another screen.

//* Keeps the windows of the floating panels in step with the GUI. New
//* panels get a window, panels that are gone have theirs hidden, and
//* every window is put where its panel is. The windows are kept, so
//* the renderers that belong to them stay valid.
Sync_Popups :: proc(w: ^Window, floats: []GUI.Float_Panel) {
	for len(w.popups) < len(floats) {
		f := floats[len(w.popups)]
		//* A window of its own, with no frame: the panel draws its
		//* own title bar, the way every other panel does.
		popup := sdl.CreateWindow(
			strings.clone_to_cstring(f.title, context.temp_allocator),
			i32(f.size.x),
			i32(f.size.y),
			sdl.WindowFlags{.BORDERLESS},
		)
		if popup == nil {
			log.warnf("could not create a window for '%s': %s", f.title, sdl.GetError())
			break
		}
		//* Text input has to be started for every window, or a text
		//* field in a floating panel never gets a character.
		if !sdl.StartTextInput(popup) {
			log.warnf("could not start text input: %s", sdl.GetError())
		}
		append(&w.popups, popup)
	}

	//* The GUI works in pixels and the window in points, so the loc
	//* of the panels are divided by the scale.
	s := scale(w^)
	for popup, i in w.popups {
		if i >= len(floats) {
			sdl.HideWindow(popup)
			continue
		}
		f := floats[i]
		sdl.SetWindowPosition(popup, i32(f.pos.x / s), i32(f.pos.y / s))
		sdl.SetWindowSize(popup, i32(f.size.x / s), i32(f.size.y / s))
		sdl.ShowWindow(popup)
	}

	clear(&w.popup_pos)
	for f in floats {
		append(&w.popup_pos, f.pos)
	}
}

//* The position of an event on the screen, in pixels.
event_global :: proc(w: Window, window_id: sdl.WindowID, pos: GUI.Vec2) -> GUI.Vec2 {
	if window_id == sdl.GetWindowID(w.handle) {
		origin := client_origin(w)
		return GUI.Vec2{origin.x + pos.x, origin.y + pos.y}
	}
	for popup, i in w.popups {
		if sdl.GetWindowID(popup) == window_id {
			if i < len(w.popup_pos) {
				//* converts sdl window coords to pixel coords
				place := w.popup_pos[i]
				return GUI.Vec2{place.x + pos.x, place.y + pos.y}
			}
			break
		}
	}
	return pos
}

//* Tells the GUI about the size of the drawable area when it is not
//* the size the GUI was told about last. The size is looked at every
//* time the events are polled: the platform can change it without
//* sending an event for it, and the event can come before the
//* platform has made the new size.
report_size :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	pw, ph := Pixel_Size(w^)
	if pw == w.pixel_w && ph == w.pixel_h { return }
	w.pixel_w = pw
	w.pixel_h = ph
	append(out, GUI.Resized_Event{size = {f32(pw), f32(ph)}})
}

//* Translates SDL events into GUI events. This is the only place that
//* knows about SDL; the core only ever sees GUI.Event.
Poll_Events :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	ev: sdl.Event

	report_size(w, out)

	for sdl.PollEvent(&ev) {
		#partial switch ev.type {
		case .MOUSE_MOTION:
			//* The mouse is placed in points, so it is scaled to the
			//* pixels the GUI works in. The scale is asked for every
			//* time: the window can be resized or moved to another
			//* display between two events.
			s := scale(w^)
			pos := GUI.Vec2{ev.motion.x * s, ev.motion.y * s}
			append(
				out,
				GUI.Mouse_Move_Event {
					pos = pos,
					global = event_global(w^, ev.motion.windowID, pos),
				},
			)
		case .MOUSE_BUTTON_DOWN:
			//* Keep the mouse with the window while the button is
			//* down, so a drag can leave the window.
			_ = sdl.CaptureMouse(true)
			s := scale(w^)
			pos := GUI.Vec2{ev.button.x * s, ev.button.y * s}
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
			s := scale(w^)
			pos := GUI.Vec2{ev.button.x * s, ev.button.y * s}
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
			//* NOTE: SDL_EVENT_TEXT_INPUT_EDITING (IME composition) is
			//* not in these bindings yet. The core already handles
			//* GUI.Ime_Editing_Event when it arrives.
		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
			//* The window has a new size. The size of the drawable
			//* area is asked for again, because the platform can send
			//* this event before the drawable area has been made.
			report_size(w, out)
		case .QUIT:
			append(out, GUI.Quit_Event{})
		}
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

//* SDL's keycodes for letters and digits are contiguous ASCII, so the
//* mapping is arithmetic. Everything else is explicit.
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
	}
	return .None
}
