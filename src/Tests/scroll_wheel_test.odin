//* Tests that scrollable widgets consume the wheel only when they can
//* scroll further, otherwise passing it to their parent.

package Tests

import GUI "../GUI"
import "core:testing"

scroll_wheel_test_make :: proc(t: ^testing.T) -> (g: ^GUI.GUI, container: GUI.Widget_ID) {
	g = test_gui_with_font(t)
	g.backend = mock_backend

	container = GUI.Make_Scroll_Container(g, g.root, GUI.Scroll_Container_Opts{
		Base_Opts = GUI.Base_Opts{
			preset = .Top_Left,
			offsets = GUI.Offset{left = 0, top = 0, right = 300, bottom = 200},
		},
	})
	GUI.New_Widget(g, .Panel, container, GUI.Widget_Opts{min_size = {300, 900}})
	GUI.layout_pass(g)
	return
}

scroll_wheel_test_child_base :: proc(bottom: f32) -> GUI.Base_Opts {
	return GUI.Base_Opts{
		preset = .Top_Left,
		offsets = GUI.Offset{left = 20, top = 20, right = 220, bottom = bottom},
		min_size = {200, 50},
	}
}

scroll_wheel_test_scroll :: proc(g: ^GUI.GUI) {
	append(&g.events, mouse_move({40, 40}))
	GUI.Handle_Events(g)
	append(&g.events, GUI.Wheel_Event{amount = -1})
	GUI.Handle_Events(g)
}

scroll_wheel_tree_test_make :: proc(t: ^testing.T) -> (g: ^GUI.GUI, container, tree: GUI.Widget_ID) {
	g, container = scroll_wheel_test_make(t)
	tree = GUI.Make_Tree(g, container, GUI.Tree_Opts{
		Base_Opts = GUI.Base_Opts{
			preset = .Top_Left,
			offsets = GUI.Offset{left = 0, top = 0, right = 200, bottom = 50},
			min_size = {200, 50},
		},
	})
	GUI.layout_pass(g)
	return
}

//* == Tree ==

@(test)
test_the_wheel_over_a_tree_with_rows_that_do_not_fit_scrolls_the_tree :: proc(t: ^testing.T) {
	g, container, tree := scroll_wheel_tree_test_make(t)
	defer test_gui_destroy(g)

	for i in 0 ..< 5 {
		GUI.tree_add_item(g, tree, "One", -1)
	}
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.tree_data(g, tree).scroll > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_tree_whose_rows_fit_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container, tree := scroll_wheel_tree_test_make(t)
	defer test_gui_destroy(g)

	GUI.tree_add_item(g, tree, "One", -1)
	GUI.tree_add_item(g, tree, "Two", -1)
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.tree_data(g, tree).scroll, 0.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}

//* == Text box ==

@(test)
test_the_wheel_over_a_text_box_scrolls_the_text_box_and_not_the_container :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	box := GUI.Make_Text_Box(g, container, GUI.Text_Box_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
		text = "one two three four five six seven eight nine ten eleven twelve",
		flags = GUI.Text_Box_Flags{.Multiline},
	})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.text_box_data(g, box).scroll_y > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_text_box_whose_text_fits_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	box := GUI.Make_Text_Box(g, container, GUI.Text_Box_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
		text = "One",
		flags = GUI.Text_Box_Flags{.Multiline},
	})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.text_box_data(g, box).scroll_y, 0.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}

//* == Rich text editor ==

@(test)
test_the_wheel_over_a_rich_text_editor_scrolls_the_editor_and_not_the_container :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	editor := GUI.Make_Rich_Text_Editor(g, container, GUI.Rich_Text_Editor_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
		text = "One\nTwo\nThree\nFour\nFive",
	})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.rich_text_editor_state(g, editor).scroll.y > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_rich_text_editor_whose_text_fits_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	editor := GUI.Make_Rich_Text_Editor(g, container, GUI.Rich_Text_Editor_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
		text = "One",
	})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.rich_text_editor_state(g, editor).scroll.y, 0.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}

//* == Chat input ==

@(test)
test_the_wheel_over_a_chat_input_scrolls_the_talk_and_not_the_container :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	chat := GUI.Make_Chat_Input(g, container, GUI.Chat_Input_Opts{
		Base_Opts = scroll_wheel_test_child_base(120),
	})
	for i in 0 ..< 10 {
		GUI.chat_input_add_line(g, chat, "Ada", "A line of the talk")
	}
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.chat_input_data(g, chat).scroll > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_chat_input_whose_lines_fit_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	chat := GUI.Make_Chat_Input(g, container, GUI.Chat_Input_Opts{
		Base_Opts = scroll_wheel_test_child_base(120),
	})
	GUI.chat_input_add_line(g, chat, "Ada", "A line of the talk")
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.chat_input_data(g, chat).scroll, 0.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}

//* == Data table ==

@(test)
test_the_wheel_over_a_data_table_scrolls_the_table_and_not_the_container :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	table := GUI.Make_Data_Table(g, container, GUI.Data_Table_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
	})
	GUI.data_table_add_column(g, table, "name", 200)
	for i in 0 ..< 20 {
		GUI.data_table_add_row(g, table, {"a row"})
	}
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.data_table_scroll(g, table) > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_data_table_whose_rows_fit_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	table := GUI.Make_Data_Table(g, container, GUI.Data_Table_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
	})
	GUI.data_table_add_column(g, table, "name", 200)
	GUI.data_table_add_row(g, table, {"a row"})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.data_table_scroll(g, table), 0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}

//* == Virtual list ==

@(test)
test_the_wheel_over_a_virtual_list_scrolls_the_list_and_not_the_container :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)

	texts := GUI.List_Texts{}
	defer delete(texts.items)
	defer delete(texts.keys)

	GUI.List_Texts_Add(&texts, "one")
	GUI.List_Texts_Add(&texts, "two")
	GUI.List_Texts_Add(&texts, "three")
	GUI.List_Texts_Add(&texts, "four")
	GUI.List_Texts_Add(&texts, "five")
	GUI.List_Texts_Add(&texts, "six")
	GUI.List_Texts_Add(&texts, "seven")
	GUI.List_Texts_Add(&texts, "eight")

	list := GUI.Make_Virtual_List(g, container, GUI.Virtual_List_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
		source = GUI.List_Source_Texts(&texts),
	})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.virtual_list_data(g, list).list.scroll > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_virtual_list_whose_rows_fit_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)

	texts := GUI.List_Texts{}
	defer delete(texts.items)
	defer delete(texts.keys)
	GUI.List_Texts_Add(&texts, "one")
	GUI.List_Texts_Add(&texts, "two")

	list := GUI.Make_Virtual_List(g, container, GUI.Virtual_List_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
		source = GUI.List_Source_Texts(&texts),
	})
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.virtual_list_data(g, list).list.scroll, 0.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}

//* == File viewer ==

@(test)
test_the_wheel_over_a_file_viewer_scrolls_the_list_and_not_the_container :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	viewer := GUI.Make_File_Viewer(g, container, GUI.File_Viewer_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
	})
	for i in 0 ..< 20 {
		GUI.file_viewer_add_entry(g, viewer, "a file", 1024, false)
	}
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.file_viewer_data(g, viewer).state.scroll > 0, true)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, 0.0)
}

@(test)
test_the_wheel_over_a_file_viewer_whose_files_fit_scrolls_the_container_around_it :: proc(t: ^testing.T) {
	g, container := scroll_wheel_test_make(t)
	defer test_gui_destroy(g)
	viewer := GUI.Make_File_Viewer(g, container, GUI.File_Viewer_Opts{
		Base_Opts = scroll_wheel_test_child_base(70),
	})
	GUI.file_viewer_add_entry(g, viewer, "a file", 1024, false)
	GUI.file_viewer_add_entry(g, viewer, "another file", 1024, false)
	GUI.layout_pass(g)
	scroll_wheel_test_scroll(g)

	testing.expect_value(t, GUI.file_viewer_data(g, viewer).state.scroll, 0.0)
	testing.expect_value(t, GUI.Scroll_Container_Get_Offset(g, container).y, GUI.SCROLL_WHEEL_STEP)
}
