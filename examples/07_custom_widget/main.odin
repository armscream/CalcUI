package main

import "core:fmt"
import "core:log"
import "core:math"
import App "../../src/App"
import GUI "../../src/GUI"

//* How many segments the ring of the gauge has.
GAUGE_SEGMENTS :: 24

GAUGE_PLATE :: GUI.Colour{0.08, 0.09, 0.12, 1}
GAUGE_TRACK :: GUI.Colour{0.17, 0.19, 0.24, 1}
GAUGE_FILL :: GUI.Colour{0.25, 0.62, 1.00, 1}
GAUGE_TEXT :: GUI.Colour{0.92, 0.94, 0.98, 1}

Gauge_Data :: struct {
	value: f32,
}

gauge: GUI.Widget_ID
readout: GUI.Widget_ID

main :: proc() {
	App.Run(
		"CalcUI - A widget of your own",
		560,
		360,
		setup,
		update,
	)
	log.info("the custom widget example is done")
}

setup :: proc(app: ^App.App) {
	g := app.gui
	GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

	gauge_class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
		name = "Gauge",
		kind = GUI.Widget_Kind{
			draw = gauge_draw,
			measure = gauge_measure,
			click = gauge_click,
		},
	})

	panel := GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "gauge_panel",
				offsets = GUI.Offset{left = 24, top = 24, right = -24, bottom = -24},
				style = GUI.Style{
					box = GUI.StyleBox{
						bg_color = GUI.RGBA(0.11, 0.12, 0.16, 1),
						border_color = {
							GUI.RGBA(0.22, 0.24, 0.30, 1),
							GUI.RGBA(0.22, 0.24, 0.30, 1),
							GUI.RGBA(0.22, 0.24, 0.30, 1),
							GUI.RGBA(0.22, 0.24, 0.30, 1),
						},
						border_width = {1, 1, 1, 1},
					},
				},
			},
		},
	)

	gauge = GUI.Make_Custom_Widget(g, panel, gauge_class, GUI.Base_Opts{
		name = "gauge",
		preset = .Top_Left,
		offsets = GUI.Offset{left = 20, top = 16, right = 260, bottom = 216},
	})
	data := new(Gauge_Data)
	data.value = 40
	GUI.Widget_Set_User_Data(g, gauge, cast(rawptr) data, free_gauge)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "up",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 20, top = 236, right = 120, bottom = 268},
			},
			text = "+10",
			on_pressed = on_up,
		},
	)

	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "down",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 132, top = 236, right = 232, bottom = 268},
			},
			text = "-10",
			on_pressed = on_down,
		},
	)

	readout = GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "readout",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 252, top = 240, right = 460, bottom = 266},
			},
			text = "40 of 100",
		},
	)
}

//* Once a frame: the label says what the gauge shows.
update :: proc(app: ^App.App) {
	g := app.gui
	data := gauge_data(g, gauge)
	if data == nil {return}
	GUI.Widget_Set_Text(g, readout, fmt.tprintf("%d of 100", int(data.value)))
}

//* The data of the gauge, or nil when there is none.
gauge_data :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> ^Gauge_Data {
	user := GUI.Widget_User_Data(g, id)
	if user == nil {return nil}
	return cast(^Gauge_Data)user
}

free_gauge :: proc(user: rawptr) {
	free(user)
}

gauge_measure :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
	return GUI.Vec2{160, 160}
}

gauge_draw :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget, content: GUI.Rect) {
	data := gauge_data(g, id)
	if data == nil {return}

	centre := GUI.Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5}
	outer := min(content.w, content.h) * 0.5 - 4
	inner := outer * 0.70
	if outer <= 0 {return}

	GUI.Draw_Rect(
		g,
		GUI.Rect{x = centre.x - outer, y = centre.y - outer, w = outer * 2, h = outer * 2},
		GAUGE_PLATE,
		outer,
	)

	value := clamp(data.value, 0, 100) / 100
	filled := -90 + 360 * value

	for i in 0 ..< GAUGE_SEGMENTS {
		from := -90 + 360 * f32(i) / f32(GAUGE_SEGMENTS) + 1.2
		to := -90 + 360 * f32(i + 1) / f32(GAUGE_SEGMENTS) - 1.2
		gauge_arc(g, centre, inner, outer, from, to, GAUGE_TRACK)
		if from < filled {
			gauge_arc(g, centre, inner, outer, from, min(to, filled), GAUGE_FILL)
		}
	}

	style := GUI.Widget_Style(g, id).text
	style.align = .Center
	style.valign = .Center
	GUI.Draw_Text(
		g,
		style,
		fmt.tprintf("%d", int(data.value)),
		GUI.Rect{x = centre.x - inner, y = centre.y - inner, w = inner * 2, h = inner * 2},
		GAUGE_TEXT,
	)
}

gauge_arc :: proc(
	g: ^GUI.GUI,
	centre: GUI.Vec2,
	inner, outer, from, to: f32,
	colour: GUI.Colour,
) {
	points: [dynamic][2]f32
	defer delete(points)

	steps := 6
	for i in 0 ..= steps {
		a := (from + (to - from) * f32(i) / f32(steps)) * math.PI / 180
		append(&points, [2]f32{centre.x + math.cos(a) * outer, centre.y + math.sin(a) * outer})
	}
	for i in steps ..= 0 {
		a := (from + (to - from) * f32(i) / f32(steps)) * math.PI / 180
		append(&points, [2]f32{centre.x + math.cos(a) * inner, centre.y + math.sin(a) * inner})
	}
	GUI.Draw_Polygon(g, points[:], colour)
}

//* A click on the gauge turns it a little.
gauge_click :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
	data := gauge_data(g, id)
	if data == nil {return}
	data.value = clamp(data.value + 5, 0, 100)
	GUI.Widget_Invalidate(g, id, GUI.Dirty_Flags{.Visual})
}

on_up :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	data := gauge_data(g, gauge)
	if data == nil {return}
	data.value = clamp(data.value + 10, 0, 100)
	GUI.Widget_Invalidate(g, gauge, GUI.Dirty_Flags{.Visual})
}

on_down :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	data := gauge_data(g, gauge)
	if data == nil {return}
	data.value = clamp(data.value - 10, 0, 100)
	GUI.Widget_Invalidate(g, gauge, GUI.Dirty_Flags{.Visual})
}
