//* == The undo of the text ==
//* Every widget that holds text keeps the changes that were made to it,
//* so that the last change can be taken back with the ctrl key and the
//* Z, and made again with the ctrl key and the Y.
//*
//* The changes are kept as the text of the widget before a change and the
//* text after it, with the caret of both. A widget that is edited says
//* what its text is before it is changed, and says that the change
//* happened after it is done, and the toolkit takes the change back when
//* it is asked to.
//*
//* The widgets do not hold their text in the same way, so the text of a
//* widget is asked for and put back through two functions: the text box
//* and the search field have a caret in their text, the chat field has
//* none, the editor has more than one caret, the field of numbers holds
//* a number and not a text, and the colour picker holds the code of a
//* colour while that code is being typed.

package GUI

import "core:strconv"
import "core:strings"

//* == The state of the text of a widget ==

//* The text of a widget and the place of the caret in it.
Undo_State :: struct {
	text:  string,
	caret: int,
}

//* The text of a widget that holds text, and the place of the caret in
//* it. The text belongs to the widget: it is not copied.
undo_text_of :: proc(g: ^GUI, id: Widget_ID) -> (text: string, caret: int) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		return d.text, d.caret
	case Search_Field_Data:
		return d.text, d.caret
	case Chat_Input_Data:
		return d.text, len(d.text)
	case Rich_Text_Editor_Data:
		if d.state == nil {return}
		place := 0
		if len(d.state.cursors) > 0 {place = d.state.cursors[0].caret}
		return d.state.text, place
	case Color_Picker_Data:
		return d.edit_text, d.caret
	case Number_Input_Data:
		text = number_input_text(g, d.value)
		return text, len(text)
	}
	return
}

//* Puts a text in a widget that holds text, and puts the caret where it
//* was. The text is copied, so the caller keeps its own copy of it.
undo_text_set :: proc(g: ^GUI, id: Widget_ID, text: string, caret: int) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Text_Box_Data:
		text_box_set_text(g, id, text)
		place := snap_offset(text, clamp(caret, 0, len(text)))
		d.caret = place
		d.sel_start = place
		d.sel_end = place
		d.selection.anchor = place
		d.selection.dragging = false
		text_box_scroll_to_caret(g, id)
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	case Search_Field_Data:
		search_field_set_text(g, id, text)
		d.caret = snap_offset(text, clamp(caret, 0, len(text)))
		invalidate(g, id, Dirty_Flags{.Visual})
	case Chat_Input_Data:
		chat_input_set_text(g, id, text)
	case Rich_Text_Editor_Data:
		rich_text_editor_set_text(g, id, text)
		if d.state == nil {return}
		place := snap_offset(text, clamp(caret, 0, len(text)))
		if len(d.state.cursors) > 0 {
			d.state.cursors[0].caret = place
			d.state.cursors[0].sel_start = place
			d.state.cursors[0].sel_end = place
		}
		d.state.selection.anchor = place
		d.state.selection.dragging = false
		invalidate(g, id, Dirty_Flags{.Visual})
	case Color_Picker_Data:
		new_text, err := strings.clone(text)
		if err != nil {return}
		delete(d.edit_text)
		d.edit_text = new_text
		place := snap_offset(text, clamp(caret, 0, len(text)))
		d.caret = place
		d.sel_start = place
		d.sel_end = place
		d.selection.anchor = place
		d.selection.dragging = false
		invalidate(g, id, Dirty_Flags{.Visual})
	case Number_Input_Data:
		value, ok := strconv.parse_f32(text)
		if !ok {return}
		number_input_set(g, id, value)
	}
	caret_reset(g)
}

//* == The changes of a widget ==

//* A copy of the text of a widget, taken before the text is changed. The
//* copy belongs to the caller: it is given to the stack of the widget
//* when the change is done, or given back when the change does not
//* happen.
Undo_Snapshot :: struct {
	state: Undo_State,
	//* Whether there is a copy at all: the text of a widget may be
	//* empty and still be worth remembering.
	taken: bool,
}

//* Takes a copy of the text of a widget, before the text is changed.
undo_snapshot :: proc(g: ^GUI, id: Widget_ID) -> Undo_Snapshot {
	text, caret := undo_text_of(g, id)
	copy_text, err := strings.clone(text)
	if err != nil {return {}}
	return Undo_Snapshot {
		state = Undo_State{text = copy_text, caret = caret},
		taken = true,
	}
}

//* Gives back the copy of a snapshot that was not used.
undo_snapshot_free :: proc(snapshot: ^Undo_Snapshot) {
	if snapshot.taken && len(snapshot.state.text) > 0 {
		delete(snapshot.state.text)
	}
	snapshot.state.text = ""
	snapshot.taken = false
}

//* Remembers the change of the text of a widget, so that it can be taken
//* back. The snapshot is given to the stack of the widget.
undo_commit :: proc(g: ^GUI, id: Widget_ID, snapshot: ^Undo_Snapshot) {
	if snapshot == nil || !snapshot.taken {return}
	stack := undo_stack_of(g, id)
	if stack == nil {
		undo_snapshot_free(snapshot)
		return
	}
	after_text, after_caret := undo_text_of(g, id)
	if after_text == snapshot.state.text {
		//* The text did not change, so there is nothing to remember.
		undo_snapshot_free(snapshot)
		return
	}
	after_copy, err := strings.clone(after_text)
	if err != nil {
		undo_snapshot_free(snapshot)
		return
	}
	undo_push(
		stack,
		Undo_Record {
			before = snapshot.state.text,
			after = after_copy,
			widget = id,
			caret = snapshot.state.caret,
			caret_after = after_caret,
		},
	)
	//* The copy of the text belongs to the record now.
	snapshot.state.text = ""
	snapshot.taken = false
}

//* Takes the last change of a widget back. The text of the widget is the
//* text it had before the change, and the caret is where it was.
text_input_undo :: proc(g: ^GUI, id: Widget_ID) -> bool {
	stack := undo_stack_find(g, id)
	if stack == nil {return false}
	record, ok := undo_step(stack)
	if !ok {return false}
	undo_text_set(g, id, record.before, record.caret)
	return true
}

//* Makes the change of a widget that was taken back happen again.
text_input_redo :: proc(g: ^GUI, id: Widget_ID) -> bool {
	stack := undo_stack_find(g, id)
	if stack == nil {return false}
	record, ok := undo_redo(stack)
	if !ok {return false}
	undo_text_set(g, id, record.after, record.caret_after)
	return true
}

//* Whether a widget has a change that can be taken back.
text_input_can_undo :: proc(g: ^GUI, id: Widget_ID) -> bool {
	stack := undo_stack_find(g, id)
	if stack == nil {return false}
	return undo_can_undo(stack)
}

//* Whether a widget has a change that can be made again.
text_input_can_redo :: proc(g: ^GUI, id: Widget_ID) -> bool {
	stack := undo_stack_find(g, id)
	if stack == nil {return false}
	return undo_can_redo(stack)
}
