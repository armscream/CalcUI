//* The text draw pipeline, checked against the contract: the layout of
//* a piece of text and the quads it puts in the draw list.
//
//* These tests only use the public side of the pipeline — draw_text and
//* text_measure — so they hold whatever the layout is built on.
package GUI

import "core:testing"

//* What a piece of text put in the draw list.
Text_Test_Draw :: struct {
	quads:   int,
	bounds:  Rect,
	last_uv: [2]f32,
	clip:    Rect,
	colour:  Colour,
}

//* A GUI with a font, ready to draw text into.
text_test_gui :: proc(t: ^testing.T) -> ^GUI {
	g := test_gui(t)
	g.backend = mock_backend
	g.default_font = font_load(g, "assets/fonts/Roboto-Regular.ttf", 16)
	return g
}

//* The rect of the quad that starts at vertex `i`.
text_test_quad :: proc(dl: ^Draw_List, i: int) -> Rect {
	v := dl.vertices[i]
	return Rect{
		x = v.pos[0],
		y = v.pos[1],
		w = dl.vertices[i + 1].pos[0] - v.pos[0],
		h = dl.vertices[i + 3].pos[1] - v.pos[1],
	}
}

//* The box that holds every quad of the list.
text_test_bounds :: proc(dl: ^Draw_List) -> Rect {
	if len(dl.vertices) < 4 { return {} }
	r := text_test_quad(dl, 0)
	for q in 1 ..< len(dl.vertices) / 4 {
		quad := text_test_quad(dl, q * 4)
		x0 := min(r.x, quad.x)
		y0 := min(r.y, quad.y)
		x1 := max(r.x + r.w, quad.x + quad.w)
		y1 := max(r.y + r.h, quad.y + quad.h)
		r = Rect{x = x0, y = y0, w = x1 - x0, h = y1 - y0}
	}
	return r
}

//* Draws a piece of text into the draw list of the GUI and reports what
//* it put there.
text_test_draw :: proc(g: ^GUI, ts: Text_Style, text: string, rect: Rect) -> Text_Test_Draw {
	draw_list_clear(&g.draw, g.viewport)
	g.target = &g.draw
	draw_text(g, ts, text, rect, rgba(1, 1, 1, 1))

	out: Text_Test_Draw
	out.quads = len(g.draw.vertices) / 4
	out.bounds = text_test_bounds(&g.draw)
	if len(g.draw.vertices) >= 4 {
		out.last_uv = g.draw.vertices[len(g.draw.vertices) - 4].uv
		out.colour = g.draw.vertices[0].colour
	}
	if len(g.draw.commands) > 0 {
		out.clip = g.draw.commands[0].clip
	}
	return out
}

@(test)
test_text_draws_glyph_quads :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 400, h = 100}

	ts := Text_Style{size = 16, colour = rgba(1, 1, 1, 1)}
	dl := text_test_draw(g, ts, "Hello", rect)

	//* Every glyph of the text is a quad in the draw list.
	testing.expect_value(t, dl.quads, 5)

	//* The ink has the colour it was given.
	testing.expect_value(t, dl.colour.r, 1.0)
	testing.expect_value(t, dl.colour.a, 1.0)

	//* A bigger size is a wider text.
	small := text_measure(g, ts, "Hello", 0)
	big_ts := Text_Style{size = 32, colour = rgba(1, 1, 1, 1)}
	big := text_measure(g, big_ts, "Hello", 0)
	testing.expect_value(t, big.x > small.x, true)

	//* And it is drawn wider too.
	small_dl := text_test_draw(g, ts, "Hello", rect)
	big_dl := text_test_draw(g, big_ts, "Hello", rect)
	testing.expect_value(t, big_dl.bounds.w > small_dl.bounds.w, true)

	test_gui_destroy(g)
}

@(test)
test_text_transform_changes_the_text_that_is_laid_out :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 400, h = 100}

	plain := Text_Style{size = 16}
	upper := Text_Style{size = 16, transform = .Upper}
	lower := Text_Style{size = 16, transform = .Lower}
	capital := Text_Style{size = 16, transform = .Capitalize}

	//* The upper cased text is measured as the upper cased text.
	m := text_measure(g, upper, "hello world", 0)
	reference := text_measure(g, plain, "HELLO WORLD", 0)
	testing.expect_value(t, m.x, reference.x)
	testing.expect_value(t, m.y, reference.y)

	//* The lower cased text is measured as the lower cased text.
	m = text_measure(g, lower, "HELLO WORLD", 0)
	reference = text_measure(g, plain, "hello world", 0)
	testing.expect_value(t, m.x, reference.x)

	//* The capitalised text has the first letter of every word in upper
	//* case, and the rest of the word as it was.
	m = text_measure(g, capital, "hello world", 0)
	reference = text_measure(g, plain, "Hello World", 0)
	testing.expect_value(t, m.x, reference.x)

	//* And the drawn text is the transformed text.
	dl := text_test_draw(g, upper, "hello", rect)
	ref_dl := text_test_draw(g, plain, "HELLO", rect)
	testing.expect_value(t, dl.quads, ref_dl.quads)
	testing.expect_value(t, dl.bounds.w, ref_dl.bounds.w)

	test_gui_destroy(g)
}

@(test)
test_text_wrap_word_makes_more_than_one_line :: proc(t: ^testing.T) {
	g := text_test_gui(t)

	plain := Text_Style{size = 16}
	wrapped := Text_Style{size = 16, wrap = .Word}

	one := text_measure(g, plain, "hello", 0)
	many := text_measure(g, wrapped, "hello world of text that wraps", 100)

	//* The text is broken into more than one line, so the block is
	//* taller than a single line.
	testing.expect_value(t, many.y > one.y, true)

	//* Every line fits in the width the text was broken at.
	testing.expect_value(t, many.x <= 100, true)

	//* The same text without a width stays on one line.
	flat := text_measure(g, wrapped, "hello world of text that wraps", 0)
	testing.expect_value(t, flat.y, one.y)

	test_gui_destroy(g)
}

@(test)
test_text_wrap_anywhere_breaks_inside_a_word :: proc(t: ^testing.T) {
	g := text_test_gui(t)

	plain := Text_Style{size = 16}
	anywhere := Text_Style{size = 16, wrap = .Anywhere}
	text := "abcdefghijklmnopqrstuvwxyz"

	one := text_measure(g, plain, text, 0)
	many := text_measure(g, anywhere, text, 60)

	//* The long word is broken into more than one line.
	testing.expect_value(t, many.y > one.y, true)

	//* And every line fits in the width it was broken at.
	testing.expect_value(t, many.x <= 60, true)

	test_gui_destroy(g)
}

@(test)
test_text_align_center_moves_the_glyphs_to_the_right :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 400, h = 100}

	left := text_test_draw(g, Text_Style{size = 16, align = .Left}, "Hello", rect)
	center := text_test_draw(g, Text_Style{size = 16, align = .Center}, "Hello", rect)
	right := text_test_draw(g, Text_Style{size = 16, align = .Right}, "Hello", rect)

	//* The centred text starts further to the right, and the right
	//* aligned text further still.
	testing.expect_value(t, center.bounds.x > left.bounds.x, true)
	testing.expect_value(t, right.bounds.x > center.bounds.x, true)

	//* The right edge of the right aligned text is the right edge of
	//* the box.
	testing.expect_value(t, right.bounds.x + right.bounds.w <= rect.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_align_fill_spreads_the_words_out :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 120, h = 200}
	text := "one two three four"

	left := text_test_draw(g, Text_Style{size = 16, align = .Left, wrap = .Word}, text, rect)
	fill := text_test_draw(g, Text_Style{size = 16, align = .Fill, wrap = .Word}, text, rect)

	//* The justified text is wider: the words are spread out so that
	//* the line fills the box.
	testing.expect_value(t, fill.bounds.w > left.bounds.w, true)

	test_gui_destroy(g)
}

@(test)
test_text_valign_center_moves_the_glyphs_down :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 400, h = 200}

	top := text_test_draw(g, Text_Style{size = 16, valign = .Top}, "Hello", rect)
	center := text_test_draw(g, Text_Style{size = 16, valign = .Center}, "Hello", rect)
	bottom := text_test_draw(g, Text_Style{size = 16, valign = .Bottom}, "Hello", rect)

	testing.expect_value(t, center.bounds.y > top.bounds.y, true)
	testing.expect_value(t, bottom.bounds.y > center.bounds.y, true)

	test_gui_destroy(g)
}

@(test)
test_text_spacing_pushes_the_lines_apart :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 100, h = 400}
	text := "hello world of wrapping text"

	plain := Text_Style{size = 16, wrap = .Word}
	spaced := Text_Style{size = 16, wrap = .Word, spacing = 12}

	//* The block of text is taller with the spacing.
	h_plain := text_measure(g, plain, text, 100).y
	h_spaced := text_measure(g, spaced, text, 100).y
	testing.expect_value(t, h_spaced > h_plain, true)

	//* And the text is drawn taller too.
	d_plain := text_test_draw(g, plain, text, rect)
	d_spaced := text_test_draw(g, spaced, text, rect)
	testing.expect_value(t, d_spaced.bounds.h > d_plain.bounds.h, true)

	test_gui_destroy(g)
}

@(test)
test_text_shadow_and_outline_add_quads :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 400, h = 100}
	text := "Hello"

	plain := text_test_draw(g, Text_Style{size = 16}, text, rect)
	n := plain.quads
	testing.expect_value(t, n > 0, true)

	//* The shadow is a second copy of every glyph.
	shadow := text_test_draw(g, Text_Style{
		size          = 16,
		shadow_colour = rgba(0, 0, 0, 0.5),
		shadow_offset = Vec2{2, 2},
	}, text, rect)
	testing.expect_value(t, shadow.quads, n * 2)

	//* The outline is a ring of eight copies around every glyph.
	outline := text_test_draw(g, Text_Style{
		size           = 16,
		outline_colour = rgba(1, 1, 1, 1),
		outline_size   = 1,
	}, text, rect)
	testing.expect_value(t, outline.quads, n * 9)

	//* Both of them.
	both := text_test_draw(g, Text_Style{
		size           = 16,
		shadow_colour  = rgba(0, 0, 0, 0.5),
		shadow_offset  = Vec2{2, 2},
		outline_colour = rgba(1, 1, 1, 1),
		outline_size   = 1,
	}, text, rect)
	testing.expect_value(t, both.quads, n * 10)

	test_gui_destroy(g)
}

@(test)
test_text_overrun_ellipsis_cuts_the_text_so_that_it_fits :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 60, h = 40}
	text := "hello world"

	plain := text_test_draw(g, Text_Style{size = 16}, text, rect)

	//* The text does not fit in the box.
	testing.expect_value(t, plain.bounds.w > rect.w, true)

	ell := text_test_draw(g, Text_Style{size = 16, overrun = .Ellipsis}, text, rect)

	//* The text was cut, and what is left fits in the box.
	testing.expect_value(t, ell.bounds.w < plain.bounds.w, true)
	testing.expect_value(t, ell.bounds.w <= rect.w + 1, true)
	testing.expect_value(t, ell.quads < plain.quads, true)

	//* The last glyph of the cut text is the ellipsis.
	only := text_test_draw(g, Text_Style{size = 16}, "…", rect)
	testing.expect_value(t, ell.last_uv, only.last_uv)

	test_gui_destroy(g)
}

@(test)
test_text_overrun_words_cuts_at_a_word_boundary :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 70, h = 40}
	text := "hello world of text"

	words := text_test_draw(g, Text_Style{size = 16, overrun = .Words}, text, rect)
	ell := text_test_draw(g, Text_Style{size = 16, overrun = .Ellipsis}, text, rect)

	//* Both of them cut the text so that it fits in the box.
	testing.expect_value(t, words.bounds.w <= rect.w + 1, true)
	testing.expect_value(t, ell.bounds.w <= rect.w + 1, true)

	//* The cut at a word boundary is never longer than the cut
	//* anywhere.
	testing.expect_value(t, words.bounds.w <= ell.bounds.w + 1, true)

	test_gui_destroy(g)
}

@(test)
test_text_clip_cuts_the_text_at_the_edge_of_the_box :: proc(t: ^testing.T) {
	g := text_test_gui(t)
	rect := Rect{x = 0, y = 0, w = 100, h = 30}

	clipped := text_test_draw(g, Text_Style{size = 16, clip = true}, "Hello", rect)
	testing.expect_value(t, clipped.clip.w, rect.w)
	testing.expect_value(t, clipped.clip.h, rect.h)

	//* Without the clip the text is only clipped to the viewport.
	plain := text_test_draw(g, Text_Style{size = 16}, "Hello", rect)
	testing.expect_value(t, plain.clip.w, g.viewport.w)

	test_gui_destroy(g)
}
