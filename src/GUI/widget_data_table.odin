//* == The data table ==
//* A table of rows and columns, with a sortable header. Rows come
//* from the program, one at a time, so each frame only pays for the
//* rows on screen. Values are text: a table is for things to be read.

package GUI

import "core:log"
import "core:strings"
import virt "core:mem/virtual"

//* The data of the widget is in widget_data.odin.

Data_Table_Opts :: struct {
	Base_Opts:  Base_Opts,
	//* Where the rows come from. The data stays in the program.
	source:     Table_Source,
	row_height: f32,
	header_height: f32,
}

DATA_TABLE_ROW_HEIGHT :: 24
DATA_TABLE_HEADER_HEIGHT :: 26
DATA_TABLE_WHEEL_LINES :: 3

Make_Data_Table :: proc(g: ^GUI, parent: Widget_ID, opts: Data_Table_Opts) -> Widget_ID {
	kind_register(g, .DataTable, data_table_kind())
	id := New_Widget(g, .DataTable, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	//* The table lives in the GUI arena.
	table, err := virt.new(&g.arena, Data_Table)
	if err != nil {
		log.panicf("data table allocation failed: %v", err)
	}

	row_height := opts.row_height
	if row_height <= 0 {row_height = DATA_TABLE_ROW_HEIGHT}
	header_height := opts.header_height
	if header_height <= 0 {header_height = DATA_TABLE_HEADER_HEIGHT}

	table^ = Data_Table{
		columns = make([dynamic]Data_Table_Column),
		order = make([dynamic]int),
		layout_x = make([dynamic]f32),
		layout_w = make([dynamic]f32),
		sorted_by = -1,
		sort = .None,
		selected_source = -1,
		selected_view = -1,
		selected_column = -1,
		row_height = row_height,
		header_height = header_height,
	}

	//* Use the table's own rows until a source is supplied.
	if opts.source.count != nil {
		table.source = opts.source
	} else {
		table.source = Table_Source_Rows(&table.rows)
	}

	w.data = Data_Table_Data{table = table}
	w.focus_mode = .All
	return id
}

//* The hooks of the widget.
data_table_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_data_table,
		click = click_data_table,
		key = key_data_table,
		pointer = pointer_data_table,
		uses_arrow_keys = true,
		theme_name = "DataTable",
	}
}

data_table_data :: proc(g: ^GUI, id: Widget_ID) -> ^Data_Table_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Data_Table_Data:
		return &d
	}
	return nil
}

//* The table behind the widget, so the program can read and change it.
data_table :: proc(g: ^GUI, id: Widget_ID) -> ^Data_Table {
	d := data_table_data(g, id)
	if d == nil {return nil}
	return d.table
}

//* == The rows ==

//* The program's rows are not copied into the table.
data_table_set_source :: proc(g: ^GUI, id: Widget_ID, source: Table_Source) {
	table := data_table(g, id)
	if table == nil {return}
	table.source = source
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Adds a row to the table's own rows. Values are copied, so the
//* caller's strings may be released afterwards. These rows are hidden
//* while the table uses another source.
data_table_add_row :: proc(g: ^GUI, id: Widget_ID, values: []string) {
	table := data_table(g, id)
	if table == nil {return}
	row := Data_Table_Row{values = make([dynamic]string, 0, len(values))}
	for value in values {
		append(&row.values, strings.clone(value))
	}
	append(&table.rows.items, row)
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Replaces a row in the table's own rows. Values are copied, and the
//* old strings are released first.
data_table_set_row :: proc(g: ^GUI, id: Widget_ID, index: int, values: []string) {
	table := data_table(g, id)
	if table == nil {return}
	if index < 0 || index >= len(table.rows.items) {return}

	row := &table.rows.items[index]
	for &value in row.values {delete(value)}
	clear(&row.values)
	for value in values {
		append(&row.values, strings.clone(value))
	}
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The number of rows shown.
data_table_row_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	table := data_table(g, id)
	if table == nil {return 0}
	data_table_order_sync(table)
	return len(table.order)
}

//* The number of source rows before filtering.
data_table_source_row_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	table := data_table(g, id)
	if table == nil {return 0}
	return table_source_count(table.source)
}

//* The source row corresponding to a displayed row.
data_table_row_source :: proc(g: ^GUI, id: Widget_ID, view: int) -> int {
	table := data_table(g, id)
	if table == nil {return -1}
	data_table_order_sync(table)
	if view < 0 || view >= len(table.order) {return -1}
	return table.order[view]
}

//* The value of a displayed cell.
data_table_cell :: proc(g: ^GUI, id: Widget_ID, view: int, column: int) -> string {
	table := data_table(g, id)
	if table == nil {return ""}
	data_table_order_sync(table)
	if view < 0 || view >= len(table.order) {return ""}
	return data_table_cell_of(table, table.order[view], column)
}

//* Says that the program's data has changed. Rows may have been added,
//* removed, or reordered. The selected row is found again by its key.
data_table_refresh :: proc(g: ^GUI, id: Widget_ID) {
	table := data_table(g, id)
	if table == nil {return}
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* == The columns ==

//* Adds a column. Its width is in logical units.
data_table_add_column :: proc(g: ^GUI, id: Widget_ID, title: string, width: f32) {
	table := data_table(g, id)
	if table == nil {return}
	append(&table.columns, Data_Table_Column{
		title = title,
		width = width,
		size = .Fixed,
		sort = .None,
	})
	table.layout_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The number of columns.
data_table_column_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	table := data_table(g, id)
	if table == nil {return 0}
	return len(table.columns)
}

//* Gets a column.
data_table_column :: proc(g: ^GUI, id: Widget_ID, index: int) -> Data_Table_Column {
	table := data_table(g, id)
	if table == nil {return {}}
	if index < 0 || index >= len(table.columns) {return {}}
	return table.columns[index]
}

//* Replaces a column. Stretch columns share the width left over after
//* fixed columns have been laid out.
data_table_set_column :: proc(g: ^GUI, id: Widget_ID, index: int, column: Data_Table_Column) {
	table := data_table(g, id)
	if table == nil {return}
	if index < 0 || index >= len(table.columns) {return}
	table.columns[index] = column
	table.layout_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The displayed width of a column.
data_table_column_width :: proc(g: ^GUI, id: Widget_ID, index: int) -> f32 {
	table := data_table(g, id)
	if table == nil {return 0}
	w := Widget_Get(g, id)
	if w == nil {return 0}
	content := data_table_content(g, w)
	data_table_layout(table, content.w)
	if index < 0 || index >= len(table.layout_w) {return 0}
	return table.layout_w[index]
}

//* == The order of the rows ==

//* Sorts by a column's requested order, or A to Z when it has none.
data_table_sort_by :: proc(g: ^GUI, id: Widget_ID, column: int) {
	table := data_table(g, id)
	if table == nil {return}
	if column < 0 || column >= len(table.columns) {return}
	direction := Data_Table_Sort.Ascending
	if s := table.columns[column].sort; s != .None {direction = s}
	table.sorted_by = column
	table.sort = direction
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Clicking the same header again reverses the order.
data_table_sort_header :: proc(g: ^GUI, id: Widget_ID, column: int) {
	table := data_table(g, id)
	if table == nil {return}
	if column < 0 || column >= len(table.columns) {return}

	if table.sorted_by == column && table.sort != .None {
		if table.sort == .Ascending {
			table.sort = .Descending
		} else {
			table.sort = .Ascending
		}
		table.order_ok = false
		invalidate(g, id, Dirty_Flags{.Visual})
		return
	}

	data_table_sort_by(g, id, column)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Sorts by a column in the requested direction. .None keeps the
//* source order.
data_table_sort :: proc(g: ^GUI, id: Widget_ID, column: int, direction: Data_Table_Sort) {
	table := data_table(g, id)
	if table == nil {return}
	if column < 0 || column >= len(table.columns) {return}
	table.sorted_by = column
	table.sort = direction
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* == The filter ==

//* Filters are evaluated for every source row when the order is next
//* built. On a large table, changing the filter can be expensive.
data_table_set_filter :: proc(g: ^GUI, id: Widget_ID, text: string) {
	table := data_table(g, id)
	if table == nil {return}
	table.filter_text = text
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Sets the filter called for each source row.
data_table_set_filter_fn :: proc(
	g: ^GUI,
	id: Widget_ID,
	filter: proc(ctx: rawptr, index: int, text: string) -> bool,
) {
	table := data_table(g, id)
	if table == nil {return}
	table.filter = filter
	table.order_ok = false
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The filter text.
data_table_filter_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	table := data_table(g, id)
	if table == nil {return ""}
	return table.filter_text
}

//* == The selected rows ==

//* The selected row as displayed, or -1 when there is none.
data_table_selected_row :: proc(g: ^GUI, id: Widget_ID) -> int {
	table := data_table(g, id)
	if table == nil {return -1}
	data_table_order_sync(table)
	return table.selected_view
}

//* The selected row in the source, or -1 when there is none. This
//* remains stable when rows are sorted or filtered.
data_table_selected_source :: proc(g: ^GUI, id: Widget_ID) -> int {
	table := data_table(g, id)
	if table == nil {return -1}
	data_table_order_sync(table)
	return table.selected_source
}

//* The key of the selected row, or 0 when there is none.
data_table_selected_key :: proc(g: ^GUI, id: Widget_ID) -> u64 {
	table := data_table(g, id)
	if table == nil {return 0}
	return table.selected_key
}

//* The selected column, or -1 when the whole row is selected.
data_table_selected_column :: proc(g: ^GUI, id: Widget_ID) -> int {
	table := data_table(g, id)
	if table == nil {return -1}
	return table.selected_column
}

//* Selects a displayed row and emits the selection signal.
data_table_select_row :: proc(g: ^GUI, id: Widget_ID, view: int) {
	data_table_select_cell(g, id, view, -1)
}

//* Selects a displayed cell and emits the selection signal. Column -1
//* selects the whole row.
data_table_select_cell :: proc(g: ^GUI, id: Widget_ID, view: int, column: int) {
	table := data_table(g, id)
	if table == nil {return}
	data_table_order_sync(table)
	if view < 0 || view >= len(table.order) {return}

	source := table.order[view]
	table.selected_view = view
	table.selected_source = source
	table.selected_key = table_source_key(table.source, source)
	table.selected_column = column
	invalidate(g, id, Dirty_Flags{.Visual})
	signal_item_selected(g, id, view)
}

//* Clears the selection.
data_table_clear_selection :: proc(g: ^GUI, id: Widget_ID) {
	table := data_table(g, id)
	if table == nil {return}
	table.selected_source = -1
	table.selected_view = -1
	table.selected_key = 0
	table.selected_column = -1
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* == The scroll ==

//* The vertical scroll position.
data_table_scroll :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	table := data_table(g, id)
	if table == nil {return 0}
	return table.scroll
}

//* Sets the vertical scroll position, clamped to the table's content.
data_table_set_scroll :: proc(g: ^GUI, id: Widget_ID, scroll: f32) {
	table := data_table(g, id)
	if table == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	table.scroll = scroll
	data_table_scroll_clamp(table, data_table_body_height(g, w))
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The horizontal scroll position.
data_table_h_scroll :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	table := data_table(g, id)
	if table == nil {return 0}
	return table.h_scroll
}

//* Sets the horizontal scroll position, clamped to the column width.
data_table_set_h_scroll :: proc(g: ^GUI, id: Widget_ID, scroll: f32) {
	table := data_table(g, id)
	if table == nil {return}
	w := Widget_Get(g, id)
	if w == nil {return}
	content := data_table_content(g, w)
	data_table_layout(table, content.w)
	table.h_scroll = scroll
	data_table_h_scroll_clamp(table, content)
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* The visible row range: the first row and the row after the last.
data_table_visible_rows :: proc(g: ^GUI, id: Widget_ID) -> Visible_Rows {
	table := data_table(g, id)
	if table == nil {return {}}
	w := Widget_Get(g, id)
	if w == nil {return {}}
	data_table_order_sync(table)
	return visible_rows_fixed(len(table.order), table.scroll, data_table_body_height(g, w), table.row_height)
}

//* == The work of the table ==

//* The space inside the table's content margin.
data_table_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

//* The row viewport below the header.
data_table_body_height :: proc(g: ^GUI, w: ^Widget) -> f32 {
	content := data_table_content(g, w)
	table := data_table(g, w.id)
	height := content.h
	if table != nil {height -= table.header_height}
	if height < 0 {height = 0}
	return height
}

//* Gets a cell value from the source, or an empty string when the
//* column is outside the row's values.
data_table_cell_of :: proc(table: ^Data_Table, row: int, column: int) -> string {
	values := table_source_values(table.source, row)
	if column < 0 || column >= len(values) {return ""}
	return values[column]
}

//* Builds the displayed row order: filter first, then sort.
data_table_order_build :: proc(table: ^Data_Table) {
	if table == nil {return}
	clear(&table.order)
	count := table_source_count(table.source)
	reserve(&table.order, count)

	for i in 0 ..< count {
		if table.filter != nil && !table.filter(table.source.ctx, i, table.filter_text) {continue}
		append(&table.order, i)
	}

	if table.sorted_by >= 0 && table.sorted_by < len(table.columns) {
		data_table_order_sort(table)
	}
	data_table_selection_sync(table)
	table.order_ok = true
}

//* Rebuilds the row order only when it is out of date.
data_table_order_sync :: proc(table: ^Data_Table) {
	if table == nil {return}
	if table.order_ok {return}
	data_table_order_build(table)
}

//* Sorts the displayed source indices.
data_table_order_sort :: proc(table: ^Data_Table) {
	count := len(table.order)
	if count < 2 {return}
	buffer := make([dynamic]int, 0, count)
	defer delete(buffer)
	for i in table.order {append(&buffer, i)}

	merge_sort_table_order(
		table.order[:],
		buffer[:],
		table,
		table.sorted_by,
		table.sort == .Descending,
	)
}

//* Stable merge sort: equal rows retain their source order.
merge_sort_table_order :: proc(
	order: []int,
	buffer: []int,
	table: ^Data_Table,
	column: int,
	descending: bool,
) {
	n := len(order)
	if n < 2 {return}
	width := 1

	for width < n {
		start := 0
		for start < n {
			middle := min(start + width, n)
			end := min(start + width * 2, n)
			left, right, at := start, middle, start

			for left < middle && right < end {
				if data_table_row_before(table, order[left], order[right], column, descending) {
					buffer[at] = order[left]
					left += 1
				} else {
					buffer[at] = order[right]
					right += 1
				}
				at += 1
			}

			for left < middle {
				buffer[at] = order[left]
				left += 1
				at += 1
			}
			for right < end {
				buffer[at] = order[right]
				right += 1
				at += 1
			}
			for i in start ..< end {order[i] = buffer[i]}
			start = end
		}
		width *= 2
	}
}

//* Compares two source rows in the requested direction.
data_table_row_before :: proc(
	table: ^Data_Table,
	a, b: int,
	column: int,
	descending: bool,
) -> bool {
	cmp := data_table_compare(table, column, a, b)
	if descending {return cmp > 0}
	return cmp < 0
}

//* Compares cell values as text, unless the column supplies a
//* comparison function.
data_table_compare :: proc(table: ^Data_Table, column: int, a, b: int) -> int {
	x := data_table_cell_of(table, a, column)
	y := data_table_cell_of(table, b, column)
	if column >= 0 && column < len(table.columns) {
		if compare := table.columns[column].compare; compare != nil {
			return compare(x, y)
		}
	}
	return strings.compare(x, y)
}

//* Restores the selected row by its key after the order changes.
data_table_selection_sync :: proc(table: ^Data_Table) {
	if table.selected_key == 0 {
		table.selected_source = -1
		table.selected_view = -1
		return
	}

	for source, view in table.order {
		if table_source_key(table.source, source) == table.selected_key {
			table.selected_view = view
			table.selected_source = source
			return
		}
	}

	table.selected_source = -1
	table.selected_view = -1
}

//* Lays out fixed columns first, then shares the remaining width
//* between stretch columns.
data_table_layout :: proc(table: ^Data_Table, width: f32) {
	if table.layout_ok && table.layout_width == width {return}
	clear(&table.layout_x)
	clear(&table.layout_w)
	reserve(&table.layout_x, len(table.columns))
	reserve(&table.layout_w, len(table.columns))

	fixed: f32 = 0
	stretch := 0
	for column in table.columns {
		if column.size == .Stretch {
			stretch += 1
		} else {
			fixed += max(column.width, column.min_width)
		}
	}

	left := max(width - fixed, 0)
	share: f32 = 0
	if stretch > 0 {share = left / f32(stretch)}

	x: f32 = 0
	for column in table.columns {
		w := column.width
		if column.size == .Stretch {w = share}
		if w < column.min_width {w = column.min_width}
		append(&table.layout_x, x)
		append(&table.layout_w, w)
		x += w
	}

	table.layout_width = width
	table.layout_ok = true
}

//* Finds the column at a screen position, or -1 when there is none.
data_table_column_at :: proc(table: ^Data_Table, x, origin: f32) -> int {
	position := x - origin + table.h_scroll
	for i in 0 ..< len(table.columns) {
		if position >= table.layout_x[i] && position < table.layout_x[i] + table.layout_w[i] {
			return i
		}
	}
	return -1
}

//* Clamps vertical scrolling to the row content.
data_table_scroll_clamp :: proc(table: ^Data_Table, viewport: f32) {
	if table == nil {return}
	content_height := f32(len(table.order)) * table.row_height
	scroll_clamp(&table.scroll, content_height, viewport)
}

//* The combined width of all columns.
data_table_total_width :: proc(table: ^Data_Table) -> f32 {
	if table == nil {return 0}
	if len(table.layout_x) != len(table.columns) || len(table.columns) == 0 {return 0}
	last := len(table.columns) - 1
	return table.layout_x[last] + table.layout_w[last]
}

//* Clamps horizontal scrolling to the column content.
data_table_h_scroll_clamp :: proc(table: ^Data_Table, content: Rect) {
	if table == nil {return}
	scroll_clamp(&table.h_scroll, data_table_total_width(table), content.w)
}

//* Scrolls the selected row into view.
data_table_scroll_to_selection :: proc(table: ^Data_Table, viewport: f32) {
	if table == nil || table.selected_view < 0 {return}
	top := f32(table.selected_view) * table.row_height
	bottom := top + table.row_height
	if top < table.scroll {
		table.scroll = top
	} else if bottom > table.scroll + viewport {
		table.scroll = bottom - viewport
	}
	data_table_scroll_clamp(table, viewport)
}

//* == The hooks ==

//* Header clicks sort; row clicks select.
click_data_table :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	table := data_table(g, id)
	if table == nil {return}
	data_table_order_sync(table)
	content := data_table_content(g, w)
	data_table_layout(table, content.w)
	header_h := table.header_height

	if g.pointer.y < content.y + header_h {
		column := data_table_column_at(table, g.pointer.x, content.x)
		if column >= 0 {data_table_sort_header(g, id, column)}
		return
	}
	if g.pointer.y < content.y {return}

	view := int((g.pointer.y - content.y - header_h + table.scroll) / table.row_height)
	if view < 0 || view >= len(table.order) {return}
	column := data_table_column_at(table, g.pointer.x, content.x)
	data_table_select_cell(g, id, view, column)
}

//* Arrow keys move the selected row or column.
key_data_table :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	table := data_table(g, id)
	if table == nil {return}
	data_table_order_sync(table)
	rows := len(table.order)
	if rows == 0 {return}

	content := data_table_content(g, w)
	viewport := content.h - table.header_height
	if viewport <= 0 {return}

	ctrl := .Ctrl in e.mods
	page := int(viewport / table.row_height)
	if page < 1 {page = 1}

	#partial switch e.key {
	case .Left:
		column := table.selected_column
		if column < 0 {column = 0} else {column = max(column - 1, 0)}
		data_table_select_cell(g, id, max(table.selected_view, 0), column)
		Event_Handled(g)
		return
	case .Right:
		column := table.selected_column
		if column < 0 {
			column = len(table.columns) - 1
		} else {
			column = min(column + 1, len(table.columns) - 1)
		}
		data_table_select_cell(g, id, max(table.selected_view, 0), column)
		Event_Handled(g)
		return
	}

	view := table.selected_view
	#partial switch e.key {
	case .Up:
		view = table.selected_view - 1
		if ctrl {view = table.selected_view - page}
	case .Down:
		view = table.selected_view + 1
		if ctrl {view = table.selected_view + page}
	case .Home:
		view = 0
	case .End:
		view = rows - 1
	case:
		return
	}

	if table.selected_view < 0 {
		view = 0
		if e.key == .Up || e.key == .End {view = rows - 1}
	}
	view = clamp(view, 0, rows - 1)
	if view == table.selected_view {return}

	data_table_select_cell(g, id, view, table.selected_column)
	data_table_scroll_to_selection(table, viewport)
	Event_Handled(g)
}

//* The wheel scrolls vertically, or horizontally with shift. The
//* table handles it only when it can move, allowing its parent to
//* scroll when the table reaches an edge.
pointer_data_table :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel {return}
	table := data_table(g, id)
	if table == nil {return}

	data_table_order_sync(table)
	content := data_table_content(g, w)
	data_table_layout(table, content.w)
	viewport := content.h - table.header_height
	delta := e.amount * DATA_TABLE_WHEEL_LINES * table.row_height

	if .Shift in g.mods {
		width := data_table_total_width(table)
		if !wheel_scroll(&table.h_scroll, delta, width, content.w) {return}
	} else {
		height := f32(len(table.order)) * table.row_height
		if !wheel_scroll(&table.scroll, delta, height, viewport) {return}
	}

	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

//* Draws the header and only the rows that are visible.
draw_data_table :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	table := data_table(g, id)
	if table == nil {return}
	data_table_order_sync(table)

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	text_style.clip = true
	text_style.valign = .Center

	data_table_layout(table, content.w)
	header_h := table.header_height

	//* The header.
	header := Rect{x = content.x, y = content.y, w = content.w, h = header_h}
	draw_rect(g, header, data_table_header_colour(g, w), 0)

	for column, i in table.columns {
		label := Rect{
			x = content.x + table.layout_x[i] - table.h_scroll,
			y = header.y,
			w = table.layout_w[i],
			h = header.h,
		}
		draw_text(g, text_style, column.title, label, ink)
		if table.sorted_by == i {
			draw_data_table_arrow(g, label, table.sort == .Descending, ink)
		}
	}

	//* The visible rows.
	body := Rect{x = content.x, y = content.y + header_h, w = content.w, h = content.h - header_h}
	if body.h <= 0 {return}

	rows := visible_rows_fixed(len(table.order), table.scroll, body.h, table.row_height)
	if rows.last <= rows.first {return}

	draw_push_clip(g.target, body)
	y := body.y - table.scroll
	for view in rows.first ..< rows.last {
		source := table.order[view]
		row := Rect{x = content.x, y = y, w = content.w, h = table.row_height}
		if view == table.selected_view {
			draw_rect(g, row, virtual_selected_colour(g, w), 0)
		}

		for i in 0 ..< len(table.columns) {
			label := Rect{
				x = content.x + table.layout_x[i] - table.h_scroll,
				y = row.y,
				w = table.layout_w[i],
				h = row.h,
			}
			draw_text(g, text_style, data_table_cell_of(table, source, i), label, ink)
		}
		y += table.row_height
	}
	draw_pop_clip(g.target)
}

//* The header colour, with a panel colour fallback.
data_table_header_colour :: proc(g: ^GUI, w: ^Widget) -> Colour {
	colour := theme_color(g, w, "header_color")
	if colour.a > 0 {return colour}
	return COLLECT_PANEL
}

//* Draws the sort arrow at the right of the sorted column's header.
draw_data_table_arrow :: proc(g: ^GUI, label: Rect, descending: bool, colour: Colour) {
	size := f32(4)
	cx := label.x + label.w - size - 4
	cy := label.y + label.h * 0.5

	points: [][2]f32
	if descending {
		points = [][2]f32{
			{cx - size, cy - size * 0.5},
			{cx + size, cy - size * 0.5},
			{cx, cy + size},
		}
	} else {
		points = [][2]f32{
			{cx - size, cy + size * 0.5},
			{cx + size, cy + size * 0.5},
			{cx, cy - size},
		}
	}
	draw_polygon(g.target, points, colour, g.atlas_texture)
}