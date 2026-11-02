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
	//* keyed on, so two sizes of one file share an atlas.
	name:  string,
	bytes: []u8,
	font:  runa.Font,

	//* The shaping options hold a pointer to our own font, so the stack
	//* has to live inside the file (it is heap allocated, so it is stable).
	stack: [1]^runa.Font,
	opts:  runa.Paragraph_Opts,

	//* The atlas is shared by every size of this file. A glyph slot is
	//* keyed by (glyph, size) because the same glyph rasterized at two
	//* sizes is two different bitmaps.
	atlas:  runa.Atlas,
	pages:  [dynamic]Texture_ID,
	glyphs: map[Glyph_Key]runa.Atlas_Slot,
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
font_load :: proc(g: ^GUI, path: string, size: f32) -> Font_ID {
	family := font_family_load(g, path)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return font_at(g, family, size)
}

//* Loads a font that is already in memory, for a font that is compiled
//* into the program instead of read from disk. The bytes are copied, so
//* the caller keeps ownership of them.
font_load_bytes :: proc(g: ^GUI, name: string, data: []u8, size: f32) -> Font_ID {
	family := font_family_add(g, name, data)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return font_at(g, family, size)
}

//* Adds a font file to the GUI and returns the instance for that
//* (file, size) pair. The file takes ownership of the bytes: the parser
//* points into them, so they have to live as long as it does.
font_add :: proc(g: ^GUI, name: string, bytes: []u8, size: f32) -> Font_ID {
	family := font_family_take(g, name, bytes)
	if family == INVALID_FONT_FAMILY_ID { return INVALID_FONT_ID }
	return font_at(g, family, size)
}

//* == Families ==

//* Loads a font file from disk and registers it as a family. The family
//* is the typeface: the size belongs to the widget that uses it.
font_family_load :: proc(g: ^GUI, path: string) -> Font_Family_ID {
	bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil {
		log.errorf("font: could not read %s: %v", path, read_err)
		return INVALID_FONT_FAMILY_ID
	}
	//* The file takes ownership of the bytes from here on.
	return font_family_take(g, path, bytes)
}

//* Registers a font that is already in memory as a family. The bytes
//* are copied, so the caller keeps ownership of them.
font_family_add :: proc(g: ^GUI, name: string, data: []u8) -> Font_Family_ID {
	bytes := make([]u8, len(data))
	copy(bytes, data)
	return font_family_take(g, name, bytes)
}

//* Registers a font file as a family. The file takes ownership of the
//* bytes: the parser points into them, so they have to live as long as
//* it does.
font_family_take :: proc(g: ^GUI, name: string, bytes: []u8) -> Font_Family_ID {
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
font_at :: proc(g: ^GUI, family: Font_Family_ID, size: f32) -> Font_ID {
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
font_resolve :: proc(g: ^GUI, ts: Text_Style) -> Font_ID {
	family := ts.family
	size := ts.size
	if family == INVALID_FONT_FAMILY_ID { family = g.default_family }
	if size <= 0 { size = g.default_font_size }
	if family == INVALID_FONT_FAMILY_ID { return g.default_font }
	return font_at(g, family, size)
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
	file.glyphs = make(map[Glyph_Key]runa.Atlas_Slot)

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
		delete(file.pages)
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
font_measure :: proc(g: ^GUI, id: Font_ID, text: string) -> Vec2 {
	f := font_get(g, id)
	if f == nil || text == "" { return {} }
	w, h := runa.measure_text(text, f.opts)
	return Vec2{w, h}
}

//* Draws `text` inside `rect`. `align` positions the line horizontally;
//* the text is laid out from the top of the rect downwards.
font_draw :: proc(g: ^GUI, id: Font_ID, text: string, rect: Rect, colour: Colour, align: Text_Align, wrap := false) {
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
			if ok {
				draw_quad(
					g.target,
					Rect{
						x = pen + pg.x_offset + slot.bearing[0],
						y = baseline + pg.y_offset + slot.bearing[1],
						w = f32(slot.px_size[0]),
						h = f32(slot.px_size[1]),
					},
					slot.uv_rect,
					colour,
					f.file.pages[slot.page_index],
				)
			}
			pen += pg.x_advance
		}
		y += line.height
	}
}

//* Returns the atlas slot for a glyph at the instance's size,
//* rasterizing it on first use.
font_slot :: proc(g: ^GUI, f: ^Font, gid: runa.Glyph_ID) -> (runa.Atlas_Slot, bool) {
	key := Glyph_Key{gid = gid, size_q = u16(f.size * 16)}
	if slot, hit := f.file.glyphs[key]; hit { return slot, true }

	slot, err := runa.raster_glyph(&f.file.font, gid, f.size, 0, &f.file.atlas)
	if err != .None { return {}, false }

	f.file.glyphs[key] = slot
	font_ensure_page(g, f.file, slot.page_index)
	return slot, true
}

//* Makes sure a texture exists for an atlas page.
font_ensure_page :: proc(g: ^GUI, file: ^Font_File, page_index: u16) {
	for len(file.pages) <= int(page_index) {
		append(&file.pages, INVALID_TEXTURE_ID)
	}
	if file.pages[page_index] == INVALID_TEXTURE_ID {
		file.pages[page_index] = alloc_texture(g)
	}
}

//* Uploads every dirty atlas page to the backend. Called once per frame
//* after the draw list is built, so a glyph rasterized this frame is
//* uploaded before the frame is submitted.
font_flush :: proc(g: ^GUI) {
	for file in g.font_files {
		for &page, i in file.atlas.pages_alpha {
			if page.is_dirty { font_upload_page(g, file, u16(i), &page, false) }
		}
		for &page, i in file.atlas.pages_color {
			if page.is_dirty { font_upload_page(g, file, u16(i), &page, true) }
		}
	}
}

//* Expands the alpha coverage of an atlas page into RGBA and uploads it.
//* One texture format then covers both solid quads and glyphs: the RGB
//* is white and the alpha is the coverage, so the vertex colour tints
//* the ink.
font_upload_page :: proc(g: ^GUI, file: ^Font_File, page_index: u16, page: ^runa.Atlas_Page, is_color: bool) {
	font_ensure_page(g, file, page_index)
	tex := file.pages[page_index]

	w := int(page.width)
	h := int(page.height)
	pixels := w * h * 4
	if len(g.upload_buf) < pixels {
		g.upload_buf = make([]u8, pixels)
	}
	buf := g.upload_buf[:pixels]

	if is_color {
		copy(buf, page.pixels[:pixels])
	} else {
		for i in 0 ..< w * h {
			buf[i * 4 + 0] = 255
			buf[i * 4 + 1] = 255
			buf[i * 4 + 2] = 255
			buf[i * 4 + 3] = page.pixels[i]
		}
	}

	g.backend.upload_texture(g.backend.ctx, tex, buf, i32(w), i32(h))
	page.is_dirty = false
}

//* Pre-rasterizes printable ASCII at a size so the first frame of a
//* screen does not stall on cold glyphs.
font_warmup :: proc(g: ^GUI, id: Font_ID) {
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
	font_flush(g)
}
