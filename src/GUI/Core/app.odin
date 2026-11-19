package Core

import "core:log"
import "core:os"
import "core:strings"

DEFAULT_FONT_NAME :: "Roboto"
DEFAULT_FONT_SIZE :: 16

Backend_Choice :: enum {
	Auto,
	GPU,
	Renderer,
}

Accessibility :: enum {
	Default,
	On,
	Off,
}

App_Options :: struct {
	title:         string,
	width, height: i32,
	backend:       Backend_Choice,
	font_path:     string,
	font_data:     []u8,
	font_name:     string,
	font_size:     f32,
	accessibility: Accessibility,
}

App_Options_With_Defaults :: proc(opts: ^App_Options) {
	if opts.title == "" { opts.title = "CalcUI" }
	if opts.width <= 0 { opts.width = 800 }
	if opts.height <= 0 { opts.height = 600 }
	if opts.font_name == "" { opts.font_name = DEFAULT_FONT_NAME }
	if opts.font_size <= 0 { opts.font_size = DEFAULT_FONT_SIZE }
	if opts.accessibility == .Default {
		opts.accessibility = Access_Available() ? .On : .Off
	}
}

App_Options_Parse_Args :: proc(opts: ^App_Options) {
	for arg in os.args[1:] {
		if arg == "--gpu" {
			opts.backend = .GPU
		} else if arg == "--renderer" {
			opts.backend = .Renderer
		} else if !strings.has_prefix(arg, "--") && opts.font_path == "" {
			opts.font_path = arg
		}
	}
}

//* The platform hooks the shared loop needs. A platform fills the ones it
//* has and leaves the rest nil.
App_Platform :: struct {
	ctx:            rawptr,
	clock:          proc(ctx: rawptr) -> f32,
	sync:           proc(ctx: rawptr, g: ^GUI),
	poll:           proc(ctx: rawptr, g: ^GUI),
	wait:           proc(ctx: rawptr, g: ^GUI, timeout_ms: i32),
	sync_popups:    proc(ctx: rawptr, g: ^GUI, backend: Backend),
	popup_window:   proc(ctx: rawptr, index: int) -> rawptr,
	set_cursor:     proc(ctx: rawptr, g: ^GUI),
	sync_clipboard: proc(ctx: rawptr, g: ^GUI),
}

//* Initializes the parts of a GUI that do not depend on the platform.
App_Initialize :: proc(
	g: ^GUI,
	opts: App_Options,
	window: rawptr,
	scale: f32,
	font_data: []u8,
) -> Font_Family_ID {
	if g == nil { return INVALID_FONT_FAMILY_ID }
	GUI_Set_Scale(g, scale)
	default_theme_use(g, true)

	if opts.accessibility == .On && Access_Available() {
		if !Access_Install(g, window) {
			log.warn("platform accessibility not available")
		}
	}

	family := INVALID_FONT_FAMILY_ID
	if opts.font_path != "" {
		family = Font_Family_Load(g, opts.font_path)
	} else {
		data := font_data
		family = Font_Family_Add(g, opts.font_name, data)
	}
	if family == INVALID_FONT_FAMILY_ID {
		log.error("the font could not be loaded")
		return family
	}
	g.default_font_size = opts.font_size
	Font_Warmup(g, Font_At(g, family, opts.font_size))
	return family
}

//* The shared event and frame loop. The platform handles the window and the
//* core handles the clock, the events and the frame scheduling.
App_Run :: proc(
	g: ^GUI,
	backend: Backend,
	platform: App_Platform,
	frame: proc(user: rawptr),
	update: proc(user: rawptr),
	user: rawptr,
) {
	if g == nil { return }
	if platform.clock != nil { _ = platform.clock(platform.ctx) }
	first_frame := true

	for !g.quit_requested {
		if platform.sync != nil { platform.sync(platform.ctx, g) }
		if platform.poll != nil { platform.poll(platform.ctx, g) }
		if platform.clock != nil { GUI_Tick(g, platform.clock(platform.ctx)) }

		input_pending := len(g.events) > 0
		Handle_Events(g)
		if g.quit_requested { break }
		Access_Apply_Actions(g)

		if !GUI_Needs_Frame(g) {
			if !input_pending && platform.wait != nil {
				platform.wait(platform.ctx, g, GUI_Next_Frame_Delay_MS(g))
			}
			continue
		}

		if update != nil { update(user) }
		if frame != nil { frame(user) }

		if platform.sync_popups != nil { platform.sync_popups(platform.ctx, g, backend) }
		for &f in g.floats { f.raise = false }
		if platform.set_cursor != nil { platform.set_cursor(platform.ctx, g) }
		if platform.sync_clipboard != nil { platform.sync_clipboard(platform.ctx, g) }

		Backend_Submit(backend, &g.draw)
		for i in 0 ..< len(g.floats) {
			window := platform.popup_window != nil ? platform.popup_window(platform.ctx, i) : nil
			if window == nil { break }
			Backend_Submit_Target(backend, &g.floats[i].draw, window)
		}

		if first_frame {
			log.infof(
				"First frame: %d draw commands, %d vertices",
				len(g.draw.commands),
				len(g.draw.vertices),
			)
			first_frame = false
		}
	}
}
