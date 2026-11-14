package GUI

import "core:fmt"
import virt "core:mem/virtual"

DATE_PICKER_FIELD_HEIGHT :: 28
DATE_PICKER_GAP :: 2
DATE_PICKER_HEAD_HEIGHT :: 24
DATE_PICKER_WEEK_HEIGHT :: 18
DATE_PICKER_CELL :: 26

Date_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	year:      int,
	month:     int,
	day:       int,
}

Make_Date_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Date_Picker_Opts) -> Widget_ID {
	kind_register(g, .DatePicker, date_picker_kind())
	id := New_Widget(g, .DatePicker, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)

	year := opts.year
	if year == 0 {year = 2026}
	month := opts.month
	if month < 1 || month > 12 {month = 1}
	day := opts.day
	if day < 1 || day > date_days_in_month(year, month) {day = 1}

	w.data = Date_Picker_Data{year = year, month = month, day = day}
	w.focus_mode = .All
	w.base_min_size.y = max(w.base_min_size.y, DATE_PICKER_FIELD_HEIGHT)
	w.min_size.y = w.base_min_size.y
	return id
}

date_picker_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_date_picker,
		click = click_date_picker,
		measure = measure_date_picker,
		theme_name = "DatePicker",
	}
}

date_picker_data :: proc(g: ^GUI, id: Widget_ID) -> ^Date_Picker_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Date_Picker_Data:
		return &d
	}
	return nil
}

date_picker_date :: proc(g: ^GUI, id: Widget_ID) -> (year, month, day: int) {
	d := date_picker_data(g, id)
	if d == nil {return 0, 0, 0}
	return d.year, d.month, d.day
}

date_picker_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	d := date_picker_data(g, id)
	if d == nil {return ""}
	return fmt.aprintf(
		"%04d-%02d-%02d",
		d.year,
		d.month,
		d.day,
		allocator = virt.arena_allocator(&g.frame_arena),
	)
}

date_picker_set_date :: proc(g: ^GUI, id: Widget_ID, year, month, day: int) {
	d := date_picker_data(g, id)
	if d == nil || month < 1 || month > 12 {return}
	if day < 1 || day > date_days_in_month(year, month) {return}
	if d.year == year && d.month == month && d.day == day {return}

	d.year = year
	d.month = month
	d.day = day
	signal_text_changed(g, id, date_picker_text(g, id))
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

date_picker_is_open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	d := date_picker_data(g, id)
	if d == nil {return false}
	return d.open
}

date_picker_set_open :: proc(g: ^GUI, id: Widget_ID, open: bool) {
	d := date_picker_data(g, id)
	if d == nil || d.open == open {return}
	d.open = open
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
}

date_picker_months: [12]string = {
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
}

date_picker_weekdays: [7]string = {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}

date_days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 1, 3, 5, 7, 8, 10, 12: return 31
	case 4, 6, 9, 11: return 30
	case 2:
		if date_is_leap(year) {return 29}
		return 28
	}
	return 30
}

date_is_leap :: proc(year: int) -> bool {
	if year % 400 == 0 {return true}
	if year % 100 == 0 {return false}
	return year % 4 == 0
}

date_weekday :: proc(year, month, day: int) -> int {
	y, m := year, month
	if m < 3 {
		y -= 1
		m += 12
	}
	w := (y + y / 4 - y / 100 + y / 400 + (13 * (m + 1)) / 5 + day - 1) % 7
	return (w + 6) % 7
}

date_first_weekday :: proc(year, month: int) -> int {
	return date_weekday(year, month, 1)
}

Date_Picker_Layout :: struct {
	field: Rect,
	head:  Rect,
	week:  Rect,
	days:  Rect,
}

date_picker_layout :: proc(content: Rect, open: bool) -> Date_Picker_Layout {
	layout := Date_Picker_Layout{field = content}
	field_h := min(f32(DATE_PICKER_FIELD_HEIGHT), content.h)
	layout.field = Rect{x = content.x, y = content.y, w = content.w, h = field_h}
	if !open {return layout}

	top := content.y + field_h + DATE_PICKER_GAP
	layout.head = Rect{x = content.x, y = top, w = content.w, h = DATE_PICKER_HEAD_HEIGHT}
	layout.week = Rect{
		x = content.x,
		y = layout.head.y + layout.head.h,
		w = content.w,
		h = DATE_PICKER_WEEK_HEIGHT,
	}
	layout.days = Rect{
		x = content.x,
		y = layout.week.y + layout.week.h,
		w = content.w,
		h = content.y + content.h - layout.week.y - layout.week.h,
	}
	return layout
}

date_picker_panel_height :: proc(year, month: int) -> f32 {
	count := date_days_in_month(year, month)
	first := date_first_weekday(year, month)
	rows := (count - 1 + first) / 7 + 1
	return f32(DATE_PICKER_GAP + DATE_PICKER_HEAD_HEIGHT + DATE_PICKER_WEEK_HEIGHT) +
		f32(rows * DATE_PICKER_CELL)
}

measure_date_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := date_picker_data(g, id)
	if d == nil {return Vec2{}}

	pad := resolved_style(g, w).box.content_margin
	width := f32(7 * DATE_PICKER_CELL)
	height := f32(DATE_PICKER_FIELD_HEIGHT)
	if d.open {
		height += date_picker_panel_height(d.year, d.month)
	}
	return Vec2{width + pad[0] + pad[2], height + pad[1] + pad[3]}
}

date_picker_day_at :: proc(days: Rect, first_weekday, count: int, p: Vec2) -> int {
	if count <= 0 {return -1}
	column := int((p.x - days.x) / f32(DATE_PICKER_CELL))
	row := int((p.y - days.y) / f32(DATE_PICKER_CELL))
	if column < 0 || column > 6 || row < 0 {return -1}

	index := row * 7 + column - first_weekday + 1
	if index < 1 || index > count {return -1}
	return index
}

date_picker_day_point :: proc(year, month, day: int) -> Vec2 {
	index := day - 1 + date_first_weekday(year, month)
	return Vec2{
		f32(index % 7) * f32(DATE_PICKER_CELL) + f32(DATE_PICKER_CELL) * 0.5,
		f32(index / 7) * f32(DATE_PICKER_CELL) + f32(DATE_PICKER_CELL) * 0.5,
	}
}

date_picker_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

click_date_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := date_picker_data(g, id)
	if d == nil {return}

	layout := date_picker_layout(date_picker_content(g, w), d.open)
	if !d.open {
		if rect_contains(layout.field, g.pointer.x, g.pointer.y) {
			date_picker_set_open(g, id, true)
		}
		return
	}

	arrow := f32(DATE_PICKER_CELL) * 0.5
	left := Rect{x = layout.head.x, y = layout.head.y, w = arrow, h = layout.head.h}
	right := Rect{
		x = layout.head.x + layout.head.w - arrow,
		y = layout.head.y,
		w = arrow,
		h = layout.head.h,
	}
	if rect_contains(left, g.pointer.x, g.pointer.y) {
		date_picker_go_month(g, id, -1)
		return
	}
	if rect_contains(right, g.pointer.x, g.pointer.y) {
		date_picker_go_month(g, id, 1)
		return
	}

	if rect_contains(layout.days, g.pointer.x, g.pointer.y) {
		index := date_picker_day_at(
			layout.days,
			date_first_weekday(d.year, d.month),
			date_days_in_month(d.year, d.month),
			g.pointer,
		)
		if index < 0 {return}
		date_picker_set_date(g, id, d.year, d.month, index)
		date_picker_set_open(g, id, false)
		return
	}

	if !rect_contains(layout.field, g.pointer.x, g.pointer.y) {
		date_picker_set_open(g, id, false)
	}
}

date_picker_go_month :: proc(g: ^GUI, id: Widget_ID, delta: int) {
	d := date_picker_data(g, id)
	if d == nil {return}

	month := d.month + delta
	year := d.year
	if month < 1 {
		month = 12
		year -= 1
	} else if month > 12 {
		month = 1
		year += 1
	}

	day := min(d.day, date_days_in_month(year, month))
	date_picker_set_date(g, id, year, month, day)
}

draw_date_picker :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := date_picker_data(g, id)
	if d == nil {return}

	style := resolved_style(g, w)
	ink := resolved_text_colour(g, id, w)
	layout := date_picker_layout(content, d.open)
	text_style := style.text
	text_style.valign = .Center
	draw_text(g, text_style, date_picker_text(g, id),
		Rect{x = layout.field.x + 6, y = layout.field.y, w = layout.field.w - 12, h = layout.field.h},
		ink,
	)

	if !d.open {return}

	head_style := style.text
	head_style.valign = .Center
	head_style.align = .Center
	name := fmt.aprintf(
		"%s %d",
		date_picker_months[d.month - 1],
		d.year,
		allocator = virt.arena_allocator(&g.frame_arena),
	)
	draw_text(g, head_style, name, layout.head, ink)
	draw_date_picker_arrow(g, layout.head, true, ink)
	draw_date_picker_arrow(g, layout.head, false, ink)

	week_style := style.text
	week_style.align = .Center
	week_style.valign = .Center
	for i in 0 ..< 7 {
		cell := Rect{
			x = layout.week.x + f32(i * DATE_PICKER_CELL),
			y = layout.week.y,
			w = DATE_PICKER_CELL,
			h = layout.week.h,
		}
		draw_text(g, week_style, date_picker_weekdays[i], cell, Scale_Colour(ink, 0.7))
	}

	count := date_days_in_month(d.year, d.month)
	first := date_first_weekday(d.year, d.month)
	day_style := style.text
	day_style.align = .Center
	day_style.valign = .Center

	for day in 1 ..= count {
		index := day - 1 + first
		cell := Rect{
			x = layout.days.x + f32(index % 7 * DATE_PICKER_CELL),
			y = layout.days.y + f32(index / 7 * DATE_PICKER_CELL),
			w = DATE_PICKER_CELL,
			h = DATE_PICKER_CELL,
		}
		if cell.y >= layout.days.y + layout.days.h {break}
		if day == d.day {
			draw_rect(g, cell, COLLECT_ACCENT, 4)
		}

		day_ink := ink
		if day == d.day {day_ink = RGBA(1, 1, 1, 1)}
		day_text := fmt.aprintf("%d", day, allocator = virt.arena_allocator(&g.frame_arena))
		draw_text(g, day_style, day_text, cell, day_ink)
	}
}

draw_date_picker_arrow :: proc(g: ^GUI, head: Rect, back: bool, colour: Colour) {
	size := f32(4)
	margin := f32(12)
	cx := head.x + margin
	if !back {
		cx = head.x + head.w - margin
	}
	cy := head.y + head.h * 0.5

	points: [][2]f32
	if back {
		points = [][2]f32{
			{cx + size, cy - size},
			{cx + size, cy + size},
			{cx - size, cy},
		}
	} else {
		points = [][2]f32{
			{cx - size, cy - size},
			{cx - size, cy + size},
			{cx + size, cy},
		}
	}
	draw_polygon(g.target, points, colour, g.atlas_texture)
}