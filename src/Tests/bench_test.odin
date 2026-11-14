//* Benchmarks for layout, drawing, styling, atlas operations and virtualized widgets.

package Tests

import GUI "../GUI"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:testing"
import "core:time"
import virt "core:mem/virtual"

Bench :: struct {
	name:       string,
	iterations: int,
	ns_each:    f64,
	vertices:   int,
	commands:   int,
}

Bench_Kind :: enum {
	Draw_List,
	Frame,
	Layout,
	Make_Atlas,
	Make_Gui,
	Atlas_Churn,
	Atlas_Churn_Big,
	Style,
	Style_And_Colour,
}

bench_measure :: proc(kind: Bench_Kind, g: ^GUI.GUI, t: ^testing.T, iterations: int) -> f64 {
	start := time.time_to_unix_nano(time.now())

	switch kind {
	case .Draw_List:
		for i in 0 ..< iterations {
			virt.arena_free_all(&g.frame_arena)
			GUI.build_draw_list(g)
		}
	case .Frame:
		for i in 0 ..< iterations {
			GUI.Frame(g)
		}
	case .Layout:
		for i in 0 ..< iterations {
			GUI.invalidate_all(g, GUI.Dirty_Flags{.Arrange, .Hit})
			GUI.layout_pass(g)
		}
	case .Make_Atlas:
		for i in 0 ..< iterations {
			a := GUI.atlas_make(GUI.ATLAS_DEFAULT_SIZE, GUI.ATLAS_DEFAULT_SIZE)
			GUI.atlas_destroy(a)
		}
	case .Make_Gui:
		for i in 0 ..< iterations {
			ng := test_gui(t)
			bench_scene_panels(ng, 100)
			GUI.layout_pass(ng)
			test_gui_destroy(ng)
		}
	case .Atlas_Churn, .Atlas_Churn_Big:
		a := GUI.atlas_make(512, 512)
		size := 16
		if kind == .Atlas_Churn_Big {
			size = 64
		}
		for i in 0 ..< iterations {
			r := GUI.atlas_alloc(a, size, size, kind == .Atlas_Churn_Big)
			if r.id >= 0 {
				GUI.atlas_free(a, r)
			}
		}
		GUI.atlas_destroy(a)
	case .Style:
		for i in 0 ..< iterations {
			for w in g.widgets {
				if w != nil {
					_ = GUI.resolved_style(g, w)
				}
			}
		}
	case .Style_And_Colour:
		for i in 0 ..< iterations {
			for w in g.widgets {
				if w != nil {
					_ = GUI.resolved_bg(g, w.id, w)
					_ = GUI.resolved_text_colour(g, w.id, w)
				}
			}
		}
	}

	return f64(time.time_to_unix_nano(time.now()) - start)
}

bench_report :: proc(b: Bench) {
	if b.vertices > 0 {
		fmt.printf("bench %s: %d x %.0f ns, %d vertices, %d commands\n",
			b.name, b.iterations, b.ns_each, b.vertices, b.commands)
	} else {
		fmt.printf("bench %s: %d x %.0f ns\n", b.name, b.iterations, b.ns_each)
	}
}

bench_expect_faster :: proc(t: ^testing.T, ns: f64, iterations: int, budget: f32) {
	multiple := bench_budget()
	if multiple > 0 {
		testing.expect_value(t, ns / f64(iterations) < f64(budget * multiple), true)
	}
}

bench_budget :: proc() -> f32 {
	buf: [64]byte
	raw := os.get_env_buf(buf[:], "CALCUI_BENCH_BUDGET")
	if raw == "" {
		return 1
	}
	value, ok := strconv.parse_f32(raw)
	if !ok {
		return 1
	}
	return max(0, value)
}

//* Benchmark scenes

bench_gui_sized :: proc(t: ^testing.T, w, h: f32) -> ^GUI.GUI {
	g := test_gui(t)
	g.viewport = GUI.Rect{w = w, h = h}
	g.window_rect = g.viewport
	return g
}

bench_scene_panels :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, .VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1),
			border_color = {GUI.RGBA(0.4, 0.4, 0.5, 1), GUI.RGBA(0.4, 0.4, 0.5, 1),
			                GUI.RGBA(0.4, 0.4, 0.5, 1), GUI.RGBA(0.4, 0.4, 0.5, 1)},
			border_width = {1, 1, 1, 1},
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel", style = style})
	}
}

bench_scene_rounded :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, GUI.VBox, g.root, GUI.Widget_Opts{separation = 2})
	style := GUI.Style {
		box = GUI.StyleBox {
			bg_color = GUI.RGBA(0.2, 0.2, 0.3, 1),
			corner_radius = {6, 6, 6, 6},
		},
	}
	for i in 0 ..< count {
		GUI.New_Widget(g, .Panel, box, GUI.Widget_Opts{name = "panel", style = style})
	}
}

bench_scene_buttons :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, GUI.VBox, g.root, GUI.Widget_Opts{separation = 2})
	for i in 0 ..< count {
		GUI.New_Widget(g, .Button, box, GUI.Widget_Opts{name = "button", text = "Press"})
	}
}

bench_scene_labels :: proc(g: ^GUI.GUI, count: int) {
	box := GUI.New_Widget(g, GUI.VBox, g.root, GUI.Widget_Opts{separation = 2})
	for i in 0 ..< count {
		GUI.New_Widget(g, .Label, box, GUI.Widget_Opts{
			name = "label",
			text = "The quick brown fox jumps over the lazy dog",
		})
	}
}

//* Virtualized data sources

BENCH_ROW_VALUES: [4]string = {"alpha", "bravo", "charlie", "delta"}

Bench_List_Data :: struct {
	count:       int,
	texts_asked: int,
}

Bench_Table_Data :: struct {
	count:        int,
	values_asked: int,
}

bench_list_count :: proc(ctx: rawptr) -> int {
	return (cast(^Bench_List_Data)ctx).count
}

bench_list_text :: proc(ctx: rawptr, index: int) -> string {
	(cast(^Bench_List_Data)ctx).texts_asked += 1
	return "a row"
}

bench_list_height :: proc(ctx: rawptr, index: int) -> f32 {
	return 20 if index % 2 == 0 else 30
}

bench_list_source :: proc(data: ^Bench_List_Data) -> GUI.List_Source {
	return GUI.List_Source{count = bench_list_count, text = bench_list_text, ctx = cast(rawptr)data}
}

bench_list_source_with_heights :: proc(data: ^Bench_List_Data) -> GUI.List_Source {
	source := bench_list_source(data)
	source.height = bench_list_height
	return source
}

bench_table_count :: proc(ctx: rawptr) -> int {
	return (cast(^Bench_Table_Data)ctx).count
}

bench_table_values :: proc(ctx: rawptr, index: int) -> []string {
	(cast(^Bench_Table_Data)ctx).values_asked += 1
	return BENCH_ROW_VALUES[:]
}

bench_table_source :: proc(data: ^Bench_Table_Data) -> GUI.Table_Source {
	return GUI.Table_Source{count = bench_table_count, values = bench_table_values, ctx = cast(rawptr)data}
}

bench_virtual_list_frames :: proc(g: ^GUI.GUI, data: ^Bench_List_Data, iterations: int) -> f64 {
	start := time.time_to_unix_nano(time.now())
	for i in 0 ..< iterations {
		data.texts_asked = 0
		virt.arena_free_all(&g.frame_arena)
		GUI.build_draw_list(g)
	}
	return f64(time.time_to_unix_nano(time.now()) - start)
}

bench_data_table_frames :: proc(g: ^GUI.GUI, data: ^Bench_Table_Data, iterations: int) -> f64 {
	start := time.time_to_unix_nano(time.now())
	for i in 0 ..< iterations {
		data.values_asked = 0
		virt.arena_free_all(&g.frame_arena)
		GUI.build_draw_list(g)
	}
	return f64(time.time_to_unix_nano(time.now()) - start)
}

//* Benchmarks

@(test)
test_bench_the_draw_list_is_built :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	bench_scene_buttons(g, 200)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	iterations := 200
	ns := bench_measure(.Draw_List, g, t, iterations)
	bench_report(Bench{"draw list, 200 buttons", iterations, ns / f64(iterations),
	                   len(g.draw.vertices), len(g.draw.commands)})
	bench_expect_faster(t, ns, iterations, 50e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_draw_list_of_boxes_is_built :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	bench_scene_panels(g, 400)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	iterations := 200
	ns := bench_measure(.Draw_List, g, t, iterations)
	bench_report(Bench{"draw list, 400 panels", iterations, ns / f64(iterations),
	                   len(g.draw.vertices), len(g.draw.commands)})
	bench_expect_faster(t, ns, iterations, 50e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_draw_list_of_text_is_built :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	bench_scene_labels(g, 60)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	iterations := 50
	ns := bench_measure(.Draw_List, g, t, iterations)
	bench_report(Bench{"draw list, 60 labels", iterations, ns / f64(iterations),
	                   len(g.draw.vertices), len(g.draw.commands)})
	bench_expect_faster(t, ns, iterations, 60e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_draw_list_of_rounded_boxes_is_built :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	g.backend.supports_shapes = true
	bench_scene_rounded(g, 200)
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	iterations := 100
	ns := bench_measure(.Draw_List, g, t, iterations)
	with_shader := len(g.draw.vertices)
	bench_report(Bench{"draw list, 200 round panels", iterations, ns / f64(iterations),
	                   with_shader, len(g.draw.commands)})

	g.backend.supports_shapes = false
	cpu_ns := bench_measure(.Draw_List, g, t, iterations)
	without_shader := len(g.draw.vertices)
	bench_report(Bench{"draw list, 200 round panels, CPU", iterations, cpu_ns / f64(iterations),
	                   without_shader, len(g.draw.commands)})

	testing.expect_value(t, without_shader > with_shader * 4, true)
	bench_expect_faster(t, ns, iterations, 60e6)
	bench_expect_faster(t, cpu_ns, iterations, 60e6)
	test_gui_destroy(g)
}

@(test)
test_bench_a_frame_is_built :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	bench_scene_buttons(g, 200)
	GUI.Frame(g)

	iterations := 100
	ns := bench_measure(.Frame, g, t, iterations)
	bench_report(Bench{"frame, 200 buttons", iterations, ns / f64(iterations),
	                   len(g.draw.vertices), len(g.draw.commands)})
	bench_expect_faster(t, ns, iterations, 60e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_layout_pass_runs :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	bench_scene_panels(g, 400)
	GUI.layout_pass(g)

	iterations := 200
	ns := bench_measure(.Layout, g, t, iterations)
	bench_report(Bench{"layout, 400 panels", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 50e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_style_of_every_widget_is_worked_out :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	bench_scene_panels(g, 400)
	GUI.layout_pass(g)

	iterations := 200
	ns := bench_measure(.Style, g, t, iterations)
	bench_report(Bench{"style, 400 panels", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 50e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_colours_of_every_widget_are_worked_out :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 1920, 4000)
	g.backend = mock_backend
	bench_scene_panels(g, 400)
	GUI.layout_pass(g)

	iterations := 200
	ns := bench_measure(.Style_And_Colour, g, t, iterations)
	bench_report(Bench{"style and colour, 400 panels", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 50e6)
	test_gui_destroy(g)
}

@(test)
test_bench_the_atlas_is_made_and_given_back :: proc(t: ^testing.T) {
	iterations := 10
	ns := bench_measure(.Make_Atlas, nil, t, iterations)
	bench_report(Bench{"atlas make and destroy", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 300e6)
}

@(test)
test_bench_a_gui_is_made_and_given_back :: proc(t: ^testing.T) {
	iterations := 10
	ns := bench_measure(.Make_Gui, nil, t, iterations)
	bench_report(Bench{"make and destroy, 100 widgets", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 300e6)
}

@(test)
test_bench_the_atlas_hands_out_and_takes_back_space :: proc(t: ^testing.T) {
	iterations := 2000
	ns := bench_measure(.Atlas_Churn, nil, t, iterations)
	bench_report(Bench{"atlas alloc and free, 16x16", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 5e6)
}

@(test)
test_bench_the_atlas_gives_out_a_glyph_page :: proc(t: ^testing.T) {
	iterations := 2000
	ns := bench_measure(.Atlas_Churn_Big, nil, t, iterations)
	bench_report(Bench{"atlas alloc and free, 64x64", iterations, ns / f64(iterations)})
	bench_expect_faster(t, ns, iterations, 5e6)
}

//* Virtualized widgets should request only visible rows, regardless of data size.

@(test)
test_bench_a_virtual_list_draws_only_the_rows_that_are_on_the_screen :: proc(t: ^testing.T) {
	sizes := [4]int{1000, 10000, 100000, 1000000}
	iterations := 50
	visible := 31
	fastest, slowest := f64(0), f64(0)

	for size in sizes {
		g := bench_gui_sized(t, 800, 600)
		g.backend = mock_backend
		g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

		data := Bench_List_Data{count = size}
		GUI.Make_Virtual_List(g, g.root, GUI.Virtual_List_Opts{
			Base_Opts = GUI.Base_Opts{name = "list"},
			source = bench_list_source(&data),
			row_height = 20,
		})
		GUI.layout_pass(g)
		GUI.build_draw_list(g)

		ns := bench_virtual_list_frames(g, &data, iterations)
		each := ns / f64(iterations)
		testing.expect_value(t, data.texts_asked, visible)

		bench_report(Bench{fmt.tprintf("virtual list, %d rows", size), iterations, each,
		                   len(g.draw.vertices), len(g.draw.commands)})

		if fastest == 0 || each < fastest {fastest = each}
		slowest = max(slowest, each)
		test_gui_destroy(g)
	}

	testing.expect_value(t, slowest < fastest * 4, true)
}

@(test)
test_bench_a_data_table_draws_only_the_rows_that_are_on_the_screen :: proc(t: ^testing.T) {
	sizes := [4]int{1000, 10000, 100000, 1000000}
	iterations := 50
	visible := 25
	fastest, slowest := f64(0), f64(0)

	for size in sizes {
		g := bench_gui_sized(t, 800, 600)
		g.backend = mock_backend
		g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

		data := Bench_Table_Data{count = size}
		id := GUI.Make_Data_Table(g, g.root, GUI.Data_Table_Opts{
			Base_Opts = GUI.Base_Opts{name = "table"},
			source = bench_table_source(&data),
		})
		GUI.data_table_add_column(g, id, "Name", 200)
		GUI.layout_pass(g)
		GUI.build_draw_list(g)

		ns := bench_data_table_frames(g, &data, iterations)
		each := ns / f64(iterations)
		testing.expect_value(t, data.values_asked, visible)

		bench_report(Bench{fmt.tprintf("data table, %d rows", size), iterations, each,
		                   len(g.draw.vertices), len(g.draw.commands)})

		if fastest == 0 || each < fastest {fastest = each}
		slowest = max(slowest, each)
		test_gui_destroy(g)
	}

	testing.expect_value(t, slowest < fastest * 4, true)
}

@(test)
test_bench_a_virtual_list_with_rows_of_different_heights_is_drawn :: proc(t: ^testing.T) {
	g := bench_gui_sized(t, 800, 600)
	g.backend = mock_backend
	g.default_font = GUI.Font_Load(g, "assets/fonts/Roboto-Regular.ttf", 16)

	data := Bench_List_Data{count = 100000}
	GUI.Make_Virtual_List(g, g.root, GUI.Virtual_List_Opts{
		Base_Opts = GUI.Base_Opts{name = "list"},
		source = bench_list_source_with_heights(&data),
		row_height = 20,
	})
	GUI.layout_pass(g)
	GUI.build_draw_list(g)

	iterations := 50
	ns := bench_virtual_list_frames(g, &data, iterations)
	testing.expect_value(t, data.texts_asked, 24)

	bench_report(Bench{"virtual list, 100000 mixed-height rows", iterations,
	                   ns / f64(iterations), len(g.draw.vertices), len(g.draw.commands)})
	bench_expect_faster(t, ns, iterations, 60e6)
	test_gui_destroy(g)
}