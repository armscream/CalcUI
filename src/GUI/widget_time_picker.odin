package GUI

import "core:fmt"
import virt "core:mem/virtual"

TIME_PICKER_FIELD_HEIGHT :: 28
TIME_PICKER_GAP           :: 2
TIME_PICKER_CELL          :: 26
TIME_PICKER_HOUR_COLUMNS  :: 6
TIME_PICKER_MINUTE_COLUMNS :: 6
TIME_PICKER_MINUTE_STEP   :: 5

Time_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	hour:      int,
	minute:    int,
}

Make_Time_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Time_Picker_Opts) -> Widget_ID {
	kind_register(g, .TimePicker, time_picker_kind())
	id := New_Widget(g, .TimePicker, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	hour := clamp(opts.hour, 0, 23)
	minute := clamp(opts.minute, 0, 59)
	w.data = Time_Picker_Data {
		hour   = hour,
		minute = minute,
	}
	w.focus_mode = .All
	if w.base_min_size.y < TIME_PICKER_FIELD_HEIGHT {w.base_min_size.y = TIME_PICKER_FIELD_HEIGHT}
	w.min_size.y = w.base_min_size.y
	return id
}

time_picker_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_time_picker,
		click = click_time_picker,
		measure = measure_time_picker,
		theme_name = "TimePicker",
	}
}

time_picker_data :: proc(g: ^GUI, id: Widget_ID) -> ^Time_Picker_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Time_Picker_Data:
		return &d
	}
	return nil
}

time_picker_time :: proc(g: ^GUI, id: Widget_ID) -> (hour, minute: int) {
	d := time_picker_data(g, id)
	if d == nil {return 0, 0}
	return d.hour, d.minute
}

time_picker_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := time_picker_data(g, id)
	if d == nil {return ""}
	return fmt.aprintf(
		"%02d:%02d",
		d.hour,
		d.minute,
		allocator = virt.arena_allocator(&g.frame_arena),
	)
}

//* Sets the time and emits the text-changed signal when it changes.
time_picker_set_time :: proc(g: ^GUI, id: Widget_ID, hour, minute: int) {
	d := time_picker_data(g, id)
	if d == nil {return}
	hour_value := clamp(hour, 0, 23)
	minute_value := clamp(minute, 0, 59)
	if d.hour == hour_value && d.minute == minute_value {return}
	d.hour = hour_value
	d.minute = minute_value
	signal_text_changed(g, id, time_picker_text(g, id))
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Adds minutes, wrapping across hour and day boundaries.
time_picker_add_minutes :: proc(g: ^GUI, id: Widget_ID, minutes: int) {
	d := time_picker_data(g, id)
	if d == nil {return}
	total := d.hour * 60 + d.minute + minutes
	total = total % (24 * 60)
	if total < 0 {total += 24 * 60}
	time_picker_set_time(g, id, total / 60, total % 60)
}

time_picker_is_open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := time_picker_data(g, id)
	if d == nil {return false}
	return d.open
}

time_picker_set_open :: proc(g: ^GUI, id: Widget_ID, open: bool) {
	d := time_picker_data(g, id)
	if d == nil {return}
	if d.open == open {return}
	d.open = open
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

Time_Picker_Layout :: struct {
	field:   Rect,
	hours:   Rect,
	minutes: Rect,
}

time_picker_layout :: proc(content: Rect, open: bool) -> Time_Picker_Layout {
	layout := Time_Picker_Layout {
		field = content,
	}
	field_h := min(f32(TIME_PICKER_FIELD_HEIGHT), content.h)
	layout.field = Rect {
		x = content.x,
		y = content.y,
		w = content.w,
		h = field_h,
	}
	if !open {return layout}

	top := content.y + field_h + TIME_PICKER_GAP
	hour_rows := 24 / TIME_PICKER_HOUR_COLUMNS
	hours := Rect {
		x = content.x,
		y = top,
		w = content.w,
		h = f32(hour_rows) * f32(TIME_PICKER_CELL),
	}
	minute_count := 60 / TIME_PICKER_MINUTE_STEP
	minute_rows := minute_count / TIME_PICKER_MINUTE_COLUMNS
	minutes := Rect {
		x = content.x,
		y = hours.y + hours.h,
		w = content.w,
		h = f32(minute_rows) * f32(TIME_PICKER_CELL),
	}
	layout.hours = hours
	layout.minutes = minutes
	return layout
}

time_picker_panel_height :: proc() -> f32 {
	layout := time_picker_layout(
		Rect{x = 0, y = 0, w = 0, h = f32(TIME_PICKER_FIELD_HEIGHT)},
		true,
	)
	return layout.minutes.y + layout.minutes.h - layout.hours.y
}

measure_time_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := time_picker_data(g, id)
	if d == nil {return {}}
	style := resolved_style(g, w)
	pad := style.box.content_margin
	columns := max(TIME_PICKER_HOUR_COLUMNS, TIME_PICKER_MINUTE_COLUMNS)
	width := f32(columns * TIME_PICKER_CELL)
	height := f32(TIME_PICKER_FIELD_HEIGHT)
	if d.open {
		height += time_picker_panel_height()
	}
	return Vec2{width + pad[0] + pad[2], height + pad[1] + pad[3]}
}

time_picker_hour_at :: proc(hours: Rect, p: Vec2) -> int {
	column := int((p.x - hours.x) / f32(TIME_PICKER_CELL))
	row := int((p.y - hours.y) / f32(TIME_PICKER_CELL))
	if column < 0 || column >= TIME_PICKER_HOUR_COLUMNS {return -1}
	if row < 0 {return -1}
	hour := row * TIME_PICKER_HOUR_COLUMNS + column
	if hour < 0 || hour > 23 {return -1}
	return hour
}

time_picker_minute_at :: proc(minutes: Rect, p: Vec2) -> int {
	column := int((p.x - minutes.x) / f32(TIME_PICKER_CELL))
	row := int((p.y - minutes.y) / f32(TIME_PICKER_CELL))
	if column < 0 || column >= TIME_PICKER_MINUTE_COLUMNS {return -1}
	if row < 0 {return -1}
	index := row * TIME_PICKER_MINUTE_COLUMNS + column
	count := 60 / TIME_PICKER_MINUTE_STEP
	if index < 0 || index >= count {return -1}
	return index * TIME_PICKER_MINUTE_STEP
}

time_picker_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

click_time_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := time_picker_data(g, id)
	if d == nil {return}
	content := time_picker_content(g, w)
	layout := time_picker_layout(content, d.open)

	if !d.open {
		if rect_contains(layout.field, g.pointer.x, g.pointer.y) {
			time_picker_set_open(g, id, true)
		}
		return
	}

	if rect_contains(layout.hours, g.pointer.x, g.pointer.y) {
		hour := time_picker_hour_at(layout.hours, g.pointer)
		if hour >= 0 {time_picker_set_time(g, id, hour, d.minute)}
		return
	}
	if rect_contains(layout.minutes, g.pointer.x, g.pointer.y) {
		minute := time_picker_minute_at(layout.minutes, g.pointer)
		if minute >= 0 {time_picker_set_time(g, id, d.hour, minute)}
		return
	}
	if !rect_contains(layout.field, g.pointer.x, g.pointer.y) {
		time_picker_set_open(g, id, false)
	}
}

draw_time_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := time_picker_data(g, id)
	if d == nil {return}
	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	text_style := style.text
	text_style.valign = .Center

	layout := time_picker_layout(content, d.open)
	label := Rect {
		x = layout.field.x + 6,
		y = layout.field.y,
		w = layout.field.w - 12,
		h = layout.field.h,
	}
	draw_text(g, text_style, time_picker_text(g, id), label, ink)

	if !d.open {return}

	cell_style := style.text
	cell_style.align = .Center
	cell_style.valign = .Center

	for hour in 0 ..< 24 {
		index := hour
		cell := Rect {
			x = layout.hours.x + f32(index % TIME_PICKER_HOUR_COLUMNS) * f32(TIME_PICKER_CELL),
			y = layout.hours.y + f32(index / TIME_PICKER_HOUR_COLUMNS) * f32(TIME_PICKER_CELL),
			w = TIME_PICKER_CELL,
			h = TIME_PICKER_CELL,
		}
		if cell.y >= layout.hours.y + layout.hours.h {break}
		cell_ink := ink
		if hour == d.hour {
			draw_rect(g, cell, COLLECT_ACCENT, 4)
			cell_ink = RGBA(1, 1, 1, 1)
		}
		label := fmt.aprintf("%d", hour, allocator = virt.arena_allocator(&g.frame_arena))
		draw_text(g, cell_style, label, cell, cell_ink)
	}

	count := 60 / TIME_PICKER_MINUTE_STEP
	for index in 0 ..< count {
		minute := index * TIME_PICKER_MINUTE_STEP
		cell := Rect {
			x = layout.minutes.x + f32(index % TIME_PICKER_MINUTE_COLUMNS) * f32(TIME_PICKER_CELL),
			y = layout.minutes.y + f32(index / TIME_PICKER_MINUTE_COLUMNS) * f32(TIME_PICKER_CELL),
			w = TIME_PICKER_CELL,
			h = TIME_PICKER_CELL,
		}
		if cell.y >= layout.minutes.y + layout.minutes.h {break}
		cell_ink := ink
		if minute == d.minute {
			draw_rect(g, cell, COLLECT_ACCENT, 4)
			cell_ink = RGBA(1, 1, 1, 1)
		}
		label := fmt.aprintf("%02d", minute, allocator = virt.arena_allocator(&g.frame_arena))
		draw_text(g, cell_style, label, cell, cell_ink)
	}
}