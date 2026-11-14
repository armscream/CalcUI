//* Text undo, redo and caret blink tests.

package Tests

import GUI "../GUI"
import "core:testing"

//* == Text undo and redo ==

@(test)
test_the_new_line_of_the_enter_key_can_be_taken_back :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	edit := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
		Base_Opts = GUI.Base_Opts{name = "edit"},
		text = "ab",
		flags = GUI.Text_Box_Flags{.Multiline},
	})
	GUI.layout_pass(g)
	d := GUI.text_box_data(g, edit)

	GUI.fire_key(g, edit, GUI.Key_Down_Event{key = .Enter})
	testing.expect_value(t, d.text, "ab\n")
	testing.expect_value(t, d.caret, 3)

	GUI.fire_key(g, edit, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab")
	testing.expect_value(t, d.caret, 2)

	GUI.fire_key(g, edit, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab\n")
	testing.expect_value(t, d.caret, 3)

	test_gui_destroy(g)
}

@(test)
test_the_ctrl_key_and_the_z_take_the_last_change_of_a_text_box_back :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		text = "ab",
	})
	GUI.layout_pass(g)
	d := GUI.text_box_data(g, field)

	GUI.text_input_insert(g, field, "c")
	testing.expect_value(t, d.text, "abc")
	testing.expect_value(t, d.caret, 3)

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab")
	testing.expect_value(t, d.caret, 2)

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "abc")
	testing.expect_value(t, d.caret, 3)

	test_gui_destroy(g)
}

@(test)
test_the_undo_of_a_text_box_goes_back_over_every_change :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		text = "ab",
	})
	GUI.layout_pass(g)
	d := GUI.text_box_data(g, field)

	GUI.text_input_insert(g, field, "c")
	GUI.text_input_backspace(g, field)
	GUI.text_input_insert(g, field, "d")
	testing.expect_value(t, d.text, "abd")

	//* Undo each change in reverse order.
	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "abc")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab")

	//* Nothing remains to undo.
	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab")

	//* Redo each change in its original order.
	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "abc")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "ab")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, d.text, "abd")

	test_gui_destroy(g)
}

@(test)
test_the_shift_key_and_the_z_make_the_change_of_a_text_box_happen_again :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		text = "ab",
	})
	GUI.layout_pass(g)

	GUI.text_input_insert(g, field, "c")
	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.text_box_data(g, field).text, "ab")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl, .Shift}})
	testing.expect_value(t, GUI.text_box_data(g, field).text, "abc")

	test_gui_destroy(g)
}

@(test)
test_the_undo_of_a_search_field :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Search_Field(g, g.root, GUI.Search_Field_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		text = "ab",
	})
	GUI.layout_pass(g)

	GUI.search_field_type(g, field, "c")
	testing.expect_value(t, GUI.search_field_text(g, field), "abc")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.search_field_text(g, field), "ab")

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.search_field_text(g, field), "abc")

	test_gui_destroy(g)
}

@(test)
test_the_undo_of_a_chat_input :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	chat := GUI.Make_Chat_Input(g, g.root, GUI.Chat_Input_Opts{Base_Opts = GUI.Base_Opts{name = "chat"}})
	GUI.layout_pass(g)

	GUI.chat_input_type(g, chat, "a")
	GUI.chat_input_type(g, chat, "b")
	testing.expect_value(t, GUI.chat_input_text(g, chat), "ab")

	GUI.fire_key(g, chat, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.chat_input_text(g, chat), "a")

	GUI.fire_key(g, chat, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.chat_input_text(g, chat), "ab")

	test_gui_destroy(g)
}

@(test)
test_the_undo_of_a_rich_text_editor :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	editor := GUI.Make_Rich_Text_Editor(g, g.root, GUI.Rich_Text_Editor_Opts{
		Base_Opts = GUI.Base_Opts{name = "editor"},
		text = "ab",
	})
	GUI.layout_pass(g)

	GUI.rich_text_editor_insert_text(g, editor, "c")
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "abc")

	GUI.fire_key(g, editor, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "ab")

	GUI.fire_key(g, editor, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.rich_text_editor_text(g, editor), "abc")

	test_gui_destroy(g)
}

@(test)
test_the_undo_of_a_number_input :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Number_Input(g, g.root, GUI.Number_Input_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		value = 12,
		min = 0,
		max = 100,
	})
	GUI.layout_pass(g)

	GUI.number_input_increment(g, field)
	testing.expect_value(t, GUI.number_input_value(g, field), 13)

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.number_input_value(g, field), 12)

	GUI.fire_key(g, field, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.number_input_value(g, field), 13)

	test_gui_destroy(g)
}

@(test)
test_the_undo_of_the_code_of_a_colour_picker :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	picker := GUI.Make_Color_Picker(g, g.root, GUI.Color_Picker_Opts{
		Base_Opts = GUI.Base_Opts{name = "picker"},
	})
	GUI.layout_pass(g)

	GUI.color_picker_begin_edit(g, picker, 0)
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "#000000")
	GUI.color_picker_type(g, picker, "1")
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "1#000000")

	GUI.fire_key(g, picker, GUI.Key_Down_Event{key = .Z, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "#000000")

	GUI.fire_key(g, picker, GUI.Key_Down_Event{key = .Y, mods = GUI.Mods{.Ctrl}})
	testing.expect_value(t, GUI.color_picker_edit_text(g, picker), "1#000000")

	test_gui_destroy(g)
}

@(test)
test_the_stack_of_the_changes_of_a_widget_goes_with_it :: proc(t: ^testing.T) {
	ownership_expect_clean(t, proc(t: ^testing.T) {
		g := text_box_test_gui(t)
		field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "field"},
			text = "ab",
		})
		GUI.layout_pass(g)

		GUI.text_input_insert(g, field, "c")
		GUI.text_input_backspace(g, field)
		testing.expect_value(t, GUI.text_input_can_undo(g, field), true)

		GUI.Widget_Free(g, field)
		testing.expect_value(t, GUI.text_input_can_undo(g, field), false)

		test_gui_destroy(g)
	})
}

//* == Caret blink ==

@(test)
test_the_caret_of_a_widget_that_has_the_keyboard_flashes :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		text = "ab",
	})
	GUI.layout_pass(g)

	GUI.focus_set(g, field)
	testing.expect_value(t, GUI.caret_visible(g), true)

	g.caret_timer = GUI.CARET_BLINK_PERIOD
	testing.expect_value(t, GUI.caret_visible(g), false)

	g.caret_timer = GUI.CARET_BLINK_PERIOD * 2
	testing.expect_value(t, GUI.caret_visible(g), true)

	g.caret_timer = GUI.CARET_BLINK_PERIOD
	GUI.text_input_insert(g, field, "c")
	testing.expect_value(t, GUI.caret_visible(g), true)

	test_gui_destroy(g)
}

@(test)
test_the_flash_of_the_caret_goes_on_while_a_widget_has_the_keyboard :: proc(t: ^testing.T) {
	g := text_box_test_gui(t)
	field := GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
		Base_Opts = GUI.Base_Opts{name = "field"},
		text = "ab",
	})
	GUI.layout_pass(g)

	g.dt = 0.1
	GUI.caret_tick(g)
	testing.expect_value(t, g.caret_timer, 0)

	GUI.focus_set(g, field)
	GUI.caret_tick(g)
	testing.expect_value(t, g.caret_timer > 0, true)

	GUI.focus_clear(g)
	GUI.caret_tick(g)
	testing.expect_value(t, g.caret_timer, 0)

	test_gui_destroy(g)
}