//* Core UI functionality, blind to any window management, or to the backends and platform implementation.
package GUI

import "core:log"
import runa "./dependencies/Runa"
import virt "core:mem/virtual"

// Outline.
// This UI is retained-mode GUI.
// The UI data is similar to Godot engine's UI, saves to a file, and can be visually authored to that file.
// This makes it easy to author the UI and parse it. Widgets are all structs, and styles can be defined as a struct.

// UI scene file example:
/*
[ui format=1 name="main_menu"]

[widget id=1 type="Panel" name="Root"]
anchors = {0, 1, 1, 0}
offsets = {0, 0, 0, 0}
style = {bg=[30,30,30,255], border=[60,60,60,255], border_width=1}

[widget id=2 type="Label" name="Title", parent=1]
anchors = {0, 0.5, 0.3, 0.5}
offsets = {0, 0, 0, 0}
style = {text={colour=[255,255,255,255], size=32}}
text = "My Game"
*/
//
// The style of a widget has two parts: the box around it (its
// background, its border and its padding) and the text inside it (the
// typeface, the size, the colour of the ink and how the text is laid
// out). A theme holds the style of every kind of widget, so a look
// changes in one place - see theme.odin.

//* Creates the GUI context and the root widget. The backend must already
//* be created: texture 0 is the backend's 1x1 white texel.
init_gui :: proc(width, height: i32, backend: Backend) -> ^GUI {
	log.info("Initializing GUI...")

	g := new(GUI)
	g^ = GUI{}
	if err := virt.arena_init_growing(&g.arena); err != nil {
		log.panicf("GUI arena init failed: %v", err)
	}
	if err := virt.arena_init_growing(&g.frame_arena); err != nil {
		log.panicf("GUI frame arena init failed: %v", err)
	}

	g.backend = backend
	g.viewport = Rect{x = 0, y = 0, w = f32(width), h = f32(height)}
	g.white_texture = Texture_ID(0)
	g.next_texture = Texture_ID(1)
	g.target = &g.draw
	g.font_instances = make(map[Font_Instance_Key]Font_ID)
	//* The look every widget starts from: the GUI's own, for the apps
	//* that do not bring a theme.
	g.default_style = Style{
		text = Text_Style{
			colour = rgba(0.92, 0.94, 0.98, 1),
		},
	}
	init_text(g)
	g.root = widget(g, .Panel, INVALID_WIDGET_ID, Widget_Opts{name = "root"})

	log.infof("Window extent: %d x %d", width, height)
	return g
}

shutdown_gui :: proc(g: ^GUI) {
	if g == nil { return }
	log.info("Shutting down GUI...")

	//* Text fields own their buffer.
	for w in g.widgets {
		#partial switch d in w.data {
		case Text_Input_Data:
			delete(d.text)
		}
	}

	font_destroy(g)
	theme_destroy(g.theme)
	draw_list_destroy(&g.draw)
	for &f in g.floats {
		draw_list_destroy(&f.draw)
	}
	delete(g.floats)
	delete(g.widgets)
	delete(g.events)
	delete(g.upload_buf)
	virt.arena_destroy(&g.frame_arena)
	virt.arena_destroy(&g.arena)
	free(cast(rawptr) g)
}

//* One frame of UI work: measure, layout, build the draw list and upload
//* any new glyphs. The caller submits the list to the backend.
frame :: proc(g: ^GUI) {
	virt.arena_free_all(&g.frame_arena)
	layout_pass(g)
	//* The grip under the pointer is looked up after the layout, so
	//* the edges it holds are the ones that are on the screen.
	update_resize_hover(g)
	build_draw_list(g)
	font_flush(g)
}

//* Sets up the text stack: the shaping cache. Safe to call once per
//* GUI; the cache is what keeps repeated labels cheap.
init_text :: proc(g: ^GUI) {
	if g.cache_ready { return }
	g.shape_cache = runa.cache_make()
	g.cache_ready = true
}

//* The shaping cache, or nil when it was never initialised. Runa
//* accepts a nil cache for one-shot shaping.
shape_cache :: proc(g: ^GUI) -> ^runa.Cache {
	return g.cache_ready ? &g.shape_cache : nil
}

//* Resize the UI viewport (called on a window resize event).
gui_resize :: proc(g: ^GUI, width, height: i32) {
	g.viewport = Rect{x = 0, y = 0, w = f32(width), h = f32(height)}
	g.layout_dirty = true
}

// Loads the ui from file
load_ui :: proc(path: string, g: ^GUI) -> Widget_ID {
	// .. parse blocs, create widgets, link parent/children
	// .. resolve anchors/offsets/images into each widget
	return g.root
}
