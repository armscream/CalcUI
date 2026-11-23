package Accessibility

import Core "../Core"
import Widgets "../Widgets"
import "core:testing"

test_gui :: proc(t: ^testing.T) -> ^Core.GUI {
	g := new(Core.GUI)
	g^ = Core.GUI{}
	g.viewport = Core.Rect{w = 800, h = 600}
	g.window_rect = g.viewport
	g.target = &g.draw
	g.scale = 1
	g.draw.scale = 1
	g.atlas = Core.atlas_make(Core.ATLAS_DEFAULT_SIZE, Core.ATLAS_DEFAULT_SIZE)
	g.atlas_texture = Core.ATLAS_TEXTURE_ID
	g.font_instances = make(map[Core.Font_Instance_Key]Core.Font_ID)
	g.glyphs = make(map[Core.Glyph_Key]Core.Glyph_Entry)
	g.class_by_type = make(map[Core.Widget_Type]Core.Widget_Class_ID)
	g.class_by_name = make(map[string]Core.Widget_Class_ID)
	Core.init_text(g)
	g.root = Core.New_Widget(g, .Panel, Core.INVALID_WIDGET_ID, Core.Widget_Opts{name = "root"})
	return g
}

test_gui_destroy :: proc(g: ^Core.GUI) {
	if g == nil { return }
	for w in g.widgets {
		if w == nil { continue }
		if w.id != Core.INVALID_WIDGET_ID {
			Core.widget_notify_destroy(g, w.id, w)
		}
		Core.widget_release_data(g, w)
		free(w)
	}
	Core.font_destroy(g)
	Core.theme_destroy(g.theme)
	Core.Style_Pool_Destroy(g)
	Core.atlas_destroy(g.atlas)
	Core.text_input_ime_destroy(g)
	Core.undo_destroy(g)
	delete(g.clipboard.text)
	Core.draw_list_destroy(&g.draw)
	for &f in g.floats {
		Core.draw_list_destroy(&f.draw)
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
	if g.class_by_type != nil { delete(g.class_by_type) }
	if g.class_by_name != nil { delete(g.class_by_name) }
	delete(g.scene_constructors)
	delete(g.commands.list)
	Core.measure_cache_destroy(g)
	free(cast(rawptr) g)
}

test_access_tree :: proc(g: ^Core.GUI) -> ^Access_Tree {
	tree := new(Access_Tree)
	tree.gui = g
	tree.hooks = access_native()
	tree.allocator = context.allocator
	tree.nodes = make(map[Core.Widget_ID]^Access_Node)
	tree.order = make([dynamic]Core.Widget_ID)
	tree.focused = Core.INVALID_WIDGET_ID
	tree.bridge = Core.Access_Bridge {
		ctx           = cast(rawptr) tree,
		node_added    = access_node_added,
		node_changed  = access_node_changed,
		node_removed  = access_node_removed,
		focus_changed = access_focus_changed,
	}
	return tree
}

@(test)
test_the_tree_of_the_window_holds_the_widgets :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	button := Widgets.Make_Button(g, g.root, Core.Button_Opts{
		Base_Opts = Core.Base_Opts{name = "ok"},
		text       = "OK",
	})

	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	testing.expect_value(t, len(tree.order), 2)
	node := access_node_of(tree, button)
	testing.expect(t, node != nil)
	testing.expect_value(t, node.role, Core.Access_Role.Button)
	testing.expect_value(t, node.name, "OK")

	Core.Widget_Free(g, button)
	testing.expect(t, access_node_of(tree, button) == nil)
	testing.expect_value(t, len(tree.order), 1)
}

@(test)
test_the_parent_of_a_widget_is_the_one_of_the_core :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	button := Widgets.Make_Button(g, g.root, Core.Button_Opts{
		Base_Opts = Core.Base_Opts{name = "ok"},
		text       = "OK",
	})
	testing.expect_value(t, access_parent_of(tree, button), g.root)
}

@(test)
test_the_children_of_a_widget_are_the_ones_of_the_core :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	first := Widgets.Make_Label(g, g.root, Core.Label_Opts{
		Base_Opts = Core.Base_Opts{name = "first"},
	})
	second := Widgets.Make_Label(g, g.root, Core.Label_Opts{
		Base_Opts = Core.Base_Opts{name = "second"},
	})

	children: [dynamic]Core.Widget_ID
	count := access_children_of(tree, g.root, &children)
	defer delete(children)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, children[0], first)
	testing.expect_value(t, children[1], second)
}

@(test)
test_the_platform_of_the_host_says_whether_it_has_one :: proc(t: ^testing.T) {
	available := Access_Available()
	native := access_native()
	testing.expect_value(t, available, native.available)
	if !available {
		testing.expect(t, native.create == nil)
		testing.expect(t, native.update == nil)
		testing.expect(t, native.destroy == nil)
		testing.expect(t, native.focus == nil)
	}
}
