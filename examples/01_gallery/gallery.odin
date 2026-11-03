//* A basic UI test scene.
//
//* Root
//* ├─ Split (horizontal)
//*    ├─ VBox "toolbar"        -> Add / Toggle / dock buttons
//*    └─ Split (vertical)
//*       ├─ Panel "status"      -> a counter, a bar, and a text field
//*       └─ Panel "target"      -> the drop target for drag-to-dock
//
//* The status and target panels have title bars: drag one onto the
//* other to dock it. The edges of a panel split it, the middle makes
//* the two panels share a tab strip, and holding Ctrl while dropping
//* in the middle swaps the two panels around.
//
//* The edges and the corners of a panel are grips: pulling on one
//* resizes the panel, and the panel next to it gives up the space.
package main

import GUI "../../src/GUI"

Demo_State :: struct {
	counter: int,
	bar:     GUI.Widget_ID,
	toolbar: GUI.Widget_ID,
	side:    GUI.Widget_ID,
	status:  GUI.Widget_ID,
	target:  GUI.Widget_ID,
	field:   GUI.Widget_ID,
	hidden:  bool,
	docked:  bool,
}

demo: Demo_State

//* The size of the GUI's own text.
DEMO_BODY_SIZE :: 16

Init_Demo :: proc(g: ^GUI.GUI, body: GUI.Font_Family_ID) {
	demo = Demo_State{
		bar = GUI.INVALID_WIDGET_ID,
		toolbar = GUI.INVALID_WIDGET_ID,
		side = GUI.INVALID_WIDGET_ID,
		status = GUI.INVALID_WIDGET_ID,
		target = GUI.INVALID_WIDGET_ID,
		field = GUI.INVALID_WIDGET_ID,
	}

	GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

	main := GUI.New_Widget(g, .Split, g.root, GUI.Widget_Opts{name = "main", split = .Horizontal})

	//* Toolbar: a vertical box of buttons, fixed width.
	toolbar := GUI.New_Widget(g, .VBox, main, GUI.Widget_Opts{
		name = "toolbar",
		min_size = GUI.Vec2{220, 0},
		fixed = true,
		separation = 8,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.11, 0.12, 0.15, 1),
				border_color = {GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1)},
				border_width = {1, 1, 1, 1},
				content_margin = {12, 12, 12, 12},
			},
		},
	})
	demo.toolbar = toolbar

	GUI.New_Widget(g, .Button, toolbar, GUI.Widget_Opts{
		name = "add",
		text = "Add",
		min_size = GUI.Vec2{0, 40},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.16, 0.42, 0.82, 1),
			},
			text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1), align = .Center, family = body},
		},
		on_click = on_demo_add,
	})
	GUI.New_Widget(g, .Button, toolbar, GUI.Widget_Opts{
		name = "hide",
		text = "Toggle Target",
		min_size = GUI.Vec2{0, 40},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.25, 0.27, 0.32, 1),
			},
			text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1), align = .Center, family = body},
		},
		on_click = on_demo_toggle,
	})
	GUI.New_Widget(g, .Button, toolbar, GUI.Widget_Opts{
		name = "GUI.Dock",
		text = "GUI.Dock Status",
		min_size = GUI.Vec2{0, 40},
		fixed = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.55, 0.32, 0.16, 1),
			},
			text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1), align = .Center, family = body},
		},
		on_click = on_demo_dock,
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint",
		text = "Drag a title bar to GUI.Dock",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.55, 0.58, 0.66, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint2",
		text = "Edges split, middle tabs,",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint3",
		text = "Ctrl swaps the panels.",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint_resize",
		text = "Pull an edge of a panel",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint_resize2",
		text = "or a corner to resize it.",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint4",
		text = "Drag a panel out of the",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint5",
		text = "window to give it its own.",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint6",
		text = "Empty space takes a whole",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	GUI.New_Widget(g, .Label, toolbar, GUI.Widget_Opts{
		name = "hint7",
		text = "panel, if the panel fits.",
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	//* Right hand side: a vertical split of two panels.
	side := GUI.New_Widget(g, .Split, main, GUI.Widget_Opts{name = "side", split = .Vertical})
	demo.side = side

	status := GUI.New_Widget(g, .Panel, side, GUI.Widget_Opts{
		name = "status",
		draggable = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.10, 0.11, 0.14, 1),
				border_color = {GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1), GUI.RGBA(0.20, 0.22, 0.27, 1)},
				border_width = {1, 1, 1, 1},
			},
			text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 0, body),
		},
	})
	demo.status = status

	GUI.New_Widget(g, .Label, status, GUI.Widget_Opts{
		name = "caption",
		text = "Counter",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 36, 16, 60},
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.75, 0.78, 0.85, 1), 0, body)},
	})

	//* The bar grows with the counter. Its width comes from the right
	//* offset, since its anchors are all zero.
	bar := GUI.New_Widget(g, .Panel, status, GUI.Widget_Opts{
		name = "bar",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 68, 16, 100},
		style = GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.20, 0.75, 0.45, 1)}},
	})
	demo.bar = bar

	//* A text field.
	GUI.New_Widget(g, .Label, status, GUI.Widget_Opts{
		name = "field_caption",
		text = "Text field",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 116, 16, 140},
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.75, 0.78, 0.85, 1), 0, body)},
	})

	field := GUI.New_Widget(g, .TextInput, status, GUI.Widget_Opts{
		name = "field",
		text = "type here",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 148, 320, 182},
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.06, 0.07, 0.09, 1),
				border_color = {GUI.RGBA(0.30, 0.33, 0.40, 1), GUI.RGBA(0.30, 0.33, 0.40, 1), GUI.RGBA(0.30, 0.33, 0.40, 1), GUI.RGBA(0.30, 0.33, 0.40, 1)},
				border_width = {1, 1, 1, 1},
			},
			text = GUI.Make_Text_Style(GUI.RGBA(0.92, 0.94, 0.98, 1), 0, body),
		},
	})
	demo.field = field

	//* A bigger font, to show that sizes share one atlas.
	GUI.New_Widget(g, .Label, status, GUI.Widget_Opts{
		name = "big",
		text = "Multi-size",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 200, 16, 240},
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.98, 0.76, 0.30, 1), 28, body)},
	})

	target := GUI.New_Widget(g, .Panel, side, GUI.Widget_Opts{
		name = "target",
		draggable = true,
		style = GUI.Style{
box = GUI.StyleBox{
				bg_color = GUI.RGBA(0.13, 0.14, 0.18, 1),
				border_color = {GUI.RGBA(0.35, 0.38, 0.45, 1), GUI.RGBA(0.35, 0.38, 0.45, 1), GUI.RGBA(0.35, 0.38, 0.45, 1), GUI.RGBA(0.35, 0.38, 0.45, 1)},
				border_width = {1, 1, 1, 1},
			},
			text = GUI.Make_Text_Style(GUI.RGBA(0.86, 0.89, 0.95, 1), 0, body),
		},
	})
	demo.target = target

	//* A small label in the corner: the rest of the panel is empty
	//* space, and a panel dropped into that space takes all of it.
	GUI.New_Widget(g, .Label, target, GUI.Widget_Opts{
		name = "drop_here",
		text = "Drop a panel here",
		preset = .Top_Left,
		offsets = GUI.Offset{16, 36, 200, 60},
		style = GUI.Style{text = GUI.Make_Text_Style(GUI.RGBA(0.45, 0.48, 0.55, 1), 0, body)},
	})

	//* The text showcase: the sizes, the colours, the alignment, the
	//* wrapping and the decorations, all in one place. It sits under
	//* the hint in the panel that is free.
	showcase := Init_Demo_Text(g, body)
	GUI.Widget_Attach(g, target, showcase)
}

on_demo_add :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	demo.counter += 1
	bar := GUI.Widget_Get(g, demo.bar)
	if bar == nil {return}
	bar.offsets.right = 16 + f32(demo.counter) * 16
	g.layout_dirty = true
}

on_demo_toggle :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	demo.hidden = !demo.hidden
	target := GUI.Widget_Get(g, demo.target)
	if target == nil {return}
	target.state -= GUI.Widget_State{.Visible}
	if !demo.hidden { target.state += GUI.Widget_State{.Visible} }
	g.layout_dirty = true
}

on_demo_dock :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	if demo.docked {
		//* Put the status panel back in the side split.
		GUI.Widget_Insert_At(g, demo.side, demo.status, 0)
		demo.docked = false
		g.layout_dirty = true
		return
	}
	//* dock the status panel next to the target one.
	GUI.Dock(g, demo.status, demo.target, .Right)
	demo.docked = true
}
