#+build windows
package Accessibility

import Core "../Core"
import Widgets "../Widgets"
import "core:testing"

//* The event of the system as the tests see it.
test_event_count: int
test_event_id: i32

test_event :: proc "system" (provider: rawptr, id: i32) -> HRESULT {
	test_event_count += 1
	test_event_id = id
	return S_OK
}

//* Whether a box of the program is switched on.
check_box_is_on :: proc(g: ^Core.GUI, id: Core.Widget_ID) -> bool {
	w := Core.Widget_Get(g, id)
	if w == nil { return false }
	#partial switch d in w.data {
	case Core.Check_Box_Data:
		return d.on
	}
	return false
}

uia_property_text :: proc(t: ^testing.T, provider: ^Uia_Provider, id: i32) -> string {
	variant: VARIANT
	result := provider.vtbl.GetPropertyValue(cast(rawptr) provider, id, &variant)
	testing.expect_value(t, result, S_OK)
	if variant.vt != VT_BSTR { return "" }
	text := variant_pointer(&variant)^
	if text == nil { return "" }
	value := uia_text_of(text)
	SysFreeString(text)
	return value
}

//* The number of a property of a widget as the system reads it.
//* A yes or no is read as the number of the platform, which keeps its
//* true in the lower half of the number.
uia_property_number :: proc(t: ^testing.T, provider: ^Uia_Provider, id: i32) -> i32 {
	variant: VARIANT
	result := provider.vtbl.GetPropertyValue(cast(rawptr) provider, id, &variant)
	testing.expect_value(t, result, S_OK)
	if variant.vt == VT_BOOL {
		value := variant_bool(&variant)^
		if value == VARIANT_TRUE { return -1 }
		return 0
	}
	return variant_int(&variant)^
}

@(test)
test_the_object_of_a_widget_says_what_it_is :: proc(t: ^testing.T) {
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

	node := access_node_of(tree, button)
	testing.expect(t, node != nil)
	object := cast(^Uia_Object)node.native
	testing.expect(t, object != nil)
	provider := object.provider
	testing.expect(t, provider != nil)

	name := uia_property_text(t, provider, UIA_NamePropertyId)
	testing.expect_value(t, name, "OK")
	delete(name)
	testing.expect_value(t, uia_property_number(t, provider, UIA_ControlTypePropertyId), UIA_ButtonControlTypeId)
	class_name := uia_property_text(t, provider, UIA_ClassNamePropertyId)
	testing.expect_value(t, class_name, "CalcUI")
	delete(class_name)
}

@(test)
test_the_object_of_a_widget_that_is_hidden_says_so :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	label := Widgets.Make_Label(g, g.root, Core.Label_Opts{
		Base_Opts = Core.Base_Opts{name = "title"},
		text       = "Hello",
	})
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	node := access_node_of(tree, label)
	object := cast(^Uia_Object)node.native
	provider := object.provider

	//* The widget is shown, so it is not off the screen.
	testing.expect_value(t, uia_property_number(t, provider, UIA_IsOffscreenPropertyId), 0)

	Core.Widget_Set_Visible(g, label, false)
	Core.Access_Sync(g)
	testing.expect_value(t, uia_property_number(t, provider, UIA_IsOffscreenPropertyId), VARIANT_TRUE)
}

@(test)
test_the_object_of_a_text_box_has_the_value :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	box := Widgets.Make_Text_Box(g, g.root, Core.Text_Box_Opts{
		Base_Opts = Core.Base_Opts{name = "name"},
		text       = "abc",
	})
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	node := access_node_of(tree, box)
	object := cast(^Uia_Object)node.native
	provider := object.provider

	testing.expect_value(t, uia_property_number(t, provider, UIA_ControlTypePropertyId), UIA_EditControlTypeId)
	value_text := uia_property_text(t, provider, UIA_ValueValuePropertyId)
	testing.expect_value(t, value_text, "abc")
	delete(value_text)

	//* The system asks for the pattern of the value.
	pattern: rawptr
	result := provider.vtbl.GetPatternProvider(cast(rawptr) provider, UIA_ValuePatternId, &pattern)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, pattern != nil)

	value := cast(^Uia_Value)pattern
	text: rawptr
	result = value.vtbl.get_Value(cast(rawptr) value, &text)
	testing.expect_value(t, result, S_OK)
	held := uia_text_of(text)
	testing.expect_value(t, held, "abc")
	delete(held)
	SysFreeString(text)

	value.vtbl.Release(cast(rawptr) value)
}

@(test)
test_the_object_of_a_box_can_be_switched :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	box := Widgets.Make_Check_Box(g, g.root, Core.Check_Box_Opts{
		Base_Opts = Core.Base_Opts{name = "on"},
		text       = "On",
	})
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	node := access_node_of(tree, box)
	object := cast(^Uia_Object)node.native
	provider := object.provider

	testing.expect_value(t, uia_property_number(t, provider, UIA_ControlTypePropertyId), UIA_CheckBoxControlTypeId)
	testing.expect_value(t, uia_property_number(t, provider, UIA_ToggleToggleStatePropertyId), 0)

	pattern: rawptr
	result := provider.vtbl.GetPatternProvider(cast(rawptr) provider, UIA_TogglePatternId, &pattern)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, pattern != nil)

	toggle := cast(^Uia_Toggle)pattern
	state: i32
	result = toggle.vtbl.get_ToggleState(cast(rawptr) toggle, &state)
	testing.expect_value(t, result, S_OK)
	testing.expect_value(t, state, 0)

	//* The system asks for the box to be switched. The action waits for
	//* the thread of the program.
	result = toggle.vtbl.Toggle(cast(rawptr) toggle)
	testing.expect_value(t, result, S_OK)
	access_apply_actions(tree)
	testing.expect(t, check_box_is_on(g, box))

	toggle.vtbl.Release(cast(rawptr) toggle)
}

@(test)
test_the_objects_of_the_tree_can_be_walked :: proc(t: ^testing.T) {
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
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	root_node := access_node_of(tree, g.root)
	root_object := cast(^Uia_Object)root_node.native
	fragment := root_object.fragment
	testing.expect(t, fragment != nil)

	//* The first child of the root of the tree.
	child: rawptr
	result := fragment.vtbl.Navigate(cast(rawptr) fragment, 3, &child)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, child != nil)

	child_provider := cast(^Uia_Provider)child
	first_name := uia_property_text(t, child_provider, UIA_NamePropertyId)
	testing.expect_value(t, first_name, "first")
	delete(first_name)
	child_provider.vtbl.Release(child)

	//* The brother after it.
	result = fragment.vtbl.Navigate(cast(rawptr) fragment, 4, &child)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, child != nil)
	child_provider = cast(^Uia_Provider)child
	second_name := uia_property_text(t, child_provider, UIA_NamePropertyId)
	testing.expect_value(t, second_name, "second")
	delete(second_name)
	child_provider.vtbl.Release(child)

	//* The parent of a widget is the root of the tree.
	first_node := access_node_of(tree, first)
	first_object := cast(^Uia_Object)first_node.native
	parent: rawptr
	result = first_object.fragment.vtbl.Navigate(cast(rawptr) first_object.fragment, 0, &parent)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, parent != nil)
	parent_provider := cast(^Uia_Provider)parent
	testing.expect_value(t, parent_provider.object.node.id, g.root)
	parent_provider.vtbl.Release(parent)
}

@(test)
test_the_object_of_a_widget_answers_for_its_interfaces :: proc(t: ^testing.T) {
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

	node := access_node_of(tree, button)
	object := cast(^Uia_Object)node.native
	provider := object.provider

	//* The interface of the provider.
	out: rawptr
	iid := IID_Raw_Provider
	result := provider.vtbl.QueryInterface(cast(rawptr) provider, &iid, &out)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, out != nil)
	provider.vtbl.Release(out)

	//* The interface of the fragment.
	out = nil
	iid = IID_Raw_Fragment
	result = provider.vtbl.QueryInterface(cast(rawptr) provider, &iid, &out)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, out != nil)
	fragment := cast(^Uia_Fragment)out
	fragment.vtbl.Release(out)

	//* An interface the object does not have.
	out = nil
	iid = IID_Value_Provider
	result = provider.vtbl.QueryInterface(cast(rawptr) provider, &iid, &out)
	testing.expect_value(t, result, E_NOINTERFACE)
	testing.expect(t, out == nil)
}

@(test)
test_the_widget_that_goes_lets_go_of_its_object :: proc(t: ^testing.T) {
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

	node := access_node_of(tree, button)
	testing.expect(t, node != nil)
	testing.expect(t, node.native != nil)

	Core.Widget_Free(g, button)
	testing.expect(t, access_node_of(tree, button) == nil)
}

@(test)
test_the_object_of_a_widget_that_is_gone_still_answers :: proc(t: ^testing.T) {
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

	node := access_node_of(tree, button)
	object := cast(^Uia_Object)node.native
	provider := object.provider
	//* The system holds the object after the widget goes.
	uia_add_ref(cast(rawptr) provider)

	Core.Widget_Free(g, button)

	//* The copy the object kept is still read without touching the widget.
	name := uia_property_text(t, provider, UIA_NamePropertyId)
	testing.expect_value(t, name, "")
	if name != "" { delete(name) }

	provider.vtbl.Release(cast(rawptr) provider)
}

@(test)
test_the_point_of_the_system_is_the_point_of_the_widget :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	root := Core.Widget_Get(g, g.root)
	root.rect = Core.Rect{w = 800, h = 600}
	label := Widgets.Make_Label(g, g.root, Core.Label_Opts{
		Base_Opts = Core.Base_Opts{name = "title"},
		text       = "Hello",
	})
	Core.Widget_Get(g, label).rect = Core.Rect{x = 10, y = 20, w = 30, h = 40}
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	//* The window is at 100, 50 and doubled, so the point of the system
	//* that covers the widget is at 220, 140.
	tree.origin = Core.Rect{x = 100, y = 50}
	tree.scale = 2

	root_node := access_node_of(tree, g.root)
	root_object := cast(^Uia_Object)root_node.native
	fragment := root_object.fragment_root
	testing.expect(t, fragment != nil)

	out: rawptr
	result := fragment.vtbl.ElementProviderFromPoint(cast(rawptr) fragment, 220, 140, &out)
	testing.expect_value(t, result, S_OK)
	testing.expect(t, out != nil)
	provider := cast(^Uia_Provider)out
	testing.expect_value(t, provider.object.node.id, label)
	provider.vtbl.Release(out)
}

@(test)
test_a_hidden_parent_makes_its_child_offscreen :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	panel := Core.New_Widget(g, .Panel, g.root, Core.Widget_Opts{name = "box"})
	label := Widgets.Make_Label(g, panel, Core.Label_Opts{
		Base_Opts = Core.Base_Opts{name = "title"},
		text       = "Hello",
	})
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	node := access_node_of(tree, label)
	object := cast(^Uia_Object)node.native
	provider := object.provider
	testing.expect_value(t, uia_property_number(t, provider, UIA_IsOffscreenPropertyId), 0)

	Core.Widget_Set_Visible(g, panel, false)
	Core.Access_Sync(g)
	testing.expect_value(t, uia_property_number(t, provider, UIA_IsOffscreenPropertyId), VARIANT_TRUE)
}

@(test)
test_a_new_name_is_told_to_the_system :: proc(t: ^testing.T) {
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

	saved_ready := uia_event_ready
	saved_event := uia_event
	defer {
		uia_event_ready = saved_ready
		uia_event = saved_event
	}
	test_event_count = 0
	test_event_id = 0
	uia_event_ready = true
	uia_event = test_event

	Core.Widget_Set_Access_Name(g, button, "Save")
	Core.Access_Sync(g)

	testing.expect_value(t, test_event_count, 1)
	testing.expect_value(t, test_event_id, UIA_AutomationNameChangedEventId)
}

@(test)
test_the_frame_brings_the_places_up_to_date :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	tree := test_access_tree(g)
	defer access_tree_destroy(tree)

	label := Widgets.Make_Label(g, g.root, Core.Label_Opts{
		Base_Opts = Core.Base_Opts{name = "title"},
		text       = "Hello",
	})
	Core.GUI_Set_Access_Bridge(g, tree.bridge)
	Core.Access_Sync(g)

	Core.Widget_Get(g, label).rect = Core.Rect{x = 5, y = 6, w = 7, h = 8}
	access_frame(tree)

	node := access_node_of(tree, label)
	object := cast(^Uia_Object)node.native
	testing.expect_value(t, object.node.rect, Core.Rect{x = 5, y = 6, w = 7, h = 8})
}

@(test)
test_the_box_of_a_widget_is_the_box_of_the_system :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(VARIANT), 24)
	testing.expect_value(t, align_of(VARIANT), 8)
	testing.expect_value(t, offset_of(VARIANT, value), 8)
}
