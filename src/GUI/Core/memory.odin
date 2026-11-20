//* == Memory report ==
//* One snapshot of what a GUI holds, so a large scene can be compared with
//* the same scene after a change. Sizes are bytes.

package Core

import runa "../dependencies/Runa"
import virt "core:mem/virtual"

arena_committed_bytes :: proc(a: ^virt.Arena) -> int {
	total := 0
	for block := a.curr_block; block != nil; block = block.prev {
		total += int(block.committed)
	}
	return total
}

Memory_Stats :: struct {
	//* Fixed sizes of the main structures.
	widget_size:      int,
	style_size:       int,
	style_cache_size: int,
	draw_vertex_size: int,
	style_pool_entries: int,
	style_pool_bytes:   int,

	//* The widget table and the memory the live widgets occupy.
	live_widgets:          int,
	widget_slots:          int,
	free_widget_slots:     int,
	widget_bytes:          int,
	arena_committed:       int,
	frame_arena_committed: int,

	//* The UI atlas.
	atlas_pages:         int,
	atlas_bytes:         int,
	atlas_scratch_bytes: int,
	atlas_dirty_regions: int,
	atlas_live_regions:  int,

	//* The text caches.
	glyph_entries:        int,
	shape_cache_entries:  int,
	shape_cache_capacity: int,
	measure_cache_entries: int,

	//* The retained draw lists.
	draw_vertex_capacity:       int,
	draw_index_capacity:        int,
	float_draw_vertex_capacity: int,
	float_draw_index_capacity:  int,

	//* The fonts and their Runa atlases.
	font_bytes:       int,
	runa_atlas_pages: int,
	runa_atlas_bytes: int,

	undo_bytes: int,

	//* The GPU side: the atlas texture and whatever the backend reports.
	gpu_atlas_bytes:    int,
	gpu_scene_bytes:    int,
	gpu_backdrop_bytes: int,
	gpu_vertex_bytes:   int,
	gpu_index_bytes:    int,
}

//* Gives back the memory of the retained draw lists and the atlas pages
//* that are no longer used, and in the aggressive mode the style pool,
//* the measure cache and the shape cache capacity too. A frame is
//* requested, so the lists are built again with the next frame. Meant to
//* run after a large scene is closed, not every frame.
GUI_Trim_Memory :: proc(g: ^GUI, aggressive := false) {
	if g == nil { return }

	draw_list_destroy(&g.draw)
	for &f in g.floats { draw_list_destroy(&f.draw) }
	g.draw_valid = false
	g.frame_requested = true

	atlas_trim(g.atlas, g.backend)

	if aggressive {
		style_cache_drop(g)
		Style_Pool_Destroy(g)
		measure_cache_clear(g)
		if g.cache_ready {
			runa.cache_set_capacity(&g.shape_cache, SHAPE_CACHE_CAPACITY)
		}
	}
}

GUI_Memory_Stats :: proc(g: ^GUI) -> Memory_Stats {
	stats := Memory_Stats {
		widget_size      = size_of(Widget),
		style_size       = size_of(Style),
		style_cache_size = size_of(Style_Cache),
		draw_vertex_size = size_of(Draw_Vertex),
	}
	if g == nil {return stats}

	stats.widget_slots = len(g.widgets)
	stats.free_widget_slots = len(g.free_widgets)
	stats.style_pool_entries = g.style_pool.count
	stats.style_pool_bytes = len(g.style_pool.chunks) * STYLE_POOL_CHUNK * size_of(Style)
	for w in g.widgets {
		if w != nil && w.id != INVALID_WIDGET_ID {stats.live_widgets += 1}
	}
	stats.widget_bytes = stats.live_widgets * stats.widget_size
	stats.arena_committed = arena_committed_bytes(&g.arena)
	stats.frame_arena_committed = arena_committed_bytes(&g.frame_arena)

	if a := g.atlas; a != nil {
		stats.atlas_pages = len(a.pages)
		for &p in a.pages {
			stats.atlas_bytes += len(p.pixels)
			stats.atlas_scratch_bytes += len(p.scratch) + cap(p.stage)
			stats.atlas_dirty_regions += len(p.dirty) + len(p.staged)
			stats.gpu_atlas_bytes += p.width * p.height * 4
		}
		stats.atlas_live_regions = atlas_live_count(a)
	}

	stats.glyph_entries = len(g.glyphs)
	if g.cache_ready {
		stats.shape_cache_entries = runa.cache_size(&g.shape_cache)
		stats.shape_cache_capacity = runa.cache_capacity(&g.shape_cache)
	}
	stats.measure_cache_entries = len(g.measure_cache)

	stats.draw_vertex_capacity = cap(g.draw.vertices)
	stats.draw_index_capacity = cap(g.draw.indices)
	for &f in g.floats {
		stats.float_draw_vertex_capacity += cap(f.draw.vertices)
		stats.float_draw_index_capacity += cap(f.draw.indices)
	}

	for file in g.font_files {
		stats.font_bytes += len(file.bytes)
		stats.runa_atlas_pages += len(file.atlas.pages_alpha) + len(file.atlas.pages_color)
		for page in file.atlas.pages_alpha {stats.runa_atlas_bytes += len(page.pixels)}
		for page in file.atlas.pages_color {stats.runa_atlas_bytes += len(page.pixels)}
	}

	for _, stack in g.undo_stacks {
		stats.undo_bytes += len(stack.records) * size_of(Undo_Record)
		for record in stack.records {
			stats.undo_bytes += len(record.before) + len(record.after)
		}
	}

	if g.backend.memory_stats != nil {
		gpu := g.backend.memory_stats(g.backend.ctx)
		stats.gpu_scene_bytes = gpu.scene_bytes
		stats.gpu_backdrop_bytes = gpu.backdrop_bytes
		stats.gpu_vertex_bytes = gpu.vertex_bytes
		stats.gpu_index_bytes = gpu.index_bytes
	}
	return stats
}
