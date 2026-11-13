package GUI

import "core:fmt"
import "core:log"
import virt "core:mem/virtual"

Error_Code :: enum {
	None,
	Out_Of_Memory,
	Backend_Invalid,
	Font_Failed,
	Invalid_Argument,
	Not_Found,
}

Error :: struct {
	code:    Error_Code,
	message: string,
	place:   string,
}

Error_To_String :: proc(e: Error) -> string {
	place := e.place
	if place == "" {place = "CalcUI"}
	return fmt.tprintf("CalcUI error [%v] at %s: %s", e.code, place, e.message)
}

//* Initializes a GUI, returning any failure instead of terminating.
Init_GUI_Checked :: proc(width, height: i32, backend: Backend) -> (^GUI, Error) {
	return Init_GUI_With_Atlas_Checked(width, height, backend, ATLAS_DEFAULT_SIZE)
}

//* Initializes a GUI with a custom atlas size.
Init_GUI_With_Atlas_Checked :: proc(
	width, height: i32,
	backend: Backend,
	atlas_size: int,
) -> (
	^GUI,
	Error,
) {
	log.info("Initializing GUI...")

	g := new(GUI)
	g^ = GUI{}
	if err := virt.arena_init_growing(&g.arena); err != nil {
		free(cast(rawptr)g)
		return nil, Error {
			code = .Out_Of_Memory,
			message = fmt.tprintf("the arena of the GUI could not be made: %v", err),
			place = "Init_GUI_With_Atlas_Checked",
		}
	}
	if err := virt.arena_init_growing(&g.frame_arena); err != nil {
		virt.arena_destroy(&g.arena)
		free(cast(rawptr)g)
		return nil, Error {
			code = .Out_Of_Memory,
			message = fmt.tprintf("the arena of the frames could not be made: %v", err),
			place = "Init_GUI_With_Atlas_Checked",
		}
	}

	Backend_Report(backend)

	g.backend = backend
	g.viewport = Rect {
		x = 0,
		y = 0,
		w = f32(width),
		h = f32(height),
	}
	g.scale = 1
	g.glyphs = make(map[Glyph_Key]Glyph_Entry)
	g.class_by_type = make(map[Widget_Type]Widget_Class_ID)
	g.class_by_name = make(map[string]Widget_Class_ID)
	g.atlas = atlas_make(atlas_size, atlas_size)
	g.atlas_texture = ATLAS_TEXTURE_ID
	g.target = &g.draw
	g.font_instances = make(map[Font_Instance_Key]Font_ID)
	g.default_style = Style {
		text = Text_Style{colour = RGBA(0.92, 0.94, 0.98, 1)},
	}
	init_text(g)
	g.root = New_Widget(g, .Panel, INVALID_WIDGET_ID, Widget_Opts{name = "root"})
	gui_make_tooltip(g)
	gui_alive_add(g)

	log.infof("Window extent: %d x %d", width, height)
	return g, Error{}
}