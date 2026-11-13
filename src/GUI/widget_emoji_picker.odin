package GUI

import "core:unicode/utf8"

Emoji_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	emoji:     string,
	group:     int,
}

EMOJI_FIELD_HEIGHT :: 28
EMOJI_GROUP_WIDTH :: 78
EMOJI_GROUP_HEIGHT :: 24
EMOJI_CELL :: 30
EMOJI_PANEL_GAP :: 4
EMOJI_SIDE_GAP :: 4
EMOJI_WHEEL_LINES :: 3

Make_Emoji_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Emoji_Picker_Opts) -> Widget_ID {
	kind_register(g, .EmojiPicker, emoji_picker_kind())
	id := New_Widget(g, .EmojiPicker, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	group := opts.group
	if group < 0 || group >= emoji_group_count() {
		group = 0
	}
	w.data = Emoji_Picker_Data{emoji = opts.emoji, group = group}
	w.focus_mode = .All
	return id
}

emoji_picker_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_emoji_picker,
		click = click_emoji_picker,
		pointer = pointer_emoji_picker,
		measure = measure_emoji_picker,
		theme_name = "EmojiPicker",
	}
}

emoji_picker_data :: proc(g: ^GUI, id: Widget_ID) -> ^Emoji_Picker_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Emoji_Picker_Data:
		return &d
	}
	return nil
}

emoji_picker_emoji :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := emoji_picker_data(g, id)
	if d == nil {return ""}
	return d.emoji
}

//* Sets the picked emoji and emits the text-changed signal.
emoji_picker_set :: proc(g: ^GUI, id: Widget_ID, emoji: string) {
	d := emoji_picker_data(g, id)
	if d == nil || d.emoji == emoji {return}
	d.emoji = emoji
	signal_text_changed(g, id, emoji)
	invalidate(g, id, Dirty_Flags{.Visual})
}

emoji_picker_group :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := emoji_picker_data(g, id)
	if d == nil {return 0}
	return d.group
}

emoji_picker_set_group :: proc(g: ^GUI, id: Widget_ID, group: int) {
	d := emoji_picker_data(g, id)
	if d == nil || group < 0 || group >= emoji_group_count() {return}
	d.group = group
	d.scroll = 0
	invalidate(g, id, Dirty_Flags{.Visual})
}

emoji_picker_is_open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := emoji_picker_data(g, id)
	if d == nil {return false}
	return d.open
}

emoji_picker_set_open :: proc(g: ^GUI, id: Widget_ID, open: bool) {
	d := emoji_picker_data(g, id)
	if d == nil || d.open == open {return}
	d.open = open
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

Emoji_Picker_Layout :: struct {
	field:  Rect,
	groups: Rect,
	grid:   Rect,
}

emoji_picker_layout :: proc(content: Rect, open: bool) -> Emoji_Picker_Layout {
	layout := Emoji_Picker_Layout{field = content}
	if !open {return layout}

	field_h := min(f32(EMOJI_FIELD_HEIGHT), content.h)
	layout.field = Rect{x = content.x, y = content.y, w = content.w, h = field_h}
	top := content.y + field_h + EMOJI_PANEL_GAP
	height := content.y + content.h - top
	if height <= 0 {return layout}

	group_w := min(f32(EMOJI_GROUP_WIDTH), content.w * 0.3)
	layout.groups = Rect{x = content.x, y = top, w = group_w, h = height}
	layout.grid = Rect{
		x = content.x + group_w + EMOJI_SIDE_GAP,
		y = top,
		w = content.w - group_w - EMOJI_SIDE_GAP,
		h = height,
	}
	return layout
}

emoji_picker_panel_height :: proc() -> f32 {
	return f32(emoji_group_count() * EMOJI_GROUP_HEIGHT)
}

measure_emoji_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := emoji_picker_data(g, id)
	if d == nil {return Vec2{}}

	pad := resolved_style(g, w).box.content_margin
	width := f32(EMOJI_GROUP_WIDTH + EMOJI_SIDE_GAP + 4 * EMOJI_CELL)
	height := f32(EMOJI_FIELD_HEIGHT)
	if d.open {
		height += f32(EMOJI_PANEL_GAP) + emoji_picker_panel_height()
	}
	return Vec2{width + pad[0] + pad[2], height + pad[1] + pad[3]}
}

emoji_picker_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

emoji_picker_columns :: proc(grid: Rect) -> int {
	if grid.w <= 0 {return 1}
	return max(int(grid.w / f32(EMOJI_CELL)), 1)
}

emoji_picker_content_height :: proc(count, columns: int) -> f32 {
	if count <= 0 || columns <= 0 {return 0}
	return f32((count - 1) / columns + 1) * f32(EMOJI_CELL)
}

emoji_picker_scroll_clamp :: proc(d: ^Emoji_Picker_Data, content_height, viewport: f32) {
	if d == nil {return}
	scroll_clamp(&d.scroll, content_height, viewport)
}

pointer_emoji_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel {return}
	d := emoji_picker_data(g, id)
	if d == nil || !d.open {return}

	layout := emoji_picker_layout(emoji_picker_content(g, w), true)
	if !rect_contains(layout.grid, e.pos.x, e.pos.y) {return}

	entries := emoji_in_group(g, d.group)
	height := emoji_picker_content_height(len(entries), emoji_picker_columns(layout.grid))
	delta := e.amount * f32(EMOJI_CELL * EMOJI_WHEEL_LINES)
	if !wheel_scroll(&d.scroll, delta, height, layout.grid.h) {return}

	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

//* Checks the first rune against the active font family.
emoji_picker_has_glyph :: proc(g: ^GUI, style: Text_Style, emoji: string) -> bool {
	if emoji == "" {return false}
	r, _ := utf8.decode_rune_in_string(emoji)
	family := style.family
	if family == INVALID_FONT_FAMILY_ID {
		family = g.default_family
	}
	return Font_Has_Glyph(g, family, r)
}

emoji_picker_cell_at :: proc(g: ^GUI, grid: Rect, scroll: f32, x, y: f32) -> int {
	columns := emoji_picker_columns(grid)
	row := int((y - grid.y + scroll) / f32(EMOJI_CELL))
	column := int((x - grid.x) / f32(EMOJI_CELL))
	if row < 0 || column < 0 || column >= columns {return -1}
	return row * columns + column
}

click_emoji_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := emoji_picker_data(g, id)
	if d == nil {return}

	layout := emoji_picker_layout(emoji_picker_content(g, w), d.open)
	if !d.open {
		emoji_picker_set_open(g, id, true)
		return
	}

	if rect_contains(layout.groups, g.pointer.x, g.pointer.y) {
		index := int((g.pointer.y - layout.groups.y) / f32(EMOJI_GROUP_HEIGHT))
		if index >= 0 && index < emoji_group_count() {
			emoji_picker_set_group(g, id, index)
		}
		return
	}

	if rect_contains(layout.grid, g.pointer.x, g.pointer.y) {
		index := emoji_picker_cell_at(g, layout.grid, d.scroll, g.pointer.x, g.pointer.y)
		entries := emoji_in_group(g, d.group)
		if index >= 0 && index < len(entries) {
			emoji_picker_set(g, id, entries[index].emoji)
		}
		return
	}

	if !rect_contains(layout.field, g.pointer.x, g.pointer.y) {
		emoji_picker_set_open(g, id, false)
	}
}

draw_emoji_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := emoji_picker_data(g, id)
	if d == nil {return}

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	emoji_ink := Colour{1, 1, 1, 1}
	layout := emoji_picker_layout(content, d.open)
	text_style := style.text
	text_style.align = .Center

	if emoji_picker_has_glyph(g, text_style, d.emoji) {
		draw_text(g, text_style, d.emoji, layout.field, emoji_ink)
	}
	if !d.open {return}

	for index in 0 ..< emoji_group_count() {
		button := Rect{
			x = layout.groups.x,
			y = layout.groups.y + f32(index) * EMOJI_GROUP_HEIGHT,
			w = layout.groups.w,
			h = EMOJI_GROUP_HEIGHT,
		}
		if button.y >= layout.groups.y + layout.groups.h {break}
		if index == d.group {
			draw_rect(g, button, COLLECT_ACCENT_SOFT, 0)
		}
		draw_text(g, style.text, emoji_group_name(g, index),
			Rect{x = button.x + 6, y = button.y, w = button.w - 8, h = button.h}, ink)
	}

	entries := emoji_in_group(g, d.group)
	columns := emoji_picker_columns(layout.grid)
	emoji_picker_scroll_clamp(d, emoji_picker_content_height(len(entries), columns), layout.grid.h)

	cell_style := style.text
	cell_style.align = .Center
	for index in 0 ..< len(entries) {
		row := index / columns
		column := index % columns
		cell := Rect{
			x = layout.grid.x + f32(column * EMOJI_CELL),
			y = layout.grid.y + f32(row * EMOJI_CELL) - d.scroll,
			w = EMOJI_CELL,
			h = EMOJI_CELL,
		}
		if cell.y + cell.h < layout.grid.y {continue}
		if cell.y > layout.grid.y + layout.grid.h {break}
		if entries[index].emoji == d.emoji {
			draw_rect(g, cell, COLLECT_ACCENT_SOFT, 0)
		}
		if emoji_picker_has_glyph(g, cell_style, entries[index].emoji) {
			draw_text(g, cell_style, entries[index].emoji, cell, emoji_ink)
		}
	}
}