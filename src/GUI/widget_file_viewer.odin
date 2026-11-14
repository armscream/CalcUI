package GUI

import "core:log"
import "core:strconv"
import "core:strings"
import virt "core:mem/virtual"

File_Viewer_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_File_Viewer :: proc(g: ^GUI, parent: Widget_ID, opts: File_Viewer_Opts) -> Widget_ID {
	kind_register(g, .FileViewer, file_viewer_kind())
	id := New_Widget(g, .FileViewer, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	state, err := virt.new(&g.arena, File_Viewer_State)
	if err != nil {
		log.panicf("the state of the file viewer could not be made: %v", err)
	}
	state^ = File_Viewer_State{}
	state.entries = make([dynamic]File_Entry, 0, 16, virt.arena_allocator(&g.arena))
	state.selected = -1
	w.data = File_Viewer_Data{state = state}
	return id
}

file_viewer_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_file_viewer,
		update = update_file_viewer,
		click = click_file_viewer,
		pointer = pointer_file_viewer,
		style = Style{
			box = StyleBox{
				bg_color = RGBA(0.10, 0.11, 0.14, 1),
				border_color = {
					RGBA(0.20, 0.22, 0.27, 1),
					RGBA(0.20, 0.22, 0.27, 1),
					RGBA(0.20, 0.22, 0.27, 1),
					RGBA(0.20, 0.22, 0.27, 1),
				},
				border_width = {1, 1, 1, 1},
			},
		},
		theme_name = "FileViewer",
	}
}

file_viewer_data :: proc(g: ^GUI, id: Widget_ID) -> ^File_Viewer_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case File_Viewer_Data:
		return &d
	}
	return nil
}

//* Sets the procedure called when the directory path changes.
file_viewer_set_load :: proc(
	g: ^GUI,
	id: Widget_ID,
	load: proc(g: ^GUI, id: Widget_ID, state: ^File_Viewer_State),
) {
	d := file_viewer_data(g, id)
	if d == nil {return}
	d.load = load
}

//* Changes the displayed directory and clears the selection.
file_viewer_set_path :: proc(g: ^GUI, id: Widget_ID, path: string) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}
	d.state.path = path
	d.state.selected = -1
	invalidate(g, id, Dirty_Flags{.Visual})
}

file_viewer_path :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return ""}
	return d.state.path
}

file_viewer_entry_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return 0}
	return len(d.state.entries)
}

file_viewer_selected :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return -1}
	return d.state.selected
}

file_viewer_entry_name :: proc(g: ^GUI, id: Widget_ID, index: int) -> string {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return ""}
	if index < 0 || index >= len(d.state.entries) {return ""}
	return d.state.entries[index].name
}

file_viewer_add_entry :: proc(
	g: ^GUI,
	id: Widget_ID,
	name: string,
	size: i64,
	directory: bool,
) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}
	append(&d.state.entries, File_Entry{name = name, size = size, directory = directory})
	invalidate(g, id, Dirty_Flags{.Visual})
}

file_viewer_clear :: proc(g: ^GUI, id: Widget_ID) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}
	clear(&d.state.entries)
	d.state.selected = -1
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Selects an entry and emits the item-selected signal.
file_viewer_select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}
	if index < 0 || index >= len(d.state.entries) {return}
	d.state.selected = index
	signal_item_selected(g, id, index)
	invalidate(g, id, Dirty_Flags{.Visual})
}

update_file_viewer :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil || d.load == nil {return}
	if d.state.path == d.loaded_path {return}

	d.loaded_path = d.state.path
	d.load(g, id, d.state)
}

FILE_VIEWER_ROW :: 20
FILE_VIEWER_MARK :: 13
FILE_VIEWER_SIZE_WIDTH :: 64
FILE_VIEWER_WHEEL_ROWS :: 3

file_viewer_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

click_file_viewer :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}

	st := d.state
	content := file_viewer_content(g, w)
	index := int((g.pointer.y - content.y + st.scroll) / FILE_VIEWER_ROW)
	if index < 0 || index >= len(st.entries) {return}

	st.selected = index
	signal_item_selected(g, id, index)
}

pointer_file_viewer :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel {return}
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}

	content := file_viewer_content(g, w)
	delta := e.amount * FILE_VIEWER_ROW * FILE_VIEWER_WHEEL_ROWS
	rows := f32(len(d.state.entries)) * FILE_VIEWER_ROW
	if !wheel_scroll(&d.state.scroll, delta, rows, content.h) {return}

	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

draw_file_viewer :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := file_viewer_data(g, id)
	if d == nil || d.state == nil {return}

	st := d.state
	style := resolved_style(g, w)
	colour := resolved_text_colour(g, id, w)

	draw_push_clip(g.target, content)
	y := content.y - st.scroll
	for entry, i in st.entries {
		if y >= content.y + content.h {break}
		row := Rect{x = content.x, y = y, w = content.w, h = FILE_VIEWER_ROW}
		if i == st.selected {
			draw_rect(g, row, RGBA(0.16, 0.42, 0.82, 1), 0)
		}

		x := content.x + 4
		if entry.directory {
			draw_file_viewer_folder(g, x, y + (FILE_VIEWER_ROW - 9) * 0.5)
			x += FILE_VIEWER_MARK + 6
		}

		name_width := max(content.w - (x - content.x) - FILE_VIEWER_SIZE_WIDTH, 0)
		draw_text(g, style.text, entry.name,
			Rect{x = x, y = y, w = name_width, h = FILE_VIEWER_ROW}, colour)

		size_style := style.text
		size_style.align = .Right
		draw_text(g, size_style, file_size_text(g, entry.size),
			Rect{
				x = content.x + content.w - FILE_VIEWER_SIZE_WIDTH,
				y = y,
				w = FILE_VIEWER_SIZE_WIDTH - 4,
				h = FILE_VIEWER_ROW,
			}, colour)

		y += FILE_VIEWER_ROW
	}
	draw_pop_clip(g.target)
}

draw_file_viewer_folder :: proc(g: ^GUI, x, y: f32) {
	colour := RGBA(0.55, 0.60, 0.70, 1)
	draw_quad(g.target, Rect{x = x, y = y, w = 6, h = 3},
		g.atlas.white_uv, colour, g.atlas_texture)
	draw_quad(g.target, Rect{x = x, y = y + 2, w = FILE_VIEWER_MARK, h = 8},
		g.atlas.white_uv, colour, g.atlas_texture)
}

file_size_text :: proc(g: ^GUI, size: i64) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	buf: [48]byte
	n := 0

	if size < 1024 {
		n = put_number(buf[:], n, size)
		n = put_text(buf[:], n, " B")
	} else if size < 1024 * 1024 {
		n = put_number(buf[:], n, size / 1024)
		n = put_text(buf[:], n, ".")
		n = put_number(buf[:], n, size % 1024 * 10 / 1024)
		n = put_text(buf[:], n, " KB")
	} else {
		n = put_number(buf[:], n, size / (1024 * 1024))
		n = put_text(buf[:], n, ".")
		n = put_number(buf[:], n, size % (1024 * 1024) * 10 / (1024 * 1024))
		n = put_text(buf[:], n, " MB")
	}

	text, err := strings.clone(string(buf[:n]), allocator)
	if err != nil {return ""}
	return text
}

put_number :: proc(buf: []byte, used: int, value: i64) -> int {
	tmp: [24]byte
	text := strconv.write_int(tmp[:], value, 10)
	return used + copy(buf[used:], text)
}

put_text :: proc(buf: []byte, used: int, text: string) -> int {
	return used + copy(buf[used:], text)
}