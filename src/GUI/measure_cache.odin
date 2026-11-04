//* == The cache of the measurements ==
//* Measuring a text means shaping it, which is not cheap. The layout
//* pass runs every frame, and it measures every text of every widget
//* every frame, so the size of a text that has not changed is
//* remembered.
//*
//* The key is the typeface, the size and the text itself, so a text
//* that changes is measured again and a text that does not is not.

package GUI

//* The key of a measurement. Everything that makes the size of a text
//* what it is has to be in it: the typeface, the size, the text, the
//* width it is broken to, the space between the lines, how it is
//* broken and what it is turned into.
Measure_Key :: struct {
	font:      Font_ID,
	size:      f32,
	text:      string,
	width:     f32,
	spacing:   f32,
	wrap:      Text_Wrap,
	transform: Text_Transform,
}

//* How many measurements are kept. The cache is emptied when it is
//* full: the texts of a program do not change that often, and a cache
//* that grows without end is a leak.
MEASURE_CACHE_LIMIT :: 2048

//* The size of a text, remembered.
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
