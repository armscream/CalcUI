//* The tests of the GUI in one file: the helpers that make a headless
//* GUI, and then the tests of every part of the toolkit: the
//* accessibility, the atlas, the contracts of the draw call, the
//* events, the fonts, the invalidation, the layout, the ownership,
//* the scale, the scenes, the styles, the text and the widgets.
package Tests

import GUI "../GUI"
import "core:testing"
import "core:os"
import runa "../GUI/dependencies/Runa"
import "core:mem"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import virt "core:mem/virtual"
import "core:strconv"

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
	}
	GUI.font_destroy(g)
	GUI.theme_destroy(g.theme)
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
	delete(g.upload_buf)
	delete(g.kinds)
	delete(g.classes)
	delete(g.signal_conns)
	if g.class_by_type != nil {delete(g.class_by_type)}
	if g.class_by_name != nil {delete(g.class_by_name)}
	delete(g.scene_constructors)
	delete(g.commands.list)
	if g.measure_cache != nil {delete(g.measure_cache)}
	virt.arena_destroy(&g.frame_arena)
	virt.arena_destroy(&g.arena)
	free(cast(rawptr)g)
}

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
	open_url               = mock_open_url,
}

mock_backend_with :: proc(state: ^Mock_State) -> GUI.Backend {
	b := mock_backend
	b.ctx = cast(rawptr)state
	return b
}

mouse_down :: proc(pos: GUI.Vec2, clicks := 1) -> GUI.Mouse_Down_Event {
	return GUI.Mouse_Down_Event{pos = pos, global = pos, button = .Left, clicks = clicks}
}

mouse_up :: proc(pos: GUI.Vec2) -> GUI.Mouse_Up_Event {
	return GUI.Mouse_Up_Event{pos = pos, global = pos, button = .Left}
}

mouse_move :: proc(pos: GUI.Vec2) -> GUI.Mouse_Move_Event {
	return GUI.Mouse_Move_Event{pos = pos, global = pos}
}

mouse_down_float :: proc(global, local: GUI.Vec2) -> GUI.Mouse_Down_Event {
	return GUI.Mouse_Down_Event{pos = local, global = global, button = .Left, clicks = 1}
}

mouse_move_float :: proc(global, local: GUI.Vec2) -> GUI.Mouse_Move_Event {
	return GUI.Mouse_Move_Event{pos = local, global = global}
}

mouse_up_float :: proc(global, local: GUI.Vec2) -> GUI.Mouse_Up_Event {
	return GUI.Mouse_Up_Event{pos = local, global = global, button = .Left}
}

//* Tests for the metadata that says what a widget is to whatever reads
//* the screen for a person who cannot see it: the role of the widget,
//* the name it is known by, the value it holds, the states it is in and
//* the widgets it is tied to.

//* The middle of a widget, where a pointer goes to click it.
centre_of :: proc(w: ^GUI.Widget) -> GUI.Vec2 {
	if w == nil {return {}}
	return GUI.Vec2{w.rect.x + w.rect.w * 0.5, w.rect.y + w.rect.h * 0.5}
}

//* == The accessibility of the widgets ==

access_test_node_changed: int = 0
access_test_focus_changed: int = 0
access_test_focused: GUI.Widget_ID = GUI.INVALID_WIDGET_ID

access_test_on_node_changed :: proc(ctx: rawptr, node: GUI.Access_Node) {
	access_test_node_changed += 1
}

access_test_on_focus_changed :: proc(ctx: rawptr, focused: GUI.Widget_ID) {
	access_test_focus_changed += 1
	access_test_focused = focused
}

access_test_gauge_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	return GUI.Vec2{100, 20}
}

@(test)
test_a_button_is_a_button_named_by_its_text :: proc(t: ^testing.T) {
	g := test_gui(t)

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "save", text = "Save"})
	info := GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, info.role, .Button)
	testing.expect_value(t, info.name, "Save")

	label := GUI.New_Widget(g, .Label, g.root, GUI.Widget_Opts{name = "caption", text = "Amount"})
	info = GUI.Widget_Access_Info(g, label)
	testing.expect_value(t, info.role, .Label)
	testing.expect_value(t, info.name, "Amount")

	test_gui_destroy(g)
}

@(test)
test_a_widget_without_text_is_named_by_its_name :: proc(t: ^testing.T) {
	g := test_gui(t)

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "save"})
	info := GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, info.name, "save")

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "side"})
	info = GUI.Widget_Access_Info(g, panel)
	testing.expect_value(t, info.name, "side")

	test_gui_destroy(g)
}

@(test)
test_a_widget_holds_the_value_it_has :: proc(t: ^testing.T) {
	g := test_gui(t)

	field := GUI.New_Widget(g, .TextBox, g.root, GUI.Widget_Opts{name = "field", text = "hello"})
	info := GUI.Widget_Access_Info(g, field)
	testing.expect_value(t, info.role, .Text_Input)
	testing.expect_value(t, info.value.text, "hello")

	slider := GUI.Make_H_Slider(
		g,
		g.root,
		GUI.Slider_Opts{
			Base_Opts = GUI.Base_Opts{name = "slider"},
			value = 25,
			min = 0,
			max = 100,
		},
	)
	info = GUI.Widget_Access_Info(g, slider)
	testing.expect_value(t, info.role, .Slider)
	testing.expect_value(t, info.value.number, 25.0)
	testing.expect_value(t, info.value.min, 0.0)
	testing.expect_value(t, info.value.max, 100.0)
	testing.expect_value(t, info.value.step, 1.0)

	box := GUI.Make_Check_Box(
		g,
		g.root,
		GUI.Check_Box_Opts{Base_Opts = GUI.Base_Opts{name = "box"}, text = "Enable"},
	)
	info = GUI.Widget_Access_Info(g, box)
	testing.expect_value(t, info.role, .Check_Box)
	testing.expect_value(t, info.name, "Enable")
	testing.expect_value(t, info.value.text, "off")

	test_gui_destroy(g)
}

@(test)
test_the_program_can_say_what_a_widget_is :: proc(t: ^testing.T) {
	g := test_gui(t)

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "save", text = "Save"})
	GUI.Widget_Set_Access_Name(g, button, "Save the file")
	GUI.Widget_Set_Access_Description(g, button, "Writes the file to disk")
	GUI.Widget_Set_Access_Role(g, button, .Toggle_Button)
	GUI.Widget_Set_Access_Value(g, button, GUI.Access_Value{text = "saved"})

	info := GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, info.role, .Toggle_Button)
	testing.expect_value(t, info.name, "Save the file")
	testing.expect_value(t, info.description, "Writes the file to disk")
	testing.expect_value(t, info.value.text, "saved")

	heading := GUI.New_Widget(
		g,
		.Label,
		g.root,
		GUI.Widget_Opts {
			name = "caption",
			text = "Amount",
			access_role = .Heading,
			access_name = "The amount",
			access_description = "How much there is",
		},
	)
	info = GUI.Widget_Access_Info(g, heading)
	testing.expect_value(t, info.role, .Heading)
	testing.expect_value(t, info.name, "The amount")
	testing.expect_value(t, info.description, "How much there is")

	//* A role of .None takes the role of the program away, and the
	//* widget is what its kind is again.
	GUI.Widget_Set_Access_Role(g, button, .None)
	info = GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, info.role, .Button)

	test_gui_destroy(g)
}

@(test)
test_a_widget_says_the_state_it_is_in :: proc(t: ^testing.T) {
	g := test_gui(t)

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "save", text = "Save"})
	info := GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, .Disabled in info.states, false)
	testing.expect_value(t, .Hidden in info.states, false)
	testing.expect_value(t, .Focused in info.states, false)

	GUI.Widget_Set_Enabled(g, button, false)
	info = GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, .Disabled in info.states, true)

	GUI.Widget_Set_Visible(g, button, false)
	info = GUI.Widget_Access_Info(g, button)
	testing.expect_value(t, .Hidden in info.states, true)

	other := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "other", text = "Other"})
	testing.expect_value(t, GUI.Focus_Set(g, other), true)
	info = GUI.Widget_Access_Info(g, other)
	testing.expect_value(t, .Focused in info.states, true)

	GUI.Widget_Set_Access_State(g, other, .Selected, true)
	info = GUI.Widget_Access_Info(g, other)
	testing.expect_value(t, .Selected in info.states, true)

	test_gui_destroy(g)
}

@(test)
test_two_widgets_can_be_tied_to_each_other :: proc(t: ^testing.T) {
	g := test_gui(t)

	label := GUI.New_Widget(g, .Label, g.root, GUI.Widget_Opts{name = "caption", text = "Name"})
	field := GUI.New_Widget(g, .TextBox, g.root, GUI.Widget_Opts{name = "field"})

	GUI.Widget_Set_Access_Relation(g, field, .Labelled_By, label)
	info := GUI.Widget_Access_Info(g, field)
	testing.expect_value(t, info.relation_count, 1)
	testing.expect_value(t, info.relations[0].kind, .Labelled_By)
	testing.expect_value(t, info.relations[0].target, label)

	GUI.Widget_Clear_Access_Relation(g, field, .Labelled_By, label)
	info = GUI.Widget_Access_Info(g, field)
	testing.expect_value(t, info.relation_count, 0)

	test_gui_destroy(g)
}

@(test)
test_the_tree_is_gathered_for_the_platform :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	child := GUI.New_Widget(g, .Button, panel, GUI.Widget_Opts{name = "child", text = "Child"})
	hidden := GUI.New_Widget(g, .Button, panel, GUI.Widget_Opts{name = "hidden", text = "Hidden"})
	GUI.Widget_Set_Visible(g, hidden, false)
	GUI.layout_pass(g)

	nodes: [dynamic]GUI.Access_Node
	defer delete(nodes)
	GUI.Access_Collect(g, &nodes)

	testing.expect_value(t, len(nodes), 3)
	testing.expect_value(t, nodes[0].id, g.root)
	testing.expect_value(t, nodes[0].depth, 0)
	testing.expect_value(t, nodes[1].id, panel)
	testing.expect_value(t, nodes[1].parent, g.root)
	testing.expect_value(t, nodes[1].depth, 1)
	testing.expect_value(t, nodes[2].id, child)
	testing.expect_value(t, nodes[2].parent, panel)
	testing.expect_value(t, nodes[2].depth, 2)
	testing.expect_value(t, nodes[2].name, "Child")

	test_gui_destroy(g)
}

@(test)
test_the_platform_is_told_what_changed :: proc(t: ^testing.T) {
	g := test_gui(t)
	access_test_node_changed = 0
	access_test_focus_changed = 0
	access_test_focused = GUI.INVALID_WIDGET_ID

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "save", text = "Save"})

	GUI.GUI_Set_Access_Bridge(
		g,
		GUI.Access_Bridge {
			node_changed = access_test_on_node_changed,
			focus_changed = access_test_on_focus_changed,
		},
	)
	epoch := GUI.GUI_Access_Epoch(g)

	GUI.Widget_Set_Access_Name(g, button, "Save the file")
	testing.expect_value(t, access_test_node_changed, 1)
	testing.expect_value(t, GUI.GUI_Access_Epoch(g) > epoch, true)

	epoch = GUI.GUI_Access_Epoch(g)
	testing.expect_value(t, GUI.Focus_Set(g, button), true)
	testing.expect_value(t, access_test_focus_changed, 1)
	testing.expect_value(t, access_test_focused, button)
	testing.expect_value(t, GUI.GUI_Access_Epoch(g) > epoch, true)

	test_gui_destroy(g)
}

@(test)
test_a_widget_of_a_class_of_its_own_has_a_role :: proc(t: ^testing.T) {
	g := test_gui(t)

	class := GUI.Widget_Register_Class(
		g,
		GUI.Widget_Class_Desc {
			name = "Gauge",
			access_role = .Custom,
			kind = GUI.Widget_Kind{measure = access_test_gauge_measure},
		},
	)
	gauge := GUI.Make_Custom_Widget(g, g.root, class, GUI.Base_Opts{name = "gauge"})

	info := GUI.Widget_Access_Info(g, gauge)
	testing.expect_value(t, info.role, .Custom)
	testing.expect_value(t, info.name, "gauge")

	test_gui_destroy(g)
}

//* Tests for the UI atlas: the space it hands out, what it throws out
//* when it is full, and how the regions get to the backend.

//* == The space ==

@(test)
test_atlas_hands_out_space_that_does_not_overlap :: proc(t: ^testing.T) {
	a := GUI.atlas_make(256, 256)

	r1 := GUI.atlas_alloc(a, 32, 32, true)
	r2 := GUI.atlas_alloc(a, 32, 32, true)
	r3 := GUI.atlas_alloc(a, 64, 16, true)

	testing.expect_value(t, r1.id >= 0, true)
	testing.expect_value(t, r2.id >= 0, true)
	testing.expect_value(t, r3.id >= 0, true)

	//* None of them is on top of another.
	testing.expect_value(t, atlas_overlaps(r1, r2), false)
	testing.expect_value(t, atlas_overlaps(r1, r3), false)
	testing.expect_value(t, atlas_overlaps(r2, r3), false)

	//* And all of them are inside the atlas.
	regions := [3]GUI.Atlas_Region{r1, r2, r3}
	for r in regions {
		testing.expect_value(t, r.x >= 0 && r.y >= 0, true)
		testing.expect_value(t, r.x + r.w <= 256, true)
		testing.expect_value(t, r.y + r.h <= 256, true)
	}

	GUI.atlas_destroy(a)
}

//* True when two regions share a pixel.
atlas_overlaps :: proc(a, b: GUI.Atlas_Region) -> bool {
	return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

@(test)
test_atlas_reserves_the_white_texel :: proc(t: ^testing.T) {
	a := GUI.atlas_make(256, 256)

	//* The white texel is at the top left, and it is white.
	testing.expect_value(t, a.white.x, 0)
	testing.expect_value(t, a.white.y, 0)
	testing.expect_value(t, a.white.w, GUI.ATLAS_WHITE_SIZE)
	testing.expect_value(t, a.white.h, GUI.ATLAS_WHITE_SIZE)
	testing.expect_value(t, a.pixels[3], 255)

	//* A region that is handed out does not sit on top of it.
	r := GUI.atlas_alloc(a, 16, 16, true)
	testing.expect_value(t, atlas_overlaps(a.white, r), false)

	GUI.atlas_destroy(a)
}

@(test)
test_atlas_uv_points_at_the_region :: proc(t: ^testing.T) {
	a := GUI.atlas_make(256, 256)

	r := GUI.atlas_alloc(a, 32, 16, true)
	testing.expect_value(t, r.uv[0], f32(r.x) / 256.0)
	testing.expect_value(t, r.uv[1], f32(r.y) / 256.0)
	testing.expect_value(t, r.uv[2], f32(r.x + r.w) / 256.0)
	testing.expect_value(t, r.uv[3], f32(r.y + r.h) / 256.0)

	GUI.atlas_destroy(a)
}

@(test)
test_atlas_throws_out_the_oldest_region_when_it_is_full :: proc(t: ^testing.T) {
	//* A small atlas, so that it fills up quickly. The white texel
	//* takes the first four rows of it.
	a := GUI.atlas_make(64, 64)

	//* A pinned region: it never goes.
	pinned := GUI.atlas_alloc(a, 32, 32, true)

	//* An unpinned one. It is the oldest, so it is the first to go.
	old := GUI.atlas_alloc(a, 32, 32, false)
	testing.expect_value(t, pinned.id >= 0, true)
	testing.expect_value(t, old.id >= 0, true)

	//* The atlas is full for this size now, so the oldest region that
	//* is not pinned is thrown out to make room.
	fresh := GUI.atlas_alloc(a, 32, 32, false)
	testing.expect_value(t, fresh.id >= 0, true)

	//* The pinned one is still there, and the oldest is not.
	testing.expect_value(t, GUI.atlas_region_valid(a, pinned), true)
	testing.expect_value(t, GUI.atlas_region_valid(a, old), false)

	//* The space of the old region is used again.
	testing.expect_value(t, fresh.x, old.x)
	testing.expect_value(t, fresh.y, old.y)

	GUI.atlas_destroy(a)
}

@(test)
test_atlas_gives_the_space_of_a_freed_region_back :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	r := GUI.atlas_alloc(a, 32, 32, false)
	GUI.atlas_free(a, r)
	testing.expect_value(t, GUI.atlas_region_valid(a, r), false)

	//* The space can be used again: the new region sits where the old
	//* one was.
	again := GUI.atlas_alloc(a, 32, 32, false)
	testing.expect_value(t, again.id >= 0, true)
	testing.expect_value(t, again.x, r.x)
	testing.expect_value(t, again.y, r.y)

	GUI.atlas_destroy(a)
}

//* == Writing ==

@(test)
test_atlas_writes_the_pixels_into_the_region :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	r := GUI.atlas_alloc(a, 2, 2, true)
	pixels := [16]u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	GUI.atlas_write(a, r, pixels[:])

	//* The pixels are in the mirror of the atlas, at the place of the
	//* region. The rows of the atlas are as wide as the atlas itself.
	base := r.y * 64 * 4 + r.x * 4
	testing.expect_value(t, a.pixels[base + 0], 1)
	testing.expect_value(t, a.pixels[base + 3], 4)
	testing.expect_value(t, a.pixels[base + 4], 5)
	testing.expect_value(t, a.pixels[base + 64 * 4 + 0], 9)
	testing.expect_value(t, a.pixels[base + 64 * 4 + 4 + 3], 16)

	GUI.atlas_destroy(a)
}

@(test)
test_atlas_expands_the_coverage_into_white :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	r := GUI.atlas_alloc(a, 2, 1, true)
	coverage := [2]u8{0, 255}
	GUI.atlas_write_coverage(a, r, coverage[:])

	base := r.y * 64 * 4 + r.x * 4
	//* The colour is white and the alpha is the coverage.
	testing.expect_value(t, a.pixels[base + 0], 255)
	testing.expect_value(t, a.pixels[base + 1], 255)
	testing.expect_value(t, a.pixels[base + 2], 255)
	testing.expect_value(t, a.pixels[base + 3], 0)
	testing.expect_value(t, a.pixels[base + 7], 255)

	GUI.atlas_destroy(a)
}
//* == Uploading ==

@(test)
test_atlas_uploads_the_whole_texture_the_first_time :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)
	state := new(Mock_State)
	backend := mock_backend_with(state)

	GUI.atlas_flush(a, backend, GUI.Texture_ID(0))

	//* The first upload makes the texture, so it is the whole atlas.
	testing.expect_value(t, state.uploads, 1)
	testing.expect_value(t, state.region_uploads, 0)

	//* After that only the parts that changed go up.
	r := GUI.atlas_alloc(a, 8, 8, true)
	pixels := make([]u8, 8 * 8 * 4)
	defer delete(pixels)
	GUI.atlas_write(a, r, pixels)
	GUI.atlas_flush(a, backend, GUI.Texture_ID(0))

	testing.expect_value(t, state.uploads, 1)
	testing.expect_value(t, state.region_uploads, 1)

	free(state)
	GUI.atlas_destroy(a)
}

//* The rules the toolkit keeps to, written down as code: the atlas and
//* its limits, the texture that names a region, the clip of the draw
//* list, the order of the drawing, the life of a resource and the life
//* of a frame. The rules themselves are in docs/contracts.md.

//* == The tests of the contracts ==

//* == The atlas ==

@(test)
test_the_atlas_says_when_it_is_full :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	//* The atlas can hold this many regions of this size.
	live := 0
	for {
		r := GUI.atlas_alloc(a, 16, 16, true)
		if r.id < 0 { break }
		live += 1
		if live > 100 { break }
	}

	//* The atlas is full now, and it says so.
	testing.expect_value(t, live > 0, true)
	testing.expect_value(t, a.exhausted > 0, true)

	//* A pinned region that does not fit is not given out.
	testing.expect_value(t, GUI.atlas_alloc(a, 16, 16, true).id, -1)

	GUI.atlas_destroy(a)
}

@(test)
test_an_unpinned_region_makes_room_for_a_pinned_one :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	//* Fill the atlas with regions that can be thrown out. An unpinned
	//* region never fails: the atlas throws one out to make room.
	for i in 0 ..< 64 {
		GUI.atlas_alloc(a, 16, 16, false)
	}

	//* A pinned region does not fit, so the atlas throws one of the
	//* unpinned ones out to make room.
	pinned := GUI.atlas_alloc(a, 16, 16, true)
	testing.expect_value(t, pinned.id >= 0, true)
	testing.expect_value(t, GUI.atlas_region_valid(a, pinned), true)

	GUI.atlas_destroy(a)
}

@(test)
test_the_oldest_region_is_thrown_out_first :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	old := GUI.atlas_alloc(a, 32, 32, false)
	GUI.atlas_next_frame(a)
	other := GUI.atlas_alloc(a, 32, 32, false)
	GUI.atlas_next_frame(a)

	//* The atlas is full for this size, so the oldest one goes.
	fresh := GUI.atlas_alloc(a, 32, 32, false)
	testing.expect_value(t, fresh.id >= 0, true)
	testing.expect_value(t, GUI.atlas_region_valid(a, old), false)
	testing.expect_value(t, GUI.atlas_region_valid(a, other), true)

	GUI.atlas_destroy(a)
}

@(test)
test_a_region_that_is_used_is_not_thrown_out :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	old := GUI.atlas_alloc(a, 32, 32, false)
	GUI.atlas_next_frame(a)
	other := GUI.atlas_alloc(a, 32, 32, false)
	GUI.atlas_next_frame(a)

	//* The older region is on the screen, so it is the last one to be
	//* thrown out.
	GUI.atlas_touch(a, old)

	fresh := GUI.atlas_alloc(a, 32, 32, false)
	testing.expect_value(t, fresh.id >= 0, true)
	testing.expect_value(t, GUI.atlas_region_valid(a, old), true)
	testing.expect_value(t, GUI.atlas_region_valid(a, other), false)

	GUI.atlas_destroy(a)
}

//* == The texture that names a region ==

@(test)
test_a_texture_that_was_thrown_out_names_nothing :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	pixels := make([]u8, 16 * 16 * 4)
	defer delete(pixels)
	for i in 0 ..< len(pixels) { pixels[i] = 255 }

	texture := GUI.texture_from_pixels(g, pixels, 16, 16)
	testing.expect_value(t, GUI.atlas_region_valid(g.atlas, texture.region), true)

	//* Fill the atlas, so that the picture is thrown out. The atlas
	//* holds a thousand of these, so a few thousand of them fill it.
	for i in 0 ..< 2048 {
		GUI.atlas_alloc(g.atlas, 64, 64, false)
	}

	//* The picture was thrown out, so it names nothing.
	testing.expect_value(t, GUI.atlas_region_valid(g.atlas, texture.region), false)

	//* And it is not drawn.
	before := len(g.draw.vertices)
	GUI.draw_texture(g, texture, GUI.Rect{x = 0, y = 0, w = 16, h = 16}, GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, len(g.draw.vertices), before)

	test_gui_destroy(g)
}

@(test)
test_a_texture_that_was_replaced_names_nothing :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	pixels := make([]u8, 16 * 16 * 4)
	defer delete(pixels)
	for i in 0 ..< len(pixels) { pixels[i] = 255 }

	texture := GUI.texture_from_pixels(g, pixels, 16, 16)
	region := texture.region

	//* The picture is given back, and the space is used again.
	GUI.texture_free(g, texture)

	testing.expect_value(t, GUI.atlas_region_valid(g.atlas, region), false)

	again := GUI.texture_from_pixels(g, pixels, 16, 16)
	testing.expect_value(t, GUI.atlas_region_valid(g.atlas, again.region), true)

	//* The old handle does not name the new picture.
	testing.expect_value(t, region.id == again.region.id, true)
	testing.expect_value(t, region.gen != again.region.gen, true)
	testing.expect_value(t, GUI.atlas_region_valid(g.atlas, region), false)

	test_gui_destroy(g)
}

@(test)
test_the_atlas_does_not_grow_for_ever :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)

	//* The same space is used again and again, so the table of the
	//* allocations does not grow.
	for i in 0 ..< 1000 {
		r := GUI.atlas_alloc(a, 16, 16, false)
		testing.expect_value(t, r.id >= 0, true)
		GUI.atlas_free(a, r)
	}
	testing.expect_value(t, len(a.allocs), 2)

	GUI.atlas_destroy(a)
}

//* == The clip ==

@(test)
test_a_quad_is_cut_to_the_clip :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_quad(&dl, GUI.Rect{x = 50, y = 10, w = 100, h = 20}, {0, 0, 1, 1}, GUI.RGBA(1, 1, 1, 1), GUI.ATLAS_TEXTURE_ID)

	testing.expect_value(t, len(dl.vertices), 4)
	testing.expect_value(t, dl.vertices[0].pos[0], 50.0)
	testing.expect_value(t, dl.vertices[2].pos[0], 100.0)

	//* The texture moves with the cut.
	testing.expect_value(t, dl.vertices[0].uv[0], 0.0)
	testing.expect_value(t, dl.vertices[2].uv[0], 0.5)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_quad_that_is_cut_away_is_not_in_the_list :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_quad(&dl, GUI.Rect{x = 200, y = 10, w = 20, h = 20}, {0, 0, 1, 1}, GUI.RGBA(1, 1, 1, 1), GUI.ATLAS_TEXTURE_ID)

	//* It costs no vertices and no indices.
	testing.expect_value(t, len(dl.vertices), 0)
	testing.expect_value(t, len(dl.indices), 0)
	testing.expect_value(t, len(dl.commands), 0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_the_clips_are_turned_on_top_of_each_other :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_push_clip(&dl, GUI.Rect{x = 0, y = 0, w = 50, h = 50})
	GUI.draw_push_clip(&dl, GUI.Rect{x = 25, y = 0, w = 50, h = 50})

	//* The clip of the list is the intersection of the two.
	testing.expect_value(t, dl.current_clip.x, 25.0)
	testing.expect_value(t, dl.current_clip.w, 25.0)

	//* A quad that is inside the first clip but outside the second is
	//* cut away.
	GUI.draw_quad(&dl, GUI.Rect{x = 5, y = 5, w = 10, h = 10}, {0, 0, 1, 1}, GUI.RGBA(1, 1, 1, 1), GUI.ATLAS_TEXTURE_ID)
	testing.expect_value(t, len(dl.vertices), 0)

	GUI.draw_pop_clip(&dl)
	testing.expect_value(t, dl.current_clip.x, 0.0)
	testing.expect_value(t, dl.current_clip.w, 50.0)

	GUI.draw_pop_clip(&dl)
	testing.expect_value(t, dl.current_clip.x, 0.0)
	testing.expect_value(t, dl.current_clip.w, 100.0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_polygon_is_cut_to_the_clip :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	points := [][2]f32{{50, 10}, {150, 10}, {150, 30}, {50, 30}}
	GUI.draw_polygon(&dl, points, GUI.RGBA(1, 1, 1, 1), GUI.ATLAS_TEXTURE_ID)

	//* The polygon is cut, so it does not reach past the clip.
	testing.expect_value(t, len(dl.vertices) > 0, true)
	for v in dl.vertices {
		testing.expect_value(t, v.pos[0] <= 100.0, true)
	}

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_line_is_cut_to_the_clip :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_thick_line(&dl, {10, 10}, {200, 10}, 2, GUI.RGBA(1, 1, 1, 1), GUI.ATLAS_TEXTURE_ID)
	testing.expect_value(t, len(dl.vertices) > 0, true)
	for v in dl.vertices {
		testing.expect_value(t, v.pos[0] <= 100.0, true)
	}

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_widget_is_cut_to_its_own_rect :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	child := GUI.New_Widget(g, .Panel, panel, GUI.Widget_Opts{name = "child"})

	w := GUI.Widget_Get(g, panel)
	c := GUI.Widget_Get(g, child)
	w.clip_contents = true
	w.rect = GUI.Rect{x = 0, y = 0, w = 50, h = 50}
	c.rect = GUI.Rect{x = 40, y = 10, w = 100, h = 20}

	GUI.build_draw_list(g)

	//* The child is cut at the edge of the panel.
	for v in g.draw.vertices {
		testing.expect_value(t, v.pos[0] <= 50.0, true)
	}

	test_gui_destroy(g)
}

//* == The order of the drawing ==

@(test)
test_the_widgets_are_drawn_in_the_order_of_the_tree :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts {
			name = "below",
			style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(1, 0, 0, 1)}},
		},
	)
	GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts {
			name = "above",
			style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0, 1, 0, 1)}},
		},
	)

	GUI.Frame(g)

	//* The one that was made last is on top: its quad comes later in
	//* the list, so it is drawn over the other one.
	below_at := -1
	above_at := -1
	for v, i in g.draw.vertices {
		if v.colour.r > 0.9 && v.colour.g < 0.1 && below_at < 0 { below_at = i }
		if v.colour.g > 0.9 && v.colour.r < 0.1 && above_at < 0 { above_at = i }
	}
	testing.expect_value(t, below_at >= 0, true)
	testing.expect_value(t, above_at >= 0, true)
	testing.expect_value(t, below_at < above_at, true)

	test_gui_destroy(g)
}

@(test)
test_a_whole_window_is_one_command :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button", text = "Press"})
	GUI.New_Widget(g, .Label, g.root, GUI.Widget_Opts{name = "label", text = "Hello"})

	GUI.Frame(g)

	//* Everything comes out of the one atlas, so the whole window is
	//* one draw call.
	testing.expect_value(t, len(g.draw.commands), 1)
	for cmd in g.draw.commands {
		testing.expect_value(t, cmd.texture, GUI.ATLAS_TEXTURE_ID)
	}

	test_gui_destroy(g)
}

@(test)
test_the_colour_of_a_vertex_is_straight_alpha :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_quad(&dl, GUI.Rect{x = 0, y = 0, w = 10, h = 10}, {0, 0, 1, 1}, GUI.RGBA(1, 0.5, 0.25, 0.5), GUI.ATLAS_TEXTURE_ID)

	//* The colour is not multiplied by the alpha: the backend that
	//* blends with premultiplied alpha does that itself.
	c := dl.vertices[0].colour
	testing.expect_value(t, c.r, 1.0)
	testing.expect_value(t, c.g, 0.5)
	testing.expect_value(t, c.b, 0.25)
	testing.expect_value(t, c.a, 0.5)

	GUI.draw_list_destroy(&dl)
}

//* == The life of a resource ==

@(test)
test_the_atlas_texture_is_given_back :: proc(t: ^testing.T) {
	state := new(Mock_State)
	g := test_gui(t)
	g.backend = mock_backend_with(state)

	GUI.Frame(g)
	testing.expect_value(t, state.destroyed, 0)

	test_gui_destroy(g)

	//* The GUI gives the texture of the atlas back to the backend.
	testing.expect_value(t, state.destroyed, 1)
	free(state)
}

@(test)
test_the_atlas_is_uploaded_once_and_the_parts_after_that :: proc(t: ^testing.T) {
	state := new(Mock_State)
	g := test_gui(t)
	g.backend = mock_backend_with(state)

	//* The first frame uploads the whole atlas, because that is what
	//* makes the texture.
	GUI.Frame(g)
	testing.expect_value(t, state.uploads, 1)

	//* The next frame has nothing new to say, so nothing goes up.
	GUI.Frame(g)
	testing.expect_value(t, state.uploads, 1)

	free(state)
	test_gui_destroy(g)
}

@(test)
test_guis_can_be_made_and_given_back_over_and_over :: proc(t: ^testing.T) {
	//* The atlas of a GUI is big, so this is the test that would find a
	//* leak of it.
	for i in 0 ..< 20 {
		g := test_gui(t)
		g.backend = mock_backend
		GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button", text = "Press"})
		GUI.Frame(g)
		test_gui_destroy(g)
	}
}

@(test)
test_textures_can_be_made_and_given_back_over_and_over :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	pixels := make([]u8, 32 * 32 * 4)
	defer delete(pixels)

	for i in 0 ..< 500 {
		texture := GUI.texture_from_pixels(g, pixels, 32, 32)
		GUI.texture_free(g, texture)
	}

	//* The space of the atlas is used again, so the table of the
	//* allocations does not grow.
	testing.expect_value(t, len(g.atlas.allocs) < 16, true)

	test_gui_destroy(g)
}

//* == The life of a frame ==

@(test)
test_the_frame_can_be_repeated :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button", text = "Press"})

	//* The frame can be run as often as the program likes, and the
	//* draw list is the same every time.
	GUI.Frame(g)
	first := len(g.draw.vertices)
	first_commands := len(g.draw.commands)

	for i in 0 ..< 50 {
		GUI.Frame(g)
	}
	testing.expect_value(t, len(g.draw.vertices), first)
	testing.expect_value(t, len(g.draw.commands), first_commands)

	test_gui_destroy(g)
}

@(test)
test_the_window_is_measured_again_when_it_is_made_bigger :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	GUI.Frame(g)

	w := GUI.Widget_Get(g, panel)
	before := w.rect.w

	GUI.gui_resize(g, 1024, 768)
	GUI.Frame(g)

	//* The widget is measured again, so it takes the new size.
	w = GUI.Widget_Get(g, panel)
	testing.expect_value(t, w.rect.w != before, true)

	//* And the clip of the list is the new size.
	testing.expect_value(t, g.draw.base_clip.w, 1024.0)

	test_gui_destroy(g)
}

@(test)
test_the_clip_of_a_floating_panel_is_its_own_window :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	GUI.Make_Float_Panel(g, panel, GUI.Vec2{100, 100}, GUI.Vec2{200, 150})

	GUI.Frame(g)

	testing.expect_value(t, len(g.floats), 1)
	//* The list of the floating panel is in the coordinates of its own
	//* window, so the clip is the size of that window.
	testing.expect_value(t, g.floats[0].draw.base_clip.w, 200.0)
	testing.expect_value(t, g.floats[0].draw.base_clip.h, 150.0)

	test_gui_destroy(g)
}

//* Tests for the draw contract: one command for a whole window, and
//* the clip that is worked out on the CPU.

//* == The clip ==

@(test)
test_a_quad_that_is_cut_away_is_dropped :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_push_clip(&dl, GUI.Rect{x = 0, y = 0, w = 50, h = 50})
	GUI.draw_quad(&dl, GUI.Rect{60, 60, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(0))

	//* Nothing was drawn: not a vertex, not a command.
	testing.expect_value(t, len(dl.vertices), 0)
	testing.expect_value(t, len(dl.indices), 0)
	testing.expect_value(t, len(dl.commands), 0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_quad_that_is_cut_keeps_the_part_of_the_texture_it_showed :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	//* A quad of 100x100 that shows the whole texture. Only the part
	//* from 25 to 75 is kept.
	GUI.draw_push_clip(&dl, GUI.Rect{x = 25, y = 25, w = 50, h = 50})
	GUI.draw_quad(
		&dl,
		GUI.Rect{x = 0, y = 0, w = 100, h = 100},
		{0, 0, 1, 1},
		GUI.Colour{1, 1, 1, 1},
		GUI.Texture_ID(0),
	)

	testing.expect_value(t, len(dl.vertices), 4)
	testing.expect_value(t, len(dl.commands), 1)

	//* The quad is cut to the clip.
	testing.expect_value(t, dl.vertices[0].pos[0], 25.0)
	testing.expect_value(t, dl.vertices[0].pos[1], 25.0)
	testing.expect_value(t, dl.vertices[2].pos[0], 75.0)
	testing.expect_value(t, dl.vertices[2].pos[1], 75.0)

	//* And the texture coordinates follow: the part that is shown is
	//* the quarter of the texture that was there before.
	testing.expect_value(t, dl.vertices[0].uv[0], 0.25)
	testing.expect_value(t, dl.vertices[0].uv[1], 0.25)
	testing.expect_value(t, dl.vertices[2].uv[0], 0.75)
	testing.expect_value(t, dl.vertices[2].uv[1], 0.75)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_quad_that_is_not_cut_keeps_its_texture_coordinates :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_quad(
		&dl,
		GUI.Rect{x = 10, y = 10, w = 20, h = 20},
		{0.25, 0.5, 0.75, 1.0},
		GUI.Colour{1, 1, 1, 1},
		GUI.Texture_ID(0),
	)

	testing.expect_value(t, dl.vertices[0].uv[0], 0.25)
	testing.expect_value(t, dl.vertices[0].uv[1], 0.5)
	testing.expect_value(t, dl.vertices[2].uv[0], 0.75)
	testing.expect_value(t, dl.vertices[2].uv[1], 1.0)

	GUI.draw_list_destroy(&dl)
}

//* == One command ==

@(test)
test_a_whole_scene_is_one_command :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	box := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{
		name = "box",
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1),
				border_color = {GUI.RGBA(0.5, 0.5, 0.6, 1), GUI.RGBA(0.5, 0.5, 0.6, 1), GUI.RGBA(0.5, 0.5, 0.6, 1), GUI.RGBA(0.5, 0.5, 0.6, 1)},
				border_width = {2, 2, 2, 2},
			},},
	})
	GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "button", text = "Press"})
	GUI.New_Widget(g, .Label, box, GUI.Widget_Opts{name = "label", text = "Hello"})

	GUI.Frame(g)

	//* Everything comes out of the one atlas, so the whole window is a
	//* single draw call.
	testing.expect_value(t, len(g.draw.commands), 1)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)
	testing.expect_value(t, g.draw.commands[0].texture, g.atlas_texture)

	test_gui_destroy(g)
}

@(test)
test_a_window_with_a_floating_panel_has_one_command_each :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{
		name = "root_panel",
		style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1)}},
	})

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{
		name = "panel",
		draggable = true,
		style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1)}},
	})
	GUI.layout_pass(g)
	GUI.Make_Float_Panel(g, panel, GUI.Vec2{100, 100}, GUI.Vec2{200, 200})

	GUI.Frame(g)

	//* The main window and the floating panel are a window each, so
	//* each one is a command of its own.
	testing.expect_value(t, len(g.draw.commands), 1)
	testing.expect_value(t, len(g.floats), 1)
	testing.expect_value(t, len(g.floats[0].draw.commands), 1)

	test_gui_destroy(g)
}

@(test)
test_the_shape_of_a_vertex_is_carried_to_the_backend :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_quad_shape(
		&dl,
		GUI.Rect{x = 10, y = 20, w = 40, h = 30},
		{0, 0, 1, 1},
		GUI.Colour{1, 1, 1, 1},
		GUI.Texture_ID(0),
		.Solid,
		6,
	)

	//* The kind, the radius and the half size of the quad are in the
	//* vertex, so the shader can work out the rounded corners.
	testing.expect_value(t, dl.vertices[0].shape[0], 1.0)
	testing.expect_value(t, dl.vertices[0].shape[1], 6.0)
	testing.expect_value(t, dl.vertices[0].shape[2], 20.0)
	testing.expect_value(t, dl.vertices[0].shape[3], 15.0)

	//* The vertex knows where it sits inside the quad.
	testing.expect_value(t, dl.vertices[0].local[0], -20.0)
	testing.expect_value(t, dl.vertices[0].local[1], -15.0)
	testing.expect_value(t, dl.vertices[2].local[0], 20.0)
	testing.expect_value(t, dl.vertices[2].local[1], 15.0)

	GUI.draw_list_destroy(&dl)
}

//* The rules of the input: the target of an event and the chain it
//* walks, the focus and the tab order, the pointer and the popups.
//* The rules themselves are written down in docs/events-focus.md.

//* == The events, the focus and the pointer ==

Event_Test_Counters :: struct {
	focus_entered: int,
	focus_exited:  int,
	pressed:       int,
	clicked:       int,
	pointed:       int,
	pointer_ups:   int,
	keyed:         int,
	last_key:      GUI.Key,
}

event_test_counters :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> ^Event_Test_Counters {
	ptr := GUI.Widget_User_Data(g, id)
	if ptr == nil { return nil }
	return cast(^Event_Test_Counters)ptr
}

event_test_counters_free :: proc(user: rawptr) {
	free(user)
}

event_test_focus_entered: int = 0
event_test_focus_exited: int = 0
event_test_pressed: int = 0
event_test_destroyed: int = 0

event_test_target: GUI.Widget_ID = GUI.INVALID_WIDGET_ID
event_test_parent: GUI.Widget_ID = GUI.INVALID_WIDGET_ID
event_test_made: GUI.Widget_ID = GUI.INVALID_WIDGET_ID
event_test_descendant: GUI.Widget_ID = GUI.INVALID_WIDGET_ID


event_test_on_focus_entered :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	event_test_focus_entered += 1
}

event_test_on_focus_exited :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	event_test_focus_exited += 1
}

event_test_on_pressed :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	event_test_pressed += 1
}

event_test_probe_click :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	counters := event_test_counters(g, id)
	if counters == nil { return }
	counters.clicked += 1
}

event_test_probe_pointer :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, e: GUI.Pointer_Event) {
	counters := event_test_counters(g, id)
	if counters == nil { return }
	counters.pointed += 1
	if e.kind == .Up {counters.pointer_ups += 1}
}

event_test_probe_key :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, e: GUI.Key_Down_Event) {
	counters := event_test_counters(g, id)
	if counters == nil { return }
	counters.keyed += 1
	counters.last_key = e.key
}

event_test_probe_construct :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	GUI.Widget_Set_User_Data(g, id, cast(rawptr)new(Event_Test_Counters), event_test_counters_free)
}

event_test_probe_destroy :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	event_test_destroyed += 1
	GUI.Widget_Free(g, event_test_descendant)
}

event_test_free_target :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	GUI.Widget_Free(g, event_test_target)
}

event_test_free_target_twice :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	GUI.Widget_Free(g, event_test_target)
	GUI.Widget_Free(g, event_test_target)
}

event_test_make_child :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	event_test_made = GUI.New_Widget(g, .Panel, event_test_parent, GUI.Widget_Opts{name = "made"})
}


event_test_probe_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "EventProbe",
		kind = GUI.Widget_Kind{
			construct = event_test_probe_construct,
			click = event_test_probe_click,
			pointer = event_test_probe_pointer,
			key = event_test_probe_key,
		},
	})
}

event_test_parent_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "EventParentProbe",
		kind = GUI.Widget_Kind{
			construct = event_test_probe_construct,
			click = event_test_probe_click,
		},
	})
}

event_test_arrow_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "EventArrowProbe",
		kind = GUI.Widget_Kind{
			construct = event_test_probe_construct,
			key = event_test_probe_key,
			uses_arrow_keys = true,
		},
	})
}

event_test_destroy_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "EventDestroyProbe",
		kind = GUI.Widget_Kind{destroy = event_test_probe_destroy},
	})
}


event_test_make_button :: proc(g: ^GUI.GUI, left: f32) -> GUI.Widget_ID {
	return GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				preset = .Top_Left,
				offsets = GUI.Offset{left, 0, left + 100, 40},
			},
		},
	)
}

event_test_make_probe :: proc(g: ^GUI.GUI, class: GUI.Widget_Class_ID, left: f32) -> GUI.Widget_ID {
	return GUI.Make_Custom_Widget(
		g,
		g.root,
		class,
		GUI.Base_Opts{
			preset = .Top_Left,
			offsets = GUI.Offset{left, 0, left + 100, 40},
			focus_mode = .All,
		},
	)
}


//* == The focus ==

@(test)
test_a_click_gives_the_focus_to_the_widget_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := event_test_make_button(g, 0)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.focused, button)
	testing.expect_value(t, GUI.Focused_Widget(g), button)
	testing.expect_value(t, GUI.Widget_Has_Focus(g, button), true)
	testing.expect_value(t, GUI.Widget_Has_Focus(g, g.root), false)

	test_gui_destroy(g)
}

@(test)
test_the_focus_signals_fire_once_for_every_change :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	event_test_focus_entered = 0
	event_test_focus_exited = 0

	first := event_test_make_button(g, 0)
	second := event_test_make_button(g, 200)
	first_w := GUI.Widget_Get(g, first)
	first_w.signals.on_focus_entered = event_test_on_focus_entered
	first_w.signals.on_focus_exited = event_test_on_focus_exited
	second_w := GUI.Widget_Get(g, second)
	second_w.signals.on_focus_entered = event_test_on_focus_entered
	second_w.signals.on_focus_exited = event_test_on_focus_exited
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)
	testing.expect_value(t, event_test_focus_entered, 1)
	testing.expect_value(t, event_test_focus_exited, 0)

	append(&g.events, mouse_down({210, 10}))
	append(&g.events, mouse_up({210, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)
	testing.expect_value(t, event_test_focus_entered, 2)
	testing.expect_value(t, event_test_focus_exited, 1)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)
	testing.expect_value(t, event_test_focus_entered, 3)
	testing.expect_value(t, event_test_focus_exited, 2)

	GUI.Widget_Set_Visible(g, first, false)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)
	testing.expect_value(t, event_test_focus_entered, 3)
	testing.expect_value(t, event_test_focus_exited, 3)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_hidden_or_disabled_gives_the_focus_up :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := event_test_make_button(g, 0)
	GUI.layout_pass(g)

	GUI.Focus_Set(g, button)
	testing.expect_value(t, g.focused, button)

	GUI.Widget_Set_Visible(g, button, false)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)

	GUI.Widget_Set_Visible(g, button, true)
	GUI.Focus_Set(g, button)
	testing.expect_value(t, g.focused, button)

	GUI.Widget_Set_Enabled(g, button, false)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_destroyed_gives_the_focus_up :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := event_test_make_button(g, 0)
	GUI.layout_pass(g)

	GUI.Focus_Set(g, button)
	GUI.Widget_Free(g, button)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	child := GUI.New_Widget(g, .Button, panel, GUI.Widget_Opts{name = "child"})
	GUI.layout_pass(g)

	GUI.Focus_Set(g, child)
	testing.expect_value(t, g.focused, child)

	GUI.Widget_Free(g, panel)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_the_program_can_give_the_focus_and_take_it_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := event_test_make_button(g, 0)
	label := GUI.New_Widget(g, .Label, g.root, GUI.Widget_Opts{name = "label", text = "A label"})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Focus_Set(g, button), true)
	testing.expect_value(t, GUI.Focused_Widget(g), button)
	testing.expect_value(t, GUI.Widget_Has_Focus(g, button), true)

	testing.expect_value(t, GUI.Focus_Set(g, label), false)
	testing.expect_value(t, GUI.Focused_Widget(g), button)

	testing.expect_value(t, GUI.Focus_Set(g, GUI.INVALID_WIDGET_ID), false)
	testing.expect_value(t, GUI.Focused_Widget(g), button)

	GUI.Focus_Clear(g)
	testing.expect_value(t, GUI.Focused_Widget(g), GUI.INVALID_WIDGET_ID)
	testing.expect_value(t, GUI.Widget_Has_Focus(g, button), false)

	test_gui_destroy(g)
}


//* == The tab order ==

@(test)
test_the_tab_key_goes_through_the_widgets_in_the_order_of_the_tree :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 0})
	first := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "second"})
	third := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "third"})
	GUI.layout_pass(g)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, third)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)

	append(&g.events, key_event(.Tab, GUI.Mods{.Shift}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, third)

	append(&g.events, key_event(.Tab, GUI.Mods{.Shift}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_only_focused_when_it_is_clicked_is_not_in_the_tab_order :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 0})
	first := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "second"})
	only_on_click := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "only on click",
			focus_mode = .Click,
			preset = .Top_Left,
			offsets = GUI.Offset{0, 400, 100, 440},
		},
	)
	GUI.layout_pass(g)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)

	append(&g.events, mouse_down({10, 410}))
	append(&g.events, mouse_up({10, 410}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, only_on_click)

	test_gui_destroy(g)
}

@(test)
test_the_tab_index_moves_a_widget_in_the_tab_order :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 0})
	first := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "second"})
	third := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "third"})
	GUI.layout_pass(g)

	GUI.Widget_Set_Tab_Index(g, third, -1)
	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, third)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)

	GUI.Widget_Set_Tab_Index(g, first, 5)
	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, first)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, third)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)

	append(&g.events, key_event(.Tab, GUI.Mods{.Shift}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, third)

	test_gui_destroy(g)
}

@(test)
test_a_widget_under_a_hidden_panel_is_not_in_the_tab_order :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	inside := GUI.New_Widget(g, .Button, panel, GUI.Widget_Opts{name = "inside"})
	GUI.layout_pass(g)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, inside)

	GUI.Widget_Set_Visible(g, panel, false)
	testing.expect_value(t, GUI.Focus_Set(g, inside), false)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)

	GUI.Focus_Clear(g)
	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}


//* == The keys ==

@(test)
test_the_arrow_keys_reach_the_widget_that_has_the_focus :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	class := event_test_probe_class(g)
	probe := event_test_make_probe(g, class, 0)
	neighbour := event_test_make_probe(g, class, 300)
	GUI.layout_pass(g)

	GUI.Focus_Set(g, probe)
	append(&g.events, key_event(.Right))
	GUI.Handle_Events(g)

	counters := event_test_counters(g, probe)
	testing.expect_value(t, counters.keyed, 1)
	testing.expect_value(t, counters.last_key, .Right)

	testing.expect_value(t, g.focused, neighbour)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_uses_the_arrow_keys_keeps_the_focus :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	class := event_test_arrow_class(g)
	probe := event_test_make_probe(g, class, 0)
	neighbour := event_test_make_probe(g, class, 300)
	GUI.layout_pass(g)

	GUI.Focus_Set(g, probe)
	append(&g.events, key_event(.Right))
	GUI.Handle_Events(g)

	counters := event_test_counters(g, probe)
	testing.expect_value(t, counters.keyed, 1)
	testing.expect_value(t, counters.last_key, .Right)

	testing.expect_value(t, g.focused, probe)

	test_gui_destroy(g)
}

@(test)
test_the_escape_key_reaches_the_widget_that_has_the_focus :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{text = "hello"})
	GUI.layout_pass(g)

	GUI.Focus_Set(g, field)
	testing.expect_value(t, g.focused, field)

	append(&g.events, key_event(.Escape))
	GUI.Handle_Events(g)

	testing.expect_value(t, field_text(g, field), "")
	testing.expect_value(t, g.quit_requested, false)

	test_gui_destroy(g)
}


//* == The chain of the event ==

@(test)
test_a_click_on_a_child_reaches_the_child_and_not_its_parent :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	parent := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_parent_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}},
	)
	child := GUI.Make_Custom_Widget(
		g,
		parent,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{20, 20, 120, 60}},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({50, 30}))
	append(&g.events, mouse_up({50, 30}))
	GUI.Handle_Events(g)

	testing.expect_value(t, event_test_counters(g, child).clicked, 1)
	testing.expect_value(t, event_test_counters(g, parent).clicked, 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_ignores_the_mouse_is_passed_over_by_the_click :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	behind := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}},
	)
	front := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}, mouse_filter = .Ignore},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{50, 50}), behind)

	append(&g.events, mouse_down({50, 50}))
	append(&g.events, mouse_up({50, 50}))
	GUI.Handle_Events(g)
	testing.expect_value(t, event_test_counters(g, behind).clicked, 1)
	testing.expect_value(t, event_test_counters(g, front).clicked, 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_disabled_does_not_take_the_mouse :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	behind := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}},
	)
	front := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{50, 50}), front)

	GUI.Widget_Set_Enabled(g, front, false)
	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{50, 50}), behind)

	append(&g.events, mouse_down({50, 50}))
	append(&g.events, mouse_up({50, 50}))
	GUI.Handle_Events(g)
	testing.expect_value(t, event_test_counters(g, behind).clicked, 1)
	testing.expect_value(t, event_test_counters(g, front).clicked, 0)

	test_gui_destroy(g)
}

@(test)
test_the_chain_of_the_event_goes_on_past_a_widget_that_passes_the_mouse_on :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	stopper := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}},
	)
	passer := GUI.Make_Custom_Widget(
		g,
		g.root,
		event_test_probe_class(g),
		GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 300, 300}, mouse_filter = .Pass},
	)
	GUI.layout_pass(g)

	chain, _ := GUI.pointer_chain(g, GUI.Vec2{50, 50})
	defer delete(chain)

	testing.expect_value(t, len(chain), 2)
	testing.expect_value(t, chain[0], passer)
	testing.expect_value(t, chain[1], stopper)

	test_gui_destroy(g)
}


//* == The pointer ==

@(test)
test_the_widget_that_is_pressed_takes_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	probe := event_test_make_probe(g, event_test_probe_class(g), 0)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.active, probe)
	testing.expect_value(t, GUI.Pointer_Captured(g), probe)
	testing.expect_value(t, event_test_counters(g, probe).pointed, 1)

	append(&g.events, mouse_move({500, 300}))
	GUI.Handle_Events(g)
	testing.expect_value(t, event_test_counters(g, probe).pointed, 2)

	testing.expect_value(t, GUI.Widget_Capture_Pointer(g, probe), true)
	testing.expect_value(t, GUI.Pointer_Captured(g), probe)
	GUI.Widget_Release_Pointer(g)
	testing.expect_value(t, GUI.Pointer_Captured(g), GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_the_widget_that_took_the_pointer_is_told_when_the_pointer_comes_up :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	probe := event_test_make_probe(g, event_test_probe_class(g), 0)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, event_test_counters(g, probe).pointer_ups, 0)

	append(&g.events, mouse_up({700, 500}))
	GUI.Handle_Events(g)

	testing.expect_value(t, event_test_counters(g, probe).pointer_ups, 1)
	testing.expect_value(t, GUI.Pointer_Captured(g), GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_a_click_happens_only_when_the_button_comes_up_over_the_widget_that_was_pressed :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	class := event_test_probe_class(g)
	first := event_test_make_probe(g, class, 0)
	second := event_test_make_probe(g, class, 300)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, event_test_counters(g, first).clicked, 1)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({310, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, event_test_counters(g, first).clicked, 1)
	testing.expect_value(t, event_test_counters(g, second).clicked, 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_cannot_hold_the_pointer_lets_it_go :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	probe := event_test_make_probe(g, event_test_probe_class(g), 0)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Pointer_Captured(g), probe)

	GUI.Widget_Set_Visible(g, probe, false)
	testing.expect_value(t, GUI.Pointer_Captured(g), GUI.INVALID_WIDGET_ID)

	GUI.Widget_Set_Visible(g, probe, true)
	append(&g.events, mouse_down({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Pointer_Captured(g), probe)

	GUI.Widget_Set_Enabled(g, probe, false)
	testing.expect_value(t, GUI.Pointer_Captured(g), GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}


//* == The popups ==

@(test)
test_a_popup_that_is_open_is_shown_and_takes_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.Make_Popup_Panel(g, g.root, GUI.Popup_Panel_Opts{})
	GUI.layout_pass(g)

	testing.expect_value(t, .Visible in GUI.Widget_Get(g, panel).state, false)
	testing.expect_value(t, GUI.Popup_Is_Open(g, panel), false)

	GUI.Popup_Open(g, panel)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, panel).state, true)
	testing.expect_value(t, GUI.Popup_Is_Open(g, panel), true)
	testing.expect_value(t, GUI.Popup_Top(g), panel)

	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{10, 10}), panel)

	GUI.Popup_Close(g, panel)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, panel).state, false)
	testing.expect_value(t, GUI.Popup_Is_Open(g, panel), false)
	testing.expect_value(t, GUI.Popup_Top(g), GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_the_popups_of_the_toolkit_come_up_when_they_are_opened :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	menu := GUI.Make_Popup_Menu(g, g.root, GUI.Popup_Menu_Opts{items = {"One", "Two"}})
	dialog := GUI.Make_Accept_Dialog(g, g.root, GUI.Accept_Dialog_Opts{text = "Are you sure?"})
	context_menu := GUI.Make_Context_Menu(g, g.root, GUI.Context_Menu_Opts{items = {{text = "One"}}})
	palette := GUI.Make_Command_Palette(g, g.root, GUI.Command_Palette_Opts{})
	GUI.layout_pass(g)

	GUI.Popup_Menu_Open(g, menu)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, menu).state, true)
	testing.expect_value(t, GUI.Popup_Top(g), menu)
	GUI.Popup_Menu_Close(g, menu)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, menu).state, false)

	GUI.Dialog_Open(g, dialog)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, dialog).state, true)
	testing.expect_value(t, GUI.Popup_Top(g), dialog)
	GUI.Dialog_Close(g, dialog)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, dialog).state, false)

	GUI.Context_Menu_Open(g, context_menu, GUI.Vec2{10, 10})
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, context_menu).state, true)
	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, context_menu), true)
	GUI.Context_Menu_Close(g, context_menu)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, context_menu).state, false)

	GUI.Command_Palette_Open(g, palette)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, palette).state, true)
	testing.expect_value(t, GUI.Command_Palette_Is_Open(g, palette), true)
	GUI.Command_Palette_Close(g, palette)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, palette).state, false)

	testing.expect_value(t, len(g.popups), 0)

	test_gui_destroy(g)
}

@(test)
test_a_popup_takes_the_keyboard_and_gives_it_back_when_it_is_closed :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := event_test_make_button(g, 0)
	palette := GUI.Make_Command_Palette(g, g.root, GUI.Command_Palette_Opts{})
	GUI.layout_pass(g)

	GUI.Focus_Set(g, button)
	testing.expect_value(t, g.focused, button)

	GUI.Command_Palette_Open(g, palette)
	testing.expect_value(t, GUI.Popup_Is_Open(g, palette), true)
	testing.expect_value(t, g.focused, palette)

	GUI.Command_Palette_Close(g, palette)
	testing.expect_value(t, GUI.Popup_Is_Open(g, palette), false)
	testing.expect_value(t, g.focused, button)

	test_gui_destroy(g)
}

@(test)
test_the_escape_key_closes_the_popup_that_is_on_top :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := event_test_make_button(g, 0)
	menu := GUI.Make_Context_Menu(g, g.root, GUI.Context_Menu_Opts{items = {{text = "One"}}})
	GUI.layout_pass(g)

	GUI.Focus_Set(g, button)
	GUI.Context_Menu_Open(g, menu, GUI.Vec2{10, 10})
	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), true)

	append(&g.events, key_event(.Escape))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), false)
	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, menu), false)
	testing.expect_value(t, g.quit_requested, false)
	testing.expect_value(t, g.focused, button)

	test_gui_destroy(g)
}

@(test)
test_a_click_outside_a_popup_closes_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	menu := GUI.Make_Context_Menu(g, g.root, GUI.Context_Menu_Opts{items = {{text = "One"}}})
	GUI.layout_pass(g)

	GUI.Context_Menu_Open(g, menu, GUI.Vec2{10, 10})
	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), true)

	append(&g.events, mouse_down({700, 500}))
	append(&g.events, mouse_up({700, 500}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), false)
	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, menu), false)

	test_gui_destroy(g)
}

@(test)
test_a_popup_whose_widget_is_destroyed_is_taken_out_of_the_stack :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.Make_Popup_Panel(g, g.root, GUI.Popup_Panel_Opts{})
	GUI.layout_pass(g)

	GUI.Popup_Open(g, panel)
	testing.expect_value(t, len(g.popups), 1)
	testing.expect_value(t, GUI.Popup_Top(g), panel)

	GUI.Widget_Free(g, panel)

	testing.expect_value(t, len(g.popups), 0)
	testing.expect_value(t, GUI.Popup_Top(g), GUI.INVALID_WIDGET_ID)
	testing.expect_value(t, GUI.Popup_Is_Open(g, panel), false)

	test_gui_destroy(g)
}


//* == The tree that changes under the event ==

@(test)
test_a_click_that_destroys_the_widget_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	event_test_pressed = 0

	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 100, 40}},
			on_pressed = event_test_free_target,
		},
	)
	event_test_target = button
	GUI.Widget_Get(g, button).signals.on_pressed = event_test_on_pressed
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Alive(g, button), false)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)
	testing.expect_value(t, event_test_pressed, 1)

	test_gui_destroy(g)
}

@(test)
test_a_click_that_destroys_a_sibling :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	first := GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 100, 40}},
			on_pressed = event_test_free_target,
		},
	)
	second := GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{200, 0, 300, 40}}},
	)
	event_test_target = second
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Alive(g, second), false)
	testing.expect_value(t, GUI.Widget_Alive(g, first), true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, panel), 1)

	testing.expect_value(t, GUI.Widget_Get(g, panel).first_child, first)
	testing.expect_value(t, GUI.Widget_Get(g, panel).last_child, first)
	testing.expect_value(t, GUI.Widget_Get(g, first).parent, panel)
	testing.expect_value(t, GUI.Widget_Get(g, first).next_sibling, GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_a_click_that_makes_a_child :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	event_test_made = GUI.INVALID_WIDGET_ID

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 100, 40}},
			on_pressed = event_test_make_child,
		},
	)
	event_test_parent = panel
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Alive(g, event_test_made), true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, panel), 1)
	testing.expect_value(t, GUI.Widget_Get(g, event_test_made).parent, panel)
	testing.expect_value(t, GUI.Widget_Get(g, panel).first_child, event_test_made)

	test_gui_destroy(g)
}

@(test)
test_a_click_that_frees_a_widget_twice :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 100, 40}},
			on_pressed = event_test_free_target_twice,
		},
	)
	event_test_target = button
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Alive(g, button), false)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})
	testing.expect_value(t, GUI.Widget_Alive(g, first), true)
	testing.expect_value(t, GUI.Widget_Alive(g, second), true)
	testing.expect_value(t, first.index == second.index, false)

	test_gui_destroy(g)
}

@(test)
test_a_destroy_hook_that_frees_a_descendant :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	event_test_destroyed = 0

	parent := GUI.Make_Custom_Widget(g, g.root, event_test_destroy_class(g), GUI.Base_Opts{name = "parent"})
	child := GUI.New_Widget(g, .Panel, parent, GUI.Widget_Opts{name = "child"})
	event_test_descendant = child
	GUI.layout_pass(g)

	GUI.Widget_Free(g, parent)

	testing.expect_value(t, event_test_destroyed, 1)
	testing.expect_value(t, GUI.Widget_Alive(g, parent), false)
	testing.expect_value(t, GUI.Widget_Alive(g, child), false)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})
	testing.expect_value(t, GUI.Widget_Alive(g, first), true)
	testing.expect_value(t, GUI.Widget_Alive(g, second), true)
	testing.expect_value(t, first.index == second.index, false)

	test_gui_destroy(g)
}

//* The tests of the fonts: the families, the fallback stack, the glyph
//* cache and what a change of the scale does to them.

font_test_bytes :: proc(t: ^testing.T) -> []u8 {
	bytes, err := os.read_entire_file_from_path("assets/fonts/Roboto-Regular.ttf", context.allocator)
	if err != nil {
		testing.fail_now(t, "could not read the test font")
	}
	return bytes
}

@(test)
test_a_family_that_falls_back_has_a_stack_of_fonts :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	primary := GUI.Font_Family_Add(g, "Roboto", bytes)
	other := GUI.Font_Family_Add(g, "Roboto again", bytes)
	testing.expect_value(t, primary != GUI.INVALID_FONT_FAMILY_ID, true)
	testing.expect_value(t, other != GUI.INVALID_FONT_FAMILY_ID, true)

	id := GUI.Font_At(g, primary, 16)
	f := GUI.font_get(g, id)
	testing.expect_value(t, len(f.stack), 1)

	testing.expect_value(t, GUI.Font_Family_Set_Fallback(g, primary, other), true)
	f = GUI.font_get(g, id)
	testing.expect_value(t, len(f.stack), 2)
	testing.expect_value(t, f.stack[0] == &GUI.font_family_get(g, primary).file.font, true)
	testing.expect_value(t, f.stack[1] == &GUI.font_family_get(g, other).file.font, true)

	test_gui_destroy(g)
}

@(test)
test_the_families_are_tried_in_order :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	primary := GUI.Font_Family_Add(g, "Roboto", bytes)
	other := GUI.Font_Family_Add(g, "Roboto again", bytes)
	GUI.Font_Family_Set_Fallback(g, primary, other)

	id := GUI.Font_At(g, primary, 16)
	f := GUI.font_get(g, id)

	lines := GUI.font_layout(g, f, "A", f.opts)
	testing.expect_value(t, len(lines), 1)
	testing.expect_value(t, len(lines[0].glyphs) > 0, true)

	for pg in lines[0].glyphs {
		testing.expect_value(t, pg.font == &GUI.font_family_get(g, primary).file.font, true)
	}

	test_gui_destroy(g)
}

@(test)
test_a_glyph_that_no_font_has_is_the_notdef_of_the_first_of_the_stack :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	primary := GUI.Font_Family_Add(g, "Roboto", bytes)
	other := GUI.Font_Family_Add(g, "Roboto again", bytes)
	GUI.Font_Family_Set_Fallback(g, primary, other)

	id := GUI.Font_At(g, primary, 16)
	f := GUI.font_get(g, id)

	testing.expect_value(t, GUI.Font_Has_Glyph(g, primary, '\u4E2D'), false)

	lines := GUI.font_layout(g, f, "\u4E2D", f.opts)
	testing.expect_value(t, len(lines), 1)
	for pg in lines[0].glyphs {
		testing.expect_value(t, pg.font == &GUI.font_family_get(g, primary).file.font, true)
		testing.expect_value(t, pg.glyph_id, runa.Glyph_ID(0))
	}

	test_gui_destroy(g)
}

@(test)
test_the_coverage_of_a_family_is_reported :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	primary := GUI.Font_Family_Add(g, "Roboto", bytes)
	testing.expect_value(t, GUI.Font_Has_Glyph(g, primary, 'A'), true)
	testing.expect_value(t, GUI.Font_Has_Glyph(g, primary, '\u4E2D'), false)
	testing.expect_value(t, GUI.Font_Has_Glyph(g, GUI.INVALID_FONT_FAMILY_ID, 'A'), false)

	test_gui_destroy(g)
}

@(test)
test_a_glyph_is_rasterized_from_the_font_that_produced_it :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	primary := GUI.Font_Family_Add(g, "Roboto", bytes)
	other := GUI.Font_Family_Add(g, "Roboto again", bytes)

	id := GUI.Font_At(g, primary, 16)
	f := GUI.font_get(g, id)

	gid := runa.font_lookup_glyph(&f.file.font, 'A')
	testing.expect_value(t, gid != runa.Glyph_ID(0), true)

	entry, ok := GUI.font_slot(g, f, &f.file.font, gid)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, len(g.glyphs), 1)

	other_file := GUI.font_family_get(g, other).file
	other_entry, other_ok := GUI.font_slot(g, f, &other_file.font, gid)
	testing.expect_value(t, other_ok, true)
	testing.expect_value(t, len(g.glyphs), 2)
	testing.expect_value(t, entry.uv != other_entry.uv, true)

	test_gui_destroy(g)
}

@(test)
test_a_change_of_the_fallback_throws_the_glyphs_away :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	primary := GUI.Font_Family_Add(g, "Roboto", bytes)
	other := GUI.Font_Family_Add(g, "Roboto again", bytes)

	id := GUI.Font_At(g, primary, 16)
	GUI.Font_Warmup(g, id)
	testing.expect_value(t, len(g.glyphs) > 0, true)

	GUI.Font_Family_Set_Fallback(g, primary, other)
	testing.expect_value(t, len(g.glyphs), 0)

	test_gui_destroy(g)
}

@(test)
test_a_font_at_two_sizes_is_two_instances :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	small := GUI.Font_At(g, family, 16)
	large := GUI.Font_At(g, family, 32)
	testing.expect_value(t, small != large, true)

	testing.expect_value(t, GUI.Font_At(g, family, 16), small)

	fs := GUI.font_get(g, small)
	fl := GUI.font_get(g, large)
	testing.expect_value(t, fs.size, 16.0)
	testing.expect_value(t, fl.size, 32.0)

	test_gui_destroy(g)
}

@(test)
test_the_measurement_and_the_drawing_agree :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := font_test_bytes(t)
	defer delete(bytes)

	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	id := GUI.Font_At(g, family, 16)

	size := GUI.Font_Measure(g, id, "Hello, world")
	testing.expect_value(t, size.x > 0, true)

	ts := GUI.Text_Style{size = 16, family = family}
	measured := GUI.text_measure(g, ts, "Hello, world", 0)
	testing.expect_value(t, abs(measured.x - size.x) < 0.01, true)
	testing.expect_value(t, abs(measured.y - size.y) < 0.01, true)

	GUI.draw_list_clear(&g.draw, g.viewport)
	g.draw.scale = g.scale
	g.target = &g.draw
	GUI.draw_text(g, ts, "Hello, world", GUI.Rect{x = 0, y = 0, w = 1000, h = 200}, GUI.RGBA(1, 1, 1, 1))

	bounds := scale_test_bounds(&g.draw)
	testing.expect_value(t, abs(bounds.w - size.x) < max(4.0, size.x * 0.1), true)

	test_gui_destroy(g)
}

//* The invalidation: what a change makes stale, and what the tree does
//* about it.

//* A GUI with a font in it, so that the text of a widget can be
//* measured.
test_gui_with_font :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := test_gui(t)
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	return g
}

//* == The flags ==

//* A change of the look of a widget makes the widget out of date, but
//* it does not make its size out of date: nothing is measured again
//* and nothing is laid out again.
@(test)
test_a_visual_change_measures_nothing :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label"}, text = "hello"},
	)
	GUI.layout_pass(g)
	//* The first layout measured the tree.
	testing.expect_value(t, g.measured_count >= 2, true)

	style := GUI.resolved_style(g, GUI.Widget_Get(g, label))
	style.box.bg_color = GUI.RGBA(1, 0, 0, 1)
	GUI.Widget_Set_Style(g, label, style^)

	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Visual), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Measure), false)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Arrange), false)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Hit), false)

	GUI.layout_pass(g)

	testing.expect_value(t, g.measured_count, 0)
	testing.expect_value(t, g.arranged_count, 0)

	//* The look of the label is out of date until it is drawn again.
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Visual), true)
	g.backend = mock_backend
	GUI.Frame(g)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Visual), false)

	test_gui_destroy(g)
}

//* A text that changes is measured again, and the widget that holds it
//* is laid out again.
@(test)
test_a_text_change_measures_the_widget_again :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	label := GUI.Make_Label(g, g.root, GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label"}, text = "hi"})
	GUI.layout_pass(g)

	small := GUI.Widget_Get(g, label).min_size.x

	GUI.Widget_Set_Text(g, label, "a much longer text")
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Measure), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Arrange), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Visual), true)

	GUI.layout_pass(g)
	testing.expect_value(t, g.measured_count, 1)
	testing.expect_value(t, g.arranged_count >= 1, true)

	//* The label is wider now.
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x > small, true)

	//* A text that gets shorter makes the label smaller again: the
	//* size of a widget is not kept for good.
	GUI.Widget_Set_Text(g, label, "hi")
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x, small)

	test_gui_destroy(g)
}

//* The tree is right after a change: the widget that follows a label
//* moves when the label gets bigger.
@(test)
test_the_layout_is_right_after_a_text_change :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{Base_Opts = GUI.Base_Opts{name = "box"}})
	first := GUI.Make_Label(g, box, GUI.Label_Opts{text = "one"})
	second := GUI.Make_Label(g, box, GUI.Label_Opts{text = "two"})
	GUI.layout_pass(g)

	top := GUI.Widget_Get(g, second).rect.y

	GUI.Widget_Set_Text(g, first, "one\none\none\none")
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, second).rect.y > top, true)

	test_gui_destroy(g)
}

//* A widget that is shown or taken away is out of date for the hit
//* test and for the look of it, but its size does not change.
@(test)
test_a_visibility_change_is_a_hit_change :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	button := GUI.Make_Button(g, g.root, GUI.Button_Opts{text = "ok"})
	GUI.layout_pass(g)

	GUI.Widget_Set_Visible(g, button, false)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, button, .Hit), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, button, .Visual), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, button, .Measure), false)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, button, .Arrange), false)

	GUI.layout_pass(g)
	testing.expect_value(t, g.measured_count, 0)
	testing.expect_value(t, g.arranged_count, 0)

	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{10, 10}) == button, false)

	GUI.Widget_Set_Visible(g, button, true)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{10, 10}) == button, true)

	test_gui_destroy(g)
}

//* A widget that moves to another parent is measured again and laid out
//* again, and the tree is right afterwards.
@(test)
test_a_reparent_arranges_the_tree_again :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{Base_Opts = GUI.Base_Opts{name = "box"}})
	panel := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "panel", min_size = GUI.Vec2{40, 20}}},
	)
	GUI.layout_pass(g)

	before := GUI.Widget_Get(g, panel).rect

	GUI.Make_Panel(g, box, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "other"}})
	GUI.Widget_Attach(g, box, panel)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, panel, .Arrange), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, box, .Arrange), true)

	GUI.layout_pass(g)

	//* The panel is in the box now, and it is not where it was: the
	//* box shares its space among its children.
	after := GUI.Widget_Get(g, panel).rect
	testing.expect_value(t, after != before, true)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, box)

	test_gui_destroy(g)
}

//* A widget that is freed leaves the tree, and the tree is laid out
//* again without it.
@(test)
test_a_freed_widget_leaves_the_tree :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{Base_Opts = GUI.Base_Opts{name = "box"}})
	first := GUI.Make_Label(g, box, GUI.Label_Opts{text = "one"})
	second := GUI.Make_Label(g, box, GUI.Label_Opts{text = "two"})
	GUI.layout_pass(g)

	top := GUI.Widget_Get(g, second).rect.y

	GUI.Widget_Free(g, first)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, second).rect.y < top, true)

	test_gui_destroy(g)
}

//* == The theme ==

//* A theme that changes makes the widgets that take it be measured
//* again: the theme can change the size of the text of a widget.
@(test)
test_a_theme_change_measures_the_widgets_that_take_it :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Label, GUI.Style{text = GUI.Text_Style{size = 20}})
	GUI.GUI_Set_Theme(g, theme)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label", use_theme = true}, text = "hello"},
	)
	GUI.layout_pass(g)

	small := GUI.Widget_Get(g, label).min_size.x

	GUI.Theme_Set_Type(theme, .Label, GUI.Style{text = GUI.Text_Style{size = 40}})
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Measure), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Theme), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Visual), true)

	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x > small, true)
	testing.expect_value(t, GUI.Widget_Get(g, label).rect.w > 0, true)

	test_gui_destroy(g)
}

//* A widget that does not take the theme is not touched by it.
@(test)
test_a_theme_change_leaves_the_widgets_that_do_not_take_it :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Label, GUI.Style{text = GUI.Text_Style{size = 20}})
	GUI.GUI_Set_Theme(g, theme)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label", use_theme = false}, text = "hello"},
	)
	GUI.layout_pass(g)

	GUI.Theme_Set_Type(theme, .Label, GUI.Style{text = GUI.Text_Style{size = 40}})
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Measure), false)

	test_gui_destroy(g)
}

//* The widget under the pointer is looked up again when the tree moves
//* under it: the widget that was under the pointer is not under it any
//* more.
@(test)
test_the_widget_under_the_pointer_follows_the_tree :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = "button", min_size = GUI.Vec2{100, 40}}, text = "ok"},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_move({20, 20}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.hot, button)

	GUI.Widget_Set_Offsets(g, button, GUI.Offset{left = 300, top = 300, right = 300, bottom = 300})
	GUI.layout_pass(g)

	testing.expect_value(t, g.hot != button, true)

	test_gui_destroy(g)
}

//* The style every widget starts from is the look of a widget that does
//* not take the theme. Changing it changes the look of every widget.
@(test)
test_the_default_style_changes_every_widget :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label", use_theme = false}, text = "hello"},
	)
	GUI.layout_pass(g)

	style := GUI.Style {
		text = GUI.Text_Style{colour = GUI.RGBA(1, 0, 0, 1)},
	}
	GUI.GUI_Set_Default_Style(g, style)

	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Visual), true)
	//* A colour does not change the size of the text, so nothing is
	//* measured again.
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, label, .Measure), false)

	GUI.layout_pass(g)
	testing.expect_value(t, g.measured_count, 0)

	testing.expect_value(t, GUI.resolved_text_colour(g, label, GUI.Widget_Get(g, label)).r, 1.0)

	test_gui_destroy(g)
}

//* A panel that is being dragged has left the layout. When the drag is
//* given up, the panel gets its place back.
@(test)
test_a_dragged_panel_gets_its_place_back :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	container := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "container", draggable = true}},
	)
	panel := GUI.Make_Panel(
		g,
		container,
		GUI.Panel_Opts {
			Base_Opts = GUI.Base_Opts{name = "panel", draggable = true, min_size = GUI.Vec2{100, 60}},
		},
	)
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, true)

	//* The dragged panel leaves the layout.
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 0.0)

	GUI.drag_cancel(g)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w > 0, true)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.h > 0, true)

	test_gui_destroy(g)
}

//* A tab that stops being shown keeps no geometry: it is neither
//* drawn nor hit.
@(test)
test_a_tab_that_stops_being_shown_keeps_no_geometry :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	tabs := GUI.Make_Tabs(g, g.root, GUI.Tabs_Opts{Base_Opts = GUI.Base_Opts{name = "tabs"}})
	first := GUI.Make_Panel(g, tabs, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "first"}})
	second := GUI.Make_Panel(g, tabs, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "second"}})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, first).rect.w > 0, true)

	GUI.set_active_tab(g, tabs, second)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, first).rect.w, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.h, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, second).rect.w > 0, true)

	test_gui_destroy(g)
}

//* The smallest size a widget asks for can be made smaller at runtime.
@(test)
test_an_asked_for_size_can_be_made_smaller :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	panel := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "panel", min_size = GUI.Vec2{120, 30}}},
	)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, panel).min_size.x, 120.0)

	GUI.Widget_Set_Min_Size(g, panel, GUI.Vec2{40, 10})
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, panel).min_size.x, 40.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).min_size.y, 10.0)

	test_gui_destroy(g)
}

//* A theme that is changed behind the back of the toolkit can be
//* brought back into the tree by hand.
@(test)
test_a_theme_changed_behind_the_back_can_be_brought_back :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Label, GUI.Style{text = GUI.Text_Style{size = 20}})
	GUI.GUI_Set_Theme(g, theme)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label", use_theme = true}, text = "hello"},
	)
	GUI.layout_pass(g)
	small := GUI.Widget_Get(g, label).min_size.x

	//* The theme is changed without saying so.
	entries := GUI.theme_entries_of(theme, .Label)
	entries.text.size = 40
	GUI.theme_put_entries(theme, .Label, entries)

	GUI.GUI_Invalidate_Theme(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x > small, true)

	test_gui_destroy(g)
}

//* A change that is made under a tab that is not showing is not lost:
//* the tab is placed again when it is showing.
@(test)
test_a_change_under_a_hidden_tab_is_not_lost :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	tabs := GUI.Make_Tabs(g, g.root, GUI.Tabs_Opts{Base_Opts = GUI.Base_Opts{name = "tabs"}})
	first := GUI.Make_Panel(g, tabs, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "first"}})
	second := GUI.Make_Panel(g, tabs, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "second"}})
	mid := GUI.Make_Panel(g, first, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "mid"}})
	deep := GUI.Make_Panel(g, mid, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "deep"}})
	GUI.layout_pass(g)

	GUI.set_active_tab(g, tabs, second)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.w, 0.0)

	//* A change is made under the tab that is not showing.
	GUI.Widget_Set_Offsets(g, deep, GUI.Offset{left = 100, top = 100, right = 100, bottom = 100})
	GUI.layout_pass(g)

	GUI.set_active_tab(g, tabs, first)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, deep).rect.x, 100.0)

	test_gui_destroy(g)
}

//* == The whole tree ==

//* The way out for a program that writes to a widget itself: the whole
//* tree is measured and laid out again.
@(test)
test_the_whole_tree_can_be_asked_for :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	GUI.Make_Label(g, g.root, GUI.Label_Opts{text = "one"})
	GUI.Make_Label(g, g.root, GUI.Label_Opts{text = "two"})
	GUI.layout_pass(g)

	//* Nothing changed, so nothing was done.
	GUI.layout_pass(g)
	testing.expect_value(t, g.measured_count, 0)
	testing.expect_value(t, g.arranged_count, 0)

	GUI.GUI_Invalidate_All(g)
	GUI.layout_pass(g)

	testing.expect_value(t, g.measured_count >= 3, true)
	testing.expect_value(t, g.arranged_count >= 3, true)

	test_gui_destroy(g)
}

//* A widget that nothing happened to is not measured again, even when
//* another widget far away from it changed.
@(test)
test_a_widget_that_did_not_change_is_left_alone :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{Base_Opts = GUI.Base_Opts{name = "box"}})
	first := GUI.Make_Label(g, box, GUI.Label_Opts{text = "one"})
	second := GUI.Make_Label(g, box, GUI.Label_Opts{text = "two"})
	GUI.layout_pass(g)

	GUI.Widget_Set_Text(g, first, "one one one")
	GUI.layout_pass(g)

	testing.expect_value(t, g.measured_count, 1)

	testing.expect_value(t, GUI.Widget_Is_Dirty(g, second, .Measure), false)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, second, .Arrange), false)

	test_gui_destroy(g)
}

//* The size of a widget that asks for one of its own is kept, even
//* when the text of the widget changes.
@(test)
test_an_asked_for_size_is_kept :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label", min_size = GUI.Vec2{120, 0}}, text = "hi"},
	)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x, 120.0)

	GUI.Widget_Set_Text(g, label, "a much longer text than before")
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x >= 120.0, true)

	GUI.Widget_Set_Min_Size(g, label, GUI.Vec2{200, 0})
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x >= 200.0, true)

	test_gui_destroy(g)
}

//* A widget that is taken out of the tree keeps its own size, and it
//* gets it back when it goes in again.
@(test)
test_a_widget_that_leaves_the_tree_keeps_its_size :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	label := GUI.Make_Label(g, g.root, GUI.Label_Opts{text = "hello"})
	GUI.layout_pass(g)
	size := GUI.Widget_Get(g, label).min_size.x

	GUI.Widget_Detach(g, label)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x, size)

	GUI.Widget_Attach(g, g.root, label)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, label).min_size.x, size)

	test_gui_destroy(g)
}

//* The tests of the flags of the size, of the stretch ratio and of the
//* direction: a widget in a box, the layout pass, and the rect of the
//* child. The flags of a widget are not looked at: what the layout does
//* with them is.

//* The room of the box of the tests is 800 by 600, the root of the GUI
//* has no margin of its own, and the space between the children of a box
//* is 4 unless the test says another number.

@(test)
test_the_default_flags_take_the_minimum_size_and_a_share :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{0, 40}})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{0, 60}, weight = 3})

	same_box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "same_box"})
	same := GUI.New_Widget(
		g,
		.Panel,
		same_box,
		GUI.Widget_Opts {
			name = "same",
			min_size = GUI.Vec2{0, 40},
			size_flags_v = GUI.Size_Flags{.Fill, .Expand},
		},
	)
	same_second := GUI.New_Widget(
		g,
		.Panel,
		same_box,
		GUI.Widget_Opts{name = "same_second", min_size = GUI.Vec2{0, 60}, weight = 3},
	)

	GUI.layout_pass(g)

	//* The minimum sizes take 100 of the 600 the box has, and the 496
	//* that are left over are shared by the weight: one part for the
	//* first child and three for the second.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.y, 0.0)
	testing.expect_value(t, f.rect.h, 164.0)
	testing.expect_value(t, s.rect.y, 168.0)
	testing.expect_value(t, s.rect.h, 432.0)
	testing.expect_value(t, s.rect.y + s.rect.h + 4.0, 604.0)

	//* The flags that are said out loud are the flags of the default.
	m := GUI.Widget_Get(g, same)
	ms := GUI.Widget_Get(g, same_second)
	testing.expect_value(t, m.rect.y, f.rect.y)
	testing.expect_value(t, m.rect.h, f.rect.h)
	testing.expect_value(t, ms.rect.y, s.rect.y)
	testing.expect_value(t, ms.rect.h, s.rect.h)

	test_gui_destroy(g)
}

@(test)
test_a_child_that_does_not_expand_takes_only_its_minimum_size :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	small := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts {
			name = "small",
			min_size = GUI.Vec2{0, 40},
			size_flags_v = GUI.Size_Flags{.Fill},
		},
	)
	big := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "big", min_size = GUI.Vec2{0, 60}})

	GUI.layout_pass(g)

	//* The child that does not expand takes only its minimum size, and
	//* the room that is left over goes to the child that expands.
	s := GUI.Widget_Get(g, small)
	b := GUI.Widget_Get(g, big)
	testing.expect_value(t, s.rect.y, 0.0)
	testing.expect_value(t, s.rect.h, 40.0)
	testing.expect_value(t, b.rect.y, 44.0)
	testing.expect_value(t, b.rect.h, 556.0)

	test_gui_destroy(g)
}

@(test)
test_a_child_that_shrinks_is_centred_in_the_room_it_would_have_had :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	shrunk := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts {
			name = "shrunk",
			min_size = GUI.Vec2{0, 40},
			size_flags_v = GUI.Size_Flags{.Fill, .Expand, .Shrink_Center},
		},
	)
	other := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "other", min_size = GUI.Vec2{0, 60}})

	GUI.layout_pass(g)

	//* The room of the first child is 40 plus its share of the 496 that
	//* are left over, and the child is centred in that room: it starts
	//* 124 down and it is 40 high.
	s := GUI.Widget_Get(g, shrunk)
	o := GUI.Widget_Get(g, other)
	testing.expect_value(t, s.rect.h, 40.0)
	testing.expect_value(t, s.rect.y, 124.0)
	testing.expect_value(t, s.rect.y + s.rect.h * 0.5, 144.0)
	testing.expect_value(t, o.rect.y, 292.0)
	testing.expect_value(t, o.rect.h, 308.0)

	test_gui_destroy(g)
}

@(test)
test_two_children_that_expand_share_the_leftover_by_their_weight :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", weight = 1})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", weight = 3})

	GUI.layout_pass(g)

	//* Nothing asks for a size of its own, so the 596 that are left of
	//* the 600 of the box are shared by the weight: 149 for the first
	//* child and 447 for the second.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.h, 149.0)
	testing.expect_value(t, s.rect.y, 153.0)
	testing.expect_value(t, s.rect.h, 447.0)

	test_gui_destroy(g)
}

@(test)
test_the_horizontal_flags_of_a_child_of_a_vertical_box :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	filled := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts {
			name = "filled",
			min_size = GUI.Vec2{100, 40},
			size_flags_h = GUI.Size_Flags{.Fill, .Expand},
		},
	)
	centred := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts {
			name = "centred",
			min_size = GUI.Vec2{100, 40},
			size_flags_h = GUI.Size_Flags{.Fill, .Expand, .Shrink_Center},
		},
	)

	GUI.layout_pass(g)

	//* The first child fills the width of the box, and the second one
	//* takes its minimum width and is centred in the box.
	f := GUI.Widget_Get(g, filled)
	c := GUI.Widget_Get(g, centred)
	testing.expect_value(t, f.rect.x, 0.0)
	testing.expect_value(t, f.rect.w, 800.0)
	testing.expect_value(t, c.rect.w, 100.0)
	testing.expect_value(t, c.rect.x, 350.0)

	test_gui_destroy(g)
}

@(test)
test_the_stretch_ratio_divides_the_share_of_a_child :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", weight = 1})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", weight = 1, stretch_ratio = 3})

	GUI.layout_pass(g)

	//* The share of a child is its weight times its ratio: the 596 that
	//* are left of the 600 of the box are shared one to three.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.h, 149.0)
	testing.expect_value(t, s.rect.y, 153.0)
	testing.expect_value(t, s.rect.h, 447.0)

	test_gui_destroy(g)
}

@(test)
test_a_stretch_ratio_of_zero_gives_a_share_of_nothing :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{0, 40}})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{0, 60}})

	GUI.Widget_Set_Stretch_Ratio(g, first, 0)
	GUI.layout_pass(g)

	//* The first child asks for nothing, so it takes only its minimum
	//* size and the room that is left over goes to the second one.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.h, 40.0)
	testing.expect_value(t, s.rect.y, 44.0)
	testing.expect_value(t, s.rect.h, 556.0)

	test_gui_destroy(g)
}

@(test)
test_the_size_flags_can_be_set_after_the_widget_is_made :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	child := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "child", min_size = GUI.Vec2{0, 40}})
	other := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "other", min_size = GUI.Vec2{0, 60}})

	GUI.layout_pass(g)

	//* The child expands: it takes its minimum size and its share.
	c := GUI.Widget_Get(g, child)
	testing.expect_value(t, c.rect.h, 288.0)

	//* Without the flag to expand it takes only its minimum size, and
	//* the room that is left over goes to the other child.
	GUI.Widget_Set_Size_Flags(g, child, GUI.Size_Flags{.Fill, .Expand}, GUI.Size_Flags{.Fill})
	GUI.layout_pass(g)

	c = GUI.Widget_Get(g, child)
	o := GUI.Widget_Get(g, other)
	testing.expect_value(t, c.rect.h, 40.0)
	testing.expect_value(t, o.rect.y, 44.0)
	testing.expect_value(t, o.rect.h, 556.0)

	test_gui_destroy(g)
}

@(test)
test_a_child_that_keeps_its_size_keeps_it_whatever_the_flags_say :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	kept := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "kept", min_size = GUI.Vec2{0, 40}})
	other := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "other", min_size = GUI.Vec2{0, 60}})

	GUI.Widget_Set_Manual_Size(g, kept, GUI.Vec2{0, 100})
	GUI.Widget_Set_Size_Flags(g, kept, GUI.Size_Flags{.Fill, .Expand}, GUI.Size_Flags{.Fill})
	GUI.layout_pass(g)

	//* The child was pulled to a size, so it keeps it: the room that is
	//* left over goes to the other child.
	k := GUI.Widget_Get(g, kept)
	o := GUI.Widget_Get(g, other)
	testing.expect_value(t, k.rect.h, 100.0)
	testing.expect_value(t, o.rect.y, 104.0)
	testing.expect_value(t, o.rect.h, 496.0)

	test_gui_destroy(g)
}

@(test)
test_a_horizontal_box_puts_its_children_in_the_other_order_when_the_direction_is_rtl :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .HBox, g.root, GUI.Widget_Opts{name = "box", separation = 10})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{100, 0}, fixed = true})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{100, 0}, fixed = true})

	GUI.layout_pass(g)

	//* From the left to the right: the first child comes first.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.x, 0.0)
	testing.expect_value(t, f.rect.w, 100.0)
	testing.expect_value(t, s.rect.x, 110.0)

	GUI.Widget_Set_Layout_Direction(g, box, .RTL)
	GUI.layout_pass(g)

	//* From the right to the left: the first child comes last.
	testing.expect_value(t, f.rect.x, 700.0)
	testing.expect_value(t, f.rect.w, 100.0)
	testing.expect_value(t, s.rect.x, 590.0)
	testing.expect_value(t, s.rect.w, 100.0)

	test_gui_destroy(g)
}

@(test)
test_a_vertical_box_is_not_affected_by_the_direction :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box", separation = 10})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{0, 40}, fixed = true})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{0, 60}, fixed = true})

	GUI.layout_pass(g)
	GUI.Widget_Set_Layout_Direction(g, box, .RTL)
	GUI.layout_pass(g)

	//* The box stacks its children from the top to the bottom, so the
	//* direction says nothing about them.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.y, 0.0)
	testing.expect_value(t, f.rect.h, 40.0)
	testing.expect_value(t, s.rect.y, 50.0)
	testing.expect_value(t, s.rect.h, 60.0)

	test_gui_destroy(g)
}

@(test)
test_a_child_takes_the_direction_of_its_parent :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .HBox, g.root, GUI.Widget_Opts{name = "box"})
	inner := GUI.New_Widget(g, .HBox, box, GUI.Widget_Opts{name = "inner"})
	first := GUI.New_Widget(g, .Panel, inner, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{100, 0}, fixed = true})
	second := GUI.New_Widget(g, .Panel, inner, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{100, 0}, fixed = true})

	GUI.Widget_Set_Layout_Direction(g, box, .RTL)
	GUI.layout_pass(g)

	//* The inner box says nothing about the direction, so it takes the
	//* direction of its parent, and its children are in the other order.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.x, 700.0)
	testing.expect_value(t, s.rect.x, 596.0)

	test_gui_destroy(g)
}

@(test)
test_the_direction_of_a_widget_that_says_one_wins_over_the_one_of_its_parent :: proc(t: ^testing.T) {	g := test_gui(t)

	box := GUI.New_Widget(g, .HBox, g.root, GUI.Widget_Opts{name = "box"})
	inner := GUI.New_Widget(
		g,
		.HBox,
		box,
		GUI.Widget_Opts{name = "inner", layout_direction = .LTR},
	)
	first := GUI.New_Widget(g, .Panel, inner, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{100, 0}, fixed = true})
	second := GUI.New_Widget(g, .Panel, inner, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{100, 0}, fixed = true})

	GUI.Widget_Set_Layout_Direction(g, box, .RTL)
	GUI.layout_pass(g)

	//* The inner box says from the left to the right, so its children
	//* are in that order, whatever the parent says.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.x, 0.0)
	testing.expect_value(t, s.rect.x, 104.0)

	test_gui_destroy(g)
}

@(test)
test_a_pull_in_a_box_from_the_right_to_the_left_gives_the_room_to_the_neighbour_on_the_right :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .HBox, g.root, GUI.Widget_Opts{name = "box"})
	first := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{100, 0}, draggable = true},
	)
	second := GUI.New_Widget(
		g,
		.Panel,
		box,
		GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{100, 0}, draggable = true},
	)

	GUI.Widget_Set_Layout_Direction(g, box, .RTL)
	GUI.layout_pass(g)

	//* The first child of the tree is on the right.
	f := GUI.Widget_Get(g, first)
	s := GUI.Widget_Get(g, second)
	testing.expect_value(t, f.rect.x, 402.0)
	testing.expect_value(t, f.rect.w, 398.0)
	testing.expect_value(t, s.rect.x, 0.0)
	testing.expect_value(t, s.rect.w, 398.0)

	//* The edge between the two panels is pulled to the right: the panel
	//* on the left grows, and the panel on the right gives the room.
	append(&g.events, mouse_down({396, 300}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({436, 300}))
	GUI.Handle_Events(g)
	GUI.layout_pass(g)

	f = GUI.Widget_Get(g, first)
	s = GUI.Widget_Get(g, second)
	testing.expect_value(t, s.rect.w, 438.0)
	testing.expect_value(t, f.rect.w, 358.0)

	test_gui_destroy(g)
}

//* A hook of a widget may move a widget while the tree is being walked:
//* the walk must go on with the children the widget had when it
//* started, or the siblings that are left are never measured again: the
//* parent takes the dirty bit away when the walk is done.

reentrancy_sibling_moves: int = 0
reentrancy_leaver_moves: int = 0
reentrancy_layout_moves: int = 0
reentrancy_layout_calls: int = 0


reentrancy_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Reentrant",
		kind = GUI.Widget_Kind{measure = reentrancy_measure},
	})
}

reentrancy_leaver_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Leaver",
		kind = GUI.Widget_Kind{measure = reentrancy_leaver_measure},
	})
}

reentrancy_mover_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Mover",
		kind = GUI.Widget_Kind{
			measure = reentrancy_counted_measure,
			layout = reentrancy_layout,
		},
	})
}

reentrancy_counted_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Counted",
		kind = GUI.Widget_Kind{measure = reentrancy_counted_measure},
	})
}


reentrancy_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	if w != nil && reentrancy_sibling_moves == 0 {
		sibling := w.next_sibling
		if sibling != GUI.INVALID_WIDGET_ID {
			reentrancy_sibling_moves += 1
			GUI.Widget_Detach(g, sibling)
		}
	}
	return GUI.Vec2{20, 20}
}

reentrancy_leaver_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	if reentrancy_leaver_moves == 0 {
		reentrancy_leaver_moves += 1
		GUI.Widget_Detach(g, id)
	}
	return GUI.Vec2{20, 20}
}

reentrancy_layout :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, rect: GUI.Rect) {
	reentrancy_layout_calls += 1
	if reentrancy_layout_moves == 0 {
		reentrancy_layout_moves += 1
		GUI.Widget_Detach(g, id)
	}
}

reentrancy_counted_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	return GUI.Vec2{20, 20}
}


@(test)
test_a_measure_that_takes_a_sibling_away_does_not_stop_the_walk :: proc(t: ^testing.T) {
	g := test_gui(t)

	reentrancy_sibling_moves = 0

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	mover := GUI.Make_Custom_Widget(g, box, reentrancy_class(g), GUI.Base_Opts{name = "mover"})
	moved := GUI.Make_Custom_Widget(g, box, reentrancy_counted_class(g), GUI.Base_Opts{name = "moved"})
	last := GUI.Make_Custom_Widget(g, box, reentrancy_counted_class(g), GUI.Base_Opts{name = "last"})

	plain := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "plain"})
	kept_a := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_a"})
	kept_b := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_b"})

	GUI.layout_pass(g)

	testing.expect_value(t, reentrancy_sibling_moves, 1)
	testing.expect_value(t, GUI.Widget_Get(g, moved).parent == GUI.INVALID_WIDGET_ID, true)

	testing.expect_value(t, GUI.Widget_Get(g, moved).min_size.x, 20.0)
	testing.expect_value(t, GUI.Widget_Get(g, moved).min_size.y, 20.0)

	testing.expect_value(t, GUI.Widget_Get(g, last).min_size.x, 20.0)
	testing.expect_value(t, GUI.Widget_Get(g, last).min_size.y, 20.0)

	testing.expect_value(t, GUI.Widget_Get(g, moved).min_size.x, GUI.Widget_Get(g, kept_a).min_size.x)
	testing.expect_value(t, GUI.Widget_Get(g, last).min_size.x, GUI.Widget_Get(g, kept_b).min_size.x)

	testing.expect_value(t, GUI.Widget_Get(g, last).rect.w, GUI.Widget_Get(g, kept_b).rect.w)
	testing.expect_value(t, GUI.Widget_Get(g, last).rect.h, GUI.Widget_Get(g, kept_b).rect.h)
	testing.expect_value(t, GUI.Widget_Get(g, last).rect.y, GUI.Widget_Get(g, kept_b).rect.y)

	test_gui_destroy(g)
}

@(test)
test_a_measure_that_takes_a_widget_away_does_not_stop_the_walk :: proc(t: ^testing.T) {
	g := test_gui(t)

	reentrancy_leaver_moves = 0

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	leaver := GUI.Make_Custom_Widget(g, box, reentrancy_leaver_class(g), GUI.Base_Opts{name = "leaver"})
	first := GUI.Make_Custom_Widget(g, box, reentrancy_counted_class(g), GUI.Base_Opts{name = "first"})
	second := GUI.Make_Custom_Widget(g, box, reentrancy_counted_class(g), GUI.Base_Opts{name = "second"})

	plain := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "plain"})
	kept_a := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_a"})
	kept_b := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_b"})

	GUI.layout_pass(g)

	testing.expect_value(t, reentrancy_leaver_moves, 1)
	testing.expect_value(t, GUI.Widget_Get(g, leaver).parent == GUI.INVALID_WIDGET_ID, true)

	testing.expect_value(t, GUI.Widget_Get(g, first).min_size.x, 20.0)
	testing.expect_value(t, GUI.Widget_Get(g, first).min_size.y, 20.0)
	testing.expect_value(t, GUI.Widget_Get(g, second).min_size.x, 20.0)
	testing.expect_value(t, GUI.Widget_Get(g, second).min_size.y, 20.0)

	testing.expect_value(t, GUI.Widget_Get(g, first).min_size.x, GUI.Widget_Get(g, kept_a).min_size.x)
	testing.expect_value(t, GUI.Widget_Get(g, second).min_size.x, GUI.Widget_Get(g, kept_b).min_size.x)

	testing.expect_value(t, GUI.Widget_Get(g, first).rect.w, GUI.Widget_Get(g, kept_a).rect.w)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.h, GUI.Widget_Get(g, kept_a).rect.h)
	testing.expect_value(t, GUI.Widget_Get(g, second).rect.y, GUI.Widget_Get(g, kept_b).rect.y)

	test_gui_destroy(g)
}

@(test)
test_a_layout_that_takes_a_widget_away_does_not_stop_the_walk :: proc(t: ^testing.T) {
	g := test_gui(t)

	reentrancy_layout_moves = 0
	reentrancy_layout_calls = 0

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	mover := GUI.Make_Custom_Widget(g, box, reentrancy_mover_class(g), GUI.Base_Opts{name = "mover"})
	first := GUI.Make_Custom_Widget(g, box, reentrancy_counted_class(g), GUI.Base_Opts{name = "first"})
	second := GUI.Make_Custom_Widget(g, box, reentrancy_counted_class(g), GUI.Base_Opts{name = "second"})

	plain := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "plain"})
	kept_a := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_a"})
	kept_b := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_b"})
	kept_c := GUI.Make_Custom_Widget(g, plain, reentrancy_counted_class(g), GUI.Base_Opts{name = "kept_c"})

	GUI.layout_pass(g)

	testing.expect_value(t, reentrancy_layout_calls, 1)
	testing.expect_value(t, reentrancy_layout_moves, 1)
	testing.expect_value(t, GUI.Widget_Get(g, mover).parent == GUI.INVALID_WIDGET_ID, true)

	testing.expect_value(t, GUI.Widget_Get(g, first).rect.h > 0.0, true)
	testing.expect_value(t, GUI.Widget_Get(g, second).rect.h > 0.0, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.h, GUI.Widget_Get(g, second).rect.h)

	testing.expect_value(t, GUI.Widget_Get(g, first).rect.w, GUI.Widget_Get(g, kept_a).rect.w)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.y, GUI.Widget_Get(g, kept_b).rect.y)
	testing.expect_value(t, GUI.Widget_Get(g, second).rect.y, GUI.Widget_Get(g, kept_c).rect.y)
	testing.expect_value(t, GUI.Widget_Get(g, second).rect.h, GUI.Widget_Get(g, kept_c).rect.h)

	test_gui_destroy(g)
}

//* == The ownership of the data of the widgets ==
//* A text that the widget owns is made with `strings.clone(text)` (the
//* default allocator) and is given back with `delete`. A text that lives
//* as long as the GUI is made in the arena of the GUI
//* (`virt.arena_allocator(&g.arena)`) and is never given back; the arena
//* is given back when the GUI is shut down.
//*
//* The table of what every kind of data owns is at the top of
//* widget.odin. The tests here see that the texts of the widgets are
//* given back when the widgets are destroyed, and that nothing of the
//* arena of the GUI is given back. Run with: odin test src/GUI

//* The number of widgets whose data of the program was given back.
ownership_test_destroyed: int = 0

//* Gives back the data of a widget of a program.
ownership_test_destroy :: proc(user: rawptr) {
	ownership_test_destroyed += 1
}

//* True when the memory of a pointer is still in use. The allocator of a
//* test keeps track of the memory that is in use, so the test can see
//* that a text is given back.
ownership_test_in_use :: proc(pointer: rawptr) -> bool {
	ta := (^mem.Tracking_Allocator)(context.allocator.data)
	_, live := ta.allocation_map[pointer]
	return live
}

//* The text of a widget that keeps one.
ownership_test_text_of :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> string {
	w := GUI.Widget_Get(g, id)
	if w == nil { return "" }
	#partial switch d in w.data {
	case GUI.Text_Box_Data:
		return d.text
	case GUI.Search_Field_Data:
		return d.text
	case GUI.Chat_Input_Data:
		return d.text
	case GUI.Command_Palette_Data:
		return d.text
	}
	return ""
}

//* Runs the body of a test and sees that it leaves nothing behind: every
//* text that a widget owns is given back, and nothing that belongs to
//* the arena of the GUI is given back.
ownership_expect_clean :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	testing.expect_leaks(
		t,
		body,
		proc(t: ^testing.T, ta: ^mem.Tracking_Allocator) {
			testing.expect_value(t, len(ta.allocation_map), 0)
			testing.expect_value(t, len(ta.bad_free_array), 0)
		},
	)
}

//* == The texts of the widgets ==

@(test)
test_the_command_palette_gives_back_its_text :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := test_gui(t)
		palette := GUI.Make_Command_Palette(
			g,
			g.root,
			GUI.Command_Palette_Opts{Base_Opts = GUI.Base_Opts{name = "palette"}},
		)

		//* The text of the filter is set, changed, emptied and changed
		//* again, and the palette is opened in between.
		GUI.Command_Palette_Set_Text(g, palette, "git")
		GUI.Widget_Set_Text(g, palette, "commit")
		GUI.Command_Palette_Open(g, palette)
		GUI.Command_Palette_Set_Text(g, palette, "status")
		GUI.Widget_Set_Text(g, palette, "log")

		//* The text of the filter belongs to the widget, so the arena
		//* of the GUI does not grow when it is set.
		used := g.arena.total_used
		GUI.Command_Palette_Set_Text(g, palette, "branch")
		testing.expect_value(t, g.arena.total_used, used)

		//* The text of the filter, and the place where it is.
		pointer := raw_data(ownership_test_text_of(g, palette))
		testing.expect_value(t, ownership_test_in_use(pointer), true)

		GUI.Widget_Free(g, palette)

		//* The text of the filter is given back with the widget.
		testing.expect_value(t, ownership_test_in_use(pointer), false)

		test_gui_destroy(g)
	})
}

@(test)
test_the_chat_input_gives_back_its_text :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := test_gui(t)
		chat := GUI.Make_Chat_Input(
			g,
			g.root,
			GUI.Chat_Input_Opts{Base_Opts = GUI.Base_Opts{name = "chat"}},
		)

		//* The text of the field is set, changed, typed into, cut short
		//* and sent.
		GUI.chat_input_set_text(g, chat, "hello")
		GUI.Widget_Set_Text(g, chat, "world")
		GUI.chat_input_type(g, chat, "!")
		GUI.chat_input_backspace(g, chat)
		GUI.chat_input_submit(g, chat)

		//* The text of the field belongs to the widget, so the arena of
		//* the GUI does not grow when it is set.
		used := g.arena.total_used
		GUI.chat_input_set_text(g, chat, "again")
		testing.expect_value(t, g.arena.total_used, used)

		//* The text of the field, and the place where it is.
		pointer := raw_data(ownership_test_text_of(g, chat))
		testing.expect_value(t, ownership_test_in_use(pointer), true)

		GUI.Widget_Free(g, chat)

		//* The text of the field is given back with the widget.
		testing.expect_value(t, ownership_test_in_use(pointer), false)

		test_gui_destroy(g)
	})
}

@(test)
test_the_search_field_gives_back_its_text :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := test_gui(t)
		field := GUI.Make_Search_Field(
			g,
			g.root,
			GUI.Search_Field_Opts{Base_Opts = GUI.Base_Opts{name = "field"}, text = "find"},
		)

		//* The text of the field is set, changed, typed into, cut short
		//* and emptied.
		GUI.search_field_set_text(g, field, "find me")
		GUI.Widget_Set_Text(g, field, "other")
		GUI.search_field_type(g, field, "x")
		GUI.search_field_backspace(g, field)
		GUI.search_field_clear(g, field)

		//* The text of the field belongs to the widget, so the arena of
		//* the GUI does not grow when it is set.
		used := g.arena.total_used
		GUI.search_field_set_text(g, field, "again")
		testing.expect_value(t, g.arena.total_used, used)

		//* The text of the field, and the place where it is.
		pointer := raw_data(ownership_test_text_of(g, field))
		testing.expect_value(t, ownership_test_in_use(pointer), true)

		GUI.Widget_Free(g, field)

		//* The text of the field is given back with the widget.
		testing.expect_value(t, ownership_test_in_use(pointer), false)

		test_gui_destroy(g)
	})
}

@(test)
test_the_text_input_gives_back_its_text :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := test_gui(t)
		field := GUI.Make_Text_Box(
			g,
			g.root,
			GUI.Text_Box_Opts{Base_Opts = GUI.Base_Opts{name = "field"}, text = "hello"},
		)

		//* The text of the field is changed, typed into, cut short and
		//* emptied.
		GUI.Widget_Set_Text(g, field, "world")
		GUI.text_input_insert(g, field, "!")
		GUI.text_input_backspace(g, field)
		GUI.text_input_clear(g, field)

		//* The text of the field belongs to the widget, so the arena of
		//* the GUI does not grow when it is set.
		used := g.arena.total_used
		GUI.Widget_Set_Text(g, field, "again")
		testing.expect_value(t, g.arena.total_used, used)

		//* The text of the field, and the place where it is.
		pointer := raw_data(ownership_test_text_of(g, field))
		testing.expect_value(t, ownership_test_in_use(pointer), true)

		GUI.Widget_Free(g, field)

		//* The text of the field is given back with the widget.
		testing.expect_value(t, ownership_test_in_use(pointer), false)

		test_gui_destroy(g)
	})
}

@(test)
test_the_text_edit_gives_back_its_text :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := test_gui(t)
		edit := GUI.Make_Text_Box(
			g,
			g.root,
			GUI.Text_Box_Opts{Base_Opts = GUI.Base_Opts{name = "edit"}, text = "hello"},
		)

		//* The text of the field is changed and typed into.
		GUI.Widget_Set_Text(g, edit, "world")
		GUI.text_input_insert(g, edit, "!")
		GUI.text_input_backspace(g, edit)

		//* The text of the field belongs to the widget, so the arena of
		//* the GUI does not grow when it is set.
		used := g.arena.total_used
		GUI.Widget_Set_Text(g, edit, "again")
		testing.expect_value(t, g.arena.total_used, used)

		//* The text of the field, and the place where it is.
		pointer := raw_data(ownership_test_text_of(g, edit))
		testing.expect_value(t, ownership_test_in_use(pointer), true)

		GUI.Widget_Free(g, edit)

		//* The text of the field is given back with the widget.
		testing.expect_value(t, ownership_test_in_use(pointer), false)

		test_gui_destroy(g)
	})
}

//* == The data of a widget ==

@(test)
test_the_data_of_a_widget_is_given_back_when_the_widget_is_destroyed :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := test_gui(t)
		field := GUI.Make_Text_Box(
			g,
			g.root,
			GUI.Text_Box_Opts{Base_Opts = GUI.Base_Opts{name = "field"}, text = "hello"},
		)
		slot := int(field.index) - 1

		//* The text of the widget, and the place where it is.
		pointer := raw_data(ownership_test_text_of(g, field))
		testing.expect_value(t, ownership_test_in_use(pointer), true)

		GUI.Widget_Free(g, field)

		//* The widget has no data of its own any more.
		released := false
		#partial switch d in g.widgets[slot].data {
		case GUI.None_Data:
			released = true
		}
		testing.expect_value(t, released, true)

		//* The memory of the text is given back with the widget.
		testing.expect_value(t, ownership_test_in_use(pointer), false)

		test_gui_destroy(g)
	})
}

@(test)
test_the_data_of_a_program_is_given_back_when_the_widget_is_destroyed :: proc(t: ^testing.T) {
	g := test_gui(t)

	ownership_test_destroyed = 0
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	GUI.Widget_Set_User_Data(g, panel, rawptr(&ownership_test_destroyed), ownership_test_destroy)

	GUI.Widget_Free(g, panel)

	//* The program is told that its data is gone.
	testing.expect_value(t, ownership_test_destroyed, 1)

	test_gui_destroy(g)
}

//* The tests of the scaling: the GUI works in logical units and the draw
//* list holds physical pixels, and the change from one to the other
//* happens in one place.

scale_test_bounds :: proc(dl: ^GUI.Draw_List) -> GUI.Rect {
	if len(dl.vertices) < 4 {return {}}
	min_x := dl.vertices[0].pos[0]
	min_y := dl.vertices[0].pos[1]
	max_x := min_x
	max_y := min_y
	for v in dl.vertices {
		min_x = min(min_x, v.pos[0])
		min_y = min(min_y, v.pos[1])
		max_x = max(max_x, v.pos[0])
		max_y = max(max_y, v.pos[1])
	}
	return GUI.Rect{x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y}
}

@(test)
test_the_draw_list_holds_physical_pixels :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	dl.scale = 2
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 50})

	testing.expect_value(t, dl.base_clip.w, 200.0)
	testing.expect_value(t, dl.base_clip.h, 100.0)

	GUI.draw_quad(&dl, GUI.Rect{x = 10, y = 5, w = 20, h = 10}, {0, 0, 1, 1}, GUI.RGBA(1, 1, 1, 1), GUI.Texture_ID(0))

	testing.expect_value(t, len(dl.vertices), 4)
	testing.expect_value(t, dl.vertices[0].pos[0], 20.0)
	testing.expect_value(t, dl.vertices[0].pos[1], 10.0)
	testing.expect_value(t, dl.vertices[2].pos[0], 60.0)
	testing.expect_value(t, dl.vertices[2].pos[1], 30.0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_the_clip_of_the_draw_list_is_in_physical_pixels :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	dl.scale = 2
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})
	GUI.draw_push_clip(&dl, GUI.Rect{x = 10, y = 10, w = 20, h = 20})

	testing.expect_value(t, dl.current_clip.x, 20.0)
	testing.expect_value(t, dl.current_clip.y, 20.0)
	testing.expect_value(t, dl.current_clip.w, 40.0)
	testing.expect_value(t, dl.current_clip.h, 40.0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_quad_outside_the_clip_is_dropped :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	dl.scale = 2
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})
	GUI.draw_push_clip(&dl, GUI.Rect{x = 0, y = 0, w = 10, h = 10})

	GUI.draw_quad(&dl, GUI.Rect{x = 50, y = 50, w = 10, h = 10}, {0, 0, 1, 1}, GUI.RGBA(1, 1, 1, 1), GUI.Texture_ID(0))

	testing.expect_value(t, len(dl.vertices), 0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_a_polygon_is_scaled_into_the_list :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	dl.scale = 2
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	points := [][2]f32{{10, 10}, {30, 10}, {30, 20}, {10, 20}}
	GUI.draw_polygon(&dl, points, GUI.RGBA(1, 1, 1, 1), GUI.Texture_ID(0))

	testing.expect_value(t, len(dl.vertices) > 0, true)
	for v in dl.vertices {
		testing.expect_value(t, v.pos[0] >= 20.0 && v.pos[0] <= 60.0, true)
		testing.expect_value(t, v.pos[1] >= 20.0 && v.pos[1] <= 40.0, true)
	}

	GUI.draw_list_destroy(&dl)
}

@(test)
test_the_viewport_of_the_gui_is_in_logical_units :: proc(t: ^testing.T) {
	g := GUI.Init_GUI(400, 300, mock_backend)
	defer GUI.Shutdown_GUI(g)

	testing.expect_value(t, g.viewport.w, 400.0)
	testing.expect_value(t, g.viewport.h, 300.0)
	testing.expect_value(t, g.scale, 1.0)

	GUI.GUI_Set_Scale(g, 2)
	testing.expect_value(t, g.scale, 2.0)
	testing.expect_value(t, g.viewport.w, 400.0)
	testing.expect_value(t, g.viewport.h, 300.0)
}

@(test)
test_the_scale_is_never_zero :: proc(t: ^testing.T) {
	g := GUI.Init_GUI(400, 300, mock_backend)
	defer GUI.Shutdown_GUI(g)

	GUI.GUI_Set_Scale(g, 0)
	testing.expect_value(t, g.scale, 1.0)

	GUI.GUI_Set_Scale(g, -2)
	testing.expect_value(t, g.scale, 1.0)
}

@(test)
test_the_glyphs_are_rasterized_at_the_physical_size :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, "assets/fonts/Roboto-Regular.ttf")
	testing.expect_value(t, family != GUI.INVALID_FONT_FAMILY_ID, true)

	id := GUI.Font_At(g, family, 16)
	f := GUI.font_get(g, id)
	testing.expect_value(t, f != nil, true)
	testing.expect_value(t, f.size, 16.0)
	testing.expect_value(t, f.px_size, 16.0)

	GUI.GUI_Set_Scale(g, 2)
	f = GUI.font_get(g, id)
	testing.expect_value(t, f.px_size, 32.0)
	testing.expect_value(t, f.scale, 2.0)

	test_gui_destroy(g)
}

@(test)
test_the_measured_size_of_the_text_does_not_change_with_the_scale :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, "assets/fonts/Roboto-Regular.ttf")
	id := GUI.Font_At(g, family, 16)

	plain := GUI.Font_Measure(g, id, "Hello, world")
	testing.expect_value(t, plain.x > 0, true)

	GUI.GUI_Set_Scale(g, 2)
	scaled := GUI.Font_Measure(g, id, "Hello, world")
	testing.expect_value(t, abs(scaled.x - plain.x) < 0.5, true)

	test_gui_destroy(g)
}

@(test)
test_the_drawn_text_is_twice_as_big_at_twice_the_scale :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, "assets/fonts/Roboto-Regular.ttf")

	rect := GUI.Rect{x = 0, y = 0, w = 400, h = 200}

	GUI.draw_list_clear(&g.draw, g.viewport)
	g.draw.scale = g.scale
	g.target = &g.draw
	GUI.draw_text(g, GUI.Text_Style{size = 16, family = family}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	plain := scale_test_bounds(&g.draw)

	GUI.GUI_Set_Scale(g, 2)
	GUI.draw_list_clear(&g.draw, g.viewport)
	g.draw.scale = g.scale
	g.target = &g.draw
	GUI.draw_text(g, GUI.Text_Style{size = 16, family = family}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	scaled := scale_test_bounds(&g.draw)

	testing.expect_value(t, plain.w > 0, true)
	testing.expect_value(t, scaled.w > plain.w * 1.8, true)
	testing.expect_value(t, scaled.h > plain.h * 1.8, true)

	test_gui_destroy(g)
}

@(test)
test_a_scale_change_throws_the_glyphs_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, "assets/fonts/Roboto-Regular.ttf")
	id := GUI.Font_At(g, family, 16)

	GUI.Font_Warmup(g, id)
	testing.expect_value(t, len(g.glyphs) > 0, true)

	live := GUI.atlas_live_count(g.atlas)

	GUI.GUI_Set_Scale(g, 2)
	testing.expect_value(t, len(g.glyphs), 0)
	testing.expect_value(t, GUI.atlas_live_count(g.atlas) < live, true)

	test_gui_destroy(g)
}

@(test)
test_a_scale_change_throws_the_measurements_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, "assets/fonts/Roboto-Regular.ttf")
	id := GUI.Font_At(g, family, 16)

	GUI.Font_Measure(g, id, "Hello")
	testing.expect_value(t, len(g.measure_cache) > 0, true)

	GUI.GUI_Set_Scale(g, 2)
	testing.expect_value(t, len(g.measure_cache), 0)

	test_gui_destroy(g)
}

@(test)
test_an_image_is_drawn_one_pixel_to_one_pixel :: proc(t: ^testing.T) {
	g := test_gui(t)
	GUI.GUI_Set_Scale(g, 2)

	pixels := make([]u8, 10 * 10 * 4)
	defer delete(pixels)
	for i in 0 ..< len(pixels) {pixels[i] = 255}

	texture := GUI.texture_from_pixels(g, pixels, 10, 10)
	testing.expect_value(t, texture.region.id >= 0, true)

	size := GUI.texture_logical_size(g, texture)
	testing.expect_value(t, size.x, 5.0)
	testing.expect_value(t, size.y, 5.0)

	GUI.draw_list_clear(&g.draw, g.viewport)
	g.draw.scale = g.scale
	g.target = &g.draw
	GUI.draw_texture(g, texture, GUI.Rect{x = 0, y = 0, w = 5, h = 5}, GUI.RGBA(1, 1, 1, 1))

	bounds := scale_test_bounds(&g.draw)
	testing.expect_value(t, bounds.w, 10.0)
	testing.expect_value(t, bounds.h, 10.0)

	test_gui_destroy(g)
}

//* Tests for the table of the constructors of the scene loader: the table
//* is whole, it belongs to the GUI, and a program can put a constructor
//* and a class of its own in it.

//* The kinds of the enum that have no `Make_` procedure of their own, so
//* no constructor in the table of the scene loader either. Every other
//* kind of the enum has both, and the test below says so when one of
//* them is missing.
SCENE_KINDS_WITHOUT_MAKE :: [3]GUI.Widget_Type {
	.Image,
	.ScrollArea,
	.ScrollBar,
}

//* Whether the kind is one of the kinds that have no `Make_` procedure.
scene_kind_without_make :: proc(kind: GUI.Widget_Type) -> bool {
	for other in SCENE_KINDS_WITHOUT_MAKE {
		if other == kind {return true}
	}
	return false
}

//* How many widgets the constructor of the program made. The counter is
//* shared by the tests that use it, and the tests run in more than one
//* thread, so the lock keeps the counter of one test out of the way of
//* the counter of another.
scene_registry_made := 0
scene_registry_lock: sync.Mutex

//* The constructor of the program: it makes a button where a label was
//* asked for, so that the loader can be seen to use it.
scene_registry_constructor :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
) -> GUI.Widget_ID {
	scene_registry_made += 1
	return GUI.Make_Button(g, parent, GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = name}})
}

//* The constructor of the class of the program.
scene_registry_class_constructor :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
) -> GUI.Widget_ID {
	scene_registry_made += 1
	return GUI.Make_Label(g, parent, GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = name}, text = text})
}

//* The child of a widget with a name.
scene_registry_child :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, name: string) -> GUI.Widget_ID {
	w := GUI.Widget_Get(g, id)
	if w == nil {return GUI.INVALID_WIDGET_ID}
	child := w.first_child
	for child != GUI.INVALID_WIDGET_ID {
		c := GUI.Widget_Get(g, child)
		if c == nil {break}
		if c.name == name {return child}
		child = c.next_sibling
	}
	return GUI.INVALID_WIDGET_ID
}

//* == The table is whole ==

@(test)
test_every_kind_of_widget_that_can_be_made_has_a_constructor :: proc(t: ^testing.T) {
	g := test_gui(t)
	GUI.scene_register_defaults(g)

	//* Every kind of the enum that has a `Make_` procedure has a
	//* constructor in the table of the scene loader. A kind that is added
	//* to the enum without one is named here.
	for kind in GUI.Widget_Type {
		if scene_kind_without_make(kind) {continue}
		if 	GUI.Scene_Constructor_Of(g, kind) != nil {continue}
		testing.expectf(
			t,
			false,
			"the kind of widget %q has no constructor in the table of the scene loader",
			GUI.type_name_of(kind),
		)
	}

	test_gui_destroy(g)
}

@(test)
test_the_two_kinds_that_have_no_constructor_have_none :: proc(t: ^testing.T) {
	g := test_gui(t)
	GUI.scene_register_defaults(g)

	//* These two kinds have no `Make_` procedure, so they have no
	//* constructor either.
	testing.expect_value(t, 	GUI.Scene_Constructor_Of(g, .Image) == nil, true)
	testing.expect_value(t, 	GUI.Scene_Constructor_Of(g, .ScrollArea) == nil, true)
	testing.expect_value(t, 	GUI.Scene_Constructor_Of(g, .ScrollBar) == nil, true)

	test_gui_destroy(g)
}

@(test)
test_the_constructor_of_a_kind_makes_a_widget_of_that_kind :: proc(t: ^testing.T) {
	g := test_gui(t)
	GUI.scene_register_defaults(g)

	//* The constructor in the table of a kind makes a widget of that
	//* kind, so that a node of that kind in a file is the widget the
	//* program expects.
	for kind in GUI.Widget_Type {
		if scene_kind_without_make(kind) {continue}
		constructor := 	GUI.Scene_Constructor_Of(g, kind)
		if constructor == nil {continue}

		id := constructor(g, g.root, "made", "text")
		if id == GUI.INVALID_WIDGET_ID {
			testing.expectf(
				t,
				false,
				"the constructor of the kind of widget %q made nothing",
				GUI.type_name_of(kind),
			)
			continue
		}
		w := GUI.Widget_Get(g, id)
		if w == nil {
			testing.expectf(
				t,
				false,
				"the constructor of the kind of widget %q made a widget that is not there",
				GUI.type_name_of(kind),
			)
			continue
		}
		if w.type != kind {
			testing.expectf(
				t,
				false,
				"the constructor of the kind of widget %q made a widget of the kind %q",
				GUI.type_name_of(kind),
				GUI.type_name_of(w.type),
			)
		}
	}

	test_gui_destroy(g)
}

//* == The table belongs to the GUI ==

@(test)
test_the_table_of_the_constructors_belongs_to_the_gui :: proc(t: ^testing.T) {
	sync.mutex_lock(&scene_registry_lock)
	defer sync.mutex_unlock(&scene_registry_lock)
	one := test_gui(t)
	other := test_gui(t)
	scene_registry_made = 0

	//* The constructor of the program goes into the table of one GUI.
	testing.expect_value(t, GUI.Scene_Register_Constructor(one, .Label, scene_registry_constructor), true)
	testing.expect_value(t, GUI.Scene_Constructor_Of(one, .Label) != nil, true)

	//* The other GUI has a table of its own, and the constructor of the
	//* program is not in it.
	testing.expect_value(t, GUI.Scene_Constructor_Of(other, .Label) == nil, true)

	text := `
[node name="Root" type="Panel"]
    [node name="Ok" type="Label" parent="Root"]
`
	//* The loader of the other GUI uses the constructor that is in its
	//* own table, and not the one of the first GUI.
	root := GUI.Scene_Load(other, text)
	testing.expect_value(t, scene_registry_made, 0)
	ok := scene_registry_child(other, root, "Ok")
	testing.expect_value(t, ok != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(other, ok).type, .Label)

	test_gui_destroy(one)
	test_gui_destroy(other)
}

//* == A constructor that is nothing ==

@(test)
test_the_table_refuses_a_constructor_that_is_nothing :: proc(t: ^testing.T) {
	sync.mutex_lock(&scene_registry_lock)
	defer sync.mutex_unlock(&scene_registry_lock)
	g := test_gui(t)
	GUI.scene_register_defaults(g)
	scene_registry_made = 0

	//* A constructor that is nothing is refused.
	testing.expect_value(t, GUI.Scene_Register_Constructor(g, .Panel, nil), false)

	//* The constructor that was there is still there.
	testing.expect_value(t, GUI.Scene_Constructor_Of(g, .Panel) != nil, true)

	//* The constructor of the program takes the place of the one that
	//* was there, and a constructor that is nothing does not take it
	//* away again.
	testing.expect_value(t, GUI.Scene_Register_Constructor(g, .Panel, scene_registry_constructor), true)
	testing.expect_value(t, GUI.Scene_Register_Constructor(g, .Panel, nil), false)
	testing.expect_value(t, GUI.Scene_Constructor_Of(g, .Panel) != nil, true)

	text := `
[node name="Root" type="Panel"]
`
	root := GUI.Scene_Load(g, text)
	//* The constructor that is in the table is the one that is used.
	testing.expect_value(t, scene_registry_made, 1)
	testing.expect_value(t, GUI.Widget_Get(g, root).type, .Button)

	test_gui_destroy(g)
}

//* == A class of the program ==

@(test)
test_a_class_of_the_program_can_be_used_by_a_scene_file :: proc(t: ^testing.T) {
	sync.mutex_lock(&scene_registry_lock)
	defer sync.mutex_unlock(&scene_registry_lock)
	g := test_gui(t)
	scene_registry_made = 0

	class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "RegistryGauge",
		type = .Label,
		constructor = scene_registry_class_constructor,
	})
	testing.expect_value(t, GUI.Widget_Class_Name(g, class), "RegistryGauge")

	text := `
[node name="Root" type="Panel"]
    [node name="Gauge" type="RegistryGauge" parent="Root"]
        text = "hello"
`
	root, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	//* The class was found by its name, so nothing is wrong with the
	//* file.
	testing.expect_value(t, len(report.entries), 0)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)

	//* The constructor of the class made the widget.
	testing.expect_value(t, scene_registry_made, 1)
	gauge := scene_registry_child(g, root, "Gauge")
	testing.expect_value(t, gauge != GUI.INVALID_WIDGET_ID, true)
	#partial switch d in GUI.Widget_Get(g, gauge).data {
	case GUI.Label_Data:
		testing.expect_value(t, d.text, "hello")
	}

	test_gui_destroy(g)
}

//* Tests for the writer of scene files: the tree that is written is the
//* tree that is read again.

//* A scene that uses every property the loader understands.
SCENE_SAVE_TEST_SCENE :: `
# The window of the program.
[node name="Root" type="Panel"]
    anchors = {0, 0, 1, 1}
    offsets = {0, 0, 0, 0}
    bg = {0.1, 0.2, 0.3, 1}
    border = {0.4, 0.5, 0.6, 1}
    border_width = 2
    padding = {4, 5, 6, 7}
    colour = {0.8, 0.9, 1, 1}
    font_size = 18
    visible = false
    min_size = {10, 20}
    custom_min_size = {30, 40}

    [node name="Title" type="Label" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {20, 20, -20, 56}
        text = "Hello"
        font_size = 24
        colour = {0.9, 0.9, 0.95, 1}

    [node name="Ok" type="Button" parent="Root"]
        text = "OK"
        bg = {0.2, 0.2, 0.2, 1}

    [node name="Field" type="TextInput" parent="Root"]
        text = "typed"

    [node name="Box" type="VBox" parent="Root"]
        anchors = {0, 0, 0, 1}
        offsets = {0, 0, 200, 0}

        [node name="InBox" type="Label" parent="Box"]
            text = "In the box"

    [node name="Fill" type="ColorRect" parent="Root"]
        bg = {0.9, 0.1, 0.1, 1}
`

//* The text of a widget, the way the file holds it.
scene_save_test_text :: proc(w: ^GUI.Widget) -> string {
	#partial switch d in w.data {
	case GUI.Label_Data:
		return d.text
	case GUI.Button_Data:
		return d.text
	case GUI.Text_Box_Data:
		return d.text
	}
	return ""
}

//* The fill of a colour rectangle.
scene_save_test_fill :: proc(w: ^GUI.Widget) -> GUI.Colour {
	#partial switch d in w.data {
	case GUI.Color_Rect_Data:
		return d.colour
	}
	return {}
}

//* Compares two widgets property by property. The name of the property
//* that is not the same is put in `property`, and the widgets are the
//* same when it is left empty.
scene_save_test_same_widget :: proc(g: ^GUI.GUI, a: GUI.Widget_ID, b: GUI.Widget_ID, property: ^string) -> bool {
	aw := GUI.Widget_Get(g, a)
	bw := GUI.Widget_Get(g, b)
	if aw == nil || bw == nil {
		property^ = "the widget"
		return false
	}
	if aw.type != bw.type {
		property^ = "the kind of the widget"
		return false
	}
	if aw.name != bw.name {
		property^ = "the name of the widget"
		return false
	}
	if aw.anchors != bw.anchors {
		property^ = "anchors"
		return false
	}
	if aw.offsets != bw.offsets {
		property^ = "offsets"
		return false
	}
	if scene_save_test_text(aw) != scene_save_test_text(bw) {
		property^ = "text"
		return false
	}

	afields := GUI.style_fields_of(&aw.style)
	bfields := GUI.style_fields_of(&bw.style)

	//* The background of a colour rectangle is its fill.
	if aw.type == .ColorRect {
		if scene_save_test_fill(aw) != scene_save_test_fill(bw) {
			property^ = "bg"
			return false
		}
	} else {
		if (.BG in afields) != (.BG in bfields) {
			property^ = "bg"
			return false
		}
		if .BG in afields && aw.style.box.bg_color != bw.style.box.bg_color {
			property^ = "bg"
			return false
		}
	}

	//* The border of the file has one colour for the four sides.
	if (.Border in afields) != (.Border in bfields) {
		property^ = "border"
		return false
	}
	if .Border in afields && aw.style.box.border_color[0] != bw.style.box.border_color[0] {
		property^ = "border"
		return false
	}

	if (.Border_Width in afields) != (.Border_Width in bfields) {
		property^ = "border_width"
		return false
	}
	if .Border_Width in afields && aw.style.box.border_width[0] != bw.style.box.border_width[0] {
		property^ = "border_width"
		return false
	}

	if (.Padding in afields) != (.Padding in bfields) {
		property^ = "padding"
		return false
	}
	if .Padding in afields && aw.style.box.content_margin != bw.style.box.content_margin {
		property^ = "padding"
		return false
	}

	atext := GUI.text_fields_of(&aw.style.text)
	btext := GUI.text_fields_of(&bw.style.text)
	if (.Colour in atext) != (.Colour in btext) {
		property^ = "colour"
		return false
	}
	if .Colour in atext && aw.style.text.colour != bw.style.text.colour {
		property^ = "colour"
		return false
	}
	if (.Size in atext) != (.Size in btext) {
		property^ = "font_size"
		return false
	}
	if .Size in atext && aw.style.text.size != bw.style.text.size {
		property^ = "font_size"
		return false
	}

	//* The family of the fonts of the text.
	if (.Family in atext) != (.Family in btext) {
		property^ = "font"
		return false
	}
	if .Family in atext && aw.style.text.family != bw.style.text.family {
		property^ = "font"
		return false
	}

	if (.Visible in aw.state) != (.Visible in bw.state) {
		property^ = "visible"
		return false
	}
	if aw.base_min_size != bw.base_min_size {
		property^ = "min_size"
		return false
	}
	if aw.custom_min_size != bw.custom_min_size {
		property^ = "custom_min_size"
		return false
	}
	return true
}

//* Compares two trees: the shape of them, the name of every widget and
//* every property the file holds. The name of the property that is not
//* the same is put in `property`.
scene_save_test_same_tree :: proc(g: ^GUI.GUI, a: GUI.Widget_ID, b: GUI.Widget_ID, property: ^string) -> bool {
	aw := GUI.Widget_Get(g, a)
	bw := GUI.Widget_Get(g, b)
	if aw == nil || bw == nil {
		property^ = "the widget"
		return false
	}

	if !scene_save_test_same_widget(g, a, b, property) {return false}

	//* The parent of every widget is the same.
	aname := ""
	bname := ""
	if aw.parent != GUI.INVALID_WIDGET_ID {
		if p := GUI.Widget_Get(g, aw.parent); p != nil {aname = p.name}
	}
	if bw.parent != GUI.INVALID_WIDGET_ID {
		if p := GUI.Widget_Get(g, bw.parent); p != nil {bname = p.name}
	}
	if aname != bname {
		property^ = "the parent of the widget"
		return false
	}

	//* The children are the same and they are in the same order.
	achild := aw.first_child
	bchild := bw.first_child
	for achild != GUI.INVALID_WIDGET_ID {
		if bchild == GUI.INVALID_WIDGET_ID {
			property^ = "a child that is missing"
			return false
		}
		ac := GUI.Widget_Get(g, achild)
		bc := GUI.Widget_Get(g, bchild)
		if ac == nil || bc == nil {
			property^ = "a child that is not there"
			return false
		}
		if !scene_save_test_same_tree(g, achild, bchild, property) {return false}
		achild = ac.next_sibling
		bchild = bc.next_sibling
	}
	if bchild != GUI.INVALID_WIDGET_ID {
		property^ = "a child that is too many"
		return false
	}
	return true
}

//* The tree of the scene above, made in code with the procedures of the
//* toolkit and with the setters. The text of the title is set in the
//* family of the fonts that is given.
scene_save_test_make_tree :: proc(g: ^GUI.GUI, family: GUI.Font_Family_ID) -> GUI.Widget_ID {
	root := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{
			name = "Root",
			preset = .Fill,
			offsets = GUI.Offset{0, 0, 0, 0},
			hidden = true,
			min_size = GUI.Vec2{10, 20},
			style = GUI.Style {
				box = GUI.StyleBox {
					bg_color = GUI.RGBA(0.1, 0.2, 0.3, 1),
					border_color = {
						GUI.RGBA(0.4, 0.5, 0.6, 1),
						GUI.RGBA(0.4, 0.5, 0.6, 1),
						GUI.RGBA(0.4, 0.5, 0.6, 1),
						GUI.RGBA(0.4, 0.5, 0.6, 1),
					},
					border_width = {2, 2, 2, 2},
					content_margin = {4, 5, 6, 7},
				},
				text = GUI.Text_Style {
					colour = GUI.RGBA(0.8, 0.9, 1, 1),
					size = 18,
				},
			},
		}},
	)
	GUI.Widget_Set_Custom_Min_Size(g, root, GUI.Vec2{30, 40})

	title := GUI.Make_Label(
		g,
		root,
		GUI.Label_Opts {
			Base_Opts = GUI.Base_Opts{
				name = "Title",
				preset = .Top,
				offsets = GUI.Offset{20, 20, -20, 56},
			},
			text = "Hello",
		},
	)
	GUI.Widget_Set_Style(
		g,
		title,
		GUI.Style {
			text = GUI.Text_Style {
				colour = GUI.RGBA(0.9, 0.9, 0.95, 1),
				size = 24,
				family = family,
			},
		},
	)

	GUI.Make_Button(
		g,
		root,
		GUI.Button_Opts {
			Base_Opts = GUI.Base_Opts{
				name = "Ok",
				style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.2, 0.2, 0.2, 1)}},
			},
			text = "OK",
		},
	)

	GUI.Make_Text_Box(
		g,
		root,
		GUI.Text_Box_Opts {
			Base_Opts = GUI.Base_Opts{name = "Field"},
			text = "typed",
		},
	)

	box := GUI.Make_VBox(
		g,
		root,
		GUI.Box_Opts{Base_Opts = GUI.Base_Opts{
			name = "Box",
			preset = .Left,
			offsets = GUI.Offset{0, 0, 200, 0},
		}},
	)
	GUI.Make_Label(
		g,
		box,
		GUI.Label_Opts {
			Base_Opts = GUI.Base_Opts{name = "InBox"},
			text = "In the box",
		},
	)

	GUI.Make_Color_Rect(
		g,
		root,
		GUI.Color_Rect_Opts {
			Base_Opts = GUI.Base_Opts{name = "Fill"},
			colour = GUI.RGBA(0.9, 0.1, 0.1, 1),
		},
	)

	return root
}

//* The class of a widget of a program of its own.
scene_save_test_class :: proc(g: ^GUI.GUI) -> GUI.Widget_Class_ID {
	return GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Dial",
		type = .Panel,
		constructor = scene_save_test_constructor,
	})
}

//* How a scene file makes a dial.
scene_save_test_constructor :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
) -> GUI.Widget_ID {
	id, found := GUI.class_by_name(g, "Dial")
	if !found {return GUI.INVALID_WIDGET_ID}
	return GUI.Make_Custom_Widget(g, parent, id, GUI.Base_Opts{name = name})
}

//* == The round trip ==

@(test)
test_every_property_of_a_scene_survives_the_round_trip :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.Scene_Load(g, SCENE_SAVE_TEST_SCENE)
	testing.expect_value(t, first != GUI.INVALID_WIDGET_ID, true)

	saved := GUI.Scene_Save(g, first)
	defer delete(saved)

	second := GUI.Scene_Load(g, saved)
	testing.expect_value(t, second != GUI.INVALID_WIDGET_ID, true)

	property: string
	testing.expect_value(t, scene_save_test_same_tree(g, first, second, &property), true)
	//* When the trees are not the same, the property that is not the
	//* same is said.
	testing.expect_value(t, property, "")

	test_gui_destroy(g)
}

@(test)
test_a_tree_made_in_code_survives_the_round_trip :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes, err := os.read_entire_file_from_path("assets/fonts/Roboto-Regular.ttf", context.allocator)
	testing.expect_value(t, err == nil, true)
	defer delete(bytes)
	family := GUI.Font_Family_Add(g, "Roboto", bytes)

	root := scene_save_test_make_tree(g, family)

	saved := GUI.Scene_Save(g, root)
	defer delete(saved)

	loaded := GUI.Scene_Load(g, saved)
	testing.expect_value(t, loaded != GUI.INVALID_WIDGET_ID, true)

	property: string
	testing.expect_value(t, scene_save_test_same_tree(g, root, loaded, &property), true)
	testing.expect_value(t, property, "")

	test_gui_destroy(g)
}

@(test)
test_the_text_of_a_scene_is_the_same_the_second_time :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.Scene_Load(g, SCENE_SAVE_TEST_SCENE)
	saved_once := GUI.Scene_Save(g, first)
	defer delete(saved_once)

	second := GUI.Scene_Load(g, saved_once)
	saved_twice := GUI.Scene_Save(g, second)
	defer delete(saved_twice)

	testing.expect_value(t, saved_once, saved_twice)

	test_gui_destroy(g)
}

@(test)
test_the_file_that_is_written_has_nothing_wrong_with_it :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.Scene_Load(g, SCENE_SAVE_TEST_SCENE)
	saved := GUI.Scene_Save(g, first)
	defer delete(saved)

	_, report := GUI.Scene_Load_Report(g, saved)
	defer GUI.Scene_Report_Destroy(&report)

	testing.expect_value(t, GUI.Scene_Report_Has_Errors(&report), false)
	testing.expect_value(t, len(report.entries), 0)

	test_gui_destroy(g)
}

//* == The names ==

@(test)
test_two_widgets_with_the_same_name_get_a_name_of_their_own_in_the_file :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* Two buttons of the same name: the loader wants the name of a
	//* node to be used once in the file.
	root := GUI.Make_Panel(g, g.root, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "Root"}})
	GUI.Make_Button(g, root, GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = "Ok"}, text = "OK"})
	GUI.Make_Button(g, root, GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = "Ok"}, text = "OK"})

	saved := GUI.Scene_Save(g, root)
	defer delete(saved)

	//* The second one gets a number after its name.
	testing.expect_value(t, strings.index(saved, "name=\"Ok\"") >= 0, true)
	testing.expect_value(t, strings.index(saved, "name=\"Ok2\"") >= 0, true)

	//* The file has nothing wrong with it.
	_, report := GUI.Scene_Load_Report(g, saved)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	//* The widgets of the GUI keep the name they have.
	child := GUI.Widget_Get(g, root).first_child
	testing.expect_value(t, GUI.Widget_Get(g, child).name, "Ok")
	child = GUI.Widget_Get(g, child).next_sibling
	testing.expect_value(t, GUI.Widget_Get(g, child).name, "Ok")

	test_gui_destroy(g)
}

@(test)
test_a_widget_of_a_kind_with_no_constructor_is_left_out_of_the_file :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* An image has no constructor, so the loader cannot make it again.
	root := GUI.Make_Panel(g, g.root, GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{name = "Root"}})
	GUI.New_Widget(g, .Image, root, GUI.Widget_Opts{name = "Picture"})
	GUI.Make_Label(g, root, GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "Title"}, text = "Hello"})

	saved := GUI.Scene_Save(g, root)
	defer delete(saved)

	//* The image is not in the file, and the label is.
	testing.expect_value(t, strings.index(saved, "Picture") < 0, true)
	testing.expect_value(t, strings.index(saved, "Title") >= 0, true)

	//* The file has nothing wrong with it.
	_, report := GUI.Scene_Load_Report(g, saved)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_of_a_class_without_a_constructor_is_written_as_the_kind_of_the_widget :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A class of the program without a constructor of its own: the
	//* loader falls back on the kind of widget whose name is the same,
	//* and the file says the kind of the widget.
	class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Dial",
		type = .Panel,
	})
	dial := GUI.Make_Custom_Widget(g, g.root, class, GUI.Base_Opts{name = "dial"})

	saved := GUI.Scene_Save(g, dial)
	defer delete(saved)

	testing.expect_value(t, strings.index(saved, "type=\"Dial\"") < 0, true)
	testing.expect_value(t, strings.index(saved, "type=\"Panel\"") >= 0, true)

	//* The file has nothing wrong with it.
	_, report := GUI.Scene_Load_Report(g, saved)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	test_gui_destroy(g)
}

@(test)
test_the_marks_in_a_text_survive_the_round_trip :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A text with the marks that have to be worked out in the file.
	text := "a \\ and\na line\ta tab\ra return"
	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "Marked"}, text = text},
	)
	saved := GUI.Scene_Save(g, label)
	defer delete(saved)

	//* The marks are worked out in the file.
	testing.expect_value(t, strings.index(saved, "\\\\") >= 0, true)
	testing.expect_value(t, strings.index(saved, "\\n") >= 0, true)
	testing.expect_value(t, strings.index(saved, "\\t") >= 0, true)
	testing.expect_value(t, strings.index(saved, "\\r") >= 0, true)

	loaded := GUI.Scene_Load(g, saved)
	testing.expect_value(t, loaded != GUI.INVALID_WIDGET_ID, true)

	#partial switch d in GUI.Widget_Get(g, loaded).data {
	case GUI.Label_Data:
		testing.expect_value(t, d.text, text)
	}

	test_gui_destroy(g)
}

@(test)
test_a_quote_in_a_text_is_written_escaped :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* The writer works the quote out, so that the file says what it
	//* means, and the loader reads the text again.
	label := GUI.Make_Label(g, g.root, GUI.Label_Opts{text = "a \"quote\""})
	saved := GUI.Scene_Save(g, label)
	defer delete(saved)

	testing.expect_value(t, strings.index(saved, "text = \"a \\\"quote\\\"\"") >= 0, true)

	loaded := GUI.Scene_Load(g, saved)
	testing.expect_value(t, loaded != GUI.INVALID_WIDGET_ID, true)
	#partial switch d in GUI.Widget_Get(g, loaded).data {
	case GUI.Label_Data:
		testing.expect_value(t, d.text, "a \"quote\"")
	}

	test_gui_destroy(g)
}

@(test)
test_a_widget_with_no_name_is_given_one :: proc(t: ^testing.T) {
	g := test_gui(t)

	label := GUI.Make_Label(g, g.root, GUI.Label_Opts{text = "Hello"})
	saved := GUI.Scene_Save(g, label)
	defer delete(saved)

	//* The name is the name of the kind of the widget and a number.
	testing.expect_value(t, strings.index(saved, "name=\"Label1\"") >= 0, true)

	_, report := GUI.Scene_Load_Report(g, saved)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_of_a_class_of_the_program_keeps_the_name_of_the_class :: proc(t: ^testing.T) {
	g := test_gui(t)

	class := scene_save_test_class(g)
	dial := GUI.Make_Custom_Widget(g, g.root, class, GUI.Base_Opts{name = "dial"})
	saved := GUI.Scene_Save(g, dial)
	defer delete(saved)

	testing.expect_value(t, strings.index(saved, "type=\"Dial\"") >= 0, true)

	//* The file can be read again: the class is the one that makes the
	//* widget.
	_, report := GUI.Scene_Load_Report(g, saved)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	test_gui_destroy(g)
}

//* == The families of the fonts ==

@(test)
test_the_family_of_the_fonts_survives_the_round_trip :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes, err := os.read_entire_file_from_path("assets/fonts/Roboto-Regular.ttf", context.allocator)
	testing.expect_value(t, err == nil, true)
	defer delete(bytes)
	family := GUI.Font_Family_Add(g, "Roboto", bytes)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts {
			Base_Opts = GUI.Base_Opts{
				name = "Title",
				style = GUI.Style{text = GUI.Text_Style{family = family}},
			},
			text = "Hello",
		},
	)

	saved := GUI.Scene_Save(g, label)
	defer delete(saved)
	//* The file names the family of the fonts.
	testing.expect_value(t, strings.index(saved, "font = \"Roboto\"") >= 0, true)

	loaded := GUI.Scene_Load(g, saved)
	testing.expect_value(t, loaded != GUI.INVALID_WIDGET_ID, true)
	//* The widget of the new tree has the same family.
	testing.expect_value(t, GUI.Widget_Get(g, loaded).style.text.family, family)

	test_gui_destroy(g)
}

//* == The file ==

@(test)
test_a_scene_can_be_written_to_a_file :: proc(t: ^testing.T) {
	g := test_gui(t)

	root := GUI.Scene_Load(g, SCENE_SAVE_TEST_SCENE)
	saved := GUI.Scene_Save(g, root)
	defer delete(saved)

	dir, dir_err := os.temp_directory(context.allocator)
	testing.expect_value(t, dir_err == nil, true)
	defer delete(dir)

	path, path_err := filepath.join({dir, "calcui_scene_save_test.scene"})
	testing.expect_value(t, path_err == nil, true)
	defer delete(path)

	testing.expect_value(t, GUI.Scene_Save_File(g, root, path), true)

	bytes, read_err := os.read_entire_file(path, context.allocator)
	testing.expect_value(t, read_err == nil, true)
	defer delete(bytes)

	testing.expect_value(t, string(bytes), saved)

	remove_err := os.remove(path)
	testing.expect_value(t, remove_err == nil, true)

	test_gui_destroy(g)
}

@(test)
test_a_tree_that_is_not_there_gives_back_nothing :: proc(t: ^testing.T) {
	g := test_gui(t)

	saved := GUI.Scene_Save(g, GUI.INVALID_WIDGET_ID)
	defer delete(saved)
	testing.expect_value(t, saved, "")

	//* The path is in the temporary directory of the machine, so that
	//* nothing is written in the working directory.
	dir, dir_err := os.temp_directory(context.allocator)
	testing.expect_value(t, dir_err == nil, true)
	defer delete(dir)

	path, path_err := filepath.join({dir, "calcui_scene_save_nothing.scene"})
	testing.expect_value(t, path_err == nil, true)
	defer delete(path)

	testing.expect_value(t, GUI.Scene_Save_File(g, GUI.INVALID_WIDGET_ID, path), false)

	test_gui_destroy(g)
}

//* Tests for the scene file loader and for the default theme.

child_by_name :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, name: string) -> GUI.Widget_ID {
	w := GUI.Widget_Get(g, id)
	if w == nil {return GUI.INVALID_WIDGET_ID}
	child := w.first_child
	for child != GUI.INVALID_WIDGET_ID {
		c := GUI.Widget_Get(g, child)
		if c == nil {break}
		if c.name == name {return child}
		child = c.next_sibling
	}
	return GUI.INVALID_WIDGET_ID
}

//* The first thing of a report that is about a property.
scene_entry_of_property :: proc(report: GUI.Scene_Report, property: string) -> (GUI.Scene_Diagnostic, bool) {
	for entry in report.entries {
		if entry.property == property {return entry, true}
	}
	return {}, false
}

//* The first error of a report.
scene_first_error :: proc(report: GUI.Scene_Report) -> (GUI.Scene_Diagnostic, bool) {
	for entry in report.entries {
		if entry.severity == .Error {return entry, true}
	}
	return {}, false
}

//* Whether a message of a report says a word.
scene_message_says :: proc(message: string, word: string) -> bool {
	return strings.index(message, word) >= 0
}

//* The constructor of a program: it makes a button where a label was
//* asked for, so that the loader can be seen to use it.
scene_test_made := 0
scene_test_other_made := 0
scene_test_lock: sync.Mutex

scene_test_constructor :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
) -> GUI.Widget_ID {
	scene_test_made += 1
	return GUI.Make_Button(g, parent, GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = name}, text = text})
}

//* The constructor that takes the place of the one before.
scene_test_other_constructor :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	text: string,
) -> GUI.Widget_ID {
	scene_test_other_made += 1
	return GUI.Make_Button(g, parent, GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = name}, text = text})
}


@(test)
test_a_scene_makes_the_widgets_it_says :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	text := `
# The window of the program.
[node name="Root" type="Panel"]
    anchors = {0, 0, 1, 1}
    offsets = {0, 0, 0, 0}
    bg = {0.11, 0.12, 0.15, 1}

    [node name="Title" type="Label" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {12, 12, -12, 40}
        text = "Hello"
        font_size = 28
        colour = {0.9, 0.9, 0.95, 1}

    [node name="Ok" type="Button" parent="Root"]
        text = "OK"
`
	root := GUI.Scene_Load(g, text)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)

	w := GUI.Widget_Get(g, root)
	testing.expect_value(t, w.name, "Root")
	testing.expect_value(t, w.type, .Panel)
	testing.expect_value(t, w.parent, g.root)
	testing.expect_value(t, GUI.Widget_Child_Count(g, root), 2)

	//* The background of the file is the background of the panel.
	testing.expect_value(t, w.style.box.bg_color, GUI.RGBA(0.11, 0.12, 0.15, 1))
	//* The anchors and the offsets place the panel in its parent.
	testing.expect_value(t, w.anchors, GUI.Anchor{0, 0, 1, 1})
	testing.expect_value(t, w.offsets, GUI.Offset{0, 0, 0, 0})

	title := child_by_name(g, root, "Title")
	testing.expect_value(t, title != GUI.INVALID_WIDGET_ID, true)
	tw := GUI.Widget_Get(g, title)
	testing.expect_value(t, tw.type, .Label)
	testing.expect_value(t, tw.parent, root)
	testing.expect_value(t, tw.style.text.colour, GUI.RGBA(0.9, 0.9, 0.95, 1))
	testing.expect_value(t, tw.style.text.size, 28.0)
	testing.expect_value(t, tw.anchors, GUI.Anchor{0, 0, 1, 0})
	testing.expect_value(t, tw.offsets, GUI.Offset{12, 12, -12, 40})
	#partial switch d in tw.data {
	case GUI.Label_Data:
		testing.expect_value(t, d.text, "Hello")
	}

	button := child_by_name(g, root, "Ok")
	testing.expect_value(t, button != GUI.INVALID_WIDGET_ID, true)
	bw := GUI.Widget_Get(g, button)
	testing.expect_value(t, bw.type, .Button)
	#partial switch d in bw.data {
	case GUI.Button_Data:
		testing.expect_value(t, d.text, "OK")
	}

	test_gui_destroy(g)
}

@(test)
test_a_scene_gives_the_widgets_their_border_and_their_padding :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    border = {0.2, 0.3, 0.4, 1}
    border_width = 2
    padding = {4, 6, 8, 10}
`
	root := GUI.Scene_Load(g, text)
	w := GUI.Widget_Get(g, root)
	testing.expect_value(t, w.style.box.border_color[0], GUI.RGBA(0.2, 0.3, 0.4, 1))
	testing.expect_value(t, w.style.box.border_width[0], 2.0)
	testing.expect_value(t, w.style.box.border_width[3], 2.0)
	testing.expect_value(t, w.style.box.content_margin[0], 4.0)
	testing.expect_value(t, w.style.box.content_margin[1], 6.0)
	testing.expect_value(t, w.style.box.content_margin[2], 8.0)
	testing.expect_value(t, w.style.box.content_margin[3], 10.0)

	test_gui_destroy(g)
}

@(test)
test_a_scene_skips_a_line_it_does_not_know :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    a_key_of_a_newer_version = {1, 2, 3}

    [node name="Ok" type="Button" parent="Root"]
        text = "OK"
`
	root := GUI.Scene_Load(g, text)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, root), 1)
	testing.expect_value(t, child_by_name(g, root, "Ok") != GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_skips_a_widget_it_cannot_make :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Alien" type="Alien" parent="Root"]
        [node name="Ok" type="Button" parent="Alien"]
            text = "OK"
`
	root := GUI.Scene_Load(g, text)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)
	//* The alien was skipped, so the button under it went to the panel
	//* the alien would have hung under.
	testing.expect_value(t, child_by_name(g, root, "Alien") == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, child_by_name(g, root, "Ok") != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, root), 1)

	test_gui_destroy(g)
}

@(test)
test_a_scene_makes_a_node_whose_parent_comes_later :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Ok" type="Button" parent="Root"]
    text = "OK"

[node name="Root" type="Panel"]
`
	root := GUI.Scene_Load(g, text)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)
	//* The panel is the root of the scene, and the button is under it.
	testing.expect_value(t, GUI.Widget_Get(g, root).type, .Panel)
	testing.expect_value(t, GUI.Widget_Child_Count(g, root), 1)
	testing.expect_value(t, child_by_name(g, root, "Ok") != GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_makes_a_node_whose_parent_is_waiting_too :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* The node at the top waits for a node that waits as well, so the
	//* loader has to go on until it makes no more progress.
	text := `
[node name="A" type="Button" parent="B"]
[node name="B" type="Button" parent="C"]
[node name="C" type="Panel"]
`
	root := GUI.Scene_Load(g, text)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(g, root).type, .Panel)

	//* Every node of the file was made.
	b := child_by_name(g, root, "B")
	testing.expect_value(t, b != GUI.INVALID_WIDGET_ID, true)
	a := child_by_name(g, b, "A")
	testing.expect_value(t, a != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(g, a).parent, b)

	//* Nothing is wrong with the file.
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	test_gui_destroy(g)
}

@(test)
test_a_scene_can_hide_a_widget_and_give_it_a_size :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Hidden" type="Label" parent="Root"]
        visible = false
        text = "gone"
    [node name="Sized" type="Label" parent="Root"]
        min_size = {120, 30}
        custom_min_size = {200, 40}
`
	root := GUI.Scene_Load(g, text)
	hidden := child_by_name(g, root, "Hidden")
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, hidden).state, false)

	sized := child_by_name(g, root, "Sized")
	sw := GUI.Widget_Get(g, sized)
	testing.expect_value(t, sw.min_size.x, 120.0)
	testing.expect_value(t, sw.min_size.y, 30.0)
	testing.expect_value(t, sw.custom_min_size.x, 200.0)
	testing.expect_value(t, sw.custom_min_size.y, 40.0)

	test_gui_destroy(g)
}

@(test)
test_a_scene_makes_a_widget_that_is_hidden_by_default :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	text := `
[node name="Root" type="Panel"]
    [node name="Field" type="TextInput" parent="Root"]
        text = "hello"
`
	root := GUI.Scene_Load(g, text)
	field := child_by_name(g, root, "Field")
	testing.expect_value(t, field != GUI.INVALID_WIDGET_ID, true)
	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.text, "hello")
	}

	test_gui_destroy(g)
}

@(test)
test_the_widgets_of_a_scene_take_the_theme :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Ok" type="Button" parent="Root"]
        text = "OK"
`
	GUI.default_theme_use(g, true)
	root := GUI.Scene_Load(g, text)
	button := child_by_name(g, root, "Ok")
	testing.expect_value(t, GUI.Widget_Get(g, button).use_theme, true)

	style := GUI.resolved_style(g, GUI.Widget_Get(g, button))
	testing.expect_value(
		t,
		style.box.bg_color,
		g.theme.types[.Button].styleboxes[GUI.THEME_NORMAL].bg_color,
	)

	test_gui_destroy(g)
}

//* == The text of a value ==

@(test)
test_a_text_with_a_quote_in_it_is_read_whole :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Title" type="Label" parent="Root"]
        text = "a \"quote\""
`
	root := GUI.Scene_Load(g, text)
	title := child_by_name(g, root, "Title")
	testing.expect_value(t, title != GUI.INVALID_WIDGET_ID, true)
	#partial switch d in GUI.Widget_Get(g, title).data {
	case GUI.Label_Data:
		testing.expect_value(t, d.text, "a \"quote\"")
	}

	test_gui_destroy(g)
}

@(test)
test_the_name_of_a_node_may_hold_a_quote :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="a \"quote\"" type="Panel"]
`
	doc, report := GUI.Scene_Parse(text, virt.arena_allocator(&g.arena))
	defer GUI.Scene_Doc_Destroy(&doc)
	defer GUI.Scene_Report_Destroy(&report)

	testing.expect_value(t, len(doc.nodes), 1)
	testing.expect_value(t, doc.nodes[0].name, "a \"quote\"")
	testing.expect_value(t, doc.nodes[0].type, "Panel")

	test_gui_destroy(g)
}

@(test)
test_a_quote_behind_two_backslashes_ends_the_value :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* Two backslashes are a backslash, so the quote behind them ends
	//* the value.
	text := `
[node name="Root" type="Panel"]
    [node name="Title" type="Label" parent="Root"]
        text = "a \\" and more"
`
	root := GUI.Scene_Load(g, text)
	title := child_by_name(g, root, "Title")
	testing.expect_value(t, title != GUI.INVALID_WIDGET_ID, true)
	#partial switch d in GUI.Widget_Get(g, title).data {
	case GUI.Label_Data:
		testing.expect_value(t, d.text, "a \\")
	}

	test_gui_destroy(g)
}

//* == The report of the loader ==

@(test)
test_a_scene_says_of_a_property_it_does_not_know :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    a_key_of_a_newer_version = {1, 2, 3}
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "a_key_of_a_newer_version")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Warning)
	testing.expect_value(t, entry.line, 3)
	testing.expect_value(t, scene_message_says(entry.message, "unknown"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_property_the_kind_of_widget_does_not_use :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    text = "Hello"
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "text")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Warning)
	testing.expect_value(t, entry.line, 3)
	testing.expect_value(t, scene_message_says(entry.message, "not used"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_value_it_cannot_read :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    anchors = {0, 0}
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "anchors")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Warning)
	testing.expect_value(t, entry.line, 3)
	testing.expect_value(t, scene_message_says(entry.message, "numbers"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_border_width_that_is_not_a_number :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    border_width = thick
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "border_width")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Warning)
	testing.expect_value(t, entry.line, 3)
	testing.expect_value(t, scene_message_says(entry.message, "number"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_visible_that_is_not_a_flag :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    visible = maybe
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "visible")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Warning)
	testing.expect_value(t, entry.line, 3)
	testing.expect_value(t, scene_message_says(entry.message, "true"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_node_without_a_type :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "type"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_kind_of_widget_it_does_not_know :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Alien"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "widget"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_kind_of_widget_it_cannot_make :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Image"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "constructor"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_two_nodes_with_the_same_name :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
[node name="Root" type="Panel"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 3)
	testing.expect_value(t, scene_message_says(entry.message, "name"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_parent_that_is_not_in_the_file :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel" parent="Nowhere"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "parent"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_a_node_that_is_its_own_parent :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel" parent="Root"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "parent"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_parents_that_make_a_circle :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="A" type="Panel" parent="B"]
[node name="B" type="Panel" parent="A"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "circle"), true)
	//* The message names every node of the circle.
	testing.expect_value(t, scene_message_says(entry.message, "A"), true)
	testing.expect_value(t, scene_message_says(entry.message, "B"), true)

	test_gui_destroy(g)
}

@(test)
test_a_scene_says_of_every_node_of_a_circle :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="A" type="Panel" parent="B"]
[node name="B" type="Panel" parent="C"]
[node name="C" type="Panel" parent="A"]
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_first_error(report)
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, scene_message_says(entry.message, "circle"), true)
	//* The message names all three nodes of the circle.
	testing.expect_value(t, scene_message_says(entry.message, "A"), true)
	testing.expect_value(t, scene_message_says(entry.message, "B"), true)
	testing.expect_value(t, scene_message_says(entry.message, "C"), true)

	test_gui_destroy(g)
}

@(test)
test_a_valid_scene_has_nothing_to_say :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    anchors = {0, 0, 1, 1}
    offsets = {0, 0, 0, 0}
    bg = {0.11, 0.12, 0.15, 1}
    border = {0.2, 0.2, 0.2, 1}
    border_width = 1
    padding = {4, 4, 4, 4}
    visible = true
    min_size = {10, 10}
    custom_min_size = {20, 20}
    [node name="Title" type="Label" parent="Root"]
        text = "Hello"
        font_size = 20
        colour = {0.9, 0.9, 0.95, 1}
`
	root, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	testing.expect_value(t, len(report.entries), 0)
	testing.expect_value(t, GUI.Scene_Report_Has_Errors(&report), false)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_the_report_of_a_scene_is_text_with_a_line_for_each_thing :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    a_key_of_a_newer_version = {1, 2, 3}
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	text_report := GUI.Scene_Report_To_String(&report, context.allocator)
	defer delete(text_report)
	testing.expect_value(t, strings.index(text_report, "scene:3: warning:") >= 0, true)

	test_gui_destroy(g)
}

//* == A scene that is used more than once ==

//* A copy of a document, so that it can be compared with the document
//* itself. The strings of the copy are copies of the strings of the
//* document, so that the copy says the same thing even when the
//* document is changed.
scene_test_copy_document :: proc(doc: GUI.Scene_Doc) -> GUI.Scene_Doc {
	copy: GUI.Scene_Doc
	copy.allocator = context.allocator
	for node in doc.nodes {
		new_node := node
		new_node.name = strings.clone(node.name)
		new_node.type = strings.clone(node.type)
		new_node.parent = strings.clone(node.parent)
		new_node.text = strings.clone(node.text)
		new_node.font = strings.clone(node.font)
		//* The path of a node without a parent is its name, so it is
		//* not given back a second time.
		if node.path == node.name {
			new_node.path = new_node.name
		} else {
			new_node.path = strings.clone(node.path)
		}
		new_node.properties = make([dynamic]GUI.Scene_Property)
		for property in node.properties {
			append(&new_node.properties, GUI.Scene_Property {
				key   = strings.clone(property.key),
				value = strings.clone(property.value),
				line  = property.line,
			})
		}
		append(&copy.nodes, new_node)
	}
	return copy
}

//* Whether two documents are the same: every node of them is the same
//* field by field.
scene_test_same_document :: proc(a: GUI.Scene_Doc, b: GUI.Scene_Doc) -> bool {
	if len(a.nodes) != len(b.nodes) {return false}
	for index in 0 ..< len(a.nodes) {
		x := a.nodes[index]
		y := b.nodes[index]
		if x.name != y.name {return false}
		if x.type != y.type {return false}
		if x.parent != y.parent {return false}
		if x.text != y.text {return false}
		if x.font != y.font {return false}
		if x.anchors != y.anchors {return false}
		if x.offsets != y.offsets {return false}
		if x.colour != y.colour {return false}
		if x.bg != y.bg {return false}
		if x.border != y.border {return false}
		if x.padding != y.padding {return false}
		if x.min_size != y.min_size {return false}
		if x.custom_min_size != y.custom_min_size {return false}
		if x.border_width != y.border_width {return false}
		if x.font_size != y.font_size {return false}
		if x.visible != y.visible {return false}
		if x.has_anchors != y.has_anchors {return false}
		if x.has_offsets != y.has_offsets {return false}
		if x.has_colour != y.has_colour {return false}
		if x.has_bg != y.has_bg {return false}
		if x.has_border != y.has_border {return false}
		if x.has_border_width != y.has_border_width {return false}
		if x.has_padding != y.has_padding {return false}
		if x.has_min_size != y.has_min_size {return false}
		if x.has_custom_min_size != y.has_custom_min_size {return false}
		if x.has_font_size != y.has_font_size {return false}
		if x.has_font != y.has_font {return false}
		if x.has_visible != y.has_visible {return false}
		if x.line != y.line {return false}
		if x.path != y.path {return false}
		if x.owns_name != y.owns_name {return false}
		if x.skipped != y.skipped {return false}
		if len(x.properties) != len(y.properties) {return false}
		for k in 0 ..< len(x.properties) {
			if x.properties[k].key != y.properties[k].key {return false}
			if x.properties[k].value != y.properties[k].value {return false}
			if x.properties[k].line != y.properties[k].line {return false}
		}
	}
	return true
}

@(test)
test_a_scene_can_be_made_more_than_once :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	text := `
[node name="Root" type="Panel"]
    [node name="Ok" type="Button" parent="Root"]
        text = "OK"
`
	doc, report := GUI.Scene_Parse(text, virt.arena_allocator(&g.arena))
	defer GUI.Scene_Doc_Destroy(&doc)
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)

	//* A copy of the document, to tell whether the loader changed it.
	before := scene_test_copy_document(doc)
	defer GUI.Scene_Doc_Destroy(&before)

	first, first_report := GUI.Scene_Instantiate(g, doc)
	defer GUI.Scene_Report_Destroy(&first_report)
	second, second_report := GUI.Scene_Instantiate(g, doc)
	defer GUI.Scene_Report_Destroy(&second_report)

	testing.expect_value(t, first != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, second != GUI.INVALID_WIDGET_ID, true)
	//* The two trees are made of other widgets.
	testing.expect_value(t, GUI.Widget_Get(g, first) != GUI.Widget_Get(g, second), true)
	testing.expect_value(t, child_by_name(g, first, "Ok") != child_by_name(g, second, "Ok"), true)

	//* Making the tree again does not change the tree that was made
	//* before.
	testing.expect_value(t, GUI.Widget_Child_Count(g, first), 1)
	testing.expect_value(t, GUI.Widget_Get(g, child_by_name(g, first, "Ok")).parent, first)

	//* Making the tree does not change the document either: every node
	//* of it is the same field by field.
	testing.expect_value(t, scene_test_same_document(before, doc), true)

	test_gui_destroy(g)
}

@(test)
test_the_nodes_of_a_scene_have_a_path :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Box" type="VBox" parent="Root"]
        [node name="Ok" type="Button" parent="Box"]
`
	doc, report := GUI.Scene_Parse(text, virt.arena_allocator(&g.arena))
	defer GUI.Scene_Doc_Destroy(&doc)
	defer GUI.Scene_Report_Destroy(&report)

	testing.expect_value(t, len(doc.nodes), 3)
	testing.expect_value(t, doc.nodes[0].path, "Root")
	testing.expect_value(t, doc.nodes[1].path, "Root/Box")
	testing.expect_value(t, doc.nodes[2].path, "Root/Box/Ok")

	test_gui_destroy(g)
}

//* == The memory of a document ==

@(test)
test_a_document_parsed_with_the_heap_gives_its_strings_back :: proc(t: ^testing.T) {
	g := test_gui(t)

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator := mem.tracking_allocator(&tracker)

	text := `
[node name="Root" type="Panel"]
    [node name="Title" type="Label" parent="Root"]
        text = "Hello"
`
	doc, report := GUI.Scene_Parse(text, allocator)

	testing.expect_value(t, len(report.entries), 0)
	testing.expect_value(t, len(doc.nodes), 2)
	testing.expect_value(t, doc.nodes[0].name, "Root")
	testing.expect_value(t, doc.nodes[0].path, "Root")
	testing.expect_value(t, doc.nodes[1].name, "Title")
	testing.expect_value(t, doc.nodes[1].parent, "Root")
	testing.expect_value(t, doc.nodes[1].text, "Hello")
	testing.expect_value(t, doc.nodes[1].path, "Root/Title")

	//* The document and the report give everything back.
	GUI.Scene_Report_Destroy(&report)
	GUI.Scene_Doc_Destroy(&doc)

	//* Every string of the document was given back.
	testing.expect_value(t, tracker.total_free_count > 0, true)
	testing.expect_value(t, tracker.current_memory_allocated, 0)

	mem.tracking_allocator_destroy(&tracker)

	test_gui_destroy(g)
}

@(test)
test_a_document_parsed_in_the_arena_of_the_gui_is_given_back :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Ok" type="Button" parent="Root"]
        text = "OK"
`
	used := g.arena.total_used
	doc, report := GUI.Scene_Parse(text, virt.arena_allocator(&g.arena))
	defer GUI.Scene_Report_Destroy(&report)
	testing.expect_value(t, len(report.entries), 0)
	//* The strings of the document live in the arena of the GUI.
	testing.expect_value(t, g.arena.total_used > used, true)

	root, _ := GUI.Scene_Instantiate(g, doc)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, child_by_name(g, root, "Ok") != GUI.INVALID_WIDGET_ID, true)

	//* The allocator of the arena does nothing when it is asked to
	//* free, so the document is given back when the GUI is shut down.
	GUI.Scene_Doc_Destroy(&doc)

	//* The widgets keep what they need: the loader gave them a copy of
	//* the name and of the text, so the document could be given back.
	ok := child_by_name(g, root, "Ok")
	testing.expect_value(t, GUI.Widget_Get(g, ok).name, "Ok")
	#partial switch d in GUI.Widget_Get(g, ok).data {
	case GUI.Button_Data:
		testing.expect_value(t, d.text, "OK")
	}

	test_gui_destroy(g)
}

@(test)
test_the_report_of_a_parse_gives_its_messages_back :: proc(t: ^testing.T) {
	g := test_gui(t)

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator := mem.tracking_allocator(&tracker)

	//* A file with two warnings: every message of the report is made in
	//* the allocator of the report.
	text := `
[node name="Root" type="Panel"]
    a_key_of_a_newer_version = {1, 2, 3}
    another_key_of_a_newer_version = {4, 5, 6}
`
	doc, report := GUI.Scene_Parse(text, allocator)
	testing.expect_value(t, len(report.entries), 2)

	GUI.Scene_Report_Destroy(&report)
	GUI.Scene_Doc_Destroy(&doc)

	//* Every message of the report was given back.
	testing.expect_value(t, tracker.total_free_count > 0, true)
	testing.expect_value(t, tracker.current_memory_allocated, 0)

	mem.tracking_allocator_destroy(&tracker)

	test_gui_destroy(g)
}

@(test)
test_the_report_of_a_file_is_good_after_the_document_is_given_back :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    a_key_of_a_newer_version = {1, 2, 3}
`
	doc, report := GUI.Scene_Parse(text, context.allocator)
	GUI.Scene_Doc_Destroy(&doc)

	//* The report holds a copy of the name of the node and of the key of
	//* the property, so it is still good after the document is gone.
	entry, found := scene_entry_of_property(report, "a_key_of_a_newer_version")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.node, "Root")
	testing.expect_value(t, entry.property, "a_key_of_a_newer_version")
	testing.expect_value(t, scene_message_says(entry.message, "unknown"), true)

	GUI.Scene_Report_Destroy(&report)

	test_gui_destroy(g)
}

@(test)
test_a_document_made_by_hand_is_not_freed :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A document that was made by hand has no allocator, so its
	//* strings are left alone: they belong to the program that made
	//* them.
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator := mem.tracking_allocator(&tracker)

	name := strings.clone("Root", allocator)
	doc: GUI.Scene_Doc
	append(&doc.nodes, GUI.Scene_Node{name = name})

	GUI.Scene_Doc_Destroy(&doc)

	//* Nothing of the node was given back.
	testing.expect_value(t, tracker.total_free_count, 0)

	//* The program gives its own string back.
	delete(name, allocator)
	testing.expect_value(t, tracker.total_free_count, 1)

	mem.tracking_allocator_destroy(&tracker)

	test_gui_destroy(g)
}

//* == The families of the fonts ==

//* The bytes of the font of the tests.
scene_test_font_bytes :: proc(t: ^testing.T) -> []u8 {
	bytes, err := os.read_entire_file_from_path("assets/fonts/Roboto-Regular.ttf", context.allocator)
	if err != nil {
		testing.fail_now(t, "could not read the test font")
	}
	return bytes
}

@(test)
test_a_node_asks_for_a_family_of_the_fonts :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := scene_test_font_bytes(t)
	defer delete(bytes)
	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	testing.expect_value(t, family != GUI.INVALID_FONT_FAMILY_ID, true)

	text := `
[node name="Root" type="Panel"]
    [node name="Title" type="Label" parent="Root"]
        font = "Roboto"
`
	root := GUI.Scene_Load(g, text)
	title := child_by_name(g, root, "Title")
	testing.expect_value(t, title != GUI.INVALID_WIDGET_ID, true)

	w := GUI.Widget_Get(g, title)
	testing.expect_value(t, w.style.text.family, family)
	testing.expect_value(t, .Family in w.style.text.set, true)

	test_gui_destroy(g)
}

@(test)
test_a_family_that_is_not_there_is_an_error :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := scene_test_font_bytes(t)
	defer delete(bytes)
	family := GUI.Font_Family_Add(g, "Roboto", bytes)
	GUI.default_theme_use(g, true)
	GUI.Theme_Set_Family(g.theme, family)

	text := `
[node name="Root" type="Panel"]
    font = "Nothing"
`
	root, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "font")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Error)
	testing.expect_value(t, entry.line, 2)
	testing.expect_value(t, scene_message_says(entry.message, "Nothing"), true)

	//* The widget takes the font of the theme.
	w := GUI.Widget_Get(g, root)
	testing.expect_value(t, w.style.text.family, GUI.INVALID_FONT_FAMILY_ID)
	testing.expect_value(t, GUI.resolved_style(g, w).text.family, family)

	test_gui_destroy(g)
}

@(test)
test_a_family_with_no_name_is_a_warning :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    font = ""
`
	_, report := GUI.Scene_Load_Report(g, text)
	defer GUI.Scene_Report_Destroy(&report)

	entry, found := scene_entry_of_property(report, "font")
	testing.expect_value(t, found, true)
	testing.expect_value(t, entry.severity, .Warning)
	testing.expect_value(t, entry.line, 2)

	test_gui_destroy(g)
}

@(test)
test_the_family_of_the_gui_is_found_by_its_name :: proc(t: ^testing.T) {
	g := test_gui(t)

	bytes := scene_test_font_bytes(t)
	defer delete(bytes)
	family := GUI.Font_Family_Add(g, "Roboto", bytes)

	testing.expect_value(t, GUI.Font_Family_By_Name(g, "Roboto"), family)
	testing.expect_value(t, GUI.Font_Family_By_Name(g, "Nothing"), GUI.INVALID_FONT_FAMILY_ID)
	testing.expect_value(t, GUI.Font_Family_By_Name(g, ""), GUI.INVALID_FONT_FAMILY_ID)

	test_gui_destroy(g)
}

//* == Finding a widget of a scene ==

@(test)
test_scene_find_finds_a_widget_by_its_path :: proc(t: ^testing.T) {
	g := test_gui(t)

	text := `
[node name="Root" type="Panel"]
    [node name="Box" type="VBox" parent="Root"]
        [node name="Ok" type="Button" parent="Box"]
            text = "OK"
`
	root := GUI.Scene_Load(g, text)

	found := GUI.Scene_Find(g, root, "Root/Box/Ok")
	testing.expect_value(t, found != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(g, found).name, "Ok")

	//* The root of the tree has a path as well.
	testing.expect_value(t, GUI.Scene_Find(g, root, "Root"), root)

	//* A path that is not there gives nothing.
	testing.expect_value(t, GUI.Scene_Find(g, root, "Root/Nothing") == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Scene_Find(g, root, "Other/Box/Ok") == GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

//* == The table of the constructors ==

@(test)
test_a_program_can_register_a_constructor :: proc(t: ^testing.T) {
	sync.mutex_lock(&scene_test_lock)
	defer sync.mutex_unlock(&scene_test_lock)
	g := test_gui(t)
	scene_test_made = 0

	testing.expect_value(t, GUI.Scene_Register_Constructor(g, .Label, scene_test_constructor), true)
	testing.expect_value(t, 	GUI.Scene_Constructor_Of(g, .Label) != nil, true)
	//* A constructor that is nothing is refused.
	testing.expect_value(t, GUI.Scene_Register_Constructor(g, .Label, nil), false)

	text := `
[node name="Root" type="Panel"]
    [node name="Ok" type="Label" parent="Root"]
        text = "OK"
`
	root := GUI.Scene_Load(g, text)
	//* The constructor of the program made the widget.
	testing.expect_value(t, scene_test_made, 1)
	ok := child_by_name(g, root, "Ok")
	testing.expect_value(t, GUI.Widget_Get(g, ok).type, .Button)

	test_gui_destroy(g)
}

@(test)
test_registering_a_constructor_twice_replaces_it :: proc(t: ^testing.T) {
	sync.mutex_lock(&scene_test_lock)
	defer sync.mutex_unlock(&scene_test_lock)
	g := test_gui(t)
	scene_test_made = 0
	scene_test_other_made = 0

	GUI.Scene_Register_Constructor(g, .Label, scene_test_constructor)
	GUI.Scene_Register_Constructor(g, .Label, scene_test_other_constructor)

	text := `
[node name="Root" type="Panel"]
    [node name="Ok" type="Label" parent="Root"]
`
	root := GUI.Scene_Load(g, text)
	//* The constructor that was put in the table last is the one that is
	//* used.
	testing.expect_value(t, scene_test_other_made, 1)
	testing.expect_value(t, scene_test_made, 0)
	testing.expect_value(t, root != GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_kind_of_widget_without_a_constructor_has_none :: proc(t: ^testing.T) {
	g := test_gui(t)
	//* The table of the constructors is filled before it is looked at,
	//* so that a kind that has a constructor is not taken for one that
	//* has none.
	GUI.scene_register_defaults(g)

	//* These two kinds have no `Make_` procedure, so they have no
	//* constructor either.
	testing.expect_value(t, GUI.Scene_Constructor_Of(g, .Image) == nil, true)
	testing.expect_value(t, GUI.Scene_Constructor_Of(g, .ScrollArea) == nil, true)
	//* A kind that has a constructor has one.
	testing.expect_value(t, GUI.Scene_Constructor_Of(g, .Panel) != nil, true)

	test_gui_destroy(g)
}

//* == The theme ==

@(test)
test_the_default_theme_has_a_style_for_every_kind_of_widget :: proc(t: ^testing.T) {
	dark := GUI.default_theme_dark()
	light := GUI.default_theme_light()

	for widget_type in GUI.Widget_Type {
		entries, ok := dark.types[widget_type]
		testing.expect_value(t, ok, true)
		//* The text of a widget has to be readable on the background.
		testing.expect_value(t, entries.text.colour.a > 0, true)

		entries, ok = light.types[widget_type]
		testing.expect_value(t, ok, true)
		testing.expect_value(t, entries.text.colour.a > 0, true)
	}

	GUI.theme_destroy(dark)
	GUI.theme_destroy(light)
}

@(test)
test_a_widget_takes_the_style_of_its_type :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.default_theme_dark()
	GUI.GUI_Set_Theme(g, theme)

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button", use_theme = true})
	style := GUI.resolved_style(g, GUI.Widget_Get(g, button))

	expected := theme.types[.Button].styleboxes[GUI.THEME_NORMAL].bg_color
	testing.expect_value(t, style.box.bg_color, expected)
	//* The corners of a button are rounded.
	testing.expect_value(t, style.box.corner_radius[0] > 0, true)

	//* A widget of another kind has another style.
	label := GUI.New_Widget(g, .Label, g.root, GUI.Widget_Opts{name = "label", use_theme = true})
	label_style := GUI.resolved_style(g, GUI.Widget_Get(g, label))
	testing.expect_value(t, label_style.box.bg_color != style.box.bg_color, true)

	test_gui_destroy(g)
}

@(test)
test_the_panels_of_the_default_theme_have_a_border :: proc(t: ^testing.T) {
	theme := GUI.default_theme_dark()
	box := theme.types[.Panel].styleboxes[GUI.THEME_NORMAL]
	testing.expect_value(t, box.border_width[0] > 0, true)
	testing.expect_value(t, box.border_color[0].a > 0, true)
	GUI.theme_destroy(theme)
}

@(test)
test_the_fields_of_the_default_theme_have_a_background :: proc(t: ^testing.T) {
	theme := GUI.default_theme_dark()
	box := theme.types[.TextBox].styleboxes[GUI.THEME_NORMAL]
	testing.expect_value(t, box.bg_color.a > 0, true)
	GUI.theme_destroy(theme)
}

@(test)
test_the_theme_gives_the_stylebox_and_the_constant_of_a_kind_of_widget :: proc(t: ^testing.T) {
	theme := GUI.default_theme_dark()

	box, has_box := GUI.Theme_Get_Stylebox(theme, .ScrollBar, "track")
	testing.expect_value(t, has_box, true)
	testing.expect_value(t, box.bg_color.a > 0, true)

	_, missing := GUI.Theme_Get_Stylebox(theme, .ScrollBar, "nothing")
	testing.expect_value(t, missing, false)

	width, has_width := GUI.Theme_Get_Constant(theme, .ScrollBar, "width")
	testing.expect_value(t, has_width, true)
	testing.expect_value(t, width, 10.0)

	minimum, has_minimum := GUI.Theme_Get_Constant(theme, .ScrollBar, "grabber_min")
	testing.expect_value(t, has_minimum, true)
	testing.expect_value(t, minimum, 24.0)

	_, missing = GUI.Theme_Get_Constant(theme, .ScrollBar, "nothing")
	testing.expect_value(t, missing, false)

	GUI.theme_destroy(theme)
}


@(test)
test_the_default_theme_can_be_put_on_the_gui :: proc(t: ^testing.T) {
	g := test_gui(t)

	GUI.default_theme_use(g, true)
	testing.expect_value(t, g.theme != nil, true)

	//* The widgets that are already there take the theme.
	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button"})
	GUI.default_theme_apply(g)
	testing.expect_value(t, GUI.Widget_Get(g, button).use_theme, true)

	style := GUI.resolved_style(g, GUI.Widget_Get(g, button))
	testing.expect_value(
		t,
		style.box.bg_color,
		g.theme.types[.Button].styleboxes[GUI.THEME_NORMAL].bg_color,
	)

	GUI.default_theme_use(g, false)
	testing.expect_value(
		t,
		g.theme.types[.Panel].styleboxes[GUI.THEME_NORMAL].bg_color,
		GUI.default_theme_palette_light().surface,
	)

	test_gui_destroy(g)
}

@(test)
test_the_default_theme_makes_a_widget_of_every_kind :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	GUI.default_theme_use(g, true)
	for widget_type in GUI.Widget_Type {
		widget := GUI.New_Widget(g, widget_type, g.root, GUI.Widget_Opts{use_theme = true})
		style := GUI.resolved_style(g, GUI.Widget_Get(g, widget))
		//* Every kind of widget has text that can be read.
		testing.expect_value(t, style.text.colour.a > 0, true)
	}

	test_gui_destroy(g)
}

//* Tests for the font family/size split and for the theme.

FONT_PATH :: "assets/fonts/Roboto-Regular.ttf"

//* == Fonts ==

@(test)
test_font_family_serves_every_size :: proc(t: ^testing.T) {
	g := test_gui(t)

	family := GUI.Font_Family_Load(g, FONT_PATH)
	testing.expect_value(t, family != GUI.INVALID_FONT_FAMILY_ID, true)

	small := GUI.Font_At(g, family, 16)
	large := GUI.Font_At(g, family, 32)
	testing.expect_value(t, small != GUI.INVALID_FONT_ID, true)
	testing.expect_value(t, large != GUI.INVALID_FONT_ID, true)
	testing.expect_value(t, small != large, true)

	//* One parsed file, two size instances, one atlas.
	testing.expect_value(t, len(g.font_files), 1)
	testing.expect_value(t, len(g.font_families), 1)
	testing.expect_value(t, len(g.fonts), 2)
	testing.expect_value(t, GUI.font_get(g, small).file == GUI.font_get(g, large).file, true)

	test_gui_destroy(g)
}

@(test)
test_font_instance_is_cached :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, FONT_PATH)

	a := GUI.Font_At(g, family, 16)
	b := GUI.Font_At(g, family, 16)
	testing.expect_value(t, a, b)

	//* The size is rounded to a half pixel, so a size that moves a
	//* little does not make a new font.
	c := GUI.Font_At(g, family, 16.2)
	testing.expect_value(t, c, a)

	//* Half a pixel more is a different size.
	d := GUI.Font_At(g, family, 16.6)
	testing.expect_value(t, d != a, true)

	test_gui_destroy(g)
}

@(test)
test_font_resolve_follows_the_style :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, FONT_PATH)
	g.default_font_size = 16

	//* A style that names no size gets the GUI's own.
	style := GUI.Text_Style{}
	testing.expect_value(t, GUI.Font_Resolve(g, style), GUI.Font_At(g, family, 16))

	//* A style that names a size gets that one.
	style.size = 24
	testing.expect_value(t, GUI.Font_Resolve(g, style), GUI.Font_At(g, family, 24))

	//* A style that names a family gets that family.
	style.family = family
	style.size = 0
	testing.expect_value(t, GUI.Font_Resolve(g, style), GUI.Font_At(g, family, 16))

	test_gui_destroy(g)
}

@(test)
test_widget_text_size_changes_its_measure :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := GUI.Font_Family_Load(g, FONT_PATH)

	small := GUI.New_Widget(
		g,
		.Label,
		g.root,
		GUI.Widget_Opts {
			name = "small",
			text = "Hello",
			preset = .Top_Left,
			style = GUI.Style{text = GUI.Text_Style{size = 16, family = family}},
		},
	)
	large := GUI.New_Widget(
		g,
		.Label,
		g.root,
		GUI.Widget_Opts {
			name = "large",
			text = "Hello",
			preset = .Top_Left,
			style = GUI.Style{text = GUI.Text_Style{size = 32, family = family}},
		},
	)
	GUI.layout_pass(g)

	sw := GUI.Widget_Get(g, small)
	lw := GUI.Widget_Get(g, large)
	testing.expect_value(t, sw.min_size.x > 0, true)
	testing.expect_value(t, lw.min_size.x > sw.min_size.x, true)
	testing.expect_value(t, lw.min_size.y > sw.min_size.y, true)

	test_gui_destroy(g)
}

//* == The theme ==

@(test)
test_theme_styles_the_widgets_that_ask :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Button, GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.9, 0.1, 0.1, 1)}})
	GUI.GUI_Set_Theme(g, theme)

	themed := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "themed", use_theme = true})
	plain := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "plain",
			style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.1, 0.2, 0.3, 1)}},
		},
	)

	tw := GUI.Widget_Get(g, themed)
	pw := GUI.Widget_Get(g, plain)

	//* The themed widget takes the theme's background.
	testing.expect_value(t, GUI.resolved_style(g, tw).box.bg_color, GUI.RGBA(0.9, 0.1, 0.1, 1))

	//* The other one keeps the style it has.
	testing.expect_value(t, GUI.resolved_style(g, pw).box.bg_color, GUI.RGBA(0.1, 0.2, 0.3, 1))

	test_gui_destroy(g)
}

@(test)
test_widget_style_wins_over_the_theme :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Button, GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.9, 0.1, 0.1, 1)}})
	GUI.GUI_Set_Theme(g, theme)

	button := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "button",
			use_theme = true,
			style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.1, 0.9, 0.1, 1)}},
		},
	)
	testing.expect_value(
		t,
		GUI.resolved_style(g, GUI.Widget_Get(g, button)).box.bg_color,
		GUI.RGBA(0.1, 0.9, 0.1, 1),
	)

	test_gui_destroy(g)
}

@(test)
test_theme_state_changes_the_background :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Button, GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.2, 0.2, 0.2, 1)}})
	GUI.Theme_Set_State(
		theme,
		.Button,
		.Hovered,
		GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.4, 0.4, 0.9, 1)}},
	)
	GUI.GUI_Set_Theme(g, theme)

	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button", use_theme = true})
	w := GUI.Widget_Get(g, button)

	//* Without the pointer the background is the theme's.
	testing.expect_value(t, GUI.resolved_bg(g, button, w), GUI.RGBA(0.2, 0.2, 0.2, 1))

	//* Under the pointer the theme says what the background is.
	g.hot = button
	testing.expect_value(t, GUI.resolved_bg(g, button, w), GUI.RGBA(0.4, 0.4, 0.9, 1))

	test_gui_destroy(g)
}

@(test)
test_theme_variation_wins_over_the_type :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Button, GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.2, 0.2, 0.2, 1)}})
	GUI.Theme_Add_Variation(
		theme,
		"danger",
		.Button,
		GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.8, 0.1, 0.1, 1)}},
	)
	GUI.GUI_Set_Theme(g, theme)

	normal := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "normal", use_theme = true})
	danger := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts{name = "danger", use_theme = true, variation = "danger"},
	)

	testing.expect_value(
		t,
		GUI.resolved_style(g, GUI.Widget_Get(g, normal)).box.bg_color,
		GUI.RGBA(0.2, 0.2, 0.2, 1),
	)
	testing.expect_value(
		t,
		GUI.resolved_style(g, GUI.Widget_Get(g, danger)).box.bg_color,
		GUI.RGBA(0.8, 0.1, 0.1, 1),
	)

	test_gui_destroy(g)
}

@(test)
test_theme_holds_the_text_style :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Label, GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(1, 0, 0, 1), size = 24}})
	GUI.GUI_Set_Theme(g, theme)

	label := GUI.New_Widget(g, .Label, g.root, GUI.Widget_Opts{name = "label", use_theme = true})
	style := GUI.resolved_style(g, GUI.Widget_Get(g, label))
	testing.expect_value(t, style.text.colour, GUI.RGBA(1, 0, 0, 1))
	testing.expect_value(t, style.text.size, 24.0)
	testing.expect_value(t, GUI.resolved_text_colour(g, label, GUI.Widget_Get(g, label)), GUI.RGBA(1, 0, 0, 1))

	test_gui_destroy(g)
}

@(test)
test_disabled_text_colour :: proc(t: ^testing.T) {
	g := test_gui(t)

	button := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "button",
			style = GUI.Style {
				text = GUI.Text_Style {
					colour = GUI.RGBA(1, 1, 1, 1),
					disabled_colour = GUI.RGBA(0.4, 0.4, 0.4, 1),
				},
			},
		},
	)
	w := GUI.Widget_Get(g, button)
	testing.expect_value(t, GUI.resolved_text_colour(g, button, w), GUI.RGBA(1, 1, 1, 1))

	//* A widget that is not enabled draws its text in the disabled
	//* colour.
	w.state -= GUI.Widget_State{.Enabled}
	testing.expect_value(t, GUI.resolved_text_colour(g, button, w), GUI.RGBA(0.4, 0.4, 0.4, 1))

	test_gui_destroy(g)
}

@(test)
test_explicit_set_mask_keeps_a_transparent_background :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(theme, .Button, GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.9, 0.1, 0.1, 1)}})
	GUI.GUI_Set_Theme(g, theme)

	//* A transparent background is the same as no background, unless
	//* the style says that it is set.
	button := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "button",
			use_theme = true,
			style = GUI.Style {
				box = GUI.StyleBox{bg_color = GUI.RGBA(0, 0, 0, 0)},
				set = bit_set[GUI.Style_Field]{.BG},
			},
		},
	)
	testing.expect_value(
		t,
		GUI.resolved_style(g, GUI.Widget_Get(g, button)).box.bg_color,
		GUI.RGBA(0, 0, 0, 0),
	)

	test_gui_destroy(g)
}

//* The tests of the text boxes: the mouse takes the text it goes over,
//* the double click takes a word, and the rules of a box say what may be
//* typed in it.

text_box_content :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> GUI.Rect {
	w := GUI.Widget_Get(g, id)
	if w == nil {return {}}
	return GUI.content_rect(g, w)
}

//* The place on the screen of a character of the text.
text_box_x_of :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, offset: int) -> f32 {
	content := text_box_content(g, id)
	return GUI.text_input_offset_x(g, id, content, offset)
}

//* The place on the screen of a character of the text of the editor.
editor_x_of :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, offset: int) -> GUI.Vec2 {
	w := GUI.Widget_Get(g, id)
	state := GUI.rich_text_editor_state(g, id)
	if w == nil || state == nil {return {}}
	content := GUI.content_rect(g, w)
	ts := GUI.rich_text_editor_text_style(g, w, state)
	lines := GUI.text_lines(g, ts, state.text, content.w)
	box := GUI.Rect {
		x = content.x - state.scroll.x,
		y = content.y - state.scroll.y,
		w = content.w,
		h = content.h,
	}
	x, y, h := GUI.text_place(g, GUI.Font_Of(g, w), box, ts, lines[:], state.text, offset)
	return GUI.Vec2{x, y + h * 0.5}
}

//* The place on the screen of a character of the text of a box of more
//* than one line.
box_x_of :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, offset: int) -> GUI.Vec2 {
	w := GUI.Widget_Get(g, id)
	d := GUI.text_box_data(g, id)
	if w == nil || d == nil {return {}}
	f := GUI.font_get(g, GUI.Font_Of(g, w))
	if f == nil {return {}}
	content := GUI.content_rect(g, w)
	lines := GUI.text_box_lines(g, w, d.text, true, content.w)
	if len(lines) == 0 {return {}}
	index := GUI.text_line_of(lines, d.text, offset)
	if index < 0 {return {}}
	ts := GUI.text_box_text_style(g, w, true)
	y := content.y - d.scroll_y
	for i in 0 ..< index {y += lines[i].height + ts.spacing}
	x := content.x + GUI.text_box_line_caret_x(lines[index], f.scale, offset)
	return GUI.Vec2{x, y + lines[index].height * 0.5}
}

text_box_test_gui :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	return g
}

@(test)
test_a_click_in_a_text_box_puts_the_caret_where_the_pointer_is :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello world", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	GUI.layout_pass(g)

	content := text_box_content(g, field)
	y := content.y + content.h * 0.5
	x := text_box_x_of(g, field, 6)

	append(&g.events, mouse_down({x, y}, 1))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.caret, 6)
		testing.expect_value(t, d.sel_start, d.caret)
		testing.expect_value(t, d.sel_end, d.caret)
	}

	test_gui_destroy(g)
}

@(test)
test_a_drag_in_a_text_box_takes_the_text_it_goes_over :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello world", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	GUI.layout_pass(g)

	content := text_box_content(g, field)
	y := content.y + content.h * 0.5
	from := text_box_x_of(g, field, 2)
	to := text_box_x_of(g, field, 7)

	append(&g.events, mouse_down({from, y}, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({to, y}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({to, y}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 2)
		testing.expect_value(t, d.sel_end, 7)
		testing.expect_value(t, d.caret, 7)
	}

	//* The text that is taken goes away when it is typed over.
	GUI.fire_text(g, field, "X")
	testing.expect_value(t, field_text(g, field), "heXorld")

	test_gui_destroy(g)
}

@(test)
test_a_drag_backwards_takes_the_text_to_the_left :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello world", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	GUI.layout_pass(g)

	content := text_box_content(g, field)
	y := content.y + content.h * 0.5
	from := text_box_x_of(g, field, 8)
	to := text_box_x_of(g, field, 3)

	append(&g.events, mouse_down({from, y}, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({to, y}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({to, y}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 8)
		testing.expect_value(t, d.sel_end, 3)
		testing.expect_value(t, d.caret, 3)
	}

	test_gui_destroy(g)
}

@(test)
test_a_double_click_takes_a_word_and_the_next_one_takes_the_text :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello world", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	GUI.layout_pass(g)

	content := text_box_content(g, field)
	y := content.y + content.h * 0.5
	x := text_box_x_of(g, field, 2)

	append(&g.events, mouse_down({x, y}, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({x, y}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down({x, y}, 2))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({x, y}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, 5)
	}

	//* The double click that follows takes all of the text.
	append(&g.events, mouse_down({x, y}, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({x, y}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down({x, y}, 2))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({x, y}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, len(d.text))
		testing.expect_value(t, d.caret, len(d.text))
	}

	test_gui_destroy(g)
}

@(test)
test_a_double_click_on_another_word_takes_that_word :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello world", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	GUI.layout_pass(g)

	content := text_box_content(g, field)
	y := content.y + content.h * 0.5
	first := text_box_x_of(g, field, 2)
	second := text_box_x_of(g, field, 8)

	append(&g.events, mouse_down({first, y}, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down({first, y}, 2))
	GUI.Handle_Events(g)

	append(&g.events, mouse_down({second, y}, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down({second, y}, 2))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 6)
		testing.expect_value(t, d.sel_end, 11)
	}

	test_gui_destroy(g)
}

@(test)
test_ctrl_a_takes_all_the_text_of_a_text_box :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.New_Widget(g, .TextBox, g.root, GUI.Widget_Opts{text = "hello world"})
	GUI.Focus_Set(g, field)

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .A, mods = GUI.Mods{.Ctrl}})

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, len(d.text))
	}

	test_gui_destroy(g)
}

@(test)
test_a_text_box_takes_only_the_characters_it_is_given :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "12",
			rules = GUI.Text_Rules{allowed = "0123456789"},
		},
	)

	GUI.fire_text(g, field, "3")
	testing.expect_value(t, field_text(g, field), "123")

	GUI.fire_text(g, field, "a")
	testing.expect_value(t, field_text(g, field), "123")

	test_gui_destroy(g)
}

@(test)
test_a_text_box_takes_only_the_characters_that_match_the_pattern :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "ab",
			rules = GUI.Text_Rules{pattern = "[a-z]+"},
		},
	)

	GUI.fire_text(g, field, "c")
	testing.expect_value(t, field_text(g, field), "abc")

	GUI.fire_text(g, field, "1")
	testing.expect_value(t, field_text(g, field), "abc")

	test_gui_destroy(g)
}

@(test)
test_a_text_box_stops_at_the_length_it_is_given :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "ab",
			rules = GUI.Text_Rules{max_length = 3},
		},
	)

	GUI.fire_text(g, field, "cde")
	testing.expect_value(t, field_text(g, field), "abc")

	test_gui_destroy(g)
}

@(test)
test_a_text_box_keeps_the_length_it_is_given :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "abcd",
			rules = GUI.Text_Rules{min_length = 3},
		},
	)

	GUI.text_input_backspace(g, field)
	testing.expect_value(t, field_text(g, field), "abc")

	GUI.text_input_backspace(g, field)
	testing.expect_value(t, field_text(g, field), "abc")

	test_gui_destroy(g)
}

@(test)
test_what_is_pasted_is_kept_to_the_rules_of_the_box :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "1",
			rules = GUI.Text_Rules{allowed = "0123456789", max_length = 3},
		},
	)

	GUI.clipboard_set(g, "23ab45")
	GUI.text_input_paste(g, field)
	testing.expect_value(t, field_text(g, field), "123")

	test_gui_destroy(g)
}

@(test)
test_the_editor_takes_the_text_the_same_way_the_text_box_does :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "editor",
				preset = .Top_Left,
				offsets = GUI.Offset{16, 16, 400, 160},
			},
			text = "hello world",
		},
	)
	GUI.layout_pass(g)

	from := editor_x_of(g, editor, 2)
	to := editor_x_of(g, editor, 7)

	append(&g.events, mouse_down(from, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move(to))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up(to))
	GUI.Handle_Events(g)

	cursor := GUI.rich_text_editor_cursor(g, editor, 0)
	testing.expect_value(t, cursor.sel_start, 2)
	testing.expect_value(t, cursor.sel_end, 7)

	//* A double click takes the word under the pointer.
	append(&g.events, mouse_down(from, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down(from, 2))
	GUI.Handle_Events(g)

	cursor = GUI.rich_text_editor_cursor(g, editor, 0)
	testing.expect_value(t, cursor.sel_start, 0)
	testing.expect_value(t, cursor.sel_end, 5)

	//* And the double click that follows takes all of the text.
	append(&g.events, mouse_down(from, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down(from, 2))
	GUI.Handle_Events(g)

	cursor = GUI.rich_text_editor_cursor(g, editor, 0)
	testing.expect_value(t, cursor.sel_start, 0)
	testing.expect_value(t, cursor.sel_end, len("hello world"))

	test_gui_destroy(g)
}

@(test)
test_the_editor_keeps_the_rules_it_is_given :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{name = "editor"},
			text = "12",
			rules = GUI.Text_Rules{allowed = "0123456789", max_length = 3},
		},
	)

	GUI.rich_text_editor_insert(g, editor, "3")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "123")

	GUI.rich_text_editor_insert(g, editor, "a")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "123")

	test_gui_destroy(g)
}

@(test)
test_a_box_of_more_than_one_line_takes_the_text_the_same_way_a_field_does :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	edit := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "edit",
				preset = .Top_Left,
				offsets = GUI.Offset{16, 16, 400, 160},
			},
			text = "hello world",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)
	GUI.layout_pass(g)

	from := box_x_of(g, edit, 0)
	to := box_x_of(g, edit, 5)

	append(&g.events, mouse_down(from, 1))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move(to))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up(to))
	GUI.Handle_Events(g)

	d := GUI.text_box_data(g, edit)
	testing.expect_value(t, d.sel_start, 0)
	testing.expect_value(t, d.sel_end, 5)

	test_gui_destroy(g)
}

pattern_matches_text :: proc(g: ^GUI.GUI, source: string, text: string) -> bool {
	pattern := GUI.pattern_compile(g, source)
	return GUI.pattern_matches(&pattern, text)
}

@(test)
test_the_enter_key_moves_the_caret_to_the_next_line_of_the_editor :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "editor",
				preset = .Top_Left,
				offsets = GUI.Offset{16, 16, 400, 160},
			},
			text = "abc",
		},
	)
	GUI.layout_pass(g)

	GUI.rich_text_editor_set_caret(g, editor, 3, false)
	GUI.fire_key(g, editor, GUI.Key_Down_Event{key = .Enter})

	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "abc\n")

	cursor := GUI.rich_text_editor_cursor(g, editor, 0)
	testing.expect_value(t, cursor.caret, 4)

	//* The caret is on the line below the text.
	w := GUI.Widget_Get(g, editor)
	state := GUI.rich_text_editor_state(g, editor)
	content := GUI.content_rect(g, w)
	ts := GUI.rich_text_editor_text_style(g, w, state)
	lines := GUI.text_lines(g, ts, state.text, content.w)
	box := GUI.Rect {
		x = content.x - state.scroll.x,
		y = content.y - state.scroll.y,
		w = content.w,
		h = content.h,
	}
	x, y, _ := GUI.text_place(g, GUI.Font_Of(g, w), box, ts, lines[:], state.text, cursor.caret)
	_, first_y, _ := GUI.text_place(g, GUI.Font_Of(g, w), box, ts, lines[:], state.text, 0)
	testing.expect_value(t, y > first_y, true)
	testing.expect_value(t, x == content.x, true)

	test_gui_destroy(g)
}

@(test)
test_the_enter_key_makes_a_new_line_in_a_box_of_more_than_one_line :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	edit := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "edit",
				preset = .Top_Left,
				offsets = GUI.Offset{16, 16, 400, 160},
			},
			text = "abc",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)
	GUI.layout_pass(g)

	d := GUI.text_box_data(g, edit)

	//* The key makes the new line: the text of the keyboard that comes
	//* with the enter key is passed over, so that the box does not get
	//* two new lines.
	GUI.fire_key(g, edit, GUI.Key_Down_Event{key = .Enter})
	testing.expect_value(t, d.text, "abc\n")
	testing.expect_value(t, d.caret, 4)

	GUI.fire_text(g, edit, "\r")
	testing.expect_value(t, d.text, "abc\n")
	testing.expect_value(t, d.caret, 4)

	//* The caret is on the line below the text.
	caret := box_x_of(g, edit, d.caret)
	first := box_x_of(g, edit, 0)
	testing.expect_value(t, caret.y > first.y, true)
	testing.expect_value(t, caret.x == first.x, true)

	test_gui_destroy(g)
}

@(test)
test_a_text_field_takes_no_line_break :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "ab",
		},
	)

	//* The line break of the enter key stays out of the text.
	GUI.fire_text(g, field, "\r")
	testing.expect_value(t, field_text(g, field), "ab")

	GUI.fire_text(g, field, "c\nd")
	testing.expect_value(t, field_text(g, field), "abcd")

	test_gui_destroy(g)
}

@(test)
test_what_is_pasted_keeps_the_lines_it_has :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{name = "editor"},
			text = "",
		},
	)

	//* The lines of the clipboard come with a carriage return and a line
	//* feed, and they are one break, not two.
	GUI.clipboard_set(g, "one\r\ntwo\r\nthree")
	GUI.rich_text_editor_paste(g, editor)
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "one\ntwo\nthree")

edit := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "edit"},
			text = "",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)

	GUI.clipboard_set(g, "one\r\ntwo\r\nthree")
	GUI.text_input_paste(g, edit)
	testing.expect_value(t, GUI.text_box_text(g, edit), "one\ntwo\nthree")

	test_gui_destroy(g)
}

@(test)
test_the_tab_key_indents_the_text_of_a_box_of_more_than_one_line :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	//* The text that the tab key makes is made once here, and it is
	//* given back when the test is over.
	expected := strings.concatenate({"ab", GUI.TEXT_INDENT})
	defer delete(expected)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{name = "editor"},
			text = "ab",
		},
	)
	GUI.Focus_Set(g, editor)

	GUI.handle_key_down(g, GUI.Key_Down_Event{key = .Tab})

	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), expected)
	testing.expect_value(t, g.focused, editor)

edit := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "edit"},
			text = "ab",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)
	GUI.Focus_Set(g, edit)

	GUI.handle_key_down(g, GUI.Key_Down_Event{key = .Tab})

	testing.expect_value(t, GUI.text_box_text(g, edit), expected)
	testing.expect_value(t, g.focused, edit)

	test_gui_destroy(g)
}

@(test)
test_the_tab_key_moves_the_focus_of_a_box_of_one_line :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "ab",
		},
	)
	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "button"},
			text = "ok",
		},
	)
	GUI.layout_pass(g)

	GUI.Focus_Set(g, field)
	GUI.handle_key_down(g, GUI.Key_Down_Event{key = .Tab})

	testing.expect_value(t, field_text(g, field), "ab")
	testing.expect_value(t, g.focused, button)

	test_gui_destroy(g)
}

@(test)
test_a_pattern_says_which_characters_may_be_typed :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	testing.expect_value(t, pattern_matches_text(g, "[0-9]", "5"), true)
	testing.expect_value(t, pattern_matches_text(g, "[0-9]", "a"), false)
	testing.expect_value(t, pattern_matches_text(g, "[0-9]", ""), false)
	testing.expect_value(t, pattern_matches_text(g, "\\d", "5"), true)
	testing.expect_value(t, pattern_matches_text(g, "\\d", "a"), false)
	testing.expect_value(t, pattern_matches_text(g, "\\w", "a"), true)
	testing.expect_value(t, pattern_matches_text(g, "\\w", " "), false)
	testing.expect_value(t, pattern_matches_text(g, "\\s", " "), true)
	testing.expect_value(t, pattern_matches_text(g, "[^0-9]", "a"), true)
	testing.expect_value(t, pattern_matches_text(g, "[^0-9]", "5"), false)
	testing.expect_value(t, pattern_matches_text(g, "[a-z]+", "abc"), true)
	testing.expect_value(t, pattern_matches_text(g, "[a-z]+", "ab1"), false)
	testing.expect_value(t, pattern_matches_text(g, "a|b", "b"), true)
	testing.expect_value(t, pattern_matches_text(g, "a|b", "c"), false)
	testing.expect_value(t, pattern_matches_text(g, ".", "x"), true)
	testing.expect_value(t, pattern_matches_text(g, ".", ""), false)
	testing.expect_value(t, pattern_matches_text(g, "a{2,3}", "aa"), true)
	testing.expect_value(t, pattern_matches_text(g, "a{2,3}", "a"), false)
	testing.expect_value(t, pattern_matches_text(g, "a{2,3}", "aaaa"), false)
	testing.expect_value(t, pattern_matches_text(g, "(ab)+", "abab"), true)
	testing.expect_value(t, pattern_matches_text(g, "(ab)+", "aba"), false)

	test_gui_destroy(g)
}

@(test)
test_a_pattern_keeps_the_letters_out_of_a_text_box :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "",
			rules = GUI.Text_Rules{pattern = "\\w+"},
		},
	)

	GUI.fire_text(g, field, "ab")
	testing.expect_value(t, field_text(g, field), "ab")

	GUI.fire_text(g, field, " ")
	testing.expect_value(t, field_text(g, field), "ab")

GUI.fire_text(g, field, "12")
	testing.expect_value(t, field_text(g, field), "ab12")

	test_gui_destroy(g)
}

//* == The two kinds of text box ==

//* The text that is submitted by a box of one line.
box_test_submitted: string

box_test_on_submitted :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, text: string) {
	box_test_submitted = text
}

//* A box of one line is as tall as one line of the font, and its text
//* does not change that.
@(test)
test_a_box_of_one_line_is_as_tall_as_one_line_of_the_font :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "hello",
		},
	)
	empty := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{Base_Opts = GUI.Base_Opts{name = "empty"}},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, field)
	f := GUI.font_get(g, GUI.Font_Of(g, w))
	style := GUI.resolved_style(g, w)
	pad := style.box.content_margin
	expected := f.line_height + max(pad[1], 1) + max(pad[3], 1)

	testing.expect_value(t, w.min_size.y, expected)

	//* The box that has no text is as tall as the one that has.
	testing.expect_value(t, GUI.Widget_Get(g, empty).min_size.y, expected)

	//* The text of the box does not make it taller.
	GUI.text_box_set_text(g, field, "a text that is much longer than one line of the font")
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, field).min_size.y, expected)

	test_gui_destroy(g)
}

//* A box of one line shows a window of the text, and the window is
//* scrolled sideways.
@(test)
test_a_box_of_one_line_scrolls_sideways_when_the_text_is_longer_than_the_window :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "field",
				preset = .Top_Left,
				offsets = GUI.Offset{16, 16, 316, 48},
			},
			text = "one two three four five six seven eight nine ten",
			shown_chars = 10,
		},
	)
	GUI.layout_pass(g)

	//* The text is longer than the window, so the box shows a scroll bar.
	testing.expect_value(t, GUI.text_box_scrollbar_h(g, field), true)

	//* The wheel scrolls the window sideways.
	append(&g.events, mouse_move({100, 30}))
	GUI.Handle_Events(g)
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	d := GUI.text_box_data(g, field)
	testing.expect_value(t, d.scroll_chars > 0, true)

	//* The window begins on the boundary of a character.
	testing.expect_value(t, GUI.snap_offset(d.text, GUI.text_box_char_offset(d.text, d.scroll_chars)) == GUI.text_box_char_offset(d.text, d.scroll_chars), true)

	test_gui_destroy(g)
}

//* A box of more than one line breaks its text into lines that fit the
//* width of the box, and it scrolls down when the lines do not fit.
@(test)
test_a_box_of_more_than_one_line_wraps_and_scrolls_down :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	text := "one two three four five six seven eight nine ten eleven twelve"
	box := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "box",
				preset = .Top_Left,
				offsets = GUI.Offset{16, 16, 216, 66},
			},
			text = text,
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, box)
	content := GUI.content_rect(g, w)
	lines := GUI.text_box_lines(g, w, text, true, content.w)

	//* The text is broken into more than one line.
	testing.expect_value(t, len(lines) > 1, true)

	//* The lines do not fit in the box, so the box scrolls down.
	testing.expect_value(t, GUI.text_box_scrollbar_v(g, box), true)

	append(&g.events, mouse_move({100, 40}))
	GUI.Handle_Events(g)
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	d := GUI.text_box_data(g, box)
	testing.expect_value(t, d.scroll_y > 0, true)

	test_gui_destroy(g)
}

//* The enter key submits a box of one line, and it makes a new line in
//* a box of more than one line.
@(test)
test_the_enter_key_submits_a_box_of_one_line :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	box_test_submitted = ""
	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "hello",
		},
	)
	GUI.Widget_Get(g, field).signals.on_submitted = box_test_on_submitted
	GUI.Focus_Set(g, field)

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Enter})

	testing.expect_value(t, box_test_submitted, "hello")

	//* The text of the box is not changed by the key.
	testing.expect_value(t, field_text(g, field), "hello")

	test_gui_destroy(g)
}

//* The rules of a box are the same in both of its kinds.
box_test_rules :: proc(t: ^testing.T, g: ^GUI.GUI, id: GUI.Widget_ID) {
	GUI.fire_text(g, id, "3")
	testing.expect_value(t, field_text(g, id), "123")

	//* The letters are kept out of the box.
	GUI.fire_text(g, id, "a")
	testing.expect_value(t, field_text(g, id), "123")

	//* The box stops at the length it was given.
	GUI.fire_text(g, id, "4")
	testing.expect_value(t, field_text(g, id), "123")
}

@(test)
test_the_rules_of_a_box_are_the_same_in_both_of_its_kinds :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "12",
			rules = GUI.Text_Rules{allowed = "0123456789", max_length = 3},
		},
	)
	box := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "box"},
			text = "12",
			rules = GUI.Text_Rules{allowed = "0123456789", max_length = 3},
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)

	box_test_rules(t, g, field)
	box_test_rules(t, g, box)

	test_gui_destroy(g)
}

//* The selection of a box is the same in both of its kinds.
box_test_selection :: proc(t: ^testing.T, g: ^GUI.GUI, id: GUI.Widget_ID) {
	GUI.text_input_select_all(g, id)
	d := GUI.text_box_data(g, id)
	testing.expect_value(t, d.sel_start, 0)
	testing.expect_value(t, d.sel_end, len(d.text))

	//* What is typed goes over the text that is taken.
	GUI.fire_text(g, id, "X")
	testing.expect_value(t, field_text(g, id), "X")

	//* The caret stands where it is put.
	GUI.text_box_set_text(g, id, "hello world")
	GUI.text_input_set_caret(g, id, 8, false)
	d = GUI.text_box_data(g, id)
	testing.expect_value(t, d.sel_start, d.caret)
	testing.expect_value(t, d.sel_end, d.caret)
}

@(test)
test_the_selection_of_a_box_is_the_same_in_both_of_its_kinds :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)

	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "hello world",
		},
	)
	box := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "box"},
			text = "hello world",
			flags = GUI.Text_Box_Flags{.Multiline},
		},
	)

	box_test_selection(t, g, field)
	box_test_selection(t, g, box)

	test_gui_destroy(g)
}

//* The text draw pipeline, checked against the contract: the layout of
//* a piece of text and the quads it puts in the draw list. Only the
//* public side of the pipeline is used, so the tests hold whatever the
//* layout is built on.

//* What a piece of text put in the draw list.
Text_Test_Draw :: struct {
	quads:   int,
	bounds:  GUI.Rect,
	last_uv: [2]f32,
	colour:  GUI.Colour,
}

//* A GUI with a font, ready to draw text into.
text_test_gui :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	return g
}

//* The rect of the quad that starts at vertex `i`.
text_test_quad :: proc(dl: ^GUI.Draw_List, i: int) -> GUI.Rect {
	v := dl.vertices[i]
	return GUI.Rect {
		x = v.pos[0],
		y = v.pos[1],
		w = dl.vertices[i + 1].pos[0] - v.pos[0],
		h = dl.vertices[i + 3].pos[1] - v.pos[1],
	}
}

//* The box that holds every quad of the list.
text_test_bounds :: proc(dl: ^GUI.Draw_List) -> GUI.Rect {
	if len(dl.vertices) < 4 {return {}}
	r := text_test_quad(dl, 0)
	for q in 1 ..< len(dl.vertices) / 4 {
		quad := text_test_quad(dl, q * 4)
		x0 := min(r.x, quad.x)
		y0 := min(r.y, quad.y)
		x1 := max(r.x + r.w, quad.x + quad.w)
		y1 := max(r.y + r.h, quad.y + quad.h)
		r = GUI.Rect {
			x = x0,
			y = y0,
			w = x1 - x0,
			h = y1 - y0,
		}
	}
	return r
}

//* Draws a piece of text into the draw list of the GUI and reports what
//* it put there.
text_test_draw :: proc(g: ^GUI.GUI, ts: GUI.Text_Style, text: string, rect: GUI.Rect) -> Text_Test_Draw {
	GUI.draw_list_clear(&g.draw, g.viewport)
	g.target = &g.draw
	GUI.draw_text(g, ts, text, rect, GUI.RGBA(1, 1, 1, 1))

	out: Text_Test_Draw
	out.quads = len(g.draw.vertices) / 4
	out.bounds = text_test_bounds(&g.draw)
	if len(g.draw.vertices) >= 4 {
		out.last_uv = g.draw.vertices[len(g.draw.vertices) - 4].uv
		out.colour = g.draw.vertices[0].colour
	}
	return out
}

@(test)
test_text_draws_glyph_quads :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 400,
		h = 100,
	}

	ts := GUI.Text_Style {
		size   = 16,
		colour = GUI.RGBA(1, 1, 1, 1),
	}
	dl := text_test_draw(g, ts, "Hello", rect)

	//* Every glyph of the text is a quad in the draw list.
	testing.expect_value(t, dl.quads, 5)

	testing.expect_value(t, dl.colour.r, 1.0)
	testing.expect_value(t, dl.colour.a, 1.0)

	small := GUI.text_measure(g, ts, "Hello", 0)
	big_ts := GUI.Text_Style {
		size   = 32,
		colour = GUI.RGBA(1, 1, 1, 1),
	}
	big := GUI.text_measure(g, big_ts, "Hello", 0)
	testing.expect_value(t, big.x > small.x, true)

	small_dl := text_test_draw(g, ts, "Hello", rect)
	big_dl := text_test_draw(g, big_ts, "Hello", rect)
	testing.expect_value(t, big_dl.bounds.w > small_dl.bounds.w, true)

	test_gui_destroy(g)
}

@(test)
test_text_transform_changes_the_text_that_is_laid_out :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 400,
		h = 100,
	}

	plain := GUI.Text_Style {
		size = 16,
	}
	upper := GUI.Text_Style {
		size      = 16,
		transform = .Upper,
	}
	lower := GUI.Text_Style {
		size      = 16,
		transform = .Lower,
	}
	capital := GUI.Text_Style {
		size      = 16,
		transform = .Capitalize,
	}

	//* The upper cased text is measured as the upper cased text.
	m := GUI.text_measure(g, upper, "hello world", 0)
	reference := GUI.text_measure(g, plain, "HELLO WORLD", 0)
	testing.expect_value(t, m.x, reference.x)
	testing.expect_value(t, m.y, reference.y)

	//* The lower cased text is measured as the lower cased text.
	m = GUI.text_measure(g, lower, "HELLO WORLD", 0)
	reference = GUI.text_measure(g, plain, "hello world", 0)
	testing.expect_value(t, m.x, reference.x)

	//* The capitalised text has the first letter of every word in upper
	//* case, and the rest of the word as it was.
	m = GUI.text_measure(g, capital, "hello world", 0)
	reference = GUI.text_measure(g, plain, "Hello World", 0)
	testing.expect_value(t, m.x, reference.x)

	//* And the drawn text is the transformed text.
	dl := text_test_draw(g, upper, "hello", rect)
	ref_dl := text_test_draw(g, plain, "HELLO", rect)
	testing.expect_value(t, dl.quads, ref_dl.quads)
	testing.expect_value(t, dl.bounds.w, ref_dl.bounds.w)

	test_gui_destroy(g)
}

@(test)
test_text_wrap_word_makes_more_than_one_line :: proc(t: ^testing.T) {
	g := text_test_gui(t)

	plain := GUI.Text_Style {
		size = 16,
	}
	wrapped := GUI.Text_Style {
		size = 16,
		wrap = .Word,
	}

	one := GUI.text_measure(g, plain, "hello", 0)
	many := GUI.text_measure(g, wrapped, "hello world of text that wraps", 100)

	//* The text is broken into more than one line, so the block is
	//* taller than a single line.
	testing.expect_value(t, many.y > one.y, true)

	//* Every line fits in the width the text was broken at.
	testing.expect_value(t, many.x <= 100, true)

	//* The same text without a width stays on one line.
	flat := GUI.text_measure(g, wrapped, "hello world of text that wraps", 0)
	testing.expect_value(t, flat.y, one.y)

	test_gui_destroy(g)
}

@(test)
test_text_wrap_anywhere_breaks_inside_a_word :: proc(t: ^testing.T) {
	g := text_test_gui(t)

	plain := GUI.Text_Style {
		size = 16,
	}
	anywhere := GUI.Text_Style {
		size = 16,
		wrap = .Anywhere,
	}
	text := "abcdefghijklmnopqrstuvwxyz"

	one := GUI.text_measure(g, plain, text, 0)
	many := GUI.text_measure(g, anywhere, text, 60)

	//* The long word is broken into more than one line.
	testing.expect_value(t, many.y > one.y, true)

	//* And every line fits in the width it was broken at.
	testing.expect_value(t, many.x <= 60, true)

	test_gui_destroy(g)
}

@(test)
test_text_align_center_moves_the_glyphs_to_the_right :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 400,
		h = 100,
	}

	left := text_test_draw(g, GUI.Text_Style{size = 16, align = .Left}, "Hello", rect)
	center := text_test_draw(g, GUI.Text_Style{size = 16, align = .Center}, "Hello", rect)
	right := text_test_draw(g, GUI.Text_Style{size = 16, align = .Right}, "Hello", rect)

	//* The centred text starts further to the right, and the right
	//* aligned text further still.
	testing.expect_value(t, center.bounds.x > left.bounds.x, true)
	testing.expect_value(t, right.bounds.x > center.bounds.x, true)

	//* The right edge of the right aligned text is the right edge of
	//* the box.
	testing.expect_value(t, right.bounds.x + right.bounds.w <= rect.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_align_fill_spreads_the_words_out :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 120,
		h = 200,
	}
	text := "one two three four"

	left := text_test_draw(g, GUI.Text_Style{size = 16, align = .Left, wrap = .Word}, text, rect)
	fill := text_test_draw(g, GUI.Text_Style{size = 16, align = .Fill, wrap = .Word}, text, rect)

	//* The justified text is wider: the words are spread out so that
	//* the line fills the box.
	testing.expect_value(t, fill.bounds.w > left.bounds.w, true)

	test_gui_destroy(g)
}

@(test)
test_text_valign_center_moves_the_glyphs_down :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 400,
		h = 200,
	}

	top := text_test_draw(g, GUI.Text_Style{size = 16, valign = .Top}, "Hello", rect)
	center := text_test_draw(g, GUI.Text_Style{size = 16, valign = .Center}, "Hello", rect)
	bottom := text_test_draw(g, GUI.Text_Style{size = 16, valign = .Bottom}, "Hello", rect)

	testing.expect_value(t, center.bounds.y > top.bounds.y, true)
	testing.expect_value(t, bottom.bounds.y > center.bounds.y, true)

	test_gui_destroy(g)
}

@(test)
test_text_spacing_pushes_the_lines_apart :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 100,
		h = 400,
	}
	text := "hello world of wrapping text"

	plain := GUI.Text_Style {
		size = 16,
		wrap = .Word,
	}
	spaced := GUI.Text_Style {
		size    = 16,
		wrap    = .Word,
		spacing = 12,
	}

	//* The block of text is taller with the spacing.
	h_plain := GUI.text_measure(g, plain, text, 100).y
	h_spaced := GUI.text_measure(g, spaced, text, 100).y
	testing.expect_value(t, h_spaced > h_plain, true)

	//* And the text is drawn taller too.
	d_plain := text_test_draw(g, plain, text, rect)
	d_spaced := text_test_draw(g, spaced, text, rect)
	testing.expect_value(t, d_spaced.bounds.h > d_plain.bounds.h, true)

	test_gui_destroy(g)
}

@(test)
test_text_shadow_and_outline_add_quads :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 400,
		h = 100,
	}
	text := "Hello"

	plain := text_test_draw(g, GUI.Text_Style{size = 16}, text, rect)
	n := plain.quads
	testing.expect_value(t, n > 0, true)

	//* The shadow is a second copy of every glyph.
	shadow := text_test_draw(
		g,
		GUI.Text_Style{size = 16, shadow_colour = GUI.RGBA(0, 0, 0, 0.5), shadow_offset = GUI.Vec2{2, 2}},
		text,
		rect,
	)
	testing.expect_value(t, shadow.quads, n * 2)

	//* The outline is a ring of eight copies around every glyph.
	outline := text_test_draw(
		g,
		GUI.Text_Style{size = 16, outline_colour = GUI.RGBA(1, 1, 1, 1), outline_size = 1},
		text,
		rect,
	)
	testing.expect_value(t, outline.quads, n * 9)

	//* Both of them.
	both := text_test_draw(
		g,
		GUI.Text_Style {
			size = 16,
			shadow_colour = GUI.RGBA(0, 0, 0, 0.5),
			shadow_offset = GUI.Vec2{2, 2},
			outline_colour = GUI.RGBA(1, 1, 1, 1),
			outline_size = 1,
		},
		text,
		rect,
	)
	testing.expect_value(t, both.quads, n * 10)

	test_gui_destroy(g)
}

@(test)
test_text_overrun_ellipsis_cuts_the_text_so_that_it_fits :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 60,
		h = 40,
	}
	text := "hello world"

	plain := text_test_draw(g, GUI.Text_Style{size = 16}, text, rect)

	//* The text does not fit in the box.
	testing.expect_value(t, plain.bounds.w > rect.w, true)

	ell := text_test_draw(g, GUI.Text_Style{size = 16, overrun = .Ellipsis}, text, rect)

	//* The text was cut, and what is left fits in the box.
	testing.expect_value(t, ell.bounds.w < plain.bounds.w, true)
	testing.expect_value(t, ell.bounds.w <= rect.w + 1, true)
	testing.expect_value(t, ell.quads < plain.quads, true)

	//* The last glyph of the cut text is the ellipsis.
	found := false
	for i in 0 ..< 4 {
		only := text_test_draw(
			g,
			GUI.Text_Style{size = 16},
			"…",
			GUI.Rect{x = f32(i) * 0.25, y = rect.y, w = rect.w, h = rect.h},
		)
		if only.last_uv == ell.last_uv {found = true}
	}
	testing.expect_value(t, found, true)

	test_gui_destroy(g)
}


@(test)
test_text_overrun_words_cuts_at_a_word_boundary :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 70,
		h = 40,
	}
	text := "hello world of text"

	words := text_test_draw(g, GUI.Text_Style{size = 16, overrun = .Words}, text, rect)
	ell := text_test_draw(g, GUI.Text_Style{size = 16, overrun = .Ellipsis}, text, rect)

	//* Both of them cut the text so that it fits in the box.
	testing.expect_value(t, words.bounds.w <= rect.w + 1, true)
	testing.expect_value(t, ell.bounds.w <= rect.w + 1, true)

	//* The cut at a word boundary is never longer than the cut
	//* anywhere.
	testing.expect_value(t, words.bounds.w <= ell.bounds.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_clip_cuts_the_text_at_the_edge_of_the_box :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := GUI.Rect {
		x = 0,
		y = 0,
		w = 40,
		h = 30,
	}

	//* The clip is worked out on the CPU: the quads that are drawn are
	//* already cut, so the text stays inside its own box.
	clipped := text_test_draw(g, GUI.Text_Style{size = 16, clip = true}, "Hello world", rect)
	testing.expect_value(t, clipped.bounds.w <= rect.w + 1, true)
	testing.expect_value(t, clipped.bounds.h <= rect.h + 1, true)

	//* Without the clip the text runs out of the box, but it is still
	//* inside the window.
	plain := text_test_draw(g, GUI.Text_Style{size = 16}, "Hello world", rect)
	testing.expect_value(t, plain.bounds.w > rect.w, true)
	testing.expect_value(t, plain.bounds.x + plain.bounds.w <= g.viewport.w + 1, true)

	test_gui_destroy(g)
}

//* Tests for the text draw pipeline: the transform, the wrapping, the
//* overrun and the decorations.

//* A GUI with a font and an empty draw list, ready for text.
test_text_gui :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	GUI.draw_list_clear(&g.draw, g.viewport)
	return g
}

//* The number of quads that were drawn. A quad is four vertices.
drawn_quads :: proc(g: ^GUI.GUI) -> int {
	return len(g.draw.vertices) / 4
}

//* The box the drawn quads cover: the smallest one that holds them all.
drawn_bounds :: proc(g: ^GUI.GUI) -> GUI.Rect {
	if len(g.draw.vertices) == 0 {return {}}
	min_x := g.draw.vertices[0].pos[0]
	min_y := g.draw.vertices[0].pos[1]
	max_x := min_x
	max_y := min_y
	for v in g.draw.vertices {
		min_x = min(min_x, v.pos[0])
		min_y = min(min_y, v.pos[1])
		max_x = max(max_x, v.pos[0])
		max_y = max(max_y, v.pos[1])
	}
	return GUI.Rect{x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y}
}

//* The number of lines of text that were drawn. The quads of one line
//* sit on top of each other, the quads of two lines do not, so the
//* quads are grouped into rows.
drawn_lines :: proc(g: ^GUI.GUI) -> int {
	rows: [64]GUI.Rect
	count := 0
	for i in 0 ..< len(g.draw.vertices) / 4 {
		p := g.draw.vertices[i * 4].pos
		q := g.draw.vertices[i * 4 + 2].pos
		r := GUI.Rect {
			x = p[0],
			y = p[1],
			w = q[0] - p[0],
			h = q[1] - p[1],
		}

		found := false
		for j in 0 ..< count {
			row := &rows[j]
			if r.y < row.y + row.h && row.y < r.y + r.h {
				bottom := max(row.y + row.h, r.y + r.h)
				row.y = min(row.y, r.y)
				row.h = bottom - row.y
				found = true
				break
			}
		}
		if !found {
			rows[count] = r
			count += 1
		}
	}
	return count
}

@(test)
test_text_draw_draws_glyph_quads :: proc(t: ^testing.T) {
	g := test_text_gui(t)

	before := len(g.draw.vertices)
	GUI.draw_text(g, GUI.Text_Style{}, "Hello", GUI.Rect{0, 0, 200, 40}, GUI.RGBA(1, 1, 1, 1))
	after := len(g.draw.vertices)

	testing.expect_value(t, after > before, true)
	//* Every quad is four vertices.
	testing.expect_value(t, (after - before) % 4, 0)
	//* One quad for every glyph of the text.
	testing.expect_value(t, (after - before) / 4 >= 5, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_draws_at_the_size_of_the_style :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 400, 100}

	GUI.draw_text(g, GUI.Text_Style{size = 16}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	small := drawn_bounds(g)

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{size = 32}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	big := drawn_bounds(g)

	testing.expect_value(t, big.h > small.h, true)
	testing.expect_value(t, big.w > small.w, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_transforms_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello world"
	rect := GUI.Rect{0, 0, 400, 40}

	GUI.draw_text(g, GUI.Text_Style{}, text, rect, GUI.RGBA(1, 1, 1, 1))
	plain := drawn_bounds(g).w

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{transform = .Upper}, text, rect, GUI.RGBA(1, 1, 1, 1))
	upper := drawn_bounds(g).w

	//* The upper case text is not the text that was given.
	testing.expect_value(t, upper > plain, true)

	//* It is the upper case text: it is as wide as the upper case
	//* string is.
	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{}, "HELLO WORLD", rect, GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, upper, drawn_bounds(g).w)

	test_gui_destroy(g)
}

@(test)
test_text_draw_capitalizes_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 400, 40}

	GUI.draw_text(g, GUI.Text_Style{transform = .Capitalize}, "hello world", rect, GUI.RGBA(1, 1, 1, 1))
	capitalized := drawn_bounds(g).w

	//* Every word starts with a capital, and the rest of the word is
	//* left as it is.
	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{}, "Hello World", rect, GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, capitalized, drawn_bounds(g).w)

	test_gui_destroy(g)
}

@(test)
test_text_draw_wraps_into_more_lines :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "the quick brown fox jumps over the lazy dog"

	GUI.draw_text(g, GUI.Text_Style{wrap = .Off}, text, GUI.Rect{0, 0, 800, 200}, GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, drawn_lines(g), 1)
	plain_height := drawn_bounds(g).h

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{wrap = .Word}, text, GUI.Rect{0, 0, 100, 200}, GUI.RGBA(1, 1, 1, 1))

	testing.expect_value(t, drawn_lines(g) > 1, true)
	testing.expect_value(t, drawn_bounds(g).h > plain_height, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_breaks_anywhere :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello wonderful world"
	rect := GUI.Rect{0, 0, 80, 100}

	GUI.draw_text(g, GUI.Text_Style{wrap = .Word}, text, rect, GUI.RGBA(1, 1, 1, 1))
	word := drawn_bounds(g).w

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{wrap = .Anywhere}, text, rect, GUI.RGBA(1, 1, 1, 1))
	anywhere := drawn_bounds(g).w

	//* The anywhere break fills the line, the word break leaves the
	//* rest of the line empty.
	testing.expect_value(t, anywhere > word, true)
	testing.expect_value(t, drawn_lines(g) > 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_valign_moves_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 200, 100}

	GUI.draw_text(g, GUI.Text_Style{valign = .Top}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	top := drawn_bounds(g).y

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{valign = .Center}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	center := drawn_bounds(g).y

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{valign = .Bottom}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	bottom := drawn_bounds(g).y

	testing.expect_value(t, center > top, true)
	testing.expect_value(t, bottom > center, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_align_moves_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 200, 40}

	GUI.draw_text(g, GUI.Text_Style{align = .Left}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	left := drawn_bounds(g).x

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{align = .Center}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	center := drawn_bounds(g).x

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{align = .Right}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	right := drawn_bounds(g).x

	testing.expect_value(t, center > left, true)
	testing.expect_value(t, right > center, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_fills_the_line :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 200, 100}

	GUI.draw_text(
		g,
		GUI.Text_Style{wrap = .Word, align = .Fill},
		"one two three four five six seven eight",
		rect,
		GUI.RGBA(1, 1, 1, 1),
	)

	//* The words are spread out, so the line reaches the edge of the
	//* box.
	testing.expect_value(t, drawn_bounds(g).w > rect.w - 10, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_spacing_pushes_the_lines_apart :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "the quick brown fox jumps over the lazy dog"
	rect := GUI.Rect{0, 0, 100, 200}

	GUI.draw_text(g, GUI.Text_Style{wrap = .Word}, text, rect, GUI.RGBA(1, 1, 1, 1))
	plain := drawn_bounds(g).h

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{wrap = .Word, spacing = 10}, text, rect, GUI.RGBA(1, 1, 1, 1))

	testing.expect_value(t, drawn_bounds(g).h > plain, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_outline_draws_a_ring_of_copies :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 200, 40}

	GUI.draw_text(g, GUI.Text_Style{}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	plain := drawn_quads(g)

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(
		g,
		GUI.Text_Style{outline_colour = GUI.RGBA(0, 0, 0, 1), outline_size = 2},
		"Hello",
		rect,
		GUI.RGBA(1, 1, 1, 1),
	)
	outlined := drawn_quads(g)

	//* The ink, and a copy of it in each of the eight directions.
	testing.expect_value(t, outlined, plain * 9)

	test_gui_destroy(g)
}

@(test)
test_text_draw_shadow_draws_a_second_copy :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{0, 0, 200, 40}

	GUI.draw_text(g, GUI.Text_Style{}, "Hello", rect, GUI.RGBA(1, 1, 1, 1))
	plain := drawn_quads(g)

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(
		g,
		GUI.Text_Style{shadow_colour = GUI.RGBA(0, 0, 0, 1), shadow_offset = GUI.Vec2{2, 2}},
		"Hello",
		rect,
		GUI.RGBA(1, 1, 1, 1),
	)
	shadowed := drawn_quads(g)

	testing.expect_value(t, shadowed, plain * 2)

	test_gui_destroy(g)
}

@(test)
test_text_draw_overrun_cuts_the_text_short :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello world this is a long text"
	rect := GUI.Rect{0, 0, 60, 40}

	GUI.draw_text(g, GUI.Text_Style{}, text, rect, GUI.RGBA(1, 1, 1, 1))
	plain := drawn_quads(g)

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{overrun = .Ellipsis}, text, rect, GUI.RGBA(1, 1, 1, 1))
	cut := drawn_quads(g)

	//* The text does not fit, so it is cut short.
	testing.expect_value(t, cut < plain, true)
	//* What is left of it fits, with the ellipsis.
	testing.expect_value(t, drawn_bounds(g).w <= rect.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_overrun_cuts_at_a_word_boundary :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello world this is a long text"
	rect := GUI.Rect{0, 0, 90, 40}

	GUI.draw_text(g, GUI.Text_Style{}, text, rect, GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, drawn_bounds(g).w > rect.w, true)

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{overrun = .Ellipsis}, text, rect, GUI.RGBA(1, 1, 1, 1))
	ellipsis := drawn_bounds(g).w

	GUI.draw_list_clear(&g.draw, g.viewport)
	GUI.draw_text(g, GUI.Text_Style{overrun = .Words}, text, rect, GUI.RGBA(1, 1, 1, 1))
	words := drawn_bounds(g).w
	testing.expect_value(t, words <= ellipsis, true)
	testing.expect_value(t, words <= rect.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_clips_to_its_box :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := GUI.Rect{10, 20, 100, 30}

	GUI.draw_text(g, GUI.Text_Style{clip = true}, "Hello world", rect, GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, len(g.draw.commands) > 0, true)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)
	bounds := drawn_bounds(g)
	testing.expect_value(t, bounds.x >= rect.x - 0.5, true)
	testing.expect_value(t, bounds.y >= rect.y - 0.5, true)
	testing.expect_value(t, bounds.x + bounds.w <= rect.x + rect.w + 0.5, true)
	testing.expect_value(t, bounds.y + bounds.h <= rect.y + rect.h + 0.5, true)

	test_gui_destroy(g)
}

//* The tests of the text input: the caret stands on the boundary of a
//* grapheme cluster, the selection is cut and pasted, and the
//* composition of an IME is shown and committed.

edit_test_text :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> string {
	w := GUI.Widget_Get(g, id)
	if w == nil {return ""}
	text := ""
	#partial switch d in w.data {
	case GUI.Text_Box_Data:
		text = d.text
	}
	return text
}

edit_test_caret :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> int {
	w := GUI.Widget_Get(g, id)
	if w == nil {return 0}
	caret := 0
	#partial switch d in w.data {
	case GUI.Text_Box_Data:
		caret = d.caret
	}
	return caret
}

edit_test_set_caret :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, offset: int) {
	w := GUI.Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case GUI.Text_Box_Data:
		d.caret = offset
		d.sel_start = offset
		d.sel_end = offset
	}
}

edit_test_field :: proc(t: ^testing.T, g: ^GUI.GUI, text: string) -> GUI.Widget_ID {
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	field := GUI.Make_Text_Box(
		g,
		g.root,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field", offsets = GUI.Offset{0, 0, 200, 30}},
			text = text,
		},
	)
	GUI.layout_pass(g)
	GUI.Focus_Set(g, field)
	return field
}

@(test)
test_the_caret_moves_over_a_whole_cluster :: proc(t: ^testing.T) {
	s := "e\u0301x"

	testing.expect_value(t, GUI.next_offset(s, 0), 3)
	testing.expect_value(t, GUI.next_offset(s, 3), 4)
	testing.expect_value(t, GUI.prev_offset(s, 4), 3)
	testing.expect_value(t, GUI.prev_offset(s, 3), 0)
	testing.expect_value(t, GUI.prev_offset(s, 0), 0)
}

@(test)
test_an_offset_that_comes_from_outside_is_snapped_to_a_cluster :: proc(t: ^testing.T) {
	s := "e\u0301x"

	snapped := GUI.snap_offset(s, 2)
	testing.expect_value(t, snapped == 0 || snapped == 3, true)

	testing.expect_value(t, GUI.snap_offset(s, 0), 0)
	testing.expect_value(t, GUI.snap_offset(s, 3), 3)
	testing.expect_value(t, GUI.snap_offset(s, 4), 4)
}

@(test)
test_backspace_takes_a_whole_cluster_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "e\u0301x")

	edit_test_set_caret(g, field, 3)
	GUI.text_input_backspace(g, field)

	testing.expect_value(t, edit_test_text(g, field), "x")
	testing.expect_value(t, edit_test_caret(g, field), 0)

	test_gui_destroy(g)
}

@(test)
test_delete_takes_a_whole_cluster_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "e\u0301x")

	edit_test_set_caret(g, field, 0)
	GUI.text_input_delete(g, field)

	testing.expect_value(t, edit_test_text(g, field), "x")
	testing.expect_value(t, edit_test_caret(g, field), 0)

	test_gui_destroy(g)
}

@(test)
test_the_selection_is_copied_cut_and_pasted :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "hello")

	GUI.text_input_select_all(g, field)
	GUI.text_input_copy(g, field)
	testing.expect_value(t, GUI.clipboard_get(g), "hello")
	testing.expect_value(t, edit_test_text(g, field), "hello")

	GUI.text_input_cut(g, field)
	testing.expect_value(t, edit_test_text(g, field), "")
	testing.expect_value(t, GUI.clipboard_get(g), "hello")

	GUI.text_input_paste(g, field)
	testing.expect_value(t, edit_test_text(g, field), "hello")

	test_gui_destroy(g)
}

@(test)
test_what_is_typed_replaces_the_selection :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "hello")

	GUI.text_input_select_all(g, field)
	GUI.text_input_insert(g, field, "bye")

	testing.expect_value(t, edit_test_text(g, field), "bye")
	testing.expect_value(t, edit_test_caret(g, field), 3)

	test_gui_destroy(g)
}

@(test)
test_the_caret_moves_over_a_word :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "one two three")

	edit_test_set_caret(g, field, 0)
	GUI.text_input_move_word(g, field, true, false)
	testing.expect_value(t, edit_test_caret(g, field), 4)

	GUI.text_input_move_word(g, field, true, false)
	testing.expect_value(t, edit_test_caret(g, field), 8)

	GUI.text_input_move_word(g, field, false, false)
	testing.expect_value(t, edit_test_caret(g, field), 4)

	test_gui_destroy(g)
}

@(test)
test_the_composition_of_an_ime_is_shown_and_committed :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "hello")

	append(&g.events, GUI.Ime_Editing_Event{text = strings.clone("ni"), start = 0, length = 0})
	GUI.Handle_Events(g)

	testing.expect_value(t, edit_test_text(g, field), "nihello")

	append(&g.events, GUI.Text_Input_Event{text = strings.clone("you")})
	GUI.Handle_Events(g)
	testing.expect_value(t, edit_test_text(g, field), "youhello")

	test_gui_destroy(g)
}

@(test)
test_the_composition_of_an_ime_is_taken_back_when_it_is_cancelled :: proc(t: ^testing.T) {
	g := test_gui(t)
	field := edit_test_field(t, g, "hello")

	append(&g.events, GUI.Ime_Editing_Event{text = strings.clone("ni"), start = 0, length = 0})
	GUI.Handle_Events(g)
	testing.expect_value(t, edit_test_text(g, field), "nihello")

	GUI.focus_clear(g)
	testing.expect_value(t, edit_test_text(g, field), "hello")

	test_gui_destroy(g)
}

//* The tests of the measurement of a text: the size of it, the lines it
//* is broken into and the budget it is cut at.

measure_test_family :: proc(t: ^testing.T, g: ^GUI.GUI) -> GUI.Font_Family_ID {
	family := GUI.Font_Family_Load(g, "assets/fonts/Roboto-Regular.ttf")
	testing.expect_value(t, family != GUI.INVALID_FONT_FAMILY_ID, true)
	return family
}

@(test)
test_the_measurement_of_an_empty_text_is_zero :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := measure_test_family(t, g)
	ts := GUI.Text_Style{size = 16, family = family}

	testing.expect_value(t, GUI.text_measure(g, ts, "", 0), GUI.Vec2{0, 0})

	test_gui_destroy(g)
}

@(test)
test_a_text_with_a_break_in_it_is_two_lines_high :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := measure_test_family(t, g)
	ts := GUI.Text_Style{size = 16, family = family}

	one := GUI.text_measure(g, ts, "Hello", 0)
	two := GUI.text_measure(g, ts, "Hello\nWorld", 0)

	testing.expect_value(t, one.y > 0, true)
	testing.expect_value(t, abs(two.y - one.y * 2) < 0.5, true)

	test_gui_destroy(g)
}

@(test)
test_the_measurement_is_the_same_at_every_scale :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := measure_test_family(t, g)
	ts := GUI.Text_Style{size = 16, family = family}

	plain := GUI.text_measure(g, ts, "Hello, world", 0)
	testing.expect_value(t, plain.x > 0, true)

	GUI.GUI_Set_Scale(g, 2)
	scaled := GUI.text_measure(g, ts, "Hello, world", 0)

	testing.expect_value(t, abs(plain.x - scaled.x) < 0.5, true)
	testing.expect_value(t, abs(plain.y - scaled.y) < 0.5, true)

	test_gui_destroy(g)
}

@(test)
test_a_text_is_broken_at_the_same_place_at_every_scale :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := measure_test_family(t, g)
	ts := GUI.Text_Style{size = 16, family = family, wrap = .Word}
	text := "one two three four five six seven eight nine ten"

	id := GUI.Font_At(g, family, 16)
	lines := GUI.wrap_text_lines(g, GUI.font_get(g, id), ts, text, 100)
	first := len(lines)
	testing.expect_value(t, first > 1, true)

	GUI.GUI_Set_Scale(g, 2)
	id = GUI.Font_At(g, family, 16)
	lines = GUI.wrap_text_lines(g, GUI.font_get(g, id), ts, text, 100)

	testing.expect_value(t, len(lines), first)

	test_gui_destroy(g)
}

@(test)
test_the_lines_of_a_text_hold_their_range :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := measure_test_family(t, g)
	ts := GUI.Text_Style{size = 16, family = family, wrap = .Word}
	text := "one two three four five"

	id := GUI.Font_At(g, family, 16)
	lines := GUI.wrap_text_lines(g, GUI.font_get(g, id), ts, text, 60)
	testing.expect_value(t, len(lines) > 1, true)

	testing.expect_value(t, lines[0].start, 0)
	for i in 0 ..< len(lines) - 1 {
		testing.expect_value(t, lines[i].end, lines[i + 1].start)
	}
	testing.expect_value(t, lines[len(lines) - 1].end, len(text))

	test_gui_destroy(g)
}

@(test)
test_the_overrun_is_cut_at_the_budget :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := measure_test_family(t, g)
	ts := GUI.Text_Style{size = 16, family = family, overrun = .Ellipsis}
	rect := GUI.Rect{x = 0, y = 0, w = 60, h = 40}

	GUI.draw_list_clear(&g.draw, g.viewport)
	g.draw.scale = g.scale
	g.target = &g.draw
	GUI.draw_text(g, ts, "Hello, world, this is a long text", rect, GUI.RGBA(1, 1, 1, 1))
	bounds := scale_test_bounds(&g.draw)

	testing.expect_value(t, bounds.w > 0, true)
	testing.expect_value(t, bounds.w <= rect.w + 4, true)

	test_gui_destroy(g)
}

//* The tests of the public widget API: the setters of the fields a program
//* may write to, the move of a widget in the tree and the children of a
//* widget.

//* A tree that is not out of date in any way, so that a setter that
//* changes nothing can be told from one that marks the widget.
settle :: proc(g: ^GUI.GUI) {
	GUI.layout_pass(g)
	GUI.build_draw_list(g)
}

//* True when the widget is not out of date in any way.
clean :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> bool {
	return !GUI.Widget_Is_Dirty(g, id, .Measure) &&
	       !GUI.Widget_Is_Dirty(g, id, .Arrange) &&
	       !GUI.Widget_Is_Dirty(g, id, .Visual) &&
	       !GUI.Widget_Is_Dirty(g, id, .Hit)
}

//* The place of the first vertex of the draw list that has the colour, or
//* -1 when the colour is not in the list.
first_vertex_of_colour :: proc(g: ^GUI.GUI, colour: GUI.Colour) -> int {
	for vertex, i in g.draw.vertices {
		if vertex.colour == colour { return i }
	}
	return -1
}

//* == The order of the drawing ==

//* The place of a widget in the order of the drawing is the number it has.
//* The widget with the highest number is drawn last, so it lies on top of
//* the others, and it is the one that takes the mouse.
@(test)
test_the_order_of_the_drawing_and_of_the_hit_test_follows_the_z_index :: proc(t: ^testing.T) {
	g := test_gui(t)
	red := GUI.RGBA(1, 0, 0, 1)
	green := GUI.RGBA(0, 1, 0, 1)
	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{
		name = "first",
		style = GUI.Style{box = GUI.StyleBox{bg_color = red}},
	})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{
		name = "second",
		style = GUI.Style{box = GUI.StyleBox{bg_color = green}},
	})
	settle(g)

	//* The two panels lie on top of each other. The one that comes last
	//* in the tree is drawn last, so it lies on top of the other.
	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{10, 10}), second)
	testing.expect_value(t, first_vertex_of_colour(g, red) < first_vertex_of_colour(g, green), true)

	//* The number of a widget puts it in front of the others.
	GUI.Widget_Set_Z_Index(g, first, 1)
	//* The order of the drawing and the order of the hit test change.
	//* The place of the widget does not.
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, first, .Visual), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, first, .Hit), true)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, first, .Arrange), false)
	testing.expect_value(t, GUI.Widget_Is_Dirty(g, first, .Measure), false)
	settle(g)
	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{10, 10}), first)
	testing.expect_value(t, first_vertex_of_colour(g, green) < first_vertex_of_colour(g, red), true)

	test_gui_destroy(g)
}

//* == The clip of the contents ==

//* The clip that is in force when the probe is drawn, and the number of
//* times it has been drawn.
clip_probe_clip: GUI.Rect
clip_probe_drawn: int

//* The drawing of the probe: it remembers the clip that is in force while
//* it is drawn.
clip_probe_draw :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, content: GUI.Rect) {
	clip_probe_drawn += 1
	clip_probe_clip = g.target.current_clip
}

//* A widget that cuts its children to its own rect has that rect in the
//* draw list while the contents are drawn.
@(test)
test_the_contents_of_a_widget_are_cut_to_its_own_rect :: proc(t: ^testing.T) {
	g := test_gui(t)
	class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "ClipProbe",
		kind = GUI.Widget_Kind{draw = clip_probe_draw},
	})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	//* The panel is smaller than the window.
	GUI.Widget_Set_Offsets(g, panel, GUI.Offset{left = 0, top = 0, right = -400, bottom = -300})
	//* The probe does not cut its own contents, so the clip that is in
	//* force while it is drawn is the one of the panel.
	GUI.Make_Custom_Widget(g, panel, class, GUI.Base_Opts{name = "probe", clip_contents = .Off})
	settle(g)

	//* Without the clip the whole of the window is in force.
	GUI.Widget_Set_Clip_Contents(g, panel, false)
	settle(g)
	clip_probe_drawn = 0
	GUI.build_draw_list(g)
	testing.expect_value(t, clip_probe_drawn, 1)
	testing.expect_value(t, clip_probe_clip, GUI.Rect{x = 0, y = 0, w = 800, h = 600})

	//* With the clip the contents are cut to the rect of the widget.
	GUI.Widget_Set_Clip_Contents(g, panel, true)
	settle(g)
	clip_probe_drawn = 0
	GUI.build_draw_list(g)
	testing.expect_value(t, clip_probe_drawn, 1)
	testing.expect_value(t, clip_probe_clip, GUI.Rect{x = 0, y = 0, w = 400, h = 300})

	test_gui_destroy(g)
}

//* == The size ==

@(test)
test_widget_set_manual_size :: proc(t: ^testing.T) {
	g := test_gui(t)
	box := GUI.New_Widget(g, .HBox, g.root, GUI.Widget_Opts{name = "box"})
	panel := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel"})
	settle(g)

	//* A size of zero in one direction means that the program does not
	//* fix that direction.
	GUI.Widget_Set_Manual_Size(g, panel, GUI.Vec2{120, 0})
	testing.expect_value(t, GUI.Widget_Get(g, panel).manual_size.x, 120.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).manual_w, true)
	testing.expect_value(t, GUI.Widget_Get(g, panel).manual_h, false)

	//* The widget has that size after the tree is laid out.
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 120.0)

	settle(g)
	GUI.Widget_Set_Manual_Size(g, panel, GUI.Vec2{120, 0})
	testing.expect_value(t, clean(g, panel), true)

	test_gui_destroy(g)
}

//* == The look ==

//* A widget that can be dragged has a title bar, and the title bar is
//* drawn.
@(test)
test_widget_set_draggable :: proc(t: ^testing.T) {
	g := test_gui(t)
	bg := GUI.RGBA(0.2, 0.2, 0.2, 1)
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{
		name = "panel",
		style = GUI.Style{box = GUI.StyleBox{bg_color = bg}},
	})
	settle(g)

	//* Without the title bar the colour of it is not in the draw list.
	testing.expect_value(t, first_vertex_of_colour(g, GUI.Scale_Colour(bg, 1.6)), -1)

	GUI.Widget_Set_Draggable(g, panel, true)
	testing.expect_value(t, GUI.Widget_Get(g, panel).draggable, true)
	settle(g)
	testing.expect_value(t, first_vertex_of_colour(g, GUI.Scale_Colour(bg, 1.6)) >= 0, true)

	//* The title bar goes away with the flag.
	GUI.Widget_Set_Draggable(g, panel, false)
	settle(g)
	testing.expect_value(t, first_vertex_of_colour(g, GUI.Scale_Colour(bg, 1.6)), -1)

	test_gui_destroy(g)
}

//* == The focus ==

//* The focus really moves: the arrow key goes to the neighbour of the
//* widget that has it.
@(test)
test_the_arrow_key_goes_to_the_neighbour :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	first := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "second"})
	settle(g)

	//* The neighbour is the widget on the right.
	GUI.Widget_Set_Focus_Neighbour(g, first, 2, second)
	testing.expect_value(t, GUI.Widget_Get(g, first).focus_neighbour[2], second)
	testing.expect_value(t, GUI.Focus_Set(g, first), true)
	testing.expect_value(t, g.focused, first)

	append(&g.events, key_event(.Right))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, second)

	test_gui_destroy(g)
}

@(test)
test_widget_set_focus_neighbour :: proc(t: ^testing.T) {
	g := test_gui(t)
	first := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "second"})
	settle(g)

	GUI.Widget_Set_Focus_Neighbour(g, first, 0, second)
	testing.expect_value(t, GUI.Widget_Get(g, first).focus_neighbour[0], second)
	//* The order of the focus is worked out when a key is pressed, so
	//* nothing is marked out of date.
	testing.expect_value(t, clean(g, first), true)

	test_gui_destroy(g)
}

@(test)
test_widget_set_focus_next :: proc(t: ^testing.T) {
	g := test_gui(t)
	first := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "second"})
	settle(g)

	GUI.Widget_Set_Focus_Next(g, first, second)
	testing.expect_value(t, GUI.Widget_Get(g, first).focus_next, second)
	testing.expect_value(t, clean(g, first), true)

	test_gui_destroy(g)
}

@(test)
test_widget_set_focus_previous :: proc(t: ^testing.T) {
	g := test_gui(t)
	first := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "second"})
	settle(g)

	GUI.Widget_Set_Focus_Previous(g, first, second)
	testing.expect_value(t, GUI.Widget_Get(g, first).focus_previous, second)
	testing.expect_value(t, clean(g, first), true)

	test_gui_destroy(g)
}

//* A widget that is not there cannot be named in the focus order. A
//* widget may be its own neighbour: the command palette names itself on
//* every side, so that the arrow keys stay where they are.
@(test)
test_a_focus_neighbour_that_is_not_there_is_refused :: proc(t: ^testing.T) {
	g := test_gui(t)
	button := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "button"})
	other := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "other"})
	gone := GUI.New_Widget(g, .Button, g.root, GUI.Widget_Opts{name = "gone"})
	GUI.Widget_Free(g, gone)
	settle(g)

	//* The widget itself is a neighbour of itself.
	GUI.Widget_Set_Focus_Neighbour(g, button, 0, button)
	testing.expect_value(t, GUI.Widget_Get(g, button).focus_neighbour[0], button)

	//* A handle that names no widget is refused.
	GUI.Widget_Set_Focus_Neighbour(g, button, 1, gone)
	testing.expect_value(t, GUI.Widget_Get(g, button).focus_neighbour[1], GUI.INVALID_WIDGET_ID)

	//* A direction that is not one of the four is refused.
	GUI.Widget_Set_Focus_Neighbour(g, button, 7, other)
	testing.expect_value(t, GUI.Widget_Get(g, button).focus_neighbour[0], button)

	//* The order of the tab key is kept whole in the same way.
	GUI.Widget_Set_Focus_Next(g, button, gone)
	testing.expect_value(t, GUI.Widget_Get(g, button).focus_next, GUI.INVALID_WIDGET_ID)
	GUI.Widget_Set_Focus_Previous(g, button, gone)
	testing.expect_value(t, GUI.Widget_Get(g, button).focus_previous, GUI.INVALID_WIDGET_ID)

	//* Nothing was marked out of date by the refused calls.
	testing.expect_value(t, clean(g, button), true)

	//* A widget that is there is taken.
	GUI.Widget_Set_Focus_Next(g, button, other)
	testing.expect_value(t, GUI.Widget_Get(g, button).focus_next, other)
	testing.expect_value(t, clean(g, button), true)

	test_gui_destroy(g)
}

//* == The text ==

//* The number of the command that is picked in a command palette.
palette_selected :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> int {
	w := GUI.Widget_Get(g, id)
	if w == nil { return -1 }
	#partial switch d in w.data {
	case GUI.Command_Palette_Data:
		return d.selected
	}
	return -1
}

//* The filter of a command palette has changed, so the selection starts
//* again at the first command that is left. The number that was picked
//* names no command any more.
@(test)
test_the_text_of_a_command_palette_starts_the_selection_again :: proc(t: ^testing.T) {
	g := test_gui(t)
	palette := GUI.Make_Command_Palette(g, g.root, GUI.Command_Palette_Opts{
		Base_Opts = GUI.Base_Opts{name = "palette"},
	})
	GUI.Command_Palette_Add(g, palette, "open", nil, "open")
	GUI.Command_Palette_Add(g, palette, "save", nil, "save")
	GUI.Command_Palette_Add(g, palette, "close", nil, "close")

	//* The filter lets "open" and "close" through, and the second of
	//* them is picked.
	GUI.Command_Palette_Set_Text(g, palette, "o")
	testing.expect_value(t, GUI.Command_Palette_Count(g, palette), 2)
	GUI.command_palette_move(g, palette, 1)
	testing.expect_value(t, palette_selected(g, palette), 1)

	//* The filter of the palette is changed through the setter of the
	//* widget: the selection starts again at the first command that is
	//* left, so that the palette runs a command that is there.
	GUI.Widget_Set_Text(g, palette, "op")
	testing.expect_value(t, GUI.Command_Palette_Count(g, palette), 1)
	testing.expect_value(t, palette_selected(g, palette), 0)

	test_gui_destroy(g)
}

//* An allocator that fills the memory with a sign when it is given back.
//* A text that is read after its memory was given back is then seen.
Poison_Allocator :: struct {
	base:  mem.Allocator,
	sizes: map[rawptr]int,
}

//* The allocator that fills the memory with a sign when it is given back.
poison_allocator :: proc(poison: ^Poison_Allocator) -> mem.Allocator {
	return mem.Allocator{
		data = poison,
		procedure = poison_allocator_proc,
	}
}

//* The work of the allocator: the size of the memory is kept while it is
//* out, and the memory is filled with a sign before it is given back.
poison_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (result: []byte, err: mem.Allocator_Error) {
	poison := cast(^Poison_Allocator)(allocator_data)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		result, err = poison.base.procedure(poison.base.data, mode, size, alignment, old_memory, old_size, loc)
		if err == nil && len(result) > 0 {
			poison.sizes[raw_data(result)] = len(result)
		}
		return
	case .Free:
		if used, ok := poison.sizes[old_memory]; ok {
			signs := ([^]u8)(old_memory)
			for i in 0 ..< used {signs[i] = 0xFF}
			delete_key(&poison.sizes, old_memory)
		}
	}
	return poison.base.procedure(poison.base.data, mode, size, alignment, old_memory, old_size, loc)
}

//* The text of a widget may be the text of the widget itself: the copy is
//* made before the old text is given back, so the text of the caller is
//* still there when it is copied.
@(test)
test_the_text_of_a_widget_may_be_the_text_of_the_widget_itself :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	//* The allocator fills the memory with a sign when it is given back,
	//* so that a text that is read after the memory was given back is
	//* seen at once.
	poison: Poison_Allocator
	poison.base = context.allocator
	poison.sizes = make(map[rawptr]int, poison.base)
	context.allocator = poison_allocator(&poison)
	defer delete(poison.sizes)
	defer context.allocator = poison.base

	palette := GUI.Make_Command_Palette(g, g.root, GUI.Command_Palette_Opts{
		Base_Opts = GUI.Base_Opts{name = "palette"},
	})
	GUI.Command_Palette_Set_Text(g, palette, "hello")
	testing.expect_value(t, GUI.Command_Palette_Text(g, palette), "hello")

	//* The text of the caller is the text of the palette.
	GUI.Widget_Set_Text(g, palette, GUI.Command_Palette_Text(g, palette)[:2])
	testing.expect_value(t, GUI.Command_Palette_Text(g, palette), "he")
}

//* == The tree ==

//* A parent that is not there is refused: the tree is left as it was.
@(test)
test_widget_set_parent :: proc(t: ^testing.T) {
	g := test_gui(t)
	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})
	child := GUI.New_Widget(g, .Panel, first, GUI.Widget_Opts{name = "child"})

	GUI.Widget_Set_Parent(g, second, child)
	testing.expect_value(t, GUI.Widget_Get(g, child).parent, second)
	testing.expect_value(t, GUI.Widget_Child_Count(g, first), 0)
	testing.expect_value(t, GUI.Widget_Child_Count(g, second), 1)

	//* The old name does the same.
	GUI.Widget_Reparent(g, first, child)
	testing.expect_value(t, GUI.Widget_Get(g, child).parent, first)
	testing.expect_value(t, GUI.Widget_Child_Count(g, first), 1)
	testing.expect_value(t, GUI.Widget_Child_Count(g, second), 0)

	//* A parent that is not there is refused, and the child stays where
	//* it is.
	gone := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "gone"})
	GUI.Widget_Free(g, gone)
	GUI.Widget_Set_Parent(g, gone, child)
	testing.expect_value(t, GUI.Widget_Get(g, child).parent, first)
	testing.expect_value(t, GUI.Widget_Child_Count(g, first), 1)
	testing.expect_value(t, GUI.Widget_Child_Count(g, second), 0)

	//* The empty handle is refused as well.
	GUI.Widget_Set_Parent(g, GUI.INVALID_WIDGET_ID, child)
	testing.expect_value(t, GUI.Widget_Get(g, child).parent, first)
	testing.expect_value(t, GUI.Widget_Child_Count(g, first), 1)

	test_gui_destroy(g)
}

@(test)
test_widget_children :: proc(t: ^testing.T) {
	g := test_gui(t)
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second"})
	third := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "third"})

	//* The children come in the order of the tree.
	children := GUI.Widget_Children(g, box)
	testing.expect_value(t, len(children), 3)
	testing.expect_value(t, children[0], first)
	testing.expect_value(t, children[1], second)
	testing.expect_value(t, children[2], third)

	//* The slice belongs to the caller: giving it back leaves the tree
	//* as it was.
	delete(children)
	testing.expect_value(t, GUI.Widget_Child_Count(g, box), 3)
	testing.expect_value(t, GUI.Widget_Get(g, first).parent, box)

	//* A widget without children gives nothing.
	testing.expect_value(t, len(GUI.Widget_Children(g, first)), 0)

	test_gui_destroy(g)
}

//* The children are given back to the caller: the memory is his, and he
//* gives it back.
@(test)
test_the_children_are_the_memory_of_the_caller :: proc(t: ^testing.T) {
	g := test_gui(t)
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box"})
	GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first"})
	GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second"})

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	children := GUI.Widget_Children(g, box, allocator)
	testing.expect_value(t, len(children), 2)
	testing.expect_value(t, track.total_allocation_count > 0, true)

	delete(children, allocator)
	testing.expect_value(t, track.current_memory_allocated, 0)

	test_gui_destroy(g)
}

//* Tests for the canvas: the widget the program draws in itself.

//* The paint procedure of the canvas in the tests: it puts one
//* rectangle in the canvas.
canvas_test_paint :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, state: ^GUI.Canvas_State) {
	GUI.canvas_add_rect(g, id, GUI.Vec2{10, 10}, GUI.Vec2{40, 20}, GUI.RGBA(1, 0, 0, 1))
}

//* == The canvas ==

@(test)
test_a_canvas_holds_what_the_program_puts_in_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	canvas := GUI.Make_Canvas(
		g,
		g.root,
		GUI.Canvas_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "canvas",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 180},
			},
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.canvas_item_count(g, canvas), 0)

	GUI.canvas_add_rect(g, canvas, GUI.Vec2{10, 10}, GUI.Vec2{40, 20}, GUI.RGBA(1, 0, 0, 1))
	GUI.canvas_add_circle(g, canvas, GUI.Vec2{60, 10}, GUI.Vec2{20, 20}, GUI.RGBA(0, 1, 0, 1))
	GUI.canvas_add_line(g, canvas, GUI.Vec2{10, 40}, GUI.Vec2{80, 60}, GUI.RGBA(0, 0, 1, 1))
	GUI.canvas_add_text(g, canvas, GUI.Vec2{10, 70}, "hello", GUI.RGBA(1, 1, 1, 1))
	testing.expect_value(t, GUI.canvas_item_count(g, canvas), 4)

	//* The things are kept in the order they were put in.
	state := GUI.canvas_data(g, canvas).state
	testing.expect_value(t, state.items[0].kind, .Rect)
	testing.expect_value(t, state.items[1].kind, .Circle)
	testing.expect_value(t, state.items[2].kind, .Line)
	testing.expect_value(t, state.items[3].kind, .Text)
	testing.expect_value(t, state.items[3].text, "hello")

	//* The canvas can be emptied.
	GUI.canvas_clear(g, canvas)
	testing.expect_value(t, GUI.canvas_item_count(g, canvas), 0)

	GUI.canvas_add_rect(g, canvas, GUI.Vec2{10, 10}, GUI.Vec2{40, 20}, GUI.RGBA(1, 0, 0, 1))
	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_canvas_places_its_items_in_its_own_room :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	canvas := GUI.Make_Canvas(
		g,
		g.root,
		GUI.Canvas_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "canvas",
				preset = .Top_Left,
				offsets = GUI.Offset{40, 30, 240, 210},
			},
		},
	)
	GUI.layout_pass(g)
	GUI.canvas_add_rect(g, canvas, GUI.Vec2{10, 20}, GUI.Vec2{40, 20}, GUI.RGBA(1, 0, 0, 1))
	GUI.Frame(g)

	content := GUI.content_rect(g, GUI.Widget_Get(g, canvas))

	min_x, min_y := f32(1e6), f32(1e6)
	max_x, max_y := f32(-1e6), f32(-1e6)
	count := 0
	red := GUI.RGBA(1, 0, 0, 1)
	for v in g.draw.vertices {
		if v.colour != red {continue}
		count += 1
		min_x = min(min_x, v.pos[0])
		min_y = min(min_y, v.pos[1])
		max_x = max(max_x, v.pos[0])
		max_y = max(max_y, v.pos[1])
	}
	testing.expect_value(t, count, 4)
	testing.expect_value(t, min_x, content.x + 10)
	testing.expect_value(t, min_y, content.y + 20)
	testing.expect_value(t, max_x, content.x + 50)
	testing.expect_value(t, max_y, content.y + 40)

	test_gui_destroy(g)
}

@(test)
test_a_canvas_is_painted_every_frame :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	canvas := GUI.Make_Canvas(
		g,
		g.root,
		GUI.Canvas_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "canvas",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 180},
			},
		},
	)
	GUI.canvas_set_paint(g, canvas, canvas_test_paint)
	GUI.layout_pass(g)

	//* The canvas is empty until it is painted.
	testing.expect_value(t, GUI.canvas_item_count(g, canvas), 0)

	GUI.Frame(g)
	testing.expect_value(t, GUI.canvas_item_count(g, canvas), 1)

	//* The next frame paints it again: what was in it is gone, and the
	//* paint procedure fills it again.
	GUI.Frame(g)
	testing.expect_value(t, GUI.canvas_item_count(g, canvas), 1)

	test_gui_destroy(g)
}

//* Tests for the chart: the bars, the lines and the pie.

//* == The chart ==

@(test)
test_a_chart_holds_its_series :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	chart := GUI.Make_Chart(
		g,
		g.root,
		GUI.Chart_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "chart",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 400, 240},
			},
			kind = .Bar,
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.chart_series_count(g, chart), 0)

	GUI.chart_add_series(g, chart, "Monday", {12, 18, 9, 24, 15}, GUI.RGBA(0.25, 0.60, 1.00, 1))
	GUI.chart_add_series(g, chart, "Tuesday", {8, 14, 12, 19, 11}, GUI.RGBA(0.95, 0.55, 0.20, 1))
	testing.expect_value(t, GUI.chart_series_count(g, chart), 2)

	//* The chart has as many points as the longest series has.
	data := GUI.chart_of(g, chart)
	testing.expect_value(t, GUI.chart_point_count(data), 5)

	//* The value of a point is the one of the first series.
	testing.expect_value(t, GUI.chart_value_at(g, chart, 0), 12.0)
	testing.expect_value(t, GUI.chart_value_at(g, chart, 99), 0.0)

	//* The bounds of the chart are the smallest and the largest number
	//* in it.
	testing.expect_value(t, data.min, 8.0)
	testing.expect_value(t, data.max, 24.0)

	//* The names under the points are kept.
	GUI.chart_set_labels(g, chart, {"Mon", "Tue", "Wed", "Thu", "Fri"})
	testing.expect_value(t, len(data.labels), 5)
	testing.expect_value(t, data.labels[0], "Mon")

	GUI.chart_set_kind(g, chart, .Line)
	testing.expect_value(t, data.kind, .Line)

	test_gui_destroy(g)
}

@(test)
test_a_chart_picks_the_point_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	chart := GUI.Make_Chart(
		g,
		g.root,
		GUI.Chart_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "chart",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 400, 240},
			},
			kind = .Bar,
		},
	)
	GUI.chart_add_series(g, chart, "Monday", {12, 18, 9, 24, 15}, GUI.RGBA(0.25, 0.60, 1.00, 1))
	GUI.layout_pass(g)

	//* The second point is in the second slot of the chart.
	content := GUI.content_rect(g, GUI.Widget_Get(g, chart))
	plot := GUI.chart_plot_rect(content)
	slot := plot.w / 5
	point := GUI.Vec2{plot.x + slot * 1.5, plot.y + plot.h * 0.5}
	testing.expect_value(t, GUI.chart_point_at(g, chart, point), 1)

	append(&g.events, mouse_down({point.x, point.y}, 1))
	append(&g.events, mouse_up({point.x, point.y}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.chart_of(g, chart).selected, 1)

	testing.expect_value(t, GUI.chart_point_at(g, chart, GUI.Vec2{-100, -100}), -1)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_pie_chart_is_drawn_from_its_first_series :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	chart := GUI.Make_Chart(
		g,
		g.root,
		GUI.Chart_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "chart",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 240},
			},
			kind = .Pie,
		},
	)
	GUI.chart_add_series(g, chart, "Share", {3, 1}, GUI.RGBA(0.25, 0.60, 1.00, 1))
	GUI.layout_pass(g)

	//* The first slice is the big one, so the pointer on the right of
	//* the middle of the pie is in it. The second slice is the small
	//* one at the top left.
	content := GUI.content_rect(g, GUI.Widget_Get(g, chart))
	centre, radius := GUI.chart_pie_geometry(content)
	testing.expect_value(t, GUI.chart_pie_point_at(GUI.chart_of(g, chart), content, GUI.Vec2{centre.x + radius * 0.5, centre.y}), 0)
	testing.expect_value(t, GUI.chart_pie_point_at(GUI.chart_of(g, chart), content, GUI.Vec2{centre.x - radius * 0.35, centre.y - radius * 0.35}), 1)

	testing.expect_value(t, GUI.chart_pie_point_at(GUI.chart_of(g, chart), content, GUI.Vec2{-100, -100}), -1)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* Tests for the collection widgets: the rating, the segmented control,
//* the switch, the accordion, the virtual list, the data table, the
//* colour picker and the emoji picker.

//* == The rating ==

@(test)
test_a_rating_picks_the_mark_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	rating := GUI.Make_Rating(g, g.root, GUI.Rating_Opts{value = 1, max = 5})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.rating_value(g, rating), 1.0)

	//* The marks stand in slots, so the pointer says which one it is on.
	testing.expect_value(t, GUI.rating_mark_at(g, rating, 8.0), 0)
	testing.expect_value(t, GUI.rating_mark_at(g, rating, 40.0), 2)
	testing.expect_value(t, GUI.rating_mark_at(g, rating, 5000.0), -1)

	append(&g.events, mouse_down({40, 10}, 1))
	append(&g.events, mouse_up({40, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.rating_value(g, rating), 3.0)

	//* The value is kept between zero and the number of marks.
	GUI.rating_set(g, rating, 99)
	testing.expect_value(t, GUI.rating_value(g, rating), 5.0)
	GUI.rating_set(g, rating, -3)
	testing.expect_value(t, GUI.rating_value(g, rating), 0.0)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The segmented control ==

@(test)
test_a_segmented_control_picks_the_piece_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	control := GUI.Make_Segmented(g, g.root, GUI.Segmented_Opts{items = {"One", "Two", "Three"}})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.segmented_count(g, control), 3)
	testing.expect_value(t, GUI.segmented_text(g, control), "")

	//* The pieces share the width, so the second one is in the middle.
	append(&g.events, mouse_down({300, 10}, 1))
	append(&g.events, mouse_up({300, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.segmented_text(g, control), "Two")

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The switch ==

@(test)
test_a_toggle_switch_turns_on_and_off_when_it_is_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	lever := GUI.Make_Toggle_Switch(g, g.root, GUI.Toggle_Switch_Opts{text = "wifi", on = false})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.toggle_switch_is_on(g, lever), false)

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.toggle_switch_is_on(g, lever), true)

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.toggle_switch_is_on(g, lever), false)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The accordion ==

@(test)
test_an_accordion_opens_the_section_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	accordion := GUI.Make_Accordion(g, g.root, GUI.Accordion_Opts{})
	first := GUI.New_Widget(g, .Label, accordion, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Label, accordion, GUI.Widget_Opts{name = "second"})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.accordion_open_section(g, accordion), -1)

	append(&g.events, mouse_down({10, GUI.ACCORDION_HEADER_HEIGHT + 5}, 1))
	append(&g.events, mouse_up({10, GUI.ACCORDION_HEADER_HEIGHT + 5}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.accordion_open_section(g, accordion), 1)

	//* The open section has a height, and the shut one has none.
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, second).rect.h > 0, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.h, 0.0)

	append(&g.events, mouse_down({10, GUI.ACCORDION_HEADER_HEIGHT + 5}, 1))
	append(&g.events, mouse_up({10, GUI.ACCORDION_HEADER_HEIGHT + 5}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.accordion_open_section(g, accordion), -1)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The colour picker ==

@(test)
test_a_colour_picker_puts_the_colour_together_from_its_parts :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	picker := GUI.Make_Color_Picker(g, g.root, GUI.Color_Picker_Opts{colour = GUI.RGBA(1, 0, 0, 1)})
	GUI.layout_pass(g)

	colour := GUI.color_picker_colour(g, picker)
	testing.expect_value(t, colour.r, 1.0)
	testing.expect_value(t, colour.g, 0.0)

	#partial switch d in GUI.Widget_Get(g, picker).data {
	case GUI.Color_Picker_Data:
		testing.expect_value(t, d.hue, 0.0)
		testing.expect_value(t, d.saturation, 1.0)
		testing.expect_value(t, d.value, 1.0)
	}

	//* A colour that is set from its parts comes back the same.
	GUI.color_picker_set_hsv(g, picker, 0.5, 1, 1)
	colour = GUI.color_picker_colour(g, picker)
	testing.expect_value(t, colour.r, 0.0)
	testing.expect_value(t, colour.g, 1.0)
	testing.expect_value(t, colour.b, 1.0)

	//* A colour that is set is taken apart again.
	GUI.color_picker_set(g, picker, GUI.RGBA(0, 0, 1, 1))
	colour = GUI.color_picker_colour(g, picker)
	testing.expect_value(t, colour.b, 1.0)
	testing.expect_value(t, colour.r, 0.0)

	//* A click on the field opens the picker.
	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_is_open(g, picker), true)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_the_code_of_a_colour_can_be_typed :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	picker := GUI.Make_Color_Picker(
		g,
		g.root,
		GUI.Color_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "colour", preset = .Top_Left, offsets = GUI.Offset{0, 0, 200, 40}},
			colour = GUI.RGBA(1, 0, 0, 1),
		},
	)
	GUI.layout_pass(g)

	//* The code of the colour is shown in the field.
	testing.expect_value(t, GUI.color_picker_code(g, picker), "#FF0000")

	//* A click on the code starts the typing of it.
	append(&g.events, mouse_down({30, 10}, 1))
	append(&g.events, mouse_up({30, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_is_editing(g, picker), true)
	testing.expect_value(t, g.focused, picker)

	//* The whole of the code is taken, and the text that is typed goes
	//* in its place.
	append(&g.events, key_event(.A, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	GUI.fire_text(g, picker, "00FF00")
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "00FF00")

	//* The enter key takes the colour that is written.
	append(&g.events, key_event(.Enter))
	GUI.Handle_Events(g)
	colour := GUI.color_picker_colour(g, picker)
	testing.expect_value(t, colour.g, 1.0)
	testing.expect_value(t, colour.r, 0.0)
	testing.expect_value(t, GUI.color_picker_is_editing(g, picker), false)

	//* The escape key throws the typing away.
	append(&g.events, mouse_down({30, 10}, 1))
	append(&g.events, mouse_up({30, 10}))
	GUI.Handle_Events(g)
	GUI.fire_text(g, picker, "00FF")
	append(&g.events, key_event(.Escape))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_is_editing(g, picker), false)
	testing.expect_value(t, GUI.color_picker_colour(g, picker).g, 1.0)

	test_gui_destroy(g)
}

@(test)
test_the_code_of_a_colour_can_be_taken_cut_and_pasted :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	picker := GUI.Make_Color_Picker(
		g,
		g.root,
		GUI.Color_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "colour", preset = .Top_Left, offsets = GUI.Offset{0, 0, 200, 40}},
			colour = GUI.RGBA(1, 0, 0, 1),
		},
	)
	GUI.layout_pass(g)

	//* The typing of the code starts with a click on the code.
	append(&g.events, mouse_down({30, 10}, 1))
	append(&g.events, mouse_up({30, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_is_editing(g, picker), true)

	//* A drag takes the text between the two ends.
	append(&g.events, mouse_down({30, 10}, 1))
	append(&g.events, mouse_move({60, 10}))
	GUI.Handle_Events(g)
	append(&g.events, key_event(.C, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	taken := GUI.clipboard_get(g)
	testing.expect_value(t, taken != "", true)
	testing.expect_value(t, strings.contains("#FF0000", taken), true)
	append(&g.events, mouse_up({60, 10}))
	GUI.Handle_Events(g)

	//* The whole of the code is taken.
	append(&g.events, key_event(.A, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)

	//* The code that is taken goes on the clipboard.
	append(&g.events, key_event(.C, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.clipboard_get(g), "#FF0000")

	//* The code that is taken is cut away from the field.
	append(&g.events, key_event(.X, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "")
	testing.expect_value(t, GUI.clipboard_get(g), "#FF0000")

	//* What is on the clipboard is pasted into the code.
	append(&g.events, key_event(.V, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "#FF0000")

	//* Only the characters that a code is made of are pasted.
	GUI.clipboard_set(g, "not a colour")
	append(&g.events, key_event(.A, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	append(&g.events, key_event(.V, GUI.Mods{.Ctrl}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "ac")

	test_gui_destroy(g)
}

@(test)
test_a_colour_picker_follows_the_pointer_while_the_mouse_is_down :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	picker := GUI.Make_Color_Picker(
		g,
		g.root,
		GUI.Color_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "colour", preset = .Top_Left, offsets = GUI.Offset{0, 0, 200, 200}},
			colour = GUI.RGBA(1, 0, 0, 1),
		},
	)
	GUI.layout_pass(g)
	GUI.color_picker_set_open(g, picker, true)
	GUI.layout_pass(g)

	layout := GUI.color_picker_layout(GUI.color_picker_content(g, GUI.Widget_Get(g, picker)), true)
	middle := layout.hue.x + layout.hue.w * 0.5
	right := layout.hue.x + layout.hue.w * 0.9

	//* A press on the strip of hues picks a colour.
	append(&g.events, mouse_down({middle, layout.hue.y + 2}, 1))
	GUI.Handle_Events(g)
	colour := GUI.color_picker_colour(g, picker)
	testing.expect_value(t, colour.g > 0.0, true)

	//* The colour follows the pointer while the mouse is down.
	append(&g.events, mouse_move({right, layout.hue.y + 2}))
	GUI.Handle_Events(g)
	moved := GUI.color_picker_colour(g, picker)
	testing.expect_value(t, moved != colour, true)

	//* The mouse is let go.
	append(&g.events, mouse_up({right, layout.hue.y + 2}))
	GUI.Handle_Events(g)

	//* The colour does not follow the pointer any more.
	append(&g.events, mouse_move({middle, layout.hue.y + 2}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.color_picker_colour(g, picker), moved)

	test_gui_destroy(g)
}


//* == The emoji picker ==

@(test)
test_an_emoji_picker_picks_the_emoji_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	picker := GUI.Make_Emoji_Picker(g, g.root, GUI.Emoji_Picker_Opts{emoji = "😀"})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.emoji_picker_emoji(g, picker), "😀")

	GUI.emoji_picker_set(g, picker, "🚀")
	testing.expect_value(t, GUI.emoji_picker_emoji(g, picker), "🚀")

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.emoji_picker_is_open(g, picker), true)

	//* A click on the first emoji of the group picks it.
	entries := GUI.emoji_in_group(g, 0)
	testing.expect_value(t, len(entries) > 0, true)
	append(&g.events, mouse_down({90, 40}, 1))
	append(&g.events, mouse_up({90, 40}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.emoji_picker_emoji(g, picker), entries[0].emoji)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The table of the emoji ==

@(test)
test_the_table_of_the_emoji_holds_every_group :: proc(t: ^testing.T) {
	g := test_gui(t)

	testing.expect_value(t, GUI.emoji_group_count(), 8)
	testing.expect_value(t, GUI.emoji_group_name(g, 0), "smileys")
	testing.expect_value(t, GUI.emoji_group_name(g, 7), "flags")
	testing.expect_value(t, GUI.emoji_group_name(g, 99), "")

	for index in 0 ..< GUI.emoji_group_count() {
		entries := GUI.emoji_in_group(g, index)
		testing.expect_value(t, len(entries) > 0, true)
	}

	testing.expect_value(t, GUI.emoji_by_name(g, "rocket"), "🚀")
	testing.expect_value(t, GUI.emoji_by_name(g, "not_an_emoji"), "")

	test_gui_destroy(g)
}

//* Tests for the rich text editor: the text, the cursors and the
//* editing.

//* == The rich text editor ==

@(test)
test_the_editor_holds_its_text :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "editor",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 320, 160},
			},
			text = "The text of the editor.",
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "The text of the editor.")

	GUI.rich_text_editor_set_text(g, editor, "Another text.")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "Another text.")

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_the_editor_edits_its_text :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "editor",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 320, 160},
			},
			text = "abc",
		},
	)
	GUI.layout_pass(g)

	//* The caret is at the end of the text.
	testing.expect_value(t, GUI.rich_text_editor_cursor_count(g, editor), 1)
	cursor := GUI.rich_text_editor_cursor(g, editor, 0)
	testing.expect_value(t, cursor.caret, 3)

	GUI.rich_text_editor_insert(g, editor, "d")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "abcd")

	GUI.rich_text_editor_backspace(g, editor)
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "abc")

	GUI.rich_text_editor_set_caret(g, editor, 0, false)
	GUI.rich_text_editor_insert(g, editor, "x")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "xabc")

	//* The whole text can be picked, and what is typed then replaces
	//* it.
	GUI.rich_text_editor_select_all(g, editor)
	testing.expect_value(t, GUI.rich_text_editor_cursor(g, editor, 0).sel_start, 0)
	testing.expect_value(t, GUI.rich_text_editor_cursor(g, editor, 0).sel_end, 4)
	GUI.rich_text_editor_insert(g, editor, "y")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "y")

	GUI.rich_text_editor_set_caret(g, editor, 0, false)
	GUI.rich_text_editor_delete(g, editor)
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "")

	test_gui_destroy(g)
}

@(test)
test_the_editor_has_more_than_one_cursor :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	editor := GUI.Make_Rich_Text_Editor(
		g,
		g.root,
		GUI.Rich_Text_Editor_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "editor",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 320, 160},
			},
			text = "hello",
		},
	)
	GUI.layout_pass(g)

	//* A second cursor is put at the start of the text.
	index := GUI.rich_text_editor_add_cursor(g, editor, 0)
	testing.expect_value(t, index, 1)
	testing.expect_value(t, GUI.rich_text_editor_cursor_count(g, editor), 2)

	//* What is typed goes in at both carets.
	GUI.rich_text_editor_insert(g, editor, "!")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "!hello!")

	testing.expect_value(t, GUI.rich_text_editor_remove_cursor(g, editor, 1), 1)
	testing.expect_value(t, GUI.rich_text_editor_cursor_count(g, editor), 1)

	//* A cursor that is not there cannot be taken away.
	testing.expect_value(t, GUI.rich_text_editor_remove_cursor(g, editor, 9), -1)

	test_gui_destroy(g)
}

@(test)
test_the_editor_can_be_wrapped_and_scrolled :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	editor := GUI.Make_Rich_Text_Editor(g, g.root, GUI.Rich_Text_Editor_Opts{text = "hello"})
	GUI.layout_pass(g)

	//* The text is not wrapped when nothing is said.
	testing.expect_value(t, GUI.rich_text_editor_is_wrapped(g, editor), false)
	GUI.rich_text_editor_set_wrap(g, editor, true)
	testing.expect_value(t, GUI.rich_text_editor_is_wrapped(g, editor), true)

	state := GUI.rich_text_editor_state(g, editor)
	GUI.rich_text_editor_scroll(g, editor, GUI.Vec2{0, 20})
	testing.expect_value(t, state.scroll.y, 20.0)

	test_gui_destroy(g)
}

//* Tests for the fields that came later: the combo box, the search
//* field, the number input, the chat input, the date picker and the
//* time picker.

//* == The combo box ==

@(test)
test_a_combo_box_picks_the_thing_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	combo := GUI.Make_Combo_Box(
		g,
		g.root,
		GUI.Combo_Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "combo",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 200, 120},
			},
			items = {"Red", "Green", "Blue"},
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.combo_box_count(g, combo), 3)
	testing.expect_value(t, GUI.combo_box_selected(g, combo), -1)
	testing.expect_value(t, GUI.combo_box_text(g, combo), "")

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.combo_box_is_open(g, combo), true)

	//* A click on the second thing picks it, and the list closes.
	append(&g.events, mouse_down({10, GUI.COMBO_BOX_FIELD_HEIGHT + 30}, 1))
	append(&g.events, mouse_up({10, GUI.COMBO_BOX_FIELD_HEIGHT + 30}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.combo_box_selected(g, combo), 1)
	testing.expect_value(t, GUI.combo_box_text(g, combo), "Green")
	testing.expect_value(t, GUI.combo_box_is_open(g, combo), false)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_combo_box_takes_the_thing_that_is_picked :: proc(t: ^testing.T) {
	g := test_gui(t)

	combo := GUI.Make_Combo_Box(g, g.root, GUI.Combo_Box_Opts{items = {"One", "Two"}})
	GUI.combo_box_select(g, combo, 1)
	testing.expect_value(t, GUI.combo_box_selected(g, combo), 1)
	testing.expect_value(t, GUI.combo_box_item_text(g, combo, 0), "One")

	//* A thing that is not on offer cannot be picked.
	GUI.combo_box_select(g, combo, 9)
	testing.expect_value(t, GUI.combo_box_selected(g, combo), 1)

	//* A thing can be put on offer later.
	GUI.combo_box_add_item(g, combo, "Three")
	testing.expect_value(t, GUI.combo_box_count(g, combo), 3)
	testing.expect_value(t, GUI.combo_box_item_text(g, combo, 2), "Three")

	test_gui_destroy(g)
}

//* == The size of the combo box ==

@(test)
test_a_combo_box_is_as_wide_as_the_widest_of_its_things :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{})
	narrow := GUI.Make_Combo_Box(g, box, GUI.Combo_Box_Opts{items = {"One"}})
	wide := GUI.Make_Combo_Box(g, box, GUI.Combo_Box_Opts{items = {"One thing that is much longer"}})
	GUI.layout_pass(g)

	//* The field is as wide as the widest of the things on offer.
	testing.expect_value(t, GUI.Widget_Get(g, wide).rect.w > GUI.Widget_Get(g, narrow).rect.w, true)

	test_gui_destroy(g)
}

@(test)
test_a_combo_box_keeps_the_size_the_program_asks_for :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	combo := GUI.Make_Combo_Box(
		g,
		g.root,
		GUI.Combo_Box_Opts{
			Base_Opts = GUI.Base_Opts{min_size = GUI.Vec2{150, 0}, max_size = GUI.Vec2{200, 0}},
			items = {"One thing that is much longer than the room it is given"},
		},
	)
	GUI.layout_pass(g)

	//* The smallest size of the program is the smallest size of the box,
	//* and the largest size of the program is the largest size of it.
	w := GUI.Widget_Get(g, combo)
	testing.expect_value(t, w.min_size.x >= 150.0, true)
	testing.expect_value(t, w.min_size.x <= 200.0, true)

	test_gui_destroy(g)
}

@(test)
test_a_combo_box_can_be_told_to_fill_the_room_it_is_given :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	box := GUI.Make_HBox(g, g.root, GUI.Box_Opts{})
	combo := GUI.Make_Combo_Box(
		g,
		box,
		GUI.Combo_Box_Opts{
			Base_Opts = GUI.Base_Opts{size_flags_h = GUI.Size_Flags{.Fill, .Expand}},
			items = {"One"},
		},
	)
	GUI.layout_pass(g)

	//* The box fills the room of its parent, and the combo box fills
	//* the box along the same axis.
	testing.expect_value(t, GUI.Widget_Get(g, combo).rect.w > 100.0, true)

	test_gui_destroy(g)
}

//* == The search field ==

@(test)
test_a_search_field_takes_the_text_that_is_typed :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.Make_Search_Field(
		g,
		g.root,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "search",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 30},
			},
			placeholder = "Search",
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.search_field_is_empty(g, field), true)
	testing.expect_value(t, GUI.search_field_placeholder(g, field), "Search")

	append(&g.events, mouse_down({40, 10}, 1))
	append(&g.events, mouse_up({40, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, field)

	append(&g.events, GUI.Key_Down_Event{key = .O})
	append(&g.events, GUI.Key_Down_Event{key = .D})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.search_field_text(g, field), "od")

	append(&g.events, GUI.Key_Down_Event{key = .Backspace})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.search_field_text(g, field), "o")

	//* The escape key empties the field, and the program does not quit.
	append(&g.events, GUI.Key_Down_Event{key = .Escape})
	GUI.Handle_Events(g)
	GUI.Frame(g)
	testing.expect_value(t, GUI.search_field_text(g, field), "")
	testing.expect_value(t, g.quit_requested, false)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_search_field_can_be_emptied_with_its_button :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.Make_Search_Field(
		g,
		g.root,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "search",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 30},
			},
			text = "odin",
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.search_field_text(g, field), "odin")

	//* The button at the right of the field empties it.
	button := GUI.search_field_clear_rect(GUI.search_field_content(g, GUI.Widget_Get(g, field)))
	append(&g.events, mouse_down({button.x + 2, button.y + 2}, 1))
	append(&g.events, mouse_up({button.x + 2, button.y + 2}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.search_field_text(g, field), "")

	test_gui_destroy(g)
}

@(test)
test_a_search_field_is_as_wide_as_the_text_in_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 400, 200}})
	field := GUI.Make_Search_Field(
		g,
		box,
		GUI.Search_Field_Opts{Base_Opts = GUI.Base_Opts{name = "search"}, placeholder = "Search"},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, field)
	//* The field is as wide as the text that says what it is for.
	empty_width := w.min_size.x
	testing.expect_value(t, empty_width > 0, true)
	testing.expect_value(t, w.rect.w, empty_width)

	//* The text that says what the field is for fits in it: it is not
	//* cut short.
	content := GUI.search_field_content(g, w)
	label := GUI.search_field_text_rect(g, field, w, content)
	style := GUI.resolved_style(g, w)
	testing.expect_value(t, GUI.text_measure(g, style.text, "Search", 0).x <= label.w, true)

	//* A text that is longer makes the field wider.
	GUI.search_field_set_text(g, field, "a much longer text")
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, field).min_size.x > empty_width, true)
	testing.expect_value(t, GUI.Widget_Get(g, field).rect.w, GUI.Widget_Get(g, field).min_size.x)

	//* A field that is given a largest width stops there.
	small := GUI.Make_Search_Field(
		g,
		box,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{name = "small"},
			text = "a text that is far too long for the field",
			max_width = 60,
		},
	)
	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, small).min_size.x, 60.0)
	testing.expect_value(t, GUI.Widget_Get(g, small).rect.w, 60.0)

	test_gui_destroy(g)
}

@(test)
test_a_search_field_shows_a_caret_where_the_pointer_is :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.Make_Search_Field(
		g,
		g.root,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "search",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 30},
			},
			text = "hello",
		},
	)
	GUI.layout_pass(g)

	//* A click on the field gives it the keyboard and puts the caret
	//* where the pointer is.
	append(&g.events, mouse_down({100, 10}, 1))
	append(&g.events, mouse_up({100, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, field)
	testing.expect_value(t, GUI.search_field_caret(g, field), 5)

	//* The arrow keys walk the caret over the text.
	append(&g.events, key_event(.Left))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.search_field_caret(g, field), 4)

	//* The character is typed at the caret.
	append(&g.events, key_event(.X, GUI.Mods{.Shift}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.search_field_text(g, field), "hellXo")

	//* The caret is drawn while the field has the keyboard.
	GUI.Frame(g)
	with_caret := len(g.draw.vertices)
	GUI.focus_clear(g)
	GUI.Frame(g)
	testing.expect_value(t, with_caret > len(g.draw.vertices), true)

	test_gui_destroy(g)
}

//* The text that the search field gives when the search is done.
search_test_text: string

search_test_submitted :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, text: string) {
	search_test_text = text
}

@(test)
test_the_enter_key_in_a_search_field_says_the_search_is_done :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	search_test_text = ""

	field := GUI.Make_Search_Field(
		g,
		g.root,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "search",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 30},
			},
			text = "hello",
			on_submitted = search_test_submitted,
		},
	)
	GUI.layout_pass(g)
	GUI.focus_set(g, field)

	//* The enter key says that the search is done, and the text of the
	//* field is given with it.
	append(&g.events, key_event(.Enter))
	GUI.Handle_Events(g)
	testing.expect_value(t, search_test_text, "hello")

	//* The field is one line long: the enter key does not make a new
	//* line in it.
	testing.expect_value(t, GUI.search_field_text(g, field), "hello")

	test_gui_destroy(g)
}


//* == The number input ==

@(test)
test_a_number_input_changes_with_its_arrows :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	number := GUI.Make_Number_Input(
		g,
		g.root,
		GUI.Number_Input_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "number",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 200, 30},
			},
			value = 5,
			min = 0,
			max = 10,
			step = 2,
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.number_input_value(g, number), 5.0)

	//* A click on the arrow that goes up adds a step.
	append(&g.events, mouse_down({190, 5}, 1))
	append(&g.events, mouse_up({190, 5}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.number_input_value(g, number), 7.0)

	//* A click on the arrow that goes down takes a step away.
	append(&g.events, mouse_down({190, 25}, 1))
	append(&g.events, mouse_up({190, 25}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.number_input_value(g, number), 5.0)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_number_input_keeps_the_number_between_its_bounds :: proc(t: ^testing.T) {
	g := test_gui(t)

	number := GUI.Make_Number_Input(
		g,
		g.root,
		GUI.Number_Input_Opts{value = 5, min = 0, max = 10},
	)
	testing.expect_value(t, GUI.number_input_value(g, number), 5.0)

	//* A number that is too big is brought back into the bounds.
	GUI.number_input_set(g, number, 99)
	testing.expect_value(t, GUI.number_input_value(g, number), 10.0)

	GUI.number_input_set(g, number, -99)
	testing.expect_value(t, GUI.number_input_value(g, number), 0.0)

	//* The arrows stop at the bounds too.
	GUI.number_input_set(g, number, 10)
	GUI.number_input_increment(g, number)
	testing.expect_value(t, GUI.number_input_value(g, number), 10.0)

	test_gui_destroy(g)
}

//* == The chat input ==

@(test)
test_a_chat_input_sends_the_line_that_is_typed :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	chat := GUI.Make_Chat_Input(
		g,
		g.root,
		GUI.Chat_Input_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "chat",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 120},
			},
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.chat_input_line_count(g, chat), 0)

	append(&g.events, mouse_down({10, 110}, 1))
	append(&g.events, mouse_up({10, 110}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, chat)

	append(&g.events, GUI.Key_Down_Event{key = .H})
	append(&g.events, GUI.Key_Down_Event{key = .I})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.chat_input_text(g, chat), "hi")

	//* The enter key sends the line: it becomes a line of the talk and
	//* the field is emptied.
	append(&g.events, GUI.Key_Down_Event{key = .Enter})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.chat_input_line_count(g, chat), 1)
	testing.expect_value(t, GUI.chat_input_line_text(g, chat, 0), "hi")
	testing.expect_value(t, GUI.chat_input_text(g, chat), "")

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The date picker ==

@(test)
test_a_date_picker_picks_the_day_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	picker := GUI.Make_Date_Picker(
		g,
		g.root,
		GUI.Date_Picker_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "date",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 220},
			},
			year = 2026,
			month = 11,
			day = 3,
		},
	)
	GUI.layout_pass(g)

	year, month, day := GUI.date_picker_date(g, picker)
	testing.expect_value(t, year, 2026)
	testing.expect_value(t, month, 11)
	testing.expect_value(t, day, 3)

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.date_picker_is_open(g, picker), true)

	//* A click on a day of the calendar picks it, and the calendar
	//* closes.
	point := GUI.date_picker_day_point(2026, 11, 17)
	layout := GUI.date_picker_layout(GUI.date_picker_content(g, GUI.Widget_Get(g, picker)), true)
	append(&g.events, mouse_down({layout.days.x + point.x, layout.days.y + point.y}, 1))
	append(&g.events, mouse_up({layout.days.x + point.x, layout.days.y + point.y}))
	GUI.Handle_Events(g)
	_, _, day = GUI.date_picker_date(g, picker)
	testing.expect_value(t, day, 17)
	testing.expect_value(t, GUI.date_picker_is_open(g, picker), false)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_the_date_picker_picks_a_year_and_clamps_the_day :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	picker := GUI.Make_Date_Picker(
		g,
		g.root,
		GUI.Date_Picker_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "date",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 220},
			},
			year = 2024,
			month = 2,
			day = 29,
		},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.date_picker_is_open(g, picker), true)

	//* A click on the title shows the years of the page that holds the
	//* year of the picker.
	layout := GUI.date_picker_layout(GUI.date_picker_content(g, GUI.Widget_Get(g, picker)), true)
	title := GUI.Vec2{layout.title.x + layout.title.w * 0.5, layout.title.y + layout.title.h * 0.5}
	append(&g.events, mouse_down(title, 1))
	append(&g.events, mouse_up(title))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.date_picker_data(g, picker).show_years, true)

	//* The page of 2024 is 2016 to 2027, so 2026 is the third year of
	//* the last row.
	cell_w := layout.days.w / 4
	cell_h := layout.days.h / 3
	year_cell := GUI.Vec2{
		layout.days.x + (2 + 0.5) * cell_w,
		layout.days.y + (2 + 0.5) * cell_h,
	}
	append(&g.events, mouse_down(year_cell, 1))
	append(&g.events, mouse_up(year_cell))
	GUI.Handle_Events(g)

	year, month, day := GUI.date_picker_date(g, picker)
	testing.expect_value(t, year, 2026)
	testing.expect_value(t, month, 2)
	testing.expect_value(t, day, 28)
	testing.expect_value(t, GUI.date_picker_data(g, picker).show_years, false)
	testing.expect_value(t, GUI.date_picker_is_open(g, picker), true)

	test_gui_destroy(g)
}

@(test)
test_the_date_picker_knows_the_days_of_the_month :: proc(t: ^testing.T) {
	testing.expect_value(t, GUI.date_days_in_month(2026, 1), 31)
	testing.expect_value(t, GUI.date_days_in_month(2026, 2), 28)
	testing.expect_value(t, GUI.date_days_in_month(2024, 2), 29)
	testing.expect_value(t, GUI.date_days_in_month(2026, 4), 30)

	//* The first of November 2026 was a Sunday, so the week starts on
	//* the first of the month.
	testing.expect_value(t, GUI.date_first_weekday(2026, 11), 6)
	testing.expect_value(t, GUI.date_weekday(2026, 11, 3), 1)
}

//* == The time picker ==

@(test)
test_a_time_picker_picks_the_hour_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	picker := GUI.Make_Time_Picker(
		g,
		g.root,
		GUI.Time_Picker_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "time",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 240, 220},
			},
			hour = 9,
			minute = 30,
		},
	)
	GUI.layout_pass(g)

	hour, minute := GUI.time_picker_time(g, picker)
	testing.expect_value(t, hour, 9)
	testing.expect_value(t, minute, 30)

	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.time_picker_is_open(g, picker), true)

	layout := GUI.time_picker_layout(GUI.time_picker_content(g, GUI.Widget_Get(g, picker)), true)
	point := GUI.Vec2{f32(GUI.TIME_PICKER_HOUR_COLUMNS - 1) * f32(GUI.TIME_PICKER_CELL) + 4, 4}
	append(&g.events, mouse_down({layout.hours.x + point.x, layout.hours.y + point.y}, 1))
	append(&g.events, mouse_up({layout.hours.x + point.x, layout.hours.y + point.y}))
	GUI.Handle_Events(g)
	hour, _ = GUI.time_picker_time(g, picker)
	testing.expect_value(t, hour, 5)

	//* The minutes are in two rows, so the last one is in the second row.
	point = GUI.Vec2{
		f32(GUI.TIME_PICKER_MINUTE_COLUMNS - 1) * f32(GUI.TIME_PICKER_CELL) + 4,
		f32(GUI.TIME_PICKER_CELL) + 4,
	}
	append(&g.events, mouse_down({layout.minutes.x + point.x, layout.minutes.y + point.y}, 1))
	append(&g.events, mouse_up({layout.minutes.x + point.x, layout.minutes.y + point.y}))
	GUI.Handle_Events(g)
	_, minute = GUI.time_picker_time(g, picker)
	testing.expect_value(t, minute, 55)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_time_picker_keeps_the_time_between_its_bounds :: proc(t: ^testing.T) {
	g := test_gui(t)

	picker := GUI.Make_Time_Picker(g, g.root, GUI.Time_Picker_Opts{hour = 9, minute = 30})
	GUI.time_picker_set_time(g, picker, 99, 99)
	hour, minute := GUI.time_picker_time(g, picker)
	testing.expect_value(t, hour, 23)
	testing.expect_value(t, minute, 59)

	//* The time goes over the hour and over the day.
	GUI.time_picker_set_time(g, picker, 23, 30)
	GUI.time_picker_add_minutes(g, picker, 60)
	hour, minute = GUI.time_picker_time(g, picker)
	testing.expect_value(t, hour, 0)
	testing.expect_value(t, minute, 30)

	test_gui_destroy(g)
}

//* Tests for the life of a widget: how it is made, how it is moved,
//* how it is destroyed, and what is left of it afterwards. Run with:
//*   odin test src/GUI

//* The widget that a test wants a callback to destroy. Odin procedure
//* literals do not capture enclosing variables, so the state of the
//* tests lives at package scope.
lifetime_test_widget: GUI.Widget_ID = GUI.INVALID_WIDGET_ID
lifetime_test_focus_exits: int = 0

//* A button that destroys itself when it is clicked.
lifetime_on_click :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	GUI.Widget_Free(g, lifetime_test_widget)
}

//* Counts the widgets that are given up the focus.
lifetime_on_focus_exited :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	lifetime_test_focus_exits += 1
}

//* == Creation ==

@(test)
test_a_widget_that_is_made_has_a_handle_that_names_it :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	testing.expect_value(t, GUI.Widget_Get(g, panel) == nil, false)
	testing.expect_value(t, GUI.Widget_Alive(g, panel), true)

	//* The handle of a widget that does not exist names nothing.
	testing.expect_value(t, GUI.Widget_Get(g, GUI.INVALID_WIDGET_ID) == nil, true)
	testing.expect_value(t, GUI.Widget_Alive(g, GUI.INVALID_WIDGET_ID), false)

	//* The widget is under the parent it was given.
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent == g.root, true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 1)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_made_under_a_parent_that_is_gone_is_made_on_its_own :: proc(t: ^testing.T) {
	g := test_gui(t)

	gone := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "gone"})
	GUI.Widget_Free(g, gone)

	//* The parent is gone, so the widget is made on its own: the tree
	//* never holds a handle to a widget that does not exist.
	orphan := GUI.New_Widget(g, .Panel, gone, GUI.Widget_Opts{name = "orphan"})
	testing.expect_value(t, GUI.Widget_Alive(g, orphan), true)
	testing.expect_value(t, GUI.Widget_Get(g, orphan).parent == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)

	test_gui_destroy(g)
}

//* == Destruction ==

@(test)
test_a_widget_that_is_destroyed_is_gone :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	testing.expect_value(t, GUI.Widget_Free(g, panel), true)

	//* The handle names nothing now.
	testing.expect_value(t, GUI.Widget_Get(g, panel) == nil, true)
	testing.expect_value(t, GUI.Widget_Alive(g, panel), false)

	//* The widget has left the tree.
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)

	//* A widget that is gone cannot be destroyed again.
	testing.expect_value(t, GUI.Widget_Free(g, panel), false)

	test_gui_destroy(g)
}

@(test)
test_the_root_cannot_be_destroyed :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* The root is the tree itself: it cannot go away.
	testing.expect_value(t, GUI.Widget_Free(g, g.root), false)
	testing.expect_value(t, GUI.Widget_Alive(g, g.root), true)

	test_gui_destroy(g)
}

@(test)
test_the_children_of_a_destroyed_widget_are_destroyed_too :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	child := GUI.New_Widget(g, .Panel, panel, GUI.Widget_Opts{name = "child"})
	grandchild := GUI.New_Widget(g, .Panel, child, GUI.Widget_Opts{name = "grandchild"})

	GUI.Widget_Free(g, panel)

	testing.expect_value(t, GUI.Widget_Alive(g, panel), false)
	testing.expect_value(t, GUI.Widget_Alive(g, child), false)
	testing.expect_value(t, GUI.Widget_Alive(g, grandchild), false)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_destroyed_gives_back_what_it_owned :: proc(t: ^testing.T) {
	g := test_gui(t)

	list := GUI.Make_Item_List(
		g,
		g.root,
		GUI.Item_List_Opts{Base_Opts = GUI.Base_Opts{name = "list"}, items = {"one", "two"}},
	)
	slot := int(list.index) - 1

	GUI.Widget_Free(g, list)

	//* The list of the widget is given back, so the widget has nothing
	//* left in it.
	released := false
	#partial switch d in g.widgets[slot].data {
	case GUI.None_Data:
		released = true
	}
	testing.expect_value(t, released, true)

	test_gui_destroy(g)
}

//* == Slot reuse ==

@(test)
test_the_slot_of_a_destroyed_widget_is_used_again :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	GUI.Widget_Free(g, first)

	//* The table does not grow: the slot of the widget that was
	//* destroyed is used again.
	before := len(g.widgets)
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})
	testing.expect_value(t, len(g.widgets), before)
	testing.expect_value(t, second.index == first.index, true)

	//* The widget that took the place has a generation of its own, so
	//* the handle of the old one does not name it.
	testing.expect_value(t, second.generation == first.generation, false)

	test_gui_destroy(g)
}

@(test)
test_a_stale_handle_does_not_name_the_widget_that_took_its_place :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	GUI.Widget_Free(g, first)
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})

	//* The handle of the widget that was destroyed names nothing, even
	//* though the slot has a widget in it again.
	testing.expect_value(t, GUI.Widget_Get(g, first) == nil, true)
	testing.expect_value(t, GUI.Widget_Alive(g, first), false)

	//* The handle of the new widget names the new widget.
	testing.expect_value(t, GUI.Widget_Get(g, second) == nil, false)
	testing.expect_value(t, GUI.Widget_Get(g, second).name, "second")

	test_gui_destroy(g)
}

@(test)
test_the_table_of_the_widgets_does_not_grow_when_widgets_are_destroyed :: proc(t: ^testing.T) {
	g := test_gui(t)

	ids: [dynamic]GUI.Widget_ID
	defer delete(ids)
	for _ in 0 ..< 8 {
		append(&ids, GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"}))
	}
	size := len(g.widgets)

	for id in ids {
		GUI.Widget_Free(g, id)
	}
	testing.expect_value(t, len(g.widgets), size)

	//* The widgets that are made again go into the slots that were
	//* freed, so the table is the size it was.
	for _ in 0 ..< 8 {
		append(&ids, GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"}))
	}
	testing.expect_value(t, len(g.widgets), size)

	test_gui_destroy(g)
}

//* == The references ==

@(test)
test_a_widget_that_is_destroyed_gives_up_the_focus :: proc(t: ^testing.T) {
	g := test_gui(t)

	lifetime_test_focus_exits = 0
	button := GUI.Make_Button(g, g.root, GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = "button"}})
	GUI.Widget_Get(g, button).signals.on_focus_exited = lifetime_on_focus_exited

	GUI.focus_set(g, button)
	testing.expect_value(t, g.focused == button, true)

	GUI.Widget_Free(g, button)

	//* The focus is given up, and the program is told about it.
	testing.expect_value(t, g.focused == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, lifetime_test_focus_exits, 1)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_destroyed_gives_up_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})

	//* The widget under the pointer.
	g.hot = panel
	//* The widget that took the mouse when it was pressed.
	g.active = panel
	//* The slider that took the mouse.
	g.slider_active = panel
	//* The grip under the pointer.
	g.resize_hover = panel

	GUI.Widget_Free(g, panel)

	testing.expect_value(t, g.hot == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.active == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.slider_active == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.resize_hover == GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_destroyed_gives_up_the_drag :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	other := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "other"})

	g.drag.armed = true
	g.drag.active = true
	g.drag.widget = panel
	g.drag.target = other
	g.drag.plan.container = other
	g.drag.plan.children[0] = other

	GUI.Widget_Free(g, panel)

	//* The drag cannot go on: the widget that was dragged is gone.
	testing.expect_value(t, g.drag.widget == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.drag.armed, false)
	testing.expect_value(t, g.drag.active, false)

	//* The plan does not name the widget that is gone either.
	GUI.Widget_Free(g, other)
	testing.expect_value(t, g.drag.target == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.drag.plan.container == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.drag.plan.children[0] == GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_destroyed_gives_up_the_resize :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	g.resize.active = true
	g.resize.widget = panel

	GUI.Widget_Free(g, panel)

	testing.expect_value(t, g.resize.widget == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, g.resize.active, false)
	testing.expect_value(t, g.resize.float_index, GUI.FLOAT_NONE)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_is_removed_when_its_widget_is_destroyed :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	index := GUI.Make_Float_Panel(g, panel, GUI.Vec2{10, 10}, GUI.Vec2{200, 100})
	testing.expect_value(t, index, 0)
	testing.expect_value(t, len(g.floats), 1)

	GUI.Widget_Free(g, panel)

	//* The panel is gone, so the window of it is gone too.
	testing.expect_value(t, len(g.floats), 0)

	test_gui_destroy(g)
}

@(test)
test_the_focus_neighbours_of_the_other_widgets_are_cleared :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})

	GUI.Widget_Get(g, first).focus_neighbour[0] = second
	GUI.Widget_Get(g, first).focus_next = second
	GUI.Widget_Get(g, first).focus_previous = second

	GUI.Widget_Free(g, second)

	testing.expect_value(t, GUI.Widget_Get(g, first).focus_neighbour[0] == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).focus_next == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).focus_previous == GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_the_tooltip_forgets_the_widget_it_is_about :: proc(t: ^testing.T) {
	g := test_gui(t)

	target := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "target"})
	tip := GUI.Make_Tooltip(g, g.root, GUI.Tooltip_Opts{Base_Opts = GUI.Base_Opts{name = "tip"}, target = target})
	testing.expect_value(t, GUI.tooltip_data(g, tip).target == target, true)

	GUI.Widget_Free(g, target)

	//* The tooltip does not point at a widget that does not exist.
	testing.expect_value(t, GUI.tooltip_data(g, tip).target == GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_destroyed_by_its_own_click_is_gone :: proc(t: ^testing.T) {
	g := test_gui(t)

	lifetime_test_widget = GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = "button"}, on_pressed = lifetime_on_click},
	)
	id := lifetime_test_widget
	GUI.layout_pass(g)

	//* The button destroys itself when it is pressed.
	append(&g.events, mouse_down({5, 5}))
	append(&g.events, mouse_up({5, 5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Alive(g, id), false)
	testing.expect_value(t, GUI.Widget_Child_Count(g, g.root), 0)

	test_gui_destroy(g)
}

//* == Moving ==

@(test)
test_a_widget_that_is_moved_keeps_its_handle :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})
	child := GUI.New_Widget(g, .Panel, first, GUI.Widget_Opts{name = "child"})

	GUI.Widget_Attach(g, second, child)

	//* The handle of the widget is the same: the widget is the same
	//* widget, it is only in another place.
	testing.expect_value(t, GUI.Widget_Alive(g, child), true)
	testing.expect_value(t, GUI.Widget_Get(g, child) == GUI.Widget_Get(g, child), true)
	testing.expect_value(t, GUI.Widget_Get(g, child).parent == second, true)

	//* The old parent does not have it any more.
	testing.expect_value(t, GUI.Widget_Child_Count(g, first), 0)
	testing.expect_value(t, GUI.Widget_Child_Count(g, second), 1)

	//* The links of the tree are whole.
	testing.expect_value(t, GUI.Widget_Get(g, second).first_child == child, true)
	testing.expect_value(t, GUI.Widget_Get(g, second).last_child == child, true)
	testing.expect_value(t, GUI.Widget_Get(g, child).prev_sibling == GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Widget_Get(g, child).next_sibling == GUI.INVALID_WIDGET_ID, true)

	test_gui_destroy(g)
}

@(test)
test_a_widget_cannot_be_attached_to_itself :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	GUI.Widget_Attach(g, panel, panel)

	//* The widget is not its own child.
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent == g.root, true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, panel), 0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_cannot_be_attached_to_its_own_child :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	child := GUI.New_Widget(g, .Panel, panel, GUI.Widget_Opts{name = "child"})

	//* The child cannot take the place of its own parent: the tree
	//* has to stay a tree.
	GUI.Widget_Attach(g, child, panel)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent == g.root, true)
	testing.expect_value(t, GUI.Widget_Get(g, child).parent == panel, true)

	//* The same goes for a place in the child list.
	GUI.Widget_Insert_At(g, child, panel, 0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent == g.root, true)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_is_moved_keeps_its_own_handles_valid :: proc(t: ^testing.T) {
	g := test_gui(t)

	first := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "second"})
	child := GUI.New_Widget(g, .Panel, first, GUI.Widget_Opts{name = "child"})

	//* The neighbours of the focus of the moved widget are not touched
	//* by the move.
	GUI.Widget_Get(g, child).focus_neighbour[1] = second

	GUI.Widget_Attach(g, second, child)

	testing.expect_value(t, GUI.Widget_Get(g, child).focus_neighbour[1] == second, true)
	testing.expect_value(t, GUI.Widget_Alive(g, second), true)

	test_gui_destroy(g)
}

@(test)
test_the_tree_is_whole_after_a_widget_is_destroyed :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "host"})
	first := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "second"})
	third := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "third"})

	//* The links of the children are whole before the destroy.
	testing.expect_value(t, GUI.Widget_Get(g, host).first_child == first, true)
	testing.expect_value(t, GUI.Widget_Get(g, host).last_child == third, true)
	testing.expect_value(t, GUI.Widget_Get(g, second).prev_sibling == first, true)
	testing.expect_value(t, GUI.Widget_Get(g, second).next_sibling == third, true)

	GUI.Widget_Free(g, second)

	//* The widget that was between the two is gone, so the two are
	//* neighbours now.
	testing.expect_value(t, GUI.Widget_Get(g, host).first_child == first, true)
	testing.expect_value(t, GUI.Widget_Get(g, host).last_child == third, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).next_sibling == third, true)
	testing.expect_value(t, GUI.Widget_Get(g, third).prev_sibling == first, true)
	testing.expect_value(t, GUI.Widget_Child_Count(g, host), 2)

	//* The handle of the widget that was destroyed names nothing.
	testing.expect_value(t, GUI.Widget_Alive(g, second), false)

	test_gui_destroy(g)
}

@(test)
test_a_tab_that_is_destroyed_leaves_the_host_showing_a_tab :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Tabs, g.root, GUI.Widget_Opts{name = "host"})
	first := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "second"})

	//* The second tab is the one that is showing.
	GUI.set_active_tab(g, host, second)
	testing.expect_value(t, GUI.is_hidden_tab(g, second), false)

	//* The tab that was showing is destroyed.
	GUI.Widget_Free(g, second)

	//* The host still shows a tab that is there: the tab that was
	//* showing would be a tab that does not exist.
	testing.expect_value(t, GUI.is_hidden_tab(g, first), false)
	testing.expect_value(t, GUI.Widget_Child_Count(g, host), 1)

	test_gui_destroy(g)
}

@(test)
test_a_tab_that_is_put_in_front_keeps_the_tab_that_is_showing :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Tabs, g.root, GUI.Widget_Opts{name = "host"})
	first := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "second"})

	//* The second tab is the one that is showing.
	GUI.set_active_tab(g, host, second)

	//* A tab is put in front of it.
	front := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "front"})
	GUI.Widget_Insert_At(g, host, front, 0)

	//* The host still shows the tab that was showing: it is the third
	//* one now.
	testing.expect_value(t, GUI.tabs_active(GUI.Widget_Get(g, host)), 2)
	testing.expect_value(t, GUI.is_hidden_tab(g, second), false)
	testing.expect_value(t, GUI.is_hidden_tab(g, first), true)
	testing.expect_value(t, GUI.is_hidden_tab(g, front), true)

	test_gui_destroy(g)
}

//* Tests for the overlays: the toast, the command palette, the tooltip
//* and the context menu.

//* == The toast ==

@(test)
test_a_toast_comes_up_and_goes_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	toast := GUI.Make_Toast(
		g,
		g.root,
		GUI.Toast_Opts {
			Base_Opts = GUI.Base_Opts {
				name = "toast",
				preset = .Top_Left,
				offsets = GUI.Offset{0, 0, 320, 48},
			},
			text = "Saved",
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Toast_Is_Visible(g, toast), false)

	GUI.Toast_Show(g, toast, "Saved", .Success, 1.0)
	testing.expect_value(t, GUI.Toast_Is_Visible(g, toast), true)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	//* It counts down, and it goes away when its time is up.
	GUI.update_toast(g, toast, GUI.Widget_Get(g, toast), 0.5)
	testing.expect_value(t, GUI.Toast_Is_Visible(g, toast), true)
	GUI.update_toast(g, toast, GUI.Widget_Get(g, toast), 0.6)
	testing.expect_value(t, GUI.Toast_Is_Visible(g, toast), false)

	test_gui_destroy(g)
}

//* == The command palette ==

@(test)
test_the_command_palette_opens_and_filters :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	palette := GUI.Make_Command_Palette(g, g.root, GUI.Command_Palette_Opts{})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Command_Palette_Is_Open(g, palette), false)

	GUI.Command_Palette_Open(g, palette)
	testing.expect_value(t, GUI.Command_Palette_Is_Open(g, palette), true)
	//* The palette has the keyboard, so that the filter can be typed
	//* into.
	testing.expect_value(t, g.focused, palette)

	GUI.Command_Palette_Add(g, palette, "Save", nil, "save")
	GUI.Command_Palette_Add(g, palette, "Open", nil, "open")
	testing.expect_value(t, GUI.Command_Palette_Count(g, palette), 2)

	//* The filter lets through the commands that match it.
	append(&g.events, GUI.Key_Down_Event{key = .S})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Command_Palette_Text(g, palette), "s")
	testing.expect_value(t, GUI.Command_Palette_Count(g, palette), 1)

	append(&g.events, GUI.Key_Down_Event{key = .Backspace})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Command_Palette_Text(g, palette), "")
	testing.expect_value(t, GUI.Command_Palette_Count(g, palette), 2)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	//* The escape key closes the palette, and the program does not quit.
	append(&g.events, GUI.Key_Down_Event{key = .Escape})
	GUI.Handle_Events(g)
	GUI.Frame(g)
	testing.expect_value(t, GUI.Command_Palette_Is_Open(g, palette), false)
	testing.expect_value(t, g.quit_requested, false)

	test_gui_destroy(g)
}

//* == The tooltip ==

@(test)
test_a_tooltip_comes_up_over_the_thing_it_is_about :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "button",
			text = "Save",
			preset = .Top_Left,
			offsets = GUI.Offset{0, 0, 120, 32},
		},
	)
	tooltip := GUI.Make_Tooltip(g, g.root, GUI.Tooltip_Opts{})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tooltip), false)

	GUI.Tooltip_Show(g, tooltip, button, "Saves the file")
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tooltip), true)

	//* The pointer rests on the thing, and the tooltip comes up.
	g.pointer = GUI.Vec2{10, 10}
	g.global_pointer = GUI.Vec2{10, 10}
	GUI.update_tooltip(g, tooltip, GUI.Widget_Get(g, tooltip), GUI.TOOLTIP_SHOW_DELAY)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tooltip), true)

	//* The pointer goes away, and the tooltip goes with it.
	g.pointer = GUI.Vec2{400, 400}
	g.global_pointer = GUI.Vec2{400, 400}
	GUI.update_tooltip(g, tooltip, GUI.Widget_Get(g, tooltip), 0.1)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tooltip), false)

	GUI.Tooltip_Show(g, tooltip, button, "Saves the file")
	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_the_gui_makes_a_tooltip_of_its_own :: proc(t: ^testing.T) {
	g, err := GUI.Init_GUI_Checked(400, 300, mock_backend)
	testing.expect_value(t, err.code, GUI.Error_Code.None)

	tip := GUI.Tooltip_Widget(g)
	testing.expect_value(t, tip != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, GUI.Tooltip_Enabled(g), true)

	w := GUI.Widget_Get(g, tip)
	testing.expect_value(t, w != nil, true)
	testing.expect_value(t, w.parent == g.root, true)
	testing.expect_value(t, w.z_index >= 100, true)

	GUI.Shutdown_GUI(g)
}

@(test)
test_a_widget_with_a_tooltip_gets_one_when_the_pointer_rests_on_it :: proc(t: ^testing.T) {
	g, err := GUI.Init_GUI_Checked(400, 300, mock_backend)
	testing.expect_value(t, err.code, GUI.Error_Code.None)
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts {
			name = "button",
			text = "Save",
			preset = .Top_Left,
			offsets = GUI.Offset{0, 0, 120, 32},
			tooltip = "Saves the file",
		},
	)
	GUI.layout_pass(g)

	tip := GUI.Tooltip_Widget(g)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), false)

	g.pointer = GUI.Vec2{10, 10}
	g.global_pointer = GUI.Vec2{10, 10}
	g.pointer_known = true
	GUI.update_tooltip(g, tip, GUI.Widget_Get(g, tip), GUI.TOOLTIP_SHOW_DELAY)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), true)

	g.pointer = GUI.Vec2{300, 200}
	g.global_pointer = GUI.Vec2{300, 200}
	GUI.update_tooltip(g, tip, GUI.Widget_Get(g, tip), 0.1)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), false)

	GUI.Set_Tooltip_Enabled(g, false)
	testing.expect_value(t, GUI.Tooltip_Enabled(g), false)
	g.pointer = GUI.Vec2{10, 10}
	g.global_pointer = GUI.Vec2{10, 10}
	GUI.update_tooltip(g, tip, GUI.Widget_Get(g, tip), GUI.TOOLTIP_SHOW_DELAY)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), false)

	GUI.Set_Tooltip_Enabled(g, true)
	testing.expect_value(t, GUI.Tooltip_Enabled(g), true)
	GUI.update_tooltip(g, tip, GUI.Widget_Get(g, tip), GUI.TOOLTIP_SHOW_DELAY)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), true)

	GUI.Shutdown_GUI(g)
}

@(test)
test_a_covered_widget_hides_its_tooltip :: proc(t: ^testing.T) {
	g := test_gui(t)

	GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts {
			name = "back",
			preset = .Top_Left,
			offsets = GUI.Offset{0, 0, 200, 100},
			tooltip = "Behind the front panel",
		},
	)
	GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts {
			name = "front",
			preset = .Top_Left,
			offsets = GUI.Offset{0, 0, 200, 100},
		},
	)
	tip := GUI.Make_Tooltip(g, g.root, GUI.Tooltip_Opts{})
	GUI.layout_pass(g)

	g.pointer = GUI.Vec2{10, 10}
	g.global_pointer = GUI.Vec2{10, 10}
	g.pointer_known = true
	GUI.update_tooltip(g, tip, GUI.Widget_Get(g, tip), GUI.TOOLTIP_SHOW_DELAY)

	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), false)
	testing.expect_value(t, GUI.tooltip_of(g, g.global_pointer), GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_a_child_without_a_tooltip_uses_the_one_of_its_parent :: proc(t: ^testing.T) {
	g := test_gui(t)

	parent := GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts {
			name = "parent",
			preset = .Top_Left,
			offsets = GUI.Offset{0, 0, 200, 100},
			tooltip = "The parent says what it is",
		},
	)
	GUI.New_Widget(
		g,
		.Panel,
		parent,
		GUI.Widget_Opts {
			name = "child",
			preset = .Top_Left,
			offsets = GUI.Offset{0, 0, 100, 50},
		},
	)
	tip := GUI.Make_Tooltip(g, g.root, GUI.Tooltip_Opts{})
	GUI.layout_pass(g)

	g.pointer = GUI.Vec2{10, 10}
	g.global_pointer = GUI.Vec2{10, 10}
	g.pointer_known = true
	GUI.update_tooltip(g, tip, GUI.Widget_Get(g, tip), GUI.TOOLTIP_SHOW_DELAY)

	testing.expect_value(t, GUI.tooltip_of(g, g.global_pointer), parent)
	testing.expect_value(t, GUI.Tooltip_Is_Visible(g, tip), true)

	test_gui_destroy(g)
}

//* == The context menu ==

//* The counter of the items of the context menu.
context_menu_test_actions: int = 0

on_context_menu_test_action :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	context_menu_test_actions += 1
}

@(test)
test_a_context_menu_picks_the_item_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	context_menu_test_actions = 0

	menu := GUI.Make_Context_Menu(
		g,
		g.root,
		GUI.Context_Menu_Opts {
			items = {
				GUI.Context_Menu_Item{text = "Copy", action = on_context_menu_test_action},
				GUI.Context_Menu_Item{text = "Paste", action = on_context_menu_test_action},
				GUI.Context_Menu_Item{separator = true},
				GUI.Context_Menu_Item{text = "Delete", disabled = true},
			},
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, menu), false)

	GUI.Context_Menu_Open(g, menu, GUI.Vec2{10, 10})
	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, menu), true)

	//* A click on the first item does it, and closes the menu.
	append(&g.events, mouse_down({20, 20}, 1))
	append(&g.events, mouse_up({20, 20}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, menu), false)
	testing.expect_value(t, context_menu_test_actions, 1)

	GUI.Context_Menu_Open(g, menu, GUI.Vec2{10, 10})
	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == The menu button ==

//* The index of the item that was picked from the menu of a menu button.
menu_button_test_picked: int = -1

on_menu_button_test_selected :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, index: int) {
	menu_button_test_picked = index
}

//* A menu button in the corner of the window, with the items it holds.
menu_button_test_make :: proc(g: ^GUI.GUI, items: []string) -> GUI.Widget_ID {
	return GUI.Make_Menu_Button(
		g,
		g.root,
		GUI.Menu_Button_Opts {
			Base_Opts = GUI.Base_Opts {
				name = "file",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 10, top = 10, right = 90, bottom = 34},
			},
			text = "File",
			items = items,
		},
	)
}

@(test)
test_a_menu_button_opens_its_menu_when_it_is_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := menu_button_test_make(g, {"New", "Open", "Save"})
	GUI.layout_pass(g)

	popup := GUI.menu_button_popup(g, button)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, popup).state, true)

	//* The menu comes up under the button, and it is as tall as its
	//* rows.
	pw := GUI.Widget_Get(g, popup)
	bw := GUI.Widget_Get(g, button)
	testing.expect_value(t, pw.rect.x, bw.rect.x)
	testing.expect_value(t, pw.rect.y, bw.rect.y + bw.rect.h)
	testing.expect_value(t, pw.rect.h >= f32(3) * f32(GUI.POPUP_ROW), true)

	//* The menu is on the screen.
	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_menu_button_picks_the_item_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	menu_button_test_picked = -1

	button := menu_button_test_make(g, {"New", "Open", "Save"})
	GUI.Widget_Get(g, button).signals.on_item_selected = on_menu_button_test_selected
	GUI.layout_pass(g)

	//* The menu comes up.
	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, button)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)

	//* The second item of the menu is clicked.
	pw := GUI.Widget_Get(g, popup)
	content := GUI.content_rect_with(pw.rect, GUI.resolved_style(g, pw).box.content_margin)
	item := GUI.Vec2{content.x + 4, content.y + f32(GUI.POPUP_ROW) * 1.5}
	append(&g.events, mouse_down(item, 1))
	append(&g.events, mouse_up(item))
	GUI.Handle_Events(g)

	testing.expect_value(t, menu_button_test_picked, 1)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)

	test_gui_destroy(g)
}

@(test)
test_a_click_on_the_menu_button_again_closes_the_menu :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := menu_button_test_make(g, {"New", "Open", "Save"})
	GUI.layout_pass(g)
	popup := GUI.menu_button_popup(g, button)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)

	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)

	test_gui_destroy(g)
}

@(test)
test_a_click_away_from_the_menu_of_a_menu_button_closes_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := menu_button_test_make(g, {"New", "Open", "Save"})
	GUI.layout_pass(g)
	popup := GUI.menu_button_popup(g, button)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)

	append(&g.events, mouse_down({700, 500}, 1))
	append(&g.events, mouse_up({700, 500}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)

	test_gui_destroy(g)
}

@(test)
test_the_escape_key_closes_the_menu_of_a_menu_button :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := menu_button_test_make(g, {"New", "Open", "Save"})
	GUI.layout_pass(g)
	popup := GUI.menu_button_popup(g, button)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)

	append(&g.events, key_event(.Escape))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)

	test_gui_destroy(g)
}

@(test)
test_the_menu_of_a_menu_button_is_not_cut_off_by_the_menu_bar :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	//* A menu bar in a column, like the one of the docking example.
	column := GUI.Make_VBox(
		g,
		g.root,
		GUI.Box_Opts{Base_Opts = GUI.Base_Opts{min_size = GUI.Vec2{0, 600}, size_flags_v = GUI.Size_Flags{.Fill}}},
	)
	bar := GUI.Make_Menu_Bar(
		g,
		column,
		GUI.Menu_Bar_Opts{Base_Opts = GUI.Base_Opts{
			name = "menubar",
			min_size = GUI.Vec2{0, 28},
			size_flags_v = GUI.Size_Flags{.Fill},
		}},
	)
	button := GUI.Make_Menu_Button(
		g,
		bar,
		GUI.Menu_Button_Opts {
			Base_Opts = GUI.Base_Opts {
				name = "file",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 8, top = 2, right = 96, bottom = 26},
			},
			text = "File",
			items = {"New", "Open", "Save"},
		},
	)
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, button)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)

	//* The menu comes up under the button, and the menu bar does not
	//* cut it off.
	pw := GUI.Widget_Get(g, popup)
	bw := GUI.Widget_Get(g, button)
	testing.expect_value(t, pw.rect.y, bw.rect.y + bw.rect.h)
	GUI.layout_pass(g)
	testing.expect_value(t, pw.clip.y, pw.rect.y)
	testing.expect_value(t, pw.clip.h, pw.rect.h)

	test_gui_destroy(g)
}

@(test)
test_a_menu_button_with_no_items_opens_no_menu :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	button := menu_button_test_make(g, {})
	GUI.layout_pass(g)
	popup := GUI.menu_button_popup(g, button)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)

	test_gui_destroy(g)
}

//* The number of times the button of the tests was pressed.
popup_test_pressed: int = 0

on_popup_test_pressed :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	popup_test_pressed += 1
}

//* A button in the corner of the window, which says so when it is
//* pressed.
popup_test_make_button :: proc(g: ^GUI.GUI) -> GUI.Widget_ID {
	return GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "ok",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 10, top = 10, right = 110, bottom = 50},
			},
			text = "OK",
			on_pressed = on_popup_test_pressed,
		},
	)
}

//* A menu button at a place of the window.
popup_test_make_menu_button :: proc(g: ^GUI.GUI, parent: GUI.Widget_ID, name: string, rect: GUI.Rect, items: []string) -> GUI.Widget_ID {
	return GUI.Make_Menu_Button(
		g,
		parent,
		GUI.Menu_Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				preset = .Top_Left,
				offsets = GUI.Offset{
					left = rect.x,
					top = rect.y,
					right = rect.x + rect.w,
					bottom = rect.y + rect.h,
				},
			},
			text = "File",
			items = items,
		},
	)
}

@(test)
test_a_click_outside_a_menu_closes_it_and_the_click_reaches_the_widget_under_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	popup_test_pressed = 0

	button := popup_test_make_button(g)
	//* A menu that belongs to nobody, opened away from the button.
	menu := GUI.Make_Popup_Menu(g, g.root, GUI.Popup_Menu_Opts{items = {"One", "Two"}})
	GUI.layout_pass(g)

	g.pointer_known = true
	g.pointer = GUI.Vec2{400, 300}
	g.global_pointer = GUI.Vec2{400, 300}
	GUI.Popup_Menu_Open(g, menu)
	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), true)

	//* The click on the button closes the menu, and the button is
	//* pressed.
	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), false)
	testing.expect_value(t, popup_test_pressed, 1)

	test_gui_destroy(g)
}

@(test)
test_a_click_on_the_button_of_an_open_menu_closes_the_menu_and_presses_the_button :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	popup_test_pressed = 0

	button := popup_test_make_menu_button(
		g,
		g.root,
		"file",
		GUI.Rect{x = 10, y = 10, w = 80, h = 24},
		{"New", "Open", "Save"},
	)
	GUI.Widget_Get(g, button).signals.on_pressed = on_popup_test_pressed
	GUI.layout_pass(g)

	popup := GUI.menu_button_popup(g, button)
	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	testing.expect_value(t, popup_test_pressed, 1)

	//* The click on the button again closes the menu, and the button is
	//* pressed.
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), false)
	testing.expect_value(t, popup_test_pressed, 2)

	test_gui_destroy(g)
}

@(test)
test_a_click_outside_a_context_menu_closes_it_and_the_click_reaches_the_widget_under_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	popup_test_pressed = 0

	button := popup_test_make_button(g)
	menu := GUI.Make_Context_Menu(g, g.root, GUI.Context_Menu_Opts{items = {{text = "One"}}})
	GUI.layout_pass(g)

	//* The menu comes up away from the button.
	GUI.Context_Menu_Open(g, menu, GUI.Vec2{400, 300})
	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), true)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), false)
	testing.expect_value(t, GUI.Context_Menu_Is_Open(g, menu), false)
	testing.expect_value(t, popup_test_pressed, 1)

	test_gui_destroy(g)
}

@(test)
test_a_click_outside_a_dialog_does_not_close_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	dialog := GUI.Make_Accept_Dialog(g, g.root, GUI.Accept_Dialog_Opts{text = "Are you sure?"})
	GUI.layout_pass(g)

	GUI.Dialog_Open(g, dialog)
	testing.expect_value(t, GUI.Popup_Is_Open(g, dialog), true)

	append(&g.events, mouse_down({700, 500}, 1))
	append(&g.events, mouse_up({700, 500}))
	GUI.Handle_Events(g)

	//* The rule is for the menus: a dialog stays open.
	testing.expect_value(t, GUI.Popup_Is_Open(g, dialog), true)

	test_gui_destroy(g)
}

@(test)
test_the_menu_of_a_menu_button_stays_inside_the_window :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	//* A button at the bottom of the window: there is no room for the
	//* menu under it, so the menu comes up over it.
	bottom := popup_test_make_menu_button(
		g,
		g.root,
		"bottom",
		GUI.Rect{x = 10, y = 560, w = 80, h = 20},
		{"New", "Open", "Save"},
	)
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, bottom))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, bottom)
	pw := GUI.Widget_Get(g, popup)
	bw := GUI.Widget_Get(g, bottom)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	//* The menu comes up over the button: its bottom is at the top of
	//* the button.
	testing.expect_value(t, abs((pw.rect.y + pw.rect.h) - bw.rect.y) < 0.5, true)
	testing.expect_value(t, pw.rect.x >= g.viewport.x, true)
	testing.expect_value(t, pw.rect.y >= g.viewport.y, true)
	testing.expect_value(t, pw.rect.x + pw.rect.w <= g.viewport.x + g.viewport.w, true)
	testing.expect_value(t, pw.rect.y + pw.rect.h <= g.viewport.y + g.viewport.h, true)
	GUI.Popup_Menu_Close(g, popup)

	//* A button at the right of the window: the menu is put at the
	//* right edge of the button, so that it stays inside the window.
	right := popup_test_make_menu_button(
		g,
		g.root,
		"right",
		GUI.Rect{x = 700, y = 10, w = 80, h = 24},
		{"Open the file that was chosen before"},
	)
	GUI.layout_pass(g)

	point = centre_of(GUI.Widget_Get(g, right))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup = GUI.menu_button_popup(g, right)
	pw = GUI.Widget_Get(g, popup)
	bw = GUI.Widget_Get(g, right)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	//* The menu is wider than the button, so it has to be put at the
	//* right edge of the button to stay inside the window.
	testing.expect_value(t, pw.rect.w > bw.rect.w, true)
	testing.expect_value(t, pw.rect.x < bw.rect.x, true)
	testing.expect_value(t, pw.rect.x + pw.rect.w <= g.viewport.x + g.viewport.w, true)
	testing.expect_value(t, abs((pw.rect.x + pw.rect.w) - (bw.rect.x + bw.rect.w)) < 0.5, true)

	test_gui_destroy(g)
}

@(test)
test_a_menu_that_does_not_fit_is_capped_to_the_window :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	items: [dynamic]string
	defer delete(items)
	for i in 0 ..< 40 {
		append(&items, "An item of the menu")
	}
	button := popup_test_make_menu_button(
		g,
		g.root,
		"long",
		GUI.Rect{x = 10, y = 10, w = 80, h = 24},
		items[:],
	)
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, button)
	pw := GUI.Widget_Get(g, popup)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	//* The menu is not taller than the window.
	testing.expect_value(t, pw.rect.h <= g.viewport.h, true)
	testing.expect_value(t, pw.rect.y + pw.rect.h <= g.viewport.y + g.viewport.h, true)

	test_gui_destroy(g)
}

@(test)
test_the_menu_of_a_menu_button_has_a_background :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := menu_button_test_make(g, {"New", "Open", "Save"})
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, button)
	pw := GUI.Widget_Get(g, popup)
	//* There is no theme on this GUI, and the menu is still a plate
	//* with a colour on it.
	style := GUI.resolved_style(g, pw)
	testing.expect_value(t, style.box.bg_color != (GUI.Colour{}), true)
	testing.expect_value(t, style.box.bg_color.a, 1.0)
	testing.expect_value(t, GUI.resolved_bg(g, popup, pw).a, 1.0)

	test_gui_destroy(g)
}

@(test)
test_the_menu_of_a_menu_button_follows_the_button :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	button := popup_test_make_menu_button(
		g,
		g.root,
		"corner",
		GUI.Rect{x = 300, y = 250, w = 80, h = 24},
		{"New", "Open", "Save"},
	)
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, button)
	pw := GUI.Widget_Get(g, popup)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	before := pw.rect

	//* The window is made smaller while the menu is open.
	GUI.gui_resize(g, 400, 300)
	g.window_rect = g.viewport
	GUI.Frame(g)

	pw = GUI.Widget_Get(g, popup)
	testing.expect_value(t, pw.rect != before, true)
	testing.expect_value(t, pw.rect.x + pw.rect.w <= g.viewport.x + g.viewport.w, true)
	testing.expect_value(t, pw.rect.y + pw.rect.h <= g.viewport.y + g.viewport.h, true)

	test_gui_destroy(g)
}

@(test)
test_the_menu_of_a_menu_button_in_a_floating_panel_opens_in_that_window :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	GUI.layout_pass(g)
	//* The panel is small, so the menu does not fit under the button.
	GUI.Make_Float_Panel(g, panel, GUI.Vec2{100, 100}, GUI.Vec2{120, 60})
	GUI.layout_pass(g)

	button := popup_test_make_menu_button(
		g,
		panel,
		"file",
		GUI.Rect{x = 10, y = 10, w = 80, h = 24},
		{"New", "Open", "Save"},
	)
	GUI.layout_pass(g)

	//* The button is in the window of the panel, so the click is in the
	//* coordinates of that window.
	point := centre_of(GUI.Widget_Get(g, button))
	global := GUI.Vec2{g.floats[0].pos.x + point.x, g.floats[0].pos.y + point.y}
	append(&g.events, mouse_down_float(global, point))
	append(&g.events, mouse_up_float(global, point))
	GUI.Handle_Events(g)

	popup := GUI.menu_button_popup(g, button)
	pw := GUI.Widget_Get(g, popup)
	testing.expect_value(t, GUI.Popup_Is_Open(g, popup), true)
	//* The menu is under the panel, so it comes up in the window of the
	//* panel.
	testing.expect_value(t, pw.parent, panel)
	//* The menu is inside the window of the panel.
	testing.expect_value(t, pw.rect.x >= 0, true)
	testing.expect_value(t, pw.rect.y >= 0, true)
	testing.expect_value(t, pw.rect.x + pw.rect.w <= 120, true)
	testing.expect_value(t, pw.rect.y + pw.rect.h <= 60, true)

	//* The menu is drawn in the list of the panel.
	GUI.Frame(g)
	testing.expect_value(t, len(g.floats[0].draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_popup_menu_without_an_owner_opens_at_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	menu := GUI.Make_Popup_Menu(g, g.root, GUI.Popup_Menu_Opts{items = {"New", "Open"}})
	GUI.layout_pass(g)

	g.pointer_known = true
	g.pointer = GUI.Vec2{200, 150}
	g.global_pointer = GUI.Vec2{200, 150}
	GUI.Popup_Menu_Open(g, menu)

	pw := GUI.Widget_Get(g, menu)
	testing.expect_value(t, GUI.Popup_Is_Open(g, menu), true)
	//* The menu comes up at the pointer, and it is not the whole
	//* window.
	testing.expect_value(t, pw.rect.x, 200.0)
	testing.expect_value(t, pw.rect.y, 150.0)
	testing.expect_value(t, pw.rect.w != g.viewport.w, true)
	testing.expect_value(t, pw.rect.h != g.viewport.h, true)

	test_gui_destroy(g)
}

//* Tests for the widgets that came after the first ones: the buttons
//* that hold a value, the lists, and the containers that lay their
//* children out.

//* A key that is pressed.
key_event :: proc(key: GUI.Key, mods := GUI.Mods{}) -> GUI.Key_Down_Event {
	return GUI.Key_Down_Event{key = key, mods = mods}
}

//* == The check box ==

@(test)
test_a_check_box_turns_on_and_off_when_it_is_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{min_size = GUI.Vec2{200, 60}})
	check := GUI.Make_Check_Box(g, box, GUI.Check_Box_Opts{text = "agree"})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.check_box_is_on(g, check), false)

	point := check_box_square_point(g, check)
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.check_box_is_on(g, check), true)

	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.check_box_is_on(g, check), false)

	test_gui_destroy(g)
}

check_box_square_point :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> GUI.Vec2 {
	w := GUI.Widget_Get(g, id)
	if w == nil {return GUI.Vec2{}}
	square := GUI.check_box_square(g, w, GUI.check_box_content(g, w))
	return GUI.Vec2{square.x + square.w * 0.5, square.y + square.h * 0.5}
}

check_box_label_point :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> GUI.Vec2 {
	w := GUI.Widget_Get(g, id)
	if w == nil {return GUI.Vec2{}}
	content := GUI.check_box_content(g, w)
	square := GUI.check_box_square(g, w, content)
	return GUI.Vec2 {
		square.x + GUI.CHECK_BOX_SIZE + GUI.CHECK_BOX_GAP + 1,
		square.y + square.h * 0.5,
	}
}

@(test)
test_a_check_box_is_not_turned_on_by_its_label :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{min_size = GUI.Vec2{200, 60}})
	check := GUI.Make_Check_Box(g, box, GUI.Check_Box_Opts{text = "agree"})
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, check)
	content := GUI.check_box_content(g, w)
	square := GUI.check_box_square(g, w, content)
	testing.expect_value(t, square.x + GUI.CHECK_BOX_SIZE + GUI.CHECK_BOX_GAP < content.w, true)
	testing.expect_value(t, w.min_size.x >= GUI.CHECK_BOX_SIZE + GUI.CHECK_BOX_GAP, true)

	point := check_box_label_point(g, check)
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.check_box_is_on(g, check), false)

	point = check_box_square_point(g, check)
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.check_box_is_on(g, check), true)

	test_gui_destroy(g)
}

link_test_link: string = ""

link_test_on_link :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, link: string) -> bool {
	link_test_link = link
	return true
}

@(test)
test_a_link_button_fires_its_signal :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	link := GUI.Make_Link_Button(
		g,
		g.root,
		GUI.Link_Button_Opts{text = "CalcUI", link = "https://example.com"},
	)
	GUI.Widget_Get(g, link).signals.on_link_activated = link_test_on_link
	GUI.layout_pass(g)

	link_test_link = ""
	point := centre_of(GUI.Widget_Get(g, link))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, link_test_link, "https://example.com")

	test_gui_destroy(g)
}

@(test)
test_a_link_button_opens_the_link_when_the_program_does_not_take_it :: proc(t: ^testing.T) {
	g := test_gui(t)
	state := new(Mock_State)
	g.backend = mock_backend_with(state)

	link := GUI.Make_Link_Button(
		g,
		g.root,
		GUI.Link_Button_Opts{text = "CalcUI", link = "https://example.com"},
	)
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, link))
	append(&g.events, mouse_down(point, 1))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, state.opened, "https://example.com")

	free(state)
	test_gui_destroy(g)
}

@(test)
test_a_link_button_asks_for_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	link := GUI.Make_Link_Button(
		g,
		g.root,
		GUI.Link_Button_Opts{text = "CalcUI", link = "https://example.com"},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, link)
	g.pointer = GUI.Vec2{w.rect.x + w.rect.w * 0.5, w.rect.y + w.rect.h * 0.5}
	GUI.update_link_button(g, link, w, 0.016)
	testing.expect_value(t, g.cursor, .Pointer)

	g.pointer = GUI.Vec2{w.rect.x + w.rect.w + 20, w.rect.y + w.rect.h * 0.5}
	g.cursor = .Default
	GUI.update_link_button(g, link, w, 0.016)
	testing.expect_value(t, g.cursor, .Default)

	test_gui_destroy(g)
}

@(test)
test_a_button_puts_its_text_where_it_is_told_to :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	theme := GUI.Default_Theme_Dark()
	GUI.GUI_Set_Theme(g, theme)

	plain := GUI.Make_Button(g, g.root, GUI.Button_Opts{text = "OK"})
	left := GUI.Make_Button(g, g.root, GUI.Button_Opts{text = "OK", text_align = .Left})
	right := GUI.Make_Button(g, g.root, GUI.Button_Opts{text = "OK", text_align = .Right})
	centre := GUI.Make_Button(g, g.root, GUI.Button_Opts{text = "OK", text_align = .Center})
	coloured := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts {
			text = "OK",
			text_align = .Left,
			Base_Opts = GUI.Base_Opts {
				style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(1, 0, 0, 1)}},
			},
		},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.resolved_style(g, GUI.Widget_Get(g, plain)).text.align, .Center)
	testing.expect_value(t, GUI.resolved_style(g, GUI.Widget_Get(g, left)).text.align, .Left)
	testing.expect_value(t, GUI.resolved_style(g, GUI.Widget_Get(g, right)).text.align, .Right)
	testing.expect_value(t, GUI.resolved_style(g, GUI.Widget_Get(g, centre)).text.align, .Center)

	testing.expect_value(
		t,
		GUI.resolved_style(g, GUI.Widget_Get(g, coloured)).text.colour,
		GUI.RGBA(1, 0, 0, 1),
	)

	test_gui_destroy(g)
}

//* == The slider ==

@(test)
test_a_slider_keeps_its_value_between_its_bounds :: proc(t: ^testing.T) {
	g := test_gui(t)

	slider := GUI.Make_Slider(
		g,
		g.root,
		.HSlider,
		GUI.Slider_Opts{value = 50, min = 0, max = 100, step = 10},
	)

	testing.expect_value(t, GUI.slider_value(g, slider), 50.0)

	//* A value outside of the bounds is cut to them.
	GUI.slider_set_value(g, slider, 200)
	testing.expect_value(t, GUI.slider_value(g, slider), 100.0)
	GUI.slider_set_value(g, slider, -20)
	testing.expect_value(t, GUI.slider_value(g, slider), 0.0)

	//* The value snaps to the step of the slider.
	GUI.slider_set_value(g, slider, 47)
	testing.expect_value(t, GUI.slider_value(g, slider), 50.0)

	test_gui_destroy(g)
}

@(test)
test_a_slider_follows_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)

	slider := GUI.Make_Slider(
		g,
		g.root,
		.HSlider,
		GUI.Slider_Opts {
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 100, bottom = 20},
			},
			value = 0,
			min = 0,
			max = 100,
			step = 1,
		},
	)
	GUI.layout_pass(g)

	//* The slider is a hundred wide, so the pointer at its middle
	//* puts the value at fifty.
	GUI.slider_move_to(g, slider, GUI.Vec2{50, 10})
	testing.expect_value(t, GUI.slider_value(g, slider), 50.0)

	//* The pointer at its end puts the value at the end of the range.
	GUI.slider_move_to(g, slider, GUI.Vec2{100, 10})
	testing.expect_value(t, GUI.slider_value(g, slider), 100.0)

	test_gui_destroy(g)
}

//* == The progress bar ==

@(test)
test_a_progress_bar_keeps_its_value_between_its_bounds :: proc(t: ^testing.T) {
	g := test_gui(t)

	bar := GUI.Make_Progress_Bar(g, g.root, GUI.Progress_Bar_Opts{value = 30, max = 100})

	GUI.progress_bar_set_value(g, bar, 60)
	testing.expect_value(t, bar_value(g, bar), 60.0)
	GUI.progress_bar_set_value(g, bar, 200)
	testing.expect_value(t, bar_value(g, bar), 100.0)

	test_gui_destroy(g)
}

bar_value :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> f32 {
	w := GUI.Widget_Get(g, id)
	if w == nil {return 0}
	#partial switch d in w.data {
	case GUI.Progress_Bar_Data:
		return d.value
	}
	return 0
}

//* == The list ==

@(test)
test_a_list_picks_the_item_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	list := GUI.Make_Item_List(g, g.root, GUI.Item_List_Opts{items = {"First", "Second", "Third"}})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.item_list_count(g, list), 3)
	testing.expect_value(t, GUI.item_list_text(g, list, 1), "Second")

	//* A click on the second row picks the second item.
	append(&g.events, mouse_down({10, GUI.ITEM_LIST_ROW + 5}, 1))
	append(&g.events, mouse_up({10, GUI.ITEM_LIST_ROW + 5}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, list).data {
	case GUI.Item_List_Data:
		testing.expect_value(t, d.selected, 1)
	}

	test_gui_destroy(g)
}

@(test)
test_a_tree_picks_the_item_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	tree := GUI.Make_Tree(g, g.root, GUI.Tree_Opts{})
	GUI.layout_pass(g)

	root := GUI.tree_add_item(g, tree, "The project", -1)
	GUI.tree_add_item(g, tree, "The source", root)
	GUI.tree_add_item(g, tree, "The readme", -1)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.tree_item_count(g, tree), 3)
	testing.expect_value(t, GUI.tree_item_text(g, tree, 1), "The source")

	//* A click on the third row picks the third item.
	append(&g.events, mouse_down({10, GUI.TREE_ROW * 2 + 5}, 1))
	append(&g.events, mouse_up({10, GUI.TREE_ROW * 2 + 5}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, tree).data {
	case GUI.Tree_Data:
		testing.expect_value(t, d.selected, 2)
	}

	test_gui_destroy(g)
}

//* == The size of the tree ==

@(test)
test_a_tree_is_as_wide_as_the_widest_of_its_items :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{})
	narrow := GUI.Make_Tree(g, box, GUI.Tree_Opts{})
	wide := GUI.Make_Tree(g, box, GUI.Tree_Opts{})
	GUI.layout_pass(g)

	GUI.tree_add_item(g, narrow, "One", -1)
	GUI.tree_add_item(g, wide, "One item that is much longer than the other one", -1)
	GUI.layout_pass(g)

	//* The tree is as wide as the widest of the items in it.
	testing.expect_value(t, GUI.Widget_Get(g, wide).rect.w > GUI.Widget_Get(g, narrow).rect.w, true)

	test_gui_destroy(g)
}

@(test)
test_a_tree_keeps_the_size_the_program_asks_for :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	tree := GUI.Make_Tree(
		g,
		g.root,
		GUI.Tree_Opts{
			Base_Opts = GUI.Base_Opts{min_size = GUI.Vec2{150, 0}, max_size = GUI.Vec2{200, 0}},
		},
	)
	GUI.layout_pass(g)

	GUI.tree_add_item(g, tree, "One item that is much longer than the room it is given", -1)
	GUI.layout_pass(g)

	//* The smallest size of the program is the smallest size of the tree,
	//* and the largest size of the program is the largest size of it.
	w := GUI.Widget_Get(g, tree)
	testing.expect_value(t, w.min_size.x >= 150.0, true)
	testing.expect_value(t, w.min_size.x <= 200.0, true)

	test_gui_destroy(g)
}

@(test)
test_a_tree_scrolls_the_rows_that_do_not_fit :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	tree := GUI.Make_Tree(
		g,
		g.root,
		GUI.Tree_Opts{
			Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 120, 40}},
		},
	)
	GUI.layout_pass(g)

	texts := []string{"One", "Two", "Three", "Four", "Five", "Six"}
	for text in texts {
		GUI.tree_add_item(g, tree, text, -1)
	}
	GUI.layout_pass(g)

	//* The wheel scrolls the rows that do not fit.
	append(&g.events, mouse_move({10, 10}))
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	d := GUI.tree_data(g, tree)
	testing.expect_value(t, d.scroll > 0.0, true)

	//* The click picks the row that is on the screen, and not the one
	//* that is under the pointer before the scroll.
	append(&g.events, mouse_down({10, 10}, 1))
	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, tree).data {
	case GUI.Tree_Data:
		testing.expect_value(t, d.selected, 3)
	}

	test_gui_destroy(g)
}

@(test)
test_a_tree_scrolls_the_row_that_is_picked_into_the_room :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	tree := GUI.Make_Tree(
		g,
		g.root,
		GUI.Tree_Opts{
			Base_Opts = GUI.Base_Opts{preset = .Top_Left, offsets = GUI.Offset{0, 0, 120, 40}},
		},
	)
	GUI.layout_pass(g)

	texts := []string{"One", "Two", "Three", "Four", "Five", "Six"}
	for text in texts {
		GUI.tree_add_item(g, tree, text, -1)
	}
	GUI.layout_pass(g)

	//* A row that is below the room of the tree is scrolled to.
	GUI.tree_select_item(g, tree, 5)

	d := GUI.tree_data(g, tree)
	testing.expect_value(t, d.scroll > 0.0, true)

	//* The scroll never goes past the last row.
	GUI.tree_select_item(g, tree, 0)
	testing.expect_value(t, d.scroll, 0.0)

	test_gui_destroy(g)
}


//* == The containers ==

@(test)
test_a_grid_puts_its_children_in_rows_and_columns :: proc(t: ^testing.T) {
	g := test_gui(t)

	grid := GUI.Make_Grid_Container(
		g,
		g.root,
		GUI.Grid_Opts{Base_Opts = GUI.Base_Opts{separation = 0}, columns = 2},
	)
	a := GUI.New_Widget(g, .Panel, grid, GUI.Widget_Opts{min_size = GUI.Vec2{40, 20}})
	b := GUI.New_Widget(g, .Panel, grid, GUI.Widget_Opts{min_size = GUI.Vec2{60, 20}})
	c := GUI.New_Widget(g, .Panel, grid, GUI.Widget_Opts{min_size = GUI.Vec2{40, 30}})

	GUI.layout_pass(g)

	//* The first two are side by side, the third is under the first.
	testing.expect_value(t, GUI.Widget_Get(g, a).rect.x, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, a).rect.w, 40.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.x, 44.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.w, 60.0)
	testing.expect_value(t, GUI.Widget_Get(g, c).rect.x, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, c).rect.y, 24.0)

	test_gui_destroy(g)
}

@(test)
test_a_margin_keeps_its_child_away_from_its_edges :: proc(t: ^testing.T) {
	g := test_gui(t)

	margin := GUI.Make_Margin_Container(g, g.root, GUI.Margin_Opts{margin = {10, 20, 30, 40}})
	child := GUI.New_Widget(g, .Panel, margin, GUI.Widget_Opts{})

	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, child).rect.x, 10.0)
	testing.expect_value(t, GUI.Widget_Get(g, child).rect.y, 20.0)
	testing.expect_value(t, GUI.Widget_Get(g, child).rect.w, 800.0 - 10.0 - 30.0)
	testing.expect_value(t, GUI.Widget_Get(g, child).rect.h, 600.0 - 20.0 - 40.0)

	test_gui_destroy(g)
}

@(test)
test_a_centre_puts_its_child_in_the_middle :: proc(t: ^testing.T) {
	g := test_gui(t)

	centre := GUI.Make_Center_Container(g, g.root, GUI.Center_Opts{})
	child := GUI.New_Widget(g, .Panel, centre, GUI.Widget_Opts{min_size = GUI.Vec2{100, 40}})

	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, child).rect.x, 350.0)
	testing.expect_value(t, GUI.Widget_Get(g, child).rect.y, 280.0)
	testing.expect_value(t, GUI.Widget_Get(g, child).rect.w, 100.0)

	test_gui_destroy(g)
}

@(test)
test_a_flow_container_starts_a_new_row_when_there_is_no_room :: proc(t: ^testing.T) {
	g := test_gui(t)

	flow := GUI.Make_Flow_Container(
		g,
		g.root,
		GUI.Flow_Container_Opts {
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 70, bottom = 100},
			},
		},
	)
	a := GUI.New_Widget(g, .Panel, flow, GUI.Widget_Opts{min_size = GUI.Vec2{60, 20}})
	b := GUI.New_Widget(g, .Panel, flow, GUI.Widget_Opts{min_size = GUI.Vec2{60, 20}})

	//* The box is narrow enough for one of them at a time.
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, a).rect.x, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.y, 24.0)

	test_gui_destroy(g)
}

@(test)
test_the_offset_of_a_scroll_container_is_cut_to_what_it_can_show :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 200, bottom = 100},
			},
		},
	)
	GUI.New_Widget(g, .Panel, container, GUI.Widget_Opts{min_size = GUI.Vec2{300, 400}})

	GUI.layout_pass(g)

	GUI.Scroll_Container_Set_Offset(g, container, GUI.Vec2{1000, 1000})
	offset := GUI.Scroll_Container_Get_Offset(g, container)
	testing.expect_value(t, offset.x, 100.0)
	testing.expect_value(t, offset.y, 300.0)

	GUI.Scroll_Container_Set_Offset(g, container, GUI.Vec2{-50, -50})
	offset = GUI.Scroll_Container_Get_Offset(g, container)
	testing.expect_value(t, offset.x, 0.0)
	testing.expect_value(t, offset.y, 0.0)

	test_gui_destroy(g)
}

@(test)
test_the_wheel_scrolls_the_scroll_container_under_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 200, bottom = 100},
			},
		},
	)
	GUI.New_Widget(g, .Panel, container, GUI.Widget_Opts{min_size = GUI.Vec2{300, 400}})

	GUI.layout_pass(g)

	append(&g.events, mouse_move({50, 50}))
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 60.0)

	append(&g.events, GUI.Wheel_Event{amount = 1})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)

	test_gui_destroy(g)
}

@(test)
test_the_wheel_of_an_inner_scroll_container_does_not_reach_the_outer_one :: proc(t: ^testing.T) {
	g := test_gui(t)

	outer := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 400, bottom = 300},
			},
		},
	)
	inner := GUI.Make_Scroll_Container(
		g,
		outer,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				min_size = GUI.Vec2{300, 400},
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 300, bottom = 400},
			},
		},
	)
	GUI.New_Widget(g, .Panel, inner, GUI.Widget_Opts{min_size = GUI.Vec2{300, 1000}})

	GUI.layout_pass(g)

	append(&g.events, mouse_move({50, 50}))
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, inner).y, 60.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, outer).y, 0.0)

	append(&g.events, mouse_move({350, 50}))
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, outer).y, 60.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, inner).y, 60.0)

	test_gui_destroy(g)
}

@(test)
test_a_scroll_container_has_no_scroll_bar_when_the_content_fits :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 200, bottom = 100},
			},
		},
	)
	content := GUI.New_Widget(g, .Panel, container, GUI.Widget_Opts{min_size = GUI.Vec2{100, 50}})

	GUI.layout_pass(g)

	bar := GUI.scroll_bar_id(g, container)
	testing.expect_value(t, bar != GUI.INVALID_WIDGET_ID, true)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, bar).state, false)

	GUI.Widget_Set_Min_Size(g, content, GUI.Vec2{100, 500})
	GUI.layout_pass(g)

	testing.expect_value(t, .Visible in GUI.Widget_Get(g, bar).state, true)

	test_gui_destroy(g)
}

@(test)
test_the_scroll_bar_can_be_dragged_and_it_pages_the_content :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 200, bottom = 100},
			},
		},
	)
	GUI.New_Widget(g, .Panel, container, GUI.Widget_Opts{min_size = GUI.Vec2{300, 400}})

	GUI.layout_pass(g)

	bar := GUI.scroll_bar_id(g, container)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, bar).state, true)

	append(&g.events, mouse_down({195, 10}))
	append(&g.events, mouse_move({195, 50}))
	append(&g.events, mouse_up({195, 50}))
	GUI.Handle_Events(g)

	testing.expect_value(t, abs(GUI.Scroll_Container_Get_Offset(g, container).y - 160.0) < 0.01, true)

	append(&g.events, mouse_down({195, 90}))
	append(&g.events, mouse_up({195, 90}))
	GUI.Handle_Events(g)

	testing.expect_value(t, abs(GUI.Scroll_Container_Get_Offset(g, container).y - 250.0) < 0.01, true)

	test_gui_destroy(g)
}

@(test)
test_the_side_of_the_scroll_bar_of_a_scroll_container_can_be_changed :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts {
				preset = .Top_Left,
				offsets = GUI.Offset{left = 0, top = 0, right = 200, bottom = 100},
			},
		},
	)
	GUI.New_Widget(g, .Panel, container, GUI.Widget_Opts{min_size = GUI.Vec2{300, 400}})

	GUI.layout_pass(g)

	bar := GUI.scroll_bar_id(g, container)
	testing.expect_value(t, GUI.Widget_Get(g, bar).rect.x, 190.0)

	GUI.Scroll_Container_Set_Bar(g, container, .Left)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, bar).rect.x, 0.0)
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, bar).state, true)

	GUI.Scroll_Container_Set_Bar(g, container, .None)
	GUI.layout_pass(g)

	testing.expect_value(t, .Visible in GUI.Widget_Get(g, bar).state, false)

	test_gui_destroy(g)
}


//* == The focus ==

@(test)
test_the_tab_key_moves_the_focus_from_one_widget_to_the_next :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 10})
	a := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{text = "a"})
	b := GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{text = "b"})
	GUI.layout_pass(g)

	//* Nothing has the focus yet, so the tab key gives it to the
	//* first widget that can have it.
	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, a)

	append(&g.events, key_event(.Tab))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, b)

	//* And back again with the shift key held down.
	append(&g.events, key_event(.Tab, GUI.Mods{.Shift}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, a)

	test_gui_destroy(g)
}

@(test)
test_a_widget_that_ignores_the_mouse_is_passed_over :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{})
	behind := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{})
	front := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{mouse_filter = .Ignore})
	GUI.layout_pass(g)

	//* The widget on top ignores the mouse, so the one behind it is
	//* found.
	testing.expect_value(t, GUI.hit_test(g, g.root, GUI.Vec2{10, 10}), behind)

	test_gui_destroy(g)
}

//* == The virtual list and the data table ==
//* The tests of the widgets that show a great many rows. The rows come
//* from the program, and only the rows that are on the screen are
//* drawn.

//* == The data of the program ==

//* A row of the data in the tests.
Virtual_Test_Row :: struct {
	//* The text of the row, for the lists.
	text: string,
	//* The values of the row, for the tables.
	values: [4]string,
	//* The key of the row: the thing that stays the same when the
	//: rows are put in another order.
	key: u64,
	//* The height of the row, for the lists whose rows are not all the
	//: same height.
	height: f32,
}

//* The data of the program in the tests.
Virtual_Test_Data :: struct {
	rows: [dynamic]Virtual_Test_Row,
	//* How many times the text of a row was asked for.
	asked: int,
	//* How many times the values of a row were asked for.
	asked_values: int,
}

//* A source of a list whose rows are the rows of the data.
virtual_test_list_source :: proc(data: ^Virtual_Test_Data, variable := false) -> GUI.List_Source {
	source := GUI.List_Source {
		count = proc(ctx: rawptr) -> int {
			return len((cast(^Virtual_Test_Data)ctx).rows)
		},
		text = proc(ctx: rawptr, index: int) -> string {
			d := cast(^Virtual_Test_Data)ctx
			d.asked += 1
			if index < 0 || index >= len(d.rows) {return ""}
			return d.rows[index].text
		},
		key = proc(ctx: rawptr, index: int) -> u64 {
			d := cast(^Virtual_Test_Data)ctx
			if index < 0 || index >= len(d.rows) {return 0}
			return d.rows[index].key
		},
		ctx = cast(rawptr)data,
	}
	if variable {
		source.height = proc(ctx: rawptr, index: int) -> f32 {
			d := cast(^Virtual_Test_Data)ctx
			if index < 0 || index >= len(d.rows) {return 0}
			return d.rows[index].height
		}
	}
	return source
}

//* A source of a table whose rows are the rows of the data.
virtual_test_table_source :: proc(data: ^Virtual_Test_Data) -> GUI.Table_Source {
	return GUI.Table_Source {
		count = proc(ctx: rawptr) -> int {
			return len((cast(^Virtual_Test_Data)ctx).rows)
		},
		values = proc(ctx: rawptr, index: int) -> []string {
			d := cast(^Virtual_Test_Data)ctx
			d.asked_values += 1
			if index < 0 || index >= len(d.rows) {return nil}
			return d.rows[index].values[:]
		},
		key = proc(ctx: rawptr, index: int) -> u64 {
			d := cast(^Virtual_Test_Data)ctx
			if index < 0 || index >= len(d.rows) {return 0}
			return d.rows[index].key
		},
		ctx = cast(rawptr)data,
	}
}

//* Fills the data with rows that have a key of their own.
virtual_test_fill :: proc(data: ^Virtual_Test_Data, count: int) {
	clear(&data.rows)
	for i in 0 ..< count {
		append(&data.rows, Virtual_Test_Row {
			text = "row",
			values = {"alpha", "bravo", "charlie", "delta"},
			key = u64(i + 1),
		})
	}
}

//* == The virtual list ==

@(test)
test_a_virtual_list_only_draws_the_rows_that_are_on_the_screen :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 100000)

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.virtual_list_count(g, list), 100000)
	testing.expect_value(t, GUI.virtual_list_first_row(g, list), 0)

	GUI.Frame(g)

	//* The hundred thousand rows are not all drawn: only the ones that
	//* are on the screen are. The program is asked for the text of
	//* those rows and of no others.
	testing.expect_value(t, len(g.draw.vertices) > 0, true)
	testing.expect_value(t, len(g.draw.vertices) < 10000, true)
	testing.expect_value(t, data.asked, 31)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_makes_no_widget_for_every_row :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 1000)

	before := len(g.widgets)
	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)

	//* The list is one widget, whatever the number of rows is.
	testing.expect_value(t, len(g.widgets), before + 1)
	testing.expect_value(t, GUI.virtual_list_count(g, list), 1000)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_picks_the_row_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 100)

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)

	//* A click on the third row picks it.
	append(&g.events, mouse_down({10, 50}, 1))
	append(&g.events, mouse_up({10, 50}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.virtual_list_selected(g, list), 2)
	testing.expect_value(t, GUI.virtual_list_key(g, list, 2), 3)

	//* A click on the same row takes it away again.
	append(&g.events, mouse_down({10, 50}, 1))
	append(&g.events, mouse_up({10, 50}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.virtual_list_selected(g, list), -1)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_keeps_the_row_that_is_picked_when_the_rows_change :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 3)

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)

	GUI.virtual_list_select(g, list, 1)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 1)

	//* The program puts the rows in another order. The row that was
	//* picked is the last one now, and it is still picked.
	row := data.rows[2]
	data.rows[2] = data.rows[1]
	data.rows[1] = data.rows[0]
	data.rows[0] = row
	GUI.virtual_list_refresh(g, list)

	testing.expect_value(t, GUI.virtual_list_selected(g, list), 2)
	testing.expect_value(t, GUI.virtual_list_key(g, list, 2), 2)
	testing.expect_value(t, GUI.virtual_list_is_picked(g, list, 2), true)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_finds_the_rows_that_are_on_the_screen :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 1000)

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)

	GUI.virtual_list_set_scroll(g, list, 200)
	rows := GUI.virtual_list_visible_rows(g, list)
	testing.expect_value(t, rows.first, 10)
	testing.expect_value(t, rows.last, 41)
	testing.expect_value(t, GUI.virtual_list_first_row(g, list), 10)

	//* The scroll never goes below the last row.
	GUI.virtual_list_set_scroll(g, list, 100000)
	testing.expect_value(t, GUI.virtual_list_scroll(g, list), 20000 - 600)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_scrolls_with_the_wheel :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 1000)

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_move({10, 10}))
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	//* The wheel goes over three rows at a time.
	testing.expect_value(t, GUI.virtual_list_scroll(g, list), 60)
	testing.expect_value(t, GUI.virtual_list_first_row(g, list), 3)

	append(&g.events, GUI.Wheel_Event{amount = 1})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.virtual_list_scroll(g, list), 0)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_moves_the_cursor_with_the_keys :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 1000)

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data), row_height = 20},
	)
	GUI.layout_pass(g)
	GUI.focus_set(g, list)

	append(&g.events, GUI.Key_Down_Event{key = .Down})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 0)

	append(&g.events, GUI.Key_Down_Event{key = .Down})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 1)

	append(&g.events, GUI.Key_Down_Event{key = .Up})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 0)

	//* The end of the list is one key away.
	append(&g.events, GUI.Key_Down_Event{key = .End})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 999)

	//* The row that is picked is brought onto the screen.
	testing.expect_value(t, GUI.virtual_list_scroll(g, list) > 0, true)

	append(&g.events, GUI.Key_Down_Event{key = .Home})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 0)
	testing.expect_value(t, GUI.virtual_list_scroll(g, list), 0)

	test_gui_destroy(g)
}

@(test)
test_a_virtual_list_shows_rows_of_different_heights :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 3)
	data.rows[0].height = 10
	data.rows[1].height = 20
	data.rows[2].height = 30

	list := GUI.Make_Virtual_List(
		g,
		g.root,
		GUI.Virtual_List_Opts{source = virtual_test_list_source(&data, true), row_height = 20},
	)
	GUI.layout_pass(g)

	//* The rows are 10, 20 and 30 high, so the first screenful shows
	//* all three of them.
	rows := GUI.virtual_list_visible_rows(g, list)
	testing.expect_value(t, rows.first, 0)
	testing.expect_value(t, rows.last, 3)

	//* A click on the second row picks the second row.
	append(&g.events, mouse_down({10, 15}, 1))
	append(&g.events, mouse_up({10, 15}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_selected(g, list), 1)

	//* A click on the third row picks the third row.
	append(&g.events, mouse_down({10, 35}, 1))
	append(&g.events, mouse_up({10, 35}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.virtual_list_is_picked(g, list, 2), true)
	testing.expect_value(t, GUI.virtual_list_is_picked(g, list, 1), true)

	test_gui_destroy(g)
}

//* == The data table ==

@(test)
test_a_data_table_puts_new_values_in_a_row :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	table := GUI.Make_Data_Table(g, g.root, GUI.Data_Table_Opts{})
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.data_table_add_row(g, table, {"alpha"})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 0), "alpha")

	//* A row of the table itself is changed without making the table
	//* again.
	GUI.data_table_set_row(g, table, 0, {"bravo"})

	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 0), "bravo")
	testing.expect_value(t, GUI.data_table_row_count(g, table), 1)

	test_gui_destroy(g)
}

@(test)
test_a_data_table_sorts_a_column_with_the_order_of_the_column :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	clear(&data.rows)
	append(&data.rows, Virtual_Test_Row{values = {"ten", "10", "", ""}, key = 1})
	append(&data.rows, Virtual_Test_Row{values = {"two", "2", "", ""}, key = 2})
	append(&data.rows, Virtual_Test_Row{values = {"one", "1", "", ""}, key = 3})

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.data_table_add_column(g, table, "size", 100)
	GUI.layout_pass(g)

	//* The second column is a number, and the order of the text would
	//: put ten before two.
	column := GUI.data_table_column(g, table, 1)
	column.compare = proc(a, b: string) -> int {
		x, x_ok := strconv.parse_int(a)
		y, y_ok := strconv.parse_int(b)
		if !x_ok || !y_ok {return strings.compare(a, b)}
		return x - y
	}
	GUI.data_table_set_column(g, table, 1, column)

	GUI.data_table_sort_by(g, table, 1)

	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 1), "1")
	testing.expect_value(t, GUI.data_table_cell(g, table, 1, 1), "2")
	testing.expect_value(t, GUI.data_table_cell(g, table, 2, 1), "10")

	test_gui_destroy(g)
}

@(test)
test_a_data_table_scrolls_sideways_with_the_shift_and_the_wheel :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 10)

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 600)
	GUI.data_table_add_column(g, table, "size", 600)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.data_table_h_scroll(g, table), 0)

	append(&g.events, mouse_move({10, 100}))
	g.mods = GUI.Mods{.Shift}
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	//* The table is 1200 wide and the window is 800, so the table goes
	//* 400 sideways at the most.
	testing.expect_value(t, GUI.data_table_h_scroll(g, table), 72)
	testing.expect_value(t, GUI.data_table_h_scroll(g, table) > 0, true)

	append(&g.events, GUI.Wheel_Event{amount = -1000})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.data_table_h_scroll(g, table), 400)

	test_gui_destroy(g)
}

@(test)
test_a_data_table_sorts_the_rows_by_the_column_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	clear(&data.rows)
	append(&data.rows, Virtual_Test_Row{values = {"charlie", "3", "", ""}, key = 1})
	append(&data.rows, Virtual_Test_Row{values = {"alpha", "1", "", ""}, key = 2})
	append(&data.rows, Virtual_Test_Row{values = {"bravo", "2", "", ""}, key = 3})

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.data_table_add_column(g, table, "size", 100)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.data_table_row_count(g, table), 3)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), -1)

	//* A click on the header of the first column puts the rows in the
	//* order of the alphabet.
	append(&g.events, mouse_down({10, 5}, 1))
	append(&g.events, mouse_up({10, 5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 0), "alpha")
	testing.expect_value(t, GUI.data_table_cell(g, table, 1, 0), "bravo")
	testing.expect_value(t, GUI.data_table_cell(g, table, 2, 0), "charlie")

	//* The same column again turns the order around.
	append(&g.events, mouse_down({10, 5}, 1))
	append(&g.events, mouse_up({10, 5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 0), "charlie")
	testing.expect_value(t, GUI.data_table_cell(g, table, 2, 0), "alpha")

	//* A click on a row picks it.
	append(&g.events, mouse_down({10, GUI.DATA_TABLE_HEADER_HEIGHT + 5}, 1))
	append(&g.events, mouse_up({10, GUI.DATA_TABLE_HEADER_HEIGHT + 5}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 0)

	GUI.Frame(g)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_a_data_table_only_draws_the_rows_that_are_on_the_screen :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 100000)

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.data_table_row_count(g, table), 100000)

	GUI.Frame(g)

	//* The hundred thousand rows are not all drawn.
	testing.expect_value(t, len(g.draw.vertices) > 0, true)
	testing.expect_value(t, len(g.draw.vertices) < 10000, true)

	//* The program is asked for the values of the rows that are on the
	//* screen and of no others.
	testing.expect_value(t, data.asked_values, 25)

	test_gui_destroy(g)
}

@(test)
test_a_data_table_keeps_the_row_that_is_picked_when_the_rows_are_sorted :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	clear(&data.rows)
	append(&data.rows, Virtual_Test_Row{values = {"charlie", "", "", ""}, key = 1})
	append(&data.rows, Virtual_Test_Row{values = {"alpha", "", "", ""}, key = 2})
	append(&data.rows, Virtual_Test_Row{values = {"bravo", "", "", ""}, key = 3})

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.layout_pass(g)

	//* The second row of the program is picked.
	GUI.data_table_select_row(g, table, 1)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 1)
	testing.expect_value(t, GUI.data_table_selected_source(g, table), 1)

	//* The rows are put in another order. The row that was picked is
	//* still the row of the program, and it is still picked.
	GUI.data_table_sort_by(g, table, 0)

	testing.expect_value(t, GUI.data_table_selected_source(g, table), 1)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 0)
	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 0), "alpha")

	test_gui_destroy(g)
}

@(test)
test_a_data_table_turns_the_rows_away_that_the_filter_turns_away :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	clear(&data.rows)
	append(&data.rows, Virtual_Test_Row{values = {"charlie", "", "", ""}, key = 1})
	append(&data.rows, Virtual_Test_Row{values = {"alpha", "", "", ""}, key = 2})
	append(&data.rows, Virtual_Test_Row{values = {"bravo", "", "", ""}, key = 3})

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.data_table_row_count(g, table), 3)

	//* The filter is asked for every row, and the rows it turns away
	//: are not shown.
	GUI.data_table_set_filter_fn(g, table, proc(ctx: rawptr, index: int, text: string) -> bool {
		rows := (cast(^Virtual_Test_Data)ctx).rows
		if index < 0 || index >= len(rows) {return false}
		return strings.contains(rows[index].values[0], text)
	})
	GUI.data_table_set_filter(g, table, "a")

	testing.expect_value(t, GUI.data_table_row_count(g, table), 3)

	GUI.data_table_set_filter(g, table, "al")

	testing.expect_value(t, GUI.data_table_row_count(g, table), 1)
	testing.expect_value(t, GUI.data_table_cell(g, table, 0, 0), "alpha")

	test_gui_destroy(g)
}

@(test)
test_a_data_table_stretches_the_columns_that_may_stretch :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 10)

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 100)
	column := GUI.data_table_column(g, table, 0)
	column.size = .Stretch
	GUI.data_table_set_column(g, table, 0, column)
	GUI.layout_pass(g)

	//* The column takes the width that is left over: the table is 800
	//: wide and the column was 100 wide.
	testing.expect_value(t, GUI.data_table_column_width(g, table, 0), 800)

	test_gui_destroy(g)
}

@(test)
test_a_data_table_picks_the_cell_that_was_clicked :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 10)

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 100)
	GUI.data_table_add_column(g, table, "size", 100)
	GUI.layout_pass(g)

	//* A click on the second row, in the second column.
	append(&g.events, mouse_down({150, GUI.DATA_TABLE_HEADER_HEIGHT + 30}, 1))
	append(&g.events, mouse_up({150, GUI.DATA_TABLE_HEADER_HEIGHT + 30}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.data_table_selected_row(g, table), 1)
	testing.expect_value(t, GUI.data_table_selected_column(g, table), 1)

	test_gui_destroy(g)
}

@(test)
test_a_data_table_scrolls_with_the_wheel :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 1000)

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.layout_pass(g)

	append(&g.events, mouse_move({10, 100}))
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.data_table_scroll(g, table), 72)

	//* The scroll never goes below the last row.
	append(&g.events, GUI.Wheel_Event{amount = -1000})
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.data_table_scroll(g, table), 1000 * GUI.DATA_TABLE_ROW_HEIGHT - (600 - GUI.DATA_TABLE_HEADER_HEIGHT))

	test_gui_destroy(g)
}

@(test)
test_a_data_table_moves_the_picked_cell_with_the_keys :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Virtual_Test_Data{}
	defer delete(data.rows)
	virtual_test_fill(&data, 100)

	table := GUI.Make_Data_Table(
		g,
		g.root,
		GUI.Data_Table_Opts{source = virtual_test_table_source(&data)},
	)
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.data_table_add_column(g, table, "size", 100)
	GUI.layout_pass(g)
	GUI.focus_set(g, table)

	append(&g.events, GUI.Key_Down_Event{key = .Down})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 0)

	append(&g.events, GUI.Key_Down_Event{key = .Down})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 1)

	append(&g.events, GUI.Key_Down_Event{key = .Right})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 1)
	testing.expect_value(t, GUI.data_table_selected_column(g, table), 1)

	append(&g.events, GUI.Key_Down_Event{key = .Up})
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.data_table_selected_row(g, table), 0)
	testing.expect_value(t, GUI.data_table_selected_column(g, table), 1)

	test_gui_destroy(g)
}

//* Headless tests for the GUI core: the tree, the layout, docking, the
//* text pipeline and the draw list. Run with: odin test src/GUI

@(test)
test_resolve_rect_anchors :: proc(t: ^testing.T) {
	parent := GUI.Rect {
		x = 0,
		y = 0,
		w = 100,
		h = 50,
	}

	r := GUI.resolve_rect(parent, GUI.Anchor{0, 0, 1, 1}, GUI.Offset{0, 0, 0, 0}, GUI.Vec2{0, 0}, .Both, .Both, GUI.Size_Flags{.Fill}, GUI.Size_Flags{.Fill}, false, false)
	testing.expect_value(t, r.x, 0.0)
	testing.expect_value(t, r.y, 0.0)
	testing.expect_value(t, r.w, 100.0)
	testing.expect_value(t, r.h, 50.0)

	r = GUI.resolve_rect(parent, GUI.Anchor{0, 0, 0.5, 1}, GUI.Offset{0, 0, 0, 0}, GUI.Vec2{0, 0}, .Both, .Both, GUI.Size_Flags{.Fill}, GUI.Size_Flags{.Fill}, false, false)
	testing.expect_value(t, r.w, 50.0)

	r = GUI.resolve_rect(
		parent,
		GUI.Anchor{0, 0, 1, 1},
		GUI.Offset{10, 20, -10, -20},
		GUI.Vec2{0, 0},
		.Both,
		.Both,
		GUI.Size_Flags{.Fill},
		GUI.Size_Flags{.Fill},
		false,
		false,
	)
	testing.expect_value(t, r.x, 10.0)
	testing.expect_value(t, r.y, 20.0)
	testing.expect_value(t, r.w, 80.0)
	testing.expect_value(t, r.h, 10.0)
}

@(test)
test_resolve_rect_min_size_grows :: proc(t: ^testing.T) {
	parent := GUI.Rect {
		x = 0,
		y = 0,
		w = 100,
		h = 50,
	}

	r := GUI.resolve_rect(parent, GUI.Anchor{0, 0, 0, 0}, GUI.Offset{0, 0, 0, 0}, GUI.Vec2{40, 10}, .End, .End, GUI.Size_Flags{.Fill}, GUI.Size_Flags{.Fill}, false, false)
	testing.expect_value(t, r.x, 0.0)
	testing.expect_value(t, r.w, 40.0)
	testing.expect_value(t, r.h, 10.0)

	r = GUI.resolve_rect(parent, GUI.Anchor{0, 0, 0, 0}, GUI.Offset{0, 0, 0, 0}, GUI.Vec2{40, 10}, .Begin, .Begin, GUI.Size_Flags{.Fill}, GUI.Size_Flags{.Fill}, false, false)
	testing.expect_value(t, r.x, -40.0)
	testing.expect_value(t, r.w, 40.0)
}

@(test)
test_split_layout_weights :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{name = "split", split = .Horizontal})
	left := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "left", weight = 1})
	right := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "right", weight = 3})

	GUI.layout_pass(g)

	l := GUI.Widget_Get(g, left)
	r := GUI.Widget_Get(g, right)
	testing.expect_value(t, l.rect.x, 0.0)
	testing.expect_value(t, l.rect.w, 200.0)
	testing.expect_value(t, r.rect.x, 200.0)
	testing.expect_value(t, r.rect.w, 600.0)
	testing.expect_value(t, r.rect.h, 600.0)

	test_gui_destroy(g)
}

@(test)
test_split_layout_fixed_min_size :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{name = "split", split = .Horizontal})
	fixed := GUI.New_Widget(
		g,
		.Panel,
		split,
		GUI.Widget_Opts{name = "fixed", min_size = GUI.Vec2{120, 0}, fixed = true},
	)
	rest := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "rest", weight = 1})

	GUI.layout_pass(g)

	f := GUI.Widget_Get(g, fixed)
	r := GUI.Widget_Get(g, rest)
	testing.expect_value(t, f.rect.w, 120.0)
	testing.expect_value(t, r.rect.x, 120.0)
	testing.expect_value(t, r.rect.w, 680.0)

	test_gui_destroy(g)
}

@(test)
test_hit_test_picks_topmost :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	button := GUI.New_Widget(
	g,
	.Button,
	panel,
	GUI.Widget_Opts {
		name    = "button",
		preset  = .Top_Left,
		offsets = GUI.Offset{0, 0, 50, 50},
	},
	)
	GUI.layout_pass(g)

	hit := GUI.hit_test(g, g.root, GUI.Vec2{10, 10})
	testing.expect_value(t, hit, button)

	hit = GUI.hit_test(g, g.root, GUI.Vec2{200, 200})
	testing.expect_value(t, hit, panel)

	hit = GUI.hit_test(g, g.root, GUI.Vec2{900, 900})
	testing.expect_value(t, hit, GUI.INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_hidden_widgets_are_not_hit :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	button := GUI.New_Widget(g, .Button, panel, GUI.Widget_Opts{name = "button"})
	GUI.layout_pass(g)

	GUI.Widget_Get(g, button).state -= GUI.Widget_State{.Visible}
	hit := GUI.hit_test(g, g.root, GUI.Vec2{10, 10})
	testing.expect_value(t, hit, panel)

	test_gui_destroy(g)
}

@(test)
test_attach_detach_keeps_identity :: proc(t: ^testing.T) {
	g := test_gui(t)

	a := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "a"})
	b := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "b"})
	child := GUI.New_Widget(g, .Panel, a, GUI.Widget_Opts{name = "child"})

	testing.expect_value(t, GUI.Widget_Child_Count(g, a), 1)
	testing.expect_value(t, GUI.Widget_Child_Count(g, b), 0)

	GUI.Widget_Attach(g, b, child)
	testing.expect_value(t, GUI.Widget_Child_Count(g, a), 0)
	testing.expect_value(t, GUI.Widget_Child_Count(g, b), 1)

	w := GUI.Widget_Get(g, child)
	testing.expect_value(t, w.parent, b)
	testing.expect_value(t, w.id, child)

	test_gui_destroy(g)
}

@(test)
test_the_drag_overlay_is_not_clipped_away :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, true)

	GUI.build_draw_list(g)

	testing.expect_value(t, len(g.draw.commands) > 0, true)
	for v in g.draw.vertices {
		testing.expect_value(t, v.pos[0] >= g.viewport.x - 0.5, true)
		testing.expect_value(t, v.pos[1] >= g.viewport.y - 0.5, true)
		testing.expect_value(t, v.pos[0] <= g.viewport.x + g.viewport.w + 0.5, true)
		testing.expect_value(t, v.pos[1] <= g.viewport.y + g.viewport.h + 0.5, true)
	}

	test_gui_destroy(g)
}

@(test)
test_a_panel_dropped_outside_the_window_floats :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({-80, -60}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({-80, -60}))
	GUI.Handle_Events(g)

	testing.expect_value(t, len(g.floats), 1)
	testing.expect_value(t, g.floats[0].widget, panel)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, GUI.INVALID_WIDGET_ID)
	testing.expect_value(t, g.floats[0].pos.x, -84.0)
	testing.expect_value(t, g.floats[0].pos.y, -64.0)
	testing.expect_value(t, g.floats[0].size.x, GUI.Widget_Get(g, panel).rect.w)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_follows_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	index := GUI.Make_Float_Panel(g, panel, GUI.Vec2{300, 200}, GUI.Vec2{320, 240})
	testing.expect_value(t, index, 0)
	GUI.layout_pass(g)

	append(&g.events, mouse_down_float({304, 204}, {4, 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move_float({404, 304}, {104, 104}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, true)
	testing.expect_value(t, g.drag.float_index, 0)
	testing.expect_value(t, g.floats[0].pos.x, 400.0)
	testing.expect_value(t, g.floats[0].pos.y, 300.0)

	append(&g.events, mouse_up_float({404, 304}, {104, 104}))
	GUI.Handle_Events(g)
	testing.expect_value(t, len(g.floats), 1)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_can_be_docked_again :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	container := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "container", draggable = true})
	target := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "target", draggable = true})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Make_Float_Panel(g, panel, GUI.Vec2{1000, 100}, GUI.Vec2{320, 240})
	GUI.layout_pass(g)

	append(&g.events, mouse_down_float({1004, 104}, {4, 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move_float({600, 300}, {-400, 200}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.plan.kind, .Tabs)

	append(&g.events, mouse_up_float({600, 300}, {-400, 200}))
	GUI.Handle_Events(g)

	testing.expect_value(t, len(g.floats), 0)
	host := GUI.Widget_Get(g, target).parent
	testing.expect_value(t, GUI.Widget_Get(g, host).type, .Tabs)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, host)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dropped_into_an_empty_split_fills_it :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	plan := GUI.dock_plan(g, panel, split, .Left, false, GUI.Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Fill)
	testing.expect_value(t, plan.preview.w, 800.0)
	testing.expect_value(t, plan.preview.h, 600.0)

	GUI.dock_apply(g, panel, plan)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Child_Count(g, split), 1)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, split)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 800.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.h, 600.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_takes_the_empty_space_of_a_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "host"})
	GUI.New_Widget(
		g,
		.Panel,
		host,
		GUI.Widget_Opts{name = "child", preset = .Top_Left, offsets = GUI.Offset{0, 0, 100, 100}},
	)
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	plan := GUI.dock_plan(g, panel, host, .Center, false, GUI.Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Fill)
	testing.expect_value(t, plan.preview.x, 0.0)
	testing.expect_value(t, plan.preview.y, 100.0)
	testing.expect_value(t, plan.preview.w, 800.0)
	testing.expect_value(t, plan.preview.h, 500.0)

	GUI.dock_apply(g, panel, plan)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, host)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.x, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.y, 100.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 800.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.h, 500.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_too_big_for_the_empty_space_does_not_fit :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "host"})
	GUI.New_Widget(
		g,
		.Panel,
		host,
		GUI.Widget_Opts{name = "child", preset = .Top_Left, offsets = GUI.Offset{0, 0, 700, 500}},
	)
	panel := GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts{name = "panel", draggable = true, min_size = GUI.Vec2{400, 400}},
	)
	GUI.layout_pass(g)

	plan := GUI.dock_plan(g, panel, host, .Center, false, GUI.Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Tabs)

	test_gui_destroy(g)
}

@(test)
test_draw_list_batches_by_texture :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_quad(&dl, GUI.Rect{0, 0, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(0))
	GUI.draw_quad(&dl, GUI.Rect{10, 0, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(0))
	GUI.draw_quad(&dl, GUI.Rect{20, 0, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(0))

	testing.expect_value(t, len(dl.commands), 1)
	testing.expect_value(t, dl.commands[0].idx_count, 18)
	testing.expect_value(t, len(dl.vertices), 12)
	testing.expect_value(t, len(dl.indices), 18)

	GUI.draw_push_clip(&dl, GUI.Rect{0, 0, 5, 5})
	GUI.draw_quad(&dl, GUI.Rect{0, 0, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(0))
	testing.expect_value(t, len(dl.commands), 1)

	GUI.draw_pop_clip(&dl)
	GUI.draw_quad(&dl, GUI.Rect{30, 0, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(1))
	testing.expect_value(t, len(dl.commands), 2)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_draw_list_clip_is_intersected :: proc(t: ^testing.T) {
	dl: GUI.Draw_List
	GUI.draw_list_clear(&dl, GUI.Rect{x = 0, y = 0, w = 100, h = 100})

	GUI.draw_push_clip(&dl, GUI.Rect{x = 0, y = 0, w = 50, h = 50})
	GUI.draw_push_clip(&dl, GUI.Rect{x = 25, y = 25, w = 100, h = 100})
	GUI.draw_quad(&dl, GUI.Rect{0, 0, 10, 10}, {0, 0, 1, 1}, GUI.Colour{1, 1, 1, 1}, GUI.Texture_ID(0))

	testing.expect_value(t, len(dl.vertices), 0)
	testing.expect_value(t, len(dl.commands), 0)

	GUI.draw_list_destroy(&dl)
}

@(test)
test_build_draw_list_emits_commands :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(
		g,
		.Panel,
		g.root,
		GUI.Widget_Opts {
			name = "panel",
			style = GUI.Style {
				box = GUI.StyleBox {
					bg_color = GUI.RGBA(1, 1, 1, 1),
					border_color = {
						GUI.RGBA(1, 1, 1, 1),
						GUI.RGBA(1, 1, 1, 1),
						GUI.RGBA(1, 1, 1, 1),
						GUI.RGBA(1, 1, 1, 1),
					},
					border_width = {2, 2, 2, 2},
				},
			},
		},
	)

	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	testing.expect_value(t, len(g.draw.commands), 1)
	testing.expect_value(t, g.draw.commands[0].idx_count, 30)

	test_gui_destroy(g)
}

test_clicks: int = 0

on_test_click :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	test_clicks += 1
}

@(test)
test_button_click_invokes_handler :: proc(t: ^testing.T) {
	g := test_gui(t)
	test_clicks = 0

	button := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts{name = "button", text = "press", on_click = on_test_click},
	)
	GUI.layout_pass(g)

	point := centre_of(GUI.Widget_Get(g, button))
	append(&g.events, mouse_down(point))
	append(&g.events, mouse_up(point))
	GUI.Handle_Events(g)

	testing.expect_value(t, test_clicks, 1)

	test_gui_destroy(g)
}

@(test)
test_click_outside_does_not_fire :: proc(t: ^testing.T) {
	g := test_gui(t)
	test_clicks = 0

	button := GUI.New_Widget(
	g,
	.Button,
	g.root,
	GUI.Widget_Opts {
		name     = "button",
		text     = "press",
		on_click = on_test_click,
		preset   = .Top_Left,
		offsets  = GUI.Offset{0, 0, 50, 50},
	},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({5, 5}))
	append(&g.events, mouse_up({700, 500}))
	GUI.Handle_Events(g)

	testing.expect_value(t, test_clicks, 0)

	test_gui_destroy(g)
}

@(test)
test_visibility_toggle :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel"})
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, panel).state, true)

	GUI.Widget_Get(g, panel).state -= GUI.Widget_State{.Visible}
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, panel).state, false)

	GUI.Widget_Get(g, panel).state += GUI.Widget_State{.Visible}
	testing.expect_value(t, .Visible in GUI.Widget_Get(g, panel).state, true)

	test_gui_destroy(g)
}

make_gallery_scene :: proc(g: ^GUI.GUI) -> (toolbar, side, status, target: GUI.Widget_ID) {
	main_split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	toolbar = GUI.New_Widget(g, .VBox, main_split, GUI.Widget_Opts{min_size = GUI.Vec2{220, 0}, fixed = true})
	side = GUI.New_Widget(g, .Split, main_split, GUI.Widget_Opts{split = .Vertical})
	status = GUI.New_Widget(
		g,
		.Panel,
		side,
		GUI.Widget_Opts{weight = 1, style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.1, 0.1, 0.2, 1)}}},
	)
	target = GUI.New_Widget(
		g,
		.Panel,
		side,
		GUI.Widget_Opts{weight = 1, style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.2, 0.1, 0.1, 1)}}},
	)
	return
}

@(test)
test_a_split_gives_the_fixed_child_its_own_size :: proc(t: ^testing.T) {
	g := test_gui(t)
	toolbar, side, status, target := make_gallery_scene(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, toolbar).rect.w, 220.0)
	testing.expect_value(t, GUI.Widget_Get(g, toolbar).rect.h, 600.0)

	testing.expect_value(t, GUI.Widget_Get(g, side).rect.x, 220.0)
	testing.expect_value(t, GUI.Widget_Get(g, side).rect.w, 580.0)

	testing.expect_value(t, GUI.Widget_Get(g, status).rect.h, 300.0)
	testing.expect_value(t, GUI.Widget_Get(g, target).rect.y, 300.0)
	testing.expect_value(t, GUI.Widget_Get(g, target).rect.h, 300.0)

	test_gui_destroy(g)
}

@(test)
test_a_scene_draws :: proc(t: ^testing.T) {
	g := test_gui(t)
	make_gallery_scene(g)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	testing.expect_value(t, len(g.draw.commands) > 0, true)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

@(test)
test_vbox_stacks_children :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 10})
	a := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{min_size = GUI.Vec2{0, 50}, fixed = true})
	b := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{min_size = GUI.Vec2{0, 30}, fixed = true})

	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, a).rect.y, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, a).rect.h, 50.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.y, 60.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.h, 30.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.w, 800.0)

	test_gui_destroy(g)
}

@(test)
test_hbox_lays_out_side_by_side :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .HBox, g.root, GUI.Widget_Opts{separation = 8})
	a := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{min_size = GUI.Vec2{100, 0}, fixed = true})
	b := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{min_size = GUI.Vec2{40, 0}, fixed = true})

	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, a).rect.x, 0.0)
	testing.expect_value(t, GUI.Widget_Get(g, a).rect.w, 100.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.x, 108.0)
	testing.expect_value(t, GUI.Widget_Get(g, b).rect.w, 40.0)

	test_gui_destroy(g)
}

@(test)
test_drag_moves_a_panel_into_a_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	container := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "container", draggable = true})
	target := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "target", draggable = true})

	panel := GUI.New_Widget(
		g,
		.Panel,
		container,
		GUI.Widget_Opts{name = "panel", draggable = true, min_size = GUI.Vec2{100, 60}},
	)
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.armed, true)
	testing.expect_value(t, g.drag.active, false)

	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, true)
	testing.expect_value(t, g.drag.widget, panel)

	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 0.0)

	append(&g.events, mouse_move({600, 300}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.target, target)
	testing.expect_value(t, g.drag.zone, .Center)
	testing.expect_value(t, g.drag.plan.kind, .Tabs)

	append(&g.events, mouse_up({600, 300}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, false)

	host := GUI.Widget_Get(g, target).parent
	testing.expect_value(t, GUI.Widget_Get(g, host).type, .Tabs)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, host)
	testing.expect_value(t, GUI.Widget_Child_Count(g, host), 2)

	test_gui_destroy(g)
}

@(test)
test_a_press_on_a_title_bar_is_not_a_drag :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.drag.active, false)
	testing.expect_value(t, g.drag.armed, false)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, g.root)

	test_gui_destroy(g)
}

@(test)
test_escape_cancels_a_drag :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, true)

	append(&g.events, GUI.Key_Down_Event{key = .Escape})
	GUI.Handle_Events(g)
	testing.expect_value(t, g.drag.active, false)
	testing.expect_value(t, g.quit_requested, false)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dropped_on_a_tab_host_becomes_one_of_its_tabs :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	host := GUI.New_Widget(g, .Tabs, split, GUI.Widget_Opts{name = "host"})
	GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "first", draggable = true})
	GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "second", draggable = true})
	panel := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	content := GUI.tabs_content_rect(GUI.Widget_Get(g, host))
	append(&g.events, mouse_move({content.x + content.w * 0.5, content.y + content.h * 0.5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.drag.target, host)
	testing.expect_value(t, g.drag.tab_host, host)
	testing.expect_value(t, g.drag.plan.kind, .Tabs)

	append(&g.events, mouse_up({content.x + content.w * 0.5, content.y + content.h * 0.5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Child_Count(g, host), 3)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, host)
	testing.expect_value(t, GUI.Widget_Get(g, host).type, .Tabs)
	testing.expect_value(t, GUI.tabs_active(GUI.Widget_Get(g, host)), 2)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dropped_on_the_strip_of_a_tab_host_becomes_a_tab :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	host := GUI.New_Widget(g, .Tabs, split, GUI.Widget_Opts{name = "host"})
	GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "first", draggable = true})
	panel := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	bar := GUI.tab_bar_rect(GUI.Widget_Get(g, host))
	append(&g.events, mouse_move({bar.x + bar.w * 0.5, bar.y + bar.h * 0.5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.drag.plan.kind, .Tabs)

	append(&g.events, mouse_up({bar.x + bar.w * 0.5, bar.y + bar.h * 0.5}))
	GUI.Handle_Events(g)

	testing.expect_value(t, GUI.Widget_Child_Count(g, host), 2)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, host)
	testing.expect_value(t, GUI.tabs_active(GUI.Widget_Get(g, host)), 1)

	test_gui_destroy(g)
}

@(test)
test_dock_splits_a_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "container", draggable = true})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})

	GUI.Dock(g, panel, container, .Right)

	split := GUI.Widget_Get(g, container).parent
	s := GUI.Widget_Get(g, split)
	testing.expect_value(t, s.type, .Split)
	testing.expect_value(t, GUI.Widget_Child_Count(g, split), 2)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, split)
	testing.expect_value(t, GUI.Widget_Index_Of(g, split, panel), 1)
	testing.expect_value(t, GUI.Widget_Index_Of(g, split, container), 0)

	#partial switch d in s.data {
	case GUI.Split_Data:
		testing.expect_value(t, d.direction, .Horizontal)
	}

	test_gui_destroy(g)
}

@(test)
test_dock_keeps_the_layout_of_the_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{name = "box", separation = 8})
	first := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "first", min_size = GUI.Vec2{0, 50}})
	second := GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "second", min_size = GUI.Vec2{0, 50}})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Dock(g, panel, box, .Right)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, box).type, .VBox)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.x, GUI.Widget_Get(g, second).rect.x)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.y < GUI.Widget_Get(g, second).rect.y, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.h, GUI.Widget_Get(g, second).rect.h)

	test_gui_destroy(g)
}

@(test)
test_dock_preview_matches_the_result :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "container", draggable = true})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	plan := GUI.dock_plan(g, panel, container, .Right, false, GUI.Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Split)
	testing.expect_value(t, plan.preview.x, 400.0)
	testing.expect_value(t, plan.preview.w, 400.0)

	GUI.dock_apply(g, panel, plan)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.x, plan.preview.x)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.y, plan.preview.y)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, plan.preview.w)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.h, plan.preview.h)

	test_gui_destroy(g)
}

@(test)
test_dock_makes_a_tab_host :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "container", draggable = true})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Dock(g, panel, container, .Center)

	host := GUI.Widget_Get(g, container).parent
	testing.expect_value(t, GUI.Widget_Get(g, host).type, .Tabs)
	testing.expect_value(t, GUI.Widget_Child_Count(g, host), 2)
	testing.expect_value(t, GUI.Widget_Get(g, panel).parent, host)
	testing.expect_value(t, GUI.tabs_active(GUI.Widget_Get(g, host)), 1)

	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.h, 600.0 - GUI.TAB_BAR_HEIGHT)
	testing.expect_value(t, GUI.Widget_Get(g, container).rect.w, 0.0)

	test_gui_destroy(g)
}

@(test)
test_a_tab_button_switches_tabs :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "container", draggable = true})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Dock(g, panel, container, .Center)
	GUI.layout_pass(g)

	host := GUI.Widget_Get(g, container).parent
	w := GUI.Widget_Get(g, host)

	rects: [GUI.MAX_TABS]GUI.Rect
	n := GUI.tab_button_rects(g, w, &rects)
	testing.expect_value(t, n, 2)

	append(&g.events, mouse_down({rects[0].x + 2, rects[0].y + 2}))
	GUI.Handle_Events(g)
	testing.expect_value(t, GUI.tabs_active(w), 0)

	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, container).rect.w, 800.0)

	test_gui_destroy(g)
}

@(test)
test_dock_swaps_two_panels :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Vertical})
	a := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "a", draggable = true})
	b := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "b", draggable = true})
	GUI.layout_pass(g)

	plan := GUI.dock_with(g, a, b, .Center, true)
	testing.expect_value(t, plan.kind, .Swap)

	testing.expect_value(t, GUI.Widget_Get(g, a).parent, split)
	testing.expect_value(t, GUI.Widget_Get(g, b).parent, split)
	testing.expect_value(t, GUI.Widget_Index_Of(g, split, a), 1)
	testing.expect_value(t, GUI.Widget_Index_Of(g, split, b), 0)

	test_gui_destroy(g)
}

@(test)
test_dock_zone_edges :: proc(t: ^testing.T) {
	container := GUI.Rect {
		x = 0,
		y = 0,
		w = 200,
		h = 200,
	}

	testing.expect_value(t, GUI.dock_zone(container, GUI.Vec2{100, 100}), .Center)
	testing.expect_value(t, GUI.dock_zone(container, GUI.Vec2{2, 100}), .Left)
	testing.expect_value(t, GUI.dock_zone(container, GUI.Vec2{198, 100}), .Right)
	testing.expect_value(t, GUI.dock_zone(container, GUI.Vec2{100, 2}), .Top)
	testing.expect_value(t, GUI.dock_zone(container, GUI.Vec2{100, 198}), .Bottom)
	testing.expect_value(t, GUI.dock_zone(container, GUI.Vec2{400, 400}), .None)
}

@(test)
test_dock_into_a_split_makes_another_slice :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{name = "split", split = .Horizontal})
	GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "a"})
	GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "b"})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	plan := GUI.dock_plan(g, panel, split, .Left, false, GUI.Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Split)
	testing.expect_value(t, plan.create_split, false)
	testing.expect_value(t, plan.count, 3)
	testing.expect_value(t, plan.other_count, 2)
	testing.expect_value(t, plan.preview.x, 0.0)

	GUI.dock_apply(g, panel, plan)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Child_Count(g, split), 3)
	testing.expect_value(t, GUI.Widget_Index_Of(g, split, panel), 0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, plan.preview.w)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.x, plan.preview.x)

	test_gui_destroy(g)
}

@(test)
test_dock_keeps_the_shape_of_a_split :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{name = "split", split = .Vertical})
	first := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "first"})
	second := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "second"})
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Dock(g, panel, split, .Left)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, split).type, .Split)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.y < GUI.Widget_Get(g, second).rect.y, true)
	testing.expect_value(t, GUI.Widget_Get(g, first).rect.x, GUI.Widget_Get(g, second).rect.x)

	test_gui_destroy(g)
}

field_text :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> string {
	w := GUI.Widget_Get(g, id)
	if w == nil {return ""}
	#partial switch d in w.data {
	case GUI.Text_Box_Data:
		return d.text
	}
	return ""
}

@(test)
test_text_input_editing :: proc(t: ^testing.T) {
	g := test_gui(t)

	field := GUI.New_Widget(g, .TextBox, g.root, GUI.Widget_Opts{text = "abc"})
	GUI.text_input_set_caret(g, field, 3, false)

	GUI.fire_text(g, field, "d")
	testing.expect_value(t, field_text(g, field), "abcd")

	GUI.text_input_backspace(g, field)
	testing.expect_value(t, field_text(g, field), "abc")

	GUI.text_input_move_caret(g, field, false, false)
	GUI.text_input_move_caret(g, field, false, false)
	GUI.fire_text(g, field, "X")
	testing.expect_value(t, field_text(g, field), "aXbc")

	GUI.text_input_set_caret(g, field, 0, false)
	GUI.text_input_set_caret(g, field, 3, true)
	GUI.fire_text(g, field, "-")
	testing.expect_value(t, field_text(g, field), "-c")

	test_gui_destroy(g)
}

@(test)
test_text_input_focus_and_caret :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.New_Widget(g, .TextBox, g.root, GUI.Widget_Opts{text = "hello"})
	GUI.layout_pass(g)

	GUI.focus_click(g, field, GUI.Vec2{20, 10})
	testing.expect_value(t, g.focused, field)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.caret > 0 && d.caret < 5, true)
	}

	test_gui_destroy(g)
}

@(test)
test_double_click_selects_the_word_and_then_the_text :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.New_Widget(g, .TextBox, g.root, GUI.Widget_Opts{text = "hello world"})
	GUI.layout_pass(g)

	GUI.focus_click(g, field, GUI.Vec2{20, 10}, 2)
	testing.expect_value(t, g.focused, field)

	//* The word under the pointer is taken.
	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, 5)
		testing.expect_value(t, d.caret, 5)
	}

	//* The second double click on the same word takes all of the text.
	GUI.focus_click(g, field, GUI.Vec2{20, 10}, 1)
	GUI.focus_click(g, field, GUI.Vec2{20, 10}, 2)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, len(d.text))
		testing.expect_value(t, d.caret, len(d.text))
	}

	GUI.fire_text(g, field, "x")
	testing.expect_value(t, field_text(g, field), "x")

	test_gui_destroy(g)
}

@(test)
test_click_away_removes_the_caret :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	other := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts{name = "other", preset = .Top_Left, offsets = GUI.Offset{16, 100, 300, 140}},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({30, 30}, 1))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, field)

	append(&g.events, mouse_down({30, 120}, 1))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused != field, true)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, d.caret)
		testing.expect_value(t, d.sel_end, d.caret)
	}

	append(&g.events, mouse_down({30, 30}, 1))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused, field)

	test_gui_destroy(g)
}

@(test)
test_click_away_clears_the_selection :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "hello world", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	other := GUI.New_Widget(
		g,
		.Button,
		g.root,
		GUI.Widget_Opts{name = "other", preset = .Top_Left, offsets = GUI.Offset{16, 100, 300, 140}},
	)
	GUI.layout_pass(g)

	append(&g.events, mouse_down({30, 30}, 3))
	GUI.Handle_Events(g)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, len(d.text))
	}

	append(&g.events, mouse_down({30, 120}, 1))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.focused != field, true)

	#partial switch d in GUI.Widget_Get(g, field).data {
	case GUI.Text_Box_Data:
		testing.expect_value(t, d.sel_start, d.caret)
		testing.expect_value(t, d.sel_end, d.caret)
	}

	testing.expect_value(t, GUI.text_input_selection_rect(g, field, GUI.Rect{0, 0, 100, 20}).w, 0.0)

	test_gui_destroy(g)
}

@(test)
test_text_input_full_frame_loop :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := GUI.New_Widget(
		g,
		.TextBox,
		g.root,
		GUI.Widget_Opts{text = "type here", preset = .Top_Left, offsets = GUI.Offset{16, 16, 300, 48}},
	)
	GUI.Frame(g)

	GUI.focus_click(g, field, GUI.Vec2{30, 30})
	GUI.Frame(g)

	GUI.text_input_set_caret(g, field, len("type here"), false)

	for i in 0 ..< 5 {
		GUI.fire_text(g, field, "x")
		GUI.Frame(g)
	}
	testing.expect_value(t, field_text(g, field), "type herexxxxx")

	GUI.text_input_backspace(g, field)
	GUI.Frame(g)
	testing.expect_value(t, field_text(g, field), "type herexxxx")

	GUI.text_input_select_all(g, field)
	GUI.Frame(g)
	GUI.fire_text(g, field, "done")
	GUI.Frame(g)
	testing.expect_value(t, field_text(g, field), "done")

	test_gui_destroy(g)
}

@(test)
test_font_sizes_share_one_file :: proc(t: ^testing.T) {
	g := test_gui(t)

	a := GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	b := GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 32)
	testing.expect_value(t, a != GUI.INVALID_FONT_ID, true)
	testing.expect_value(t, b != GUI.INVALID_FONT_ID, true)
	testing.expect_value(t, a != b, true)

	testing.expect_value(t, len(g.font_files), 1)
	testing.expect_value(t, len(g.fonts), 2)
	testing.expect_value(t, GUI.font_get(g, a).file == GUI.font_get(g, b).file, true)

	c := GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	testing.expect_value(t, c, a)

	test_gui_destroy(g)
}

@(test)
test_a_panel_is_resized_by_pulling_on_its_edge :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	left := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "left", draggable = true})
	right := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "right", draggable = true})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, left).rect.w, 400.0)
	testing.expect_value(t, GUI.Widget_Get(g, right).rect.w, 400.0)

	append(&g.events, mouse_down({398, 100}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({448, 100}))
	GUI.Handle_Events(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, left).rect.w, 450.0)
	testing.expect_value(t, GUI.Widget_Get(g, right).rect.x, 450.0)
	testing.expect_value(t, GUI.Widget_Get(g, right).rect.w, 350.0)

	GUI.layout_pass(g)
	testing.expect_value(t, GUI.Widget_Get(g, left).rect.w, 450.0)
	testing.expect_value(t, GUI.Widget_Get(g, right).rect.w, 350.0)

	append(&g.events, mouse_up({448, 100}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, false)

	test_gui_destroy(g)
}

@(test)
test_a_panel_is_resized_by_pulling_on_its_corner :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Vertical})
	top := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "top", draggable = true})
	bottom := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "bottom", draggable = true})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, top).rect.h, 300.0)
	testing.expect_value(t, GUI.Widget_Get(g, bottom).rect.y, 300.0)

	append(&g.events, mouse_down({798, 298}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({778, 278}))
	GUI.Handle_Events(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, top).rect.w, 780.0)
	testing.expect_value(t, GUI.Widget_Get(g, top).rect.h, 280.0)
	testing.expect_value(t, GUI.Widget_Get(g, bottom).rect.y, 280.0)
	testing.expect_value(t, GUI.Widget_Get(g, bottom).rect.h, 320.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_cannot_be_pulled_below_its_minimum :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{split = .Horizontal})
	left := GUI.New_Widget(
		g,
		.Panel,
		split,
		GUI.Widget_Opts{name = "left", draggable = true, min_size = GUI.Vec2{200, 0}},
	)
	right := GUI.New_Widget(g, .Panel, split, GUI.Widget_Opts{name = "right", draggable = true})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, left).rect.w, 500.0)
	testing.expect_value(t, GUI.Widget_Get(g, right).rect.w, 300.0)

	append(&g.events, mouse_down({498, 100}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({50, 100}))
	GUI.Handle_Events(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, left).rect.w, 200.0)
	testing.expect_value(t, GUI.Widget_Get(g, right).rect.w, 600.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_in_a_panel_is_resized_by_its_offsets :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "host"})
	panel := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 800.0)

	append(&g.events, mouse_down({798, 100}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({698, 100}))
	GUI.Handle_Events(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 700.0)
	testing.expect_value(t, GUI.Widget_Get(g, host).rect.w, 800.0)

	test_gui_destroy(g)
}

@(test)
test_the_title_bar_of_a_panel_is_not_a_grip :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	append(&g.events, mouse_down({10, 10}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, false)
	testing.expect_value(t, g.drag.armed, true)

	append(&g.events, mouse_up({10, 10}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down({2, 100}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	testing.expect_value(t, g.drag.armed, false)

	test_gui_destroy(g)
}

@(test)
test_a_panel_in_a_tab_host_is_resized_through_its_host :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Tabs, g.root, GUI.Widget_Opts{name = "host"})
	panel := GUI.New_Widget(g, .Panel, host, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 800.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.h, 576.0)

	append(&g.events, mouse_down({798, 300}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({698, 300}))
	GUI.Handle_Events(g)
	GUI.layout_pass(g)

	testing.expect_value(t, GUI.Widget_Get(g, host).rect.w, 700.0)
	testing.expect_value(t, GUI.Widget_Get(g, panel).rect.w, 700.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dragged_out_of_the_window_can_be_resized :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	header := GUI.header_rect(GUI.Widget_Get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move({900, 700}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_up({900, 700}))
	GUI.Handle_Events(g)

	testing.expect_value(t, len(g.floats), 1)
	GUI.layout_pass(g)

	f := g.floats[0]
	append(
		&g.events,
		mouse_down_float({f.pos.x + f.size.x - 2, f.pos.y + 100}, {f.size.x - 2, 100}),
	)
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	append(
		&g.events,
		mouse_move_float({f.pos.x + f.size.x + 38, f.pos.y + 100}, {f.size.x + 38, 100}),
	)
	GUI.Handle_Events(g)

	testing.expect_value(t, g.floats[0].size.x, f.size.x + 40)

	test_gui_destroy(g)
}

@(test)
test_the_free_space_of_a_container_is_never_cut_too_far :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "host", draggable = true})
	for i in 0 ..< 6 {
		GUI.New_Widget(
			g,
			.Panel,
			host,
			GUI.Widget_Opts {
				name = "child",
				preset = .Top_Left,
				offsets = GUI.Offset{0, f32(i) * 20, 100, f32(i) * 20 + 10},
			},
		)
	}
	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	space, count := GUI.container_free_space(g, host)
	testing.expect_value(t, count > 0, true)
	testing.expect_value(t, space[0].w > 0, true)

	child := GUI.Widget_Get(g, host).first_child
	for child != GUI.INVALID_WIDGET_ID {
		c := GUI.Widget_Get(g, child)
		if c == nil {break}
		for i in 0 ..< count {
			overlap_x :=
				min(space[i].x + space[i].w, c.rect.x + c.rect.w) - max(space[i].x, c.rect.x)
			overlap_y :=
				min(space[i].y + space[i].h, c.rect.y + c.rect.h) - max(space[i].y, c.rect.y)
			testing.expect_value(t, overlap_x > 0 && overlap_y > 0, false)
		}
		child = c.next_sibling
	}

	plan := GUI.dock_plan(g, panel, host, .Center, false, GUI.Vec2{400, 300})
	testing.expect_value(t, plan.kind != .None, true)

	test_gui_destroy(g)
}

@(test)
test_the_grip_of_a_floating_panel_is_marked :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Make_Float_Panel(g, panel, GUI.Vec2{1000, 500}, GUI.Vec2{320, 240})
	GUI.layout_pass(g)

	g.global_pointer = GUI.Vec2{1000 + 320 - 2, 500 + 100}
	GUI.update_resize_hover(g)

	testing.expect_value(t, g.resize_hover, panel)
	testing.expect_value(t, g.cursor, .Resize_E)

	g.global_pointer = GUI.Vec2{1000 + 100, 500 + 100}
	GUI.update_resize_hover(g)
	testing.expect_value(t, g.resize_hover, GUI.INVALID_WIDGET_ID)
	testing.expect_value(t, g.cursor, .Default)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_is_resized_by_its_window :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{name = "panel", draggable = true})
	GUI.layout_pass(g)

	GUI.Make_Float_Panel(g, panel, GUI.Vec2{300, 200}, GUI.Vec2{320, 240})
	GUI.layout_pass(g)

	append(&g.events, mouse_down_float({618, 300}, {318, 100}))
	GUI.Handle_Events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move_float({658, 300}, {358, 100}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.floats[0].size.x, 360.0)
	testing.expect_value(t, g.floats[0].pos.x, 300.0)

	append(&g.events, mouse_up_float({658, 300}, {358, 100}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_down_float({302, 300}, {2, 100}))
	GUI.Handle_Events(g)
	append(&g.events, mouse_move_float({342, 300}, {42, 100}))
	GUI.Handle_Events(g)

	testing.expect_value(t, g.floats[0].size.x, 320.0)
	testing.expect_value(t, g.floats[0].pos.x, 340.0)

	test_gui_destroy(g)
}

@(test)
test_font_loads_and_measures :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	font := GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	testing.expect_value(t, font != GUI.INVALID_FONT_ID, true)
	testing.expect_value(t, g.default_font, font)

	size := GUI.Font_Measure(g, font, "Hello")
	testing.expect_value(t, size.x > 0, true)
	testing.expect_value(t, size.y > 0, true)

	longer := GUI.Font_Measure(g, font, "Hello world")
	testing.expect_value(t, longer.x > size.x, true)

	test_gui_destroy(g)
}

@(test)
test_text_draws_glyphs_and_uploads_atlas :: proc(t: ^testing.T) {
	g := test_gui(t)
	state := new(Mock_State)
	g.backend = mock_backend_with(state)

	font := GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	testing.expect_value(t, font != GUI.INVALID_FONT_ID, true)

	label := GUI.New_Widget(
		g,
		.Label,
		g.root,
		GUI.Widget_Opts {
			name = "label",
			text = "Hello",
			preset = .Top_Left,
			style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1)}},
		},
	)

	GUI.Frame(g)

	w := GUI.Widget_Get(g, label)
	testing.expect_value(t, w.min_size.x > 0, true)

	testing.expect_value(t, len(g.draw.vertices) > 4, true)

	testing.expect_value(t, state.uploads + state.region_uploads > 0, true)

	for cmd in g.draw.commands {
		testing.expect_value(t, cmd.texture, g.atlas_texture)
	}

	free(state)
	test_gui_destroy(g)
}

//* Tests for the life of the GUI: the making of it, the giving back of
//* it, the check of the backend and the version of the toolkit.

@(test)
test_the_checked_init_gives_the_gui_and_no_error :: proc(t: ^testing.T) {
	g, err := GUI.Init_GUI_Checked(640, 480, mock_backend)
	testing.expect_value(t, err.code, GUI.Error_Code.None)
	testing.expect_value(t, g != nil, true)
	testing.expect_value(t, g.viewport.w, 640.0)
	testing.expect_value(t, g.viewport.h, 480.0)
	GUI.Shutdown_GUI(g)
}

@(test)
test_the_gui_can_be_given_back_twice :: proc(t: ^testing.T) {
	g, err := GUI.Init_GUI_Checked(400, 300, mock_backend)
	testing.expect_value(t, err.code, GUI.Error_Code.None)
	GUI.Shutdown_GUI(g)
	GUI.Shutdown_GUI(g)
}

@(test)
test_the_backend_is_checked_for_what_it_needs :: proc(t: ^testing.T) {
	testing.expect_value(t, GUI.Backend_Validate(GUI.Backend{}), false)
	testing.expect_value(
		t,
		GUI.Backend_Validate(GUI.Backend{submit = mock_submit, upload_texture = mock_upload_texture}),
		true,
	)
}

@(test)
test_the_nil_safe_calls_of_the_backend_do_nothing :: proc(t: ^testing.T) {
	b := GUI.Backend{}
	testing.expect_value(t, GUI.Backend_Create(b, nil, 10, 10), false)
	testing.expect_value(t, GUI.Backend_Resize(b, 10, 10), false)
	testing.expect_value(t, GUI.Backend_Upload_Texture(b, GUI.ATLAS_TEXTURE_ID, nil, 1, 1), false)
	GUI.Backend_Destroy(b)
	GUI.Backend_Destroy_Texture(b, GUI.ATLAS_TEXTURE_ID)
	GUI.Backend_Submit(b, nil)
	GUI.Backend_Submit_Target(b, nil, nil)
}

@(test)
test_the_version_of_the_toolkit_is_there :: proc(t: ^testing.T) {
	testing.expect_value(t, GUI.Version(), GUI.CALCUI_VERSION)
	testing.expect_value(t, GUI.API_Version(), GUI.CALCUI_API_VERSION)
	testing.expect_value(t, GUI.Is_Compatible(GUI.CALCUI_API_VERSION), true)
	testing.expect_value(t, GUI.Is_Compatible(GUI.CALCUI_API_VERSION + 1), false)
}

//* Tests for the size of a widget: a widget with text takes the size of
//* that text, a widget without text fills the room it is given, and the
//* text of a widget never touches its border.

@(test)
test_a_widget_with_text_takes_the_size_of_its_text :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{Base_Opts = GUI.Base_Opts{name = "press"}, text = "press"},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, button)
	//* The button is as wide as its text and its padding, and it is
	//* not as wide as the window it is in.
	testing.expect_value(t, w.rect.w < g.viewport.w, true)
	testing.expect_value(t, w.rect.w >= GUI.Font_Measure(g, GUI.Font_Of(g, w), "press").x, true)
	testing.expect_value(t, w.rect.x, 0.0)

	test_gui_destroy(g)
}

@(test)
test_a_widget_without_text_fills_the_room_it_is_given :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	panel := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{
			name = "panel",
			offsets = GUI.Offset{left = 10, top = 10, right = -10, bottom = -10},
		}},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, panel)
	testing.expect_value(t, w.rect.x, 10.0)
	testing.expect_value(t, w.rect.y, 10.0)
	testing.expect_value(t, w.rect.w, g.viewport.w - 20.0)
	testing.expect_value(t, w.rect.h, g.viewport.h - 20.0)

	test_gui_destroy(g)
}

@(test)
test_the_text_of_a_widget_never_touches_its_border :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	label := GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{Base_Opts = GUI.Base_Opts{name = "label"}, text = "hello"},
	)
	GUI.layout_pass(g)

	w := GUI.Widget_Get(g, label)
	size := GUI.Font_Measure(g, GUI.Font_Of(g, w), "hello")
	testing.expect_value(t, w.min_size.x >= size.x + 1, true)
	testing.expect_value(t, w.min_size.y >= size.y + 1, true)

	test_gui_destroy(g)
}

@(test)
test_the_text_of_a_button_is_in_the_middle_of_it :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	button := GUI.Make_Button(g, g.root, GUI.Button_Opts{text = "ok"})
	GUI.layout_pass(g)

	//* The text of a button is in the middle of it, both ways.
	style := GUI.resolved_style(g, GUI.Widget_Get(g, button))
	testing.expect_value(t, style.text.align, GUI.Text_Align.Center)
	testing.expect_value(t, style.text.valign, GUI.V_Align.Center)

	test_gui_destroy(g)
}

@(test)
test_the_text_of_a_button_can_be_put_in_another_place :: proc(t: ^testing.T) {
	g := test_gui_with_font(t)

	button := GUI.Make_Button(
		g,
		g.root,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "button",
				style = GUI.Style {
					text = GUI.Text_Style {
						set = bit_set[GUI.Text_Field]{.Align},
						align = .Left,
					},
				},
			},
			text = "ok",
		},
	)
	GUI.layout_pass(g)

	//* A program that says where the text of its button goes is obeyed.
	style := GUI.resolved_style(g, GUI.Widget_Get(g, button))
	testing.expect_value(t, style.text.align, GUI.Text_Align.Left)
	testing.expect_value(t, style.text.valign, GUI.V_Align.Center)

	test_gui_destroy(g)
}
