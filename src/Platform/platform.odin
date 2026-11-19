package Platform

import sdl "vendor:sdl3"
import GUI "../GUI"

clock_last: u64
clock_started: bool

Clock_Delta :: proc() -> f32 {
	now := sdl.GetPerformanceCounter()
	freq := sdl.GetPerformanceFrequency()
	if freq == 0 { return 0 }
	if !clock_started {
		clock_started = true
		clock_last = now
		return 0
	}
	dt := f32(f64(now - clock_last) / f64(freq))
	clock_last = now
	return dt
}

//* The SDL3 hooks of the shared application loop.
App_Platform :: proc(w: ^Window) -> GUI.App_Platform {
	return GUI.App_Platform {
		ctx            = w,
		clock          = platform_clock,
		sync           = platform_sync,
		poll           = platform_poll,
		wait           = platform_wait,
		sync_popups    = platform_sync_popups,
		popup_window   = platform_popup_window,
		set_cursor     = platform_set_cursor,
		sync_clipboard = platform_sync_clipboard,
	}
}

platform_clock :: proc(ctx: rawptr) -> f32 {
	return Clock_Delta()
}

platform_sync :: proc(ctx: rawptr, g: ^GUI.GUI) {
	if g == nil { return }
	s := Scale((cast(^Window) ctx)^)
	if g.scale != s { GUI.GUI_Set_Scale(g, s) }
}

platform_poll :: proc(ctx: rawptr, g: ^GUI.GUI) {
	w := cast(^Window) ctx
	Poll_Events(w, &g.events)
	g.window_rect = Global_Rect(w^)
}

platform_wait :: proc(ctx: rawptr, g: ^GUI.GUI, timeout_ms: i32) {
	Wait_Events(cast(^Window) ctx, &g.events, timeout_ms)
}

platform_sync_popups :: proc(ctx: rawptr, g: ^GUI.GUI, backend: GUI.Backend) {
	w := cast(^Window) ctx
	Sync_Popups(w, g.floats[:], backend.release_target, backend.ctx)
}

platform_popup_window :: proc(ctx: rawptr, index: int) -> rawptr {
	w := cast(^Window) ctx
	if index < 0 || index >= len(w.popups) { return nil }
	return cast(rawptr) w.popups[index].handle
}

platform_set_cursor :: proc(ctx: rawptr, g: ^GUI.GUI) {
	Set_Cursor(cast(^Window) ctx, g.cursor)
}

platform_sync_clipboard :: proc(ctx: rawptr, g: ^GUI.GUI) {
	Sync_Clipboard(g)
}
