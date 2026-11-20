package Core
//* == UI atlas ==
//* The atlas owns a copy of the pixels. A change is written into that
//* copy and only the region that changed is uploaded, so a glyph that
//* is rasterized does not cost a whole page upload.
//
//* The atlas is made of pages. A page is a fixed-size RGBA texture with
//* its own shelves, allocations and dirty regions. The first page uses
//* the size the GUI was made with; a request that does not fit any page
//* makes another one, so retained draw lists keep their valid UVs.
//
//* The shelves are stacked from the top of a page downwards, and a new
//* region goes on the first shelf that is tall enough and has room left.
//* A region that is not pinned can be thrown out when room is needed; a
//* region that a retained draw list names stays until the next build.
ATLAS_DEFAULT_SIZE :: 1024
ATLAS_WHITE_SIZE :: 4

Atlas_Options :: struct {
	page_size: int,
	max_pages: int,
}

Atlas_Region :: struct { // Id -1 when region not valid
	id:   int,
	gen:  u32,
	page: u16,
	x, y, w, h: int,
	uv:   [4]f32, // u0, v0, u1, v1
}

//* A block of a shelf that was given back and can be used again.
Atlas_Block :: struct {
	x, y, w, h: int,
}

//* A shelf: a horizontal band of a page. The blocks that were freed
//* inside it are kept, so the space can be used again.
Atlas_Shelf :: struct {
	y:      int,
	height: int,
	cursor: int, // the first x that is not used yet
	free:   [dynamic]Atlas_Block,
}

//* A part of a page that is waiting to go up, held in the staging
//* buffer while the page keeps no CPU mirror.
Atlas_Staged :: struct {
	offset: int,
	size:   int,
	x, y, w, h: int,
}

//* The pixels are the CPU mirror that a change is written into before
//* gpu upload. A backend that can upload regions drops the mirror after
//* the first full upload and stages the changes instead.
Atlas_Page :: struct {
	width, height: int,
	pixels:  []u8,
	shelves: [dynamic]Atlas_Shelf,
	//* The parts that changed and are waiting to go up.
	dirty:   [dynamic]Atlas_Region,
	uploads: [dynamic]Texture_Upload,
	scratch: []u8,
	stage:   [dynamic]u8,
	staged:  [dynamic]Atlas_Staged,
	//* Whether the whole page was already uploaded. The first upload
	//* makes the texture; the ones after it are regions of it.
	uploaded: bool,
}

Atlas_Alloc :: struct {
	region: Atlas_Region,
	pinned: bool,
	used:   u64, // the frame the region was last used in
	freed:  bool,
	gen:    u32,
}

UI_Atlas :: struct {
	page_w, page_h: int,
	max_pages: int,
	pages:  [dynamic]Atlas_Page,
	allocs: [dynamic]Atlas_Alloc,
	free_slots: [dynamic]int,
	frame:   u64,
	retained_frame: u64,
	white:   Atlas_Region,
	white_uv: [4]f32,
	//* How many times an allocation could not be served.
	exhausted: int,
}

atlas_page_make :: proc(width, height: int) -> Atlas_Page {
	p := Atlas_Page{width = width, height = height}
	p.pixels = make([]u8, width * height * 4)
	return p
}

//* Makes an atlas whose first page is `width` x `height` pixels. The
//* white texel is reserved at the top left. `max_pages` of zero is unlimited.
atlas_make :: proc(width, height: int, max_pages := 0) -> ^UI_Atlas {
	a := new(UI_Atlas)
	a.page_w = width
	a.page_h = height
	a.max_pages = max_pages
	append(&a.pages, atlas_page_make(width, height))

	first := &a.pages[0]
	for y in 0 ..< ATLAS_WHITE_SIZE {
		for x in 0 ..< ATLAS_WHITE_SIZE {
			at := (y * width + x) * 4
			first.pixels[at + 0] = 255
			first.pixels[at + 1] = 255
			first.pixels[at + 2] = 255
			first.pixels[at + 3] = 255
		}
	}

	a.white = atlas_alloc(a, ATLAS_WHITE_SIZE, ATLAS_WHITE_SIZE, true)
	//* The middle of the block: the filter never leaves it.
	a.white_uv = [4]f32{
		f32(a.white.x) + 2.5 / f32(width),
		f32(a.white.y) + 2.5 / f32(height),
		f32(a.white.x) + 2.5 / f32(width),
		f32(a.white.y) + 2.5 / f32(height),
	}
	return a
}

atlas_destroy :: proc(a: ^UI_Atlas) {
	if a == nil { return }
	for &p in a.pages { atlas_page_destroy(&p) }
	delete(a.pages)
	delete(a.allocs)
	delete(a.free_slots)
	free(cast(rawptr) a)
}

atlas_page_destroy :: proc(p: ^Atlas_Page) {
	delete(p.pixels)
	for &s in p.shelves { delete(s.free) }
	delete(p.shelves)
	delete(p.dirty)
	delete(p.uploads)
	delete(p.scratch)
	delete(p.stage)
	delete(p.staged)
	p^ = {}
}

atlas_page_count :: proc(a: ^UI_Atlas) -> int {
	if a == nil { return 0 }
	return len(a.pages)
}

//* Whether a page holds no live region, so it can be given back.
atlas_page_is_empty :: proc(a: ^UI_Atlas, page: int) -> bool {
	for &alloc in a.allocs {
		if alloc.freed { continue }
		if int(alloc.region.page) == page { return false }
	}
	return true
}

//* Gives back the pages at the end that hold no live region, and the
//* staging and gather buffers that are not waiting to go up. The pages
//* that stay keep their index, so their textures and retained UVs stay
//* valid.
atlas_trim :: proc(a: ^UI_Atlas, backend: Backend) {
	if a == nil { return }

	for i := len(a.pages) - 1; i > 0; i -= 1 {
		if !atlas_page_is_empty(a, i) { break }
		p := &a.pages[i]
		if p.uploaded && backend.destroy_texture != nil {
			backend.destroy_texture(backend.ctx, atlas_texture_of_page(i))
		}
		atlas_page_destroy(p)
		_ = pop(&a.pages)
	}

	for &p in a.pages {
		if len(p.staged) == 0 {
			delete(p.stage)
			p.stage = nil
		}
		if len(p.dirty) == 0 {
			delete(p.scratch)
			p.scratch = nil
		}
	}
}

//* The texture of a page. The first page keeps ATLAS_TEXTURE_ID, so the
//* white texel and every region on it stay where they were.
atlas_texture_of_page :: proc(page: int) -> Texture_ID {
	return Texture_ID(u32(ATLAS_TEXTURE_ID) + u32(page))
}

atlas_texture_for :: proc(region: Atlas_Region) -> Texture_ID {
	if region.id < 0 { return ATLAS_TEXTURE_ID }
	return atlas_texture_of_page(int(region.page))
}

atlas_page :: proc(a: ^UI_Atlas, index: int) -> ^Atlas_Page {
	if a == nil || index < 0 || index >= len(a.pages) { return nil }
	return &a.pages[index]
}

//* Hands out a region of `w` x `h` pixels. A pinned region is never
//* thrown out; an unpinned one is the first to go when the pages are
//* full. A new page is made when none of the existing ones has room and
//* the limit allows it. The region is invalid when there is no room.
atlas_alloc :: proc(a: ^UI_Atlas, w, h: int, pinned: bool) -> Atlas_Region {
	if w <= 0 || h <= 0 { return Atlas_Region{id = -1} }

	//* Try again after throwing something out: the space that is freed
	//* is the space that is used. Only a region that can hold the
	//* request is worth throwing out; the other regions still name
	//* space that the retained draw lists may use.
	for {
		if region, ok := atlas_alloc_raw(a, w, h); ok {
			return atlas_commit(a, region, w, h, pinned)
		}
		if !atlas_evict_for(a, w, h) { break }
	}

	if a.max_pages == 0 || len(a.pages) < a.max_pages {
		page_w := a.page_w
		page_h := a.page_h
		if w > page_w { page_w = atlas_size_for(w) }
		if h > page_h { page_h = atlas_size_for(h) }
		append(&a.pages, atlas_page_make(page_w, page_h))
		index := len(a.pages) - 1
		if region, ok := atlas_alloc_raw_page(&a.pages[index], u16(index), w, h); ok {
			return atlas_commit(a, region, w, h, pinned)
		}
	}

	a.exhausted += 1
	return Atlas_Region{id = -1}
}

//* The smallest power of two that holds `need`, so an image that is
//* larger than a page still gets a page of its own.
atlas_size_for :: proc(need: int) -> int {
	size := 1
	for size < need { size *= 2 }
	return size
}

//* Puts the region in a slot and gives it its generation. A slot that
//* was given back is used again, so the table of the allocations does not grow for ever.
atlas_commit :: proc(
	a: ^UI_Atlas,
	region: Atlas_Region,
	w, h: int,
	pinned: bool,
) -> Atlas_Region {
	out := region
	out.w = w
	out.h = h
	gen: u32 = 1
	slot := -1
	if len(a.free_slots) > 0 {
		slot = a.free_slots[len(a.free_slots) - 1]
		_ = pop(&a.free_slots)
		gen = a.allocs[slot].gen + 1
	} else {
		append(&a.allocs, Atlas_Alloc{})
		slot = len(a.allocs) - 1
	}
	out.id = slot
	out.gen = gen
	a.allocs[slot] = Atlas_Alloc{
		region = out,
		pinned = pinned,
		used   = a.frame,
		gen    = gen,
	}
	return out
}

//* Finds a place for a region of `w` x `h` pixels in any page, without
//* touching the list of allocations.
atlas_alloc_raw :: proc(a: ^UI_Atlas, w, h: int) -> (Atlas_Region, bool) {
	for &p, index in a.pages {
		if region, ok := atlas_alloc_raw_page(&p, u16(index), w, h); ok {
			return region, true
		}
	}
	return Atlas_Region{id = -1}, false
}

//* Finds a place in one page. A block that was given back and is big
//* enough is cut into the part that is used and the two parts that are
//* left; the blocks are looked at from the back, so that taking one out
//* does not move the ones that are still to come.
atlas_alloc_raw_page :: proc(
	p: ^Atlas_Page,
	page: u16,
	w, h: int,
) -> (Atlas_Region, bool) {
	if w > p.width || h > p.height { return Atlas_Region{id = -1}, false }

	for &s in p.shelves {
		for i := len(s.free) - 1; i >= 0; i -= 1 {
			b := s.free[i]
			if b.w < w || b.h < h { continue }

			atlas_take_block(&s.free, i)

			right := Atlas_Block{x = b.x + w, y = b.y, w = b.w - w, h = h}
			bottom := Atlas_Block{x = b.x, y = b.y + h, w = b.w, h = b.h - h}
			if right.w > 0 { append(&s.free, right) }
			if bottom.h > 0 { append(&s.free, bottom) }

			return atlas_region(p, page, b.x, b.y, w, h), true
		}
	}

	//* The tail of a shelf that is tall enough.
	for &s in p.shelves {
		if s.height >= h && s.cursor + w <= p.width {
			x := s.cursor
			s.cursor += w
			return atlas_region(p, page, x, s.y, w, h), true
		}
	}

	//* A new shelf at the bottom.
	y := 0
	if len(p.shelves) > 0 {
		last := p.shelves[len(p.shelves) - 1]
		y = last.y + last.height
	}
	if y + h > p.height { return Atlas_Region{id = -1}, false }
	append(&p.shelves, Atlas_Shelf{y = y, height = h, cursor = w})
	return atlas_region(p, page, 0, y, w, h), true
}

atlas_take_block :: proc(blocks: ^[dynamic]Atlas_Block, index: int) {
	ordered_remove(blocks, index)
}

atlas_region :: proc(p: ^Atlas_Page, page: u16, x, y, w, h: int) -> Atlas_Region {
	return Atlas_Region{
		id = -1,
		page = page,
		x = x,
		y = y,
		w = w,
		h = h,
		uv = [4]f32{
			f32(x) / f32(p.width),
			f32(y) / f32(p.height),
			f32(x + w) / f32(p.width),
			f32(y + h) / f32(p.height),
		},
	}
}

atlas_region_uv_inside :: proc(a: ^UI_Atlas, region: Atlas_Region, x, y, w, h: int) -> [4]f32 {
	p := atlas_page(a, int(region.page))
	if p == nil { return {} }
	return [4]f32{
		f32(region.x + x) / f32(p.width),
		f32(region.y + y) / f32(p.height),
		f32(region.x + x + w) / f32(p.width),
		f32(region.y + y + h) / f32(p.height),
	}
}

//* The texture coordinates of a sub-rectangle of a region, in pixels.
//* The values may be fractional, which the nine-patch layout needs when
//* an edge is tiled and the last tile is only partly shown.
atlas_region_uv_inside_f :: proc(
	a: ^UI_Atlas,
	region: Atlas_Region,
	x, y, w, h: f32,
) -> [4]f32 {
	p := atlas_page(a, int(region.page))
	if p == nil { return {} }
	return [4]f32{
		(f32(region.x) + x) / f32(p.width),
		(f32(region.y) + y) / f32(p.height),
		(f32(region.x) + x + w) / f32(p.width),
		(f32(region.y) + y + h) / f32(p.height),
	}
}

//* True when the region still names the space it was given. A region
//* that was given back, or whose slot was used again, does not.
atlas_region_valid :: proc(a: ^UI_Atlas, region: Atlas_Region) -> bool {
	if region.id < 0 || region.id >= len(a.allocs) { return false }
	alloc := a.allocs[region.id]
	if alloc.freed { return false }
	return alloc.gen == region.gen && alloc.region.page == region.page
}

//* Throws out the region that was used longest ago. Only the regions
//* that are not pinned can go, and a region that the retained draw
//* lists name stays: the lists would draw stale texture coordinates.
atlas_evict :: proc(a: ^UI_Atlas) -> bool {
	oldest := -1
	oldest_used := u64(0)
	for &alloc, i in a.allocs {
		if alloc.freed || alloc.pinned { continue }
		if alloc.used == a.retained_frame { continue }
		if oldest < 0 || alloc.used < oldest_used {
			oldest_used = alloc.used
			oldest = i
		}
	}
	if oldest < 0 { return false }
	atlas_free(a, a.allocs[oldest].region)
	return true
}

//* Throws out the least recently used region that is not pinned, that
//* the retained draw lists do not name, and that is big enough to hold
//* a request of `w` x `h`. A region that cannot satisfy the request
//* would only be lost without helping, so it stays.
atlas_evict_for :: proc(a: ^UI_Atlas, w, h: int) -> bool {
	oldest := -1
	oldest_used := u64(0)
	for &alloc, i in a.allocs {
		if alloc.freed || alloc.pinned { continue }
		if alloc.used == a.retained_frame { continue }
		if alloc.region.w < w || alloc.region.h < h { continue }
		if oldest < 0 || alloc.used < oldest_used {
			oldest_used = alloc.used
			oldest = i
		}
	}
	if oldest < 0 { return false }
	atlas_free(a, a.allocs[oldest].region)
	return true
}

//* Gives a region back. The space is put on the free list of its
//* shelf, so it can be used again, and the generation of the slot goes
//* up, so a handle to the region names nothing from now on.
atlas_free :: proc(a: ^UI_Atlas, region: Atlas_Region) {
	if !atlas_region_valid(a, region) { return }
	alloc := &a.allocs[region.id]
	alloc.freed = true
	alloc.gen += 1
	atlas_release(a, alloc.region)
	append(&a.free_slots, region.id)
}

//* Puts the space of a region back on the free list of its shelf. The
//* shelf owns the band that the y of the region falls in; a region
//* carved from the bottom of a split block is still in that band.
atlas_release :: proc(a: ^UI_Atlas, region: Atlas_Region) {
	p := atlas_page(a, int(region.page))
	if p == nil { return }
	for &s in p.shelves {
		if region.y >= s.y && region.y < s.y + s.height {
			append(&s.free, Atlas_Block{x = region.x, y = region.y, w = region.w, h = region.h})
			return
		}
	}
}

//* Puts room for a region in the staging buffer of a page and says where
//* it is. The bytes are filled by the caller; nothing is uploaded until
//* the flush.
atlas_stage :: proc(p: ^Atlas_Page, region: Atlas_Region) -> []u8 {
	size := region.w * region.h * 4
	start := len(p.stage)
	resize(&p.stage, start + size)
	append(
		&p.staged,
		Atlas_Staged {
			offset = start,
			size = size,
			x = region.x,
			y = region.y,
			w = region.w,
			h = region.h,
		},
	)
	return p.stage[start:start + size]
}

//* Writes RGBA pixels into a region. The pixels are `w` x `h` and
//* have four bytes each.
atlas_write :: proc(a: ^UI_Atlas, region: Atlas_Region, pixels: []u8) {
	if !atlas_region_valid(a, region) { return }
	p := atlas_page(a, int(region.page))
	if p == nil { return }
	if len(pixels) < region.w * region.h * 4 { return }

	if p.pixels == nil {
		dst := atlas_stage(p, region)
		for row in 0 ..< int(region.h) {
			src := pixels[row * region.w * 4:][:region.w * 4]
			copy(dst[row * region.w * 4:][:region.w * 4], src)
		}
		return
	}

	dst := p.pixels[region.y * p.width * 4 + region.x * 4:]
	for row in 0 ..< int(region.h) {
		src := pixels[row * region.w * 4:][:region.w * 4]
		copy(dst[row * p.width * 4:][:region.w * 4], src)
	}
	atlas_mark_dirty(a, region)
}

//* Writes eight bit coverage into a region: the colour is white and
//* the alpha is the coverage, so the colour of the quad tints it.
atlas_write_coverage :: proc(a: ^UI_Atlas, region: Atlas_Region, coverage: []u8) {
	if !atlas_region_valid(a, region) { return }
	p := atlas_page(a, int(region.page))
	if p == nil { return }
	if len(coverage) < region.w * region.h { return }

	if p.pixels == nil {
		dst := atlas_stage(p, region)
		for row in 0 ..< int(region.h) {
			base := row * region.w * 4
			for col in 0 ..< int(region.w) {
				c := coverage[row * region.w + col]
				at := base + col * 4
				dst[at + 0] = 255
				dst[at + 1] = 255
				dst[at + 2] = 255
				dst[at + 3] = c
			}
		}
		return
	}

	dst := p.pixels[region.y * p.width * 4 + region.x * 4:]
	for row in 0 ..< int(region.h) {
		base := row * p.width * 4
		for col in 0 ..< int(region.w) {
			c := coverage[row * region.w + col]
			at := base + col * 4
			dst[at + 0] = 255
			dst[at + 1] = 255
			dst[at + 2] = 255
			dst[at + 3] = c
		}
	}
	atlas_mark_dirty(a, region)
}

//* Says that a region changed and is waiting to go up.
atlas_mark_dirty :: proc(a: ^UI_Atlas, region: Atlas_Region) {
	p := atlas_page(a, int(region.page))
	if p == nil { return }
	for d in p.dirty {
		if d.id == region.id && d.gen == region.gen { return }
	}
	append(&p.dirty, region)
}

//* Uploads the regions of every page that changed. The first time a
//* page goes up whole, because that is what makes its texture; after
//* that only the regions that changed are sent, and they go up together.
//* A backend that can upload regions no longer needs the CPU mirror after
//* the first upload, so it is given back and later writes are staged.
atlas_flush :: proc(a: ^UI_Atlas, backend: Backend) {
	if backend.upload_texture == nil { return }

	for &p, index in a.pages {
		texture := atlas_texture_of_page(index)
		if !p.uploaded {
			if p.pixels == nil { continue }
			if backend.upload_texture(backend.ctx, texture, p.pixels, i32(p.width), i32(p.height)) {
				p.uploaded = true
				clear(&p.dirty)
				if backend.upload_texture_regions != nil {
					delete(p.pixels)
					p.pixels = nil
				}
			}
			continue
		}

		if len(p.staged) > 0 && backend.upload_texture_regions != nil {
			clear(&p.uploads)
			for item in p.staged {
				append(
					&p.uploads,
					Texture_Upload {
						pixels = p.stage[item.offset:item.offset + item.size],
						w = i32(item.w),
						h = i32(item.h),
						x = i32(item.x),
						y = i32(item.y),
					},
				)
			}
			if backend.upload_texture_regions(backend.ctx, texture, p.uploads[:]) {
				clear(&p.staged)
				clear(&p.stage)
			}
			continue
		}

		if p.pixels == nil { continue }
		if len(p.dirty) == 0 { continue }

		//* A backend that cannot send a part of a texture gets the whole
		//* page: a full upload is still better than a stale glyph.
		if backend.upload_texture_regions == nil {
			if backend.upload_texture(backend.ctx, texture, p.pixels, i32(p.width), i32(p.height)) {
				clear(&p.dirty)
			}
			continue
		}

		atlas_gather(a, &p)
		if len(p.uploads) == 0 {
			clear(&p.dirty)
			continue
		}
		if backend.upload_texture_regions(backend.ctx, texture, p.uploads[:]) {
			clear(&p.dirty)
		}
	}
}

//* Puts the pixels of the regions that changed into the scratch
//* buffer of their page, and says where each of them is.
atlas_gather :: proc(a: ^UI_Atlas, p: ^Atlas_Page) {
	clear(&p.uploads)
	if p.pixels == nil { return }
	need := 0
	for region in p.dirty {
		if !atlas_region_valid(a, region) { continue }
		need += region.w * region.h * 4
	}
	if need == 0 { return }

	if len(p.scratch) < need {
		delete(p.scratch)
		p.scratch = make([]u8, need)
	}

	at := 0
	for region in p.dirty {
		if !atlas_region_valid(a, region) { continue }
		size := region.w * region.h * 4
		rows := p.scratch[at:at + size]
		src := p.pixels[region.y * p.width * 4 + region.x * 4:]
		for row in 0 ..< int(region.h) {
			copy(rows[row * region.w * 4:][:region.w * 4], src[row * p.width * 4:][:region.w * 4])
		}
		append(
			&p.uploads,
			Texture_Upload {
				pixels = rows,
				w      = i32(region.w),
				h      = i32(region.h),
				x      = i32(region.x),
				y      = i32(region.y),
			},
		)
		at += size
	}
}

//* Says that a region was used this frame, so it is the last one to be
//* thrown out.
atlas_touch :: proc(a: ^UI_Atlas, region: Atlas_Region) {
	if !atlas_region_valid(a, region) { return }
	a.allocs[region.id].used = a.frame
}

atlas_touch_if_valid :: proc(a: ^UI_Atlas, region: Atlas_Region) -> bool {
	if a == nil { return false }
	if region.id < 0 || region.id >= len(a.allocs) { return false }
	alloc := &a.allocs[region.id]
	if alloc.freed || alloc.gen != region.gen || alloc.region.page != region.page { return false }
	alloc.used = a.frame
	return true
}

//* The next frame: the regions that were not used are the first to go.
atlas_next_frame :: proc(a: ^UI_Atlas) {
	a.frame += 1
}

atlas_build_begin :: proc(a: ^UI_Atlas) {
	if a == nil {return}
	a.retained_frame = a.frame
}

atlas_live_count :: proc(a: ^UI_Atlas) -> int {
	n := 0
	for &alloc in a.allocs {
		if !alloc.freed { n += 1 }
	}
	return n
}

atlas_dirty_count :: proc(a: ^UI_Atlas) -> int {
	n := 0
	for &p in a.pages { n += len(p.dirty) }
	return n
}

atlas_uploaded_count :: proc(a: ^UI_Atlas) -> int {
	n := 0
	for &p in a.pages {
		if p.uploaded { n += 1 }
	}
	return n
}
