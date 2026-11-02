//* Headless tests for the GUI core. Run with:
//*   odin test src/GUI
package GUI

import "core:testing"
import virt "core:mem/virtual"

//* A GUI with no backend, used to exercise the tree and the layout.
test_gui :: proc(t: ^testing.T) -> ^GUI {
	g := new(GUI)
	g^ = GUI{}
	if err := virt.arena_init_growing(&g.arena); err != nil {
		testing.fail_now(t, "arena init failed")
	}
	if err := virt.arena_init_growing(&g.frame_arena); err != nil {
		testing.fail_now(t, "frame arena init failed")
	}
	g.viewport = Rect{x = 0, y = 0, w = 800, h = 600}
	//* The main window sits at the top left of the screen in the tests.
	g.window_rect = g.viewport
	g.target = &g.draw
	g.next_texture = Texture_ID(1)
	g.font_instances = make(map[Font_Instance_Key]Font_ID)
	g.default_style = Style{
		text = Text_Style{
			colour = rgba(0.92, 0.94, 0.98, 1),
		},
	}
	init_text(g)
	g.root = widget(g, .Panel, INVALID_WIDGET_ID, Widget_Opts{name = "root"})
	return g
}

//* Mouse events in the main window. The window sits at the origin of
//* the screen in the tests, so the two positions are the same.
mouse_down :: proc(pos: Vec2, clicks := 1) -> Mouse_Down_Event {
	return Mouse_Down_Event{pos = pos, global = pos, button = .Left, clicks = clicks}
}

mouse_up :: proc(pos: Vec2) -> Mouse_Up_Event {
	return Mouse_Up_Event{pos = pos, global = pos, button = .Left}
}

mouse_move :: proc(pos: Vec2) -> Mouse_Move_Event {
	return Mouse_Move_Event{pos = pos, global = pos}
}

//* Mouse events in a floating panel: `pos` is in the panel's own
//* window, `global` is on the screen.
mouse_down_float :: proc(global, local: Vec2) -> Mouse_Down_Event {
	return Mouse_Down_Event{pos = local, global = global, button = .Left, clicks = 1}
}

mouse_move_float :: proc(global, local: Vec2) -> Mouse_Move_Event {
	return Mouse_Move_Event{pos = local, global = global}
}

mouse_up_float :: proc(global, local: Vec2) -> Mouse_Up_Event {
	return Mouse_Up_Event{pos = local, global = global, button = .Left}
}

//* Tears the test GUI down so the memory tracker stays quiet.
test_gui_destroy :: proc(g: ^GUI) {
	if g == nil { return }
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
	//* Every floating panel has a draw list of its own.
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

@(test)
test_resolve_rect_anchors :: proc(t: ^testing.T) {
	parent := Rect{x = 0, y = 0, w = 100, h = 50}

	//* Full rect.
	r := resolve_rect(parent, Anchor{0, 0, 1, 1}, Offset{0, 0, 0, 0}, Vec2{0, 0}, .Both, .Both)
	testing.expect_value(t, r.x, 0.0)
	testing.expect_value(t, r.y, 0.0)
	testing.expect_value(t, r.w, 100.0)
	testing.expect_value(t, r.h, 50.0)

	//* Half width, anchored left.
	r = resolve_rect(parent, Anchor{0, 0, 0.5, 1}, Offset{0, 0, 0, 0}, Vec2{0, 0}, .Both, .Both)
	testing.expect_value(t, r.w, 50.0)

	//* Offsets shrink the rect.
	r = resolve_rect(parent, Anchor{0, 0, 1, 1}, Offset{10, 20, -10, -20}, Vec2{0, 0}, .Both, .Both)
	testing.expect_value(t, r.x, 10.0)
	testing.expect_value(t, r.y, 20.0)
	testing.expect_value(t, r.w, 80.0)
	testing.expect_value(t, r.h, 10.0)
}

@(test)
test_resolve_rect_min_size_grows :: proc(t: ^testing.T) {
	parent := Rect{x = 0, y = 0, w = 100, h = 50}

	//* Too small for its minimum: grows to the right.
	r := resolve_rect(parent, Anchor{0, 0, 0, 0}, Offset{0, 0, 0, 0}, Vec2{40, 10}, .End, .End)
	testing.expect_value(t, r.x, 0.0)
	testing.expect_value(t, r.w, 40.0)
	testing.expect_value(t, r.h, 10.0)

	//* Grows to the left instead.
	r = resolve_rect(parent, Anchor{0, 0, 0, 0}, Offset{0, 0, 0, 0}, Vec2{40, 10}, .Begin, .Begin)
	testing.expect_value(t, r.x, -40.0)
	testing.expect_value(t, r.w, 40.0)
}

@(test)
test_split_layout_weights :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{name = "split", split = .Horizontal})
	left := widget(g, .Panel, split, Widget_Opts{name = "left", weight = 1})
	right := widget(g, .Panel, split, Widget_Opts{name = "right", weight = 3})

	layout_pass(g)

	l := widget_get(g, left)
	r := widget_get(g, right)
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

	split := widget(g, .Split, g.root, Widget_Opts{name = "split", split = .Horizontal})
	fixed := widget(g, .Panel, split, Widget_Opts{
		name = "fixed", min_size = Vec2{120, 0}, fixed = true,
	})
	rest := widget(g, .Panel, split, Widget_Opts{name = "rest", weight = 1})

	layout_pass(g)

	f := widget_get(g, fixed)
	r := widget_get(g, rest)
	testing.expect_value(t, f.rect.w, 120.0)
	testing.expect_value(t, r.rect.x, 120.0)
	testing.expect_value(t, r.rect.w, 680.0)

	test_gui_destroy(g)
}

@(test)
test_hit_test_picks_topmost :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel"})
	button := widget(g, .Button, panel, Widget_Opts{
		name = "button",
		//* A small button in the top-left corner.
		preset = .Top_Left,
		offsets = Offset{0, 0, 50, 50},
	})
	layout_pass(g)

	hit := hit_test(g, g.root, Vec2{10, 10})
	testing.expect_value(t, hit, button)

	//* Inside the panel but outside the button: the panel wins.
	hit = hit_test(g, g.root, Vec2{200, 200})
	testing.expect_value(t, hit, panel)

	//* Outside the viewport entirely: nothing is hit.
	hit = hit_test(g, g.root, Vec2{900, 900})
	testing.expect_value(t, hit, INVALID_WIDGET_ID)

	test_gui_destroy(g)
}

@(test)
test_hidden_widgets_are_not_hit :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel"})
	button := widget(g, .Button, panel, Widget_Opts{name = "button"})
	layout_pass(g)

	widget_get(g, button).state -= Widget_State{.Visible}
	hit := hit_test(g, g.root, Vec2{10, 10})
	testing.expect_value(t, hit, panel)

	test_gui_destroy(g)
}

@(test)
test_attach_detach_keeps_identity :: proc(t: ^testing.T) {
	g := test_gui(t)

	a := widget(g, .Panel, g.root, Widget_Opts{name = "a"})
	b := widget(g, .Panel, g.root, Widget_Opts{name = "b"})
	child := widget(g, .Panel, a, Widget_Opts{name = "child"})

	testing.expect_value(t, widget_child_count(g, a), 1)
	testing.expect_value(t, widget_child_count(g, b), 0)

	//* Move the child from a to b.
	widget_attach(g, b, child)
	testing.expect_value(t, widget_child_count(g, a), 0)
	testing.expect_value(t, widget_child_count(g, b), 1)

	w := widget_get(g, child)
	testing.expect_value(t, w.parent, b)
	testing.expect_value(t, w.id, child)

	test_gui_destroy(g)
}

@(test)
test_the_drag_overlay_is_not_clipped_away :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	header := header_rect(widget_get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	handle_events(g)
	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	handle_events(g)
	testing.expect_value(t, g.drag.active, true)

	build_draw_list(g)

	//* The overlay is drawn after the tree, so it is clipped to the
	//* viewport and not to nothing.
	last := g.draw.commands[len(g.draw.commands) - 1]
	testing.expect_value(t, last.clip.w, g.viewport.w)
	testing.expect_value(t, last.clip.h, g.viewport.h)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dropped_outside_the_window_floats :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	header := header_rect(widget_get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	handle_events(g)
	//* The pointer leaves the window.
	append(&g.events, mouse_move({-80, -60}))
	handle_events(g)
	append(&g.events, mouse_up({-80, -60}))
	handle_events(g)

	//* The panel left the tree and got a window of its own.
	testing.expect_value(t, len(g.floats), 1)
	testing.expect_value(t, g.floats[0].widget, panel)
	testing.expect_value(t, widget_get(g, panel).parent, INVALID_WIDGET_ID)
	//* The panel keeps the place the pointer had on its title bar.
	testing.expect_value(t, g.floats[0].pos.x, -84.0)
	testing.expect_value(t, g.floats[0].pos.y, -64.0)
	testing.expect_value(t, g.floats[0].size.x, widget_get(g, panel).rect.w)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_follows_the_pointer :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	index := float_panel(g, panel, Vec2{300, 200}, Vec2{320, 240})
	testing.expect_value(t, index, 0)
	layout_pass(g)

	//* Press on the title bar of the floating panel and move it.
	append(&g.events, mouse_down_float({304, 204}, {4, 4}))
	handle_events(g)
	append(&g.events, mouse_move_float({404, 304}, {104, 104}))
	handle_events(g)
	testing.expect_value(t, g.drag.active, true)
	testing.expect_value(t, g.drag.float_index, 0)
	testing.expect_value(t, g.floats[0].pos.x, 400.0)
	testing.expect_value(t, g.floats[0].pos.y, 300.0)

	append(&g.events, mouse_up_float({404, 304}, {104, 104}))
	handle_events(g)
	//* It is still a floating panel.
	testing.expect_value(t, len(g.floats), 1)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_can_be_docked_again :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Horizontal})
	container := widget(g, .Panel, split, Widget_Opts{name = "container", draggable = true})
	target := widget(g, .Panel, split, Widget_Opts{name = "target", draggable = true})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	float_panel(g, panel, Vec2{1000, 100}, Vec2{320, 240})
	layout_pass(g)

	//* Drag the floating panel over the middle of the target.
	append(&g.events, mouse_down_float({1004, 104}, {4, 4}))
	handle_events(g)
	append(&g.events, mouse_move_float({600, 300}, {-400, 200}))
	handle_events(g)
	testing.expect_value(t, g.drag.plan.kind, .Tabs)

	append(&g.events, mouse_up_float({600, 300}, {-400, 200}))
	handle_events(g)

	//* It is back in the tree, as a tab of the target.
	testing.expect_value(t, len(g.floats), 0)
	host := widget_get(g, target).parent
	testing.expect_value(t, widget_get(g, host).type, .Tabs)
	testing.expect_value(t, widget_get(g, panel).parent, host)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dropped_into_an_empty_split_fills_it :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Horizontal})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* The split is empty, so all of it is free space.
	plan := dock_plan(g, panel, split, .Left, false, Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Fill)
	testing.expect_value(t, plan.preview.w, 800.0)
	testing.expect_value(t, plan.preview.h, 600.0)

	dock_apply(g, panel, plan)
	layout_pass(g)

	//* The panel is the only child of the split, so it takes all of it.
	testing.expect_value(t, widget_child_count(g, split), 1)
	testing.expect_value(t, widget_get(g, panel).parent, split)
	testing.expect_value(t, widget_get(g, panel).rect.w, 800.0)
	testing.expect_value(t, widget_get(g, panel).rect.h, 600.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_takes_the_empty_space_of_a_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A panel with one small child in the corner: the rest of it is
	//* empty.
	host := widget(g, .Panel, g.root, Widget_Opts{name = "host"})
	widget(g, .Panel, host, Widget_Opts{
		name = "child",
		preset = .Top_Left,
		offsets = Offset{0, 0, 100, 100},
	})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	plan := dock_plan(g, panel, host, .Center, false, Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Fill)
	//* The largest piece of the empty space is below the child.
	testing.expect_value(t, plan.preview.x, 0.0)
	testing.expect_value(t, plan.preview.y, 100.0)
	testing.expect_value(t, plan.preview.w, 800.0)
	testing.expect_value(t, plan.preview.h, 500.0)

	dock_apply(g, panel, plan)
	layout_pass(g)

	//* The panel took the empty space.
	testing.expect_value(t, widget_get(g, panel).parent, host)
	testing.expect_value(t, widget_get(g, panel).rect.x, 0.0)
	testing.expect_value(t, widget_get(g, panel).rect.y, 100.0)
	testing.expect_value(t, widget_get(g, panel).rect.w, 800.0)
	testing.expect_value(t, widget_get(g, panel).rect.h, 500.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_too_big_for_the_empty_space_does_not_fit :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := widget(g, .Panel, g.root, Widget_Opts{name = "host"})
	widget(g, .Panel, host, Widget_Opts{
		name = "child",
		preset = .Top_Left,
		offsets = Offset{0, 0, 700, 500},
	})
	panel := widget(g, .Panel, g.root, Widget_Opts{
		name = "panel",
		draggable = true,
		min_size = Vec2{400, 400},
	})
	layout_pass(g)

	//* The free space is a strip on the right that is too narrow, so
	//* the panel does not take it and the drop falls back to a tab.
	plan := dock_plan(g, panel, host, .Center, false, Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Tabs)

	test_gui_destroy(g)
}

@(test)
test_draw_list_batches_by_texture_and_clip :: proc(t: ^testing.T) {
	dl: Draw_List
	draw_list_clear(&dl, Rect{x = 0, y = 0, w = 100, h = 100})

	//* Three quads, same texture, same clip: one command.
	draw_quad(&dl, Rect{0, 0, 10, 10}, {0, 0, 1, 1}, Colour{1, 1, 1, 1}, Texture_ID(0))
	draw_quad(&dl, Rect{10, 0, 10, 10}, {0, 0, 1, 1}, Colour{1, 1, 1, 1}, Texture_ID(0))
	draw_quad(&dl, Rect{20, 0, 10, 10}, {0, 0, 1, 1}, Colour{1, 1, 1, 1}, Texture_ID(0))

	testing.expect_value(t, len(dl.commands), 1)
	testing.expect_value(t, dl.commands[0].idx_count, 18)
	testing.expect_value(t, len(dl.vertices), 12)
	testing.expect_value(t, len(dl.indices), 18)

	//* A different clip starts a new command.
	draw_push_clip(&dl, Rect{0, 0, 5, 5})
	draw_quad(&dl, Rect{0, 0, 10, 10}, {0, 0, 1, 1}, Colour{1, 1, 1, 1}, Texture_ID(0))
	testing.expect_value(t, len(dl.commands), 2)

	//* A different texture starts a new command too.
	draw_pop_clip(&dl)
	draw_quad(&dl, Rect{30, 0, 10, 10}, {0, 0, 1, 1}, Colour{1, 1, 1, 1}, Texture_ID(1))
	testing.expect_value(t, len(dl.commands), 3)

	draw_list_destroy(&dl)
}

@(test)
test_draw_list_clip_is_intersected :: proc(t: ^testing.T) {
	dl: Draw_List
	draw_list_clear(&dl, Rect{x = 0, y = 0, w = 100, h = 100})

	draw_push_clip(&dl, Rect{x = 0, y = 0, w = 50, h = 50})
	draw_push_clip(&dl, Rect{x = 25, y = 25, w = 100, h = 100})
	draw_quad(&dl, Rect{0, 0, 10, 10}, {0, 0, 1, 1}, Colour{1, 1, 1, 1}, Texture_ID(0))

	testing.expect_value(t, dl.commands[0].clip.x, 25.0)
	testing.expect_value(t, dl.commands[0].clip.w, 25.0)

	draw_list_destroy(&dl)
}

@(test)
test_build_draw_list_emits_commands :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{
		name = "panel",
		style = Style{
			bg = rgba(1, 1, 1, 1),
			border = rgba(1, 1, 1, 1),
			border_width = 2,
		},
	})

	layout_pass(g)
	build_draw_list(g)

	//* One background quad plus four border quads, all batched into a
	//* single command because they share a texture and a clip.
	testing.expect_value(t, len(g.draw.commands), 1)
	testing.expect_value(t, g.draw.commands[0].idx_count, 30)

	test_gui_destroy(g)
}

//* Odin procedure literals do not capture enclosing variables, so test
//* state lives at package scope.
test_clicks: int = 0

on_test_click :: proc(g: ^GUI, id: Widget_ID) {
	test_clicks += 1
}

@(test)
test_button_click_invokes_handler :: proc(t: ^testing.T) {
	g := test_gui(t)
	test_clicks = 0

	button := widget(g, .Button, g.root, Widget_Opts{
		name = "button",
		text = "press",
		on_click = on_test_click,
	})
	layout_pass(g)

	//* Press and release over the button.
	append(&g.events, mouse_down({5, 5}))
	append(&g.events, mouse_up({5, 5}))
	handle_events(g)

	testing.expect_value(t, test_clicks, 1)

	test_gui_destroy(g)
}

@(test)
test_click_outside_does_not_fire :: proc(t: ^testing.T) {
	g := test_gui(t)
	test_clicks = 0

	button := widget(g, .Button, g.root, Widget_Opts{
		name = "button",
		text = "press",
		on_click = on_test_click,
		//* A small button in the top-left corner.
		preset = .Top_Left,
		offsets = Offset{0, 0, 50, 50},
	})
	layout_pass(g)

	append(&g.events, mouse_down({5, 5}))
	append(&g.events, mouse_up({700, 500}))
	handle_events(g)

	testing.expect_value(t, test_clicks, 0)

	test_gui_destroy(g)
}

@(test)
test_visibility_toggle :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel"})
	testing.expect_value(t, .Visible in widget_get(g, panel).state, true)

	widget_get(g, panel).state -= Widget_State{.Visible}
	testing.expect_value(t, .Visible in widget_get(g, panel).state, false)

	widget_get(g, panel).state += Widget_State{.Visible}
	testing.expect_value(t, .Visible in widget_get(g, panel).state, true)

	test_gui_destroy(g)
}

@(test)
test_demo_scene_layout :: proc(t: ^testing.T) {
	g := test_gui(t)
	init_demo(g, INVALID_FONT_FAMILY_ID)
	layout_pass(g)

	//* The toolbar keeps its minimum width, the rest takes the remainder.
	toolbar := widget_get(g, demo.toolbar)
	testing.expect_value(t, toolbar.rect.w, 220.0)
	testing.expect_value(t, toolbar.rect.h, 600.0)

	//* The right hand split fills the remaining width.
	side := widget_get(g, demo.side)
	testing.expect_value(t, side.rect.x, 220.0)
	testing.expect_value(t, side.rect.w, 580.0)

	//* The vertical split gives each panel half the height.
	status := widget_get(g, demo.status)
	target := widget_get(g, demo.target)
	testing.expect_value(t, status.rect.h, 300.0)
	testing.expect_value(t, target.rect.y, 300.0)
	testing.expect_value(t, target.rect.h, 300.0)

	//* The bar starts empty.
	bar := widget_get(g, demo.bar)
	testing.expect_value(t, bar.rect.w, 0.0)

	test_gui_destroy(g)
}

@(test)
test_demo_scene_draws :: proc(t: ^testing.T) {
	g := test_gui(t)
	init_demo(g, INVALID_FONT_FAMILY_ID)
	layout_pass(g)
	build_draw_list(g)

	//* Something was drawn.
	testing.expect_value(t, len(g.draw.commands) > 0, true)
	testing.expect_value(t, len(g.draw.vertices) > 0, true)

	test_gui_destroy(g)
}

//* == Containers ==

@(test)
test_vbox_stacks_children :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := widget(g, .VBox, g.root, Widget_Opts{separation = 10})
	a := widget(g, .Panel, box, Widget_Opts{min_size = Vec2{0, 50}, fixed = true})
	b := widget(g, .Panel, box, Widget_Opts{min_size = Vec2{0, 30}, fixed = true})

	layout_pass(g)

	testing.expect_value(t, widget_get(g, a).rect.y, 0.0)
	testing.expect_value(t, widget_get(g, a).rect.h, 50.0)
	testing.expect_value(t, widget_get(g, b).rect.y, 60.0)
	testing.expect_value(t, widget_get(g, b).rect.h, 30.0)
	//* The cross axis is the whole box.
	testing.expect_value(t, widget_get(g, b).rect.w, 800.0)

	test_gui_destroy(g)
}

@(test)
test_hbox_lays_out_side_by_side :: proc(t: ^testing.T) {
	g := test_gui(t)

	box := widget(g, .HBox, g.root, Widget_Opts{separation = 8})
	a := widget(g, .Panel, box, Widget_Opts{min_size = Vec2{100, 0}, fixed = true})
	b := widget(g, .Panel, box, Widget_Opts{min_size = Vec2{40, 0}, fixed = true})

	layout_pass(g)

	testing.expect_value(t, widget_get(g, a).rect.x, 0.0)
	testing.expect_value(t, widget_get(g, a).rect.w, 100.0)
	testing.expect_value(t, widget_get(g, b).rect.x, 108.0)
	testing.expect_value(t, widget_get(g, b).rect.w, 40.0)

	test_gui_destroy(g)
}

//* == Drag to dock ==

@(test)
test_drag_moves_a_panel_into_a_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Horizontal})
	container := widget(g, .Panel, split, Widget_Opts{name = "container", draggable = true})
	target := widget(g, .Panel, split, Widget_Opts{name = "target", draggable = true})

	panel := widget(g, .Panel, container, Widget_Opts{
		name = "panel",
		draggable = true,
		min_size = Vec2{100, 60},
	})
	layout_pass(g)

	//* Press on the title bar arms the drag, it does not start it.
	header := header_rect(widget_get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	handle_events(g)
	testing.expect_value(t, g.drag.armed, true)
	testing.expect_value(t, g.drag.active, false)

	//* Moving the pointer starts the drag.
	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	handle_events(g)
	testing.expect_value(t, g.drag.active, true)
	testing.expect_value(t, g.drag.widget, panel)

	//* The dragged widget leaves the layout.
	layout_pass(g)
	testing.expect_value(t, widget_get(g, panel).rect.w, 0.0)

	//* Move over the middle of the other panel: it is found, and the
	//* plan says the panel would become a tab of it.
	append(&g.events, mouse_move({600, 300}))
	handle_events(g)
	testing.expect_value(t, g.drag.target, target)
	testing.expect_value(t, g.drag.zone, .Center)
	testing.expect_value(t, g.drag.plan.kind, .Tabs)

	//* Release drops it.
	append(&g.events, mouse_up({600, 300}))
	handle_events(g)
	testing.expect_value(t, g.drag.active, false)

	//* The panel is now a tab of the target, which became a host.
	host := widget_get(g, target).parent
	testing.expect_value(t, widget_get(g, host).type, .Tabs)
	testing.expect_value(t, widget_get(g, panel).parent, host)
	testing.expect_value(t, widget_child_count(g, host), 2)

	test_gui_destroy(g)
}

@(test)
test_a_press_on_a_title_bar_is_not_a_drag :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	header := header_rect(widget_get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	handle_events(g)
	append(&g.events, mouse_up({header.x + 4, header.y + 4}))
	handle_events(g)

	//* The panel never left its slot.
	testing.expect_value(t, g.drag.active, false)
	testing.expect_value(t, g.drag.armed, false)
	testing.expect_value(t, widget_get(g, panel).parent, g.root)

	test_gui_destroy(g)
}

@(test)
test_escape_cancels_a_drag :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	header := header_rect(widget_get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	handle_events(g)
	append(&g.events, mouse_move({header.x + 40, header.y + 40}))
	handle_events(g)
	testing.expect_value(t, g.drag.active, true)

	append(&g.events, Key_Down_Event{key = .Escape})
	handle_events(g)
	testing.expect_value(t, g.drag.active, false)
	testing.expect_value(t, g.quit_requested, false)

	test_gui_destroy(g)
}

//* == Docking ==

@(test)
test_dock_splits_a_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := widget(g, .Panel, g.root, Widget_Opts{name = "container", draggable = true})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})

	dock(g, panel, container, .Right)

	//* The container is replaced by a split that holds it and the
	//* panel.
	split := widget_get(g, container).parent
	s := widget_get(g, split)
	testing.expect_value(t, s.type, .Split)
	testing.expect_value(t, widget_child_count(g, split), 2)
	testing.expect_value(t, widget_get(g, panel).parent, split)
	testing.expect_value(t, widget_index_of(g, split, panel), 1)
	testing.expect_value(t, widget_index_of(g, split, container), 0)

	#partial switch d in s.data {
	case Split_Data:
		testing.expect_value(t, d.direction, .Horizontal)
	}

	test_gui_destroy(g)
}

@(test)
test_dock_keeps_the_layout_of_the_container :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A vertical box: its children are stacked downwards.
	box := widget(g, .VBox, g.root, Widget_Opts{name = "box", separation = 8})
	first := widget(g, .Panel, box, Widget_Opts{name = "first", min_size = Vec2{0, 50}})
	second := widget(g, .Panel, box, Widget_Opts{name = "second", min_size = Vec2{0, 50}})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	dock(g, panel, box, .Right)
	layout_pass(g)

	//* The box is still a vertical box, so nothing inside it turned
	//* sideways: the children are still one above the other.
	testing.expect_value(t, widget_get(g, box).type, .VBox)
	testing.expect_value(t, widget_get(g, first).rect.x, widget_get(g, second).rect.x)
	testing.expect_value(t, widget_get(g, first).rect.y < widget_get(g, second).rect.y, true)
	testing.expect_value(t, widget_get(g, first).rect.h, widget_get(g, second).rect.h)

	test_gui_destroy(g)
}

@(test)
test_dock_preview_matches_the_result :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := widget(g, .Panel, g.root, Widget_Opts{name = "container", draggable = true})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	plan := dock_plan(g, panel, container, .Right, false, Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Split)
	testing.expect_value(t, plan.preview.x, 400.0)
	testing.expect_value(t, plan.preview.w, 400.0)

	dock_apply(g, panel, plan)
	layout_pass(g)

	//* The panel ends up exactly where the preview said it would.
	testing.expect_value(t, widget_get(g, panel).rect.x, plan.preview.x)
	testing.expect_value(t, widget_get(g, panel).rect.y, plan.preview.y)
	testing.expect_value(t, widget_get(g, panel).rect.w, plan.preview.w)
	testing.expect_value(t, widget_get(g, panel).rect.h, plan.preview.h)

	test_gui_destroy(g)
}

@(test)
test_dock_makes_a_tab_host :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := widget(g, .Panel, g.root, Widget_Opts{name = "container", draggable = true})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	dock(g, panel, container, .Center)

	//* The container became a tab host with both panels in it.
	host := widget_get(g, container).parent
	testing.expect_value(t, widget_get(g, host).type, .Tabs)
	testing.expect_value(t, widget_child_count(g, host), 2)
	testing.expect_value(t, widget_get(g, panel).parent, host)
	//* The panel that was dropped is the one on show.
	testing.expect_value(t, tabs_active(widget_get(g, host)), 1)

	layout_pass(g)

	//* The panel underneath is still there, below the strip.
	testing.expect_value(t, widget_get(g, panel).rect.h, 600.0 - TAB_BAR_HEIGHT)
	//* The panel that is not showing keeps no room.
	testing.expect_value(t, widget_get(g, container).rect.w, 0.0)

	test_gui_destroy(g)
}

@(test)
test_a_tab_button_switches_tabs :: proc(t: ^testing.T) {
	g := test_gui(t)

	container := widget(g, .Panel, g.root, Widget_Opts{name = "container", draggable = true})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	dock(g, panel, container, .Center)
	layout_pass(g)

	host := widget_get(g, container).parent
	w := widget_get(g, host)

	//* The first tab is the container that was there before.
	rects: [MAX_TABS]Rect
	n := tab_button_rects(g, w, &rects)
	testing.expect_value(t, n, 2)

	append(&g.events, mouse_down({rects[0].x + 2, rects[0].y + 2}))
	handle_events(g)
	testing.expect_value(t, tabs_active(w), 0)

	layout_pass(g)
	//* The panel that was underneath is showing again.
	testing.expect_value(t, widget_get(g, container).rect.w, 800.0)

	test_gui_destroy(g)
}

@(test)
test_dock_swaps_two_panels :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Vertical})
	a := widget(g, .Panel, split, Widget_Opts{name = "a", draggable = true})
	b := widget(g, .Panel, split, Widget_Opts{name = "b", draggable = true})
	layout_pass(g)

	//* Dropping one panel on the other with the swap modifier set
	//* exchanges their places.
	plan := dock_with(g, a, b, .Center, true)
	testing.expect_value(t, plan.kind, .Swap)

	testing.expect_value(t, widget_get(g, a).parent, split)
	testing.expect_value(t, widget_get(g, b).parent, split)
	testing.expect_value(t, widget_index_of(g, split, a), 1)
	testing.expect_value(t, widget_index_of(g, split, b), 0)

	test_gui_destroy(g)
}

@(test)
test_dock_zone_edges :: proc(t: ^testing.T) {
	container := Rect{x = 0, y = 0, w = 200, h = 200}

	testing.expect_value(t, dock_zone(container, Vec2{100, 100}), .Center)
	testing.expect_value(t, dock_zone(container, Vec2{2, 100}), .Left)
	testing.expect_value(t, dock_zone(container, Vec2{198, 100}), .Right)
	testing.expect_value(t, dock_zone(container, Vec2{100, 2}), .Top)
	testing.expect_value(t, dock_zone(container, Vec2{100, 198}), .Bottom)
	testing.expect_value(t, dock_zone(container, Vec2{400, 400}), .None)
}

@(test)
test_dock_into_a_split_makes_another_slice :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{name = "split", split = .Horizontal})
	widget(g, .Panel, split, Widget_Opts{name = "a"})
	widget(g, .Panel, split, Widget_Opts{name = "b"})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	plan := dock_plan(g, panel, split, .Left, false, Vec2{400, 300})
	testing.expect_value(t, plan.kind, .Split)
	//* The split keeps its own shape and gains a slice.
	testing.expect_value(t, plan.create_split, false)
	testing.expect_value(t, plan.count, 3)
	testing.expect_value(t, plan.other_count, 2)
	//* The panel takes the first slice.
	testing.expect_value(t, plan.preview.x, 0.0)

	dock_apply(g, panel, plan)
	layout_pass(g)

	testing.expect_value(t, widget_child_count(g, split), 3)
	testing.expect_value(t, widget_index_of(g, split, panel), 0)
	testing.expect_value(t, widget_get(g, panel).rect.w, plan.preview.w)
	testing.expect_value(t, widget_get(g, panel).rect.x, plan.preview.x)

	test_gui_destroy(g)
}

@(test)
test_dock_keeps_the_shape_of_a_split :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A split with two panels in it.
	split := widget(g, .Split, g.root, Widget_Opts{name = "split", split = .Vertical})
	first := widget(g, .Panel, split, Widget_Opts{name = "first"})
	second := widget(g, .Panel, split, Widget_Opts{name = "second"})
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* Dropping on the left makes a new split across the old one, so
	//* the old split keeps stacking its panels downwards.
	dock(g, panel, split, .Left)
	layout_pass(g)

	testing.expect_value(t, widget_get(g, split).type, .Split)
	testing.expect_value(t, widget_get(g, first).rect.y < widget_get(g, second).rect.y, true)
	testing.expect_value(t, widget_get(g, first).rect.x, widget_get(g, second).rect.x)

	test_gui_destroy(g)
}

//* == Text input ==

field_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	w := widget_get(g, id)
	if w == nil { return "" }
	#partial switch d in w.data {
	case Text_Input_Data:
		return d.text
	}
	return ""
}

@(test)
test_text_input_editing :: proc(t: ^testing.T) {
	g := test_gui(t)

	field := widget(g, .TextInput, g.root, Widget_Opts{text = "abc"})
	text_input_set_caret(g, field, 3, false)

	//* Typing inserts at the caret.
	fire_text(g, field, "d")
	testing.expect_value(t, field_text(g, field), "abcd")

	//* Backspace removes the character before the caret.
	text_input_backspace(g, field)
	testing.expect_value(t, field_text(g, field), "abc")

	//* The caret moves by codepoint.
	text_input_move_caret(g, field, false, false)
	text_input_move_caret(g, field, false, false)
	fire_text(g, field, "X")
	testing.expect_value(t, field_text(g, field), "aXbc")

	//* A selection is replaced by what is typed.
	text_input_set_caret(g, field, 0, false)
	text_input_set_caret(g, field, 3, true)
	fire_text(g, field, "-")
	testing.expect_value(t, field_text(g, field), "-c")

	test_gui_destroy(g)
}

@(test)
test_text_input_focus_and_caret :: proc(t: ^testing.T) {
	g := test_gui(t)
	//* The caret is placed by measuring the text, so a font is needed.
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := widget(g, .TextInput, g.root, Widget_Opts{text = "hello"})
	layout_pass(g)

	//* Clicking the field focuses it.
	focus_click(g, field, Vec2{20, 10})
	testing.expect_value(t, g.focused, field)

	//* The caret sits at the clicked offset.
	#partial switch d in widget_get(g, field).data {
	case Text_Input_Data:
		testing.expect_value(t, d.caret > 0 && d.caret < 5, true)
	}

	test_gui_destroy(g)
}

@(test)
test_double_click_selects_all_text :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := widget(g, .TextInput, g.root, Widget_Opts{text = "hello world"})
	layout_pass(g)

	//* A double click selects everything.
	focus_click(g, field, Vec2{20, 10}, 2)
	testing.expect_value(t, g.focused, field)

	#partial switch d in widget_get(g, field).data {
	case Text_Input_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, len(d.text))
		testing.expect_value(t, d.caret, len(d.text))
	}

	//* Typing replaces the selection.
	fire_text(g, field, "x")
	testing.expect_value(t, field_text(g, field), "x")

	test_gui_destroy(g)
}

@(test)
test_click_away_removes_the_caret :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := widget(g, .TextInput, g.root, Widget_Opts{
		text = "hello",
		preset = .Top_Left,
		offsets = Offset{16, 16, 300, 48},
	})
	other := widget(g, .Button, g.root, Widget_Opts{
		name = "other",
		preset = .Top_Left,
		offsets = Offset{16, 100, 300, 140},
	})
	layout_pass(g)

	//* Click into the field: it takes the focus.
	append(&g.events, mouse_down({30, 30}, 1))
	handle_events(g)
	testing.expect_value(t, g.focused, field)

	//* Click somewhere else: the focus (and the caret) is gone.
	append(&g.events, mouse_down({30, 120}, 1))
	handle_events(g)
	testing.expect_value(t, g.focused, INVALID_WIDGET_ID)

	//* Clicking the field again brings it back.
	append(&g.events, mouse_down({30, 30}, 1))
	handle_events(g)
	testing.expect_value(t, g.focused, field)

	test_gui_destroy(g)
}

@(test)
test_click_away_clears_the_selection :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := widget(g, .TextInput, g.root, Widget_Opts{
		text = "hello world",
		preset = .Top_Left,
		offsets = Offset{16, 16, 300, 48},
	})
	other := widget(g, .Button, g.root, Widget_Opts{
		name = "other",
		preset = .Top_Left,
		offsets = Offset{16, 100, 300, 140},
	})
	layout_pass(g)

	//* Double click selects everything.
	append(&g.events, mouse_down({30, 30}, 2))
	handle_events(g)

	#partial switch d in widget_get(g, field).data {
	case Text_Input_Data:
		testing.expect_value(t, d.sel_start, 0)
		testing.expect_value(t, d.sel_end, len(d.text))
	}

	//* Clicking away drops the selection with the caret.
	append(&g.events, mouse_down({30, 120}, 1))
	handle_events(g)
	testing.expect_value(t, g.focused, INVALID_WIDGET_ID)

	#partial switch d in widget_get(g, field).data {
	case Text_Input_Data:
		testing.expect_value(t, d.sel_start, d.caret)
		testing.expect_value(t, d.sel_end, d.caret)
	}

	//* So nothing is highlighted any more.
	testing.expect_value(t, text_input_selection_rect(g, field, Rect{0, 0, 100, 20}).w, 0.0)

	test_gui_destroy(g)
}

//* == Fonts ==

@(test)
test_text_input_full_frame_loop :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	field := widget(g, .TextInput, g.root, Widget_Opts{
		text = "type here",
		preset = .Top_Left,
		offsets = Offset{16, 16, 300, 48},
	})
	frame(g)

	//* Click into the field.
	focus_click(g, field, Vec2{30, 30})
	frame(g)

	//* The click put the caret where the pointer landed (in the middle
	//* of "type here"); put it at the end.
	text_input_set_caret(g, field, len("type here"), false)

	//* Type, with a full frame after every character.
	for i in 0 ..< 5 {
		fire_text(g, field, "x")
		frame(g)
	}
	testing.expect_value(t, field_text(g, field), "type herexxxxx")

	//* And edit: backspace, arrows, selection.
	text_input_backspace(g, field)
	frame(g)
	testing.expect_value(t, field_text(g, field), "type herexxxx")

	text_input_select_all(g, field)
	frame(g)
	fire_text(g, field, "done")
	frame(g)
	testing.expect_value(t, field_text(g, field), "done")

	test_gui_destroy(g)
}

@(test)
test_font_sizes_share_one_file :: proc(t: ^testing.T) {
	g := test_gui(t)

	a := font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	b := font_load(g, "assets/fonts/Roboto-Regular.ttf", 32)
	testing.expect_value(t, a != INVALID_FONT_ID, true)
	testing.expect_value(t, b != INVALID_FONT_ID, true)
	testing.expect_value(t, a != b, true)

	//* One parsed file, two size instances, one shared atlas.
	testing.expect_value(t, len(g.font_files), 1)
	testing.expect_value(t, len(g.fonts), 2)
	testing.expect_value(t, font_get(g, a).file == font_get(g, b).file, true)

	//* The same size returns the same instance.
	c := font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	testing.expect_value(t, c, a)

	test_gui_destroy(g)
}

//* == Resizing ==

@(test)
test_a_panel_is_resized_by_pulling_on_its_edge :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Horizontal})
	left := widget(g, .Panel, split, Widget_Opts{name = "left", draggable = true})
	right := widget(g, .Panel, split, Widget_Opts{name = "right", draggable = true})
	layout_pass(g)

	//* The split gives each panel half of the window.
	testing.expect_value(t, widget_get(g, left).rect.w, 400.0)
	testing.expect_value(t, widget_get(g, right).rect.w, 400.0)

	//* Press on the right edge of the left panel and pull it to the
	//* right.
	append(&g.events, mouse_down({398, 100}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({448, 100}))
	handle_events(g)
	layout_pass(g)

	//* The left panel took the space, the right one gave it up.
	testing.expect_value(t, widget_get(g, left).rect.w, 450.0)
	testing.expect_value(t, widget_get(g, right).rect.x, 450.0)
	testing.expect_value(t, widget_get(g, right).rect.w, 350.0)

	//* The size is kept: the layout does not take it away again.
	layout_pass(g)
	testing.expect_value(t, widget_get(g, left).rect.w, 450.0)
	testing.expect_value(t, widget_get(g, right).rect.w, 350.0)

	append(&g.events, mouse_up({448, 100}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, false)

	test_gui_destroy(g)
}

@(test)
test_a_panel_is_resized_by_pulling_on_its_corner :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Vertical})
	top := widget(g, .Panel, split, Widget_Opts{name = "top", draggable = true})
	bottom := widget(g, .Panel, split, Widget_Opts{name = "bottom", draggable = true})
	layout_pass(g)

	//* The split gives each panel half of the window.
	testing.expect_value(t, widget_get(g, top).rect.h, 300.0)
	testing.expect_value(t, widget_get(g, bottom).rect.y, 300.0)

	//* Pull the bottom right corner of the top panel up and to the
	//* left.
	append(&g.events, mouse_down({798, 298}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({778, 278}))
	handle_events(g)
	layout_pass(g)

	//* The top panel is narrower and shorter, the bottom one took up
	//* the space that was left.
	testing.expect_value(t, widget_get(g, top).rect.w, 780.0)
	testing.expect_value(t, widget_get(g, top).rect.h, 280.0)
	testing.expect_value(t, widget_get(g, bottom).rect.y, 280.0)
	testing.expect_value(t, widget_get(g, bottom).rect.h, 320.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_cannot_be_pulled_below_its_minimum :: proc(t: ^testing.T) {
	g := test_gui(t)

	split := widget(g, .Split, g.root, Widget_Opts{split = .Horizontal})
	left := widget(
		g,
		.Panel,
		split,
		Widget_Opts{name = "left", draggable = true, min_size = Vec2{200, 0}},
	)
	right := widget(g, .Panel, split, Widget_Opts{name = "right", draggable = true})
	layout_pass(g)

	//* The left panel takes its minimum size, plus a share of the
	//* space that is left.
	testing.expect_value(t, widget_get(g, left).rect.w, 500.0)
	testing.expect_value(t, widget_get(g, right).rect.w, 300.0)

	//* Pull the right edge of the left panel to the left.
	append(&g.events, mouse_down({498, 100}))
	handle_events(g)
	append(&g.events, mouse_move({50, 100}))
	handle_events(g)
	layout_pass(g)

	//* It stops at its minimum, and the other panel has the rest.
	testing.expect_value(t, widget_get(g, left).rect.w, 200.0)
	testing.expect_value(t, widget_get(g, right).rect.w, 600.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_in_a_panel_is_resized_by_its_offsets :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := widget(g, .Panel, g.root, Widget_Opts{name = "host"})
	panel := widget(g, .Panel, host, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* The panel fills its host.
	testing.expect_value(t, widget_get(g, panel).rect.w, 800.0)

	//* Pull its right edge to the left.
	append(&g.events, mouse_down({798, 100}))
	handle_events(g)
	append(&g.events, mouse_move({698, 100}))
	handle_events(g)
	layout_pass(g)

	//* The panel is narrower now, and the host keeps its size.
	testing.expect_value(t, widget_get(g, panel).rect.w, 700.0)
	testing.expect_value(t, widget_get(g, host).rect.w, 800.0)

	test_gui_destroy(g)
}

@(test)
test_the_title_bar_of_a_panel_is_not_a_grip :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* A press on the title bar starts a drag, not a resize.
	append(&g.events, mouse_down({10, 10}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, false)
	testing.expect_value(t, g.drag.armed, true)

	//* Below the title bar, the edge of the panel is a grip.
	append(&g.events, mouse_up({10, 10}))
	handle_events(g)
	append(&g.events, mouse_down({2, 100}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, true)
	testing.expect_value(t, g.drag.armed, false)

	test_gui_destroy(g)
}

@(test)
test_a_panel_in_a_tab_host_is_resized_through_its_host :: proc(t: ^testing.T) {
	g := test_gui(t)

	host := widget(g, .Tabs, g.root, Widget_Opts{name = "host"})
	panel := widget(g, .Panel, host, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* The panel fills the content of the host, below the tab strip.
	testing.expect_value(t, widget_get(g, panel).rect.w, 800.0)
	testing.expect_value(t, widget_get(g, panel).rect.h, 576.0)

	//* Pull the right edge of the panel to the left.
	append(&g.events, mouse_down({798, 300}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move({698, 300}))
	handle_events(g)
	layout_pass(g)

	//* The host is narrower now, and the panel with it.
	testing.expect_value(t, widget_get(g, host).rect.w, 700.0)
	testing.expect_value(t, widget_get(g, panel).rect.w, 700.0)

	test_gui_destroy(g)
}

@(test)
test_a_panel_dragged_out_of_the_window_can_be_resized :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* Drag the panel out of the window: it gets a window of its own.
	header := header_rect(widget_get(g, panel))
	append(&g.events, mouse_down({header.x + 4, header.y + 4}))
	handle_events(g)
	append(&g.events, mouse_move({900, 700}))
	handle_events(g)
	append(&g.events, mouse_up({900, 700}))
	handle_events(g)

	testing.expect_value(t, len(g.floats), 1)
	layout_pass(g)

	//* Pull the right edge of the floating panel to the right.
	f := g.floats[0]
	append(&g.events, mouse_down_float({f.pos.x + f.size.x - 2, f.pos.y + 100}, {f.size.x - 2, 100}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move_float({f.pos.x + f.size.x + 38, f.pos.y + 100}, {f.size.x + 38, 100}))
	handle_events(g)

	testing.expect_value(t, g.floats[0].size.x, f.size.x + 40)

	test_gui_destroy(g)
}

@(test)
test_the_free_space_of_a_container_is_never_cut_too_far :: proc(t: ^testing.T) {
	g := test_gui(t)

	//* A panel with several children in its corner: every child cuts
	//* the free space into more pieces.
	host := widget(g, .Panel, g.root, Widget_Opts{name = "host", draggable = true})
	for i in 0 ..< 6 {
		widget(g, .Panel, host, Widget_Opts{
			name = "child",
			preset = .Top_Left,
			offsets = Offset{0, f32(i) * 20, 100, f32(i) * 20 + 10},
		})
	}
	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* The free space is found without running out of room for it.
	space, count := container_free_space(g, host)
	testing.expect_value(t, count > 0, true)
	testing.expect_value(t, space[0].w > 0, true)

	//* None of the free space is covered by a child: the pieces that
	//* did not fit are left out instead.
	child := widget_get(g, host).first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		for i in 0 ..< count {
			overlap_x := min(space[i].x + space[i].w, c.rect.x + c.rect.w) - max(space[i].x, c.rect.x)
			overlap_y := min(space[i].y + space[i].h, c.rect.y + c.rect.h) - max(space[i].y, c.rect.y)
			testing.expect_value(t, overlap_x > 0 && overlap_y > 0, false)
		}
		child = c.next_sibling
	}

	//* A drop on the panel still works: it becomes a tab.
	plan := dock_plan(g, panel, host, .Center, false, Vec2{400, 300})
	testing.expect_value(t, plan.kind != .None, true)

	test_gui_destroy(g)
}

@(test)
test_the_grip_of_a_floating_panel_is_marked :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	//* The panel is a window of its own, outside of the main window.
	float_panel(g, panel, Vec2{1000, 500}, Vec2{320, 240})
	layout_pass(g)

	//* The pointer is on the right edge of the floating panel.
	g.global_pointer = Vec2{1000 + 320 - 2, 500 + 100}
	update_resize_hover(g)

	//* The grip is marked and the pointer asks for a resize cursor.
	testing.expect_value(t, g.resize_hover, panel)
	testing.expect_value(t, g.cursor, .Resize_E)

	//* The pointer is somewhere else: there is no grip.
	g.global_pointer = Vec2{1000 + 100, 500 + 100}
	update_resize_hover(g)
	testing.expect_value(t, g.resize_hover, INVALID_WIDGET_ID)
	testing.expect_value(t, g.cursor, .Default)

	test_gui_destroy(g)
}

@(test)
test_a_floating_panel_is_resized_by_its_window :: proc(t: ^testing.T) {
	g := test_gui(t)

	panel := widget(g, .Panel, g.root, Widget_Opts{name = "panel", draggable = true})
	layout_pass(g)

	float_panel(g, panel, Vec2{300, 200}, Vec2{320, 240})
	layout_pass(g)

	//* Pull the right edge of the floating panel to the right.
	append(&g.events, mouse_down_float({618, 300}, {318, 100}))
	handle_events(g)
	testing.expect_value(t, g.resize.active, true)
	append(&g.events, mouse_move_float({658, 300}, {358, 100}))
	handle_events(g)

	//* The window is wider, and it did not move.
	testing.expect_value(t, g.floats[0].size.x, 360.0)
	testing.expect_value(t, g.floats[0].pos.x, 300.0)

	//* Pull the left edge to the right: the window moves with it.
	append(&g.events, mouse_up_float({658, 300}, {358, 100}))
	handle_events(g)
	append(&g.events, mouse_down_float({302, 300}, {2, 100}))
	handle_events(g)
	append(&g.events, mouse_move_float({342, 300}, {42, 100}))
	handle_events(g)

	testing.expect_value(t, g.floats[0].size.x, 320.0)
	testing.expect_value(t, g.floats[0].pos.x, 340.0)

	test_gui_destroy(g)
}

//* == Text pipeline ==
//* A mock backend that records texture uploads, so the font path can be
//* tested without a window.
mock_uploads: int = 0

mock_create :: proc(ctx, window: rawptr, w, h: i32) -> bool { return true }
mock_destroy :: proc(ctx: rawptr) {}
mock_resize :: proc(ctx: rawptr, w, h: i32) -> bool { return true }
mock_upload_texture :: proc(ctx: rawptr, id: Texture_ID, pixels: []u8, w, h: i32) -> bool {
	mock_uploads += 1
	return true
}
mock_submit :: proc(ctx: rawptr, dl: ^Draw_List) {}

mock_backend :: Backend {
	ctx = nil,
	create = mock_create,
	destroy = mock_destroy,
	resize = mock_resize,
	upload_texture = mock_upload_texture,
	submit = mock_submit,
}

@(test)
test_font_loads_and_measures :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend

	font := font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	testing.expect_value(t, font != INVALID_FONT_ID, true)
	testing.expect_value(t, g.default_font, font)

	//* Text has a real width, and it grows with the string.
	size := font_measure(g, font, "Hello")
	testing.expect_value(t, size.x > 0, true)
	testing.expect_value(t, size.y > 0, true)

	longer := font_measure(g, font, "Hello world")
	testing.expect_value(t, longer.x > size.x, true)

	test_gui_destroy(g)
}

@(test)
test_text_draws_glyphs_and_uploads_atlas :: proc(t: ^testing.T) {
	g := test_gui(t)
	g.backend = mock_backend
	mock_uploads = 0

	font := font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	testing.expect_value(t, font != INVALID_FONT_ID, true)

	label := widget(g, .Label, g.root, Widget_Opts{
		name = "label",
		text = "Hello",
		preset = .Top_Left,
		style = Style{text = Text_Style{colour = rgba(1, 1, 1, 1)}},
	})

	frame(g)

	//* The label grew to fit its text.
	w := widget_get(g, label)
	testing.expect_value(t, w.min_size.x > 0, true)

	//* Glyph quads were emitted.
	testing.expect_value(t, len(g.draw.vertices) > 4, true)

	//* The glyph atlas page was uploaded to the backend.
	testing.expect_value(t, mock_uploads > 0, true)

	//* Every command stays inside one page texture (the glyph pages).
	for cmd in g.draw.commands {
		testing.expect_value(t, cmd.texture != INVALID_TEXTURE_ID, true)
	}

	test_gui_destroy(g)
}
