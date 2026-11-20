//* The helpers that make a headless GUI for the tests: a GUI with no
//* window, a backend that does nothing, the events of the mouse, and the
//* fonts the text tests need. The tests of every file of the package use
//* them, so they live on their own now that the tests are not one file.

package Tests

import GUI "../GUI"
import "core:testing"
import virt "core:mem/virtual"

test_gui :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := new(GUI.GUI)
	g^ = GUI.GUI{}
	if err := virt.arena_init_growing(&g.arena); err != nil {
		testing.fail_now(t, "arena init failed")
	}
	if err := virt.arena_init_growing(&g.frame_arena); err != nil {
		testing.fail_now(t, "Frame arena init failed")
	}
	g.viewport = GUI.Rect {
		x = 0,
		y = 0,
		w = 800,
		h = 600,
	}
	g.window_rect = g.viewport
	g.target = &g.draw
	g.scale = 1
	g.draw.scale = 1
	g.atlas = GUI.atlas_make(GUI.ATLAS_DEFAULT_SIZE, GUI.ATLAS_DEFAULT_SIZE)
	g.atlas_texture = GUI.ATLAS_TEXTURE_ID
	g.font_instances = make(map[GUI.Font_Instance_Key]GUI.Font_ID)
	g.glyphs = make(map[GUI.Glyph_Key]GUI.Glyph_Entry)
	g.class_by_type = make(map[GUI.Widget_Type]GUI.Widget_Class_ID)
	g.class_by_name = make(map[string]GUI.Widget_Class_ID)
	g.default_style = GUI.Style {
		text = GUI.Text_Style{colour = GUI.RGBA(0.92, 0.94, 0.98, 1)},
	}
	GUI.init_text(g)
	g.root = GUI.New_Widget(g, .Panel, GUI.INVALID_WIDGET_ID, GUI.Widget_Opts{name = "root"})
	return g
}

test_gui_destroy :: proc(g: ^GUI.GUI) {
	if g == nil {return}
	for w in g.widgets {
		if w == nil {continue}
		if w.id != GUI.INVALID_WIDGET_ID {
			GUI.widget_notify_destroy(g, w.id, w)
		}
		GUI.widget_release_data(g, w)
		free(w)
	}
	GUI.font_destroy(g)
	GUI.theme_destroy(g.theme)
	GUI.Style_Pool_Destroy(g)
	GUI.atlas_destroy(g.atlas)
	GUI.text_input_ime_destroy(g)
	GUI.undo_destroy(g)
	delete(g.clipboard.text)
	if g.backend.destroy_texture != nil {
		g.backend.destroy_texture(g.backend.ctx, g.atlas_texture)
	}
	GUI.draw_list_destroy(&g.draw)
	for &f in g.floats {
		GUI.draw_list_destroy(&f.draw)
	}
	delete(g.floats)
	delete(g.popups)
	delete(g.widgets)
	delete(g.widget_generations)
	delete(g.free_widgets)
	delete(g.events)
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
	if g.class_by_type != nil {delete(g.class_by_type)}
	if g.class_by_name != nil {delete(g.class_by_name)}
	delete(g.scene_constructors)
	delete(g.commands.list)
	GUI.measure_cache_destroy(g)
	virt.arena_destroy(&g.frame_arena)
	virt.arena_destroy(&g.arena)
	free(cast(rawptr)g)
}

//* A GUI with a font, so the text has a size to measure.
test_gui_with_font :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := test_gui(t)
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	return g
}

//* == The backend that does nothing ==

mock_create :: proc(ctx, window: rawptr, w, h: i32) -> bool {return true}
mock_destroy :: proc(ctx: rawptr) {}
mock_resize :: proc(ctx: rawptr, w, h: i32) -> bool {return true}
mock_upload_texture :: proc(ctx: rawptr, id: GUI.Texture_ID, pixels: []u8, w, h: i32) -> bool {
	if ctx != nil {
		m := cast(^Mock_State)ctx
		m.uploads += 1
	}
	return true
}
mock_upload_texture_regions :: proc(
	ctx: rawptr,
	id: GUI.Texture_ID,
	regions: []GUI.Texture_Upload,
) -> bool {
	if ctx != nil {
		m := cast(^Mock_State)ctx
		m.region_uploads += len(regions)
	}
	return true
}
mock_destroy_texture :: proc(ctx: rawptr, id: GUI.Texture_ID) {
	if ctx != nil {
		m := cast(^Mock_State)ctx
		m.destroyed += 1
	}
}
mock_submit :: proc(ctx: rawptr, dl: ^GUI.Draw_List) {}

mock_invalidate :: proc(ctx: rawptr) {
	if ctx != nil {
		m := cast(^Mock_State)ctx
		m.invalidations += 1
	}
}

mock_open_url :: proc(ctx: rawptr, url: string) -> bool {
	if ctx != nil {
		m := cast(^Mock_State)ctx
		m.opened = url
	}
	return true
}

Mock_State :: struct {
	uploads:        int,
	region_uploads: int,
	destroyed:      int,
	opened:         string,
	invalidations:  int,
}

mock_backend :: GUI.Backend {
	ctx                    = nil,
	create                 = mock_create,
	destroy                = mock_destroy,
	resize                 = mock_resize,
	upload_texture         = mock_upload_texture,
	upload_texture_regions = mock_upload_texture_regions,
	destroy_texture        = mock_destroy_texture,
	submit                 = mock_submit,
	invalidate             = mock_invalidate,
	open_url               = mock_open_url,
}

//* == The events of the mouse ==

mouse_down :: proc(pos: GUI.Vec2, clicks := 1) -> GUI.Mouse_Down_Event {
	return GUI.Mouse_Down_Event{pos = pos, global = pos, button = .Left, clicks = clicks}
}

mouse_up :: proc(pos: GUI.Vec2) -> GUI.Mouse_Up_Event {
	return GUI.Mouse_Up_Event{pos = pos, global = pos, button = .Left}
}

mouse_move :: proc(pos: GUI.Vec2) -> GUI.Mouse_Move_Event {
	return GUI.Mouse_Move_Event{pos = pos, global = pos}
}

//* A left, top, right, bottom offset, which most widgets of a test place.
test_offset :: proc(left, top, right, bottom: f32) -> GUI.Offset {
	return GUI.Offset{left = left, top = top, right = right, bottom = bottom}
}

//* Starts a draw list in the way the frame does, without a frame.
begin_draw :: proc(g: ^GUI.GUI) {
	g.target = &g.draw
	GUI.draw_list_clear(&g.draw, g.viewport)
}
