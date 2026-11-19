package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:os"
import App "../../src/App"
import Backend "../../src/Backend"
import GUI "../../src/GUI"

Mode :: enum {
	Dark,
	Light,
	Ocean,
	Liquid_Glass,
	Neumorphism,
	Material_3,
	Fluent,
}

Palette :: struct {
	window:         GUI.Colour,
	surface:        GUI.Colour,
	field:          GUI.Colour,
	button:         GUI.Colour,
	hover:          GUI.Colour,
	pressed:        GUI.Colour,
	border:         GUI.Colour,
	text:           GUI.Colour,
	dim:            GUI.Colour,
	accent:         GUI.Colour,
	accent2:        GUI.Colour,
	//* The colour of a panel title. Zero means the mode uses the accent.
	heading:        GUI.Colour,
	//* The fill of a checked box or a selected segment. Zero means the
	//* mode uses the accent and white ink.
	accent_soft:    GUI.Colour,
	on_accent:      GUI.Colour,
	popup:          GUI.Colour,
	danger:         GUI.Colour,
	danger_hi:      GUI.Colour,
	success:        GUI.Colour,
	success_hi:     GUI.Colour,
	//* How the shape of a mode is made. A mode that does not use glass
	//* leaves the blur at zero, and one that is not raised draws a
	//* border of one colour on every side.
	panel_radius:   f32,
	control_radius: f32,
	field_radius:   f32,
	border_width:   f32,
	panel_blur:     f32,
	button_blur:    f32,
	field_blur:     f32,
	panel_optics:   GUI.Glass_Optics,
	button_optics:  GUI.Glass_Optics,
	field_optics:   GUI.Glass_Optics,
	shadow:         GUI.Colour,
	shadow_size:    f32,
	shadow_offset:  GUI.Vec2,
	filled_button:  bool,
	base_light:     bool,
	raised:         bool,
	light_border:   GUI.Colour,
	dark_border:    GUI.Colour,
	wall_a:         GUI.Colour,
	wall_b:         GUI.Colour,
	wall_c:         GUI.Colour,
	wall_d:         GUI.Colour,
	wall_alpha:     f32,
}

g: ^GUI.GUI
family: GUI.Font_Family_ID
mode: Mode
status: GUI.Widget_ID
banner: GUI.Widget_ID
variant_sample: GUI.Widget_ID
variant_toggle: GUI.Widget_ID
wallpaper: GUI.Widget_ID
specimen: GUI.Widget_ID
specimen_glass: GUI.Widget_ID
wall_phase: f32
show_danger := true
wall_texture: GUI.Texture
wall_pixels: []u8
wall_tex_w, wall_tex_h: int
wall_bake_accum: f32
wall_dirty := true

WALL_TEX_MAX :: 512
WALL_BAKE_HZ :: 4

swatch_rects: [5]GUI.Widget_ID
status_buffer: [384]u8
last_stats: Backend.Backend_Stats
last_stats_mode: Mode

main :: proc() {
	App.Run(
		"CalcUI - Theming",
		1180,
		760,
		proc(app: ^App.App) {
			g = app.gui
			family = app.family
			build()
			apply_mode(initial_mode())
		},
		frame_update,
	)
	delete(wall_pixels)
	log.info("the theming example is done")
}

frame_update :: proc(app: ^App.App) {
	if mode != .Liquid_Glass && mode != .Fluent {
		return
	}
	s := Backend.Stats_Get()
	if s.glass_commands == 0 {
		return
	}
	if s == last_stats && mode == last_stats_mode {
		return
	}
	last_stats = s
	last_stats_mode = mode
	text := fmt.bprintf(
		status_buffer[:],
		"%s  glass %d  taps %d  captures %d  mips %d  backdrop %d px  passes %d  full %d  partial %d  wakes %d",
		status_text(mode),
		s.glass_commands,
		s.glass_taps,
		s.capture_points,
		s.mip_generations,
		s.backdrop_pixels,
		s.draw_passes,
		s.full_updates,
		s.partial_updates,
		s.wake_timers,
	)
	GUI.Widget_Set_Text(g, status, text)
}

//* The starting theme can come from the command line: --dark, --light,
//* --ocean, --glass, --neo, --m3 or --fluent.
initial_mode :: proc() -> Mode {
	for arg in os.args {
		switch arg {
		case "--dark":
			return .Dark
		case "--glass":
			return .Liquid_Glass
		case "--neo":
			return .Neumorphism
		case "--m3":
			return .Material_3
		case "--fluent":
			return .Fluent
		case "--light":
			return .Light
		case "--ocean":
			return .Ocean
		}
	}
	return .Dark
}

palette :: proc(m: Mode) -> Palette {
	p := Palette {
		panel_radius = 10,
		control_radius = 8,
		field_radius = 6,
		border_width = 1,
		on_accent = GUI.RGBA(1, 1, 1, 1),
		wall_alpha = 0.040,
	}
	switch m {
	case .Dark:
		p.window = GUI.RGBA(0.07, 0.08, 0.10, 1)
		p.surface = GUI.RGBA(0.10, 0.12, 0.16, 1)
		p.field = GUI.RGBA(0.13, 0.15, 0.19, 1)
		p.button = GUI.RGBA(0.17, 0.19, 0.24, 1)
		p.hover = GUI.RGBA(0.24, 0.28, 0.35, 1)
		p.pressed = GUI.RGBA(0.12, 0.14, 0.18, 1)
		p.border = GUI.RGBA(0.25, 0.28, 0.35, 1)
		p.text = GUI.RGBA(0.88, 0.91, 0.96, 1)
		p.dim = GUI.RGBA(0.52, 0.56, 0.64, 1)
		p.accent = GUI.RGBA(0.30, 0.62, 1.00, 1)
		p.accent2 = GUI.RGBA(0.72, 0.42, 0.98, 1)
		p.popup = GUI.RGBA(0.09, 0.11, 0.15, 1)
		p.danger = GUI.RGBA(0.58, 0.17, 0.20, 1)
		p.danger_hi = GUI.RGBA(0.74, 0.24, 0.28, 1)
		p.success = GUI.RGBA(0.15, 0.50, 0.30, 1)
		p.success_hi = GUI.RGBA(0.22, 0.66, 0.40, 1)
		p.shadow = GUI.RGBA(0, 0, 0, 0.35)
		p.shadow_size = 18
		p.shadow_offset = {0, 6}
	case .Light:
		p.window = GUI.RGBA(0.90, 0.92, 0.96, 1)
		p.surface = GUI.RGBA(0.97, 0.98, 1.00, 1)
		p.field = GUI.RGBA(0.92, 0.94, 0.98, 1)
		p.button = GUI.RGBA(0.86, 0.89, 0.94, 1)
		p.hover = GUI.RGBA(0.78, 0.83, 0.92, 1)
		p.pressed = GUI.RGBA(0.72, 0.78, 0.88, 1)
		p.border = GUI.RGBA(0.74, 0.78, 0.85, 1)
		p.text = GUI.RGBA(0.12, 0.14, 0.18, 1)
		p.dim = GUI.RGBA(0.42, 0.45, 0.52, 1)
		p.accent = GUI.RGBA(0.16, 0.44, 0.86, 1)
		p.accent2 = GUI.RGBA(0.55, 0.25, 0.80, 1)
		p.accent_soft = GUI.RGBA(0.82, 0.88, 0.97, 1)
		p.popup = GUI.RGBA(0.99, 0.99, 1.00, 1)
		p.danger = GUI.RGBA(0.78, 0.22, 0.24, 1)
		p.danger_hi = GUI.RGBA(0.88, 0.30, 0.32, 1)
		p.success = GUI.RGBA(0.16, 0.58, 0.33, 1)
		p.success_hi = GUI.RGBA(0.22, 0.70, 0.42, 1)
		p.shadow = GUI.RGBA(0.10, 0.15, 0.25, 0.18)
		p.shadow_size = 16
		p.shadow_offset = {0, 4}
		p.base_light = true
	case .Ocean:
		p.window = GUI.RGBA(0.04, 0.09, 0.11, 1)
		p.surface = GUI.RGBA(0.07, 0.14, 0.17, 1)
		p.field = GUI.RGBA(0.09, 0.17, 0.21, 1)
		p.button = GUI.RGBA(0.11, 0.21, 0.25, 1)
		p.hover = GUI.RGBA(0.15, 0.29, 0.34, 1)
		p.pressed = GUI.RGBA(0.08, 0.16, 0.20, 1)
		p.border = GUI.RGBA(0.18, 0.35, 0.40, 1)
		p.text = GUI.RGBA(0.82, 0.95, 0.96, 1)
		p.dim = GUI.RGBA(0.45, 0.66, 0.70, 1)
		p.accent = GUI.RGBA(0.12, 0.72, 0.68, 1)
		p.accent2 = GUI.RGBA(0.12, 0.48, 0.85, 1)
		p.popup = GUI.RGBA(0.05, 0.11, 0.13, 1)
		p.danger = GUI.RGBA(0.72, 0.24, 0.26, 1)
		p.danger_hi = GUI.RGBA(0.86, 0.32, 0.34, 1)
		p.success = GUI.RGBA(0.14, 0.56, 0.42, 1)
		p.success_hi = GUI.RGBA(0.22, 0.72, 0.56, 1)
		p.shadow = GUI.RGBA(0, 0, 0, 0.35)
		p.shadow_size = 18
		p.shadow_offset = {0, 6}
	case .Liquid_Glass:
		p.window = GUI.RGBA(0.06, 0.08, 0.16, 1)
		p.surface = GUI.RGBA(1, 1, 1, 0.13)
		p.field = GUI.RGBA(0, 0, 0, 0.16)
		p.button = GUI.RGBA(1, 1, 1, 0.16)
		p.hover = GUI.RGBA(1, 1, 1, 0.26)
		p.pressed = GUI.RGBA(1, 1, 1, 0.09)
		p.border = GUI.RGBA(1, 1, 1, 0.40)
		p.text = GUI.RGBA(1, 1, 1, 0.97)
		p.dim = GUI.RGBA(1, 1, 1, 0.62)
		p.accent = GUI.RGBA(0.62, 0.82, 1.00, 1)
		p.accent2 = GUI.RGBA(0.72, 0.36, 1.00, 1)
		p.heading = GUI.RGBA(1, 1, 1, 0.95)
		p.accent_soft = GUI.RGBA(0.18, 0.36, 0.72, 1)
		p.popup = GUI.RGBA(0.10, 0.12, 0.22, 0.96)
		p.danger = GUI.RGBA(1.00, 0.32, 0.36, 0.72)
		p.danger_hi = GUI.RGBA(1.00, 0.42, 0.46, 0.88)
		p.success = GUI.RGBA(0.20, 0.85, 0.52, 0.72)
		p.success_hi = GUI.RGBA(0.28, 0.95, 0.62, 0.88)
		p.panel_blur = 22
		p.button_blur = 13
		p.field_blur = 15
		p.panel_optics = {refraction = 12, dispersion = 3, fresnel = 0.85, saturation = 1.3}
		p.button_optics = {refraction = 4, dispersion = 1.4, fresnel = 0.55, saturation = 1.15}
		p.field_optics = {refraction = 4, dispersion = 1, fresnel = 0.45, saturation = 1.1}
		p.wall_alpha = 0.085
		p.field_radius = 10
		p.panel_radius = 24
		p.control_radius = 13
		p.shadow = GUI.RGBA(0, 0, 0, 0.42)
		p.shadow_size = 26
		p.shadow_offset = {0, 10}
		p.wall_a = GUI.RGBA(0.20, 0.42, 1.00, 1)
		p.wall_b = GUI.RGBA(0.78, 0.30, 1.00, 1)
		p.wall_c = GUI.RGBA(0.10, 0.85, 0.80, 1)
		p.wall_d = GUI.RGBA(1.00, 0.45, 0.66, 1)
	case .Neumorphism:
		p.window = GUI.RGBA(0.878, 0.898, 0.925, 1)
		p.surface = GUI.RGBA(0.878, 0.898, 0.925, 1)
		p.field = GUI.RGBA(0.878, 0.898, 0.925, 1)
		p.button = GUI.RGBA(0.878, 0.898, 0.925, 1)
		p.hover = GUI.RGBA(0.912, 0.929, 0.949, 1)
		p.pressed = GUI.RGBA(0.835, 0.855, 0.886, 1)
		p.border = GUI.RGBA(0.68, 0.72, 0.79, 1)
		p.light_border = GUI.RGBA(1, 1, 1, 0.95)
		p.dark_border = GUI.RGBA(0.64, 0.69, 0.77, 0.85)
		p.text = GUI.RGBA(0.22, 0.26, 0.33, 1)
		p.dim = GUI.RGBA(0.42, 0.46, 0.53, 1)
		p.accent = GUI.RGBA(0.29, 0.45, 0.68, 1)
		p.accent2 = GUI.RGBA(0.42, 0.34, 0.72, 1)
		p.accent_soft = GUI.RGBA(0.73, 0.81, 0.93, 1)
		p.popup = GUI.RGBA(0.878, 0.898, 0.925, 1)
		p.danger = GUI.RGBA(0.66, 0.28, 0.30, 1)
		p.danger_hi = GUI.RGBA(0.76, 0.34, 0.36, 1)
		p.success = GUI.RGBA(0.28, 0.52, 0.40, 1)
		p.success_hi = GUI.RGBA(0.34, 0.61, 0.47, 1)
		p.panel_radius = 20
		p.control_radius = 14
		p.field_radius = 12
		p.border_width = 2
		p.shadow = GUI.RGBA(0.61, 0.66, 0.75, 0.75)
		p.shadow_size = 14
		p.shadow_offset = {6, 6}
		p.raised = true
		p.base_light = true
	case .Material_3:
		p.window = GUI.RGBA(0.996, 0.969, 1.000, 1)
		p.surface = GUI.RGBA(0.953, 0.929, 0.969, 1)
		p.field = GUI.RGBA(0.902, 0.878, 0.914, 1)
		p.button = GUI.RGBA(0.902, 0.878, 0.914, 1)
		p.hover = GUI.RGBA(0.55, 0.44, 0.79, 1)
		p.pressed = GUI.RGBA(0.35, 0.27, 0.56, 1)
		p.border = GUI.RGBA(0.792, 0.769, 0.816, 1)
		p.text = GUI.RGBA(0.114, 0.106, 0.125, 1)
		p.dim = GUI.RGBA(0.286, 0.271, 0.310, 1)
		p.accent = GUI.RGBA(0.404, 0.314, 0.643, 1)
		p.accent2 = GUI.RGBA(0.49, 0.32, 0.38, 1)
		p.accent_soft = GUI.RGBA(0.918, 0.867, 1.000, 1)
		p.popup = GUI.RGBA(0.965, 0.945, 0.980, 1)
		p.danger = GUI.RGBA(0.702, 0.149, 0.118, 1)
		p.danger_hi = GUI.RGBA(0.80, 0.24, 0.20, 1)
		p.success = GUI.RGBA(0.22, 0.42, 0.13, 1)
		p.success_hi = GUI.RGBA(0.30, 0.53, 0.18, 1)
		p.panel_radius = 26
		p.control_radius = 20
		p.field_radius = 16
		p.shadow = GUI.RGBA(0, 0, 0, 0.15)
		p.shadow_size = 18
		p.shadow_offset = {0, 6}
		p.filled_button = true
		p.base_light = true
	case .Fluent:
		p.window = GUI.RGBA(0.13, 0.13, 0.14, 1)
		p.surface = GUI.RGBA(0.16, 0.17, 0.19, 0.78)
		p.field = GUI.RGBA(1, 1, 1, 0.045)
		p.button = GUI.RGBA(1, 1, 1, 0.06)
		p.hover = GUI.RGBA(1, 1, 1, 0.10)
		p.pressed = GUI.RGBA(1, 1, 1, 0.03)
		p.border = GUI.RGBA(1, 1, 1, 0.10)
		p.text = GUI.RGBA(1, 1, 1, 0.96)
		p.dim = GUI.RGBA(1, 1, 1, 0.60)
		p.accent = GUI.RGBA(0.38, 0.80, 1.00, 1)
		p.accent2 = GUI.RGBA(0.72, 0.63, 1.00, 1)
		p.accent_soft = GUI.RGBA(0.06, 0.42, 0.74, 1)
		p.popup = GUI.RGBA(0.14, 0.15, 0.17, 0.96)
		p.danger = GUI.RGBA(0.42, 0.10, 0.09, 0.85)
		p.danger_hi = GUI.RGBA(0.62, 0.17, 0.15, 0.90)
		p.success = GUI.RGBA(0.12, 0.38, 0.14, 0.85)
		p.success_hi = GUI.RGBA(0.18, 0.50, 0.20, 0.90)
		p.panel_radius = 8
		p.control_radius = 5
		p.field_radius = 5
		p.panel_blur = 30
		p.panel_optics = {refraction = 3, dispersion = 0.6, fresnel = 0.3, saturation = 1.05}
		p.button_optics = {refraction = 1.5, dispersion = 0.3, fresnel = 0.2, saturation = 1.02}
		p.field_optics = {refraction = 1.5, dispersion = 0.3, fresnel = 0.2, saturation = 1.02}
		p.shadow = GUI.RGBA(0, 0, 0, 0.36)
		p.shadow_size = 16
		p.shadow_offset = {0, 6}
		p.wall_a = GUI.RGBA(0.16, 0.22, 0.36, 1)
		p.wall_b = GUI.RGBA(0.28, 0.20, 0.36, 1)
		p.wall_c = GUI.RGBA(0.10, 0.26, 0.30, 1)
		p.wall_d = GUI.RGBA(0.22, 0.28, 0.44, 1)
		p.wall_alpha = 0.022
	}
	return p
}

build :: proc() {
	wallpaper = GUI.Make_Canvas(
		g,
		g.root,
		GUI.Canvas_Opts{
			Base_Opts = GUI.Base_Opts{name = "wallpaper", preset = .Fill, use_theme = false},
			repaint_rate = 8,
		},
	)
	GUI.canvas_set_paint(g, wallpaper, paint_wallpaper)
	GUI.Widget_Set_Style(
		g,
		wallpaper,
		GUI.Style{box = GUI.StyleBox{bg_color = GUI.RGBA(0.04, 0.05, 0.10, 1)}},
	)
	GUI.Widget_Set_Visible(g, wallpaper, false)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "title",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 26, top = 18, right = 600, bottom = 52},
				use_theme = true,
				style = GUI.Style{text = GUI.Text_Style{size = 26, family = family}},
			},
			text = "Theming and motion",
		},
	)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "subtitle",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 26, top = 54, right = -26, bottom = 92},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{size = 14, family = family, wrap = .Word}},
			},
			text = "One theme decides the boxes, the ink, the states, the variations and the transition of every widget that takes it. Switch the palette and the same tree is laid out and drawn with another look.",
		},
	)

	modes := GUI.Make_HBox(
		g,
		g.root,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "modes",
				preset = .Top,
				offsets = GUI.Offset{left = 26, top = 100, right = -26, bottom = 140},
				separation = 10,
			},
		},
	)

	for entry in ([]struct {
		name: string,
		mode: Mode,
	}{{"Dark", .Dark}, {"Light", .Light}, {"Ocean", .Ocean}, {"Glass", .Liquid_Glass}, {"Neo", .Neumorphism}, {"M3", .Material_3}, {"Fluent", .Fluent}}) {
		GUI.Make_Button(
			g,
			modes,
			GUI.Button_Opts{
				Base_Opts = GUI.Base_Opts{
					name = entry.name,
					use_theme = true,
					min_size = GUI.Vec2{76, 30},
					fixed = true,
				},
				text = entry.name,
				on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
					switch GUI.Widget_Name(gui, id) {
					case "Dark":
						apply_mode(.Dark)
					case "Light":
						apply_mode(.Light)
					case "Ocean":
						apply_mode(.Ocean)
					case "Glass":
						apply_mode(.Liquid_Glass)
					case "Neo":
						apply_mode(.Neumorphism)
					case "M3":
						apply_mode(.Material_3)
					case "Fluent":
						apply_mode(.Fluent)
					}
				},
			},
		)
	}

	status = GUI.Make_Label(
		g,
		modes,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "status",
				size_flags_h = GUI.Size_Flags{.Fill},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{valign = .Center}},
			},
			text = "The dark theme is showing.",
		},
	)

	main_row := GUI.Make_HBox(
		g,
		g.root,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "main_row",
				preset = .Fill,
				offsets = GUI.Offset{left = 26, top = 152, right = -26, bottom = -176},
				separation = 14,
			},
		},
	)

	make_specimen()

	make_buttons_panel(main_row)
	make_controls_panel(main_row)
	make_inputs_panel(main_row)
	make_colours_panel(main_row)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "footer",
				preset = .Bottom,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 26, top = -46, right = -26, bottom = -18},
				use_theme = true,
				variation = "dim",
			},
			text = "The buttons switch the theme. Hover a control to see its transition.",
		},
	)
}

make_specimen :: proc() {
	specimen = GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "specimen",
				preset = .Bottom_Left,
				offsets = GUI.Offset{left = 26, top = -166, right = 326, bottom = -64},
				use_theme = false,
			},
		},
	)
	pattern := GUI.Make_Canvas(
		g,
		specimen,
		GUI.Canvas_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "specimen_pattern",
				preset = .Fill,
				use_theme = false,
				style = GUI.Style {
					box = GUI.StyleBox {
						bg_color = GUI.RGBA(0.02, 0.03, 0.06, 1),
						corner_radius = {16, 16, 16, 16},
					},
				},
			},
			repaint_rate = 4,
		},
	)
	GUI.canvas_set_paint(g, pattern, paint_specimen)
	specimen_glass = GUI.Make_Panel(
		g,
		specimen,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "specimen_glass",
				preset = .Fill,
				offsets = GUI.Offset{left = 30, top = 14, right = -30, bottom = -14},
				use_theme = false,
			},
		},
	)
}

make_buttons_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_panel",
				min_size = GUI.Vec2{250, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Buttons",
		},
	)

	box := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_box",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = -14},
				separation = 9,
			},
		},
	)

	GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "primary", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "Primary action",
		},
	)
	variant_sample = GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "variant_sample", use_theme = true, variation = "danger", size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A variation",
		},
	)
	variant_toggle = GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "variant_toggle", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "Switch the variation",
			on_pressed = proc(gui: ^GUI.GUI, id: GUI.Widget_ID) {
				show_danger = !show_danger
				if variant_sample == GUI.INVALID_WIDGET_ID {return}
				variation := show_danger ? "danger" : "success"
				GUI.Widget_Set_Variation(gui, variant_sample, variation)
				GUI.Widget_Set_Text(gui, variant_sample, show_danger ? "A danger button" : "A success button")
			},
		},
	)
	disabled := GUI.Make_Button(
		g,
		box,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{name = "disabled", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A disabled button",
		},
	)
	GUI.Widget_Set_Enabled(g, disabled, false)

	segmented := GUI.Make_Segmented(
		g,
		box,
		GUI.Segmented_Opts{
			Base_Opts = GUI.Base_Opts{name = "segmented", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 30}, fixed = true},
			items = []string{"Day", "Week", "Month"},
		},
	)
	GUI.segmented_select(g, segmented, 1)

	GUI.Make_Label(
		g,
		box,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "buttons_hint",
				size_flags_h = GUI.Size_Flags{.Fill},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{wrap = .Word}},
			},
			text = "The box, the ink, the margin and the corner are all in the theme.",
		},
	)
	return panel
}

make_controls_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "controls_panel",
				min_size = GUI.Vec2{280, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "controls_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Controls",
		},
	)
	box := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "controls_box",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = -14},
				separation = 10,
			},
		},
	)
	GUI.Make_Check_Box(
		g,
		box,
		GUI.Check_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "check", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A check box",
			on = true,
		},
	)
	GUI.Make_Toggle_Switch(
		g,
		box,
		GUI.Toggle_Switch_Opts{
			Base_Opts = GUI.Base_Opts{name = "toggle", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = "A toggle switch",
			on = true,
		},
	)
	make_text_box_field(box, "field", "The text box takes the field colour")
	GUI.Make_H_Slider(
		g,
		box,
		GUI.Slider_Opts{
			Base_Opts = GUI.Base_Opts{name = "slider", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 26}, fixed = true},
			value = 62,
			min = 0,
			max = 100,
		},
	)
	GUI.Make_Progress_Bar(
		g,
		box,
		GUI.Progress_Bar_Opts{
			Base_Opts = GUI.Base_Opts{name = "progress", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 16}, fixed = true},
			value = 72,
			max = 100,
		},
	)
	GUI.Make_Rating(
		g,
		box,
		GUI.Rating_Opts{
			Base_Opts = GUI.Base_Opts{name = "rating", use_theme = true, min_size = GUI.Vec2{0, 26}, fixed = true},
			value = 4,
			max = 5,
		},
	)
	GUI.Make_Number_Input(
		g,
		box,
		GUI.Number_Input_Opts{
			Base_Opts = GUI.Base_Opts{name = "amount", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			value = 42,
			min = 0,
			max = 100,
			step = 1,
		},
	)
	GUI.Make_Color_Picker(
		g,
		box,
		GUI.Color_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "color_picker", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 82}, fixed = true},
			colour = GUI.RGBA(0.30, 0.62, 1.0, 1),
		},
	)
	return panel
}

make_text_box_field :: proc(parent: GUI.Widget_ID, name, text: string) {
	GUI.Make_Text_Box(
		g,
		parent,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = name, use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			text = text,
		},
	)
}

make_inputs_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "inputs_panel",
				min_size = GUI.Vec2{250, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "inputs_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Inputs",
		},
	)
	box := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "inputs_box",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = -14},
				separation = 10,
			},
		},
	)
	make_text_box_field(box, "inputs_field", "A single line of text")
	GUI.Make_Search_Field(
		g,
		box,
		GUI.Search_Field_Opts{
			Base_Opts = GUI.Base_Opts{name = "search", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			placeholder = "Search the theme",
		},
	)
	combo := GUI.Make_Combo_Box(
		g,
		box,
		GUI.Combo_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "combo", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			items = []string{"Acrylic", "Mica", "Aero"},
		},
	)
	GUI.combo_box_select(g, combo, 1)
	GUI.Make_Date_Picker(
		g,
		box,
		GUI.Date_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "date", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			year = 2026,
			month = 11,
			day = 16,
		},
	)
	GUI.Make_Time_Picker(
		g,
		box,
		GUI.Time_Picker_Opts{
			Base_Opts = GUI.Base_Opts{name = "time", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, fixed = true},
			hour = 14,
			minute = 30,
		},
	)
	GUI.Make_Text_Box(
		g,
		box,
		GUI.Text_Box_Opts{
			Base_Opts = GUI.Base_Opts{name = "notes", use_theme = true, size_flags_h = GUI.Size_Flags{.Fill}, min_size = GUI.Vec2{0, 96}, fixed = true},
			flags = GUI.Text_Box_Flags{.Multiline},
			text = "A multiline box. Acrylic panels blur the wallpaper behind them.",
		},
	)
	return panel
}
make_colours_panel :: proc(parent: GUI.Widget_ID) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "colours_panel",
				min_size = GUI.Vec2{260, 0},
				weight = 1,
			},
		},
	)
	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "colours_title",
				preset = .Top,
				size_flags_h = GUI.Size_Flags{.Fill},
				offsets = GUI.Offset{left = 14, top = 12, right = -14, bottom = 36},
				use_theme = true,
				variation = "accent_label",
				style = GUI.Style{text = GUI.Text_Style{size = 15, family = family}},
			},
			text = "Palette",
		},
	)
	banner = GUI.Make_Panel(
		g,
		panel,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "banner",
				preset = .Top,
				offsets = GUI.Offset{left = 14, top = 44, right = -14, bottom = 132},
			},
		},
	)
	GUI.Make_Label(
		g,
		banner,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "banner_text",
				preset = .Fill,
				offsets = GUI.Offset{left = 12, top = 12, right = -12, bottom = -12},
				style = GUI.Style{text = GUI.Text_Style{colour = GUI.RGBA(1, 1, 1, 1), size = 15, family = family, align = .Center, valign = .Center}},
			},
			text = "The banner is a tween",
		},
	)
	GUI.Make_Button(
		g,
		panel,
		GUI.Button_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "banner_button",
				preset = .Top,
				offsets = GUI.Offset{left = 14, top = 140, right = -14, bottom = 170},
				use_theme = true,
			},
			text = "A themed button",
		},
	)

	swatches := GUI.Make_VBox(
		g,
		panel,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "swatches",
				preset = .Fill,
				offsets = GUI.Offset{left = 14, top = 182, right = -14, bottom = -14},
				separation = 6,
			},
		},
	)
	p := palette(mode)
	swatch_rects[0] = make_swatch(swatches, "swatch_accent", "accent", p.accent)
	swatch_rects[1] = make_swatch(swatches, "swatch_accent2", "accent 2", p.accent2)
	swatch_rects[2] = make_swatch(swatches, "swatch_danger", "danger", p.danger)
	swatch_rects[3] = make_swatch(swatches, "swatch_success", "success", p.success)
	swatch_rects[4] = make_swatch(swatches, "swatch_text", "text", p.text)
	return panel
}

make_swatch :: proc(
	parent: GUI.Widget_ID,
	name, label: string,
	colour: GUI.Colour,
) -> GUI.Widget_ID {
	row := GUI.Make_HBox(
		g,
		parent,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{name = name, min_size = GUI.Vec2{0, 24}, fixed = true, separation = 8},
		},
	)
	swatch := GUI.Make_Color_Rect(
		g,
		row,
		GUI.Color_Rect_Opts{
			Base_Opts = GUI.Base_Opts{name = name, min_size = GUI.Vec2{24, 24}, fixed = true},
			colour = colour,
		},
	)
	GUI.Make_Label(
		g,
		row,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = name,
				size_flags_h = GUI.Size_Flags{.Fill},
				use_theme = true,
				variation = "dim",
				style = GUI.Style{text = GUI.Text_Style{valign = .Center}},
			},
			text = label,
		},
	)
	return swatch
}

apply_mode :: proc(next: Mode) {
	mode = next
	wall_dirty = true
	p := palette(next)
	GUI.Default_Theme_Use(g, !p.base_light)
	theme := g.theme
	if theme != nil {
		GUI.Theme_Set_Family(theme, family)
		GUI.Theme_Set_Size(theme, 15)

		border := [4]GUI.Colour{p.border, p.border, p.border, p.border}
		panel_border := border
		button_border := border
		field_border := border
		if p.raised {
			panel_border = {p.light_border, p.light_border, p.dark_border, p.dark_border}
			button_border = panel_border
			field_border = {p.dark_border, p.dark_border, p.light_border, p.light_border}
		}

		button_bg := p.button
		button_ink := p.text
		if p.filled_button {
			button_bg = p.accent
			button_ink = p.on_accent
		}
		focus_ink := p.filled_button ? button_ink : p.accent

		seg_fill := p.accent
		if p.accent_soft.a > 0 {seg_fill = p.accent_soft}
		seg_ink := GUI.RGBA(1, 1, 1, 1)
		if p.accent_soft.a > 0 && p.base_light {seg_ink = p.text}

		button_shadow_scale: f32 = p.raised ? 0.7 : 0.25
		button_offset_scale: f32 = p.raised ? 0.6 : 0.25
		soft_shadow := p.shadow
		soft_shadow.a *= 0.35

		GUI.Theme_Set_Type(
			theme,
			.Label,
			GUI.Style{text = GUI.Text_Style{colour = p.text}},
		)
		GUI.Theme_Add_Variation(
			theme,
			"dim",
			.Label,
			GUI.Style{text = GUI.Text_Style{colour = p.dim}},
		)
		GUI.Theme_Add_Variation(
			theme,
			"accent_label",
			.Label,
			GUI.Style{text = GUI.Text_Style{colour = p.heading.a > 0 ? p.heading : p.accent}},
		)

		GUI.Theme_Set_Type(
			theme,
			.Panel,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.surface,
					border_color = panel_border,
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.panel_radius, p.panel_radius, p.panel_radius, p.panel_radius},
					content_margin = {12, 12, 12, 12},
					shadow_color = p.shadow,
					shadow_size = p.shadow_size,
					shadow_offset = p.shadow_offset,
					shadow_spread = p.panel_blur > 0 ? 3 : (p.raised ? 2 : 0),
					backdrop_blur = p.panel_blur,
					optics = p.panel_optics,
				},
				text = GUI.Text_Style{colour = p.text},
				transition = GUI.Style_Transition{duration = 0.18, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = button_bg,
					border_color = button_border,
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.control_radius, p.control_radius, p.control_radius, p.control_radius},
					content_margin = {12, 7, 12, 7},
					shadow_color = p.shadow,
					shadow_size = p.shadow_size * button_shadow_scale,
					shadow_offset = {p.shadow_offset.x * button_offset_scale, p.shadow_offset.y * button_offset_scale},
					backdrop_blur = p.button_blur,
					optics = p.button_optics,
				},
				text = GUI.Text_Style {
					colour = button_ink,
					hover_colour = button_ink,
					pressed_colour = button_ink,
					disabled_colour = p.dim,
					focus_colour = focus_ink,
					align = .Center,
					valign = .Center,
				},
				transition = GUI.Style_Transition{duration = 0.15, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_State(theme, .Button, .Hovered, GUI.Style{box = GUI.StyleBox{bg_color = p.hover}})
		pressed_box := GUI.StyleBox{bg_color = p.pressed}
		if p.raised {
			pressed_box.border_color = field_border
			pressed_box.shadow_color = soft_shadow
			pressed_box.shadow_size = p.shadow_size * 0.3
			pressed_box.shadow_spread = 1
			pressed_box.shadow_inset = true
		}
		GUI.Theme_Set_State(theme, .Button, .Pressed, GUI.Style{box = pressed_box})
		GUI.Theme_Set_State(theme, .Button, .Disabled, GUI.Style{box = GUI.StyleBox{bg_color = p.field}})
		GUI.Theme_Set_State(
			theme,
			.Button,
			.Focused,
			GUI.Style {
				box = GUI.StyleBox{border_color = {p.accent, p.accent, p.accent, p.accent}},
				text = GUI.Text_Style{colour = focus_ink},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.TextBox,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.field,
					border_color = field_border,
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.field_radius, p.field_radius, p.field_radius, p.field_radius},
					content_margin = {8, 6, 8, 6},
					backdrop_blur = p.field_blur,
					optics = p.field_optics,
					shadow_color = p.raised ? soft_shadow : (GUI.Colour{}),
					shadow_size = p.raised ? p.shadow_size * 0.3 : 0,
					shadow_spread = p.raised ? 1 : 0,
					shadow_inset = p.raised,
				},
				text = GUI.Text_Style {
					colour = p.text,
					disabled_colour = p.dim,
					focus_colour = p.accent,
					wrap = .Word,
				},
				transition = GUI.Style_Transition{duration = 0.15, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_State(
			theme,
			.TextBox,
			.Focused,
			GUI.Style{box = GUI.StyleBox{border_color = {p.accent, p.accent, p.accent, p.accent}}},
		)

		field_margin := [4]f32{8, 5, 8, 5}
		apply_field_style(theme, .ComboBox, p, field_border, field_margin)
		apply_field_style(theme, .SearchField, p, field_border, field_margin)
		apply_field_style(theme, .NumberInput, p, field_border, field_margin)
		apply_field_style(theme, .DatePicker, p, field_border, field_margin)
		apply_field_style(theme, .TimePicker, p, field_border, field_margin)

		GUI.Theme_Set_Type(
			theme,
			.Segmented,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.field,
					border_color = field_border,
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.control_radius, p.control_radius, p.control_radius, p.control_radius},
					content_margin = {4, 4, 4, 4},
				},
				text = GUI.Text_Style{colour = p.text, valign = .Center},
				transition = GUI.Style_Transition{duration = 0.15, easing = .Out_Cubic},
			},
		)
		GUI.Theme_Set_Type(
			theme,
			.Rating,
			GUI.Style{text = GUI.Text_Style{colour = p.text}},
		)
		GUI.Theme_Set_Type(
			theme,
			.ToggleSwitch,
			GUI.Style{text = GUI.Text_Style{colour = p.text, valign = .Center}},
		)
		on_border := [4]GUI.Colour{p.accent, p.accent, p.accent, p.accent}
		on_hover_border := [4]GUI.Colour{p.accent2, p.accent2, p.accent2, p.accent2}
		GUI.Theme_Set_Stylebox(
			theme,
			.CheckBox,
			"box",
			mode_box(p.field, field_border, p.border_width, 5),
		)
		GUI.Theme_Set_Stylebox(
			theme,
			.CheckBox,
			"box_hover",
			mode_box(p.hover, field_border, p.border_width, 5),
		)
		GUI.Theme_Set_Stylebox(
			theme,
			.CheckBox,
			"box_on",
			mode_box(seg_fill, on_border, p.border_width, 5),
		)
		GUI.Theme_Set_Stylebox(
			theme,
			.CheckBox,
			"box_on_hover",
			mode_box(seg_fill, on_hover_border, p.border_width, 5),
		)

		GUI.Theme_Set_Type(
			theme,
			.HSlider,
			GUI.Style{text = GUI.Text_Style{colour = p.text}},
		)
		GUI.Theme_Set_Type(
			theme,
			.ProgressBar,
			GUI.Style{text = GUI.Text_Style{colour = p.text}},
		)
		GUI.Theme_Set_Color(theme, .HSlider, "track_color", p.field)
		GUI.Theme_Set_Color(theme, .HSlider, "fill_color", p.accent)
		GUI.Theme_Set_Color(theme, .ProgressBar, "track_color", p.field)
		GUI.Theme_Set_Color(theme, .ProgressBar, "fill_color", p.accent)
		GUI.Theme_Set_Color(theme, .ToggleSwitch, "fill_color", seg_fill)
		GUI.Theme_Set_Color(theme, .ToggleSwitch, "thumb_color", GUI.RGBA(1, 1, 1, 0.97))
		GUI.Theme_Set_Color(theme, .Segmented, "fill_color", seg_fill)
		GUI.Theme_Set_Color(theme, .Segmented, "on_fill_color", seg_ink)
		GUI.Theme_Set_Color(theme, .Rating, "fill_color", p.accent)
		GUI.Theme_Set_Color(theme, .Rating, "track_color", p.dim)
		GUI.Theme_Set_Color(theme, .ComboBox, "panel_color", p.popup)
		GUI.Theme_Set_Color(theme, .ComboBox, "fill_color", seg_fill)
		GUI.Theme_Set_Color(theme, .ComboBox, "on_fill_color", seg_ink)
		GUI.Theme_Set_Color(theme, .DatePicker, "fill_color", seg_fill)
		GUI.Theme_Set_Color(theme, .DatePicker, "on_fill_color", seg_ink)
		GUI.Theme_Set_Color(theme, .TimePicker, "fill_color", seg_fill)
		GUI.Theme_Set_Color(theme, .TimePicker, "on_fill_color", seg_ink)

		GUI.Theme_Add_Variation(
			theme,
			"danger",
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.danger,
					border_color = {p.danger_hi, p.danger_hi, p.danger_hi, p.danger_hi},
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.control_radius, p.control_radius, p.control_radius, p.control_radius},
					content_margin = {12, 7, 12, 7},
					shadow_color = p.shadow,
					shadow_size = p.shadow_size * button_shadow_scale,
					shadow_offset = {p.shadow_offset.x * button_offset_scale, p.shadow_offset.y * button_offset_scale},
					backdrop_blur = p.button_blur,
					optics = p.button_optics,
				},
				text = GUI.Text_Style{colour = GUI.RGBA(1, 0.95, 0.95, 1)},
			},
		)
		GUI.Theme_Set_Variation_State(
			theme,
			"danger",
			.Button,
			.Hovered,
			GUI.Style{box = GUI.StyleBox{bg_color = p.danger_hi}},
		)
		GUI.Theme_Add_Variation(
			theme,
			"success",
			.Button,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.success,
					border_color = {p.success_hi, p.success_hi, p.success_hi, p.success_hi},
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.control_radius, p.control_radius, p.control_radius, p.control_radius},
					content_margin = {12, 7, 12, 7},
					shadow_color = p.shadow,
					shadow_size = p.shadow_size * button_shadow_scale,
					shadow_offset = {p.shadow_offset.x * button_offset_scale, p.shadow_offset.y * button_offset_scale},
					backdrop_blur = p.button_blur,
					optics = p.button_optics,
				},
				text = GUI.Text_Style{colour = GUI.RGBA(0.94, 1, 0.95, 1)},
			},
		)
		GUI.Theme_Set_Variation_State(
			theme,
			"success",
			.Button,
			.Hovered,
			GUI.Style{box = GUI.StyleBox{bg_color = p.success_hi}},
		)
	}

	glass_wall := next == .Liquid_Glass || next == .Fluent
	if wallpaper != GUI.INVALID_WIDGET_ID {
		GUI.Widget_Set_Visible(g, wallpaper, glass_wall)
	}
	if specimen != GUI.INVALID_WIDGET_ID {
		GUI.Widget_Set_Visible(g, specimen, glass_wall)
	}
	if specimen_glass != GUI.INVALID_WIDGET_ID {
		GUI.Widget_Set_Style(
			g,
			specimen_glass,
			GUI.Style {
				box = GUI.StyleBox {
					bg_color = p.surface,
					border_color = {p.border, p.border, p.border, p.border},
					border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
					corner_radius = {p.panel_radius, p.panel_radius, p.panel_radius, p.panel_radius},
					backdrop_blur = p.panel_blur,
					optics = p.panel_optics,
				},
			},
		)
	}

	update_swatches()
	GUI.Widget_Set_Style(
		g,
		g.root,
		GUI.Style {
			box = GUI.StyleBox {
				bg_color = p.window,
			},
			text = GUI.Text_Style{colour = p.text},
		},
	)
	GUI.Widget_Set_Text(g, status, status_text(next))
	if glass_wall && !g.backend.supports_backdrop_blur {
		GUI.Widget_Set_Text(g, status, "Glass over the wallpaper. Start with --gpu to blur, bend and split it.")
	}
	GUI.Animation_Stop_Target(g, status)
	GUI.Animation_Start(
		g,
		GUI.Animation_Desc{
			target = status,
			property = .Opacity,
			from = GUI.Animation_Value(f32(0.20)),
			to = GUI.Animation_Value(f32(1)),
			duration = 0.30,
			easing = .Out_Cubic,
		},
	)
	start_banner(p)
}

apply_field_style :: proc(
	theme: ^GUI.Theme,
	type: GUI.Widget_Type,
	p: Palette,
	border: [4]GUI.Colour,
	margin: [4]f32,
) {
	soft_shadow := p.shadow
	soft_shadow.a *= 0.35
	GUI.Theme_Set_Type(
		theme,
		type,
		GUI.Style {
			box = GUI.StyleBox {
				bg_color = p.field,
				border_color = border,
				border_width = {p.border_width, p.border_width, p.border_width, p.border_width},
				corner_radius = {p.field_radius, p.field_radius, p.field_radius, p.field_radius},
				content_margin = margin,
				backdrop_blur = p.field_blur,
				optics = p.field_optics,
				shadow_color = p.raised ? soft_shadow : (GUI.Colour{}),
				shadow_size = p.raised ? p.shadow_size * 0.3 : 0,
				shadow_spread = p.raised ? 1 : 0,
				shadow_inset = p.raised,
			},
			text = GUI.Text_Style {
				colour = p.text,
				disabled_colour = p.dim,
				focus_colour = p.accent,
				valign = .Center,
			},
			transition = GUI.Style_Transition{duration = 0.15, easing = .Out_Cubic},
		},
	)
}

update_swatches :: proc() {
	p := palette(mode)
	GUI.color_rect_set_colour(g, swatch_rects[0], p.accent)
	GUI.color_rect_set_colour(g, swatch_rects[1], p.accent2)
	GUI.color_rect_set_colour(g, swatch_rects[2], p.danger)
	GUI.color_rect_set_colour(g, swatch_rects[3], p.success)
	GUI.color_rect_set_colour(g, swatch_rects[4], p.text)
}

status_text :: proc(m: Mode) -> string {
	switch m {
	case .Dark:
		return "The dark theme is showing."
	case .Light:
		return "The light theme is showing."
	case .Ocean:
		return "The ocean theme is showing."
	case .Liquid_Glass:
		return "Liquid glass over a moving wallpaper."
	case .Neumorphism:
		return "Soft surfaces pressed out of one colour."
	case .Material_3:
		return "Material 3 Expressive: tonal colour and big shapes."
	case .Fluent:
		return "Fluent acrylic panels over a Mica backdrop."
	}
	return ""
}

mode_box :: proc(bg: GUI.Colour, border: [4]GUI.Colour, width, radius: f32) -> GUI.StyleBox {
	return GUI.StyleBox {
		bg_color = bg,
		border_color = border,
		border_width = {width, width, width, width},
		corner_radius = {radius, radius, radius, radius},
	}
}

//* The wallpaper the glass panels sit on. It is baked into one texture a
//* few times a second and drawn as a single textured quad, so the glass
//* blurs a picture rather than a pile of discs.
paint_wallpaper :: proc(gui: ^GUI.GUI, id: GUI.Widget_ID, state: ^GUI.Canvas_State) {
	w := gui.viewport.w
	h := gui.viewport.h
	if w <= 0 || h <= 0 {
		return
	}
	wall_phase += gui.dt * 0.22
	if wall_texture.region.id < 0 {
		install_wall_texture(gui)
	}
	wall_bake_accum += gui.dt
	if wall_dirty || wall_bake_accum >= 1 / WALL_BAKE_HZ {
		wall_bake_accum = 0
		wall_dirty = false
		bake_wallpaper()
		_ = GUI.texture_update(gui, wall_texture, wall_pixels)
	}
	append(
		&state.items,
		GUI.Canvas_Item {
			kind = .Texture,
			pos = {0, 0},
			size = {w, h},
			texture = wall_texture,
			colour = GUI.RGBA(1, 1, 1, 1),
		},
	)
}

install_wall_texture :: proc(gui: ^GUI.GUI) {
	w := gui.viewport.w
	h := gui.viewport.h
	if w <= 0 || h <= 0 {
		return
	}
	if w >= h {
		wall_tex_w = WALL_TEX_MAX
		wall_tex_h = max(1, int(f32(WALL_TEX_MAX) * h / w))
	} else {
		wall_tex_h = WALL_TEX_MAX
		wall_tex_w = max(1, int(f32(WALL_TEX_MAX) * w / h))
	}
	delete(wall_pixels)
	wall_pixels = make([]u8, wall_tex_w * wall_tex_h * 4)
	bake_wallpaper()
	wall_texture = GUI.texture_from_pixels(gui, wall_pixels, wall_tex_w, wall_tex_h)
	wall_dirty = false
	wall_bake_accum = 0
}

bake_wallpaper :: proc() {
	if len(wall_pixels) < wall_tex_w * wall_tex_h * 4 || wall_tex_w <= 0 || wall_tex_h <= 0 {
		return
	}
	p := palette(mode)
	w := wall_tex_w
	h := wall_tex_h

	for y in 0 ..< h {
		for x in 0 ..< w {
			at := (y * w + x) * 4
			wall_set_pixel(wall_pixels, at, p.window)
		}
	}

	shade_rows := int(f32(h) * 0.55)
	for y in 0 ..< shade_rows {
		for x in 0 ..< w {
			at := (y * w + x) * 4
			colour := GUI.Colour{0, 0, 0, 0.22}
			blend_wall_pixel(wall_pixels, at, colour)
		}
	}

	if p.wall_a.a > 0 {
		size := f32(min(w, h))
		wall_blob_pixels((0.18 + 0.05 * math.sin(wall_phase)) * f32(w), (0.30 + 0.06 * math.cos(wall_phase * 0.8)) * f32(h), 0.78 * size, p.wall_a)
		wall_blob_pixels((0.84 + 0.04 * math.cos(wall_phase * 0.7)) * f32(w), (0.18 + 0.05 * math.sin(wall_phase * 1.1)) * f32(h), 0.70 * size, p.wall_b)
		wall_blob_pixels((0.52 + 0.07 * math.sin(wall_phase * 0.9 + 1.3)) * f32(w), (0.90 + 0.04 * math.cos(wall_phase * 0.6)) * f32(h), 0.74 * size, p.wall_c)
		wall_blob_pixels((0.72 + 0.05 * math.sin(wall_phase * 0.6 + 2.1)) * f32(w), (0.58 + 0.05 * math.cos(wall_phase * 0.9)) * f32(h), 0.44 * size, p.wall_d)

		step := max(1, int(0.0475 * f32(w)))
		line := GUI.Colour{1, 1, 1, 0.045}
		for x := step; x < w; x += step {
			for y in 0 ..< h {
				blend_wall_pixel(wall_pixels, (y * w + x) * 4, line)
			}
		}
		for y := step; y < h; y += step {
			for x in 0 ..< w {
				blend_wall_pixel(wall_pixels, (y * w + x) * 4, line)
			}
		}

		bar := GUI.Colour{1, 1, 1, 0.10}
		wall_rect_pixels(0.08 * f32(w), 0.20 * f32(h), 0.20 * f32(w), 22 * f32(w) / 1180, bar)
		wall_rect_pixels(0.70 * f32(w), 0.68 * f32(h), 0.16 * f32(w), 30 * f32(w) / 1180, bar)
		wall_rect_pixels(0.40 * f32(w), 0.42 * f32(h), 64 * f32(w) / 1180, 64 * f32(w) / 1180, GUI.Colour{0.02, 0.03, 0.06, 0.55})
		wall_circle_pixels(0.58 * f32(w), 0.08 * f32(h), 45 * f32(w) / 1180, GUI.Colour{1, 1, 1, 0.08})
	}
}

wall_set_pixel :: proc(pixels: []u8, at: int, colour: GUI.Colour) {
	pixels[at + 0] = u8(clamp(colour.r, 0, 1) * 255)
	pixels[at + 1] = u8(clamp(colour.g, 0, 1) * 255)
	pixels[at + 2] = u8(clamp(colour.b, 0, 1) * 255)
	pixels[at + 3] = u8(clamp(colour.a, 0, 1) * 255)
}

blend_wall_pixel :: proc(pixels: []u8, at: int, colour: GUI.Colour) {
	a := clamp(colour.a, 0, 1)
	if a <= 0 {
		return
	}
	pixels[at + 0] = u8(f32(pixels[at + 0]) * (1 - a) + clamp(colour.r, 0, 1) * a * 255)
	pixels[at + 1] = u8(f32(pixels[at + 1]) * (1 - a) + clamp(colour.g, 0, 1) * a * 255)
	pixels[at + 2] = u8(f32(pixels[at + 2]) * (1 - a) + clamp(colour.b, 0, 1) * a * 255)
}

wall_rect_pixels :: proc(x, y, w, h: f32, colour: GUI.Colour) {
	x0 := max(int(x), 0)
	y0 := max(int(y), 0)
	x1 := min(int(x + w + 0.999), wall_tex_w)
	y1 := min(int(y + h + 0.999), wall_tex_h)
	for py in y0 ..< y1 {
		for px in x0 ..< x1 {
			blend_wall_pixel(wall_pixels, (py * wall_tex_w + px) * 4, colour)
		}
	}
}

wall_circle_pixels :: proc(cx, cy, radius: f32, colour: GUI.Colour) {
	if radius <= 0 {
		return
	}
	x0 := max(int(cx - radius), 0)
	y0 := max(int(cy - radius), 0)
	x1 := min(int(cx + radius + 0.999), wall_tex_w)
	y1 := min(int(cy + radius + 0.999), wall_tex_h)
	for py in y0 ..< y1 {
		for px in x0 ..< x1 {
			dx := f32(px) + 0.5 - cx
			dy := f32(py) + 0.5 - cy
			if dx * dx + dy * dy <= radius * radius {
				blend_wall_pixel(wall_pixels, (py * wall_tex_w + px) * 4, colour)
			}
		}
	}
}

wall_blob_pixels :: proc(cx, cy, radius: f32, colour: GUI.Colour) {
	if radius <= 0 {
		return
	}
	alpha := min(palette(mode).wall_alpha * 12, 0.5)
	x0 := max(int(cx - radius), 0)
	y0 := max(int(cy - radius), 0)
	x1 := min(int(cx + radius + 0.999), wall_tex_w)
	y1 := min(int(cy + radius + 0.999), wall_tex_h)
	inv := 1 / radius
	for py in y0 ..< y1 {
		for px in x0 ..< x1 {
			dx := f32(px) + 0.5 - cx
			dy := f32(py) + 0.5 - cy
			t := 1 - math.sqrt(dx * dx + dy * dy) * inv
			if t <= 0 {
				continue
			}
			blend_wall_pixel(
				wall_pixels,
				(py * wall_tex_w + px) * 4,
				GUI.Colour{colour.r, colour.g, colour.b, alpha * t * t},
			)
		}
	}
}

paint_specimen :: proc(gui: ^GUI.GUI, id: GUI.Widget_ID, state: ^GUI.Canvas_State) {
	x := f32(26)
	y := gui.viewport.h - 166
	w := f32(300)
	h := f32(102)
	if w <= 0 || h <= 0 {return}

	cell :: 12
	for gy := 0; gy < int(h); gy += cell {
		for gx := 0; gx < int(w); gx += cell {
			colour := GUI.RGBA(0.10, 0.30, 0.85, 1)
			if (gx / cell + gy / cell) % 2 == 0 {
				colour = GUI.RGBA(0.95, 0.45, 0.18, 1)
			}
			append(
				&state.items,
				GUI.Canvas_Item {
					kind = .Rect,
					pos = {x + f32(gx), y + f32(gy)},
					size = {cell, cell},
					colour = colour,
				},
			)
		}
	}

	append(
		&state.items,
		GUI.Canvas_Item {
			kind = .Circle,
			pos = {x + w * 0.16, y - 22},
			size = {92, 92},
			colour = GUI.RGBA(1, 1, 1, 0.85),
		},
	)
	append(
		&state.items,
		GUI.Canvas_Item {
			kind = .Rect,
			pos = {x + w * 0.62, y + h * 0.30},
			size = {48, h},
			colour = GUI.RGBA(0.02, 0.03, 0.06, 0.8),
		},
	)
	append(
		&state.items,
		GUI.Canvas_Item {
			kind = .Rect,
			pos = {x + w * 0.70, y + h * 0.10},
			size = {2, h * 0.8},
			colour = GUI.RGBA(1, 1, 1, 0.9),
		},
	)
}

//* A flat canvas has no gradient, so a blob is a stack of discs that
//* fade out towards its edge.

start_banner :: proc(p: Palette) {
	if banner == GUI.INVALID_WIDGET_ID {return}
	GUI.Animation_Stop_Target(g, banner)
	GUI.Animation_Start(
		g,
		GUI.Animation_Desc{
			target = banner,
			property = .Background,
			from = GUI.Animation_Value(p.accent),
			to = GUI.Animation_Value(p.accent2),
			duration = 2.6,
			easing = .Smooth,
			repeat = 0,
			ping_pong = false,
		},
	)
}
