//* Tests for the text draw pipeline: the transform, the wrapping, the
//* overrun and the decorations.
package GUI

import "core:testing"

//* A GUI with a font and an empty draw list, ready for text.
test_text_gui :: proc(t: ^testing.T) -> ^GUI {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	draw_list_clear(&g.draw, g.viewport)
	return g
}

//* The number of quads that were drawn. A quad is four vertices.
drawn_quads :: proc(g: ^GUI) -> int {
	return len(g.draw.vertices) / 4
}

//* The box the drawn quads cover: the smallest one that holds them all.
drawn_bounds :: proc(g: ^GUI) -> Rect {
	if len(g.draw.vertices) == 0 { return {} }
	min_x := g.draw.vertices[0].pos[0]
	min_y := g.draw.vertices[0].pos[1]
	max_x := min_x
	max_y := min_y
	for v in g.draw.vertices {
		min_x = min(min_x, v.pos[0])
		min_y = min(min_y, v.pos[1])
		max_x = max(max_x, v.pos[0])
		max_y = max(max_y, v.pos[1])
	}
	return Rect{x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y}
}

//* The number of lines of text that were drawn. The quads of one line
//* sit on top of each other, the quads of two lines do not, so the
//* quads are grouped into rows.
drawn_lines :: proc(g: ^GUI) -> int {
	rows: [64]Rect
	count := 0
	for i in 0 ..< len(g.draw.vertices) / 4 {
		p := g.draw.vertices[i*4].pos
		q := g.draw.vertices[i*4+2].pos
		r := Rect{x = p[0], y = p[1], w = q[0]-p[0], h = q[1]-p[1]}

		found := false
		for j in 0 ..< count {
			row := &rows[j]
			if r.y < row.y+row.h && row.y < r.y+r.h {
				bottom := max(row.y+row.h, r.y+r.h)
				row.y = min(row.y, r.y)
				row.h = bottom - row.y
				found = true
				break
			}
		}
		if !found {
			rows[count] = r
			count += 1
		}
	}
	return count
}

@(test)
test_text_draw_draws_glyph_quads :: proc(t: ^testing.T) {
	g := test_text_gui(t)

	before := len(g.draw.vertices)
	draw_text(g, Text_Style{}, "Hello", Rect{0, 0, 200, 40}, rgba(1, 1, 1, 1))
	after := len(g.draw.vertices)

	//* The text grew the draw list.
	testing.expect_value(t, after > before, true)
	//* Every quad is four vertices.
	testing.expect_value(t, (after - before) % 4, 0)
	//* One quad for every glyph of the text.
	testing.expect_value(t, (after - before) / 4 >= 5, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_draws_at_the_size_of_the_style :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 400, 100}

	draw_text(g, Text_Style{size = 16}, "Hello", rect, rgba(1, 1, 1, 1))
	small := drawn_bounds(g)

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{size = 32}, "Hello", rect, rgba(1, 1, 1, 1))
	big := drawn_bounds(g)

	//* The bigger text is bigger.
	testing.expect_value(t, big.h > small.h, true)
	testing.expect_value(t, big.w > small.w, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_transforms_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello world"
	rect := Rect{0, 0, 400, 40}

	draw_text(g, Text_Style{}, text, rect, rgba(1, 1, 1, 1))
	plain := drawn_bounds(g).w

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{transform = .Upper}, text, rect, rgba(1, 1, 1, 1))
	upper := drawn_bounds(g).w

	//* The upper case text is not the text that was given.
	testing.expect_value(t, upper > plain, true)

	//* It is the upper case text: it is as wide as the upper case
	//* string is.
	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{}, "HELLO WORLD", rect, rgba(1, 1, 1, 1))
	testing.expect_value(t, upper, drawn_bounds(g).w)

	test_gui_destroy(g)
}

@(test)
test_text_draw_capitalizes_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 400, 40}

	draw_text(g, Text_Style{transform = .Capitalize}, "hello world", rect, rgba(1, 1, 1, 1))
	capitalized := drawn_bounds(g).w

	//* Every word starts with a capital, and the rest of the word is
	//* left as it is.
	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{}, "Hello World", rect, rgba(1, 1, 1, 1))
	testing.expect_value(t, capitalized, drawn_bounds(g).w)

	test_gui_destroy(g)
}

@(test)
test_text_draw_wraps_into_more_lines :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "the quick brown fox jumps over the lazy dog"

	draw_text(g, Text_Style{wrap = .Off}, text, Rect{0, 0, 800, 200}, rgba(1, 1, 1, 1))
	testing.expect_value(t, drawn_lines(g), 1)
	plain_height := drawn_bounds(g).h

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{wrap = .Word}, text, Rect{0, 0, 100, 200}, rgba(1, 1, 1, 1))

	//* The narrow box needs more than one line.
	testing.expect_value(t, drawn_lines(g) > 1, true)
	testing.expect_value(t, drawn_bounds(g).h > plain_height, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_breaks_anywhere :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello wonderful world"
	rect := Rect{0, 0, 80, 100}

	draw_text(g, Text_Style{wrap = .Word}, text, rect, rgba(1, 1, 1, 1))
	word := drawn_bounds(g).w

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{wrap = .Anywhere}, text, rect, rgba(1, 1, 1, 1))
	anywhere := drawn_bounds(g).w

	//* The anywhere break fills the line, the word break leaves the
	//* rest of the line empty.
	testing.expect_value(t, anywhere > word, true)
	testing.expect_value(t, drawn_lines(g) > 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_valign_moves_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 200, 100}

	draw_text(g, Text_Style{valign = .Top}, "Hello", rect, rgba(1, 1, 1, 1))
	top := drawn_bounds(g).y

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{valign = .Center}, "Hello", rect, rgba(1, 1, 1, 1))
	center := drawn_bounds(g).y

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{valign = .Bottom}, "Hello", rect, rgba(1, 1, 1, 1))
	bottom := drawn_bounds(g).y

	testing.expect_value(t, center > top, true)
	testing.expect_value(t, bottom > center, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_align_moves_the_text :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 200, 40}

	draw_text(g, Text_Style{align = .Left}, "Hello", rect, rgba(1, 1, 1, 1))
	left := drawn_bounds(g).x

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{align = .Center}, "Hello", rect, rgba(1, 1, 1, 1))
	center := drawn_bounds(g).x

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{align = .Right}, "Hello", rect, rgba(1, 1, 1, 1))
	right := drawn_bounds(g).x

	testing.expect_value(t, center > left, true)
	testing.expect_value(t, right > center, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_fills_the_line :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 200, 100}

	draw_text(
		g,
		Text_Style{wrap = .Word, align = .Fill},
		"one two three four five six seven eight",
		rect,
		rgba(1, 1, 1, 1),
	)

	//* The words are spread out, so the line reaches the edge of the
	//* box.
	testing.expect_value(t, drawn_bounds(g).w > rect.w - 10, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_spacing_pushes_the_lines_apart :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "the quick brown fox jumps over the lazy dog"
	rect := Rect{0, 0, 100, 200}

	draw_text(g, Text_Style{wrap = .Word}, text, rect, rgba(1, 1, 1, 1))
	plain := drawn_bounds(g).h

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{wrap = .Word, spacing = 10}, text, rect, rgba(1, 1, 1, 1))

	testing.expect_value(t, drawn_bounds(g).h > plain, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_outline_draws_a_ring_of_copies :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 200, 40}

	draw_text(g, Text_Style{}, "Hello", rect, rgba(1, 1, 1, 1))
	plain := drawn_quads(g)

	draw_list_clear(&g.draw, g.viewport)
	draw_text(
		g,
		Text_Style{outline_colour = rgba(0, 0, 0, 1), outline_size = 2},
		"Hello",
		rect,
		rgba(1, 1, 1, 1),
	)
	outlined := drawn_quads(g)

	//* The ink, and a copy of it in each of the eight directions.
	testing.expect_value(t, outlined, plain * 9)

	test_gui_destroy(g)
}

@(test)
test_text_draw_shadow_draws_a_second_copy :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{0, 0, 200, 40}

	draw_text(g, Text_Style{}, "Hello", rect, rgba(1, 1, 1, 1))
	plain := drawn_quads(g)

	draw_list_clear(&g.draw, g.viewport)
	draw_text(
		g,
		Text_Style{shadow_colour = rgba(0, 0, 0, 1), shadow_offset = Vec2{2, 2}},
		"Hello",
		rect,
		rgba(1, 1, 1, 1),
	)
	shadowed := drawn_quads(g)

	testing.expect_value(t, shadowed, plain * 2)

	test_gui_destroy(g)
}

@(test)
test_text_draw_overrun_cuts_the_text_short :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello world this is a long text"
	rect := Rect{0, 0, 60, 40}

	draw_text(g, Text_Style{}, text, rect, rgba(1, 1, 1, 1))
	plain := drawn_quads(g)

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{overrun = .Ellipsis}, text, rect, rgba(1, 1, 1, 1))
	cut := drawn_quads(g)

	//* The text does not fit, so it is cut short.
	testing.expect_value(t, cut < plain, true)
	//* What is left of it fits, with the ellipsis.
	testing.expect_value(t, drawn_bounds(g).w <= rect.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_overrun_cuts_at_a_word_boundary :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	text := "hello world this is a long text"
	rect := Rect{0, 0, 90, 40}

	//* The text does not fit the box.
	draw_text(g, Text_Style{}, text, rect, rgba(1, 1, 1, 1))
	testing.expect_value(t, drawn_bounds(g).w > rect.w, true)

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{overrun = .Ellipsis}, text, rect, rgba(1, 1, 1, 1))
	ellipsis := drawn_bounds(g).w

	draw_list_clear(&g.draw, g.viewport)
	draw_text(g, Text_Style{overrun = .Words}, text, rect, rgba(1, 1, 1, 1))
	words := drawn_bounds(g).w

	//* The words are cut at a word boundary, so the text is not longer
	//* than the text that was cut anywhere.
	testing.expect_value(t, words <= ellipsis, true)
	//* And what is left of it fits.
	testing.expect_value(t, words <= rect.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_draw_clips_to_its_box :: proc(t: ^testing.T) {
	g := test_text_gui(t)
	rect := Rect{10, 20, 100, 30}

	draw_text(g, Text_Style{clip = true}, "Hello", rect, rgba(1, 1, 1, 1))

	//* The text is drawn inside its own box.
	testing.expect_value(t, len(g.draw.commands) > 0, true)
	testing.expect_value(t, g.draw.commands[0].clip.x, 10.0)
	testing.expect_value(t, g.draw.commands[0].clip.y, 20.0)
	testing.expect_value(t, g.draw.commands[0].clip.w, 100.0)
	testing.expect_value(t, g.draw.commands[0].clip.h, 30.0)

	test_gui_destroy(g)
}
