//* == The undo stack ==
//* A widget that can be edited keeps its changes on a stack, so that
//* the last one can be taken back. The stack belongs to the widget,
//* because two text fields have two histories.

package GUI

//* One change that can be taken back.
Undo_Record :: struct {
	//* What was there before the change.
	before: string,
	//* What there is now.
	after:  string,
	//* The widget the change belongs to.
	widget: Widget_ID,
	//* Where the caret was before the change.
	caret:  int,
}

//* The history of a widget.
Undo_Stack :: struct {
	records: [dynamic]Undo_Record,
	//* The record that is looked at now. Everything after it has been
	//* taken back.
	at:      int,
	//* How many records the stack holds at most.
	limit:   int,
}

//* The number of changes that are kept.
UNDO_LIMIT :: 100

//* Remembers a change, so that it can be taken back.
undo_push :: proc(stack: ^Undo_Stack, record: Undo_Record) {
	//* Everything that was taken back is forgotten when a new change
	//* is made.
	if stack.at < len(stack.records) {
		resize(&stack.records, stack.at)
	}
	append(&stack.records, record)
	stack.at = len(stack.records)
	if stack.limit > 0 && len(stack.records) > stack.limit {
		//* The oldest change is dropped.
		ordered_remove(&stack.records, 0)
		stack.at = len(stack.records)
	}
}

//* True when there is a change that can be taken back.
undo_can_undo :: proc(stack: ^Undo_Stack) -> bool {
	return stack.at > 0
}

//* True when there is a change that can be made again.
undo_can_redo :: proc(stack: ^Undo_Stack) -> bool {
	return stack.at < len(stack.records)
}

//* Takes the last change back. The record that comes back says what
//* the text was before the change and what it is now.
undo_step :: proc(stack: ^Undo_Stack) -> (Undo_Record, bool) {
	if !undo_can_undo(stack) {return {}, false}
	stack.at -= 1
	record := stack.records[stack.at]
	return record, true
}

//* Makes a change that was taken back happen again.
undo_redo :: proc(stack: ^Undo_Stack) -> (Undo_Record, bool) {
	if !undo_can_redo(stack) {return {}, false}
	record := stack.records[stack.at]
	stack.at += 1
	return record, true
}

//* Forgets everything.
undo_clear :: proc(stack: ^Undo_Stack) {
	clear(&stack.records)
	stack.at = 0
}
