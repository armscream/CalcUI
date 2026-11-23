//* == Custom backend ==
// The same draw list the toolkit gives SDL3, rendered by the shared
// software backend. There is no window, no SDL and no GPU, so the
// program runs on a machine with no screen: it writes the picture it
// drew to a file instead of showing it.

package main

import "core:log"
import Backend "../../src/Backend"
import GUI "../../src/GUI"

WIDTH :: 640
HEIGHT :: 400

FONT_DATA :: #load("../../assets/fonts/Roboto-Regular.ttf")

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	state := &Backend.Software_State{}
	defer Backend.software_destroy(state)

	backend := GUI.Backend {
		ctx                    = cast(rawptr)state,
		create                 = Backend.software_create,
		destroy                = Backend.software_destroy,
		resize                 = Backend.software_resize,
		upload_texture         = Backend.software_upload_texture,
		upload_texture_regions = Backend.software_upload_texture_regions,
		destroy_texture        = Backend.software_destroy_texture,
		submit                 = Backend.software_submit,
		submit_target          = Backend.software_submit_target,
		supports_shapes        = true,
		supports_backdrop_blur = true,
	}

	if !GUI.Backend_Create(backend, nil, WIDTH, HEIGHT) {
		log.panic("the renderer could not be made")
	}

	g := GUI.Init_GUI(WIDTH, HEIGHT, backend)
	defer GUI.Shutdown_GUI(g)
	g.scale = 1

	family := GUI.Font_Family_Add(g, "Roboto", FONT_DATA)
	g.default_font_size = 16
	GUI.Font_Warmup(g, GUI.Font_At(g, family, 16))

	build_scene(g)

	GUI.Frame(g)
	GUI.Backend_Submit(backend, &g.draw)

	path := "bin\\custom_backend.ppm"
	if !Backend.software_write_ppm(state, path) {
		log.panicf("could not write %s", path)
	}
	log.infof("wrote %s", path)
}

build_scene :: proc(g: ^GUI.GUI) {
	root := GUI.Widget_Get(g, g.root)
	root_style := root.style
	root_style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)
	GUI.Widget_Set_Style(g, g.root, root_style)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "title",
				offsets = GUI.Offset{left = 24, top = 24, right = -24, bottom = 56},
			},
			text = "CalcUI with a backend of its own",
		},
	)

	GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "card",
				offsets = GUI.Offset{left = 24, top = 72, right = -260, bottom = -164},
				style = GUI.Style {
					box = GUI.StyleBox {
						bg_color = GUI.RGBA(0.18, 0.22, 0.34, 1),
						border_color = {
							GUI.RGBA(0.30, 0.38, 0.52, 1),
							GUI.RGBA(0.30, 0.38, 0.52, 1),
							GUI.RGBA(0.30, 0.38, 0.52, 1),
							GUI.RGBA(0.30, 0.38, 0.52, 1),
						},
						border_width = {1, 1, 1, 1},
						corner_radius = {18, 18, 18, 18},
						content_margin = {16, 16, 16, 16},
						shadow_color = GUI.RGBA(0, 0, 0, 0.55),
						shadow_size = 16,
						shadow_offset = {0, 6},
						shadow_spread = 4,
					},
				},
			},
		},
	)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "card_title",
				offsets = GUI.Offset{left = 44, top = 96, right = -44, bottom = 128},
			},
			text = "A rounded surface with a shadow",
		},
	)

	for i in 0 ..< 4 {
		x0 := 400 + f32(i) * 40
		GUI.Make_Panel(
			g,
			g.root,
			GUI.Panel_Opts {
				Base_Opts = GUI.Base_Opts {
					offsets = GUI.Offset{left = x0, top = 170, right = x0 + 22 - WIDTH, bottom = -90},
					style = GUI.Style {
						box = GUI.StyleBox {
							bg_color = i % 2 == 0 ? GUI.RGBA(0.55, 0.18, 0.22, 1) : GUI.RGBA(0.14, 0.48, 0.40, 1),
						},
					},
				},
			},
		)
	}

	GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "glass",
				offsets = GUI.Offset{left = 300, top = 120, right = -40, bottom = -60},
				style = GUI.Style {
					box = GUI.StyleBox {
						bg_color = GUI.RGBA(0.85, 0.91, 1.0, 0.18),
						border_color = {
							GUI.RGBA(0.90, 0.95, 1.0, 0.35),
							GUI.RGBA(0.90, 0.95, 1.0, 0.35),
							GUI.RGBA(0.90, 0.95, 1.0, 0.35),
							GUI.RGBA(0.90, 0.95, 1.0, 0.35),
						},
						border_width = {1, 1, 1, 1},
						corner_radius = {24, 24, 24, 24},
						content_margin = {16, 16, 16, 16},
						backdrop_blur = 14,
					},
				},
			},
		},
	)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "glass_title",
				offsets = GUI.Offset{left = 316, top = 140, right = -56, bottom = 172},
			},
			text = "Frosted glass",
		},
	)

	GUI.Make_Label(
		g,
		g.root,
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "foot",
				offsets = GUI.Offset{left = 36, top = 320, right = -36, bottom = -20},
			},
			text = "Every pixel was filled by hand from the draw list.",
		},
	)

	image_pixels := make([]u8, 32 * 32 * 4)
	defer delete(image_pixels)
	for y in 0 ..< 32 {
		for x in 0 ..< 32 {
			at := (y * 32 + x) * 4
			left := x < 16
			image_pixels[at + 0] = left ? 210 : 60
			image_pixels[at + 1] = left ? 80 : 70
			image_pixels[at + 2] = left ? 60 : 190
			image_pixels[at + 3] = 255
		}
	}
	image := GUI.texture_from_pixels(g, image_pixels, 32, 32)

	GUI.Make_Texture_Rect(
		g,
		g.root,
		GUI.Texture_Rect_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "image",
				offsets = GUI.Offset{left = 60, top = 144, right = -460, bottom = -175},
				style = GUI.Style {
					box = GUI.StyleBox{corner_radius = {16, 16, 16, 16}},
				},
			},
			texture = image,
		},
	)

	GUI.Make_Panel(
		g,
		g.root,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "field",
				offsets = GUI.Offset{left = 40, top = 248, right = -360, bottom = -100},
				style = GUI.Style {
					box = GUI.StyleBox {
						bg_color = GUI.RGBA(0.10, 0.12, 0.18, 1),
						border_color = {
							GUI.RGBA(0.24, 0.28, 0.38, 1),
							GUI.RGBA(0.24, 0.28, 0.38, 1),
							GUI.RGBA(0.24, 0.28, 0.38, 1),
							GUI.RGBA(0.24, 0.28, 0.38, 1),
						},
						border_width = {1, 1, 1, 1},
						corner_radius = {12, 12, 12, 12},
						shadow_color = GUI.RGBA(0, 0, 0, 0.55),
						shadow_size = 8,
						shadow_spread = 3,
						shadow_inset = true,
					},
				},
			},
		},
	)
}
