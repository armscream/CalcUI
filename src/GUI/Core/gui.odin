//* The life of a GUI: it is made, it is fed one frame at a time, and it
//* is given back. It knows nothing of the window or of the backend, and
package Core

import "core:log"
import "core:os"
import runa "../dependencies/Runa"
import virt "core:mem/virtual"

Init_GUI :: proc(width, height: i32, backend: Backend) -> ^GUI {
	return Init_GUI_With_Atlas(width, height, backend, ATLAS_DEFAULT_SIZE)
}

//* The GUIs that are alive. The list is what makes a second call of
//* `Shutdown_GUI` harmless: the pointer of a GUI that was given back is
//* not in the list any more, so the memory it points at is never read
//* again. The toolkit is not made for more than one thread, and the list
//* is not made for more than one thread either.
gui_alive: [dynamic]rawptr

gui_alive_add :: proc(g: ^GUI) {
	append(&gui_alive, cast(rawptr) g)
}

gui_alive_take :: proc(g: ^GUI) -> bool {
	key := cast(rawptr) g
	for i in 0 ..< len(gui_alive) {
		if gui_alive[i] != key { continue }
		for j in i ..< len(gui_alive) - 1 {
			gui_alive[j] = gui_alive[j + 1]
		}
		resize_dynamic_array(&gui_alive, len(gui_alive) - 1)
		if len(gui_alive) == 0 {
			delete(gui_alive)
			gui_alive = nil
		}
		return true
	}
	return false
}

Init_GUI_With_Atlas :: proc(width, height: i32, backend: Backend, atlas_size: int) -> ^GUI {
	g, err := Init_GUI_With_Atlas_Checked(width, height, backend, atlas_size)
	if err.code != .None {
		log.panicf("%s", Error_To_String(err))
	}
	return g
}

Shutdown_GUI :: proc(g: ^GUI) {
	if g == nil { return }
	if !gui_alive_take(g) { return }
	g.shutdown = true
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
	undo_destroy(g)
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
	delete(g.animations)
	delete(g.animations_done)
	delete(g.update_scratch)
	delete(g.children_scratch)
	delete(g.float_scratch)
	delete(g.signal_scratch)
	delete(g.hit_scratch)
	delete(g.chain_scratch)
	delete(g.access_pending)
	delete(g.access_spare)
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

report_atlas_failures :: proc(g: ^GUI) {
	if g.atlas == nil {return}
	if g.atlas.exhausted == g.atlas_failures {return}
	g.atlas_failures = g.atlas.exhausted
	log.warnf(
		"the atlas is full: %d region(s) could not be put into it",
		g.atlas_failures,
	)
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

