//* Text rendering.
//
//* Runa does the shaping (GSUB/GPOS, bidi, line breaking) and the
//* rasterization; the GUI owns the glyph atlas and uploads its pages to
//* the backend as textures. Nothing here knows about SDL — the backend
//* only ever sees a Texture_ID and a quad.
//
//* A *font file* is parsed once and shared by every size loaded from it:
//* the glyph atlas lives on the file, so a 12px and a 32px instance of
//* the same typeface share their pages. A *font instance* is a
//* (file, size) pair — that is what a widget references.
package GUI

import "core:log"
import "core:os"
import virt "core:mem/virtual"
import runa "./dependencies/Runa"

//* One atlas page holds the glyphs of one font file.
ATLAS_SIZE :: 512

Font_ID :: distinct u32
INVALID_FONT_ID :: Font_ID(0)

//* A family is a typeface: one parsed file, any number of sizes. The
//* size belongs to the widget that uses the family, so one family
//* serves every size.
Font_Family_ID :: distinct u32
INVALID_FONT_FAMILY_ID :: Font_Family_ID(0)

//* A parsed font file. Shared by all of its size instances.
Font_File :: struct {
	//* The name the file was loaded under. It is what the cache is
	//* keyed on, so two sizes of one file share their atlas.
	name:  string,
	bytes: []u8,
	font:  runa.Font,

	//* The shaping options hold a pointer to our own font, so the stack
	//* has to live inside the file (it is heap allocated, so it is stable).
	stack: [1]^runa.Font,
	opts:  runa.Paragraph_Opts,

	//* Runa's own atlas: the rasterizer puts the glyphs here first.
	//* Every glyph is then copied into the UI atlas, so that the whole
	//* UI is drawn out of one texture.
	atlas: runa.Atlas,
	//* The glyph cache. A glyph slot is keyed by (glyph, size) because
	//* the same glyph rasterized at two sizes is two different bitmaps.
	glyphs: map[Glyph_Key]Glyph_Entry,
}

//* A glyph that lives in the UI atlas: where it is, how big it is and
//* where its bitmap is.
Glyph_Entry :: struct {
	px_size: [2]u16,
	bearing: [2]f32,
	//* The place of the bitmap in the UI atlas.
	uv:     [4]f32,
	region: Atlas_Region,
}


//* A (file, size) pair. This is what the draw pass uses.
Font :: struct {
	id:   Font_ID,
	file: ^Font_File,
	size: f32,
	opts: runa.Paragraph_Opts,
}

//* A typeface: the parsed file, under a name a widget can point at.
Font_Family :: struct {
	id:   Font_Family_ID,
	name: string,
	file: ^Font_File,
}

//* The key of the instance cache: a file at a size.
Font_Instance_Key :: struct {
	file:   ^Font_File,
	size_q: u16,
}

//* Glyph cache key. The size is quantised to 1/16 px so that 12.0 and
//* 12.0001 share a slot.
Glyph_Key :: struct {
	gid:    runa.Glyph_ID,
	size_q: u16,
}

//* Loads a font file at `size` pixels and returns the instance for that
//* (file, size) pair. The file is parsed once; asking for another size
//* of the same file reuses it and its atlas.
Font_Load :: proc(g: ^GUI, path: string, size: f32) -> Font_ID {
	family := Font_Family_Load(g, path)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return Font_At(g, family, size)
}

//* Loads a font that is already in memory, for a font that is compiled
//* into the program instead of read from disk. The bytes are copied, so
//* the caller keeps ownership of them.
font_load_bytes :: proc(g: ^GUI, name: string, data: []u8, size: f32) -> Font_ID {
	family := Font_Family_Add(g, name, data)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return Font_At(g, family, size)
}

//* Adds a font file to the GUI and returns the instance for that
//* (file, size) pair. The file takes ownership of the bytes: the parser
//* points into them, so they have to live as long as it does.
font_add :: proc(g: ^GUI, name: string, bytes: []u8, size: f32) -> Font_ID {
	family := Font_Family_Take(g, name, bytes)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return Font_At(g, family, size)
}

//* == Families ==

//* Loads a font file from disk and registers it as a family. The family
//* is the typeface: the size belongs to the widget that uses it.
Font_Family_Load :: proc(g: ^GUI, path: string) -> Font_Family_ID {
	bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil {
		log.errorf("font: could not read %s: %v", path, read_err)
		return INVALID_FONT_FAMILY_ID
	}
	//* The file takes ownership of the bytes from here on.
	return Font_Family_Take(g, path, bytes)
}

//* Registers a font that is already in memory as a family. The bytes
//* are copied, so the caller keeps ownership of them.
Font_Family_Add :: proc(g: ^GUI, name: string, data: []u8) -> Font_Family_ID {
	bytes := make([]u8, len(data))
	copy(bytes, data)
	return Font_Family_Take(g, name, bytes)
}

//* Registers a font file as a family. The file takes ownership of the
//* bytes: the parser points into them, so they have to live as long as
//* it does.
Font_Family_Take :: proc(g: ^GUI, name: string, bytes: []u8) -> Font_Family_ID {
	file := font_file(g, name, bytes)
	if file == nil { return INVALID_FONT_FAMILY_ID }

	//* The file is a family already: it was registered before.
	for fam in g.font_families {
		if fam.file == file { return fam.id }
	}

	fam := new(Font_Family)
	fam.id = Font_Family_ID(len(g.font_families) + 1)
	fam.name = name
	fam.file = file
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

//* == Instances ==

//* The instance of a family at a size. The instance is made on first
//* use and kept after that, so a size that changes at runtime is a
//* lookup and not a new font.
Font_At :: proc(g: ^GUI, family: Font_Family_ID, size: f32) -> Font_ID {
	fam := font_family_get(g, family)
	if fam == nil { return INVALID_FONT_ID }

	q := quantise_size(size)
	key := Font_Instance_Key{file = fam.file, size_q = u16(q * 16)}
	if id, hit := g.font_instances[key]; hit { return id }

	f := new(Font)
	f.id = Font_ID(len(g.fonts) + 1)
	f.file = fam.file
	f.size = q
	f.opts = fam.file.opts
	f.opts.size = q

	append(&g.fonts, f)
	g.font_instances[key] = f.id
	if g.default_font == INVALID_FONT_ID { g.default_font = f.id }
	if g.default_font_size <= 0 { g.default_font_size = q }
	log.infof("font: %s at %.0fpx", fam.name, q)
	return f.id
}

//* The size is rounded to a half pixel, so a size that changes every
//* frame does not make a new atlas page every frame.
quantise_size :: proc(size: f32) -> f32 {
	if size <= 0 { return 0 }
	q := int(size * 2 + 0.5)
	return f32(q) * 0.5
}

//* The font a piece of text is drawn with: the family at the size the
//* style asks for. The size falls back to the GUI's own. A widget that
//* takes the theme gets the theme's typeface and size through its
//* resolved style.
Font_Resolve :: proc(g: ^GUI, ts: Text_Style) -> Font_ID {
	family := ts.family
	size := ts.size
	if family == INVALID_FONT_FAMILY_ID { family = g.default_family }
	if size <= 0 { size = g.default_font_size }
	if family == INVALID_FONT_FAMILY_ID { return g.default_font }
	return Font_At(g, family, size)
}

//* Returns the parsed file for a name, parsing it on first use. The
//* file takes ownership of the bytes.
font_file :: proc(g: ^GUI, name: string, bytes: []u8) -> ^Font_File {
	for f in g.font_files {
		if f.name == name {
			//* The file was parsed already: these bytes are not needed.
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
	file.stack[0] = &file.font
	file.opts = runa.Paragraph_Opts{
		fonts = runa.Font_Stack(file.stack[:]),
		align = .Start,
	}
	file.atlas = runa.atlas_make(ATLAS_SIZE, ATLAS_SIZE)
	file.glyphs = make(map[Glyph_Key]Glyph_Entry)

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
		delete(file.glyphs)
		runa.atlas_destroy(&file.atlas)
		runa.font_destroy(&file.font)
		delete(file.bytes)
		free(cast(rawptr) file)
	}
	clear(&g.font_files)
	delete(g.font_files)

	if g.cache_ready {
		runa.cache_destroy(&g.shape_cache)
		g.cache_ready = false
	}
}

//* Measures `text` in the font's pixel space.
Font_Measure :: proc(g: ^GUI, id: Font_ID, text: string) -> Vec2 {
	f := font_get(g, id)
	if f == nil || text == "" { return {} }
	w, h := runa.measure_text(text, f.opts)
	return Vec2{w, h}
}

//* Draws `text` inside `rect`. `align` positions the line horizontally;
//* the text is laid out from the top of the rect downwards.
Font_Draw :: proc(g: ^GUI, id: Font_ID, text: string, rect: Rect, colour: Colour, align: Text_Align, wrap := false) {
	f := font_get(g, id)
	if f == nil || text == "" { return }

	opts := f.opts
	opts.max_width = wrap ? rect.w : 0

	lines, err := runa.layout_paragraph(text, opts, shape_cache(g), virt.arena_allocator(&g.frame_arena))
	if err != .None { return }

	y := rect.y
	for line in lines {
		x := rect.x
		switch align {
		case .Center: x += (rect.w - line.width) * 0.5
		case .Right:  x += rect.w - line.width
		case .Left:
		case .Fill:
			//* Justified text is spread out by the text pipeline; the
			//* lines themselves start at the left edge.
		}

		baseline := y + line.baseline
		pen := x
		for pg in line.glyphs {
			slot, ok := font_slot(g, f, pg.glyph_id)
			if ok && slot.px_size[0] > 0 && slot.px_size[1] > 0 {
				draw_quad(
					g.target,
					Rect{
						x = pen + pg.x_offset + slot.bearing[0],
						y = baseline + pg.y_offset + slot.bearing[1],
						w = f32(slot.px_size[0]),
						h = f32(slot.px_size[1]),
					},
					slot.uv,
					colour,
					g.atlas_texture,
				)
			}
			pen += pg.x_advance
		}
		y += line.height
	}
}

//* Returns the glyph of a file at the instance's size, rasterizing it
//* on first use. The bitmap is copied into the UI atlas, so that the
//* whole UI comes out of one texture.
font_slot :: proc(g: ^GUI, f: ^Font, gid: runa.Glyph_ID) -> (Glyph_Entry, bool) {
	key := Glyph_Key{gid = gid, size_q = u16(f.size * 16)}
	if entry, hit := f.file.glyphs[key]; hit { return entry, true }

	slot, err := runa.raster_glyph(&f.file.font, gid, f.size, 0, &f.file.atlas)
	if err != .None { return {}, false }

	entry := Glyph_Entry{
		px_size = slot.px_size,
		bearing = slot.bearing,
	}
	f.file.glyphs[key] = entry
	if !font_place_glyph(g, f, &entry, slot) { return {}, false }
	f.file.glyphs[key] = entry
	return entry, true
}

//* Copies the bitmap of a rasterized glyph into the UI atlas.
font_place_glyph :: proc(g: ^GUI, f: ^Font, entry: ^Glyph_Entry, slot: runa.Atlas_Slot) -> bool {
	w := int(slot.px_size[0])
	h := int(slot.px_size[1])
	if w <= 0 || h <= 0 { return false }

	pages: ^[dynamic]runa.Atlas_Page = &f.file.atlas.pages_alpha
	if slot.is_color { pages = &f.file.atlas.pages_color }
	if int(slot.page_index) >= len(pages^) { return false }
	page := &pages^[int(slot.page_index)]

	//* Where the bitmap sits in the page.
	x := int(slot.uv_rect[0] * f32(page.width) + 0.5)
	y := int(slot.uv_rect[1] * f32(page.height) + 0.5)
	if x < 0 { x = 0 }
	if y < 0 { y = 0 }
	if x + w > int(page.width) { return false }
	if y + h > int(page.height) { return false }

	region := atlas_alloc(g.atlas, w, h, true)
	if region.id < 0 { return false }

	if slot.is_color {
		//* The page holds RGBA already.
		rows := make([]u8, w * h * 4, context.allocator)
		defer delete(rows)
		for row in 0 ..< h {
			src := page.pixels[(y + row) * int(page.width) * 4 + x * 4:]
			copy(rows[row * w * 4:][:w * 4], src[:w * 4])
		}
		atlas_write(g.atlas, region, rows)
	} else {
		//* The page holds the coverage on its own: it is expanded into
		//* white and the coverage, so the colour of the quad tints it.
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

//* Pre-rasterizes printable ASCII at a size so the first frame of a
//* screen does not stall on cold glyphs.
Font_Warmup :: proc(g: ^GUI, id: Font_ID) {
	f := font_get(g, id)
	if f == nil { return }

	ascii: [95]u8
	for i in 0 ..< len(ascii) { ascii[i] = u8(0x20 + i) }
	text := string(ascii[:])

	lines, err := runa.layout_paragraph(text, f.opts, shape_cache(g), virt.arena_allocator(&g.frame_arena))
	if err != .None { return }
	for line in lines {
		for pg in line.glyphs {
			_, _ = font_slot(g, f, pg.glyph_id)
		}
	}
	atlas_flush(g.atlas, g.backend, g.atlas_texture)
}
