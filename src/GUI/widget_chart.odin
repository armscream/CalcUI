//* Bar, line and pie charts. The data is behind a pointer because a
//* chart can hold a lot of numbers.

package GUI

import "core:fmt"
import "core:log"
import "core:math"
import virt "core:mem/virtual"

//* How many pieces the arc of a pie slice is cut into.
CHART_PIE_SEGMENTS :: 24

Chart_Opts :: struct {
	Base_Opts: Base_Opts,
	kind:      Chart_Kind,
}

//* Makes a chart. Its series are added one by one.
Make_Chart :: proc(g: ^GUI, parent: Widget_ID, opts: Chart_Opts) -> Widget_ID {
	kind_register(g, .Chart, chart_kind())
	id := New_Widget(g, .Chart, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	chart, err := virt.new(&g.arena, Chart)
	if err != nil {
		log.panicf("chart allocation failed: %v", err)
	}
	chart^ = Chart{kind = opts.kind, min = 0, max = 1, selected = -1}
	w.data = Chart_Data{chart = chart}
	return id
}

chart_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw       = draw_chart,
		click      = click_chart,
		update     = update_chart,
		style      = Style{},
		theme_name = "Chart",
	}
}

chart_data :: proc(g: ^GUI, id: Widget_ID) -> ^Chart_Data {
	w := Widget_Get(g, id)
	if w == nil {
		return nil
	}
	#partial switch &d in w.data {
	case Chart_Data:
		return &d
	}
	return nil
}

chart_of :: proc(g: ^GUI, id: Widget_ID) -> ^Chart {
	d := chart_data(g, id)
	if d == nil {
		return nil
	}
	return d.chart
}

//* == The data ==

//* Adds a series and updates the chart bounds. A colour without alpha
//* uses one from the default palette.
chart_add_series :: proc(g: ^GUI, id: Widget_ID, name: string, values: []f32, colour: Colour) -> int {
	chart := chart_of(g, id)
	if chart == nil {
		return -1
	}
	series := Chart_Series{name = name, colour = colour}
	for v in values {
		append(&series.values, v)
	}
	append(&chart.series, series)
	chart_work_out_bounds(chart)
	invalidate(g, id, Dirty_Flags{.Visual})
	return len(chart.series) - 1
}

chart_work_out_bounds :: proc(chart: ^Chart) {
	lo, hi: f32
	found := false
	for series in chart.series {
		for v in series.values {
			if !found {
				lo, hi = v, v
				found = true
				continue
			}
			lo = min(lo, v)
			hi = max(hi, v)
		}
	}
	if !found {
		chart.min = 0
		chart.max = 1
		return
	}
	chart.min = lo
	chart.max = hi
}

chart_set_kind :: proc(g: ^GUI, id: Widget_ID, kind: Chart_Kind) {
	chart := chart_of(g, id)
	if chart == nil {
		return
	}
	chart.kind = kind
	invalidate(g, id, Dirty_Flags{.Visual})
}

chart_series_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	chart := chart_of(g, id)
	if chart == nil {
		return 0
	}
	return len(chart.series)
}

//* The greatest number of points in any series.
chart_point_count :: proc(chart: ^Chart) -> int {
	count := 0
	for series in chart.series {
		if len(series.values) > count {
			count = len(series.values)
		}
	}
	return count
}

chart_set_labels :: proc(g: ^GUI, id: Widget_ID, labels: []string) {
	chart := chart_of(g, id)
	if chart == nil {
		return
	}
	clear(&chart.labels)
	for label in labels {
		append(&chart.labels, label)
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Returns the first series' value at a point.
chart_value_at :: proc(g: ^GUI, id: Widget_ID, index: int) -> f32 {
	chart := chart_of(g, id)
	if chart == nil || index < 0 || len(chart.series) == 0 {
		return 0
	}
	values := chart.series[0].values
	if index >= len(values) {
		return 0
	}
	return values[index]
}

//* Returns the point under the pointer, or -1 when there is none.
chart_point_at :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) -> int {
	chart := chart_of(g, id)
	if chart == nil {
		return -1
	}
	w := Widget_Get(g, id)
	if w == nil {
		return -1
	}
	content := content_rect(g, w)
	count := chart_point_count(chart)
	if count <= 0 {
		return -1
	}
	switch chart.kind {
	case .Bar:
		plot := chart_plot_rect(content)
		if !rect_contains(plot, pos.x, pos.y) {
			return -1
		}
		slot := plot.w / f32(count)
		if slot <= 0 {
			return -1
		}
		return clamp(int((pos.x - plot.x) / slot), 0, count - 1)
	case .Line:
		plot := chart_plot_rect(content)
		if !rect_contains(plot, pos.x, pos.y) {
			return -1
		}
		if count == 1 {
			return 0
		}
		f := (pos.x - plot.x) / plot.w * f32(count - 1)
		return clamp(int(math.round(f)), 0, count - 1)
	case .Pie:
		return chart_pie_point_at(chart, content, pos)
	}
	return -1
}

//* == The drawing ==

CHART_AXIS_WIDTH      :: 44
CHART_LABEL_HEIGHT    :: 18
CHART_AXIS_THICKNESS  :: 1
CHART_PIE_MARGIN      :: 12
CHART_DOT_SIZE        :: 6
CHART_LINE_WIDTH      :: 2

//* Default series colours.
CHART_COLOURS := [8]Colour{
	{0.35, 0.74, 1.00, 1},
	{1.00, 0.55, 0.30, 1},
	{0.40, 0.85, 0.50, 1},
	{0.95, 0.45, 0.55, 1},
	{0.75, 0.55, 0.95, 1},
	{0.95, 0.85, 0.35, 1},
	{0.35, 0.85, 0.85, 1},
	{0.72, 0.74, 0.80, 1},
}

draw_chart :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	chart := chart_of(g, id)
	if chart == nil {
		return
	}
	switch chart.kind {
	case .Bar:
		draw_chart_bars(g, chart, w, content)
	case .Line:
		draw_chart_line(g, chart, w, content)
	case .Pie:
		draw_chart_pie(g, chart, w, content)
	}
}

//* Bars are grouped by point, with one bar per series.
draw_chart_bars :: proc(g: ^GUI, chart: ^Chart, w: ^Widget, content: Rect) {
	plot := chart_plot_rect(content)
	count := chart_point_count(chart)
	if count <= 0 || len(chart.series) == 0 {
		return
	}
	slot := plot.w / f32(count)
	bar_w := slot * 0.8 / f32(len(chart.series))
	for s in 0 ..< len(chart.series) {
		series := &chart.series[s]
		colour := chart_series_colour(chart, s)
		for i in 0 ..< len(series.values) {
			y := chart_value_y(chart, plot, series.values[i])
			bottom := plot.y + plot.h
			h := bottom - y
			if h < 1 {
				h = 1
				y = bottom - 1
			}
			x := plot.x + slot * f32(i) + slot * 0.1 + bar_w * f32(s)
			draw_rect(g, Rect{x = x, y = y, w = bar_w, h = h}, colour, 0)
		}
	}
	chart_draw_axes(g, chart, w, content, plot)
	chart_draw_labels(g, chart, w, content, plot)
}

//* Each series is a line through its points, with a dot at each point.
draw_chart_line :: proc(g: ^GUI, chart: ^Chart, w: ^Widget, content: Rect) {
	plot := chart_plot_rect(content)
	for s in 0 ..< len(chart.series) {
		series := &chart.series[s]
		colour := chart_series_colour(chart, s)
		for i in 0 ..< len(series.values) {
			p := chart_point_pos(chart, plot, i, series.values[i])
			if i > 0 {
				q := chart_point_pos(chart, plot, i - 1, series.values[i-1])
				draw_thick_line(
					g.target,
					{q.x, q.y},
					{p.x, p.y},
					CHART_LINE_WIDTH,
					colour,
					g.atlas_texture,
				)
			}
			draw_rect(
				g,
				Rect{
					x = p.x - CHART_DOT_SIZE * 0.5,
					y = p.y - CHART_DOT_SIZE * 0.5,
					w = CHART_DOT_SIZE,
					h = CHART_DOT_SIZE,
				},
				colour,
				0,
			)
		}
	}
	chart_draw_axes(g, chart, w, content, plot)
	chart_draw_labels(g, chart, w, content, plot)
}

//* The first series supplies the pie slices.
draw_chart_pie :: proc(g: ^GUI, chart: ^Chart, w: ^Widget, content: Rect) {
	if len(chart.series) == 0 {
		return
	}
	series := &chart.series[0]
	total := f32(0)
	for v in series.values {
		total += max(v, f32(0))
	}
	if total <= 0 {
		return
	}
	centre, radius := chart_pie_geometry(content)
	if radius <= 0 {
		return
	}
	angle := f32(-math.PI * 0.5)
	for i in 0 ..< len(series.values) {
		share := max(series.values[i], f32(0)) / total
		span := share * f32(math.PI) * 2
		colour := chart_slice_colour(chart, i)
		points: [CHART_PIE_SEGMENTS + 2][2]f32
		n := 0
		segments := max(2, int(span / (math.PI / 12)))
		for s in 0 ..= segments {
			a := angle + span * f32(s) / f32(segments)
			points[n] = [2]f32{
				centre.x + math.cos(a) * radius,
				centre.y + math.sin(a) * radius,
			}
			n += 1
		}
		points[n] = [2]f32{centre.x, centre.y}
		n += 1
		draw_polygon(g.target, points[:n], colour, g.atlas_texture)
		angle += span
	}
	chart_draw_legend(g, chart, w, content, centre, radius)
}

//* Slice names appear beside the pie.
chart_draw_legend :: proc(
	g: ^GUI,
	chart: ^Chart,
	w: ^Widget,
	content: Rect,
	centre: Vec2,
	radius: f32,
) {
	if len(chart.labels) == 0 {
		return
	}
	x := centre.x + radius + 16
	if x + 80 > content.x + content.w {
		return
	}
	style := resolved_style(g, w)
	label_style := style.text
	label_style.valign = .Center
	top := centre.y - f32(len(chart.labels)) * 10 * 0.5
	for i in 0 ..< len(chart.labels) {
		y := top + f32(i) * 10
		draw_rect(g, Rect{x = x, y = y, w = 8, h = 8}, chart_slice_colour(chart, i), 0)
		label := Rect{x = x + 12, y = y - 2, w = content.x + content.w - x - 12, h = 12}
		draw_text(g, label_style, chart.labels[i], label, resolved_text_colour(g, w.id, w))
	}
}

//* Draws the value and point axes.
chart_draw_axes :: proc(g: ^GUI, chart: ^Chart, w: ^Widget, content: Rect, plot: Rect) {
	colour := chart_axis_colour()
	draw_quad(
		g.target,
		Rect{x = plot.x, y = plot.y, w = CHART_AXIS_THICKNESS, h = plot.h},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	draw_quad(
		g.target,
		Rect{
			x = plot.x,
			y = plot.y + plot.h - CHART_AXIS_THICKNESS,
			w = plot.w,
			h = CHART_AXIS_THICKNESS,
		},
		g.atlas.white_uv,
		colour,
		g.atlas_texture,
	)
	style := resolved_style(g, w)
	number_style := style.text
	number_style.align = .Right
	number_style.valign = .Center
	top := Rect{x = content.x, y = plot.y, w = CHART_AXIS_WIDTH - 6, h = 14}
	draw_text(g, number_style, chart_number(g, chart.max), top, resolved_text_colour(g, w.id, w))
	bottom := Rect{x = content.x, y = plot.y + plot.h - 14, w = CHART_AXIS_WIDTH - 6, h = 14}
	draw_text(g, number_style, chart_number(g, chart.min), bottom, resolved_text_colour(g, w.id, w))
}

chart_draw_labels :: proc(g: ^GUI, chart: ^Chart, w: ^Widget, content: Rect, plot: Rect) {
	if len(chart.labels) == 0 {
		return
	}
	count := chart_point_count(chart)
	style := resolved_style(g, w)
	label_style := style.text
	label_style.align = .Center
	label_style.valign = .Center
	slot := plot.w / f32(max(count, 1))
	for i in 0 ..< min(len(chart.labels), count) {
		x := chart_point_x(chart, plot, i)
		r := Rect{x = x - slot * 0.5, y = plot.y + plot.h, w = slot, h = CHART_LABEL_HEIGHT}
		if r.x < content.x {
			r.w = min(r.w, content.x + content.w - content.x)
			r.x = content.x
		}
		if r.x + r.w > content.x + content.w {
			r.w = content.x + content.w - r.x
		}
		draw_text(g, label_style, chart.labels[i], r, resolved_text_colour(g, w.id, w))
	}
}

//* == The places ==

//* Leaves room for the value axis and point labels.
chart_plot_rect :: proc(content: Rect) -> Rect {
	w := content.w - CHART_AXIS_WIDTH
	h := content.h - CHART_LABEL_HEIGHT
	if w < 0 {
		w = 0
	}
	if h < 0 {
		h = 0
	}
	return Rect{
		x = content.x + CHART_AXIS_WIDTH,
		y = content.y,
		w = w,
		h = h,
	}
}

//* Line points sit at the plot edges; bar points sit at slot centres.
chart_point_x :: proc(chart: ^Chart, plot: Rect, index: int) -> f32 {
	count := chart_point_count(chart)
	if count <= 0 {return plot.x}
	if chart.kind == .Line && count > 1 {
		return plot.x + plot.w * f32(index) / f32(count - 1)
	}
	return plot.x + plot.w * (f32(index) + 0.5) / f32(count)
}

chart_point_pos :: proc(chart: ^Chart, plot: Rect, index: int, value: f32) -> Vec2 {
	return Vec2{chart_point_x(chart, plot, index), chart_value_y(chart, plot, value)}
}

//* Maps the smallest value to the bottom and the largest to the top.
chart_value_y :: proc(chart: ^Chart, plot: Rect, value: f32) -> f32 {
	span := chart.max - chart.min
	t := f32(0)
	if span > 0 {
		t = (value - chart.min) / span
	}
	t = clamp(t, 0, 1)
	return plot.y + plot.h * (1 - t)
}

chart_pie_geometry :: proc(content: Rect) -> (centre: Vec2, radius: f32) {
	centre = Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5}
	radius = min(content.w, content.h) * 0.5 - CHART_PIE_MARGIN
	return
}

//* Returns the pie slice under the pointer, or -1 when there is none.
chart_pie_point_at :: proc(chart: ^Chart, content: Rect, pos: Vec2) -> int {
	if len(chart.series) == 0 {return -1}
	series := &chart.series[0]
	total := f32(0)
	for v in series.values {
		total += max(v, f32(0))
	}
	if total <= 0 {return -1}
	centre, radius := chart_pie_geometry(content)
	if radius <= 0 {
		return -1
	}
	dx := pos.x - centre.x
	dy := pos.y - centre.y
	if dx * dx + dy * dy > radius * radius {return -1}
	a := math.atan2(dx, -dy)
	if a < 0 {
		a += math.PI * 2
	}
	share := a / (math.PI * 2) * total
	acc := f32(0)
	for v, i in series.values {
		acc += max(v, f32(0))
		if share <= acc {return i}
	}
	return len(series.values) - 1
}

//* == The colours ==

chart_series_colour :: proc(chart: ^Chart, index: int) -> Colour {
	if index < 0 || index >= len(chart.series) {
		return CHART_COLOURS[0]
	}
	c := chart.series[index].colour
	if c.a > 0 {return c}
	return CHART_COLOURS[index % len(CHART_COLOURS)]
}

chart_slice_colour :: proc(chart: ^Chart, index: int) -> Colour {
	if len(chart.series) == 0 {
		return CHART_COLOURS[0]
	}
	base := chart.series[0].colour
	if base.a <= 0 {
		return CHART_COLOURS[index % len(CHART_COLOURS)]
	}
	return Scale_Colour(base, max(1 - 0.12 * f32(index), 0.45))
}

chart_axis_colour :: proc() -> Colour {
	return Colour{0.42, 0.45, 0.51, 1}
}

chart_number :: proc(g: ^GUI, value: f32) -> string {
	return fmt.aprintf("%.1f", value, allocator = virt.arena_allocator(&g.frame_arena))
}

//* == The pointer ==

click_chart :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	chart := chart_of(g, id)
	if chart == nil {return}
	index := chart_point_at(g, id, g.pointer)
	if index < 0 {return}
	chart.selected = index
	signal_item_selected(g, id, index)
}

update_chart :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	chart := chart_of(g, id)
	if chart == nil {return}
	count := chart_point_count(chart)
	if chart.selected >= count {
		chart.selected = count - 1
	}
}