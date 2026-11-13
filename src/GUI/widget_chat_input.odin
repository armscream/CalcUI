//* A chat history with a text field at the bottom.

package GUI

import "core:strings"
import virt "core:mem/virtual"

CHAT_INPUT_FIELD_HEIGHT :: 28
CHAT_LINE_HEIGHT        :: 20
CHAT_WHEEL_LINES        :: 3

Chat_Input_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Chat_Input :: proc(g: ^GUI, parent: Widget_ID, opts: Chat_Input_Opts) -> Widget_ID {
	kind_register(g, .ChatInput, chat_input_kind())
	id := New_Widget(g, .ChatInput, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Chat_Input_Data{}
	w.focus_mode = .All
	w.base_min_size.y = max(w.base_min_size.y, f32(CHAT_INPUT_FIELD_HEIGHT * 2))
	w.min_size.y = w.base_min_size.y
	return id
}

chat_input_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw       = draw_chat_input,
		click      = click_chat_input,
		key        = key_chat_input,
		pointer    = pointer_chat_input,
		theme_name = "ChatInput",
	}
}

chat_input_data :: proc(g: ^GUI, id: Widget_ID) -> ^Chat_Input_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Chat_Input_Data:
		return &d
	}
	return nil
}

chat_input_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := chat_input_data(g, id)
	if d == nil { return "" }
	return d.text
}

chat_input_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	d := chat_input_data(g, id)
	if d == nil { return }
	new_text := strings.clone(text)
	delete(d.text)
	d.text = new_text
	invalidate(g, id, Dirty_Flags{.Visual})
}

chat_input_add_line :: proc(g: ^GUI, id: Widget_ID, who, text: string, system: bool = false) {
	d := chat_input_data(g, id)
	if d == nil { return }
	allocator := virt.arena_allocator(&g.arena)
	append(&d.lines, Chat_Line{
		who = strings.clone(who, allocator),
		text = strings.clone(text, allocator),
		system = system,
	})
	invalidate(g, id, Dirty_Flags{.Visual})
}

chat_input_line_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := chat_input_data(g, id)
	if d == nil { return 0 }
	return len(d.lines)
}

chat_input_line_text :: proc(g: ^GUI, id: Widget_ID, index: int) -> string {
	d := chat_input_data(g, id)
	if d == nil || index < 0 || index >= len(d.lines) { return "" }
	return d.lines[index].text
}

chat_input_clear_lines :: proc(g: ^GUI, id: Widget_ID) {
	d := chat_input_data(g, id)
	if d == nil { return }
	clear(&d.lines)
	d.scroll = 0
	invalidate(g, id, Dirty_Flags{.Visual})
}

chat_input_visible_lines :: proc(g: ^GUI, w: ^Widget) -> int {
	if w == nil { return 0 }
	layout := chat_input_layout(chat_input_content(g, w))
	return max(0, int(layout.talk.h / f32(CHAT_LINE_HEIGHT)))
}

chat_input_scroll :: proc(g: ^GUI, id: Widget_ID, lines: f32) {
	d := chat_input_data(g, id)
	if d == nil { return }

	d.scroll += lines * f32(CHAT_LINE_HEIGHT)
	older := len(d.lines) - chat_input_visible_lines(g, Widget_Get(g, id))
	limit := f32(max(0, older)) * f32(CHAT_LINE_HEIGHT)
	d.scroll = clamp(d.scroll, 0, limit)
}

chat_input_submit :: proc(g: ^GUI, id: Widget_ID) {
	d := chat_input_data(g, id)
	if d == nil || strings.trim_space(d.text) == "" { return }

	chat_input_add_line(g, id, "", d.text)
	sent := d.lines[len(d.lines) - 1].text
	delete(d.text)
	d.text = strings.clone("")
	signal_submitted(g, id, sent)
	invalidate(g, id, Dirty_Flags{.Visual})
}

chat_input_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

Chat_Input_Layout :: struct {
	talk:  Rect,
	field: Rect,
}

chat_input_layout :: proc(content: Rect) -> Chat_Input_Layout {
	field_h := min(f32(CHAT_INPUT_FIELD_HEIGHT), content.h)
	talk_h := max(0, content.h - field_h - 4)
	return Chat_Input_Layout{
		talk = Rect{x = content.x, y = content.y, w = content.w, h = talk_h},
		field = Rect{
			x = content.x,
			y = content.y + content.h - field_h,
			w = content.w,
			h = field_h,
		},
	}
}

chat_input_type :: proc(g: ^GUI, id: Widget_ID, c: string) {
	d := chat_input_data(g, id)
	if d == nil || c == "" { return }

	snapshot := undo_snapshot(g, id)
	new_text := strings.concatenate({d.text, c})
	delete(d.text)
	d.text = new_text
	undo_commit(g, id, &snapshot)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

chat_input_backspace :: proc(g: ^GUI, id: Widget_ID) {
	d := chat_input_data(g, id)
	if d == nil || d.text == "" { return }

	end := len(d.text)
	for end > 0 && (d.text[end - 1] & 0xC0) == 0x80 {
		end -= 1
	}
	if end > 0 { end -= 1 }

	snapshot := undo_snapshot(g, id)
	new_text := strings.clone(d.text[:end])
	delete(d.text)
	d.text = new_text
	undo_commit(g, id, &snapshot)
	invalidate(g, id, Dirty_Flags{.Visual})
	caret_reset(g)
}

key_chat_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	ctrl := .Ctrl in e.mods
	shift := .Shift in e.mods

	if ctrl {
		#partial switch e.key {
		case .Z:
			if shift {
				text_input_redo(g, id)
			} else {
				text_input_undo(g, id)
			}
			Event_Handled(g)
			return
		case .Y:
			text_input_redo(g, id)
			Event_Handled(g)
			return
		}
	}

	#partial switch e.key {
	case .Enter:
		chat_input_submit(g, id)
	case .Backspace:
		chat_input_backspace(g, id)
	case:
		c := key_character(g, e.key, shift)
		if c != "" { chat_input_type(g, id, c) }
	}
}

click_chat_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	layout := chat_input_layout(chat_input_content(g, w))
	if rect_contains(layout.field, g.pointer.x, g.pointer.y) {
		focus_set(g, id)
	}
}

pointer_chat_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel { return }
	d := chat_input_data(g, id)
	if d == nil { return }

	before := d.scroll
	chat_input_scroll(g, id, -e.amount * CHAT_WHEEL_LINES)
	if d.scroll == before { return }
	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

draw_chat_input :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := chat_input_data(g, id)
	if d == nil { return }

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	layout := chat_input_layout(content)

	text_style := style.text
	text_style.valign = .Center
	visible := max(0, int(layout.talk.h / f32(CHAT_LINE_HEIGHT)))
	scrolled := int(d.scroll / f32(CHAT_LINE_HEIGHT))
	first := max(0, len(d.lines) - visible - scrolled)
	y := layout.talk.y + layout.talk.h - f32(len(d.lines) - first) * CHAT_LINE_HEIGHT

	for line, i in d.lines {
		if i < first { continue }
		row := Rect{x = layout.talk.x, y = y, w = layout.talk.w, h = CHAT_LINE_HEIGHT}
		if row.y + row.h > layout.talk.y + layout.talk.h {
			y += CHAT_LINE_HEIGHT
			continue
		}

		row_ink := ink
		if line.system { row_ink = Scale_Colour(ink, 0.7) }
		label := row
		if line.who != "" {
			who_text := strings.concatenate({line.who, ":"}, virt.arena_allocator(&g.frame_arena))
			who_width := text_measure(g, text_style, who_text, 0).x
			draw_text(g, text_style, who_text,
				Rect{x = row.x, y = row.y, w = who_width, h = row.h}, COLLECT_ACCENT)
			label.x += who_width + 6
			label.w -= who_width + 6
		}
		draw_text(g, text_style, line.text, label, row_ink)
		y += CHAT_LINE_HEIGHT
	}

	draw_rect(g, layout.field, COLLECT_PANEL, 4)
	field_style := style.text
	field_style.valign = .Center
	field := Rect{
		x = layout.field.x + 8,
		y = layout.field.y,
		w = layout.field.w - 16,
		h = layout.field.h,
	}
	draw_text(g, field_style, d.text, field, ink)
}