package GUI

//* == Undo stack ==

//* One reversible text change, including caret positions.
Undo_Record :: struct {
	before:      string,
	after:       string,
	widget:      Widget_ID,
	caret:       int,
	caret_after: int,
}

Undo_Stack :: struct {
	records: [dynamic]Undo_Record,
	at:      int, // Next record to redo.
	limit:   int,
}

UNDO_LIMIT :: 100

//* Frees the text owned by a record.
undo_record_free :: proc(record: ^Undo_Record) {
	if len(record.before) > 0 {delete(record.before)}
	if len(record.after) > 0 {delete(record.after)}
	record.before = ""
	record.after = ""
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
	return stack.records[stack.at], true
}

//* Moves forward one change.
undo_redo :: proc(stack: ^Undo_Stack) -> (Undo_Record, bool) {
	if !undo_can_redo(stack) {return {}, false}
	record := stack.records[stack.at]
	stack.at += 1
	return record, true
}

//* Frees all records.
undo_clear :: proc(stack: ^Undo_Stack) {
	for &record in stack.records {undo_record_free(&record)}
	delete(stack.records)
	stack.records = nil
	stack.at = 0
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