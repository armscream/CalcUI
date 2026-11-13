package GUI

import "core:os"
import "core:slice"
import "core:strings"
import virt "core:mem/virtual"

Popup_Item :: struct {
	text:      string,
	icon:      Texture_ID,
	separator: bool,
	disabled:  bool,
	checked:   bool,
}

Popup_Menu_Data :: struct {
	items:    [dynamic]Popup_Item,
	selected: int,
	visible:  bool,
	owner:    Widget_ID,
}

Popup_Menu_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Make_Popup_Menu :: proc(g: ^GUI, parent: Widget_ID, opts: Popup_Menu_Opts) -> Widget_ID {
	kind_register(g, .PopupMenu, popup_menu_kind())
	id := New_Widget(g, .PopupMenu, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	data := Popup_Menu_Data{selected = -1, owner = INVALID_WIDGET_ID}
	for item in opts.items {append(&data.items, Popup_Item{text = item})}
	w.data = data
	w.state -= Widget_State{.Visible}
	return id
}

Popup_Menu_Add_Item :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Popup_Menu_Data:
		append(&d.items, Popup_Item{text = text})
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

Popup_Menu_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	owner := INVALID_WIDGET_ID
	#partial switch &d in w.data {
	case Popup_Menu_Data:
		d.visible = true
		owner = d.owner
	}
	if owner == INVALID_WIDGET_ID {popup_menu_place_at_pointer(g, id)}
	Popup_Open(g, id)
}

Popup_Menu_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Popup_Menu_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

//* Selects an item, closes the menu and emits item-selected on the menu and its owner, if any.
Popup_Menu_Select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil {return}
	owner := INVALID_WIDGET_ID
	#partial switch &d in w.data {
	case Popup_Menu_Data:
		if index < 0 || index >= len(d.items) {return}
		d.selected = index
		d.visible = false
		owner = d.owner
	}
	Popup_Close(g, id)
	signal_item_selected(g, id, index)
	if owner != INVALID_WIDGET_ID {signal_item_selected(g, owner, index)}
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

POPUP_ROW :: 24

popup_menu_size :: proc(g: ^GUI, id: Widget_ID) -> Vec2 {
	w := Widget_Get(g, id)
	if w == nil {return {}}
	style := resolved_style(g, w)
	margin := style.box.content_margin
	width := f32(0)
	count := 0

	#partial switch d in w.data {
	case Popup_Menu_Data:
		for item in d.items {
			count += 1
			width = max(width, text_measure(g, style.text, item.text, 0).x)
		}
	}
	if count == 0 {return {}}

	width += 16 + margin[0] + margin[2]
	height := f32(count * POPUP_ROW) + margin[1] + margin[3]
	return Vec2{x = width, y = height}
}

menu_place :: proc(anchor: Rect, size: Vec2, bounds: Rect) -> Rect {
	width := min(size.x, bounds.w)
	height := min(size.y, bounds.h)

	below := anchor.y + anchor.h
	over := anchor.y - height
	room_below := bounds.y + bounds.h - below
	room_over := over - bounds.y

	y := below
	if room_below < height && room_over > room_below {y = over}

	x := anchor.x
	if x + width > bounds.x + bounds.w {x = anchor.x + anchor.w - width}

	x = clamp(x, bounds.x, max(bounds.x, bounds.x + bounds.w - width))
	y = clamp(y, bounds.y, max(bounds.y, bounds.y + bounds.h - height))
	return Rect{x = x, y = y, w = width, h = height}
}

popup_menu_place :: proc(g: ^GUI, id: Widget_ID, anchor: Rect) {
	size := popup_menu_size(g, id)
	if size.x <= 0 {return}
	size.x = max(size.x, anchor.w)
	popup_set_rect(g, id, menu_place(anchor, size, widget_bounds(g, id)))
}

popup_menu_place_at_pointer :: proc(g: ^GUI, id: Widget_ID) {
	point := g.pointer
	if g.pointer_known {point = window_local_pos(g, id, g.global_pointer)}
	popup_menu_place(g, id, Rect{x = point.x, y = point.y})
}

popup_menu_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_popup_menu,
		click = click_popup_menu,
		style = Style{
			box = StyleBox{
				bg_color = RGBA(0.11, 0.12, 0.15, 1),
				content_margin = {4, 4, 4, 4},
			},
		},
		theme_name = "PopupMenu",
	}
}

popup_menu_item_at :: proc(g: ^GUI, w: ^Widget, p: Vec2) -> int {
	style := resolved_style(g, w)
	content := content_rect_with(w.rect, style.box.content_margin)
	if !rect_contains(content, p.x, p.y) {return -1}

	index := int((p.y - content.y) / f32(POPUP_ROW))
	#partial switch d in w.data {
	case Popup_Menu_Data:
		if index < 0 || index >= len(d.items) {return -1}
		item := d.items[index]
		if item.separator || item.disabled {return -1}
	}
	return index
}

click_popup_menu :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	index := popup_menu_item_at(g, w, g.pointer)
	if index < 0 {
		Popup_Menu_Close(g, id)
		return
	}
	Popup_Menu_Select(g, id, index)
}

draw_popup_menu :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	style := resolved_style(g, w)
	row_style := style.text
	row_style.valign = .Center

	#partial switch d in w.data {
	case Popup_Menu_Data:
		lit := -1
		if g.hot == id {lit = popup_menu_item_at(g, w, g.pointer)}
		y := content.y

		for item, index in d.items {
			if y >= content.y + content.h {break}
			if item.separator {
				draw_quad(
					g.target,
					Rect{x = content.x, y = y + POPUP_ROW * 0.5, w = content.w, h = 1},
					g.atlas.white_uv,
					RGBA(0.25, 0.27, 0.33, 1),
					g.atlas_texture,
				)
			} else {
				if index == lit {
					draw_rect(g, Rect{x = content.x, y = y, w = content.w, h = POPUP_ROW}, RGBA(0.16, 0.42, 0.82, 1), 0)
				}
				label := Rect{x = content.x + 8, y = y, w = content.w - 16, h = POPUP_ROW}
				ink := resolved_text_colour(g, id, w)
				if item.disabled {ink = Scale_Colour(ink, 0.5)}
				draw_text(g, row_style, item.text, label, ink)
			}
			y += POPUP_ROW
		}
	}
}

popup_panel_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_popup_panel,
		click = click_popup_panel,
		measure = measure_popup_panel,
		style = Style{box = StyleBox{content_margin = {8, 8, 8, 8}}},
		theme_name = "PopupPanel",
	}
}

draw_popup_panel :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	draw_overlay_plate(g, w)
}

click_popup_panel :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
}

measure_popup_panel :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	return Vec2{160, 100}
}

Popup_Panel_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Popup_Panel :: proc(g: ^GUI, parent: Widget_ID, opts: Popup_Panel_Opts) -> Widget_ID {
	kind_register(g, .PopupPanel, popup_panel_kind())
	id := New_Widget(g, .PopupPanel, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.state -= Widget_State{.Visible}
	return id
}

Popup_Panel_Open :: proc(g: ^GUI, id: Widget_ID) {
	Popup_Open(g, id)
}

Popup_Panel_Close :: proc(g: ^GUI, id: Widget_ID) {
	Popup_Close(g, id)
}

Dialog_Data :: struct {
	text:     string,
	visible:  bool,
	accepted: bool,
}

Accept_Dialog_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

Make_Accept_Dialog :: proc(g: ^GUI, parent: Widget_ID, opts: Accept_Dialog_Opts) -> Widget_ID {
	kind_register(g, .AcceptDialog, accept_dialog_kind())
	id := New_Widget(g, .AcceptDialog, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Dialog_Data{text = opts.text}
	w.state -= Widget_State{.Visible}
	return id
}

Make_Confirmation_Dialog :: proc(g: ^GUI, parent: Widget_ID, opts: Accept_Dialog_Opts) -> Widget_ID {
	kind_register(g, .ConfirmationDialog, confirmation_dialog_kind())
	id := New_Widget(g, .ConfirmationDialog, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Dialog_Data{text = opts.text}
	w.state -= Widget_State{.Visible}
	return id
}

Dialog_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Dialog_Data:
		d.visible = true
		d.accepted = false
	}
	popup_open_core(g, id)
}

Dialog_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Dialog_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

Dialog_Accept :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Dialog_Data:
		d.accepted = true
	}
	Dialog_Close(g, id)
}

Dialog_Was_Accepted :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil {return false}
	#partial switch d in w.data {
	case Dialog_Data:
		return d.accepted
	}
	return false
}

accept_dialog_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_accept_dialog,
		click = click_accept_dialog,
		measure = measure_accept_dialog,
		style = Style{box = StyleBox{content_margin = {12, 12, 12, 12}}},
		theme_name = "AcceptDialog",
	}
}

draw_accept_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	draw_overlay_plate(g, w)
	style := resolved_style(g, w)
	draw_dialog_message(g, id, w, content, style^)
	draw_dialog_buttons(g, id, w, content, []Dialog_Button{.OK})
}

click_accept_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	content := content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
	if dialog_button_at(content, 1, g.pointer) >= 0 {Dialog_Accept(g, id)}
}

confirmation_dialog_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_confirmation_dialog,
		click = click_confirmation_dialog,
		measure = measure_confirmation_dialog,
		style = Style{box = StyleBox{content_margin = {12, 12, 12, 12}}},
		theme_name = "ConfirmationDialog",
	}
}

draw_confirmation_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	draw_overlay_plate(g, w)
	style := resolved_style(g, w)
	draw_dialog_message(g, id, w, content, style^)
	draw_dialog_buttons(g, id, w, content, []Dialog_Button{.OK, .Cancel})
}

draw_dialog_message :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect, style: Style) {
	#partial switch d in w.data {
	case Dialog_Data:
		draw_text(g, style.text, d.text, dialog_message_rect(content), resolved_text_colour(g, id, w))
	}
}

click_confirmation_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	content := content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
	index := dialog_button_at(content, 2, g.pointer)
	if index < 0 {return}
	if index == 0 {
		Dialog_Accept(g, id)
		return
	}
	Dialog_Close(g, id)
}

measure_dialog :: proc(g: ^GUI, w: ^Widget, smallest: Vec2) -> Vec2 {
	style := resolved_style(g, w)
	margin := style.box.content_margin
	width, height := f32(0), f32(0)

	#partial switch d in w.data {
	case Dialog_Data:
		size := text_measure(g, style.text, d.text, 0)
		width, height = size.x, size.y
	}

	width += margin[0] + margin[2]
	height += margin[1] + margin[3] + DIALOG_BUTTON_HEIGHT + DIALOG_BUTTON_GAP
	return Vec2{x = max(width, smallest.x), y = max(height, smallest.y)}
}

measure_accept_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	return measure_dialog(g, w, Vec2{260, 120})
}

measure_confirmation_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	return measure_dialog(g, w, Vec2{320, 140})
}

DIALOG_BUTTON_HEIGHT :: 26
DIALOG_BUTTON_WIDTH :: 84
DIALOG_BUTTON_GAP :: 8
FILE_DIALOG_PATH_HEIGHT :: 22
FILE_DIALOG_ROW :: 20

Dialog_Button :: enum {
	None,
	OK,
	Cancel,
	Open,
}

dialog_button_text :: proc(button: Dialog_Button) -> string {
	#partial switch button {
	case .OK: return "OK"
	case .Cancel: return "Cancel"
	case .Open: return "Open"
	case: return ""
	}
}

dialog_button_row_rect :: proc(content: Rect) -> Rect {
	return Rect{
		x = content.x,
		y = content.y + content.h - DIALOG_BUTTON_HEIGHT,
		w = content.w,
		h = DIALOG_BUTTON_HEIGHT,
	}
}

dialog_button_rect :: proc(content: Rect, index: int) -> Rect {
	row := dialog_button_row_rect(content)
	return Rect{
		x = row.x + row.w - f32(DIALOG_BUTTON_WIDTH) - f32(index) * f32(DIALOG_BUTTON_WIDTH + DIALOG_BUTTON_GAP),
		y = row.y,
		w = DIALOG_BUTTON_WIDTH,
		h = DIALOG_BUTTON_HEIGHT,
	}
}

dialog_button_at :: proc(content: Rect, count: int, p: Vec2) -> int {
	for index in 0 ..< count {
		if rect_contains(dialog_button_rect(content, index), p.x, p.y) {return index}
	}
	return -1
}

dialog_message_rect :: proc(content: Rect) -> Rect {
	return Rect{
		x = content.x,
		y = content.y,
		w = content.w,
		h = content.h - DIALOG_BUTTON_HEIGHT - DIALOG_BUTTON_GAP,
	}
}

overlay_plate_colour :: proc(g: ^GUI, w: ^Widget, name: string, fallback: Colour) -> Colour {
	colour := theme_color(g, w, name)
	if colour.a == 0 {return fallback}
	return colour
}

draw_overlay_plate :: proc(g: ^GUI, w: ^Widget) {
	plate := overlay_plate_colour(g, w, "surface", RGBA(0.11, 0.12, 0.15, 1))
	border := overlay_plate_colour(g, w, "border", RGBA(0.24, 0.26, 0.31, 1))
	draw_rect(g, w.rect, plate, 6)
	draw_outline(g, w.rect, border, 1)
}

draw_dialog_buttons :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	content: Rect,
	buttons: []Dialog_Button,
) {
	label := resolved_style(g, w).text
	label.align = .Center
	label.valign = .Center

	for button, index in buttons {
		rect := dialog_button_rect(content, index)
		draw_rect(g, rect, RGBA(0.20, 0.62, 1.0, 1), 4)
		draw_text(g, label, dialog_button_text(button), rect, RGBA(1, 1, 1, 1))
	}
}

File_Dialog_Data :: struct {
	path:    string,
	mode:    File_Dialog_Mode,
	visible: bool,
}

File_Dialog_Mode :: enum {
	Open_File,
	Save_File,
	Open_Folder,
}

File_Dialog_Opts :: struct {
	Base_Opts: Base_Opts,
	mode:      File_Dialog_Mode,
}

Make_File_Dialog :: proc(g: ^GUI, parent: Widget_ID, opts: File_Dialog_Opts) -> Widget_ID {
	kind_register(g, .FileDialog, file_dialog_kind())
	id := New_Widget(g, .FileDialog, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = File_Dialog_Data{mode = opts.mode}
	w.state -= Widget_State{.Visible}
	return id
}

File_Dialog_Path :: proc(g: ^GUI, id: Widget_ID) -> string {
	w := Widget_Get(g, id)
	if w == nil {return ""}
	#partial switch d in w.data {
	case File_Dialog_Data:
		return d.path
	}
	return ""
}

File_Dialog_Set_Path :: proc(g: ^GUI, id: Widget_ID, path: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case File_Dialog_Data:
		d.path = path
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

File_Dialog_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case File_Dialog_Data:
		d.visible = true
	}
	popup_open_core(g, id)
}

File_Dialog_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case File_Dialog_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

file_dialog_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_file_dialog,
		click = click_file_dialog,
		measure = measure_file_dialog,
		style = Style{box = StyleBox{content_margin = {12, 12, 12, 12}}},
		theme_name = "FileDialog",
	}
}

file_dialog_list_rect :: proc(content: Rect) -> Rect {
	return Rect{
		x = content.x,
		y = content.y + FILE_DIALOG_PATH_HEIGHT,
		w = content.w,
		h = content.h - FILE_DIALOG_PATH_HEIGHT - DIALOG_BUTTON_HEIGHT - DIALOG_BUTTON_GAP,
	}
}

file_dialog_path :: proc(g: ^GUI, id: Widget_ID) -> string {
	return File_Dialog_Path(g, id)
}

//* Returns directory entries sorted with folders first. The caller must release them with os.file_info_slice_delete.
file_dialog_entries :: proc(path: string) -> []os.File_Info {
	if path == "" {return nil}
	entries, err := os.read_directory_by_path(path, -1, context.allocator)
	if err != nil {return nil}

	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {
		if a.type != b.type {return a.type == .Directory}
		return a.name < b.name
	})
	return entries
}

file_dialog_go_into :: proc(g: ^GUI, id: Widget_ID, path, name: string) {
	joined, err := os.join_path([]string{path, name}, virt.arena_allocator(&g.arena))
	if err != nil {return}
	File_Dialog_Set_Path(g, id, joined)
}

draw_file_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	draw_overlay_plate(g, w)
	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	path := file_dialog_path(g, id)

	draw_text(
		g,
		style.text,
		path,
		Rect{x = content.x, y = content.y, w = content.w, h = FILE_DIALOG_PATH_HEIGHT},
		ink,
	)

	list := file_dialog_list_rect(content)
	entries := file_dialog_entries(path)
	for entry in entries {
		if entry == entries[len(entries) - 1] && len(entries) == 0 {break}
	}
	if len(entries) > 0 {
		y := list.y
		for entry in entries {
			if y + FILE_DIALOG_ROW > list.y + list.h {break}
			name := entry.name
			if entry.type == .Directory {
				name = strings.concatenate({name, "/"}, virt.arena_allocator(&g.frame_arena))
			}
			draw_text(g, style.text, name, Rect{x = list.x, y = y, w = list.w, h = FILE_DIALOG_ROW}, ink)
			y += FILE_DIALOG_ROW
		}
		os.file_info_slice_delete(entries, context.allocator)
	}
	draw_dialog_buttons(g, id, w, content, []Dialog_Button{.Open, .Cancel})
}

click_file_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	content := content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
	if dialog_button_at(content, 2, g.pointer) >= 0 {
		File_Dialog_Close(g, id)
		return
	}

	path := file_dialog_path(g, id)
	entries := file_dialog_entries(path)
	if len(entries) == 0 {return}

	list := file_dialog_list_rect(content)
	if !rect_contains(list, g.pointer.x, g.pointer.y) {
		os.file_info_slice_delete(entries, context.allocator)
		return
	}

	row := int((g.pointer.y - list.y) / f32(FILE_DIALOG_ROW))
	if row < 0 || row >= len(entries) {
		os.file_info_slice_delete(entries, context.allocator)
		return
	}

	entry := entries[row]
	if entry.type == .Directory {file_dialog_go_into(g, id, path, entry.name)}
	os.file_info_slice_delete(entries, context.allocator)
}

measure_file_dialog :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	return Vec2{420, 280}
}