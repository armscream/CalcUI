package main

import "core:log"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import Backend "../Backend"
import GUI "../GUI"
import plat "../Window"

//* The font is compiled into the program, so it is found wherever the
//* program is started from. A font path on the command line replaces
//* it.
FONT_NAME :: "Roboto-Regular"
FONT_DATA :: #load("../../assets/fonts/Roboto-Regular.ttf")
BODY_SIZE :: 16
TITLE_SIZE :: 28

/*
cd C:\Users\czvan\Syncthing\Programming\Odin\Practice\calcui

# fastest: build and run in one step
C:\Odin\odin.exe run src\Main

# or build once, then run the exe
C:\Odin\odin.exe build src\Main -out:CalcUI.exe
.\CalcUI.exe
*/

//* Loads the font: the one compiled into the program, or the file at
//* `path` when one was named on the command line. It is a family: the
//* size belongs to the widget that uses it.
load_family :: proc(g: ^GUI.GUI, path: string) -> GUI.Font_Family_ID {
	if path == "" {
		return GUI.font_family_add(g, FONT_NAME, FONT_DATA)
	}
	return GUI.font_family_load(g, path)
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	//* --gpu selects the SDL3 GPU backend (Vulkan / D3D / Metal / GL).
	//* Anything else is the path of a font to use instead of the one
	//* that is compiled in.
	use_gpu := false
	font_path := ""
	for arg in os.args[1:] {
		if arg == "--gpu" {
			use_gpu = true
		} else if !strings.has_prefix(arg, "--") {
			font_path = arg
		}
	}

	if !plat.init_sdl() {
		log.panicf("SDL init failed: %s", sdl.GetError())
	}
	defer sdl.Quit()

	window, ok := plat.create_window(900, 620, "CalcUI")
	if !ok {
		log.panic("window creation failed")
	}
	defer plat.destroy_window(window)

	pw, ph := plat.pixel_size(window)

	renderer_state := Backend.Renderer_State{}
	gpu_state := Backend.GPU_State{}

	backend: GUI.Backend
	if use_gpu {
		log.info("backend: SDL3 GPU")
		backend = GUI.Backend{
			ctx = cast(rawptr)&gpu_state,
			create = Backend.gpu_create,
			destroy = Backend.gpu_destroy,
			resize = Backend.gpu_resize,
			upload_texture = Backend.gpu_upload_texture,
			submit = Backend.gpu_submit,
			submit_target = Backend.gpu_submit_target,
		}
	} else {
		log.info("backend: SDL3 renderer")
		backend = GUI.Backend{
			ctx = cast(rawptr)&renderer_state,
			create = Backend.renderer_create,
			destroy = Backend.renderer_destroy,
			resize = Backend.renderer_resize,
			upload_texture = Backend.renderer_upload_texture,
			submit = Backend.renderer_submit,
			submit_target = Backend.renderer_submit_target,
		}
	}

	if !backend.create(backend.ctx, cast(rawptr)window.handle, pw, ph) {
		log.panic("backend creation failed")
	}
	defer backend.destroy(backend.ctx)

	g := GUI.init_gui(pw, ph, backend)
	defer GUI.shutdown_gui(g)

	//* One typeface, any number of sizes: the file is parsed once and
	//* the glyph atlas is shared by every size of it.
	family := load_family(g, font_path)
	font_name := font_path
	if font_name == "" { font_name = FONT_NAME }
	if family == GUI.INVALID_FONT_FAMILY_ID {
		log.panicf("could not load the font '%s'", font_name)
	}
	//* The size the GUI's own text uses. A widget that names no size
	//* gets this one.
	g.default_font_size = BODY_SIZE
	//* Pre-rasterize the common glyphs so the first frame is complete.
	GUI.font_warmup(g, GUI.font_at(g, family, BODY_SIZE))
	GUI.font_warmup(g, GUI.font_at(g, family, TITLE_SIZE))

	// A basic UI test scene.
	GUI.init_demo(g, family)

	first_frame := true
	for !g.quit_requested {
		plat.poll_events(&window, &g.events)
		//* The GUI needs to know where the window is on the screen, so
		//* it can tell a panel that was dropped outside of it.
		g.window_rect = plat.global_rect(window)
		GUI.handle_events(g)
		GUI.frame(g)

		//* Every floating panel gets a window of its own.
		plat.sync_popups(&window, g.floats[:])
		//* The pointer changes over an edge that can be pulled.
		plat.set_cursor(&window, g.cursor)
		backend.submit(backend.ctx, &g.draw)
		for i in 0 ..< len(g.floats) {
			if i >= len(window.popups) { break }
			backend.submit_target(
				backend.ctx,
				&g.floats[i].draw,
				cast(rawptr)window.popups[i],
			)
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




