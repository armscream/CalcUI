//* Text rendering: Runa does the shaping and the rasterization, the GUI
//* owns the glyph atlas and uploads its pages to the backend. A font file
//* is parsed once and shared by every size loaded from it, and the sizes
//* are logical.
package GUI

import "core:log"
import "core:os"
import virt "core:mem/virtual"
import runa "./dependencies/Runa"

ATLAS_SIZE :: 512

MAX_FONT_STACK :: 16

Font_ID :: distinct u32
INVALID_FONT_ID :: Font_ID(0)

Font_Family_ID :: distinct u32
INVALID_FONT_FAMILY_ID :: Font_Family_ID(0)

Font_File :: struct {
	name:  string,
	bytes: []u8,
	font:  runa.Font,
	atlas: runa.Atlas,
}

Glyph_Entry :: struct {
	px_size: [2]u16,
	bearing: [2]f32,
	uv:     [4]f32,
	region: Atlas_Region,
}

Font :: struct {
	id:   Font_ID,
	file: ^Font_File,
	family: Font_Family_ID,
	size: f32,
	px_size: f32,
	scale: f32,
	opts: runa.Paragraph_Opts,
	stack: []^runa.Font,
}

Font_Family :: struct {
	id:   Font_Family_ID,
	name: string,
	file: ^Font_File,
	fallback: Font_Family_ID,
}

Font_Instance_Key :: struct {
	file:   ^Font_File,
	size_q: u32,
}

Glyph_Key :: struct {
	font: ^runa.Font,
	gid:  runa.Glyph_ID,
	px_q: u32,
}

Font_Load :: proc(g: ^GUI, path: string, size: f32) -> Font_ID {
	family := Font_Family_Load(g, path)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return Font_At(g, family, size)
}

Font_Family_Load :: proc(g: ^GUI, path: string) -> Font_Family_ID {
	bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil {
		log.errorf("font: could not read %s: %v", path, read_err)
		return INVALID_FONT_FAMILY_ID
	}
	return Font_Family_Take(g, path, bytes)
}

Font_Family_Add :: proc(g: ^GUI, name: string, data: []u8) -> Font_Family_ID {
	bytes := make([]u8, len(data))
	copy(bytes, data)
	return Font_Family_Take(g, name, bytes)
}

Font_Family_Take :: proc(g: ^GUI, name: string, bytes: []u8) -> Font_Family_ID {
	file := font_file(g, name, bytes)
	if file == nil { return INVALID_FONT_FAMILY_ID }

	for fam in g.font_families {
		if fam.file == file { return fam.id }
	}

	fam := new(Font_Family)
	fam.id = Font_Family_ID(len(g.font_families) + 1)
	fam.name = name
	fam.file = file
	fam.fallback = INVALID_FONT_FAMILY_ID
	append(&g.font_families, fam)
	if g.default_family == INVALID_FONT_FAMILY_ID { g.default_family = fam.id }
	log.infof("font: family %s", name)
	return fam.id
}

font_family_get :: proc(g: ^GUI, id: Font_Family_ID) -> ^Font_Family {
	if id == INVALID_FONT_FAMILY_ID { return nil }
	idx := int(id) - 1
	if idx < 0 || idx >= len(g.font_families) { return nil }
	return g.font_families[idx]
}

//* The family of the GUI whose name is the one asked for, or nothing
//* when there is no family of that name. The name of a family is the
//* name it was given when it was added, and a family that was loaded
//* from a file has the path of the file as its name.
//
//* The family belongs to the GUI, and it is given back when the GUI is
//* shut down.
Font_Family_By_Name :: proc(g: ^GUI, name: string) -> Font_Family_ID {
	if g == nil { return INVALID_FONT_FAMILY_ID }
	for fam in g.font_families {
		if fam.name == name { return fam.id }
	}
	return INVALID_FONT_FAMILY_ID
}

Font_Family_Set_Fallback :: proc(g: ^GUI, family: Font_Family_ID, fallback: Font_Family_ID) -> bool {
	fam := font_family_get(g, family)
	if fam == nil { return false }
	if family == fallback { return false }
	fam.fallback = fallback
	font_invalidate(g)
	return true
}

Font_Has_Glyph :: proc(g: ^GUI, family: Font_Family_ID, codepoint: rune) -> bool {
	seen: [MAX_FONT_STACK]Font_Family_ID
	count := 0
	id := family
	for id != INVALID_FONT_FAMILY_ID && count < MAX_FONT_STACK {
		for i in 0 ..< count {
			if seen[i] == id { return false }
		}
		seen[count] = id
		count += 1
		fam := font_family_get(g, id)
		if fam == nil { return false }
		if runa.font_lookup_glyph(&fam.file.font, codepoint) != 0 { return true }
		id = fam.fallback
	}
	return false
}

Font_At :: proc(g: ^GUI, family: Font_Family_ID, size: f32) -> Font_ID {
	fam := font_family_get(g, family)
	if fam == nil { return INVALID_FONT_ID }

	q := quantise_size(size)
	key := Font_Instance_Key{file = fam.file, size_q = u32(q * 16)}
	if id, hit := g.font_instances[key]; hit { return id }

	f := new(Font)
	f.id = Font_ID(len(g.fonts) + 1)
	f.file = fam.file
	f.family = family
	f.size = q
	f.scale = g.scale
	f.px_size = q * g.scale
	f.opts = runa.Paragraph_Opts{
		size = f.px_size,
		align = .Start,
	}
	font_stack_build(g, f)

	append(&g.fonts, f)
	g.font_instances[key] = f.id
	if g.default_font == INVALID_FONT_ID { g.default_font = f.id }
	if g.default_font_size <= 0 { g.default_font_size = q }
	log.infof("font: %s at %.0fpx", fam.name, q)
	return f.id
}

quantise_size :: proc(size: f32) -> f32 {
	if size <= 0 { return 0 }
	q := int(size * 2 + 0.5)
	return f32(q) * 0.5
}

Font_Resolve :: proc(g: ^GUI, ts: Text_Style) -> Font_ID {
	family := ts.family
	size := ts.size
	if family == INVALID_FONT_FAMILY_ID { family = g.default_family }
	if size <= 0 { size = g.default_font_size }
	if family == INVALID_FONT_FAMILY_ID { return g.default_font }
	return Font_At(g, family, size)
}

font_stack_build :: proc(g: ^GUI, f: ^Font) {
	delete(f.stack)
	f.stack = nil
	f.opts.fonts = runa.Font_Stack(nil)

	seen: [MAX_FONT_STACK]Font_Family_ID
	count := 0
	id := f.family
	for id != INVALID_FONT_FAMILY_ID && count < MAX_FONT_STACK {
		repeat := false
		for i in 0 ..< count {
			if seen[i] == id { repeat = true }
		}
		if repeat { break }
		seen[count] = id
		count += 1
		fam := font_family_get(g, id)
		if fam == nil { break }
		id = fam.fallback
	}
	if count == 0 { return }

	stack := make([]^runa.Font, count)
	filled := 0
	for i in 0 ..< count {
		fam := font_family_get(g, seen[i])
		if fam == nil {break}
		stack[filled] = &fam.file.font
		filled += 1
	}
	f.stack = stack[:filled]
	f.opts.fonts = runa.Font_Stack(f.stack)
}

font_file :: proc(g: ^GUI, name: string, bytes: []u8) -> ^Font_File {
	for f in g.font_files {
		if f.name == name {
			delete(bytes)
			return f
		}
	}

	font, ferr := runa.font_load(bytes)
	if ferr != .None {
		log.errorf("font: could not parse %s: %v", name, ferr)
		delete(bytes)
		return nil
	}

	file := new(Font_File)
	file.name = name
	file.bytes = bytes
	file.font = font
	file.atlas = runa.atlas_make(ATLAS_SIZE, ATLAS_SIZE)

	append(&g.font_files, file)
	return file
}

font_get :: proc(g: ^GUI, id: Font_ID) -> ^Font {
	if id == INVALID_FONT_ID { return nil }
	idx := int(id) - 1
	if idx < 0 || idx >= len(g.fonts) { return nil }
	return g.fonts[idx]
}

font_destroy :: proc(g: ^GUI) {
	for f in g.fonts {
		delete(f.stack)
		free(cast(rawptr) f)
	}
	clear(&g.fonts)
	delete(g.fonts)
	delete(g.font_instances)

	for fam in g.font_families {
		free(cast(rawptr) fam)
	}
	clear(&g.font_families)
	delete(g.font_families)

	for file in g.font_files {
		runa.atlas_destroy(&file.atlas)
		runa.font_destroy(&file.font)
		delete(file.bytes)
		free(cast(rawptr) file)
	}
	clear(&g.font_files)
	delete(g.font_files)

	if g.glyphs != nil {
		clear(&g.glyphs)
		delete(g.glyphs)
	}

	if g.cache_ready {
		runa.cache_destroy(&g.shape_cache)
		g.cache_ready = false
	}
}

font_invalidate :: proc(g: ^GUI) {
	for _, entry in g.glyphs {
		atlas_free(g.atlas, entry.region)
	}
	if g.glyphs != nil { clear(&g.glyphs) }

	for file in g.font_files {
		runa.atlas_destroy(&file.atlas)
		file.atlas = runa.atlas_make(ATLAS_SIZE, ATLAS_SIZE)
	}

	for f in g.fonts {
		f.scale = g.scale
		f.px_size = f.size * g.scale
		f.opts.size = f.px_size
		font_stack_build(g, f)
	}

	measure_cache_clear(g)
}

font_layout :: proc(g: ^GUI, f: ^Font, str: string, opts: runa.Paragraph_Opts) -> []runa.Line {
	allocator := virt.arena_allocator(&g.frame_arena)
	lines, err := runa.layout_paragraph(str, opts, shape_cache(g), allocator)
	if err != .None { return nil }
	return lines
}

Font_Measure :: proc(g: ^GUI, id: Font_ID, text: string) -> Vec2 {
	f := font_get(g, id)
	if f == nil || text == "" { return {} }

	key := Measure_Key {
		font = id,
		size = f.size,
		text = text,
		width = 0,
		spacing = 0,
		wrap = .Off,
		transform = .None,
	}
	if size, ok := measure_cache_get(g, key); ok { return size }

	opts := f.opts
	opts.max_width = 0
	lines := font_layout(g, f, text, opts)
	if len(lines) == 0 { return {} }

	w: f32 = 0
	h: f32 = 0
	for line in lines {
		w = max(w, line.width)
		h += line.height
	}
	size := Vec2{w / f.scale, h / f.scale}
	measure_cache_put(g, key, size)
	return size
}

Font_Draw :: proc(g: ^GUI, id: Font_ID, text: string, rect: Rect, colour: Colour, align: Text_Align, wrap := false) {
	f := font_get(g, id)
	if f == nil || text == "" { return }

	opts := f.opts
	opts.max_width = wrap ? rect.w * f.scale : 0

	lines := font_layout(g, f, text, opts)
	if len(lines) == 0 { return }

	y := rect.y
	for line in lines {
		x := rect.x
		width := line.width / f.scale
		switch align {
		case .Center: x += (rect.w - width) * 0.5
		case .Right:  x += rect.w - width
		case .Left:
		case .Fill:
		}

		baseline := y + line.baseline / f.scale
		pen := x
		for pg in line.glyphs {
			slot, ok := font_slot(g, f, pg.font, pg.glyph_id)
			if ok && slot.px_size[0] > 0 && slot.px_size[1] > 0 {
				draw_quad(
					g.target,
					Rect{
						x = pen + (pg.x_offset + slot.bearing[0]) / f.scale,
						y = baseline + (pg.y_offset + slot.bearing[1]) / f.scale,
						w = f32(slot.px_size[0]) / f.scale,
						h = f32(slot.px_size[1]) / f.scale,
					},
					slot.uv,
					colour,
					g.atlas_texture,
				)
			}
			pen += pg.x_advance / f.scale
		}
		y += line.height / f.scale
	}
}

font_slot :: proc(g: ^GUI, f: ^Font, src: ^runa.Font, gid: runa.Glyph_ID) -> (Glyph_Entry, bool) {
	key := Glyph_Key{font = src, gid = gid, px_q = u32(f.px_size * 16)}
	if entry, hit := g.glyphs[key]; hit { return entry, true }

	slot, err := runa.raster_glyph(src, gid, f.px_size, 0, &f.file.atlas)
	if err != .None { return {}, false }

	entry := Glyph_Entry{
		px_size = slot.px_size,
		bearing = slot.bearing,
	}
	if slot.px_size[0] == 0 || slot.px_size[1] == 0 {
		g.glyphs[key] = entry
		return entry, true
	}
	if !font_place_glyph(g, f, &entry, slot) { return {}, false }
	g.glyphs[key] = entry
	return entry, true
}

font_place_glyph :: proc(g: ^GUI, f: ^Font, entry: ^Glyph_Entry, slot: runa.Atlas_Slot) -> bool {
	w := int(slot.px_size[0])
	h := int(slot.px_size[1])
	if w <= 0 || h <= 0 { return false }

	pages: ^[dynamic]runa.Atlas_Page = &f.file.atlas.pages_alpha
	if slot.is_color { pages = &f.file.atlas.pages_color }
	if int(slot.page_index) >= len(pages^) { return false }
	page := &pages^[int(slot.page_index)]

	x := int(slot.uv_rect[0] * f32(page.width) + 0.5)
	y := int(slot.uv_rect[1] * f32(page.height) + 0.5)
	if x < 0 { x = 0 }
	if y < 0 { y = 0 }
	if x + w > int(page.width) { return false }
	if y + h > int(page.height) { return false }

	region := atlas_alloc(g.atlas, w, h, true)
	if region.id < 0 { return false }

	if slot.is_color {
		rows := make([]u8, w * h * 4, context.allocator)
		defer delete(rows)
		for row in 0 ..< h {
			src := page.pixels[(y + row) * int(page.width) * 4 + x * 4:]
			copy(rows[row * w * 4:][:w * 4], src[:w * 4])
		}
		atlas_write(g.atlas, region, rows)
	} else {
		rows := make([]u8, w * h, context.allocator)
		defer delete(rows)
		for row in 0 ..< h {
			src := page.pixels[(y + row) * int(page.width) + x:]
			copy(rows[row * w:][:w], src[:w])
		}
		atlas_write_coverage(g.atlas, region, rows)
	}

	entry.uv = region.uv
	entry.region = region
	return true
}

Font_Warmup :: proc(g: ^GUI, id: Font_ID) {
	f := font_get(g, id)
	if f == nil { return }

	ascii: [95]u8
	for i in 0 ..< len(ascii) { ascii[i] = u8(0x20 + i) }
	text := string(ascii[:])

	lines := font_layout(g, f, text, f.opts)
	for line in lines {
		for pg in line.glyphs {
			_, _ = font_slot(g, f, pg.font, pg.glyph_id)
		}
	}
	atlas_flush(g.atlas, g.backend, g.atlas_texture)
}
