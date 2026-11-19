package Core
import "core:math"

//* The time the caret is there, and the time it is gone.
CARET_BLINK_PERIOD :: 0.5

//* Starts the flash of the caret again: the caret is there at once.
caret_reset :: proc(g: ^GUI) {
	if g == nil {return}
	g.caret_timer = g.time
	g.caret_blink_valid = false
}

caret_elapsed :: proc(g: ^GUI) -> f32 {
	return max(g.time - g.caret_timer, 0)
}

caret_phase_index :: proc(g: ^GUI) -> i32 {
	period := f32(CARET_BLINK_PERIOD)
	elapsed := caret_elapsed(g)
	cycle := math.floor(elapsed / (period * 2))
	phase := elapsed - cycle * (period * 2)
	return i32(cycle * 2 + (phase < period ? 0 : 1))
}

caret_visible :: proc(g: ^GUI) -> bool {
	if g == nil {return true}
	return caret_phase_index(g) % 2 == 0
}

caret_tick :: proc(g: ^GUI) {
	if g == nil {return}
	if !widget_takes_text(g, g.focused) {
		if g.caret_timer != 0 {draw_invalidate(g)}
		g.caret_timer = 0
		g.caret_blink = 0
		g.caret_blink_valid = false
		return
	}
	if !g.caret_blink_valid {
		g.caret_timer = g.time
	}
	phase := caret_phase_index(g)
	if g.caret_blink_valid && phase != g.caret_blink {
		draw_invalidate(g)
	}
	g.caret_blink = phase
	g.caret_blink_valid = true

	period := f32(CARET_BLINK_PERIOD)
	elapsed := caret_elapsed(g)
	cycle := math.floor(elapsed / (period * 2))
	phase_in_cycle := elapsed - cycle * (period * 2)
	next := phase_in_cycle < period ? g.caret_timer + cycle * (period * 2) + period :
		g.caret_timer + (cycle + 1) * (period * 2)
	wake_at(g, next)
}
