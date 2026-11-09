//* The life of a GUI: it is made, it is fed one frame at a time, and it
//* is given back. It knows nothing of the window or of the backend, and
//* the backend is made first.
package GUI

import "core:time"

import "core:log"
import "core:os"
import runa "./dependencies/Runa"
import virt "core:mem/virtual"

Init_GUI :: proc(width, height: i32, backend: Backend) -> ^GUI {
	return Init_GUI_With_Atlas(width, height, backend, ATLAS_DEFAULT_SIZE)
}

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
	g.glyphs = make(map[Glyph_Key]Glyph_Entry)
	g.class_by_type = make(map[Widget_Type]Widget_Class_ID)
	g.class_by_name = make(map[string]Widget_Class_ID)
	g.atlas = atlas_make(atlas_size, atlas_size)
	g.atlas_texture = ATLAS_TEXTURE_ID
	g.target = &g.draw
	g.font_instances = make(map[Font_Instance_Key]Font_ID)
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

Shutdown_GUI :: proc(g: ^GUI) {
	if g == nil { return }
	log.info("Shutting down GUI...")

	for w in g.widgets {
		if w == nil { continue }
		if w.id != INVALID_WIDGET_ID {
			widget_notify_destroy(g, w.id, w)
		}
		widget_release_data(g, w)
	}

	font_destroy(g)
	theme_destroy(g.theme)
	atlas_destroy(g.atlas)
	text_input_ime_destroy(g)
	delete(g.clipboard.text)
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

Frame :: proc(g: ^GUI) {
	virt.arena_free_all(&g.frame_arena)
	g.dt = frame_time(g)
	layout_pass(g)
	update_resize_hover(g)
	build_draw_list(g)
	atlas_flush(g.atlas, g.backend, g.atlas_texture)
	atlas_next_frame(g.atlas)
	report_atlas_failures(g)
}

report_atlas_failures :: proc(g: ^GUI) {
	if g.atlas == nil {return}
	if g.atlas.exhausted == g.atlas_failures {return}
	g.atlas_failures = g.atlas.exhausted
	log.warnf(
		"the atlas is full: %d region(s) could not be put into it",
		g.atlas_failures,
	)
}

frame_time :: proc(g: ^GUI) -> f32 {
	now := time.time_to_unix_nano(time.now())
	if g.last_frame == 0 {
		g.last_frame = now
		return 0
	}
	dt := f32(now - g.last_frame) / 1e9
	g.last_frame = now
	if dt > 0.25 { return 0 }
	return dt
}

init_text :: proc(g: ^GUI) {
	if g.cache_ready { return }
	g.shape_cache = runa.cache_make()
	g.cache_ready = true
}

shape_cache :: proc(g: ^GUI) -> ^runa.Cache {
	return g.cache_ready ? &g.shape_cache : nil
}

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

GUI_Set_Scale :: proc(g: ^GUI, scale: f32) {
	if g == nil {return}
	factor := scale
	if !(factor > 0) {factor = 1}
	if g.scale == factor {return}
	g.scale = factor
	font_invalidate(g)
	measure_cache_clear(g)
	invalidate_all(g, Dirty_Flags{.Arrange, .Hit})
}

gui_pixel_size :: proc(g: ^GUI) -> Vec2 {
	return Vec2 {
		x = g.viewport.w * g.scale,
		y = g.viewport.h * g.scale,
	}
}

Load_UI :: proc(path: string, g: ^GUI) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	allocator := virt.arena_allocator(&g.arena)
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != nil {
		log.errorf("the scene %q could not be read: %v", path, err)
		return INVALID_WIDGET_ID
	}
	text := string(data)
	return Scene_Load(g, text)
}