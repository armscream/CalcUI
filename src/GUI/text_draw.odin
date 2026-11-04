package GUI

//* == Drawing text ==
//* The draw pass of a piece of text.
//
//* The text style says how the text looks: the typeface and the size,
//* the colour of the ink, how the text is broken into lines, where it
//* sits in its box and what is drawn under it. The decorations - the
//* outline and the shadow - are drawn first, so the ink is on top of
//* them.
//
//* The pipeline is:
//*   transform -> wrap -> overrun -> vertical alignment -> horizontal
//*   alignment -> shadow -> outline -> ink
//
//* Everything that lives longer than a frame is in the font; every
//* allocation this file does is in the frame arena, which is emptied at
//* the start of every frame.

import runa "./dependencies/Runa"
import virt "core:mem/virtual"
import "core:strings"
import "core:unicode"

//* The mark that says the text was cut short.
TEXT_ELLIPSIS :: "…"

//* The eight directions the outline is copied in. The rasterizer has no
//* stroke mode, so an outline is a ring of copies of the glyph.
OUTLINE_DIRS :: [8][2]f32{{1, 0}, {0, 1}, {-1, 0}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

//* One glyph, ready to be drawn: where it is, where it samples from
//* and which page of the atlas it is on.
Glyph_Quad :: struct {
	rect: Rect,
	uv:   [4]f32,
	tex:  Texture_ID,
}

//* One line of the block: the glyphs, their metrics, and the text they
//* were shaped from.
Text_Line :: struct {
	glyphs:   []runa.Paragraph_Glyph,
	width:    f32,
	height:   f32,
	baseline: f32,
	//* The text the clusters point into. It is the whole string when
	//* the text is broken at word boundaries, and the piece of it when
	//* it is broken anywhere.
	src:      string,
	//* Where the line starts in `src`.
	start:    int,
}

//* Draws `text` into `rect`, in the style's font and colour.
draw_text :: proc(g: ^GUI, ts: Text_Style, text: string, rect: Rect, colour: Colour) {
	if text == "" {return}
	font_id := Font_Resolve(g, ts)
	if font_id == INVALID_FONT_ID {return}
	f := font_get(g, font_id)
	if f == nil {return}

	//* The transform comes first: everything after it works on the
	//* string that is really drawn.
	src := apply_text_transform(g, ts, text)

	//* The lines of the block.
	lines := wrap_text_lines(g, f, ts, src, rect.w)
	if len(lines) == 0 {return}

	//* The last line is cut short when the text does not fit.
	if ts.overrun != .None {
		cut_text_overrun(g, f, ts, &lines, rect)
	}

	//* The quads of the glyphs are worked out once, so the shadow, the
	//* outline and the ink are all drawn from the same list.
	quads := glyph_quads(g, f, lines[:], ts, rect)
	if len(quads) == 0 {return}

	if ts.clip {draw_push_clip(g.target, rect)}

	//* The shadow, under everything else.
	if ts.shadow_colour.a > 0 {
		off := ts.shadow_offset
		for q in quads {
			draw_quad(
				g.target,
				Rect{x = q.rect.x + off.x, y = q.rect.y + off.y, w = q.rect.w, h = q.rect.h},
				q.uv,
				ts.shadow_colour,
				q.tex,
			)
		}
	}

	//* The outline: a ring of copies of every glyph around itself.
	if ts.outline_size > 0 && ts.outline_colour.a > 0 {
		d := ts.outline_size
		for q in quads {
			for o in OUTLINE_DIRS {
				draw_quad(
					g.target,
					Rect {
						x = q.rect.x + o[0] * d,
						y = q.rect.y + o[1] * d,
						w = q.rect.w,
						h = q.rect.h,
					},
					q.uv,
					ts.outline_colour,
					q.tex,
				)
			}
		}
	}

	//* The ink.
	for q in quads {
		draw_quad(g.target, q.rect, q.uv, colour, q.tex)
	}

	if ts.clip {draw_pop_clip(g.target)}
}

//* The size of the text as it would be drawn: the width of the widest
//* line and the height of the whole block. `width` is the width the
//* text is wrapped at (0 means it is not wrapped). Nothing is drawn.
text_measure :: proc(g: ^GUI, ts: Text_Style, text: string, width: f32) -> Vec2 {
	if text == "" {return {}}
	font_id := Font_Resolve(g, ts)
	if font_id == INVALID_FONT_ID {return {}}
	f := font_get(g, font_id)
	if f == nil {return {}}

	//* The size of a text that has not changed is remembered: shaping
	//* it is not cheap, and the layout pass measures every text of
	//* every widget every frame.
	key := Measure_Key {
		font      = font_id,
		size      = ts.size,
		text      = text,
		width     = width,
		spacing   = ts.spacing,
		wrap      = ts.wrap,
		transform = ts.transform,
	}
	if size, ok := measure_cache_get(g, key); ok {return size}

	src := apply_text_transform(g, ts, text)
	lines := wrap_text_lines(g, f, ts, src, width)
	if len(lines) == 0 {return {}}

	w: f32 = 0
	for line in lines {
		w = max(w, line.width)
	}
	size := Vec2{w, text_block_height(lines[:], ts.spacing)}
	measure_cache_put(g, key, size)
	return size
}

//* == The layout ==

//* The lines of the text, broken to fit `max_w`.
wrap_text_lines :: proc(
	g: ^GUI,
	f: ^Font,
	ts: Text_Style,
	text: string,
	max_w: f32,
) -> [dynamic]Text_Line {
	opts := f.opts
	opts.max_width = 0
	switch ts.wrap {
	case .Word:
		if max_w > 0 {opts.max_width = max_w}
	case .Anywhere:
		//* Runa only breaks at word boundaries, so the pieces that fit
		//* the width are cut by hand below.
		return wrap_text_anywhere(g, f, text, max_w)
	case .Off:
	}
	return shape_text_lines(g, f, text, text, opts)
}

//* Lays a string out and gives back its lines. The clusters of the
//* glyphs are byte offsets into `src`, which is the text the line was
//* shaped from.
shape_text_lines :: proc(
	g: ^GUI,
	f: ^Font,
	str: string,
	src: string,
	opts: runa.Paragraph_Opts,
) -> [dynamic]Text_Line {
	allocator := virt.arena_allocator(&g.frame_arena)
	shaped, err := runa.layout_paragraph(str, opts, shape_cache(g), allocator)
	if err != .None {return nil}

	out := make([dynamic]Text_Line, 0, len(shaped), allocator)
	for l in shaped {
		start := 0
		if len(l.glyphs) > 0 {start = int(l.glyphs[0].cluster)}
		append(
			&out,
			Text_Line {
				glyphs = l.glyphs,
				width = l.width,
				height = l.height,
				baseline = l.baseline,
				src = src,
				start = start,
			},
		)
	}
	return out
}

//* Breaks the text into the pieces that fit the width. Runa breaks at
//* word boundaries only, so the pieces are cut here: the text is
//* shaped once, the advances say where a piece ends, and every piece
//* is laid out on its own.
wrap_text_anywhere :: proc(g: ^GUI, f: ^Font, text: string, max_w: f32) -> [dynamic]Text_Line {
	allocator := virt.arena_allocator(&g.frame_arena)
	out := make([dynamic]Text_Line, 0, 4, allocator)
	if max_w <= 0 {
		opts := f.opts
		opts.max_width = 0
		for l in shape_text_lines(g, f, text, text, opts) {append(&out, l)}
		return out
	}

	//* A hard break ends a piece of its own: the text after it starts
	//* a new line.
	start := 0
	for i in 0 ..= len(text) {
		if i < len(text) && text[i] != '\n' {continue}
		end := i
		if end > start && text[end - 1] == '\r' {end -= 1}
		wrap_text_piece(&out, g, f, text[start:end], max_w)
		start = i + 1
	}
	return out
}

//* Cuts one piece of text into the chunks that fit the width. A word
//* that is too wide is cut at a codepoint boundary, and a space stays
//* with the chunk before it.
wrap_text_piece :: proc(out: ^[dynamic]Text_Line, g: ^GUI, f: ^Font, piece: string, max_w: f32) {
	if piece == "" {return}
	allocator := virt.arena_allocator(&g.frame_arena)

	//* The piece is shaped once: the advances say where the chunks end.
	opts := f.opts
	opts.max_width = 0
	shaped, err := runa.layout_paragraph(piece, opts, shape_cache(g), allocator)
	if err != .None {return}

	glyphs: []runa.Paragraph_Glyph
	if len(shaped) > 0 {glyphs = shaped[0].glyphs}

	start := 0
	width: f32 = 0
	has_glyph := false
	for pg in glyphs {
		cluster := int(pg.cluster)
		//* The chunk before took the space.
		if cluster < start {continue}
		if has_glyph && width + pg.x_advance > max_w {
			cut := cluster
			//* A space belongs to the chunk before it.
			for cut < len(piece) && piece[cut] == ' ' {cut += 1}
			for l in shape_text_lines(g, f, piece[start:cut], piece[start:cut], opts) {
				append(out, l)
			}
			start = cut
			width = 0
			has_glyph = false
			if cut > cluster {continue}
		}
		width += pg.x_advance
		has_glyph = true
	}
	if start < len(piece) {
		for l in shape_text_lines(g, f, piece[start:], piece[start:], opts) {append(out, l)}
	}
}

//* The height of a block of text: the lines and the space between them.
text_block_height :: proc(lines: []Text_Line, spacing: f32) -> f32 {
	if len(lines) == 0 {return 0}
	h: f32 = 0
	for i in 0 ..< len(lines) {
		h += lines[i].height
		if i < len(lines) - 1 {h += spacing}
	}
	return h
}

//* == The transform ==

//* The text as it is laid out: the transform of the style is applied to
//* it before anything else happens.
apply_text_transform :: proc(g: ^GUI, ts: Text_Style, text: string) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	switch ts.transform {
	case .Upper:
		res, err := strings.to_upper(text, allocator)
		if err != nil {return text}
		return res
	case .Lower:
		res, err := strings.to_lower(text, allocator)
		if err != nil {return text}
		return res
	case .Capitalize:
		return capitalize_text(g, text)
	case .None:
	}
	return text
}

//* The text with the first letter of every word in upper case. A word
//* starts at the beginning of the text and after any rune that is not a
//* letter; the rest of the word is left as it is.
capitalize_text :: proc(g: ^GUI, text: string) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	b: strings.Builder
	if _, err := strings.builder_init_len_cap(&b, 0, len(text), allocator);
	   err != nil {return text}

	start := true
	for r in text {
		if unicode.is_letter(r) {
			if start {
				strings.write_rune(&b, unicode.to_upper(r))
			} else {
				strings.write_rune(&b, r)
			}
			start = false
		} else {
			strings.write_rune(&b, r)
			start = true
		}
	}
	return strings.to_string(b)
}

//* == The overrun ==

//* Cuts the last line short when the text does not fit the box, and
//* puts an ellipsis where it was cut. The cut text is laid out again,
//* so the ellipsis is shaped with the text it belongs to.
cut_text_overrun :: proc(
	g: ^GUI,
	f: ^Font,
	ts: Text_Style,
	lines: ^[dynamic]Text_Line,
	box: Rect,
) {
	if len(lines) == 0 {return}
	last := lines[len(lines) - 1]
	if len(last.glyphs) == 0 {return}

	//* The ellipsis is part of the text, so it has to fit as well.
	budget := box.w - Font_Measure(g, f.id, TEXT_ELLIPSIS).x
	if last.width <= budget {return}

	//* The longest piece of the line that still fits.
	width: f32 = 0
	keep := 0
	for pg in last.glyphs {
		if width + pg.x_advance > budget {break}
		width += pg.x_advance
		keep += 1
	}
	if keep == 0 {return}

	src := last.src
	cut := int(last.glyphs[keep].cluster)
	if cut > len(src) {cut = len(src)}

	//* The words are cut at a word boundary.
	if ts.overrun == .Words {
		if p := last_space_before(src, last.start, cut); p > last.start {cut = p}
	}
	//* A space in front of the ellipsis is not wanted.
	for cut > last.start && src[cut - 1] == ' ' {cut -= 1}

	//* The cut text is laid out again, in the same way as the text it
	//* replaces.
	opts := f.opts
	opts.max_width = 0
	if ts.wrap == .Word && box.w > 0 {opts.max_width = box.w}
	trimmed := join_text(g, src[last.start:cut], TEXT_ELLIPSIS)
	cut_lines := shape_text_lines(g, f, trimmed, trimmed, opts)
	if len(cut_lines) == 0 {return}

	resize(lines, len(lines) - 1)
	for l in cut_lines {append(lines, l)}
}

//* The place of the last space in `src[from:to]`, so that a cut can be
//* made at a word boundary.
last_space_before :: proc(src: string, from, to: int) -> int {
	end := min(to, len(src))
	for i := end - 1; i >= from; i -= 1 {
		if src[i] == ' ' {return i}
	}
	return -1
}

//* Two strings, joined in the frame arena.
join_text :: proc(g: ^GUI, a, b: string) -> string {
	allocator := virt.arena_allocator(&g.frame_arena)
	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, len(a) + len(b), allocator);
	   err != nil {
		return a
	}
	strings.write_string(&builder, a)
	strings.write_string(&builder, b)
	return strings.to_string(builder)
}

//* == The quads ==

//* The quads of every glyph of the text, in the order they are drawn.
glyph_quads :: proc(
	g: ^GUI,
	f: ^Font,
	lines: []Text_Line,
	ts: Text_Style,
	rect: Rect,
) -> []Glyph_Quad {
	quads := make([dynamic]Glyph_Quad, 0, 64, virt.arena_allocator(&g.frame_arena))

	//* Where the block of text sits in the box.
	top := rect.y
	switch ts.valign {
	case .Center:
		top += (rect.h - text_block_height(lines, ts.spacing)) * 0.5
	case .Bottom:
		top += rect.h - text_block_height(lines, ts.spacing)
	case .Top:
	}

	y := top
	for li in 0 ..< len(lines) {
		line := lines[li]
		x := rect.x
		switch ts.align {
		case .Center:
			x += (rect.w - line.width) * 0.5
		case .Right:
			x += rect.w - line.width
		case .Left, .Fill:
		}

		//* A justified line has its words spread out so that it fills
		//* the box. The last line of a paragraph is not justified, and
		//* neither is a line with a single word in it.
		extra: f32 = 0
		if ts.align == .Fill && li < len(lines) - 1 {
			if spaces := line_space_count(line); spaces > 0 {
				extra = (rect.w - line.width) / f32(spaces)
			}
		}

		baseline := y + line.baseline
		pen := x
		for gi in 0 ..< len(line.glyphs) {
			pg := line.glyphs[gi]
			if gi > 0 && extra != 0 && line_has_space(line, gi - 1) {
				//* A space was swallowed between the two glyphs, so
				//* the word after it is pushed to the right.
				pen += extra
			}
			slot, ok := font_slot(g, f, pg.glyph_id)
			if ok && slot.px_size[0] > 0 && slot.px_size[1] > 0 {
				append(
					&quads,
					Glyph_Quad {
						rect = Rect {
							x = pen + pg.x_offset + slot.bearing[0],
							y = baseline + pg.y_offset + slot.bearing[1],
							w = f32(slot.px_size[0]),
							h = f32(slot.px_size[1]),
						},
						uv = slot.uv,
						tex = g.atlas_texture,
					},
				)
			}
			pen += pg.x_advance
		}
		y += line.height + ts.spacing
	}
	return quads[:]
}

//* How many spaces a line holds. The spaces are found by looking at
//* the bytes between the clusters of the glyphs: that is where a space
//* of the source text was swallowed. Zero is returned when the clusters
//* do not go forward, which is what right-to-left text looks like, and
//* such a line cannot be justified.
line_space_count :: proc(line: Text_Line) -> int {
	n := 0
	for gi in 0 ..< len(line.glyphs) - 1 {
		if line_has_space(line, gi) {n += 1}
	}
	return n
}

//* Whether the bytes between two glyphs hold a space.
line_has_space :: proc(line: Text_Line, gi: int) -> bool {
	if gi < 0 || gi + 1 >= len(line.glyphs) {return false}
	lo := int(line.glyphs[gi].cluster)
	hi := int(line.glyphs[gi + 1].cluster)
	if hi <= lo {return false}
	if lo < 0 {lo = 0}
	if hi > len(line.src) {hi = len(line.src)}
	for i in lo ..< hi {
		if line.src[i] == ' ' {return true}
	}
	return false
}
