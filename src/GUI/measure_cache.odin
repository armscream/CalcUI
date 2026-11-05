package GUI

Measure_Key :: struct {
	font:      Font_ID,
	size:      f32,
	text:      string,
	width:     f32,
	spacing:   f32,
	wrap:      Text_Wrap,
	transform: Text_Transform,
}

//* How many measurements are kept. The cache is emptied when it is full: a
//* cache that grows without end is a leak.
MEASURE_CACHE_LIMIT :: 2048

//* The size of a text, and whether it is in the cache.
measure_cache_get :: proc(g: ^GUI, key: Measure_Key) -> (Vec2, bool) {
	if g.measure_cache == nil {return {}, false}
	size, ok := g.measure_cache[key]
	return size, ok
}

//* Remembers the size of a text.
measure_cache_put :: proc(g: ^GUI, key: Measure_Key, size: Vec2) {
	if g.measure_cache == nil {
		g.measure_cache = make(map[Measure_Key]Vec2)
	}
	if len(g.measure_cache) >= MEASURE_CACHE_LIMIT {
		clear(&g.measure_cache)
	}
	g.measure_cache[key] = size
}

//* Forgets every measurement. It is needed when the typeface itself
//* changes, which happens when a font file is loaded again.
measure_cache_clear :: proc(g: ^GUI) {
	if g.measure_cache == nil {return}
	clear(&g.measure_cache)
}
