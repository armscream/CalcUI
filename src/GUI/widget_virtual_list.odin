package GUI

import "core:log"
import virt "core:mem/virtual"

Virtual_List_Opts :: struct {
	Base_Opts: Base_Opts,
	source:     List_Source,
	row_height: f32,
}

VIRTUAL_LIST_ROW_HEIGHT :: 22
VIRTUAL_LIST_WHEEL_LINES :: 3

Make_Virtual_List :: proc(g: ^GUI, parent: Widget_ID, opts: Virtual_List_Opts) -> Widget_ID {
	kind_register(g, .VirtualList, virtual_list_kind())
	id := New_Widget(g, .VirtualList, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	list, err := virt.new(&g.arena, Virtual_List)
	if err != nil {
		log.panicf("virtual list allocation failed: %v", err)
	}
	row_height := opts.row_height
	if row_height <= 0 {row_height = VIRTUAL_LIST_ROW_HEIGHT}
	list^ = Virtual_List {
		source = opts.source,
		row_height = row_height,
		cursor = -1,
		count = -1,
	}

	w.data = Virtual_List_Data {list = list}
	w.focus_mode = .All
	return id
}

virtual_list_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_virtual_list,
		click = click_virtual_list,
		key = key_virtual_list,
		pointer = pointer_virtual_list,
		uses_arrow_keys = true,
		theme_name = "VirtualList",
	}
}

virtual_list_data :: proc(g: ^GUI, id: Widget_ID) -> ^Virtual_List_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Virtual_List_Data:
		return &d
	}
	return nil
}

//* Returns the list state for reading or modification.
virtual_list :: proc(g: ^GUI, id: Widget_ID) -> ^Virtual_List {
	d := virtual_list_data(g, id)
	if d == nil {return nil}
	return d.list
}

//* Returns the number of rows.
virtual_list_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	list := virtual_list(g, id)
	if list == nil {return 0}
	virtual_list_sync(list)
	return list.count
}

//* Returns the default row height.
virtual_list_row_height :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	list := virtual_list(g, id)
	if list == nil {return VIRTUAL_LIST_ROW_HEIGHT}
	return list.row_height
}

//* Sets the row height. Zero or less restores the default.
virtual_list_set_row_height :: proc(g: ^GUI, id: Widget_ID, height: f32) {
	list := virtual_list(g, id)
	if list == nil {return}
	new_height := height
	if new_height <= 0 {new_height = VIRTUAL_LIST_ROW_HEIGHT}
	list.row_height = new_height
	list.offsets_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Returns the current scroll offset.
virtual_list_scroll :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	list := virtual_list(g, id)
	if list == nil {return 0}
	return list.scroll
}

//* Sets the scroll offset, clamped to the content bounds.
virtual_list_set_scroll :: proc(g: ^GUI, id: Widget_ID, scroll: f32) {
	list := virtual_list(g, id)
	if list == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	list.scroll = scroll
	content := virtual_list_content(g, w)
	virtual_list_scroll_clamp(list, content.h)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Returns the index of the top visible row.
virtual_list_first_row :: proc(g: ^GUI, id: Widget_ID) -> int {
	list := virtual_list(g, id)
	if list == nil {return 0}
	virtual_list_sync(list)
	return virtual_list_row_at(list, list.scroll)
}

//* Scrolls to the specified row.
virtual_list_set_first_row :: proc(g: ^GUI, id: Widget_ID, first: int) {
	list := virtual_list(g, id)
	if list == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	virtual_list_sync(list)
	row := first
	if row < 0 {row = 0}
	if row >= list.count {row = max(list.count - 1, 0)}
	list.scroll = virtual_list_row_top(list, row)
	content := virtual_list_content(g, w)
	virtual_list_scroll_clamp(list, content.h)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Returns the range of visible rows as [first, last).
virtual_list_visible_rows :: proc(g: ^GUI, id: Widget_ID) -> Visible_Rows {
	list := virtual_list(g, id)
	if list == nil {return {}}
	w := Widget_Get(g, id)
	if w == nil {return {}}
	virtual_list_sync(list)
	content := virtual_list_content(g, w)
	return virtual_list_visible(list, content.h)
}

//* Refreshes the source data and restores picks by row key.
virtual_list_refresh :: proc(g: ^GUI, id: Widget_ID) {
	list := virtual_list(g, id)
	if list == nil {return}
	list.resync = true
	list.offsets_ok = false
	virtual_list_sync(list)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Returns a row's stable key.
virtual_list_key :: proc(g: ^GUI, id: Widget_ID, index: int) -> u64 {
	list := virtual_list(g, id)
	if list == nil {return 0}
	virtual_list_sync(list)
	if index < 0 || index >= list.count {return 0}
	return list_source_key(list.source, index)
}

//* Returns the selected row, or -1 when none is selected.
virtual_list_selected :: proc(g: ^GUI, id: Widget_ID) -> int {
	list := virtual_list(g, id)
	if list == nil {return -1}
	virtual_list_sync(list)
	if len(list.selected) == 0 {return -1}
	return list.selected[0].index
}

//* Reports whether a row is selected.
virtual_list_is_picked :: proc(g: ^GUI, id: Widget_ID, index: int) -> bool {
	list := virtual_list(g, id)
	if list == nil {return false}
	virtual_list_sync(list)
	if index < 0 || index >= list.count {return false}
	return virtual_list_is_selected(list, index)
}

//* Selects one row, replacing the current selection.
virtual_list_select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	list := virtual_list(g, id)
	if list == nil {return}
	virtual_list_sync(list)
	if index < 0 || index >= list.count {return}
	key := list_source_key(list.source, index)
	clear(&list.selected)
	append(&list.selected, Virtual_List_Pick{key = key, index = index})
	list.cursor = index
	list.cursor_key = key
	invalidate(g, id, Dirty_Flags{.Visual})
	signal_item_selected(g, id, index)
}

//* Toggles a row's selection.
virtual_list_toggle :: proc(g: ^GUI, id: Widget_ID, index: int) {
	list := virtual_list(g, id)
	if list == nil {return}
	virtual_list_sync(list)
	if index < 0 || index >= list.count {return}
	key := list_source_key(list.source, index)
	for i in 0 ..< len(list.selected) {
		if list.selected[i].key == key {
			ordered_remove(&list.selected, i)
			list.cursor = index
			list.cursor_key = key
			invalidate(g, id, Dirty_Flags{.Visual})
			signal_item_selected(g, id, index)
			return
		}
	}
	append(&list.selected, Virtual_List_Pick{key = key, index = index})
	list.cursor = index
	list.cursor_key = key
	invalidate(g, id, Dirty_Flags{.Visual})
	signal_item_selected(g, id, index)
}

//* Clears the selection.
virtual_list_clear_selection :: proc(g: ^GUI, id: Widget_ID) {
	list := virtual_list(g, id)
	if list == nil {return}
	if len(list.selected) == 0 {return}
	clear(&list.selected)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Synchronizes row counts and restores picks after a source refresh.
virtual_list_sync :: proc(list: ^Virtual_List) {
	if list == nil {return}
	count := list_source_count(list.source)
	if count != list.count {
		list.count = count
		list.offsets_ok = false
		if list.cursor >= count {list.cursor = count - 1}
		for i in 0 ..< len(list.selected) {
			if list.selected[i].index >= count {list.selected[i].index = -1}
		}
	}
	if !list.resync {return}
	list.resync = false
	list.cursor = virtual_list_find_key(list, list.cursor_key)
	for i in 0 ..< len(list.selected) {
		list.selected[i].index = virtual_list_find_key(list, list.selected[i].key)
	}
}

//* Finds a row by key, or returns -1.
virtual_list_find_key :: proc(list: ^Virtual_List, key: u64) -> int {
	if list == nil || key == 0 {return -1}
	if list.source.key == nil {
		index := int(key) - 1
		if index < 0 || index >= list.count {return -1}
		return index
	}
	for i in 0 ..< list.count {
		if list_source_key(list.source, i) == key {return i}
	}
	return -1
}

virtual_list_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

//* Returns the total height of all rows.
virtual_list_content_height :: proc(list: ^Virtual_List) -> f32 {
	if list == nil {return 0}
	virtual_list_sync(list)
	if list.count <= 0 {return 0}
	if list.source.height != nil {
		if !list.offsets_ok {virtual_list_offsets_build(list)}
		return list.offsets[list.count]
	}
	return f32(list.count) * list.row_height
}

//* Returns the vertical offset of a row.
virtual_list_row_top :: proc(list: ^Virtual_List, index: int) -> f32 {
	if list == nil || index <= 0 {return 0}
	if list.source.height != nil {
		if !list.offsets_ok {virtual_list_offsets_build(list)}
		if index < len(list.offsets) {return list.offsets[index]}
		return list.offsets[len(list.offsets) - 1]
	}
	return f32(index) * list.row_height
}

//* Returns a row's height.
virtual_list_row_size :: proc(list: ^Virtual_List, index: int) -> f32 {
	if list == nil {return VIRTUAL_LIST_ROW_HEIGHT}
	return list_source_height(list.source, index, list.row_height)
}

//* Builds cumulative row offsets for variable-height rows.
virtual_list_offsets_build :: proc(list: ^Virtual_List) {
	clear(&list.offsets)
	reserve(&list.offsets, list.count + 1)
	total: f32 = 0
	for i in 0 ..< list.count {
		append(&list.offsets, total)
		total += list_source_height(list.source, i, list.row_height)
	}
	append(&list.offsets, total)
	list.offsets_ok = true
}

//* Finds the row at a vertical offset.
virtual_list_row_at :: proc(list: ^Virtual_List, offset: f32) -> int {
	if list == nil || list.count <= 0 {return -1}
	if list.source.height == nil {
		index := int(offset / list.row_height)
		if index < 0 {index = 0}
		if index >= list.count {index = list.count - 1}
		return index
	}
	if !list.offsets_ok {virtual_list_offsets_build(list)}
	low := 0
	high := list.count - 1
	for low < high {
		middle := (low + high + 1) / 2
		if list.offsets[middle] <= offset {
			low = middle
		} else {
			high = middle - 1
		}
	}
	return low
}

//* Returns the visible row range.
virtual_list_visible :: proc(list: ^Virtual_List, viewport: f32) -> Visible_Rows {
	if list == nil || list.count <= 0 {return {}}
	if list.source.height == nil {
		return visible_rows_fixed(list.count, list.scroll, viewport, list.row_height)
	}
	if !list.offsets_ok {virtual_list_offsets_build(list)}
	first := virtual_list_row_at(list, list.scroll)
	if first < 0 {first = 0}
	bottom := list.scroll + viewport
	last := first
	for last < list.count && list.offsets[last] < bottom {
		last += 1
	}
	return {first = first, last = min(list.count, last)}
}

//* Clamps scrolling to the content bounds.
virtual_list_scroll_clamp :: proc(list: ^Virtual_List, viewport: f32) {
	if list == nil {return}
	scroll_clamp(&list.scroll, virtual_list_content_height(list), viewport)
}

//* Scrolls the cursor row into view.
virtual_list_scroll_to_cursor :: proc(list: ^Virtual_List, viewport: f32) {
	if list == nil || list.cursor < 0 {return}
	top := virtual_list_row_top(list, list.cursor)
	bottom := top + virtual_list_row_size(list, list.cursor)
	if top < list.scroll {
		list.scroll = top
	} else if bottom > list.scroll + viewport {
		list.scroll = bottom - viewport
	}
	virtual_list_scroll_clamp(list, viewport)
}

//* Reports whether a row is selected.
virtual_list_is_selected :: proc(list: ^Virtual_List, index: int) -> bool {
	if list == nil || len(list.selected) == 0 {return false}
	key := list_source_key(list.source, index)
	for pick in list.selected {
		if pick.key == key {return true}
	}
	return false
}

click_virtual_list :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := virtual_list_data(g, id)
	if d == nil {return}
	list := d.list
	if list == nil {return}
	virtual_list_sync(list)
	if list.count <= 0 {return}
	content := virtual_list_content(g, w)
	if !rect_contains(content, g.pointer.x, g.pointer.y) {return}
	index := virtual_list_row_at(list, g.pointer.y - content.y + list.scroll)
	if index < 0 || index >= list.count {return}
	virtual_list_toggle(g, id, index)
}

key_virtual_list :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := virtual_list_data(g, id)
	if d == nil {return}
	list := d.list
	if list == nil {return}
	virtual_list_sync(list)
	if list.count <= 0 {return}

	content := virtual_list_content(g, w)
	page := int(content.h / list.row_height)
	if page < 1 {page = 1}
	shift := .Shift in e.mods
	ctrl := .Ctrl in e.mods

	target := list.cursor
	#partial switch e.key {
	case .Up:
		target = list.cursor - 1
		if ctrl {target = list.cursor - page}
	case .Down:
		target = list.cursor + 1
		if ctrl {target = list.cursor + page}
	case .Home:
		target = 0
	case .End:
		target = list.count - 1
	case:
		return
	}
	if list.cursor < 0 {
		target = 0
		if e.key == .Up || e.key == .End {target = list.count - 1}
	}
	if target < 0 {target = 0}
	if target >= list.count {target = list.count - 1}
	if target == list.cursor {return}

	key := list_source_key(list.source, target)
	list.cursor = target
	list.cursor_key = key
	if shift {
		virtual_list_add_pick(list, target, key)
	} else {
		clear(&list.selected)
		append(&list.selected, Virtual_List_Pick{key = key, index = target})
	}
	virtual_list_scroll_to_cursor(list, content.h)
	invalidate(g, id, Dirty_Flags{.Visual})
	signal_item_selected(g, id, target)
	Event_Handled(g)
}

//* Adds a row to the selection if it is not already selected.
virtual_list_add_pick :: proc(list: ^Virtual_List, index: int, key: u64) {
	for pick in list.selected {
		if pick.key == key {return}
	}
	append(&list.selected, Virtual_List_Pick{key = key, index = index})
}

//* Scrolls only when the list has room, allowing parent scroll containers
//* to handle wheel input when the list is already at its limits.
pointer_virtual_list :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel {return}
	d := virtual_list_data(g, id)
	if d == nil {return}
	list := d.list
	if list == nil {return}
	content := virtual_list_content(g, w)
	step := list.row_height * VIRTUAL_LIST_WHEEL_LINES
	if step <= 0 {step = VIRTUAL_LIST_ROW_HEIGHT}
	if !wheel_scroll(&list.scroll, e.amount * step, virtual_list_content_height(list), content.h) {return}
	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

draw_virtual_list :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := virtual_list_data(g, id)
	if d == nil {return}
	list := d.list
	if list == nil {return}
	virtual_list_sync(list)
	if list.count <= 0 {return}

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	text_style.clip = true
	text_style.valign = .Center

	rows := virtual_list_visible(list, content.h)
	if rows.last <= rows.first {return}

	draw_push_clip(g.target, content)
	for index in rows.first ..< rows.last {
		top := virtual_list_row_top(list, index) - list.scroll
		row := Rect {
			x = content.x,
			y = content.y + top,
			w = content.w,
			h = virtual_list_row_size(list, index),
		}
		if virtual_list_is_selected(list, index) {
			draw_rect(g, row, virtual_selected_colour(g, w), 0)
		}
		label := Rect {
			x = row.x + 4,
			y = row.y,
			w = row.w - 8,
			h = row.h,
		}
		draw_text(g, text_style, list_source_text(list.source, index), label, ink)
	}
	draw_pop_clip(g.target)
}