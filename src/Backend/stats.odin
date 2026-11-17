package Backend

Backend_Stats :: struct {
	glass_commands:  int,
	capture_points:  int,
	backdrop_pixels: int,
	glass_pixels:    int,
	draw_passes:     int,
	glass_taps:      int,
	cache_hits:      int,
	//* How the scene was written: a full render clears it, a scissored
	//* replay keeps it and redraws only the dirty rectangle.
	full_updates:     int,
	partial_updates:  int,
	scene_updates:    int,
	//* The captures of the backdrop, and the mip chains built on them.
	backdrop_blits:   int,
	mip_generations:  int,
	//* Wake timers the last frame armed. The core counts them; the
	//* application copies the number here before it reads the stats.
	wake_timers:      int,
}

Stats: Backend_Stats

Stats_Reset :: proc() {
	Stats = {}
}

Stats_Get :: proc() -> Backend_Stats {
	return Stats
}
