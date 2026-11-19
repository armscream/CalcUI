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

package Core
import virt "core:mem/virtual"
import "core:math"
import "core:fmt"
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


Undo_Snapshot :: struct {
	state: Undo_State,
	kind:  Undo_Kind,
	//* Whether there is a copy at all: the text of a widget may be
	//* empty and still be worth remembering.
	taken: bool,
}

//* Takes a copy of the text of a widget, before the text is changed.
undo_snapshot :: proc(g: ^GUI, id: Widget_ID) -> Undo_Snapshot {
	return undo_snapshot_kind(g, id, .Programmatic)
}

undo_snapshot_kind :: proc(g: ^GUI, id: Widget_ID, kind: Undo_Kind) -> Undo_Snapshot {
	text, caret := undo_text_of(g, id)
	copy_text, err := strings.clone(text)
	if err != nil {return {}}
	return Undo_Snapshot {
		state = Undo_State{text = copy_text, caret = caret},
		kind = kind,
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

	kind := snapshot.kind
	if undo_kind_coalesces(kind) &&
	   stack.group_open &&
	   stack.group_kind == kind &&
	   stack.at == len(stack.records) &&
	   len(stack.records) > 0 {
		previous := &stack.records[len(stack.records) - 1]
		if snapshot.state.caret == previous.caret_after &&
		   snapshot.state.text == previous.after {
			after_copy, err := strings.clone(after_text)
			if err != nil {
				undo_snapshot_free(snapshot)
				return
			}
			if len(previous.after) > 0 {delete(previous.after)}
			previous.after = after_copy
			previous.caret_after = after_caret
			previous.kind = kind
			undo_snapshot_free(snapshot)
			return
		}
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
			kind = kind,
		},
	)
	stack.group_kind = kind
	stack.group_open = undo_kind_coalesces(kind)
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

number_input_data :: proc(g: ^GUI, id: Widget_ID) -> ^Number_Input_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Number_Input_Data:
		return &d
	}
	return nil
}

//* Clamps the value and emits value-changed when it changes.
number_input_set :: proc(g: ^GUI, id: Widget_ID, value: f32) {
	d := number_input_data(g, id)
	if d == nil {return}
	new_value := clamp(value, d.min, d.max)
	if d.value == new_value {return}
	d.value = new_value
	signal_value_changed(g, id, new_value)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Formats whole numbers without decimals.
number_input_text :: proc(g: ^GUI, value: f32) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	if value == math.floor(value) && abs(value) < 1e9 {
		return fmt.aprintf("%d", int(value), allocator = allocator)
	}
	return fmt.aprintf("%.2f", value, allocator = allocator)
}

search_field_data :: proc(g: ^GUI, id: Widget_ID) -> ^Search_Field_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Search_Field_Data:
		return &d
	}
	return nil
}

//* Sets the text and emits the text-changed signal.
search_field_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := search_field_data(g, id)
	if d == nil {return}
	if d.text == text {return}
	delete(d.text)
	d.text = strings.clone(text)
	d.caret = len(d.text)
	signal_text_changed(g, id, d.text)
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

chat_input_data :: proc(g: ^GUI, id: Widget_ID) -> ^Chat_Input_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Chat_Input_Data:
		return &d
	}
	return nil
}

chat_input_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := chat_input_data(g, id)
	if d == nil { return }
	new_text := strings.clone(text)
	delete(d.text)
	d.text = new_text
	invalidate(g, id, Dirty_Flags{.Visual})
}

rich_text_editor_data :: proc(g: ^GUI, id: Widget_ID) -> ^Rich_Text_Editor_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Rich_Text_Editor_Data:
		return &d
	}
	return nil
}

rich_text_editor_state :: proc(g: ^GUI, id: Widget_ID) -> ^Rich_Text_Editor_State {
	data := rich_text_editor_data(g, id)
	if data == nil {return nil}
	return data.state
}


rich_text_editor_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	state := rich_text_editor_state(g, id)
	if state == nil || state.text == text {return}

	new_text, err := strings.clone(text)
	if err != nil {return}
	delete(state.text)
	state.text = new_text

	end := len(state.text)
	clear(&state.cursors)
	append(&state.cursors, Rich_Cursor{caret = end, sel_start = end, sel_end = end})
	state.selection.anchor = end
	state.selection.mode = .Character
	state.selection.dragging = false
	signal_text_changed(g, id, state.text)
	invalidate(g, id, Dirty_Flags{.Visual})
}

rich_text_editor_click :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, p: Vec2, clicks: int) {
	state := rich_text_editor_state(g, id)
	if state == nil {return}
	undo_group_break(g, id)

	offset := rich_text_editor_offset_at_local(g, id, w, text_box_local(w, p))
	action := text_click_action(state.text, &state.selection, offset, clicks)
	for &cursor in state.cursors {
		text_select_apply(
			state.text, &cursor.caret, &cursor.sel_start, &cursor.sel_end,
			&state.selection, action, offset,
		)
	}
	caret_reset(g)
	invalidate(g, id, Dirty_Flags{.Visual})
}


rich_text_editor_text_style :: proc(
	g: ^GUI,
	w: ^Widget,
	state: ^Rich_Text_Editor_State,
) -> Text_Style {
	ts := resolved_style(g, w).text
	ts.wrap = state.wrap ? .Word : .Off
	ts.transform = .None
	ts.overrun = .None
	return ts
}

rich_text_editor_offset_at_local :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	local: Vec2,
) -> int {
	state := rich_text_editor_state(g, id)
	if state == nil {return 0}

	content := content_rect(g, w)
	ts := rich_text_editor_text_style(g, w, state)
	lines := text_lines(g, ts, state.text, content.w)
	box := Rect{
		x = content.x - state.scroll.x,
		y = content.y - state.scroll.y,
		w = content.w,
		h = content.h,
	}
	p := Vec2{local.x + w.rect.x, local.y + w.rect.y}
	return text_offset_at(g, Font_Of(g, w), box, ts, lines[:], state.text, p)
}


//* == Undo stack ==

Undo_Kind :: enum u8 {
	Programmatic,
	Typing,
	Backspace,
	Delete,
	Replace,
	Paste,
}

//* One reversible text change, including caret positions.
Undo_Record :: struct {
	before:      string,
	after:       string,
	widget:      Widget_ID,
	caret:       int,
	caret_after: int,
	kind:        Undo_Kind,
}

Undo_Stack :: struct {
	records:    [dynamic]Undo_Record,
	at:         int, // Next record to redo.
	limit:      int,
	group_kind: Undo_Kind,
	group_open: bool,
}

UNDO_LIMIT :: 100

//* Frees the text owned by a record.
undo_record_free :: proc(record: ^Undo_Record) {
	if len(record.before) > 0 {delete(record.before)}
	if len(record.after) > 0 {delete(record.after)}
	record.before = ""
	record.after = ""
}

undo_kind_coalesces :: proc(kind: Undo_Kind) -> bool {
	#partial switch kind {
	case .Typing, .Backspace, .Delete:
		return true
	}
	return false
}

//* Adds a change, discarding any redo history.
undo_push :: proc(stack: ^Undo_Stack, record: Undo_Record) {
	if stack.at < len(stack.records) {
		for i in stack.at ..< len(stack.records) {
			undo_record_free(&stack.records[i])
		}
		resize(&stack.records, stack.at)
	}
	append(&stack.records, record)
	stack.at = len(stack.records)
	stack.group_kind = .Programmatic
	stack.group_open = false

	if stack.limit > 0 && len(stack.records) > stack.limit {
		undo_record_free(&stack.records[0])
		ordered_remove(&stack.records, 0)
		stack.at = len(stack.records)
	}
}

undo_can_undo :: proc(stack: ^Undo_Stack) -> bool {
	return stack.at > 0
}

undo_can_redo :: proc(stack: ^Undo_Stack) -> bool {
	return stack.at < len(stack.records)
}

//* Moves back one change.
undo_step :: proc(stack: ^Undo_Stack) -> (Undo_Record, bool) {
	if !undo_can_undo(stack) {return {}, false}
	stack.at -= 1
	stack.group_kind = .Programmatic
	stack.group_open = false
	return stack.records[stack.at], true
}

//* Moves forward one change.
undo_redo :: proc(stack: ^Undo_Stack) -> (Undo_Record, bool) {
	if !undo_can_redo(stack) {return {}, false}
	record := stack.records[stack.at]
	stack.at += 1
	stack.group_kind = .Programmatic
	stack.group_open = false
	return record, true
}

//* Frees all records.
undo_clear :: proc(stack: ^Undo_Stack) {
	for &record in stack.records {undo_record_free(&record)}
	delete(stack.records)
	stack.records = nil
	stack.at = 0
	stack.group_kind = .Programmatic
	stack.group_open = false
}

//* == Per-widget stacks ==

//* Gets or creates a widget's undo stack.
undo_stack_of :: proc(g: ^GUI, id: Widget_ID) -> ^Undo_Stack {
	if g == nil {return nil}
	if g.undo_stacks == nil {
		g.undo_stacks = make(map[Widget_ID]^Undo_Stack)
	}
	stack, ok := g.undo_stacks[id]
	if !ok {
		stack = new(Undo_Stack)
		stack.limit = UNDO_LIMIT
		g.undo_stacks[id] = stack
	}
	return stack
}

//* Finds a widget's undo stack without creating one.
undo_stack_find :: proc(g: ^GUI, id: Widget_ID) -> ^Undo_Stack {
	if g == nil || g.undo_stacks == nil {return nil}
	stack, ok := g.undo_stacks[id]
	if !ok {return nil}
	return stack
}

undo_group_break :: proc(g: ^GUI, id: Widget_ID) {
	stack := undo_stack_find(g, id)
	if stack == nil {return}
	stack.group_kind = .Programmatic
	stack.group_open = false
}

//* Frees and removes a widget's undo stack.
undo_forget :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil || g.undo_stacks == nil {return}
	stack, ok := g.undo_stacks[id]
	if !ok {return}
	delete_key(&g.undo_stacks, id)
	undo_clear(stack)
	free(cast(rawptr)stack)
}

//* Frees all widget undo stacks.
undo_destroy :: proc(g: ^GUI) {
	if g == nil || g.undo_stacks == nil {return}
	for _, stack in g.undo_stacks {
		undo_clear(stack)
		free(cast(rawptr)stack)
	}
	delete(g.undo_stacks)
	g.undo_stacks = nil
}
