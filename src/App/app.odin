//* The skeleton of an application: the window, backend, GUI,
//* font and the loop. A program outside this repository uses this package
//* instead of copying the bootstrap from the examples.
//*   App.Run("CalcUI", 900, 600, setup, update)
//*   App.Run_With(App.Options{title = "CalcUI"}, setup, update)
package App

import "core:log"
import "core:mem"
import sdl "vendor:sdl3"
import Backend "../Backend"
import GUI "../GUI"
import plat "../Platform"

DEFAULT_FONT_DATA :: #load("../../assets/fonts/Roboto-Regular.ttf")
DEFAULT_FONT_NAME :: GUI.DEFAULT_FONT_NAME
DEFAULT_FONT_SIZE :: GUI.DEFAULT_FONT_SIZE

App :: struct {
	window: plat.Window,
	gui: ^GUI.GUI,
	backend: GUI.Backend,
	renderer_state: Backend.Renderer_State,
	gpu_state: Backend.GPU_State,
	family: GUI.Font_Family_ID,
	update_fn: proc(app: ^App),
}

Backend_Choice :: GUI.Backend_Choice
Accessibility :: GUI.Accessibility
Options :: GUI.App_Options

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

	GUI.Access_Register()
	settings := opts
	GUI.App_Options_With_Defaults(&settings)
	GUI.App_Options_Parse_Args(&settings)

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


app_start :: proc(app: ^App, opts: Options, setup: proc(app: ^App)) -> (started, backend_made: bool) {
	pw, ph := app.window.pixel_w, app.window.pixel_h
	lw, lh := app.window.logical_w, app.window.logical_h

	backend, ok := Backend.create_backend(
		opts.backend,
		cast(rawptr) &app.gpu_state,
		cast(rawptr) &app.renderer_state,
		cast(rawptr) app.window.handle,
		pw,
		ph,
	)
	if !ok { return false, false }
	app.backend = backend
	backend_made = true

	app.gui = GUI.Init_GUI(lw, lh, app.backend)
	data := opts.font_data
	if len(data) == 0 { data = DEFAULT_FONT_DATA }
	app.family = GUI.App_Initialize(
		app.gui,
		opts,
		cast(rawptr) app.window.handle,
		plat.Scale(app.window),
		data,
	)
	if app.family == GUI.INVALID_FONT_FAMILY_ID { return false, true }

	if setup != nil { setup(app) }
	return true, true
}


app_frame :: proc(user: rawptr) {
	app := cast(^App) user
	GUI.Frame(app.gui)
	Backend.Stats.wake_timers = app.gui.wake_count
}

app_update :: proc(user: rawptr) {
	app := cast(^App) user
	if app.update_fn != nil { app.update_fn(app) }
}

app_run :: proc(app: ^App, update: proc(app: ^App)) {
	app.update_fn = update
	GUI.App_Run(
		app.gui,
		app.backend,
		plat.App_Platform(&app.window),
		app_frame,
		app_update,
		cast(rawptr) app,
	)
}

app_stop :: proc(app: ^App, backend_made: bool) {
	if app.gui != nil {
		Backend.sdl3_audio_shutdown(app.gui)
		GUI.Shutdown_GUI(app.gui)
		app.gui = nil
	}
	if backend_made {
		GUI.Backend_Destroy(app.backend)
	}
	plat.Destroy_Window(&app.window)
}
