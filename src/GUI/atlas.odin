package GUI

//* == UI atlas ==
//* The atlas owns a copy of the pixels. A change is written into that
//* copy and only the region that changed is uploaded, so a glyph that
//* is rasterized does not cost a 16 MiB upload.
//
//* The shelves are stacked from the top of the atlas downwards, and a
//* new region goes on the first shelf that is tall enough and has room
//* left. The glyphs are pinned, because a glyph that is thrown out
//* would have to be rasterized again; the images are not.
//
//* A region is named by its slot and by a generation. The generation
//* goes up when the space is given back, so a handle to a region that
//* is gone never names the region that took its place.

//* The size of the atlas, in pixels, when nothing else is asked for.
//* 2048x2048 of RGBA is 16 MiB.
ATLAS_DEFAULT_SIZE :: 2048

//* The white texel at the top left of the atlas is this big. A solid
//* quad samples the middle of it, so the filter never reaches a
//* neighbouring pixel.
ATLAS_WHITE_SIZE :: 4

//* A piece of the atlas. The id is the slot the region lives in and
//* the generation says how many times that slot has been used; the id
//* is -1 when the region is not valid.
Atlas_Region :: struct {
	id:   int,
	gen:  u32,
	x, y, w, h: int,
	uv:   [4]f32, // u0, v0, u1, v1
}

//* A block of a shelf that was given back and can be used again.
Atlas_Block :: struct {
	x, y, w, h: int,
}

//* A shelf: a horizontal band of the atlas. The blocks that were freed
//* inside it are kept, so the space can be used again.
Atlas_Shelf :: struct {
	y:      int,
	height: int,
	cursor: int, // the first x that is not used yet
	free:   [dynamic]Atlas_Block,
}

Atlas_Alloc :: struct {
	region: Atlas_Region,
	pinned: bool,
	used:   u64, // the frame the region was last used in
	freed:  bool,
	gen:    u32,
}

UI_Atlas :: struct {
	width, height: int,
	pixels:  []u8,
	shelves: [dynamic]Atlas_Shelf,
	allocs:  [dynamic]Atlas_Alloc,
	free_slots: [dynamic]int,
	dirty:   [dynamic]Atlas_Region,
	frame:   u64,
	white:   Atlas_Region,
	white_uv: [4]f32,
	scratch:  []u8,
	//* The parts that are waiting to go up, and where they are in the scratch buffer.
	uploads:  [dynamic]Texture_Upload,
	//* Whether the whole atlas was already uploaded. The first upload
	//* makes the texture; the ones after it are regions of it.
	uploaded: bool,
	//* How many times an allocation could not be served.
	exhausted: int,
}

//* Makes an atlas of `width` x `height` pixels. The white texel is
//* reserved at the top left.
atlas_make :: proc(width, height: int) -> ^UI_Atlas {
	a := new(UI_Atlas)
	a.width = width
	a.height = height
	a.pixels = make([]u8, width * height * 4)

	for y in 0 ..< ATLAS_WHITE_SIZE {
		for x in 0 ..< ATLAS_WHITE_SIZE {
			at := (y * width + x) * 4
			a.pixels[at + 0] = 255
			a.pixels[at + 1] = 255
			a.pixels[at + 2] = 255
			a.pixels[at + 3] = 255
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
	delete(a.pixels)
	delete(a.scratch)
	for &s in a.shelves { delete(s.free) }
	delete(a.shelves)
	delete(a.allocs)
	delete(a.free_slots)
	delete(a.dirty)
	delete(a.uploads)
	free(cast(rawptr) a)
}

//* Hands out a region of `w` x `h` pixels. A pinned region is never
//* thrown out; an unpinned one is the first to go when the atlas is
//* full. The region is invalid when there is no room for it.
atlas_alloc :: proc(a: ^UI_Atlas, w, h: int, pinned: bool) -> Atlas_Region {
	if w <= 0 || h <= 0 { return Atlas_Region{id = -1} }
	if w > a.width || h > a.height {
		a.exhausted += 1
		return Atlas_Region{id = -1}
	}

	//* Try again after throwing something out: the space that is
	//* freed is the space that is used. A region that is not pinned
	//* can always be thrown out to make room
	for {
		if region, ok := atlas_alloc_raw(a, w, h); ok {
			return atlas_commit(a, region, w, h, pinned)
		}
		if !atlas_evict(a) { break }
	}
	a.exhausted += 1
	return Atlas_Region{id = -1}
}

//* Puts the region in a slot and gives it its generation. A slot that
//* was given back is used again, so the table of the allocations does
//* not grow for ever.
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

//* Finds a place for a region of `w` x `h` pixels, without touching
//* the list of allocations.
atlas_alloc_raw :: proc(a: ^UI_Atlas, w, h: int) -> (Atlas_Region, bool) {
	//* A block that was given back and is big enough. The block is cut
	//* into the part that is used and the two parts that are left.
	//* The blocks are looked at from the back, so that taking one out
	//* does not move the ones that are still to come.
	for &s in a.shelves {
		for i := len(s.free) - 1; i >= 0; i -= 1 {
			b := s.free[i]
			if b.w < w || b.h < h { continue }

			atlas_take_block(&s.free, i)

			right := Atlas_Block{x = b.x + w, y = b.y, w = b.w - w, h = h}
			bottom := Atlas_Block{x = b.x, y = b.y + h, w = b.w, h = b.h - h}
			if right.w > 0 { append(&s.free, right) }
			if bottom.h > 0 { append(&s.free, bottom) }

			return atlas_region(a, b.x, b.y, w, h), true
		}
	}

	//* The tail of a shelf that is tall enough.
	for &s in a.shelves {
		if s.height >= h && s.cursor + w <= a.width {
			x := s.cursor
			s.cursor += w
			return atlas_region(a, x, s.y, w, h), true
		}
	}

	//* A new shelf at the bottom.
	y := 0
	if len(a.shelves) > 0 {
		last := a.shelves[len(a.shelves) - 1]
		y = last.y + last.height
	}
	if y + h > a.height { return Atlas_Region{id = -1}, false }
	append(&a.shelves, Atlas_Shelf{y = y, height = h, cursor = w})
	return atlas_region(a, 0, y, w, h), true
}

atlas_take_block :: proc(blocks: ^[dynamic]Atlas_Block, index: int) {
	ordered_remove(blocks, index)
}

atlas_region :: proc(a: ^UI_Atlas, x, y, w, h: int) -> Atlas_Region {
	return Atlas_Region{
		id = -1,
		x = x,
		y = y,
		w = w,
		h = h,
		uv = [4]f32{
			f32(x) / f32(a.width),
			f32(y) / f32(a.height),
			f32(x + w) / f32(a.width),
			f32(y + h) / f32(a.height),
		},
	}
}

atlas_region_uv_inside :: proc(a: ^UI_Atlas, region: Atlas_Region, x, y, w, h: int) -> [4]f32 {
	return [4]f32{
		f32(region.x + x) / f32(a.width),
		f32(region.y + y) / f32(a.height),
		f32(region.x + x + w) / f32(a.width),
		f32(region.y + y + h) / f32(a.height),
	}
}

//* True when the region still names the space it was given. A region
//* that was given back, or whose slot was used again, does not.
atlas_region_valid :: proc(a: ^UI_Atlas, region: Atlas_Region) -> bool {
	if region.id < 0 || region.id >= len(a.allocs) { return false }
	alloc := a.allocs[region.id]
	if alloc.freed { return false }
	return alloc.gen == region.gen
}

//* Throws out the region that was used longest ago. Only the regions
//* that are not pinned can go.
atlas_evict :: proc(a: ^UI_Atlas) -> bool {
	oldest := -1
	oldest_used := u64(0)
	for &alloc, i in a.allocs {
		if alloc.freed || alloc.pinned { continue }
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

//* Puts the space of a region back on the free list of its shelf.
atlas_release :: proc(a: ^UI_Atlas, region: Atlas_Region) {
	for &s in a.shelves {
		if s.y == region.y {
			append(&s.free, Atlas_Block{x = region.x, y = region.y, w = region.w, h = region.h})
			return
		}
	}
}

//* == Writing ==

//* Writes RGBA pixels into a region. The pixels are `w` x `h` and
//* have four bytes each.
atlas_write :: proc(a: ^UI_Atlas, region: Atlas_Region, pixels: []u8) {
	if !atlas_region_valid(a, region) { return }
	if len(pixels) < region.w * region.h * 4 { return }

	dst := a.pixels[region.y * a.width * 4 + region.x * 4:]
	for row in 0 ..< int(region.h) {
		src := pixels[row * region.w * 4:][:region.w * 4]
		copy(dst[row * a.width * 4:][:region.w * 4], src)
	}
	atlas_mark_dirty(a, region)
}

//* Writes eight bit coverage into a region: the colour is white and
//* the alpha is the coverage, so the colour of the quad tints it.
atlas_write_coverage :: proc(a: ^UI_Atlas, region: Atlas_Region, coverage: []u8) {
	if !atlas_region_valid(a, region) { return }
	if len(coverage) < region.w * region.h { return }

	dst := a.pixels[region.y * a.width * 4 + region.x * 4:]
	for row in 0 ..< int(region.h) {
		base := row * a.width * 4
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
	for d in a.dirty {
		if d.id == region.id && d.gen == region.gen { return }
	}
	append(&a.dirty, region)
}

//* == Uploading ==

//* Uploads the regions that changed. The first time the whole atlas
//* goes up, because that is what makes the texture; after that only
//* the regions that changed are sent, and they go up together.
atlas_flush :: proc(a: ^UI_Atlas, backend: Backend, texture: Texture_ID) {
	if backend.upload_texture == nil { return }

	if !a.uploaded {
		if backend.upload_texture(backend.ctx, texture, a.pixels, i32(a.width), i32(a.height)) {
			a.uploaded = true
			clear(&a.dirty)
		}
		return
	}

	if len(a.dirty) == 0 { return }

	//* A backend that cannot send a part of a texture gets the whole
	//* thing: a 16 MiB atlas is still better than a stale glyph.
	if backend.upload_texture_regions == nil {
		if backend.upload_texture(backend.ctx, texture, a.pixels, i32(a.width), i32(a.height)) {
			clear(&a.dirty)
		}
		return
	}

	//* The pixels of every region are put together in one buffer, so
	//* the backend gets them in one call.
	atlas_gather(a)
	if len(a.uploads) == 0 {
		clear(&a.dirty)
		return
	}
	if backend.upload_texture_regions(backend.ctx, texture, a.uploads[:]) {
		clear(&a.dirty)
	}
}

//* Puts the pixels of the regions that changed into the scratch
//* buffer, and says where each of them is.
atlas_gather :: proc(a: ^UI_Atlas) {
	clear(&a.uploads)
	need := 0
	for region in a.dirty {
		if !atlas_region_valid(a, region) { continue }
		need += region.w * region.h * 4
	}
	if need == 0 { return }

	if len(a.scratch) < need {
		delete(a.scratch)
		a.scratch = make([]u8, need)
	}

	at := 0
	for region in a.dirty {
		if !atlas_region_valid(a, region) { continue }
		size := region.w * region.h * 4
		rows := a.scratch[at:at + size]
		src := a.pixels[region.y * a.width * 4 + region.x * 4:]
		for row in 0 ..< int(region.h) {
			copy(rows[row * region.w * 4:][:region.w * 4], src[row * a.width * 4:][:region.w * 4])
		}
		append(
			&a.uploads,
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

//* The next frame: the regions that were not used are the first to go.
atlas_next_frame :: proc(a: ^UI_Atlas) {
	a.frame += 1
}

atlas_live_count :: proc(a: ^UI_Atlas) -> int {
	n := 0
	for &alloc in a.allocs {
		if !alloc.freed { n += 1 }
	}
	return n
}
