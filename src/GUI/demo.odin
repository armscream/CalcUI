//* A basic UI test scene.
//
//* Root
//* ├─ Split (horizontal)
//*    ├─ VBox "toolbar"        -> Add / Toggle / Dock buttons
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
package GUI

Demo_State :: struct {
	counter: int,
	bar:     Widget_ID,
	toolbar: Widget_ID,
	side:    Widget_ID,
	status:  Widget_ID,
	target:  Widget_ID,
	field:   Widget_ID,
	hidden:  bool,
	docked:  bool,
}

demo: Demo_State

//* The size of the GUI's own text.
DEMO_BODY_SIZE :: 16

init_demo :: proc(g: ^GUI, body: Font_Family_ID) {
	demo = Demo_State{
		bar = INVALID_WIDGET_ID,
		toolbar = INVALID_WIDGET_ID,
		side = INVALID_WIDGET_ID,
		status = INVALID_WIDGET_ID,
		target = INVALID_WIDGET_ID,
		field = INVALID_WIDGET_ID,
	}

	widget_get(g, g.root).style.bg = rgba(0.07, 0.08, 0.10, 1)

	main := widget(g, .Split, g.root, Widget_Opts{name = "main", split = .Horizontal})

	//* Toolbar: a vertical box of buttons, fixed width.
	toolbar := widget(g, .VBox, main, Widget_Opts{
		name = "toolbar",
		min_size = Vec2{220, 0},
		fixed = true,
		separation = 8,
		style = Style{
			bg = rgba(0.11, 0.12, 0.15, 1),
			border = rgba(0.20, 0.22, 0.27, 1),
			border_width = 1,
			padding = {12, 12, 12, 12},
		},
	})
	demo.toolbar = toolbar

	widget(g, .Button, toolbar, Widget_Opts{
		name = "add",
		text = "Add",
		min_size = Vec2{0, 40},
		fixed = true,
		style = Style{
			bg = rgba(0.16, 0.42, 0.82, 1),
			text = Text_Style{colour = rgba(1, 1, 1, 1), align = .Center, family = body},
		},
		on_click = on_demo_add,
	})
	widget(g, .Button, toolbar, Widget_Opts{
		name = "hide",
		text = "Toggle Target",
		min_size = Vec2{0, 40},
		fixed = true,
		style = Style{
			bg = rgba(0.25, 0.27, 0.32, 1),
			text = Text_Style{colour = rgba(1, 1, 1, 1), align = .Center, family = body},
		},
		on_click = on_demo_toggle,
	})
	widget(g, .Button, toolbar, Widget_Opts{
		name = "dock",
		text = "Dock Status",
		min_size = Vec2{0, 40},
		fixed = true,
		style = Style{
			bg = rgba(0.55, 0.32, 0.16, 1),
			text = Text_Style{colour = rgba(1, 1, 1, 1), align = .Center, family = body},
		},
		on_click = on_demo_dock,
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint",
		text = "Drag a title bar to dock",
		style = Style{text = text_style(rgba(0.55, 0.58, 0.66, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint2",
		text = "Edges split, middle tabs,",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint3",
		text = "Ctrl swaps the panels.",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint_resize",
		text = "Pull an edge of a panel",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint_resize2",
		text = "or a corner to resize it.",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint4",
		text = "Drag a panel out of the",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint5",
		text = "window to give it its own.",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint6",
		text = "Empty space takes a whole",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	widget(g, .Label, toolbar, Widget_Opts{
		name = "hint7",
		text = "panel, if the panel fits.",
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	//* Right hand side: a vertical split of two panels.
	side := widget(g, .Split, main, Widget_Opts{name = "side", split = .Vertical})
	demo.side = side

	status := widget(g, .Panel, side, Widget_Opts{
		name = "status",
		draggable = true,
		style = Style{
			bg = rgba(0.10, 0.11, 0.14, 1),
			border = rgba(0.20, 0.22, 0.27, 1),
			border_width = 1,
			text = text_style(rgba(0.86, 0.89, 0.95, 1), 0, body),
		},
	})
	demo.status = status

	widget(g, .Label, status, Widget_Opts{
		name = "caption",
		text = "Counter",
		preset = .Top_Left,
		offsets = Offset{16, 36, 16, 60},
		style = Style{text = text_style(rgba(0.75, 0.78, 0.85, 1), 0, body)},
	})

	//* The bar grows with the counter. Its width comes from the right
	//* offset, since its anchors are all zero.
	bar := widget(g, .Panel, status, Widget_Opts{
		name = "bar",
		preset = .Top_Left,
		offsets = Offset{16, 68, 16, 100},
		style = Style{bg = rgba(0.20, 0.75, 0.45, 1)},
	})
	demo.bar = bar

	//* A text field.
	widget(g, .Label, status, Widget_Opts{
		name = "field_caption",
		text = "Text field",
		preset = .Top_Left,
		offsets = Offset{16, 116, 16, 140},
		style = Style{text = text_style(rgba(0.75, 0.78, 0.85, 1), 0, body)},
	})

	field := widget(g, .TextInput, status, Widget_Opts{
		name = "field",
		text = "type here",
		preset = .Top_Left,
		offsets = Offset{16, 148, 320, 182},
		style = Style{
			bg = rgba(0.06, 0.07, 0.09, 1),
			border = rgba(0.30, 0.33, 0.40, 1),
			border_width = 1,
			text = text_style(rgba(0.92, 0.94, 0.98, 1), 0, body),
		},
	})
	demo.field = field

	//* A bigger font, to show that sizes share one atlas.
	widget(g, .Label, status, Widget_Opts{
		name = "big",
		text = "Multi-size",
		preset = .Top_Left,
		offsets = Offset{16, 200, 16, 240},
		style = Style{text = text_style(rgba(0.98, 0.76, 0.30, 1), 28, body)},
	})

	target := widget(g, .Panel, side, Widget_Opts{
		name = "target",
		draggable = true,
		style = Style{
			bg = rgba(0.13, 0.14, 0.18, 1),
			border = rgba(0.35, 0.38, 0.45, 1),
			border_width = 1,
			text = text_style(rgba(0.86, 0.89, 0.95, 1), 0, body),
		},
	})
	demo.target = target

	//* A small label in the corner: the rest of the panel is empty
	//* space, and a panel dropped into that space takes all of it.
	widget(g, .Label, target, Widget_Opts{
		name = "drop_here",
		text = "Drop a panel here",
		preset = .Top_Left,
		offsets = Offset{16, 36, 200, 60},
		style = Style{text = text_style(rgba(0.45, 0.48, 0.55, 1), 0, body)},
	})

	//* The text showcase: the sizes, the colours, the alignment, the
	//* wrapping and the decorations, all in one place. It sits under
	//* the hint in the panel that is free.
	showcase := init_demo_text(g, body)
	widget_attach(g, target, showcase)
}

on_demo_add :: proc(g: ^GUI, id: Widget_ID) {
	demo.counter += 1
	bar := widget_get(g, demo.bar)
	if bar == nil { return }
	bar.offsets.right = 16 + f32(demo.counter) * 16
	g.layout_dirty = true
}

on_demo_toggle :: proc(g: ^GUI, id: Widget_ID) {
	demo.hidden = !demo.hidden
	target := widget_get(g, demo.target)
	if target == nil { return }
	target.state -= Widget_State{.Visible}
	if !demo.hidden { target.state += Widget_State{.Visible} }
	g.layout_dirty = true
}

on_demo_dock :: proc(g: ^GUI, id: Widget_ID) {
	if demo.docked {
		//* Put the status panel back in the side split.
		widget_insert_at(g, demo.side, demo.status, 0)
		demo.docked = false
		g.layout_dirty = true
		return
	}
	//* Dock the status panel next to the target one.
	dock(g, demo.status, demo.target, .Right)
	demo.docked = true
}
