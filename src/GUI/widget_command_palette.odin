//* The command palette: a searchable list of program commands.

package GUI

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

overlay_contains_fold :: proc(haystack, needle: string) -> bool {
	if needle == "" { return true }
	n := len(needle)
	if n > len(haystack) { return false }
	for i in 0 ..= len(haystack) - n {
		if strings.equal_fold(haystack[i:i+n], needle) { return true }
	}
	return false
}

Command_Palette_Opts :: struct {
	Base_Opts: Base_Opts,
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
	w.data = Command_Palette_Data{selected = -1, text = strings.clone("")}
	w.focus_mode = .All
	w.mouse_filter = .Ignore
	w.focus_neighbour = {id, id, id, id}
	w.state -= Widget_State{.Visible}
	return id
}

Command_Palette_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	command_palette_sync(g, id)
	#partial switch &d in w.data {
	case Command_Palette_Data:
		d.visible = true
		delete(d.text)
		d.text = strings.clone("")
		d.selected = -1
	}
	popup_open_core(g, id)
}

Command_Palette_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Command_Palette_Data:
		d.visible = false
		d.selected = -1
	}
	Popup_Close(g, id)
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

//* Adds enabled program commands without replacing existing entries.
command_palette_sync :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }
	for command in g.commands.list {
		if !command.enabled { continue }
		found := false
		for existing in d.commands {
			if existing.label == command.name {
				found = true
				break
			}
		}
		if !found {
			append(&d.commands, Palette_Command{
				label    = command.name,
				action   = command.action,
				keywords = command.name,
			})
		}
	}
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

command_palette_data :: proc(g: ^GUI, id: Widget_ID) -> ^Command_Palette_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Command_Palette_Data:
		return &d
	}
	return nil
}

palette_command_matches :: proc(command: Palette_Command, filter: string) -> bool {
	return filter == "" ||
		overlay_contains_fold(command.label, filter) ||
		overlay_contains_fold(command.keywords, filter)
}

Command_Palette_Count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := command_palette_data(g, id)
	if d == nil { return 0 }
	count := 0
	for command in d.commands {
		if palette_command_matches(command, d.text) { count += 1 }
	}
	return count
}

command_palette_reset :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }
	d.selected = Command_Palette_Count(g, id) > 0 ? 0 : -1
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
}

command_palette_run :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }

	action: proc(g: ^GUI, id: Widget_ID)
	index := 0
	for command in d.commands {
		if !palette_command_matches(command, d.text) { continue }
		if index == d.selected {
			action = command.action
			break
		}
		index += 1
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
}

draw_command_palette :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Command_Palette_Data:
		if !d.visible { return }

		rows := Command_Palette_Count(g, id)
		panel := Rect{
			x = content.x,
			y = content.y,
			w = content.w,
			h = PALETTE_FIELD_HEIGHT + f32(rows) * PALETTE_ROW,
		}
		draw_rect(g, panel, RGBA(0.11, 0.12, 0.15, 0.98), 8)

		ink := resolved_text_colour(g, id, w)
		row_style := resolved_style(g, w).text
		row_style.valign = .Center

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
		index := 0
		for command in d.commands {
			if !palette_command_matches(command, d.text) { continue }

			row := Rect{x = content.x + 4, y = y, w = content.w - 8, h = PALETTE_ROW}
			row_ink := ink
			if index == d.selected {
				draw_rect(g, row, RGBA(0.16, 0.42, 0.82, 1), 4)
				row_ink = RGBA(1, 1, 1, 1)
			}
			draw_text(g, row_style, command.label,
				Rect{x = row.x + 8, y = row.y, w = row.w - 16, h = row.h}, row_ink)
			y += PALETTE_ROW
			index += 1
		}
	}
}