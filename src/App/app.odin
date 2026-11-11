//* The skeleton of an application: the window, backend, GUI,
//* font and the loop. A program outside this repository uses this package 
//* instead of copying the bootstrap from the examples.
//*   App.Run("CalcUI", 900, 600, setup, update)
//*   App.Run_With(App.Options{title = "CalcUI"}, setup, update)
package App

import "core:log"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import Backend "../Backend"
import GUI "../GUI"
import plat "../Window"

//* default font the toolkit ships with.
DEFAULT_FONT_DATA :: #load("../../assets/fonts/Roboto-Regular.ttf")

//* The family name of the built-in font.
DEFAULT_FONT_NAME :: "Roboto"

DEFAULT_FONT_SIZE :: 16

// App state
App :: struct {
	window: plat.Window,
	gui: ^GUI.GUI,
	backend: GUI.Backend,
	renderer_state: Backend.Renderer_State,
	gpu_state: Backend.GPU_State,
	family: GUI.Font_Family_ID,
}

//* The settings of an application: the window, backend and font.
Options :: struct {
	title: string,
	width, height: i32,
	use_gpu: bool,
	font_path: string,
	font_data: []u8,
	font_name: string,
	font_size: f32,
}

//* Runs an application with the given title and size. The setup function
//* puts the widgets in the tree, and the update function is called once a
//* frame. Gives false back when the application could not be started.
Run :: proc(
	title: string,
	width, height: i32,
	setup: proc(app: ^App),
	update: proc(app: ^App),
) -> bool {
	opts := Options {
		title = title,
		width = width,
		height = height,
	}
	return Run_With(opts, setup, update)
}

//* Runs an application with the given options. The setup function puts the
//* widgets in the tree, and the update function is called once a frame.
//* returns false when the application could not be started.
Run_With :: proc(
	opts: Options,
	setup: proc(app: ^App),
	update: proc(app: ^App),
) -> bool {
	logger := log.create_console_logger()
	context.logger = logger
	defer log.destroy_console_logger(logger)

	settings := opts
	with_defaults(&settings)
	parse_args(&settings)

	if !plat.Init_SDL() {
		log.errorf("SDL init failed: %s", sdl.GetError())
		return false
	}
	defer sdl.Quit()

	window, ok := plat.Create_Window(settings.width, settings.height, settings.title)
	if !ok {
		log.errorf("the window could not be made: %s", sdl.GetError())
		return false
	}

	app := new(App)
	app.window = window
	app.family = GUI.INVALID_FONT_FAMILY_ID

	started, backend_made := app_start(app, settings, setup)
	if started {
		app_run(app, update)
	}
	app_stop(app, backend_made)
	free(cast(rawptr) app)
	return started
}

Load_Font :: proc(app: ^App, path: string) -> GUI.Font_Family_ID {
	if app == nil || app.gui == nil { return GUI.INVALID_FONT_FAMILY_ID }
	return GUI.Font_Family_Load(app.gui, path)
}

Font :: proc(app: ^App, size: f32) -> GUI.Font_ID {
	if app == nil || app.gui == nil { return GUI.INVALID_FONT_ID }
	return GUI.Font_At(app.gui, app.family, size)
}

parse_args :: proc(opts: ^Options) {
	for arg in os.args[1:] {
		if arg == "--gpu" {
			opts.use_gpu = true
		} else if !strings.has_prefix(arg, "--") && opts.font_path == "" {
			opts.font_path = arg
		}
	}
}

with_defaults :: proc(opts: ^Options) {
	if opts.title == "" { opts.title = "CalcUI" }
	if opts.width <= 0 { opts.width = 800 }
	if opts.height <= 0 { opts.height = 600 }
	if opts.font_name == "" { opts.font_name = DEFAULT_FONT_NAME }
	if opts.font_size <= 0 { opts.font_size = DEFAULT_FONT_SIZE }
}

app_start :: proc(app: ^App, opts: Options, setup: proc(app: ^App)) -> (started, backend_made: bool) {
	pw, ph := plat.Pixel_Size(app.window)
	lw, lh := plat.Logical_Size(app.window)

	if opts.use_gpu {
		log.info("backend: SDL3 GPU")
		app.backend = GUI.Backend {
			ctx                    = cast(rawptr)&app.gpu_state,
			create                 = Backend.gpu_create,
			destroy                = Backend.gpu_destroy,
			resize                 = Backend.gpu_resize,
			upload_texture         = Backend.gpu_upload_texture,
			upload_texture_regions = Backend.gpu_upload_texture_regions,
			destroy_texture        = Backend.gpu_destroy_texture,
			submit                 = Backend.gpu_submit,
			submit_target          = Backend.gpu_submit_target,
			open_url               = Backend.open_url,
			supports_shapes        = true,
		}
	} else {
		log.info("backend: SDL3 renderer")
		app.backend = GUI.Backend {
			ctx                    = cast(rawptr)&app.renderer_state,
			create                 = Backend.renderer_create,
			destroy                = Backend.renderer_destroy,
			resize                 = Backend.renderer_resize,
			upload_texture         = Backend.renderer_upload_texture,
			upload_texture_regions = Backend.renderer_upload_texture_regions,
			destroy_texture        = Backend.renderer_destroy_texture,
			submit                 = Backend.renderer_submit,
			submit_target          = Backend.renderer_submit_target,
			open_url               = Backend.open_url,
		}
	}

	if !GUI.Backend_Create(app.backend, cast(rawptr) app.window.handle, pw, ph) {
		log.error("the backend could not be made")
		return false, false
	}
	backend_made = true

	app.gui = GUI.Init_GUI(lw, lh, app.backend)
	GUI.GUI_Set_Scale(app.gui, plat.Scale(app.window))
	GUI.Default_Theme_Use(app.gui, true)

	app.family = load_family(app.gui, opts)
	if app.family == GUI.INVALID_FONT_FAMILY_ID {
		log.error("the font could not be loaded")
		return false, true
	}
	app.gui.default_font_size = opts.font_size
	GUI.Font_Warmup(app.gui, GUI.Font_At(app.gui, app.family, opts.font_size))

	if setup != nil { setup(app) }
	return true, true
}

app_run :: proc(app: ^App, update: proc(app: ^App)) {
	first_frame := true
	for !app.gui.quit_requested {
		plat.Sync_Scale(app.gui, app.window)
		plat.Poll_Events(&app.window, &app.gui.events)
		app.gui.window_rect = plat.Global_Rect(app.window)
		if update != nil { update(app) }
		GUI.Handle_Events(app.gui)
		GUI.Frame(app.gui)

		plat.Sync_Popups(&app.window, app.gui.floats[:])
		plat.Set_Cursor(&app.window, app.gui.cursor)
		plat.Sync_Clipboard(app.gui)

		GUI.Backend_Submit(app.backend, &app.gui.draw)
		for i in 0 ..< len(app.gui.floats) {
			if i >= len(app.window.popups) { break }
			GUI.Backend_Submit_Target(
				app.backend,
				&app.gui.floats[i].draw,
				cast(rawptr) app.window.popups[i],
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

app_stop :: proc(app: ^App, backend_made: bool) {
	if app.gui != nil {
		GUI.Shutdown_GUI(app.gui)
		app.gui = nil
	}
	if backend_made {
		GUI.Backend_Destroy(app.backend)
	}
	plat.Destroy_Window(app.window)
}

load_family :: proc(g: ^GUI.GUI, opts: Options) -> GUI.Font_Family_ID {
	if opts.font_path != "" {
		return GUI.Font_Family_Load(g, opts.font_path)
	}
	data := opts.font_data
	if len(data) == 0 { data = DEFAULT_FONT_DATA }
	return GUI.Font_Family_Add(g, opts.font_name, data)
}
