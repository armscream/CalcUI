//* == Shared parts of the examples ==
//* The loop every example shares: a window, a GUI, the widgets the
//* setup function puts in it, and an update function called once a frame.
//*   common.Run("CalcUI", setup, update)

package common

import "core:log"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import Backend "../../src/Backend"
import GUI "../../src/GUI"
import plat "../../src/Window"

//* The font is compiled into the program, so it is found wherever the
//* program is started from. A font path on the command line replaces it.
FONT_NAME :: "Roboto-Regular"
FONT_DATA :: #load("../../assets/fonts/Roboto-Regular.ttf")

//* The size of the body text and of the titles.
BODY_SIZE :: 16
TITLE_SIZE :: 28

App :: struct {
	window: plat.Window,
	gui:    ^GUI.GUI,
	backend: GUI.Backend,
	//* The state of the backend in use. Which of the two is used
	//* depends on --gpu.
	renderer_state: Backend.Renderer_State,
	gpu_state:      Backend.GPU_State,
	family: GUI.Font_Family_ID,
}

//* The font of the example: the one that is compiled in, or the file at
//* `path` when one was named on the command line.
load_family :: proc(g: ^GUI.GUI, path: string) -> GUI.Font_Family_ID {
	if path == "" {
		return GUI.Font_Family_Add(g, FONT_NAME, FONT_DATA)
	}
	return GUI.Font_Family_Load(g, path)
}

//* Runs an example until the window is closed.
//
//*   --gpu   uses the SDL3 GPU backend instead of the SDL3 renderer.
Run :: proc(
	title: string,
	width: i32,
	height: i32,
	setup: proc(app: ^App),
	update: proc(app: ^App),
) {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	use_gpu := false
	font_path := ""
	for arg in os.args[1:] {
		if arg == "--gpu" {
			use_gpu = true
		} else if !strings.has_prefix(arg, "--") {
			font_path = arg
		}
	}

	if !plat.Init_SDL() {
		log.panicf("SDL init failed: %s", sdl.GetError())
	}
	defer sdl.Quit()

	window, ok := plat.Create_Window(width, height, title)
	if !ok {
		log.panic("window creation failed")
	}
	defer plat.Destroy_Window(window)

	pw, ph := plat.Pixel_Size(window)

	app := &App{
		window = window,
		family = GUI.INVALID_FONT_FAMILY_ID,
	}

	if use_gpu {
		log.info("backend: SDL3 GPU")
		app.backend = GUI.Backend{
			ctx = cast(rawptr)&app.gpu_state,
			create = Backend.gpu_create,
			destroy = Backend.gpu_destroy,
			resize = Backend.gpu_resize,
			upload_texture = Backend.gpu_upload_texture,
			upload_texture_regions = Backend.gpu_upload_texture_regions,
			destroy_texture = Backend.gpu_destroy_texture,
			submit = Backend.gpu_submit,
			submit_target = Backend.gpu_submit_target,
			supports_shapes = true,
		}
	} else {
		log.info("backend: SDL3 renderer")
		app.backend = GUI.Backend{
			ctx = cast(rawptr)&app.renderer_state,
			create = Backend.renderer_create,
			destroy = Backend.renderer_destroy,
			resize = Backend.renderer_resize,
			upload_texture = Backend.renderer_upload_texture,
			upload_texture_regions = Backend.renderer_upload_texture_regions,
			destroy_texture = Backend.renderer_destroy_texture,
			submit = Backend.renderer_submit,
			submit_target = Backend.renderer_submit_target,
		}
	}

	if !app.backend.create(app.backend.ctx, cast(rawptr)window.handle, pw, ph) {
		log.panic("backend creation failed")
	}
	defer app.backend.destroy(app.backend.ctx)

	app.gui = GUI.Init_GUI(pw, ph, app.backend)
	defer GUI.Shutdown_GUI(app.gui)

	app.family = load_family(app.gui, font_path)
	if app.family == GUI.INVALID_FONT_FAMILY_ID {
		log.panicf("could not load the font")
	}
	app.gui.default_font_size = BODY_SIZE
	//* Pre-rasterize the common glyphs, so the first frame is whole.
	GUI.Font_Warmup(app.gui, GUI.Font_At(app.gui, app.family, BODY_SIZE))
	GUI.Font_Warmup(app.gui, GUI.Font_At(app.gui, app.family, TITLE_SIZE))

	if setup != nil {setup(app)}

	first_frame := true
	for !app.gui.quit_requested {
		plat.Poll_Events(&app.window, &app.gui.events)
		app.gui.window_rect = plat.Global_Rect(app.window)
		if update != nil {update(app)}
		GUI.Handle_Events(app.gui)
		GUI.Frame(app.gui)

		//* Every floating panel gets a window of its own.
		plat.Sync_Popups(&app.window, app.gui.floats[:])
		//* The pointer changes over an edge that can be pulled.
		plat.Set_Cursor(&app.window, app.gui.cursor)
		plat.Sync_Clipboard(app.gui)

		app.backend.submit(app.backend.ctx, &app.gui.draw)
		for i in 0 ..< len(app.gui.floats) {
			if i >= len(app.window.popups) {break}
			app.backend.submit_target(
				app.backend.ctx,
				&app.gui.floats[i].draw,
				cast(rawptr)app.window.popups[i],
			)
		}

		if first_frame {
			log.infof(
				"First frame: %d draw commands, %d vertices",
				len(app.gui.draw.commands),
				len(app.gui.draw.vertices),
			)
			first_frame = false
		}
	}
}
