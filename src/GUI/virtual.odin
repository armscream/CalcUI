//* == The virtual view ==
//* The parts that the virtual list and the data table share: where the
//* rows come from, which of them are on the screen, and how a row is
//* found. The data stays in the program: the widget asks for one row
//* at a time, so a frame costs the rows that are on the screen and not
//* the rows that are not.

package GUI

import "core:math"
import "core:strings"

//* == The sources ==

//* Where the rows of a list come from.
List_Source :: struct {
	//* How many rows there are.
	count: proc(ctx: rawptr) -> int,
	//* The text of a row. The text is used until the frame is over, so
	//* it may point into the data of the program.
	text: proc(ctx: rawptr, index: int) -> string,
	//* The key of a row: the thing that stays the same when the rows
	//: are put in another order. When there is no key, the number of
	//: the row is its key.
	key: proc(ctx: rawptr, index: int) -> u64,
	//* The height of a row, for a list whose rows are not all the same
	//: height. When there is none, every row has the height of the
	//: list.
	height: proc(ctx: rawptr, index: int) -> f32,
	//* The data of the program. It is given to every call.
	ctx: rawptr,
}

//* Where the rows of a table come from.
Table_Source :: struct {
	//* How many rows there are.
	count: proc(ctx: rawptr) -> int,
	//* The values of a row. The values are used until the frame is
	//: over, so they may point into the data of the program.
	values: proc(ctx: rawptr, index: int) -> []string,
	//* The key of a row: the thing that stays the same when the rows
	//: are put in another order. When there is no key, the number of
	//: the row is its key.
	key: proc(ctx: rawptr, index: int) -> u64,
	//* The data of the program. It is given to every call.
	ctx: rawptr,
}

//* The rows of a list, for the lists whose rows are texts.
List_Texts :: struct {
	items: [dynamic]string,
	//* The keys of the rows, when the rows have keys of their own.
	keys:  [dynamic]u64,
}

//* The rows of a table, for the tables whose rows the program keeps.
Table_Rows :: struct {
	items: [dynamic]Data_Table_Row,
}

//* Adds a row to the rows of the program. The values are copied, so
//* the strings of the caller may go away afterwards.
Table_Rows_Add :: proc(rows: ^Table_Rows, values: []string, key: u64 = 0) {
	if rows == nil {return}
	row := Data_Table_Row{values = make([dynamic]string, 0, len(values)), key = key}
	for value in values {
		append(&row.values, strings.clone(value))
	}
	append(&rows.items, row)
}

//* Adds a row to the rows of the program. A key of 0 means that the row
//* has no key of its own, and its number is its key.
List_Texts_Add :: proc(texts: ^List_Texts, text: string, key: u64 = 0) {
	if texts == nil {return}
	append(&texts.items, text)
	append(&texts.keys, key)
}

//* == The sources that are made for you ==

//* Makes a source of a list of texts. The texts are not copied, so they
//* must stay as long as the source is used.
List_Source_Texts :: proc(texts: ^List_Texts) -> List_Source {
	return List_Source {
		count = proc(ctx: rawptr) -> int {
			return len((cast(^List_Texts)ctx).items)
		},
		text = proc(ctx: rawptr, index: int) -> string {
			items := (cast(^List_Texts)ctx).items
			if index < 0 || index >= len(items) {return ""}
			return items[index]
		},
		key = proc(ctx: rawptr, index: int) -> u64 {
			source := cast(^List_Texts)ctx
			if index < 0 || index >= len(source.keys) {return 0}
			return source.keys[index]
		},
		ctx = cast(rawptr)texts,
	}
}

//* Makes a source of a table of rows. The rows are not copied, so they
//* must stay as long as the source is used.
Table_Source_Rows :: proc(rows: ^Table_Rows) -> Table_Source {
	return Table_Source {
		count = proc(ctx: rawptr) -> int {
			return len((cast(^Table_Rows)ctx).items)
		},
		values = proc(ctx: rawptr, index: int) -> []string {
			items := (cast(^Table_Rows)ctx).items
			if index < 0 || index >= len(items) {return nil}
			return items[index].values[:]
		},
		key = proc(ctx: rawptr, index: int) -> u64 {
			items := (cast(^Table_Rows)ctx).items
			if index < 0 || index >= len(items) {return 0}
			return items[index].key
		},
		ctx = cast(rawptr)rows,
	}
}

//* == Asking a source ==

//* The number of rows of a source.
list_source_count :: proc(source: List_Source) -> int {
	if source.count == nil {return 0}
	count := source.count(source.ctx)
	if count < 0 {return 0}
	return count
}

//* The text of a row of a source.
list_source_text :: proc(source: List_Source, index: int) -> string {
	if source.text == nil {return ""}
	return source.text(source.ctx, index)
}

//* The key of a row of a source. A source without keys gives every row
//* its own number as its key, so that the rows can still be picked.
list_source_key :: proc(source: List_Source, index: int) -> u64 {
	if source.key != nil {
		key := source.key(source.ctx, index)
		if key != 0 {return key}
	}
	return u64(index) + 1
}

//* The height of a row of a source. The height of the list is used when
//* the source does not give one.
list_source_height :: proc(source: List_Source, index: int, fallback: f32) -> f32 {
	if source.height == nil {return fallback}
	height := source.height(source.ctx, index)
	if height <= 0 {return fallback}
	return height
}

//* The number of rows of a source.
table_source_count :: proc(source: Table_Source) -> int {
	if source.count == nil {return 0}
	count := source.count(source.ctx)
	if count < 0 {return 0}
	return count
}

//* The values of a row of a source.
table_source_values :: proc(source: Table_Source, index: int) -> []string {
	if source.values == nil {return nil}
	return source.values(source.ctx, index)
}

//* The key of a row of a source. A source without keys gives every row
//* its own number as its key, so that the rows can still be picked.
table_source_key :: proc(source: Table_Source, index: int) -> u64 {
	if source.key != nil {
		key := source.key(source.ctx, index)
		if key != 0 {return key}
	}
	return u64(index) + 1
}

//* == The rows that are on the screen ==

//* The rows that are on the screen: the first row that is not above the
//* screen, and the row after the last one that is on it.
Visible_Rows :: struct {
	first: int,
	last: int,
}

//* How many rows of a height fit on a screen of a height.
visible_row_count :: proc(viewport, row_height: f32) -> int {
	if row_height <= 0 {return 0}
	rows := int(math.ceil(viewport / row_height))
	if rows < 1 {rows = 1}
	return rows + 1
}

//* The rows that are on the screen when every row has the same height.
visible_rows_fixed :: proc(count: int, scroll, viewport, row_height: f32) -> Visible_Rows {
	if count <= 0 || row_height <= 0 {return {}}
	first := int(scroll / row_height)
	if first < 0 {first = 0}
	if first >= count {first = count - 1}
	last := min(count, first + visible_row_count(viewport, row_height))
	return {first = first, last = last}
}

//* == The look ==

//* The colour of the rows that are picked. The theme has the colour
//* under the name "selected_color"; the colour of the collection
//* widgets is used when the theme has none.
virtual_selected_colour :: proc(g: ^GUI, w: ^Widget) -> Colour {
	colour := theme_color(g, w, "selected_color")
	if colour.a > 0 {return colour}
	return COLLECT_ACCENT_SOFT
}

//* == The scroll ==

//* The greatest scroll there can be: the height of the rows without the
//* height of the screen.
scroll_maximum :: proc(content_height, viewport: f32) -> f32 {
	maximum := content_height - viewport
	if maximum < 0 {return 0}
	return maximum
}

//* Puts a scroll where it belongs: never above the first row and never
//* below the last one.
scroll_clamp :: proc(scroll: ^f32, content_height, viewport: f32) {
	scroll^ = clamp(scroll^, 0, scroll_maximum(content_height, viewport))
}
