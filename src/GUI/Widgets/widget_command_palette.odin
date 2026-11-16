//* The command palette: a searchable list of program commands.

package Widgets
import "core:strings"

PALETTE_FIELD_HEIGHT :: 36
PALETTE_ROW          :: 24

overlay_key_characters: string = "abcdefghijklmnopqrstuvwxyz0123456789 "

overlay_key_character :: proc(key: Key) -> string {
	i := int(key)
	if i >= int(Key.A) && i <= int(Key.Z) {
		at := i - int(Key.A)
		return overlay_key_characters[at:at+1]
	}
	if i >= int(Key.Digit0) && i <= int(Key.Digit9) {
		at := 26 + i - int(Key.Digit0)
		return overlay_key_characters[at:at+1]
	}
	if key == .Space { return " " }
	return ""
}



Make_Command_Palette :: proc(g: ^GUI, parent: Widget_ID, opts: Command_Palette_Opts) -> Widget_ID {
	kind_register(g, .CommandPalette, command_palette_kind())
	base := base_widget_opts(opts.Base_Opts)
	if base.preset == .Fill && opts.Base_Opts.offsets == (Offset{}) {
		base.preset = .Top_Left
		base.offsets = Offset{left = 80, top = 40, right = 720, bottom = 340}
	}

	id := New_Widget(g, .CommandPalette, parent, base)
	w := Widget_Get(g, id)
	w.data = Command_Palette_Data{selected = -1, text = strings.clone(""), matches_dirty = true}
	w.focus_mode = .All
	w.mouse_filter = .Ignore
	w.focus_neighbour = {id, id, id, id}
	w.state -= Widget_State{.Visible}
	return id
}



Command_Palette_Is_Open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := command_palette_data(g, id)
	return d != nil && d.visible
}

Command_Palette_Text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := command_palette_data(g, id)
	if d == nil { return "" }
	return d.text
}

Command_Palette_Set_Text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := command_palette_data(g, id)
	if d == nil { return }
	new_text := strings.clone(text)
	delete(d.text)
	d.text = new_text
	command_palette_reset(g, id)
	invalidate(g, id, Dirty_Flags{.Visual})
}


Command_Palette_Add :: proc(
	g: ^GUI,
	id: Widget_ID,
	label: string,
	action: proc(g: ^GUI, id: Widget_ID),
	keywords: string,
) {
	d := command_palette_data(g, id)
	if d == nil { return }
	append(&d.commands, Palette_Command{label = label, action = action, keywords = keywords})
	d.matches_dirty = true
	invalidate(g, id, Dirty_Flags{.Visual})
}

command_palette_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw           = draw_command_palette,
		update         = update_command_palette,
		click          = click_command_palette,
		key            = key_command_palette,
		uses_arrow_keys = true,
		style          = Style{box = StyleBox{content_margin = {8, 8, 8, 8}}},
		theme_name     = "CommandPalette",
	}
}





command_palette_move :: proc(g: ^GUI, id: Widget_ID, delta: int) {
	d := command_palette_data(g, id)
	if d == nil { return }

	count := Command_Palette_Count(g, id)
	if count == 0 {
		d.selected = -1
		return
	}

	selected := d.selected
	if selected < 0 {
		selected = delta > 0 ? 0 : count - 1
	} else {
		selected += delta
	}
	d.selected = clamp(selected, 0, count - 1)
	command_palette_scroll_to_selection(g, id)
}

command_palette_visible_rows :: proc(g: ^GUI, id: Widget_ID) -> int {
	w := Widget_Get(g, id)
	if w == nil {return 1}
	content := content_rect(g, w)
	return max(int((content.h - PALETTE_FIELD_HEIGHT) / PALETTE_ROW), 1)
}

command_palette_scroll_to_selection :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil || d.selected < 0 {return}
	visible := command_palette_visible_rows(g, id)
	if d.selected < d.scroll {
		d.scroll = d.selected
	} else if d.selected >= d.scroll + visible {
		d.scroll = d.selected - visible + 1
	}
	d.scroll = clamp(d.scroll, 0, max(Command_Palette_Count(g, id) - visible, 0))
}

command_palette_row_at :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, pos: Vec2) -> int {
	d := command_palette_data(g, id)
	if d == nil || !d.visible {return -1}
	content := content_rect(g, w)
	if pos.x < content.x || pos.x >= content.x + content.w {return -1}
	top := content.y + PALETTE_FIELD_HEIGHT
	if pos.y < top || pos.y >= content.y + content.h {return -1}
	row := int((pos.y - top) / PALETTE_ROW)
	if row < 0 || row >= command_palette_visible_rows(g, id) {return -1}
	index := d.scroll + row
	if index < 0 || index >= Command_Palette_Count(g, id) {return -1}
	return index
}

command_palette_run :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }

	action: proc(g: ^GUI, id: Widget_ID)
	matches := command_palette_matches(d)
	if d.selected >= 0 && d.selected < len(matches) {
		command := d.commands[matches[d.selected].index]
		action = command.action
		d.last_tag = command.tag
	}

	Command_Palette_Close(g, id)
	if action != nil { action(g, id) }
}

command_palette_type :: proc(g: ^GUI, id: Widget_ID, c: string) {
	d := command_palette_data(g, id)
	if d == nil { return }
	text := strings.concatenate({d.text, c})
	delete(d.text)
	d.text = text
	command_palette_reset(g, id)
	invalidate(g, id, Dirty_Flags{.Visual})
}

command_palette_backspace :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }

	end := len(d.text)
	for end > 0 && (d.text[end-1] & 0xC0) == 0x80 {
		end -= 1
	}
	if end > 0 { end -= 1 }

	text := strings.clone(d.text[:end])
	delete(d.text)
	d.text = text
	command_palette_reset(g, id)
	invalidate(g, id, Dirty_Flags{.Visual})
}

key_command_palette :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	#partial switch e.key {
	case .Up:        command_palette_move(g, id, -1)
	case .Down:      command_palette_move(g, id, 1)
	case .Enter:     command_palette_run(g, id)
	case .Backspace: command_palette_backspace(g, id)
	case:
		if c := overlay_key_character(e.key); c != "" {
			command_palette_type(g, id, c)
		}
	}
}

update_command_palette :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	#partial switch d in w.data {
	case Command_Palette_Data:
		if !d.visible { return }
		if g.focused != id { focus_set(g, id) }
	}
}

click_command_palette :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	focus_set(g, id)
	d := command_palette_data(g, id)
	if d == nil || !d.visible {return}
	row := command_palette_row_at(g, id, w, g.pointer)
	if row < 0 {return}
	d.selected = row
	command_palette_run(g, id)
}

draw_command_palette :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch &d in w.data {
	case Command_Palette_Data:
		if !d.visible { return }

		matches := command_palette_matches(&d)
		count := len(matches)
		visible := command_palette_visible_rows(g, id)
		d.scroll = clamp(d.scroll, 0, max(count - visible, 0))
		shown := min(count, visible)

		panel := Rect{
			x = content.x,
			y = content.y,
			w = content.w,
			h = PALETTE_FIELD_HEIGHT + f32(shown) * PALETTE_ROW,
		}
		draw_rect(g, panel, RGBA(0.11, 0.12, 0.15, 0.98), 8)

		ink := resolved_text_colour(g, id, w)
		row_style := resolved_style(g, w).text
		row_style.valign = .Center
		row_style.overrun = .Ellipsis
		row_style.clip = true

		field := Rect{x = content.x, y = content.y, w = content.w, h = PALETTE_FIELD_HEIGHT}
		draw_rect(g, field, RGBA(0.16, 0.17, 0.21, 1), 6)

		text := d.text
		colour := ink
		if text == "" {
			text = "Type a command"
			colour = Scale_Colour(ink, 0.55)
		}
		draw_text(g, row_style, text,
			Rect{x = field.x + 12, y = field.y, w = field.w - 24, h = field.h}, colour)

		y := field.y + field.h
		for match, rank in matches {
			if rank < d.scroll { continue }
			if rank >= d.scroll + shown {break}
			command := d.commands[match.index]

			row := Rect{x = content.x + 4, y = y, w = content.w - 8, h = PALETTE_ROW}
			row_ink := ink
			if rank == d.selected {
				draw_rect(g, row, RGBA(0.16, 0.42, 0.82, 1), 4)
				row_ink = RGBA(1, 1, 1, 1)
			}

			label_style := row_style
			label_style.align = .Left
			detail_x := row.x + row.w
			label_w := row.w - 16
			detail_w: f32 = 0
			if command.detail != "" {
				natural := Measure_Text(g, row_style, command.label, 0).x
				label_w = min(natural + 20, row.w - 16)
				detail_x = row.x + 8 + label_w + 12
				detail_w = row.x + row.w - 8 - detail_x
			}
			draw_text(g, label_style, command.label,
				Rect{x = row.x + 8, y = row.y, w = label_w, h = row.h}, row_ink)
			if detail_w >= 48 {
				detail_style := row_style
				detail_style.align = .Left
				draw_text(g, detail_style, command.detail,
					Rect{x = detail_x, y = row.y, w = detail_w, h = row.h},
					Scale_Colour(row_ink, 0.62))
			}
			y += PALETTE_ROW
		}
	}
}
