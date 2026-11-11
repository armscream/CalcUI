//* == Drawing text ==
//* The draw pass of a piece of text: the transform, the wrap, the
//* overrun, then the alignment, and last the shadow, the outline and
//* the ink.
//*
//* Everything in this file is in logical units. Runa lays the text out
//* in physical pixels, so every metric that comes from it is divided by
//* the scale of the font before it is used, and the width a text is
//* broken at is given to Runa in physical pixels.
//*
//* A line of text knows the range of the source it was made from:
//* `start` is the lowest cluster of the line and `end` is the start of
//* the next line, the length of the source for the last line, so that
//* `src[start:end]` is the text of the line in logical order, for
//* left-to-right text and for right-to-left text alike. Runa gives the
//* glyphs of a line in visual order, so the clusters of a
//* right-to-left line go backwards, and every cut of the text is made
//* by the cluster of a glyph and not by its place in the line.
//*
//* Everything that lives longer than a frame is in the font; every
//* allocation this file does is in the frame arena, which is emptied at
//* the start of every frame.

package GUI

import runa "./dependencies/Runa"
import virt "core:mem/virtual"
import "core:strings"
import "core:unicode"

TEXT_ELLIPSIS :: "…"

OUTLINE_DIRS :: [8][2]f32{{1, 0}, {0, 1}, {-1, 0}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

Glyph_Quad :: struct {
	rect: Rect,
	uv:   [4]f32,
	tex:  Texture_ID,
}

Text_Line :: struct {
	glyphs:   []runa.Paragraph_Glyph,
	width:    f32,
	height:   f32,
	baseline: f32,
	src:      string,
	start:    int,
	end:      int,
}

line_cluster :: struct {
	cluster: int,
	advance: f32,
}

draw_text :: proc(g: ^GUI, ts: Text_Style, text: string, rect: Rect, colour: Colour) {
	if text == "" {return}
	font_id := Font_Resolve(g, ts)
	if font_id == INVALID_FONT_ID {return}
	f := font_get(g, font_id)
	if f == nil {return}

	src := apply_text_transform(g, ts, text)

	lines := wrap_text_lines(g, f, ts, src, rect.w)
	if len(lines) == 0 {return}

	if ts.overrun != .None {
		cut_text_overrun(g, f, ts, &lines, rect)
	}

	quads := glyph_quads(g, f, lines[:], ts, rect)
	if len(quads) == 0 {return}

	if ts.clip {draw_push_clip(g.target, rect)}

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

	for q in quads {
		draw_quad(g.target, q.rect, q.uv, colour, q.tex)
	}

	if ts.clip {draw_pop_clip(g.target)}
}

text_measure :: proc(g: ^GUI, ts: Text_Style, text: string, width: f32) -> Vec2 {
	if text == "" {return {}}
	font_id := Font_Resolve(g, ts)
	if font_id == INVALID_FONT_ID {return {}}
	f := font_get(g, font_id)
	if f == nil {return {}}

	key := Measure_Key {
		font      = font_id,
		size      = ts.size,
		text      = text,
		width     = width,
		spacing   = ts.spacing,
		wrap      = ts.wrap,
		transform = ts.transform,
	}
	if ts.wrap == .Off && ts.spacing == 0 && ts.transform == .None {
		key = Measure_Key {
			font      = font_id,
			size      = f.size,
			text      = text,
			width     = 0,
			spacing   = 0,
			wrap      = .Off,
			transform = .None,
		}
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

wrap_text_lines :: proc(
	g: ^GUI,
	f: ^Font,
	ts: Text_Style,
	text: string,
	max_w: f32,
) -> [dynamic]Text_Line {
	opts := f.opts
	opts.max_width = 0
	out: [dynamic]Text_Line
	switch ts.wrap {
	case .Word:
		if max_w > 0 {opts.max_width = max_w * f.scale}
		out = shape_text_lines(g, f, text, text, 0, opts)
	case .Anywhere:
		out = wrap_text_anywhere(g, f, text, max_w)
	case .Off:
		out = shape_text_lines(g, f, text, text, 0, opts)
	}
	//* A text that ends with a line break has a line of its own below it:
	//* the caret at the end of the text belongs to that line.
	if len(text) > 0 && text[len(text) - 1] == '\n' &&
	   (len(out) == 0 || out[len(out) - 1].start < len(text)) {
		if cap(out) == 0 {
			out = make([dynamic]Text_Line, 0, 1, virt.arena_allocator(&g.frame_arena))
		}
		last := Text_Line{start = len(text), end = len(text), src = text}
		if len(out) > 0 {
			last.height = out[len(out) - 1].height
			last.baseline = out[len(out) - 1].baseline
		}
		append(&out, last)
	}
	return out
}

shape_text_lines :: proc(
	g: ^GUI,
	f: ^Font,
	str: string,
	src: string,
	base: int,
	opts: runa.Paragraph_Opts,
) -> [dynamic]Text_Line {
	allocator := virt.arena_allocator(&g.frame_arena)
	shaped, err := runa.layout_paragraph(str, opts, shape_cache(g), allocator)
	if err != .None {return nil}

	out := make([dynamic]Text_Line, 0, len(shaped), allocator)
	for l in shaped {
		start := base
		if len(l.glyphs) > 0 {start = base + lowest_cluster(l.glyphs)}
		append(
			&out,
			Text_Line {
				glyphs = l.glyphs,
				width = l.width / f.scale,
				height = l.height / f.scale,
				baseline = l.baseline / f.scale,
				src = src,
				start = start,
				end = base + len(str),
			},
		)
	}
	for i in 0 ..< len(out) {
		if i + 1 < len(out) {out[i].end = out[i + 1].start}
	}
	return out
}

lowest_cluster :: proc(glyphs: []runa.Paragraph_Glyph) -> int {
	lowest := 0
	for pg, gi in glyphs {
		c := int(pg.cluster)
		if gi == 0 || c < lowest {lowest = c}
	}
	return lowest
}

finalize_lines :: proc(lines: ^[dynamic]Text_Line, src_len: int) {
	for i in 0 ..< len(lines) {
		if i + 1 < len(lines) {
			lines[i].end = lines[i + 1].start
		} else {
			lines[i].end = src_len
		}
	}
}

wrap_text_anywhere :: proc(g: ^GUI, f: ^Font, text: string, max_w: f32) -> [dynamic]Text_Line {
	allocator := virt.arena_allocator(&g.frame_arena)
	out := make([dynamic]Text_Line, 0, 4, allocator)
	opts := f.opts
	opts.max_width = 0
	if max_w <= 0 || text == "" {
		for l in shape_text_lines(g, f, text, text, 0, opts) {append(&out, l)}
		return out
	}

	start := 0
	i := 0
	for i < len(text) {
		if text[i] == '\n' {
			end := i + 1
			wrap_text_piece(&out, g, f, text, start, end, max_w)
			start = end
			i = end
			continue
		}
		if text[i] == '\r' {
			end := i + 1
			if end < len(text) && text[end] == '\n' {end += 1}
			wrap_text_piece(&out, g, f, text, start, end, max_w)
			start = end
			i = end
			continue
		}
		i += 1
	}
	if start < len(text) {
		wrap_text_piece(&out, g, f, text, start, len(text), max_w)
	}
	finalize_lines(&out, len(text))
	return out
}

wrap_text_piece :: proc(
	out: ^[dynamic]Text_Line,
	g: ^GUI,
	f: ^Font,
	text: string,
	from: int,
	to: int,
	max_w: f32,
) {
	if to <= from {return}
	allocator := virt.arena_allocator(&g.frame_arena)

	opts := f.opts
	opts.max_width = 0
	piece := text[from:to]
	shaped, err := runa.layout_paragraph(piece, opts, shape_cache(g), allocator)
	if err != .None {return}

	glyphs: []runa.Paragraph_Glyph
	if len(shaped) > 0 {glyphs = shaped[0].glyphs}

	clusters := glyph_clusters(g, glyphs, f.scale)
	chunk := 0
	width: f32 = 0
	taken := 0
	ci := 0
	for ci < len(clusters) {
		c := clusters[ci]
		if taken > 0 && width + c.advance > max_w {
			rel := c.cluster
			for rel < len(piece) && piece[rel] == ' ' {rel += 1}
			append_text_chunk(out, g, f, text, from + chunk, from + rel, opts)
			chunk = rel
			width = 0
			taken = 0
			for ci < len(clusters) && clusters[ci].cluster < rel {ci += 1}
			continue
		}
		width += c.advance
		taken += 1
		ci += 1
	}
	append_text_chunk(out, g, f, text, from + chunk, to, opts)
}

append_text_chunk :: proc(
	out: ^[dynamic]Text_Line,
	g: ^GUI,
	f: ^Font,
	text: string,
	from: int,
	to: int,
	opts: runa.Paragraph_Opts,
) {
	if to <= from {return}
	for l in shape_text_lines(g, f, text[from:to], text, from, opts) {
		append(out, l)
	}
}

text_block_height :: proc(lines: []Text_Line, spacing: f32) -> f32 {
	if len(lines) == 0 {return 0}
	h: f32 = 0
	for i in 0 ..< len(lines) {
		h += lines[i].height
		if i < len(lines) - 1 {h += spacing}
	}
	return h
}

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

	budget := box.w - Font_Measure(g, f.id, TEXT_ELLIPSIS).x
	if last.width <= budget {return}

	clusters := glyph_clusters(g, last.glyphs, f.scale)
	i := cluster_fit(clusters, budget)
	if i >= len(clusters) {return}

	src := last.src
	cut := clusters[i].cluster
	if cut > len(src) {cut = len(src)}
	if cut <= last.start {return}

	if ts.overrun == .Words {
		if p := last_space_before(src, last.start, cut); p > last.start {cut = p}
	}
	for cut > last.start && src[cut - 1] == ' ' {cut -= 1}
	if cut <= last.start {return}

	opts := f.opts
	opts.max_width = 0
	trimmed := join_text(g, src[last.start:cut], TEXT_ELLIPSIS)
	cut_lines := shape_text_lines(g, f, trimmed, trimmed, 0, opts)
	if len(cut_lines) == 0 {return}

	resize(lines, len(lines) - 1)
	if len(lines) > 0 {lines[len(lines) - 1].end = last.start}
	for l in cut_lines {append(lines, l)}
}

last_space_before :: proc(src: string, from, to: int) -> int {
	end := min(to, len(src))
	for i := end - 1; i >= from; i -= 1 {
		if src[i] == ' ' {return i}
	}
	return -1
}

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

glyph_clusters :: proc(g: ^GUI, glyphs: []runa.Paragraph_Glyph, scale: f32) -> []line_cluster {
	allocator := virt.arena_allocator(&g.frame_arena)
	pairs := make([dynamic]line_cluster, 0, len(glyphs), allocator)
	for pg in glyphs {
		append(&pairs, line_cluster{cluster = int(pg.cluster), advance = pg.x_advance / scale})
	}
	sort_line_clusters(pairs[:])

	out := make([dynamic]line_cluster, 0, len(pairs), allocator)
	for p in pairs {
		if len(out) > 0 && out[len(out) - 1].cluster == p.cluster {
			out[len(out) - 1].advance += p.advance
			continue
		}
		append(&out, p)
	}
	return out[:]
}

sort_line_clusters :: proc(clusters: []line_cluster) {
	for i in 1 ..< len(clusters) {
		c := clusters[i]
		j := i - 1
		for j >= 0 && clusters[j].cluster > c.cluster {
			clusters[j + 1] = clusters[j]
			j -= 1
		}
		clusters[j + 1] = c
	}
}

cluster_fit :: proc(clusters: []line_cluster, budget: f32) -> int {
	width: f32 = 0
	for c, i in clusters {
		if i > 0 && width + c.advance > budget {return i}
		width += c.advance
	}
	return len(clusters)
}

glyph_quads :: proc(
	g: ^GUI,
	f: ^Font,
	lines: []Text_Line,
	ts: Text_Style,
	rect: Rect,
) -> []Glyph_Quad {
	quads := make([dynamic]Glyph_Quad, 0, 64, virt.arena_allocator(&g.frame_arena))

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

		extra: f32 = 0
		if ts.align == .Fill && li < len(lines) - 1 {
			if spaces := line_space_count(line); spaces > 0 {
				extra = (rect.w - line.width) / f32(spaces)
			}
		}

		baseline := (y + line.baseline) * f.scale
		pen := x * f.scale
		for gi in 0 ..< len(line.glyphs) {
			pg := line.glyphs[gi]
			if gi > 0 && extra != 0 && line_has_space(line, gi - 1) {
				pen += extra * f.scale
			}
			quad, uv, ok := font_glyph_place(g, f, pg, pen, baseline)
			if ok {
				append(
					&quads,
					Glyph_Quad {
						rect = quad,
						uv = uv,
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

line_space_count :: proc(line: Text_Line) -> int {
	if !line_goes_forward(line) {return 0}
	n := 0
	for gi in 0 ..< len(line.glyphs) - 1 {
		if line_has_space(line, gi) {n += 1}
	}
	return n
}

line_goes_forward :: proc(line: Text_Line) -> bool {
	for gi in 1 ..< len(line.glyphs) {
		if int(line.glyphs[gi].cluster) < int(line.glyphs[gi - 1].cluster) {return false}
	}
	return true
}

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
