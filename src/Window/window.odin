//* The window layer is the only part of the program that knows about
//* physical pixels. SDL gives the pointer, the size of the window and the
//* place of the window on the screen in points, and a point is the logical
//* unit the GUI works in; the drawable area is in pixels. The scale says
//* how many pixels one point is worth on the display the window is on.
package Window

import sdl "vendor:sdl3"
import "core:c"
import "core:log"
import "core:strings"
import GUI "../GUI"

Window :: struct {
	handle: ^sdl.Window,
	pixel_w: i32,
	pixel_h: i32,
	popups: [dynamic]^sdl.Window,
	popup_pos: [dynamic]GUI.Vec2,
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

Pixel_Size :: proc(w: Window) -> (i32, i32) {
	pw, ph: i32
	sdl.GetWindowSizeInPixels(w.handle, &pw, &ph)
	return pw, ph
}

Logical_Size :: proc(w: Window) -> (i32, i32) {
	tw, th: i32
	sdl.GetWindowSize(w.handle, &tw, &th)
	return tw, th
}

Scale :: proc(w: Window) -> f32 {
	pw, _ := Pixel_Size(w)
	tw, _ := Logical_Size(w)
	if pw <= 0 || tw <= 0 { return 1 }
	return f32(pw) / f32(tw)
}

Sync_Scale :: proc(g: ^GUI.GUI, w: Window) {
	if g == nil { return }
	s := Scale(w)
	if g.scale == s { return }
	GUI.GUI_Set_Scale(g, s)
}

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
	tw, th := Logical_Size(w)
	return GUI.Rect{x = origin.x, y = origin.y, w = f32(tw), h = f32(th)}
}

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

Sync_Clipboard :: proc(g: ^GUI.GUI) {
	if g == nil { return }
	if g.clipboard.dirty {
		text := strings.clone_to_cstring(GUI.Clipboard_Get(g), context.temp_allocator)
		_ = sdl.SetClipboardText(text)
		g.clipboard.dirty = false
		return
	}
	if !sdl.HasClipboardText() { return }
	data := sdl.GetClipboardText()
	if data == nil { return }
	text, _ := strings.clone_from_cstring(cstring(data))
	sdl.free(cast(rawptr)data)
	if text == GUI.Clipboard_Get(g) {
		if text != "" { delete(text) }
		return
	}
	GUI.Clipboard_Pulled(g, text)
	if text != "" { delete(text) }
}

Sync_Popups :: proc(w: ^Window, floats: []GUI.Float_Panel) {
	for len(w.popups) < len(floats) {
		f := floats[len(w.popups)]
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
		if !sdl.StartTextInput(popup) {
			log.warnf("could not start text input: %s", sdl.GetError())
		}
		append(&w.popups, popup)
	}

	for popup, i in w.popups {
		if i >= len(floats) {
			sdl.HideWindow(popup)
			continue
		}
		f := floats[i]
		sdl.SetWindowPosition(popup, i32(f.pos.x), i32(f.pos.y))
		sdl.SetWindowSize(popup, i32(f.size.x), i32(f.size.y))
		sdl.ShowWindow(popup)
	}

	clear(&w.popup_pos)
	for f in floats {
		append(&w.popup_pos, f.pos)
	}
}

event_global :: proc(w: Window, window_id: sdl.WindowID, pos: GUI.Vec2) -> GUI.Vec2 {
	if window_id == sdl.GetWindowID(w.handle) {
		origin := client_origin(w)
		return GUI.Vec2{origin.x + pos.x, origin.y + pos.y}
	}
	for popup, i in w.popups {
		if sdl.GetWindowID(popup) == window_id {
			if i < len(w.popup_pos) {
				place := w.popup_pos[i]
				return GUI.Vec2{place.x + pos.x, place.y + pos.y}
			}
			break
		}
	}
	return pos
}

report_size :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	pw, ph := Pixel_Size(w^)
	if pw == w.pixel_w && ph == w.pixel_h { return }
	w.pixel_w = pw
	w.pixel_h = ph
	tw, th := Logical_Size(w^)
	append(out, GUI.Resized_Event{size = {f32(tw), f32(th)}})
}

Poll_Events :: proc(w: ^Window, out: ^[dynamic]GUI.Event) {
	ev: sdl.Event

	report_size(w, out)

	for sdl.PollEvent(&ev) {
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
