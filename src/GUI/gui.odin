//* The life of a GUI: it is made, it is fed one frame at a time, and it
//* is given back. It knows nothing of the window or of the backend, and
//* the backend is made first.
package GUI

import "core:time"

import "core:log"
import "core:os"
import runa "./dependencies/Runa"
import virt "core:mem/virtual"

// The UI is retained mode: the widgets are kept, and the tree is a file
// that can be made by hand and parsed back.

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
// The style of a widget has two parts: the box around it and the text
// inside it. A theme holds the style of every kind of widget, so a look
// changes in one place - see theme.odin.

//* Creates the GUI and the root widget. The backend must already be
//* made: the GUI owns the one texture of the atlas. The width and the
//* height are in logical units; the scale says how many physical pixels
//* one of them is worth.
Init_GUI :: proc(width, height: i32, backend: Backend) -> ^GUI {
	return Init_GUI_With_Atlas(width, height, backend, ATLAS_DEFAULT_SIZE)
}

//* Creates the GUI with an atlas of a size of its own. The atlas holds
//* the glyphs and the pictures and takes sixteen bytes a pixel, so the
//* default of 2048 by 2048 is sixteen megabytes. A program that shows
//* a little text can ask for less.
Init_GUI_With_Atlas :: proc(width, height: i32, backend: Backend, atlas_size: int) -> ^GUI {
	log.info("Initializing GUI...")

	g := new(GUI)
	g^ = GUI{}
	if err := virt.arena_init_growing(&g.arena); err != nil {
		log.panicf("GUI arena init failed: %v", err)
	}
	if err := virt.arena_init_growing(&g.frame_arena); err != nil {
		log.panicf("GUI Frame arena init failed: %v", err)
	}

	g.backend = backend
	g.viewport = Rect{x = 0, y = 0, w = f32(width), h = f32(height)}
	g.scale = 1
	//* Every widget belongs to a class. A program that brings a widget
	//* of its own puts its class here.
	g.class_by_type = make(map[Widget_Type]Widget_Class_ID)
	g.class_by_name = make(map[string]Widget_Class_ID)
	//* The one texture of the whole UI. Every quad of every widget
	//* comes out of it, so a window is one draw call.
	g.atlas = atlas_make(atlas_size, atlas_size)
	g.atlas_texture = ATLAS_TEXTURE_ID
	g.target = &g.draw
	g.font_instances = make(map[Font_Instance_Key]Font_ID)
	//* The look every widget starts from, for the programs that bring
	//* no theme of their own.
	g.default_style = Style{
		text = Text_Style{
			colour = RGBA(0.92, 0.94, 0.98, 1),
		},
	}
	init_text(g)
	g.root = New_Widget(g, .Panel, INVALID_WIDGET_ID, Widget_Opts{name = "root"})

	log.infof("Window extent: %d x %d", width, height)
	return g
}

//* Gives the GUI back: the fonts, the theme and the atlas go with it,
//* and the texture of the atlas goes back to the backend.
Shutdown_GUI :: proc(g: ^GUI) {
	if g == nil { return }
	log.info("Shutting down GUI...")

	//* What the widgets own is given back: the text fields own their
	//* buffer, and the widgets that hold lists own their lists.
	for w in g.widgets {
		if w == nil { continue }
		//* The class of the widget is told that it goes away. A widget
		//* that was destroyed already has been told.
		if w.id != INVALID_WIDGET_ID {
			widget_notify_destroy(g, w.id, w)
		}
		widget_release_data(g, w)
	}

	font_destroy(g)
	theme_destroy(g.theme)
	atlas_destroy(g.atlas)
	if g.backend.destroy_texture != nil {
		g.backend.destroy_texture(g.backend.ctx, g.atlas_texture)
	}
	draw_list_destroy(&g.draw)
	for &f in g.floats {
		draw_list_destroy(&f.draw)
	}
	delete(g.floats)
	delete(g.popups)
	delete(g.widgets)
	delete(g.widget_generations)
	delete(g.free_widgets)
	delete(g.events)
	delete(g.upload_buf)
	delete(g.kinds)
	delete(g.classes)
	delete(g.signal_conns)
	if g.class_by_type != nil { delete(g.class_by_type) }
	if g.class_by_name != nil { delete(g.class_by_name) }
	delete(g.scene_constructors)
	delete(g.commands.list)
	if g.measure_cache != nil { delete(g.measure_cache) }
	virt.arena_destroy(&g.frame_arena)
	virt.arena_destroy(&g.arena)
	free(cast(rawptr) g)
}

//* One frame of UI work: measure, layout, build the draw list and upload
//* any new glyphs. The caller submits the list to the backend.
Frame :: proc(g: ^GUI) {
	virt.arena_free_all(&g.frame_arena)
	g.dt = frame_time(g)
	layout_pass(g)
	//* The grip under the pointer is looked up after the layout, so
	//* the edges it holds are the ones that are on the screen.
	update_resize_hover(g)
	build_draw_list(g)
	//* The atlas sends the parts that changed, not the whole thing.
	atlas_flush(g.atlas, g.backend, g.atlas_texture)
	atlas_next_frame(g.atlas)
	report_atlas_failures(g)
}

//* Says once that the atlas is full: a glyph that did not fit into it
//* is not drawn.
report_atlas_failures :: proc(g: ^GUI) {
	if g.atlas == nil {return}
	if g.atlas.exhausted == g.atlas_failures {return}
	g.atlas_failures = g.atlas.exhausted
	log.warnf(
		"the atlas is full: %d region(s) could not be put into it",
		g.atlas_failures,
	)
}

//* How long the last frame took, in seconds. The first frame counts as
//* nothing, so that a widget that counts down does not lose a second
//* at the start.
frame_time :: proc(g: ^GUI) -> f32 {
	now := time.time_to_unix_nano(time.now())
	if g.last_frame == 0 {
		g.last_frame = now
		return 0
	}
	dt := f32(now - g.last_frame) / 1e9
	g.last_frame = now
	//* A frame that took a long time is not worth counting: the program
	//* was asleep, not busy.
	if dt > 0.25 { return 0 }
	return dt
}

//* Sets up the shaping cache, which is what keeps repeated labels
//* cheap. Safe to call as often as the program likes.
init_text :: proc(g: ^GUI) {	if g.cache_ready { return }
	g.shape_cache = runa.cache_make()
	g.cache_ready = true
}

//* The shaping cache, or nil when it was never initialised. Runa
//* accepts a nil cache for one-shot shaping.
shape_cache :: proc(g: ^GUI) -> ^runa.Cache {
	return g.cache_ready ? &g.shape_cache : nil
}

//* Resizes the viewport, on a window resize event. The width and the
//* height are in logical units.
gui_resize :: proc(g: ^GUI, width, height: i32) {
	g.viewport = Rect{x = 0, y = 0, w = f32(width), h = f32(height)}
	invalidate_all(g, Dirty_Flags{.Arrange, .Hit})
	if g.backend.resize != nil {
		g.backend.resize(
			g.backend.ctx,
			i32(g.viewport.w * g.scale),
			i32(g.viewport.h * g.scale),
		)
	}
}

//* Sets the scale of the GUI: how many physical pixels one logical unit
//* is worth. It is 1.0 on a display that does not scale of its own.
//* The glyphs are rasterized again and the tree is measured and laid out
//* again, because everything that is measured changes with it.
GUI_Set_Scale :: proc(g: ^GUI, scale: f32) {
	if g == nil {return}
	if !(scale > 0) {scale = 1}
	if g.scale == scale {return}
	g.scale = scale
	font_invalidate(g)
	measure_cache_clear(g)
	invalidate_all(g, Dirty_Flags{.Arrange, .Hit})
}

//* The size of the drawable area in physical pixels.
gui_pixel_size :: proc(g: ^GUI) -> Vec2 {
	return Vec2 {
		x = g.viewport.w * g.scale,
		y = g.viewport.h * g.scale,
	}
}

// Loads a scene file: a tree of nodes, the kind of widget of every
// node, the anchors and the offsets, the styles and the signals. The
// widget of the first node is the root of the scene. An invalid widget
// is returned when the file cannot be read.
Load_UI :: proc(path: string, g: ^GUI) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	//* The text of the file lives in the arena of the GUI, so it goes
	//* away with the GUI.
	allocator := virt.arena_allocator(&g.arena)
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != nil {
		log.errorf("the scene %q could not be read: %v", path, err)
		return INVALID_WIDGET_ID
	}
	//* The loader keeps the strings of the widgets it makes in the
	//* arena of the GUI as well, so the text of the file is not needed
	//* after the scene is made.
	text := string(data)
	return scene_load(g, text)
}